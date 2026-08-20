extends CanvasLayer

signal restart_requested
signal upgrade_tree_requested
signal save_slot_requested(slot: int)
signal load_slot_requested(slot: int)
signal startup_slot_selected(slot: int)
signal tutorial_replay_requested

const Balance = preload("res://scripts/game_balance.gd")

var progression: Node
var settings_controller: Node
var save_game_controller: Node
var root_control: Control
var data_caption_label: Label
var data_label: Label
var data_gain_label: Label
var array_caption_label: Label
var array_progress_label: Label
var array_progress_bar: ProgressBar
var status_label: Label
var time_label: Label
var save_mode_label: Label
var tutorial_label: Label
var banner_label: Label
var tree_panel: PanelContainer
var tree_button: Button
var upgrade_available_label: Label
var next_system_name_label: Label
var next_system_branch_label: Label
var next_system_cost_label: Label
var next_system_bar: ProgressBar
var tracking_panel: PanelContainer
var tracking_name: Label
var tracking_bar: ProgressBar
var debug_panel: PanelContainer
var debug_label: Label
var end_overlay: ColorRect
var end_title: Label
var end_stats: Label
var restart_button: Button
var settings_button: Button
var settings_overlay: Control
var settings_title: Label
var settings_subtitle: Label
var settings_language_label: Label
var settings_hint: Label
var language_selector: OptionButton
var tutorial_replay_button: Button
var settings_close_button: Button
var startup_overlay: Control
var startup_title: Label
var startup_subtitle: Label
var startup_hint: Label
var startup_slot_titles: Array[Label] = []
var startup_slot_details: Array[Label] = []
var startup_slot_buttons: Array[Button] = []
var save_section_label: Label
var save_feedback: Label
var save_slot_titles: Array[Label] = []
var save_slot_details: Array[Label] = []
var save_slot_buttons: Array[Button] = []
var load_slot_buttons: Array[Button] = []
var overwrite_dialog: ConfirmationDialog
var pending_overwrite_slot: int = 0
var banner_timer: float = 0.0
var tutorial_complete: bool = false
var last_runtime_second: int = -1
var last_tracking_text: String = ""
var last_observation_data: float = -1.0
var data_gain_tween: Tween
var last_end_success: bool = false
var paused_by_settings: bool = false
var paused_by_startup: bool = false
var active_save_slot: int = 0
var autosave_status_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	set_process(true)


func bind_progression(controller: Node) -> void:
	progression = controller
	progression.state_changed.connect(_refresh_progression)
	last_observation_data = float(progression.observation_data)
	_refresh_progression()


func bind_settings(controller: Node) -> void:
	settings_controller = controller
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	_sync_language_selector()
	_apply_locale()


func bind_save_games(controller: Node) -> void:
	save_game_controller = controller
	if not save_game_controller.slots_changed.is_connected(_refresh_save_slot_views):
		save_game_controller.slots_changed.connect(_refresh_save_slot_views)
	_refresh_save_slot_views()


func _process(delta: float) -> void:
	if banner_timer > 0.0:
		banner_timer -= delta
		var fade := clampf(banner_timer / 0.3, 0.0, 1.0)
		banner_label.modulate.a = fade
		if banner_timer <= 0.0:
			banner_label.visible = false
	if autosave_status_timer > 0.0:
		autosave_status_timer -= delta
		if autosave_status_timer <= 0.0:
			_refresh_save_mode_label(false)


func set_runtime(seconds: float) -> void:
	var whole_seconds := int(seconds)
	if whole_seconds == last_runtime_second:
		return
	last_runtime_second = whole_seconds
	var minutes := whole_seconds / 60
	var remaining := whole_seconds % 60
	time_label.text = tr("HUD_TIME") % [minutes, remaining]


func show_banner(text: String, color: Color = Color.WHITE, duration: float = 2.5) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.modulate.a = 1.0
	banner_label.visible = true
	banner_timer = duration


func set_tracking(progress: float, target_type: String, multiplier: float, target_count: int = 1) -> void:
	if not tracking_panel.visible:
		tracking_panel.visible = true
	var progress_percent := int(progress * 100.0)
	tracking_bar.value = float(progress_percent)
	var target_name := tr("METEOR_%s" % target_type.to_upper())
	var next_text := tr("HUD_TRACKING_MULTI") % [target_name, progress_percent, target_count] if target_count > 1 else tr("HUD_TRACKING") % [target_name, progress_percent]
	if multiplier > 1.01:
		next_text += "   x%.2f" % multiplier
	if next_text != last_tracking_text:
		last_tracking_text = next_text
		tracking_name.text = next_text


func hide_tracking() -> void:
	if tracking_panel != null and tracking_panel.visible:
		tracking_panel.visible = false
		last_tracking_text = ""


