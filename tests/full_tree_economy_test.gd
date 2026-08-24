extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")

const RUN_SECONDS := 1080.0
const STEP := 0.05
const SEEDS := [20260821, 20260837, 20260853]

var game
var active_elapsed: float = 0.0
var completion_time: float = -1.0
var completion_successes: int = -1
var completion_earned: float = -1.0
var checkpoint_successes: Dictionary = {}
var discovery_times: Dictionary = {}
var seen_available_nodes: Dictionary = {}
var last_arrival_time: float = 0.0
var longest_no_arrival: float = 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_cost := 0
	for definition in Balance.UPGRADE_NODES:
		total_cost += int(definition.cost)
	print("FULL_TREE_ECONOMY_ENV engine=%s run_seconds=%.0f step_seconds=%.2f seeds=%s nodes=%d total_cost=%d" % [
		Engine.get_version_info(), RUN_SECONDS, STEP, str(SEEDS),
		Balance.UPGRADE_NODES.size(), total_cost,
	])
	var failed := false
	for seed in SEEDS:
		var result: Dictionary = await _run_seed(seed)
		print("FULL_TREE_ECONOMY_RESULT seed=%d purchased=%d/%d final_successes=%d final_earned=%.0f bank=%.0f completion_seconds=%.1f completion_successes=%d completion_earned=%.0f checkpoints=%s discoveries=%s longest_no_arrival=%.1f" % [
			seed,
			int(result.purchased),
			Balance.UPGRADE_NODES.size(),
			int(result.successes),
			float(result.earned),
			float(result.bank),
			float(result.completion_time),
			int(result.completion_successes),
			float(result.completion_earned),
			str(result.checkpoints),
			str(result.discoveries),
			float(result.longest_no_arrival),
		])
		if int(result.purchased) != Balance.UPGRADE_NODES.size() or float(result.completion_time) < 0.0:
			failed = true
	if failed:
		push_error("FULL_TREE_ECONOMY_FAIL: at least one deterministic 18-minute run could not purchase all research")
		quit(1)
		return
	print("FULL_TREE_ECONOMY_PASS: all 41 research systems are purchasable before the 18-minute final event")
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
	discovery_times = {
		"radiant_plotting": -1.0,
		"filter_wheel": -1.0,
		"ephemeris_marks": -1.0,
	}
	seen_available_nodes.clear()
	last_arrival_time = 0.0
	longest_no_arrival = 0.0
	_record_available_arrivals()
	while active_elapsed < RUN_SECONDS:
		var round_duration: float = minf(
			game.progression.get_observation_duration(),
			RUN_SECONDS - active_elapsed
		)
		await _run_round(round_duration)
		_record_available_arrivals()
		_purchase_affordable_research()
		if completion_time < 0.0 and game.progression.upgrade_level == Balance.UPGRADE_NODES.size():
			completion_time = active_elapsed
			completion_successes = game.progression.success_count
			completion_earned = game.progression.total_data_earned
	longest_no_arrival = maxf(longest_no_arrival, RUN_SECONDS - last_arrival_time)
	var result := {
		"purchased": game.progression.upgrade_level,
		"successes": game.progression.success_count,
		"earned": game.progression.total_data_earned,
		"bank": game.progression.observation_data,
		"completion_time": completion_time,
		"completion_successes": completion_successes,
		"completion_earned": completion_earned,
		"checkpoints": checkpoint_successes.duplicate(true),
		"discoveries": discovery_times.duplicate(true),
		"longest_no_arrival": longest_no_arrival,
	}
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	return result


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
	game.events.reset()
	game.spawner.reset()
	game.spawner.rng.seed = seed
	game.spawner.forecast_rng.seed = seed + 1000
	game.spawner.warm_contact_rng.seed = seed + 2000
	game.events.rng.seed = seed + 3000
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
	game.spawner.contact_announced.connect(_on_contact_announced)


func _run_round(duration: float) -> void:
	game.spawner.set_phase_time_remaining(duration)
	game.spawner.start_spawning()
	game.events.start()
	var round_elapsed := 0.0
	while round_elapsed < duration:
		var delta := minf(STEP, duration - round_elapsed)
		var remaining := maxf(0.0, duration - round_elapsed)
		game.spawner.set_phase_time_remaining(remaining)
		game.spawner._process(delta)
		game.events._process(delta)
		if game.sky_contacts.dish_active():
			game.sky_contacts._update_dishes(delta)
		_process_targets(delta)
		round_elapsed += delta
		active_elapsed += delta
		_record_success_checkpoints()
	game.events.pause_for_intermission()
	game.spawner.reset()
	game.sky_contacts.reset()
	game.sky_contacts.refresh_dishes()
	await process_frame


func _process_targets(delta: float) -> void:
	var manual_target = _first_uncovered_target()
	for target in game.meteor_layer.get_children():
		if not is_instance_valid(target):
			continue
		if target == manual_target:
			target.apply_manual_observation(delta, 0.0, game.progression.get_tracking_radius())
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


func _on_contact_announced(contact: Dictionary) -> void:
	if not game.progression.dish_commitment_enabled():
		return
	for dish in game.sky_contacts.dishes:
		if int(dish.assigned_id) == -1 and game.sky_contacts._locked_target(dish) == null:
			game.sky_contacts.assign_to_contact(int(contact.id))
			return


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
	game.progression.add_observation(
		round(reward * research_multiplier),
		was_manual,
		multiplier * research_multiplier
	)


func _purchase_affordable_research() -> void:
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
			game.sky_contacts.refresh_dishes()
			game.spawner.refresh_active_features()
			_record_available_arrivals()
			purchased_one = true


func _record_success_checkpoints() -> void:
	for checkpoint in [270, 540, 810]:
		if active_elapsed >= float(checkpoint) and not checkpoint_successes.has(checkpoint):
			checkpoint_successes[checkpoint] = game.progression.success_count


func _record_available_arrivals() -> void:
	for definition in Balance.UPGRADE_NODES:
		var node_id := String(definition.id)
		if discovery_times.has(node_id) and float(discovery_times[node_id]) < 0.0 and game.progression.is_node_revealed(node_id):
			discovery_times[node_id] = active_elapsed
		if seen_available_nodes.has(node_id) or game.progression.get_node_state(node_id) != "available":
			continue
		seen_available_nodes[node_id] = true
		longest_no_arrival = maxf(longest_no_arrival, active_elapsed - last_arrival_time)
		last_arrival_time = active_elapsed
