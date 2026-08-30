extends Control

# A procedural ending plate. It deliberately reuses the observatory's red-light
# vocabulary instead of introducing a separate illustrated cutscene asset.
const STAR_COUNT := 58
const GALACTIC_RING_COUNT := 5
const ROUTE_POINTS := [
	Vector2(0.50, 0.16),
	Vector2(0.45, 0.13),
	Vector2(0.39, 0.16),
	Vector2(0.34, 0.09),
	Vector2(0.28, 0.13),
	Vector2(0.23, 0.05),
	Vector2(0.18, 0.11),
	Vector2(0.25, 0.20),
	Vector2(0.34, 0.22),
	Vector2(0.43, 0.19),
	Vector2(0.55, 0.22),
	Vector2(0.65, 0.16),
	Vector2(0.74, 0.20),
]
const PHENOMENA_POINTS := [
	Vector2(0.13, 0.22),
	Vector2(0.30, 0.16),
	Vector2(0.70, 0.18),
	Vector2(0.87, 0.27),
	Vector2(0.80, 0.58),
]

var pullback_progress: float = 0.0:
	set(value):
		pullback_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var route_progress: float = 0.0:
	set(value):
		route_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var phenomena_progress: float = 0.0:
	set(value):
		phenomena_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var dawn_progress: float = 0.0:
	set(value):
		dawn_progress = clampf(value, 0.0, 1.0)
		queue_redraw()

var star_samples: Array[Vector4] = []
var galactic_ring_points: Array[PackedVector2Array] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_star_samples()
	resized.connect(_rebuild_galactic_ring_points)
	_rebuild_galactic_ring_points()
	# The ending is normally hidden; do not keep an idle redraw loop alive in the
	# regular game HUD. reset_animation() enables it only for the reveal.
	set_process(false)
	queue_redraw()


func _process(_delta: float) -> void:
	if pullback_progress < 1.0 or route_progress < 1.0 or phenomena_progress < 1.0 or dawn_progress < 1.0:
		queue_redraw()


func reset_animation() -> void:
	set_process(true)
	pullback_progress = 0.0
	route_progress = 0.0
	phenomena_progress = 0.0
	dawn_progress = 0.0
	visible = true
	queue_redraw()


func complete_animation() -> void:
	pullback_progress = 1.0
	route_progress = 1.0
	phenomena_progress = 1.0
	dawn_progress = 1.0
	set_process(false)
	queue_redraw()


func _build_star_samples() -> void:
	star_samples.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4E49574854415443
	for _index in range(STAR_COUNT):
		star_samples.append(Vector4(
			rng.randf_range(0.06, 0.94),
			rng.randf_range(0.06, 0.76),
			rng.randf_range(0.65, 1.65),
			rng.randf_range(0.42, 1.0)
		))


func _rebuild_galactic_ring_points() -> void:
	galactic_ring_points.clear()
	if size.x <= 1.0 or size.y <= 1.0:
		queue_redraw()
		return
	var centre := Vector2(size.x * 0.5, size.y * 0.16)
	for ring in range(GALACTIC_RING_COUNT):
		var ratio := float(ring) / float(GALACTIC_RING_COUNT - 1)
		var radii := Vector2(42.0 + ratio * 82.0, 14.0 + ratio * 25.0)
		galactic_ring_points.append(_ellipse_points(centre, radii, 72, -0.18))
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	# Keep the animated record in the upper sky so the final title and tallies
	# retain a calm, readable field once the choreography settles.
	var centre := Vector2(size.x * 0.5, size.y * 0.16)
	_draw_dawn_horizon()
	_draw_star_pullback(centre)
	_draw_galactic_record(centre)
	_draw_constellation_route(centre)
	_draw_phenomena_transfer(centre)


func _draw_dawn_horizon() -> void:
	if dawn_progress <= 0.001:
		return
	var eased := _ease_out_cubic(dawn_progress)
	var top_y := lerpf(size.y * 1.04, size.y * 0.61, eased)
	var band_count := 36
	for band in range(band_count):
		var t0 := float(band) / float(band_count)
		var t1 := float(band + 1) / float(band_count)
		var y0 := lerpf(top_y, size.y, t0)
		var y1 := lerpf(top_y, size.y, t1)
		var horizon_weight := pow(1.0 - t0, 1.7)
		var colour := Color(
			lerpf(0.28, 0.12, t0),
			lerpf(0.055, 0.018, t0),
			lerpf(0.022, 0.012, t0),
			eased * (0.04 + horizon_weight * 0.17)
		)
		draw_rect(Rect2(0.0, y0, size.x, maxf(1.0, y1 - y0 + 1.0)), colour)
	draw_line(
		Vector2(0.0, top_y),
		Vector2(size.x, top_y),
		Color(0.92, 0.24, 0.10, eased * 0.24),
		1.0,
		true
	)


func _draw_star_pullback(centre: Vector2) -> void:
	var scale := lerpf(1.18, 0.96, _ease_out_cubic(pullback_progress))
	var now := float(Time.get_ticks_msec()) * 0.001
	for index in range(star_samples.size()):
		var sample := star_samples[index]
		var base := Vector2(sample.x * size.x, sample.y * size.y)
		var point := centre + (base - centre) * scale
		# Twinkle while the camera moves, then settle to a deterministic final
		# brightness so natural completion and a skip produce the same plate.
		var shimmer := 0.78 + sin(now * (0.75 + float(index % 4) * 0.13) + float(index) * 1.91) * 0.22 * (1.0 - pullback_progress)
		var alpha := (0.035 + pullback_progress * 0.40) * sample.w * shimmer
		draw_circle(point, sample.z, Color(0.93, 0.71, 0.57, alpha))


