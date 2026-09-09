extends Button

const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const POPUP_BODY_SPEC_SIZE := 20
const POPUP_META_SPEC_SIZE := 16

var owner_popup: CanvasLayer
var module_id := ""
var owned := false
var installed := false
var category := ""
var equip_available := false

func update_state(is_owned: bool, is_installed: bool, module_category: String) -> void:
	owned = is_owned
	installed = is_installed
	category = module_category
	equip_available = owned and owner_popup.model().spare_count(module_id) > 0 and owner_popup.model().first_empty_slot() >= 0
	# Keep inspection/focus available when equipping is blocked.
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if equip_available else Control.CURSOR_ARROW
	queue_redraw()

func _draw() -> void:
	var hover: bool = is_hovered() or has_focus()
	var fill := UITheme.GROUND if owned else Color(UITheme.GROUND, 0.68)
	var border := (UITheme.ACCENT_LINE if equip_available else UITheme.TOOLTIP_LABEL) if hover else (UITheme.INK_MID if equip_available else UITheme.INK_LOW)
	draw_rect(Rect2(Vector2.ZERO, size), fill)
	draw_rect(Rect2(Vector2.ZERO, size), Color(border, 0.9 if owned or hover else 0.52), false, UITheme.px(1), true)
	# Reserve the upper band for the glyph and the lower band for readable type.
	var glyph_rect := Rect2(Vector2(UITheme.px(13), UITheme.px(20)), Vector2(size.x - UITheme.px(26), UITheme.px(40)))
	Visual.draw_module(self, glyph_rect, module_id, equip_available)
	# Codes remain available in the selected module details.
	var short_name := owner_popup.tr("MODULE_%s_SHORT" % module_id.to_upper())
	draw_string(UITheme.sans(), Vector2(UITheme.px(7), size.y - UITheme.px(28)), short_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - UITheme.px(14), UITheme.size_px(POPUP_BODY_SPEC_SIZE), UITheme.INK_HIGH if owned else UITheme.INK_LOW)
	var state_key := "MODX_OWNED" if owned else "MODX_LOCKED"
	draw_string(UITheme.mono(), Vector2(UITheme.px(7), size.y - UITheme.px(9)), (owner_popup.tr("MODX_QUANTITY") % [owner_popup.model().owned_count(module_id), owner_popup.model().installed_count(module_id)] if owned else owner_popup.tr(state_key)), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.size_px(POPUP_META_SPEC_SIZE), UITheme.TOOLTIP_LABEL)
	if installed:
		var mark := Rect2(Vector2(size.x - UITheme.px(18), UITheme.px(6)), Vector2.ONE * UITheme.px(10))
		draw_rect(mark, UITheme.TOOLTIP_LABEL, false, UITheme.px(1), true)
		draw_rect(mark.grow(-UITheme.px(3)), UITheme.TOOLTIP_LABEL)
