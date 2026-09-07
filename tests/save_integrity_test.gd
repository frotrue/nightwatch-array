extends SceneTree
const Saves = preload("res://scripts/save_game_controller.gd")
var failures: Array[String] = []

class FailingSave:
	extends Saves
	var fail_write := false
	var fail_commit := false
	func _write_slot_config(config: ConfigFile, path: String) -> Error:
		if fail_write:
			return ERR_FILE_CANT_WRITE
		return super._write_slot_config(config, path)
	func _commit_slot_file(staged: String, destination: String) -> Error:
		if fail_commit:
			return ERR_CANT_CREATE
		return super._commit_slot_file(staged, destination)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory := "res://build/save_integrity_%d" % Time.get_ticks_usec()
	var saves := FailingSave.new()
	saves.save_directory = directory
	root.add_child(saves)
	var old := {"elapsed_time": 73.0, "progression": {"observation_data": 420.0, "purchased_nodes": ["better_lens"]}}
	var newer := {"elapsed_time": 81.0, "progression": {"observation_data": 800.0, "purchased_nodes": ["better_lens", "wide_field"]}}
	_check(saves.save_slot(1, old) == OK, "initial save succeeds")
	var path := directory.path_join("slot_1.cfg")
	var hash_before := FileAccess.get_sha256(path)
	var summary_before: Dictionary = saves.get_slot_summary(1)
	saves.fail_write = true
	_check(saves.save_slot(1, newer) == ERR_FILE_CANT_WRITE, "staging write failure propagates")
	_check(FileAccess.get_sha256(path) == hash_before and saves.load_slot(1) == old, "write failure preserves previous bytes and readable run")
	saves.fail_write = false
	saves.fail_commit = true
	_check(saves.save_slot(1, newer) == ERR_CANT_CREATE, "commit failure propagates")
	_check(FileAccess.get_sha256(path) == hash_before and saves.get_slot_summary(1) == summary_before, "commit failure preserves data and cached summary")
	_check(not FileAccess.file_exists(path + ".tmp.%d" % OS.get_process_id()), "failed staging artifact is cleaned")
	saves.fail_commit = false
	_check(saves.save_slot(1, newer) == OK and saves.load_slot(1) == newer, "replacement succeeds without a delete gap")
	_check(saves.get_slot_summary(1).upgrade_level == 2, "replacement updates the summary")
	var detached: Dictionary = saves.load_slot(1)
	detached.progression.observation_data = 0.0
	_check(saves.load_slot(1) == newer, "loaded payload is detached from the persisted record")
	# A leftover staging file is not a committed save, including after a crash.
	var staged := ConfigFile.new()
	staged.set_value("meta", "version", 1)
	staged.set_value("run", "data", old)
	staged.save(path + ".tmp")
	_check(saves.load_slot(1) == newer, "uncommitted staging file cannot override a good save")
	var corrupt_path := directory.path_join("slot_2.cfg")
	var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	file.store_string("[run\nbroken=")
	file.close()
	var errors_were_visible := Engine.print_error_messages
	Engine.print_error_messages = false # Only the deliberate ConfigFile syntax error.
	var corrupt: Dictionary = saves._read_slot_summary(2)
	var broken_run: Dictionary = saves.load_slot(2)
	Engine.print_error_messages = errors_were_visible
	_check(corrupt.exists and not corrupt.valid and broken_run.is_empty(), "corrupt file remains an occupied invalid slot, never a new-game slot")
	_check(FileAccess.file_exists(corrupt_path), "inspection does not erase corrupt files")
	_check(not saves.get_slot_summary(3).exists, "genuinely missing file is an empty slot")
	for invalid in [{"elapsed_time": {}}, {"progression": []}, {"progression": {"observation_data": INF}}, {}]:
		var config := ConfigFile.new()
		config.set_value("meta", "version", 1)
		config.set_value("run", "data", invalid)
		config.save(directory.path_join("slot_3.cfg"))
		var summary: Dictionary = saves._read_slot_summary(3)
		_check(summary.exists and not summary.valid and saves.load_slot(3).is_empty(), "malformed numeric/container payload is rejected consistently")
		_check(saves.save_slot(1, invalid) == ERR_INVALID_DATA and saves.load_slot(1) == newer, "invalid write cannot replace a valid record")
	_check(saves.reset_slot(2) == OK and not saves.get_slot_summary(2).exists, "explicit reset still clears a corrupt slot")
	saves.free()
	if failures.is_empty():
		print("SAVE_INTEGRITY_PASS: staged replacement, write/commit failures, corrupt occupancy, detached reads, numeric validation and explicit reset")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SAVE_INTEGRITY: " + message)
