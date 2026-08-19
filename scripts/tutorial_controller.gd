extends CanvasLayer

signal tutorial_started
signal tutorial_completed

const STEP_WELCOME := 0
const STEP_OBSERVE := 1
const STEP_UPGRADE_TREE := 2
const STEP_INSTALL := 3
const STEP_COMPLETE := 4

var settings_controller: Node
var progression: Node
var overlay: Control
var dim: ColorRect
var card: PanelContainer
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


func skip_tutorial() -> void:
	_finish_tutorial()


func _set_step(step: int) -> void:
	current_step = step
	var modal := step == STEP_WELCOME or step == STEP_COMPLETE
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
			body_label.text = tr("TUTORIAL_TREE_BODY")
			hint_label.text = tr("TUTORIAL_TREE_HINT")
		STEP_INSTALL:
			step_label.text = tr("TUTORIAL_STEP") % [3, 3]
			title_label.text = tr("TUTORIAL_INSTALL_TITLE")
			body_label.text = tr("TUTORIAL_INSTALL_BODY")
			hint_label.text = tr("TUTORIAL_INSTALL_HINT")
			if progression != null and progression.upgrade_level >= 16:
				primary_button.visible = true
				primary_button.text = tr("TUTORIAL_CONTINUE")
		STEP_COMPLETE:
			step_label.text = tr("TUTORIAL_STEP_COMPLETE")
			title_label.text = tr("TUTORIAL_COMPLETE_TITLE")
			body_label.text = tr("TUTORIAL_COMPLETE_BODY")
			hint_label.text = tr("TUTORIAL_COMPLETE_HINT")
			primary_button.text = tr("TUTORIAL_FINISH")
	skip_button.text = tr("TUTORIAL_SKIP")


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


func _build_interface() -> void:
	overlay = Control.new()
	overlay.name = "TutorialOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	var interface_font := SystemFont.new()
	interface_font.font_names = PackedStringArray(["Pretendard", "Noto Sans CJK KR", "Malgun Gothic", "Segoe UI"])
	overlay.add_theme_font_override("font", interface_font)
	dim = ColorRect.new()
	dim.color = Color(0.002, 0.006, 0.018, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _panel_style(Color("081326"), Color("65cde4"), 14, 2))
	overlay.add_child(card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	step_label = _make_label("", 12, Color("65cde4"))
	step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(step_label)
	skip_button = Button.new()
	skip_button.flat = true
	skip_button.text = tr("TUTORIAL_SKIP")
	skip_button.pressed.connect(skip_tutorial)
	header.add_child(skip_button)
	title_label = _make_label("", 25, Color("f1f8ff"))
	column.add_child(title_label)
	body_label = _make_label("", 15, Color("c2d2df"))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body_label)
	hint_label = _make_label("", 12, Color("7ee9dc"))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint_label)
	primary_button = Button.new()
	primary_button.custom_minimum_size = Vector2(0, 44)
	primary_button.add_theme_font_size_override("font_size", 14)
	primary_button.pressed.connect(_on_primary_pressed)
	column.add_child(primary_button)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
