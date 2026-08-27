extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const ComparisonStar = preload("res://scripts/comparison_star.gd")

const STEP := 0.05
const SEEDS := [20260821, 20260837, 20260853]
const SURVEY_DRIVER_SPEED := 720.0
const WATCHDOG_SECONDS := 14400.0
const MAX_NO_ARRIVAL_SECONDS := Balance.MAX_OBSERVATION_DURATION * 2.0
const EXPECTED_FINAL_VALUE_MULTIPLIER := 8192.0
const HOST_HARVEST_CONFIRMATIONS := 3
const MULTIPLIER_NODES := [
	"perfect_observation",
	"shower_detector",
	"taurus_full_gallop",
	"double_star_resolution",
	"perseid_outburst",
	"echo_delay_line",
	"galaxy_imaging",
	"fireball_tail",
	"draco_synthesis",
	"draco_apotheosis",
]

var game
var active_elapsed: float = 0.0
var completion_time: float = -1.0
var completion_successes: int = -1
var completion_earned: float = -1.0
var checkpoint_successes: Dictionary = {}
var multiplier_purchase_times: Dictionary = {}
var seen_available_nodes: Dictionary = {}
var availability_times: Dictionary = {}
var purchase_times: Dictionary = {}
var last_arrival_time: float = 0.0
var longest_no_arrival: float = 0.0
var purchase_batches: Array[Dictionary] = []
var max_purchase_batch: int = 0
var arrival_gaps: Array[Dictionary] = []
var simulated_round_index: int = 0
var survey_driver_direction: int = 1
var survey_driver_cursor := Vector2(240.0, 420.0)
var transit_income: float = 0.0
var m32_purchase_time: float = -1.0
var m110_purchase_time: float = -1.0
var post_m32_harvests: int = 0
var post_m110_harvests: int = 0
var galactic_observation_seconds: float = 0.0
var transit_cursor_seconds: float = 0.0
var meteor_cursor_seconds: float = 0.0
var max_local_group_purchase_batch: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_cost := 0
	for definition in Balance.UPGRADE_NODES:
		total_cost += int(definition.cost)
	print("FULL_TREE_ECONOMY_ENV engine=%s watchdog_seconds=%.0f max_no_arrival_seconds=%.0f step_seconds=%.2f seeds=%s nodes=%d total_cost=%d" % [
		Engine.get_version_info(), WATCHDOG_SECONDS, MAX_NO_ARRIVAL_SECONDS, STEP,
		str(SEEDS), Balance.UPGRADE_NODES.size(), total_cost,
	])
	var failed := false
	for seed in SEEDS:
		var result: Dictionary = await _run_seed(seed)
		print("FULL_TREE_ECONOMY_RESULT seed=%d purchased=%d/%d completion_seconds=%.1f successes=%d earned=%.0f bank=%.0f value_multiplier=%.2f next_node=%s next_cost=%.0f checkpoints=%s multiplier_times=%s longest_multiplier_gap=%.1f arrival_gaps=%s purchase_batches=%s max_purchase_batch=%d max_local_group_purchase_batch=%d longest_no_arrival=%.1f local_group_purchase_gaps=%s transit_income=%.0f post_m32_harvests=%d post_m32_rate_per_minute=%.3f post_m110_harvests=%d post_m110_rate_per_minute=%.3f galactic_observation_seconds=%.1f transit_cursor_seconds=%.1f meteor_cursor_seconds=%.1f transit_cursor_total_share=%.3f transit_cursor_busy_share=%.3f meteor_cursor_total_share=%.3f transit_metrics=%s" % [
			seed,
			int(result.purchased),
			Balance.UPGRADE_NODES.size(),
			float(result.completion_time),
			int(result.successes),
			float(result.earned),
			float(result.bank),
			float(result.value_multiplier),
			String(result.next_node),
			float(result.next_cost),
			str(result.checkpoints),
			str(result.multiplier_times),
			float(result.longest_multiplier_gap),
			str(result.arrival_gaps),
			str(result.purchase_batches),
			int(result.max_purchase_batch),
			int(result.max_local_group_purchase_batch),
			float(result.longest_no_arrival),
			str(result.local_group_purchase_gaps),
			float(result.transit_income),
			int(result.post_m32_harvests),
			float(result.post_m32_harvest_rate_per_minute),
			int(result.post_m110_harvests),
			float(result.post_m110_harvest_rate_per_minute),
			float(result.galactic_observation_seconds),
			float(result.transit_cursor_seconds),
			float(result.meteor_cursor_seconds),
			float(result.transit_cursor_total_share),
			float(result.transit_cursor_busy_share),
			float(result.meteor_cursor_total_share),
			str(result.transit_metrics),
		])
		if (
			int(result.purchased) != Balance.UPGRADE_NODES.size()
			or float(result.completion_time) < 0.0
			or float(result.longest_no_arrival) > MAX_NO_ARRIVAL_SECONDS + STEP
			or not is_equal_approx(float(result.value_multiplier), EXPECTED_FINAL_VALUE_MULTIPLIER)
			or not _all_local_group_gaps_within(Dictionary(result.local_group_purchase_gaps), 120.0 + STEP)
			or int(Dictionary(result.transit_metrics).get("harvests_at_confirmation_3", 0)) <= 0
			or int(result.post_m32_harvests) <= 0
			or int(result.post_m110_harvests) <= 0
			or float(result.transit_cursor_busy_share) >= 0.50
			or int(result.max_local_group_purchase_batch) > 1
			or float(result.transit_income) <= 0.0
		):
			failed = true
	if failed:
		push_error("FULL_TREE_ECONOMY_FAIL: completion, multiplier, or no-arrival invariant failed")
		quit(1)
		return
	print("FULL_TREE_ECONOMY_PASS: all %d research systems complete with x8192 value growth and no arrival gap above %.0f seconds" % [
		Balance.UPGRADE_NODES.size(), MAX_NO_ARRIVAL_SECONDS,
	])
	quit(0)


