extends "res://tests/stellar_test.gd"

func _run() -> void:
	await _test_remnant()
	_test_signal()
	await _test_cancel()
	if failures.is_empty(): print("NEUTRON_STAR_PASS: remnant unlock, deterministic formation, delay, shared capacity, pulse observation, retention, departure and cleanup")
	quit(0 if failures.is_empty() else 1)

func _unlock(game) -> void:
	game.progression.purchased_nodes["galactic_reference_frame"] = true
	game.deep_sky.state.research_ids.assign(["ext_protocol", "ext_sct_supernova"])

func _test_remnant() -> void:
	var game = _game()
	game.spawner.spawn_policy.reseed(41)
	game.spawner.phase_time_remaining = 50.0
	var source = game.spawner.spawn_meteor("stellar", Vector2(500, 300), Vector2(24, -8))
	game.spawner.prepare_stellar_remnant(source)
	check(not source.remnant_pending, "no remnant before the research unlock")
	_unlock(game)
	var before := JSON.stringify(game.spawner.get_simulation_save())
	var selected := 0
	var chosen_id := -1
	for id in range(1, 101):
		source.rng.seed = id
		game.spawner.prepare_stellar_remnant(source)
		if source.remnant_pending: selected += 1; chosen_id = id
	check(selected > 15 and selected < 55, "some, not all, stellar sources form remnants")
	check(JSON.stringify(game.spawner.get_simulation_save()) == before, "formation leaves saved RNG streams unchanged")
	source.rng.seed = chosen_id
	game.spawner.prepare_stellar_remnant(source)
	var saved_rng: Dictionary = game.spawner.spawn_policy.save_state()
	game.spawner.spawn_policy.reseed(999)
	game.spawner.spawn_policy.restore_state(saved_rng)
	source.remnant_pending = false
	game.spawner.prepare_stellar_remnant(source)
	check(source.remnant_pending, "restored RNG state retains formation even with a different initial seed")
	game.spawner.phase_time_remaining = 2.0
	source.remnant_pending = false
	game.spawner.prepare_stellar_remnant(source)
	check(not source.remnant_pending, "late completion leaves no unobservable remnant")
	game.spawner.phase_time_remaining = 50.0
	game.spawner.spawn_meteor("stellar", Vector2(800, 200), Vector2.RIGHT)
	game.spawner.spawn_meteor("stellar", Vector2(800, 400), Vector2.RIGHT)
	check(game.spawner.spawn_meteor("neutron_star", Vector2.ZERO, Vector2.RIGHT) == null, "neutron stars share three stellar slots")
	source.observation_progress = 1.0
	source.tick_resolve()
	check(source.remnant_pending, "real observed callback schedules the selected remnant")
	for tick in 54:
		source.tick_motion(1.0 / 60.0, tick)
		source.tick_resolve()
		if tick < 53: check(game.meteor_layer.get_children().all(func(body): return body.type_id != "neutron_star"), "remnant waits for the explosion to finish")
	var child = game.meteor_layer.get_children().filter(func(body): return body.type_id == "neutron_star")[0]
	check(child.global_position == source.global_position and child.initial_velocity.normalized().is_equal_approx(source.initial_velocity.normalized()), "remnant inherits completion position and direction")
	check(child.get_progress() == 0.0 and child.can_be_tracked(), "remnant is a new unobserved target")
	check(source.is_queued_for_deletion() and not source.visible, "parent frees its slot on the remnant birth tick")
	child.complete_from_supernova()
	check(child.alive, "other supernovae cannot complete neutron stars")
	await process_frame
	check(game.meteor_layer.get_child_count() == 3, "replacement respects the shared cap after deletion")
	game.free()

func _test_signal() -> void:
	var game = _game()
	var body = game.spawner.spawn_meteor("neutron_star", Vector2(500, 300), Vector2(24, -8))
	body.wobble_phase = 0.0
	body.age = 0.0
	body.apply_manual_observation(0.1, 0.0, 50.0)
	var dim: float = body.observation_progress
	body.observation_progress = 0.0
	body.age = body.ROTATION_PERIOD / 4.0
	body.apply_manual_observation(0.1, 0.0, 50.0)
	check(body.observation_progress > dim * 4.0, "beam alignment changes actual manual work")
	body.observation_progress = 0.4
	body.simulation_tick = 100
	body.tick_observation(1.0)
	check(is_equal_approx(body.observation_progress, 0.4), "missed signal never decays accumulated observation")
	body.base_automatic_rate = 1.0
	body.age = 0.0
	body.tick_observation(0.1)
	var automatic_dim: float = body.observation_progress - 0.4
	body.observation_progress = 0.4
	body.age = body.ROTATION_PERIOD / 4.0
	body.tick_observation(0.1)
	check(body.observation_progress - 0.4 > automatic_dim * 4.0, "automatic observation uses the same pulse windows")
	var held_age: float = body.age
	paused = true
	game.simulate_tick()
	check(body.age == held_age, "pause freezes the pulse clock")
	paused = false
	game.effects.motion_intensity = 0.0
	game.effects.screen_flashes_enabled = false
	body.observation_progress = 1.0
	body.tick_resolve()
	var paid: float = game.progression.observation_data
	var position: Vector2 = body.position
	body.tick_motion(0.5, 101)
	check(body.position != position and not body.can_be_tracked(), "completed neutron star travels away without remaining trackable")
	body._finish_observation(1.0)
	check(game.progression.observation_data == paid, "repeat completion cannot repay")
	body.tick_motion(3.0, 102)
	check(body.is_queued_for_deletion() and not body.visible, "departure removes the remnant without another explosion")
	game.free()

func _test_cancel() -> void:
	for action in ["load", "round"]:
		var game = _game()
		_unlock(game)
		var source = game.spawner.spawn_meteor("stellar", Vector2(500, 300), Vector2.RIGHT)
		source.observation_progress = 1.0
		source.tick_resolve()
		source.remnant_pending = true
		if action == "load": game._apply_save_data(game._build_save_data())
		else: game._end_observation_phase()
		await process_frame
		check(game.meteor_layer.get_child_count() == 0, "cleanup cancels the pending remnant: " + action)
		game.free()
