extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
var game: Node
var output := ""
var recording := false
var record_frames := 0
var failures: Array[String] = []
var manifest: Array[Dictionary] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Ending review requires a renderer"); quit(1); return
	recording = "--record" in OS.get_cmdline_user_args()
	root.size = Vector2i(1152, 648)
	root.gui_disable_input = true
	var output_root := "res://build/ending_review"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_root = argument.trim_prefix("--output=").trim_suffix("/")
	output = output_root + "/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	# Synthetic bulk research must not add purchase cues to the ending soundtrack.
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await process_frame
	game.settings.set_language("ko")
	game.settings.set_muted(false, false)
	game.settings.set_mute_when_unfocused(false, false)
	game.settings.set_motion_intensity(1.0)
	game.settings.set_screen_flashes_enabled(true)
	game.progression.debug_purchase_all()
	game.deep_sky.debug_purchase_all_research()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game._close_upgrade_tree_without_transition()
	game.ending.set_process(false)
	game.ending.start(true)
	if recording:
		process_frame.connect(_record_frame)
		return
	await _capture("00_last_signal")
	for stage in range(1, 7):
		while game.ending.phase < stage: _step(0.1)
		var stage_sample: float = minf(5.0, game.ending.DURATIONS[stage] * 0.5)
		while game.ending.phase_elapsed < stage_sample - 0.00001: _step(minf(0.05, stage_sample - game.ending.phase_elapsed))
		await _capture("%02d_stage" % stage)
		if stage == 2:
			game.ending.open_settings()
			await _capture("02_settings_pause")
			game.hud.close_settings()
			game.hud.layer = 80
		if stage == 4:
			for moment in [8.0, 12.0, 16.0, 19.0, 24.0, 26.0, 27.0, 27.4, 27.7]:
				while game.ending.phase_elapsed < moment - 0.00001: _step(minf(0.05, moment - game.ending.phase_elapsed))
				await _capture("04_approach_%04.1f" % moment)
				if moment == 19.0:
					game.settings.set_motion_intensity(0.0)
					game.settings.set_screen_flashes_enabled(false)
					game.ending.advance(0.0, false, Vector2.ZERO)
					await _capture("04_reduced_motion_no_flash")
					game.settings.set_motion_intensity(1.0)
					game.settings.set_screen_flashes_enabled(true)
	for i in 80: _step(0.1)
	await _capture("07_final_record_ko")
	game.settings.set_language("en")
	_step(0.0)
	await _capture("08_final_record_en")
	game.ending.return_to_chart()
	await _capture("09_return_to_chart")
	var file := FileAccess.open(output + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	game.queue_free()
	paused = false
	await process_frame
	await process_frame
	if failures.is_empty(): print("LAST_OBSERVATION_REVIEW_PASS: " + output); quit(0)
	else: quit(1)

func _step(delta: float) -> void:
	game.ending.advance(delta, true, game.ending.film.size * Vector2(0.5, 0.465))

func _record_frame() -> void:
	_step(1.0 / 30.0)
	record_frames += 1
	if game.ending.phase == game.ending.Phase.RECORD and game.ending.phase_elapsed >= 18.0:
		print("LAST_OBSERVATION_MOVIE_PASS: %d frames" % record_frames)
		quit(0)

func _capture(label: String) -> void:
	# Headless DisplayServer cannot report a hidden cursor; verify this here.
	game.ending._process(0.0)
	if game.ending.active:
		var cinematic: bool = game.ending.phase >= game.ending.Phase.COLLAPSE and game.ending.phase < game.ending.Phase.RECORD
		var expected := Input.MOUSE_MODE_HIDDEN if cinematic and not game.hud.is_settings_open() else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != expected: failures.append(label + " cursor mode"); push_error(label + " cursor mode")
	_step(0.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output + "/" + label + ".png"
	if picture.save_png(path) != OK: failures.append(path); push_error("Capture failed: " + path)
	var view: Dictionary = game.ending.visual_state()
	manifest.append({"name": label, "phase": game.ending.phase, "time": game.ending.elapsed, "camera_zoom": view.camera_zoom, "camera_dive": view.camera_dive, "camera_rush": view.camera_rush, "camera_crossing": view.camera_crossing, "disc_rotation": view.disc_rotation, "chart_stars": game.ending.lines.chart_points.size(), "dimensions": [picture.get_width(), picture.get_height()]})
