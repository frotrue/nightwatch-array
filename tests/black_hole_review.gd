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
	var lens_extent: float = game.black_hole_lens.lens.scale.x * root.canvas_transform.get_scale().x
	for y in 648:
		for x in 1152:
			if baseline.get_pixel(x, y) != refracted.get_pixel(x, y):
				changed += 1
				if Vector2(x, y).distance_to(Vector2(576, 300)) > lens_extent + 2.0: outside += 1
	if changed < 80 or outside > 0: failures.append("lens pixel boundary: changed=%d outside=%d" % [changed, outside])
	print("BLACK_HOLE_LENS_PIXELS changed=", changed, " outside=", outside)
	pattern.hide()
	var sample = game.spawner.spawn_meteor("common", centre + Vector2(40, 0), Vector2(100, 0), 30.0)
	sample.age = 3.0
	sample.primary_color = Color(0.2, 1.0, 0.2)
	sample.glow_color = sample.primary_color
	sample.base_automatic_rate = 0.0
	sample.previous_simulation_position = sample.global_position
	sample.reset_physics_interpolation()
	_freeze(game)
	game.black_hole_lens.motion_scale = 0.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "06_meteor_lens_off")
	var original := _green_centroid(root.get_texture().get_image())
	game.black_hole_lens.motion_scale = 1.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "07_meteor_lens_on")
	var bent := _green_centroid(root.get_texture().get_image())
	var predicted: Vector2 = game.observation_view.world_to_screen(sample.get_observation_position(1.0))
	if original == Vector2.INF or bent == Vector2.INF or bent.distance_to(original) < 8.0 or bent.distance_to(predicted) > 6.0:
		failures.append("meteor lens/selection mismatch: original=%s actual=%s predicted=%s" % [original, bent, predicted])
	print("METEOR_LENS_CENTRE original=", original, " rendered=", bent, " selection=", predicted)
	var secondary := _green_centroid(root.get_texture().get_image(), Rect2i(495, 275, 50, 50))
	if secondary == Vector2.INF: failures.append("missing inverted meteor image outside the black shadow")
	print("METEOR_LENS_SECONDARY centre=", secondary)
	# Real trail crossing behind the shadow: two curved arcs, not a painted ring.
	sample.primary_color = Color("b6dbed")
	sample.glow_color = sample.primary_color
	sample.position = centre + Vector2(65, 12)
	sample.previous_simulation_position = sample.position
	for station in 40: sample.trail_points.append(sample.position - Vector2(4, 0) * float(station))
	sample.reset_physics_interpolation()
	game.black_hole_lens.motion_scale = 0.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "08_trail_lens_off")
	game.black_hole_lens.motion_scale = 1.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "09_trail_lens_on")
	await _review_multiple(game)
	await _review_light_strands(game)
	game.free()
	paused = false
	_finish("BLACK_HOLE_REVIEW", "%d captures at " % records.size() + ProjectSettings.globalize_path(output))

func _review_light_strands(game: Node2D) -> void:
	_clear_sky(game)
	await process_frame
	game.effects.reset()
	game.starfield.set_galactic_mode(true)
	game.starfield.set_watch_progress(0.0)
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(576, 300))
	var hole = game.spawner.spawn_meteor("black_hole", centre, Vector2.RIGHT, 30.0)
	hole.age = 5.0
	hole.wobble_phase = 0.6
	_freeze(game)
	game.black_hole_lens.motion_scale = 1.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "14_light_strands_deep_space")
	var region := Rect2i(530, 254, 92, 92)
	var moving := root.get_texture().get_image().get_region(region)
	hole.age = 9.0
	await _capture(game, "15_light_strands_flow")
	if moving.get_data() == root.get_texture().get_image().get_region(region).get_data():
		failures.append("light strands did not flow with simulation age")
	hole.completion_motion_scale = 0.0
	await _capture(game, "16_light_strands_motion_zero")
	var still := root.get_texture().get_image().get_region(region)
	hole.age = 13.0
	await _capture(game, "17_light_strands_motion_zero_later")
	if still.get_data() != root.get_texture().get_image().get_region(region).get_data():
		failures.append("light strands moved at zero motion strength")
	if still.get_pixel(46, 46).get_luminance() > 0.03:
		failures.append("black hole centre lost its dark silhouette")
	# Enlarged production geometry for inspecting strand falloff, not game scale.
	hole.body_radius *= 3.0
	hole.completion_motion_scale = 1.0
	game.black_hole_lens._process(0.0)
	await _capture(game, "18_light_strands_detail_3x")