func _run_seed(seed: int) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare(seed)
	active_elapsed = 0.0
	completion_time = -1.0
	completion_successes = -1
	completion_earned = -1.0
	checkpoint_successes.clear()
	multiplier_purchase_times.clear()
	for node_id in MULTIPLIER_NODES:
		multiplier_purchase_times[node_id] = -1.0
	seen_available_nodes.clear()
	availability_times.clear()
	purchase_times.clear()
	transit_income = 0.0
	m32_purchase_time = -1.0
	m110_purchase_time = -1.0
	post_m32_harvests = 0
	post_m110_harvests = 0
	galactic_observation_seconds = 0.0
	transit_cursor_seconds = 0.0
	meteor_cursor_seconds = 0.0
	max_local_group_purchase_batch = 0
	last_arrival_time = 0.0
	longest_no_arrival = 0.0
	purchase_batches.clear()
	max_purchase_batch = 0
	arrival_gaps.clear()
	simulated_round_index = 0
	_reset_survey_driver()
	_record_available_arrivals()
	while not game.progression.is_research_complete() and active_elapsed < WATCHDOG_SECONDS:
		var round_duration: float = game.progression.get_observation_duration()
		await _run_round(round_duration)
		_record_available_arrivals()
		_purchase_affordable_research()
		if game.progression.is_research_complete():
			completion_time = active_elapsed
			completion_successes = game.progression.success_count
			completion_earned = game.progression.total_data_earned
			break
		longest_no_arrival = maxf(longest_no_arrival, active_elapsed - last_arrival_time)
	if completion_time >= 0.0:
		longest_no_arrival = maxf(longest_no_arrival, completion_time - last_arrival_time)
	var next_candidate := _cheapest_available_research()
	var result := {
		"purchased": game.progression.upgrade_level,
		"successes": game.progression.success_count,
		"earned": game.progression.total_data_earned,
		"bank": game.progression.observation_data,
		"completion_time": completion_time,
		"completion_successes": completion_successes,
		"completion_earned": completion_earned,
		"checkpoints": checkpoint_successes.duplicate(true),
		"value_multiplier": game.progression.get_observation_value_multiplier("common", 1),
		"next_node": String(next_candidate.get("id", "")),
		"next_cost": float(next_candidate.get("cost", 0.0)),
		"multiplier_times": multiplier_purchase_times.duplicate(true),
		"longest_multiplier_gap": _longest_multiplier_gap(),
		"purchase_batches": purchase_batches.duplicate(true),
		"max_purchase_batch": max_purchase_batch,
		"max_local_group_purchase_batch": max_local_group_purchase_batch,
		"arrival_gaps": arrival_gaps.duplicate(true),
		"longest_no_arrival": longest_no_arrival,
		"local_group_purchase_gaps": _local_group_purchase_gaps(),
		"transit_income": transit_income,
		"post_m32_harvests": post_m32_harvests,
		"post_m32_harvest_rate_per_minute": _harvest_rate_per_minute(post_m32_harvests, m32_purchase_time),
		"post_m110_harvests": post_m110_harvests,
		"post_m110_harvest_rate_per_minute": _harvest_rate_per_minute(post_m110_harvests, m110_purchase_time),
		"galactic_observation_seconds": galactic_observation_seconds,
		"transit_cursor_seconds": transit_cursor_seconds,
		"meteor_cursor_seconds": meteor_cursor_seconds,
		"transit_cursor_total_share": _safe_ratio(transit_cursor_seconds, galactic_observation_seconds),
		"transit_cursor_busy_share": _safe_ratio(transit_cursor_seconds, transit_cursor_seconds + meteor_cursor_seconds),
		"meteor_cursor_total_share": _safe_ratio(meteor_cursor_seconds, galactic_observation_seconds),
		"transit_metrics": game.host_stars.get_metrics(),
	}
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	return result


