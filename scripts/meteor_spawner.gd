extends Node

signal meteor_spawned(meteor)
signal rare_spawned(type_id)
signal contact_announced(contact)
signal contact_resolved(contact, meteor)

const SpawnPolicy = preload("res://scripts/spawn_policy.gd")
const Balance = preload("res://scripts/game_balance.gd")
const MeteorScript = preload("res://scripts/meteor.gd")
const MAX_TOTAL_METEORS := 32
const FORECAST_INTERCEPT_DISTANCE := 190.0
const MINIMUM_PAYABLE_TRACK_TIME := 0.95
const ENTRY_MARGIN := 24.0
const ENTRY_BOUNDARY_TOP := 0
const ENTRY_BOUNDARY_LEFT := 1
const ENTRY_BOUNDARY_RIGHT := 2
# Bottom entry stays forbidden because it would cross the control shelf. Choose
# the remaining boundary before solving the path so widening the sky cannot
# silently multiply top candidates and pull the stream upward.
const TOP_ENTRY_SHARE := 0.30
const ENTRY_BOUNDARY_ORDER := [
	ENTRY_BOUNDARY_LEFT, ENTRY_BOUNDARY_TOP, ENTRY_BOUNDARY_RIGHT,
	ENTRY_BOUNDARY_LEFT, ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_TOP,
	ENTRY_BOUNDARY_LEFT, ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_LEFT,
	ENTRY_BOUNDARY_TOP, ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_LEFT,
	ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_TOP, ENTRY_BOUNDARY_LEFT,
	ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_LEFT, ENTRY_BOUNDARY_TOP,
	ENTRY_BOUNDARY_RIGHT, ENTRY_BOUNDARY_TOP,
]
const BURNOUT_GRID_COLUMNS := 4
const BURNOUT_GRID_ROWS := 3
# Meteors always entered from the true edges, but the burnout point stayed well
# inside them, so the outer sky held no deadline and read as dead. The
# horizontal inset guarded nothing and is now nearly gone; the vertical one
# still clears the phase clock above and the controls below, because a burnout
# under either is a target the player cannot hit.
const BURNOUT_SAFE_MIN := Vector2(0.03, 0.11)
const BURNOUT_SAFE_MAX := Vector2(0.97, 0.89)
const BURNOUT_CELL_ORDER := [0, 5, 10, 3, 8, 1, 6, 11, 4, 9, 2, 7]
const OUTER_BURNOUT_CELLS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 11]
# Jitter is a second inset on top of the safe rect: at 0.18 the outer cells
# never used their outer third. Widening it is what actually reaches the edge.
const BURNOUT_JITTER_MIN := 0.10
const BURNOUT_JITTER_MAX := 0.90
const PLAN_SPEED_FACTOR_MIN := 0.96
const PLAN_SPEED_FACTOR_MAX := 1.08
const MIN_ECHO_PHASE_REMAINING := 2.0
const ECHO_DELAY_INTERVAL := 0.75
const ECHO_BEACON_LEAD := 1.25
const ECHO_BOUNDARY_MARGIN := 0.12
const LEONID_STORM_DURATION := 7.0
const LEONID_STORM_REQUIRED_TIME := 9.0
# Automatic lanes are partial assist: at 7x analysis time the scan duration
# exceeds every eligible target's lifetime, so completion needs another source.
const LANE_TIME_MULTIPLIER := 7.0
const REGULAR_ACTIVE_TYPES := ["common", "fast", "fragment", "fragment_piece", "fireball"]

enum LaneSelectionOrder {
	PARTNER_FIRST,
	BANK_UNSUPPORTED_FIRST,
}

var meteor_layer: Node2D
var progression: Node
var extension_reserved_slots := 0
var extension_owner: Node
var observation_view: Camera2D
var spawn_policy := SpawnPolicy.new()
var next_simulation_id := 1
var rng := RandomNumberGenerator.new()
var forecast_rng := RandomNumberGenerator.new()
var warm_contact_rng := RandomNumberGenerator.new()
var echo_rng := RandomNumberGenerator.new()
var module_rng := RandomNumberGenerator.new()
var running: bool = false
var pause_regular_spawns: bool = false
var next_spawn_time: float = Balance.FIRST_METEOR_DELAY
var first_spawn_pending: bool = true
# Production finishes work that already has a viable partner first. The probe
# flips this switch to measure banking on unsupported targets before dish overlap.
var lane_selection_order: LaneSelectionOrder = LaneSelectionOrder.PARTNER_FIRST
var pending_contacts: Array[Dictionary] = []
var next_contact_id: int = 1
var phase_time_remaining: float = INF
var burnout_cell_cursors: Dictionary = {}
var entry_boundary_cursors: Dictionary = {}
var leonid_storm_remaining: int = 0
var leonid_storm_timer: float = 0.0
var leonid_storm_interval: float = 0.0
var leonid_storm_spawn_index: int = 0
var pending_echoes: Array[Dictionary] = []
var echo_burst_serial: int = 0
var canis_major_spawned_this_round: bool = false


func setup(target_layer: Node2D, progression_controller: Node, view: Camera2D = null) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	observation_view = view
	rng.randomize()
	forecast_rng.randomize()
	warm_contact_rng.randomize()
	echo_rng.randomize()
	module_rng.randomize()
	spawn_policy.reseed(rng.seed)


func start_spawning() -> void:
	running = true
	pause_regular_spawns = false
	canis_major_spawned_this_round = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true
	# Forecast phases start with one warm contact so their information pipeline
	# does not reduce the number of payable objects in a bounded watch. Exactly
	# one common contact anchors every measured round; never prefill a burst.
	if forecast_enabled() and pending_contacts.is_empty():
		_announce_regular_spawn(warm_contact_rng, "common")


func reset() -> void:
	running = false
	for child in meteor_layer.get_children():
		child.queue_free()
	pause_regular_spawns = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true
	pending_contacts.clear()
	pending_echoes.clear()
	echo_burst_serial = 0
	canis_major_spawned_this_round = false
	phase_time_remaining = INF
	burnout_cell_cursors.clear()
	entry_boundary_cursors.clear()
	leonid_storm_remaining = 0
	leonid_storm_timer = 0.0
	leonid_storm_interval = 0.0
	leonid_storm_spawn_index = 0


