extends Node

signal meteor_spawned(meteor)
signal rare_spawned(type_id)
signal contact_announced(contact)
signal contact_resolved(contact, meteor)

const Balance = preload("res://scripts/game_balance.gd")
const MeteorScript = preload("res://scripts/meteor.gd")
const MAX_TOTAL_METEORS := 32
const FORECAST_INTERCEPT_DISTANCE := 190.0
const MINIMUM_PAYABLE_TRACK_TIME := 0.95
# Automatic lanes are partial assist: at 7x analysis time the scan duration
# exceeds every eligible target's lifetime, so completion needs another source.
const LANE_TIME_MULTIPLIER := 7.0

enum LaneSelectionOrder {
	PARTNER_FIRST,
	BANK_UNSUPPORTED_FIRST,
}

var meteor_layer: Node2D
var progression: Node
var rng := RandomNumberGenerator.new()
var forecast_rng := RandomNumberGenerator.new()
var warm_contact_rng := RandomNumberGenerator.new()
var running: bool = false
var pause_regular_spawns: bool = false
var next_spawn_time: float = Balance.FIRST_METEOR_DELAY
var first_spawn_pending: bool = true
var secondary_refresh: float = 0.0
# Production finishes work that already has a viable partner first. The probe
# flips this switch to measure banking on unsupported targets before dish overlap.
var lane_selection_order: LaneSelectionOrder = LaneSelectionOrder.PARTNER_FIRST
var pending_contacts: Array[Dictionary] = []
var next_contact_id: int = 1
var phase_time_remaining: float = INF


func setup(target_layer: Node2D, progression_controller: Node) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	rng.randomize()
	forecast_rng.randomize()
	warm_contact_rng.randomize()


func start_spawning() -> void:
	running = true
	pause_regular_spawns = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true
	# Forecast phases start with one warm contact so their information pipeline
	# does not reduce the number of payable objects in a bounded watch. Exactly
	# one common contact anchors every measured round; never prefill a burst.
	if forecast_enabled() and pending_contacts.is_empty():
		_announce_regular_spawn(warm_contact_rng)


func reset() -> void:
	running = false
	for child in meteor_layer.get_children():
		child.queue_free()
	pause_regular_spawns = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true
	secondary_refresh = 0.0
	pending_contacts.clear()
	phase_time_remaining = INF


func _process(delta: float) -> void:
	if not running:
		return
	secondary_refresh -= delta
	if secondary_refresh <= 0.0:
		secondary_refresh = 0.35
		_refresh_secondary_camera()
	_update_pending_contacts(delta)
	if pause_regular_spawns:
		return
	next_spawn_time -= delta
	if next_spawn_time > 0.0:
		return
	if _active_count() + pending_contacts.size() >= progression.get_max_active():
		next_spawn_time = 0.45
		return
	if first_spawn_pending:
		first_spawn_pending = false
		_spawn_first_meteor()
	elif forecast_enabled():
		_announce_regular_spawn()
	else:
		spawn_meteor(_choose_regular_type())
	var base_interval := rng.randf_range(
		Balance.REGULAR_SPAWN_INTERVAL_MIN,
		Balance.REGULAR_SPAWN_INTERVAL_MAX
	)
	next_spawn_time = maxf(1.15, base_interval * progression.get_spawn_interval_scale())


func spawn_meteor(type_id: String = "common", custom_start := Vector2.INF, custom_velocity := Vector2.INF, lifetime_override: float = -1.0):
	# Shower and fragment paths intentionally bypass the regular progression cap.
	# Keep one reserved slot for the final major target while bounding all burst
	# paths so a missed frame cannot turn into an ever-growing render workload.
	var instance_limit := MAX_TOTAL_METEORS if type_id == "major" else MAX_TOTAL_METEORS - 1
	if meteor_layer == null or meteor_layer.get_child_count() >= instance_limit:
		return null
	var spec := Balance.meteor_spec(type_id)
	var start := custom_start
	var move_velocity := custom_velocity
	if custom_start == Vector2.INF:
		var entry := plan_entry(type_id)
		start = entry.start
		move_velocity = entry.velocity
	var lifetime_scale: float = progression.get_lifetime_multiplier()
	if lifetime_override > 0.0:
		lifetime_scale = lifetime_override / float(spec.lifetime)
	var meteor = MeteorScript.new()
	var features := _current_features(type_id)
	meteor.configure(spec, type_id, start, move_velocity, lifetime_scale, features)
	meteor.fragment_requested.connect(_on_fragment_requested)
	meteor_layer.add_child(meteor)
	meteor_spawned.emit(meteor)
	if type_id == "fireball" or type_id == "major":
		rare_spawned.emit(type_id)
	return meteor


