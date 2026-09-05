extends CanvasLayer

signal return_requested
const Modules = preload("res://scripts/observation_modules.gd")
const SkyView = preload("res://scripts/andromeda_sky.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const TARGET_SPECS := [
	["star_a", "stars", Vector2(0.22, 0.40), 3.8, 2000.0],
	["star_b", "stars", Vector2(0.28, 0.46), 3.8, 2000.0],
	["star_c", "stars", Vector2(0.33, 0.40), 3.8, 2000.0],
	["g1", "cluster", Vector2(0.73, 0.46), 10.0, 8000.0],
	["cloud_a", "cloud", Vector2(0.46, 0.70), 5.0, 2800.0],
	["cloud_b", "cloud", Vector2(0.51, 0.65), 5.0, 2800.0],
	["cloud_c", "cloud", Vector2(0.56, 0.70), 5.0, 2800.0],
]

var game: Node
var modules = Modules.new()
var active := false
var modules_open := false
var targets: Array[Dictionary] = []
var tracked_indices: Array[int] = []
var cursor := Vector2.ZERO
var active_seconds := 0.0
var round_number := 1
var round_remaining := 60.0
var records := {"stars": 0, "cluster": 0, "cloud": 0}
var previous_pause := false
var ui: Control
var sky: Control
var menu: Control
var header: Label
var status: Label
var data_label: Label
var gain_label: Label
var gain_timer := 0.0
var recent_gain := 0.0
var equipped_label: Label
var hint: Label
var record_label: Label
var module_button: Button
var back_button: Button
var settings_button: Button
var menu_title: Label
var menu_intro: Label
var slot_label: Label
var continue_button: Button
var unequip_button: Button
var module_rows: Dictionary = {}
var last_ui_second := -1

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_make_targets()
	visible = false
	set_process(false)

func setup(controller: Node) -> void:
	game = controller
	game.settings.language_changed.connect(func(_locale): refresh_ui())
	game.settings.input_bindings_changed.connect(refresh_ui)
	game.progression.state_changed.connect(refresh_ui)
	refresh_ui()

func _make_targets() -> void:
	targets.clear()
	for spec in TARGET_SPECS:
		targets.append({"id": spec[0], "kind": spec[1], "position": spec[2], "duration": spec[3], "reward": spec[4], "progress": 0.0, "cooldown": 0.0})

func is_open() -> bool:
	return active

func open_stage() -> bool:
	if active or game == null or not game.progression.galaxy_unlocked():
		return false
	previous_pause = get_tree().paused
	get_tree().paused = true
	active = true
	visible = true
	modules_open = false
	menu.visible = false
	game.hud.visible = false
	game.sound.reset_streak_audio()
	game.progression.reset_manual_combo()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if round_remaining <= 0.0:
		round_remaining = game.progression.get_observation_duration()
	set_process(true)
	refresh_ui()
	return true

func close_stage() -> void:
	if not active:
		return
	active = false
	visible = false
	modules_open = false
	tracked_indices.clear()
	menu.visible = false
	set_process(false)
	game.hud.visible = true
	game.hud.tutorial_replay_button.disabled = game.hud.is_phase_summary_open()
	game.hud.tutorial_replay_button.tooltip_text = ""
	get_tree().paused = previous_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func reset() -> void:
	close_stage()
	modules.load_save_data({})
	_make_targets()
	records = {"stars": 0, "cluster": 0, "cloud": 0}
	active_seconds = 0.0
	gain_timer = 0.0
	recent_gain = 0.0
	round_number = 1
	round_remaining = 60.0

func settings_open() -> bool:
	return game != null and game.hud.is_settings_open()

func open_settings() -> void:
	if not active:
		return
	layer = 70
	game.hud.visible = true
	game.hud.open_settings()
	game.hud.tutorial_replay_button.disabled = true
	game.hud.tutorial_replay_button.tooltip_text = tr("ANDROMEDA_TUTORIAL_HINT")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_modules() -> void:
	if not active or settings_open():
		return
	modules_open = not modules_open
	menu.visible = modules_open
	tracked_indices.clear()
	if not modules_open and round_remaining <= 0.0:
		round_number += 1
		round_remaining = game.progression.get_observation_duration()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if modules_open else Input.MOUSE_MODE_HIDDEN
	refresh_ui()
	if modules_open:
		continue_button.grab_focus()
	else:
		get_viewport().gui_release_focus()

