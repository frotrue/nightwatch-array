extends RefCounted

# Shared procedural instrument mark for transient and positional forecasts.
static func draw_direction(canvas: CanvasItem, point: Vector2, direction: Vector2, visual_scale: float, color: Color, opacity: float = 1.0, reach: float = 26.0) -> void:
	var axis := PackedVector2Array([point - direction * 4.0 * visual_scale, point + direction * 8.0 * visual_scale, point + direction * reach * visual_scale])
	var colors := PackedColorArray([Color(color, opacity * 0.28), Color(color, opacity * 0.8), Color(color, 0.0)])
	canvas.draw_polyline_colors(axis, colors, 1.1 * visual_scale, true)
