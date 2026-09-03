extends SceneTree

# Synthetic A/B renderer/input workload, NOT normal spawn density or a human
# playtest. Each rendered frame advances exactly 1/60 simulated second. Fixed
# grids keep 18 or 32 live specimens (including a Major at 32); bounded ages and
# immediate in-place replenishment intentionally omit expiry, fragment spawning,
# and post-completion meteor linger. Production tracking, meteor processing/draw,
# completion feedback, HUD and twinkle code still execute unchanged.
#
# Run windowed with the Windows/OpenGL renderer for frame-time evidence. A
# --headless run validates mechanics only and explicitly reports cpu_only=true.
# NIGHTWATCH_OBSERVATION_PERF_FRAMES optionally selects 180..1800 frames per phase
# (default 360). All phases also execute 60 untimed warm-up frames. Compare the
# same frame count, environment and source identities; time is not accelerated
# through Engine.time_scale and hardware cursor movement is never injected.

const Fixtures = preload("res://tests/support/game_fixture.gd")
const MainScene = preload("res://scenes/main.tscn")
const FIXED_STEP := 1.0 / 60.0
const SEED := 20260904
const DEFAULT_FRAMES := 360
const WARMUP_FRAMES := 60
const FRAMES_ENV := "NIGHTWATCH_OBSERVATION_PERF_FRAMES"
const WATCHDOG_SECONDS := 180.0
const VIEWPORT := Vector2(1152.0, 648.0)
const PHASES := ["still", "sweep", "hold"]
const WORKLOADS := [18, 32]
const SOURCE_FILES := [
	"tests/observation_performance_probe.gd", "tests/support/game_fixture.gd",
	"scenes/main.tscn",
	"scripts/observation_controller.gd", "scripts/meteor.gd", "scripts/game.gd",
	"scripts/effects_layer.gd", "scripts/hud.gd", "scripts/ui_theme.gd",
	"scripts/progression_controller.gd", "scripts/game_balance.gd",
]


class ScriptedObserver:
	extends "res://scripts/observation_controller.gd"

	var scripted_cursor := VIEWPORT * 0.5

	# The inherited _process still samples, finds targets, applies tracking,
	# refreshes the HUD and schedules its real drawing. Only input sampling is
	# replaced, so the OS cursor cannot change the workload or move the window.
	func _screen_to_world(_point: Vector2) -> Vector2:
		return scripted_cursor

	func _cursor_is_on_ui() -> bool:
		return false


var game
var meteors: Array = []
var failures: Array[String] = []
var sample_frames := DEFAULT_FRAMES
var probe_start_usec := 0
var completed_rows := 0
var packets_landed := 0
var source_hashes := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	probe_start_usec = Time.get_ticks_usec()
	sample_frames = _configured_frames()
	source_hashes = _source_hashes()
	root.gui_disable_input = true
	print("OBSERVATION_PERF_ENV " + JSON.stringify({
		"engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(),
		"cpu_only": DisplayServer.get_name() == "headless",
		"viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"process_monitor_note": "TIME_PROCESS is a coarse engine monitor; only the end-of-phase value is reported, not falsely attributed per-frame percentiles. sync_work_ms measures the scripted production calls directly.",
		"frame_note": "Wall-clock process-frame intervals include the bounded probe bookkeeping; sync_work excludes bookkeeping and draw submission.",
		"visual_clock_note": "Production hover-ring pulse still uses the real clock; its phase is not pixel-deterministic, but its geometry budget is unchanged.",
		"seed": SEED, "fixed_step": FIXED_STEP,
		"frames_per_phase": sample_frames, "warmup_frames": WARMUP_FRAMES,
		"workloads": WORKLOADS, "phases": PHASES,
		"synthetic": true, "isolated_settings_and_slots": true,
		"input": "scripted engine-local button and coordinate sampler; no OS injection",
		"research": ["multi_target_analysis"],
		"research_note": "isolated feature flag, not a legal completed research build",
		"target_lifetime_seconds": 30.0, "target_age_seconds": "2..6 repeating",
		"replenishment": "in-place immediately after completion; no dead linger specimens",
		"excluded": ["spawn cadence", "automation", "survey summons", "host targets", "phenomena", "audio playback", "human input feel"],
		"sources": source_hashes,
	}))
	_check(root.get_visible_rect().size.is_equal_approx(VIEWPORT), "Expected 1152x648 viewport")
	for count in WORKLOADS:
		for phase in PHASES:
			if not failures.is_empty():
				break
			await _measure_phase(count, phase)
	_release_button()
	await _dispose_game()
	_check(source_hashes == _source_hashes(), "Source files changed during the sample")
	if failures.is_empty() and completed_rows == WORKLOADS.size() * PHASES.size():
		print("OBSERVATION_PERF_PASS: %d valid synthetic samples; performance values are diagnostics, not a gameplay acceptance gate" % completed_rows)
		quit(0)
	else:
		for failure in failures:
			push_error("OBSERVATION_PERF_INVALID: " + failure)
		print("OBSERVATION_PERF_FAIL: %d invalid condition(s), %d completed samples" % [failures.size(), completed_rows])
		quit(1)


