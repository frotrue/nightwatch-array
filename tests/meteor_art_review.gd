extends "res://tests/module_overhaul_review.gd"

# Reuse the isolated game/capture fixture. These authored moving specimens are
# art comparisons, not a claim about natural spawn density or player comfort.
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Meteor art review requires desktop rendering")
		quit(1)
		return
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Meteor art review timeout"); quit(1))
	if "--special" in OS.get_cmdline_user_args():
		await _review_special()
		return
	root.gui_disable_input = true
	var game := await _game()
	_freeze(game)
	_clear_sky(game)
	game.hud.hide()
	game.observer.hide()
	game.effects.reset()
	var source := Capture.source_snapshot(failures)
	var revision := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	output = "res://build/meteor_art_review/" + revision + "/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var captions := CanvasLayer.new()
	root.add_child(captions)
	var title := Label.new()
	title.position = Vector2(55, 45)
	title.add_theme_font_size_override("font_size", 22)
	captions.add_child(title)
	for scenario in ["detail", "normal", "shower"]:
		_clear_sky(game)
		game.effects.reset()
		var targets: Array = []
		var amount := 2 if scenario == "detail" else (6 if scenario == "normal" else 24)
		title.text = {"detail": "일반 · 고속 유성  /  4배 확대", "normal": "일반 · 고속 유성  /  기본 크기", "shower": "일반 · 고속 유성  /  유성우 밀도 시안"}[scenario]
		for index in amount:
			var kind := "common" if index % 2 == 0 else "fast"
			var target = game.spawner.spawn_meteor(kind, Vector2.ZERO, Vector2.RIGHT.rotated(-0.10) * float(Balance.meteor_spec(kind).speed), 30.0)
			if target == null:
				failures.append("could not spawn review specimen " + str(index))
				continue
			_freeze(target)
			target.base_automatic_rate = 0.0
			target.dish_assist_rate = 0.0
			target.lane_assist_rate = 0.0
			target.wobble_phase = float(index) * 1.37
			target.scale = Vector2.ONE * (4.0 if scenario == "detail" else 1.0)
			targets.append(target)
		_pose(game, targets, scenario, 0.0)
		await _capture(game, scenario)
		if "--animate" in OS.get_cmdline_user_args():
			var directory := output.path_join(scenario + "_frames")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			for frame in 120:
				_pose(game, targets, scenario, float(frame) / 30.0)
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(directory.path_join("%03d.png" % frame)) != OK:
					failures.append("could not write animation frame")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": source, "frames": records, "failures": failures, "synthetic": true, "fps": 30}, "\t"))
	file.close()
	captions.free()
	game.free()
	paused = false
	_finish("METEOR_ART_REVIEW", "detail, ordinary sky and 24-target density at " + ProjectSettings.globalize_path(output))


func _pose(game: Node, targets: Array, scenario: String, time: float) -> void:
	for index in targets.size():
		var target = targets[index]
		var direction := Vector2.RIGHT.rotated(-0.10)
		var speed := float(Balance.meteor_spec(target.type_id).speed)
		var screen := Vector2(765, 230 + index * 170)
		if scenario != "detail":
			var travel := fposmod(120.0 + index * 173.0 + speed * time, 1400.0)
			screen = Vector2(travel - 120.0, 180.0 + fposmod(index * 79.0, 290.0) - travel * 0.07)
		target.position = game.observation_view.screen_to_world(screen)
		target.age = 0.8 + time
		target.trail_points.clear()
		for sample in target.max_trail_points:
			var distance := float(sample + 1) * speed / 60.0
			var history: Vector2 = target.position - direction * distance
			history.y += sin(float(sample) * 0.10) * float(sample) * 0.045
			target.trail_points.append(history)
		target.reset_physics_interpolation()
		target.queue_redraw()


