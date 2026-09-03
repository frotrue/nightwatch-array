extends SceneTree

# Windowed frame-time probe for the research chart. It covers normal idle,
# coalesced wheel bursts, fixed-inspector selection, the Galactic Reference
# Frame pull-back, and its static final frame. This remains a measurement probe,
# not a pass/fail gate; the documented candidate acceptance is p95 < 16.7 ms.

const PHASE_SECONDS := 3.0
const PULLBACK_MEASURE_SECONDS := 3.8
const WHEEL_EVENTS_PER_FRAME := 8
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")

var game
var tree
var frame_times: Array[float] = []
var workload_times: Array[float] = []
var phase_start_usec: int = 0
var last_frame_usec: int = 0
var selection_step: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	# This is a scripted workload; live mouse input must not alter the sample.
	root.gui_disable_input = true
	_disable_hardware_input(game)
	await process_frame
	await process_frame
	tree = game.upgrade_tree
	tree._reset_view(false)
	tree.open_tree()
	await process_frame
	await process_frame

	var galactic_research_nodes := 0
	for definition in Balance.UPGRADE_NODES:
		if String(definition.branch) == "local_group":
			galactic_research_nodes += 1
	print("RESEARCH_UI_PROBE_ENV engine=%s renderer=%s display=%s viewport=%s window=%s refresh_hz=%.2f vsync=%d wheel_events_per_frame=%d phase_seconds=%.1f galactic_research_nodes=%d galactic_decorations=%d background_points=%d pullback_seconds=%.1f target_p95_ms=16.7 isolated=true input=scripted" % [
		Engine.get_version_info(),
		RenderingServer.get_current_rendering_method(),
		DisplayServer.get_name(),
		root.get_visible_rect().size,
		DisplayServer.window_get_size(),
		DisplayServer.screen_get_refresh_rate(),
		DisplayServer.window_get_vsync_mode(),
		WHEEL_EVENTS_PER_FRAME,
		PHASE_SECONDS,
		galactic_research_nodes,
		int(tree.ChartData.LOCAL_GROUP_GALAXIES.size()) - galactic_research_nodes,
		int(tree.galactic_background_stars.size()),
		float(tree.PULLBACK_DURATION),
	])
	await _measure_phase("idle", Callable())
	await _measure_phase("wheel_burst", _inject_wheel_burst)
	tree._reset_view(false)
	tree.tooltip_suppressed_until_motion = false
	_select_probe_node("better_lens")
	await process_frame
	await process_frame
	await _measure_phase("inspector_selection", _inject_inspector_selection)
	tree._on_node_unhovered(tree.hovered_node_id)
	tree._hide_node_tooltip()
	game.progression.debug_purchase_all()
	await _measure_phase("galactic_transition", Callable(), PULLBACK_MEASURE_SECONDS)
	await _measure_phase("galactic_final", Callable())

	tree.close_tree()
	game.queue_free()
	await process_frame
	print("RESEARCH_UI_PROBE_COMPLETE")
	quit(0)


func _measure_phase(label: String, workload: Callable, duration: float = PHASE_SECONDS) -> void:
	frame_times.clear()
	workload_times.clear()
	var layout_passes_before: int = tree.chart_layout_passes
	var inspector_refreshes_before: int = tree.tooltip_content_refreshes
	phase_start_usec = Time.get_ticks_usec()
	last_frame_usec = phase_start_usec
	while float(Time.get_ticks_usec() - phase_start_usec) / 1000000.0 < duration:
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
	_print_stats(label, tree.chart_layout_passes - layout_passes_before, tree.tooltip_content_refreshes - inspector_refreshes_before)


func _inject_wheel_burst() -> void:
	for _index in range(WHEEL_EVENTS_PER_FRAME):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		tree._on_tree_viewport_gui_input(wheel)


func _inject_inspector_selection() -> void:
	# The inspector is fixed now; moving a legacy tooltip position measures no
	# meaningful UI work. Exercise the real selection/description refresh instead.
	selection_step += 1
	_select_probe_node("better_lens" if selection_step % 2 == 0 else "long_exposure")


func _select_probe_node(node_id: String) -> void:
	# Mirror the old target's exit before the new target's enter, so two markers
	# cannot remain highlighted during a one-cursor workload.
	if not tree.hovered_node_id.is_empty():
		tree._on_node_unhovered(tree.hovered_node_id)
	tree._on_node_hovered(node_id)


func _disable_hardware_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		_disable_hardware_input(child)


func _print_stats(label: String, layout_passes: int, inspector_refreshes: int) -> void:
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
	print("RESEARCH_UI_PROBE phase=%s avg_ms=%.2f p50=%.2f p95=%.2f p99=%.2f max_ms=%.2f work_avg_ms=%.3f work_p95_ms=%.3f work_max_ms=%.3f frames=%d layout_passes=%d inspector_refreshes=%d draw_calls=%d primitives=%d" % [
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
		inspector_refreshes,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]
