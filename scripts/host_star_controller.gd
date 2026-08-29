extends Node2D

signal transit_confirmed(star, confirmation_count, projected_reward, multiplier, was_manual, quality_grade)
signal host_harvested(star, reward, multiplier, was_manual, quality_grade, confirmation_count)
signal transit_missed(star_id)

const HostStar = preload("res://scripts/host_star.gd")
const ComparisonStar = preload("res://scripts/comparison_star.gd")
const MAX_HOST_STARS := 2
const MAX_ACTIVE_TRANSITS := 2
const REFERENCE_STAR_BONUS_SCREEN_RADIUS := 132.0
const REFERENCE_STAR_VALUE_MULTIPLIER := 1.25
const WEAK_REFERENCE_VALUE_MULTIPLIER := 1.10
const BASE_TRANSIT_REWARD := 180000000.0
const TRANSIT_WAIT_MIN := 8.0
const TRANSIT_WAIT_MAX := 12.0
const SECOND_TRANSIT_WAIT_MIN := 4.0
const SECOND_TRANSIT_WAIT_MAX := 6.0
const THIRD_TRANSIT_WAIT_MIN := 3.0
const THIRD_TRANSIT_WAIT_MAX := 5.0
const TRANSIT_WINDOW := 8.0
const DECOY_WINDOW := 4.0
const RESPAWN_MIN := 6.0
const RESPAWN_MAX := 8.0

var progression: Node
var observation_view: Camera2D
var host_star = null
var host_stars: Array = []
var running: bool = false
var next_star_id: int = 1
var next_transit_remaining: float = 0.0
var transit_remaining: float = 0.0
var respawn_remaining: float = 0.0
var respawn_elapsed: float = 0.0
var next_waits: Dictionary = {}
var window_times: Dictionary = {}
var rehide_times: Dictionary = {}
var opportunity_counts: Dictionary = {}
var respawn_queue: Array[float] = []
var profile_cursor: int = 0
var rng := RandomNumberGenerator.new()
var metrics: Dictionary = {}


func setup(progression_controller: Node, view: Camera2D = null) -> void:
	progression = progression_controller
	observation_view = view
	rng.seed = 0x4c4f43414c
	_reset_metrics()


func reset() -> void:
	running = false
	_clear_all_hosts()
	next_star_id = 1
	next_transit_remaining = 0.0
	transit_remaining = 0.0
	respawn_remaining = 0.0
	respawn_elapsed = 0.0
	respawn_queue.clear()
	profile_cursor = 0
	rng.seed = 0x4c4f43414c
	_reset_metrics()
	queue_redraw()


func refresh_unlock_state() -> void:
	if progression == null or not progression.host_stars_unlocked():
		_clear_all_hosts()
		respawn_queue.clear()
		_sync_compatibility()
		queue_redraw()
		return
	var desired := mini(MAX_HOST_STARS, progression.get_host_star_capacity())
	while host_stars.size() > desired:
		_remove_host(host_stars.back(), false)
	while host_stars.size() + respawn_queue.size() < desired:
		_spawn_host()
	_sync_compatibility()
	queue_redraw()


func begin_round() -> void:
	running = true
	refresh_unlock_state()
	for star in host_stars:
		if String(star.state) == "idle" and int(star.confirmation_count) < HostStar.MAX_CONFIRMATIONS and float(next_waits.get(_key(star), 0.0)) <= 0.0:
			_schedule_transit(star)
	_sync_compatibility()


func end_round() -> void:
	for star in host_stars.duplicate():
		if String(star.state) == "transiting":
			_miss_transit(star)
		elif String(star.state) == "decoy":
			_finish_decoy_window(star, false)
	running = false
	_sync_compatibility()


