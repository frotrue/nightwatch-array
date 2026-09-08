extends Node

signal language_changed(locale: String)
signal number_notation_changed(notation: String)
signal audio_changed(master_linear: float, muted: bool)
signal master_volume_changed(master_linear: float)
signal mute_changed(muted: bool)
signal audio_policy_changed
signal fullscreen_changed(fullscreen: bool)
signal display_changed(fullscreen: bool)
signal performance_changed(vsync_enabled: bool, fps_limit: int)
signal accessibility_changed(motion_intensity: float, screen_flashes_enabled: bool)
signal binding_changed(action: StringName)
signal bindings_changed(action: StringName)
signal input_bindings_changed

const InputBindings = preload("res://scripts/game_input_bindings.gd")
const UITheme = preload("res://scripts/ui_theme.gd")

const SETTINGS_VERSION := 3
const SETTINGS_PATH := "user://settings.cfg"
const SUPPORTED_LOCALES := ["en", "ko"]
const NUMBER_NOTATIONS := ["compact", "scientific"]
const DEFAULT_MASTER_LINEAR := 1.0
const DEFAULT_MUTED := false
const DEFAULT_FULLSCREEN := false
const DEFAULT_MUTE_WHEN_UNFOCUSED := false
const DEFAULT_VSYNC_ENABLED := true
const DEFAULT_FPS_LIMIT := 0
const DEFAULT_MOTION_INTENSITY := 1.0
const DEFAULT_SCREEN_FLASHES_ENABLED := true
const SUPPORTED_FPS_LIMITS := [0, 30, 60, 120]
const MIN_MASTER_DB := -80.0

var settings_path: String = SETTINGS_PATH
var locale: String = "en"
var number_notation: String = "compact"
var tutorial_completed: bool = false
var research_chart_rotation: float = 0.0
var master_linear: float = DEFAULT_MASTER_LINEAR
var muted: bool = DEFAULT_MUTED
var fullscreen: bool = DEFAULT_FULLSCREEN
var mute_when_unfocused: bool = DEFAULT_MUTE_WHEN_UNFOCUSED
var vsync_enabled: bool = DEFAULT_VSYNC_ENABLED
var fps_limit: int = DEFAULT_FPS_LIMIT
var motion_intensity: float = DEFAULT_MOTION_INTENSITY
var screen_flashes_enabled: bool = DEFAULT_SCREEN_FLASHES_ENABLED

var _editable_bindings: Dictionary = {}
var _binding_load_errors: Dictionary = {}
var _loaded_version: int = 0
var _application_focused: bool = true


func _init(custom_settings_path: String = SETTINGS_PATH) -> void:
	settings_path = SETTINGS_PATH if custom_settings_path.is_empty() else custom_settings_path


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_application_focused = true if DisplayServer.get_name().to_lower() == "headless" else DisplayServer.window_is_focused()
	load_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_focused = true
		_apply_audio()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_focused = false
		_apply_audio()


func set_settings_path(custom_settings_path: String, reload_now: bool = false) -> void:
	settings_path = SETTINGS_PATH if custom_settings_path.is_empty() else custom_settings_path
	if reload_now and is_inside_tree():
		load_settings()