func _prepare_game(count: int) -> void:
	seed(SEED)
	game = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	var original_observer: Node2D = game.get_node("ObservationController")
	var scripted_observer := ScriptedObserver.new()
	# main.tscn authors z_index=50 in addition to the script. Keep the cursor
	# above meteors (10), survey (15), dishes (20) and effects (40), as shipped.
	scripted_observer.z_index = original_observer.z_index
	Fixtures.replace_child(game, "ObservationController", scripted_observer)
	root.add_child(game)
	_disable_callbacks(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	game.sound.set_process(false)
	game.spawner.running = false
	game.events.running = false
	game.effects.rng.seed = SEED
	# This one explicitly declared synthetic feature exercises the real
	# additional-target scan without introducing unrelated economic/proc systems.
	game.progression.purchased_nodes["multi_target_analysis"] = true
	game.progression.purchase_order.append("multi_target_analysis")
	game.effects.packet_landed.connect(_on_packet_landed)
	packets_landed = 0
	game.observation_phase_duration = (WARMUP_FRAMES + sample_frames) * FIXED_STEP + 10.0
	game.observation_phase_remaining = game.observation_phase_duration
	game.observer.reset()
	meteors.clear()
	for index in range(count):
		var type_id := "common"
		if index > 0:
			type_id = "fireball" if index % 7 == 0 else ("fragment" if index % 4 == 0 else "common")
		if count == 32 and index == count - 1:
			type_id = "major"
		var columns := 6
		var rows := ceili(float(count) / columns)
		var start := Vector2(125.0 + float(index % columns) * 165.0, 125.0 + float(index / columns) * 365.0 / maxf(1.0, rows - 1))
		var direction := Vector2.from_angle(-0.25 + float(index % 5) * 0.12)
		var meteor = game.spawner.spawn_meteor(type_id, start, direction * 18.0, 30.0, start + direction * 80.0)
		if meteor == null:
			_check(false, "Spawner rejected declared specimen %d/%d" % [index, count])
			return
		meteor.set_process(false)
		meteor.split_done = true
		meteor.age = 2.0
		meteor.trail_points.clear()
		for trail_index in range(meteor.max_trail_points):
			meteor.trail_points.append(start - direction * float(trail_index) * 3.0)
		meteors.append(meteor)
	game.effects.reset()
	game.hud.banner_timer = 0.0
	game.hud.banner_root.visible = false
	game.hud._refresh_progression()
	game.observer.cursor_position = VIEWPORT * 0.5
	game.observer.previous_cursor_position = game.observer.cursor_position
	game.observer.scripted_cursor = game.observer.cursor_position
	_disable_callbacks(game)
	_pause_tweens()
	_check(game.settings is Fixtures.NoSettings and game.save_games is Fixtures.NoSaveSlots, "Persistence services were not isolated")
	_check(game.observer.z_index == 50 and game.observer.z_index > game.effects.z_index, "Scripted observer lost the shipped draw order")
	_check(game.active_save_slot == 0, "Probe unexpectedly selected a save slot")
	_check(game.observation_phase_active and not paused, "Synthetic observation phase is not live")


func _measure_phase(count: int, phase: String) -> void:
	_prepare_game(count)
	if not failures.is_empty():
		return
	for frame in range(WARMUP_FRAMES):
		_step(phase, frame)
		await process_frame
	var frames: Array[float] = []
	var work: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	var minimum_live := count
	var maximum_live := 0
	var minimum_major := 1 if count == 32 else 0
	var visible_samples := 0
	var tracked_frames := 0
	var hover_frames := 0
	var maximum_particles := 0
	var maximum_packets := 0
	var cursor_distance := 0.0
	var completion_start: int = game.progression.manual_successes
	var landed_start := packets_landed
	var previous_cursor: Vector2 = game.observer.cursor_position
	var last_frame_usec := Time.get_ticks_usec()
	for frame in range(sample_frames):
		if float(Time.get_ticks_usec() - probe_start_usec) / 1000000.0 > WATCHDOG_SECONDS:
			_check(false, "180-second watchdog exceeded")
			break
		var started := Time.get_ticks_usec()
		_step(phase, WARMUP_FRAMES + frame)
		work.append(float(Time.get_ticks_usec() - started) / 1000.0)
		cursor_distance += previous_cursor.distance_to(game.observer.cursor_position)
		previous_cursor = game.observer.cursor_position
		var live := 0
		var major := 0
		for meteor in meteors:
			if is_instance_valid(meteor) and meteor.alive:
				live += 1
				major += int(meteor.type_id == "major")
				if meteor.visible and root.get_visible_rect().has_point(game.observation_view.world_to_screen(meteor.global_position)) and meteor.trail_points.size() > 1:
					visible_samples += 1
		minimum_live = mini(minimum_live, live)
		maximum_live = maxi(maximum_live, live)
		minimum_major = mini(minimum_major, major)
		tracked_frames += int(game.observer._selection_is_valid())
		hover_frames += int(game.observer._target_is_valid(game.observer.hovered_meteor))
		maximum_particles = maxi(maximum_particles, game.effects.particles.size())
		maximum_packets = maxi(maximum_packets, game.effects.popups.size())
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last_frame_usec) / 1000.0)
		last_frame_usec = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var completions: int = game.progression.manual_successes - completion_start
	_check(frames.size() == sample_frames, "%s/%d did not finish every sample" % [phase, count])
	_check(minimum_live == count and maximum_live == count and game.meteor_layer.get_child_count() == count, "%s/%d changed the declared live workload" % [phase, count])
	_check(visible_samples == count * sample_frames, "%s/%d lost visible targets or trails" % [phase, count])
	_check(minimum_major == (1 if count == 32 else 0), "%s/%d lost its declared Major" % [phase, count])
	_check(not game.hitstop_active and is_equal_approx(Engine.time_scale, 1.0), "%s/%d unexpectedly entered real-time hitstop" % [phase, count])
	if phase == "still":
		_check(cursor_distance < 0.001 and completions == 0, "Still phase had cursor motion or completions")
	elif phase == "sweep":
		_check(cursor_distance > sample_frames * 20.0 and hover_frames > 0 and completions == 0, "Sweep phase did not exercise moving hover selection")
	elif phase == "hold":
		_check(tracked_frames > sample_frames / 2 and completions > 0 and maximum_particles > 0 and packets_landed > landed_start, "Hold phase did not exercise tracking, completion, particles and landed packets")
	if DisplayServer.get_name() != "headless":
		_check(_mean(draws) > 0.0 and _mean(primitives) > 0.0, "Windowed sample did not submit rendered geometry")
	var over_budget := 0
	for milliseconds in frames:
		over_budget += int(milliseconds > 16.7)
	print("OBSERVATION_PERF_RESULT " + JSON.stringify({
		"phase": phase, "declared_live": count, "frames": frames.size(),
		"simulation_seconds": sample_frames * FIXED_STEP, "frame_ms": _distribution(frames),
		"over_16_7_ms": over_budget, "sync_work_ms": _distribution(work),
		"engine_process_ms_end": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": _distribution(draws), "primitives": _distribution(primitives),
		"live_min": minimum_live, "live_max": maximum_live, "major_min": minimum_major,
		"visible_target_samples": visible_samples, "cursor_distance_px": cursor_distance,
		"tracked_frames": tracked_frames, "hover_frames": hover_frames,
		"manual_completions": completions, "automatic_completions": game.progression.automatic_successes,
		"packets_landed": packets_landed - landed_start,
		"peak_particles": maximum_particles, "peak_packets": maximum_packets,
		"valid": failures.is_empty(),
	}))
	completed_rows += 1
	await _dispose_game()


