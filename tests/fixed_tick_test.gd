extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Clock = preload("res://scripts/simulation_clock.gd")
const BufferedInput = preload("res://scripts/simulation_input.gd")
const Policy = preload("res://scripts/spawn_policy.gd")
var failures: Array[String] = []

class UncachedObserver:
	extends "res://scripts/observation_controller.gd"
	func _begin_tick_cache() -> void: pass
	func _end_tick_cache() -> void: pass

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("FIXED_TICK: " + message)

func _run() -> void:
	var clock := Clock.new()
	check(clock.request_hitstop(0.05), "hitstop starts")
	for i in 3: check(is_equal_approx(clock.begin_tick(), 0.06), "hitstop lasts exactly three ticks")
	check(not clock.request_hitstop(0.1), "cooldown blocks immediate restart")
	for i in 24: clock.begin_tick()
	check(clock.request_hitstop(0.11), "cooldown releases after 24 ticks")
	for i in 7: check(is_equal_approx(clock.begin_tick(), 0.06), "110 ms rounds up to seven ticks")
	check(clock.begin_tick() == 1.0, "normal speed resumes")
	var input := BufferedInput.new()
	input.reset(Vector2.ZERO)
	input.push(0.0, Vector2.ZERO, true)
	input.push(0.005, Vector2(100, 0), true)
	input.push(0.010, Vector2.ZERO, false)
	var segments := input.consume(Clock.STEP)
	var travel := 0.0
	var held_time := 0.0
	for segment in segments:
		travel += Vector2(segment.start).distance_to(segment.end)
		if segment.held: held_time += float(segment.duration)
	check(is_equal_approx(travel, 200.0) and is_equal_approx(held_time, 0.01), "press, return and release within one frame retain the full path and held duration")
	check(not input.held and input.consume(2.0 * Clock.STEP).size() == 1, "a second tick cannot replay consumed input")
	input.reset(Vector2(900, 200))
	segments = input.consume(Clock.STEP)
	check(segments[0].start == segments[0].end and not segments[0].held, "pause/reset discards a pre-boundary gesture")
	var baseline: Dictionary = {}
	for fps in [30, 60, 144, 240]:
		var result := _run_schedule(fps)
		if baseline.is_empty(): baseline = result
		else: check(result == baseline, "identical authority and RNG under %d rendered frames/sec" % fps)
	_test_policy()
	_test_lifecycle()
	_test_observation_cache()
	await process_frame
	if failures.is_empty():
		print("FIXED_TICK_PASS: 30/60/144/240 render schedules, input edges, local hitstop, independent streams, capacity, forecast deferral and save replay")
		quit(0)
	else: quit(1)

func _game(cached: bool = true):
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	if not cached: Fixtures.replace_child(game, "ObservationController", UncachedObserver.new())
	root.add_child(game)
	game.set_physics_process(false)
	game.spawner.spawn_policy.reseed(271828)
	game.spawner.rng.seed = 35
	game.spawner.forecast_rng.seed = 36
	game.spawner.echo_rng.seed = 37
	game.spawner.module_rng.seed = 38
	game.events.rng.seed = 39
	game.observation_phase_duration = 120.0
	game.observation_phase_remaining = 120.0
	return game


func _test_observation_cache() -> void:
	# Same raw path against the live calculation: quality, swept intersections,
	# primary/secondary roles and changing loadouts must survive memoization.
	var games := [_game(), _game(false)]
	for game in games:
		game.spawner.running = false
		game.events.running = false
		for node in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[node.id] = true
		for id in game.deep_sky.Data.RESEARCH: game.deep_sky.state.research_ids.append(id)
		var modules = game.deep_sky.modules
		modules.unlocked_slots = 5
		for id in ["linear_observation", "wide", "wide_correlation", "overcharge", "precision"]: modules.grant_copy(id)
		modules.slots.assign(["linear_observation", "wide", "wide_correlation", "overcharge", "precision"])
		for i in 6:
			var target = game.spawner.spawn_meteor("common", Vector2(380 + i * 50, 260), Vector2(8, 3), 1000.0)
			target.required_track_time = 1000000.0
			target.base_automatic_rate = 0.0
		game.observer.tick_input.reset(Vector2(520, 270))
		game.observer.input_time = 0.0
		game.observer.tick_input.push(0.0, Vector2(520, 270), true)
	for tick in 60:
		for game in games:
			var modules = game.deep_sky.modules
			if tick == 15: modules.slots[0] = "" # switch line to circle
			if tick == 30: modules.slots[0] = "linear_observation"
			if tick == 40: modules.burst_remaining = Clock.STEP * 3.0
			if tick == 45: game.deep_sky.state.research_ids.clear()
			for sample in 17:
				var at := (tick + float(sample + 1) / 17.0) * Clock.STEP
				game.observer.tick_input.push(at, Vector2(520 + sin(at * 30.0) * 300, 270 + cos(at * 21.0) * 90), tick < 55)
			game.simulate_tick()
		for i in 6:
			var left = games[0].meteor_layer.get_child(i)
			var right = games[1].meteor_layer.get_child(i)
			for property in ["manual_tracking_time", "quality_integral", "observation_progress", "manual_contribution", "interruption_count"]:
				check(is_equal_approx(float(left.get(property)), float(right.get(property))), "cached contact differs at tick %d target %d: %s" % [tick, i, property])
		check(games[0].observer.tracked_meteors.size() == games[1].observer.tracked_meteors.size(), "cached target selection matches live calculation")
	check(games[0].meteor_layer.get_child(0).manual_tracking_time > 0.0, "cache parity exercised real contact")
	var observer = games[0].observer
	observer._begin_tick_cache()
	var summoned = games[0].spawner.spawn_meteor("common", Vector2(500, 260), Vector2.ZERO, 1000.0)
	check(summoned != null and summoned in observer._target_children(), "mid-pass Sky Sweep summon refreshes cached membership")
	observer._end_tick_cache()
	for game in games: game.free()

