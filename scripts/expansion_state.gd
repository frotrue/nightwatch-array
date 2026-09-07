extends RefCounted

const Data = preload("res://scripts/expansion_data.gd")
var research_ids: Array[String] = []
var selected_plan := ""
var records: Dictionary = {}
var exposures := 0
var samples := 0
var samples_earned := 0
var samples_spent := 0
var pending_offer: Array[String] = []
var acquisition_seed := 1
var analysis_serial := 0
var rewarded_plans: Array[String] = []
var guided_plans: Array[String] = []
var record_complete := false

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	acquisition_seed = rng.randi_range(1, 2147483646)
	for id in Data.PLAN_ORDER:
		var fields: Array = []
		for _definition in Data.PLANS[id].fields:
			fields.append({"prepared": false, "complete": false, "evidence": {}, "parallel_progress": 0.0})
		records[id] = fields

func plan_available(id: String) -> bool:
	return Data.PLANS.has(id) and Data.PLANS[id].research in research_ids

func field_index(id: String = "") -> int:
	if id.is_empty():
		id = selected_plan
	var fields: Array = records.get(id, [])
	for index in range(fields.size()):
		if not fields[index].complete:
			return index
	return fields.size()

func plan_complete(id: String) -> bool:
	return Data.PLANS.has(id) and field_index(id) == Data.PLANS[id].fields.size()

func completed_count(tier: int = 0) -> int:
	var count := 0
	for id in Data.PLAN_ORDER:
		if (tier == 0 or Data.PLANS[id].tier == tier) and plan_complete(id):
			count += 1
	return count

func active_field() -> Dictionary:
	if not Data.PLANS.has(selected_plan) or plan_complete(selected_plan):
		return {}
	return records[selected_plan][field_index()]

func field_definition() -> Dictionary:
	if active_field().is_empty():
		return {}
	return Data.PLANS[selected_plan].fields[field_index()]

func select_plan(id: String) -> bool:
	if not plan_available(id):
		return false
	selected_plan = id
	prepare_from_bank()
	return true

func exposure_capacity() -> int:
	return 2 if "ext_synthesis" in research_ids else 1

func prepare_from_bank() -> void:
	var field := active_field()
	if not field.is_empty() and not field.prepared and exposures > 0:
		exposures -= 1
		field.prepared = true

func field_ready() -> bool:
	var field := active_field()
	var definition := field_definition()
	if field.is_empty() or not field.prepared:
		return false
	for event in definition.events:
		if not field.evidence.get(event.slot, false):
			return false
	if definition.get("ordinary", false) and not field.evidence.get("ordinary", false):
		return false
	if definition.get("parallel", false) and field.parallel_progress < 0.25:
		return false
	return true

func record_m31() -> Dictionary:
	if field_ready():
		var plan := selected_plan
		var index := field_index()
		active_field().complete = true
		var finished := plan_complete(plan)
		prepare_from_bank()
		return {"plan": plan, "field": index, "plan_complete": finished}
	exposures = mini(exposure_capacity(), exposures + 1)
	prepare_from_bank()
	return {}

func record_evidence(plan: String, index: int, slot: String) -> bool:
	if not records.has(plan) or index < 0 or index >= records[plan].size():
		return false
	var field: Dictionary = records[plan][index]
	if not field.prepared or field.complete or field.evidence.get(slot, false):
		return false
	field.evidence[slot] = true
	return true

func research_ready(id: String) -> bool:
	if not Data.RESEARCH.has(id) or id in research_ids:
		return false
	var definition: Dictionary = Data.RESEARCH[id]
	for prerequisite in definition.requires:
		if prerequisite not in research_ids:
			return false
	if definition.has("plan") and not plan_complete(definition.plan):
		return false
	if definition.has("tier") and completed_count(definition.tier) < definition.count:
		return false
	return id != "ext_protocol"