func mark_first_success() -> void:
	if tutorial_complete:
		return
	tutorial_complete = true
	tutorial_label.text = tr("HUD_TUTORIAL_DONE")
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func():
		if is_instance_valid(tutorial_label):
			tutorial_label.visible = false
	)


func reset_tutorial() -> void:
	tutorial_complete = false
	tutorial_label.text = tr("HUD_TUTORIAL_START")
	tutorial_label.visible = true


func restore_tutorial(already_observed: bool) -> void:
	tutorial_complete = already_observed
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") if already_observed else tr("HUD_TUTORIAL_START")
	tutorial_label.visible = not already_observed


func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible


func is_debug_visible() -> bool:
	return debug_panel.visible


func show_end(success: bool, stats_text: String) -> void:
	last_end_success = success
	end_title.text = tr("HUD_END_SUCCESS") if success else tr("HUD_END_FAILURE")
	end_title.add_theme_color_override("font_color", Color("ffe1a3") if success else Color("ff9a86"))
	end_stats.text = stats_text
	end_overlay.visible = true


func hide_end() -> void:
	end_overlay.visible = false


func open_settings() -> void:
	if settings_overlay.visible:
		return
	settings_overlay.visible = true
	settings_overlay.move_to_front()
	paused_by_settings = not get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_language_selector()
	_refresh_save_slots()
	save_feedback.visible = false


func close_settings() -> void:
	if not settings_overlay.visible:
		return
	settings_overlay.visible = false
	if overwrite_dialog != null and overwrite_dialog.visible:
		overwrite_dialog.hide()
	if paused_by_settings:
		get_tree().paused = false
	paused_by_settings = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible


func open_startup_slots() -> void:
	if startup_overlay == null or startup_overlay.visible:
		return
	startup_overlay.visible = true
	startup_overlay.move_to_front()
	paused_by_startup = not get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_startup_slots()


func close_startup_slots() -> void:
	if startup_overlay == null or not startup_overlay.visible:
		return
	startup_overlay.visible = false
	if paused_by_startup:
		get_tree().paused = false
	paused_by_startup = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_startup_slots_open() -> bool:
	return startup_overlay != null and startup_overlay.visible


func set_active_save_slot(slot: int) -> void:
	active_save_slot = slot
	autosave_status_timer = 0.0
	_refresh_save_mode_label(false)
	_refresh_save_slot_views()


func show_autosaved(slot: int) -> void:
	active_save_slot = slot
	autosave_status_timer = 2.2
	_refresh_save_mode_label(true)


func _refresh_save_mode_label(just_saved: bool) -> void:
	if save_mode_label == null:
		return
	save_mode_label.visible = just_saved and active_save_slot > 0
	if not save_mode_label.visible:
		return
	save_mode_label.text = tr("HUD_AUTOSAVED")
	save_mode_label.add_theme_color_override("font_color", Color("8fffe5"))


func _unhandled_key_input(event: InputEvent) -> void:
	if is_settings_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if overwrite_dialog != null and overwrite_dialog.visible:
			overwrite_dialog.hide()
			get_viewport().set_input_as_handled()
			return
		close_settings()
		get_viewport().set_input_as_handled()


func _refresh_progression() -> void:
	if progression == null:
		return
	var current_data := float(progression.observation_data)
	if last_observation_data >= 0.0 and current_data > last_observation_data:
		_show_data_gain(current_data - last_observation_data)
	last_observation_data = current_data
	data_label.text = "%04d" % int(floor(current_data))
	status_label.text = tr("HUD_OBSERVED_COUNT") % progression.success_count
	array_progress_bar.value = float(progression.upgrade_level)
	array_progress_label.text = tr("HUD_ARRAY_PROGRESS") % [
		progression.upgrade_level,
		Balance.UPGRADE_NODES.size()
	]
	var affordable := 0
	for node_id in progression.get_available_nodes():
		if progression.can_purchase(node_id):
			affordable += 1
	tree_button.text = tr("HUD_UPGRADE_BUTTON") % [progression.upgrade_level, Balance.UPGRADE_NODES.size()]
	_refresh_next_system(affordable)


