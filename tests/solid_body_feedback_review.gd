extends "res://tests/module_overhaul_review.gd"

class OcclusionReference:
	extends Node2D
	var points := PackedVector2Array()
	var radius := 5.0
	func _draw() -> void:
		for point in points: draw_circle(point, radius, Color.MAGENTA)

# Real game completion signals, save-free frozen poses for visual review.
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	create_timer(40.0).timeout.connect(func(): push_error("Solid feedback review timeout"); quit(1))
	var game := await _game()
	_freeze(game)
	_clear_sky(game)
	game.hud.hide()
	game.observer.hide()
	game.effects.reset()
	output = "res://build/solid_body_feedback_review/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var targets: Array = []
	var captions := CanvasLayer.new()
	root.add_child(captions)
	var kinds := ["variable_star", "binary_star", "galaxy"]
	for index in kinds.size():
		var screen := Vector2(240 + index * 335, 300)
		var target = game.spawner.spawn_meteor(kinds[index], game.observation_view.screen_to_world(screen), Vector2(120, -20), 30.0)
		# A fully arrived body must occlude the reference and animate without
		# relying on the ordinary arrival-opacity ramp.
		target.age = 8.0
		target.wobble_phase = 0.6
		target.set_process(false)
		targets.append(target)
		var label := Label.new()
		label.position = screen + Vector2(-110, 125)
		label.size = Vector2(220, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = ["소행성", "얼음 소행성", "행성"][index]
		captions.add_child(label)
	await _capture(game, "01_before")
	var initial := root.get_texture().get_image()
	var occlusion := OcclusionReference.new()
	occlusion.z_index = 9
	occlusion.radius = game.observation_view.screen_length_to_world(5.0)
	for target in targets: occlusion.points.append(target.position)
	game.add_child(occlusion)
	await _capture(game, "08_background_occlusion")
	var covered := root.get_texture().get_image()
	for index in 3:
		var region := Rect2i(237 + index * 335, 297, 6, 6)
		if initial.get_region(region).get_data() != covered.get_region(region).get_data():
			failures.append("background light leaked through solid body " + str(index))
	occlusion.free()
	for target in targets: target.age = 12.0
	await _capture(game, "02_evolved")
	_compare_bodies(initial, root.get_texture().get_image(), "material animation")
	for target in targets: target.observation_progress = 0.05
	await _capture(game, "03_low_progress")
	var low := root.get_texture().get_image()
	for target in targets: target.observation_progress = 0.95
	await _capture(game, "04_high_progress")
	_compare_bodies(low, root.get_texture().get_image(), "observation feedback")
	for target in targets: target.self_modulate = Color.BLACK
	await _capture(game, "09_material_tint")
	var tinted := root.get_texture().get_image()
	for index in 3:
		var center := tinted.get_pixel(240 + index * 335, 300)
		if maxf(center.r, maxf(center.g, center.b)) > 0.01: failures.append("material ignored body tint " + str(index))
	for target in targets: target.self_modulate = Color.WHITE
	for target in targets:
		target.age = 12.0
		target.completion_motion_scale = 0.0
		target.completion_glint_enabled = false
	await _capture(game, "05_still")
	var still := root.get_texture().get_image()
	for target in targets: target.age = 13.0
	await _capture(game, "06_still_later")
	if still.get_data() != root.get_texture().get_image().get_data(): failures.append("reduced-motion materials still moved")
	for target in targets:
		var surface = target.planet_surface.clouds.material if target.type_id == "galaxy" else target.material
		if surface.get_shader_parameter("flashes") != 0.0: failures.append("flash setting ignored: " + target.type_id)
		target.age = 8.0
		target.completion_motion_scale = 1.0
		target.completion_glint_enabled = true
		target.scale = Vector2.ONE * 2.0
	await _capture(game, "07_detail")
	for target in targets: target.scale = Vector2.ONE
	var target_count: int = game.meteor_layer.get_child_count()
	if "--animate" in OS.get_cmdline_user_args():
		await _capture_animation(game, targets)
	else:
		for target in targets: target._finish_observation(1.0)
	if target_count != game.meteor_layer.get_child_count(): failures.append("completion art created new observation targets")
	# Isolate the body art; the normal bounded reward particles are tested separately.
	game.effects.reset()
	for elapsed in [0.06, 0.23, 0.43]:
		for target in targets:
			target.linger_time = target.linger_duration - elapsed
			target.queue_redraw()
		await _capture(game, "completion_%03dms" % int(elapsed * 1000))
	for target in targets:
		target.completion_motion_scale = 0.0
		target.completion_glint_enabled = false
		target.linger_time = target.linger_duration - 0.23
		target.queue_redraw()
	await _capture(game, "05_reduced_motion")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"frames": records, "failures": failures, "synthetic": true}, "\t"))
	manifest.close()
	captions.free()
	game.free()
	paused = false
	_finish("SOLID_BODY_FEEDBACK_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))

func _compare_bodies(before: Image, after: Image, reason: String) -> void:
	for index in 3:
		var region := Rect2i(160 + index * 335, 220, 160, 160)
		if before.get_region(region).get_data() == after.get_region(region).get_data():
			failures.append(reason + " missing for body " + str(index))

func _capture_animation(game: Node, targets: Array) -> void:
	var directory := output.path_join("animation")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for target in targets: target.scale = Vector2.ONE * 1.8
	for frame in 150:
		for target in targets:
			if frame < 120:
				target.age = 4.0 + float(frame) / 30.0
				target.observation_progress = clampf((float(frame) - 20.0) / 100.0, 0.0, 0.95)
			else:
				target.age = 8.0
				if frame == 120: target._finish_observation(1.0)
				target.linger_time = maxf(0.0, target.linger_duration - float(frame - 120) / 30.0)
			target.queue_redraw()
		game.effects.reset()
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image().get_region(Rect2i(100, 160, 960, 300))
		if capture.save_png(directory.path_join("%03d.png" % frame)) != OK: failures.append("animation frame write failed")
	for target in targets: target.scale = Vector2.ONE
