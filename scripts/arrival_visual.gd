extends RefCounted

static func edge_rect(view_rect: Rect2, visual_scale: float) -> Rect2:
	# Reserve the top clock and the ground/HUD strip, including after pull-back.
	return Rect2(view_rect.position + Vector2(40, 90) * visual_scale, view_rect.size - Vector2(80, 190) * visual_scale)

static func edge_point(point: Vector2, view_rect: Rect2, visual_scale: float) -> Vector2:
	var bounds := edge_rect(view_rect, visual_scale)
	var half := bounds.size * 0.5
	var offset := point - bounds.get_center()
	if offset.is_zero_approx():
		offset = Vector2.UP
	var ratio := maxf(absf(offset.x) / maxf(half.x, 1.0), absf(offset.y) / maxf(half.y, 1.0))
	return bounds.get_center() + offset / ratio

# Shared procedural instrument mark for transient and positional forecasts.
static func draw_direction(canvas: CanvasItem, point: Vector2, direction: Vector2, visual_scale: float, color: Color, opacity: float = 1.0, reach: float = 26.0) -> void:
	var axis := PackedVector2Array([point - direction * 4.0 * visual_scale, point + direction * 8.0 * visual_scale, point + direction * reach * visual_scale])
	var colors := PackedColorArray([Color(color, opacity * 0.28), Color(color, opacity * 0.8), Color(color, 0.0)])
	canvas.draw_polyline_colors(axis, colors, 1.1 * visual_scale, true)
