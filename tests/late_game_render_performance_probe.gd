extends SceneTree

# Real-renderer, wall-time late-game diagnostic. Unlike the fixed-grid input
# probe this runs natural spawning, two fragmentation modules, automatic scans,
# solid bodies, completion effects and sound code together. Never runs on player
# persistence; an optional NIGHTWATCH_PERF_SAVE points to a read-only CFG copy.
const Fixtures = preload("res://tests/support/game_fixture.gd")
const MODULES := ["overcharge", "focus", "sweep_optics", "capture_hold", "focus"]
const WARMUP := 5.0
const SAMPLE := 25.0
var failures: Array[String] = []

class Observer:
	extends "res://scripts/observation_controller.gd"
	var point := Vector2(576, 300)
	func _screen_to_world(_position: Vector2) -> Vector2: return point
	func _cursor_is_on_ui() -> bool: return false

class Driver:
	extends Node
	var observer: Node
	var samples_per_tick := 17
	func _physics_process(_delta: float) -> void:
		for i in samples_per_tick:
			var at: float = observer.input_time + (i + 1) / (float(samples_per_tick) * 60.0)
			observer.point = Vector2(576 + sin(at * 2) * 400, 300 + cos(at * 3) * 200)
			observer.tick_input.push(at, observer.point, true)

