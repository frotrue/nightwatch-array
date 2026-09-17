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

func _project(point: Vector2, view: Dictionary) -> Vector2:
	return size * Vector2(0.5, 0.465) + (point - Vector2(view.camera_offset)).rotated(float(view.camera_roll)) * float(view.camera_zoom) * size.y

func _horizon_visibility(point: Vector2, view: Dictionary) -> float:
	var radius: float = view.horizon_radius
	return smoothstep(radius * 1.02, radius * 1.13, point.length())

func _draw() -> void:
	if controller == null or not controller.active: return
	var view: Dictionary = controller.visual_state()
	var center := size * Vector2(0.5, 0.465)
	var motion: float = controller.motion_scale
	var fall: float = float(view.collapse) * motion
	var reveal := smoothstep(0.18, 0.72, float(view.charge))
	var fade: float = (1.0 - float(view.blackout)) * (1.0 - smoothstep(0.45, 0.80, float(view.collapse)))
	var opacity := reveal * fade * 0.27
	for segment in chart_segments:
		if not chart_points.has(segment[0]) or not chart_points.has(segment[1]): continue
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for j in 9:
			var p: Vector2 = Vector2(chart_points[segment[0]]).lerp(chart_points[segment[1]], j / 8.0)
			p = _warped(p, fall)
			points.append(_project(p, view))
			colors.append(Color(0.67, 0.72, 0.80, opacity * _horizon_visibility(p, view)))
		draw_polyline_colors(points, colors, 0.75, true)
	for point: Vector2 in chart_points.values():
		var p := _warped(point, fall)
		draw_circle(_project(p, view), 1.45, Color(0.92, 0.91, 0.84, opacity * 1.5 * _horizon_visibility(p, view)), true, -1, true)
	# Perspective flight past fixed flecks provides depth as the observer falls in.
	# Different depths leave the viewport at different speeds; no random respawn.
	if motion > 0.0:
		var dive: float = view.camera_dive
		var flight_alpha := smoothstep(0.015, 0.5, float(view.camera_rush)) * (1.0 - float(view.blackout)) * (1.0 - float(view.camera_crossing))
		var shutter: Array[Dictionary] = []
		for j in 7: shutter.append(controller.visual_state(maxf(0.0, controller.phase_elapsed - j * 0.022)))
		var horizon_center := _project(Vector2.ZERO, view)
		var horizon_radius := float(view.horizon_radius) * float(view.camera_zoom) * size.y
		for mote in dust:
			if mote.z - dive * 0.6 <= 0.14: continue
			var tail := PackedVector2Array()
			var colors := PackedColorArray()
			for j in 7:
				var earlier: Dictionary = shutter[j]
				var p := Vector2(mote.x, mote.y) * 0.45 / (mote.z - float(earlier.camera_dive) * 0.6)
				var at := _project(p, earlier)
				tail.append(at)
				var visible := smoothstep(horizon_radius * 1.02, horizon_radius * 1.13, at.distance_to(horizon_center))
				colors.append(Color(0.68, 0.78, 0.98, flight_alpha * mote.z * (1.0 - j / 6.0) * visible))
			draw_polyline_colors(tail, colors, 0.65 + mote.z, true)
	if controller.phase == controller.Phase.OBSERVE:
		var ring_radius: float = controller.observation_radius()
		var ink := Color(0.88, 0.9, 0.93, 0.58 if controller.tracking else 0.16)
		draw_arc(center, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * controller.observation_progress, 100, ink, 1.15, true)
		for i in 5:
			var base := Vector2(size.x * (0.32 + i * 0.09), size.y * 0.78)
			var tip := base + (center - base).normalized() * 7.0
			draw_line(base, tip, Color(0.76, 0.56, 0.43, 0.55), 1.0, true)
			draw_line(tip, center + (tip - center).normalized() * ring_radius, Color(0.76, 0.56, 0.43, 0.05), 0.7, true)
