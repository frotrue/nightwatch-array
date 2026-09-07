extends CanvasLayer

const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
var game: Node
var previous_pause := false
var previous_mouse := Input.MOUSE_MODE_VISIBLE
var previous_focus: WeakRef
var selected_slot := 0
var selected_id := ""
var panel: Panel
var overlay: Control
var launcher: Button
var heading: Label
var slot_heading: Label
var owned_heading: Label
var detail: Label
var hint: Label
var slots: Array[Button] = []
var slot_glyphs: Array[Control] = []
var owned_buttons: Dictionary = {}
var equip_button: Button
var clear_button: Button
var close_button: Button

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-223, -217)
	panel.size = Vector2(446, 434)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("080C13")
	style.border_color = Color("746355")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	heading = label_at(Vector2(25, 19), 350, 20)
	close_button = button_at(Vector2(391, 14), Vector2(32, 32), close)
	close_button.text = "×"
	slot_heading = label_at(Vector2(25, 70), 220, 12)
	for index in range(2):
		var button := button_at(Vector2(42 + index * 190, 100), Vector2(166, 61), select_slot.bind(index))
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slots.append(button)
		var glyph = Visual.new()
		glyph.position = Vector2(8, 10)
		glyph.size = Vector2(39, 39)
		button.add_child(glyph)
		slot_glyphs.append(glyph)
	owned_heading = label_at(Vector2(25, 187), 350, 12)
	for index in range(2):
		var id: String = ["focus", "wide"][index]
		var button := button_at(Vector2(25 + index * 202, 215), Vector2(193, 59), select_module.bind(id))
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var glyph = Visual.new()
		glyph.position = Vector2(5, 10)
		glyph.size = Vector2(35, 35)
		glyph.configure(id)
		button.add_child(glyph)
		owned_buttons[id] = button
	detail = label_at(Vector2(25, 292), 396, 12)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equip_button = button_at(Vector2(25, 354), Vector2(256, 32), _equip)
	clear_button = button_at(Vector2(295, 354), Vector2(126, 32), _clear)
	hint = label_at(Vector2(25, 399), 396, 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.visible = false

func setup(controller: Node) -> void:
	game = controller
	layer = game.upgrade_tree.layer + 1
	game.deep_sky.changed.connect(refresh)
	game.settings.language_changed.connect(func(_locale): refresh())
	launcher = Button.new()
	launcher.flat = true
	launcher.name = "ModuleLoadoutButton"
	launcher.z_index = 101
	launcher.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	launcher.offset_left = 38
	launcher.offset_right = 202
	launcher.offset_top = -60
	launcher.offset_bottom = -25
	launcher.add_theme_font_override("font", UITheme.sans())
	launcher.add_theme_font_size_override("font_size", 12)
	launcher.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	launcher.pressed.connect(open)
	game.upgrade_tree.overlay.add_child(launcher)
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
	var focused := get_viewport().gui_get_focus_owner()
	previous_focus = weakref(focused) if focused != null else null
	game._release_hitstop()
	game.observer.reset()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_slot = 0
	selected_id = game.deep_sky.modules.purchased[0] if not game.deep_sky.modules.purchased.is_empty() else ""
	overlay.show()
	refresh()
	close_button.grab_focus()

func close() -> void:
	if not is_open():
		return
	overlay.hide()
	get_tree().paused = previous_pause
	Input.mouse_mode = previous_mouse
	var control = previous_focus.get_ref() if previous_focus != null else null
	if is_instance_valid(control) and control.is_visible_in_tree():
		control.grab_focus()
	else:
		get_viewport().gui_release_focus()

func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed("nw_menu_back") or event.is_action_pressed("nw_chart")):
		close()
		get_viewport().set_input_as_handled()

func select_slot(index: int) -> void:
	selected_slot = index
	refresh()

func select_module(id: String) -> void:
	selected_id = id
	refresh()

func _equip() -> void:
	game.deep_sky.equip(selected_id, selected_slot)

func _clear() -> void:
	game.deep_sky.equip("", selected_slot)

func refresh() -> void:
	if game == null:
		return
	launcher.text = tr("DEEP_MODULES")
	launcher.visible = game.upgrade_tree.is_open() and game.deep_sky.modules_unlocked()
	heading.text = tr("DEEP_MODULES")
	slot_heading.text = tr("DEEP_SLOTS")
	owned_heading.text = tr("DEEP_OWNED")
	var model = game.deep_sky.modules
	var ids: Array = [model.equipped, model.secondary]
	for index in range(2):
		slots[index].text = ("› " if index == selected_slot else "") + (tr("MODULE_NONE") if ids[index].is_empty() else tr("MODULE_%s_SHORT" % ids[index].to_upper())) + "  "
		slot_glyphs[index].visible = not ids[index].is_empty()
		slot_glyphs[index].configure(ids[index])
	for id in owned_buttons:
		owned_buttons[id].visible = id in model.purchased
		owned_buttons[id].text = ("◇ " if id == selected_id else "") + tr("MODULE_%s_SHORT" % id.to_upper()) + (" · " + tr("MODULE_EQUIPPED") if id in ids else "")
	detail.text = tr("DEEP_NO_MODULES") if selected_id.is_empty() else tr("MODULE_%s_DESC" % selected_id.to_upper())
	equip_button.text = tr("MODULE_FIT_SLOT") % (selected_slot + 1)
	equip_button.disabled = selected_id.is_empty() or selected_id not in model.purchased or selected_id in ids
	clear_button.text = tr("MODULE_UNEQUIP")
	clear_button.disabled = ids[selected_slot].is_empty()
	hint.text = tr("DEEP_FREE_EQUIP")
	if game.hud.autosave_failed:
		hint.text = tr("AUTOSAVE_FAILURE") % game.active_save_slot

func label_at(p: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = p
	label.size.x = width
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UITheme.INK_HIGH)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label

func button_at(p: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.position = p
	button.size = dimensions
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("0A0D13") if state != "focus" else Color.TRANSPARENT
		style.border_color = UITheme.ACCENT_LINE if state in ["hover", "focus"] else Color("443E39")
		style.set_border_width_all(1)
		style.content_margin_left = 8
		style.content_margin_right = 8
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	panel.add_child(button)
	return button
