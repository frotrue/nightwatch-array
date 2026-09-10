extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")

const STEP := 0.05
const SEEDS := [20260821, 20260837, 20260853]
const SEEDS_ENV := "NIGHTWATCH_ECONOMY_SEEDS"
const STRATEGIES_ENV := "NIGHTWATCH_ECONOMY_STRATEGIES"
const DEFAULT_STRATEGIES := ["cheapest"]
const SURVEY_DRIVER_SPEED := 720.0
const WATCHDOG_SECONDS := 14400.0
const NO_ARRIVAL_REFERENCE_SECONDS := Balance.MAX_OBSERVATION_DURATION * 2.0
const EXPECTED_FINAL_VALUE_MULTIPLIER := 8192.0
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
const MILESTONE_NODES := [
	"better_lens",
	"polar_survey",
	"secondary_camera",
	"predictive_dish_control",
	"automated_tracking",
	"momentum_acquisition",
	"echo_correlation_10",
	"leonid_radiant",
	"sirius_fireball",
	"draco_synthesis",
	"galactic_reference_frame",
]

var game
var current_strategy := "cheapest"
var active_elapsed: float = 0.0
var research_completion_time: float = -1.0
var content_completion_time: float = -1.0
var completion_successes: int = -1
var completion_earned: float = -1.0
var completion_bank: float = -1.0
var checkpoint_successes: Dictionary = {}
var multiplier_purchase_times: Dictionary = {}
var reveal_times: Dictionary = {}
var seen_available_nodes: Dictionary = {}
var availability_times: Dictionary = {}
var affordable_times: Dictionary = {}
var purchase_times: Dictionary = {}
var last_arrival_time: float = 0.0
var longest_no_arrival: float = 0.0
var purchase_batches: Array[Dictionary] = []
var max_purchase_batch: int = 0
var arrival_gaps: Array[Dictionary] = []
var simulated_round_index: int = 0
var survey_driver_direction: int = 1
var survey_driver_cursor := Vector2(240.0, 420.0)
var manual_meteor_income: float = 0.0
var automatic_meteor_income: float = 0.0
var first_manual_completion_time: float = -1.0
var first_automatic_completion_time: float = -1.0
var round_reports: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_cost := 0
	for definition in Balance.UPGRADE_NODES:
		total_cost += int(definition.cost)
	var seeds := _seeds_from_environment()
	var strategies := _strategies_from_environment()
	print("FULL_TREE_ECONOMY_ENV engine=%s watchdog_seconds=%.0f no_arrival_reference_seconds=%.0f step_seconds=%.2f seeds=%s strategies=%s nodes=%d total_cost=%d" % [
		Engine.get_version_info(), WATCHDOG_SECONDS, NO_ARRIVAL_REFERENCE_SECONDS, STEP,
		str(seeds), str(strategies), Balance.UPGRADE_NODES.size(), total_cost,
	])
	var failed := false
	for strategy in strategies:
		var strategy_completion_times: Array[float] = []
		for seed in seeds:
			current_strategy = String(strategy)
			var result: Dictionary = await _run_seed(int(seed))
			_print_result(int(seed), result)
			if float(result.research_completion_time) >= 0.0:
				strategy_completion_times.append(float(result.research_completion_time))
			var errors := _validation_errors(result)
			if not errors.is_empty():
				failed = true
				push_error("FULL_TREE_ECONOMY_INVALID strategy=%s seed=%d errors=%s" % [current_strategy, int(seed), str(errors)])
		if not strategy_completion_times.is_empty():
			strategy_completion_times.sort()
			print("FULL_TREE_ECONOMY_SUMMARY strategy=%s samples=%d research_seconds_min=%.1f research_seconds_median=%.1f research_seconds_max=%.1f" % [
				String(strategy), strategy_completion_times.size(), strategy_completion_times.front(),
				_median(strategy_completion_times), strategy_completion_times.back(),
			])
	if failed:
		push_error("FULL_TREE_ECONOMY_FAIL: the current 95-node driver broke an economy lane, ledger, timeline, or the approved research-arrival contract")
		quit(1)
		return
	print("FULL_TREE_ECONOMY_PASS: active base research completed; manual/automatic income reconciled; research arrival gaps within contract")
	quit(0)


