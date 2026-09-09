extends CanvasLayer

const UITheme = preload("res://scripts/ui_theme.gd")
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
const INVENTORY_FILTERS := ["all", "trace", "sweep", "link"]

const RingSlot = preload("res://scripts/ui/module_ring_slot.gd")

const InventoryTile = preload("res://scripts/ui/module_inventory_tile.gd")

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
var inventory_empty: Label
var inventory_scroll: ScrollContainer
var inventory_grid: GridContainer
var filter_buttons: Dictionary = {}
var inventory_filter := "all"
var summary_heading: Label
var summary: Label
var summary_details: Label
var capacity_label: Label
var help_button: Button
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
var tooltip_from_focus := false

func model():
	return game.deep_sky.modules

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var view = preload("res://scenes/ui/module_popup.tscn").instantiate()
	capacity_label = view.get_node("%CapacityLabel")
	close_button = view.get_node("%CloseButton")
	draw_button = view.get_node("%DrawButton")
	draw_window = view.get_node("%DrawWindow")
	filter_buttons = {"all": view.get_node("%FilterButtonsAll"), "trace": view.get_node("%FilterButtonsTrace"), "sweep": view.get_node("%FilterButtonsSweep"), "link": view.get_node("%FilterButtonsLink")}
	heading = view.get_node("%Heading")
	help_button = view.get_node("%HelpButton")
	hint = view.get_node("%Hint")
	instructions = view.get_node("%Instructions")
	inventory_count = view.get_node("%InventoryCount")
	inventory_empty = view.get_node("%InventoryEmpty")
	inventory_grid = view.get_node("%InventoryGrid")
	inventory_heading = view.get_node("%InventoryHeading")
	inventory_scroll = view.get_node("%InventoryScroll")
	overlay = view
	slot_captions = [view.get_node("%SlotCaptions0"), view.get_node("%SlotCaptions1"), view.get_node("%SlotCaptions2"), view.get_node("%SlotCaptions3"), view.get_node("%SlotCaptions4")]
	summary = view.get_node("%Summary")
	summary_details = view.get_node("%SummaryDetails")
	summary_heading = view.get_node("%SummaryHeading")
	surface = view.get_node("%Surface")
	tooltip_action = view.get_node("%TooltipPanel").get_node("%TooltipAction")
	tooltip_code = view.get_node("%TooltipPanel").get_node("%TooltipCode")
	tooltip_combo = view.get_node("%TooltipPanel").get_node("%TooltipCombo")
	tooltip_effect = view.get_node("%TooltipPanel").get_node("%TooltipEffect")
	tooltip_name = view.get_node("%TooltipPanel").get_node("%TooltipName")
	tooltip_panel = view.get_node("%TooltipPanel")
	add_child(view)
	view.get_node("%Surface").draw.connect(_draw_surface)
	view.get_node("%CloseButton").pressed.connect(close)
	view.get_node("%FilterButtonsAll").pressed.connect(set_inventory_filter.bind("all"))
	view.get_node("%FilterButtonsTrace").pressed.connect(set_inventory_filter.bind("trace"))
	view.get_node("%FilterButtonsSweep").pressed.connect(set_inventory_filter.bind("sweep"))
	view.get_node("%FilterButtonsLink").pressed.connect(set_inventory_filter.bind("link"))
	view.get_node("%DrawButton").pressed.connect(open_draw)
	for index in Modules.MAX_SLOTS:
		var slot: Button = preload("res://scenes/ui/module_ring_slot.tscn").instantiate()
		slot.owner_popup = self
		slot.index = index
		# The ring's placement follows slot count; its control/style is authored.
		slot.position = (RING_CENTER + Vector2.from_angle(-PI / 2 + TAU * index / 5.0) * RING_RADIUS - Vector2.ONE * SLOT_RADIUS) * UITheme.SCALE
		surface.add_child(slot)
		slot.pressed.connect(remove_module.bind(index))
		slot.mouse_entered.connect(show_slot_tooltip.bind(index))
		slot.mouse_exited.connect(_on_tooltip_mouse_exited)
		slot.gui_input.connect(_on_slot_pointer_input.bind(index))
		slot.focus_entered.connect(show_slot_tooltip.bind(index, true))
		slot.focus_exited.connect(_on_tooltip_focus_exited)
		slots.append(slot)
	for id in Modules.DEFINITIONS:
		var tile: Button = preload("res://scenes/ui/module_inventory_tile.tscn").instantiate()
		tile.owner_popup = self
		tile.module_id = id
		inventory_grid.add_child(tile)
		tile.pressed.connect(equip_from_inventory.bind(id))
		tile.mouse_entered.connect(show_module_tooltip.bind(id))
		tile.mouse_exited.connect(_on_tooltip_mouse_exited)
		tile.gui_input.connect(_on_tile_pointer_input.bind(id))
		tile.focus_entered.connect(_on_tile_focus.bind(id))
		tile.focus_exited.connect(_on_tooltip_focus_exited)
		owned_buttons[id] = tile
	for id in filter_buttons:
		filter_buttons[id].draw.connect(_draw_filter.bind(id))
	for button in [close_button, help_button, draw_button]:
		button.draw.connect(_draw_action_underline.bind(button))
	help_button.pressed.connect(func(): refresh(false))
	draw_window.setup(self)
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
	help_button.set_pressed_no_signal(false)
	game.hud.set_external_readouts_covered(true)
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
	game.hud.set_external_readouts_covered(false)
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
		if tooltip_from_focus:
			var control: Control = owned_buttons.get(hover_id) if hover_kind == "module" else slots[hover_slot]
			if control == null or not control.is_visible_in_tree() or not control.has_focus():
				hide_tooltip()
				return
			# Recompute after scrolling/layout, but never replace a keyboard
			# anchor with the position of an idle mouse.
			tooltip_pointer = overlay.get_global_transform().affine_inverse() * control.get_global_rect().get_center()
		else:
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
	inventory_count.text = tr("MODX_COUNT") % model().purchased.size()
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
	var visible_count := 0
	for id in owned_buttons:
		var tile: InventoryTile = owned_buttons[id]
		var definition: Dictionary = _definition(id)
		tile.visible = _matches_filter(id, definition)
		if tile.visible:
			visible_count += 1
		tile.update_state(id in model().purchased, id in installed_ids, _category_for(id, definition))
		# A filtered grid keeps its original child order, so keyboard focus remains
		# stable as modules are added to the catalog later.
		tile.focus_mode = Control.FOCUS_ALL if tile.visible else Control.FOCUS_NONE
	inventory_empty.visible = visible_count == 0
	inventory_empty.text = tr("MODX_EMPTY" if model().purchased.is_empty() else "MODX_EMPTY_CATEGORY")
	summary_heading.text = tr("MODX_CURRENT")
	var old_speed := _effect_number("speed", 1.0)
	var new_speed := _effect_number("new_speed", 1.0)
	var manual_speed := old_speed * new_speed
	summary.text = _format_translation("MODX_STATIC_SUMMARY", [manual_speed, _effect_number("radius", 1.0), _effect_number("m31_value", 1.0), _effect_number("m31_cooldown", 1.0)], "Manual ×%.2f · Radius ×%.2f · M31 ×%.2f · Wait ×%.2f" % [manual_speed, _effect_number("radius", 1.0), _effect_number("m31_value", 1.0), _effect_number("m31_cooldown", 1.0)])
	if not help_button.button_pressed:
		summary.text = _changed_summary(manual_speed)
	summary.visible = not summary.text.is_empty()
	summary_details.text = _conditional_summary(installed_ids)
	summary_details.visible = not summary_details.text.is_empty()
	capacity_label.text = tr("MODX_SLOTS_USED") % [installed_ids.size(), model().unlocked_slots]
	capacity_label.visible = installed_ids.is_empty() or help_button.button_pressed
	instructions.text = tr("EXT_SAMPLES_COUNT") % game.deep_sky.samples
	draw_button.text = tr("DRAW_OPEN")
	help_button.text = tr("UI_DETAILS_HIDE" if help_button.button_pressed else "MODX_HELP_SHOW")
	hint.text = tr("MODX_EQUIP_HINT") if not game.hud.autosave_failed else tr("AUTOSAVE_FAILURE") % game.active_save_slot
	hint.visible = help_button.button_pressed or game.hud.autosave_failed
	if inventory_scroll != null:
		inventory_scroll.queue_redraw()
	surface.queue_redraw()
	_update_tooltip()