func purchase_module(id: String) -> bool:
	if not active or not modules_open or settings_open():
		return false
	if not modules.purchase(id, game.progression):
		return false
	game.sound.play_upgrade()
	refresh_ui()
	game._autosave_active_slot()
	return true

func equip_module(id: String) -> bool:
	if not active or not modules_open or settings_open() or not modules.equip(id):
		return false
	game.sound.play_slot_confirm()
	refresh_ui()
	game._autosave_active_slot()
	return true

func tracking_radius() -> float:
	return game.progression.get_tracking_radius() * float(modules.effect("radius")) if game != null else 52.0

func _process(delta: float) -> void:
	if not active:
		return
	if settings_open():
		tracked_indices.clear()
		return
	layer = 90
	game.hud.visible = false
	cursor = ui.get_local_mouse_position()
	var pointer_on_ui := cursor.y < 100.0 or cursor.y > ui.size.y - 70.0
	var hold := Input.is_action_pressed("nw_observe") and not pointer_on_ui
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if modules_open or pointer_on_ui else Input.MOUSE_MODE_HIDDEN
	advance_observation(delta / maxf(Engine.time_scale, 0.001), cursor, hold)
	sky.queue_redraw()

func advance_observation(delta: float, pointer: Vector2, held: bool, allow_automatic: bool = true) -> void:
	tracked_indices.clear()
	if not active or modules_open or settings_open() or delta <= 0.0:
		return
	var step := minf(delta, round_remaining)
	if step <= 0.0:
		return
	cursor = pointer
	active_seconds += step
	gain_timer = maxf(0.0, gain_timer - step)
	gain_label.visible = gain_timer > 0.0
	if gain_timer <= 0.0:
		recent_gain = 0.0
	game.elapsed_time += step
	round_remaining = maxf(0.0, round_remaining - step)
	var radius := tracking_radius()
	var candidates: Array[int] = []
	for index in range(targets.size()):
		var target := targets[index]
		if target.cooldown > 0.0:
			target.cooldown = maxf(0.0, target.cooldown - step)
			continue
		if held and pointer.distance_to(target.position * ui.size) <= radius:
			candidates.append(index)
	candidates.sort_custom(func(a, b): return pointer.distance_squared_to(targets[a].position * ui.size) < pointer.distance_squared_to(targets[b].position * ui.size))
	for index in candidates.slice(0, int(modules.effect("targets"))):
		tracked_indices.append(index)
		var target := targets[index]
		var centering := 1.0 - clampf(pointer.distance_to(target.position * ui.size) / radius, 0.0, 1.0)
		var speed: float = game.progression.get_manual_analysis_speed_multiplier() * game.progression.get_analysis_speed_multiplier("galaxy") * float(modules.effect("speed"))
		target.progress = minf(1.0, target.progress + step * speed * lerpf(0.8, 1.2, centering) / target.duration)
		if target.progress >= 1.0:
			_complete_target(index, true)
	# The existing dishes keep basic stellar fields productive while the cursor
	# tackles the cluster or cloud. They never gain module speed or target count.
	if allow_automatic:
		var dishes: int = game.progression.get_dish_count()
		for index in range(mini(dishes, 3)):
			var target := targets[index]
			if target.cooldown > 0.0 or index in tracked_indices:
				continue
			target.progress = minf(1.0, target.progress + step * 0.035)
			if target.progress >= 1.0:
				_complete_target(index, false)
	game.autosave_elapsed += step
	if game.autosave_elapsed >= game.AUTOSAVE_INTERVAL_SECONDS:
		game.autosave_elapsed = 0.0
		game._autosave_active_slot()
	if round_remaining <= 0.0:
		toggle_modules()
		game._autosave_active_slot()
	if int(round_remaining) != last_ui_second:
		last_ui_second = int(round_remaining)
		refresh_ui()