# Optional A/A audit, kept out of timed performance runs. Hash the first 1,200
# ticks, spawn/contact/completion order, target state and gameplay RNG streams.
class Trace:
	extends Node
	var game: Node
	var ticks := 0
	var digest := HashingContext.new()
	func _init() -> void: digest.start(HashingContext.HASH_SHA256)
	func record(value: Array) -> void:
		if ticks < 1200: digest.update(JSON.stringify(value).to_utf8_buffer())
	func spawned(target: Node) -> void:
		record(["spawn", game.simulation_clock.tick, target.simulation_id, target.type_id, target.position, target.velocity])
		target.observed.connect(func(meteor, reward, multiplier, manual, grade):
			record(["complete", game.simulation_clock.tick, meteor.simulation_id, reward, multiplier, manual, grade]))
	func _physics_process(_delta: float) -> void:
		if ticks >= 1200: return
		var state: Array = ["tick", game.simulation_clock.tick, game.progression.success_count, game.progression.total_data_earned]
		for target in game.meteor_layer.get_children() + game.deep_sky.director.targets():
			state.append([target.simulation_id, target.type_id, target.position.x, target.position.y, target.age, target.get_progress(), target.alive])
		for rng in [game.spawner.rng, game.spawner.forecast_rng, game.spawner.warm_contact_rng, game.spawner.echo_rng, game.spawner.module_rng, game.events.rng, game.survey.rng, game.deep_sky.director.occurrence_rng]:
			state.append(str(rng.state))
		for kind in game.spawner.spawn_policy.ORDER:
			state.append([str(game.spawner.spawn_policy.occurrence[kind].state), str(game.spawner.spawn_policy.entries[kind].state)])
		record(state)
		ticks += 1
		if ticks == 1200: print("LATE_RENDER_TRACE ", digest.finish().hex_encode())

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Late-game frame measurements require a real renderer")
		quit(1)
		return
	create_timer(90.0).timeout.connect(func():
		push_error("Late-game rendering probe timed out")
		quit(1))
	root.gui_disable_input = true
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	var observer := Observer.new()
	observer.z_index = 50
	Fixtures.replace_child(game, "ObservationController", observer)
	root.add_child(game)
	observer.set_process_input(false)
	var saved_path := OS.get_environment("NIGHTWATCH_PERF_SAVE")
	if not saved_path.is_empty():
		var config := ConfigFile.new()
		if config.load(saved_path) != OK:
			push_error("Could not read the isolated performance save")
			game.free()
			quit(1)
			return
		game._apply_save_data(config.get_value("run", "data"))
	else:
		for node in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[node.id] = true
		for id in game.deep_sky.Data.RESEARCH: game.deep_sky.state.research_ids.append(id)
		game.deep_sky.modules.unlocked_slots = 5
		for id in MODULES:
			game.deep_sky.modules.grant_copy(id)
			game.deep_sky.modules.equip(id)
		game._sync_galactic_systems()
	# A copied save supplies research/equipment, not a partly random transient sky.
	game.spawner.reset()
	for target in game.meteor_layer.get_children(): target.free()
	game.events.reset()
	game.effects.reset()
	game.deep_sky.director.scheduler_seed = 663322
	game.deep_sky.director.reset()
	for target in game.deep_sky.director.targets(): target.free()
	# Seed BEFORE start_spawning creates its first warm forecast.
	game.spawner.rng.seed = 556611
	game.spawner.forecast_rng.seed = 112233
	game.spawner.warm_contact_rng.seed = 442233
	game.spawner.echo_rng.seed = 881122
	game.spawner.module_rng.seed = 551199
	game.spawner.spawn_policy.reseed(771155)
	game.events.rng.seed = 901234
	game.effects.rng.seed = 778899
	game._begin_observation_phase()
	# begin_round intentionally installs its own deterministic survey seed.
	game.survey.rng.seed = 332211
	var tracer: Trace
	if OS.get_environment("NIGHTWATCH_PERF_TRACE") == "1":
		tracer = Trace.new()
		tracer.game = game
		tracer.process_physics_priority = 100
		game.spawner.meteor_spawned.connect(tracer.spawned)
		game.spawner.contact_announced.connect(func(contact): tracer.record(["contact", game.simulation_clock.tick, contact]))
		root.add_child(tracer)
	# Guarantee the expensive solid surface throughout the sample; stochastic
	# planet admission alone can miss it entirely. This one diagnostic target
	# moves normally but cannot complete during the measurement window.
	var planet = game.spawner.spawn_meteor("galaxy", Vector2(820, 220), Vector2(3, 0), 1000.0, Vector2(940, 260))
	if planet == null:
		push_error("Could not admit the diagnostic planet")
		game.free()
		quit(1)
		return
	planet.required_track_time = 1000000.0
	var driver := Driver.new()
	driver.observer = observer
	var input_samples := OS.get_environment("NIGHTWATCH_PERF_INPUT_SAMPLES")
	if input_samples.is_valid_int(): driver.samples_per_tick = clampi(int(input_samples), 1, 134)
	driver.process_physics_priority = -100
	root.add_child(driver)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("LATE_RENDER_ENV ", JSON.stringify({"engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(), "viewport":str(root.size),
		"copied_save":not saved_path.is_empty(), "warmup":WARMUP, "sample":SAMPLE, "noncompleting_planets":1,
		"input_samples_per_tick":driver.samples_per_tick, "trace_enabled":tracer != null,
		"base_research":game.progression.purchased_nodes.size(), "outer_research":game.deep_sky.state.research_ids.size()}))
	var frames: Array[float] = []
	var started := Time.get_ticks_usec()
	var last := started
	var first_tick := -1
	var successes: int = game.progression.success_count
	var targets := 0
	var planets := 0
	var particles := 0
	while (Time.get_ticks_usec() - started) / 1000000.0 < WARMUP + SAMPLE:
		await process_frame
		var now := Time.get_ticks_usec()
		if (now - started) / 1000000.0 > WARMUP:
			if first_tick < 0:
				first_tick = game.simulation_clock.tick
				successes = game.progression.success_count
			else:
				frames.append((now - last) / 1000.0)
				targets = maxi(targets, game.meteor_layer.get_child_count())
				particles = maxi(particles, game.effects.particles.size())
				for target in game.meteor_layer.get_children():
					if target.type_id == "galaxy": planets += 1
		last = now
	var elapsed: float = frames.reduce(func(a, b): return a + b, 0.0) / 1000.0
	frames.sort()
	var completions: int = game.progression.success_count - successes
	if frames.is_empty() or targets < 10 or planets == 0 or particles == 0 or completions == 0:
		failures.append("Incomplete late-game rendering workload")
	print("LATE_RENDER_RESULT ", JSON.stringify({"fps":frames.size() / elapsed,
		"p95_ms":frames[floori((frames.size() - 1) * 0.95)], "p99_ms":frames[floori((frames.size() - 1) * 0.99)],
		"max_ms":frames.back(), "frames":frames.size(), "peak_targets":targets,
		"planet_frame_samples":planets, "peak_particles":particles, "completions":completions,
		"ticks_per_second":(game.simulation_clock.tick - first_tick) / elapsed,
		"draw_calls_end":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
	driver.free()
	if tracer != null: tracer.free()
	game.set_physics_process(false)
	await create_timer(0.25).timeout # Settle delayed sound cues before freeing owners.
	game.free()
	await process_frame
	for failure in failures: push_error(failure)
	print("LATE_RENDER_PASS" if failures.is_empty() else "LATE_RENDER_FAIL")
	quit(0 if failures.is_empty() else 1)
