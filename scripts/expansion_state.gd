extends RefCounted

const Data = preload("res://scripts/expansion_data.gd")
var research_ids: Array[String] = []
var samples := 0
var samples_earned := 0
var samples_spent := 0
var acquisition_seed := 1
var draw_serial := 0
var last_draw := ""

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	acquisition_seed = rng.randi_range(1, 2147483646)

func research_ready(id: String) -> bool:
	if not Data.RESEARCH.has(id) or id in research_ids or id == "ext_protocol":
		return false
	for prerequisite in Data.RESEARCH[id].requires:
		if prerequisite not in research_ids:
			return false
	return true

func draw_cost() -> int:
	return 6 if "ext_record_complete" in research_ids else Data.DRAW_COST

func sample_reward() -> int:
	return 3 if "ext_synthesis" in research_ids else 2

func award_samples(amount: int) -> int:
	var awarded := mini(maxi(0, amount), 1000000000 - samples_earned)
	samples += awarded
	samples_earned += awarded
	return awarded

func draw_module() -> String:
	if "ext_protocol" not in research_ids or samples < draw_cost():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = acquisition_seed + draw_serial * 7919
	var id: String = Data.SAMPLE_MODULES[rng.randi_range(0, Data.SAMPLE_MODULES.size() - 1)]
	samples -= draw_cost()
	samples_spent += draw_cost()
	draw_serial += 1
	last_draw = id
	return id

func get_save_data() -> Dictionary:
	return {"research_ids": research_ids.duplicate(), "samples": samples, "samples_earned": samples_earned, "samples_spent": samples_spent, "acquisition_seed": acquisition_seed, "draw_serial": draw_serial, "last_draw": last_draw, "catalogue_version": Data.CATALOGUE_VERSION}

func load_save_data(data: Dictionary, legacy: bool = false) -> void:
	research_ids.clear()
	var saved_ids = data.get("research_ids", [])
	if saved_ids is Array:
		for id in saved_ids:
			if id is String and Data.RESEARCH.has(id) and id not in research_ids:
				research_ids.append(id)
	samples_earned = Data.integer(data.get("samples_earned", 0), 1000000000)
	samples_spent = Data.integer(data.get("samples_spent", 0), samples_earned)
	samples = mini(Data.integer(data.get("samples", 0), 1000000000), samples_earned - samples_spent)
	# A paid, unchosen v2 offer becomes currency exactly once on migration.
	var offer = data.get("pending_offer", [])
	if legacy and offer is Array and samples_spent >= 8:
		for id in offer:
			if id is String and id in Data.SAMPLE_MODULES:
				samples_spent -= 8
				samples += 8
				break
	acquisition_seed = maxi(1, Data.integer(data.get("acquisition_seed", acquisition_seed), 2147483646, acquisition_seed))
	draw_serial = Data.integer(data.get("draw_serial", data.get("analysis_serial", 0)), 100000000)
	last_draw = data.get("last_draw", "") if data.get("last_draw", "") is String and data.get("last_draw", "") in Data.SAMPLE_MODULES else ""
