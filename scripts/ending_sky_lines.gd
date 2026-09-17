extends Control

# Catalogue geometry is copied for this transient effect. No research positions,
# topology or selection state are edited by the cinematic deformation.
var controller: Node
var chart_points: Dictionary = {}
var chart_segments: Array[PackedStringArray] = []
var dust: Array[Vector3] = []

func configure(ending: Node, chart: Node) -> void:
	controller = ending
	chart_points.clear()
	chart_segments.clear()
	var source: Dictionary = chart.expanded_star_positions
	var bounds := Rect2()
	var first := true
	for point: Vector2 in source.values():
		if first: bounds = Rect2(point, Vector2.ZERO); first = false
		else: bounds = bounds.expand(point)
	var unit := maxf(bounds.size.x / (16.0 / 9.0), bounds.size.y) / 0.88
	for key in source:
		chart_points[key] = (Vector2(source[key]) - bounds.get_center()) / maxf(unit, 1.0)
	for cid in chart.chart_constellations:
		for segment in chart.chart_constellations[cid].segments:
			chart_segments.append(PackedStringArray([cid + "/" + segment[0], cid + "/" + segment[1]]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 934781
	dust.clear()
	for i in 210:
		dust.append(Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(-0.62, 0.62), rng.randf_range(0.25, 1.0)))

func _warped(point: Vector2, amount: float) -> Vector2:
	var distance := point.length()
	var turn := amount * (1.1 + 0.9 / (0.28 + distance))
	return point.rotated(turn) * pow(maxf(0.025, 1.0 - amount), 0.65 + distance * 0.15)

func _draw() -> void:
	if controller == null or not controller.active: return
	var view: Dictionary = controller.visual_state()
	var center := size * Vector2(0.5, 0.465)
	var motion: float = controller.motion_scale
	var fall: float = float(view.collapse) * motion
	var presence: float = view.presence
	var reveal := smoothstep(0.18, 0.72, float(view.charge))
	var fade: float = (1.0 - float(view.blackout)) * (1.0 - smoothstep(0.45, 0.80, float(view.collapse)))
	var opacity := reveal * fade * 0.27
	for segment in chart_segments:
		if not chart_points.has(segment[0]) or not chart_points.has(segment[1]): continue
		var points := PackedVector2Array()
		for j in 9:
			var p: Vector2 = Vector2(chart_points[segment[0]]).lerp(chart_points[segment[1]], j / 8.0)
			points.append(center + _warped(p, fall) * size.y)
		draw_polyline(points, Color(0.67, 0.72, 0.80, opacity), 0.75, true)
	for point: Vector2 in chart_points.values():
		var at := center + _warped(point, fall) * size.y
		draw_circle(at, 1.45, Color(0.92, 0.91, 0.84, opacity * 1.5), true, -1, true)
	# Flecks join the background warp only during the final loss of the sky.
	if motion > 0.0:
		for mote in dust:
			var p := Vector2(mote.x, mote.y)
			var tail := PackedVector2Array()
			for j in 7:
				var amount := clampf(fall - j * 0.012 * presence, 0.0, 1.0)
				tail.append(center + _warped(p, amount) * size.y)
			draw_polyline(tail, Color(0.58, 0.69, 0.9, fall * fade * mote.z * 0.62), 0.65 + mote.z, true)
	if controller.phase == controller.Phase.OBSERVE:
		var ring_radius := size.y * 0.205
		var ink := Color(0.88, 0.9, 0.93, 0.58 if controller.tracking else 0.16)
		draw_arc(center, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * controller.observation_progress, 100, ink, 1.15, true)
		for i in 5:
			var base := Vector2(size.x * (0.32 + i * 0.09), size.y * 0.78)
			var tip := base + (center - base).normalized() * 7.0
			draw_line(base, tip, Color(0.76, 0.56, 0.43, 0.55), 1.0, true)
			draw_line(tip, center + (tip - center).normalized() * ring_radius, Color(0.76, 0.56, 0.43, 0.05), 0.7, true)