func _refresh_next_system(affordable: int) -> void:
	var definition := _get_recommended_upgrade()
	if definition.is_empty():
		upgrade_available_label.text = tr("HUD_ARRAY_COMPLETE")
		upgrade_available_label.add_theme_color_override("font_color", Color("8fffe5"))
		next_system_name_label.text = tr("HUD_NETWORK_STABLE")
		next_system_name_label.add_theme_color_override("font_color", Color("dffff7"))
		next_system_branch_label.text = "16 / 16"
		next_system_branch_label.add_theme_color_override("font_color", Color("7ee9dc"))
		next_system_cost_label.text = tr("HUD_ALL_SYSTEMS_ONLINE")
		next_system_cost_label.add_theme_color_override("font_color", Color("7ee9dc"))
		next_system_bar.max_value = float(Balance.UPGRADE_NODES.size())
		next_system_bar.value = float(Balance.UPGRADE_NODES.size())
		next_system_bar.add_theme_stylebox_override("fill", _panel_style(Color("52e0b1"), Color("8fffe5"), 3))
		tree_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.064, 0.105, 0.94), Color("52e0b1"), 10))
		return

	var branch_id := String(definition.branch)
	var branch: Dictionary = Balance.BRANCHES.get(branch_id, {})
	var branch_color: Color = branch.get("color", Color("53d6ff"))
	var cost := float(definition.cost)
	var ready: bool = bool(progression.can_purchase(String(definition.id)))
	upgrade_available_label.text = tr("HUD_NEXT_SYSTEM")
	upgrade_available_label.add_theme_color_override("font_color", Color("7f9bb1"))
	next_system_name_label.text = tr("UPGRADE_%s_NAME" % String(definition.id).to_upper())
	next_system_name_label.add_theme_color_override("font_color", Color("e9f8ff"))
	next_system_branch_label.text = tr("BRANCH_%s" % branch_id.to_upper())
	next_system_branch_label.add_theme_color_override("font_color", branch_color)
	next_system_bar.max_value = maxf(1.0, cost)
	next_system_bar.value = minf(float(progression.observation_data), cost)
	next_system_bar.add_theme_stylebox_override("fill", _panel_style(branch_color.darkened(0.18), branch_color, 3))
	if ready:
		next_system_cost_label.text = tr("HUD_READY_INSTALL") % int(cost)
		next_system_cost_label.add_theme_color_override("font_color", Color("8fffe5"))
		tree_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.075, 0.105, 0.96), branch_color, 10))
	else:
		next_system_cost_label.text = tr("HUD_DATA_PROGRESS") % [
			int(floor(progression.observation_data)),
			int(cost)
		]
		next_system_cost_label.add_theme_color_override("font_color", Color("8da7bb"))
		tree_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.064, 0.105, 0.94), branch_color.darkened(0.42), 10))
	if affordable > 1:
		upgrade_available_label.text += tr("HUD_READY_COUNT") % affordable


func _get_recommended_upgrade() -> Dictionary:
	var recommendation: Dictionary = {}
	for node_id in progression.get_available_nodes():
		var definition: Dictionary = Balance.upgrade_definition(node_id)
		if recommendation.is_empty() or int(definition.cost) < int(recommendation.cost):
			recommendation = definition
	return recommendation


func _show_data_gain(amount: float) -> void:
	if amount < 1.0 or data_gain_label == null:
		return
	if data_gain_tween != null and data_gain_tween.is_valid():
		data_gain_tween.kill()
	data_gain_label.text = tr("HUD_DATA_GAIN") % int(round(amount))
	data_gain_label.modulate = Color.WHITE
	data_gain_label.visible = true
	data_label.modulate = Color("8fffe5")
	data_gain_tween = create_tween()
	data_gain_tween.set_parallel(true)
	data_gain_tween.tween_property(data_label, "modulate", Color.WHITE, 0.48)
	data_gain_tween.tween_property(data_gain_label, "modulate:a", 0.0, 0.72).set_delay(0.42)
	data_gain_tween.chain().tween_callback(func():
		if is_instance_valid(data_gain_label):
			data_gain_label.visible = false
	)


func _on_tree_button_pressed() -> void:
	upgrade_tree_requested.emit()


func show_save_feedback(text: String, color: Color) -> void:
	save_feedback.text = text
	save_feedback.add_theme_color_override("font_color", color)
	save_feedback.visible = true


func _on_save_slot_pressed(slot: int) -> void:
	if save_game_controller == null:
		return
	if save_game_controller.has_slot(slot):
		pending_overwrite_slot = slot
		overwrite_dialog.dialog_text = tr("SAVE_OVERWRITE_PROMPT") % slot
		overwrite_dialog.popup_centered(Vector2i(430, 180))
		return
	save_slot_requested.emit(slot)


func _on_load_slot_pressed(slot: int) -> void:
	if save_game_controller != null and save_game_controller.has_slot(slot):
		load_slot_requested.emit(slot)


func _on_startup_slot_pressed(slot: int) -> void:
	if save_game_controller == null:
		return
	var summary: Dictionary = save_game_controller.get_slot_summary(slot)
	if bool(summary.get("exists", false)) and not bool(summary.get("valid", false)):
		return
	startup_slot_selected.emit(slot)


func _on_overwrite_confirmed() -> void:
	if pending_overwrite_slot < 1:
		return
	var slot := pending_overwrite_slot
	pending_overwrite_slot = 0
	save_slot_requested.emit(slot)


