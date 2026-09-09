extends Button

const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const SLOT_RADIUS := 38.0
const CHANGE_SECONDS := 0.28

var owner_popup: CanvasLayer
var index := 0
var shown_id := ""
var previous_id := ""
var blend := 1.0:
	set(value):
		blend = value
		queue_redraw()
var animation: Tween

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= UITheme.px(SLOT_RADIUS)

func update_module(id: String, animate: bool) -> void:
	if shown_id == id:
		queue_redraw()
		return
	if animation != null and animation.is_valid():
		animation.kill()
	previous_id = shown_id
	shown_id = id
	blend = 0.0 if animate else 1.0
	if animate:
		animation = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		animation.tween_property(self, "blend", 1.0, CHANGE_SECONDS)

func finish_animation() -> void:
	if animation != null and animation.is_valid():
		animation.kill()
	blend = 1.0
	previous_id = ""

func _draw() -> void:
	var center := size * 0.5
	var radius := UITheme.px(SLOT_RADIUS)
	var locked: bool = index >= owner_popup.model().unlocked_slots
	draw_circle(center, radius, UITheme.GROUND)
	var ink := Color(UITheme.INK_LOW, 0.65) if locked else Color(UITheme.ACCENT_LINE, 0.9 if not shown_id.is_empty() else 0.55)
	if not locked and shown_id.is_empty():
		ink.a = lerpf(0.55 if previous_id.is_empty() else 0.9, 0.55, blend)
		for segment in range(24):
			draw_arc(center, radius, TAU * segment / 24.0, TAU * (segment + 0.45) / 24.0, 4, ink, UITheme.px(1), true)
	else:
		var previous_alpha := 0.55 if previous_id.is_empty() else 0.9
		if not locked:
			ink.a = lerpf(previous_alpha, 0.9, blend)
		draw_arc(center, radius, 0, TAU, 64, ink, UITheme.px(1), true)
	if locked:
		var lock_ink := Color(UITheme.INK_LOW, 0.75)
		draw_arc(center + Vector2(0, -UITheme.px(2)), UITheme.px(5), PI, TAU, 16, lock_ink, UITheme.px(1.6), true)
		draw_rect(Rect2(center + Vector2(-7, -2) * UITheme.SCALE, Vector2(14, 11) * UITheme.SCALE), lock_ink, false, UITheme.px(1.6))
	elif shown_id.is_empty():
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(center - axis * UITheme.px(11), center + axis * UITheme.px(11), UITheme.TOOLTIP_LABEL, UITheme.px(1.5), true)
	var glyph_rect := Rect2(Vector2.ONE * UITheme.px(8), size - Vector2.ONE * UITheme.px(16))
	if not locked and not shown_id.is_empty():
		Visual.draw_module(self, glyph_rect, shown_id, true, blend)
	if not locked and not previous_id.is_empty() and blend < 1.0:
		Visual.draw_module(self, glyph_rect, previous_id, true, 1.0 - blend)
	if has_focus() and not locked:
		draw_arc(center, radius + UITheme.px(5), 0, TAU, 48, Color(UITheme.ACCENT_LINE, 0.55), UITheme.px(1), true)
