extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Bindings = preload("res://scripts/game_input_bindings.gd")
const Policy = preload("res://scripts/spawn_policy.gd")
const Balance = preload("res://scripts/game_balance.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("WHITE_HOLE: " + message)

func _key(game: Node, code: int, modifiers: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = modifiers
	event.shift_pressed = modifiers
	event.echo = echo
	game.input_router._unhandled_key_input(event)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	var layer = game.debug_celestials
	check(layer.get_child_count() == 0, "normal startup has no white holes")
	var save_before := JSON.stringify(game._build_save_data())
	var meteor_count: int = game.meteor_layer.get_child_count()
	_key(game, KEY_W, false)
	_key(game, KEY_W, true, true)
	check(layer.get_child_count() == 0, "plain W and key repeat cannot summon previews")
	_key(game, KEY_W)
	check(game.meteor_layer.get_child_count() == meteor_count + 1, "reserved debug chord creates an observable target")
	var playable = game.meteor_layer.get_child(game.meteor_layer.get_child_count() - 1)
	check(playable.type_id == "white_hole" and playable.can_be_tracked(), "debug target uses the normal observation pipeline")
	check(playable.position.is_equal_approx(game.get_global_mouse_position()), "observable debug spawn uses the cursor")
	playable.free()
	layer.spawn_white_hole(game.get_global_mouse_position(), 1.0)
	var first = layer.get_child(0)
	check(first.position.is_equal_approx(game.get_global_mouse_position()), "debug spawn uses the world-space cursor")
	var second = layer.spawn_white_hole(Vector2(500, 300), 2.0)
	var third = layer.spawn_white_hole(Vector2(700, 300), 1.0)
	check(second.scale.is_equal_approx(Vector2(2, 2)), "preview size accepts pulled-back camera units")
	check(first.emission.material != second.emission.material, "separate preview instances own their shader state")
	check(layer.spawn_white_hole(Vector2.ZERO, 1.0) == null, "debug previews are bounded at three")
	check(game.meteor_layer.get_child_count() == meteor_count, "previews never enter meteor admission or observation")
	_key(game, KEY_E)
	check(first.effect_mode == 1 and second.effect_mode == 1 and third.effect_mode == 1, "effect comparison updates all live previews")
	check(JSON.stringify(game._build_save_data()) == save_before, "spawning and switching effects leave the saved run and RNG unchanged")
	check(Bindings._reserved_key_reason(KEY_W, {"ctrl": true, "shift": true}) == "reserved_debug_input", "W chord cannot be rebound as gameplay")
	check(Bindings._reserved_key_reason(KEY_E, {"ctrl": true, "shift": true}) == "reserved_debug_input", "E chord cannot be rebound as gameplay")
	var before_age: float = first.age
	paused = true
	game.simulate_tick()
	check(first.age == before_age, "paused simulation does not age debug effects")
	_key(game, KEY_E)
	check(first.effect_mode == 0, "comparison chord works while chart simulation is paused")
	paused = false
	game.settings.set_motion_intensity(0.0, false)
	game.settings.set_screen_flashes_enabled(false, false)
	var before_visual: float = first.visual_time
	game.simulate_tick()
	check(first.age > before_age and first.visual_time == before_visual, "reduced motion freezes animation without freezing lifetime")
	check(first.emission.material.get_shader_parameter("motion") == 0.0 and first.emission.material.get_shader_parameter("pulses") == 0.0, "accessibility changes propagate to active shader instances")
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "reduced motion disables the sky copy")
	game.settings.set_motion_intensity(1.0, false)
	first.position = Vector2(576, 324)
	first.present()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "visible active preview lenses the sky")
	check(first.lensed_sky.z_index < game.meteor_layer.z_index and not first.lensed_sky.z_as_relative, "optical layer precedes real observation targets")
	check(first.lensed_sky.material != second.lensed_sky.material, "sky lenses have independent material state")
	first.hide()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "hidden previews do not copy the screen")
	first.show()
	first.position = Vector2(-10000, -10000)
	first.present()
	check(first.background_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "offscreen previews do not copy the screen")
	first.advance(first.LIFETIME)
	check(first.is_queued_for_deletion() and not first.visible, "expiry hides and releases a preview")
	check(layer.spawn_white_hole(Vector2.ZERO, 1.0) != null, "expired preview frees a slot before deferred deletion")
	game._apply_save_data(game._build_save_data())
	check(layer.get_child_count() == 0, "loading clears visual previews")
	layer.spawn_white_hole(Vector2.ZERO, 1.0)
	game.reset_run()
	check(layer.get_child_count() == 0, "run reset clears previews")
	layer.spawn_white_hole(Vector2.ZERO, 1.0)
	game._end_observation_phase()
	check(layer.get_child_count() == 0, "round end clears previews")
	game.free()
	paused = false
	await process_frame
	for manual in [false, true]:
		for motion in [0.0, 1.0]: _test_observable_release(manual, motion)
	_test_capacity_and_cleanup()
	_test_worker_parity()
	await _test_research_and_natural_arrivals()
	_test_researched_ejecta()
	if failures.is_empty(): print("WHITE_HOLE_PASS: Phoenix research, natural arrivals, save/RNG compatibility, upgraded ejecta, debug routing, pause and cleanup")
	quit(0 if failures.is_empty() else 1)