func plan_entry(type_id: String) -> Dictionary:
	return _plan_entry_with_rng(type_id, rng)


func _plan_entry_with_rng(type_id: String, source_rng: RandomNumberGenerator) -> Dictionary:
	var size := get_viewport().get_visible_rect().size
	var spec := Balance.meteor_spec(type_id)
	var start := Vector2.ZERO
	match source_rng.randi_range(0, 2):
		0:
			start = Vector2(source_rng.randf_range(70.0, size.x - 70.0), -24.0)
		1:
			start = Vector2(-24.0, source_rng.randf_range(55.0, size.y * 0.68))
		_:
			start = Vector2(size.x + 24.0, source_rng.randf_range(55.0, size.y * 0.62))
	var target := Vector2(
		source_rng.randf_range(size.x * 0.24, size.x * 0.78),
		source_rng.randf_range(size.y * 0.30, size.y * 0.78)
	)
	return {
		"start": start,
		"velocity": (target - start).normalized() * float(spec.speed) * source_rng.randf_range(0.9, 1.12),
	}


func forecast_enabled() -> bool:
	return progression != null and progression.forecast_visible()


func set_phase_time_remaining(seconds: float) -> void:
	phase_time_remaining = maxf(0.0, seconds)


# A forecast names where the object will be before it exists, and names it
# wrong: the estimate carries an error that only resolves as the object closes.
func _announce_regular_spawn(source_rng: RandomNumberGenerator = null) -> void:
	var lead_time: float = progression.get_forecast_lead()
	# Never invite a commitment that the phase clock will silently erase. The
	# object needs both its full warning and one ordinary manual tracking window.
	if phase_time_remaining < lead_time + MINIMUM_PAYABLE_TRACK_TIME:
		return
	var planning_rng: RandomNumberGenerator = rng if source_rng == null else source_rng
	var type_id := _choose_regular_type_with_rng(planning_rng)
	var entry := _plan_entry_with_rng(type_id, planning_rng)
	var direction: Vector2 = Vector2(entry.velocity).normalized()
	var min_error: float = progression.get_forecast_min_error()
	var max_error: float = progression.get_forecast_max_error()
	var contact := {
		"id": next_contact_id,
		"type_id": type_id,
		"start": entry.start,
		"velocity": entry.velocity,
		"direction": direction,
		"intercept": Vector2(entry.start) + direction * FORECAST_INTERCEPT_DISTANCE,
		"error_offset": Vector2.from_angle(forecast_rng.randf_range(0.0, TAU)) * forecast_rng.randf_range(min_error, max_error),
		"max_error": max_error,
		"countdown": lead_time,
		"lead_time": lead_time,
		"trajectory_known": progression.has_upgrade("trajectory"),
		"classified": progression.forecast_classifies(),
		"abandoned_flash": 0.0,
	}
	next_contact_id += 1
	pending_contacts.append(contact)
	contact_announced.emit(contact)


func _update_pending_contacts(delta: float) -> void:
	for index in range(pending_contacts.size() - 1, -1, -1):
		var contact: Dictionary = pending_contacts[index]
		contact.abandoned_flash = maxf(0.0, float(contact.abandoned_flash) - delta)
		contact.countdown = maxf(0.0, float(contact.countdown) - delta)
		if float(contact.countdown) > 0.0:
			continue
		pending_contacts.remove_at(index)
		var meteor = spawn_meteor(String(contact.type_id), contact.start, contact.velocity)
		contact_resolved.emit(contact, meteor)


func spawn_for_shower(index: int) -> void:
	var type_id := "common"
	if index % 9 == 6:
		type_id = "fireball"
	elif index % 5 == 3:
		type_id = "fragment"
	elif index % 3 == 1:
		type_id = "fast"
	spawn_meteor(type_id)


func spawn_major_fireball():
	var size := get_viewport().get_visible_rect().size
	var start := Vector2(size.x + 80.0, size.y * 0.16)
	var target := Vector2(-110.0, size.y * 0.72)
	return spawn_meteor("major", start, (target - start).normalized() * 128.0, 14.0)


