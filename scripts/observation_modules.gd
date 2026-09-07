extends RefCounted

const MAX_SLOTS := 5
const INITIAL_SLOTS := 2
const DEFINITIONS := {
	"focus": {"cost": 120000000.0, "speed": 1.8, "radius": 1.0, "targets": 1, "glyph": "focus", "code": "FOCUS", "badge": "×1.80", "requires": []},
	"wide": {"cost": 120000000.0, "speed": 0.75, "radius": 1.65, "targets": 3, "glyph": "wide", "code": "WIDE", "badge": "×1.65", "requires": []},
	"precision": {"cost": 180000000.0, "speed": 1.5, "radius": 0.7, "glyph": "focus", "code": "PRECISION", "badge": "×1.50", "requires": ["focus"]},
	"record": {"cost": 180000000.0, "speed": 0.8, "m31_value": 1.5, "glyph": "focus", "code": "RECORD", "badge": "×1.50", "requires": ["wide"]},
	"revisit": {"cost": 240000000.0, "m31_cooldown": 0.6, "glyph": "wide", "code": "REVISIT", "badge": "×0.60", "requires": [], "slots_required": 3},
}
const SLOT_RESEARCH := {
	"slot_3": {"capacity": 3, "cost": 240000000.0, "requires": ["precision", "record"]},
	"slot_4": {"capacity": 4, "cost": 360000000.0, "requires": ["revisit"]},
	"slot_5": {"capacity": 5, "cost": 480000000.0, "requires": []},
}
const RESEARCH_IDS := ["focus", "wide", "precision", "record", "slot_3", "revisit", "slot_4", "slot_5"]
var purchased: Array[String] = []
var slots: Array[String] = ["", "", "", "", ""]
var unlocked_slots := INITIAL_SLOTS
var _cached_slots: Array[String] = []
var _cached_purchased: Array[String] = []
var _cached_capacity := -1
var _cached_effects: Dictionary = {}

func research_owned(id: String) -> bool:
	if SLOT_RESEARCH.has(id):
		return unlocked_slots >= int(SLOT_RESEARCH[id].capacity)
	return id in purchased

func research_ready(id: String) -> bool:
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
	if not id.is_empty() and (not DEFINITIONS.has(id) or id not in purchased or id in slots):
		return false
	slots[slot] = id
	return true

func installed_ids() -> Array[String]:
	var result: Array[String] = []
	for index in range(mini(slots.size(), clampi(unlocked_slots, INITIAL_SLOTS, MAX_SLOTS))):
		var id := slots[index]
		if DEFINITIONS.has(id) and id in purchased and id not in result:
			result.append(id)
	return result

func effect(key: String):
	# Array equality detects direct fixture mutation without allocating on reads.
	if _cached_capacity != unlocked_slots or _cached_slots != slots or _cached_purchased != purchased:
		_cached_effects = configuration(installed_ids())
		_cached_slots = slots.duplicate()
		_cached_purchased = purchased.duplicate()
		_cached_capacity = unlocked_slots
	return _cached_effects.get(key)

static func configuration(selection) -> Dictionary:
	var result := {"cost": 0.0, "speed": 1.0, "radius": 1.0, "targets": 1, "m31_value": 1.0, "m31_cooldown": 1.0}
	var ids: Array = selection if selection is Array else [selection]
	var used: Array = []
	for id in ids:
		if not id is String or not DEFINITIONS.has(id) or id in used:
			continue
		used.append(id)
		var definition: Dictionary = DEFINITIONS[id]
		for key in ["speed", "radius", "m31_value", "m31_cooldown"]:
			result[key] *= float(definition.get(key, 1.0))
		result.targets = maxi(result.targets, int(definition.get("targets", 1)))
		result.cost += definition.cost
	return result

func get_save_data() -> Dictionary:
	return {"purchased": purchased.duplicate(), "slots": slots.duplicate(), "unlocked_slots": unlocked_slots}

func load_save_data(data: Dictionary) -> void:
	purchased.clear()
	slots = ["", "", "", "", ""]
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
	var saved = data.get("slots", [data.get("equipped", ""), data.get("secondary", "")])
	if saved is Array:
		for index in range(mini(saved.size(), unlocked_slots)):
			if saved[index] is String and not saved[index].is_empty():
				equip(saved[index], index)
