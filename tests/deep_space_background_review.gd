extends "res://tests/deep_sky_preview.gd"

# Synthetic production-scene captures; does not read or write player saves.
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Deep space review requires a renderer")
		quit(1)
		return
	create_timer(120.0, true, false, true).timeout.connect(func(): push_error("Deep space review timeout"); quit(1))
	root.size = Vector2i(1152, 648)
	root.gui_disable_input = true
	output = "res://build/deep_space_review/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.spawner.reset()
	game.events.running = false
	game.observer.native_cursor_visible = false
	game.hud.hide()
	_freeze(game)
	game.starfield.set_watch_progress(0.0)
	var early := await _sky_frame("01_before_expansion")
	game.starfield.set_watch_progress(0.95)
	await _sky_frame("02_before_expansion_dawn")
	game.progression.debug_purchase_all()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game._close_upgrade_tree_without_transition()
	game.effects.reset()
	for tween in get_processed_tweens(): tween.kill()
	game.starfield.set_watch_progress(0.0)
	var expanded := await _sky_frame("03_expanded_background")
	game.starfield.set_watch_progress(0.95)
	var late := await _sky_frame("04_expanded_round_end")
	if expanded.get_data() != late.get_data(): failures.append("expanded sky changed during observation")
	if early.get_data() == expanded.get_data(): failures.append("expansion did not replace the terrestrial sky")
	game.starfield.finish_watch(false)
	var dimmed := await _sky_frame("05_expanded_intermission")
	if dimmed.get_data() == expanded.get_data(): failures.append("expanded intermission did not dim")
	game.starfield.set_watch_progress(0.0)
	# Production actors show contrast against the asset without imitating mockup UI.
	var specs := [
		["stellar", Vector2(200, 465)], ["galaxy", Vector2(300, 180)],
		["black_hole", Vector2(935, 320)], ["neutron_star", Vector2(810, 155)],
	]
	for index in 14:
		specs.append(["fast" if index % 3 == 0 else "common", Vector2(100 + (index * 211) % 920, 130 + (index * 83) % 340)])
	for spec in specs:
		var origin: Vector2 = game.observation_view.screen_to_world(spec[1])
		var body = game.spawner.spawn_meteor(spec[0], origin, Vector2(75, 28))
		if body == null:
			failures.append("capture could not spawn " + str(spec[0]))
			continue
		for step in 20: body.simulate_tick(1.0 / 60.0)
	_freeze(game)
	game.hud.show()
	var gameplay: Image
	for locale in ["ko", "en"]:
		_set_locale(game, locale)
		game.hud.banner_root.hide()
		game.hud.data_gain_label.hide()
		var localized := await _sky_frame("06_gameplay_" + locale)
		var actors := localized.get_region(Rect2i(100, 100, 950, 450))
		if gameplay != null and gameplay.get_data() != actors.get_data():
			failures.append("locale change altered frozen gameplay actors")
		gameplay = actors
	game.hud.hide()
	game.meteor_layer.hide()
	game.black_hole_lens.hide()
	for size in [Vector2i(1440, 900), Vector2i(2560, 1080)]:
		root.size = size
		game.observation_view.set_observation_span(1.5)
		game.starfield.queue_redraw()
		await _sky_frame("07_resize_%dx%d" % [size.x, size.y])
	root.size = Vector2i(1152, 648)
	game.reset_run()
	_freeze(game)
	game.hud.hide()
	game.effects.reset()
	game.observer.native_cursor_visible = false
	var reset := await _sky_frame("08_reset_to_early")
	if early.get_data() != reset.get_data(): failures.append("reset did not restore the original opening background")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"failures": failures, "frames": records, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	for failure in failures: push_error(failure)
	print("DEEP_SPACE_BACKGROUND_REVIEW_PASS" if failures.is_empty() else "DEEP_SPACE_BACKGROUND_REVIEW_FAIL")
	quit(0 if failures.is_empty() else 1)


func _sky_frame(label: String) -> Image:
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	# Match the parent preview's frozen-canvas refresh after locale/font changes.
	_redraw_capture_items(root)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output.path_join(label + ".png")
	if picture.save_png(path) != OK: failures.append("capture failed: " + label)
	records.append({"file": path, "size": str(picture.get_size()), "window_size": str(root.size)})
	return picture
