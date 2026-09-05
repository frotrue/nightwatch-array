extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Capture = preload("res://tests/capture_reference.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): push_error("Andromeda capture watchdog expired"); quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("Andromeda preview needs a real renderer")
		quit(1)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	var output := "res://build/andromeda_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.progression.debug_purchase_all()
	game.progression.observation_data = 240000000.0
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	var records: Array = []
	for locale in ["en", "ko"]:
		TranslationServer.set_locale(locale)
		game.upgrade_tree._refresh()
		game.upgrade_tree.galaxy_hub.refresh_text()
		await _capture(game.andromeda, output, locale + "_galaxy_hub", records)
	game._enter_andromeda()
	var stage = game.andromeda
	stage.set_process(false)
	for locale in ["en", "ko"]:
		TranslationServer.set_locale(locale)
		stage.refresh_ui()
		stage.cursor = stage.targets[3].position * stage.ui.size
		stage.targets[3].progress = 0.45
		stage.tracked_indices.clear()
		stage.tracked_indices.append(3)
		await _capture(stage, output, locale + "_observation", records)
		stage.toggle_modules()
		await _capture(stage, output, locale + "_modules", records)
		stage.toggle_modules()
	stage.toggle_modules()
	stage.purchase_module("wide")
	stage.toggle_modules()
	stage._make_targets()
	stage.advance_observation(1.2, Vector2(0.28, 0.42) * stage.ui.size, true, false)
	await _capture(stage, output, "ko_wide_observation", records)
	if source != Capture.source_snapshot(failures):
		failures.append("Source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"source": source, "frames": records, "failures": failures, "synthetic": true, "note": "Isolated rendered first-stage poses. Not a human playtest."}, "\t"))
	manifest.close()
	game.free()
	paused = false
	if failures.is_empty() and records.size() == 7:
		print("ANDROMEDA_PREVIEW_PASS: 7 frames at " + ProjectSettings.globalize_path(output))
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _capture(stage: Node, output: String, name: String, records: Array) -> void:
	stage.sky.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	RenderingServer.force_sync()
	var first: Image = root.get_texture().get_image()
	await process_frame
	RenderingServer.force_draw()
	RenderingServer.force_sync()
	var second: Image = root.get_texture().get_image()
	if first.get_data() != second.get_data() or second.get_size() != Vector2i(1152, 648):
		failures.append("Unstable or wrong-sized frame: " + name)
	var file := output.path_join(name + ".png")
	if second.save_png(file) != OK:
		failures.append("Failed writing: " + file)
	var hub = stage.game.upgrade_tree.galaxy_hub
	records.append({"file": file, "sha256": FileAccess.get_sha256(file), "locale": TranslationServer.get_locale(), "module": stage.modules.equipped, "tracked": stage.tracked_indices.duplicate(), "modules_open": stage.modules_open, "galaxy_hub": hub.is_visible_in_tree(), "hub_size": [hub.size.x, hub.size.y], "hub_detail_position": [hub.selected_code.position.x, hub.selected_code.position.y]})
