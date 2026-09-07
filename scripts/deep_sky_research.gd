extends Node2D

signal changed
const Modules = preload("res://scripts/observation_modules.gd")
const Target = preload("res://scripts/andromeda_target.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const Data = preload("res://scripts/expansion_data.gd")
const State = preload("res://scripts/expansion_state.gd")
const Director = preload("res://scripts/anomaly_director.gd")
var game: Node
var modules = Modules.new()
var state = State.new()
var observations := 0
var target: Node2D
var director: Node
var _last_available := false
var samples: int:
	get: return state.samples
var record_complete: bool:
	get: return "ext_record_complete" in state.research_ids

func setup(controller: Node) -> void:
	game = controller
	target = Target.new()
	target.research = self
	add_child(target)
	director = Director.new()
	add_child(director)
	director.setup(self)
	game.progression.state_changed.connect(_on_progression_changed)
	game.settings.language_changed.connect(func(_locale): target.queue_redraw(); changed.emit())
	_last_available = available()
	target.visible = _last_available

func _process(delta: float) -> void:
	if game != null and game.observation_phase_active:
		modules.advance_time(delta / maxf(Engine.time_scale, 0.001))

func _on_progression_changed() -> void:
	var unlocked := available()
	target.visible = unlocked
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
	return available() and (observations > 0 or not modules.purchased.is_empty())

func research_owned(id: String) -> bool:
	return id in state.research_ids if Data.RESEARCH.has(id) else modules.research_owned(id)

func research_ready(id: String) -> bool:
	if not modules_unlocked():
		return false
	if Data.RESEARCH.has(id):
		return state.research_ready(id)
	if id not in Modules.RESEARCH_IDS or not modules.research_ready(id):
		return false
	if id == "slot_3":
		return research_owned("ext_trace_study")
	if id == "slot_4":
		return research_owned("ext_sweep_study") and research_owned("ext_link_study")
	if id == "slot_5":
		return research_owned("ext_combined_watch")
	return true

func research_cost(id: String) -> float:
	return float(Data.RESEARCH[id].cost) if Data.RESEARCH.has(id) else modules.research_cost(id)

func can_purchase(id: String) -> bool:
	return research_ready(id) and game.progression.observation_data >= research_cost(id)

func _chart_action_allowed() -> bool:
	return modules_unlocked() and game.upgrade_tree.is_open() and not game.module_popup.is_open() and not game.hud.is_settings_open()

func purchase(id: String) -> bool:
	if not _chart_action_allowed() or not can_purchase(id):
		return false
	var before := get_save_data()
	var balance: float = game.progression.observation_data
	if Data.RESEARCH.has(id):
		game.progression.observation_data -= research_cost(id)
		state.research_ids.append(id)
		var definition: Dictionary = Data.RESEARCH[id]
		if definition.has("grant"):
			modules.grant(definition.grant)

	else:
		if not modules.purchase(id, game.progression):
			return false
	_sync_protocol()
	if not _commit_transaction(before, balance):
		return false
	game.sound.play_upgrade()
	game.progression.state_changed.emit()
	changed.emit()
	return true

func equip(id: String, slot: int = -1) -> bool:
	if not modules_unlocked() or not game.module_popup.is_open():
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
	if not modules_unlocked() or not game.module_popup.is_open() or game.hud.is_settings_open():
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
	for id in Modules.RESEARCH_IDS:
		if modules.research_owned(id):
			count += 1
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
	var required: Array = []
	if id == "slot_3": required = ["ext_trace_study"]
	elif id == "slot_4": required = ["slot_3", "ext_sweep_study", "ext_link_study"]
	elif id == "slot_5": required = ["slot_4", "ext_combined_watch"]
	elif id == "revisit": required = ["slot_3"]
	elif Data.RESEARCH.has(id): required = Data.RESEARCH[id].requires
	else: required = Modules.DEFINITIONS.get(id, {}).get("requires", [])
	var names: Array[String] = []
	for prerequisite in required:
		names.append(research_name(prerequisite))
	return tr("RING_REQUIRES") % " + ".join(names) if not names.is_empty() else tr("DEEP_FIRST_HINT")

func current_objective() -> String:
	if not modules_unlocked():
		return tr("DEEP_FIRST_HINT") if available() else ""
	return tr("MODX_DRAW_HINT")

func record_observation(value_multiplier: float = -1.0) -> void:
	if value_multiplier < 0.0:
		value_multiplier = float(modules.effect("m31_value"))
	observations += 1
	game.observer.release_target(target)
	var reward: float = 8000.0 * game.progression.get_observation_value_multiplier("common", 1) * value_multiplier
	reward = game.progression.add_galactic_observation(reward)
	game.effects.spawn_success(target.global_position, reward, Color("D4DAE5"), 1.0, 1.0, "GOOD", game.hud.get_data_anchor(), 0.4, true)
	game.sound.play_success(1.0, 1, 0.4)
	_sync_protocol()
	if observations == 1:
		game.hud.show_banner(tr("DEEP_FIRST_RECORD"), UITheme.ACCENT_TEXT, 4.0)
	target.queue_redraw()
	changed.emit()
	game._autosave_active_slot()

func record_ordinary_observation(meteor: Node) -> void:
	modules.notify_completed(meteor)

func award_anomaly_data(anomaly: Node) -> void:
	var manual: bool = anomaly.get_manual_contribution() >= 0.25 or anomaly.discovered
	var base: float = anomaly.archive_value if anomaly.origin_kind == "archive" else anomaly.base_value
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

func archive_meteor(meteor: Node) -> void:
	director.archive_meteor(meteor)

func end_round() -> void:
	director.end_round()
	modules.set_m31_manual_active(false)

func resume_targets() -> void:
	director.resume_targets()

func reset() -> void:
	observations = 0
	modules.load_save_data({})
	state = State.new()
	if director != null:
		director.reset()
	target.progress = 0.0
	target.cooldown = 0.0
	target.value_integral = 0.0
	target.cooldown_integral = 0.0
	target.integrated_progress = 0.0
	target.visible = available()
	target.queue_redraw()
	_sync_protocol()
	changed.emit()

func get_save_data() -> Dictionary:
	return {"version": 3, "observations": observations, "modules": modules.get_save_data(), "progress": target.progress, "cooldown": target.cooldown, "value_integral": target.value_integral, "cooldown_integral": target.cooldown_integral, "extension": state.get_save_data(), "anomalies": director.get_save_data()}

static func supports_save(data: Dictionary) -> bool:
	var version = data.get("version", 1)
	return (version is int or version is float) and version in [1, 2, 3]

func load_save_data(data: Dictionary, legacy: Dictionary = {}) -> bool:
	if not supports_save(data):
		return false
	reset()
	var owned = data.get("modules", legacy.get("modules", {}))
	modules.load_save_data(owned if owned is Dictionary else {})
	observations = Data.integer(data.get("observations", 0), 1000000000)
	target.progress = Data.number(data.get("progress", 0), 0.999999)
	target.integrated_progress = target.progress
	target.cooldown = Data.number(data.get("cooldown", 0), 15.75)
	if data.get("version", 1) >= 2:
		var extension = data.get("extension", {})
		state.load_save_data(extension if extension is Dictionary else {}, data.get("version", 1) == 2)
	for id in state.research_ids:
		if Data.RESEARCH[id].has("grant"):
			modules.grant(Data.RESEARCH[id].grant)
	var value: float = modules.effect("m31_value")
	var delay: float = modules.effect("m31_cooldown")
	target.value_integral = Data.number(data.get("value_integral", target.progress * value), target.progress * 1.5)
	target.cooldown_integral = Data.number(data.get("cooldown_integral", target.progress * delay), target.progress * 2.25)
	_sync_protocol()
	var anomalies = data.get("anomalies", {})
	if not anomalies is Dictionary: anomalies = {}
	if data.get("version", 1) == 2: anomalies = Director.migrate_v2(anomalies)
	director.load_save_data(anomalies)
	target.queue_redraw()
	changed.emit()
	return true
