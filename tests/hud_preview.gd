extends SceneTree

# Captures the main HUD for design review. Run windowed, not --headless.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var survey_preview := OS.get_environment("NIGHTWATCH_SURVEY_PREVIEW") == "1"
	var galactic_preview := OS.get_environment("NIGHTWATCH_GALACTIC_PREVIEW") == "1"
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	game.upgrade_tree.close_tree()
	game.hud.close_settings() if game.hud.has_method("close_settings") else null
	game.progression.add_debug_data(1284.0)
	game.hud.set_observation_phase(3, 24.0, 40.0)
	# Freeze the gameplay controller so it cannot hide the synthetic tracking
	# readout before the capture settles.
	game.observer.set_process(false)
	if survey_preview or galactic_preview:
		game.set_process(false)
		game.spawner.set_process(false)
		game.events.set_process(false)
		game.sky_contacts.set_process(false)
	if galactic_preview:
		game.progression.debug_purchase_all()
		game.hud.hide_tracking()
	elif survey_preview:
		game.progression.debug_purchase_node("polar_survey")
		game.survey.begin_round(3)
		var sweep_cursor := Vector2(560.0, 420.0)
		game.survey.set_scanning(true, sweep_cursor)
		game.survey.apply_scan_segment(sweep_cursor - Vector2(210.0, 0.0), sweep_cursor)
		game.observer.cursor_position = sweep_cursor
		game.observer.previous_cursor_position = game.observer.cursor_position
		game.observer.was_holding = true
		game.observer.interaction_mode = game.observer.InteractionMode.SCANNING
		game.observer.queue_redraw()
		game.hud.hide_tracking()
	else:
		var centre: Vector2 = root.get_visible_rect().size * Vector2(0.5, 0.62)
		game.hud.set_tracking(0.67, "fast", 1.34, 1, centre)
	for _index in range(8):
		await process_frame
	var image := root.get_texture().get_image()
	var output_path := "res://build/galactic_preview.png" if galactic_preview else ("res://build/survey_preview.png" if survey_preview else "res://build/hud_preview.png")
	print("PREVIEW_SAVED" if image.save_png(output_path) == OK else "PREVIEW_FAILED")
	quit()
