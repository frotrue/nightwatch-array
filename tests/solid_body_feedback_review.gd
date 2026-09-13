extends "res://tests/module_overhaul_review.gd"

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
	output = "res://build/solid_body_feedback_review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var targets: Array = []
	var captions := CanvasLayer.new()
	root.add_child(captions)
	var kinds := ["variable_star", "binary_star", "galaxy"]
	for index in kinds.size():
		var screen := Vector2(240 + index * 335, 300)
		var target = game.spawner.spawn_meteor(kinds[index], game.observation_view.screen_to_world(screen), Vector2(120, -20), 30.0)
		target.age = 2.0
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
	for target in targets: target._finish_observation(1.0)
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
	captions.free()
	game.free()
	paused = false
	_finish("SOLID_BODY_FEEDBACK_REVIEW", "%d frames at " % records.size() + ProjectSettings.globalize_path(output))
