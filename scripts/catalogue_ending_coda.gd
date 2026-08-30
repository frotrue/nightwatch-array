extends Control

# Read-only replay of the completed chart. All Local Group decorations join the
# ending, but never become research, purchase targets, or save-state entries.
const ChartData = preload("res://scripts/research_chart_data.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const MAP_OUTER_RADIUS := 548.0
const CORE_RADIUS := 104.0
const DISK_TILT := 0.52
const ROUTE_SAMPLES := 12

var constellation_progress: float = 0.0:
	set(value):
		constellation_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var pullback_progress: float = 0.0:
	set(value):
		pullback_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var route_progress: float = 0.0:
	set(value):
		route_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var illumination_progress: float = 0.0:
	set(value):
		illumination_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var settle_progress: float = 0.0:
	set(value):
		settle_progress = clampf(value, 0.0, 1.0)
		queue_redraw()

var constellation_figures: Array[Dictionary] = []
var chart_star_offsets: Dictionary = {}
var chart_max_radius: float = 1.0
var galaxy_node_ids: Array[String] = []
var galaxy_positions: Dictionary = {}
var galaxy_codes: Array[String] = []
var galaxy_route_points := PackedVector2Array()
var route_lengths := PackedFloat32Array()
var galaxy_arrivals := PackedFloat32Array()
var route_total_length: float = 0.0
var background_stars: Array[Vector3] = []
var unit_ring := PackedVector2Array()
var glow_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_chart_geometry()
	_cache_decoration()
	resized.connect(queue_redraw)
	set_process(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func reset_animation() -> void:
	constellation_progress = 0.0
	pullback_progress = 0.0
	route_progress = 0.0
	illumination_progress = 0.0
	settle_progress = 0.0
	visible = true
	set_process(true)


func complete_animation() -> void:
	constellation_progress = 1.0
	pullback_progress = 1.0
	route_progress = 1.0
	illumination_progress = 1.0
	settle_progress = 1.0
	set_process(false)
	queue_redraw()


func _cache_chart_geometry() -> void:
	constellation_figures.clear()
	chart_star_offsets.clear()
	chart_max_radius = 1.0
	for record in ChartData.chart_offsets():
		var key := "%s/%s" % [record.constellation_id, record.star_id]
		chart_star_offsets[key] = Vector2(record.offset)
		chart_max_radius = maxf(chart_max_radius, Vector2(record.offset).length())
	for constellation_id in ChartData.CONSTELLATIONS:
		var source: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var points := PackedVector2Array()
		var magnitudes := PackedFloat32Array()
		var indices := {}
		var edges: Array[Vector2i] = []
		for star in source.stars:
			indices[String(star.id)] = points.size()
			points.append(chart_star_offsets["%s/%s" % [constellation_id, star.id]])
			magnitudes.append(float(star.magnitude))
		for segment in source.segments:
			edges.append(Vector2i(indices[String(segment[0])], indices[String(segment[1])]))
		constellation_figures.append({"id": constellation_id, "points": points, "magnitudes": magnitudes, "edges": edges})

	galaxy_node_ids.assign(["galactic_reference_frame"])
	galaxy_codes.assign(["MILKY WAY"])
	galaxy_positions = ChartData.galactic_map_offsets()
	galaxy_positions["galactic_reference_frame"] = Vector2.ZERO
	var controls := PackedVector2Array([Vector2.ZERO])
	for galaxy in ChartData.LOCAL_GROUP_GALAXIES:
		var node_id := String(galaxy.node_id)
		galaxy_node_ids.append(node_id)
		galaxy_codes.append(String(galaxy.bayer))
		controls.append(galaxy_positions[node_id])
	_cache_galaxy_route(controls)


func _cache_galaxy_route(controls: PackedVector2Array) -> void:
	galaxy_route_points = PackedVector2Array([controls[0]])
	route_lengths = PackedFloat32Array([0.0])
	galaxy_arrivals = PackedFloat32Array([0.0])
	route_total_length = 0.0
	# Same Catmull-Rom geometry as the chart, with all astronomical records as
	# controls. This route is not the live functional prerequisite graph.
	for index in range(controls.size() - 1):
		var p0 := controls[maxi(0, index - 1)]
		var p1 := controls[index]
		var p2 := controls[index + 1]
		var p3 := controls[mini(controls.size() - 1, index + 2)]
		var c1 := p1 + (p2 - p0) / 6.0
		var c2 := p2 - (p3 - p1) / 6.0
		for sample_index in range(1, ROUTE_SAMPLES + 1):
			var t := float(sample_index) / float(ROUTE_SAMPLES)
			var u := 1.0 - t
			var point := p1 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p2 * t * t * t
			route_total_length += galaxy_route_points[-1].distance_to(point)
			galaxy_route_points.append(point)
			route_lengths.append(route_total_length)
		galaxy_arrivals.append(route_total_length)
	for index in range(galaxy_arrivals.size()):
		galaxy_arrivals[index] /= maxf(1.0, route_total_length)


func _cache_decoration() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4E49574854415443
	for _index in range(74):
		background_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.05, 0.25)))
	for index in range(97):
		unit_ring.append(Vector2.RIGHT.rotated(TAU * float(index) / 96.0))
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.42, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.36), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0)])
	glow_texture = GradientTexture2D.new()
	glow_texture.width = 128
	glow_texture.height = 128
	glow_texture.gradient = gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)


