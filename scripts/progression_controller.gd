extends Node

signal state_changed
signal upgrade_purchased(definition)
signal purchase_rejected(node_id, reason_key, value)

const Balance = preload("res://scripts/game_balance.gd")

var observation_data: float = 0.0
var success_count: int = 0
var purchased_nodes: Dictionary = {}
var purchase_order: Array[String] = []
var manual_successes: int = 0
var automatic_successes: int = 0
var total_data_earned: float = 0.0
var best_multiplier: float = 1.0
var manual_streak: int = 0

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
	manual_streak = 0
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
		"manual_streak": manual_streak,
	}


func load_save_data(data: Dictionary) -> void:
	observation_data = maxf(0.0, float(data.get("observation_data", 0.0)))
	success_count = maxi(0, int(data.get("success_count", 0)))
	manual_successes = maxi(0, int(data.get("manual_successes", 0)))
	automatic_successes = maxi(0, int(data.get("automatic_successes", 0)))
	total_data_earned = maxf(0.0, float(data.get("total_data_earned", observation_data)))
	best_multiplier = maxf(1.0, float(data.get("best_multiplier", 1.0)))
	manual_streak = maxi(0, int(data.get("manual_streak", 0)))
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
	state_changed.emit()


func add_observation(amount: float, was_manual: bool, multiplier: float) -> float:
	var final_amount := amount
	if was_manual:
		manual_streak += 1
		if has_upgrade("observation_streak"):
			final_amount *= 1.0 + minf(0.5, float(maxi(0, manual_streak - 1)) * 0.08)
	else:
		manual_streak = 0
	final_amount = round(final_amount)
	observation_data += final_amount
	total_data_earned += final_amount
	success_count += 1
	if was_manual:
		manual_successes += 1
	else:
		automatic_successes += 1
	best_multiplier = maxf(best_multiplier, multiplier)
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
		if has_upgrade(String(gate)):
			return true
	return false


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
	observation_data += 100000.0
	var made_progress := true
	while made_progress:
		made_progress = false
		for definition in Balance.UPGRADE_NODES:
			var node_id := String(definition.id)
			if can_purchase(node_id):
				request_purchase(node_id)
				made_progress = true


func get_tracking_radius() -> float:
	return 52.0 if has_upgrade("better_lens") else 36.0


func get_lifetime_multiplier() -> float:
	return 1.35 if has_upgrade("long_exposure") else 1.0


func get_spawn_interval_scale() -> float:
	return lerpf(1.0, 0.34, get_progression_ratio())


func get_observation_duration() -> float:
	var duration: float = Balance.BASE_OBSERVATION_DURATION
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if not has_upgrade(node_id):
			continue
		var parameters: Dictionary = definition.get("effect_parameters", {})
		duration += float(parameters.get("observation_duration_bonus", 0.0))
	return minf(duration, Balance.MAX_OBSERVATION_DURATION)


func get_max_active() -> int:
	return mini(
		Balance.MAX_ACTIVE_METEORS,
		Balance.BASE_MAX_ACTIVE_METEORS
		+ int(has_upgrade("array_planning"))
		+ int(has_upgrade("multi_target_analysis"))
	)


# Secondary Camera no longer scans on its own; it hands the player a dish to
# aim. The later network nodes keep their automatic lanes, one fewer each,
# so the array's total coverage is unchanged and one lane of it is now steered.
func get_dish_count() -> int:
	return 1 if has_upgrade("secondary_camera") else 0


func get_secondary_slots() -> int:
	if has_upgrade("observatory_network"):
		return 2
	if has_upgrade("multi_target_analysis"):
		return 1
	return 0


func get_progression_ratio() -> float:
	return clampf(float(upgrade_level) / float(Balance.UPGRADE_NODES.size()), 0.0, 1.0)


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
