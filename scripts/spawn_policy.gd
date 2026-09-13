extends RefCounted

const Clock = preload("res://scripts/simulation_clock.gd")
const ORDER := ["common", "fast", "fragment", "fireball", "satellite", "variable_star", "comet", "binary_star", "galaxy", "black_hole"]
const LATE_TYPES := ["satellite", "variable_star", "comet", "binary_star", "galaxy", "black_hole"]
const BASE_PROBABILITIES := {
	"common": 0.5 / 60.0, "fast": 0.125 / 60.0,
	"fragment": 0.0875 / 60.0, "fireball": 0.0375 / 60.0,
	"satellite": 0.0375 / 60.0, "variable_star": 0.025 / 60.0,
	"comet": 0.0225 / 60.0, "binary_star": 0.0175 / 60.0,
	"galaxy": 0.01 / 60.0,
	"black_hole": 0.008 / 60.0,
}
const UNLOCKS := {
	"fast": "edge_detection", "fragment": "fragment_analysis", "fireball": "rare_detection",
	"satellite": "satellite_catalog", "variable_star": "variable_watchlist",
	"comet": "comet_solutions", "binary_star": "double_star_resolution", "galaxy": "galaxy_imaging",
	"black_hole": "galaxy_imaging",
}
# Emergency ceiling only. The research active-target limit gates new natural
# arrivals, while proc children can use headroom without taking late reservations.
const ATMOSPHERIC_SAFETY_SLOTS := 54
const LATE_SLOTS := 7
const LATE_TYPE_SLOTS := 2
const MAX_PENDING_PER_TYPE := 32
const DEFER_SECONDS := 2.0

var occurrence: Dictionary = {}
var entries: Dictionary = {}
var counters: Dictionary = {}
var admission_cursor := 0

func _init(seed_value: int = 1) -> void:
	reseed(seed_value)

func reseed(seed_value: int) -> void:
	occurrence.clear()
	entries.clear()
	counters.clear()
	admission_cursor = 0
	for i in ORDER.size():
		var kind: String = ORDER[i]
		var draw := RandomNumberGenerator.new()
		draw.seed = seed_value + (i + 1) * 104729
		occurrence[kind] = draw
		var entry := RandomNumberGenerator.new()
		entry.seed = seed_value + (i + 1) * 15485863
		entries[kind] = entry
		counters[kind] = {"rolled": 0, "admitted": 0, "deferred": 0, "expired": 0, "cap_rejected": 0}

static func mean_interval(low: float, high: float, floor_value: float) -> float:
	if floor_value <= low: return (low + high) * 0.5
	if floor_value >= high: return floor_value
	return (floor_value * (floor_value - low) + (high * high - floor_value * floor_value) * 0.5) / (high - low)

func probability(kind: String, progression: Node) -> float:
	if UNLOCKS.has(kind) and not progression.has_upgrade(UNLOCKS[kind]): return 0.0
	return _scaled_probability(kind, progression.get_spawn_probability_multiplier())

func _scaled_probability(kind: String, multiplier: float) -> float:
	return clampf(float(BASE_PROBABILITIES[kind]) * multiplier, 0.0, 1.0)

func roll(progression: Node) -> Array[String]:
	var selected: Array[String] = []
	var multiplier: float = progression.get_spawn_probability_multiplier()
	for kind: String in ORDER:
		var value: float = occurrence[kind].randf()
		var chance := 0.0 if UNLOCKS.has(kind) and not progression.has_upgrade(UNLOCKS[kind]) else _scaled_probability(kind, multiplier)
		if value < chance:
			selected.append(kind)
			counters[kind].rolled += 1
	return selected

func save_state() -> Dictionary:
	var result := {"cursor": admission_cursor, "occurrence": {}, "entries": {}}
	for kind: String in ORDER:
		# RNG states exceed exact JSON floating-point integer precision.
		result.occurrence[kind] = str(occurrence[kind].state)
		result.entries[kind] = str(entries[kind].state)
	return result

func restore_state(data: Dictionary) -> void:
	admission_cursor = clampi(int(data.get("cursor", 0)), 0, ORDER.size() - 1)
	for stream in ["occurrence", "entries"]:
		var saved = data.get(stream, {})
		if not saved is Dictionary: continue
		var destination: Dictionary = occurrence if stream == "occurrence" else entries
		for kind: String in ORDER:
			var value = saved.get(kind, "")
			if value is String and value.is_valid_int(): destination[kind].state = value.to_int()