func constellation_light(index: int) -> float:
	return clampf(constellation_progress * float(constellation_figures.size()) - float(index), 0.0, 1.0)


func galaxy_light(index: int) -> float:
	if route_progress >= 1.0:
		return 1.0
	return smoothstep(galaxy_arrivals[index] - 0.008, galaxy_arrivals[index] + 0.018, route_progress)


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0 or glow_texture == null:
		return
	for star in background_stars:
		draw_circle(Vector2(star.x * size.x, star.y * size.y), 0.8, Color(0.73, 0.63, 0.60, star.z))
	var centre := Vector2(size.x * lerpf(0.5, 0.33, settle_progress), size.y * 0.49)
	var radius := lerpf(minf(size.x * 0.43, size.y * 0.55), minf(size.x * 0.285, size.y * 0.49), settle_progress)
	var map_scale := radius / MAP_OUTER_RADIUS
	_draw_galaxy_map(centre, map_scale)
	var chart_radius := lerpf(minf(size.x * 0.43, size.y * 0.40), CORE_RADIUS * map_scale, pullback_progress)
	_draw_constellations(centre, chart_radius)
	_draw_completion_wave(centre, radius)


func _draw_constellations(centre: Vector2, radius: float) -> void:
	var scale_amount := radius / chart_max_radius
	var point_scale := Vector2(scale_amount, scale_amount * lerpf(1.0, DISK_TILT, pullback_progress))
	for index in range(constellation_figures.size()):
		var figure: Dictionary = constellation_figures[index]
		var light := constellation_light(index)
		var points: PackedVector2Array = figure.points
		var edges: Array = figure.edges
		for edge_index in range(edges.size()):
			var edge: Vector2i = edges[edge_index]
			var start := centre + points[edge.x] * point_scale
			var finish := centre + points[edge.y] * point_scale
			draw_line(start, finish, Color(0.65, 0.28, 0.17, 0.10), 0.8, true)
			var traced := clampf(light * float(edges.size()) - float(edge_index), 0.0, 1.0)
			if traced > 0.0:
				var endpoint := start.lerp(finish, traced)
				draw_line(start, endpoint, Color(0.92, 0.32, 0.13, 0.10), lerpf(4.0, 2.0, pullback_progress), true)
				draw_line(start, endpoint, Color(1.0, 0.61, 0.35, 0.70), lerpf(1.1, 0.65, pullback_progress), true)
		for star_index in range(points.size()):
			var point := centre + points[star_index] * point_scale
			var alpha := 0.09 + smoothstep(0.0, 0.55, light) * 0.91
			var star_radius := clampf(2.7 - float(figure.magnitudes[star_index]) * 0.22, 1.2, 3.1) * lerpf(1.0, 0.43, pullback_progress)
			_draw_glow(point, Vector2.ONE * lerpf(13.0, 4.0, pullback_progress), alpha * 0.30)
			draw_circle(point, star_radius, Color(1.0, 0.78, 0.53, alpha))


