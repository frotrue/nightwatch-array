extends CanvasLayer

const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const RING_CENTER := Vector2(700, 590)
const RING_RADIUS := 180.0
const SLOT_RADIUS := 38.0
const CHANGE_SECONDS := 0.28

class RingSlot:
	extends Button
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

class InventoryTile:
	extends Button
	var owner_popup: CanvasLayer
	var module_id := ""
	func _draw() -> void:
		var installed: bool = module_id in owner_popup.model().installed_ids()
		var hover: bool = is_hovered() or has_focus()
		draw_rect(Rect2(Vector2.ZERO, size), UITheme.GROUND)
		draw_rect(Rect2(Vector2.ZERO, size), Color(UITheme.ACCENT_LINE, 0.9) if hover else Color(UITheme.INK_LOW, 0.6), false, UITheme.px(1), true)
		Visual.draw_module(self, Rect2(Vector2.ONE * UITheme.px(13), size - Vector2.ONE * UITheme.px(26)), module_id, not installed)
		var font: Font = UITheme.mono()
		var code: String = Modules.DEFINITIONS[module_id].code
		draw_string(font, Vector2(UITheme.px(6), UITheme.px(14)), code, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.size_px(10), UITheme.INK_LOW if installed else UITheme.INK_MID)
		if installed:
			var mark := Rect2(size - Vector2.ONE * UITheme.px(24), Vector2.ONE * UITheme.px(14))
			draw_rect(mark, UITheme.TOOLTIP_LABEL, false, UITheme.px(1), true)
			draw_rect(mark.grow(-UITheme.px(3)), UITheme.TOOLTIP_LABEL)

var game: Node
var previous_pause := false
var previous_mouse := Input.MOUSE_MODE_VISIBLE
var previous_focus: WeakRef
var previous_chart_visible := true
var overlay: Control
var surface: Control
var launcher: Button
var close_button: Button
var heading: Label
var inventory_heading: Label
var inventory_count: Label
var summary_heading: Label
var summary: Label
var capacity_label: Label
var instructions: Label
var hint: Label
var slots: Array[RingSlot] = []
var slot_captions: Array[Label] = []
var owned_buttons: Dictionary = {}
var tooltip_panel: PanelContainer
var tooltip_name: Label
var tooltip_code: Label
var tooltip_effect: Label
var tooltip_combo: Label
var tooltip_action: Label
var hover_kind := ""
var hover_id := ""
var hover_slot := -1
var tooltip_pointer := Vector2.ZERO

func model():
	return game.deep_sky.modules

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = UITheme.SCRIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.draw.connect(_draw_surface)
	overlay.add_child(surface)
	heading = _label(surface, Vector2(140, 277), 1000, 24, UITheme.INK_HIGH)
	close_button = _text_action(surface, Vector2(1580, 270), Vector2(200, 40), close)
	for index in range(Modules.MAX_SLOTS):
		var button := RingSlot.new()
		button.owner_popup = self
		button.index = index
		button.position = (RING_CENTER + Vector2.from_angle(-PI / 2 + TAU * index / 5.0) * RING_RADIUS - Vector2.ONE * SLOT_RADIUS) * UITheme.SCALE
		button.size = Vector2.ONE * UITheme.px(SLOT_RADIUS * 2)
		_empty_button_style(button)
		button.pressed.connect(remove_module.bind(index))
		button.mouse_entered.connect(show_slot_tooltip.bind(index))
		button.mouse_exited.connect(hide_tooltip)
		button.focus_entered.connect(show_slot_tooltip.bind(index))
		button.focus_exited.connect(hide_tooltip)
		surface.add_child(button)
		slots.append(button)
		var center := button.position / UITheme.SCALE + Vector2.ONE * SLOT_RADIUS
		var label_pos := center + Vector2(-95, -65 if index == 0 else 50)
		var caption := _label(surface, label_pos, 190, 15, UITheme.INK_HIGH)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_captions.append(caption)
	inventory_heading = _label(surface, Vector2(1180, 344), 420, 11, UITheme.INK_MID, true)
	inventory_count = _label(surface, Vector2(1640, 344), 140, 11, UITheme.INK_LOW, true)
	inventory_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for id in Modules.DEFINITIONS:
		var tile := InventoryTile.new()
		tile.module_id = id
		tile.owner_popup = self
		tile.size = Vector2.ONE * UITheme.px(120)
		_empty_button_style(tile)
		tile.pressed.connect(equip_from_inventory.bind(id))
		tile.mouse_entered.connect(show_module_tooltip.bind(id))
		tile.mouse_exited.connect(hide_tooltip)
		tile.focus_entered.connect(show_module_tooltip.bind(id))
		tile.focus_exited.connect(hide_tooltip)
		surface.add_child(tile)
		owned_buttons[id] = tile
	summary_heading = _label(surface, Vector2(400, 832), 600, 10, UITheme.TOOLTIP_LABEL, true)
	summary_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary = _label(surface, Vector2(335, 860), 730, 16, UITheme.TOOLTIP_VALUE)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capacity_label = _label(surface, Vector2(400, 888), 600, 10, UITheme.INK_LOW, true)
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions = _label(surface, Vector2(1180, 764), 600, 12, UITheme.TOOLTIP_LABEL)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = _label(surface, Vector2(1180, 864), 600, 11, UITheme.INK_LOW)
	_build_tooltip()
	overlay.hide()
	set_process(false)

