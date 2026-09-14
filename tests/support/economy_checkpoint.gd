extends RefCounted

# Diagnostic-only checkpoints. Variant bytes preserve Vector2 and 64-bit RNG
# state exactly; decoding deliberately disables object construction.
const FORMAT := "nightwatch-economy-checkpoint"
const VERSION := 1
const MAX_BYTES := 64 * 1024 * 1024
const FIELDS := {
	"game": ["next_simulation_id", "autosave_elapsed", "observation_phase_duration"],
	"clock": ["tick", "epoch", "hitstop_ticks", "cooldown_ticks"],
	"spawner": ["next_simulation_id", "next_contact_id"],
	"policy": ["counters"],
	"director": ["remaining", "opportunity_pending", "scheduler_seed", "scheduler_serial", "event_serial", "cycle", "tickets"],
	"contacts": ["dishes", "cursor_position"],
	"observer": ["seen", "selected"],
}

static func owners(session) -> Dictionary:
	var game = session.game
	return {"game": game, "clock": game.simulation_clock, "spawner": game.spawner,
		"policy": game.spawner.spawn_policy, "director": game.deep_sky.director,
		"contacts": game.sky_contacts, "observer": game.observer}

static func streams(session) -> Dictionary:
	return {"coverage": session.game.observer.coverage_rng, "purchase": session.purchase_rng,
		"warm_contact": session.game.spawner.warm_contact_rng,
		"anomaly": session.game.deep_sky.director.occurrence_rng}

static func capture(session) -> Dictionary:
	var runtime := {}
	var targets := owners(session)
	for owner in FIELDS:
		runtime[owner] = {}
		for field in FIELDS[owner]: runtime[owner][field] = targets[owner].get(field)
	var rng := {}
	var generators := streams(session)
	for key in generators:
		rng[key] = {"seed": generators[key].seed, "state": generators[key].state}
	return {"config": session.config.duplicate(true), "run": session.game._build_save_data(),
		"viewport_size": session.game.get_viewport_rect().size,
		"runtime": runtime.duplicate(true), "rng": rng, "rounds": session.rounds.duplicate(true),
		"purchases": session.purchases.duplicate(true), "actions": session.actions.duplicate(true),
		"spent": session.spent, "revision": session.revision,
		"lineage": session.checkpoint_lineage.duplicate(true)}

static func restore(session, data: Dictionary) -> void:
	var game = session.game
	game._apply_save_data(data.run)
	# Player saves intentionally reset the sky and skip these streams at an
	# intermission. A diagnostic continuation must retain their exact states.
	game.spawner.restore_simulation_save(data.run.simulation.spawner)
	game.events.restore_simulation_save(data.run.simulation.events)
	var targets := owners(session)
	for owner in FIELDS:
		for field in FIELDS[owner]: targets[owner].set(field, data.runtime[owner][field])
	var generators := streams(session)
	for key in generators:
		generators[key].seed = data.rng[key].seed
		generators[key].state = data.rng[key].state
	# Reconcile derived capacity with current research when branching after edits.
	game.sky_contacts.refresh_dishes()
	session.rounds.assign(data.rounds)
	session.purchases.assign(data.purchases)
	session.actions.assign(data.actions)
	session.spent = data.spent
	session.revision = data.revision
	session.checkpoint_lineage.assign(data.lineage)

static func source_manifest() -> Dictionary:
	var files: Array[String] = ["res://project.godot", "res://scenes/main.tscn", "res://tools/economy_simulator.gd"]
	_collect_scripts("res://scripts", files)
	_collect_scripts("res://tests/support", files)
	files.sort()
	var hashes := {}
	for path in files: hashes[path] = FileAccess.get_sha256(path)
	return {"engine": Engine.get_version_info().string, "platform": OS.get_name(), "files": hashes}

static func _collect_scripts(directory: String, files: Array[String]) -> void:
	for name in DirAccess.get_files_at(directory):
		if name.ends_with(".gd"): files.append(directory.path_join(name))
	for name in DirAccess.get_directories_at(directory):
		_collect_scripts(directory.path_join(name), files)