func _longest_multiplier_gap() -> float:
	var purchase_times: Array[float] = []
	for node_id in MULTIPLIER_NODES:
		var purchase_time := float(multiplier_purchase_times.get(node_id, -1.0))
		if purchase_time >= 0.0:
			purchase_times.append(purchase_time)
	purchase_times.sort()
	var longest_gap := 0.0
	for index in range(1, purchase_times.size()):
		longest_gap = maxf(longest_gap, purchase_times[index] - purchase_times[index - 1])
	return longest_gap


func _prepare(seed: int) -> void:
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.sky_contacts.set_process(false)
	game.observer.set_process(false)
	game.host_stars.set_process(false)
	# The gate advances simulated minutes in milliseconds and does not measure
	# audio. Remove the runtime synth so queued WAV playbacks cannot outlive a seed.
	if game.sound != null and is_instance_valid(game.sound):
		game.sound.free()
		game.sound = null
	game.progression.reset()
	game.host_stars.reset()
	game._sync_galactic_systems()
	game.events.reset()
	game.spawner.reset()
	game.spawner.rng.seed = seed
	game.spawner.forecast_rng.seed = seed + 1000
	game.spawner.warm_contact_rng.seed = seed + 2000
	game.events.rng.seed = seed + 3000
	game.spawner.echo_rng.seed = seed + 4000
	game.spawner.next_contact_id = 1
	var game_spawn_handler := Callable(game, "_on_meteor_spawned")
	if game.spawner.meteor_spawned.is_connected(game_spawn_handler):
		game.spawner.meteor_spawned.disconnect(game_spawn_handler)
	game.spawner.meteor_spawned.connect(_on_target_spawned)
	var game_rare_handler := Callable(game, "_on_rare_spawned")
	if game.spawner.rare_spawned.is_connected(game_rare_handler):
		game.spawner.rare_spawned.disconnect(game_rare_handler)
	var game_upgrade_handler := Callable(game, "_on_upgrade_purchased")
	if game.progression.upgrade_purchased.is_connected(game_upgrade_handler):
		game.progression.upgrade_purchased.disconnect(game_upgrade_handler)
	var game_confirmation_handler := Callable(game, "_on_transit_confirmed")
	if game.host_stars.transit_confirmed.is_connected(game_confirmation_handler):
		game.host_stars.transit_confirmed.disconnect(game_confirmation_handler)
	game.host_stars.transit_confirmed.connect(_on_transit_confirmed)
	var game_harvest_handler := Callable(game, "_on_host_harvested")
	if game.host_stars.host_harvested.is_connected(game_harvest_handler):
		game.host_stars.host_harvested.disconnect(game_harvest_handler)
	game.host_stars.host_harvested.connect(_on_host_harvested)
	var game_banner_handler := Callable(game, "_on_event_banner")
	if game.events.banner_requested.is_connected(game_banner_handler):
		game.events.banner_requested.disconnect(game_banner_handler)


