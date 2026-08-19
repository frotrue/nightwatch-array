extends CanvasLayer

signal restart_requested
signal upgrade_tree_requested

const Balance = preload("res://scripts/game_balance.gd")

var progression: Node
var settings_controller: Node
var root_control: Control
var data_label: Label
var status_label: Label
var time_label: Label
var tutorial_label: Label
var banner_label: Label
var tree_button: Button
var upgrade_available_label: Label
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
var settings_close_button: Button
var banner_timer: float = 0.0
var tutorial_complete: bool = false
var last_runtime_second: int = -1
var last_tracking_text: String = ""
var last_end_success: bool = false
var paused_by_settings: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	set_process(true)


func bind_progression(controller: Node) -> void:
	progression = controller
	progression.state_changed.connect(_refresh_progression)
	_refresh_progression()


func bind_settings(controller: Node) -> void:
	settings_controller = controller
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	_sync_language_selector()
	_apply_locale()


func _process(delta: float) -> void:
	if banner_timer > 0.0:
		banner_timer -= delta
		var fade := clampf(banner_timer / 0.3, 0.0, 1.0)
		banner_label.modulate.a = fade
		if banner_timer <= 0.0:
			banner_label.visible = false


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


func set_tracking(progress: float, target_type: String, multiplier: float) -> void:
	if not tracking_panel.visible:
		tracking_panel.visible = true
	var progress_percent := int(progress * 100.0)
	tracking_bar.value = float(progress_percent)
	var target_name := tr("METEOR_%s" % target_type.to_upper())
	var next_text := tr("HUD_TRACKING") % [target_name, progress_percent]
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


func close_settings() -> void:
	if not settings_overlay.visible:
		return
	settings_overlay.visible = false
	if paused_by_settings:
		get_tree().paused = false
	paused_by_settings = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible


func _unhandled_key_input(event: InputEvent) -> void:
	if is_settings_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_settings()
		get_viewport().set_input_as_handled()


func _refresh_progression() -> void:
	if progression == null:
		return
	data_label.text = tr("HUD_DATA") % int(floor(progression.observation_data))
	status_label.text = tr("HUD_STATUS") % [
		progression.success_count,
		progression.upgrade_level,
		Balance.UPGRADE_NODES.size()
	]
	var affordable := 0
	for node_id in progression.get_available_nodes():
		if progression.can_purchase(node_id):
			affordable += 1
	tree_button.text = tr("HUD_UPGRADE_BUTTON") % [progression.upgrade_level, Balance.UPGRADE_NODES.size()]
	if affordable > 0:
		upgrade_available_label.text = tr("HUD_UPGRADE_AVAILABLE")
		upgrade_available_label.add_theme_color_override("font_color", Color("7ee9dc"))
	else:
		upgrade_available_label.text = tr("HUD_NEXT_DISCOVERY")
		upgrade_available_label.add_theme_color_override("font_color", Color("718ca5"))


func _on_tree_button_pressed() -> void:
	upgrade_tree_requested.emit()


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
	settings_button.text = "⚙  " + tr("SETTINGS_BUTTON")
	settings_title.text = tr("SETTINGS_TITLE")
	settings_subtitle.text = tr("SETTINGS_SUBTITLE")
	settings_language_label.text = tr("SETTINGS_LANGUAGE")
	settings_hint.text = tr("SETTINGS_LANGUAGE_HINT")
	settings_close_button.text = tr("SETTINGS_CLOSE")
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
	if progression != null:
		_refresh_progression()


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
	top_panel.anchor_right = 0.62
	top_panel.offset_top = 16.0
	top_panel.offset_bottom = 65.0
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.10, 0.82), Color(0.26, 0.48, 0.68, 0.34), 8))
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(top_panel)
	var top_margin := MarginContainer.new()
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_theme_constant_override("margin_left", 16)
	top_margin.add_theme_constant_override("margin_right", 16)
	top_panel.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 24)
	top_margin.add_child(top_row)
	data_label = _make_label(tr("HUD_DATA") % 0, 17, Color("bdeaff"))
	status_label = _make_label(tr("HUD_STATUS") % [0, 0, Balance.UPGRADE_NODES.size()], 15, Color("93adc6"))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_label = _make_label(tr("HUD_TIME") % [0, 0], 14, Color("7893ac"))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(data_label)
	top_row.add_child(status_label)
	top_row.add_child(time_label)

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

	var tree_panel := PanelContainer.new()
	tree_panel.name = "UpgradeTreeLauncher"
	tree_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tree_panel.offset_left = -310.0
	tree_panel.offset_top = -100.0
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
	tree_column.add_theme_constant_override("separation", 5)
	tree_margin.add_child(tree_column)
	upgrade_available_label = _make_label(tr("HUD_NEXT_DISCOVERY"), 11, Color("718ca5"))
	upgrade_available_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree_button = Button.new()
	tree_button.mouse_filter = Control.MOUSE_FILTER_STOP
	tree_button.text = tr("HUD_UPGRADE_BUTTON") % [0, Balance.UPGRADE_NODES.size()]
	tree_button.custom_minimum_size = Vector2(270, 38)
	tree_button.add_theme_font_size_override("font_size", 14)
	tree_button.add_theme_color_override("font_color", Color("d9f7ff"))
	tree_button.add_theme_stylebox_override("normal", _panel_style(Color("12405c"), Color("387794"), 6))
	tree_button.add_theme_stylebox_override("hover", _panel_style(Color("185b79"), Color("68b4d2"), 6))
	tree_button.add_theme_stylebox_override("pressed", _panel_style(Color("0d3047"), Color("78d9ef"), 6))
	tree_button.pressed.connect(_on_tree_button_pressed)
	tree_column.add_child(upgrade_available_label)
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
	panel.offset_left = -245.0
	panel.offset_top = -150.0
	panel.offset_right = 245.0
	panel.offset_bottom = 150.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("081326"), Color("4f829e"), 12))
	settings_overlay.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
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
	language_selector.custom_minimum_size = Vector2(0, 44)
	language_selector.add_item(tr("SETTINGS_ENGLISH"))
	language_selector.set_item_metadata(0, "en")
	language_selector.add_item(tr("SETTINGS_KOREAN"))
	language_selector.set_item_metadata(1, "ko")
	language_selector.item_selected.connect(_on_language_selected)
	column.add_child(language_selector)
	settings_hint = _make_label(tr("SETTINGS_LANGUAGE_HINT"), 12, Color("829caf"))
	settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(settings_hint)
	settings_close_button = Button.new()
	settings_close_button.text = tr("SETTINGS_CLOSE")
	settings_close_button.custom_minimum_size = Vector2(0, 42)
	settings_close_button.pressed.connect(close_settings)
	column.add_child(settings_close_button)


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