func setup(controller: Node) -> void:
	game = controller
	layer = game.upgrade_tree.layer + 1
	game.deep_sky.changed.connect(refresh)
	game.settings.language_changed.connect(func(_locale): refresh())
	launcher = _text_action(game.upgrade_tree.overlay, Vector2(63, 980), Vector2(273, 58), open)
	launcher.z_index = 101
	game.upgrade_tree.tree_opened.connect(refresh)
	game.upgrade_tree.tree_closed.connect(refresh)
	refresh()

func is_open() -> bool:
	return overlay.visible

func open() -> void:
	if is_open() or not game.upgrade_tree.is_open() or not game.deep_sky.modules_unlocked() or game.hud.is_settings_open() or game.hud.is_startup_slots_open() or game.hud.is_end_open() or game.tutorial.is_modal_step():
		return
	previous_pause = get_tree().paused
	previous_mouse = Input.mouse_mode
	previous_chart_visible = game.upgrade_tree.visible
	var focused := get_viewport().gui_get_focus_owner()
	previous_focus = weakref(focused) if focused != null else null
	game._release_hitstop()
	game.observer.reset()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Hide only the chart canvas, retaining its logical open/pause state. The
	# paused real sky remains the backdrop, as in the supplied ring mockup.
	game.upgrade_tree.hide()
	overlay.show()
	refresh(false)
	finish_animations()
	set_process(true)
	close_button.grab_focus()

func close() -> void:
	if not is_open():
		return
	hide_tooltip()
	finish_animations()
	overlay.hide()
	set_process(false)
	get_tree().paused = previous_pause
	Input.mouse_mode = previous_mouse
	game.upgrade_tree.visible = previous_chart_visible
	var control = previous_focus.get_ref() if previous_focus != null else null
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()
	else:
		get_viewport().gui_release_focus()

func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("nw_menu_back", false, true) or event.is_action_pressed("nw_chart", false, true)):
		close()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if tooltip_panel.visible:
		tooltip_pointer = overlay.get_local_mouse_position()
		_place_tooltip()

func equip_from_inventory(id: String) -> void:
	if id not in model().purchased or id in model().installed_ids() or model().first_empty_slot() < 0:
		return
	game.deep_sky.equip(id)

func remove_module(index: int) -> void:
	if index < 0 or index >= model().unlocked_slots or model().slots[index].is_empty():
		return
	game.deep_sky.equip("", index)

func finish_animations() -> void:
	for slot in slots:
		slot.finish_animation()

