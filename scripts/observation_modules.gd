extends RefCounted

const MAX_SLOTS := 5
const INITIAL_SLOTS := 2
const DEFINITIONS := {
	# All fourteen modules use one draw pool. Legacy costs and prerequisites
	# remain for the retained module diagnostic API, not the current chart.
	"focus": {"cost": 120000000.0, "speed": 1.8, "radius": 1.0, "targets": 1, "glyph": "focus", "code": "FOCUS", "badge": "×1.80", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"wide": {"cost": 120000000.0, "speed": 0.75, "radius": 1.65, "targets": 3, "glyph": "wide", "code": "WIDE", "badge": "×1.65", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"precision": {"cost": 180000000.0, "speed": 1.5, "radius": 0.7, "glyph": "focus", "code": "PRECISION", "badge": "×1.50", "requires": ["focus"], "source": "sample", "category": "trace", "pool": "trace"},
	"record": {"cost": 180000000.0, "speed": 0.8, "m31_value": 1.5, "glyph": "focus", "code": "RECORD", "badge": "×1.50", "requires": ["wide"], "source": "sample", "category": "link", "pool": "link"},
	"revisit": {"cost": 240000000.0, "m31_cooldown": 0.6, "glyph": "wide", "code": "REVISIT", "badge": "×0.60", "requires": [], "slots_required": 3, "source": "sample", "category": "link", "pool": "link"},
	"trail_integrator": {"cost": 0.0, "new_speed": 0.9, "trail_progress": 0.6, "glyph": "focus", "code": "TRAIL", "badge": "TRAIL 60%", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"sweep_optics": {"cost": 0.0, "new_speed": 0.9, "sweep_charge": 1.35, "rare_radius": 1.5, "glyph": "wide", "code": "SWEEP", "badge": "CHARGE ×1.35", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"relay_bus": {"cost": 0.0, "new_speed": 0.9, "relay_dish": 1.75, "glyph": "wide", "code": "RELAY", "badge": "DISH ×1.75", "requires": [], "source": "sample", "category": "link", "pool": "link"},
	"long_baseline": {"cost": 0.0, "new_speed": 0.85, "baseline_speed": 1.6, "glyph": "focus", "code": "BASELINE", "badge": "1s ×1.60", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"dual_processor": {"cost": 0.0, "primary_speed": 1.3, "secondary_speed": 0.55, "glyph": "focus", "code": "DUAL", "badge": "DUAL ×1.30", "requires": [], "source": "sample", "category": "trace", "pool": "trace"},
	"afterglow_archive": {"cost": 0.0, "archive_value": 0.5, "archive_lifetime": 8.0, "glyph": "wide", "code": "ARCHIVE", "badge": "AFTERGLOW", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"wide_correlation": {"cost": 0.0, "primary_speed": 0.75, "secondary_speed": 1.35, "glyph": "wide", "code": "CORRELATE", "badge": "LINK ×1.35", "requires": [], "source": "sample", "category": "sweep", "pool": "sweep"},
	"reference_bus": {"cost": 0.0, "m31_manual_speed": 0.75, "reference_dish": 1.6, "glyph": "focus", "code": "REFERENCE", "badge": "M31 DISH ×1.60", "requires": [], "source": "sample", "category": "link", "pool": "link"},
	"shutter_weave": {"cost": 0.0, "m31_cooldown": 1.25, "shutter_speed": 1.35, "glyph": "wide", "code": "SHUTTER", "badge": "M31 5s ×1.35", "requires": [], "source": "sample", "category": "link", "pool": "link"},
}
const SLOT_RESEARCH := {
	"slot_3": {"capacity": 3, "cost": 240000000.0, "requires": []},
	"slot_4": {"capacity": 4, "cost": 360000000.0, "requires": []},
	"slot_5": {"capacity": 5, "cost": 480000000.0, "requires": []},
}
const RESEARCH_IDS := ["focus", "wide", "precision", "record", "slot_3", "revisit", "slot_4", "slot_5"]
var purchased: Array[String] = []
var quantities: Dictionary = {}
var slots: Array[String] = ["", "", "", "", ""]
var unlocked_slots := INITIAL_SLOTS
var _cached_slots: Array[String] = []
var _cached_purchased: Array[String] = []
var _cached_capacity := -1
var _cached_quantities: Dictionary = {}
var _cached_effects: Dictionary = {}
var shutter_remaining := 0.0
var _m31_manual_active := false

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
	if key == "trail_progress":
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
		"m31_value": 1.0,
		"m31_cooldown": 1.0,
		"sweep_charge": 1.0,
		"rare_radius": 1.0,
	}
	var ids: Array = selection if selection is Array else [selection]
	var used: Array = []
	for id in ids:
		if not id is String or not DEFINITIONS.has(id) or id in used:
			continue
		used.append(id)
		var definition: Dictionary = DEFINITIONS[id]
		for key in ["speed", "new_speed", "radius", "m31_value", "m31_cooldown", "sweep_charge", "rare_radius"]:
			result[key] *= maxf(0.1, 1.0 + (float(definition.get(key, 1.0)) - 1.0) * ids.count(id))
		result.targets += (int(definition.get("targets", 1)) - 1) * ids.count(id)
		result.cost += definition.cost
	return result

func get_save_data() -> Dictionary:
	return {
		"purchased": purchased.duplicate(),
		"quantities": quantities.duplicate(),
		"slots": slots.duplicate(),
		"unlocked_slots": unlocked_slots,
		"shutter_remaining": shutter_remaining,
	}

func load_save_data(data: Dictionary) -> void:
	purchased.clear()
	quantities.clear()
	slots = ["", "", "", "", ""]
	shutter_remaining = _finite_range(data.get("shutter_remaining", 0.0), 0.0, 5.0)
	_m31_manual_active = false
	var capacity = data.get("unlocked_slots", INITIAL_SLOTS)
	# JSON numbers are floats; preserve researched capacity across disk saves.
	unlocked_slots = INITIAL_SLOTS
	if (capacity is int or capacity is float) and is_finite(float(capacity)) and floorf(float(capacity)) == float(capacity):
		unlocked_slots = int(clampf(float(capacity), INITIAL_SLOTS, MAX_SLOTS))
	var owned = data.get("purchased", [])
	if owned is Array:
		for id in owned:
			if id is String and DEFINITIONS.has(id) and id not in purchased:
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
	if "shutter_weave" not in purchased:
		shutter_remaining = 0.0
	_cached_capacity = -1


func advance_time(real_delta: float) -> void:
	if real_delta <= 0.0 or shutter_remaining <= 0.0:
		return
	shutter_remaining = maxf(0.0, shutter_remaining - real_delta)


func shutter_active() -> bool:
	return has("shutter_weave") and shutter_remaining > 0.0


func set_m31_manual_active(active: bool) -> void:
	_m31_manual_active = active


func m31_manual_active() -> bool:
	return _m31_manual_active


func dish_multiplier(target) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var multiplier := 1.0
	var manual_contribution := _target_manual_contribution(target)
	if has("relay_bus") and manual_contribution >= 0.25:
		multiplier *= stacked_effect("relay_bus", "relay_dish")
	# Reference Bus cross-feeds ordinary/anomaly dish work while the cursor is
	# genuinely on M31. M31 itself stays manual-only.
	if has("reference_bus") and String(target.get("type_id")) != "andromeda" and m31_manual_active():
		multiplier *= stacked_effect("reference_bus", "reference_dish")
	# New dish modifiers have their own cap. Existing dish rates are deliberately
	# outside it, because this contract must not retroactively weaken old builds.
	return clampf(multiplier, 0.25, 2.5)


func notify_completed(target) -> bool:
	if not has("shutter_weave") or not _shutter_target_eligible(target):
		return false
	if _target_manual_contribution(target) < 0.25:
		return false
	# Refreshing replaces the current window; completed targets cannot stack it.
	shutter_remaining = 5.0
	return true


func _target_manual_contribution(target) -> float:
	if target != null and is_instance_valid(target) and target.has_method("get_manual_contribution"):
		return maxf(0.0, float(target.get_manual_contribution()))
	return 0.0


func _shutter_target_eligible(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var type_id := String(target.get("type_id"))
	if type_id in ["andromeda", "fragment", "fragment_piece"]:
		return false
	if target.has_meta("afterglow_archive") or target.has_meta("shutter_ineligible"):
		return false
	return target.has_method("is_natural_observation") and target.is_natural_observation()


func _finite_range(value, minimum: float, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return minimum
	return clampf(float(value), minimum, maximum)
