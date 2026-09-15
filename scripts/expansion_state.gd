extends RefCounted

const Data = preload("res://scripts/expansion_data.gd")
var retired_research_ids: Array[String] = []
var research_ids: Array[String] = []
var samples := 0
var samples_earned := 0
var samples_spent := 0
var acquisition_seed := 1
var draw_serial := 0
var last_draw := ""
# Per-save onboarding: unclaimed, funded first draw, drawn / awaiting equip, done.
enum Intro { UNCLAIMED, DRAW, EQUIP, COMPLETE }
var module_intro_stage := Intro.UNCLAIMED
var module_intro_id := ""
const ADDITIVE_EFFECTS := ["tracking_grace", "survey_count", "combo_window", "combo_speed", "combo_radius", "combo_cap", "echo_probability", "echo_count", "forecast_lead", "dish_count", "gravity_slow_seconds", "white_hole_ejecta_count"]
var _cached_research_ids: Array[String] = []
var _cached_effects: Dictionary = {}

func effect(key: String, fallback: float = 1.0) -> float:
	if _cached_research_ids != research_ids:
		_cached_research_ids = research_ids.duplicate()
		_cached_effects.clear()
		for id in research_ids:
			for effect_key in Data.RESEARCH[id].effects:
				var value := float(Data.RESEARCH[id].effects[effect_key])
				if effect_key == "slot_capacity":
					_cached_effects[effect_key] = maxf(float(_cached_effects.get(effect_key, 2.0)), value)
				elif effect_key in ADDITIVE_EFFECTS:
					_cached_effects[effect_key] = float(_cached_effects.get(effect_key, 0.0)) + value
				else:
					_cached_effects[effect_key] = float(_cached_effects.get(effect_key, 1.0)) * value
	return float(_cached_effects.get(key, fallback))

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
	if module_intro_stage == Intro.DRAW:
		module_intro_stage = Intro.EQUIP
		module_intro_id = id
	return id

func get_save_data() -> Dictionary:
	return {"retired_research_ids": retired_research_ids.duplicate(), "research_ids": research_ids.duplicate(), "samples": samples, "samples_earned": samples_earned, "samples_spent": samples_spent, "acquisition_seed": acquisition_seed, "draw_serial": draw_serial, "last_draw": last_draw, "module_intro_stage": module_intro_stage, "module_intro_id": module_intro_id, "catalogue_version": Data.CATALOGUE_VERSION}

func load_save_data(data: Dictionary, legacy: bool = false) -> void:
	research_ids.clear()
	retired_research_ids.clear()
	var retired = data.get("retired_research_ids", [])
	if retired is Array:
		for id in retired:
			if id is String and id in Data.RETIRED_RESEARCH_IDS and id not in retired_research_ids:
				retired_research_ids.append(id)
	var saved_ids = data.get("research_ids", [])
	if saved_ids is Array:
		for id in saved_ids:
			if id is String and Data.RESEARCH.has(id) and id not in research_ids:
				research_ids.append(id)
			elif id is String and id in Data.RETIRED_RESEARCH_IDS and id not in retired_research_ids:
				retired_research_ids.append(id)
	samples_earned = Data.integer(data.get("samples_earned", 0), 1000000000)
	samples_spent = Data.integer(data.get("samples_spent", 0), samples_earned)
	samples = mini(Data.integer(data.get("samples", 0), 1000000000), samples_earned - samples_spent)
	# A paid, unchosen v2 offer becomes currency exactly once on migration.
	# Refund the payment independently of the current catalogue; never grant its item.
	var offer = data.get("pending_offer", [])
	if legacy and offer is Array and samples_spent >= 8:
		for id in offer:
			if id is String and not id.is_empty():
				samples_spent -= 8
				samples += 8
				break
	acquisition_seed = maxi(1, Data.integer(data.get("acquisition_seed", acquisition_seed), 2147483646, acquisition_seed))
	draw_serial = Data.integer(data.get("draw_serial", data.get("analysis_serial", 0)), 100000000)
	last_draw = data.get("last_draw", "") if data.get("last_draw", "") is String and data.get("last_draw", "") in Data.SAMPLE_MODULES else ""
	module_intro_stage = Data.integer(data.get("module_intro_stage", Intro.UNCLAIMED), Intro.COMPLETE)
	module_intro_id = data.get("module_intro_id", "") if data.get("module_intro_id", "") is String and data.get("module_intro_id", "") in Data.SAMPLE_MODULES else ""
