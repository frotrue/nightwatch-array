extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Policy = preload("res://scripts/spawn_policy.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BLACK_HOLE: " + message)

func _game():
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	return game

func _run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("Black hole test timeout"); quit(1))
	for manual in [false, true]:
		var game = _game()
		var source = game.spawner.spawn_meteor("black_hole", Vector2(550, 300), Vector2(30, 0), 30.0)
		check(source != null and game.spawner.spawn_meteor("black_hole") == null, "one reserved black hole")
		var near = game.spawner.spawn_meteor("common", Vector2(750, 300), Vector2(20, 0), 20.0)
		var far = game.spawner.spawn_meteor("fast", Vector2(800, 300), Vector2(20, 0), 20.0)
		var boundary = game.spawner.spawn_meteor("binary_star", Vector2(550, 540), Vector2(20, 0), 20.0)
		var dead = game.spawner.spawn_meteor("fragment_piece", Vector2(560, 300), Vector2(20, 0), 20.0)
		dead.alive = false
		near.observation_progress = 0.4
		var before: Vector2 = source.position
		source.tick_motion(STEP, 1)
		check(source.position != before and near.gravity_capture == null, "live black hole moves without attracting")
		# Set the completion pose exactly for the inclusive radius assertion.
		source.position = Vector2(550, 300)
		source.manual_touched = manual
		source.observation_progress = 1.0
		source.tick_resolve()
		check(near.gravity_capture != null and boundary.gravity_capture != null, "manual/automatic completion gathers inside and boundary targets")
		check(far.gravity_capture == null and dead.gravity_capture == null and source.gravity_capture == null, "outside, dead and black holes are excluded")
		var capture = near.gravity_capture
		var reward: float = game.progression.observation_data
		source.tick_resolve()
		check(capture == near.gravity_capture and reward == game.progression.observation_data, "completion and capture fire once")
		source.free()
		check(not game.black_hole_lens.lens.visible and game.black_hole_lens.background_copy.copy_mode == 0, "lens copy releases with source")
		var age: float = near.age
		for tick in 51: near.tick_motion(STEP, tick + 2)
		check(near.position.distance_to(Vector2(550, 300)) < 70.0, "gather survives source deletion and reaches a loose central cluster")
		check(is_equal_approx(near.age, age), "pull preserves the remaining observation window")
		check(near.observation_progress == 0.4 and near.alive and game.progression.observation_data == reward, "pull never consumes, completes or pays for targets")
		for tick in 70:
			var previous: Vector2 = near.position
			near.tick_motion(STEP, tick + 53)
			check(near.position.distance_to(previous) < 3.0, "release and normal motion have no path snap")
		check(near.gravity_capture == null, "temporary gravity state expires")
		# Repeated captures rebase from the current position, with no discontinuity.
		var start: Vector2 = near.position
		near.begin_gravity_capture(Vector2(500, 300), 1.0)
		check(near.position == start, "recapture starts at current position")
		var save: Dictionary = game._build_save_data()
		game._apply_save_data(save)
		await process_frame
		check(game.meteor_layer.get_child_count() == 0, "load clears transient captured sky")
		game.free()
	_test_policy()
	_test_lensed_contacts()
	await _test_worker_parity()
	if failures.is_empty(): print("BLACK_HOLE_PASS: unlock, reserved spawn, completion, radius, capture/release, save cleanup and worker parity")
	quit(0 if failures.is_empty() else 1)

func _test_policy() -> void:
	var game = _game()
	var policy := Policy.new(87)
	check(policy.probability("black_hole", game.progression) == 0.0, "black hole locked initially")
	game.progression.purchased_nodes["galaxy_imaging"] = true
	check(policy.probability("black_hole", game.progression) > 0.0, "planet research unlocks black hole")
	var old_save := policy.save_state()
	old_save.occurrence.erase("black_hole")
	old_save.entries.erase("black_hole")
	policy.restore_state(old_save)
	var other := Policy.new(87)
	other.restore_state(old_save)
	for tick in 1200:
		check(policy.roll(game.progression) == other.roll(game.progression), "old saves deterministically initialize the added stream")
	# Admission follows the ordinary forecast pipeline, rather than a special event.
	game.spawner._announce_regular_spawn(null, "black_hole")
	game.spawner.pending_contacts.back().countdown = 0.0
	game.spawner._update_pending_contacts(STEP)
	check(game.spawner._slot_count(["black_hole"]) == 1, "ordinary forecast admits black hole")
	game.free()

