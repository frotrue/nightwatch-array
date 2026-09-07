extends RefCounted

# Permanent purchases, two freely changeable equipped slots. Module effects are
# consumed by the existing observer; they do not rewrite earlier research.
const DEFINITIONS := {
	"focus": {"cost": 120000000.0, "speed": 1.8, "radius": 1.0, "targets": 1},
	"wide": {"cost": 120000000.0, "speed": 0.75, "radius": 1.65, "targets": 3},
}
var purchased: Array[String] = []
var equipped := ""
var secondary := ""
var _cached_first := "\u0001"
var _cached_second := "\u0001"
var _cached_effects: Dictionary = {}

func purchase(id: String, progression: Node) -> bool:
	if not DEFINITIONS.has(id) or id in purchased or not progression.galaxy_unlocked():
		return false
	var cost: float = DEFINITIONS[id].cost
	if progression.observation_data < cost:
		return false
	progression.observation_data -= cost
	purchased.append(id)
	progression.state_changed.emit()
	return true

func equip(id: String, slot: int = 0) -> bool:
	if slot < 0 or slot > 1 or (not id.is_empty() and id not in purchased):
		return false
	var other := secondary if slot == 0 else equipped
	if not id.is_empty() and id == other:
		return false
	if slot == 0:
		equipped = id
	else:
		secondary = id
	return true

func installed_ids() -> Array[String]:
	var result: Array[String] = []
	for id in [equipped, secondary]:
		if id in purchased and id not in result:
			result.append(id)
	return result

func effect(key: String):
	# Public slot/ownership fields are also used by save fixtures. Compare the
	# effective ids on read so direct changes cannot leave stale cached effects.
	var first := equipped if equipped in purchased else ""
	var second := secondary if secondary in purchased and secondary != first else ""
	if first != _cached_first or second != _cached_second:
		_cached_effects = configuration([first, second])
		_cached_first = first
		_cached_second = second
	return _cached_effects.get(key)

static func configuration(selection) -> Dictionary:
	var result := {"cost": 0.0, "speed": 1.0, "radius": 1.0, "targets": 1}
	var ids: Array = selection if selection is Array else [selection]
	var used: Array = []
	for id in ids:
		if not id is String or not DEFINITIONS.has(id) or id in used:
			continue
		used.append(id)
		var definition: Dictionary = DEFINITIONS[id]
		result.speed *= definition.speed
		result.radius *= definition.radius
		result.targets = maxi(result.targets, definition.targets)
		result.cost += definition.cost
	return result

func get_save_data() -> Dictionary:
	return {"purchased": purchased.duplicate(), "equipped": equipped, "slots": [equipped, secondary]}

func load_save_data(data: Dictionary) -> void:
	purchased.clear()
	var saved = data.get("purchased", [])
	if saved is Array:
		for id in saved:
			if id is String and DEFINITIONS.has(id) and id not in purchased:
				purchased.append(id)
	var slot = data.get("equipped", "")
	equipped = slot if slot is String and slot in purchased else ""
	secondary = ""
	if data.has("slots"):
		equipped = ""
		var slots = data.slots
		if slots is Array:
			for index in range(mini(2, slots.size())):
				if slots[index] is String:
					equip(slots[index], index)