func _game():
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	return game

func _ejecta(game) -> Array:
	return game.meteor_layer.get_children().filter(func(body): return body.get_meta("white_hole_ejecta", false))

func _test_observable_release(manual: bool, motion: float) -> void:
	var game = _game()
	game.effects.motion_intensity = motion
	game.effects.screen_flashes_enabled = false
	var natural_rng := JSON.stringify(game.spawner.spawn_policy.save_state())
	var source = game.spawner.spawn_meteor("white_hole", Vector2(576, 300), Vector2(20, -4))
	check(game.spawner.spawn_policy.probability("white_hole", game.progression) == 0.0, "debug target does not unlock natural white holes")
	var start: Vector2 = source.position
	source.tick_motion(0.5, 1)
	check(source.position.is_equal_approx(start + Vector2(10, -2)), "spawn heading produces straight constant-speed travel")
	if manual:
		for tick in 240:
			source.simulation_tick += 1
			source.apply_manual_observation(1.0 / 60.0, 0.0, 80.0)
			source.tick_resolve()
			if not source.alive: break
	else:
		source.dish_assist_rate = 2.0
		for tick in 60:
			source.tick_observation(1.0 / 60.0)
			source.tick_resolve()
			if not source.alive: break
	check(source.observed_successfully and not source.can_be_tracked(), "manual/dish observation completes and releases the target")
	check(_ejecta(game).is_empty(), "completion prepares a beam before the first wave")
	var data_after_source: float = game.progression.observation_data
	source._finish_observation(1.0)
	check(game.progression.observation_data == data_after_source, "repeat completion cannot repay the source")
	var held_time: float = source.visual_time
	paused = true
	game.simulate_tick()
	check(source.visual_time == held_time and _ejecta(game).is_empty(), "pause freezes completion and ejection")
	paused = false
	for tick in 72:
		source.tick_motion(1.0 / 60.0, tick + 2)
		source.tick_resolve()
		if tick == 10: check(_ejecta(game).size() == 4, "first wave releases four instead of the whole burst")
	var children := _ejecta(game)
	check(children.size() == 24 and source.emitted_count == 24, "one completion emits exactly 24 bodies in six waves")
	check(game.progression.observation_data == data_after_source, "emission itself grants no meteor rewards")
	var kinds := {}
	var sides := [0, 0]
	for body in children:
		kinds[body.type_id] = true
		sides[0 if body.initial_velocity.dot(source.release_axis) > 0.0 else 1] += 1
		check(body.alive and body.can_be_tracked() and body.get_progress() == 0.0, "ejecta start as unobserved normal targets")
		check(body.type_id not in ["white_hole", "stellar", "black_hole", "major"], "burst cannot recursively create celestial sources")
	check(kinds.size() == 5 and sides == [12, 12], "five meteor kinds are distributed across both poles")
	check(JSON.stringify(game.spawner.spawn_policy.save_state()) == natural_rng, "debug release preserves natural RNG streams")
	children[0].observation_progress = 1.0
	children[0].tick_resolve()
	check(game.progression.observation_data > data_after_source, "released meteors pay only through ordinary observation")
	source.tick_motion(0.25, 100)
	check(source.is_queued_for_deletion(), "source vanishes when the beam finishes")
	game.free()

