extends "res://tests/module_overhaul_review.gd"

class HeatReference:
	extends Node2D
	func _draw() -> void:
		for y in range(-90, 91, 6):
			for x in range(-90, 91, 6):
				draw_circle(Vector2(x, y), 0.65, Color("94b7c9"))

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
	await _review_animation(game, star, centre, unit)
	for target in game.meteor_layer.get_children(): target.show()
	var hole = game.black_hole_lens.target
	var original_hole_position: Vector2 = hole.position
	hole.position = centre + Vector2(100, 0) * unit
	hole.previous_simulation_position = hole.position
	hole.reset_physics_interpolation()
	game.black_hole_lens._process(0.0)
	await _capture(game, "10_heat_lens_overlap")
	hole.position = original_hole_position
	hole.previous_simulation_position = hole.position
	hole.reset_physics_interpolation()
	game.black_hole_lens._process(0.0)
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
		if star.stellar_surface.background_copy.copy_mode != BackBufferCopy.COPY_MODE_DISABLED: failures.append("completed star still copied the screen")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	game.free()
	paused = false
	_finish("STELLAR_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))

func _review_animation(game: Node, star: Node2D, centre: Vector2, unit: float) -> void:
	game.black_hole_lens._process(0.0)
	var pattern := HeatReference.new()
	pattern.position = centre
	pattern.scale = Vector2.ONE * unit
	pattern.z_index = 0
	game.add_child(pattern)
	star.stellar_surface.heat_enabled = false
	await _capture(game, "04_heat_reference_off")
	var original := root.get_texture().get_image()
	star.stellar_surface.heat_enabled = true
	await _capture(game, "05_heat_reference_on")
	var warped := root.get_texture().get_image()
	var screen_centre: Vector2 = game.observation_view.world_to_screen(centre)
	var outer_radius: float = star.get_observation_body_radius() / unit * 3.0 + 2.0
	var changed := 0
	var outside := 0
	for y in 648:
		for x in 1152:
			if original.get_pixel(x, y) != warped.get_pixel(x, y):
				changed += 1
				if Vector2(x, y).distance_to(screen_centre) > outer_radius: outside += 1
	if changed < 20 or outside > 0: failures.append("heat distortion scope: changed=%d outside=%d" % [changed, outside])
	print("STELLAR_HEAT_PIXELS changed=", changed, " outside=", outside)
	pattern.free()
	# This target is spawned after the star, as most real passing meteors are.
	# Heat must reach its rendered trail without moving its simulation position.
	var nearby := _nearby_meteor(game, centre, unit)
	var physical_position: Vector2 = nearby.position
	star.stellar_surface.heat_enabled = false
	await _capture(game, "11_nearby_meteor_heat_off")
	var original_centre := _green_centre(root.get_texture().get_image())
	star.stellar_surface.heat_enabled = true
	await _capture(game, "12_nearby_meteor_heat_on")
	var warped_centre := _green_centre(root.get_texture().get_image())
	if not original_centre.is_finite() or not warped_centre.is_finite() or original_centre.distance_to(warped_centre) < 1.0:
		failures.append("heat did not refract the later-spawned meteor")
	if nearby.position != physical_position: failures.append("visual heat moved the meteor's simulation position")
	print("STELLAR_NEIGHBOR_SHIFT pixels=", original_centre.distance_to(warped_centre))
	nearby.free()
	# Hold the normal arrival/fade envelope on its steady plateau, so this
	# compares animation rather than the ordinary lifetime visibility change.
	star.age = star.visible_lifetime * 0.4
	star.completion_motion_scale = 0.0
	await _capture(game, "06_motion_off")
	var still := root.get_texture().get_image()
	star.age += 1.0
	await _capture(game, "07_motion_off_later")
	if still.get_data() != root.get_texture().get_image().get_data(): failures.append("reduced-motion surface still animated")
	if star.stellar_surface.background_copy.copy_mode != BackBufferCopy.COPY_MODE_DISABLED: failures.append("reduced motion still copied the screen")
	star.completion_motion_scale = 1.0
	star.completion_glint_enabled = false
	star.age = 3.0
	star.observation_progress = 0.05
	await _capture(game, "08_low_charge")
	var low := root.get_texture().get_image()
	star.observation_progress = 0.95
	await _capture(game, "09_high_charge")
	if low.get_data() == root.get_texture().get_image().get_data(): failures.append("observation progress has no visual feedback")
	if star.stellar_surface.photosphere.material.get_shader_parameter("pulses") != 0.0: failures.append("flash setting did not suppress light pulses")
	star.completion_glint_enabled = true
	star.position = Vector2(-3000, -3000)
	star.stellar_surface.present(star.get_observation_body_radius(), 1.0, star.age, star.wobble_phase, 0.95, 1.0, true, Color.WHITE)
	if star.stellar_surface.background_copy.copy_mode != BackBufferCopy.COPY_MODE_DISABLED: failures.append("off-screen star still copied the screen")
	star.position = centre
	if "--animate" in OS.get_cmdline_user_args():
		await _capture_animation(game, star, centre, unit)
	star.age = 3.0
	star.observation_progress = 0.78

func _nearby_meteor(game: Node, centre: Vector2, unit: float) -> Node2D:
	var nearby = game.spawner.spawn_meteor("common", centre + Vector2(70, -18) * unit, Vector2(120, 0), 30.0)
	nearby.primary_color = Color(0.08, 1.0, 0.08)
	nearby.glow_color = nearby.primary_color
	nearby.age = 5.0
	for i in 16: nearby.trail_points.append(nearby.position - Vector2(2.0 * i, 0.5 * i) * unit)
	nearby.set_process(false)
	return nearby

func _green_centre(frame: Image) -> Vector2:
	var weighted_position := Vector2.ZERO
	var total := 0.0
	for y in range(235, 305):
		for x in range(570, 665):
			var color := frame.get_pixel(x, y)
			var weight := maxf(0.0, color.g - maxf(color.r, color.b) * 1.6)
			weighted_position += Vector2(x, y) * weight
			total += weight
	return weighted_position / total if total > 0.0 else Vector2.INF

func _capture_animation(game: Node, star: Node2D, centre: Vector2, unit: float) -> void:
	var directory := output.path_join("animation")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var nearby := _nearby_meteor(game, centre, unit)
	game.sky_contacts.hide()
	for frame in 150:
		star.age = 3.0 + float(frame) / 30.0
		star.observation_progress = clampf((float(frame) - 45.0) / 110.0, 0.0, 0.95)
		star.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image().get_region(Rect2i(395, 135, 310, 310))
		if capture.save_png(directory.path_join("%03d.png" % frame)) != OK: failures.append("animation frame write failed")
	nearby.free()
	game.sky_contacts.show()
