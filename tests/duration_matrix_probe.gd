extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")

const DURATIONS := [20.0, 30.0, 40.0, 50.0, 60.0]
const TIMELINE_SECONDS := 1080.0
const STEP := 0.05
const DEFAULT_SEED_COUNT := 5
const SEED_COUNT_ENV := "NIGHTWATCH_MATRIX_SEEDS"
const BASE_SEED := 20260821
const ROWS := [
	{"name": "opening", "upgrades": []},
	{"name": "wide-field", "upgrades": ["edge_detection", "array_planning", "observation_scheduling", "wide_field"]},
	{
		"name": "predictive-dish",
		"upgrades": [
			"edge_detection", "array_planning", "observation_scheduling", "wide_field", "trajectory",
			"secondary_camera", "predictive_dish_control",
		],
	},
	{"name": "completed-array", "upgrades": []},
]

var game
var current_row_name: String = ""
var round_announced: int = 0
var round_resolved: int = 0
var round_realized: int = 0
var round_completed: int = 0
var round_data: float = 0.0
var round_showers: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_count := _seed_count_from_environment()
	print("DURATION_MATRIX_ENV engine=%s timeline_seconds=%.0f step_seconds=%.2f seeds=%d base_seed=%d" % [
		Engine.get_version_info(),
		TIMELINE_SECONDS,
		STEP,
		seed_count,
		BASE_SEED,
	])
	for row_variant in ROWS:
		var row: Dictionary = row_variant
		for duration_variant in DURATIONS:
			await _run_cell(row, float(duration_variant), seed_count)
	print("DURATION_MATRIX_COMPLETE")
	quit(0)


func _run_cell(row: Dictionary, duration: float, seed_count: int) -> void:
	var rates: Array[float] = []
	var announced_total := 0
	var realized_total := 0
	var completed_total := 0
	var pending_cutoff_total := 0
	var unfinished_cutoff_total := 0
	var shower_total := 0
	var round_total := 0
	for seed_offset in range(seed_count):
		var result: Dictionary = await _run_timeline(row, duration, BASE_SEED + seed_offset)
		for rate_variant in result.rates:
			rates.append(float(rate_variant))
		announced_total += int(result.announced)
		realized_total += int(result.realized)
		completed_total += int(result.completed)
		pending_cutoff_total += int(result.pending_cutoff)
		unfinished_cutoff_total += int(result.unfinished_cutoff)
		shower_total += int(result.showers)
		round_total += int(result.rounds)
	# Some approved durations do not divide the nominal timeline exactly. Report
	# rates against the full rounds actually simulated, never the nominal target.
	var active_minutes := float(round_total) * duration / 60.0
	var mean_rate := _mean(rates)
	var rate_stddev := _sample_stddev(rates, mean_rate)
	var sorted_rates: Array[float] = rates.duplicate()
	sorted_rates.sort()
	print("DURATION_MATRIX row=%s duration=%02d rounds=%d mean_data_per_min=%.2f stddev=%.2f cv=%.3f p10=%.2f p50=%.2f p90=%.2f announced_per_min=%.2f realized_per_min=%.2f completed_per_min=%.2f pending_per_round=%.3f unfinished_per_round=%.3f showers_per_min=%.3f" % [
		String(row.name),
		int(duration),
		round_total,
		mean_rate,
		rate_stddev,
		0.0 if mean_rate <= 0.0 else rate_stddev / mean_rate,
		_percentile(sorted_rates, 0.10),
		_percentile(sorted_rates, 0.50),
		_percentile(sorted_rates, 0.90),
		float(announced_total) / active_minutes,
		float(realized_total) / active_minutes,
		float(completed_total) / active_minutes,
		float(pending_cutoff_total) / float(round_total),
		float(unfinished_cutoff_total) / float(round_total),
		float(shower_total) / active_minutes,
	])


