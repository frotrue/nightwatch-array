extends Control

# Catalogue geometry is copied for this transient effect. No research positions,
# topology or selection state are edited by the cinematic deformation.
var controller: Node
var chart_points: Dictionary = {}
var chart_segments: Array[PackedStringArray] = []
var star_tracks: Dictionary = {}
var dust: Array[Vector3] = []

func configure(ending: Node, chart: Node) -> void:
	controller = ending
	chart_points.clear()
	chart_segments.clear()
	star_tracks.clear()
	var source: Dictionary = chart.expanded_star_positions
	var bounds := Rect2()
	var first := true
	for point: Vector2 in source.values():
		if first: bounds = Rect2(point, Vector2.ZERO); first = false
		else: bounds = bounds.expand(point)
	var unit := maxf(bounds.size.x / (16.0 / 9.0), bounds.size.y) / 0.95
	for key in source:
		chart_points[key] = (Vector2(source[key]) - bounds.get_center()) / maxf(unit, 1.0)
	for cid in chart.chart_constellations:
		for segment in chart.chart_constellations[cid].segments:
			chart_segments.append(PackedStringArray([cid + "/" + segment[0], cid + "/" + segment[1]]))
	# Inner stars lose their connections first. Every retained catalogue point has
	# its own release time; drawing this copy never changes the research chart.
	var order: Array = chart_points.keys()
	order.sort_custom(func(a, b): return Vector2(chart_points[a]).length_squared() < Vector2(chart_points[b]).length_squared())
	for i in order.size():
		var seed_value := float(posmod(hash(order[i]), 1000)) / 999.0
		star_tracks[order[i]] = {"release": 1.0 + i * 16.0 / maxf(order.size() - 1, 1.0), "join": 1.35 + seed_value * 0.65, "orbit": 2.8 + seed_value * 0.7, "lane": 2.15 + seed_value * 0.45}
	var rng := RandomNumberGenerator.new()
	rng.seed = 934781
	dust.clear()
	for i in 210:
		dust.append(Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(-0.62, 0.62), rng.randf_range(0.25, 1.0)))

func star_pose(key: String, time: float, view: Dictionary) -> Vector3:
	var origin: Vector2 = chart_points[key]
	var track: Dictionary = star_tracks[key]
	var age: float = time - track.release
	if age <= 0.0 or controller.motion_scale == 0.0: return Vector3(origin.x, origin.y, 0.0)
	var local := origin.rotated(-float(view.disc_tilt)) * Vector2(1.0, view.disc_flatten)
	var angle := local.angle()
	var radius: float = view.horizon_radius * track.lane
	var entry := Vector2(cos(angle), sin(angle) / float(view.disc_flatten)) * radius
	entry = entry.rotated(float(view.disc_tilt))
	var point: Vector2
	var joined := 0.0
	if age < float(track.join):
		var t := pow(age / float(track.join), 1.6)
		var tangent := Vector2(-sin(angle), cos(angle) / float(view.disc_flatten)).rotated(float(view.disc_tilt)) * radius
		var control_a := origin.lerp(entry, 0.16)
		var control_b := entry - tangent * 0.8
		point = origin * pow(1.0 - t, 3.0) + control_a * 3.0 * pow(1.0 - t, 2.0) * t + control_b * 3.0 * (1.0 - t) * t * t + entry * t * t * t
		joined = smoothstep(0.6, 1.0, t)
	else:
		var t := clampf((age - float(track.join)) / float(track.orbit), 0.0, 1.0)
		var spin: float = controller.disc_rotation(time) - controller.disc_rotation(float(track.release) + float(track.join))
		angle += spin + pow(t, 1.7) * TAU * 0.8
		radius *= lerpf(1.0, 0.32, pow(t, 1.25))
		point = Vector2(cos(angle), sin(angle) / float(view.disc_flatten)).rotated(float(view.disc_tilt)) * radius
		joined = 1.0
	point = origin.lerp(point, controller.motion_scale)
	return Vector3(point.x, point.y, joined * controller.motion_scale)

func star_alpha(key: String, time: float) -> float:
	if controller.motion_scale == 0.0: return 1.0 - smoothstep(6.0, 22.0, time)
	var track: Dictionary = star_tracks[key]
	var orbit_age: float = (time - track.release - track.join) / track.orbit
	return 1.0 - smoothstep(0.78, 1.0, orbit_age)

func _star_visibility(pose: Vector3, view: Dictionary) -> float:
	var point := Vector2(pose.x, pose.y)
	# Joined stars pass in front of the core on the near side, just like the gas.
	var front := smoothstep(-0.008, 0.024, point.rotated(-float(view.disc_tilt)).y)
	return maxf(_horizon_visibility(point, view), front * pose.z)

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
	_draw_chart(view)
	# Perspective flight past fixed flecks provides depth as the observer falls in.
	# Different depths leave the viewport at different speeds; no random respawn.
	if motion > 0.0 and float(view.camera_rush) > 0.015:
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

func _draw_chart(view: Dictionary) -> void:
	var reveal := smoothstep(0.10, 0.55, float(view.charge))
	var fade := (1.0 - float(view.blackout)) * (1.0 - float(view.camera_crossing))
	var time: float = controller.collapse_time()
	var opacity := reveal * fade
	if opacity <= 0.0: return
	for segment in chart_segments:
		if not chart_points.has(segment[0]) or not chart_points.has(segment[1]): continue
		var first_release := minf(star_tracks[segment[0]].release, star_tracks[segment[1]].release)
		var connection := 1.0 - smoothstep(0.0, 0.75, time - first_release)
		if controller.motion_scale == 0.0: connection = star_alpha(segment[0], time)
		if connection <= 0.0: continue
		var from := star_pose(segment[0], time, view)
		var to := star_pose(segment[1], time, view)
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for j in 9:
			var p := Vector2(from.x, from.y).lerp(Vector2(to.x, to.y), j / 8.0)
			points.append(_project(p, view))
			colors.append(Color(0.67, 0.72, 0.80, opacity * connection * 0.28 * _horizon_visibility(p, view)))
		draw_polyline_colors(points, colors, 0.75, true)
	for key: String in chart_points:
		var alpha := opacity * star_alpha(key, time) * _horizon_visibility(chart_points[key], view)
		if alpha <= 0.0: continue
		var pose := star_pose(key, time, view)
		var track: Dictionary = star_tracks[key]
		var detached: float = smoothstep(0.0, 0.65, time - float(track.release)) * controller.motion_scale
		var tone := Color(0.86, 0.90, 0.99).lerp(Color(1.0, 0.76, 0.44), detached)
		if detached > 0.0:
			var tail := PackedVector2Array()
			var colors := PackedColorArray()
			for j in 10:
				var earlier := star_pose(key, maxf(0.0, time - j * 0.055), view)
				tail.append(_project(Vector2(earlier.x, earlier.y), view))
				colors.append(Color(tone, alpha * detached * (1.0 - j / 9.0) * _star_visibility(earlier, view) * 0.8))
			draw_polyline_colors(tail, colors, 1.15, true)
		var at := _project(Vector2(pose.x, pose.y), view)
		alpha *= _star_visibility(pose, view)
		draw_circle(at, 3.8, Color(tone, alpha * (0.10 + detached * 0.15)), true, -1, true)
		draw_circle(at, 1.45 + detached * 0.45, Color(tone, alpha * 0.90), true, -1, true)
