extends Control

# A small observation glyph shared by library, slots and live sky.
var module_id := "focus"
var owned := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(id: String, active: bool = true) -> void:
	module_id = id
	owned = active
	queue_redraw()

func _draw() -> void:
	draw_module(self, Rect2(Vector2.ZERO, size), module_id, owned)

static func draw_module(canvas: CanvasItem, rect: Rect2, id: String, active: bool = true) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.28
	var ink := Color("E6DDD5", 0.95 if active else 0.45)
	if id == "focus":
		canvas.draw_arc(c, r * 0.62, 0, TAU, 32, ink, 1.0, true)
		canvas.draw_circle(c, 2.2, ink)
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			canvas.draw_line(c + direction * r * 0.86, c + direction * r * 1.22, ink, 1.0, true)
	elif id == "wide":
		canvas.draw_arc(c, r * 1.15, -PI * 0.88, -PI * 0.12, 24, ink, 1.0, true)
		canvas.draw_arc(c, r * 1.15, PI * 0.12, PI * 0.88, 24, ink, 1.0, true)
		for offset in [Vector2(-0.52, 0.22), Vector2(0, -0.35), Vector2(0.52, 0.22)]:
			canvas.draw_circle(c + offset * r, 2.1, ink)
