class_name GameInputBindings
extends RefCounted

## Canonical Nightwatch input metadata and lossless ConfigFile serialization.
##
## Project defaults are deliberately repeated here. project.godot initializes the
## actions before any scene runs; this table lets tests and settings reloads restore
## that same baseline before applying a saved editable-slot override.

const ACTION_OBSERVE: StringName = &"nw_observe"
const ACTION_DISH: StringName = &"nw_dish"
const ACTION_CHART: StringName = &"nw_chart"
const ACTION_MENU_BACK: StringName = &"nw_menu_back"
const ACTION_CONTINUE: StringName = &"nw_continue"
const ACTION_FULLSCREEN: StringName = &"nw_fullscreen"

const ACTION_ORDER := [
	ACTION_OBSERVE,
	ACTION_DISH,
	ACTION_CHART,
	ACTION_MENU_BACK,
	ACTION_CONTINUE,
	ACTION_FULLSCREEN,
]

const RESERVED_DEBUG_KEYS := [
	KEY_D,
	KEY_N,
	KEY_A,
	KEY_G,
	KEY_M,
	KEY_R,
	KEY_S,
	KEY_F,
	KEY_BACKSPACE,
]

const RESERVED_GUI_NAVIGATION_KEYS := [
	KEY_TAB,
	KEY_UP,
	KEY_DOWN,
	KEY_LEFT,
	KEY_RIGHT,
	KEY_HOME,
	KEY_END,
	KEY_PAGEUP,
	KEY_PAGEDOWN,
]

const _NO_MODIFIERS := {
	"shift": false,
	"alt": false,
	"ctrl": false,
	"meta": false,
}

const ACTION_METADATA := {
	ACTION_OBSERVE: {
		"active_contexts": [&"observation"],
		"slots": [
			{
				"id": &"primary",
				"editable": false,
				"locked": true,
				"optional": false,
				"default": {
					"kind": "mouse_button",
					"code": MOUSE_BUTTON_LEFT,
					"modifiers": _NO_MODIFIERS,
				},
			},
		],
	},
	ACTION_DISH: {
		"active_contexts": [&"observation"],
		"slots": [
			{
				"id": &"primary",
				"editable": false,
				"locked": true,
				"optional": false,
				"default": {
					"kind": "mouse_button",
					"code": MOUSE_BUTTON_RIGHT,
					"modifiers": _NO_MODIFIERS,
				},
			},
		],
	},
	ACTION_CHART: {
		"active_contexts": [&"observation", &"research_chart"],
		"slots": [
			{
				"id": &"primary",
				"editable": true,
				"locked": false,
				"optional": false,
				"accepted_kinds": ["key"],
				"default": {
					"kind": "key",
					"logical": KEY_U,
					"modifiers": _NO_MODIFIERS,
				},
			},
		],
	},
	ACTION_MENU_BACK: {
		"active_contexts": [
			&"observation",
			&"research_chart",
			&"settings",
			&"dialog",
			&"phase_summary",
		],
		"slots": [
			{
				"id": &"primary",
				"editable": false,
				"locked": true,
				"optional": false,
				"default": {
					"kind": "key",
					"logical": KEY_ESCAPE,
					"modifiers": _NO_MODIFIERS,
				},
			},
			{
				"id": &"alternate",
				"editable": true,
				"locked": false,
				"optional": true,
				"accepted_kinds": ["key"],
				"reserved_keycodes": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
				"default": null,
			},
		],
	},
	ACTION_CONTINUE: {
		"active_contexts": [&"phase_summary"],
		"slots": [
			{
				"id": &"enter",
				"editable": false,
				"locked": true,
				"optional": false,
				"default": {
					"kind": "key",
					"logical": KEY_ENTER,
					"modifiers": _NO_MODIFIERS,
				},
			},
			{
				"id": &"space",
				"editable": false,
				"locked": true,
				"optional": false,
				"default": {
					"kind": "key",
					"logical": KEY_SPACE,
					"modifiers": _NO_MODIFIERS,
				},
			},
			{
				"id": &"primary",
				"editable": true,
				"locked": false,
				"optional": false,
				"accepted_kinds": ["key"],
				"default": {
					"kind": "key",
					"logical": KEY_U,
					"modifiers": _NO_MODIFIERS,
				},
			},
		],
	},
	ACTION_FULLSCREEN: {
		"active_contexts": [&"global"],
		"slots": [
			{
				"id": &"primary",
				"editable": true,
				"locked": false,
				"optional": false,
				"accepted_kinds": ["key"],
				"reserved_keycodes": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
				"default": {
					"kind": "key",
					"logical": KEY_F11,
					"modifiers": _NO_MODIFIERS,
				},
			},
		],
	},
}


