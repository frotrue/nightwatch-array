extends Control

# A small observation glyph shared by library, slots and live sky.
const UITheme = preload("res://scripts/ui_theme.gd")
const Modules = preload("res://scripts/observation_modules.gd")

var module_id := "focus"
var owned := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(id: String, active: bool = true) -> void:
	if module_id == id and owned == active:
		return
	module_id = id
	owned = active
	queue_redraw()

func _draw() -> void:
	draw_module(self, Rect2(Vector2.ZERO, size), module_id, owned)

static func draw_module(canvas: CanvasItem, rect: Rect2, id: String, active: bool = true, opacity: float = 1.0) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.28
	var definition: Dictionary = Modules.DEFINITIONS.get(id, {})
	var expansion_ids := ["sweep_optics", "wide_correlation", "linear_observation", "capture_hold", "overcharge"]
	if id not in expansion_ids:
		id = String(definition.get("glyph", id))
	var ink := Color(UITheme.TOOLTIP_NAME, (0.95 if active else 0.45) * opacity)
	if id == "split":
		canvas.draw_line(c + Vector2(-1.2, 0) * r, c, ink, 1.2, true)
		for side in [-1.0, 1.0]:
			var end := c + Vector2(0.95, side * 0.65) * r
			canvas.draw_line(c, end, ink, 1.2, true)
			canvas.draw_circle(end, 2.2, ink)
	elif id == "focus":
		canvas.draw_arc(c, r * 0.62, 0, TAU, 32, ink, 1.0, true)
		canvas.draw_circle(c, 2.2, ink)
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			canvas.draw_line(c + direction * r * 0.86, c + direction * r * 1.22, ink, 1.0, true)
	elif id == "wide":
		canvas.draw_arc(c, r * 1.15, -PI * 0.88, -PI * 0.12, 24, ink, 1.0, true)
		canvas.draw_arc(c, r * 1.15, PI * 0.12, PI * 0.88, 24, ink, 1.0, true)
		for offset in [Vector2(-0.52, 0.22), Vector2(0, -0.35), Vector2(0.52, 0.22)]:
			canvas.draw_circle(c + offset * r, 2.1, ink)
	elif id == "sweep_optics":
		# Fan-shaped scan rays and the lens that receives them.
		canvas.draw_arc(c, r * 0.75, -PI * 0.46, PI * 0.46, 24, ink, 1.0, true)
		for angle in [-PI * 0.44, -PI * 0.22, 0.0, PI * 0.22, PI * 0.44]:
			canvas.draw_line(c, c + Vector2.from_angle(angle) * r * 1.15, ink, 1.0, true)
		canvas.draw_arc(c, r * 0.28, 0, TAU, 20, ink, 1.0, true)
	elif id == "wide_correlation":
		# Two broad wave fronts intersect around a correlation point.
		canvas.draw_arc(c, r * 0.92, -PI * 0.85, PI * 0.85, 32, ink, 1.0, true)
		canvas.draw_arc(c, r * 0.56, PI * 0.15, PI * 0.85, 24, ink, 1.0, true)
		canvas.draw_line(c + Vector2(-1.12, 0) * r, c + Vector2(1.12, 0) * r, ink, 1.0, true)
		canvas.draw_circle(c, r * 0.14, ink)

	elif id == "linear_observation":
		canvas.draw_rect(Rect2(c - Vector2(1.25, 0.32) * r, Vector2(2.5, 0.64) * r), ink, false, 1.2, true)
		canvas.draw_line(c - Vector2(0, 0.62) * r, c + Vector2(0, 0.62) * r, ink, 1.0, true)
	elif id == "capture_hold":
		for row in [-1.0, 0.0, 1.0]:
			canvas.draw_line(c + Vector2(-1.0, row * 0.45) * r, c + Vector2(0.25, row * 0.3) * r, ink, 1.0, true)
		canvas.draw_circle(c + Vector2(0.7, 0) * r, r * 0.2, ink)
	elif id == "overcharge":
		canvas.draw_polyline(PackedVector2Array([c + Vector2(0.3, -1.1) * r, c + Vector2(-0.5, 0.1) * r, c + Vector2(0.4, -0.05) * r, c + Vector2(-0.25, 1.1) * r]), ink, 1.7, true)