func load_settings(path_override: String = "") -> Dictionary:
	if not path_override.is_empty():
		settings_path = path_override
	var fallback_locale := _default_locale()
	locale = fallback_locale
	number_notation = "compact"
	tutorial_completed = false
	research_chart_rotation = 0.0
	master_linear = DEFAULT_MASTER_LINEAR
	muted = DEFAULT_MUTED
	fullscreen = DEFAULT_FULLSCREEN
	mute_when_unfocused = DEFAULT_MUTE_WHEN_UNFOCUSED
	vsync_enabled = DEFAULT_VSYNC_ENABLED
	fps_limit = DEFAULT_FPS_LIMIT
	motion_intensity = DEFAULT_MOTION_INTENSITY
	screen_flashes_enabled = DEFAULT_SCREEN_FLASHES_ENABLED
	_loaded_version = 0
	_binding_load_errors.clear()

	var config := ConfigFile.new()
	var load_error := config.load(settings_path)
	var config_loaded := load_error == OK
	if config_loaded:
		_loaded_version = _validated_version(config.get_value("settings", "version", 0))
		locale = _validated_locale(config.get_value("accessibility", "language", fallback_locale), fallback_locale)
		var saved_notation = config.get_value("display", "number_notation", "compact")
		if saved_notation is String and saved_notation in NUMBER_NOTATIONS:
			number_notation = saved_notation
		tutorial_completed = _validated_bool(
			config.get_value("onboarding", "tutorial_completed", false),
			false
		)
		research_chart_rotation = _validated_rotation(
			config.get_value("research_chart", "rotation", 0.0)
		)
		master_linear = _validated_linear(
			config.get_value("audio", "master_linear", DEFAULT_MASTER_LINEAR)
		)
		muted = _validated_bool(
			config.get_value("audio", "muted", DEFAULT_MUTED),
			DEFAULT_MUTED
		)
		mute_when_unfocused = _validated_bool(
			config.get_value("audio", "mute_when_unfocused", DEFAULT_MUTE_WHEN_UNFOCUSED),
			DEFAULT_MUTE_WHEN_UNFOCUSED
		)
		fullscreen = _validated_bool(
			config.get_value("display", "fullscreen", DEFAULT_FULLSCREEN),
			DEFAULT_FULLSCREEN
		)
		vsync_enabled = _validated_bool(
			config.get_value("display", "vsync_enabled", DEFAULT_VSYNC_ENABLED),
			DEFAULT_VSYNC_ENABLED
		)
		fps_limit = _validated_fps_limit(
			config.get_value("performance", "fps_limit", DEFAULT_FPS_LIMIT)
		)
		motion_intensity = _validated_unit_float(
			config.get_value("accessibility", "motion_intensity", DEFAULT_MOTION_INTENSITY),
			DEFAULT_MOTION_INTENSITY
		)
		screen_flashes_enabled = _validated_bool(
			config.get_value("accessibility", "screen_flashes_enabled", DEFAULT_SCREEN_FLASHES_ENABLED),
			DEFAULT_SCREEN_FLASHES_ENABLED
		)
	elif load_error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load settings: %s" % error_string(load_error))

	_editable_bindings = _load_bindings(config if config_loaded else null)
	InputBindings.apply_editable_overrides(_editable_bindings)
	TranslationServer.set_locale(locale)
	_apply_audio()
	_apply_fullscreen()
	_apply_vsync()
	_apply_performance()
	return {
		"error": load_error,
		"version": _loaded_version,
		"binding_errors": _binding_load_errors.duplicate(true),
	}


func save_settings() -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Replacing unreadable settings file: %s" % error_string(load_error))
	config.set_value("settings", "version", SETTINGS_VERSION)
	config.set_value("accessibility", "language", locale)
	config.set_value("display", "number_notation", number_notation)
	config.set_value("onboarding", "tutorial_completed", tutorial_completed)
	config.set_value("research_chart", "rotation", research_chart_rotation)
	config.set_value("audio", "master_linear", master_linear)
	config.set_value("audio", "muted", muted)
	config.set_value("audio", "mute_when_unfocused", mute_when_unfocused)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("performance", "fps_limit", fps_limit)
	if config.has_section_key("performance", "background_throttle"):
		config.erase_section_key("performance", "background_throttle")
	config.set_value("accessibility", "motion_intensity", motion_intensity)
	config.set_value("accessibility", "screen_flashes_enabled", screen_flashes_enabled)
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		config.set_value("input", String(action), _bindings_for_save(action))
	var ensure_error := _ensure_settings_directory()
	if ensure_error != OK:
		push_warning("Could not create settings directory: %s" % error_string(ensure_error))
		return ensure_error
	var save_error := config.save(settings_path)
	if save_error != OK:
		push_warning("Could not save settings: %s" % error_string(save_error))
	return save_error


func set_language(requested_locale: String, persist: bool = true) -> void:
	var normalized := requested_locale.to_lower().left(2)
	if normalized not in SUPPORTED_LOCALES:
		normalized = "en"
	if locale == normalized and TranslationServer.get_locale().left(2) == normalized:
		return
	locale = normalized
	TranslationServer.set_locale(locale)
	if persist:
		save_settings()
	language_changed.emit(locale)


