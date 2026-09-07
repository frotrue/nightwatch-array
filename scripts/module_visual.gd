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
	# The nine expansion modules each get a stable, named glyph. Keeping their
	# IDs here means a future metadata refactor cannot accidentally turn every
	# new module into the legacy focus glyph through a missing `glyph` field.
	var expansion_ids := [
		"trail_integrator", "sweep_optics", "relay_bus", "long_baseline",
		"dual_processor", "afterglow_archive", "wide_correlation",
		"reference_bus", "shutter_weave",
	]
	if id not in expansion_ids:
		id = String(definition.get("glyph", id))
	var ink := Color(UITheme.TOOLTIP_NAME, (0.95 if active else 0.45) * opacity)
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
	elif id == "trail_integrator":
		# A path entering a small integration aperture.
		canvas.draw_polyline(PackedVector2Array([
			c + Vector2(-1.15, 0.42) * r,
			c + Vector2(-0.55, 0.18) * r,
			c + Vector2(0.02, -0.08) * r,
			c + Vector2(0.56, -0.32) * r,
		]), ink, 1.2, true)
		canvas.draw_arc(c + Vector2(0.58, -0.33) * r, r * 0.32, 0, TAU, 24, ink, 1.0, true)
		canvas.draw_circle(c + Vector2(-1.18, 0.42) * r, 2.0, ink)
	elif id == "sweep_optics":
		# Fan-shaped scan rays and the lens that receives them.
		canvas.draw_arc(c, r * 0.75, -PI * 0.46, PI * 0.46, 24, ink, 1.0, true)
		for angle in [-PI * 0.44, -PI * 0.22, 0.0, PI * 0.22, PI * 0.44]:
			canvas.draw_line(c, c + Vector2.from_angle(angle) * r * 1.15, ink, 1.0, true)
		canvas.draw_arc(c, r * 0.28, 0, TAU, 20, ink, 1.0, true)
	elif id == "relay_bus":
		# Three relay points joined by a single signal path.
		var relay_points := [c + Vector2(-0.92, 0.42) * r, c, c + Vector2(0.92, -0.42) * r]
		for index in range(relay_points.size() - 1):
			canvas.draw_line(relay_points[index], relay_points[index + 1], ink, 1.0, true)
		for point in relay_points:
			canvas.draw_circle(point, r * 0.16, ink, false, 1.0, true)
	elif id == "long_baseline":
		# A long interferometric baseline with a centered readout mark.
		canvas.draw_line(c + Vector2(-1.18, 0) * r, c + Vector2(1.18, 0) * r, ink, 1.2, true)
		for end in [-1.18, 1.18]:
			canvas.draw_line(c + Vector2(end, -0.3) * r, c + Vector2(end, 0.3) * r, ink, 1.0, true)
		canvas.draw_circle(c, r * 0.18, ink)
	elif id == "dual_processor":
		# Two processing apertures share a short central bus.
		for x in [-0.64, 0.64]:
			var processor_center := c + Vector2(x, 0) * r
			canvas.draw_rect(Rect2(processor_center - Vector2.ONE * r * 0.25, Vector2.ONE * r * 0.5), ink, false, 1.0, true)
		canvas.draw_line(c + Vector2(-0.38, 0) * r, c + Vector2(0.38, 0) * r, ink, 1.0, true)
		canvas.draw_circle(c, r * 0.1, ink)
	elif id == "afterglow_archive":
		# A tray preserves a fading signal as three archive points.
		canvas.draw_rect(Rect2(c + Vector2(-0.75, -0.48) * r, Vector2(1.5, 0.96) * r), ink, false, 1.0, true)
		for offset in [Vector2(-0.42, 0), Vector2(0, 0), Vector2(0.42, 0)]:
			canvas.draw_circle(c + offset * r, r * 0.13, ink)
		canvas.draw_arc(c + Vector2(0, 0.82) * r, r * 0.25, PI, TAU, 16, ink, 1.0, true)
	elif id == "wide_correlation":
		# Two broad wave fronts intersect around a correlation point.
		canvas.draw_arc(c, r * 0.92, -PI * 0.85, PI * 0.85, 32, ink, 1.0, true)
		canvas.draw_arc(c, r * 0.56, PI * 0.15, PI * 0.85, 24, ink, 1.0, true)
		canvas.draw_line(c + Vector2(-1.12, 0) * r, c + Vector2(1.12, 0) * r, ink, 1.0, true)
		canvas.draw_circle(c, r * 0.14, ink)
	elif id == "reference_bus":
		# A reference cross feeds a target node from the left.
		canvas.draw_line(c + Vector2(-1.14, 0) * r, c + Vector2(0.32, 0) * r, ink, 1.0, true)
		canvas.draw_line(c + Vector2(-0.42, -0.44) * r, c + Vector2(-0.42, 0.44) * r, ink, 1.0, true)
		canvas.draw_circle(c + Vector2(0.52, 0) * r, r * 0.3, ink, false, 1.0, true)
		canvas.draw_circle(c + Vector2(0.52, 0) * r, r * 0.08, ink)
	elif id == "shutter_weave":
		# Alternating shutter leaves make a compact weave around a beam.
		for index in range(4):
			var x := -0.78 + index * 0.52
			var top := c + Vector2(x, -0.58 if index % 2 == 0 else -0.34) * r
			var bottom := c + Vector2(x + 0.24, 0.34 if index % 2 == 0 else 0.58) * r
			canvas.draw_line(top, bottom, ink, 1.1, true)
		canvas.draw_line(c + Vector2(-1.15, 0) * r, c + Vector2(1.15, 0) * r, ink, 0.8, true)
