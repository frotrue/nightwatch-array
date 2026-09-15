extends "res://tests/module_overhaul_review.gd"

# Reuse the isolated game/capture fixture. These authored moving specimens are
# art comparisons, not a claim about natural spawn density or player comfort.
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Meteor art review requires desktop rendering")
		quit(1)
		return
	create_timer(60.0, true, false, true).timeout.connect(func(): push_error("Meteor art review timeout"); quit(1))
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
