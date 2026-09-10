extends Node

signal state_changed
signal upgrade_purchased(definition)
signal purchase_rejected(node_id, reason_key, value)

const Balance = preload("res://scripts/game_balance.gd")
# The original 52-node topology has 51 pacing upgrades. Predictive Dish Control
# and later content research remain interaction-only for density normalization.
const PACING_NODE_COUNT := 51
const BASE_MANUAL_COMBO_WINDOW := 2.6
const MAX_MANUAL_COMBO_COUNT := 12
const PERSEID_SURVEY_TARGET_THRESHOLD := 3
# Spectral capstone x maximum precision factor x Perfect grade. Legacy saves
# may contain the research economy multiplier in this stat; values above the
# intrinsic ceiling cannot be a truthful manual-observation multiplier.
const MAX_INTRINSIC_OBSERVATION_MULTIPLIER := 1.35 * 3.0 * 1.55

# Owned by DeepSkyResearch; never duplicated in the progression save.
var extension_state: RefCounted
var observation_data: float = 0.0
var success_count: int = 0
var purchased_nodes: Dictionary = {}
var purchase_order: Array[String] = []
var manual_successes: int = 0
var automatic_successes: int = 0
var total_data_earned: float = 0.0
var best_multiplier: float = 1.0
var manual_combo_count: int = 0
var manual_combo_remaining: float = 0.0
var leonid_charge: int = 0

var upgrade_level: int:
	get:
		return purchased_nodes.size()


func reset() -> void:
	observation_data = 0.0
	success_count = 0
	purchased_nodes.clear()
	purchase_order.clear()
	manual_successes = 0
	automatic_successes = 0
	total_data_earned = 0.0
	best_multiplier = 1.0
	reset_manual_combo()
	leonid_charge = 0
	state_changed.emit()


func get_save_data() -> Dictionary:
	return {
		"observation_data": observation_data,
		"success_count": success_count,
		"purchased_nodes": purchased_nodes.keys(),
		"purchase_order": purchase_order.duplicate(),
		"manual_successes": manual_successes,
		"automatic_successes": automatic_successes,
		"total_data_earned": total_data_earned,
		"best_multiplier": best_multiplier,
		"leonid_charge": leonid_charge,
	}


func load_save_data(data: Dictionary) -> void:
	observation_data = maxf(0.0, float(data.get("observation_data", 0.0)))
	success_count = maxi(0, int(data.get("success_count", 0)))
	manual_successes = maxi(0, int(data.get("manual_successes", 0)))
	automatic_successes = maxi(0, int(data.get("automatic_successes", 0)))
	total_data_earned = maxf(0.0, float(data.get("total_data_earned", observation_data)))
	best_multiplier = clampf(
		float(data.get("best_multiplier", 1.0)),
		1.0,
		MAX_INTRINSIC_OBSERVATION_MULTIPLIER
	)
	# Manual momentum belongs to the live observation rhythm. Old saves may
	# still contain `manual_streak`; deliberately ignore it instead of carrying a
	# timed interaction bonus across a load or an intermission.
	reset_manual_combo()
	leonid_charge = maxi(0, int(data.get("leonid_charge", 0)))
	purchased_nodes.clear()
	purchase_order.clear()
	var saved_nodes = data.get("purchased_nodes", [])
	if saved_nodes is Array:
		for node_variant in saved_nodes:
			var node_id := String(node_variant)
			if not Balance.upgrade_definition(node_id).is_empty():
				purchased_nodes[node_id] = true
	var saved_order = data.get("purchase_order", [])
	if saved_order is Array:
		for node_variant in saved_order:
			var node_id := String(node_variant)
			if purchased_nodes.has(node_id) and node_id not in purchase_order:
				purchase_order.append(node_id)
	for node_variant in purchased_nodes.keys():
		var node_id := String(node_variant)
		if node_id not in purchase_order:
			purchase_order.append(node_id)
	leonid_charge = mini(leonid_charge, get_leonid_trigger_count())
	state_changed.emit()


