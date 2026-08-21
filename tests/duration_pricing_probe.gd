extends SceneTree

const ProbeProgression = preload("res://scripts/progression_controller.gd")

const TIMELINE_SECONDS := 600.0
const STEP := 0.05
const DEFAULT_SEED_COUNT := 10
const SEED_COUNT_ENV := "NIGHTWATCH_PRICING_SEEDS"
const BASE_SEED := 20260821
const NODES := [
	{
		"id": "observation_scheduling",
		"before_duration": 20.0,
		"after_duration": 30.0,
		"before": ["array_planning"],
		"after": ["array_planning", "observation_scheduling"],
	},
	{
		"id": "thermal_management",
		"before_duration": 30.0,
		"after_duration": 40.0,
		"before": ["array_planning", "observation_scheduling", "edge_detection", "wide_field"],
		"after": ["array_planning", "observation_scheduling", "edge_detection", "wide_field", "thermal_management"],
	},
	{
		"id": "extended_watch_protocol",
		"before_duration": 40.0,
		"after_duration": 50.0,
		"before": [
			"array_planning", "observation_scheduling", "edge_detection", "wide_field",
			"thermal_management", "trajectory",
		],
		"after": [
			"array_planning", "observation_scheduling", "edge_detection", "wide_field",
			"thermal_management", "trajectory", "extended_watch_protocol",
		],
	},
	{
		"id": "continuous_watch_rotation",
		"before_duration": 50.0,
		"after_duration": 60.0,
		"before": [
			"array_planning", "observation_scheduling", "edge_detection", "wide_field",
			"thermal_management", "trajectory", "extended_watch_protocol", "rare_detection",
		],
		"after": [
			"array_planning", "observation_scheduling", "edge_detection", "wide_field",
			"thermal_management", "trajectory", "extended_watch_protocol", "rare_detection",
			"continuous_watch_rotation",
		],
	},
]

var game
var progression
var round_realized: int = 0
var round_completed: int = 0
var round_data: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_count := _seed_count_from_environment()
	print("DURATION_PRICING_ENV engine=%s timeline_seconds=%.0f step_seconds=%.2f seeds=%d pacing_denominator=20" % [
		Engine.get_version_info(),
		TIMELINE_SECONDS,
		STEP,
		seed_count,
	])
	for node_variant in NODES:
		var node: Dictionary = node_variant
		var before: Dictionary = await _measure_configuration(
			String(node.id) + "-before",
			float(node.before_duration),
			node.before,
			seed_count
		)
		var after: Dictionary = await _measure_configuration(
			String(node.id) + "-after",
			float(node.after_duration),
			node.after,
			seed_count
		)
		var marginal_total := float(after.mean_total) - float(before.mean_total)
		print("DURATION_PRICING_RESULT node=%s duration=%d_to_%d before_rate=%.2f after_rate=%.2f before_total=%.2f after_total=%.2f marginal_total=%.2f price_1_5_rounds=%.0f price_2_rounds=%.0f" % [
			String(node.id),
			int(node.before_duration),
			int(node.after_duration),
			float(before.mean_rate),
			float(after.mean_rate),
			float(before.mean_total),
			float(after.mean_total),
			marginal_total,
			marginal_total * 1.5,
			marginal_total * 2.0,
		])
	print("DURATION_PRICING_COMPLETE")
	quit(0)


func _measure_configuration(label: String, duration: float, upgrades: Array, seed_count: int) -> Dictionary:
	var totals: Array[float] = []
	var rates: Array[float] = []
	var realized_total := 0
	var completed_total := 0
	var round_total := 0
	for seed_offset in range(seed_count):
		var result: Dictionary = await _run_timeline(duration, upgrades, BASE_SEED + seed_offset)
		for value in result.totals:
			totals.append(float(value))
		for value in result.rates:
			rates.append(float(value))
		realized_total += int(result.realized)
		completed_total += int(result.completed)
		round_total += int(result.rounds)
	var mean_total := _mean(totals)
	var mean_rate := _mean(rates)
	var rate_stddev := _sample_stddev(rates, mean_rate)
	print("DURATION_PRICING_CELL label=%s duration=%d rounds=%d mean_total=%.2f mean_rate=%.2f rate_cv=%.3f realized_per_min=%.2f completed_per_min=%.2f" % [
		label,
		int(duration),
		round_total,
		mean_total,
		mean_rate,
		0.0 if mean_rate <= 0.0 else rate_stddev / mean_rate,
		float(realized_total) * 60.0 / (float(seed_count) * TIMELINE_SECONDS),
		float(completed_total) * 60.0 / (float(seed_count) * TIMELINE_SECONDS),
	])
	return {"mean_total": mean_total, "mean_rate": mean_rate}


