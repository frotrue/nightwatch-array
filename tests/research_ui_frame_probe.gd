extends SceneTree

# Windowed frame-time probe for the research chart. The middle phase injects a
# burst of wheel events every rendered frame; the final phase exercises the
# cursor-following tooltip. This is a measurement probe, not a pass/fail gate.

const PHASE_SECONDS := 3.0
const WHEEL_EVENTS_PER_FRAME := 8

var game
var tree
var frame_times: Array[float] = []
var workload_times: Array[float] = []
var phase_start_usec: int = 0
var last_frame_usec: int = 0
var original_rotation: float = 0.0
var tooltip_motion_step: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	tree = game.upgrade_tree
	original_rotation = game.settings.get_research_chart_rotation()
	tree._reset_view(false)
	tree.open_tree()
	await process_frame
	await process_frame

	print("RESEARCH_UI_PROBE_ENV engine=%s renderer=%s viewport=%s window=%s refresh_hz=%.2f vsync=%d wheel_events_per_frame=%d phase_seconds=%.1f" % [
		Engine.get_version_info(),
		RenderingServer.get_current_rendering_method(),
		root.get_visible_rect().size,
		DisplayServer.window_get_size(),
		DisplayServer.screen_get_refresh_rate(),
		DisplayServer.window_get_vsync_mode(),
		WHEEL_EVENTS_PER_FRAME,
		PHASE_SECONDS,
	])
	await _measure_phase("idle", Callable())
	await _measure_phase("wheel_burst", _inject_wheel_burst)
	tree.tooltip_suppressed_until_motion = false
	tree._on_node_hovered("better_lens")
	await process_frame
	await process_frame
	await _measure_phase("tooltip_motion", _inject_tooltip_motion)

	# Wheel input mutates the in-memory setting without writing it until close.
	# Restore the player's value first so this measurement has no persistent side effect.
	tree.pending_rotation_delta = 0.0
	tree.rotation_offset = original_rotation
	tree.close_tree()
	game.queue_free()
	await process_frame
	print("RESEARCH_UI_PROBE_COMPLETE")
	quit(0)


func _measure_phase(label: String, workload: Callable) -> void:
	frame_times.clear()
	workload_times.clear()
	var layout_passes_before: int = tree.chart_layout_passes
	phase_start_usec = Time.get_ticks_usec()
	last_frame_usec = phase_start_usec
	while float(Time.get_ticks_usec() - phase_start_usec) / 1000000.0 < PHASE_SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last_frame_usec) / 1000.0)
		last_frame_usec = now
		if workload.is_valid():
			var workload_start := Time.get_ticks_usec()
			workload.call()
			workload_times.append(float(Time.get_ticks_usec() - workload_start) / 1000.0)
	# The process-frame signal resumes before node _process callbacks. Commit the
	# final queued wheel burst here so it is attributed to this phase, not the next.
	tree._flush_pending_rotation()
	_print_stats(label, tree.chart_layout_passes - layout_passes_before)


func _inject_wheel_burst() -> void:
	for _index in range(WHEEL_EVENTS_PER_FRAME):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		tree._on_tree_viewport_gui_input(wheel)


func _inject_tooltip_motion() -> void:
	# Calling _input() alone would still read the host's stationary mouse. Alternate
	# concrete overlay-local points so the measured Control actually moves.
	tooltip_motion_step += 1
	var direction := -1.0 if tooltip_motion_step % 2 == 0 else 1.0
	tree._position_node_tooltip(Vector2(576.0 + direction * 96.0, 324.0 + direction * 48.0))


func _print_stats(label: String, layout_passes: int) -> void:
	var sorted_times: Array[float] = frame_times.duplicate()
	sorted_times.sort()
	var sorted_workload_times: Array[float] = workload_times.duplicate()
	sorted_workload_times.sort()
	var total := 0.0
	var maximum := 0.0
	for milliseconds in frame_times:
		total += milliseconds
		maximum = maxf(maximum, milliseconds)
	var average := total / maxf(1.0, float(frame_times.size()))
	var workload_total := 0.0
	var workload_maximum := 0.0
	for milliseconds in workload_times:
		workload_total += milliseconds
		workload_maximum = maxf(workload_maximum, milliseconds)
	var workload_average := workload_total / maxf(1.0, float(workload_times.size()))
	print("RESEARCH_UI_PROBE phase=%s avg_ms=%.2f p50=%.2f p95=%.2f p99=%.2f max_ms=%.2f work_avg_ms=%.3f work_p95_ms=%.3f work_max_ms=%.3f frames=%d layout_passes=%d draw_calls=%d primitives=%d" % [
		label,
		average,
		_percentile(sorted_times, 0.50),
		_percentile(sorted_times, 0.95),
		_percentile(sorted_times, 0.99),
		maximum,
		workload_average,
		_percentile(sorted_workload_times, 0.95),
		workload_maximum,
		frame_times.size(),
		layout_passes,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]
