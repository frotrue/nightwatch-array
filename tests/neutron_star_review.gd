extends "res://tests/deep_sky_preview.gd"

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	create_timer(120.0, true, false, true).timeout.connect(func(): push_error("Neutron review timeout"); quit(1))
	root.size = Vector2i(1152, 648)
	root.gui_disable_input = true
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.settings.set_language("ko", false)
	game.spawner.reset()
	game.events.running = false
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	game.progression.purchased_nodes["galactic_reference_frame"] = true
	game.deep_sky.state.research_ids.assign(["ext_protocol", "ext_sct_supernova"])
	game.spawner.spawn_policy.reseed(41)
	game.observation_phase_remaining = 40.0
	_freeze(game)
	game.hud.hide()
	game.observer.native_cursor_visible = false
	for tween in get_processed_tweens(): tween.kill()
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var origin: Vector2 = game.observation_view.screen_to_world(Vector2(480, 320))
	var star = game.spawner.spawn_meteor("stellar", origin, Vector2(18, -4) * unit)
	game.spawner.phase_time_remaining = 40.0
	# Select a production formation roll for a reproducible positive example.
	for id in range(1, 100):
		star.rng.seed = id
		game.spawner.prepare_stellar_remnant(star)
		if star.remnant_pending: break
	star.remnant_pending = false
	star.age = 2.0
	game.observer.tick_input.reset(origin)
	game.observer.input_time = 0.0
	game.observer.set_process_input(false)
	var caption_layer := CanvasLayer.new()
	game.add_child(caption_layer)
	var caption := Label.new()
	caption.position = Vector2(120, 100)
	caption.size = Vector2(912, 40)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 22)
	caption_layer.add_child(caption)
	output = "res://build/neutron_star/" + RenderingServer.get_current_rendering_method()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var remnant: Node2D
	var stats := {"supernova_tick": -1, "birth_tick": -1, "completed_tick": -1}
	var departure_luma: Array[float] = []
	for tick in 960:
		var target = star if is_instance_valid(star) and star.alive else remnant
		var held: bool = tick >= 60 and is_instance_valid(target) and target.alive
		var cursor: Vector2 = target.position + target.velocity / 60.0 if held else origin
		game.observer.tick_input.push(game.observer.input_time + 1.0 / 60.0, cursor, held)
		game.simulate_tick()
		game.effects._process(1.0 / 60.0)
		if is_instance_valid(star) and star.observed_successfully and stats.supernova_tick < 0:
			stats.supernova_tick = tick
		if not is_instance_valid(remnant):
			for body in game.meteor_layer.get_children():
				if body.type_id == "neutron_star": remnant = body; stats.birth_tick = tick
		if is_instance_valid(remnant) and remnant.observed_successfully and stats.completed_tick < 0:
			stats.completed_tick = tick
		caption.text = "항성 관측" if stats.supernova_tick < 0 else ("초신성 · 가스와 잔해 확산" if stats.birth_tick < 0 else ("중성자별 · 회전 신호를 모아 관측" if stats.completed_tick < 0 else "주기 관측 완료 · 이동하며 퇴장"))
		if tick % 2 == 1:
			for body in game.meteor_layer.get_children():
				body.previous_simulation_position = body.position
				body.reset_physics_interpolation()
				body.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.save_png(output.path_join("frame_%03d.png" % (tick / 2)))
			if is_instance_valid(remnant) and stats.completed_tick >= 0 and tick - stats.completed_tick in [132, 174]:
				var centre: Vector2i = Vector2i(game.observation_view.world_to_screen(remnant.global_position))
				departure_luma.append(frame.get_pixelv(centre).get_luminance())
	if stats.birth_tick - stats.supernova_tick != 54: failures.append("remnant did not follow the complete 0.9-second explosion")
	if stats.completed_tick <= stats.birth_tick + 60: failures.append("remnant did not accumulate multiple signal windows")
	if is_instance_valid(remnant): failures.append("completed remnant did not depart")
	if departure_luma.size() != 2 or departure_luma[1] >= departure_luma[0] * 0.5:
		failures.append("completed remnant did not visibly fade before removal")
	var manifest := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "stats": stats, "departure_luma": departure_luma, "frames": 480, "fps": 30, "failures": failures}, "\t"))
	game.free()
	paused = false
	if failures.is_empty(): print("NEUTRON_STAR_REVIEW_PASS: real manual observation, supernova, delayed birth, pulse tracking and departure")
	else: push_error(str(failures))
	quit(0 if failures.is_empty() else 1)
