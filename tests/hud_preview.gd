extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")

# Captures the main HUD for design review. Run windowed, not --headless.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var survey_preview := OS.get_environment("NIGHTWATCH_SURVEY_PREVIEW") == "1"
	var galactic_preview := OS.get_environment("NIGHTWATCH_GALACTIC_PREVIEW") == "1"
	var transit_preview := OS.get_environment("NIGHTWATCH_TRANSIT_PREVIEW") == "1"
	var ending_preview := OS.get_environment("NIGHTWATCH_ENDING_PREVIEW") == "1"
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	Fixtures.configure_before_ready(game)
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
	if survey_preview or galactic_preview or transit_preview or ending_preview:
		game.set_process(false)
		game.spawner.set_process(false)
		game.events.set_process(false)
		game.sky_contacts.set_process(false)
	if ending_preview:
		var preview_locale := OS.get_environment("NIGHTWATCH_ENDING_PREVIEW_LOCALE")
		if preview_locale in ["en", "ko"]:
			TranslationServer.set_locale(preview_locale)
		game._show_catalogue_ending_debug_preview()
		# Capture the actual map at a chosen reveal beat (2.8 / 5.2 / 8.1s).
		# By default retain the completed map beside the record and choices.
		var requested_step := OS.get_environment("NIGHTWATCH_ENDING_PREVIEW_STEP").to_float()
		game.hud.end_reveal_tween.custom_step(requested_step if requested_step > 0.0 else 8.1)
		if game.hud.end_reveal_tween != null and game.hud.end_reveal_tween.is_valid():
			game.hud.end_reveal_tween.pause()
		game.hud.end_coda.set_process(false)
		game.hud.end_coda.queue_redraw()
	elif galactic_preview or transit_preview:
		game.progression.debug_purchase_all()
		if transit_preview:
			game.host_stars.advance_time(game.host_stars.next_transit_remaining)
			game.host_stars.advance_time(game.host_stars.TRANSIT_WINDOW * 0.48)
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
	for _index in range(12):
		await process_frame
	RenderingServer.force_draw()
	RenderingServer.force_sync()
	if ending_preview:
		print("ENDING_PREVIEW_STATE: ", JSON.stringify({
			"constellations": game.hud.end_coda.constellation_progress,
			"pullback": game.hud.end_coda.pullback_progress,
			"route": game.hud.end_coda.route_progress,
			"illumination": game.hud.end_coda.illumination_progress,
			"settle": game.hud.end_coda.settle_progress,
			"body_alpha": game.hud.end_reveal_body.modulate.a,
			"actions_alpha": game.hud.end_actions.modulate.a,
		}))
	var image := root.get_texture().get_image()
	var output_path := "res://build/ending_preview.png" if ending_preview else ("res://build/transit_preview.png" if transit_preview else ("res://build/galactic_preview.png" if galactic_preview else ("res://build/survey_preview.png" if survey_preview else "res://build/hud_preview.png")))
	print("PREVIEW_SAVED" if image.save_png(output_path) == OK else "PREVIEW_FAILED")
	quit()