func add_observation(amount: float, was_manual: bool, intrinsic_multiplier: float) -> float:
	var final_amount := amount
	if was_manual:
		record_manual_combo_success()
		if has_upgrade("observation_streak"):
			final_amount *= 1.0 + minf(0.5, float(maxi(0, manual_combo_count - 1)) * 0.08)
	final_amount = round(final_amount)
	observation_data += final_amount
	total_data_earned += final_amount
	success_count += 1
	if was_manual:
		manual_successes += 1
		best_multiplier = maxf(best_multiplier, intrinsic_multiplier)
	else:
		automatic_successes += 1
	state_changed.emit()
	return final_amount


func add_debug_data(amount: float) -> void:
	observation_data += amount
	total_data_earned += amount
	state_changed.emit()


func get_node_state(node_id: String) -> String:
	var definition := Balance.upgrade_definition(node_id)
	if definition.is_empty():
		return "missing"
	if has_upgrade(node_id):
		return "purchased"
	if not is_node_revealed(node_id):
		return "hidden"
	for prerequisite in definition.prerequisites:
		if not has_upgrade(String(prerequisite)):
			return "locked"
	return "available"


func is_node_revealed(node_id: String) -> bool:
	var definition := Balance.upgrade_definition(node_id)
	if definition.is_empty():
		return false
	var reveal_gates: Array = definition.hidden_until
	if reveal_gates.is_empty():
		return true
	for gate in reveal_gates:
		if is_reveal_gate_met(gate):
			return true
	return false


func is_reveal_gate_met(gate) -> bool:
	if gate is Dictionary:
		var condition: Dictionary = gate
		match String(condition.get("type", "")):
			"success_count":
				return success_count >= maxi(0, int(condition.get("minimum", 0)))
			"other_constellations_complete":
				return _all_research_outside_branch_purchased(String(condition.get("excluded_branch", "")))
			_:
				return false
	return has_upgrade(String(gate))


func _all_research_outside_branch_purchased(excluded_branch: String) -> bool:
	if excluded_branch.is_empty():
		return false
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var branch := String(definition.get("branch", ""))
		if branch == excluded_branch:
			continue
		if not has_upgrade(String(definition.id)):
			return false
	return true


func can_purchase(node_id: String) -> bool:
	var definition := Balance.upgrade_definition(node_id)
	return (
		not definition.is_empty()
		and get_node_state(node_id) == "available"
		and observation_data >= float(definition.cost)
	)


func request_purchase(node_id: String) -> bool:
	var definition := Balance.upgrade_definition(node_id)
	if definition.is_empty():
		purchase_rejected.emit(node_id, "UPGRADE_ERROR_UNKNOWN", "")
		return false
	var state := get_node_state(node_id)
	if state != "available":
		purchase_rejected.emit(node_id, "UPGRADE_ERROR_STATE", state)
		return false
	var cost := float(definition.cost)
	if observation_data < cost:
		purchase_rejected.emit(node_id, "UPGRADE_ERROR_NEED_DATA", int(ceil(cost - observation_data)))
		return false
	observation_data = maxf(0.0, observation_data - cost)
	purchased_nodes[node_id] = true
	purchase_order.append(node_id)
	upgrade_purchased.emit(definition)
	state_changed.emit()
	return true


func has_upgrade(id: String) -> bool:
	return purchased_nodes.has(id)


func get_available_nodes() -> Array[String]:
	var available: Array[String] = []
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if get_node_state(node_id) == "available":
			available.append(node_id)
	return available


func debug_purchase_node(node_id: String) -> bool:
	var definition := Balance.upgrade_definition(node_id)
	if definition.is_empty() or has_upgrade(node_id):
		return false
	observation_data += float(definition.cost)
	return request_purchase(node_id)


