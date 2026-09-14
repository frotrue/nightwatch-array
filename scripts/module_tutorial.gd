extends CanvasLayer

# The saved model owns rewards/results; this layer only gates the first UI actions.
# The chart and module popup retain their normal pause ownership throughout.
const State = preload("res://scripts/expansion_state.gd")
var enabled := true
var active := false
var game: Node
var target: Button
var phase := ""
var settings_layer := -1
@onready var screen: Control = $Screen
@onready var highlight: Panel = $Screen/Highlight
@onready var card: PanelContainer = $Screen/Card
@onready var step_label: Label = $Screen/Card/Content/Step
@onready var title_label: Label = $Screen/Card/Content/Title
@onready var body_label: Label = $Screen/Card/Content/Body
@onready var hint_label: Label = $Screen/Card/Content/Hint

func setup(controller: Node) -> void:
	game = controller
	screen.hide()
	set_process(enabled)

func cancel() -> void:
	active = false
	phase = ""
	target = null
	screen.hide()
	_restore_settings_layer()

func is_equip_target(index: int) -> bool:
	return active and game != null and game.deep_sky.state.module_intro_stage == State.Intro.EQUIP and not game.module_popup.is_draw_open() and index == game.deep_sky.modules.first_empty_slot()

func _process(_delta: float) -> void:
	if game == null or not enabled:
		return
	var state = game.deep_sky.state
	if not game.deep_sky.modules_unlocked() or state.module_intro_stage not in [State.Intro.DRAW, State.Intro.EQUIP]:
		if active:
			cancel()
			game.module_popup.intro_completed_notice = state.module_intro_stage == State.Intro.COMPLETE
			game.module_popup.refresh(false)
			if game.module_popup.is_open():
				game.module_popup.close_button.grab_focus()
		return
	if game._loading_save or game.hud.is_startup_slots_open() or game.tutorial.active:
		return
	if game.hud.is_settings_open():
		if active:
			_raise_settings()
		screen.hide()
		return
	_restore_settings_layer()
	if game.hud.is_phase_summary_open():
		return
	if not game.upgrade_tree.is_open():
		game.upgrade_tree.open_tree()
	# Let the galaxy reveal finish before taking over its controls.
	if not game.upgrade_tree.galactic_pullback_seen:
		return
	if not active:
		active = true
		if state.module_intro_stage == State.Intro.EQUIP:
			game.module_popup.open_draw()
	var popup = game.module_popup
	var next_phase := "OPEN"
	var next_target: Button = popup.draw_launcher
	var focus_rect: Rect2 = next_target.get_global_rect()
	if state.module_intro_stage == State.Intro.DRAW and popup.is_open() and not popup.is_draw_open():
		popup.open_draw()
	if popup.is_draw_open():
		var draw = popup.draw_window
		if draw.drawing:
			next_phase = "REVEAL"
			next_target = draw.skip_button
		elif state.module_intro_stage == State.Intro.EQUIP:
			next_phase = "RESULT"
			next_target = draw.loadout_button
		else:
			next_phase = "DRAW"
			next_target = draw.action
		focus_rect = next_target.get_global_rect()
		if next_phase == "RESULT":
			focus_rect = focus_rect.merge(draw.result_panel.get_global_rect())
	elif state.module_intro_stage == State.Intro.EQUIP:
		next_phase = "EQUIP"
		var index: int = game.deep_sky.modules.first_empty_slot()
		if index < 0:
			return
		next_target = popup.slots[index]
		focus_rect = next_target.get_global_rect().merge(popup.slot_captions[index].get_global_rect())
	if phase != next_phase or target != next_target:
		phase = next_phase
		target = next_target
		popup.hide_tooltip()
		popup.refresh(false)
	if not target.disabled and not target.has_focus():
		target.grab_focus()
	_refresh_text()
	_place_spotlight(focus_rect.grow(7.0))
	screen.show()

func _refresh_text() -> void:
	var step := 1 if phase == "OPEN" else (2 if phase in ["DRAW", "REVEAL"] else 3)
	step_label.text = tr("MODULE_INTRO_STEP") % step
	title_label.text = tr("MODULE_INTRO_%s_TITLE" % phase)
	body_label.text = tr("MODULE_INTRO_%s_BODY" % phase)
	if phase == "EQUIP":
		var id: String = game.deep_sky.state.module_intro_id
		body_label.text = tr("MODULE_INTRO_EQUIP_BODY") % tr("MODULE_%s_NAME" % id.to_upper())
	hint_label.text = tr("MODULE_INTRO_HINT") % game.settings.binding_label("nw_menu_back")
	if game.hud.autosave_failed:
		hint_label.text = (tr("AUTOSAVE_FAILURE") % game.active_save_slot) + " " + hint_label.text

func _place_spotlight(rect: Rect2) -> void:
	var bounds := Rect2(Vector2.ZERO, screen.size)
	var hole := rect.intersection(bounds)
	highlight.position = hole.position
	highlight.size = hole.size
	var areas := [
		Rect2(0, 0, bounds.size.x, hole.position.y),
		Rect2(0, hole.end.y, bounds.size.x, bounds.size.y - hole.end.y),
		Rect2(0, hole.position.y, hole.position.x, hole.size.y),
		Rect2(hole.end.x, hole.position.y, bounds.size.x - hole.end.x, hole.size.y),
	]
	for i in 4:
		var shade: ColorRect = screen.get_node("Shade%d" % i)
		shade.position = areas[i].position
		shade.size = areas[i].size
	# Both languages use the same authored card; place it opposite the target.
	card.position = Vector2(40 if hole.get_center().x > bounds.size.x * 0.5 else bounds.size.x - card.size.x - 40, bounds.size.y - card.size.y - 40)

func _input(event: InputEvent) -> void:
	if not active:
		return
	if game.hud.is_settings_open():
		if event.is_action_pressed("nw_menu_back", false, true):
			game.hud.consume_menu_back()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("nw_menu_back", false, true):
		_raise_settings()
		screen.hide()
		game.hud.open_settings()
		game.hud.tutorial_replay_button.disabled = true
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(target) and target.is_visible_in_tree() and not target.disabled:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and target.get_global_rect().has_point(event.position):
			return
		if event.is_action("ui_accept") and not event.is_echo():
			target.grab_focus()
			return
	get_viewport().set_input_as_handled()

func _raise_settings() -> void:
	game.hud.tutorial_replay_button.disabled = true
	if settings_layer < 0:
		settings_layer = game.hud.layer
		game.hud.layer = layer + 1

func _restore_settings_layer() -> void:
	if settings_layer >= 0:
		game.hud.layer = settings_layer
		settings_layer = -1