func _test_capacity_and_cleanup() -> void:
	var game = _game()
	var source = game.debug_celestials.spawn_observable_white_hole(Vector2(576, 300), 1.0)
	game.debug_celestials.spawn_observable_white_hole(Vector2(450, 250), 1.0)
	game.debug_celestials.spawn_observable_white_hole(Vector2(650, 250), 1.0)
	check(game.debug_celestials.spawn_observable_white_hole(Vector2.ZERO, 1.0) == null, "observable white holes retain a three-body cap")
	for index in Policy.ATMOSPHERIC_SAFETY_SLOTS: game.spawner.spawn_meteor("common", Vector2(30, 100), Vector2.RIGHT)
	source.observation_progress = 1.0
	source.tick_resolve()
	source.tick_motion(1.1, 1)
	source.tick_resolve()
	check(_ejecta(game).is_empty() and game.meteor_layer.get_child_count() == Policy.ATMOSPHERIC_SAFETY_SLOTS + 3, "reserved sources cannot overflow the atmospheric ejecta budget")
	game._end_observation_phase()
	check(not game.meteor_layer.get_children().any(func(body): return body.type_id == "white_hole"), "round end removes sources and cancels pending release")
	game._begin_observation_phase()
	source = game.debug_celestials.spawn_observable_white_hole(Vector2(576, 300), 1.0)
	source.tick_motion(16.0, 1)
	source.tick_resolve()
	check(not source.observed_successfully and _ejecta(game).is_empty(), "unobserved expiry never emits meteors")
	game._apply_save_data(game._build_save_data())
	check(not game.meteor_layer.get_children().any(func(body): return body.type_id == "white_hole"), "load clears ordinary in-flight white holes without replaying emission")
	game.free()

func _test_worker_parity() -> void:
	var game = _game()
	var serial = game.spawner.spawn_meteor("white_hole", Vector2(400, 300), Vector2(20, -5))
	var worker = game.spawner.spawn_meteor("white_hole", Vector2(400, 300), Vector2(20, -5))
	for tick in 30:
		serial.tick_motion(1.0 / 60.0, tick)
		var result = game.MeteorMotionBatch.calculate(0, 1, [worker.motion_snapshot(1.0 / 60.0)])[0]
		worker.apply_motion_result(result, 1.0 / 60.0, tick)
	check(serial.position.is_equal_approx(worker.position) and is_equal_approx(serial.visual_time, worker.visual_time), "worker and serial paths advance both trajectory and optical time identically")
	game.free()