func advance_time(delta: float) -> void:
	if not running or progression == null or not progression.host_stars_unlocked():
		return
	var step := maxf(0.0, delta)
	_advance_respawns(step)
	for star in host_stars.duplicate():
		if not is_instance_valid(star):
			continue
		var key := _key(star)
		if bool(star.is_hidden):
			continue
		var rehide := float(rehide_times.get(key, 0.0))
		if rehide > 0.0 and not bool(star.manual_touched):
			rehide = maxf(0.0, rehide - step)
			rehide_times[key] = rehide
			if rehide <= 0.0:
				_rehide_host(star)
				continue
		match String(star.state):
			"idle":
				if int(star.confirmation_count) >= HostStar.MAX_CONFIRMATIONS:
					continue
				var wait := maxf(0.0, float(next_waits.get(key, 0.0)) - step)
				next_waits[key] = wait
				star.set_forecast(wait, maxf(wait, float(star.forecast_total)), _forecast_notches(star))
				if wait <= 0.0 and _active_window_count() < _active_capacity():
					_start_opportunity(star)
			"transiting", "decoy":
				var window := maxf(0.0, float(window_times.get(key, 0.0)) - step)
				window_times[key] = window
				var total_window := DECOY_WINDOW if String(star.state) == "decoy" else TRANSIT_WINDOW
				star.set_transit_phase(1.0 - window / total_window)
				if window <= 0.0:
					if String(star.state) == "decoy":
						_finish_decoy_window(star, false)
					else:
						_miss_transit(star)
	_sync_compatibility()


func record_sweep_segment(from: Vector2, to: Vector2) -> int:
	var revealed := 0
	var direction := from.direction_to(to)
	if direction.is_zero_approx():
		return 0
	for star in host_stars:
		if not bool(star.is_hidden):
			continue
		var radius: float = star.get_tracking_radius(_screen_length(36.0))
		if _distance_to_segment(star.global_position, from, to) > radius:
			continue
		if star.record_reveal_sweep(direction.angle()):
			revealed += 1
			var key := _key(star)
			rehide_times[key] = float(Dictionary(star.profile).get("rehide_seconds", 0.0))
			if float(next_waits.get(key, 0.0)) <= 0.0:
				_schedule_transit(star, 0.8)
	metrics.hidden_hosts_revealed = int(metrics.hidden_hosts_revealed) + revealed
	return revealed


func reference_bonus_for(world_position: Vector2) -> Dictionary:
	# Local Group targets no longer add a separate reference-star economy rule.
	# They are observed like every other target and pay their reward directly.
	return {"applied": false, "multiplier": 1.0, "star_id": 0, "normalized_distance": INF, "source": "none"}


func record_meteor_observation(world_position: Vector2) -> Dictionary:
	if not host_stars.is_empty():
		metrics.meteor_observations_while_host_live = int(metrics.meteor_observations_while_host_live) + 1
	var result := reference_bonus_for(world_position)
	if bool(result.applied):
		metrics.reference_bonus_observations = int(metrics.reference_bonus_observations) + 1
		if String(result.source) == "weak_chain":
			metrics.weak_reference_bonus_observations = int(metrics.weak_reference_bonus_observations) + 1
		elif _active_window_count() > 0:
			metrics.reference_bonuses_during_transit = int(metrics.reference_bonuses_during_transit) + 1
	return result


func get_host_by_id(star_id: int):
	for star in host_stars:
		if int(star.stable_star_id) == star_id:
			return star
	return null


func get_metrics() -> Dictionary:
	var result := metrics.duplicate(true)
	var live_observations := int(metrics.meteor_observations_while_host_live)
	result["meteor_reference_bonus_ratio"] = float(metrics.reference_bonus_observations) / float(live_observations) if live_observations > 0 else 0.0
	result["current_host_state"] = String(host_star.state) if host_star != null else "absent"
	result["current_host_count"] = host_stars.size()
	result["current_active_transits"] = _active_window_count()
	result["current_confirmations"] = int(host_star.confirmation_count) if host_star != null else 0
	result["available_profiles"] = _available_profile_ids()
	return result


