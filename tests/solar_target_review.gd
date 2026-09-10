extends "res://tests/module_overhaul_review.gd"

# Save-free desktop art review. Labels belong to the comparison fixture only.
func _run() -> void:
	create_timer(50.0, true, false, true).timeout.connect(func(): push_error("Solar target review timeout"); quit(1))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.gui_disable_input = true
	var game := await _game()
	game.upgrade_tree.configure_galactic_state(true, true)
	var source := Capture.source_snapshot(failures)
	output = "res://build/solar_target_review/%d" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_freeze(game)
	_clear_sky(game)
	game.effects.reset()
	game.observer.hide()
	game.hud.hide()
	var labels := CanvasLayer.new()
	root.add_child(labels)
	var samples := [
		["common", Vector2(250, 210)], ["fireball", Vector2(570, 210)], ["major", Vector2(900, 210)],
		["variable_star", Vector2(250, 420)], ["binary_star", Vector2(570, 420)], ["galaxy", Vector2(900, 420)]]
	var caption_labels: Array[Label] = []
	for sample in samples:
		var world: Vector2 = game.observation_view.screen_to_world(sample[1])
		var target = game.spawner.spawn_meteor(sample[0], world, Vector2(140, -30), 30.0)
		target.set_process(false)
		target.age = 2.0
		target.wobble_phase = 0.6
		target.base_automatic_rate = 0.0
		target.dish_assist_rate = 0.0
		target.lane_assist_rate = 0.0
		for index in range(20): target.trail_points.append(world - Vector2(4, -0.85) * float(index))
		var caption := Label.new()
		caption.position = sample[1] + Vector2(-120, 75)
		caption.size = Vector2(240, 30)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels.add_child(caption)
		caption_labels.append(caption)
	for locale in ["ko", "en"]:
		_set_locale(game, locale)
		for index in range(samples.size()): caption_labels[index].text = tr("METEOR_" + String(samples[index][0]).to_upper())
		await _capture(game, locale + "_size_comparison")
	labels.hide()
	game.hud.show()
	game.observer.show()
	game.observer.cursor_position = game.observation_view.screen_to_world(Vector2(606, 420))
	game.observer.previous_cursor_position = game.observer.cursor_position
	_install(game, ["linear_observation"])
	_set_locale(game, "ko")
	await _capture(game, "ko_observation_field")
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	_freeze(game)
	for locale in ["ko", "en"]:
		_set_locale(game, locale)
		for id in ["variable_watchlist", "double_star_resolution", "galaxy_imaging"]:
			game.upgrade_tree._show_node_tooltip(id)
			if not game.upgrade_tree.tooltip_panel.is_visible_in_tree(): failures.append("research inspector hidden: " + id)
			await _capture(game, locale + "_research_" + id)
			if game.upgrade_tree.tooltip_name.text != tr("UPGRADE_" + id.to_upper() + "_NAME"): failures.append("wrong inspector: " + id)
	if source != Capture.source_snapshot(failures): failures.append("source changed during capture")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	labels.free()
	game.free()
	paused = false
	_finish("SOLAR_TARGET_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))
