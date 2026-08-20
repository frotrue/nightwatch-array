extends Node

signal slots_changed

const SAVE_VERSION := 1
const SLOT_COUNT := 3

var save_directory := "user://saves"
var slot_summaries: Dictionary = {}


func _ready() -> void:
	_ensure_save_directory()
	_reload_slot_summaries()


func set_save_directory(path: String) -> void:
	save_directory = path.trim_suffix("/")
	_ensure_save_directory()
	_reload_slot_summaries()
	slots_changed.emit()


func save_slot(slot: int, run_data: Dictionary) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	_ensure_save_directory()
	var config := ConfigFile.new()
	var saved_at := int(Time.get_unix_time_from_system())
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "saved_at", saved_at)
	config.set_value("run", "data", run_data.duplicate(true))
	var error := config.save(_slot_path(slot))
	if error == OK:
		slot_summaries[slot] = _summary_from_run_data(run_data, saved_at)
		slots_changed.emit()
	return error


func load_slot(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {}
	var config := ConfigFile.new()
	if config.load(_slot_path(slot)) != OK:
		return {}
	if int(config.get_value("meta", "version", -1)) != SAVE_VERSION:
		return {}
	var data = config.get_value("run", "data", {})
	return data.duplicate(true) if data is Dictionary else {}


func get_slot_summary(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {"exists": false, "valid": false}
	if not slot_summaries.has(slot):
		slot_summaries[slot] = _read_slot_summary(slot)
	var summary = slot_summaries.get(slot, {})
	return summary.duplicate(true) if summary is Dictionary else {"exists": false, "valid": false}


func _read_slot_summary(slot: int) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(_slot_path(slot))
	if error != OK:
		return {"exists": false, "valid": true}
	var version := int(config.get_value("meta", "version", -1))
	var data = config.get_value("run", "data", {})
	if version != SAVE_VERSION or not (data is Dictionary):
		return {"exists": true, "valid": false}
	var progression_data = data.get("progression", {})
	if not (progression_data is Dictionary):
		progression_data = {}
	return {
		"exists": true,
		"valid": true,
		"saved_at": int(config.get_value("meta", "saved_at", 0)),
		"elapsed_time": maxf(0.0, float(data.get("elapsed_time", 0.0))),
		"observation_data": maxf(0.0, float(progression_data.get("observation_data", 0.0))),
		"upgrade_level": _validated_string_array(progression_data.get("purchased_nodes", [])).size(),
	}


func _summary_from_run_data(run_data: Dictionary, saved_at: int) -> Dictionary:
	var progression_data = run_data.get("progression", {})
	if not (progression_data is Dictionary):
		progression_data = {}
	return {
		"exists": true,
		"valid": true,
		"saved_at": saved_at,
		"elapsed_time": maxf(0.0, float(run_data.get("elapsed_time", 0.0))),
		"observation_data": maxf(0.0, float(progression_data.get("observation_data", 0.0))),
		"upgrade_level": _validated_string_array(progression_data.get("purchased_nodes", [])).size(),
	}


func _reload_slot_summaries() -> void:
	slot_summaries.clear()
	for slot in range(1, SLOT_COUNT + 1):
		slot_summaries[slot] = _read_slot_summary(slot)


func has_slot(slot: int) -> bool:
	var summary := get_slot_summary(slot)
	return bool(summary.get("exists", false)) and bool(summary.get("valid", false))


func _slot_path(slot: int) -> String:
	return "%s/slot_%d.cfg" % [save_directory, slot]


func _is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func _ensure_save_directory() -> void:
	var absolute_path := ProjectSettings.globalize_path(save_directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("Could not create save directory: %s" % error_string(error))


func _validated_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(String(entry))
	return result
