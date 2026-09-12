extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const PROBE_SECONDS := 24.0
const PROBE_SECONDS_ENV := "NIGHTWATCH_PROBE_SECONDS"
const RENDER_STRESS_OBJECTS := 18
const RENDER_STRESS_OBJECTS_ENV := "NIGHTWATCH_RENDER_STRESS_OBJECTS"

var game
var probe_seconds: float = PROBE_SECONDS
var render_stress_objects: int = RENDER_STRESS_OBJECTS
var frame_times: Array[float] = []
var cursor_distances: Array[float] = []
var second_start_usec: int = 0
var probe_start_usec: int = 0
var last_frame_usec: int = 0
var second_index: int = 0
var previous_cursor_position := Vector2.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	await process_frame
	probe_seconds = _probe_seconds_from_environment()
	render_stress_objects = _render_stress_objects_from_environment()
	# Keep the synthetic sky live for the entire measurement. The ordinary
	# opening round lasts 20 seconds and would otherwise turn the final samples
	# of this 24-second probe into a paused summary screen.
	game.observation_phase_duration = maxf(game.observation_phase_duration, probe_seconds + 1.0)
	game.observation_phase_remaining = game.observation_phase_duration
	game.spawner.set_phase_time_remaining(game.observation_phase_remaining)
	game.hud.set_observation_phase(1, game.observation_phase_remaining, game.observation_phase_duration)
	_prepare_render_stress()
	previous_cursor_position = root.get_mouse_position()
	probe_start_usec = Time.get_ticks_usec()
	second_start_usec = probe_start_usec
	last_frame_usec = probe_start_usec
	print("FRAME_PROBE_ENV engine=%s viewport=%s window=%s refresh_hz=%.2f mode=%d vsync=%d renderer=%s duration_seconds=%.2f stress_objects=%d observation_window_seconds=%.2f isolated=true" % [
		Engine.get_version_info(),
		root.get_visible_rect().size,
		DisplayServer.window_get_size(),
		DisplayServer.screen_get_refresh_rate(),
		DisplayServer.window_get_mode(),
		DisplayServer.window_get_vsync_mode(),
		RenderingServer.get_current_rendering_method(),
		probe_seconds,
		render_stress_objects,
		game.observation_phase_duration,
	])
	print("FRAME_PROBE_READY: keep still during seconds 1-7 and 19-24; move rapidly during seconds 8-18")
	while float(Time.get_ticks_usec() - probe_start_usec) / 1000000.0 < probe_seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last_frame_usec) / 1000.0)
		var cursor_position := root.get_mouse_position()
		cursor_distances.append(cursor_position.distance_to(previous_cursor_position))
		previous_cursor_position = cursor_position
		last_frame_usec = now
		if now - second_start_usec >= 1000000:
			_print_second_stats()
			second_start_usec = now
	game.queue_free()
	await process_frame
	print("FRAME_PROBE_COMPLETE")
	quit(0)


func _probe_seconds_from_environment() -> float:
	if not OS.has_environment(PROBE_SECONDS_ENV):
		return PROBE_SECONDS
	var configured := OS.get_environment(PROBE_SECONDS_ENV).strip_edges()
	if not configured.is_valid_float():
		push_warning("Ignoring invalid %s=%s" % [PROBE_SECONDS_ENV, configured])
		return PROBE_SECONDS
	var seconds := configured.to_float()
	if seconds <= 0.0:
		push_warning("Ignoring non-positive %s=%s" % [PROBE_SECONDS_ENV, configured])
		return PROBE_SECONDS
	return seconds


func _prepare_render_stress() -> void:
	game.spawner.pause_regular_spawns = true
	var viewport_size := root.get_visible_rect().size
	# Keep the documented 18/32-object fixture independent of the safety budget.
	var regular_objects := mini(render_stress_objects, 31)
	var columns := 6
	var rows := maxi(1, int(ceil(float(regular_objects) / float(columns))))
	for index in range(regular_objects):
		var type_id := "fireball" if index % 7 == 0 else ("fragment" if index % 4 == 0 else "common")
		var start := Vector2(
			80.0 + float(index % 6) * (viewport_size.x - 160.0) / 5.0,
			viewport_size.y * 0.14 + float(index / columns) * viewport_size.y * 0.72 / maxf(1.0, float(rows - 1))
		)
		var direction := Vector2.from_angle(-0.35 + float(index % 5) * 0.16)
		var meteor = game.spawner.spawn_meteor(type_id, start, direction * 18.0, 40.0)
		meteor.trail_points.clear()
		for trail_index in range(meteor.max_trail_points):
			meteor.trail_points.append(start - direction * float(trail_index) * 7.0)
	if render_stress_objects >= 32:
		game.spawner.spawn_major_fireball()


func _render_stress_objects_from_environment() -> int:
	if not OS.has_environment(RENDER_STRESS_OBJECTS_ENV):
		return RENDER_STRESS_OBJECTS
	var configured := OS.get_environment(RENDER_STRESS_OBJECTS_ENV).strip_edges()
	if not configured.is_valid_int():
		push_warning("Ignoring invalid %s=%s" % [RENDER_STRESS_OBJECTS_ENV, configured])
		return RENDER_STRESS_OBJECTS
	return clampi(configured.to_int(), 1, 32)


func _print_second_stats() -> void:
	if frame_times.is_empty():
		return
	second_index += 1
	var sorted_times: Array[float] = frame_times.duplicate()
	sorted_times.sort()
	var total := 0.0
	var cursor_total := 0.0
	var maximum := 0.0
	for index in range(frame_times.size()):
		var milliseconds := frame_times[index]
		total += milliseconds
		cursor_total += cursor_distances[index]
		maximum = maxf(maximum, milliseconds)
	var average := total / float(frame_times.size())
	var p50 := _percentile(sorted_times, 0.50)
	var p95 := _percentile(sorted_times, 0.95)
	var p99 := _percentile(sorted_times, 0.99)
	var over_1_5x := 0
	var over_2x := 0
	var over_3x := 0
	for milliseconds in frame_times:
		if milliseconds >= p50 * 1.5:
			over_1_5x += 1
		if milliseconds >= p50 * 2.0:
			over_2x += 1
		if milliseconds >= p50 * 3.0:
			over_3x += 1
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("FRAME_PROBE second=%02d avg_ms=%.2f p50=%.2f p95=%.2f p99=%.2f max_ms=%.2f over1.5x=%d over2x=%d over3x=%d cursor_px=%.1f frames=%d draw_calls=%d primitives=%d" % [
		second_index, average, p50, p95, p99, maximum, over_1_5x, over_2x, over_3x,
		cursor_total, frame_times.size(), draw_calls, primitives
	])
	frame_times.clear()
	cursor_distances.clear()


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]
