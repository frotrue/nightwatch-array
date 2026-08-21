extends SceneTree

const PROBE_SECONDS := 8.0
const PROBE_SECONDS_ENV := "NIGHTWATCH_PROBE_SECONDS"
const FINISHED_ENV := "NIGHTWATCH_PROBE_FINISHED"

var frame_times: Array[float] = []
var probe_seconds: float = PROBE_SECONDS
var probe_start_usec: int = 0
var second_start_usec: int = 0
var last_frame_usec: int = 0
var second_index: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/probe_layer2.tscn")
	var probe = packed.instantiate()
	root.add_child(probe)
	await process_frame
	await process_frame
	var finished_mode := OS.get_environment(FINISHED_ENV) == "1"
	if finished_mode:
		probe._finish()
	else:
		# Exercise the densest wave without waiting a full minute for it.
		probe.elapsed = 61.0
		probe.next_signal_in = 0.1
	probe_seconds = _probe_seconds_from_environment()
	probe_start_usec = Time.get_ticks_usec()
	second_start_usec = probe_start_usec
	last_frame_usec = probe_start_usec
	print("LAYER2_FRAME_PROBE_ENV engine=%s renderer=%s duration_seconds=%.2f finished=%s" % [
		Engine.get_version_info(),
		RenderingServer.get_current_rendering_method(),
		probe_seconds,
		finished_mode,
	])
	while float(Time.get_ticks_usec() - probe_start_usec) / 1000000.0 < probe_seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - last_frame_usec) / 1000.0)
		last_frame_usec = now
		if now - second_start_usec >= 1000000:
			_print_second_stats(probe)
			second_start_usec = now
	probe.queue_free()
	await process_frame
	print("LAYER2_FRAME_PROBE_COMPLETE")
	quit(0)


func _probe_seconds_from_environment() -> float:
	if not OS.has_environment(PROBE_SECONDS_ENV):
		return PROBE_SECONDS
	var configured := OS.get_environment(PROBE_SECONDS_ENV).strip_edges()
	if not configured.is_valid_float():
		return PROBE_SECONDS
	return maxf(0.1, configured.to_float())


func _print_second_stats(probe) -> void:
	if frame_times.is_empty():
		return
	second_index += 1
	var sorted_times: Array[float] = frame_times.duplicate()
	sorted_times.sort()
	var total := 0.0
	var maximum := 0.0
	for milliseconds in frame_times:
		total += milliseconds
		maximum = maxf(maximum, milliseconds)
	var average := total / float(frame_times.size())
	var p95 := _percentile(sorted_times, 0.95)
	var p99 := _percentile(sorted_times, 0.99)
	print("LAYER2_FRAME_PROBE second=%02d avg_ms=%.2f p95=%.2f p99=%.2f max_ms=%.2f frames=%d signals=%d meteors=%d draw_calls=%d primitives=%d process_ms=%.3f" % [
		second_index,
		average,
		p95,
		p99,
		maximum,
		frame_times.size(),
		probe.signals.size(),
		probe.meteor_layer.get_child_count(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
	])
	frame_times.clear()


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]