func get_save_data() -> Dictionary:
	var saved_hosts: Array[Dictionary] = []
	for star in host_stars:
		var key := _key(star)
		saved_hosts.append({
			"host": star.get_save_data(),
			"next_wait": float(next_waits.get(key, 0.0)),
			"window": float(window_times.get(key, 0.0)),
			"rehide": float(rehide_times.get(key, 0.0)),
			"opportunities": int(opportunity_counts.get(key, 0)),
		})
	return {
		"next_star_id": next_star_id,
		"profile_cursor": profile_cursor,
		"respawn_queue": respawn_queue.duplicate(),
		"hosts": saved_hosts,
		"host": host_star.get_save_data() if host_star != null else {},
		"next_transit_remaining": next_transit_remaining,
		"transit_remaining": transit_remaining,
		"respawn_remaining": respawn_remaining,
		"respawn_elapsed": respawn_elapsed,
		"metrics": metrics.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_clear_all_hosts()
	next_star_id = maxi(1, int(data.get("next_star_id", 1)))
	profile_cursor = maxi(0, int(data.get("profile_cursor", 0)))
	respawn_queue.clear()
	var saved_respawns = data.get("respawn_queue", [])
	if saved_respawns is Array:
		for seconds_variant in saved_respawns:
			respawn_queue.append(clampf(float(seconds_variant), 0.0, RESPAWN_MAX))
	_reset_metrics()
	var saved_metrics = data.get("metrics", {})
	if saved_metrics is Dictionary:
		for key in metrics.keys():
			metrics[key] = saved_metrics.get(key, metrics[key])
	var saved_hosts = data.get("hosts", [])
	if progression != null and progression.host_stars_unlocked() and saved_hosts is Array and not saved_hosts.is_empty():
		for record_variant in saved_hosts:
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant
			var host_data = record.get("host", {})
			if not (host_data is Dictionary) or host_data.is_empty():
				continue
			var position_data = host_data.get("position", [])
			var star_id := int(host_data.get("stable_star_id", next_star_id))
			var saved_position := _host_position(star_id, host_stars.size())
			if position_data is Array and position_data.size() >= 2:
				saved_position = Vector2(float(position_data[0]), float(position_data[1]))
			var star = _create_host(star_id, saved_position, String(host_data.get("profile_id", "basic")))
			star.load_save_data(host_data)
			var key := _key(star)
			next_waits[key] = maxf(0.0, float(record.get("next_wait", 0.0)))
			window_times[key] = clampf(float(record.get("window", 0.0)), 0.0, TRANSIT_WINDOW)
			rehide_times[key] = maxf(0.0, float(record.get("rehide", 0.0)))
			opportunity_counts[key] = maxi(0, int(record.get("opportunities", 0)))
	else:
		_load_legacy_single_host(data)
	refresh_unlock_state()
	_sync_compatibility()
	queue_redraw()


func _load_legacy_single_host(data: Dictionary) -> void:
	if progression == null or not progression.host_stars_unlocked():
		return
	var host_data = data.get("host", {})
	if host_data is Dictionary and not host_data.is_empty():
		var star_id := int(host_data.get("stable_star_id", next_star_id))
		var position_data = host_data.get("position", [])
		var saved_position := _host_position(star_id, 0)
		if position_data is Array and position_data.size() >= 2:
			saved_position = Vector2(float(position_data[0]), float(position_data[1]))
		var star = _create_host(star_id, saved_position, String(host_data.get("profile_id", "basic")))
		star.load_save_data(host_data)
		next_waits[_key(star)] = maxf(0.0, float(data.get("next_transit_remaining", 0.0)))
		window_times[_key(star)] = clampf(float(data.get("transit_remaining", 0.0)), 0.0, TRANSIT_WINDOW)
	else:
		var legacy_respawn := clampf(float(data.get("respawn_remaining", 0.0)), 0.0, RESPAWN_MAX)
		if legacy_respawn > 0.0:
			respawn_queue.append(legacy_respawn)


func _advance_respawns(step: float) -> void:
	if not respawn_queue.is_empty():
		respawn_elapsed += step
	for index in range(respawn_queue.size() - 1, -1, -1):
		respawn_queue[index] = maxf(0.0, float(respawn_queue[index]) - step)
		if float(respawn_queue[index]) <= 0.0 and host_stars.size() < _host_capacity():
			respawn_queue.remove_at(index)
			_spawn_host(true)
	respawn_remaining = float(respawn_queue[0]) if not respawn_queue.is_empty() else 0.0


func _spawn_host(from_respawn: bool = false) -> void:
	if host_stars.size() >= _host_capacity():
		return
	var star_id := next_star_id
	next_star_id += 1
	var profile_id := _next_profile_id()
	var star = _create_host(star_id, _host_position(star_id, host_stars.size()), profile_id)
	metrics.hosts_spawned = int(metrics.hosts_spawned) + 1
	if from_respawn:
		metrics.respawn_count = int(metrics.respawn_count) + 1
		metrics.respawn_gap_total = float(metrics.respawn_gap_total) + respawn_elapsed
		metrics.last_respawn_gap = respawn_elapsed
	respawn_elapsed = 0.0
	_schedule_transit(star)


func _create_host(star_id: int, world_position: Vector2, profile_id: String):
	var star = HostStar.new()
	star.configure(star_id, world_position, BASE_TRANSIT_REWARD, observation_view)
	var profile: Dictionary = GameBalance.GALACTIC_OBSERVATION_PROFILES.get(profile_id, {})
	star.configure_profile(profile_id, profile)
	star.transit_completed.connect(_on_transit_completed)
	star.harvest_completed.connect(_on_harvest_completed)
	star.decoy_completed.connect(_on_decoy_completed)
	add_child(star)
	host_stars.append(star)
	next_waits[_key(star)] = 0.0
	window_times[_key(star)] = 0.0
	rehide_times[_key(star)] = 0.0
	opportunity_counts[_key(star)] = 0
	_sync_compatibility()
	return star


func _schedule_transit(star, override_wait: float = -1.0) -> void:
	if star == null or String(star.state) != "idle":
		return
	var confirmations := int(star.confirmation_count)
	if confirmations >= HostStar.MAX_CONFIRMATIONS:
		next_waits[_key(star)] = 0.0
		star.set_forecast(0.0, 0.0, 0)
		_sync_compatibility()
		return
	var wait := override_wait
	if wait < 0.0:
		match confirmations:
			0:
				wait = rng.randf_range(TRANSIT_WAIT_MIN, TRANSIT_WAIT_MAX)
			1:
				wait = rng.randf_range(SECOND_TRANSIT_WAIT_MIN, SECOND_TRANSIT_WAIT_MAX)
			_:
				wait = rng.randf_range(THIRD_TRANSIT_WAIT_MIN, THIRD_TRANSIT_WAIT_MAX)
		if bool(Dictionary(star.profile).get("burst", false)):
			wait = minf(wait, 2.0 + float(confirmations))
	next_waits[_key(star)] = wait
	star.set_forecast(wait, wait, _forecast_notches(star))
	metrics.transit_wait_count = int(metrics.transit_wait_count) + 1
	metrics.transit_wait_total = float(metrics.transit_wait_total) + wait
	metrics.last_transit_wait = wait
	_sync_compatibility()


func _start_opportunity(star) -> void:
	if star == null or bool(star.is_hidden) or String(star.state) != "idle" or int(star.confirmation_count) >= HostStar.MAX_CONFIRMATIONS:
		return
	var key := _key(star)
	opportunity_counts[key] = int(opportunity_counts.get(key, 0)) + 1
	star.begin_transit()
	window_times[key] = TRANSIT_WINDOW
	metrics.transits_started = int(metrics.transits_started) + 1


func _spawn_comparisons(star) -> void:
	_clear_comparisons_for(int(star.stable_star_id))
	var count := maxi(1, int(Dictionary(star.profile).get("comparison_candidates", 1)))
	var correct_index := int(star.stable_star_id) % count
	star.set_comparison_locked(true)
	for index in range(count):
		var comparison = ComparisonStar.new()
		var angle := -0.75 + float(index) * 1.5 / maxf(1.0, float(count - 1))
		var offset := Vector2.from_angle(angle) * _screen_length(54.0)
		var is_correct := index == correct_index
		var tint: Color = star.get_visual_color() if is_correct else Color("8eb9d8")
		comparison.configure(int(star.stable_star_id), star.position + offset, is_correct, tint, observation_view)
		comparison.comparison_completed.connect(_on_comparison_completed)
		add_child(comparison)
	metrics.comparison_windows_started = int(metrics.comparison_windows_started) + 1


func _on_comparison_completed(comparison) -> void:
	var star = get_host_by_id(int(comparison.host_id))
	if star == null:
		comparison.queue_free()
		return
	if bool(comparison.correct):
		star.set_comparison_locked(false)
		_clear_comparisons_for(int(star.stable_star_id))
		metrics.comparisons_locked = int(metrics.comparisons_locked) + 1
	else:
		comparison.reset_progress()
		metrics.wrong_comparisons = int(metrics.wrong_comparisons) + 1


func _miss_transit(star) -> void:
	if star == null or String(star.state) != "transiting":
		return
	var star_id := int(star.stable_star_id)
	star.cancel_transit()
	window_times[_key(star)] = 0.0
	_clear_comparisons_for(star_id)
	metrics.transits_missed = int(metrics.transits_missed) + 1
	_schedule_transit(star)
	transit_missed.emit(star_id)


func _finish_decoy_window(star, spoiled: bool) -> void:
	if star == null:
		return
	if String(star.state) == "decoy":
		star.cancel_decoy()
	window_times[_key(star)] = 0.0
	metrics.decoys_ignored = int(metrics.decoys_ignored) + (0 if spoiled else 1)
	metrics.decoys_spoiled = int(metrics.decoys_spoiled) + (1 if spoiled else 0)
	_schedule_transit(star, 1.4)


func _on_decoy_completed(star) -> void:
	_finish_decoy_window(star, true)


func _on_transit_completed(star, multiplier: float, was_manual: bool, quality_grade: String) -> void:
	if star not in host_stars:
		return
	window_times[_key(star)] = 0.0
	_clear_comparisons_for(int(star.stable_star_id))
	metrics.transits_completed = int(metrics.transits_completed) + 1
	metrics.confirmations_recorded = int(metrics.confirmations_recorded) + 1
	var confirmations := int(star.confirmation_count)
	var profile_multiplier := float(Dictionary(star.profile).get("reward_multiplier", 1.0))
	var reward: float = maxf(1.0, round(float(star.base_value) * multiplier * profile_multiplier))
	transit_confirmed.emit(star, confirmations, reward, multiplier, was_manual, quality_grade)
	host_harvested.emit(star, reward, multiplier * profile_multiplier, was_manual, quality_grade, confirmations)
	metrics.hosts_harvested = int(metrics.hosts_harvested) + 1
	metrics.harvest_reward_total = float(metrics.harvest_reward_total) + reward
	_remove_host(star, true)
	_sync_compatibility()


func _on_harvest_completed(star) -> void:
	if star not in host_stars:
		return
	var confirmations := int(star.confirmation_count)
	var multiplier: float = star.get_harvest_multiplier()
	var reward: float = star.get_harvest_reward()
	var quality_grade: String = star.get_harvest_quality_grade()
	metrics.hosts_harvested = int(metrics.hosts_harvested) + 1
	metrics.harvest_reward_total = float(metrics.harvest_reward_total) + reward
	metrics["harvests_at_confirmation_%d" % confirmations] = int(metrics.get("harvests_at_confirmation_%d" % confirmations, 0)) + 1
	host_harvested.emit(star, reward, multiplier, true, quality_grade, confirmations)
	_remove_host(star, true)
	_sync_compatibility()


func _remove_host(star, schedule_respawn: bool) -> void:
	if star == null:
		return
	var star_id := int(star.stable_star_id)
	var key := _key(star)
	_clear_comparisons_for(star_id)
	host_stars.erase(star)
	next_waits.erase(key)
	window_times.erase(key)
	rehide_times.erase(key)
	opportunity_counts.erase(key)
	if star.get_parent() == self:
		remove_child(star)
	star.queue_free()
	if schedule_respawn:
		respawn_queue.append(rng.randf_range(RESPAWN_MIN, RESPAWN_MAX))
		respawn_remaining = float(respawn_queue[0])
		respawn_elapsed = 0.0
	_sync_compatibility()


func _clear_comparisons_for(star_id: int) -> void:
	for child in get_children():
		if child is ComparisonStar and int(child.host_id) == star_id:
			remove_child(child)
			child.queue_free()
	var star = get_host_by_id(star_id)
	if star != null:
		star.set_comparison_locked(false)


func _rehide_host(star) -> void:
	_clear_comparisons_for(int(star.stable_star_id))
	if String(star.state) == "transiting":
		star.cancel_transit()
	elif String(star.state) == "decoy":
		star.cancel_decoy()
	star.set_hidden(true)
	next_waits[_key(star)] = 0.0
	window_times[_key(star)] = 0.0
	metrics.hosts_rehidden = int(metrics.hosts_rehidden) + 1


func _next_profile_id() -> String:
	var profiles := _available_profile_ids()
	if profiles.is_empty():
		return "basic"
	var profile_id := String(profiles[profile_cursor % profiles.size()])
	profile_cursor += 1
	return profile_id


func _available_profile_ids() -> Array[String]:
	if progression == null:
		return []
	return progression.get_galactic_host_profile_ids()


func _host_capacity() -> int:
	return mini(MAX_HOST_STARS, progression.get_host_star_capacity()) if progression != null else 1


func _active_capacity() -> int:
	return mini(MAX_ACTIVE_TRANSITS, progression.get_active_transit_capacity()) if progression != null else 1


func _active_window_count() -> int:
	var count := 0
	for star in host_stars:
		if String(star.state) in ["transiting", "decoy"]:
			count += 1
	return count


func _forecast_notches(star) -> int:
	var configured := int(Dictionary(star.profile).get("forecast_notches", 0))
	if configured <= 0:
		return 0
	return 1 if int(star.confirmation_count) > 0 else configured


func _host_position(star_id: int, slot_index: int) -> Vector2:
	var atmospheric := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if observation_view != null and observation_view.has_method("atmospheric_world_rect"):
		atmospheric = observation_view.atmospheric_world_rect()
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 0x484f5354 + star_id * 7919
	var x_band := Vector2(0.15, 0.48) if slot_index % 2 == 0 else Vector2(0.52, 0.85)
	return atmospheric.position + Vector2(
		atmospheric.size.x * seeded.randf_range(x_band.x, x_band.y),
		atmospheric.size.y * seeded.randf_range(0.16, 0.52)
	)


func _weak_reference_positions() -> Array[Vector2]:
	var visible := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if observation_view != null and observation_view.has_method("visible_world_rect"):
		visible = observation_view.visible_world_rect()
	return [
		visible.position + visible.size * Vector2(0.08, 0.23),
		visible.position + visible.size * Vector2(0.91, 0.31),
		visible.position + visible.size * Vector2(0.18, 0.72),
	]


func _draw() -> void:
	pass


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _screen_length(screen_pixels: float) -> float:
	if observation_view != null and observation_view.has_method("screen_length_to_world"):
		return observation_view.screen_length_to_world(screen_pixels)
	return screen_pixels


func _key(star) -> String:
	return str(int(star.stable_star_id))


func _sync_compatibility() -> void:
	host_star = host_stars[0] if not host_stars.is_empty() else null
	if host_star == null:
		next_transit_remaining = 0.0
		transit_remaining = 0.0
	else:
		next_transit_remaining = float(next_waits.get(_key(host_star), 0.0))
		transit_remaining = float(window_times.get(_key(host_star), 0.0))
	respawn_remaining = float(respawn_queue[0]) if not respawn_queue.is_empty() else 0.0


func _clear_all_hosts() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	host_stars.clear()
	host_star = null
	next_waits.clear()
	window_times.clear()
	rehide_times.clear()
	opportunity_counts.clear()


func _reset_metrics() -> void:
	metrics = {
		"hosts_spawned": 0,
		"hosts_harvested": 0,
		"harvests_at_confirmation_1": 0,
		"harvests_at_confirmation_2": 0,
		"harvests_at_confirmation_3": 0,
		"respawn_count": 0,
		"respawn_gap_total": 0.0,
		"last_respawn_gap": 0.0,
		"transit_wait_count": 0,
		"transit_wait_total": 0.0,
		"last_transit_wait": 0.0,
		"transits_started": 0,
		"transits_completed": 0,
		"transits_missed": 0,
		"confirmations_recorded": 0,
		"harvest_reward_total": 0.0,
		"meteor_observations_while_host_live": 0,
		"reference_bonus_observations": 0,
		"weak_reference_bonus_observations": 0,
		"reference_bonuses_during_transit": 0,
		"decoys_started": 0,
		"decoys_ignored": 0,
		"decoys_spoiled": 0,
		"comparison_windows_started": 0,
		"comparisons_locked": 0,
		"wrong_comparisons": 0,
		"hidden_hosts_revealed": 0,
		"hosts_rehidden": 0,
		"linked_candidates_abandoned": 0,
	}