static func action_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for action_value in ACTION_ORDER:
		names.append(StringName(action_value))
	return names


static func has_action(action: StringName) -> bool:
	return ACTION_METADATA.has(StringName(action))


static func metadata_for_action(action: StringName) -> Dictionary:
	var normalized := StringName(action)
	if not ACTION_METADATA.has(normalized):
		return {}
	var result: Dictionary = ACTION_METADATA[normalized].duplicate(true)
	# Keep a short alias for consumers written before active_contexts was named.
	result["contexts"] = result["active_contexts"].duplicate()
	return result


static func all_metadata() -> Dictionary:
	var result := {}
	for action_value in ACTION_ORDER:
		var action := StringName(action_value)
		result[action] = metadata_for_action(action)
	return result


static func fixed_descriptors(action: StringName) -> Array:
	return _slot_descriptors(action, false)


static func default_editable_descriptors(action: StringName) -> Array:
	return _slot_descriptors(action, true)


static func editable_slots(action: StringName) -> Array:
	var result: Array = []
	var metadata := metadata_for_action(action)
	for slot_value in metadata.get("slots", []):
		var slot: Dictionary = slot_value
		if bool(slot.get("editable", false)):
			result.append(slot.duplicate(true))
	return result


static func project_default_descriptors(action: StringName) -> Array:
	var result := fixed_descriptors(action)
	result.append_array(default_editable_descriptors(action))
	return result


static func reset_input_map_to_project_defaults() -> void:
	for action_value in ACTION_ORDER:
		var action := StringName(action_value)
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		for descriptor_value in project_default_descriptors(action):
			if descriptor_value == null:
				continue
			var input_event := descriptor_to_event(descriptor_value)
			if input_event != null:
				InputMap.action_add_event(action, input_event)


static func apply_editable_overrides(overrides: Dictionary) -> void:
	# Always begin from the known project baseline so reloads cannot retain stale
	# runtime events from an earlier profile.
	reset_input_map_to_project_defaults()
	for action_value in ACTION_ORDER:
		var action := StringName(action_value)
		var descriptors: Array = fixed_descriptors(action)
		if overrides.has(action):
			descriptors.append_array(overrides[action])
		else:
			descriptors.append_array(default_editable_descriptors(action))
		InputMap.action_erase_events(action)
		for descriptor_value in descriptors:
			if descriptor_value == null:
				continue
			var input_event := descriptor_to_event(descriptor_value)
			if input_event != null:
				InputMap.action_add_event(action, input_event)


