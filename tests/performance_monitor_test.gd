extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Settings = preload("res://scripts/game_settings.gd")
const Sampler = preload("res://scripts/performance_sampler.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://monitor_test_%d.cfg" % OS.get_process_id()
	var settings := Settings.new(path)
	settings.load_settings()
	_check(not settings.performance_monitor_enabled, "missing setting defaults off")
	settings.set_performance_monitor_enabled(true)
	var reloaded := Settings.new(path)
	reloaded.load_settings()
	_check(reloaded.performance_monitor_enabled, "enabled state persists across reload")
	reloaded.set_performance_monitor_enabled(false)
	settings.load_settings()
	_check(not settings.performance_monitor_enabled, "disabled state persists")
	var config := ConfigFile.new()
	config.set_value("performance", "monitor_enabled", "true")
	config.save(path)
	settings.load_settings()
	_check(not settings.performance_monitor_enabled, "invalid bool fails closed")
	settings.free()
	reloaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Sampler._valid_percent(-1) == -1 and Sampler._valid_percent("80") == -1, "unavailable and invalid values stay unavailable")
	_check(Sampler._valid_percent(0) == 0 and Sampler._valid_percent(101) == -1, "real zero is distinct from unavailable")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var monitor: Control = game.hud.performance_monitor
	_check(not monitor.visible and not monitor.is_processing() and monitor.sampler.process.is_empty(), "default off has no sampling or helper")
	game.hud.open_settings("display")
	game.hud.performance_monitor_button.pressed.emit()
	_check(game.settings.performance_monitor_enabled and monitor.is_processing(), "settings button enables monitor immediately")
	_check(not monitor.visible, "settings owns the foreground without a partial monitor showing behind it")
	_check(_ignores_mouse(monitor), "whole monitor passes observation input through")
	var helper_pid: int = monitor.sampler.process.get("pid", -1)
	var require_gpu := OS.get_environment("NIGHTWATCH_MONITOR_GPU_TEST") == "1"
	if OS.get_name() == "Windows":
		_check(helper_pid > 0, "Windows helper is packaged for local execution")
	for _attempt in 20:
		await create_timer(0.5).timeout
		if monitor.sampler.cpu >= 0 and (not require_gpu or monitor.sampler.gpu > 0): break
	_check(monitor.fps > 0 and monitor.frame_ms > 0, "frame metrics update while settings pause gameplay")
	_check(monitor.get_node("%Tick").text == TranslationServer.translate("PERF_PAUSED"), "paused simulation is explicitly labelled")
	if OS.get_name() == "Windows": _check(monitor.sampler.cpu >= 0, "real process CPU samples arrive")
	if require_gpu: _check(monitor.sampler.gpu > 0, "rendered workload produces nonzero process GPU usage")
	_check(not monitor.get_node("%Usage").text.contains("GPU 3D"), "GPU label includes all engine types")
	print("MONITOR_NATIVE_SAMPLE: cpu=", monitor.sampler.cpu, " gpu=", monitor.sampler.gpu)
	game.hud.close_settings()
	await create_timer(0.7).timeout
	_check(monitor.visible, "closing settings shows the enabled monitor")
	_check(monitor.ticks_per_second > 0, "live simulation tick count advances")
	game.simulation_clock.reset_boundary()
	game.simulation_clock.tick += 100000
	await create_timer(0.55).timeout
	_check(monitor.ticks_per_second < 100, "restored tick counters do not masquerade as executed work")
	if DisplayServer.get_name().to_lower() != "headless":
		game.settings.set_language("ko", false)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/performance_monitor_ko.png")
		for locale in ["ko", "en"]:
			game.settings.set_language(locale, false)
			game.hud.open_settings("display")
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/performance_settings_%s.png" % locale)
	game.settings.set_performance_monitor_enabled(false, false)
	_check(not monitor.visible and not monitor.is_processing() and monitor.sampler.process.is_empty(), "disable stops processing and releases pipes")
	if helper_pid > 0: _check(not OS.is_process_running(helper_pid), "disable terminates owned helper")
	game.settings.set_performance_monitor_enabled(true, false)
	helper_pid = monitor.sampler.process.get("pid", -1)
	_check(monitor.sampler.cpu == -1 and monitor.get_node("%FrameGraph").history.is_empty(), "reenable clears stale metrics")
	game.queue_free()
	await process_frame
	if helper_pid > 0: _check(not OS.is_process_running(helper_pid), "scene shutdown terminates owned helper")
	paused = false
	if failures.is_empty(): print("PERFORMANCE_MONITOR_PASS: settings persistence, lifecycle, native sampling and passive UI")
	quit(0 if failures.is_empty() else 1)

func _ignores_mouse(node: Node) -> bool:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE: return false
	for child in node.get_children():
		if not _ignores_mouse(child): return false
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PERFORMANCE_MONITOR: " + message)