func _complete_target(index: int, manual: bool) -> void:
	var target := targets[index]
	var reward: float = target.reward * game.progression.get_observation_value_multiplier("common", 1)
	if manual:
		reward = game.progression.add_galactic_observation(reward)
		game.sound.play_success(1.0, 1, 0.3)
	else:
		reward = game.progression.add_observation(reward * 0.45, false, 1.0)
		game.sound.play_automatic_tick()
	# Keep the suspended atmospheric round's accounting independent of this sky.
	game.phase_start_total_data += reward
	game.phase_start_successes += 1
	if manual:
		game.phase_start_manual_successes += 1
	else:
		game.phase_start_automatic_successes += 1
	records[target.kind] += 1
	target.progress = 0.0
	target.cooldown = 7.0
	recent_gain += reward
	gain_timer = 1.8
	refresh_ui()

func _return_to_map() -> void:
	close_stage()
	return_requested.emit()

func _label(text: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.sans())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Control, callback: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", UITheme.ACCENT_TEXT)
	button.add_theme_color_override("font_hover_color", UITheme.INK_MAX)
	button.add_theme_color_override("font_disabled_color", UITheme.INK_MID)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	sky = SkyView.new()
	sky.stage = self
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(sky)
	header = _label("", 25, UITheme.INK_HIGH)
	header.position = Vector2(38, 23)
	ui.add_child(header)
	status = _label("", 11, UITheme.INK_MID)
	status.position = Vector2(40, 62)
	ui.add_child(status)
	module_button = _button(ui, toggle_modules)
	module_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	module_button.offset_left = -250
	module_button.offset_right = -38
	module_button.offset_top = 28
	module_button.offset_bottom = 65
	data_label = _label("", 20, UITheme.INK_HIGH)
	data_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	data_label.position = Vector2(38, -56)
	ui.add_child(data_label)
	gain_label = _label("", 13, UITheme.GAIN)
	gain_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ui.add_child(gain_label)
	equipped_label = _label("", 12, UITheme.ACCENT_TEXT)
	equipped_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	equipped_label.position = Vector2(39, -28)
	ui.add_child(equipped_label)
	hint = _label("", 12, UITheme.HINT)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-260, -38)
	hint.size.x = 520
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(hint)
	settings_button = _button(ui, open_settings)
	settings_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	settings_button.offset_left = -170
	settings_button.offset_right = -38
	settings_button.offset_top = -50
	settings_button.offset_bottom = -16
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color("090B10")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(dim)
	menu_title = _label("", 30, UITheme.INK_HIGH)
	menu_title.position = Vector2(64, 60)
	menu.add_child(menu_title)
	menu_intro = _label("", 13, UITheme.INK_MID)
	menu_intro.position = Vector2(66, 108)
	menu_intro.size = Vector2(1000, 45)
	menu_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(menu_intro)
	slot_label = _label("", 15, UITheme.ACCENT_TEXT)
	slot_label.position = Vector2(66, 164)
	menu.add_child(slot_label)
	var index := 0
	for id in Modules.DEFINITIONS:
		var row := Control.new()
		row.position = Vector2(64, 225 + index * 122)
		row.size = Vector2(1024, 112)
		menu.add_child(row)
		var line := ColorRect.new()
		line.size = Vector2(1024, 1)
		line.color = UITheme.ACCENT_DEEP
		row.add_child(line)
		var title := _label("", 20, UITheme.INK_HIGH)
		title.position = Vector2(0, 18)
		row.add_child(title)
		var description := _label("", 13, UITheme.TOOLTIP_BODY)
		description.position = Vector2(0, 53)
		description.size = Vector2(680, 50)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)
		var action := _button(row, func(): _module_action(id))
		action.position = Vector2(740, 20)
		action.size = Vector2(275, 58)
		module_rows[id] = {"title": title, "description": description, "action": action}
		index += 1
	record_label = _label("", 12, UITheme.INK_MID)
	record_label.position = Vector2(66, 490)
	menu.add_child(record_label)
	unequip_button = _button(menu, func(): equip_module(""))
	unequip_button.position = Vector2(64, 545)
	unequip_button.size = Vector2(160, 42)
	back_button = _button(menu, _return_to_map)
	back_button.position = Vector2(245, 545)
	back_button.size = Vector2(180, 42)
	continue_button = _button(menu, toggle_modules)
	continue_button.position = Vector2(850, 540)
	continue_button.size = Vector2(240, 48)
	menu.visible = false

