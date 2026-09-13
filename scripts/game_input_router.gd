extends Node

# Global actions that must continue to route while the scene tree is paused.
# Pointer-heavy chart interaction keeps first refusal in UpgradeTree._input(),
# and the catalogue reveal keeps its existing first refusal in HUD._input().
const ACTION_OBSERVE := &"nw_observe"
const ACTION_DISH := &"nw_dish"
const ACTION_CHART := &"nw_chart"
const ACTION_MENU_BACK := &"nw_menu_back"
const ACTION_CONTINUE := &"nw_continue"
const ACTION_FULLSCREEN := &"nw_fullscreen"

const DEBUG_KEYS := [
	KEY_D,
	KEY_N,
	KEY_A,
	KEY_G,
	KEY_M,
	KEY_B,
	KEY_R,
	KEY_S,
	KEY_F,
	KEY_E,
	KEY_BACKSPACE,
]

var game: Node
var hud: Node
var settings: Node
var tutorial: Node
var upgrade_tree: Node


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(
	game_controller: Node,
	hud_controller: Node,
	settings_controller: Node,
	tutorial_controller: Node,
	upgrade_tree_controller: Node
) -> void:
	game = game_controller
	hud = hud_controller
	settings = settings_controller
	tutorial = tutorial_controller
	upgrade_tree = upgrade_tree_controller


func _input(event: InputEvent) -> void:
	# Rebinding must see the physical candidate before a focused Control consumes
	# it in the GUI stage. HUD owns validation, conflict display, and completion.
	if hud == null or not hud.has_method("handle_rebind_capture_input"):
		return
	if bool(hud.call("handle_rebind_capture_input", event)):
		_mark_input_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not _is_raw_debug_input(event) or _hud_state(&"is_rebind_capture_active"):
		return
	if _hud_state(&"is_startup_slots_open") or _tutorial_is_modal():
		return
	# The gameplay root stops receiving input while the chart pauses the tree.
	# Keep debug dispatch here without allowing gameplay simulation to run paused.
	if game != null:
		game.handle_debug_key_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _hud_state(&"is_rebind_capture_active"):
		# The capture path above normally consumes candidate presses. Keep any
		# rejected or deferred press from leaking into fullscreen/debug/navigation.
		if _is_button_press(event):
			_mark_input_handled()
		return
	if _is_raw_debug_input(event):
		# Reserved debug chords never fall through to editable navigation bindings.
		return
	if _action_pressed(event, ACTION_FULLSCREEN):
		if settings != null and settings.has_method("toggle_fullscreen"):
			settings.call("toggle_fullscreen")
		_mark_input_handled()
		return
	if game != null and game.get("module_popup") != null and game.module_popup.is_open():
		if _action_pressed(event, ACTION_CHART) or _action_pressed(event, ACTION_MENU_BACK):
			game.module_popup.close()
			_mark_input_handled()
		return
	if _action_pressed(event, ACTION_MENU_BACK):
		_route_menu_back()
		_mark_input_handled()
		return

	var summary_open := _hud_state(&"is_phase_summary_open")
	var continue_pressed := _action_pressed(event, ACTION_CONTINUE)
	var chart_pressed := _action_pressed(event, ACTION_CHART)
	if summary_open and (continue_pressed or chart_pressed):
		if not _hud_blocks_game_navigation() and not _tutorial_is_modal():
			game.call("_on_phase_summary_continue_requested")
		_mark_input_handled()
		return
	if chart_pressed:
		_route_chart()
		_mark_input_handled()


func _route_menu_back() -> void:
	# UpgradeTree receives _input before this unhandled route and owns both its
	# ordinary close and pullback skip+close behavior.
	if _upgrade_tree_is_open():
		return
	if hud != null and hud.has_method("consume_menu_back"):
		if bool(hud.call("consume_menu_back")):
			return
	# Ending choices, startup recovery, and modal tutorial steps must not be
	# dismissed by a global Escape. A phase summary is intentionally absent from
	# this list: opening Settings over it is the pause-menu behavior.
	if _hud_state(&"is_startup_slots_open") or _tutorial_is_modal():
		return
	if _hud_state(&"is_settings_open") or _hud_state(&"is_controls_open"):
		return
	if hud != null and hud.has_method("open_settings"):
		hud.call("open_settings")


func _route_chart() -> void:
	if _upgrade_tree_is_open():
		return
	if _hud_blocks_game_navigation() or _tutorial_is_modal():
		return
	if upgrade_tree != null and upgrade_tree.has_method("open_tree"):
		upgrade_tree.call("open_tree")


func _hud_blocks_game_navigation() -> bool:
	return (
		_hud_state(&"is_startup_slots_open")
		or _hud_state(&"is_settings_open")
		or _hud_state(&"is_controls_open")
	)


func _upgrade_tree_is_open() -> bool:
	return (
		upgrade_tree != null
		and upgrade_tree.has_method("is_open")
		and bool(upgrade_tree.call("is_open"))
	)


func _tutorial_is_modal() -> bool:
	return (
		tutorial != null
		and tutorial.has_method("is_modal_step")
		and bool(tutorial.call("is_modal_step"))
	)


func _hud_state(method: StringName) -> bool:
	return hud != null and hud.has_method(method) and bool(hud.call(method))


func _action_pressed(event: InputEvent, action: StringName) -> bool:
	# Editable bindings include modifiers. Exact matching keeps, for example,
	# Shift+F11 bound to the chart from also firing the plain F11 fullscreen
	# action before the chart route sees it.
	return InputMap.has_action(action) and event.is_action_pressed(action, false, true)


func _is_button_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventAction:
		return event.pressed
	return false


func _is_raw_debug_input(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if event.keycode == KEY_F9:
		return true
	return event.ctrl_pressed and event.shift_pressed and event.keycode in DEBUG_KEYS


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