func show_module_tooltip(id: String, from_focus: bool = false) -> void:
	if not owned_buttons.has(id) or id not in model().purchased or not owned_buttons[id].visible:
		hide_tooltip()
		return
	hover_kind = "module"
	hover_id = id
	hover_slot = -1
	tooltip_from_focus = from_focus
	tooltip_pointer = owned_buttons[id].get_global_rect().get_center()
	_update_tooltip()

func _on_tile_focus(id: String) -> void:
	show_module_tooltip(id, true)
	var tile: InventoryTile = owned_buttons.get(id)
	if tile != null and inventory_scroll != null:
		inventory_scroll.ensure_control_visible(tile)

func show_slot_tooltip(index: int, from_focus: bool = false) -> void:
	hover_kind = "slot"
	hover_slot = index
	hover_id = model().slots[index]
	tooltip_from_focus = from_focus
	tooltip_pointer = slots[index].get_global_rect().get_center()
	_update_tooltip()

func hide_tooltip() -> void:
	hover_kind = ""
	tooltip_from_focus = false
	tooltip_panel.hide()

func _on_tooltip_mouse_exited() -> void:
	if not tooltip_from_focus:
		hide_tooltip()

func _on_tooltip_focus_exited() -> void:
	if tooltip_from_focus:
		hide_tooltip()

