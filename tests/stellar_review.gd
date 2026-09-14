extends "res://tests/module_overhaul_review.gd"

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	var game := await _game()
	game.deep_sky.state.module_intro_stage = 3
	game.module_popup.close()
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	game.upgrade_tree.focus_constellation("scutum")
	game.upgrade_tree._on_node_hovered("ext_sct_stellar")
	_freeze(game)
	output = "res://build/stellar/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for locale in ["ko", "en"]:
		_set_locale(game, locale)
		await _capture(game, locale + "_scutum_unlock")
	game.upgrade_tree.close_tree()
	_set_locale(game, "ko")
	_clear_sky(game)
	game.effects.reset()
	game.observation_phase_active = true
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(550, 290))
	var star = game.spawner.spawn_meteor("stellar", centre, Vector2.RIGHT * 30, 30.0)
	var kinds := ["common", "fireball", "variable_star", "binary_star", "galaxy"]
	for i in kinds.size():
		var offset := Vector2.RIGHT.rotated(float(i) * TAU / 5.0) * (125.0 + i * 7.0) * unit
		var target = game.spawner.spawn_meteor(kinds[i], centre + offset, Vector2(120, 30), 30.0)
		if not target.is_solid_body():
			for j in 18: target.trail_points.append(target.position - Vector2(j * 3, j))
	game.spawner.spawn_meteor("black_hole", centre + Vector2(290, -20) * unit, Vector2.RIGHT, 30.0)
	star.age = 3.0
	star.observation_progress = 0.78
	game.observer.cursor_position = centre
	game.observer.previous_cursor_position = centre
	game.observer.native_cursor_visible = false
	_freeze(game)
	await _capture(game, "01_star")
	star.age = 11.0
	await _capture(game, "02_star_evolved")
	if Image.load_from_file(output.path_join("01_star.png")).get_data() == Image.load_from_file(output.path_join("02_star_evolved.png")).get_data():
		failures.append("stellar surface did not evolve with simulation age")
	star.age = 3.0
	star.scale = Vector2.ONE * 3.0
	for target in game.meteor_layer.get_children():
		if target != star: target.hide()
	await _capture(game, "03_star_detail")
	star.scale = Vector2.ONE
	for target in game.meteor_layer.get_children(): target.show()
	star.observation_progress = 1.0
	star.manual_touched = true
	star.manual_tracking_time = 3.0
	star.quality_integral = 2.4
	star.tick_resolve()
	game.effects.reset()
	_freeze(game)
	for stage in [0.15, 0.45, 0.85]:
		star.linger_time = star.linger_duration * (1.0 - stage)
		for target in game.meteor_layer.get_children():
			if not target.alive and target != star: target.linger_time = target.linger_duration * (1.0 - stage)
		await _capture(game, "supernova_%02d" % int(stage * 100))
		if star.stellar_surface.visible: failures.append("photosphere remained visible after the supernova")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	_finish("STELLAR_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))