func _run_round(duration: float) -> void:
	simulated_round_index += 1
	game.progression.reset_manual_combo()
	game.survey.begin_round(simulated_round_index)
	_reset_survey_driver()
	game.spawner.set_phase_time_remaining(duration)
	game.spawner.start_spawning()
	game.host_stars.begin_round()
	game.events.start()
	if game.progression.leonid_storm_ready() and game.spawner.try_start_leonid_storm():
		game.progression.consume_leonid_storm_charge()
	var round_elapsed := 0.0
	while round_elapsed < duration:
		var delta := minf(STEP, duration - round_elapsed)
		game.progression.update_manual_combo(delta)
		var remaining := maxf(0.0, duration - round_elapsed)
		game.spawner.set_phase_time_remaining(remaining)
		game.spawner._process(delta)
		game.events._process(delta)
		game.survey.advance_time(delta)
		game.host_stars.advance_time(delta)
		if game.sky_contacts.dish_active():
			game.sky_contacts._update_dishes(delta)
		_process_targets(delta)
		if _first_uncovered_target() == null:
			_process_survey_gap(delta)
		else:
			game.survey.set_scanning(false, survey_driver_cursor)
		round_elapsed += delta
		active_elapsed += delta
		_record_success_checkpoints()
	game.events.pause_for_intermission()
	game.host_stars.end_round()
	game.spawner.reset()
	game.sky_contacts.reset()
	game.survey.end_round()
	game.sky_contacts.refresh_dishes()
	await process_frame


func _process_targets(delta: float) -> void:
	var host_activity := false
	for star in game.host_stars.host_stars.duplicate():
		if not is_instance_valid(star) or not bool(star.is_hidden):
			continue
		for angle in [0.0, PI * 0.5, PI]:
			var direction: Vector2 = Vector2.from_angle(float(angle)) * game.observation_view.screen_length_to_world(80.0)
			game.host_stars.record_sweep_segment(star.global_position - direction, star.global_position + direction)
		host_activity = true
	for child in game.host_stars.get_children():
		if child is ComparisonStar and bool(child.correct):
			child.apply_manual_observation(
				delta,
				0.0,
				child.get_tracking_radius(game.progression.get_tracking_radius()),
				game.progression.get_manual_analysis_speed_multiplier()
			)
			host_activity = true
	for star in game.host_stars.host_stars.duplicate():
		if not is_instance_valid(star):
			continue
		if String(star.state) == "transiting" and not bool(star.comparison_locked):
			star.apply_manual_observation(
				delta,
				0.0,
				star.get_tracking_radius(game.progression.get_tracking_radius()),
				game.progression.get_manual_analysis_speed_multiplier()
			)
			host_activity = true
		elif String(star.state) == "idle" and int(star.confirmation_count) >= HOST_HARVEST_CONFIRMATIONS:
			star.arm_harvest()
			star.apply_manual_observation(
				delta,
				0.0,
				star.get_tracking_radius(game.progression.get_tracking_radius()),
				game.progression.get_manual_analysis_speed_multiplier()
			)
			host_activity = true
	var manual_target = null if host_activity else _first_uncovered_target()
	if game.progression.host_stars_unlocked():
		galactic_observation_seconds += delta
		if host_activity:
			transit_cursor_seconds += delta
		elif manual_target != null:
			meteor_cursor_seconds += delta
	for target in game.meteor_layer.get_children():
		if not is_instance_valid(target):
			continue
		if target == manual_target:
			target.apply_manual_observation(
				delta,
				0.0,
				game.progression.get_tracking_radius(),
				game.progression.get_manual_analysis_speed_multiplier()
			)
		target._process(delta)
		if not target.alive:
			target.free()