static func write_file(path: String, data: Dictionary, source: Dictionary) -> Dictionary:
	if path.is_empty(): return {"ok": false, "error": "invalid_checkpoint_path"}
	var bytes := var_to_bytes(data)
	var envelope := {"format": FORMAT, "version": VERSION, "source": source,
		"sha256": _digest(bytes), "payload": Marshalls.raw_to_base64(bytes)}
	var absolute := ProjectSettings.globalize_path(path)
	var staged := absolute + ".tmp.%d" % OS.get_process_id()
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "checkpoint_write_failed", "detail": error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(envelope, "\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(staged, absolute)
	if error != OK:
		DirAccess.remove_absolute(staged)
		return {"ok": false, "error": "checkpoint_write_failed", "detail": error_string(error)}
	return {"ok": true, "path": absolute}

static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "checkpoint_read_failed"}
	if file.get_length() > MAX_BYTES: return {"ok": false, "error": "checkpoint_too_large"}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"ok": false, "error": "invalid_checkpoint"}
	var envelope: Dictionary = json.data
	if envelope.get("format") != FORMAT or envelope.get("version") != VERSION:
		return {"ok": false, "error": "unsupported_checkpoint_version"}
	if not envelope.get("payload") is String or not envelope.get("source") is Dictionary:
		return {"ok": false, "error": "invalid_checkpoint"}
	var bytes := Marshalls.base64_to_raw(envelope.payload)
	if bytes.is_empty() or _digest(bytes) != envelope.get("sha256"):
		return {"ok": false, "error": "checkpoint_checksum_mismatch"}
	var data = bytes_to_var(bytes)
	if not data is Dictionary: return {"ok": false, "error": "invalid_checkpoint"}
	return {"ok": true, "data": data, "source": envelope.source, "sha256": envelope.sha256}

static func validate(data: Dictionary, session) -> String:
	if not data.get("viewport_size") is Vector2: return "invalid_checkpoint_viewport"
	for key in ["config", "run", "runtime", "rng"]:
		if not data.get(key) is Dictionary: return "invalid_checkpoint_" + key
	for key in ["rounds", "purchases", "actions", "lineage"]:
		if not data.get(key) is Array: return "invalid_checkpoint_" + key
		for row in data[key]:
			if not row is Dictionary: return "invalid_checkpoint_" + key
	if not data.get("revision") is int or data.revision < 0: return "invalid_checkpoint_revision"
	if not data.get("spent") is float or not is_finite(data.spent) or data.spent < 0: return "invalid_checkpoint_spent"
	var run: Dictionary = data.run
	if run.get("observation_phase_active", true) != false: return "checkpoint_not_at_boundary"
	if not run.get("progression") is Dictionary or not run.get("deep_sky") is Dictionary or not run.get("simulation") is Dictionary:
		return "invalid_checkpoint_run"
	if not session.game.save_games._valid_run_data(run) or not session.game._supports_deep_sky_save(run):
		return "invalid_checkpoint_run"
	for key in ["spawner", "events"]:
		if not run.simulation.get(key) is Dictionary: return "invalid_checkpoint_simulation"
	if not run.progression.get("purchased_nodes") is Array: return "invalid_checkpoint_research"
	for id in run.progression.purchased_nodes:
		if not id is String or session.Balance.upgrade_definition(id).is_empty(): return "checkpoint_unknown_research"
	var extension = run.deep_sky.get("extension", {})
	if not extension is Dictionary or not extension.get("research_ids") is Array: return "invalid_checkpoint_research"
	for id in extension.research_ids:
		if not id is String or not session.Expansion.RESEARCH.has(id): return "checkpoint_unknown_research"
	var targets := owners(session)
	for owner in FIELDS:
		if not data.runtime.get(owner) is Dictionary: return "invalid_checkpoint_runtime"
		for field in FIELDS[owner]:
			if not data.runtime[owner].has(field) or typeof(data.runtime[owner][field]) != typeof(targets[owner].get(field)):
				return "invalid_checkpoint_runtime"
	for key in streams(session):
		if not data.rng.get(key) is Dictionary or not data.rng[key].get("seed") is int or not data.rng[key].get("state") is int:
			return "invalid_checkpoint_rng"
	return ""

static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