func get_language_index() -> int:
	return SUPPORTED_LOCALES.find(locale)


func set_number_notation(value: String, persist: bool = true) -> void:
	if value not in NUMBER_NOTATIONS or value == number_notation:
		return
	number_notation = value
	if persist:
		save_settings()
	number_notation_changed.emit(number_notation)


func format_data(value: float, small_decimals: int = 0) -> String:
	return UITheme.data_number(value, number_notation, small_decimals)


func is_tutorial_completed() -> bool:
	return tutorial_completed


func set_tutorial_completed(completed: bool, persist: bool = true) -> void:
	if tutorial_completed == completed:
		return
	tutorial_completed = completed
	if persist:
		save_settings()


func get_research_chart_rotation() -> float:
	return research_chart_rotation


func set_research_chart_rotation(value: float, persist: bool = true) -> void:
	var normalized := wrapf(value, -PI, PI) if is_finite(value) else 0.0
	if is_equal_approx(research_chart_rotation, normalized):
		return
	research_chart_rotation = normalized
	if persist:
		save_settings()


func get_master_volume_linear() -> float:
	return master_linear


func get_master_linear() -> float:
	return master_linear


func set_master_volume_linear(value: float, persist: bool = true) -> void:
	var normalized := _validated_linear(value)
	if is_equal_approx(master_linear, normalized):
		_apply_audio()
		return
	master_linear = normalized
	_apply_audio()
	if persist:
		save_settings()
	master_volume_changed.emit(master_linear)
	audio_changed.emit(master_linear, muted)


func set_master_linear(value: float, persist: bool = true) -> void:
	set_master_volume_linear(value, persist)


func is_muted() -> bool:
	return muted


func set_muted(value: bool, persist: bool = true) -> void:
	if muted == value:
		_apply_audio()
		return
	muted = value
	_apply_audio()
	if persist:
		save_settings()
	mute_changed.emit(muted)
	audio_changed.emit(master_linear, muted)


func toggle_muted(persist: bool = true) -> bool:
	set_muted(not muted, persist)
	return muted


func should_mute_when_unfocused() -> bool:
	return mute_when_unfocused


func set_mute_when_unfocused(value: bool, persist: bool = true) -> void:
	if mute_when_unfocused == value:
		_apply_audio()
		return
	mute_when_unfocused = value
	_apply_audio()
	if persist:
		save_settings()
	audio_policy_changed.emit()


func toggle_mute_when_unfocused(persist: bool = true) -> bool:
	set_mute_when_unfocused(not mute_when_unfocused, persist)
	return mute_when_unfocused


func is_fullscreen() -> bool:
	return fullscreen


func set_fullscreen(value: bool, persist: bool = true) -> void:
	if fullscreen == value:
		_apply_fullscreen()
		return
	fullscreen = value
	_apply_fullscreen()
	if persist:
		save_settings()
	fullscreen_changed.emit(fullscreen)
	display_changed.emit(fullscreen)


func toggle_fullscreen(persist: bool = true) -> bool:
	set_fullscreen(not fullscreen, persist)
	return fullscreen


func is_vsync_enabled() -> bool:
	return vsync_enabled


func set_vsync_enabled(value: bool, persist: bool = true) -> void:
	if vsync_enabled == value:
		_apply_vsync()
		return
	vsync_enabled = value
	_apply_vsync()
	if persist:
		save_settings()
	performance_changed.emit(vsync_enabled, fps_limit)


func toggle_vsync(persist: bool = true) -> bool:
	set_vsync_enabled(not vsync_enabled, persist)
	return vsync_enabled


func get_fps_limit() -> int:
	return fps_limit


func set_fps_limit(value: int, persist: bool = true) -> void:
	var normalized := _validated_fps_limit(value)
	if fps_limit == normalized:
		_apply_performance()
		return
	fps_limit = normalized
	_apply_performance()
	if persist:
		save_settings()
	performance_changed.emit(vsync_enabled, fps_limit)


func get_motion_intensity() -> float:
	return motion_intensity


