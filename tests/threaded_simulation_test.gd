extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const ReferenceSelection = preload("res://tests/support/reference_observation_selection.gd")
const STEP := 1.0 / 60.0
const TYPES := ["common", "fast", "fragment", "fireball", "comet", "variable_star", "binary_star", "galaxy"]
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func make_game(mode: int, count: int):
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	if mode == 0: Fixtures.replace_child(game, "ObservationController", ReferenceSelection.new())
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.observer.set_process_input(false)
	game.spawner.running = false
	game.events.running = false
	game.spawner.spawn_policy.reseed(271828)
	game.spawner.rng.seed = 35
	game.spawner.forecast_rng.seed = 36
	game.spawner.echo_rng.seed = 37
	game.spawner.module_rng.seed = 38
	game.events.rng.seed = 39
	game.survey.rng.seed = 40
	game.parallel_motion_enabled = mode != 0
	game.observer.parallel_contacts_enabled = mode != 0
	game.observer.simulation_workers.worker_limit = 0 if mode == 1 else 100 # cap must clamp this
	for node in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[node.id] = true
	for id in game.deep_sky.Data.RESEARCH: game.deep_sky.state.research_ids.append(id)
	var modules = game.deep_sky.modules
	modules.unlocked_slots = 5
	for id in ["linear_observation", "capture_hold", "wide", "overcharge", "wide_correlation"]:
		modules.grant_copy(id)
		modules.equip(id)
	game.observation_phase_duration = 1000.0
	game.observation_phase_remaining = 1000.0
	for index in count:
		var kind: String = TYPES[index % TYPES.size()]
		var target = game.spawner.MeteorScript.new()
		var columns := 40 if count > 128 else 16
		var rows := ceili(float(count) / columns)
		var position := Vector2(70 + (index % columns) * (1000.0 / (columns - 1)), 100 + (index / columns) * (430.0 / maxf(rows - 1, 1)))
		var spec: Dictionary = game.Balance.meteor_spec(kind)
		target.configure(spec, kind, position, Vector2(25, 6), 100.0 / float(spec.lifetime), game.spawner._current_features(kind), position + Vector2(200, 25), game.observation_view)
		target.simulation_id = game.allocate_simulation_id()
		game.meteor_layer.add_child(target)
		game._on_meteor_spawned(target)
		target.required_track_time = 1000000.0
		target.base_automatic_rate = 0.0
	game.observer.tick_input.reset(Vector2(520, 270))
	game.observer.input_time = 0.0
	game.observer.tick_input.push(0.0, Vector2(520, 270), true)
	return game

func step_game(game, tick: int, samples: int = 17, held: bool = true) -> void:
	for sample in samples:
		var at: float = (tick + float(sample + 1) / samples) * STEP
		game.observer.tick_input.push(at, Vector2(520 + sin(at * 12) * 330, 270 + cos(at * 9) * 120), held)
	game.simulate_tick()

func _run() -> void:
	var games := [make_game(0, 128), make_game(1, 128), make_game(2, 128)]
	var observed := 0.0
	for tick in 60:
		for game in games:
			if tick == 15: game.deep_sky.modules.slots[0] = ""
			if tick == 20: game.progression.purchased_nodes.erase("polar_survey")
			if tick == 25: game.progression.purchased_nodes["polar_survey"] = true
			if tick == 30: game.deep_sky.modules.slots[0] = "linear_observation"
			if tick == 35: game.simulation_clock.request_hitstop(0.05)
			if tick == 40: game.deep_sky.modules.burst_remaining = STEP * 3.0
			if tick == 45: game.deep_sky.state.research_ids.clear()
			step_game(game, tick, 67 if tick % 5 == 0 else 17, tick < 55)
		for game in games.slice(1):
			var reference_selection = games[0].observer.selected_meteor
			var actual_selection = game.observer.selected_meteor
			check((reference_selection == null) == (actual_selection == null), "selection presence differs")
			if reference_selection != null and actual_selection != null:
				check(reference_selection.simulation_id == actual_selection.simulation_id, "primary latch/tie order differs")
			check(is_equal_approx(game.observer.tracking_grace_remaining, games[0].observer.tracking_grace_remaining), "tracking grace differs")
			check(game.observer.tracked_meteors.map(func(target): return target.simulation_id) == games[0].observer.tracked_meteors.map(func(target): return target.simulation_id), "additional target order differs")
		for index in 128:
			var reference = games[0].meteor_layer.get_child(index)
			for game in games.slice(1):
				var actual = game.meteor_layer.get_child(index)
				check(actual.position.is_equal_approx(reference.position) and actual.velocity.is_equal_approx(reference.velocity), "parallel motion differs at tick %d target %d" % [tick, index])
				check(actual.trail_points == reference.trail_points, "parallel trail samples differ")
				for property in ["age", "manual_tracking_time", "quality_integral", "observation_progress", "manual_contribution", "interruption_count"]:
					check(is_equal_approx(float(actual.get(property)), float(reference.get(property))), "parallel %s differs at tick %d target %d" % [property, tick, index])
			observed += reference.manual_tracking_time
	check(observed > 0.0, "comparison exercised observation")
	var pool = games[2].observer.simulation_workers
	check(pool.worker_count() <= 3 and pool.worker_count() == mini(3, maxi(0, OS.get_processor_count() - 1)), "simulation respects main plus three workers")
	for worker in pool._workers:
		check(worker.execution_thread != 0 and worker.execution_thread != OS.get_thread_caller_id(), "work executed on a real background thread")
	check(games[1].observer.simulation_workers.worker_count() == 0, "single-thread fallback creates no workers")
	var before: int = games[2].simulation_clock.tick
	paused = true
	games[2].simulate_tick()
	check(games[2].simulation_clock.tick == before, "pause does not schedule another tick")
	paused = false
	for game in games: game.free()
	check(pool.worker_count() == 0, "scene exit joins all persistent workers")
	pool.shutdown() # idempotent close
	for failure in failures: print("THREAD_FAILURE ", failure)
	if failures.is_empty(): print("THREADED_SIMULATION_PASS: live/single-batch/threaded parity, caps, hitstop, equipment, pause and shutdown")
	quit(0 if failures.is_empty() else 1)