func simulate_tick(delta: float) -> void:
	if not running: return
	_update_pending_echoes(delta)
	_update_pending_contacts(delta)
	_update_leonid_storm(delta)
	# Consume every occurrence stream, even while locked or the atmospheric sky is paused.
	var selected := spawn_policy.roll(progression)
	if first_spawn_pending:
		next_spawn_time -= delta
		if next_spawn_time > 0.000001 or pause_regular_spawns: return
		first_spawn_pending = false
		_spawn_first_meteor()
	for kind in selected:
		if pause_regular_spawns and kind not in SpawnPolicy.LATE_TYPES: continue
		_announce_regular_spawn(spawn_policy.entries[kind], kind)

func _slot_count(kinds: Array) -> int:
	var count := 0
	if meteor_layer != null:
		for child in meteor_layer.get_children():
			if not child.is_queued_for_deletion() and child.type_id in kinds: count += 1
	return count

func _has_spawn_space(kind: String, count: int = 1, natural: bool = false) -> bool:
	if meteor_layer == null: return false
	if kind == "major": return _slot_count(["major"]) + count <= 1
	if kind in SpawnPolicy.LATE_TYPES:
		var own := _slot_count([kind])
		if own + count > SpawnPolicy.LATE_TYPE_SLOTS: return false
		var extras := 0
		for other in SpawnPolicy.LATE_TYPES: extras += maxi(0, _slot_count([other]) - 1)
		return own + count <= 1 or extras + count <= 1
	if _slot_count(REGULAR_ACTIVE_TYPES) + count > SpawnPolicy.ATMOSPHERIC_SLOTS: return false
	return not natural or _regular_active_count() + count <= progression.get_max_active()

func get_simulation_save() -> Dictionary:
	return {"rng": spawn_policy.save_state(), "first_pending": first_spawn_pending,
		"first_remaining": next_spawn_time, "canis_consumed": canis_major_spawned_this_round,
		"leonid_remaining": leonid_storm_remaining, "leonid_timer": leonid_storm_timer,
		"leonid_interval": leonid_storm_interval, "leonid_index": leonid_storm_spawn_index,
		"proc_rng": str(rng.state), "echo_rng": str(echo_rng.state), "module_rng": str(module_rng.state),
		"forecast_rng": str(forecast_rng.state), "entry_cells": burnout_cell_cursors.duplicate(), "entry_boundaries": entry_boundary_cursors.duplicate()}

func restore_simulation_save(data: Dictionary, legacy: bool = false) -> void:
	# Ordinary in-flight sky is intentionally not saved. Do not recreate its warm forecast.
	for contact in pending_contacts: contact_resolved.emit(contact, null)
	pending_contacts.clear()
	first_spawn_pending = bool(data.get("first_pending", false))
	next_spawn_time = clampf(float(data.get("first_remaining", 0.0)), 0.0, Balance.FIRST_METEOR_DELAY)
	canis_major_spawned_this_round = bool(data.get("canis_consumed", canis_major_spawned_this_round))
	leonid_storm_remaining = clampi(int(data.get("leonid_remaining", 0)), 0, 100)
	leonid_storm_timer = maxf(0.0, float(data.get("leonid_timer", 0.0)))
	leonid_storm_interval = maxf(0.0, float(data.get("leonid_interval", 0.0)))
	leonid_storm_spawn_index = maxi(0, int(data.get("leonid_index", 0)))
	if legacy: return
	if data.get("rng") is Dictionary: spawn_policy.restore_state(data.rng)
	for key in ["proc_rng", "echo_rng", "module_rng", "forecast_rng"]:
		var value = data.get(key, "")
		if value is String and value.is_valid_int():
			var stream: RandomNumberGenerator = {"proc_rng": rng, "echo_rng": echo_rng, "module_rng": module_rng, "forecast_rng": forecast_rng}[key]
			stream.state = value.to_int()
	for key in ["entry_cells", "entry_boundaries"]:
		var saved = data.get(key, {})
		if saved is Dictionary:
			var destination: Dictionary = burnout_cell_cursors if key == "entry_cells" else entry_boundary_cursors
			for kind in saved:
				if kind is String and kind.length() <= 120 and destination.size() < 1000 and (saved[kind] is float or saved[kind] is int): destination[kind] = clampi(int(saved[kind]), 0, 1000000000)


func spawn_meteor(type_id: String = "common", custom_start := Vector2.INF, custom_velocity := Vector2.INF, lifetime_override: float = -1.0, custom_burnout := Vector2.INF, is_observation_echo: bool = false, is_leonid_storm: bool = false, is_perseid_outburst: bool = false):
	if not _has_spawn_space(type_id): return null
	var spec := Balance.meteor_spec(type_id)
	var start := custom_start
	var move_velocity := custom_velocity
	var burnout := custom_burnout
	if custom_start == Vector2.INF:
		var entry := plan_entry(type_id)
		start = entry.start
		move_velocity = entry.velocity
		burnout = entry.burnout
	var lifetime_scale: float = progression.get_lifetime_multiplier()
	if lifetime_override > 0.0:
		lifetime_scale = lifetime_override / float(spec.lifetime)
	var meteor = MeteorScript.new()
	var features := _current_features(type_id)
	meteor.configure(spec, type_id, start, move_velocity, lifetime_scale, features, burnout, observation_view)
	if is_observation_echo:
		meteor.set_meta("gemini_echo", true)
	if is_leonid_storm:
		meteor.set_meta("leonid_storm", true)
	if is_perseid_outburst:
		meteor.set_meta("perseid_outburst", true)
	meteor.fragment_requested.connect(_on_fragment_requested)
	meteor.simulation_id = next_simulation_id
	next_simulation_id += 1
	if get_parent().has_method("allocate_simulation_id"): meteor.simulation_id = get_parent().allocate_simulation_id()
	meteor_layer.add_child(meteor)
	meteor.previous_simulation_position = meteor.global_position
	meteor.reset_physics_interpolation()
	meteor_spawned.emit(meteor)
	if type_id == "fireball" or type_id == "major":
		rare_spawned.emit(type_id)
	return meteor


