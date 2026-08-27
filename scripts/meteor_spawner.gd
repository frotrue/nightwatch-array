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
const ENTRY_MARGIN := 24.0
const BURNOUT_GRID_COLUMNS := 4
const BURNOUT_GRID_ROWS := 3
const BURNOUT_SAFE_MIN := Vector2(0.08, 0.14)
const BURNOUT_SAFE_MAX := Vector2(0.92, 0.86)
const BURNOUT_CELL_ORDER := [0, 5, 10, 3, 8, 1, 6, 11, 4, 9, 2, 7]
const OUTER_BURNOUT_CELLS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 11]
const BURNOUT_JITTER_MIN := 0.18
const BURNOUT_JITTER_MAX := 0.82
const BURNOUT_JITTER_ATTEMPTS := 8
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
var rng := RandomNumberGenerator.new()
var forecast_rng := RandomNumberGenerator.new()
var warm_contact_rng := RandomNumberGenerator.new()
var echo_rng := RandomNumberGenerator.new()
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
var burnout_cell_cursors: Dictionary = {}
var leonid_storm_remaining: int = 0
var leonid_storm_timer: float = 0.0
var leonid_storm_interval: float = 0.0
var leonid_storm_spawn_index: int = 0
var pending_echoes: Array[Dictionary] = []
var echo_burst_serial: int = 0


func setup(target_layer: Node2D, progression_controller: Node) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	rng.randomize()
	forecast_rng.randomize()
	warm_contact_rng.randomize()
	echo_rng.randomize()


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
	pending_echoes.clear()
	echo_burst_serial = 0
	phase_time_remaining = INF
	burnout_cell_cursors.clear()
	leonid_storm_remaining = 0
	leonid_storm_timer = 0.0
	leonid_storm_interval = 0.0
	leonid_storm_spawn_index = 0


func _process(delta: float) -> void:
	if not running:
		return
	secondary_refresh -= delta
	if secondary_refresh <= 0.0:
		secondary_refresh = 0.35
		_refresh_secondary_camera()
	_update_pending_echoes(delta)
	_update_pending_contacts(delta)
	_update_leonid_storm(delta)
	if pause_regular_spawns:
		return
	next_spawn_time -= delta
	if next_spawn_time > 0.0:
		return
	# The research contract is a cap on live atmospheric work. Forecasts are
	# information about future work, while same-round deep targets have their own
	# long dwell times; charging either against this budget made better warning
	# and deep-sky discoveries suppress ordinary meteor arrivals. Burst sources
	# still count once their atmospheric objects are live, and every path remains
	# bounded by MAX_TOTAL_METEORS inside spawn_meteor().
	if _regular_active_count() >= progression.get_max_active():
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