func sample_pool(owned: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for category in Data.POOLS:
		if "ext_%s_study" % category not in research_ids:
			continue
		for id in Data.POOLS[category]:
			if id not in owned:
				result.append(id)
	return result

func collection_complete(owned: Array[String]) -> bool:
	for id in Data.SAMPLE_MODULES:
		if id not in owned:
			return false
	return true

func award_samples(amount: int, owned: Array[String]) -> int:
	if amount <= 0 or collection_complete(owned):
		return 0
	var awarded := mini(amount, 1000000000 - samples_earned)
	samples += awarded
	samples_earned += awarded
	return awarded

func start_analysis(owned: Array[String]) -> bool:
	var pool := sample_pool(owned)
	if not pending_offer.is_empty() or samples < Data.ANALYSIS_COST or pool.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = acquisition_seed + analysis_serial * 7919
	while pending_offer.size() < mini(3, pool.size() + pending_offer.size()):
		var index := rng.randi_range(0, pool.size() - 1)
		pending_offer.append(pool[index])
		pool.remove_at(index)
	samples -= Data.ANALYSIS_COST
	samples_spent += Data.ANALYSIS_COST
	analysis_serial += 1
	return true

func get_save_data() -> Dictionary:
	return {"research_ids": research_ids.duplicate(), "selected_plan": selected_plan, "records": records.duplicate(true), "exposures": exposures, "samples": samples, "samples_earned": samples_earned, "samples_spent": samples_spent, "pending_offer": pending_offer.duplicate(), "acquisition_seed": acquisition_seed, "analysis_serial": analysis_serial, "catalogue_version": Data.CATALOGUE_VERSION, "rewarded_plans": rewarded_plans.duplicate(), "guided_plans": guided_plans.duplicate(), "record_complete": record_complete}

func load_save_data(data: Dictionary, owned: Array[String]) -> void:
	research_ids.clear()
	var saved_ids = data.get("research_ids", [])
	if saved_ids is Array:
		for id in saved_ids:
			if id is String and Data.RESEARCH.has(id) and id not in research_ids:
				research_ids.append(id)
	var saved_records = data.get("records", {})
	for id in Data.PLAN_ORDER:
		var clean: Array = []
		var saved = saved_records.get(id, []) if saved_records is Dictionary else []
		for index in range(Data.PLANS[id].fields.size()):
			var entry = saved[index] if saved is Array and index < saved.size() and saved[index] is Dictionary else {}
			var evidence: Dictionary = {}
			var raw_evidence = entry.get("evidence", {})
			var allowed: Array[String] = ["ordinary"]
			for event in Data.PLANS[id].fields[index].events:
				allowed.append(event.slot)
			if raw_evidence is Dictionary:
				for key in allowed:
					if Data.flag(raw_evidence.get(key, false)):
						evidence[key] = true
			clean.append({"prepared": Data.flag(entry.get("prepared", false)), "complete": Data.flag(entry.get("complete", false)), "evidence": evidence, "parallel_progress": Data.number(entry.get("parallel_progress", 0), 0.25)})
		records[id] = clean
	selected_plan = data.get("selected_plan", "") if data.get("selected_plan", "") is String else ""
	if not plan_available(selected_plan):
		selected_plan = ""
	exposures = Data.integer(data.get("exposures", 0), exposure_capacity())
	samples_earned = Data.integer(data.get("samples_earned", 0), 1000000000)
	samples_spent = Data.integer(data.get("samples_spent", 0), samples_earned)
	samples = mini(Data.integer(data.get("samples", 0), 1000000000), samples_earned - samples_spent)
	acquisition_seed = maxi(1, Data.integer(data.get("acquisition_seed", acquisition_seed), 2147483646, acquisition_seed))
	analysis_serial = Data.integer(data.get("analysis_serial", 0), 100000000)
	pending_offer.clear()
	var offer = data.get("pending_offer", [])
	if offer is Array:
		for id in offer:
			if id is String and id in Data.SAMPLE_MODULES and id not in pending_offer and id not in owned and pending_offer.size() < 3:
				pending_offer.append(id)
	rewarded_plans.clear()
	guided_plans.clear()
	for pair in [["rewarded_plans", rewarded_plans], ["guided_plans", guided_plans]]:
		var values = data.get(pair[0], [])
		if values is Array:
			for id in values:
				if id is String and Data.PLANS.has(id) and id not in pair[1]:
					pair[1].append(id)
	record_complete = Data.flag(data.get("record_complete", false)) and plan_complete("plan_integrated_1")
	prepare_from_bank()
