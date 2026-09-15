extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Bindings = preload("res://scripts/game_input_bindings.gd")
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
	if failures.is_empty(): print("WHITE_HOLE_PASS: debug routing, bounded previews, save isolation, pause, accessibility and cleanup")
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
	check(not game.spawner.spawn_policy.ORDER.has("white_hole"), "white holes never enter natural occurrence streams")
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
	for index in 51: game.spawner.spawn_meteor("common", Vector2(30, 100), Vector2.RIGHT)
	source.observation_progress = 1.0
	source.tick_resolve()
	source.tick_motion(1.1, 1)
	source.tick_resolve()
	check(_ejecta(game).is_empty() and game.meteor_layer.get_child_count() == 54, "burst respects the shared atmospheric safety budget")
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