func _refresh_save_slots() -> void:
	if save_game_controller == null or save_slot_titles.size() != 3:
		return
	for slot in range(1, 4):
		var index := slot - 1
		var summary: Dictionary = save_game_controller.get_slot_summary(slot)
		save_slot_titles[index].text = tr("SAVE_SLOT_TITLE") % slot
		if slot == active_save_slot:
			save_slot_titles[index].text += tr("SAVE_ACTIVE_MARKER")
		var exists := bool(summary.get("exists", false))
		var valid := bool(summary.get("valid", false))
		load_slot_buttons[index].disabled = not exists or not valid
		save_slot_buttons[index].text = tr("SAVE_OVERWRITE") if exists and valid else tr("SAVE_ACTION")
		load_slot_buttons[index].text = tr("LOAD_ACTION")
		save_slot_details[index].text = _format_slot_details(summary)


func _refresh_save_slot_views() -> void:
	_refresh_save_slots()
	if is_startup_slots_open():
		_refresh_startup_slots()


func _refresh_startup_slots() -> void:
	if save_game_controller == null or startup_slot_titles.size() != 3:
		return
	for slot in range(1, 4):
		var index := slot - 1
		var summary: Dictionary = save_game_controller.get_slot_summary(slot)
		var exists := bool(summary.get("exists", false))
		var valid := bool(summary.get("valid", false))
		startup_slot_titles[index].text = tr("SAVE_SLOT_TITLE") % slot
		startup_slot_details[index].text = _format_slot_details(summary)
		startup_slot_buttons[index].disabled = exists and not valid
		if exists and valid:
			startup_slot_buttons[index].text = tr("STARTUP_CONTINUE")
		elif exists:
			startup_slot_buttons[index].text = tr("STARTUP_UNAVAILABLE")
		else:
			startup_slot_buttons[index].text = tr("STARTUP_NEW_GAME")