func refresh(animate: bool = true) -> void:
	if game == null:
		return
	launcher.text = tr("DEEP_MODULES")
	launcher.visible = game.upgrade_tree.is_open() and game.deep_sky.modules_unlocked()
	if not is_open():
		return
	heading.text = tr("DEEP_MODULES")
	close_button.text = tr("RING_CLOSE")
	inventory_heading.text = tr("DEEP_OWNED")
	inventory_count.text = tr("RING_MODULE_COUNT") % model().purchased.size()
	for index in range(Modules.MAX_SLOTS):
		var id: String = model().slots[index]
		var locked: bool = index >= model().unlocked_slots
		slots[index].disabled = locked or id.is_empty()
		slots[index].focus_mode = Control.FOCUS_NONE if locked or id.is_empty() else Control.FOCUS_ALL
		slots[index].update_module(id, animate)
		slot_captions[index].text = tr("RING_LOCKED") if locked else (tr("RING_EMPTY") if id.is_empty() else tr("MODULE_%s_SHORT" % id.to_upper()))
		slot_captions[index].add_theme_color_override("font_color", UITheme.INK_LOW if locked else UITheme.INK_HIGH)
	var placed := 0
	for id in owned_buttons:
		var tile: InventoryTile = owned_buttons[id]
		tile.visible = id in model().purchased
		if tile.visible:
			tile.position = Vector2(1180 + (placed % 4) * 138, 410 + (placed / 4) * 138) * UITheme.SCALE
			placed += 1
			tile.queue_redraw()
	summary_heading.text = tr("RING_CURRENT")
	summary.text = tr("RING_SUMMARY") % [model().effect("speed"), model().effect("radius"), model().effect("targets")]
	capacity_label.text = tr("RING_CAPACITY") % [model().unlocked_slots, Modules.MAX_SLOTS - model().unlocked_slots]
	instructions.text = tr("DEEP_NO_MODULES") if model().purchased.is_empty() else tr("RING_INSTRUCTIONS")
	hint.text = tr("DEEP_FREE_EQUIP") if not game.hud.autosave_failed else tr("AUTOSAVE_FAILURE") % game.active_save_slot
	surface.queue_redraw()
	_update_tooltip()

func show_module_tooltip(id: String) -> void:
	hover_kind = "module"
	hover_id = id
	hover_slot = -1
	tooltip_pointer = owned_buttons[id].get_global_rect().get_center()
	_update_tooltip()

func show_slot_tooltip(index: int) -> void:
	hover_kind = "slot"
	hover_slot = index
	hover_id = model().slots[index]
	tooltip_pointer = slots[index].get_global_rect().get_center()
	_update_tooltip()

func hide_tooltip() -> void:
	hover_kind = ""
	tooltip_panel.hide()

func _update_tooltip() -> void:
	if hover_kind.is_empty() or not is_open():
		tooltip_panel.hide()
		return
	var id := hover_id
	if hover_kind == "slot":
		id = model().slots[hover_slot]
	if hover_kind == "slot" and hover_slot >= model().unlocked_slots:
		tooltip_name.text = tr("RING_LOCKED")
		tooltip_code.text = tr("RING_SLOT_CODE") % [hover_slot + 1, Modules.MAX_SLOTS]
		tooltip_effect.text = tr("RING_UNLOCK_BY") % tr("RING_RESEARCH_%d" % (hover_slot + 1))
		tooltip_combo.text = tr("RING_RESEARCH_LOCATION")
		tooltip_action.text = tr("RING_LOCKED_ACTION")
	elif id.is_empty():
		tooltip_name.text = tr("RING_EMPTY")
		tooltip_code.text = tr("RING_SLOT_CODE") % [hover_slot + 1, Modules.MAX_SLOTS]
		tooltip_effect.text = tr("RING_EMPTY_HINT")
		tooltip_combo.text = ""
		tooltip_action.text = tr("RING_EMPTY_ACTION")
	else:
		tooltip_name.text = tr("MODULE_%s_NAME" % id.to_upper())
		tooltip_code.text = String(Modules.DEFINITIONS[id].code) + " · " + (tr("RING_SLOT_SHORT") % (hover_slot + 1) if hover_kind == "slot" else tr("RING_MODULE_TYPE"))
		tooltip_effect.text = tr("RING_EFFECT") + "  " + tr("MODULE_%s_DESC" % id.to_upper())
		tooltip_combo.text = tr("RING_COMBO") + "  " + tr("MODULE_%s_COMBO" % id.to_upper())
		if hover_kind == "slot":
			tooltip_action.text = tr("RING_REMOVE_ACTION")
		elif id in model().installed_ids():
			tooltip_action.text = tr("RING_EQUIPPED_ACTION")
		elif model().first_empty_slot() < 0:
			tooltip_action.text = tr("RING_FULL_ACTION")
		else:
			tooltip_action.text = tr("RING_EQUIP_ACTION") % (model().first_empty_slot() + 1)
	tooltip_combo.visible = not tooltip_combo.text.is_empty()
	tooltip_panel.show()
	tooltip_panel.size = Vector2(UITheme.px(400), 0)
	_place_tooltip.call_deferred()