func try_spawn_module_fragments(parent, chance: float) -> int:
	# One roll per completed common/fast target. A separate stream leaves normal
	# arrivals and constellation bursts unchanged when equipment is swapped.
	if not running or phase_time_remaining <= 0.0 or not is_instance_valid(parent):
		return 0
	if parent.type_id not in ["common", "fast"] or not parent.observed_successfully or parent.get_meta("module_fragment", false) or parent.get_meta("module_split_checked", false):
		return 0
	parent.set_meta("module_split_checked", true)
	if chance <= 0.0 or module_rng.randf() >= clampf(chance, 0.0, 1.0):
		return 0
	if not _has_spawn_space("fragment_piece", 2): return 0
	var direction: Vector2 = parent.velocity.normalized() if parent.velocity.length_squared() > 0.01 else Vector2.RIGHT
	var speed := clampf(parent.velocity.length() * 0.65, 130.0, 220.0)
	for angle in [-0.48, 0.48]:
		var branch := direction.rotated(angle)
		var piece = spawn_meteor("fragment_piece", parent.position + branch * 7.0, branch * speed, 2.9)
		piece.set_meta("module_fragment", true)
		piece.base_value = parent.base_value * 0.25
		piece.primary_color = parent.primary_color
		piece.glow_color = parent.glow_color
		piece.body_radius = minf(piece.body_radius, parent.body_radius * 0.65)
	return 2


func should_trigger_observation_echo(roll: float) -> bool:
	return (
		progression != null
		and progression.get_observation_echo_count() > 0
		and roll < progression.get_observation_echo_probability()
	)


func can_schedule_observation_echo(trigger_type: String = "") -> bool:
	return phase_time_remaining >= _echo_required_phase_time(trigger_type)


func try_spawn_observation_echo(trigger_was_manual: bool, trigger_is_echo: bool, trigger_meteor = null) -> int:
	# Echoes reward a fresh manual success. Meteors created by the burst cannot
	# recursively open another burst, and a near-expired round never rolls an
	# effect whose targets would be erased by the intermission boundary.
	if (
		not running
		or not trigger_was_manual
		or trigger_is_echo
		or not can_schedule_observation_echo(String(trigger_meteor.type_id) if is_instance_valid(trigger_meteor) else "")
		or not should_trigger_observation_echo(echo_rng.randf())
	):
		return 0
	return _spawn_observation_echo_burst(trigger_meteor)


func _spawn_observation_echo_burst(trigger_meteor = null) -> int:
	var count: int = progression.get_observation_echo_count()
	var trigger := _echo_trigger_snapshot(trigger_meteor)
	var scheduled := 0
	for index in count:
		var queued := pending_echoes.size()
		for contact in pending_contacts:
			if not contact.get("natural", false): queued += 1
		if queued >= 64:
			break
		var type_id := _echo_type_for_trigger(trigger)
		var entry := _plan_echo_entry(type_id, index, count, trigger)
		var delay := float(index) * ECHO_DELAY_INTERVAL if progression.has_upgrade("echo_delay_line") else 0.0
		if progression.has_upgrade("echo_beacon"):
			_announce_echo_contact(type_id, entry, ECHO_BEACON_LEAD + delay, index)
			scheduled += 1
		elif progression.has_upgrade("echo_delay_line"):
			pending_echoes.append({
				"countdown": delay,
				"type_id": type_id,
				"entry": entry,
				"sequence": index,
			})
			scheduled += 1
		else:
			var meteor = spawn_meteor(type_id, entry.start, entry.velocity, -1.0, entry.burnout, true)
			if meteor == null:
				break
			scheduled += 1
	echo_burst_serial += 1
	return scheduled


func _echo_required_phase_time(trigger_type: String) -> float:
	var last_delay := 0.0
	if progression != null and progression.has_upgrade("echo_delay_line"):
		last_delay = float(maxi(0, progression.get_observation_echo_count() - 1)) * ECHO_DELAY_INTERVAL
	var lead := ECHO_BEACON_LEAD if progression != null and progression.has_upgrade("echo_beacon") else 0.0
	var candidate_types: Array[String] = []
	if progression != null and progression.has_upgrade("echo_signature_lock") and trigger_type in ["common", "fast", "fragment", "fireball"]:
		candidate_types.append(trigger_type)
	else:
		candidate_types.append("common")
		if progression != null and progression.has_upgrade("edge_detection"):
			candidate_types.append("fast")
		if progression != null and progression.has_upgrade("fragment_analysis"):
			candidate_types.append("fragment")
		if progression != null and progression.has_upgrade("rare_detection"):
			candidate_types.append("fireball")
	var payable_time := MINIMUM_PAYABLE_TRACK_TIME
	for type_id in candidate_types:
		payable_time = maxf(payable_time, float(Balance.meteor_spec(type_id).track_time) / 1.42)
	return maxf(MIN_ECHO_PHASE_REMAINING, lead + last_delay + payable_time + ECHO_BOUNDARY_MARGIN)


func _echo_trigger_snapshot(trigger_meteor) -> Dictionary:
	if not is_instance_valid(trigger_meteor):
		return {}
	return {
		"type_id": String(trigger_meteor.type_id),
		"entry": Vector2(trigger_meteor.entry_position),
		"burnout": Vector2(trigger_meteor.burnout_position),
		"velocity": Vector2(trigger_meteor.initial_velocity),
	}


func _echo_type_for_trigger(trigger: Dictionary) -> String:
	var trigger_type := String(trigger.get("type_id", ""))
	if progression.has_upgrade("echo_signature_lock") and trigger_type in ["common", "fast", "fragment", "fireball"]:
		return trigger_type
	return _choose_echo_type_with_rng(echo_rng)


func _plan_echo_entry(type_id: String, index: int, count: int, trigger: Dictionary) -> Dictionary:
	if progression.has_upgrade("echo_deconfliction"):
		return _plan_deconflicted_echo_entry(type_id, index, count, trigger)
	if progression.has_upgrade("mirror_echo_solution") and not trigger.is_empty():
		var activity := _meteor_activity_rect()
		var mirror_x := activity.position.x + activity.end.x
		var mirrored_start := Vector2(mirror_x - float(Vector2(trigger.entry).x), float(Vector2(trigger.entry).y))
		var mirrored_burnout := Vector2(mirror_x - float(Vector2(trigger.burnout).x), float(Vector2(trigger.burnout).y))
		var direction := (mirrored_burnout - mirrored_start).normalized()
		var offset := (float(index) - float(count - 1) * 0.5) * 24.0
		var perpendicular := Vector2(-direction.y, direction.x) * offset
		return {
			"start": mirrored_start + perpendicular,
			"velocity": Vector2(-float(Vector2(trigger.velocity).x), float(Vector2(trigger.velocity).y)),
			"burnout": mirrored_burnout + perpendicular,
		}
	return plan_entry(type_id)