func _first_uncovered_target():
	var dish_locked_ids: Dictionary = {}
	for dish in game.sky_contacts.dishes:
		var locked_id := int(dish.locked_id)
		if locked_id != 0:
			dish_locked_ids[locked_id] = true
	for target in game.meteor_layer.get_children():
		if target.can_be_tracked() and not dish_locked_ids.has(target.get_instance_id()):
			return target
	return null


func _process_survey_gap(delta: float) -> void:
	if not game.progression.survey_enabled():
		return
	var endpoint_x := 930.0 if survey_driver_direction > 0 else 220.0
	var travel := SURVEY_DRIVER_SPEED * delta * float(survey_driver_direction)
	var next_x := survey_driver_cursor.x + travel
	if (survey_driver_direction > 0 and next_x >= endpoint_x) or (survey_driver_direction < 0 and next_x <= endpoint_x):
		next_x = endpoint_x
	var next_cursor := Vector2(next_x, survey_driver_cursor.y)
	game.survey.set_scanning(true, next_cursor)
	game.survey.apply_scan_segment(survey_driver_cursor, next_cursor, delta)
	survey_driver_cursor = next_cursor
	if is_equal_approx(next_x, endpoint_x):
		survey_driver_direction *= -1


func _reset_survey_driver() -> void:
	survey_driver_direction = 1
	survey_driver_cursor = Vector2(240.0, 420.0)


func _on_target_spawned(target) -> void:
	target.observed.connect(_on_target_observed)


