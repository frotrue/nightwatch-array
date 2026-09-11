extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const STEP := 1.0 / 60.0
const SAMPLES := [1, 17, 67]
const TICKS := 120
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.gui_disable_input = true
	var rendered := DisplayServer.get_name() != "headless"
	print("DENSE_INPUT_ENV ", JSON.stringify({"cpu_only":not rendered,"renderer":RenderingServer.get_current_rendering_method(),"synthetic":true,"research":"all base and extension flags; five equipped modules","excludes":["natural spawning", "completion effects", "audio", "human input"]}))
	for count in [4, 22]:
		for samples in SAMPLES:
			var game = load("res://scenes/main.tscn").instantiate()
			Fixtures.configure_before_ready(game)
			root.add_child(game)
			game.set_physics_process(false)
			game.set_process(false)
			game.observer.set_process_input(false)
			game.spawner.running = false
			game.events.running = false
			for node in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[node.id] = true
			for id in game.deep_sky.Data.RESEARCH: game.deep_sky.state.research_ids.append(id)
			var modules = game.deep_sky.modules
			modules.unlocked_slots = 5
			var loadout := ["linear_observation", "capture_hold", "wide", "overcharge", "wide_correlation"]
			for i in 5:
				modules.grant(loadout[i])
				modules.equip(loadout[i], i)
			game.observation_phase_duration = 120.0
			game.observation_phase_remaining = 120.0
			# All modifiers execute, but target completion/feedback cannot vary the workload.
			for i in count:
				var target = game.spawner.spawn_meteor("common", Vector2(380 + (i % 6) * 50, 240 + (i / 6) * 20), Vector2(1, 0), 1000.0)
				target.required_track_time = 1000000.0
				target.base_automatic_rate = 0.0
			game.observer.tick_input.reset(Vector2(520, 270))
			game.observer.input_time = 0.0
			game.observer.tick_input.push(0.0, Vector2(520, 270), true)
			var durations: Array[float] = []
			var frames: Array[float] = []
			var last_frame := Time.get_ticks_usec()
			for tick in TICKS:
				for sample in samples:
					var at: float = (tick + float(sample + 1) / samples) * STEP
					game.observer.tick_input.push(at, Vector2(520 + sin(at * 8.0) * 80, 270 + cos(at * 5.0) * 10), true)
				var started := Time.get_ticks_usec()
				game.simulate_tick()
				durations.append((Time.get_ticks_usec() - started) / 1000.0)
				if rendered:
					await process_frame
					var now := Time.get_ticks_usec()
					frames.append((now - last_frame) / 1000.0)
					last_frame = now
			var progress := 0.0
			for target in game.meteor_layer.get_children(): progress += target.manual_tracking_time
			durations.sort()
			frames.sort()
			if not is_equal_approx(progress, count * TICKS * STEP): failures.append("Raw input lost or duplicated held contact time")
			if game.meteor_layer.get_child_count() != count: failures.append("Workload changed")
			if rendered and Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) <= 0: failures.append("No real draw calls")
			print("DENSE_INPUT_RESULT ", JSON.stringify({"targets":count,"samples_per_tick":samples,"ticks":TICKS,"p95_ms":durations[113],"mean_ms":durations.reduce(func(a,b):return a+b,0.0)/TICKS,"manual_seconds":progress,"frame_p95_ms":frames[113] if rendered else null,"frame_mean_ms":frames.reduce(func(a,b):return a+b,0.0)/TICKS if rendered else null}))
			game.free()
			await process_frame
	for failure in failures: push_error(failure)
	print("DENSE_INPUT_PERF_PASS" if failures.is_empty() else "DENSE_INPUT_PERF_FAIL")
	quit(0 if failures.is_empty() else 1)