func _run_timeline(row: Dictionary, duration: float, seed: int) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare_timeline(row, seed)
	var rates: Array[float] = []
	var announced_total := 0
	var realized_total := 0
	var completed_total := 0
	var pending_cutoff_total := 0
	var unfinished_cutoff_total := 0
	var shower_total := 0
	var round_count := int(round(TIMELINE_SECONDS / duration))
	for round_number in range(1, round_count + 1):
		if round_number > 1:
			await _reset_round()
		_reset_round_metrics()
		game.spawner.set_phase_time_remaining(duration)
		game.spawner.start_spawning()
		game.events.start()
		var step_count := int(round(duration / STEP))
		for step_index in range(step_count):
			var remaining := maxf(0.0, duration - float(step_index) * STEP)
			game.spawner.set_phase_time_remaining(remaining)
			game.spawner._process(STEP)
			game.events._process(STEP)
			if game.sky_contacts.dish_active():
				game.sky_contacts._update_dishes(STEP)
			_process_meteors(STEP)
		if round_completed > round_realized:
			push_error("A cutoff object leaked into %s/%ds round %d" % [current_row_name, int(duration), round_number])
			quit(1)
			return {}
		if game.events.shower_state != "idle":
			push_error("A shower crossed %s/%ds round %d" % [current_row_name, int(duration), round_number])
			quit(1)
			return {}
		rates.append(round_data * 60.0 / duration)
		announced_total += round_announced
		realized_total += round_realized
		completed_total += round_completed
		pending_cutoff_total += maxi(0, round_announced - round_resolved)
		unfinished_cutoff_total += maxi(0, round_realized - round_completed)
		shower_total += round_showers
	game.free()
	game = null
	await process_frame
	return {
		"rates": rates,
		"announced": announced_total,
		"realized": realized_total,
		"completed": completed_total,
		"pending_cutoff": pending_cutoff_total,
		"unfinished_cutoff": unfinished_cutoff_total,
		"showers": shower_total,
		"rounds": round_count,
	}


func _prepare_timeline(row: Dictionary, seed: int) -> void:
	current_row_name = String(row.name)
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.sky_contacts.set_process(false)
	game.observer.set_process(false)
	game.events.reset()
	game.spawner.reset()
	game.progression.reset()
	var upgrades: Array = row.upgrades
	if current_row_name == "completed-array":
		upgrades = []
		for definition in Balance.UPGRADE_NODES:
			upgrades.append(String(definition.id))
	for node_variant in upgrades:
		var node_id := String(node_variant)
		game.progression.purchased_nodes[node_id] = true
		game.progression.purchase_order.append(node_id)
	game.sky_contacts.refresh_dishes()
	game.spawner.refresh_active_features()
	var game_spawn_handler := Callable(game, "_on_meteor_spawned")
	if game.spawner.meteor_spawned.is_connected(game_spawn_handler):
		game.spawner.meteor_spawned.disconnect(game_spawn_handler)
	game.spawner.contact_announced.connect(_on_contact_announced)
	game.spawner.contact_resolved.connect(_on_contact_resolved)
	game.spawner.meteor_spawned.connect(_on_meteor_spawned)
	game.events.shower_started.connect(_on_shower_started)
	game.spawner.rng.seed = seed
	game.spawner.forecast_rng.seed = seed + 1000
	game.spawner.warm_contact_rng.seed = seed + 2000
	game.events.rng.seed = seed + 3000
	game.spawner.next_contact_id = 1
	game.events.run_time = 0.0


func _reset_round() -> void:
	game.events.pause_for_intermission()
	game.spawner.reset()
	game.sky_contacts.reset()
	game.sky_contacts.refresh_dishes()
	await process_frame


func _reset_round_metrics() -> void:
	round_announced = 0
	round_resolved = 0
	round_realized = 0
	round_completed = 0
	round_data = 0.0
	round_showers = 0


func _on_contact_announced(_contact: Dictionary) -> void:
	round_announced += 1


func _on_contact_resolved(_contact: Dictionary, _meteor) -> void:
	round_resolved += 1


func _on_meteor_spawned(meteor) -> void:
	round_realized += 1
	meteor.observed.connect(_on_meteor_observed)


func _on_meteor_observed(_meteor, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	round_completed += 1
	round_data += game.progression.add_observation(reward, was_manual, multiplier)


func _on_shower_started() -> void:
	round_showers += 1


func _process_meteors(delta: float) -> void:
	game.progression.update_manual_combo(delta)
	var manual_target = _first_uncovered_meteor()
	for meteor in game.meteor_layer.get_children():
		if not is_instance_valid(meteor):
			continue
		if meteor == manual_target:
			meteor.apply_manual_observation(
				delta,
				0.0,
				game.progression.get_tracking_radius(),
				game.progression.get_manual_analysis_speed_multiplier()
			)
		meteor._process(delta)
		if not meteor.alive:
			meteor.free()


func _first_uncovered_meteor():
	var dish_locked_ids: Dictionary = {}
	for dish in game.sky_contacts.dishes:
		var locked_id := int(dish.locked_id)
		if locked_id != 0:
			dish_locked_ids[locked_id] = true
	for meteor in game.meteor_layer.get_children():
		if meteor.can_be_tracked() and not dish_locked_ids.has(meteor.get_instance_id()):
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


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]


func _seed_count_from_environment() -> int:
	if not OS.has_environment(SEED_COUNT_ENV):
		return DEFAULT_SEED_COUNT
	var configured := OS.get_environment(SEED_COUNT_ENV).strip_edges()
	if not configured.is_valid_int():
		return DEFAULT_SEED_COUNT
	return clampi(configured.to_int(), 1, 50)