func _test_lensed_contacts() -> void:
	var game = _game()
	var hole = game.spawner.spawn_meteor("black_hole", Vector2(500, 300), Vector2(1, 0), 30.0)
	hole.age = 4.0
	var sample = game.spawner.spawn_meteor("common", Vector2(540, 300), Vector2(1, 0), 30.0)
	var physical: Vector2 = sample.global_position
	var apparent: Vector2 = sample.get_observation_position(1.0)
	check(apparent.distance_to(physical) > 8.0 and sample.global_position == physical, "optical image shifts without moving the physical target")
	check(game.observer._target_contact_distance(sample, apparent) < 0.001, "visual centre receives centred manual quality")
	game.observer.previous_cursor_position = apparent
	game.observer.cursor_position = apparent
	check(game.observer._circle_contact_interval(sample, 1.0) == Vector2(0, 1), "circle contact follows the lensed image")
	check(game.observer._linear_contact_interval(sample, 1.0) == Vector2(0, 1), "linear contact follows the lensed image")
	game.observer._begin_tick_cache()
	var cached: Vector2 = game.observer._target_position_at(sample, 0.4)
	game.observer._end_tick_cache()
	check(cached == game.observer._target_position_at(sample, 0.4), "cached and uncached optical contact poses match")
	game.black_hole_lens.motion_scale = 0.0
	check(sample.get_observation_position(1.0) == physical, "reduced motion restores original image and contact centre")
	game.black_hole_lens.motion_scale = 1.0
	check(hole.get_observation_position(1.0) == hole.global_position, "black hole never lenses itself")
	var close: Vector2 = hole.global_position + Vector2(2, 0)
	var close_image: Vector2 = game.black_hole_lens.project_position(close, 1.0)
	check(close_image.is_finite() and close_image.distance_to(hole.global_position) > hole.body_radius, "near-aligned primary image remains visible outside the shadow")
	var distant: Vector2 = hole.global_position + Vector2(1000, 0)
	check(game.black_hole_lens.project_position(distant, 1.0) == distant, "far-field contacts are unchanged")
	game.black_hole_lens.motion_scale = 0.5
	var half_strength: Vector2 = sample.get_observation_position(1.0)
	check(half_strength.x > physical.x and half_strength.x < apparent.x, "reduced lens strength returns the apparent centre continuously")
	hole.free()
	check(sample.get_observation_position(1.0) == physical, "removing the lens clears optical selection offsets")
	game.free()

func _test_worker_parity() -> void:
	var games: Array = []
	for parallel in [false, true]:
		var game = _game()
		game.parallel_motion_enabled = parallel
		for index in 132:
			var target = game.spawner.MeteorScript.new()
			target.configure(game.Balance.meteor_spec("common"), "common", Vector2(300 + index, 300), Vector2(20, 0), 10.0, {})
			target.wobble_phase = 0.0
			target.simulation_id = index
			game.meteor_layer.add_child(target)
			if index < 3: target.begin_gravity_capture(Vector2(250, 300), 1.0)
		games.append(game)
	for tick in 130:
		for game in games: game._tick_target_motion(game.meteor_layer.get_children(), STEP)
		for index in 132:
			var left = games[0].meteor_layer.get_child(index)
			var right = games[1].meteor_layer.get_child(index)
			check(left.position.distance_to(right.position) < 0.0001 and is_equal_approx(left.age, right.age), "threaded and serial capture/release match")
	for game in games: game.free()
	await process_frame