func _run_schedule(fps: int) -> Dictionary:
	var game = _game()
	game.observer.tick_input.reset(Vector2(420, 240))
	game.observer.input_time = 0.0
	game.observer.tick_input.push(0.0, Vector2(420, 240), true)
	for i in 601:
		game.observer.tick_input.push(i / 60.0, Vector2(420 + 100 * sin(i * 0.05), 240), true)
	var target = game.spawner.spawn_meteor("common", Vector2(420, 240), Vector2(1, 0), 30.0)
	target.required_track_time = 0.2
	var ticks := 0
	for frame in fps * 10:
		var due := mini(600, floori(float(frame + 1) * 60.0 / fps + 0.000001))
		while ticks < due:
			game.simulate_tick()
			ticks += 1
		game._process(1.0 / fps)
		game.observer._process(1.0 / fps)
		for meteor in game.meteor_layer.get_children(): meteor._process(1.0 / fps)
	var objects: Array = []
	for meteor in game.meteor_layer.get_children():
		if not meteor.is_queued_for_deletion(): objects.append([meteor.simulation_id, meteor.type_id, meteor.position, meteor.age, meteor.get_progress()])
	var result := {"tick": game.simulation_clock.tick, "time": game.observation_phase_remaining,
		"reward": game.progression.total_data_earned, "successes": game.progression.success_count,
		"objects": objects, "rng": game.spawner.spawn_policy.save_state(), "counters": game.spawner.spawn_policy.counters.duplicate(true)}
	check(result.successes > 0, "scripted cursor produces a real observation")
	game.free()
	return result

func _test_lifecycle() -> void:
	var game = _game()
	game.spawner.running = false
	game.events.running = false
	var tick: int = game.simulation_clock.tick
	var remaining: float = game.observation_phase_remaining
	paused = true
	game.simulate_tick()
	check(game.simulation_clock.tick == tick and game.observation_phase_remaining == remaining, "pause advances neither ticks nor round time")
	paused = false
	game.observation_phase_duration = 20.0
	game.observation_phase_remaining = Clock.STEP
	var target = game.spawner.spawn_meteor("common", Vector2(450, 240), Vector2.ZERO, Clock.STEP)
	target.required_track_time = 0.001
	game.observer.tick_input.reset(Vector2(450, 240))
	game.observer.input_time = 0.0
	game.observer.tick_input.push(0.0, Vector2(450, 240), true)
	game.simulate_tick()
	check(game.progression.success_count == 1 and not game.observation_phase_active, "completion wins over expiry and is included in the last round tick")
	check(int(game.last_clean_round_result.get("observations", 0)) == 1, "last-tick reward reaches the summary exactly once")
	var save: Dictionary = game._build_save_data()
	save.observation_phase_active = true
	save.observation_phase_remaining = 0.0
	save.erase("simulation")
	save.erase("spawn_model_version")
	game._apply_save_data(save)
	check(not game.observation_phase_active and game.progression.success_count == 1, "legacy zero-time save cannot revive a round or repeat its reward")
	var before: int = game.progression.success_count
	save.spawn_model_version = 999
	save.progression = {}
	game._apply_save_data(save)
	check(game.progression.success_count == before, "unsupported future spawn model is rejected before mutation")
	game.free()
	paused = false