func _format_slot_details(summary: Dictionary) -> String:
	var exists := bool(summary.get("exists", false))
	var valid := bool(summary.get("valid", false))
	if not exists:
		return tr("SAVE_SLOT_EMPTY")
	if not valid:
		return tr("SAVE_SLOT_INVALID")
	var saved_at := int(summary.get("saved_at", 0))
	var timezone: Dictionary = Time.get_time_zone_from_system()
	var local_saved_at := saved_at + int(timezone.get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(local_saved_at)
	var stamp := "%04d-%02d-%02d %02d:%02d" % [date.year, date.month, date.day, date.hour, date.minute]
	var seconds := int(summary.get("elapsed_time", 0.0))
	return tr("SAVE_SLOT_META") % [
		stamp, seconds / 60, seconds % 60,
		int(summary.get("observation_data", 0.0)), int(summary.get("upgrade_level", 0))
	]


func _on_language_selected(index: int) -> void:
	if settings_controller == null or index < 0 or index >= language_selector.item_count:
		return
	settings_controller.set_language(String(language_selector.get_item_metadata(index)))


func _on_language_changed(_locale: String) -> void:
	_sync_language_selector()
	_apply_locale()


func _sync_language_selector() -> void:
	if settings_controller == null or language_selector == null:
		return
	var index: int = settings_controller.get_language_index()
	if index >= 0 and index < language_selector.item_count:
		language_selector.select(index)


func _apply_locale() -> void:
	if root_control == null:
		return
	data_caption_label.text = tr("HUD_DATA_CAPTION")
	array_caption_label.text = tr("HUD_ARRAY_CAPTION")
	settings_button.text = "⚙  " + tr("SETTINGS_BUTTON")
	settings_title.text = tr("SETTINGS_TITLE")
	settings_subtitle.text = tr("SETTINGS_SUBTITLE")
	settings_language_label.text = tr("SETTINGS_LANGUAGE")
	settings_hint.text = tr("SETTINGS_LANGUAGE_HINT")
	tutorial_replay_button.text = tr("TUTORIAL_REPLAY")
	startup_title.text = tr("STARTUP_SAVE_TITLE")
	startup_subtitle.text = tr("STARTUP_SAVE_SUBTITLE")
	startup_hint.text = tr("STARTUP_SAVE_HINT")
	save_section_label.text = tr("SAVE_SECTION_TITLE")
	save_feedback.text = tr("SAVE_SECTION_HINT")
	settings_close_button.text = tr("SETTINGS_CLOSE")
	overwrite_dialog.title = tr("SAVE_OVERWRITE_TITLE")
	overwrite_dialog.ok_button_text = tr("SAVE_OVERWRITE_CONFIRM")
	overwrite_dialog.cancel_button_text = tr("SAVE_CANCEL")
	language_selector.set_item_text(0, tr("SETTINGS_ENGLISH"))
	language_selector.set_item_text(1, tr("SETTINGS_KOREAN"))
	tutorial_label.text = tr("HUD_TUTORIAL_DONE") if tutorial_complete else tr("HUD_TUTORIAL_START")
	restart_button.text = tr("HUD_RESTART")
	end_title.text = tr("HUD_END_SUCCESS") if last_end_success else tr("HUD_END_FAILURE")
	debug_label.text = "\n\n".join([
		tr("HUD_DEBUG_TITLE"),
		"\n".join([
			tr("HUD_DEBUG_DATA"), tr("HUD_DEBUG_NEXT"), tr("HUD_DEBUG_ALL"),
			tr("HUD_DEBUG_METEOR"), tr("HUD_DEBUG_RARE"), tr("HUD_DEBUG_SHOWER"),
			tr("HUD_DEBUG_FINAL"), tr("HUD_DEBUG_RESET")
		])
	])
	last_runtime_second = -1
	last_tracking_text = ""
	_refresh_save_mode_label(autosave_status_timer > 0.0)
	if progression != null:
		_refresh_progression()
	_refresh_save_slot_views()


func _build_interface() -> void:
	root_control = Control.new()
	root_control.name = "Interface"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	var interface_font := SystemFont.new()
	interface_font.font_names = PackedStringArray(["Pretendard", "Noto Sans CJK KR", "Malgun Gothic", "Segoe UI"])
	root_control.add_theme_font_override("font", interface_font)

	var top_panel := PanelContainer.new()
	top_panel.name = "TopStatus"
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.anchor_left = 0.02
	top_panel.anchor_right = 0.70
	top_panel.offset_top = 16.0
	top_panel.offset_bottom = 94.0
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.10, 0.82), Color(0.26, 0.48, 0.68, 0.34), 8))
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top_panel)
	var top_margin := MarginContainer.new()
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_margin.add_theme_constant_override("margin_top", 9)
	top_margin.add_theme_constant_override("margin_bottom", 9)
	top_panel.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 16)
	top_margin.add_child(top_row)

	var data_column := VBoxContainer.new()
	data_column.name = "DataReadout"
	data_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	data_column.custom_minimum_size = Vector2(178, 0)
	data_column.add_theme_constant_override("separation", -2)
	top_row.add_child(data_column)
	data_caption_label = _make_label(tr("HUD_DATA_CAPTION"), 10, Color("6f8da6"))
	var data_row := HBoxContainer.new()
	data_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	data_row.add_theme_constant_override("separation", 8)
	data_label = _make_label("0000", 27, Color("d9f7ff"))
	data_gain_label = _make_label(tr("HUD_DATA_GAIN") % 0, 12, Color("8fffe5"))
	data_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	data_gain_label.visible = false
	data_row.add_child(data_label)
	data_row.add_child(data_gain_label)
	data_column.add_child(data_caption_label)
	data_column.add_child(data_row)

	var first_divider := VSeparator.new()
	first_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(first_divider)
	var progress_column := VBoxContainer.new()
	progress_column.name = "ArrayProgress"
	progress_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_column.add_theme_constant_override("separation", 3)
	top_row.add_child(progress_column)
	var progress_header := HBoxContainer.new()
	progress_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	array_caption_label = _make_label(tr("HUD_ARRAY_CAPTION"), 10, Color("6f8da6"))
	array_caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	array_progress_label = _make_label(tr("HUD_ARRAY_PROGRESS") % [0, Balance.UPGRADE_NODES.size()], 11, Color("9fc4d8"))
	array_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_header.add_child(array_caption_label)
	progress_header.add_child(array_progress_label)
	array_progress_bar = ProgressBar.new()
	array_progress_bar.name = "ArrayCompletionBar"
	array_progress_bar.max_value = float(Balance.UPGRADE_NODES.size())
	array_progress_bar.show_percentage = false
	array_progress_bar.custom_minimum_size = Vector2(220, 8)
	array_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	array_progress_bar.add_theme_stylebox_override("background", _panel_style(Color("071722"), Color("173849"), 3))
	array_progress_bar.add_theme_stylebox_override("fill", _panel_style(Color("368f9f"), Color("70e7d8"), 3))
	status_label = _make_label(tr("HUD_OBSERVED_COUNT") % 0, 11, Color("7897ad"))
	progress_column.add_child(progress_header)
	progress_column.add_child(array_progress_bar)
	progress_column.add_child(status_label)

	var second_divider := VSeparator.new()
	second_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(second_divider)
	var run_column := VBoxContainer.new()
	run_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_column.custom_minimum_size = Vector2(112, 0)
	run_column.alignment = BoxContainer.ALIGNMENT_CENTER
	run_column.add_theme_constant_override("separation", 2)
	top_row.add_child(run_column)
	time_label = _make_label(tr("HUD_TIME") % [0, 0], 14, Color("7893ac"))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	save_mode_label = _make_label("", 9, Color("7897ad"))
	save_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	save_mode_label.visible = false
	run_column.add_child(time_label)
	run_column.add_child(save_mode_label)

	banner_label = _make_label("", 24, Color.WHITE)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.anchor_left = 0.25
	banner_label.anchor_right = 0.75
	banner_label.offset_top = 84.0
	banner_label.offset_bottom = 122.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.visible = false
	root_control.add_child(banner_label)

	tutorial_label = _make_label(tr("HUD_TUTORIAL_START"), 16, Color("c9d8e8"))
	tutorial_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_label.anchor_left = 0.28
	tutorial_label.anchor_right = 0.72
	tutorial_label.offset_top = -79.0
	tutorial_label.offset_bottom = -43.0
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root_control.add_child(tutorial_label)

	tree_panel = PanelContainer.new()
	tree_panel.name = "UpgradeTreeLauncher"
	tree_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tree_panel.offset_left = -340.0
	tree_panel.offset_top = -162.0
	tree_panel.offset_right = -18.0
	tree_panel.offset_bottom = -18.0
	tree_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.064, 0.105, 0.93), Color(0.29, 0.63, 0.80, 0.55), 10))
	root_control.add_child(tree_panel)
	var tree_margin := MarginContainer.new()
	tree_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		tree_margin.add_theme_constant_override(side, 10)
	tree_panel.add_child(tree_margin)
	var tree_column := VBoxContainer.new()
	tree_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_column.add_theme_constant_override("separation", 6)
	tree_margin.add_child(tree_column)
	var next_header := HBoxContainer.new()
	next_header.name = "NextSystemHeader"
	next_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_available_label = _make_label(tr("HUD_NEXT_SYSTEM"), 10, Color("7f9bb1"))
	upgrade_available_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_system_branch_label = _make_label("", 9, Color("53d6ff"))
	next_system_branch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_header.add_child(upgrade_available_label)
	next_header.add_child(next_system_branch_label)
	next_system_name_label = _make_label("", 16, Color("e9f8ff"))
	next_system_name_label.name = "NextSystemName"
	next_system_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var next_progress_row := HBoxContainer.new()
	next_progress_row.name = "NextSystemProgress"
	next_progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_progress_row.add_theme_constant_override("separation", 10)
	next_system_bar = ProgressBar.new()
	next_system_bar.show_percentage = false
	next_system_bar.custom_minimum_size = Vector2(182, 8)
	next_system_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_system_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_system_bar.add_theme_stylebox_override("background", _panel_style(Color("071722"), Color("173849"), 3))
	next_system_bar.add_theme_stylebox_override("fill", _panel_style(Color("368f9f"), Color("70e7d8"), 3))
	next_system_cost_label = _make_label("0 / 0", 10, Color("8da7bb"))
	next_system_cost_label.custom_minimum_size = Vector2(92, 0)
	next_system_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_progress_row.add_child(next_system_bar)
	next_progress_row.add_child(next_system_cost_label)
	tree_button = Button.new()
	tree_button.mouse_filter = Control.MOUSE_FILTER_STOP
	tree_button.text = tr("HUD_UPGRADE_BUTTON") % [0, Balance.UPGRADE_NODES.size()]
	tree_button.custom_minimum_size = Vector2(300, 36)
	tree_button.add_theme_font_size_override("font_size", 14)
	tree_button.add_theme_color_override("font_color", Color("d9f7ff"))
	tree_button.add_theme_stylebox_override("normal", _panel_style(Color("12405c"), Color("387794"), 6))
	tree_button.add_theme_stylebox_override("hover", _panel_style(Color("185b79"), Color("68b4d2"), 6))
	tree_button.add_theme_stylebox_override("pressed", _panel_style(Color("0d3047"), Color("78d9ef"), 6))
	tree_button.pressed.connect(_on_tree_button_pressed)
	tree_column.add_child(next_header)
	tree_column.add_child(next_system_name_label)
	tree_column.add_child(next_progress_row)
	tree_column.add_child(tree_button)

	tracking_panel = PanelContainer.new()
	tracking_panel.name = "TrackingReadout"
	tracking_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tracking_panel.offset_left = 18.0
	tracking_panel.offset_top = -88.0
	tracking_panel.offset_right = 256.0
	tracking_panel.offset_bottom = -36.0
	tracking_panel.custom_minimum_size = Vector2(238, 48)
	tracking_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.07, 0.11, 0.88), Color(0.32, 0.76, 0.86, 0.44), 6))
	tracking_panel.visible = false
	root_control.add_child(tracking_panel)
	var tracking_column := VBoxContainer.new()
	tracking_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_panel.add_child(tracking_column)
	tracking_name = _make_label(tr("HUD_TRACKING") % [tr("METEOR_COMMON"), 0], 12, Color("bcefff"))
	tracking_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracking_bar = ProgressBar.new()
	tracking_bar.max_value = 100.0
	tracking_bar.show_percentage = false
	tracking_bar.custom_minimum_size = Vector2(220, 9)
	tracking_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracking_bar.add_theme_stylebox_override("background", _panel_style(Color("071722"), Color("173849"), 3))
	tracking_bar.add_theme_stylebox_override("fill", _panel_style(Color("65dcbf"), Color("8fffe5"), 3))
	tracking_column.add_child(tracking_name)
	tracking_column.add_child(tracking_bar)

	_build_debug_panel()
	_build_end_overlay()
	_build_settings_ui()
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings_button.offset_left = -146.0
	settings_button.offset_top = 16.0
	settings_button.offset_right = -18.0
	settings_button.offset_bottom = 55.0
	settings_button.text = "⚙  " + tr("SETTINGS_BUTTON")
	settings_button.add_theme_font_size_override("font_size", 13)
	settings_button.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.055, 0.10, 0.88), Color(0.26, 0.48, 0.68, 0.5), 8))
	settings_button.add_theme_stylebox_override("hover", _panel_style(Color(0.04, 0.10, 0.16, 0.96), Color("62b7d4"), 8))
	settings_button.pressed.connect(open_settings)
	root_control.add_child(settings_button)
	_build_startup_slots_ui()


