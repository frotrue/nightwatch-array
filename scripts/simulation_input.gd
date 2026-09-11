extends RefCounted

# Timestamped screen-space input; rendering never consumes this queue.
const MAX_SAMPLES := 4096
var samples: Array[Dictionary] = []
var position := Vector2.ZERO
var held := false
var time := 0.0
var overflow_count := 0

func reset(point: Vector2, at_time: float = 0.0) -> void:
	samples.clear()
	position = point
	held = false
	time = at_time

func push(at_time: float, point: Vector2, pressed: bool, dish: bool = false) -> void:
	if samples.size() >= MAX_SAMPLES:
		overflow_count += 1
		reset(point, maxf(time, at_time))
		return
	var timestamp := maxf(time, at_time)
	if not samples.is_empty(): timestamp = maxf(timestamp, float(samples.back().time))
	samples.append({"time": timestamp, "position": point, "held": pressed, "dish": dish})

func consume(until: float) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	while not samples.is_empty() and float(samples[0].time) <= until:
		var sample: Dictionary = samples.pop_front()
		var duration := maxf(0.0, float(sample.time) - time)
		segments.append({"start": position, "end": sample.position, "duration": duration, "held": held, "dish": sample.dish})
		position = sample.position
		held = sample.held
		time = maxf(time, float(sample.time))
	if until > time:
		var endpoint := position
		# Motion samples span time; button changes take effect at their timestamp.
		if not samples.is_empty() and float(samples[0].time) > time:
			endpoint = position.lerp(samples[0].position, clampf((until - time) / (float(samples[0].time) - time), 0.0, 1.0))
		segments.append({"start": position, "end": endpoint, "duration": until - time, "held": held, "dish": false})
		position = endpoint
		time = until
	return segments
