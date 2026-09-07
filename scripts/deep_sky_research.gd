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
var pending_offer: Array[String]:
	get: return state.pending_offer
var record_complete: bool:
	get: return state.record_complete

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
		return state.completed_count(1) >= 1
	if id == "slot_4":
		return state.completed_count(1) >= 2
	if id == "slot_5":
		return state.completed_count(2) >= 2
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
		if id == "ext_record_complete":
			state.record_complete = true
		for plan_id in Data.PLAN_ORDER:
			if Data.PLANS[plan_id].research == id and state.selected_plan.is_empty():
				state.select_plan(plan_id)
				director.plan_selected()
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

func sample_pool() -> Array[String]:
	return state.sample_pool(modules.purchased)

func collection_complete() -> bool:
	return state.collection_complete(modules.purchased)

func begin_analysis() -> bool:
	if not _chart_action_allowed():
		return false
	var before := get_save_data()
	if not state.start_analysis(modules.purchased):
		return false
	if not _commit_transaction(before, game.progression.observation_data):
		return false
	game.sound.play_slot_confirm()
	changed.emit()
	return true

func choose_analysis(id: String) -> bool:
	if not _chart_action_allowed() or id not in state.pending_offer or id in modules.purchased:
		return false
	var before := get_save_data()
	if not modules.grant(id):
		return false
	state.pending_offer.clear()
	if not _commit_transaction(before, game.progression.observation_data):
		return false
	game.sound.play_slot_confirm()
	changed.emit()
	return true

func direct_analysis(id: String) -> bool:
	if not _chart_action_allowed() or not state.pending_offer.is_empty() or id not in sample_pool() or state.samples < Data.DIRECT_COST:
		return false
	var before := get_save_data()
	state.samples -= Data.DIRECT_COST
	state.samples_spent += Data.DIRECT_COST
	modules.grant(id)
	if not _commit_transaction(before, game.progression.observation_data):
		return false
	game.sound.play_slot_confirm()
	changed.emit()
	return true

func plan_available(id: String) -> bool:
	return modules_unlocked() and state.plan_available(id)

func select_plan(id: String) -> bool:
	if not _chart_action_allowed() or not plan_available(id):
		return false
	var before := get_save_data()
	state.select_plan(id)
	director.plan_selected()
	if not _commit_transaction(before, game.progression.observation_data):
		return false
	changed.emit()
	return true

func active_plan() -> String:
	return state.selected_plan

func plan_progress(id: String) -> Vector2i:
	if not Data.PLANS.has(id):
		return Vector2i.ZERO
	return Vector2i(state.field_index(id), Data.PLANS[id].fields.size())

func completed_plans() -> int:
	return state.completed_count()

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

func plan_name(id: String) -> String:
	return tr("EXT_PLAN_%s_NAME" % id.trim_prefix("plan_").to_upper())

func plan_detail(id: String) -> String:
	if not Data.PLANS.has(id):
		return ""
	var progress := plan_progress(id)
	var description := tr("EXT_PLAN_%s_DESC" % id.trim_prefix("plan_").to_upper())
	if progress.x == progress.y:
		return description + "\n\n" + tr("EXT_PLAN_DONE")
	var field: Dictionary = Data.PLANS[id].fields[progress.x]
	var hints: Array[String] = [tr("EXT_FIELD_LOOP")]
	var kinds: Array[String] = []
	for event in field.events:
		if event.kind not in kinds: kinds.append(event.kind)
	for kind in kinds:
		if kind == "pair" and field.get("mode", "manual") != "manual":
			hints.append(tr("EXT_TASK_%s" % String(field.mode).to_upper()))
		else:
			hints.append(tr("EXT_HELP_%s" % kind.to_upper()))
	if field.get("ordinary", false): hints.append(tr("EXT_HELP_ORDINARY"))
	return description + "\n\n" + tr("EXT_FIELD_PROGRESS") % [progress.x + 1, progress.y, tr("EXT_FIELD_%s" % String(field.id).to_upper())] + "\n" + "\n".join(hints)

func prerequisite_text(id: String) -> String:
	if id == "slot_3": return tr("EXT_REQUIRE_BASIC") % 1
	if id == "slot_4": return tr("EXT_REQUIRE_BASIC") % 2
	if id == "slot_5": return tr("EXT_REQUIRE_ADVANCED") % 2
	if Data.RESEARCH.has(id):
		var definition: Dictionary = Data.RESEARCH[id]
		if definition.has("plan"):
			return tr("EXT_REQUIRE_PLAN") % plan_name(definition.plan)
		if definition.has("tier"):
			return tr("EXT_REQUIRE_BASIC" if definition.tier == 1 else "EXT_REQUIRE_ADVANCED") % definition.count
		return tr("DEEP_FIRST_HINT") if not modules_unlocked() else tr("EXT_REQUIRE_PROTOCOL")
	var definition: Dictionary = Modules.DEFINITIONS.get(id, {})
	if id == "revisit": return tr("RING_REQUIRES") % tr("RING_RESEARCH_3")
	var names: Array[String] = []
	for required in definition.get("requires", []):
		names.append(research_name(required))
	return tr("RING_REQUIRES") % " + ".join(names)

