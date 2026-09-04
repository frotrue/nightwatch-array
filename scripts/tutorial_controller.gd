extends CanvasLayer

const UITheme = preload("res://scripts/ui_theme.gd")

signal tutorial_started
signal tutorial_completed

const Balance = preload("res://scripts/game_balance.gd")
const STEP_WELCOME := 0
const STEP_OBSERVE := 1
const STEP_UPGRADE_TREE := 2
const STEP_INSTALL := 3
const STEP_COMPLETE := 4

var settings_controller: Node
var progression: Node
var overlay: Control
var dim: ColorRect
var card: Control
var step_label: Label
var title_label: Label
var body_label: Label
var hint_label: Label
var primary_button: Button
var skip_button: Button
var current_step: int = -1
var active: bool = false
var paused_by_tutorial: bool = false
var auto_start_enabled: bool = true
var persist_current_run: bool = true


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()


func setup(settings: Node, progression_controller: Node) -> void:
	settings_controller = settings
	progression = progression_controller
	if not settings_controller.language_changed.is_connected(_on_language_changed):
		settings_controller.language_changed.connect(_on_language_changed)
	if (
		settings_controller.has_signal("input_bindings_changed")
		and not settings_controller.is_connected("input_bindings_changed", _on_input_bindings_changed)
	):
		settings_controller.connect("input_bindings_changed", _on_input_bindings_changed)
	if auto_start_enabled and not settings_controller.is_tutorial_completed():
		call_deferred("start_tutorial")


func start_tutorial(persist_completion: bool = true) -> void:
	persist_current_run = persist_completion
	active = true
	if persist_current_run:
		settings_controller.set_tutorial_completed(false)
	overlay.visible = true
	_set_step(STEP_WELCOME)
	tutorial_started.emit()


func notify_observation_completed() -> void:
	if active and current_step == STEP_OBSERVE:
		_set_step(STEP_UPGRADE_TREE)


func notify_upgrade_tree_opened() -> void:
	if active and current_step == STEP_UPGRADE_TREE:
		_set_step(STEP_INSTALL)


func notify_upgrade_purchased() -> void:
	if active and current_step == STEP_INSTALL:
		_set_step(STEP_COMPLETE)


func is_active() -> bool:
	return active


func is_modal_step() -> bool:
	return active and current_step in [STEP_WELCOME, STEP_COMPLETE]


func skip_tutorial() -> void:
	_finish_tutorial()


func _set_step(step: int) -> void:
	current_step = step
	var modal := is_modal_step()
	dim.visible = modal
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	_position_card(modal)
	primary_button.visible = step == STEP_WELCOME or step == STEP_COMPLETE
	skip_button.visible = step != STEP_COMPLETE
	match step:
		STEP_WELCOME:
			_pause_for_tutorial()
			step_label.text = tr("TUTORIAL_STEP_WELCOME")
			title_label.text = tr("TUTORIAL_WELCOME_TITLE")
			body_label.text = tr("TUTORIAL_WELCOME_BODY")
			hint_label.text = tr("TUTORIAL_WELCOME_HINT")
			primary_button.text = tr("TUTORIAL_START")
		STEP_OBSERVE:
			_resume_from_tutorial_pause()
			step_label.text = tr("TUTORIAL_STEP") % [1, 3]
			title_label.text = tr("TUTORIAL_OBSERVE_TITLE")
			body_label.text = tr("TUTORIAL_OBSERVE_BODY")
			hint_label.text = tr("TUTORIAL_OBSERVE_HINT")
		STEP_UPGRADE_TREE:
			step_label.text = tr("TUTORIAL_STEP") % [2, 3]
			title_label.text = tr("TUTORIAL_TREE_TITLE")
			body_label.text = _binding_text("TUTORIAL_TREE_BODY", "nw_chart")
			hint_label.text = tr("TUTORIAL_TREE_HINT")
		STEP_INSTALL:
			step_label.text = tr("TUTORIAL_STEP") % [3, 3]
			title_label.text = tr("TUTORIAL_INSTALL_TITLE")
			body_label.text = tr("TUTORIAL_INSTALL_BODY")
			hint_label.text = tr("TUTORIAL_INSTALL_HINT")
			if progression != null and progression.upgrade_level >= Balance.research_node_count():
				primary_button.visible = true
				primary_button.text = tr("TUTORIAL_CONTINUE")
		STEP_COMPLETE:
			step_label.text = tr("TUTORIAL_STEP_COMPLETE")
			title_label.text = tr("TUTORIAL_COMPLETE_TITLE")
			body_label.text = tr("TUTORIAL_COMPLETE_BODY")
			hint_label.text = _binding_text("TUTORIAL_COMPLETE_HINT", "nw_chart")
			primary_button.text = tr("TUTORIAL_FINISH")
	skip_button.text = tr("TUTORIAL_SKIP")
	primary_button.focus_mode = Control.FOCUS_ALL if modal else Control.FOCUS_NONE
	skip_button.focus_mode = Control.FOCUS_ALL if modal and skip_button.visible else Control.FOCUS_NONE
	if modal:
		call_deferred("_focus_modal_primary", step)
	else:
		primary_button.release_focus()
		skip_button.release_focus()