func refresh_active_features() -> void:
	for child in meteor_layer.get_children():
		if child.has_method("set_features"):
			child.set_features(_current_features(String(child.type_id)))
	_refresh_secondary_camera()


func _spawn_first_meteor() -> void:
	var size := get_viewport().get_visible_rect().size
	var start := Vector2(size.x + 16.0, size.y * 0.18)
	var target := Vector2(size.x * 0.31, size.y * 0.57)
	var spec := Balance.meteor_spec("common")
	spawn_meteor("common", start, (target - start).normalized() * float(spec.speed), 5.2)


func _choose_regular_type() -> String:
	return _choose_regular_type_with_rng(rng)


func _choose_regular_type_with_rng(source_rng: RandomNumberGenerator) -> String:
	var roll := source_rng.randf()
	if progression.has_upgrade("rare_detection") and roll < 0.075:
		return "fireball"
	if progression.has_upgrade("fragment_analysis") and roll < 0.25:
		return "fragment"
	if progression.has_upgrade("edge_detection") and roll < 0.50:
		return "fast"
	return "common"


func _current_features(type_id: String) -> Dictionary:
	return {
		"wide_field": progression.has_upgrade("wide_field"),
		"prediction": progression.has_upgrade("trajectory"),
		"precision": progression.has_upgrade("precision_multiplier"),
		"perfect": progression.has_upgrade("perfect_observation"),
		"automation": progression.get_automation_strength(type_id),
	}


func _refresh_secondary_camera() -> void:
	var slots: int = progression.get_secondary_slots()
	var candidates: Array = []
	for child_index in range(meteor_layer.get_child_count()):
		var child = meteor_layer.get_child(child_index)
		if child.has_method("set_lane_assist_rate"):
			child.set_lane_assist_rate(0.0)
		if not child.has_method("can_be_tracked") or not child.can_be_tracked():
			continue
		if child.type_id in ["fireball", "major"]:
			continue
		candidates.append(child)
	if slots <= 0:
		return
	candidates.sort_custom(_lane_candidate_precedes)
	for index in range(mini(slots, candidates.size())):
		var candidate = candidates[index]
		candidate.set_lane_assist_rate(candidate.get_assist_rate(LANE_TIME_MULTIPLIER))


func _lane_candidate_precedes(a, b) -> bool:
	var a_priority := _lane_candidate_priority(a)
	var b_priority := _lane_candidate_priority(b)
	if a_priority != b_priority:
		return a_priority < b_priority
	var a_progress := float(a.observation_progress)
	var b_progress := float(b.observation_progress)
	if not is_equal_approx(a_progress, b_progress):
		return a_progress > b_progress
	return a.get_instance_id() < b.get_instance_id()


func _lane_candidate_priority(candidate) -> int:
	var dish_held: bool = candidate.has_dish_assist()
	if not dish_held and candidate.has_non_dish_lane_partner():
		return 0
	if lane_selection_order == LaneSelectionOrder.BANK_UNSUPPORTED_FIRST:
		return 2 if dish_held else 1
	return 1 if dish_held else 2


func set_bank_unsupported_before_dish(enabled: bool) -> void:
	lane_selection_order = (
		LaneSelectionOrder.BANK_UNSUPPORTED_FIRST
		if enabled
		else LaneSelectionOrder.PARTNER_FIRST
	)


func _on_fragment_requested(origin: Vector2, parent_velocity: Vector2, parent_type: String) -> void:
	var piece_count := 4 if parent_type == "major" else 3
	var spread := 0.34 if parent_type == "major" else 0.25
	var available_slots := maxi(0, (MAX_TOTAL_METEORS - 1) - meteor_layer.get_child_count())
	for index in range(mini(piece_count, available_slots)):
		var centered := float(index) - float(piece_count - 1) * 0.5
		var direction := parent_velocity.normalized().rotated(centered * spread)
		var speed := parent_velocity.length() * rng.randf_range(0.88, 1.18)
		spawn_meteor("fragment_piece", origin + direction * 7.0, direction * speed, 3.2 if parent_type == "major" else 2.65)


func _active_count() -> int:
	var count := 0
	for child_index in range(meteor_layer.get_child_count()):
		var child = meteor_layer.get_child(child_index)
		if child.has_method("can_be_tracked") and child.can_be_tracked():
			count += 1
	return count