func _plan_deconflicted_echo_entry(type_id: String, index: int, count: int, trigger: Dictionary) -> Dictionary:
	var activity := _meteor_activity_rect()
	var spec := Balance.meteor_spec(type_id)
	var speed := float(spec.speed)
	var lifetime_scale: float = progression.get_lifetime_multiplier() if progression != null else 1.0
	var burn_distance := MeteorScript.burn_distance_for(speed, float(spec.lifetime) * lifetime_scale, float(spec.get("burn_terminal_ratio", 1.0)))
	var sequence := echo_burst_serial * maxi(1, count) + index
	var boundary_roll := fposmod((float(sequence) + 0.5) * 0.61803398875, 1.0)
	var entry_boundary := _entry_boundary_from_roll(boundary_roll)
	var wants_left := false
	if progression.has_upgrade("mirror_echo_solution") and not trigger.is_empty():
		wants_left = float(Vector2(trigger.entry).x) > activity.get_center().x
		entry_boundary = ENTRY_BOUNDARY_LEFT if wants_left else ENTRY_BOUNDARY_RIGHT
	var reachable := _reachable_burnout_cells(
		type_id, activity, burn_distance, entry_boundary
	)
	if reachable.is_empty():
		return plan_entry(type_id)
	var spacing := maxi(1, reachable.size() / maxi(1, count))
	var cell_index: int = int(reachable[(echo_burst_serial + index * spacing) % reachable.size()])
	var jitter_x := fposmod((float(sequence) + 0.5) * 0.41421356237, 1.0)
	var jitter_y := float(index) / float(maxi(1, count - 1))
	var solution := _entry_solution_for_cell(
		activity, cell_index, burn_distance, entry_boundary,
		index, jitter_x, jitter_y
	)
	if solution.is_empty():
		return plan_entry(type_id)
	var chosen := Vector2(solution.start)
	var target := Vector2(solution.target)
	return {
		"start": chosen,
		"velocity": (target - chosen).normalized() * speed,
		"burnout": target,
		"burn_distance": burn_distance,
	}


func _announce_echo_contact(type_id: String, entry: Dictionary, countdown: float, sequence: int) -> void:
	var direction := Vector2(entry.velocity).normalized()
	var max_error: float = progression.get_forecast_max_error(type_id)
	var min_error: float = progression.get_forecast_min_error(type_id)
	var contact := {
		"id": next_contact_id,
		"type_id": type_id,
		"start": entry.start,
		"velocity": entry.velocity,
		"burnout": entry.burnout,
		"direction": direction,
		"intercept": Vector2(entry.start) + direction * _world_px(FORECAST_INTERCEPT_DISTANCE),
		"error_offset": Vector2.from_angle(forecast_rng.randf_range(0.0, TAU)) * _world_px(forecast_rng.randf_range(min_error, max_error)),
		"max_error": _world_px(max_error),
		"countdown": countdown,
		"lead_time": countdown,
		"trajectory_known": progression.has_upgrade("mirror_echo_solution") or progression.has_upgrade("trajectory"),
		"classified": true,
		"abandoned_flash": 0.0,
		"gemini_echo": true,
		"echo_sequence": sequence,
	}
	next_contact_id += 1
	pending_contacts.append(contact)
	contact_announced.emit(contact)


func _update_pending_echoes(delta: float) -> void:
	var remaining: Array[Dictionary] = []
	for echo_variant in pending_echoes:
		var echo: Dictionary = echo_variant
		echo.countdown = float(echo.countdown) - delta
		if float(echo.countdown) > 0.0:
			remaining.append(echo)
			continue
		var entry: Dictionary = echo.entry
		var meteor = spawn_meteor(String(echo.type_id), entry.start, entry.velocity, -1.0, entry.burnout, true)
		if meteor == null and phase_time_remaining >= _echo_required_phase_time(String(echo.type_id)):
			echo["deferred"] = float(echo.get("deferred", 0.0)) + delta
			if float(echo.deferred) <= SpawnPolicy.DEFER_SECONDS: remaining.append(echo)
	pending_echoes = remaining


func try_start_leonid_storm() -> bool:
	var storm_count: int = progression.get_leonid_storm_count() if progression != null else 0
	if (
		not running
		or pause_regular_spawns
		or leonid_storm_remaining > 0
		or phase_time_remaining < LEONID_STORM_REQUIRED_TIME
		or storm_count <= 0
	):
		return false
	leonid_storm_remaining = storm_count
	leonid_storm_interval = LEONID_STORM_DURATION / float(storm_count)
	leonid_storm_timer = 0.0
	leonid_storm_spawn_index = 0
	_update_leonid_storm(0.0)
	return true


func leonid_storm_active() -> bool:
	return leonid_storm_remaining > 0


func _update_leonid_storm(delta: float) -> void:
	if leonid_storm_remaining <= 0:
		return
	leonid_storm_timer -= delta
	while leonid_storm_remaining > 0 and leonid_storm_timer <= 0.0:
		var type_id := _leonid_storm_type(leonid_storm_spawn_index)
		var entry := _leonid_storm_entry(type_id, leonid_storm_spawn_index)
		var meteor = spawn_meteor(
			type_id, entry.start, entry.velocity, -1.0, entry.burnout, false, true
		)
		if meteor == null:
			leonid_storm_timer = 0.10
			return
		leonid_storm_remaining -= 1
		leonid_storm_spawn_index += 1
		leonid_storm_timer += leonid_storm_interval


func _leonid_storm_type(index: int) -> String:
	var storm_count: int = progression.get_leonid_storm_count() if progression != null else 0
	if index == 0 and progression.has_upgrade("fragment_front"):
		return "fragment"
	if index == storm_count - 1 and progression.has_upgrade("fireball_tail"):
		return "fireball"
	if progression.has_upgrade("edge_detection") and index % 3 == 1:
		return "fast"
	return "common"