func debug_purchase_all() -> void:
	var debug_budget := 0.0
	for definition in Balance.UPGRADE_NODES:
		debug_budget += float(definition.cost)
	observation_data += debug_budget
	var made_progress := true
	while made_progress:
		made_progress = false
		for definition in Balance.UPGRADE_NODES:
			var node_id := String(definition.id)
			if can_purchase(node_id):
				request_purchase(node_id)
				made_progress = true


func _base_get_tracking_radius() -> float:
	var base_radius := 52.0 if has_upgrade("better_lens") else 36.0
	return base_radius + get_taurus_tracking_radius_bonus()


func survey_enabled() -> bool:
	return has_upgrade("polar_survey")


func _base_get_survey_required_distance() -> float:
	if has_upgrade("draco_sweep"):
		return 190.0
	return 380.0 if has_upgrade("sweep_gain") else 460.0


func get_survey_spawn_probability() -> float:
	if has_upgrade("draco_sweep"):
		return 1.0
	if has_upgrade("deep_exposure"):
		return 0.55
	if has_upgrade("faint_recovery"):
		return 0.42
	return 0.30


func survey_charge_persists() -> bool:
	return has_upgrade("sustained_sweep")


func _base_get_survey_cooldown_seconds() -> float:
	if has_upgrade("draco_sweep"):
		return 0.45
	return 0.9 if has_upgrade("rapid_scan") else 1.5


func _base_get_survey_spawn_count() -> int:
	if has_upgrade("draco_sweep"):
		return 4
	return 2 if has_upgrade("polar_cascade") else 1


func record_manual_combo_success() -> void:
	if manual_combo_remaining <= 0.0:
		manual_combo_count = 0
	manual_combo_count = mini(MAX_MANUAL_COMBO_COUNT, manual_combo_count + 1)
	manual_combo_remaining = get_manual_combo_window()


func update_manual_combo(delta: float) -> void:
	if manual_combo_count <= 0:
		return
	manual_combo_remaining = maxf(0.0, manual_combo_remaining - maxf(0.0, delta))
	if manual_combo_remaining <= 0.0:
		manual_combo_count = 0


func reset_manual_combo() -> void:
	manual_combo_count = 0
	manual_combo_remaining = 0.0


func _base_get_manual_combo_window() -> float:
	if has_upgrade("taurus_full_gallop"):
		return 5.0
	if has_upgrade("sustained_charge"):
		return 4.0
	if has_upgrade("cadence_memory"):
		return 3.5
	if has_upgrade("momentum_acquisition"):
		return 3.0
	return BASE_MANUAL_COMBO_WINDOW


func _base_get_taurus_combo_cap() -> int:
	if not has_upgrade("momentum_acquisition"):
		return 0
	if has_upgrade("taurus_full_gallop"):
		return 10
	if has_upgrade("sustained_charge"):
		return 7
	if has_upgrade("cadence_memory"):
		return 5
	return 4


func get_taurus_combo_stack_count() -> int:
	return mini(manual_combo_count, get_taurus_combo_cap())


func get_manual_combo_display_count() -> int:
	if not has_upgrade("observation_streak"):
		return 0
	return manual_combo_count


func get_manual_combo_progress() -> float:
	if manual_combo_count <= 0:
		return 0.0
	return clampf(manual_combo_remaining / maxf(get_manual_combo_window(), 0.001), 0.0, 1.0)


func get_manual_analysis_speed_multiplier() -> float:
	var stacks := get_taurus_combo_stack_count()
	if stacks <= 0:
		return extension_effect("manual_speed")
	var speed_per_stack := 0.04 if has_upgrade("accelerated_analysis") else 0.02
	if has_upgrade("rapid_focus"):
		speed_per_stack += 0.01
	speed_per_stack += extension_effect("combo_speed", 0.0)
	return (1.0 + float(stacks) * speed_per_stack) * extension_effect("manual_speed")


func get_taurus_tracking_radius_bonus() -> float:
	var stacks := get_taurus_combo_stack_count()
	if stacks <= 0:
		return 0.0
	var radius_per_stack := 2.0 if has_upgrade("expanded_sweep") else 1.0
	if has_upgrade("wide_pursuit"):
		radius_per_stack += 0.5
	radius_per_stack += extension_effect("combo_radius", 0.0)
	return float(stacks) * radius_per_stack