func _step(phase: String, frame: int) -> void:
	# Frozen/repeating lifetime poses keep every authored shape on screen; these
	# are render stress specimens, not a claim about normal meteor trajectories.
	for meteor in meteors:
		meteor.age = 2.0 + fmod(float(frame) * FIXED_STEP, 4.0)
	var observer = game.observer
	match phase:
		"still": observer.scripted_cursor = VIEWPORT * 0.5
		"sweep":
			observer.scripted_cursor = Vector2(110.0 + fposmod(float(frame) * 137.0, 930.0), 125.0 + fposmod(float(frame) * 73.0, 365.0))
		"hold": observer.scripted_cursor = meteors[0].global_position
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = phase == "hold"
	Input.parse_input_event(button)
	game._process(FIXED_STEP)
	observer._process(FIXED_STEP)
	for meteor in meteors:
		meteor._process(FIXED_STEP)
		if not meteor.alive:
			_replenish(meteor)
	if game.effects.is_processing() or not game.effects.particles.is_empty() or not game.effects.popups.is_empty() or game.effects.kick_amplitude > 0.0:
		game.effects._process(FIXED_STEP)
	game.effects.set_process(false)
	game.hud._process(FIXED_STEP)
	game.twinkle_stars._process(FIXED_STEP)
	for tween in get_processed_tweens():
		tween.pause()
		tween.custom_step(FIXED_STEP)
	_pause_tweens()