func _run_seed(seed: int) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare(seed)
	active_elapsed = 0.0
	research_completion_time = -1.0
	content_completion_time = -1.0
	completion_successes = -1
	completion_earned = -1.0
	completion_bank = -1.0
	checkpoint_successes.clear()
	multiplier_purchase_times.clear()
	for node_id in MULTIPLIER_NODES:
		multiplier_purchase_times[node_id] = -1.0
	reveal_times.clear()
	seen_available_nodes.clear()
	availability_times.clear()
	affordable_times.clear()
	purchase_times.clear()
	manual_meteor_income = 0.0
	automatic_meteor_income = 0.0
	first_manual_completion_time = -1.0
	first_automatic_completion_time = -1.0
	round_reports.clear()
	last_arrival_time = 0.0
	longest_no_arrival = 0.0
	purchase_batches.clear()
	max_purchase_batch = 0
	arrival_gaps.clear()
	simulated_round_index = 0
	_reset_survey_driver()
	_record_node_states()
	while (
		(not game.progression.is_research_complete())
		and active_elapsed < WATCHDOG_SECONDS
	):
		var round_duration: float = game.progression.get_observation_duration()
		await _run_round(round_duration)
		_record_node_states()
		if not game.progression.is_research_complete():
			_purchase_affordable_research()
		if game.progression.is_research_complete() and research_completion_time < 0.0:
			research_completion_time = active_elapsed
			completion_successes = game.progression.success_count
			completion_earned = game.progression.total_data_earned
			completion_bank = game.progression.observation_data
			longest_no_arrival = maxf(longest_no_arrival, research_completion_time - last_arrival_time)
		if research_completion_time < 0.0:
			longest_no_arrival = maxf(longest_no_arrival, active_elapsed - last_arrival_time)
	if game.progression.is_research_complete():
		content_completion_time = active_elapsed
	var next_candidate := _cheapest_available_research()
	var source_total := _source_income_total()
	var total_cost := _purchased_cost_total()
	var result := {
		"strategy": current_strategy,
		"purchased": game.progression.upgrade_level,
		"successes": game.progression.success_count,
		"earned": game.progression.total_data_earned,
		"bank": game.progression.observation_data,
		"research_completion_time": research_completion_time,
		"content_completion_time": content_completion_time,
		"completion_successes": completion_successes,
		"completion_earned": completion_earned,
		"completion_bank": completion_bank,
		"rounds": simulated_round_index,
		"checkpoints": checkpoint_successes.duplicate(true),
		"value_multiplier": game.progression.get_observation_value_multiplier("common", 1),
		"observation_span": game.progression.get_observation_span(),
		"next_node": String(next_candidate.get("id", "")),
		"next_cost": float(next_candidate.get("cost", 0.0)),
		"multiplier_times": multiplier_purchase_times.duplicate(true),
		"longest_multiplier_gap": _longest_multiplier_gap(),
		"max_purchase_batch": max_purchase_batch,
		"large_purchase_batches": _large_purchase_batches(),
		"arrival_gaps": arrival_gaps.duplicate(true),
		"longest_no_arrival": longest_no_arrival,
		"milestone_times": _milestone_purchase_times(),
		"top_reveal_to_available_gaps": _top_timeline_gaps(reveal_times, availability_times, 5),
		"top_cash_barriers": _top_timeline_gaps(availability_times, affordable_times, 5),
		"top_affordable_to_purchase_gaps": _top_timeline_gaps(affordable_times, purchase_times, 5),
		"top_available_to_purchase_gaps": _top_timeline_gaps(availability_times, purchase_times, 5),
		"longest_purchase_gap": _longest_purchase_gap(),
		"manual_meteor_income": manual_meteor_income,
		"automatic_meteor_income": automatic_meteor_income,
		"source_income_total": source_total,
		"purchased_cost_total": total_cost,
		"income_reconciliation_error": absf(game.progression.total_data_earned - source_total),
		"bank_reconciliation_error": absf(game.progression.total_data_earned - total_cost - game.progression.observation_data),
		"manual_income_share": _safe_ratio(manual_meteor_income, source_total),
		"automatic_income_share": _safe_ratio(automatic_meteor_income, source_total),
		"first_manual_completion_time": first_manual_completion_time,
		"first_automatic_completion_time": first_automatic_completion_time,
		"round_rate_summary": _round_rate_summary(),
		"timeline_counts": {
			"revealed": reveal_times.size(),
			"available": availability_times.size(),
			"affordable": affordable_times.size(),
			"purchased": purchase_times.size(),
		},
		"node_timelines": _node_timelines(),
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
	# The gate advances simulated minutes in milliseconds and does not measure
	# audio. Remove the runtime synth so queued WAV playbacks cannot outlive a seed.
	if game.sound != null and is_instance_valid(game.sound):
		game.sound.free()
		game.sound = null
	game.progression.reset()
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
	var game_banner_handler := Callable(game, "_on_event_banner")
	if game.events.banner_requested.is_connected(game_banner_handler):
		game.events.banner_requested.disconnect(game_banner_handler)


func _run_round(duration: float) -> void:
	simulated_round_index += 1
	var source_income_before := _source_income_total()
	game.progression.reset_manual_combo()
	game.survey.begin_round(simulated_round_index)
	_reset_survey_driver()
	game.spawner.set_phase_time_remaining(duration)
	game.spawner.start_spawning()
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
		if game.sky_contacts.dish_active():
			game.sky_contacts._update_dishes(delta)
		var manual_target_used := _process_targets(delta)
		_record_node_states()
		if not manual_target_used:
			_process_survey_gap(delta)
		else:
			# Model the same continuously held gesture as the observation controller.
			game.survey.set_scanning(false, survey_driver_cursor, true)
		round_elapsed += delta
		active_elapsed += delta
		_record_success_checkpoints()
	game.events.pause_for_intermission()
	game.spawner.reset()
	game.sky_contacts.reset()
	game.survey.end_round()
	game.sky_contacts.refresh_dishes()
	var round_income := _source_income_total() - source_income_before
	round_reports.append({
		"round": simulated_round_index,
		"end_time": active_elapsed,
		"duration": duration,
		"income": round_income,
		"rate_per_minute": round_income * 60.0 / maxf(duration, 0.001),
	})
	await process_frame


func _process_targets(delta: float) -> bool:
	var manual_target = _select_manual_target()
	if manual_target != null:
		var cursor_point := _manual_cursor_point(manual_target)
		_apply_manual_target(manual_target, cursor_point, delta)
		if game.progression.has_upgrade("multi_target_analysis"):
			for candidate in _all_manual_targets():
				if candidate == manual_target:
					continue
				_apply_manual_target(candidate, cursor_point, delta)
	for target in game.meteor_layer.get_children():
		if not is_instance_valid(target):
			continue
		target._process(delta)
		if not target.alive:
			target.free()
	return manual_target != null


func _select_manual_target():
	return _first_uncovered_target()


func _all_manual_targets() -> Array:
	var result: Array = []
	result.append_array(game.meteor_layer.get_children())
	return result


func _target_is_trackable(target) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.has_method("can_be_tracked")
		and target.can_be_tracked()
	)