func _on_tile_pointer_input(event: InputEvent, id: String) -> void:
	if tooltip_from_focus and event is InputEventMouseMotion and not event.relative.is_zero_approx():
		show_module_tooltip(id)

func _on_slot_pointer_input(event: InputEvent, index: int) -> void:
	if tooltip_from_focus and event is InputEventMouseMotion and not event.relative.is_zero_approx():
		show_slot_tooltip(index)

func _update_tooltip() -> void:
	if hover_kind.is_empty() or not is_open() or is_draw_open():
		tooltip_panel.hide()
		return
	var id := hover_id
	if hover_kind == "module" and (id not in model().purchased or not owned_buttons.has(id) or not owned_buttons[id].visible):
		hide_tooltip()
		return
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
	# Owned modules already describe their conditions and tradeoffs in the effect.
	# Acquisition guidance remains useful for locked/empty slots only.
	tooltip_combo.visible = not tooltip_combo.text.is_empty() and (hover_kind == "slot" and (hover_slot >= model().unlocked_slots or model().slots[hover_slot].is_empty()))
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
	if id not in model().purchased:
		return false
	match inventory_filter:
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

func _changed_summary(manual_speed: float) -> String:
	var parts: Array[String] = []
	var stats := {"MODX_STAT_MANUAL": manual_speed, "MODX_STAT_RADIUS": _effect_number("radius", 1.0), "MODX_STAT_M31": _effect_number("m31_value", 1.0), "MODX_STAT_WAIT": _effect_number("m31_cooldown", 1.0)}
	for key in stats:
		var value: float = stats[key]
		if is_equal_approx(value, 1.0):
			continue
		var delta := (value - 1.0) * 100.0
		var number := String.num(delta, 1).trim_suffix(".0")
		parts.append(tr(key) + " " + ("+" if delta > 0.0 else "") + number + "%")
	return " · ".join(parts)


func _conditional_summary(installed_ids: Array[String]) -> String:
	var count := 0
	var seen: Array[String] = []
	for id in installed_ids:
		if id in seen: continue
		seen.append(id)
		var definition := _definition(id)
		var text := String(definition.get("conditional_desc", definition.get("conditional", "")))
		var is_conditional := not text.is_empty() or id in ["focus", "trail_integrator", "sweep_optics", "relay_bus", "long_baseline", "dual_processor", "afterglow_archive", "wide_correlation", "reference_bus", "shutter_weave"]
		if is_conditional:
			count += 1
	return "" if count == 0 else tr("MODX_CONDITIONAL_COUNT") % count

func set_inventory_filter(filter_id: String) -> void:
	if filter_id not in INVENTORY_FILTERS:
		return
	inventory_filter = filter_id
	if is_open():
		refresh(false)

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

func _text_action(parent: Control, p: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button: Button = preload("res://scenes/ui/module_action.tscn").instantiate()
	button.position = p * UITheme.SCALE
	button.size = dimensions * UITheme.SCALE
	button.pressed.connect(callback)
	button.draw.connect(_draw_action_underline.bind(button))
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

func _draw_filter(filter_id: String) -> void:
	var button: Button = filter_buttons[filter_id]
	var color := UITheme.ACCENT_LINE if inventory_filter == filter_id else Color(UITheme.INK_LOW, 0.55)
	button.draw_line(Vector2(0, button.size.y - UITheme.px(2)), button.size - Vector2(0, UITheme.px(2)), color, UITheme.px(1), true)

func _draw_action_underline(button: Button) -> void:
	button.draw_line(Vector2(0, button.size.y - 1), button.size - Vector2(0, 1), Color(UITheme.TOOLTIP_ACTION, 0.7), UITheme.px(1), true)
