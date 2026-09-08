extends Control

# A presentation surface inside ModulePopup's existing pause/focus boundary.
# The transaction is saved BEFORE animation starts; closing/skipping never rolls.
const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const REVEAL_SECONDS := 1.8
const CENTER := Vector2(338, 326)
var host: CanvasLayer
var drawing := false
var elapsed := 0.0
var result_id := ""
var new_copy := false
var title: Label
var subtitle: Label
var balance: Label
var status: Label
var result_name: Label
var result_kind: Label
var result_effect: Label
var result_quantity: Label
var action: Button
var skip_button: Button
var loadout_button: Button
var close_button: Button
var result_panel: Control

func setup(owner_popup: CanvasLayer) -> void:
	host = owner_popup
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = _label(self, Vector2(70, 55), Vector2(760, 40), 25, UITheme.INK_HIGH)
	subtitle = _label(self, Vector2(70, 100), Vector2(910, 44), 14, UITheme.TOOLTIP_BODY)
	close_button = _button(Vector2(955, 58), Vector2(125, 35), host.close)
	balance = _label(self, Vector2(640, 162), Vector2(430, 35), 19, UITheme.ACCENT_TEXT)
	status = _label(self, Vector2(140, 516), Vector2(396, 34), 14, UITheme.TOOLTIP_VALUE)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel = Control.new()
	result_panel.position = Vector2(640, 223)
	result_panel.size = Vector2(425, 240)
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result_panel)
	result_kind = _label(result_panel, Vector2.ZERO, Vector2(420, 30), 12, UITheme.INK_MID)
	result_name = _label(result_panel, Vector2(0, 36), Vector2(420, 48), 29, UITheme.INK_HIGH)
	result_effect = _label(result_panel, Vector2(0, 102), Vector2(420, 105), 16, UITheme.TOOLTIP_BODY)
	result_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_quantity = _label(result_panel, Vector2(0, 215), Vector2(420, 32), 13, UITheme.ACCENT_TEXT)
	action = _button(Vector2(640, 498), Vector2(425, 49), begin_draw, true)
	skip_button = _button(Vector2(199, 559), Vector2(278, 36), finish_reveal)
	loadout_button = _button(Vector2(640, 560), Vector2(425, 36), host.show_loadout)
	hide()
	set_process(false)

func enter() -> void:
	drawing = false
	elapsed = REVEAL_SECONDS
	result_id = host.game.deep_sky.state.last_draw
	new_copy = false
	show()
	set_process(true)
	refresh()
	action.grab_focus()

func leave() -> void:
	# Ownership and the last result already live in the saved model.
	drawing = false
	elapsed = REVEAL_SECONDS
	hide()
	set_process(false)

func begin_draw() -> void:
	if drawing or not visible:
		return
	drawing = true
	result_id = ""
	elapsed = 0.0
	refresh()
	var id: String = host.game.deep_sky.draw_module()
	if id.is_empty():
		drawing = false
		result_id = host.game.deep_sky.state.last_draw
		refresh()
		return
	result_id = id
	new_copy = host.model().owned_count(id) == 1
	if host.game.settings.motion_intensity <= 0.0:
		finish_reveal()
	else:
		refresh()
		skip_button.grab_focus()

func finish_reveal() -> void:
	if not drawing:
		return
	drawing = false
	elapsed = REVEAL_SECONDS
	refresh()
	action.grab_focus()

func refresh() -> void:
	if host == null or not visible:
		return
	var research: Node = host.game.deep_sky
	title.text = tr("DRAW_TITLE")
	subtitle.text = tr("DRAW_POOL") % [research.Data.SAMPLE_MODULES.size(), research.Data.SAMPLE_MODULES.size()]
	close_button.text = tr("DRAW_CLOSE")
	balance.text = tr("EXT_SAMPLES_COUNT") % research.samples
	action.text = tr("MODX_DRAW") % research.state.draw_cost()
	action.disabled = drawing or research.samples < research.state.draw_cost()
	loadout_button.text = tr("DRAW_LOADOUT")
	skip_button.text = tr("DRAW_SKIP")
	skip_button.visible = drawing
	result_panel.visible = not drawing
	if drawing:
		status.text = tr("DRAW_ALIGN" if elapsed >= REVEAL_SECONDS * 0.5 else "DRAW_SCAN")
	elif result_id.is_empty():
		status.text = tr("DRAW_READY")
		result_kind.text = tr("DRAW_SPECIMEN")
		result_name.text = tr("DRAW_WAITING")
		result_effect.text = tr("DRAW_EXPLAIN")
		result_quantity.text = tr("DRAW_NO_AUTO_EQUIP")
	else:
		status.text = "" # The result heading already identifies the acquisition.
		result_kind.text = tr("DRAW_NEW" if new_copy else "DRAW_SAVED")
		result_name.text = tr("MODULE_%s_NAME" % result_id.to_upper())
		result_effect.text = tr("MODULE_%s_DESC" % result_id.to_upper())
		result_quantity.text = tr("MODX_QUANTITY") % [host.model().owned_count(result_id), host.model().installed_count(result_id)]
		if not new_copy and host.model().owned_count(result_id) > 1:
			result_quantity.text += "  ·  " + tr("DRAW_DUPLICATE")
	if host.game.hud.autosave_failed:
		status.text = tr("AUTOSAVE_FAILURE") % host.game.active_save_slot
	status.visible = not status.text.is_empty()
	queue_redraw()