func _test_research_and_natural_arrivals() -> void:
	var game = _game()
	var p = game.progression
	var policy := Policy.new(317)
	check(policy.probability("white_hole", p) == 0.0, "new save cannot spawn white holes")
	p.debug_purchase_all()
	game.upgrade_tree.open_tree()
	p.observation_data = 3000000000.0
	check(not game.deep_sky.can_purchase("ext_phe_white_hole"), "expansion alone does not unlock Phoenix")
	for id in ["ext_sge_cadence", "ext_sge_forecast", "ext_sge_solution", "ext_cnc_planet", "ext_cnc_tracking", "ext_sgr_black_hole"]:
		check(game.deep_sky.purchase(id), "normal precursor purchase: " + id)
	check(policy.probability("black_hole", p) > 0.0 and policy.probability("white_hole", p) == 0.0, "black holes precede white holes")
	check(not game.deep_sky.can_purchase("ext_phe_white_hole"), "black hole tracking and analysis separate the unlocks")
	for id in ["ext_sgr_tracking", "ext_sgr_yield", "ext_phe_white_hole"]:
		check(game.deep_sky.purchase(id), "Phoenix is reachable without completing Sagittarius: " + id)
	var before: float = policy.probability("white_hole", p)
	var black_before: float = policy.probability("black_hole", p)
	check(before > 0.0 and not game.deep_sky.research_owned("ext_sgr_linger"), "white hole is a successor branch without a full-constellation gate")
	for id in ["ext_phe_ejecta", "ext_phe_tracking", "ext_phe_arrivals", "ext_phe_yield", "ext_phe_outflow"]:
		check(game.deep_sky.purchase(id), "real Phoenix transaction: " + id)
	check(is_equal_approx(policy.probability("white_hole", p) / before, 1.5), "search research changes the independent white-hole probability")
	check(is_equal_approx(policy.probability("black_hole", p), black_before), "Phoenix does not retune black-hole occurrence")
	var source = game.spawner.spawn_meteor("white_hole", Vector2(500, 300), Vector2.RIGHT)
	source.base_automatic_rate = 1.0
	source.tick_observation(0.1)
	check(is_equal_approx(source.observation_progress, 0.15), "Phoenix tracking speeds up actual automatic observation")
	check(source.ejecta_count == 48, "two burst researches accumulate on a real source")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(saved)
	check(game.deep_sky.research_owned("ext_phe_outflow"), "new research survives JSON save/load")
	check(JSON.parse_string(JSON.stringify(game.spawner.spawn_policy.save_state())) == saved.simulation.spawner.rng, "all new and existing streams resume exactly")
	await process_frame
	check(game.meteor_layer.get_child_count() == 0, "load does not replay natural sources or ejecta")
	game.spawner.set_phase_time_remaining(60.0)
	game.spawner._announce_regular_spawn(game.spawner.spawn_policy.entries.white_hole, "white_hole")
	check(game.spawner.pending_contacts.size() == 1, "unlocked white holes use the natural forecast queue")
	var contact: Dictionary = game.spawner.pending_contacts.back()
	contact.countdown = 0.0
	game.spawner._update_pending_contacts(1.0 / 60.0)
	check(game.spawner.spawn_policy.counters.white_hole.admitted == 1, "natural admission reaches the playable subclass")
	source = game.meteor_layer.get_child(0)
	check(source.type_id == "white_hole" and source.can_be_tracked() and source.ejecta_count == 48, "natural arrivals carry researched mechanics")
	var start: Vector2 = source.position
	source.tick_motion(0.2, 1)
	check(source.position.is_equal_approx(start + source.initial_velocity * 0.2), "natural entry keeps its chosen heading")
	game.spawner.phase_time_remaining = game.spawner._minimum_payable_time("white_hole") - 0.01
	game.spawner._announce_regular_spawn(game.spawner.spawn_policy.entries.white_hole, "white_hole")
	check(game.spawner.pending_contacts.is_empty(), "late-round announcements leave time for the beam and ejecta")
	# A v6 save keeps its old streams and ownership; only the new stream is seeded.
	saved.deep_sky.extension.catalogue_version = 6
	saved.deep_sky.extension.research_ids = saved.deep_sky.extension.research_ids.filter(func(id): return not String(id).begins_with("ext_phe_"))
	saved.simulation.spawner.rng.occurrence.erase("white_hole")
	saved.simulation.spawner.rng.entries.erase("white_hole")
	game._apply_save_data(saved)
	check(p.has_extension_research("ext_sgr_yield") and not p.has_extension_research("ext_phe_white_hole"), "old saves keep black-hole research without a free Phoenix unlock")
	var restored: Dictionary = game.spawner.spawn_policy.save_state()
	for stream in ["occurrence", "entries"]:
		for kind in saved.simulation.spawner.rng[stream]:
			check(restored[stream][kind] == saved.simulation.spawner.rng[stream][kind], "legacy RNG preserved: " + stream + "/" + kind)
		check(restored[stream].has("white_hole"), "missing white-hole stream receives a seeded fallback")
	check(game.spawner.MAX_TOTAL_METEORS == 70, "new reservation preserves the overall safety ceiling")
	game.free()
	paused = false

func _test_researched_ejecta() -> void:
	for upgraded in [false, true]:
		var game = _game()
		game.progression.purchased_nodes["galactic_reference_frame"] = true
		game.deep_sky.state.research_ids.assign(["ext_protocol", "ext_phe_white_hole", "ext_phe_ejecta", "ext_phe_yield"])
		if upgraded: game.deep_sky.state.research_ids.append("ext_phe_outflow")
		var source = game.spawner.spawn_meteor("white_hole", Vector2(576, 300), Vector2(20, -4))
		source.observation_progress = 1.0
		source.tick_resolve()
		var paid: float = game.progression.observation_data
		for tick in 72:
			source.tick_motion(1.0 / 60.0, tick + 1)
			source.tick_resolve()
		var children := _ejecta(game)
		var expected := 48 if upgraded else 36
		check(children.size() == expected and source.emitted_count == expected, "research changes the full six-wave burst")
		check(game.progression.observation_data == paid, "larger emission is not an immediate data grant")
		var sides := [0, 0]
		for body in children:
			sides[0 if body.initial_velocity.dot(source.release_axis) > 0.0 else 1] += 1
			check(is_equal_approx(body.base_value, float(Balance.meteor_spec(body.type_id).value) * 1.5), "ejecta analysis reaches each emitted body")
		check(sides[0] == expected / 2 and sides[1] == expected / 2, "upgrades retain balanced bipolar emission")
		var ordinary = game.spawner.spawn_meteor("common", Vector2(100, 200), Vector2.RIGHT)
		check(is_equal_approx(ordinary.base_value, Balance.meteor_spec("common").value), "ejecta analysis leaves ordinary meteor data unchanged")
		children[0].observation_progress = 1.0
		children[0].tick_resolve()
		check(game.progression.observation_data > paid, "enhanced ejecta pay through the normal observation callback")
		game.free()