func _manual_cursor_point(target) -> Vector2:
	if target != null and target.has_method("get_manual_contact_distance"):
		var radius: float = game.observation_view.screen_length_to_world(float(target.ring_radius_screen))
		var angle := float(target.arc_start) + float(target.arc_span) * 0.5
		return target.global_position + Vector2.from_angle(angle) * radius
	return target.global_position if target != null else Vector2.ZERO


func _apply_manual_target(target, cursor_point: Vector2, delta: float) -> bool:
	if not _target_is_trackable(target):
		return false
	var default_radius: float = game.observation_view.screen_length_to_world(game.progression.get_tracking_radius())
	var tracking_radius: float = target.get_tracking_radius(default_radius)
	var distance := (
		float(target.get_manual_contact_distance(cursor_point))
		if target.has_method("get_manual_contact_distance")
		else cursor_point.distance_to(target.global_position)
	)
	if distance > tracking_radius:
		return false
	target.apply_manual_observation(
		delta,
		distance,
		tracking_radius,
		game.progression.get_manual_analysis_speed_multiplier()
	)
	return true


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
	var final_reward: float = game.progression.add_observation(
		round(reward * research_multiplier),
		was_manual,
		multiplier * research_multiplier
	)
	if was_manual:
		manual_meteor_income += final_reward
		if first_manual_completion_time < 0.0:
			first_manual_completion_time = active_elapsed
	else:
		automatic_meteor_income += final_reward
		if first_automatic_completion_time < 0.0:
			first_automatic_completion_time = active_elapsed
	_record_node_states()
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


