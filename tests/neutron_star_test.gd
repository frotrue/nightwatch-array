extends "res://tests/stellar_test.gd"

func _run() -> void:
	await _test_remnant()
	_test_signal()
	_test_beam_geometry()
	await _test_beam_lifecycle()
	await _test_cancel()
	if failures.is_empty(): print("NEUTRON_STAR_PASS: remnant formation, pulse observation, beam geometry, automatic completion, expiry, worker parity and cleanup")
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

func _stationary(game, kind: String, at: Vector2):
	var body = game.spawner.spawn_meteor(kind, at, Vector2.RIGHT, 30.0)
	check(body != null, "beam fixture admits " + kind)
	if body == null: return null
	body.initial_velocity = Vector2.ZERO
	body.velocity = Vector2.ZERO
	body.burnout_position = at
	return body

func _test_beam_geometry() -> void:
	var game = _game()
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var origin: Vector2 = game.observation_view.screen_to_world(Vector2(560, 330))
	var direction := Vector2(0.82, 0.48).normalized()
	var source = _stationary(game, "neutron_star", origin)
	source.age = 0.0
	source.wobble_phase = 0.0
	var forward = _stationary(game, "common", origin + direction * 50.0 * unit)
	var backward = _stationary(game, "fast", origin - direction * 50.0 * unit)
	var side = _stationary(game, "common", origin + direction.orthogonal() * 100.0 * unit)
	var distant = _stationary(game, "common", origin + direction * 300.0 * unit)
	var excluded: Array = []
	for kind in ["stellar", "black_hole", "white_hole", "neutron_star"]:
		excluded.append(_stationary(game, kind, forward.position))
	var bounds: Rect2 = game.observation_view.atmospheric_rect()
	var targets: Array = game.meteor_layer.get_children()
	source.illuminate_targets(targets, bounds)
	check(forward.pulsar_assist_rate == 0.0, "unobserved pulsar cannot illuminate targets")
	source.observation_progress = 1.0
	source.tick_resolve()
	source.illuminate_targets(targets, bounds)
	check(forward.pulsar_assist_rate > 0.0 and backward.pulsar_assist_rate > 0.0, "both magnetic poles provide work")
	check(side.pulsar_assist_rate == 0.0 and distant.pulsar_assist_rate == 0.0, "side and out-of-range targets receive no work")
	for body in excluded: check(body.pulsar_assist_rate == 0.0, "special celestial excluded: " + body.type_id)
	forward.tick_observation(0.01)
	check(forward.observation_progress > 0.0 and forward.observation_progress < 1.0, "beam accumulates work instead of instant completion")
	forward.pulsar_assist_rate = 0.0
	source.age = source.ROTATION_PERIOD / 4.0
	source.illuminate_targets([forward], bounds)
	check(forward.pulsar_assist_rate == 0.0, "rotating away stops illumination")
	source.age = 0.0
	source.illuminate_targets([forward], Rect2(origin - Vector2.ONE, Vector2.ONE * 2.0))
	check(forward.pulsar_assist_rate == 0.0, "off-screen target cannot receive work")
	source.linger_time = 0.0
	source.illuminate_targets([forward], bounds)
	check(forward.pulsar_assist_rate == 0.0, "expired release cannot leave active beams")
	# At a wider view, the actual surface is smaller than a screen-compensated budget.
	game.observation_view.observation_span = 1.5
	source.linger_time = 3.0
	var visual_scale: float = game.observation_view.meteor_visual_scale()
	source._draw_type_silhouette(12.0, 1.0, visual_scale)
	var beam_length: float = source.surface.emission.material.get_shader_parameter("beam_length")
	var axis: Vector3 = source.surface.emission.material.get_shader_parameter("magnetic_axis")
	var tip: Vector2 = source.surface.to_global(Vector2(axis.x, axis.y) * beam_length)
	forward.position = tip + direction * forward.body_radius * visual_scale * 2.0
	source.illuminate_targets([forward], game.observation_view.atmospheric_rect())
	check(forward.pulsar_assist_rate == 0.0, "camera pullback cannot extend contact beyond the rendered pole")
	source.age = 0.37
	source.completion_motion_scale = 0.4
	source._draw_type_silhouette(12.0, 1.0, visual_scale)
	axis = source.surface.emission.material.get_shader_parameter("magnetic_axis")
	forward.position = source.surface.to_global(Vector2(axis.x, axis.y) * 70.0)
	source.illuminate_targets([forward], game.observation_view.atmospheric_rect())
	check(forward.pulsar_assist_rate > 0.0, "dimmed moving beam stays aligned with actual contact")
	game.free()

func _test_beam_lifecycle() -> void:
	var results: Array = []
	for parallel in [false, true]:
		var game = _game()
		game.parallel_motion_enabled = parallel
		game.observation_phase_remaining = 30.0
		var unit: float = game.observation_view.screen_length_to_world(1.0)
		var origin: Vector2 = game.observation_view.screen_to_world(Vector2(560, 330))
		var source = _stationary(game, "neutron_star", origin)
		source.wobble_phase = 0.0
		source.age = 0.0
		source.completion_motion_scale = 0.0
		source.completion_glint_enabled = false
		source.observation_progress = 1.0
		source.tick_resolve()
		var targets: Array = []
		for kind in ["common", "variable_star", "binary_star", "galaxy"]:
			var target = _stationary(game, kind, origin + Vector2(30, 28) * unit)
			targets.append(target)
		# Exercise production worker motion above its threshold without affecting the beam.
		for i in game.PARALLEL_MOTION_THRESHOLD:
			var filler = Meteor.new()
			var at := origin + Vector2(450, 200) * unit
			filler.configure(Balance.meteor_spec("common"), "common", at, Vector2.ZERO, 20.0, {}, at, game.observation_view)
			filler.simulation_id = game.allocate_simulation_id()
			game.meteor_layer.add_child(filler)
			game._on_meteor_spawned(filler)
		var before: int = game.progression.success_count
		var trace: Array = []
		for tick in 180:
			game.simulate_tick()
			trace.append(targets.map(func(body): return body.observation_progress))
		for target in targets:
			check(target.observed_successfully and target.get_automatic_contribution() > 0.99, "beam completes real target through automatic lane: " + target.type_id)
		check(game.progression.success_count == before + targets.size(), "beam targets pay exactly once")
		results.append({"trace": trace, "data": game.progression.observation_data})
		var survivor = game.meteor_layer.get_child(game.meteor_layer.get_child_count() - 1)
		survivor.position = origin + Vector2(30, 28) * unit
		survivor.entry_position = survivor.position
		survivor.burnout_position = survivor.position
		survivor.pulsar_assist_rate = 4.0
		game.simulate_tick()
		check(survivor.pulsar_assist_rate == 0.0 and survivor.get_progress() == 0.0, "game clears stale assistance after the source departs")
		await process_frame
		game.free()
	check(results[0] == results[1], "serial and worker beam histories and rewards agree")