func _draw_galaxy_map(centre: Vector2, map_scale: float) -> void:
	var presence := smoothstep(0.12, 0.72, pullback_progress)
	if presence <= 0.001:
		return
	_draw_glow(centre, Vector2(210.0, 108.0) * map_scale, presence * 0.28)
	draw_set_transform(centre, 0.0, Vector2.ONE * map_scale)
	draw_polyline(galaxy_route_points, Color(0.78, 0.30, 0.16, presence * 0.09), 0.7 / map_scale, true)
	var lit_route := _lit_route_points()
	if lit_route.size() > 1:
		draw_polyline(lit_route, Color(0.88, 0.22, 0.09, presence * 0.09), 7.0 / map_scale, true)
		draw_polyline(lit_route, Color(0.97, 0.40, 0.17, presence * 0.22), 3.0 / map_scale, true)
		draw_polyline(lit_route, Color(1.0, 0.64, 0.38, presence * 0.73), 1.0 / map_scale, true)
	draw_set_transform(Vector2.ZERO)
	var label_alpha := smoothstep(0.0, 0.8, settle_progress)
	for index in range(1, galaxy_node_ids.size()):
		var offset: Vector2 = galaxy_positions[galaxy_node_ids[index]] * map_scale
		var point := centre + offset
		var light := galaxy_light(index)
		var alpha := presence * (0.13 + 0.87 * light)
		var pulse := sin(PI * light)
		_draw_glow(point, Vector2(18.0, 11.0) * (1.0 + pulse * 0.8), light * presence * 0.75)
		var axis := Vector2(6.0, 0.0).rotated(-0.35 + float(index % 4) * 0.17)
		draw_line(point - axis, point + axis, Color(1.0, 0.64, 0.40, alpha * 0.7), 2.8, true)
		draw_line(point - axis * 0.82, point + axis * 0.82, Color(1.0, 0.87, 0.66, alpha), 1.0, true)
		draw_circle(point, 1.7 + pulse, Color(1.0, 0.84, 0.61, alpha))
		if label_alpha > 0.001:
			_draw_code(point, offset, galaxy_codes[index], label_alpha * light * 0.68)
	if label_alpha > 0.001:
		var code := tr("TREE_GALACTIC_REFERENCE_CODE")
		var font := UITheme.mono()
		var font_size := 10
		var width := font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, centre + Vector2(-width * 0.5, CORE_RADIUS * map_scale * DISK_TILT + 20.0), code, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.66, 0.41, label_alpha * 0.80))


func _lit_route_points() -> PackedVector2Array:
	if route_progress >= 1.0:
		return galaxy_route_points
	var result := PackedVector2Array([galaxy_route_points[0]])
	var target_length := route_progress * route_total_length
	for index in range(1, galaxy_route_points.size()):
		if route_lengths[index] <= target_length:
			result.append(galaxy_route_points[index])
			continue
		var segment_length := maxf(0.0001, route_lengths[index] - route_lengths[index - 1])
		result.append(galaxy_route_points[index - 1].lerp(galaxy_route_points[index], (target_length - route_lengths[index - 1]) / segment_length))
		break
	return result


func _draw_code(point: Vector2, offset: Vector2, code: String, alpha: float) -> void:
	var font := UITheme.mono()
	var font_size := 10
	var label_position := point + offset.normalized() * 11.0
	if offset.x < 0.0:
		label_position.x -= font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	label_position.y += 3.0
	draw_string(font, label_position, code, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.91, 0.69, 0.51, alpha))


func _draw_glow(point: Vector2, radii: Vector2, alpha: float) -> void:
	draw_texture_rect(glow_texture, Rect2(point - radii, radii * 2.0), false, Color(1.0, 0.43, 0.20, alpha))


func _draw_completion_wave(centre: Vector2, radius: float) -> void:
	if illumination_progress <= 0.0 or illumination_progress >= 1.0:
		return
	var wave_radius := radius * lerpf(0.05, 1.12, illumination_progress)
	var wave := PackedVector2Array()
	for point in unit_ring:
		wave.append(centre + point * Vector2(wave_radius, wave_radius * DISK_TILT))
	draw_polyline(wave, Color(1.0, 0.66, 0.38, sin(PI * illumination_progress) * 0.28), 1.4, true)