func _run_timeline(duration: float, upgrades: Array, seed: int) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare_timeline(upgrades, seed)
	var totals: Array[float] = []
	var rates: Array[float] = []
	var realized_total := 0
	var completed_total := 0
	var round_count := int(round(TIMELINE_SECONDS / duration))
	for round_number in range(1, round_count + 1):
		if round_number > 1:
			await _reset_round()
		round_realized = 0
		round_completed = 0
		round_data = 0.0
		game.spawner.set_phase_time_remaining(duration)
		game.spawner.start_spawning()
		var step_count := int(round(duration / STEP))
		for step_index in range(step_count):
			game.spawner.set_phase_time_remaining(maxf(0.0, duration - float(step_index) * STEP))
			game.spawner._process(STEP)
			_process_meteors(STEP)
		if round_completed > round_realized:
			push_error("A cutoff object leaked into pricing round %d" % round_number)
			quit(1)
			return {}
		totals.append(round_data)
		rates.append(round_data * 60.0 / duration)
		realized_total += round_realized
		completed_total += round_completed
	game.free()
	game = null
	await process_frame
	return {
		"totals": totals,
		"rates": rates,
		"realized": realized_total,
		"completed": completed_total,
		"rounds": round_count,
	}


func _prepare_timeline(upgrades: Array, seed: int) -> void:
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.sky_contacts.set_process(false)
	game.observer.set_process(false)
	game.events.reset()
	game.spawner.reset()
	progression = ProbeProgression.new()
	progression.name = "PricingProbeProgression"
	game.add_child(progression)
	game.progression = progression
	game.spawner.progression = progression
	game.events.progression = progression
	game.sky_contacts.progression = progression
	game.observer.progression = progression
	for node_variant in upgrades:
		var node_id := String(node_variant)
		progression.purchased_nodes[node_id] = true
		progression.purchase_order.append(node_id)
	game.sky_contacts.refresh_dishes()
	game.spawner.refresh_active_features()
	var game_spawn_handler := Callable(game, "_on_meteor_spawned")
	if game.spawner.meteor_spawned.is_connected(game_spawn_handler):
		game.spawner.meteor_spawned.disconnect(game_spawn_handler)
	game.spawner.meteor_spawned.connect(_on_meteor_spawned)
	game.spawner.rng.seed = seed
	game.spawner.forecast_rng.seed = seed + 1000
	game.spawner.warm_contact_rng.seed = seed + 2000
	game.spawner.next_contact_id = 1


func _reset_round() -> void:
	game.spawner.reset()
	game.sky_contacts.reset()
	game.sky_contacts.refresh_dishes()
	await process_frame


func _on_meteor_spawned(meteor) -> void:
	round_realized += 1
	meteor.observed.connect(_on_meteor_observed)


func _on_meteor_observed(_meteor, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	round_completed += 1
	round_data += progression.add_observation(reward, was_manual, multiplier)


func _process_meteors(delta: float) -> void:
	var manual_target = _first_meteor()
	for meteor in game.meteor_layer.get_children():
		if not is_instance_valid(meteor):
			continue
		if meteor == manual_target:
			meteor.apply_manual_observation(delta, 0.0, progression.get_tracking_radius())
		meteor._process(delta)
		if not meteor.alive:
			meteor.free()


func _first_meteor():
	for meteor in game.meteor_layer.get_children():
		if meteor.can_be_tracked():
			return meteor
	return null


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _sample_stddev(values: Array[float], mean: float) -> float:
	if values.size() < 2:
		return 0.0
	var square_sum := 0.0
	for value in values:
		var difference := value - mean
		square_sum += difference * difference
	return sqrt(square_sum / float(values.size() - 1))


func _seed_count_from_environment() -> int:
	if not OS.has_environment(SEED_COUNT_ENV):
		return DEFAULT_SEED_COUNT
	var configured := OS.get_environment(SEED_COUNT_ENV).strip_edges()
	if not configured.is_valid_int():
		return DEFAULT_SEED_COUNT
	return clampi(configured.to_int(), 1, 50)