func _purchase_affordable_research() -> void:
	var batch_size := 0
	var batch_nodes: Array[String] = []
	var bank_before: float = game.progression.observation_data
	while true:
		var candidate := _next_purchase_candidate()
		if candidate.is_empty():
			break
		var candidate_id := String(candidate.id)
		if game.progression.request_purchase(candidate_id):
			purchase_times[candidate_id] = active_elapsed
			batch_size += 1
			batch_nodes.append(candidate_id)
			if candidate_id in MULTIPLIER_NODES:
				multiplier_purchase_times[candidate_id] = active_elapsed
			game.sky_contacts.refresh_dishes()
			game.spawner.refresh_active_features()
			game._sync_galactic_systems()
			_record_node_states()
		else:
			push_error("FULL_TREE_ECONOMY_PURCHASE_REJECTED strategy=%s node=%s time=%.1f" % [current_strategy, candidate_id, active_elapsed])
			break
	if batch_size > 0:
		purchase_batches.append({
			"time": active_elapsed,
			"count": batch_size,
			"bank_before": bank_before,
			"bank_after": game.progression.observation_data,
			"nodes": batch_nodes,
		})
		max_purchase_batch = maxi(max_purchase_batch, batch_size)


func _next_purchase_candidate() -> Dictionary:
	var candidate: Dictionary = {}
	var candidate_rank := 999
	var candidate_cost := INF
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var node_id := String(definition.id)
		if not game.progression.can_purchase(node_id):
			continue
		var rank := _strategy_rank(definition)
		var cost := float(definition.cost)
		if rank < candidate_rank or (rank == candidate_rank and cost < candidate_cost):
			candidate = definition
			candidate_rank = rank
			candidate_cost = cost
	return candidate


func _strategy_rank(definition: Dictionary) -> int:
	if current_strategy == "cheapest":
		return 0
	var branch := String(definition.get("branch", ""))
	var node_id := String(definition.id)
	var effect_type := String(definition.get("effect_type", ""))
	var is_automation := (
		effect_type == "automation"
		or branch == "network"
		or node_id in ["secondary_camera", "predictive_dish_control", "automated_tracking", "observatory_network", "draco_array"]
	)
	if current_strategy == "automation_first":
		return 0 if is_automation else 1
	if current_strategy == "manual_first":
		if branch in ["optics", "taurus", "lyra", "ursa_minor", "perseus"]:
			return 0
		return 2 if is_automation else 1
	return 0


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


func _record_node_states() -> void:
	var arriving_nodes: Array[String] = []
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var node_id := String(definition.id)
		if not reveal_times.has(node_id) and game.progression.is_node_revealed(node_id):
			reveal_times[node_id] = active_elapsed
		var state: String = game.progression.get_node_state(node_id)
		if state == "available":
			if not seen_available_nodes.has(node_id):
				seen_available_nodes[node_id] = true
				availability_times[node_id] = active_elapsed
				arriving_nodes.append(node_id)
			if not affordable_times.has(node_id) and game.progression.observation_data >= float(definition.cost):
				affordable_times[node_id] = active_elapsed
	if not arriving_nodes.is_empty():
		var arrival_gap := active_elapsed - last_arrival_time
		longest_no_arrival = maxf(longest_no_arrival, arrival_gap)
		if arrival_gap > Balance.MAX_OBSERVATION_DURATION + STEP:
			arrival_gaps.append({"time": active_elapsed, "gap": arrival_gap, "nodes": arriving_nodes})
		last_arrival_time = active_elapsed


func _milestone_purchase_times() -> Dictionary:
	var result := {}
	for node_id in MILESTONE_NODES:
		if purchase_times.has(node_id):
			result[node_id] = purchase_times[node_id]
	return result


func _node_timelines() -> Dictionary:
	var result := {}
	for definition_variant in Balance.UPGRADE_NODES:
		var node_id := String(Dictionary(definition_variant).id)
		result[node_id] = {
			"r": float(reveal_times.get(node_id, -1.0)),
			"a": float(availability_times.get(node_id, -1.0)),
			"f": float(affordable_times.get(node_id, -1.0)),
			"p": float(purchase_times.get(node_id, -1.0)),
		}
	return result


func _large_purchase_batches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for batch_variant in purchase_batches:
		var batch: Dictionary = batch_variant
		if int(batch.count) >= 5:
			result.append(batch.duplicate(true))
	return result