func _on_target_observed(target, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	var active_target_count := 1
	for candidate in game.meteor_layer.get_children():
		if candidate.has_method("can_be_tracked") and candidate.can_be_tracked():
			active_target_count += 1
	var research_multiplier: float = game.progression.get_observation_value_multiplier(
		String(target.type_id), active_target_count
	)
	var reference_result: Dictionary = game.host_stars.record_meteor_observation(target.global_position)
	game.progression.add_observation(
		round(reward * research_multiplier * float(reference_result.get("multiplier", 1.0))),
		was_manual,
		multiplier * research_multiplier
	)
	var is_proc_target := (
		bool(target.get_meta("gemini_echo", false))
		or bool(target.get_meta("leonid_storm", false))
		or bool(target.get_meta("perseid_outburst", false))
		or bool(target.get_meta("polar_summoned", false))
	)
	if was_manual and not is_proc_target and not target.is_major():
		game.progression.record_leonid_manual_success()
		if game.progression.leonid_storm_ready() and game.spawner.try_start_leonid_storm():
			game.progression.consume_leonid_storm_charge()
	if not target.is_major():
		game.spawner.try_spawn_observation_echo(
			was_manual,
			is_proc_target,
			target
		)


func _on_transit_confirmed(_star, _confirmation_count: int, _projected_reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	game.progression.record_transit_confirmation(was_manual, multiplier)


func _on_host_harvested(_star, reward: float, _multiplier: float, _was_manual: bool, _quality_grade: String, _confirmation_count: int) -> void:
	var final_reward: float = game.progression.add_transit_harvest(
		round(reward * game.progression.get_transit_value_multiplier())
	)
	transit_income += final_reward
	if game.progression.has_upgrade("messier_32"):
		post_m32_harvests += 1
	if game.progression.has_upgrade("messier_110"):
		post_m110_harvests += 1


func _purchase_affordable_research() -> void:
	var batch_size := 0
	var batch_nodes: Array[String] = []
	var bank_before: float = game.progression.observation_data
	var purchased_one := true
	while purchased_one:
		purchased_one = false
		var candidate_id := ""
		var candidate_cost := INF
		for definition in Balance.UPGRADE_NODES:
			var node_id := String(definition.id)
			var cost := float(definition.cost)
			if game.progression.can_purchase(node_id) and cost < candidate_cost:
				candidate_id = node_id
				candidate_cost = cost
		if not candidate_id.is_empty():
			game.progression.request_purchase(candidate_id)
			purchase_times[candidate_id] = active_elapsed
			if candidate_id == "messier_32":
				m32_purchase_time = active_elapsed
			elif candidate_id == "messier_110":
				m110_purchase_time = active_elapsed
			batch_size += 1
			batch_nodes.append(candidate_id)
			if candidate_id in MULTIPLIER_NODES:
				multiplier_purchase_times[candidate_id] = active_elapsed
			game.sky_contacts.refresh_dishes()
			game.spawner.refresh_active_features()
			game._sync_galactic_systems()
			_record_available_arrivals()
			purchased_one = true
	if batch_size > 0:
		var local_group_batch_size := 0
		for node_id in batch_nodes:
			if String(Balance.upgrade_definition(node_id).get("branch", "")) == "local_group":
				local_group_batch_size += 1
		max_local_group_purchase_batch = maxi(max_local_group_purchase_batch, local_group_batch_size)
		purchase_batches.append({
			"time": active_elapsed,
			"count": batch_size,
			"bank_before": bank_before,
			"bank_after": game.progression.observation_data,
			"nodes": batch_nodes,
		})
		max_purchase_batch = maxi(max_purchase_batch, batch_size)


func _cheapest_available_research() -> Dictionary:
	var candidate: Dictionary = {}
	var candidate_cost := INF
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		var cost := float(definition.cost)
		if game.progression.get_node_state(node_id) == "available" and cost < candidate_cost:
			candidate = {"id": node_id, "cost": cost}
			candidate_cost = cost
	return candidate


func _record_success_checkpoints() -> void:
	for checkpoint in [270, 540, 810]:
		if active_elapsed >= float(checkpoint) and not checkpoint_successes.has(checkpoint):
			checkpoint_successes[checkpoint] = game.progression.success_count


func _record_available_arrivals() -> void:
	var arriving_nodes: Array[String] = []
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if seen_available_nodes.has(node_id) or game.progression.get_node_state(node_id) != "available":
			continue
		seen_available_nodes[node_id] = true
		availability_times[node_id] = active_elapsed
		arriving_nodes.append(node_id)
	if arriving_nodes.is_empty():
		return
	var arrival_gap := active_elapsed - last_arrival_time
	longest_no_arrival = maxf(longest_no_arrival, arrival_gap)
	if arrival_gap > Balance.MAX_OBSERVATION_DURATION + STEP:
		arrival_gaps.append({"time": active_elapsed, "gap": arrival_gap, "nodes": arriving_nodes})
	last_arrival_time = active_elapsed


func _local_group_purchase_gaps() -> Dictionary:
	var result := {}
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(definition.get("branch", "")) != "local_group":
			continue
		var node_id := String(definition.id)
		if availability_times.has(node_id) and purchase_times.has(node_id):
			result[node_id] = float(purchase_times[node_id]) - float(availability_times[node_id])
	return result


func _all_local_group_gaps_within(gaps: Dictionary, ceiling: float) -> bool:
	var local_group_count := 0
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(definition.get("branch", "")) != "local_group":
			continue
		local_group_count += 1
		var node_id := String(definition.id)
		if not gaps.has(node_id) or float(gaps[node_id]) > ceiling:
			return false
	return gaps.size() == local_group_count


func _harvest_rate_per_minute(harvest_count: int, start_time: float) -> float:
	if start_time < 0.0 or completion_time <= start_time:
		return 0.0
	return float(harvest_count) * 60.0 / (completion_time - start_time)


func _safe_ratio(numerator: float, denominator: float) -> float:
	return numerator / denominator if denominator > 0.0 else 0.0