func spawn_meteor(type_id: String = "common", custom_start := Vector2.INF, custom_velocity := Vector2.INF, lifetime_override: float = -1.0, custom_burnout := Vector2.INF, is_observation_echo: bool = false, is_leonid_storm: bool = false, is_perseid_outburst: bool = false):
	# Shower and fragment paths intentionally bypass the regular progression cap.
	# Keep one reserved slot for the final major target while bounding all burst
	# paths so a missed frame cannot turn into an ever-growing render workload.
	var instance_limit := MAX_TOTAL_METEORS if type_id == "major" else MAX_TOTAL_METEORS - 1
	if meteor_layer == null or meteor_layer.get_child_count() >= instance_limit:
		return null
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
	meteor.configure(spec, type_id, start, move_velocity, lifetime_scale, features, burnout)
	if is_observation_echo:
		meteor.set_meta("gemini_echo", true)
	if is_leonid_storm:
		meteor.set_meta("leonid_storm", true)
	if is_perseid_outburst:
		meteor.set_meta("perseid_outburst", true)
	meteor.fragment_requested.connect(_on_fragment_requested)
	meteor_layer.add_child(meteor)
	meteor_spawned.emit(meteor)
	if type_id == "fireball" or type_id == "major":
		rare_spawned.emit(type_id)
	return meteor


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
		var reserved_objects := meteor_layer.get_child_count() + pending_contacts.size() + pending_echoes.size()
		if reserved_objects >= MAX_TOTAL_METEORS - 1:
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
		var size := get_viewport().get_visible_rect().size
		var mirrored_start := Vector2(size.x - float(Vector2(trigger.entry).x), float(Vector2(trigger.entry).y))
		var mirrored_burnout := Vector2(size.x - float(Vector2(trigger.burnout).x), float(Vector2(trigger.burnout).y))
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
	var size := get_viewport().get_visible_rect().size
	var spec := Balance.meteor_spec(type_id)
	var speed := float(spec.speed)
	var lifetime_scale: float = progression.get_lifetime_multiplier() if progression != null else 1.0
	var burn_distance := MeteorScript.burn_distance_for(speed, float(spec.lifetime) * lifetime_scale, float(spec.get("burn_terminal_ratio", 1.0)))
	var reachable := _reachable_burnout_cells(type_id, size, burn_distance)
	if reachable.is_empty():
		return plan_entry(type_id)
	var wants_left := false
	if progression.has_upgrade("mirror_echo_solution") and not trigger.is_empty():
		wants_left = float(Vector2(trigger.entry).x) > size.x * 0.5
		var mirrored_reachable: Array[int] = []
		for reachable_cell_variant in reachable:
			var reachable_cell := int(reachable_cell_variant)
			var reachable_target := _burnout_cell_center(size, reachable_cell)
			for candidate in _entry_candidates(reachable_target, size, burn_distance):
				if (float(Vector2(candidate).x) <= size.x * 0.5) == wants_left:
					mirrored_reachable.append(reachable_cell)
					break
		if mirrored_reachable.size() >= count:
			reachable = mirrored_reachable
	var spacing := maxi(1, reachable.size() / maxi(1, count))
	var cell_index: int = int(reachable[(echo_burst_serial + index * spacing) % reachable.size()])
	var target := _burnout_cell_center(size, cell_index)
	var candidates := _entry_candidates(target, size, burn_distance)
	if candidates.is_empty():
		return plan_entry(type_id)
	var chosen: Vector2 = candidates[index % candidates.size()]
	if progression.has_upgrade("mirror_echo_solution") and not trigger.is_empty():
		for candidate in candidates:
			if (float(Vector2(candidate).x) <= size.x * 0.5) == wants_left:
				chosen = Vector2(candidate)
				break
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
		"intercept": Vector2(entry.start) + direction * FORECAST_INTERCEPT_DISTANCE,
		"error_offset": Vector2.from_angle(forecast_rng.randf_range(0.0, TAU)) * forecast_rng.randf_range(min_error, max_error),
		"max_error": max_error,
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
		spawn_meteor(String(echo.type_id), entry.start, entry.velocity, -1.0, entry.burnout, true)
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
	var size := get_viewport().get_visible_rect().size
	var should_start_left := index % 2 == 0
	var starts_left := float(Vector2(entry.start).x) <= size.x * 0.5
	if should_start_left == starts_left:
		return entry
	return {
		"start": Vector2(size.x - float(Vector2(entry.start).x), float(Vector2(entry.start).y)),
		"velocity": Vector2(-float(Vector2(entry.velocity).x), float(Vector2(entry.velocity).y)),
		"burnout": Vector2(size.x - float(Vector2(entry.burnout).x), float(Vector2(entry.burnout).y)),
		"burn_distance": float(entry.get("burn_distance", 0.0)),
	}


func plan_entry(type_id: String) -> Dictionary:
	return _plan_entry_with_rng(type_id, rng)


func _plan_entry_with_rng(type_id: String, source_rng: RandomNumberGenerator) -> Dictionary:
	var size := get_viewport().get_visible_rect().size
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
	var reachable_cells := _reachable_burnout_cells(type_id, size, burn_distance)
	if reachable_cells.is_empty():
		return _crossing_entry_plan(
			size, speed, burn_distance, entry_selector,
			candidate_fraction, jitter_x, jitter_y
		)
	var cell_index := _next_burnout_cell(type_id, reachable_cells)
	var target := _burnout_cell_center(size, cell_index)
	var entry_candidates: Array[Vector2] = []
	for attempt in range(BURNOUT_JITTER_ATTEMPTS):
		var center_blend := float(attempt) / float(maxi(1, BURNOUT_JITTER_ATTEMPTS - 1))
		var jittered_target := _sample_burnout_cell(
			size, cell_index,
			lerpf(jitter_x, 0.5, center_blend),
			lerpf(jitter_y, 0.5, center_blend)
		)
		var jittered_candidates := _entry_candidates(jittered_target, size, burn_distance)
		if jittered_candidates.is_empty():
			continue
		target = jittered_target
		entry_candidates = jittered_candidates
		break
	if entry_candidates.is_empty():
		entry_candidates = _entry_candidates(target, size, burn_distance)
	var candidate_index := (
		entry_selector + mini(entry_candidates.size() - 1, int(candidate_fraction * entry_candidates.size()))
	) % entry_candidates.size()
	var start: Vector2 = entry_candidates[candidate_index]
	return {
		"start": start,
		"velocity": (target - start).normalized() * speed,
		"burnout": target,
		"burn_distance": burn_distance,
	}


