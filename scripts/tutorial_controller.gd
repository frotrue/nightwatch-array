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
	hint_label.visible = modal
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
	var view = preload("res://scenes/ui/tutorial_controller.tscn").instantiate()
	body_label = view.get_node("%BodyLabel")
	card = view.get_node("%Card")
	dim = view.get_node("%Dim")
	hint_label = view.get_node("%HintLabel")
	overlay = view
	primary_button = view.get_node("%PrimaryButton")
	skip_button = view.get_node("%SkipButton")
	step_label = view.get_node("%StepLabel")
	title_label = view.get_node("%TitleLabel")
	add_child(view)
	view.get_node("%SkipButton").pressed.connect(skip_tutorial)
	view.get_node("%PrimaryButton").pressed.connect(_on_primary_pressed)