func _place_tooltip() -> void:
	var margin := UITheme.px(16)
	var offset := Vector2.ONE * UITheme.px(18)
	var p := tooltip_pointer + offset
	if p.x + tooltip_panel.size.x > overlay.size.x - margin:
		p.x = tooltip_pointer.x - offset.x - tooltip_panel.size.x
	if p.y + tooltip_panel.size.y > overlay.size.y - margin:
		p.y = tooltip_pointer.y - offset.y - tooltip_panel.size.y
	p.x = clampf(p.x, margin, maxf(margin, overlay.size.x - tooltip_panel.size.x - margin))
	p.y = clampf(p.y, margin, maxf(margin, overlay.size.y - tooltip_panel.size.y - margin))
	tooltip_panel.position = p

func _build_tooltip() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.custom_minimum_size.x = UITheme.px(400)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.TOOLTIP_BACKGROUND
	style.border_color = UITheme.TOOLTIP_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = UITheme.px(26)
	style.content_margin_right = UITheme.px(26)
	style.content_margin_top = UITheme.px(20)
	style.content_margin_bottom = UITheme.px(20)
	tooltip_panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(tooltip_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UITheme.size_px(10))
	tooltip_panel.add_child(column)
	var list: Array[Label] = []
	for spec in [[19, UITheme.TOOLTIP_NAME], [11, UITheme.TOOLTIP_LABEL], [14, UITheme.TOOLTIP_BODY], [14, UITheme.TOOLTIP_BODY], [13, UITheme.TOOLTIP_ACTION]]:
		var label := UITheme.spec_label("", UITheme.sans(), spec[0], spec[1])
		# Give wrapping its final width before the first container layout.
		label.custom_minimum_size.x = UITheme.px(348)
		label.size.x = UITheme.px(348)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
		list.append(label)
	tooltip_name = list[0]
	tooltip_code = list[1]
	tooltip_code.add_theme_font_override("font", UITheme.mono())
	tooltip_effect = list[2]
	tooltip_combo = list[3]
	tooltip_action = list[4]
	tooltip_panel.hide()

func _draw_surface() -> void:
	surface.draw_line(Vector2(140, 322) * UITheme.SCALE, Vector2(1780, 322) * UITheme.SCALE, Color(UITheme.INK_MID, 0.3), UITheme.px(1), true)
	var center := RING_CENTER * UITheme.SCALE
	surface.draw_arc(center, UITheme.px(RING_RADIUS), 0, TAU, 128, Color(UITheme.INK_MID, 0.42), UITheme.px(1), true)
	surface.draw_arc(center, UITheme.px(16), 0, TAU, 48, Color(UITheme.INSTRUMENT_ARC, 0.35), UITheme.px(1), true)
	surface.draw_circle(center, UITheme.px(2.2), UITheme.INSTRUMENT_ARC)
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		surface.draw_line(center + direction * UITheme.px(22), center + direction * UITheme.px(28), Color(UITheme.INSTRUMENT_ARC, 0.45), UITheme.px(1), true)
	for y in [382, 748]:
		surface.draw_line(Vector2(1180, y) * UITheme.SCALE, Vector2(1780, y) * UITheme.SCALE, Color(UITheme.INK_MID, 0.22), UITheme.px(1), true)

func _label(parent: Control, p: Vector2, width: float, spec_size: int, ink: Color, mono: bool = false) -> Label:
	var label := UITheme.spec_label("", UITheme.mono() if mono else UITheme.sans(), spec_size, ink)
	label.position = p * UITheme.SCALE
	label.size.x = UITheme.px(width)
	parent.add_child(label)
	return label

func _empty_button_style(button: Button) -> void:
	button.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _text_action(parent: Control, p: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.position = p * UITheme.SCALE
	button.size = dimensions * UITheme.SCALE
	_empty_button_style(button)
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", UITheme.size_px(14))
	button.add_theme_color_override("font_color", UITheme.INK_MID)
	button.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
	button.pressed.connect(callback)
	button.draw.connect(func(): button.draw_line(Vector2(0, button.size.y - 1), button.size - Vector2(0, 1), Color(UITheme.INK_MID, 0.55), UITheme.px(1), true))
	parent.add_child(button)
	return button