func _top_timeline_gaps(start_times: Dictionary, end_times: Dictionary, limit: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for node_id_variant in end_times:
		var node_id := String(node_id_variant)
		if not start_times.has(node_id):
			continue
		entries.append({
			"node": node_id,
			"gap": float(end_times[node_id]) - float(start_times[node_id]),
			"start": float(start_times[node_id]),
			"end": float(end_times[node_id]),
		})
	entries.sort_custom(_sort_gap_desc)
	if entries.size() > limit:
		entries.resize(limit)
	return entries


func _sort_gap_desc(left: Dictionary, right: Dictionary) -> bool:
	return float(left.gap) > float(right.gap)


func _longest_purchase_gap() -> float:
	var times: Array[float] = [0.0]
	for batch_variant in purchase_batches:
		var batch: Dictionary = batch_variant
		times.append(float(batch.time))
	if research_completion_time >= 0.0:
		times.append(research_completion_time)
	times.sort()
	var longest := 0.0
	for index in range(1, times.size()):
		longest = maxf(longest, times[index] - times[index - 1])
	return longest


func _source_income_total() -> float:
	return manual_meteor_income + automatic_meteor_income


func _purchased_cost_total() -> float:
	var result := 0.0
	for node_id_variant in game.progression.purchased_nodes:
		result += float(Balance.upgrade_definition(String(node_id_variant)).get("cost", 0.0))
	return result


func _round_rate_summary() -> Dictionary:
	if round_reports.is_empty():
		return {}
	var rates: Array[float] = []
	for report_variant in round_reports:
		var report: Dictionary = report_variant
		rates.append(float(report.rate_per_minute))
	rates.sort()
	return {
		"rounds": rates.size(),
		"minimum": rates.front(),
		"median": _median(rates),
		"maximum": rates.back(),
		"last": float(round_reports.back().rate_per_minute),
	}


func _validation_errors(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(result.purchased) != Balance.UPGRADE_NODES.size():
		errors.append("research_not_complete")
	if float(result.research_completion_time) < 0.0:
		errors.append("missing_research_completion_time")
	if not is_equal_approx(float(result.value_multiplier), EXPECTED_FINAL_VALUE_MULTIPLIER):
		errors.append("unexpected_global_value_multiplier")
	if not is_equal_approx(float(result.observation_span), 1.0):
		errors.append("unexpected_final_observation_span")
	if float(result.manual_meteor_income) <= 0.0 or float(result.automatic_meteor_income) <= 0.0:
		errors.append("meteor_income_lane_not_exercised")
	if float(result.income_reconciliation_error) > 0.5:
		errors.append("source_income_does_not_reconcile")
	if float(result.bank_reconciliation_error) > 0.5:
		errors.append("bank_does_not_reconcile")
	if float(result.bank) < 0.0:
		errors.append("negative_bank")
	if float(result.longest_no_arrival) > NO_ARRIVAL_REFERENCE_SECONDS + STEP:
		errors.append("research_arrival_gap_exceeds_design_contract")
	var counts: Dictionary = result.timeline_counts
	for key in ["revealed", "available", "affordable", "purchased"]:
		if int(counts.get(key, 0)) != Balance.UPGRADE_NODES.size():
			errors.append("incomplete_%s_timeline" % key)
	return errors


func _print_result(seed: int, result: Dictionary) -> void:
	print("ECONOMY_SEED ", seed, " ", JSON.stringify(result))


func _seeds_from_environment() -> Array[int]:
	var result: Array[int] = []
	var configured := OS.get_environment(SEEDS_ENV).strip_edges()
	if not configured.is_empty():
		for token in configured.split(",", false):
			var cleaned := String(token).strip_edges()
			if cleaned.is_valid_int():
				result.append(int(cleaned))
	if result.is_empty():
		result.assign(SEEDS)
	return result


func _strategies_from_environment() -> Array[String]:
	var result: Array[String] = []
	var configured := OS.get_environment(STRATEGIES_ENV).strip_edges()
	if not configured.is_empty():
		for token in configured.split(",", false):
			var strategy := String(token).strip_edges().to_lower()
			if strategy in ["cheapest", "automation_first", "manual_first"] and strategy not in result:
				result.append(strategy)
	if result.is_empty():
		result.assign(DEFAULT_STRATEGIES)
	return result


func _median(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	var middle := int(sorted_values.size() / 2)
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return (sorted_values[middle - 1] + sorted_values[middle]) * 0.5


func _safe_ratio(numerator: float, denominator: float) -> float:
	return numerator / denominator if denominator > 0.0 else 0.0