func _build_startup_slots_ui() -> void:
	startup_overlay = Control.new()
	startup_overlay.name = "StartupSaveSlots"
	startup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	startup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	startup_overlay.visible = false
	root_control.add_child(startup_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.002, 0.007, 0.02, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	startup_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -335.0
	panel.offset_top = -235.0
	panel.offset_right = 335.0
	panel.offset_bottom = 235.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("071426"), Color("4c8aa8"), 14))
	startup_overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	startup_title = _make_label(tr("STARTUP_SAVE_TITLE"), 28, Color("e8f6ff"))
	startup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	startup_subtitle = _make_label(tr("STARTUP_SAVE_SUBTITLE"), 11, Color("6f9ab2"))
	startup_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(startup_title)
	column.add_child(startup_subtitle)
	var divider := HSeparator.new()
	column.add_child(divider)
	for slot in range(1, 4):
		_build_startup_slot_row(column, slot)
	startup_hint = _make_label(tr("STARTUP_SAVE_HINT"), 12, Color("8ba7b9"))
	startup_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	startup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(startup_hint)


func _build_startup_slot_row(parent: VBoxContainer, slot: int) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 84)
	row_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.065, 0.11, 0.9), Color(0.20, 0.43, 0.58, 0.66), 9))
	parent.add_child(row_panel)
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 16)
	row_margin.add_theme_constant_override("margin_right", 12)
	row_margin.add_theme_constant_override("margin_top", 10)
	row_margin.add_theme_constant_override("margin_bottom", 10)
	row_panel.add_child(row_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row_margin.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)
	var title := _make_label(tr("SAVE_SLOT_TITLE") % slot, 17, Color("e8f6ff"))
	var details := _make_label(tr("SAVE_SLOT_EMPTY"), 11, Color("829caf"))
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	info.add_child(details)
	var select_button := Button.new()
	select_button.text = tr("STARTUP_NEW_GAME")
	select_button.custom_minimum_size = Vector2(168, 52)
	select_button.add_theme_font_size_override("font_size", 13)
	select_button.add_theme_color_override("font_color", Color("d9f7ff"))
	select_button.add_theme_stylebox_override("normal", _panel_style(Color("12405c"), Color("387794"), 7))
	select_button.add_theme_stylebox_override("hover", _panel_style(Color("185b79"), Color("68b4d2"), 7))
	select_button.add_theme_stylebox_override("pressed", _panel_style(Color("0d3047"), Color("78d9ef"), 7))
	select_button.pressed.connect(_on_startup_slot_pressed.bind(slot))
	row.add_child(select_button)
	startup_slot_titles.append(title)
	startup_slot_details.append(details)
	startup_slot_buttons.append(select_button)