func _base_get_lifetime_multiplier() -> float:
	var multiplier := 1.35 if has_upgrade("long_exposure") else 1.0
	if has_upgrade("adaptive_exposure_grid"):
		multiplier *= 1.12
	return multiplier


func _base_get_spawn_interval_scale() -> float:
	var scale := lerpf(1.0, 0.34, get_progression_ratio())
	if has_upgrade("radiant_plotting"):
		scale *= 0.94
	if has_upgrade("burst_windowing"):
		scale *= 0.88
	return scale


func _base_get_regular_spawn_interval_floor() -> float:
	if has_upgrade("draco_cadence"):
		return 0.45
	if has_upgrade("canis_cadence_iii"):
		return Balance.CANIS_FINAL_REGULAR_SPAWN_INTERVAL_FLOOR
	if has_upgrade("canis_cadence_ii"):
		return 0.85
	if has_upgrade("canis_cadence_i"):
		return 1.00
	return 1.15


func _base_get_observation_echo_probability() -> float:
	if has_upgrade("draco_echo"):
		return 0.65
	if has_upgrade("echo_correlation_20"):
		return 0.20
	if has_upgrade("echo_correlation_10"):
		return 0.10
	return 0.0


func _base_get_observation_echo_count() -> int:
	if has_upgrade("draco_echo"):
		return 6
	if has_upgrade("triple_echo_array"):
		return 3
	if has_upgrade("dual_echo_channel"):
		return 2
	if has_upgrade("single_echo_channel"):
		return 1
	return 0


func get_leonid_trigger_count() -> int:
	if has_upgrade("draco_storm"):
		return 2
	if has_upgrade("leonid_storm"):
		return 5
	if has_upgrade("storm_front"):
		return 6
	if has_upgrade("rapid_reacquisition"):
		return 7
	if has_upgrade("dense_stream"):
		return 8
	if has_upgrade("compressed_cadence"):
		return 9
	if has_upgrade("leonid_radiant"):
		return 10
	return 0


func get_leonid_storm_count() -> int:
	if has_upgrade("draco_storm"):
		return 30
	if has_upgrade("leonid_storm"):
		return 20
	if has_upgrade("storm_front"):
		return 16
	if has_upgrade("dense_stream"):
		return 12
	if has_upgrade("leonid_radiant"):
		return 8
	return 0


func record_leonid_manual_success() -> void:
	var trigger_count := get_leonid_trigger_count()
	if trigger_count <= 0:
		return
	leonid_charge = mini(trigger_count, leonid_charge + 1)


func leonid_storm_ready() -> bool:
	var trigger_count := get_leonid_trigger_count()
	return trigger_count > 0 and leonid_charge >= trigger_count


func consume_leonid_storm_charge() -> void:
	leonid_charge = 0


func get_observation_duration() -> float:
	var duration: float = Balance.BASE_OBSERVATION_DURATION
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if not has_upgrade(node_id):
			continue
		var parameters: Dictionary = definition.get("runtime_parameters", {})
		duration += float(parameters.get("observation_duration_bonus", 0.0))
	return minf(duration, Balance.MAX_OBSERVATION_DURATION)


func get_max_active() -> int:
	return mini(
		Balance.MAX_ACTIVE_METEORS,
		Balance.BASE_MAX_ACTIVE_METEORS
		+ int(has_upgrade("array_planning"))
		+ int(has_upgrade("multi_target_analysis"))
		+ int(has_upgrade("cascade_sampling"))
		+ int(has_upgrade("perseid_survey"))
		+ int(has_upgrade("canis_capacity_i"))
		+ int(has_upgrade("canis_capacity_ii"))
		+ Balance.CANIS_FINAL_ACTIVE_CAPACITY_DELTA * int(has_upgrade("canis_capacity_iii"))
		+ 6 * int(has_upgrade("draco_capacity"))
	)


