extends RefCounted

# Pure numerical kernel. Each job returns its own output arrays; snapshots are
# immutable until all jobs finish. Target order and input segment order survive.
static func calculate(first: int, last: int, targets: Array, segments: Array, linear: bool) -> Array:
	var output: Array = []
	for index in range(first, last):
		var target: Dictionary = targets[index]
		var values := PackedFloat64Array()
		values.resize(segments.size() * 3)
		values.fill(-1.0)
		var radius: float = target.radius
		var extent: Vector2 = target.extent
		for segment_index in segments.size():
			var segment: Dictionary = segments[segment_index]
			if not segment.held: continue
			var start: Vector2 = segment.start - position_at(target, segment.first)
			var motion: Vector2 = segment.end - position_at(target, segment.last) - start
			var interval := rectangle_interval(start, motion, extent) if linear else circle_interval(start, motion, radius)
			if interval.x < 0.0 or interval.y <= interval.x: continue
			var fraction := (interval.x + interval.y) * 0.5
			var relative: Vector2 = Vector2(segment.start).lerp(segment.end, fraction) - position_at(target, lerpf(segment.first, segment.last, fraction))
			var distance := relative.length()
			if linear: distance = maxf(absf(relative.x) / extent.x, absf(relative.y) / extent.y) * radius
			var offset := segment_index * 3
			values[offset] = interval.x
			values[offset + 1] = interval.y
			values[offset + 2] = distance
		output.append(values)
	return output


static func position_at(target: Dictionary, fraction: float) -> Vector2:
	var start: Vector2 = target.previous
	var end: Vector2 = target.current
	return Vector2(lerpf(start.x, end.x, fraction), lerpf(start.y, end.y, fraction))


static func circle_interval(start: Vector2, motion: Vector2, radius: float) -> Vector2:
	var a := motion.length_squared()
	if a < 0.000001: return Vector2(0, 1) if start.length_squared() <= radius * radius else Vector2(-1, -1)
	var b := 2.0 * start.dot(motion)
	var c := start.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0: return Vector2(-1, -1)
	var enter := maxf(0.0, (-b - sqrt(discriminant)) / (2.0 * a))
	var leave := minf(1.0, (-b + sqrt(discriminant)) / (2.0 * a))
	return Vector2(enter, leave) if leave > enter else Vector2(-1, -1)


static func rectangle_interval(start: Vector2, motion: Vector2, extent: Vector2) -> Vector2:
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if absf(motion[axis]) < 0.00001:
			if absf(start[axis]) > extent[axis]: return Vector2(-1, -1)
		else:
			var first: float = (-extent[axis] - start[axis]) / motion[axis]
			var last: float = (extent[axis] - start[axis]) / motion[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter > leave: return Vector2(-1, -1)
	return Vector2(enter, leave)