func _build_debug_panel() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_panel.offset_left = -350.0
	debug_panel.offset_top = 78.0
	debug_panel.offset_right = -18.0
	debug_panel.offset_bottom = 252.0
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.025, 0.07, 0.96), Color(0.62, 0.45, 0.94, 0.7), 8))
	debug_panel.visible = false
	root_control.add_child(debug_panel)
	debug_label = _make_label(
		"\n\n".join([tr("HUD_DEBUG_TITLE"), "\n".join([tr("HUD_DEBUG_DATA"), tr("HUD_DEBUG_NEXT"), tr("HUD_DEBUG_ALL"), tr("HUD_DEBUG_METEOR"), tr("HUD_DEBUG_RARE"), tr("HUD_DEBUG_SHOWER"), tr("HUD_DEBUG_FINAL"), tr("HUD_DEBUG_RESET")])]),
		13,
		Color("d8c6ff")
	)
	debug_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	debug_panel.add_child(debug_label)


func _build_end_overlay() -> void:
	end_overlay = ColorRect.new()
	end_overlay.name = "EndOverlay"
	end_overlay.color = Color(0.004, 0.009, 0.025, 0.91)
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	end_overlay.visible = false
	root_control.add_child(end_overlay)
	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -265.0
	center_panel.offset_top = -180.0
	center_panel.offset_right = 265.0
	center_panel.offset_bottom = 180.0
	center_panel.add_theme_stylebox_override("panel", _panel_style(Color("071324"), Color("467695"), 12))
	end_overlay.add_child(center_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	center_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	end_title = _make_label(tr("HUD_END_SUCCESS"), 28, Color("ffe1a3"))
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_stats = _make_label("", 16, Color("adc7da"))
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	restart_button = Button.new()
	restart_button.text = tr("HUD_RESTART")
	restart_button.custom_minimum_size = Vector2(0, 44)
	restart_button.add_theme_font_size_override("font_size", 15)
	restart_button.pressed.connect(func(): restart_requested.emit())
	column.add_child(end_title)
	column.add_child(end_stats)
	column.add_child(restart_button)


func _build_settings_ui() -> void:
	settings_overlay = Control.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.visible = false
	root_control.add_child(settings_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.009, 0.025, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340.0
	panel.offset_top = -280.0
	panel.offset_right = 340.0
	panel.offset_bottom = 280.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("081326"), Color("4f829e"), 12))
	settings_overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	settings_title = _make_label(tr("SETTINGS_TITLE"), 25, Color("e8f6ff"))
	settings_subtitle = _make_label(tr("SETTINGS_SUBTITLE"), 11, Color("6f8ca5"))
	column.add_child(settings_title)
	column.add_child(settings_subtitle)
	var divider := HSeparator.new()
	column.add_child(divider)
	settings_language_label = _make_label(tr("SETTINGS_LANGUAGE"), 14, Color("bdeaff"))
	column.add_child(settings_language_label)
	language_selector = OptionButton.new()
	language_selector.custom_minimum_size = Vector2(0, 38)
	language_selector.add_item(tr("SETTINGS_ENGLISH"))
	language_selector.set_item_metadata(0, "en")
	language_selector.add_item(tr("SETTINGS_KOREAN"))
	language_selector.set_item_metadata(1, "ko")
	language_selector.item_selected.connect(_on_language_selected)
	column.add_child(language_selector)
	settings_hint = _make_label(tr("SETTINGS_LANGUAGE_HINT"), 12, Color("829caf"))
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(settings_hint)
	tutorial_replay_button = Button.new()
	tutorial_replay_button.text = tr("TUTORIAL_REPLAY")
	tutorial_replay_button.custom_minimum_size = Vector2(0, 36)
	tutorial_replay_button.pressed.connect(func(): tutorial_replay_requested.emit())
	column.add_child(tutorial_replay_button)
	var save_divider := HSeparator.new()
	column.add_child(save_divider)
	save_section_label = _make_label(tr("SAVE_SECTION_TITLE"), 15, Color("bdeaff"))
	column.add_child(save_section_label)
	for slot in range(1, 4):
		_build_save_slot_row(column, slot)
	save_feedback = _make_label(tr("SAVE_SECTION_HINT"), 12, Color("829caf"))
	save_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_feedback.visible = false
	column.add_child(save_feedback)
	settings_close_button = Button.new()
	settings_close_button.text = tr("SETTINGS_CLOSE")
	settings_close_button.custom_minimum_size = Vector2(0, 40)
	settings_close_button.pressed.connect(close_settings)
	column.add_child(settings_close_button)
	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = tr("SAVE_OVERWRITE_TITLE")
	overwrite_dialog.ok_button_text = tr("SAVE_OVERWRITE_CONFIRM")
	overwrite_dialog.cancel_button_text = tr("SAVE_CANCEL")
	overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	settings_overlay.add_child(overwrite_dialog)