# Secondary Camera hands the player a manually placed dish. Predictive Dish
# Control later pre-positions idle dishes without adding another input gesture.
# The network nodes keep their automatic lanes, one fewer each, while the final
# Observatory Network deliberately adds late-game dish capacity.
func _base_get_dish_count() -> int:
	if has_upgrade("draco_array"):
		return 4
	if has_upgrade("observatory_network"):
		return 2
	return 1 if has_upgrade("secondary_camera") else 0


func dish_auto_assignment_enabled() -> bool:
	return has_upgrade("predictive_dish_control")


func forecast_visible() -> bool:
	return has_upgrade("wide_field") or has_upgrade("ephemeris_marks") or dish_active()


func dish_active() -> bool:
	return get_dish_count() > 0


func _base_get_forecast_lead() -> float:
	var lead := 4.0 if dish_active() else (3.0 if has_upgrade("ephemeris_marks") else 2.0)
	if has_upgrade("crowd_forecast"):
		lead += 0.8
	return lead


func _base_get_forecast_max_error(type_id: String = "") -> float:
	if has_upgrade("change_detection") and is_andromeda_target(type_id):
		return 22.0
	if has_upgrade("double_star_resolution") and type_id == "binary_star":
		return 22.0
	if has_upgrade("trajectory"):
		return 40.0
	return 58.0 if has_upgrade("contact_ledger") else 70.0


func _base_get_forecast_min_error(type_id: String = "") -> float:
	if has_upgrade("change_detection") and is_andromeda_target(type_id):
		return 8.0
	if has_upgrade("double_star_resolution") and type_id == "binary_star":
		return 8.0
	if has_upgrade("trajectory"):
		return 14.0
	return 23.0 if has_upgrade("contact_ledger") else 28.0


func forecast_classifies(type_id: String = "") -> bool:
	return (
		has_upgrade("rare_detection")
		or (has_upgrade("change_detection") and is_andromeda_target(type_id))
		or (has_upgrade("double_star_resolution") and type_id == "binary_star")
	)


func is_deep_target(type_id: String) -> bool:
	return type_id in ["satellite", "variable_star", "comet", "binary_star", "galaxy"]


func is_andromeda_target(type_id: String) -> bool:
	return type_id in ["satellite", "variable_star", "comet", "galaxy"]


func _base_get_analysis_speed_multiplier(type_id: String) -> float:
	if has_upgrade("andromeda_deep_survey") and is_andromeda_target(type_id):
		return 1.25
	return 1.0


func get_observation_value_multiplier(type_id: String, active_target_count: int) -> float:
	var multiplier := 1.0
	for definition in Balance.UPGRADE_NODES:
		if not has_upgrade(String(definition.id)):
			continue
		var parameters: Dictionary = definition.get("runtime_parameters", {})
		multiplier *= maxf(1.0, float(parameters.get("observation_value_multiplier", 1.0)))
	if type_id == "fragment_piece" and has_upgrade("companion_resolution"):
		multiplier *= 1.35
	if type_id in ["fragment", "fragment_piece"] and has_upgrade("debris_correlation"):
		multiplier *= 1.2
	if is_andromeda_target(type_id) and has_upgrade("andromeda_deep_survey"):
		multiplier *= 1.3
	if is_perseid_survey_active(active_target_count):
		multiplier *= 1.18
	if type_id in ["fragment", "fragment_piece"]:
		multiplier *= extension_effect("fragment_data")
	return multiplier * extension_effect("data")


func is_perseid_survey_active(active_target_count: int) -> bool:
	return has_upgrade("perseid_survey") and active_target_count >= PERSEID_SURVEY_TARGET_THRESHOLD


func is_research_complete() -> bool:
	return upgrade_level >= Balance.research_node_count()


func galaxy_unlocked() -> bool:
	return has_upgrade("galactic_reference_frame")


func get_observation_span() -> float:
	return 1.0