func set_motion_intensity(value: float, persist: bool = true) -> void:
	var normalized := _validated_unit_float(value, DEFAULT_MOTION_INTENSITY)
	if is_equal_approx(motion_intensity, normalized):
		return
	motion_intensity = normalized
	if persist:
		save_settings()
	accessibility_changed.emit(motion_intensity, screen_flashes_enabled)


func are_screen_flashes_enabled() -> bool:
	return screen_flashes_enabled


func set_screen_flashes_enabled(value: bool, persist: bool = true) -> void:
	if screen_flashes_enabled == value:
		return
	screen_flashes_enabled = value
	if persist:
		save_settings()
	accessibility_changed.emit(motion_intensity, screen_flashes_enabled)


func toggle_screen_flashes(persist: bool = true) -> bool:
	set_screen_flashes_enabled(not screen_flashes_enabled, persist)
	return screen_flashes_enabled


func get_input_actions_metadata() -> Dictionary:
	return InputBindings.all_metadata()


func get_action_metadata(action: StringName) -> Dictionary:
	return InputBindings.metadata_for_action(action)


func get_binding_load_errors() -> Dictionary:
	return _binding_load_errors.duplicate(true)


func binding_labels(action: StringName) -> PackedStringArray:
	var labels: PackedStringArray = []
	for binding_value in _effective_slot_bindings(action):
		var binding: Dictionary = binding_value
		var descriptor: Variant = binding.get("descriptor", null)
		if descriptor == null:
			continue
		var label := InputBindings.descriptor_label(descriptor)
		if not label.is_empty():
			labels.append(label)
	return labels


func get_binding_labels(action: StringName) -> PackedStringArray:
	return binding_labels(action)


func binding_label(action: StringName, slot: int = -1) -> String:
	var labels := binding_labels(action)
	if slot >= 0:
		return labels[slot] if slot < labels.size() else ""
	return " / ".join(labels)


func get_binding_label(action: StringName, slot: int = -1) -> String:
	return binding_label(action, slot)


func get_editable_binding_event(action: StringName, editable_slot: int = 0) -> InputEvent:
	var normalized := StringName(action)
	if not _editable_bindings.has(normalized):
		return null
	var descriptors: Array = _editable_bindings[normalized]
	if editable_slot < 0 or editable_slot >= descriptors.size():
		return null
	var descriptor: Variant = descriptors[editable_slot]
	return null if descriptor == null else InputBindings.descriptor_to_event(descriptor)


func validate_binding_conflict(
	action: StringName,
	input_event: InputEvent,
	editable_slot: int = 0,
	use_physical: bool = false
) -> Dictionary:
	var descriptor := InputBindings.event_to_descriptor(input_event, use_physical)
	if descriptor.is_empty():
		return _result_failure("unsupported_event")
	return validate_binding_descriptor_conflict(action, descriptor, editable_slot)


func validate_binding_descriptor_conflict(
	action: StringName,
	descriptor_value: Variant,
	editable_slot: int = 0
) -> Dictionary:
	var normalized := StringName(action)
	if not InputBindings.has_action(normalized):
		return _result_failure("unknown_action")
	var slots := InputBindings.editable_slots(normalized)
	if editable_slot < 0 or editable_slot >= slots.size():
		return _result_failure("locked_or_missing_slot")
	var validation := InputBindings.validate_descriptor(descriptor_value)
	if not bool(validation.get("ok", false)):
		return _result_failure(String(validation.get("reason", "invalid_descriptor")))
	var descriptor: Dictionary = validation["descriptor"]
	var target_slot: Dictionary = slots[editable_slot]
	var slot_rejection := _slot_descriptor_rejection(target_slot, descriptor)
	if not slot_rejection.is_empty():
		return _result_failure(slot_rejection)
	for other_action_value in InputBindings.action_names():
		var other_action := StringName(other_action_value)
		if not InputBindings.contexts_overlap(normalized, other_action):
			continue
		for binding_value in _effective_slot_bindings(other_action):
			var binding: Dictionary = binding_value
			if (
				other_action == normalized
				and bool(binding.get("editable", false))
				and int(binding.get("editable_index", -1)) == editable_slot
			):
				continue
			var other_descriptor: Variant = binding.get("descriptor", null)
			if other_descriptor == null:
				continue
			if InputBindings.descriptors_equal(descriptor, other_descriptor):
				return {
					"ok": false,
					"reason": "conflict",
					"conflict_action": other_action,
					"conflict_label": InputBindings.descriptor_label(other_descriptor),
					"conflict_locked": not bool(binding.get("editable", false)),
				}
	return {"ok": true, "descriptor": descriptor.duplicate(true)}


