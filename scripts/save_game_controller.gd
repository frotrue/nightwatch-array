extends Node

signal slots_changed

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const RUN_NUMBER_FIELDS := ["elapsed_time", "observation_round", "observation_phase_remaining", "observation_phase_duration", "phase_start_successes", "phase_start_manual_successes", "phase_start_automatic_successes", "phase_start_total_data", "best_round_rate", "best_round_data"]
const PROGRESSION_NUMBER_FIELDS := ["observation_data", "success_count", "manual_successes", "automatic_successes", "total_data_earned", "best_multiplier", "leonid_charge"]

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
	if not _valid_run_data(run_data):
		return ERR_INVALID_DATA
	_ensure_save_directory()
	var config := ConfigFile.new()
	var saved_at := int(Time.get_unix_time_from_system())
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "saved_at", saved_at)
	config.set_value("run", "data", run_data.duplicate(true))
	# Stage beside the destination, then replace it in one rename. A failed
	# write/commit never truncates the last successfully saved player record.
	var destination := ProjectSettings.globalize_path(_slot_path(slot))
	var staged := destination + ".tmp.%d" % OS.get_process_id()
	var error := _write_slot_config(config, staged)
	if error == OK:
		error = _commit_slot_file(staged, destination)
	if error != OK and FileAccess.file_exists(staged):
		DirAccess.remove_absolute(staged)
	if error == OK:
		slot_summaries[slot] = _summary_from_run_data(run_data, saved_at)
		slots_changed.emit()
	return error


func _write_slot_config(config: ConfigFile, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(config.encode_to_text())
	file.flush()
	var error := file.get_error()
	file.close()
	return error


func _commit_slot_file(staged: String, destination: String) -> Error:
	return DirAccess.rename_absolute(staged, destination)


func load_slot(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {}
	var config := ConfigFile.new()
	if config.load(_slot_path(slot)) != OK:
		return {}
	return _decoded_run(config).duplicate(true)


func reset_slot(slot: int) -> Error:
	if not _is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	var absolute_path := ProjectSettings.globalize_path(_slot_path(slot))
	var error := OK
	if FileAccess.file_exists(absolute_path):
		error = DirAccess.remove_absolute(absolute_path)
	if error == OK:
		slot_summaries[slot] = {"exists": false, "valid": true}
		slots_changed.emit()
	return error


func get_slot_summary(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		return {"exists": false, "valid": false}
	if not slot_summaries.has(slot):
		slot_summaries[slot] = _read_slot_summary(slot)
	var summary = slot_summaries.get(slot, {})
	return summary.duplicate(true) if summary is Dictionary else {"exists": false, "valid": false}


func _read_slot_summary(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_slot_path(slot)):
		return {"exists": false, "valid": true}
	var config := ConfigFile.new()
	var error := config.load(_slot_path(slot))
	if error != OK:
		return {"exists": true, "valid": false}
	var data := _decoded_run(config)
	if data.is_empty():
		return {"exists": true, "valid": false}
	var timestamp = config.get_value("meta", "saved_at", 0)
	return _summary_from_run_data(data, timestamp if timestamp is int else 0)


func _decoded_run(config: ConfigFile) -> Dictionary:
	var version = config.get_value("meta", "version", -1)
	var data = config.get_value("run", "data", {})
	if not version is int or version != SAVE_VERSION or not data is Dictionary:
		return {}
	return data if _valid_run_data(data) else {}


func _valid_run_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var progression = data.get("progression", {})
	return progression is Dictionary and _valid_number_fields(data, RUN_NUMBER_FIELDS) and _valid_number_fields(progression, PROGRESSION_NUMBER_FIELDS)


func _valid_number_fields(data: Dictionary, fields: Array) -> bool:
	for key in fields:
		if not data.has(key):
			continue
		var value = data[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	return true


func _summary_from_run_data(run_data: Dictionary, saved_at: int) -> Dictionary:
	var progression_data = run_data.get("progression", {})
	if not (progression_data is Dictionary):
		progression_data = {}
	return {
		"exists": true,
		"valid": true,
		"saved_at": saved_at,
		"elapsed_time": _nonnegative_number(run_data.get("elapsed_time", 0.0)),
		"observation_data": _nonnegative_number(progression_data.get("observation_data", 0.0)),
		"upgrade_level": _validated_string_array(progression_data.get("purchased_nodes", [])).size(),
	}


func _nonnegative_number(value) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0.0
	return maxf(0.0, float(value))


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