func _process(delta: float) -> void:
	if drawing:
		elapsed += delta / maxf(Engine.time_scale, 0.001)
		if elapsed >= REVEAL_SECONDS:
			finish_reveal()
		else:
			status.text = tr("DRAW_ALIGN" if elapsed >= REVEAL_SECONDS * 0.5 else "DRAW_SCAN")
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("100C09"))
	draw_line(Vector2(70, 134), Vector2(1080, 134), Color(UITheme.ACCENT_LINE, 0.25), 1.0)
	draw_line(Vector2(600, 178), Vector2(600, 594), Color(UITheme.ACCENT_LINE, 0.18), 1.0)
	var t := clampf(elapsed / REVEAL_SECONDS, 0.0, 1.0)
	var motion: float = host.game.settings.motion_intensity if host != null else 1.0
	var rotation := t * TAU * 1.5 * motion if drawing else 0.0
	for ring in range(3):
		var radius := 92.0 + ring * 38.0
		draw_arc(CENTER, radius, 0, TAU, 128, Color(UITheme.ACCENT_LINE, 0.12 + ring * 0.025), 1.0, true)
	for index in range(48):
		var angle := TAU * index / 48.0 - PI * 0.5
		var axis := Vector2.from_angle(angle)
		draw_line(CENTER + axis * 171, CENTER + axis * (181 if index % 4 == 0 else 176), Color(UITheme.INK_MID, 0.7), 1.0, true)
	for index in range(6):
		var angle := rotation + TAU * index / 6.0
		var radius := lerpf(142.0, 44.0, smoothstep(0.25, 1.0, t)) if drawing else 142.0
		var point := CENTER + Vector2.from_angle(angle) * radius
		draw_circle(point, 2.5, Color(UITheme.ACCENT_LINE, 0.9))
		if drawing:
			draw_arc(CENTER, radius, angle - 0.35, angle, 20, Color(UITheme.ACCENT_LINE, 0.45), 1.2, true)
	if drawing:
		draw_arc(CENTER, 190.0, -PI * 0.5, -PI * 0.5 + TAU * t, 128, UITheme.ACCENT_LINE, 2.0, true)
		var half := lerpf(18.0, 36.0, t)
		var diamond := PackedVector2Array([CENTER + Vector2(0, -half), CENTER + Vector2(half, 0), CENTER + Vector2(0, half), CENTER + Vector2(-half, 0), CENTER + Vector2(0, -half)])
		draw_polyline(diamond, UITheme.ACCENT_TEXT, 1.5, true)
	elif not result_id.is_empty():
		Visual.draw_module(self, Rect2(CENTER - Vector2(73, 73), Vector2(146, 146)), result_id, true, 1.0)
	else:
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			draw_line(CENTER - axis * 18, CENTER + axis * 18, UITheme.INK_MID, 1.5, true)
		draw_circle(CENTER, 40, Color(UITheme.ACCENT_LINE, 0.25), false, 1.0, true)

func _label(parent: Control, p: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = p
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(p: Vector2, dimensions: Vector2, callback: Callable, filled := false) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 16 if filled else 14)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("38241B") if filled and state != "disabled" else Color(0, 0, 0, 0)
		style.border_color = UITheme.ACCENT_LINE if state in ["hover", "focus"] else Color(UITheme.ACCENT_LINE, 0.45 if filled else 0.16)
		style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", UITheme.INK_HIGH)
	button.add_theme_color_override("font_hover_color", UITheme.INK_MAX)
	button.add_theme_color_override("font_focus_color", UITheme.INK_MAX)
	button.add_theme_color_override("font_disabled_color", UITheme.INK_LOW)
	button.pressed.connect(callback)
	add_child(button)
	return button