func _focus_modal_primary(expected_step: int) -> void:
	if not active or current_step != expected_step or not is_modal_step():
		return
	if primary_button == null or not primary_button.is_visible_in_tree():
		return
	primary_button.grab_focus()


func _binding_text(text_key: String, action: String) -> String:
	var template := tr(text_key)
	if "%s" not in template:
		return template
	var label := "U"
	if settings_controller != null and settings_controller.has_method("binding_label"):
		label = String(settings_controller.binding_label(action))
	return template % label


func _on_primary_pressed() -> void:
	match current_step:
		STEP_WELCOME:
			_set_step(STEP_OBSERVE)
		STEP_INSTALL:
			_set_step(STEP_COMPLETE)
		STEP_COMPLETE:
			_finish_tutorial()


func _finish_tutorial() -> void:
	active = false
	current_step = -1
	primary_button.release_focus()
	skip_button.release_focus()
	primary_button.focus_mode = Control.FOCUS_NONE
	skip_button.focus_mode = Control.FOCUS_NONE
	overlay.visible = false
	_resume_from_tutorial_pause()
	if persist_current_run:
		settings_controller.set_tutorial_completed(true)
	tutorial_completed.emit()


func _pause_for_tutorial() -> void:
	if not get_tree().paused:
		paused_by_tutorial = true
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_from_tutorial_pause() -> void:
	if paused_by_tutorial:
		get_tree().paused = false
	paused_by_tutorial = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _position_card(modal: bool) -> void:
	if modal:
		card.set_anchors_preset(Control.PRESET_CENTER)
		card.offset_left = -320.0
		card.offset_top = -175.0
		card.offset_right = 320.0
		card.offset_bottom = 175.0
	elif current_step == STEP_INSTALL:
		card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		card.offset_left = 24.0
		card.offset_top = -190.0
		card.offset_right = 684.0
		card.offset_bottom = -24.0
	else:
		card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		card.offset_left = -684.0
		card.offset_top = 84.0
		card.offset_right = -24.0
		card.offset_bottom = 250.0


func _on_language_changed(_locale: String) -> void:
	if active:
		_set_step(current_step)


func _on_input_bindings_changed() -> void:
	if active:
		_set_step(current_step)


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "TutorialOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	# The embedded faces are the ones the rest of the red-light layer uses; a
	# system font here made the tutorial the only screen in a different voice.
	dim = ColorRect.new()
	dim.color = UITheme.SCRIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	# No card. Type on the dimmed sky, like every other overlay.
	card = Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(card)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", int(UITheme.px(14.0)))
	card.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	step_label = _spec_label("", UITheme.mono(), 13.0, UITheme.INK_MID, 0.30)
	step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(step_label)
	skip_button = Button.new()
	skip_button.text = tr("TUTORIAL_SKIP")
	_style_text_action(skip_button, 15.0, UITheme.INK_LOW)
	skip_button.pressed.connect(skip_tutorial)
	header.add_child(skip_button)
	title_label = _spec_label("", UITheme.sans("medium"), 34.0, UITheme.INK_MAX, -0.01)
	column.add_child(title_label)
	body_label = _spec_label("", UITheme.sans("light"), 19.0, UITheme.INK_HIGH)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)
	hint_label = _spec_label("", UITheme.mono(), 14.0, UITheme.HINT, 0.10)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)
	primary_button = Button.new()
	primary_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_text_action(primary_button, 22.0, UITheme.BANNER_TITLE)
	primary_button.pressed.connect(_on_primary_pressed)
	column.add_child(primary_button)


func _spec_label(text: String, font: Font, spec_size: float, color: Color, em: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	var font_size := UITheme.size_px(spec_size)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if not is_zero_approx(em):
		label.add_theme_constant_override("spacing_glyph", UITheme.tracking(font_size, em))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _style_text_action(button: Button, spec_size: float, color: Color) -> void:
	var font_size := UITheme.size_px(spec_size)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UITheme.sans())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("spacing_glyph", UITheme.tracking(font_size, 0.06))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 1
	style.border_color = UITheme.ACCENT_DEEP
	style.content_margin_left = UITheme.px(10.0)
	style.content_margin_right = UITheme.px(10.0)
	style.content_margin_top = UITheme.px(12.0)
	style.content_margin_bottom = UITheme.px(9.0)
	var hover := style.duplicate()
	hover.border_color = UITheme.ACCENT_TEXT
	for state in ["normal", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", hover)