func _test_policy() -> void:
	_test_fragment_admission()
	check(is_equal_approx(Policy.mean_interval(1.6, 2.4, 1.15), 2.0), "floor below interval")
	check(is_equal_approx(Policy.mean_interval(0.4, 0.8, 1.0), 1.0), "floor above interval")
	check(is_equal_approx(Policy.mean_interval(0.4, 0.8, 0.6), 0.65), "floor intersects interval")
	var game = _game()
	var left := Policy.new(1234)
	var right := Policy.new(1234)
	var before: float = game.progression.get_spawn_probability_multiplier()
	game.progression.purchased_nodes["galaxy_imaging"] = true
	check(is_equal_approx(left.probability("common", game.progression) / game.progression.get_spawn_probability_multiplier(), 0.5 / 60.0), "late unlock leaves common base probability intact")
	for i in 1000:
		var actual: Array[String] = left.roll(game.progression)
		var expected: Array[String] = []
		for kind in Policy.ORDER:
			if right.occurrence[kind].randf() < right.probability(kind, game.progression): expected.append(kind)
		check(actual == expected, "shared spawn multiplier preserves every per-type outcome")
	check(left.save_state() == right.save_state(), "locked/unlocked admission cannot perturb occurrence streams")
	var saved := left.save_state()
	var expected := left.roll(game.progression)
	left.restore_state(saved)
	check(left.roll(game.progression) == expected, "RNG state resumes the exact next draw")
	check(before > 0.0, "calibration produces a finite positive multiplier")
	for i in Policy.ATMOSPHERIC_SAFETY_SLOTS: game.spawner.spawn_meteor("common", Vector2(300, 200), Vector2(1, 0), 100.0)
	check(game.spawner.spawn_meteor("common") == null, "atmospheric hard capacity is bounded")
	for kind in Policy.LATE_TYPES:
		check(game.spawner.spawn_meteor(kind) != null, "late type has reserved space: " + kind)
	check(game.spawner.spawn_meteor("galaxy") != null, "one shared late extra slot")
	check(game.spawner.spawn_meteor("comet") == null, "late extra cannot evict another type's reservation")
	check(game.spawner.spawn_major_fireball() != null, "major target retains a reserved slot")
	game.spawner._announce_regular_spawn(null, "common")
	var ticket: Dictionary = game.spawner.pending_contacts.back()
	ticket.countdown = 0.0
	game.spawner._update_pending_contacts(Clock.STEP)
	check(ticket in game.spawner.pending_contacts and ticket.deferred > 0.0, "full sky defers arrival without losing its forecast")
	for i in 122: game.spawner._update_pending_contacts(Clock.STEP)
	check(ticket not in game.spawner.pending_contacts, "deferred ticket has a bounded lifetime")
	var data: Dictionary = game._build_save_data()
	game._apply_save_data(data)
	check(game.spawner.spawn_policy.save_state() == data.simulation.spawner.rng, "active save restores independent RNG streams")
	check(game.spawner.pending_contacts.is_empty(), "load does not duplicate a warm forecast")
	game.free()


func _test_fragment_admission() -> void:
	# Reproduce the old 22-slot failure through both actual split entry points.
	for early_completion in [false, true]:
		for occupied in [20, 21, 22]:
			var game = _game()
			var parent = game.spawner.spawn_meteor("fragment", Vector2(500, 300), Vector2(80, 0), 5.0)
			for i in occupied - 1: game.spawner.spawn_meteor("common", Vector2(300, 200), Vector2(1, 0), 10.0)
			if early_completion: parent.observation_progress = 1.0
			else: parent.age = parent.visible_lifetime * parent.split_progress + 0.0001
			parent.tick_resolve()
			check(game.spawner._slot_count(["fragment_piece"]) == 3, "full three-piece split at former cap, completion=%s count=%d" % [early_completion, occupied])
			parent.tick_resolve()
			check(game.spawner._slot_count(["fragment_piece"]) == 3, "completed split is not duplicated")
			game.free()
	var game = _game()
	var last
	for i in game.progression.get_max_active(): last = game.spawner.spawn_meteor("fragment_piece", Vector2(500, 300), Vector2(10, 0), 5.0)
	check(not game.spawner._has_spawn_space("common", 1, true), "an active fragment cloud pauses new natural arrivals")
	check(game.spawner._has_spawn_space("fragment_piece", 3), "natural arrival throttling does not reject a triggered split")
	last.alive = false
	check(game.spawner._has_spawn_space("common", 1, true), "completed linger does not consume the research active limit")
	# Emergency capacity still includes both children and fading parents.
	while game.spawner._has_spawn_space("fragment_piece"):
		game.spawner.spawn_meteor("fragment_piece", Vector2(500, 300), Vector2(10, 0), 5.0)
	check(game.spawner._slot_count(game.spawner.REGULAR_ACTIVE_TYPES) == Policy.ATMOSPHERIC_SAFETY_SLOTS, "children and linger reach exactly the safety ceiling")
	check(game.spawner.spawn_meteor("fragment_piece") == null, "final overload guard rejects further children")
	game.free()
