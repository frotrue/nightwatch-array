extends "res://tests/module_overhaul_review.gd"

# Real-renderer, save-free completion sequence plus a deterministic lens oracle.
class ReferenceStars:
	extends Node2D
	func _draw() -> void:
		for row in 13:
			for column in 17:
				draw_circle(Vector2(400 + column * 20, 180 + row * 20), 1.1, Color("aab7cd"))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	create_timer(45.0).timeout.connect(func(): push_error("Black hole review timeout"); quit(1))
	var game := await _game()
	_freeze(game)
	_clear_sky(game)
	game.effects.reset()
	game.observer.hide()
	game.hud.hide()
	output = "res://build/black_hole_review/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(576, 300))
	var source = game.spawner.spawn_meteor("black_hole", centre, Vector2(22, -3), 30.0)
	source.age = 5.0
	source.entry_position = centre - Vector2(100, -14)
	source.burnout_position = centre + Vector2(500, -70)
	var targets: Array = []
	for index in 9:
		var angle := TAU * float(index) / 9.0
		var point := centre + Vector2.from_angle(angle) * (180.0 + float(index % 2) * 35.0)
		var kind: String = ["common", "fast", "fragment", "variable_star", "binary_star"][index % 5]
		var target = game.spawner.spawn_meteor(kind, point, Vector2(25, -8), 25.0)
		target.age = 2.0
		target.wobble_phase = 0.6
		target.entry_position = point - Vector2(25, -8) * 2.0
		target.burnout_position = point + Vector2(25, -8) * 23.0
		for station in 20: target.trail_points.append(point - Vector2(3, -1) * float(station))
		targets.append(target)
	_freeze(game)
	source.previous_simulation_position = source.global_position
	source.reset_physics_interpolation()
	game.black_hole_lens._process(0.0)
	await _capture(game, "01_moving_black_hole")
	source.observation_progress = 1.0
	source._finish_observation(1.0)
	game.effects.reset()
	for tick in 51:
		for target in targets: target.tick_motion(1.0 / 60.0, tick + 1)
		source.tick_motion(1.0 / 60.0, tick + 1)
		if tick in [17, 50]:
			for target in targets:
				target.previous_simulation_position = target.global_position
				target.reset_physics_interpolation()
			game.black_hole_lens._process(0.0)
			await _capture(game, "02_pull_300ms" if tick == 17 else "03_gathered_850ms")
	_clear_sky(game)
	await process_frame
	var pattern := ReferenceStars.new()
	pattern.z_index = -19
	game.add_child(pattern)
	var hole = game.spawner.spawn_meteor("black_hole", centre, Vector2(1, 0), 30.0)
	hole.age = 5.0
	hole.previous_simulation_position = hole.global_position
	hole.reset_physics_interpolation()
	_freeze(game)
	game.black_hole_lens.motion_scale = 0.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "04_lens_reference_off")
	var baseline := root.get_texture().get_image()
	game.black_hole_lens.motion_scale = 1.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "05_lens_reference_on")
	var refracted := root.get_texture().get_image()
	var changed := 0
	var outside := 0
	for y in 648:
		for x in 1152:
			if baseline.get_pixel(x, y) != refracted.get_pixel(x, y):
				changed += 1
				if Vector2(x, y).distance_to(Vector2(576, 300)) > 105.0: outside += 1
	if changed < 80 or outside > 0: failures.append("lens pixel boundary: changed=%d outside=%d" % [changed, outside])
	print("BLACK_HOLE_LENS_PIXELS changed=", changed, " outside=", outside)
	game.free()
	paused = false
	_finish("BLACK_HOLE_REVIEW", "%d captures at " % records.size() + ProjectSettings.globalize_path(output))