func _reachable_burnout_cells(type_id: String, size: Vector2, burn_distance: float) -> Array[int]:
	var reachable: Array[int] = []
	for ordered_index in BURNOUT_CELL_ORDER:
		var cell_index := int(ordered_index)
		if type_id in ["common", "fast"] and cell_index not in OUTER_BURNOUT_CELLS:
			continue
		var center := _burnout_cell_center(size, cell_index)
		if not _entry_candidates(center, size, burn_distance).is_empty():
			reachable.append(cell_index)
	return reachable


func _crossing_entry_plan(size: Vector2, speed: float, burn_distance: float, entry_selector: int, candidate_fraction: float, jitter_x: float, jitter_y: float) -> Dictionary:
	var start := Vector2.ZERO
	match entry_selector:
		0:
			start = Vector2(lerpf(0.0, size.x, candidate_fraction), -ENTRY_MARGIN)
		1:
			start = Vector2(-ENTRY_MARGIN, lerpf(0.0, size.y, candidate_fraction))
		_:
			start = Vector2(size.x + ENTRY_MARGIN, lerpf(0.0, size.y, candidate_fraction))
	var safe_rect := _burnout_safe_rect(size)
	var inward_target := safe_rect.position + Vector2(
		lerpf(0.25, 0.75, jitter_x) * safe_rect.size.x,
		lerpf(0.25, 0.75, jitter_y) * safe_rect.size.y
	)
	var direction := (inward_target - start).normalized()
	if direction.is_zero_approx():
		direction = (
			Vector2.DOWN if entry_selector == 0
			else (Vector2.RIGHT if entry_selector == 1 else Vector2.LEFT)
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


func _burnout_safe_rect(size: Vector2) -> Rect2:
	var minimum := Vector2(size.x * BURNOUT_SAFE_MIN.x, size.y * BURNOUT_SAFE_MIN.y)
	var maximum := Vector2(size.x * BURNOUT_SAFE_MAX.x, size.y * BURNOUT_SAFE_MAX.y)
	return Rect2(minimum, maximum - minimum)


func _burnout_cell_center(size: Vector2, cell_index: int) -> Vector2:
	var safe_rect := _burnout_safe_rect(size)
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


func _sample_burnout_cell(size: Vector2, cell_index: int, jitter_x: float, jitter_y: float) -> Vector2:
	var safe_rect := _burnout_safe_rect(size)
	var cell_size := Vector2(
		safe_rect.size.x / float(BURNOUT_GRID_COLUMNS),
		safe_rect.size.y / float(BURNOUT_GRID_ROWS)
	)
	var column := cell_index % BURNOUT_GRID_COLUMNS
	var row := cell_index / BURNOUT_GRID_COLUMNS
	return safe_rect.position + Vector2(
		(float(column) + lerpf(BURNOUT_JITTER_MIN, BURNOUT_JITTER_MAX, clampf(jitter_x, 0.0, 1.0))) * cell_size.x,
		(float(row) + lerpf(BURNOUT_JITTER_MIN, BURNOUT_JITTER_MAX, clampf(jitter_y, 0.0, 1.0))) * cell_size.y
	)


func _entry_candidates(target: Vector2, size: Vector2, burn_distance: float) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	_append_horizontal_entry_candidates(candidates, target, size, burn_distance)
	_append_vertical_entry_candidates(candidates, target, size, burn_distance, -ENTRY_MARGIN)
	_append_vertical_entry_candidates(candidates, target, size, burn_distance, size.x + ENTRY_MARGIN)
	return candidates


func _append_horizontal_entry_candidates(candidates: Array[Vector2], target: Vector2, size: Vector2, burn_distance: float) -> void:
	var normal_distance := target.y + ENTRY_MARGIN
	if normal_distance > burn_distance:
		return
	var tangent_distance := sqrt(maxf(0.0, burn_distance * burn_distance - normal_distance * normal_distance))
	for start_x in [target.x - tangent_distance, target.x + tangent_distance]:
		if start_x >= 0.0 and start_x <= size.x:
			candidates.append(Vector2(start_x, -ENTRY_MARGIN))


func _append_vertical_entry_candidates(candidates: Array[Vector2], target: Vector2, size: Vector2, burn_distance: float, start_x: float) -> void:
	var normal_distance := absf(target.x - start_x)
	if normal_distance > burn_distance:
		return
	var tangent_distance := sqrt(maxf(0.0, burn_distance * burn_distance - normal_distance * normal_distance))
	for start_y in [target.y - tangent_distance, target.y + tangent_distance]:
		if start_y >= 0.0 and start_y <= size.y:
			candidates.append(Vector2(start_x, start_y))


func forecast_enabled() -> bool:
	return progression != null and progression.forecast_visible()


func set_phase_time_remaining(seconds: float) -> void:
	phase_time_remaining = maxf(0.0, seconds)


# A forecast names where the object will be before it exists, and names it
# wrong: the estimate carries an error that only resolves as the object closes.
func _announce_regular_spawn(source_rng: RandomNumberGenerator = null) -> void:
	var planning_rng: RandomNumberGenerator = rng if source_rng == null else source_rng
	var type_id := _choose_regular_type_with_rng(planning_rng)
	var lead_time: float = progression.get_forecast_lead()
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
		"id": next_contact_id,
		"type_id": type_id,
		"start": entry.start,
		"velocity": entry.velocity,
		"burnout": entry.burnout,
		"direction": direction,
		"intercept": Vector2(entry.start) + direction * FORECAST_INTERCEPT_DISTANCE,
		"error_offset": Vector2.from_angle(forecast_rng.randf_range(0.0, TAU)) * forecast_rng.randf_range(min_error, max_error),
		"max_error": max_error,
		"countdown": lead_time,
		"lead_time": lead_time,
		"trajectory_known": progression.has_upgrade("trajectory"),
		"classified": progression.forecast_classifies(type_id),
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
		var is_echo := bool(contact.get("gemini_echo", false))
		var meteor = spawn_meteor(
			String(contact.type_id), contact.start, contact.velocity, -1.0,
			Vector2(contact.get("burnout", Vector2.INF)), is_echo
		)
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
	var threshold := 0.0
	if progression.has_upgrade("galaxy_imaging"):
		threshold += 0.02
		if roll < threshold:
			return "galaxy"
	if progression.has_upgrade("double_star_resolution"):
		threshold += 0.035
		if roll < threshold:
			return "binary_star"
	if progression.has_upgrade("comet_solutions"):
		threshold += 0.045
		if roll < threshold:
			return "comet"
	if progression.has_upgrade("variable_watchlist"):
		threshold += 0.05
		if roll < threshold:
			return "variable_star"
	if progression.has_upgrade("satellite_catalog"):
		threshold += 0.075
		if roll < threshold:
			return "satellite"
	if progression.has_upgrade("rare_detection"):
		threshold += 0.075
	if progression.has_upgrade("rare_detection") and roll < threshold:
		return "fireball"
	if progression.has_upgrade("fragment_analysis"):
		threshold += 0.175
	if progression.has_upgrade("fragment_analysis") and roll < threshold:
		return "fragment"
	if progression.has_upgrade("edge_detection"):
		threshold += 0.25
	if progression.has_upgrade("edge_detection") and roll < threshold:
		return "fast"
	return "common"


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
		"prediction": progression.has_upgrade("trajectory"),
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


func _on_fragment_requested(origin: Vector2, parent_velocity: Vector2, parent_type: String, parent_is_echo: bool, parent_is_leonid: bool = false, parent_is_perseid: bool = false) -> void:
	var piece_count := 4 if parent_type == "major" else 3
	var spread := 0.34 if parent_type == "major" else 0.25
	var burst_direction := parent_velocity.normalized()
	if burst_direction.is_zero_approx():
		burst_direction = Vector2.RIGHT
	var burst_speed := parent_velocity.length()
	# The parent is intentionally slow at its terminal split. Preserve the old
	# 245px/s fragment burst so the children read as released energy rather than
	# inheriting the parent's near-stall. Major fragments keep the finale speed.
	if parent_type != "major":
		burst_speed = maxf(burst_speed, float(Balance.meteor_spec("fragment").speed))
	var available_slots := maxi(0, (MAX_TOTAL_METEORS - 1) - meteor_layer.get_child_count())
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
