extends "res://tests/late_game_render_performance_probe.gd"

# Capacity-bypassing stress, not a legal endgame build or spawn-rate benchmark.
# Real 60 Hz motion/contact and normal frame rendering, unlike frozen geometry.
# Common/fast only; completion/expiry, natural events and survey summons excluded.
# Injected completion visuals keep effects active without altering target counts.
class TimedGame:
	extends "res://scripts/game.gd"
	var tick_us := 0
	var motion_us := 0
	var measured_ticks := 0
	func simulate_tick() -> void:
		var start := Time.get_ticks_usec()
		super.simulate_tick()
		tick_us += Time.get_ticks_usec() - start
		measured_ticks += 1
	func _tick_target_motion(targets: Array, delta: float) -> void:
		var start := Time.get_ticks_usec()
		super._tick_target_motion(targets, delta)
		motion_us += Time.get_ticks_usec() - start

class TimedObserver:
	extends Observer
	var observation_us := 0
	func simulate_tick(delta: float) -> void:
		var start := Time.get_ticks_usec()
		super.simulate_tick(delta)
		observation_us += Time.get_ticks_usec() - start

class TimedMeteor:
	extends "res://scripts/meteor.gd"
	var draw_us := 0
	func _draw() -> void:
		var start := Time.get_ticks_usec()
		super._draw()
		draw_us += Time.get_ticks_usec() - start

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dense rendering requires a real renderer")
		quit(1)
		return
	create_timer(90.0).timeout.connect(func(): push_error("Dense rendering timeout"); quit(1))
	root.gui_disable_input = true
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for count in [128, 1000]:
		seed(20260912)
		var game = load("res://scenes/main.tscn").instantiate()
		game.set_script(TimedGame)
		Fixtures.configure_before_ready(game)
		var observer := TimedObserver.new()
		observer.z_index = 50
		Fixtures.replace_child(game, "ObservationController", observer)
		root.add_child(game)
		print("DENSE_RENDER_SOURCES ", JSON.stringify({"hud":game.hud.get_script().source_code.sha256_text(),"effects":game.effects.get_script().source_code.sha256_text()}))
		observer.set_process_input(false)
		for definition in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[definition.id] = true
		game.deep_sky.modules.unlocked_slots = 5
		for id in ["wide", "capture_hold", "overcharge"]:
			game.deep_sky.modules.grant_copy(id)
			game.deep_sky.modules.equip(id)
		game._sync_galactic_systems()
		game.spawner.reset()
		game.events.reset()
		game.survey.end_round()
		game.deep_sky.director.remaining = 1000000.0
		for target in game.meteor_layer.get_children(): target.free()
		game.observation_phase_duration = 1000.0
		game.observation_phase_remaining = 1000.0
		game.effects.reset()
		game.effects.rng.seed = 778899
		var originals: Array = []
		var columns := 40 if count == 1000 else 16
		var rows := ceili(float(count) / columns)
		for index in count:
			var kind := "common" if index % 2 == 0 else "fast"
			var start := Vector2(80 + (index % columns) * (970.0 / (columns - 1)), 100 + (index / columns) * (420.0 / maxf(rows - 1, 1)))
			var target := TimedMeteor.new()
			var spec: Dictionary = game.Balance.meteor_spec(kind)
			target.configure(spec, kind, start, Vector2(2, 0.5), 1000.0 / float(spec.lifetime), game.spawner._current_features(kind), start + Vector2(200, 25), game.observation_view)
			target.simulation_id = game.allocate_simulation_id()
			game.meteor_layer.add_child(target)
			game._on_meteor_spawned(target)
			target.required_track_time = 1000000.0
			target.base_automatic_rate = 0.0
			target.split_done = true
			originals.append(target)
		var driver := Driver.new()
		driver.observer = observer
		driver.process_physics_priority = -100
		root.add_child(driver)
		print("DENSE_RENDER_ENV ", JSON.stringify({"count":count,"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(root.size),"warmup":2,"sample":6,"raw_samples_per_tick":17,"effects":"one injected success per 0.05 wall seconds","kinds":["common","fast"]}))
		var frames: Array[float] = []
		var started := Time.get_ticks_usec()
		var last := started
		var first_tick := -1
		var next_effect := 0.0
		var min_count: int = count
		var max_count: int = count
		var max_particles := 0
		while (Time.get_ticks_usec() - started) / 1000000.0 < 8.0:
			await process_frame
			var now := Time.get_ticks_usec()
			var elapsed := (now - started) / 1000000.0
			if elapsed >= next_effect:
				game.effects.spawn_success(Vector2(576, 300), 10, Color.WHITE, 1.0, 0.7, "GOOD", game.hud.get_data_anchor(), 0, false)
				next_effect = elapsed + 0.05
			if elapsed > 2.0:
				if first_tick < 0:
					first_tick = game.simulation_clock.tick
					game.tick_us = 0
					game.motion_us = 0
					game.measured_ticks = 0
					observer.observation_us = 0
					for target in originals: target.draw_us = 0
				else: frames.append((now - last) / 1000.0)
				min_count = mini(min_count, game.meteor_layer.get_child_count())
				max_count = maxi(max_count, game.meteor_layer.get_child_count())
				max_particles = maxi(max_particles, game.effects.particles.size())
			last = now
		var observed := 0
		var draw_us := 0
		for target in originals:
			observed += int(target.manual_tracking_time > 0.0)
			draw_us += target.draw_us
		if frames.is_empty() or min_count != count or max_count != count or observed == 0 or max_particles == 0 or Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) == 0:
			failures.append("Incomplete dense rendering workload at %d targets" % count)
		if frames.is_empty():
			driver.free()
			game.free()
			continue
		var seconds: float = frames.reduce(func(a,b): return a + b, 0.0) / 1000.0
		frames.sort()
		print("DENSE_RENDER_RESULT ", JSON.stringify({"count":count,"frames":frames.size(),"fps":frames.size()/seconds,"p95_ms":frames[floori((frames.size()-1)*0.95)] if frames.size() >= 100 else null,"p99_ms":frames[floori((frames.size()-1)*0.99)] if frames.size() >= 100 else null,"ticks_per_second":(game.simulation_clock.tick-first_tick)/seconds,"tick_cpu_ms":game.tick_us/maxf(1.0,game.measured_ticks)/1000.0,"motion_cpu_ms":game.motion_us/maxf(1.0,game.measured_ticks)/1000.0,"observer_cpu_ms":observer.observation_us/maxf(1.0,game.measured_ticks)/1000.0,"meteor_draw_cpu_ms_per_frame":draw_us/maxf(1.0,frames.size())/1000.0,"observed_targets":observed,"min_count":min_count,"max_count":max_count,"peak_particles":max_particles}))
		driver.free()
		game.free()
		await process_frame
	for failure in failures: push_error(failure)
	print("DENSE_RENDER_PASS" if failures.is_empty() else "DENSE_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)