func current_objective() -> String:
	if not modules_unlocked():
		return tr("DEEP_FIRST_HINT") if available() else ""
	var field: Dictionary = state.active_field()
	if field.is_empty():
		return tr("EXT_RECORD_DONE" if state.record_complete else "EXT_SELECT_PLAN")
	var prefix := plan_name(state.selected_plan) + " · "
	if not field.prepared:
		return prefix + tr("EXT_NEED_EXPOSURE")
	if state.field_ready():
		return tr("EXT_READY_SYNTHESIS")
	var definition: Dictionary = state.field_definition()
	var mode: String = definition.get("mode", "manual")
	var events_done := true
	for event in definition.events:
		if not field.evidence.get(event.slot, false):
			events_done = false
			if event.kind == "pair" and mode != "manual":
				return prefix + tr("EXT_TASK_%s" % mode.to_upper())
			return prefix + tr("EXT_NEXT_%s" % String(event.kind).to_upper())
	if definition.get("parallel", false) and field.parallel_progress < 0.25:
		return prefix + tr("EXT_TASK_PARALLEL")
	if events_done and definition.get("ordinary", false) and not field.evidence.get("ordinary", false):
		return prefix + tr("EXT_TASK_ORDINARY")
	return prefix + tr("EXT_FIELD_%s" % String(definition.id).to_upper())

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
	var completion: Dictionary = state.record_m31()
	if not completion.is_empty():
		if completion.plan_complete and completion.plan not in state.rewarded_plans:
			state.rewarded_plans.append(completion.plan)
			if Data.PLANS[completion.plan].tier == 1:
				var awarded: int = state.award_samples(6, modules.purchased)
				if awarded > 0:
					sample_feedback(awarded)
		game.hud.show_banner(tr("EXT_FIELD_COMPLETED") % plan_name(completion.plan), UITheme.ACCENT_TEXT, 3.0)
	elif observations == 1:
		game.hud.show_banner(tr("DEEP_FIRST_RECORD"), UITheme.ACCENT_TEXT, 4.0)
	target.queue_redraw()
	changed.emit()
	game._autosave_active_slot()

func note_m31_manual_progress(amount: float) -> void:
	var field: Dictionary = state.active_field()
	if field.is_empty() or not field.prepared or not state.field_definition().get("parallel", false) or not director.pair_automatic_active():
		return
	var before: float = field.parallel_progress
	field.parallel_progress = minf(0.25, before + maxf(0.0, amount))
	if before < 0.25 and field.parallel_progress >= 0.25:
		changed.emit()

func record_ordinary_observation(meteor: Node) -> void:
	modules.notify_completed(meteor)
	var definition: Dictionary = state.field_definition()
	if not definition.get("ordinary", false) or meteor.type_id not in ["common", "fast"] or not meteor.is_natural_observation() or meteor.get_manual_contribution() < 0.25:
		return
	if state.record_evidence(state.selected_plan, state.field_index(), "ordinary"):
		changed.emit()

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

func record_sweep_segment(from: Vector2, to: Vector2) -> void:
	director.record_sweep_segment(from, to)

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
	return {"version": 2, "observations": observations, "modules": modules.get_save_data(), "progress": target.progress, "cooldown": target.cooldown, "value_integral": target.value_integral, "cooldown_integral": target.cooldown_integral, "extension": state.get_save_data(), "anomalies": director.get_save_data()}

static func supports_save(data: Dictionary) -> bool:
	var version = data.get("version", 1)
	return (version is int or version is float) and version in [1, 2]

func load_save_data(data: Dictionary, legacy: Dictionary = {}) -> bool:
	if not supports_save(data):
		return false
	reset()
	var owned = data.get("modules", legacy.get("modules", {}))
	modules.load_save_data(owned if owned is Dictionary else {})
	observations = Data.integer(data.get("observations", 0), 1000000000)
	target.progress = Data.number(data.get("progress", 0), 0.999999)
	target.integrated_progress = target.progress
	target.cooldown = Data.number(data.get("cooldown", 0), 8.75)
	if data.get("version", 1) == 2:
		var extension = data.get("extension", {})
		state.load_save_data(extension if extension is Dictionary else {}, modules.purchased)
	else:
		state.exposures = 1 if observations > 0 else 0
	for id in state.research_ids:
		if Data.RESEARCH[id].has("grant"):
			modules.grant(Data.RESEARCH[id].grant)
	var value: float = modules.effect("m31_value")
	var delay: float = modules.effect("m31_cooldown")
	target.value_integral = Data.number(data.get("value_integral", target.progress * value), target.progress * 1.5)
	target.cooldown_integral = Data.number(data.get("cooldown_integral", target.progress * delay), target.progress * 1.25)
	_sync_protocol()
	var anomalies = data.get("anomalies", {})
	director.load_save_data(anomalies if anomalies is Dictionary else {})
	target.queue_redraw()
	changed.emit()
	return true