func _draw_galactic_record(centre: Vector2) -> void:
	var record_alpha := 0.04 + pullback_progress * 0.16 + phenomena_progress * 0.10
	for ring in range(galactic_ring_points.size()):
		var ratio := float(ring) / float(GALACTIC_RING_COUNT - 1)
		draw_polyline(galactic_ring_points[ring], Color(0.72, 0.16, 0.09, record_alpha * (1.0 - ratio * 0.65)), 1.0, true)
	var core_radius := lerpf(4.0, 13.0, phenomena_progress)
	draw_circle(centre, core_radius, Color(0.95, 0.30, 0.13, 0.08 + phenomena_progress * 0.18))


func _draw_constellation_route(centre: Vector2) -> void:
	var points := PackedVector2Array()
	var scale := lerpf(1.08, 0.94, _ease_out_cubic(pullback_progress))
	for normalized in ROUTE_POINTS:
		var base := Vector2(normalized.x * size.x, normalized.y * size.y)
		points.append(centre + (base - centre) * scale)
	_draw_progressive_route(points)
	var glyph_slice := 1.0 / maxf(1.0, float(points.size()))
	for index in range(points.size()):
		var threshold := float(index) * glyph_slice
		var local := clampf((route_progress - threshold) / glyph_slice, 0.0, 1.0)
		if local <= 0.001:
			continue
		_draw_constellation_glyph(points[index], index, local)


func _draw_progressive_route(points: PackedVector2Array) -> void:
	if points.size() < 2 or route_progress <= 0.0:
		return
	var scaled := route_progress * float(points.size() - 1)
	for index in range(points.size() - 1):
		var local := clampf(scaled - float(index), 0.0, 1.0)
		if local <= 0.0:
			break
		var endpoint := points[index].lerp(points[index + 1], _ease_out_cubic(local))
		draw_line(points[index], endpoint, Color(0.80, 0.17, 0.09, 0.20), 4.0, true)
		draw_line(points[index], endpoint, Color(0.98, 0.50, 0.29, 0.72), 1.2, true)


func _draw_constellation_glyph(origin: Vector2, index: int, alpha: float) -> void:
	var angle := -0.55 + float(index % 5) * 0.27
	var offsets := [
		Vector2(-8.0, 3.0).rotated(angle),
		Vector2.ZERO,
		Vector2(7.0, -5.0).rotated(angle),
	]
	for edge in range(offsets.size() - 1):
		draw_line(
			origin + offsets[edge],
			origin + offsets[edge + 1],
			Color(0.92, 0.34, 0.18, alpha * 0.55),
			1.0,
			true
		)
	for offset in offsets:
		draw_circle(origin + offset, 1.2 + alpha * 1.15, Color(1.0, 0.78, 0.62, alpha))


func _draw_phenomena_transfer(centre: Vector2) -> void:
	if phenomena_progress <= 0.0:
		return
	for index in range(PHENOMENA_POINTS.size()):
		var local := clampf(phenomena_progress * float(PHENOMENA_POINTS.size()) - float(index), 0.0, 1.0)
		if local <= 0.0:
			continue
		var origin := Vector2(PHENOMENA_POINTS[index].x * size.x, PHENOMENA_POINTS[index].y * size.y)
		var travel := _ease_in_out_cubic(local)
		var particle := origin.lerp(centre, travel)
		_draw_diamond(origin, 4.0, Color(0.96, 0.30, 0.15, (1.0 - travel * 0.65) * 0.78))
		draw_line(origin, particle, Color(0.87, 0.18, 0.10, (1.0 - travel) * 0.28), 1.0, true)
		draw_circle(particle, 2.0 + (1.0 - travel) * 1.2, Color(1.0, 0.72, 0.48, 0.92))
		if local >= 0.999:
			var pip_angle := -PI * 0.5 + TAU * float(index) / float(PHENOMENA_POINTS.size())
			var pip := centre + Vector2.RIGHT.rotated(pip_angle) * 22.0
			draw_circle(pip, 2.3, Color(1.0, 0.56, 0.32, 0.88))
	if phenomena_progress >= 0.999:
		draw_arc(centre, 28.0, 0.0, TAU, 48, Color(0.90, 0.24, 0.12, 0.48), 1.1, true)


func _draw_diamond(centre: Vector2, radius: float, colour: Color) -> void:
	var points := PackedVector2Array([
		centre + Vector2(0.0, -radius),
		centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius),
		centre + Vector2(-radius, 0.0),
		centre + Vector2(0.0, -radius),
	])
	draw_polyline(points, colour, 1.2, true)


func _ellipse_points(centre: Vector2, radii: Vector2, segments: int, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var angle := TAU * float(index) / float(segments)
		points.append(centre + Vector2(cos(angle) * radii.x, sin(angle) * radii.y).rotated(rotation))
	return points


func _ease_out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - clampf(value, 0.0, 1.0), 3.0)


func _ease_in_out_cubic(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	if clamped < 0.5:
		return 4.0 * clamped * clamped * clamped
	return 1.0 - pow(-2.0 * clamped + 2.0, 3.0) * 0.5
