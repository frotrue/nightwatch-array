extends RefCounted

# The authored 36 x 16 faceted surface is static. Keep its original cell edges,
# triangulation and flat colors in one cached triangle array instead of recreating 576
# canvas polygons on every simulation update. Halo/rim remain native canvas art.
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var revision := 0
var alpha := -1.0
var radius := -1.0
var primary := Color.TRANSPARENT
var glow := Color.TRANSPARENT

func _prepare(requested_radius: float, requested_primary: Color, requested_glow: Color) -> void:
	if not vertices.is_empty() and radius == requested_radius and primary == requested_primary and glow == requested_glow:
		return
	radius = requested_radius
	primary = requested_primary
	glow = requested_glow
	vertices.clear()
	colors.clear()
	indices.clear()
	revision += 1
	alpha = 1.0
	var bands := 36
	for index in range(bands):
		var y0 := -1.0 + 2.0 * float(index) / float(bands)
		var y1 := -1.0 + 2.0 * float(index + 1) / float(bands)
		var y := (y0 + y1) * 0.5
		var width0 := sqrt(maxf(0.0, 1.0 - y0 * y0))
		var width1 := sqrt(maxf(0.0, 1.0 - y1 * y1))
		var band := 0.48 + 0.12 * sin(y * 22.0 + 0.7 * sin(y * 9.0))
		for column in range(16):
			var x0 := -1.0 + float(column) / 8.0
			var x1 := -1.0 + float(column + 1) / 8.0
			var x := (x0 + x1) * 0.5
			var lighting := clampf(0.38 + 0.58 * sqrt(maxf(0.0, 1.0 - x * x - y * y * 0.35)) - x * 0.35 - y * 0.17, 0.13, 1.0)
			var color := primary.darkened(1.0 - band * lighting)
			if index % 9 in [3, 4]: color = glow.darkened(1.0 - lighting * 0.78)
			var points := PackedVector2Array([
				Vector2(x0 * width0, y0) * radius, Vector2(x1 * width0, y0) * radius,
				Vector2(x1 * width1, y1) * radius, Vector2(x0 * width1, y1) * radius])
			var cell := Geometry2D.triangulate_polygon(points)
			var offset := vertices.size()
			for vertex in cell: indices.append(offset + vertex)
			vertices.append_array(points)
			for vertex in points.size(): colors.append(Color(color, 1.0))

func draw(canvas: Node2D, requested_radius: float, requested_primary: Color, requested_glow: Color, visibility: float) -> void:
	_prepare(requested_radius, requested_primary, requested_glow)
	if alpha != visibility:
		for i in colors.size():
			var color := colors[i]
			color.a = visibility
			colors[i] = color
		alpha = visibility
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, colors)