func _module_action(id: String) -> void:
	if id in modules.purchased:
		equip_module(id)
	else:
		purchase_module(id)

func refresh_ui() -> void:
	if not active or game == null or header == null:
		return
	header.text = tr("ANDROMEDA_TITLE")
	status.text = tr("ANDROMEDA_STATUS") % [round_number, ceili(round_remaining)]
	if game.hud.autosave_failed:
		status.text += " · " + tr("AUTOSAVE_FAILURE")
	data_label.text = UITheme.grouped_integer(int(game.progression.observation_data))
	gain_label.text = "+" + UITheme.grouped_integer(int(recent_gain))
	gain_label.position = Vector2(52 + data_label.get_minimum_size().x, -50)
	gain_label.visible = gain_timer > 0.0
	var name := tr("MODULE_NONE") if modules.equipped.is_empty() else tr("MODULE_%s_NAME" % modules.equipped.to_upper())
	equipped_label.text = tr("MODULE_SLOT") % name
	module_button.text = tr("MODULE_OPEN") % game.settings.binding_label(&"nw_chart")
	settings_button.text = tr("SETTINGS_BUTTON")
	hint.text = tr("ANDROMEDA_HINT")
	menu_title.text = tr("MODULE_TITLE")
	menu_intro.text = tr("MODULE_INTRO")
	slot_label.text = tr("MODULE_BALANCE") % [UITheme.grouped_integer(int(game.progression.observation_data)), name]
	for id in module_rows:
		var row: Dictionary = module_rows[id]
		row.title.text = tr("MODULE_%s_NAME" % id.to_upper())
		row.description.text = tr("MODULE_%s_DESC" % id.to_upper())
		var owned: bool = id in modules.purchased
		var cost: float = Modules.DEFINITIONS[id].cost
		row.action.disabled = (owned and modules.equipped == id) or (not owned and game.progression.observation_data < cost)
		row.action.text = tr("MODULE_EQUIPPED") if modules.equipped == id else (tr("MODULE_EQUIP") if owned else tr("MODULE_BUY") % UITheme.grouped_integer(int(cost)))
	unequip_button.text = tr("MODULE_UNEQUIP")
	unequip_button.disabled = modules.equipped.is_empty()
	back_button.text = tr("ANDROMEDA_RETURN")
	continue_button.text = tr("ANDROMEDA_NEXT_ROUND") if round_remaining <= 0.0 else tr("ANDROMEDA_RESUME")
	record_label.text = tr("ANDROMEDA_RECORDS") % [records.stars, records.cluster, records.cloud]
	sky.queue_redraw()

func get_save_data() -> Dictionary:
	var states: Array = []
	for target in targets:
		states.append({"id": target.id, "progress": target.progress, "cooldown": target.cooldown})
	return {"version": 1, "active": active, "modules": modules.get_save_data(), "active_seconds": active_seconds, "round_number": round_number, "round_remaining": round_remaining, "records": records.duplicate(), "targets": states}

func load_save_data(data: Dictionary) -> void:
	reset()
	if data.get("version", 1) != 1:
		return
	var saved_modules = data.get("modules", {})
	modules.load_save_data(saved_modules if saved_modules is Dictionary else {})
	active_seconds = _number(data.get("active_seconds", 0.0), 0.0, 1000000000.0)
	round_number = int(_number(data.get("round_number", 1), 1.0, 1000000.0))
	round_remaining = _number(data.get("round_remaining", 60.0), 0.0, 60.0)
	var saved_records = data.get("records", {})
	if saved_records is Dictionary:
		for kind in records:
			records[kind] = int(_number(saved_records.get(kind, 0), 0.0, 1000000000.0))
	var states = data.get("targets", [])
	if states is Array:
		for state in states:
			if not (state is Dictionary):
				continue
			for target in targets:
				if state.get("id", "") == target.id:
					target.progress = _number(state.get("progress", 0.0), 0.0, 0.999)
					target.cooldown = _number(state.get("cooldown", 0.0), 0.0, 7.0)
	refresh_ui()

func _number(value, minimum: float, maximum: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return minimum
	return clampf(float(value), minimum, maximum)
