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
var debug_preview := false
var _preview_backup: Dictionary = {}
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
	if debug_preview:
		_restore_debug_preview()

func start_debug_preview() -> void:
	if active or game.tutorial.active or game.hud.is_settings_open() or game.hud.is_startup_slots_open() or game.hud.is_phase_summary_open():
		return
	if game.module_popup.is_draw_open() and game.module_popup.draw_window.drawing:
		return
	if game.upgrade_tree.galactic_unlocked and not game.upgrade_tree.galactic_pullback_seen:
		return
	_preview_backup = {
		"state": game.deep_sky.state, "modules": game.deep_sky.modules,
		"paused": get_tree().paused, "mouse": Input.mouse_mode,
		"chart": game.upgrade_tree.is_open(), "popup": game.module_popup.is_open(),
		"draw": game.module_popup.is_draw_open(), "autosave_failed": game.hud.autosave_failed,
		"enabled": enabled,
		"inventory_filter": game.module_popup.inventory_filter,
	}
	game.module_popup.close()
	debug_preview = true
	enabled = true
	game.hud.autosave_failed = false
	# Keep the live objects intact. Only the module UI sees this disposable model.
	game.deep_sky.state = State.new()
	game.deep_sky.state.research_ids.append("ext_protocol")
	game.deep_sky.state.award_samples(8)
	game.deep_sky.state.module_intro_stage = State.Intro.DRAW
	game.deep_sky.modules = game.deep_sky.Modules.new()
	game.upgrade_tree.open_tree()
	game.module_popup.refresh(false)
	set_process(true)
	_process(0.0)

func _restore_debug_preview() -> void:
	game.module_popup.close()
	game.deep_sky.state = _preview_backup.state
	game.deep_sky.modules = _preview_backup.modules
	game.hud.autosave_failed = _preview_backup.autosave_failed
	game.module_popup.set_inventory_filter(_preview_backup.inventory_filter)
	if not _preview_backup.chart:
		game.upgrade_tree.close_tree()
	# Refresh subscribers while gameplay's change handler still ignores the preview.
	game.deep_sky.changed.emit()
	if _preview_backup.popup:
		game.module_popup.open()
		if _preview_backup.draw:
			game.module_popup.open_draw()
	debug_preview = false
	game.module_popup.refresh(false)
	get_tree().paused = _preview_backup.paused
	Input.mouse_mode = _preview_backup.mouse
	enabled = _preview_backup.enabled
	set_process(enabled)
	_preview_backup.clear()

func _process(_delta: float) -> void:
	if game == null or not enabled:
		return
	var state = game.deep_sky.state
	if not game.deep_sky.modules_unlocked() or state.module_intro_stage not in [State.Intro.DRAW, State.Intro.EQUIP]:
		if active:
			if debug_preview:
				cancel()
				return
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
	if not game.upgrade_tree.galactic_pullback_seen and not debug_preview:
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
		next_target = popup.owned_buttons[state.module_intro_id]
		if not next_target.visible:
			popup.set_inventory_filter("all")
		focus_rect = next_target.get_global_rect()
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
	if debug_preview:
		hint_label.text = tr("MODULE_INTRO_PREVIEW_HINT")
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
	if debug_preview and (event.is_action_pressed("nw_menu_back", false, true) or (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_T)):
		cancel()
		get_viewport().set_input_as_handled()
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
