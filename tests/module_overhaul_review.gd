extends "res://tests/deep_sky_preview.gd"

# Save-free review: desktop captures by default, paired synthetic workloads with
# -- --probe, or a human-controlled 60-second session with -- --slice.
const Modules = preload("res://scripts/observation_modules.gd")
const NEW_MODULES := ["linear_observation", "capture_hold", "overcharge"]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--probe" in args:
		await _probe()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Desktop rendering is required")
		quit(1)
		return
	var game := await _game()
	if "--slice" in args:
		await _slice(game)
		return
	root.gui_disable_input = true
	var source := Capture.source_snapshot(failures)
	output = "res://build/module_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_freeze(game)
	_clear_sky(game)
	game.effects.reset()
	game.hud.banner_root.hide()
	game.observer.native_cursor_visible = false
	var center: Vector2 = game.observation_view.screen_to_world(Vector2(576, 320))
	game.observer.cursor_position = center
	game.observer.previous_cursor_position = center
	await _capture(game, "01_circle")
	_install(game, ["linear_observation"])
	await _capture(game, "02_line")
	var meteor = game.spawner.spawn_meteor("common", center + Vector2(60, 0), Vector2(150, 0), 30.0)
	meteor.set_process(false)
	meteor.observation_progress = 0.55
	game.observer.selected_meteor = meteor
	game.observer.tracked_meteors = [meteor]
	game.observer.was_holding = true
	game.effects.reset()
	_freeze(game)
	await _capture(game, "03_line_tracking")
	_install(game, NEW_MODULES)
	game.deep_sky.modules.restore_round_state({"burst_remaining": 4.5})
	game.observer._apply_manual_contact(meteor, 0.00001)
	var held_position: Vector2 = meteor.position
	meteor._process(0.5)
	if meteor.position != held_position: failures.append("captured meteor moved")
	game.effects.reset()
	_freeze(game)
	await _capture(game, "04_overcharge_hold")
	game.observer.reset()
	game.upgrade_tree.open_tree()
	game.module_popup.open()
	for locale in ["ko", "en"]:
		_set_locale(game, locale)
		for id in NEW_MODULES:
			game.module_popup.show_module_tooltip(id)
			await _capture(game, locale + "_popup_" + id)
	if source != Capture.source_snapshot(failures): failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"source": source, "frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	_finish("MODULE_REVIEW", "10 frames at " + ProjectSettings.globalize_path(output))

func _game() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	var advanced := true
	while advanced:
		advanced = false
		for definition in Balance.UPGRADE_NODES:
			if not game.progression.has_upgrade(definition.id) and game.progression.debug_purchase_node(definition.id): advanced = true
	game.settings.set_language("ko", false)
	game.galactic_pullback_seen = true
	game.deep_sky.modules.unlocked_slots = 5
	game.hud.banner_root.hide()
	return game

func _install(game: Node, ids: Array) -> void:
	var model = game.deep_sky.modules
	for slot in range(5): model.equip("", slot)
	for index in range(ids.size()):
		model.grant(ids[index])
		model.equip(ids[index], index)
	model.reset_round()

func _slice(game: Node) -> void:
	game.upgrade_tree.close_tree()
	game.upgrade_tree.configure_galactic_state(true, true)
	paused = false
	game.effects.reset()
	_install(game, NEW_MODULES + ["focus", "wide"])
	game.observation_phase_duration = 60.0
	game.observation_phase_remaining = 60.0
	game.spawner.set_phase_time_remaining(60.0)
	DisplayServer.window_set_title("Nightwatch — 새 모듈 60초 체험 (저장 없음)")
	print("MODULE_SLICE_READY: line, capture, overcharge, split and wide; hold LMB and move normally")
	var deadline := Time.get_ticks_msec() + 120000
	var elapsed := 0.0
	var held_seconds := 0.0
	var successes: int = game.progression.success_count
	while elapsed < 60.0 and Time.get_ticks_msec() < deadline:
		await process_frame
		var delta := game.get_process_delta_time()
		if not game.observation_phase_active: break
		if paused: continue
		elapsed += delta
		if Input.is_action_pressed(&"nw_observe"): held_seconds += delta
	print("MODULE_SLICE_RESULT: held_seconds=%.2f completions=%d; human feedback is required" % [held_seconds, game.progression.success_count - successes])
	quit()

func _probe() -> void:
	var source := Capture.source_snapshot(failures)
	var rows: Array = []
	for seed_value in range(20260910, 20260918):
		for ids in [[], ["linear_observation"], ["capture_hold"], ["overcharge"], NEW_MODULES]:
			var game := await _game()
			_freeze(game)
			_clear_sky(game)
			game.spawner.running = false # Fixed arrivals only; no research-triggered bursts.
			_install(game, ids)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var held := 0.0
			var burst := 0.0
			var completed := 0
			var peak := 0
			var center: Vector2 = game.observation_view.screen_to_world(Vector2(576, 320))
			game.observer.cursor_position = center + Vector2(100, 0)
			for step in range(600):
				if step % 8 == 0:
					var position := center + Vector2(rng.randf_range(-150, 150), rng.randf_range(-85, 85))
					var meteor = game.spawner.spawn_meteor("common", position, Vector2(rng.randf_range(60, 130), 0), 2.0)
					if meteor != null:
						meteor.set_process(false)
						meteor.base_automatic_rate = 0.0
						meteor.required_track_time = 1.0
				game.observer.previous_cursor_position = game.observer.cursor_position
				game.observer.cursor_position = center + Vector2(cos(step * 0.08) * 100, sin(step * 0.08) * 70)
				game.observer._update_manual_tracking(0.05)
				game.deep_sky.modules.advance_time(0.05)
				if game.deep_sky.modules.burst_remaining > 0: burst += 0.05
				for meteor in game.meteor_layer.get_children():
					if meteor.capture_remaining > 0: held += 0.05
					meteor._process(0.05)
					if not meteor.alive:
						if meteor.observed_successfully: completed += 1
						meteor.free()
				peak = maxi(peak, game.meteor_layer.get_child_count())
			if peak > 32: failures.append("unbounded target population")
			rows.append({"seed": seed_value, "modules": ids, "completions": completed, "held_target_seconds": held, "burst_seconds": burst, "peak_live": peak})
			game.free()
			await process_frame
	if source != Capture.source_snapshot(failures): failures.append("source changed during probe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/module_review"))
	var file := FileAccess.open("res://build/module_review/paired_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": source, "synthetic": true, "duration": 30, "step": 0.05, "rows": rows, "failures": failures}, "\t"))
	file.close()
	_finish("MODULE_PAIRED_PROBE", "8 seeds × 5 configurations; synthetic cursor, no pacing or comfort verdict")

func _finish(marker: String, detail: String) -> void:
	if failures.is_empty(): print(marker + "_PASS: " + detail)
	else: push_error(str(failures))
	quit(0 if failures.is_empty() else 1)

func _clear_sky(game: Node) -> void:
	game.observer.reset()
	for meteor in game.meteor_layer.get_children(): meteor.free()