func _leonid_storm_entry(type_id: String, index: int) -> Dictionary:
	var entry := plan_entry(type_id)
	if not progression.has_upgrade("split_radiant_model"):
		return entry
	var activity := _meteor_activity_rect()
	var should_start_left := index % 2 == 0
	var starts_left := float(Vector2(entry.start).x) <= activity.get_center().x
	if should_start_left == starts_left:
		return entry
	var mirror_x := activity.position.x + activity.end.x
	return {
		"start": Vector2(mirror_x - float(Vector2(entry.start).x), float(Vector2(entry.start).y)),
		"velocity": Vector2(-float(Vector2(entry.velocity).x), float(Vector2(entry.velocity).y)),
		"burnout": Vector2(mirror_x - float(Vector2(entry.burnout).x), float(Vector2(entry.burnout).y)),
		"burn_distance": float(entry.get("burn_distance", 0.0)),
	}


func plan_entry(type_id: String) -> Dictionary:
	return _plan_entry_with_rng(type_id, rng)


func _plan_entry_with_rng(type_id: String, source_rng: RandomNumberGenerator) -> Dictionary:
	var activity := _meteor_activity_rect()
	var spec := Balance.meteor_spec(type_id)
	# Keep the planning stream at the legacy fixed five draws so changing spatial
	# geometry cannot silently change later type rolls or spawn cadence.
	var entry_selector := source_rng.randi_range(0, 2)
	var candidate_fraction := source_rng.randf()
	var jitter_x := source_rng.randf()
	var jitter_y := source_rng.randf()
	var speed := float(spec.speed) * source_rng.randf_range(
		PLAN_SPEED_FACTOR_MIN, PLAN_SPEED_FACTOR_MAX
	)
	var lifetime_scale: float = progression.get_lifetime_multiplier() if progression != null else 1.0
	var lifetime := float(spec.lifetime) * lifetime_scale
	var burn_distance := MeteorScript.burn_distance_for(
		speed, lifetime, float(spec.get("burn_terminal_ratio", 1.0))
	)
	var entry_boundary := _next_entry_boundary(type_id)
	var reachable_cells := _reachable_burnout_cells(
		type_id, activity, burn_distance, entry_boundary
	)
	if reachable_cells.is_empty():
		return _crossing_entry_plan(
			activity, speed, burn_distance, entry_boundary,
			candidate_fraction, jitter_x, jitter_y
		)
	var cell_index := _next_burnout_cell(type_id, reachable_cells)
	var boundary_solution := _entry_solution_for_cell(
		activity, cell_index, burn_distance, entry_boundary,
		entry_selector, jitter_x, jitter_y
	)
	if not boundary_solution.is_empty():
		var solved_start := Vector2(boundary_solution.start)
		var solved_target := Vector2(boundary_solution.target)
		return {
			"start": solved_start,
			"velocity": (solved_target - solved_start).normalized() * speed,
			"burnout": solved_target,
			"burn_distance": burn_distance,
		}
	return _crossing_entry_plan(
		activity, speed, burn_distance, entry_boundary,
		candidate_fraction, jitter_x, jitter_y
	)


func _reachable_burnout_cells(type_id: String, activity: Rect2, burn_distance: float, entry_boundary: int = -1) -> Array[int]:
	var reachable: Array[int] = []
	for ordered_index in BURNOUT_CELL_ORDER:
		var cell_index := int(ordered_index)
		if type_id in ["common", "fast"] and cell_index not in OUTER_BURNOUT_CELLS:
			continue
		var center := _burnout_cell_center(activity, cell_index)
		var is_reachable := (
			_burnout_cell_reachable_from_boundary(
				activity, cell_index, burn_distance, entry_boundary
			)
			if entry_boundary >= 0
			else not _entry_candidates(center, activity, burn_distance).is_empty()
		)
		if is_reachable:
			reachable.append(cell_index)
	return reachable


func _crossing_entry_plan(activity: Rect2, speed: float, burn_distance: float, entry_boundary: int, candidate_fraction: float, jitter_x: float, jitter_y: float) -> Dictionary:
	var start := Vector2.ZERO
	match entry_boundary:
		ENTRY_BOUNDARY_TOP:
			start = Vector2(lerpf(activity.position.x, activity.end.x, candidate_fraction), activity.position.y - ENTRY_MARGIN)
		ENTRY_BOUNDARY_LEFT:
			start = Vector2(activity.position.x - ENTRY_MARGIN, lerpf(activity.position.y, activity.end.y, candidate_fraction))
		_:
			start = Vector2(activity.end.x + ENTRY_MARGIN, lerpf(activity.position.y, activity.end.y, candidate_fraction))
	var safe_rect := _burnout_safe_rect(activity)
	var inward_target := safe_rect.position + Vector2(
		lerpf(0.25, 0.75, jitter_x) * safe_rect.size.x,
		lerpf(0.25, 0.75, jitter_y) * safe_rect.size.y
	)
	var direction := (inward_target - start).normalized()
	if direction.is_zero_approx():
		direction = (
			Vector2.DOWN if entry_boundary == ENTRY_BOUNDARY_TOP
			else (Vector2.RIGHT if entry_boundary == ENTRY_BOUNDARY_LEFT else Vector2.LEFT)
		)
	return {
		"start": start,
		"velocity": direction * speed,
		"burnout": start + direction * burn_distance,
		"burn_distance": burn_distance,
	}


func _next_burnout_cell(type_id: String, reachable_cells: Array[int]) -> int:
	# Every distance/lifetime combination gets its own cursor. Filtering the
	# low-discrepancy order before advancing avoids skip bias when a shallow type
	# cannot geometrically reach one of the deep cells.
	if reachable_cells.is_empty():
		return 0
	var cell_parts := PackedStringArray()
	for cell_index in reachable_cells:
		cell_parts.append(str(cell_index))
	var signature := "%s:%s" % [type_id, ",".join(cell_parts)]
	var cursor := int(burnout_cell_cursors.get(signature, 0))
	burnout_cell_cursors[signature] = cursor + 1
	return reachable_cells[cursor % reachable_cells.size()]


func _burnout_safe_rect(activity: Rect2) -> Rect2:
	var minimum := activity.position + activity.size * BURNOUT_SAFE_MIN
	var maximum := activity.position + activity.size * BURNOUT_SAFE_MAX
	return Rect2(minimum, maximum - minimum)


func _burnout_cell_center(activity: Rect2, cell_index: int) -> Vector2:
	var safe_rect := _burnout_safe_rect(activity)
	var cell_size := Vector2(
		safe_rect.size.x / float(BURNOUT_GRID_COLUMNS),
		safe_rect.size.y / float(BURNOUT_GRID_ROWS)
	)
	var column := cell_index % BURNOUT_GRID_COLUMNS
	var row := cell_index / BURNOUT_GRID_COLUMNS
	return safe_rect.position + Vector2(
		(float(column) + 0.5) * cell_size.x,
		(float(row) + 0.5) * cell_size.y
	)


