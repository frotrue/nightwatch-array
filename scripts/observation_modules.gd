extends RefCounted

# Permanent purchases, one freely changeable equipped slot. Module effects are
# consumed by the Andromeda stage; they do not rewrite earlier research.
const DEFINITIONS := {
	"focus": {"cost": 120000000.0, "speed": 1.8, "radius": 1.0, "targets": 1},
	"wide": {"cost": 120000000.0, "speed": 0.75, "radius": 1.65, "targets": 3},
}
var purchased: Array[String] = []
var equipped := ""

func purchase(id: String, progression: Node) -> bool:
	if not DEFINITIONS.has(id) or id in purchased or not progression.galaxy_unlocked():
		return false
	var cost: float = DEFINITIONS[id].cost
	if progression.observation_data < cost:
		return false
	progression.observation_data -= cost
	purchased.append(id)
	if equipped.is_empty():
		equipped = id
	progression.state_changed.emit()
	return true

func equip(id: String) -> bool:
	if not id.is_empty() and id not in purchased:
		return false
	equipped = id
	return true

func effect(key: String):
	if DEFINITIONS.has(equipped) and equipped in purchased:
		return DEFINITIONS[equipped][key]
	return {"speed": 1.0, "radius": 1.0, "targets": 1}.get(key)

func get_save_data() -> Dictionary:
	return {"purchased": purchased.duplicate(), "equipped": equipped}

func load_save_data(data: Dictionary) -> void:
	purchased.clear()
	var saved = data.get("purchased", [])
	if saved is Array:
		for id in saved:
			if id is String and DEFINITIONS.has(id) and id not in purchased:
				purchased.append(id)
	var slot = data.get("equipped", "")
	equipped = slot if slot is String and slot in purchased else ""
