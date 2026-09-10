extends Node2D

signal changed
const Modules = preload("res://scripts/observation_modules.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const Data = preload("res://scripts/expansion_data.gd")
const State = preload("res://scripts/expansion_state.gd")
const Director = preload("res://scripts/anomaly_director.gd")
var game: Node
var modules = Modules.new()
var state = State.new()
var observations := 0
var retired_m31: Dictionary = {}
var director: Node
var _last_available := false
var samples: int:
	get: return state.samples
var record_complete: bool:
	get: return "ext_record_complete" in state.research_ids

func setup(controller: Node) -> void:
	game = controller
	game.progression.extension_state = state
	director = Director.new()
	add_child(director)
	director.setup(self)
	game.progression.state_changed.connect(_on_progression_changed)
	game.settings.language_changed.connect(func(_locale): changed.emit())
	_last_available = available()

func _on_progression_changed() -> void:
	var unlocked := available()
	_sync_protocol()
	if unlocked != _last_available:
		_last_available = unlocked
		changed.emit()

func _sync_protocol() -> void:
	if modules_unlocked() and "ext_protocol" not in state.research_ids:
		state.research_ids.append("ext_protocol")
	if director != null:
		game.spawner.extension_reserved_slots = 3 if not director.available_kinds().is_empty() else 0

func available() -> bool:
	return game != null and game.progression.galaxy_unlocked()

func modules_unlocked() -> bool:
	return available()

func research_owned(id: String) -> bool:
	return id in state.research_ids

func research_ready(id: String) -> bool:
	if not modules_unlocked():
		return false
	return state.research_ready(id)

func research_cost(id: String) -> float:
	return float(Data.RESEARCH.get(id, {}).get("cost", 0.0))

func can_purchase(id: String) -> bool:
	return research_ready(id) and game.progression.observation_data >= research_cost(id)

func _chart_action_allowed() -> bool:
	return modules_unlocked() and game.upgrade_tree.is_open() and not game.module_popup.is_open() and not game.hud.is_settings_open()

func purchase(id: String) -> bool:
	if not _chart_action_allowed() or not can_purchase(id):
		return false
	var before := get_save_data()
	var balance: float = game.progression.observation_data
	game.progression.observation_data -= research_cost(id)
	state.research_ids.append(id)
	modules.unlocked_slots = maxi(modules.unlocked_slots, int(state.effect("slot_capacity", 2.0)))
	_sync_protocol()
	if not _commit_transaction(before, balance):
		return false
	game.sound.play_upgrade()
	game.progression.state_changed.emit()
	changed.emit()
	return true

func equip(id: String, slot: int = -1) -> bool:
	if not modules_unlocked() or not game.module_popup.is_open() or game.module_popup.is_draw_open():
		return false
	var before := get_save_data()
	if not modules.equip(id, slot):
		return false
	game.observer.reset()
	if not _commit_transaction(before, game.progression.observation_data):
		return false
	game.sound.play_slot_confirm()
	changed.emit()
	return true

func _commit_transaction(before: Dictionary, balance: float) -> bool:
	# Slot-less diagnostic games are deliberately in-memory. Real active slots
	# must persist the debit and result together before revealing a candidate.
	if game.active_save_slot in [1, 2, 3] and not game._autosave_active_slot():
		game.progression.observation_data = balance
		load_save_data(before)
		director.resume_targets()
		game.progression.state_changed.emit()
		changed.emit()
		return false
	return true

func draw_module() -> String:
	if not modules_unlocked() or not game.module_popup.is_draw_open() or game.hud.is_settings_open():
		return ""
	var before := get_save_data()
	var id: String = state.draw_module()
	if id.is_empty():
		return ""
	if not modules.grant_copy(id):
		state.load_save_data(before.extension)
		return ""
	if not _commit_transaction(before, game.progression.observation_data):
		return ""
	game.sound.play_slot_confirm()
	changed.emit()
	return id

func paid_research_count() -> int:
	var count := 0
	for id in state.research_ids:
		if Data.RESEARCH[id].cost > 0.0:
			count += 1
	return count

func research_name(id: String) -> String:
	if Data.RESEARCH.has(id):
		return tr("EXT_RESEARCH_%s_NAME" % id.trim_prefix("ext_").to_upper())
	if Modules.SLOT_RESEARCH.has(id):
		return tr("RING_RESEARCH_%d" % Modules.SLOT_RESEARCH[id].capacity)
	return tr("MODULE_%s_NAME" % id.to_upper())

func research_description(id: String) -> String:
	if Data.RESEARCH.has(id):
		return tr("EXT_RESEARCH_%s_DESC" % id.trim_prefix("ext_").to_upper())
	if Modules.SLOT_RESEARCH.has(id):
		var capacity: int = Modules.SLOT_RESEARCH[id].capacity
		return tr("RING_RESEARCH_DESC") % [capacity - 1, capacity]
	return tr("MODULE_%s_DESC" % id.to_upper())

func prerequisite_text(id: String) -> String:
	var required: Array = Data.RESEARCH.get(id, {}).get("requires", [])
	var names: Array[String] = []
	for prerequisite in required:
		names.append(research_name(prerequisite))
	return tr("RING_REQUIRES") % " + ".join(names) if not names.is_empty() else tr("DEEP_FIRST_HINT")

func current_objective() -> String:
	if not modules_unlocked():
		return tr("DEEP_FIRST_HINT") if available() else ""
	return ""

func award_anomaly_data(anomaly: Node) -> void:
	modules.record_completion(anomaly)
	var manual: bool = anomaly.get_manual_contribution() >= 0.25 or anomaly.discovered
	var base: float = anomaly.base_value
	var intrinsic := 1.0 if manual else 0.68
	var amount: float = base * intrinsic * game.progression.get_observation_value_multiplier("common", game.meteor_layer.get_child_count() + director.object_count())
	var reward: float = game.progression.add_observation(round(amount), manual, intrinsic)
	game.effects.spawn_success(anomaly.global_position, reward, anomaly.get_visual_color(), intrinsic, 0.4, "GOOD" if manual else "AUTOMATIC", game.hud.get_data_anchor(), 0.0, false)
	if manual:
		game.sound.play_success(intrinsic, game.progression.manual_combo_count, 0.35)
	else:
		game.sound.play_automatic_tick()

func sample_feedback(amount: int) -> void:
	game.hud.show_banner(tr("EXT_SAMPLES_GAINED") % amount, UITheme.ACCENT_TEXT, 2.2)
	game.sound.play_slot_confirm()


func end_round() -> void:
	director.end_round()

func resume_targets() -> void:
	director.resume_targets()

func reset() -> void:
	observations = 0
	retired_m31.clear()
	modules.load_save_data({})
	state = State.new()
	game.progression.extension_state = state
	if director != null:
		director.reset()
	_sync_protocol()
	changed.emit()

func get_save_data() -> Dictionary:
	return {"version": 4, "observations": observations, "retired_m31": retired_m31.duplicate(true), "modules": modules.get_save_data(), "extension": state.get_save_data(), "anomalies": director.get_save_data()}

static func supports_save(data: Dictionary) -> bool:
	var version = data.get("version", 1)
	if not (version is int or version is float) or version not in [1, 2, 3, 4]:
		return false
	var extension = data.get("extension", {})
	if extension is Dictionary and extension.has("catalogue_version"):
		var catalogue = extension.catalogue_version
		if not (catalogue is int or catalogue is float) or not is_finite(float(catalogue)) or floorf(float(catalogue)) != float(catalogue) or catalogue < 0 or catalogue > Data.CATALOGUE_VERSION:
			return false
	return true

func load_save_data(data: Dictionary, legacy: Dictionary = {}) -> bool:
	if not supports_save(data):
		return false
	reset()
	var owned = data.get("modules", legacy.get("modules", {}))
	modules.load_save_data(owned if owned is Dictionary else {})
	observations = Data.integer(data.get("observations", 0), 1000000000)
	var retired = data.get("retired_m31", {})
	retired_m31 = retired.duplicate(true) if retired is Dictionary else {}
	for key in ["progress", "cooldown", "value_integral", "cooldown_integral"]:
		if data.has(key): retired_m31[key] = Data.number(data[key], 1000000000.0)
	if data.get("version", 1) >= 2:
		var extension = data.get("extension", {})
		state.load_save_data(extension if extension is Dictionary else {}, data.get("version", 1) == 2)
	# Before catalogue 3, these research purchases were represented by module
	# ownership. Convert once; a newly drawn copy must never buy research.
	var saved_extension = data.get("extension", {})
	var old_catalogue := not saved_extension is Dictionary or Data.integer(saved_extension.get("catalogue_version", 0), 1000) < 3
	if old_catalogue:
		for id in Data.LEGACY_PURCHASE_IDS:
			if Data.RESEARCH.has(id) and id in modules.purchased and id not in state.research_ids:
				state.research_ids.append(id)
		for id in Data.RETIRED_RESEARCH_IDS:
			if id in modules.purchased and id not in state.retired_research_ids:
				state.retired_research_ids.append(id)
		for id in Data.LEGACY_GRANTS:
			if id in state.research_ids or id in state.retired_research_ids: modules.grant(Data.LEGACY_GRANTS[id])
	for capacity in range(3, modules.unlocked_slots + 1):
		var id := "slot_%d" % capacity
		if id not in state.research_ids: state.research_ids.append(id)
	modules.unlocked_slots = maxi(modules.unlocked_slots, int(state.effect("slot_capacity", 2.0)))
	_sync_protocol()
	var anomalies = data.get("anomalies", {})
	if not anomalies is Dictionary: anomalies = {}
	if data.get("version", 1) == 2: anomalies = Director.migrate_v2(anomalies)
	director.load_save_data(anomalies)
	changed.emit()
	return true