func _burnout_cell_sample_rect(activity: Rect2, cell_index: int) -> Rect2:
	var safe_rect := _burnout_safe_rect(activity)
	var cell_size := Vector2(
		safe_rect.size.x / float(BURNOUT_GRID_COLUMNS),
		safe_rect.size.y / float(BURNOUT_GRID_ROWS)
	)
	var column := cell_index % BURNOUT_GRID_COLUMNS
	var row := cell_index / BURNOUT_GRID_COLUMNS
	return Rect2(
		safe_rect.position + Vector2(column, row) * cell_size + cell_size * BURNOUT_JITTER_MIN,
		cell_size * (BURNOUT_JITTER_MAX - BURNOUT_JITTER_MIN)
	)


func _burnout_cell_reachable_from_boundary(activity: Rect2, cell_index: int, burn_distance: float, entry_boundary: int) -> bool:
	var sample_rect := _burnout_cell_sample_rect(activity, cell_index)
	if entry_boundary == ENTRY_BOUNDARY_TOP:
		var start_y := activity.position.y - ENTRY_MARGIN
		var maximum_horizontal := maxf(
			sample_rect.end.x - activity.position.x,
			activity.end.x - sample_rect.position.x
		)
		var minimum_vertical := sqrt(maxf(
			0.0, burn_distance * burn_distance - maximum_horizontal * maximum_horizontal
		))
		var cell_vertical_min := sample_rect.position.y - start_y
		var cell_vertical_max := sample_rect.end.y - start_y
		return maxf(cell_vertical_min, minimum_vertical) <= minf(cell_vertical_max, burn_distance)
	var start_x := (
		activity.position.x - ENTRY_MARGIN
		if entry_boundary == ENTRY_BOUNDARY_LEFT
		else activity.end.x + ENTRY_MARGIN
	)
	var maximum_vertical := maxf(
		sample_rect.end.y - activity.position.y,
		activity.end.y - sample_rect.position.y
	)
	var minimum_horizontal := sqrt(maxf(
		0.0, burn_distance * burn_distance - maximum_vertical * maximum_vertical
	))
	var cell_horizontal_min := (
		sample_rect.position.x - start_x
		if entry_boundary == ENTRY_BOUNDARY_LEFT
		else start_x - sample_rect.end.x
	)
	var cell_horizontal_max := (
		sample_rect.end.x - start_x
		if entry_boundary == ENTRY_BOUNDARY_LEFT
		else start_x - sample_rect.position.x
	)
	return maxf(cell_horizontal_min, minimum_horizontal) <= minf(cell_horizontal_max, burn_distance)


func _entry_solution_for_cell(activity: Rect2, cell_index: int, burn_distance: float, entry_boundary: int, entry_selector: int, jitter_x: float, jitter_y: float) -> Dictionary:
	var sample_rect := _burnout_cell_sample_rect(activity, cell_index)
	if entry_boundary == ENTRY_BOUNDARY_TOP:
		var sampled_x := lerpf(sample_rect.position.x, sample_rect.end.x, jitter_x)
		for target_x in [sampled_x, sample_rect.position.x, sample_rect.end.x]:
			var top_solution := _top_entry_solution(
				activity, sample_rect, burn_distance, float(target_x),
				entry_selector, jitter_y
			)
			if not top_solution.is_empty():
				return top_solution
		return {}
	var sampled_y := lerpf(sample_rect.position.y, sample_rect.end.y, jitter_y)
	for target_y in [sampled_y, sample_rect.position.y, sample_rect.end.y]:
		var side_solution := _side_entry_solution(
			activity, sample_rect, burn_distance, entry_boundary,
			float(target_y), entry_selector, jitter_x
		)
		if not side_solution.is_empty():
			return side_solution
	return {}


func _top_entry_solution(activity: Rect2, sample_rect: Rect2, burn_distance: float, target_x: float, entry_selector: int, jitter_y: float) -> Dictionary:
	var start_y := activity.position.y - ENTRY_MARGIN
	var maximum_horizontal := maxf(
		target_x - activity.position.x,
		activity.end.x - target_x
	)
	var minimum_vertical := sqrt(maxf(
		0.0, burn_distance * burn_distance - maximum_horizontal * maximum_horizontal
	))
	var feasible_min := maxf(sample_rect.position.y - start_y, minimum_vertical)
	var feasible_max := minf(sample_rect.end.y - start_y, burn_distance)
	if feasible_min > feasible_max:
		return {}
	var vertical_distance := lerpf(feasible_min, feasible_max, jitter_y)
	var target := Vector2(target_x, start_y + vertical_distance)
	var horizontal_distance := sqrt(maxf(
		0.0, burn_distance * burn_distance - vertical_distance * vertical_distance
	))
	var starts: Array[Vector2] = []
	for start_x in [target.x - horizontal_distance, target.x + horizontal_distance]:
		if start_x >= activity.position.x and start_x <= activity.end.x:
			starts.append(Vector2(start_x, start_y))
	if starts.is_empty():
		return {}
	return {"start": starts[entry_selector % starts.size()], "target": target}


func _side_entry_solution(activity: Rect2, sample_rect: Rect2, burn_distance: float, entry_boundary: int, target_y: float, entry_selector: int, jitter_x: float) -> Dictionary:
	var starts_left := entry_boundary == ENTRY_BOUNDARY_LEFT
	var start_x := activity.position.x - ENTRY_MARGIN if starts_left else activity.end.x + ENTRY_MARGIN
	var maximum_vertical := maxf(
		target_y - activity.position.y,
		activity.end.y - target_y
	)
	var minimum_horizontal := sqrt(maxf(
		0.0, burn_distance * burn_distance - maximum_vertical * maximum_vertical
	))
	var cell_horizontal_min := sample_rect.position.x - start_x if starts_left else start_x - sample_rect.end.x
	var cell_horizontal_max := sample_rect.end.x - start_x if starts_left else start_x - sample_rect.position.x
	var feasible_min := maxf(cell_horizontal_min, minimum_horizontal)
	var feasible_max := minf(cell_horizontal_max, burn_distance)
	if feasible_min > feasible_max:
		return {}
	var horizontal_distance := lerpf(feasible_min, feasible_max, jitter_x)
	var target := Vector2(
		start_x + horizontal_distance if starts_left else start_x - horizontal_distance,
		target_y
	)
	var vertical_distance := sqrt(maxf(
		0.0, burn_distance * burn_distance - horizontal_distance * horizontal_distance
	))
	var starts: Array[Vector2] = []
	for candidate_y in [target.y - vertical_distance, target.y + vertical_distance]:
		if candidate_y >= activity.position.y and candidate_y <= activity.end.y:
			starts.append(Vector2(start_x, candidate_y))
	if starts.is_empty():
		return {}
	return {"start": starts[entry_selector % starts.size()], "target": target}