func set_editable_binding(
	action: StringName,
	input_event: InputEvent,
	editable_slot: int = 0,
	persist: bool = true,
	use_physical: bool = false
) -> Dictionary:
	var descriptor := InputBindings.event_to_descriptor(input_event, use_physical)
	if descriptor.is_empty():
		return _result_failure("unsupported_event")
	return set_editable_binding_descriptor(action, descriptor, editable_slot, persist)


func set_editable_binding_descriptor(
	action: StringName,
	descriptor_value: Variant,
	editable_slot: int = 0,
	persist: bool = true
) -> Dictionary:
	var normalized := StringName(action)
	var conflict := validate_binding_descriptor_conflict(normalized, descriptor_value, editable_slot)
	if not bool(conflict.get("ok", false)):
		return conflict
	var descriptors: Array = _editable_bindings.get(
		normalized,
		InputBindings.default_editable_descriptors(normalized)
	).duplicate(true)
	var descriptor: Dictionary = conflict["descriptor"]
	if InputBindings.descriptors_equal(descriptors[editable_slot], descriptor):
		return {"ok": true, "changed": false}
	descriptors[editable_slot] = descriptor.duplicate(true)
	_editable_bindings[normalized] = descriptors
	InputBindings.apply_editable_overrides(_editable_bindings)
	var save_error := OK
	if persist:
		save_error = save_settings()
	_emit_binding_changed(normalized)
	return {"ok": true, "changed": true, "save_error": save_error}


func clear_editable_binding(
	action: StringName,
	editable_slot: int = 0,
	persist: bool = true
) -> Dictionary:
	var normalized := StringName(action)
	if not InputBindings.has_action(normalized):
		return _result_failure("unknown_action")
	var slots := InputBindings.editable_slots(normalized)
	if editable_slot < 0 or editable_slot >= slots.size():
		return _result_failure("locked_or_missing_slot")
	var slot: Dictionary = slots[editable_slot]
	if not bool(slot.get("optional", false)):
		return _result_failure("required_binding")
	var descriptors: Array = _editable_bindings.get(
		normalized,
		InputBindings.default_editable_descriptors(normalized)
	).duplicate(true)
	if descriptors[editable_slot] == null:
		return {"ok": true, "changed": false}
	descriptors[editable_slot] = null
	_editable_bindings[normalized] = descriptors
	InputBindings.apply_editable_overrides(_editable_bindings)
	var save_error := OK
	if persist:
		save_error = save_settings()
	_emit_binding_changed(normalized)
	return {"ok": true, "changed": true, "save_error": save_error}


func reset_nightwatch_bindings(persist: bool = true) -> Error:
	_editable_bindings.clear()
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		_editable_bindings[action] = InputBindings.default_editable_descriptors(action)
	InputBindings.apply_editable_overrides(_editable_bindings)
	var save_error := OK
	if persist:
		save_error = save_settings()
	for action_value in InputBindings.action_names():
		binding_changed.emit(StringName(action_value))
		bindings_changed.emit(StringName(action_value))
	input_bindings_changed.emit()
	return save_error


func reset_input_bindings(persist: bool = true) -> Error:
	return reset_nightwatch_bindings(persist)


