extends CanvasLayer

const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/module_visual.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const DrawWindow = preload("res://scripts/module_draw_window.gd")
const RING_CENTER := Vector2(700, 590)
const RING_RADIUS := 180.0
const SLOT_RADIUS := 38.0
const CHANGE_SECONDS := 0.28
# The popup is authored against the 1920x1080 spec frame and rendered at 0.6x
# in the shared 1152x648 viewport. Keep readable prose and actions above the
# resulting 12px/14px output thresholds instead of inheriting the tiny chart
# metadata sizes.
const POPUP_BODY_SPEC_SIZE := 20 # 12px at UITheme.SCALE
const POPUP_ACTION_SPEC_SIZE := 24 # 14px at UITheme.SCALE
const POPUP_META_SPEC_SIZE := 16 # 10px at UITheme.SCALE
const INVENTORY_COLUMNS := 3
const INVENTORY_TILE_SPEC_SIZE := Vector2(188, 104)
const INVENTORY_GAP_SPEC := 10.0
const INVENTORY_SCROLL_SPEC_RECT := Rect2(1174, 414, 620, 338)
const INVENTORY_GRID_SPEC_WIDTH := 600.0
const INVENTORY_FILTERS := ["all", "owned", "trace", "sweep", "link"]

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
	var owned := false
	var installed := false
	var category := ""

	func update_state(is_owned: bool, is_installed: bool, module_category: String) -> void:
		owned = is_owned
		installed = is_installed
		category = module_category
		queue_redraw()

	func _draw() -> void:
		var hover: bool = is_hovered() or has_focus()
		var fill := UITheme.GROUND if owned else Color(UITheme.GROUND, 0.68)
		var border := UITheme.ACCENT_LINE if hover else (UITheme.INK_MID if owned else UITheme.INK_LOW)
		draw_rect(Rect2(Vector2.ZERO, size), fill)
		draw_rect(Rect2(Vector2.ZERO, size), Color(border, 0.9 if owned or hover else 0.52), false, UITheme.px(1), true)
		Visual.draw_module(self, Rect2(Vector2.ONE * UITheme.px(13), size - Vector2.ONE * UITheme.px(26)), module_id, owned and owner_popup.model().spare_count(module_id) > 0)
		var font: Font = UITheme.mono()
		var definition: Dictionary = Modules.DEFINITIONS.get(module_id, {})
		var code: String = String(definition.get("code", module_id.to_upper()))
		draw_string(font, Vector2(UITheme.px(7), UITheme.px(16)), code, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.size_px(POPUP_META_SPEC_SIZE), UITheme.INK_LOW if not owned else UITheme.INK_MID)
		var short_name := owner_popup.tr("MODULE_%s_SHORT" % module_id.to_upper())
		draw_string(UITheme.sans(), Vector2(UITheme.px(7), size.y - UITheme.px(28)), short_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - UITheme.px(14), UITheme.size_px(POPUP_BODY_SPEC_SIZE), UITheme.INK_HIGH if owned else UITheme.INK_LOW)
		var state_key := "MODX_OWNED" if owned else "MODX_LOCKED"
		draw_string(UITheme.mono(), Vector2(UITheme.px(7), size.y - UITheme.px(9)), (owner_popup.tr("MODX_QUANTITY") % [owner_popup.model().owned_count(module_id), owner_popup.model().installed_count(module_id)] if owned else owner_popup.tr(state_key)), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.size_px(POPUP_META_SPEC_SIZE), UITheme.TOOLTIP_LABEL)
		if installed:
			var mark := Rect2(Vector2(size.x - UITheme.px(18), UITheme.px(6)), Vector2.ONE * UITheme.px(10))
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
var draw_launcher: Button
var draw_window: Control
var close_button: Button
var draw_button: Button
var heading: Label
var inventory_heading: Label
var inventory_count: Label
var inventory_scroll: ScrollContainer
var inventory_grid: GridContainer
var filter_buttons: Dictionary = {}
var inventory_filter := "all"
var summary_heading: Label
var summary: Label
var summary_details: Label
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
		var caption := _label(surface, label_pos, 190, POPUP_BODY_SPEC_SIZE, UITheme.INK_HIGH)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_captions.append(caption)
	inventory_heading = _label(surface, Vector2(1180, 344), 420, POPUP_BODY_SPEC_SIZE, UITheme.INK_MID, true)
	inventory_count = _label(surface, Vector2(1640, 344), 140, POPUP_BODY_SPEC_SIZE, UITheme.INK_MID, true)
	inventory_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for filter_index in range(INVENTORY_FILTERS.size()):
		var filter_id: String = INVENTORY_FILTERS[filter_index]
		var filter := _filter_action(surface, Vector2(1180 + filter_index * 117, 376), Vector2(108, 30), filter_id)
		filter_buttons[filter_id] = filter
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.position = Vector2(INVENTORY_SCROLL_SPEC_RECT.position) * UITheme.SCALE
	inventory_scroll.size = Vector2(INVENTORY_SCROLL_SPEC_RECT.size) * UITheme.SCALE
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inventory_scroll.focus_mode = Control.FOCUS_NONE
	surface.add_child(inventory_scroll)
	inventory_grid = GridContainer.new()
	inventory_grid.columns = INVENTORY_COLUMNS
	inventory_grid.custom_minimum_size = Vector2(UITheme.px(INVENTORY_GRID_SPEC_WIDTH), 0)
	inventory_grid.add_theme_constant_override("h_separation", UITheme.px(INVENTORY_GAP_SPEC))
	inventory_grid.add_theme_constant_override("v_separation", UITheme.px(INVENTORY_GAP_SPEC))
	inventory_scroll.add_child(inventory_grid)
	for id in Modules.DEFINITIONS:
		var tile := InventoryTile.new()
		tile.module_id = id
		tile.owner_popup = self
		tile.custom_minimum_size = INVENTORY_TILE_SPEC_SIZE * UITheme.SCALE
		tile.size = INVENTORY_TILE_SPEC_SIZE * UITheme.SCALE
		_empty_button_style(tile)
		tile.pressed.connect(equip_from_inventory.bind(id))
		tile.mouse_entered.connect(show_module_tooltip.bind(id))
		tile.mouse_exited.connect(hide_tooltip)
		tile.focus_entered.connect(_on_tile_focus.bind(id))
		tile.focus_exited.connect(hide_tooltip)
		inventory_grid.add_child(tile)
		owned_buttons[id] = tile
	summary_heading = _label(surface, Vector2(400, 842), 600, POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_LABEL, true)
	summary_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary = _label(surface, Vector2(250, 872), 900, POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_VALUE)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_details = _label(surface, Vector2(250, 902), 900, POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_BODY)
	summary_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary_details.size.y = UITheme.px(24)
	capacity_label = _label(surface, Vector2(400, 944), 600, POPUP_BODY_SPEC_SIZE, UITheme.INK_MID, true)
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions = _label(surface, Vector2(1180, 766), 600, POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_BODY)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = _label(surface, Vector2(1180, 908), 600, POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_VALUE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draw_button = _text_action(surface, Vector2(1180, 813), Vector2(610, 54), open_draw)
	draw_window = DrawWindow.new()
	overlay.add_child(draw_window)
	draw_window.setup(self)
	_build_tooltip()
	overlay.hide()
	set_process(false)

func setup(controller: Node) -> void:
	game = controller
	layer = game.upgrade_tree.layer + 1
	game.deep_sky.changed.connect(refresh)
	game.settings.language_changed.connect(func(_locale): refresh())
	launcher = _text_action(game.upgrade_tree.overlay, Vector2(63, 940), Vector2(273, 50), open)
	launcher.z_index = 101
	draw_launcher = _text_action(game.upgrade_tree.overlay, Vector2.ZERO, Vector2(273, 50), open_draw)
	draw_launcher.z_index = 101
	game.upgrade_tree.tree_opened.connect(refresh)
	game.upgrade_tree.tree_closed.connect(refresh)
	refresh()

func is_open() -> bool:
	return overlay.visible

func is_draw_open() -> bool:
	return is_open() and draw_window.visible

func open_draw() -> void:
	if not is_open():
		open()
	if not is_open() or is_draw_open():
		return
	hide_tooltip()
	surface.hide()
	draw_window.enter()

func show_loadout() -> void:
	draw_window.leave()
	surface.show()
	refresh(false)
	close_button.grab_focus()

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
	surface.show()
	draw_window.leave()
	overlay.show()
	refresh(false)
	finish_animations()
	set_process(true)
	close_button.grab_focus()

func close() -> void:
	if not is_open():
		return
	hide_tooltip()
	draw_window.leave()
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
	if id not in model().purchased or model().spare_count(id) <= 0 or model().first_empty_slot() < 0:
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
	place_launcher()
	launcher.text = tr("DEEP_MODULES")
	launcher.visible = game.upgrade_tree.is_open() and game.deep_sky.modules_unlocked()
	draw_launcher.text = tr("DRAW_TITLE")
	draw_launcher.visible = launcher.visible
	if not is_open():
		return
	draw_window.refresh()
	heading.text = tr("DEEP_MODULES")
	close_button.text = tr("RING_CLOSE")
	inventory_heading.text = tr("MODX_INVENTORY")
	inventory_count.text = _format_translation("MODX_COUNT", [model().purchased.size(), Modules.DEFINITIONS.size()], "%d / %d" % [model().purchased.size(), Modules.DEFINITIONS.size()])
	for filter_id in filter_buttons:
		var filter: Button = filter_buttons[filter_id]
		filter.text = _filter_label(filter_id)
		filter.add_theme_color_override("font_color", UITheme.ACCENT_TEXT if inventory_filter == filter_id else UITheme.INK_MID)
		filter.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
		filter.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
	for index in range(Modules.MAX_SLOTS):
		var id: String = model().slots[index]
		var locked: bool = index >= model().unlocked_slots
		slots[index].disabled = locked or id.is_empty()
		slots[index].focus_mode = Control.FOCUS_NONE if locked or id.is_empty() else Control.FOCUS_ALL
		slots[index].update_module(id, animate)
		slot_captions[index].text = tr("RING_LOCKED") if locked else (tr("RING_EMPTY") if id.is_empty() else tr("MODULE_%s_SHORT" % id.to_upper()))
		slot_captions[index].add_theme_color_override("font_color", UITheme.INK_LOW if locked else UITheme.INK_HIGH)
	var installed_ids: Array[String] = model().installed_ids()
	for id in owned_buttons:
		var tile: InventoryTile = owned_buttons[id]
		var definition: Dictionary = _definition(id)
		tile.visible = _matches_filter(id, definition)
		tile.update_state(id in model().purchased, id in installed_ids, _category_for(id, definition))
		# A filtered grid keeps its original child order, so keyboard focus remains
		# stable as modules are added to the catalog later.
		tile.focus_mode = Control.FOCUS_ALL if tile.visible else Control.FOCUS_NONE
	summary_heading.text = tr("MODX_CURRENT")
	var old_speed := _effect_number("speed", 1.0)
	var new_speed := _effect_number("new_speed", 1.0)
	var manual_speed := old_speed * new_speed
	summary.text = _format_translation("MODX_STATIC_SUMMARY", [manual_speed, _effect_number("radius", 1.0), _effect_number("m31_value", 1.0), _effect_number("m31_cooldown", 1.0)], "Manual ×%.2f · Radius ×%.2f · M31 ×%.2f · Wait ×%.2f" % [manual_speed, _effect_number("radius", 1.0), _effect_number("m31_value", 1.0), _effect_number("m31_cooldown", 1.0)])
	summary_details.text = _conditional_summary(installed_ids)
	capacity_label.text = tr("RING_CAPACITY") % [model().unlocked_slots, Modules.MAX_SLOTS - model().unlocked_slots]
	instructions.text = tr("EXT_SAMPLES_COUNT") % game.deep_sky.samples
	draw_button.text = tr("DRAW_OPEN")
	hint.text = tr("MODX_EQUIP_HINT") if not game.hud.autosave_failed else tr("AUTOSAVE_FAILURE") % game.active_save_slot
	if inventory_scroll != null:
		inventory_scroll.queue_redraw()
	surface.queue_redraw()
	_update_tooltip()

func show_module_tooltip(id: String) -> void:
	if not owned_buttons.has(id):
		return
	hover_kind = "module"
	hover_id = id
	hover_slot = -1
	tooltip_pointer = owned_buttons[id].get_global_rect().get_center()
	_update_tooltip()

func _on_tile_focus(id: String) -> void:
	show_module_tooltip(id)
	var tile: InventoryTile = owned_buttons.get(id)
	if tile != null and inventory_scroll != null:
		inventory_scroll.ensure_control_visible(tile)

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
	if hover_kind.is_empty() or not is_open() or is_draw_open():
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
		var definition: Dictionary = _definition(id)
		var is_catalog_tile := hover_kind == "module"
		tooltip_name.text = tr("MODULE_%s_NAME" % id.to_upper())
		var category := _category_for(id, definition)
		var category_label := _category_label(category)
		tooltip_code.text = String(definition.get("code", id.to_upper())) + " · " + (tr("RING_SLOT_SHORT") % (hover_slot + 1) if hover_kind == "slot" else category_label)
		tooltip_effect.text = tr("RING_EFFECT") + "  " + tr("MODULE_%s_DESC" % id.to_upper())
		if is_catalog_tile and id not in model().purchased:
			tooltip_combo.text = _acquisition_route(id, definition)
		else:
			var combo := _translation_or_empty("MODULE_%s_COMBO" % id.to_upper())
			tooltip_combo.text = (tr("RING_COMBO") + "  " + combo) if not combo.is_empty() else _acquisition_route(id, definition)
		if hover_kind == "slot":
			tooltip_action.text = tr("RING_REMOVE_ACTION")
		elif is_catalog_tile and id not in model().purchased:
			tooltip_action.text = tr("MODX_LOCKED_ACTION")
		elif model().spare_count(id) <= 0:
			tooltip_action.text = tr("RING_EQUIPPED_ACTION")
		elif model().first_empty_slot() < 0:
			tooltip_action.text = tr("RING_FULL_ACTION")
		else:
			tooltip_action.text = tr("RING_EQUIP_ACTION") % (model().first_empty_slot() + 1)
	tooltip_combo.visible = not tooltip_combo.text.is_empty()
	tooltip_panel.show()
	tooltip_panel.size = Vector2(UITheme.px(400), 0)
	_place_tooltip.call_deferred()

func _definition(id: String) -> Dictionary:
	var definition = Modules.DEFINITIONS.get(id, {})
	return definition if definition is Dictionary else {}

func _effect_number(key: String, fallback: float) -> float:
	var value = model().effect(key)
	return fallback if value == null or not is_finite(float(value)) else float(value)

func _category_for(id: String, definition: Dictionary = {}) -> String:
	var category := String(definition.get("category", definition.get("pool", ""))).to_lower()
	if category in ["trace", "sweep", "link"]:
		return category
	# Legacy definitions predate category metadata. Their fallback keeps filters
	# useful while preserving the five original IDs and their visual order.
	if id in ["focus", "precision", "trail_integrator", "long_baseline", "dual_processor"]:
		return "trace"
	if id in ["wide", "afterglow_archive", "sweep_optics", "wide_correlation"]:
		return "sweep"
	if id in ["record", "revisit", "relay_bus", "reference_bus", "shutter_weave"]:
		return "link"
	return ""

func _source_for(id: String, definition: Dictionary = {}) -> String:
	var source := String(definition.get("source", "")).to_lower()
	if source in ["purchase", "research", "sample"]:
		return source
	return "purchase" if id in ["focus", "wide", "precision", "record", "revisit"] else "research"

func _matches_filter(id: String, definition: Dictionary) -> bool:
	match inventory_filter:
		"owned":
			return id in model().purchased
		"trace", "sweep", "link":
			return _category_for(id, definition) == inventory_filter
		_:
			return true

func _filter_label(filter_id: String) -> String:
	return tr("MODX_FILTER_%s" % filter_id.to_upper())

func _category_label(category: String) -> String:
	if category.is_empty():
		return tr("MODX_CATEGORY_OTHER")
	return tr("MODX_CATEGORY_%s" % category.to_upper())

func _translation_or_empty(key: String) -> String:
	var translated := TranslationServer.translate(key)
	return "" if translated == key else String(translated)

func _format_translation(key: String, arguments: Array, fallback: String) -> String:
	var template := _translation_or_empty(key)
	return fallback if template.is_empty() else template % arguments

func _acquisition_route(id: String, definition: Dictionary) -> String:
	var category := _category_for(id, definition)
	var category_label := _category_label(category)
	match _source_for(id, definition):
		"research":
			var research_id := String(definition.get("research_id", definition.get("research", "")))
			if not research_id.is_empty():
				var research_key := "EXT_RESEARCH_%s_NAME" % research_id.trim_prefix("ext_").to_upper()
				var research_name := _translation_or_empty(research_key)
				if not research_name.is_empty():
					return _format_translation("MODX_ACQUIRE_RESEARCH", [research_name], "Research grant · %s" % research_name)
			return _format_translation("MODX_ACQUIRE_RESEARCH", [category_label], "Research grant · %s" % category_label)
		"sample":
			return tr("MODX_DRAW_ROUTE")
		_:
			return tr("MODX_ACQUIRE_PURCHASE")

func _conditional_summary(installed_ids: Array[String]) -> String:
	var lines: Array[String] = []
	var seen: Array[String] = []
	for id in installed_ids:
		if id in seen: continue
		seen.append(id)
		var definition := _definition(id)
		var text := String(definition.get("conditional_desc", definition.get("conditional", "")))
		var is_conditional := not text.is_empty() or id in ["trail_integrator", "sweep_optics", "relay_bus", "long_baseline", "dual_processor", "afterglow_archive", "wide_correlation", "reference_bus", "shutter_weave"]
		if is_conditional:
			var short_name := _translation_or_empty("MODULE_%s_SHORT" % id.to_upper())
			if short_name.is_empty():
				short_name = id.replace("_", " ").capitalize()
			lines.append("· " + short_name + (" ×%d" % installed_ids.count(id) if installed_ids.count(id) > 1 else ""))
	return tr("MODX_CONDITIONAL_NONE") if lines.is_empty() else tr("MODX_CONDITIONAL") + "  " + "  ".join(lines)

func set_inventory_filter(filter_id: String) -> void:
	if filter_id not in INVENTORY_FILTERS:
		return
	inventory_filter = filter_id
	if is_open():
		refresh(false)

func _filter_action(parent: Control, p: Vector2, dimensions: Vector2, filter_id: String) -> Button:
	var button := Button.new()
	button.position = p * UITheme.SCALE
	button.size = dimensions * UITheme.SCALE
	_empty_button_style(button)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", UITheme.size_px(POPUP_META_SPEC_SIZE))
	button.add_theme_color_override("font_color", UITheme.INK_MID)
	button.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
	button.pressed.connect(set_inventory_filter.bind(filter_id))
	button.draw.connect(func():
		var color := UITheme.ACCENT_LINE if inventory_filter == filter_id else Color(UITheme.INK_LOW, 0.55)
		button.draw_line(Vector2(0, button.size.y - UITheme.px(2)), button.size - Vector2(0, UITheme.px(2)), color, UITheme.px(1), true)
	)
	parent.add_child(button)
	return button

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
	style.content_margin_top = UITheme.px(18)
	style.content_margin_bottom = UITheme.px(18)
	tooltip_panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(tooltip_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UITheme.size_px(9))
	tooltip_panel.add_child(column)
	var list: Array[Label] = []
	for spec in [
		[POPUP_ACTION_SPEC_SIZE, UITheme.TOOLTIP_NAME],
		[POPUP_META_SPEC_SIZE, UITheme.INK_MID],
		[POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_BODY],
		[POPUP_BODY_SPEC_SIZE, UITheme.TOOLTIP_BODY],
		[POPUP_ACTION_SPEC_SIZE, UITheme.TOOLTIP_ACTION],
	]:
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
	tooltip_action.add_theme_font_override("font", UITheme.sans("medium"))
	tooltip_panel.hide()

func _draw_surface() -> void:
	surface.draw_line(Vector2(140, 322) * UITheme.SCALE, Vector2(1780, 322) * UITheme.SCALE, Color(UITheme.INK_MID, 0.3), UITheme.px(1), true)
	var center := RING_CENTER * UITheme.SCALE
	surface.draw_arc(center, UITheme.px(RING_RADIUS), 0, TAU, 128, Color(UITheme.INK_MID, 0.42), UITheme.px(1), true)
	surface.draw_arc(center, UITheme.px(16), 0, TAU, 48, Color(UITheme.INSTRUMENT_ARC, 0.35), UITheme.px(1), true)
	surface.draw_circle(center, UITheme.px(2.2), UITheme.INSTRUMENT_ARC)
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		surface.draw_line(center + direction * UITheme.px(22), center + direction * UITheme.px(28), Color(UITheme.INSTRUMENT_ARC, 0.45), UITheme.px(1), true)
	for y in [402, 760]:
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
	button.add_theme_font_size_override("font_size", UITheme.size_px(POPUP_ACTION_SPEC_SIZE))
	button.add_theme_color_override("font_color", UITheme.TOOLTIP_ACTION)
	button.add_theme_color_override("font_hover_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_focus_color", UITheme.ACCENT_TEXT)
	button.pressed.connect(callback)
	button.draw.connect(func(): button.draw_line(Vector2(0, button.size.y - 1), button.size - Vector2(0, 1), Color(UITheme.TOOLTIP_ACTION, 0.7), UITheme.px(1), true))
	parent.add_child(button)
	return button

func place_launcher() -> void:
	if launcher == null or game == null: return
	launcher.position = game.upgrade_tree.ATLAS_ACTION_ORIGIN
	launcher.size = game.upgrade_tree.ATLAS_ACTION_SIZE
	launcher.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if draw_launcher != null:
		draw_launcher.position = launcher.position + game.upgrade_tree.ATLAS_ACTION_STEP
		draw_launcher.size = launcher.size
		draw_launcher.alignment = HORIZONTAL_ALIGNMENT_LEFT
