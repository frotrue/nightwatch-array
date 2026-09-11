extends SceneTree
# Independent fan oracle frozen from 5c1294e; shrinking/reused arrays and byte equality.
class Base:
	extends "res://scripts/meteor.gd"
	func _draw_graded_polygon(
		points: PackedVector2Array,
		bright_point: Vector2,
		centre_color: Color,
		rim_color: Color
	) -> void:
		# A flat fill ends the head on a hard outline, and a hard outline over a
		# narrow tail is what reads as a bulb tied to a thread. A fan from an
		# interior point keeps the organic silhouette and lets its edge fall off,
		# so the head dissolves into the trail instead of sitting on top of it.
		var count := points.size()
		if count < 3:
			return
		var vertices := PackedVector2Array()
		var colors := PackedColorArray()
		vertices.append(bright_point)
		colors.append(centre_color)
		for index in range(count):
			vertices.append(points[index])
			colors.append(rim_color)
		var indices := PackedInt32Array()
		for index in range(count):
			indices.append(0)
			indices.append(1 + index)
			indices.append(1 + (index + 1) % count)
		triangle_batch.append(indices, vertices, colors)

const Cached = preload("res://scripts/meteor.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var base = Base.new()
	var cached = Cached.new()
	var points := PackedVector2Array()
	var valid := true
	for count in [12, 16, 8, 12, 3, 2, 0, 12]:
		points.clear()
		for i in count: points.append(Vector2(cos(float(i)), sin(float(i))) * 10)
		for target in [base, cached]:
			target.triangle_batch.begin()
			for part in 3: target._draw_graded_polygon(points, Vector2(1,2), Color(0.4,0.7,0.8,0.9), Color(0.2,0.3,0.8,0))
		valid = valid and base.triangle_batch.vertices.to_byte_array() == cached.triangle_batch.vertices.to_byte_array() and base.triangle_batch.colors.to_byte_array() == cached.triangle_batch.colors.to_byte_array() and base.triangle_batch.indices.to_byte_array() == cached.triangle_batch.indices.to_byte_array()
	var results := {"before":[], "after":[]}
	for sample in (6 if OS.get_environment("NIGHTWATCH_FAN_BENCH") == "1" else 0):
		var order := [base, cached] if sample % 2 == 0 else [cached, base]
		for target in order:
			var began := Time.get_ticks_usec()
			for iteration in 10000:
				target.triangle_batch.begin()
				for part in 3: target._draw_graded_polygon(points, Vector2(1,2), Color(0.4,0.7,0.8,0.9), Color(0.2,0.3,0.8,0))
			results["before" if target == base else "after"].append((Time.get_ticks_usec() - began) / 10000.0)
	print("FAN_CACHE_RESULT ", JSON.stringify(results), " bytes_equal=",valid)
	base.free()
	cached.free()
	print("METEOR_FAN_CACHE_PASS" if valid else "METEOR_FAN_CACHE_FAIL")
	quit(0 if valid else 1)