func _review_special() -> void:
	root.gui_disable_input = true
	var game := await _game()
	_freeze(game)
	_clear_sky(game)
	game.hud.hide()
	game.observer.hide()
	game.effects.reset()
	var source := Capture.source_snapshot(failures)
	var revision := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	output = "res://build/sample_meteor_review/" + revision + "/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for scenario in ["detail", "normal"]:
		game.deep_sky.director.end_round()
		var ticket: String = "n/art/" + scenario
		game.deep_sky.director._ensure_ticket(ticket, "rare", "natural")
		game.deep_sky.director._spawn_component({"ticket": ticket, "event_id": ticket, "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.30, 0.35), "end": Vector2(0.68, 0.53)})
		var target = game.deep_sky.director.targets()[0]
		_freeze(target)
		target.scale = Vector2.ONE * (4.0 if scenario == "detail" else 1.0)
		_special_pose(game, target, scenario, 0.0)
		await _capture(game, scenario)
		if "--animate" in OS.get_cmdline_user_args():
			var directory := output.path_join(scenario + "_frames")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			for frame in 120:
				var time := float(frame) / 30.0
				_special_pose(game, target, scenario, minf(time, 3.5))
				if frame == 105:
					var samples_before: int = game.deep_sky.samples
					target.stage_progress = 1.0
					target.manual_work = 1.0
					target.tick_resolve()
					var samples_after: int = game.deep_sky.samples
					target.tick_resolve()
					if samples_after <= samples_before or game.deep_sky.samples != samples_after:
						failures.append("special art fixture must complete through the normal one-time sample reward")
				if frame >= 105:
					target._linger = maxf(0.0, 0.45 - (time - 3.5))
				# Isolate this target's body animation; reward particles have their own renderer probe.
				game.effects.reset()
				await process_frame
				await RenderingServer.frame_post_draw
				if root.get_texture().get_image().save_png(directory.path_join("%03d.png" % frame)) != OK:
					failures.append("could not write special meteor animation frame")
	if revision != "before":
		await _verify_special_surface(game)
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": source, "frames": records, "failures": failures, "synthetic": true, "fps": 30}, "\t"))
	file.close()
	game.free()
	paused = false
	_finish("SAMPLE_METEOR_ART_REVIEW", "special meteor detail, native size and completion at " + ProjectSettings.globalize_path(output))


func _special_pose(game: Node, target: Node2D, scenario: String, time: float) -> void:
	var screen := Vector2(735, 285)
	if scenario == "normal":
		screen = Vector2(500, 280) + Vector2(46, 12) * time
	target.position = game.observation_view.screen_to_world(screen)
	target.body_position = target.global_position
	target.age = 3.5 + time
	if target.alive:
		target.stage_progress = minf(time / 3.5, 0.99)
	target.previous_simulation_position = target.global_position
	target.reset_physics_interpolation()
	target.queue_redraw()


func _verify_special_surface(game: Node) -> void:
	game.deep_sky.director.end_round()
	game.deep_sky.director._ensure_ticket("n/art/settings", "rare", "natural")
	game.deep_sky.director._spawn_component({"ticket": "n/art/settings", "kind": "rare", "origin_kind": "natural", "start": Vector2(0.30, 0.35), "end": Vector2(0.68, 0.53)})
	var target = game.deep_sky.director.targets()[0]
	_freeze(target)
	_special_pose(game, target, "normal", 0.0)
	target.age = 0.5
	await _capture(game, "warning")
	if target._surface.visible:
		failures.append("special meteor surface visible before its arrival warning ends")
	var crop := Rect2i(395, 250, 130, 55)
	game.effects.set_accessibility_effects(0.0, false)
	target.age = 3.5
	# Let the warning-to-body visibility change submit before comparing settled frames.
	target.queue_redraw()
	await _capture(game, "reduced_motion_a")
	var still := root.get_texture().get_image().get_region(crop).get_data()
	target.age += 2.0
	await _capture(game, "reduced_motion_b")
	if still != root.get_texture().get_image().get_region(crop).get_data():
		failures.append("zero-motion special meteor still animates at a fixed position")
	game.effects.set_accessibility_effects(1.0, true)
	await _capture(game, "motion_a")
	var moving := root.get_texture().get_image().get_region(crop).get_data()
	target.age += 2.0
	await _capture(game, "motion_b")
	var lit: Color = root.get_texture().get_image().get_pixel(500, 280)
	if moving == root.get_texture().get_image().get_region(crop).get_data():
		failures.append("special meteor surface does not animate with motion enabled")
	target.self_modulate = Color.BLACK
	await _capture(game, "body_tint")
	var tinted: Color = root.get_texture().get_image().get_pixel(500, 280)
	if tinted.get_luminance() >= lit.get_luminance() * 0.5:
		failures.append("special meteor surface ignores its body's tint")
	target.self_modulate = Color.WHITE
	target.stage_progress = 1.0
	target.manual_work = 1.0
	target.tick_resolve()
	target._linger = 0.23
	game.effects.reset()
	await _capture(game, "completion")
	game.effects.set_accessibility_effects(0.0, false)
	await _capture(game, "reduced_completion")
	target._linger = 0.0
	await _capture(game, "faded")
	var faded := root.get_texture().get_image().get_region(crop).get_data()
	target.hide()
	await _capture(game, "empty")
	if faded != root.get_texture().get_image().get_region(crop).get_data():
		failures.append("special meteor leaves a visible surface after fading out")