func _green_centroid(frame: Image, region := Rect2i(580, 270, 106, 61)) -> Vector2:
	var total := 0.0
	var centre := Vector2.ZERO
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var color := frame.get_pixel(x, y)
			var weight := maxf(0.0, color.g - maxf(color.r, color.b) * 1.6)
			total += weight
			centre += Vector2(x, y) * weight
	return centre / total if total > 0.01 else Vector2.INF

func _review_multiple(game: Node2D) -> void:
	_clear_sky(game)
	await process_frame
	game.effects.reset()
	var holes: Array = []
	var samples: Array = []
	for index in 3:
		var centre: Vector2 = game.observation_view.screen_to_world(Vector2(230 + index * 345, 210))
		var hole = game.spawner.spawn_meteor("black_hole", centre, Vector2.RIGHT, 30.0)
		hole.age = 5.0
		holes.append(hole)
		var sample = game.spawner.spawn_meteor("common", centre + Vector2(40, 0), Vector2.RIGHT, 30.0)
		sample.age = 3.0
		sample.primary_color = Color(0.2, 1.0, 0.2)
		sample.glow_color = sample.primary_color
		sample.base_automatic_rate = 0.0
		samples.append(sample)
	_freeze(game)
	game.black_hole_lens._process(0.0)
	await _capture(game, "10_three_lenses")
	_check_multiple_centres(game, samples)
	# Overlap two lens passes and verify their composed primary image.
	holes[1].position = holes[0].position + Vector2(60, 0)
	samples[0].position = holes[0].position + Vector2(110, 0)
	samples[1].hide()
	for body in [holes[1], samples[0]]:
		body.previous_simulation_position = body.position
		body.reset_physics_interpolation()
	game.black_hole_lens._process(0.0)
	await _capture(game, "11_overlapping_lenses")
	_check_multiple_centres(game, [samples[0], samples[2]])
	# Full supported scene for manual visual/performance review: three stars
	# with independent heat materials plus all three black hole passes.
	for index in 3:
		var centre: Vector2 = game.observation_view.screen_to_world(Vector2(230 + index * 345, 430))
		var star = game.spawner.spawn_meteor("stellar", centre, Vector2.RIGHT, 30.0)
		star.age = 5.0
		star.observation_progress = 0.2 + index * 0.3
	_freeze(game)
	game.black_hole_lens._process(0.0)
	await _capture(game, "12_three_stars_and_holes")
	game.black_hole_lens.motion_scale = 0.0
	game.black_hole_lens._process(0.0)
	for body in game.meteor_layer.get_children():
		body.completion_motion_scale = 0.0
		body.queue_redraw()
	await _capture(game, "13_six_bodies_reduced_motion")

func _check_multiple_centres(game: Node2D, samples: Array) -> void:
	var frame := root.get_texture().get_image()
	for sample in samples:
		var predicted: Vector2 = game.observation_view.world_to_screen(sample.get_observation_position(1.0))
		var region := Rect2i(Vector2i(predicted) - Vector2i(25, 25), Vector2i(51, 51))
		region = region.intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
		var actual := _green_centroid(frame, region)
		if actual == Vector2.INF or actual.distance_to(predicted) > 6.0:
			failures.append("multiple-lens selection mismatch: rendered=%s selection=%s" % [actual, predicted])
		print("MULTIPLE_LENS_CENTRE rendered=", actual, " selection=", predicted)
