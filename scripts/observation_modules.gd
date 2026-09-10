extends RefCounted

const RETIRED_IDS := ["record", "revisit", "reference_bus", "shutter_weave"]
const MAX_SLOTS := 5
const INITIAL_SLOTS := 2
const OVERCHARGE_COUNT := 12
const OVERCHARGE_SECONDS := 6.0
var charge_count := 0
var burst_remaining := 0.0
const DEFINITIONS := {
	# Active modules use one draw pool. Legacy costs and prerequisites
	# remain for the retained module diagnostic API, not the current chart.
	"focus": {"cost": 120000000.0, "split_chance": 0.3, "glyph": "split", "code": "SPLIT", "badge": "30%", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"wide": {"cost": 120000000.0, "speed": 0.75, "radius": 1.65, "targets": 3, "glyph": "wide", "code": "WIDE", "badge": "×1.65", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"precision": {"cost": 180000000.0, "speed": 1.5, "radius": 0.7, "glyph": "focus", "code": "PRECISION", "badge": "×1.50", "requires": ["focus"], "source": "sample", "category": "trace", "pool": "trace"},
	"sweep_optics": {"cost": 0.0, "new_speed": 0.9, "sweep_charge": 1.35, "rare_radius": 1.5, "glyph": "wide", "code": "SWEEP", "badge": "CHARGE ×1.35", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"wide_correlation": {"cost": 0.0, "primary_speed": 0.75, "secondary_speed": 1.35, "glyph": "wide", "code": "CORRELATE", "badge": "LINK ×1.35", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"linear_observation": {"cost": 0.0, "line_width": 4.0, "glyph": "linear_observation", "code": "LINE", "badge": "LINE ×4", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"capture_hold": {"cost": 0.0, "hold_seconds": 2.0, "glyph": "capture_hold", "code": "HOLD", "badge": "HOLD 2s", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"overcharge": {"cost": 0.0, "burst_speed": 2.0, "burst_radius": 1.5, "glyph": "overcharge", "code": "BURST", "badge": "12 → 6s", "requires": [], "source": "sample", "category": "link", "pool": "link"},
}
const SLOT_RESEARCH := {
	"slot_3": {"capacity": 3, "cost": 240000000.0, "requires": []},
	"slot_4": {"capacity": 4, "cost": 360000000.0, "requires": []},
	"slot_5": {"capacity": 5, "cost": 480000000.0, "requires": []},
}
const RESEARCH_IDS := ["focus", "wide", "precision", "slot_3", "slot_4", "slot_5"]
var purchased: Array[String] = []
var quantities: Dictionary = {}
var slots: Array[String] = ["", "", "", "", ""]
var unlocked_slots := INITIAL_SLOTS
var _cached_slots: Array[String] = []
var _cached_purchased: Array[String] = []
var _cached_capacity := -1
var _cached_quantities: Dictionary = {}
var _cached_effects: Dictionary = {}

func research_owned(id: String) -> bool:
	if SLOT_RESEARCH.has(id):
		return unlocked_slots >= int(SLOT_RESEARCH[id].capacity)
	return id in purchased

func research_ready(id: String) -> bool:
	if id not in RESEARCH_IDS:
		return false
	var definition: Dictionary = SLOT_RESEARCH.get(id, DEFINITIONS.get(id, {}))
	if definition.is_empty() or research_owned(id):
		return false
	if SLOT_RESEARCH.has(id) and unlocked_slots != int(definition.capacity) - 1:
		return false
	if unlocked_slots < int(definition.get("slots_required", INITIAL_SLOTS)):
		return false
	for required in definition.requires:
		if required not in purchased:
			return false
	return true

func research_cost(id: String) -> float:
	return float(SLOT_RESEARCH.get(id, DEFINITIONS.get(id, {})).get("cost", 0.0))

func purchase(id: String, progression: Node) -> bool:
	if not progression.galaxy_unlocked() or not research_ready(id):
		return false
	var cost := research_cost(id)
	if progression.observation_data < cost:
		return false
	progression.observation_data -= cost
	if SLOT_RESEARCH.has(id):
		unlocked_slots = int(SLOT_RESEARCH[id].capacity)
	else:
		purchased.append(id)
	progression.state_changed.emit()
	return true


# Research and specimen rewards own inventory only. Equipment remains an
# explicit player choice, including when the first reward arrives mid-round.
func grant(id: String) -> bool:
	if not DEFINITIONS.has(id) or id in purchased:
		return false
	purchased.append(id)
	return true

func owned_count(id: String) -> int:
	return int(quantities.get(id, 1)) if id in purchased else 0

func installed_count(id: String) -> int:
	return installed_ids().count(id)

func spare_count(id: String) -> int:
	return maxi(0, owned_count(id) - installed_count(id))

func grant_copy(id: String) -> bool:
	if not DEFINITIONS.has(id) or owned_count(id) >= 1000000000:
		return false
	var count := owned_count(id)
	grant(id)
	quantities[id] = count + 1
	_cached_capacity = -1
	return true

func stacked_effect(id: String, key: String) -> float:
	if key == "hold_seconds":
		return float(DEFINITIONS.get(id, {}).get(key, 0.0)) * installed_count(id)
	return maxf(0.1, 1.0 + (float(DEFINITIONS.get(id, {}).get(key, 1.0)) - 1.0) * installed_count(id))

func first_empty_slot() -> int:
	for index in range(mini(slots.size(), clampi(unlocked_slots, INITIAL_SLOTS, MAX_SLOTS))):
		if slots[index].is_empty():
			return index
	return -1

func equip(id: String, slot: int = -1) -> bool:
	if slot == -1 and not id.is_empty():
		slot = first_empty_slot()
	if slot < 0 or slot >= mini(slots.size(), clampi(unlocked_slots, INITIAL_SLOTS, MAX_SLOTS)):
		return false
	if not id.is_empty() and (not DEFINITIONS.has(id) or id not in purchased or slots.slice(0, unlocked_slots).count(id) - int(slots[slot] == id) >= owned_count(id)):
		return false
	if slots[slot] != id and (slots[slot] == "overcharge" or id == "overcharge"):
		reset_round()
	slots[slot] = id
	return true

func installed_ids() -> Array[String]:
	var result: Array[String] = []
	for index in range(mini(slots.size(), clampi(unlocked_slots, INITIAL_SLOTS, MAX_SLOTS))):
		var id := slots[index]
		if DEFINITIONS.has(id) and id in purchased and result.count(id) < owned_count(id):
			result.append(id)
	return result


# `has` means active in the current loadout. Call `research_owned` when a
# caller needs inventory state for a research or reward decision.
func has(id: String) -> bool:
	return id in installed_ids()

func effect(key: String):
	# Array equality detects direct fixture mutation without allocating on reads.
	if _cached_capacity != unlocked_slots or _cached_slots != slots or _cached_purchased != purchased or _cached_quantities != quantities:
		_cached_effects = configuration(installed_ids())
		_cached_slots = slots.duplicate()
		_cached_purchased = purchased.duplicate()
		_cached_quantities = quantities.duplicate()
		_cached_capacity = unlocked_slots
	return _cached_effects.get(key)

static func configuration(selection) -> Dictionary:
	var result := {
		"cost": 0.0,
		"speed": 1.0,
		"new_speed": 1.0,
		"radius": 1.0,
		"targets": 1,
		"sweep_charge": 1.0,
		"rare_radius": 1.0,
		"split_chance": 0.0,
	}
	var ids: Array = selection if selection is Array else [selection]
	var used: Array = []
	for id in ids:
		if not id is String or not DEFINITIONS.has(id) or id in used:
			continue
		used.append(id)
		var definition: Dictionary = DEFINITIONS[id]
		for key in ["speed", "new_speed", "radius", "sweep_charge", "rare_radius"]:
			result[key] *= maxf(0.1, 1.0 + (float(definition.get(key, 1.0)) - 1.0) * ids.count(id))
		result.targets += (int(definition.get("targets", 1)) - 1) * ids.count(id)
		result.split_chance = minf(1.0, result.split_chance + float(definition.get("split_chance", 0.0)) * ids.count(id))
		result.cost += definition.cost
	return result

func get_save_data() -> Dictionary:
	return {
		"purchased": purchased.duplicate(),
		"quantities": quantities.duplicate(),
		"slots": slots.duplicate(),
		"unlocked_slots": unlocked_slots,
	}

func load_save_data(data: Dictionary) -> void:
	reset_round()
	purchased.clear()
	quantities.clear()
	slots = ["", "", "", "", ""]
	var capacity = data.get("unlocked_slots", INITIAL_SLOTS)
	# JSON numbers are floats; preserve researched capacity across disk saves.
	unlocked_slots = INITIAL_SLOTS
	if (capacity is int or capacity is float) and is_finite(float(capacity)) and floorf(float(capacity)) == float(capacity):
		unlocked_slots = int(clampf(float(capacity), INITIAL_SLOTS, MAX_SLOTS))
	var owned = data.get("purchased", [])
	if owned is Array:
		for id in owned:
			if id is String and (DEFINITIONS.has(id) or id in RETIRED_IDS) and id not in purchased:
				purchased.append(id)
	var counts = data.get("quantities", {})
	if counts is Dictionary:
		for id in purchased:
			var count = counts.get(id, 1)
			if (count is int or count is float) and is_finite(float(count)) and floorf(float(count)) == float(count):
				quantities[id] = int(clampf(float(count), 1, 1000000000))
	var saved = data.get("slots", [data.get("equipped", ""), data.get("secondary", "")])
	if saved is Array:
		for index in range(mini(saved.size(), unlocked_slots)):
			if saved[index] is String and not saved[index].is_empty():
				equip(saved[index], index)
	_cached_capacity = -1


func reset_round() -> void:
	charge_count = 0
	burst_remaining = 0.0

func record_completion(target: Node) -> void:
	if not has("overcharge") or not is_instance_valid(target) or target.get_meta("overcharge_counted", false):
		return
	target.set_meta("overcharge_counted", true)
	if burst_remaining > 0.0:
		return
	charge_count += 1
	if charge_count >= OVERCHARGE_COUNT:
		charge_count = 0
		burst_remaining = OVERCHARGE_SECONDS

func advance_time(delta: float) -> void:
	if not has("overcharge"):
		reset_round()
	else:
		burst_remaining = maxf(0.0, burst_remaining - maxf(0.0, delta))

func burst_multiplier(key: String) -> float:
	return stacked_effect("overcharge", key) if has("overcharge") and burst_remaining > 0.0 else 1.0

func get_round_state() -> Dictionary:
	return {"charge_count": charge_count, "burst_remaining": burst_remaining}

func restore_round_state(data: Dictionary) -> void:
	reset_round()
	if not has("overcharge"):
		return
	var count = data.get("charge_count", 0)
	var remaining = data.get("burst_remaining", 0.0)
	if (count is int or count is float) and is_finite(float(count)):
		charge_count = int(clampf(float(count), 0, OVERCHARGE_COUNT - 1))
	if (remaining is int or remaining is float) and is_finite(float(remaining)):
		burst_remaining = clampf(float(remaining), 0, OVERCHARGE_SECONDS)
	if burst_remaining > 0.0:
		charge_count = 0