static func validate_descriptor(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("not_dictionary")
	var descriptor: Dictionary = value
	var kind_value: Variant = descriptor.get("kind", null)
	if typeof(kind_value) != TYPE_STRING and typeof(kind_value) != TYPE_STRING_NAME:
		return _failure("missing_kind")
	var kind := String(kind_value)
	var modifiers_result := _validate_modifiers(descriptor.get("modifiers", null))
	if not bool(modifiers_result.get("ok", false)):
		return modifiers_result
	var normalized_modifiers: Dictionary = modifiers_result["modifiers"]

	if kind == "key":
		var has_logical := descriptor.has("logical")
		var has_physical := descriptor.has("physical")
		if has_logical == has_physical:
			return _failure("key_code_choice")
		if descriptor.size() != 3:
			return _failure("unexpected_fields")
		var field := "logical" if has_logical else "physical"
		var code_value: Variant = descriptor[field]
		if typeof(code_value) != TYPE_INT or int(code_value) <= 0:
			return _failure("invalid_key_code")
		var reserved_reason := _reserved_key_reason(int(code_value), normalized_modifiers)
		if not reserved_reason.is_empty():
			return _failure(reserved_reason)
		return {
			"ok": true,
			"descriptor": {
				"kind": "key",
				field: int(code_value),
				"modifiers": normalized_modifiers,
			},
		}

	if kind == "mouse_button":
		if descriptor.size() != 3 or not descriptor.has("code"):
			return _failure("unexpected_fields")
		var button_value: Variant = descriptor["code"]
		if typeof(button_value) != TYPE_INT or int(button_value) <= 0 or int(button_value) > 9:
			return _failure("invalid_mouse_button")
		return {
			"ok": true,
			"descriptor": {
				"kind": "mouse_button",
				"code": int(button_value),
				"modifiers": normalized_modifiers,
			},
		}

	return _failure("unsupported_kind")


static func event_to_descriptor(input_event: InputEvent, use_physical: bool = false) -> Dictionary:
	if input_event is InputEventKey:
		var key_event := input_event as InputEventKey
		var descriptor := {
			"kind": "key",
			"modifiers": _modifiers_from_event(key_event),
		}
		if use_physical and key_event.physical_keycode != KEY_NONE:
			descriptor["physical"] = int(key_event.physical_keycode)
		elif key_event.keycode != KEY_NONE:
			descriptor["logical"] = int(key_event.keycode)
		elif key_event.physical_keycode != KEY_NONE:
			descriptor["physical"] = int(key_event.physical_keycode)
		else:
			return {}
		return descriptor
	if input_event is InputEventMouseButton:
		var mouse_event := input_event as InputEventMouseButton
		return {
			"kind": "mouse_button",
			"code": int(mouse_event.button_index),
			"modifiers": _modifiers_from_event(mouse_event),
		}
	return {}


static func descriptor_to_event(value: Variant) -> InputEvent:
	var validation := validate_descriptor(value)
	if not bool(validation.get("ok", false)):
		return null
	var descriptor: Dictionary = validation["descriptor"]
	var input_event: InputEvent
	if String(descriptor["kind"]) == "key":
		var key_event := InputEventKey.new()
		if descriptor.has("logical"):
			key_event.keycode = int(descriptor["logical"])
		else:
			key_event.physical_keycode = int(descriptor["physical"])
		input_event = key_event
	else:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = int(descriptor["code"])
		input_event = mouse_event
	_apply_modifiers(input_event, descriptor["modifiers"])
	return input_event


static func descriptors_equal(left_value: Variant, right_value: Variant) -> bool:
	if left_value == null or right_value == null:
		return left_value == right_value
	var left_result := validate_descriptor(left_value)
	var right_result := validate_descriptor(right_value)
	if not bool(left_result.get("ok", false)) or not bool(right_result.get("ok", false)):
		return false
	return left_result["descriptor"] == right_result["descriptor"]


static func descriptor_label(value: Variant) -> String:
	var validation := validate_descriptor(value)
	if not bool(validation.get("ok", false)):
		return ""
	var descriptor: Dictionary = validation["descriptor"]
	var label := ""
	if String(descriptor["kind"]) == "mouse_button":
		match int(descriptor["code"]):
			MOUSE_BUTTON_LEFT:
				label = "LMB"
			MOUSE_BUTTON_RIGHT:
				label = "RMB"
			MOUSE_BUTTON_MIDDLE:
				label = "MMB"
			_:
				label = "Mouse %d" % int(descriptor["code"])
	else:
		var code := int(descriptor.get("logical", descriptor.get("physical", 0)))
		label = "Esc" if code == KEY_ESCAPE else OS.get_keycode_string(code)
		if label.is_empty():
			label = "Key %d" % code
	var modifiers: Dictionary = descriptor["modifiers"]
	var prefixes: PackedStringArray = []
	if bool(modifiers["ctrl"]):
		prefixes.append("Ctrl")
	if bool(modifiers["alt"]):
		prefixes.append("Alt")
	if bool(modifiers["shift"]):
		prefixes.append("Shift")
	if bool(modifiers["meta"]):
		prefixes.append("Meta")
	if prefixes.is_empty():
		return label
	prefixes.append(label)
	return "+".join(prefixes)


static func contexts_overlap(left_action: StringName, right_action: StringName) -> bool:
	if StringName(left_action) == StringName(right_action):
		return true
	var left_metadata := metadata_for_action(left_action)
	var right_metadata := metadata_for_action(right_action)
	if left_metadata.is_empty() or right_metadata.is_empty():
		return false
	var left_contexts: Array = left_metadata.get("active_contexts", [])
	var right_contexts: Array = right_metadata.get("active_contexts", [])
	if &"global" in left_contexts or &"global" in right_contexts:
		return true
	for context_value in left_contexts:
		if context_value in right_contexts:
			return true
	return false


static func _reserved_key_reason(code: int, modifiers: Dictionary) -> String:
	# Focus navigation is consumed by Control before the router's unhandled-input
	# stage. Keeping it configurable would create another saved-but-inert binding.
	if code in RESERVED_GUI_NAVIGATION_KEYS:
		return "reserved_gui_navigation"
	# Game._unhandled_input owns these raw shortcuts before configurable actions
	# route. Accepting one would create a binding that saves successfully but can
	# never fire.
	if code == KEY_F9:
		return "reserved_debug_input"
	if bool(modifiers["ctrl"]) and bool(modifiers["shift"]) and code in RESERVED_DEBUG_KEYS:
		return "reserved_debug_input"
	return ""


static func _slot_descriptors(action: StringName, editable: bool) -> Array:
	var result: Array = []
	var metadata := metadata_for_action(action)
	for slot_value in metadata.get("slots", []):
		var slot: Dictionary = slot_value
		if bool(slot.get("editable", false)) != editable:
			continue
		var descriptor: Variant = slot.get("default", null)
		result.append(null if descriptor == null else descriptor.duplicate(true))
	return result


static func _validate_modifiers(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("invalid_modifiers")
	var modifiers: Dictionary = value
	if modifiers.size() != 4:
		return _failure("invalid_modifiers")
	for key in ["shift", "alt", "ctrl", "meta"]:
		if not modifiers.has(key) or typeof(modifiers[key]) != TYPE_BOOL:
			return _failure("invalid_modifiers")
	return {
		"ok": true,
		"modifiers": {
			"shift": bool(modifiers["shift"]),
			"alt": bool(modifiers["alt"]),
			"ctrl": bool(modifiers["ctrl"]),
			"meta": bool(modifiers["meta"]),
		},
	}


static func _modifiers_from_event(input_event: InputEventWithModifiers) -> Dictionary:
	return {
		"shift": input_event.shift_pressed,
		"alt": input_event.alt_pressed,
		"ctrl": input_event.ctrl_pressed,
		"meta": input_event.meta_pressed,
	}


static func _apply_modifiers(input_event: InputEvent, modifiers: Dictionary) -> void:
	if not input_event is InputEventWithModifiers:
		return
	var modified_event := input_event as InputEventWithModifiers
	modified_event.shift_pressed = bool(modifiers["shift"])
	modified_event.alt_pressed = bool(modifiers["alt"])
	modified_event.ctrl_pressed = bool(modifiers["ctrl"])
	modified_event.meta_pressed = bool(modifiers["meta"])


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