func get_secondary_slots() -> int:
	if has_upgrade("draco_array"):
		return 4
	if has_upgrade("observatory_network"):
		return 2
	if has_upgrade("multi_target_analysis"):
		return 1
	return 0


func get_progression_ratio() -> float:
	# The original 51 pacing systems retain the shipped density curve. Later
	# content can add targets and interaction without diluting that curve before
	# it is purchased or accelerating it after the original tree is complete.
	var pacing_level := 0
	for node_variant in purchased_nodes:
		var node_id := String(node_variant)
		if node_id == "predictive_dish_control":
			continue
		var definition := Balance.upgrade_definition(node_id)
		if bool(definition.get("affects_pacing", true)):
			pacing_level += 1
	return clampf(float(pacing_level) / float(PACING_NODE_COUNT), 0.0, 1.0)


# Passive automation is unattended lifetime coverage, not a limited hardware
# analysis duration. At base lifetimes its tuned rates cover common 139%, fast
# 58%, fragment 65%, piece 81%, and major 49%; keep it outside dish/lane multipliers.
func get_automation_strength(type_id: String) -> float:
	var strength := 0.0
	if has_upgrade("automated_tracking"):
		match type_id:
			"common", "fragment_piece": strength = 0.29
			"fast": strength = 0.16
			"fragment": strength = 0.13
			"major": strength = 0.035
			_: strength = 0.0
	if type_id == "fragment_piece" and has_upgrade("fragment_analysis") and has_upgrade("multi_target_analysis"):
		strength = maxf(strength, 0.18)
	return strength


# Permanent outer-chart research composes after the original sky formulas.
func extension_effect(key: String, fallback: float = 1.0) -> float:
	return extension_state.effect(key, fallback) if extension_state != null else fallback

func get_tracking_radius() -> float:
	return _base_get_tracking_radius() * extension_effect("tracking_radius")

func get_survey_required_distance() -> float:
	return _base_get_survey_required_distance() * extension_effect("survey_distance")

func get_survey_cooldown_seconds() -> float:
	return _base_get_survey_cooldown_seconds() * extension_effect("survey_cooldown")

func get_survey_spawn_count() -> int:
	return _base_get_survey_spawn_count() + int(extension_effect("survey_count", 0.0))

func get_manual_combo_window() -> float:
	return _base_get_manual_combo_window() + extension_effect("combo_window", 0.0)

func get_taurus_combo_cap() -> int:
	return mini(MAX_MANUAL_COMBO_COUNT, _base_get_taurus_combo_cap() + int(extension_effect("combo_cap", 0.0))) if _base_get_taurus_combo_cap() > 0 else 0

func get_lifetime_multiplier() -> float:
	return _base_get_lifetime_multiplier() * extension_effect("meteor_lifetime")

func get_spawn_interval_scale() -> float:
	return _base_get_spawn_interval_scale() * extension_effect("spawn_interval")

func get_regular_spawn_interval_floor() -> float:
	return _base_get_regular_spawn_interval_floor() * extension_effect("spawn_interval")

func get_observation_echo_probability() -> float:
	return clampf(_base_get_observation_echo_probability() + extension_effect("echo_probability", 0.0), 0.0, 1.0)

func get_observation_echo_count() -> int:
	return _base_get_observation_echo_count() + int(extension_effect("echo_count", 0.0))

func get_dish_count() -> int:
	return _base_get_dish_count() + int(extension_effect("dish_count", 0.0))

func get_forecast_lead() -> float:
	return _base_get_forecast_lead() + extension_effect("forecast_lead", 0.0)

func get_forecast_max_error(type_id: String = "") -> float:
	return _base_get_forecast_max_error(type_id) * extension_effect("forecast_error")

func get_forecast_min_error(type_id: String = "") -> float:
	return _base_get_forecast_min_error(type_id) * extension_effect("forecast_error")

func get_analysis_speed_multiplier(type_id: String) -> float:
	return _base_get_analysis_speed_multiplier(type_id) * extension_effect("analysis_speed")