func _entry_candidates(target: Vector2, activity: Rect2, burn_distance: float) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	_append_horizontal_entry_candidates(candidates, target, activity, burn_distance)
	_append_vertical_entry_candidates(candidates, target, activity, burn_distance, activity.position.x - ENTRY_MARGIN)
	_append_vertical_entry_candidates(candidates, target, activity, burn_distance, activity.end.x + ENTRY_MARGIN)
	return candidates


func _entry_boundary_from_roll(boundary_roll: float) -> int:
	if boundary_roll < TOP_ENTRY_SHARE:
		return ENTRY_BOUNDARY_TOP
	if boundary_roll < TOP_ENTRY_SHARE + (1.0 - TOP_ENTRY_SHARE) * 0.5:
		return ENTRY_BOUNDARY_LEFT
	return ENTRY_BOUNDARY_RIGHT


func _next_entry_boundary(type_id: String) -> int:
	var cursor := int(entry_boundary_cursors.get(type_id, 0))
	entry_boundary_cursors[type_id] = cursor + 1
	return int(ENTRY_BOUNDARY_ORDER[cursor % ENTRY_BOUNDARY_ORDER.size()])


func _append_horizontal_entry_candidates(candidates: Array[Vector2], target: Vector2, activity: Rect2, burn_distance: float) -> void:
	var start_y := activity.position.y - ENTRY_MARGIN
	var normal_distance := target.y - start_y
	if normal_distance > burn_distance:
		return
	var tangent_distance := sqrt(maxf(0.0, burn_distance * burn_distance - normal_distance * normal_distance))
	for start_x in [target.x - tangent_distance, target.x + tangent_distance]:
		if start_x >= activity.position.x and start_x <= activity.end.x:
			candidates.append(Vector2(start_x, start_y))


func _append_vertical_entry_candidates(candidates: Array[Vector2], target: Vector2, activity: Rect2, burn_distance: float, start_x: float) -> void:
	var normal_distance := absf(target.x - start_x)
	if normal_distance > burn_distance:
		return
	var tangent_distance := sqrt(maxf(0.0, burn_distance * burn_distance - normal_distance * normal_distance))
	for start_y in [target.y - tangent_distance, target.y + tangent_distance]:
		if start_y >= activity.position.y and start_y <= activity.end.y:
			candidates.append(Vector2(start_x, start_y))


func forecast_enabled() -> bool:
	return progression != null and progression.forecast_visible()


func set_phase_time_remaining(seconds: float) -> void:
	phase_time_remaining = maxf(0.0, seconds)


# A forecast names where the object will be before it exists, and names it
# wrong: the estimate carries an error that only resolves as the object closes.
func _announce_regular_spawn(source_rng: RandomNumberGenerator = null, type_id: String = "common") -> void:
	var planning_rng: RandomNumberGenerator = rng if source_rng == null else source_rng
	var lead_time: float = progression.get_forecast_lead() if forecast_enabled() else 0.0
	var count := 0
	for pending in pending_contacts:
		if pending.get("natural", false) and pending.type_id == type_id: count += 1
	if count >= SpawnPolicy.MAX_PENDING_PER_TYPE:
		spawn_policy.counters[type_id].cap_rejected += 1
		return
	# Never announce a forecast that the phase clock will silently erase. The
	# object needs both its full warning and enough centered manual time for its
	# own catalog entry. Long Andromeda targets therefore stop announcing earlier
	# than an ordinary meteor, but still complete within the current round.
	var spec := Balance.meteor_spec(type_id)
	var payable_track_time := maxf(
		MINIMUM_PAYABLE_TRACK_TIME,
		float(spec.track_time) / 1.42
	)
	if phase_time_remaining < lead_time + payable_track_time:
		return
	var entry := _plan_entry_with_rng(type_id, planning_rng)
	var direction: Vector2 = Vector2(entry.velocity).normalized()
	var min_error: float = progression.get_forecast_min_error(type_id)
	var max_error: float = progression.get_forecast_max_error(type_id)
	var contact := {
		"natural": true,
		"deferred": 0.0,
		"visible": forecast_enabled(),
		"id": next_contact_id,
		"type_id": type_id,
		"start": entry.start,
		"velocity": entry.velocity,
		"burnout": entry.burnout,
		"direction": direction,
		"intercept": Vector2(entry.start) + direction * _world_px(FORECAST_INTERCEPT_DISTANCE),
		"error_offset": Vector2.from_angle(forecast_rng.randf_range(0.0, TAU)) * _world_px(forecast_rng.randf_range(min_error, max_error)),
		"max_error": _world_px(max_error),
		"countdown": lead_time,
		"lead_time": lead_time,
		"trajectory_known": progression.has_upgrade("trajectory"),
		"classified": progression.forecast_classifies(type_id),
		"abandoned_flash": 0.0,
	}
	next_contact_id += 1
	pending_contacts.append(contact)
	if forecast_enabled(): contact_announced.emit(contact)