func _build_save_slot_row(parent: VBoxContainer, slot: int) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 67)
	row_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.10, 0.82), Color(0.20, 0.39, 0.53, 0.55), 8))
	parent.add_child(row_panel)
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 12)
	row_margin.add_theme_constant_override("margin_right", 10)
	row_margin.add_theme_constant_override("margin_top", 7)
	row_margin.add_theme_constant_override("margin_bottom", 7)
	row_panel.add_child(row_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_margin.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)
	var title := _make_label(tr("SAVE_SLOT_TITLE") % slot, 14, Color("e8f6ff"))
	var details := _make_label(tr("SAVE_SLOT_EMPTY"), 11, Color("829caf"))
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(title)
	info.add_child(details)
	var save_button := Button.new()
	save_button.text = tr("SAVE_ACTION")
	save_button.custom_minimum_size = Vector2(104, 42)
	save_button.pressed.connect(_on_save_slot_pressed.bind(slot))
	row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = tr("LOAD_ACTION")
	load_button.custom_minimum_size = Vector2(90, 42)
	load_button.disabled = true
	load_button.pressed.connect(_on_load_slot_pressed.bind(slot))
	row.add_child(load_button)
	save_slot_titles.append(title)
	save_slot_details.append(details)
	save_slot_buttons.append(save_button)
	load_slot_buttons.append(load_button)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