func _replenish(meteor) -> void:
	# Keep exactly N live draws without allocating a (N+1)th lingering specimen.
	# The real observed signal and completion feedback already ran above.
	meteor.alive = true
	meteor.observed_successfully = false
	meteor.observation_progress = 0.0
	meteor.precision_focus = 0.0
	meteor.last_quality = 0.0
	meteor.last_manual_frame = -100
	meteor.manual_touched = false
	meteor.manual_tracking_time = 0.0
	meteor.quality_integral = 0.0
	meteor.interruption_count = 0
	meteor.linger_time = 0.0
	meteor.queue_redraw()


func _disable_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		_disable_callbacks(child)


func _pause_tweens() -> void:
	for tween in get_processed_tweens():
		tween.pause()


func _on_packet_landed(_amount: float) -> void:
	packets_landed += 1


func _release_button() -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = false
	Input.parse_input_event(button)


func _dispose_game() -> void:
	_release_button()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	meteors.clear()
	game = null


func _configured_frames() -> int:
	if not OS.has_environment(FRAMES_ENV):
		return DEFAULT_FRAMES
	var configured := OS.get_environment(FRAMES_ENV).strip_edges()
	if not configured.is_valid_int() or configured.to_int() < 180 or configured.to_int() > 1800:
		_check(false, "%s must be an integer in 180..1800" % FRAMES_ENV)
		return DEFAULT_FRAMES
	return configured.to_int()


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in SOURCE_FILES:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(1.0, values.size())


func _distribution(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {
		"mean": _mean(sorted), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99),
		"max": sorted[-1] if not sorted.is_empty() else 0.0,
	}


func _percentile(sorted: Array[float], ratio: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(ceili(float(sorted.size() - 1) * ratio), 0, sorted.size() - 1)]