func _update_pending_contacts(delta: float) -> void:
	# Rotate type priority; FIFO order within each type survives temporary saturation.
	var priority: Array = SpawnPolicy.ORDER.slice(spawn_policy.admission_cursor) + SpawnPolicy.ORDER.slice(0, spawn_policy.admission_cursor)
	spawn_policy.admission_cursor = (spawn_policy.admission_cursor + 1) % SpawnPolicy.ORDER.size()
	var due: Array = pending_contacts.duplicate()
	due.sort_custom(func(a, b):
		var left := priority.find(String(a.type_id))
		var right := priority.find(String(b.type_id))
		return int(a.id) < int(b.id) if left == right else left < right)
	for contact: Dictionary in due:
		contact.abandoned_flash = maxf(0.0, float(contact.abandoned_flash) - delta)
		contact.countdown = maxf(0.0, float(contact.countdown) - delta)
		if float(contact.countdown) > 0.000001: continue
		var kind := String(contact.type_id)
		var natural := bool(contact.get("natural", false))
		var spec := Balance.meteor_spec(kind)
		var payable := maxf(MINIMUM_PAYABLE_TRACK_TIME, float(spec.track_time) / 1.42)
		var blocked := not _has_spawn_space(kind, 1, natural) or (natural and pause_regular_spawns and kind not in SpawnPolicy.LATE_TYPES)
		if phase_time_remaining < payable or (blocked and float(contact.get("deferred", 0.0)) >= SpawnPolicy.DEFER_SECONDS):
			pending_contacts.erase(contact)
			if natural: spawn_policy.counters[kind].expired += 1
			contact_resolved.emit(contact, null)
			continue
		if blocked:
			if natural and float(contact.get("deferred", 0.0)) == 0.0: spawn_policy.counters[kind].deferred += 1
			contact["deferred"] = float(contact.get("deferred", 0.0)) + delta
			continue
		var meteor = spawn_meteor(kind, contact.start, contact.velocity, -1.0, Vector2(contact.get("burnout", Vector2.INF)), bool(contact.get("gemini_echo", false)))
		if meteor == null: continue
		pending_contacts.erase(contact)
		if natural: spawn_policy.counters[kind].admitted += 1
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


func spawn_for_perseid_outburst(index: int) -> void:
	var type_id := "common"
	if progression.has_upgrade("fragment_analysis") and index in [2, 6]:
		type_id = "fragment"
	elif progression.has_upgrade("edge_detection") and index % 2 == 1:
		type_id = "fast"
	spawn_meteor(type_id, Vector2.INF, Vector2.INF, -1.0, Vector2.INF, false, false, true)


func spawn_major_fireball():
	var activity := _meteor_activity_rect()
	var start := Vector2(activity.end.x + 80.0, activity.position.y + activity.size.y * 0.16)
	var target := Vector2(activity.position.x - 110.0, activity.position.y + activity.size.y * 0.72)
	return spawn_meteor("major", start, (target - start).normalized() * 128.0, 14.0)


func try_spawn_canis_major_fireball():
	if canis_major_spawned_this_round:
		return null
	var meteor = spawn_major_fireball()
	if meteor != null:
		canis_major_spawned_this_round = true
	return meteor


func refresh_active_features() -> void:
	for child in meteor_layer.get_children():
		if child.has_method("set_features"):
			child.set_features(_current_features(String(child.type_id)))
	_refresh_secondary_camera()


func _spawn_first_meteor() -> void:
	var activity := _meteor_activity_rect()
	var start := Vector2(activity.end.x + 16.0, activity.position.y + activity.size.y * 0.18)
	var target := activity.position + activity.size * Vector2(0.31, 0.57)
	var spec := Balance.meteor_spec("common")
	spawn_meteor("common", start, (target - start).normalized() * float(spec.speed), 5.2)


func _choose_echo_type_with_rng(source_rng: RandomNumberGenerator) -> String:
	# Echo bursts are immediate meteor entries, not the long-lived deep targets
	# whose analysis windows depend on forecast lead time.
	var roll := source_rng.randf()
	if progression.has_upgrade("rare_detection") and roll < 0.075:
		return "fireball"
	if progression.has_upgrade("fragment_analysis") and roll < 0.25:
		return "fragment"
	if progression.has_upgrade("edge_detection") and roll < 0.50:
		return "fast"
	return "common"


func _current_features(type_id: String) -> Dictionary:
	var spec := Balance.meteor_spec(type_id)
	var spectral_band := String(spec.get("spectral_band", "blue"))
	return {
		"wide_field": progression.has_upgrade("wide_field"),
		"precision": progression.has_upgrade("precision_multiplier"),
		"perfect": progression.has_upgrade("perfect_observation"),
		"automation": progression.get_automation_strength(type_id),
		"analysis_speed": progression.get_analysis_speed_multiplier(type_id),
		"spectral_calibrated": progression.has_upgrade("%s_band" % spectral_band),
		"spectral_capstone": progression.has_upgrade("lyrid_spectrograph"),
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
	return a.simulation_id < b.simulation_id


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


func _on_fragment_requested(origin: Vector2, parent_velocity: Vector2, parent_type: String, parent_is_echo: bool, parent_is_leonid: bool = false, parent_is_perseid: bool = false) -> void:
	var piece_count := 4 if parent_type == "major" else 3
	var spread := 0.34 if parent_type == "major" else 0.25
	var burst_direction := parent_velocity.normalized()
	if burst_direction.is_zero_approx():
		burst_direction = Vector2.RIGHT
	var burst_speed := parent_velocity.length()
	# The parent is intentionally slow at its terminal split. Preserve the old
	# 245px/s fragment burst so the children read as released energy rather than
	# inheriting the parent's near-stall. Major fragments keep the fireball speed.
	if parent_type != "major":
		burst_speed = maxf(burst_speed, float(Balance.meteor_spec("fragment").speed))
	var available_slots := maxi(0, SpawnPolicy.ATMOSPHERIC_SLOTS - _slot_count(REGULAR_ACTIVE_TYPES))
	for index in range(mini(piece_count, available_slots)):
		var centered := float(index) - float(piece_count - 1) * 0.5
		var direction := burst_direction.rotated(centered * spread)
		var speed := burst_speed * rng.randf_range(0.88, 1.18)
		spawn_meteor(
			"fragment_piece", origin + direction * 7.0, direction * speed,
			3.2 if parent_type == "major" else 2.65, Vector2.INF,
			parent_is_echo, parent_is_leonid, parent_is_perseid
		)


func _regular_active_count() -> int:
	var count := 0
	for child_index in range(meteor_layer.get_child_count()):
		var child = meteor_layer.get_child(child_index)
		if (
			String(child.get("type_id")) in REGULAR_ACTIVE_TYPES
			and child.has_method("can_be_tracked")
			and child.can_be_tracked()
		):
			count += 1
	return count


func _meteor_activity_rect() -> Rect2:
	if observation_view != null:
		if observation_view.has_method("meteor_activity_rect"):
			return observation_view.meteor_activity_rect()
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