func _load_bindings(config: ConfigFile) -> Dictionary:
	var candidates := {}
	var saved_actions := {}
	var fallback_actions := {}
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		candidates[action] = InputBindings.default_editable_descriptors(action)
		if config == null or not config.has_section_key("input", String(action)):
			continue
		var validation := _validate_saved_action(action, config.get_value("input", String(action)))
		if bool(validation.get("ok", false)):
			candidates[action] = validation["descriptors"]
			saved_actions[action] = true
		else:
			fallback_actions[action] = true
			_binding_load_errors[action] = String(validation.get("reason", "invalid_binding"))

	# Conflicting saved overrides fall back by action. Repeat because restoring one
	# default may expose a conflict with another saved override. Project defaults are
	# conflict-free under the declared active contexts, so this always converges.
	var changed := true
	while changed:
		changed = false
		var conflicts := _conflicting_saved_actions(candidates, saved_actions, fallback_actions)
		for action_value in conflicts:
			var action := StringName(action_value)
			if fallback_actions.has(action):
				continue
			fallback_actions[action] = true
			candidates[action] = InputBindings.default_editable_descriptors(action)
			_binding_load_errors[action] = "conflict"
			changed = true
	return candidates


func _validate_saved_action(action: StringName, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _result_failure("not_array")
	var saved: Array = value
	var slots := InputBindings.editable_slots(action)
	if saved.size() > slots.size():
		return _result_failure("too_many_bindings")
	var descriptors: Array = []
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		if index >= saved.size() or saved[index] == null:
			if bool(slot.get("optional", false)):
				descriptors.append(null)
				continue
			return _result_failure("missing_required_binding")
		var validation := InputBindings.validate_descriptor(saved[index])
		if not bool(validation.get("ok", false)):
			return _result_failure(String(validation.get("reason", "invalid_descriptor")))
		var descriptor: Dictionary = validation["descriptor"]
		var slot_rejection := _slot_descriptor_rejection(slot, descriptor)
		if not slot_rejection.is_empty():
			return _result_failure(slot_rejection)
		descriptors.append(descriptor)
	var occupied := InputBindings.fixed_descriptors(action)
	for descriptor_value in descriptors:
		if descriptor_value == null:
			continue
		for occupied_value in occupied:
			if InputBindings.descriptors_equal(descriptor_value, occupied_value):
				return _result_failure("duplicate_binding")
		occupied.append(descriptor_value)
	return {"ok": true, "descriptors": descriptors}


func _conflicting_saved_actions(
	candidates: Dictionary,
	saved_actions: Dictionary,
	fallback_actions: Dictionary
) -> Array[StringName]:
	var conflicts: Array[StringName] = []
	var actions := InputBindings.action_names()
	for left_index in range(actions.size()):
		var left_action := StringName(actions[left_index])
		for right_index in range(left_index, actions.size()):
			var right_action := StringName(actions[right_index])
			if not InputBindings.contexts_overlap(left_action, right_action):
				continue
			var left_bindings := _candidate_slot_bindings(left_action, candidates[left_action])
			var right_bindings := _candidate_slot_bindings(right_action, candidates[right_action])
			for left_binding_value in left_bindings:
				var left_binding: Dictionary = left_binding_value
				for right_binding_value in right_bindings:
					var right_binding: Dictionary = right_binding_value
					if left_action == right_action and left_binding["slot_index"] >= right_binding["slot_index"]:
						continue
					if not InputBindings.descriptors_equal(left_binding["descriptor"], right_binding["descriptor"]):
						continue
					var left_saved := saved_actions.has(left_action) and not fallback_actions.has(left_action)
					var right_saved := saved_actions.has(right_action) and not fallback_actions.has(right_action)
					if left_saved and bool(left_binding["editable"]):
						if left_action not in conflicts:
							conflicts.append(left_action)
					if right_saved and bool(right_binding["editable"]):
						if right_action not in conflicts:
							conflicts.append(right_action)
	return conflicts


func _candidate_slot_bindings(action: StringName, editable_descriptors: Array) -> Array:
	var result: Array = []
	var metadata := InputBindings.metadata_for_action(action)
	var editable_index := 0
	var slot_index := 0
	for slot_value in metadata.get("slots", []):
		var slot: Dictionary = slot_value
		var editable := bool(slot.get("editable", false))
		var descriptor: Variant
		if editable:
			descriptor = editable_descriptors[editable_index]
			editable_index += 1
		else:
			descriptor = slot.get("default", null)
		if descriptor != null:
			result.append({
				"slot_index": slot_index,
				"editable": editable,
				"descriptor": descriptor,
			})
		slot_index += 1
	return result


func _effective_slot_bindings(action: StringName) -> Array:
	var normalized := StringName(action)
	if not InputBindings.has_action(normalized):
		return []
	var editable_descriptors: Array = _editable_bindings.get(
		normalized,
		InputBindings.default_editable_descriptors(normalized)
	)
	var result: Array = []
	var metadata := InputBindings.metadata_for_action(normalized)
	var editable_index := 0
	var slot_index := 0
	for slot_value in metadata.get("slots", []):
		var slot: Dictionary = slot_value
		var editable := bool(slot.get("editable", false))
		var descriptor: Variant
		var current_editable_index := -1
		if editable:
			descriptor = editable_descriptors[editable_index]
			current_editable_index = editable_index
			editable_index += 1
		else:
			descriptor = slot.get("default", null)
		result.append({
			"slot_index": slot_index,
			"editable_index": current_editable_index,
			"editable": editable,
			"locked": not editable,
			"optional": bool(slot.get("optional", false)),
			"descriptor": descriptor,
		})
		slot_index += 1
	return result


func _bindings_for_save(action: StringName) -> Array:
	var result: Array = []
	var descriptors: Array = _editable_bindings.get(
		action,
		InputBindings.default_editable_descriptors(action)
	)
	var slots := InputBindings.editable_slots(action)
	for index in range(descriptors.size()):
		var descriptor: Variant = descriptors[index]
		if descriptor == null and bool(slots[index].get("optional", false)):
			continue
		result.append(null if descriptor == null else descriptor.duplicate(true))
	return result


func _slot_descriptor_rejection(slot: Dictionary, descriptor: Dictionary) -> String:
	if String(descriptor["kind"]) not in slot.get("accepted_kinds", []):
		return "keyboard_only"
	if String(descriptor["kind"]) != "key":
		return ""
	var code := int(descriptor.get("logical", descriptor.get("physical", 0)))
	if code in slot.get("reserved_keycodes", []):
		return "reserved_gui_activation"
	return ""


func _emit_binding_changed(action: StringName) -> void:
	binding_changed.emit(action)
	bindings_changed.emit(action)
	input_bindings_changed.emit()


func _apply_audio() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		push_warning("Master audio bus is unavailable")
		return
	AudioServer.set_bus_volume_db(master_bus, maxf(linear_to_db(master_linear), MIN_MASTER_DB))
	AudioServer.set_bus_mute(master_bus, muted or (mute_when_unfocused and not _application_focused))


func _apply_fullscreen() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var requested_mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != requested_mode:
		DisplayServer.window_set_mode(requested_mode)


func _apply_vsync() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var requested_mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != requested_mode:
		DisplayServer.window_set_vsync_mode(requested_mode)


func _apply_performance() -> void:
	# Headless validation and performance probes own their own pacing contracts.
	if DisplayServer.get_name().to_lower() == "headless":
		return
	Engine.max_fps = fps_limit


func _ensure_settings_directory() -> Error:
	var directory := settings_path.get_base_dir()
	if directory.is_empty():
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))


func _default_locale() -> String:
	var fallback := OS.get_locale_language().to_lower().left(2)
	return fallback if fallback in SUPPORTED_LOCALES else "en"


func _validated_version(value: Variant) -> int:
	return int(value) if typeof(value) == TYPE_INT and int(value) >= 0 else 0


func _validated_locale(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return fallback
	var normalized := String(value).to_lower().left(2)
	return normalized if normalized in SUPPORTED_LOCALES else fallback


func _validated_bool(value: Variant, fallback: bool) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


func _validated_rotation(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var numeric := float(value)
	return wrapf(numeric, -PI, PI) if is_finite(numeric) else 0.0


func _validated_linear(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return DEFAULT_MASTER_LINEAR
	var numeric := float(value)
	return clampf(numeric, 0.0, 1.0) if is_finite(numeric) else DEFAULT_MASTER_LINEAR


func _validated_unit_float(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return fallback
	var numeric := float(value)
	return clampf(numeric, 0.0, 1.0) if is_finite(numeric) else fallback


func _validated_fps_limit(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return DEFAULT_FPS_LIMIT
	var numeric := int(value)
	return numeric if numeric in SUPPORTED_FPS_LIMITS else DEFAULT_FPS_LIMIT


func _result_failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
