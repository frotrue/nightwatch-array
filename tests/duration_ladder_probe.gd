extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")

const ROUND_COUNT := 18
const STEP := 0.05
const SPAWN_SEED := 20260821
const ROWS := [
	{"name": "base", "duration": 20.0, "upgrades": []},
	{
		"name": "observation-scheduling", "duration": 30.0,
		"upgrades": ["array_planning", "observation_scheduling"],
	},
	{
		"name": "thermal-management", "duration": 40.0,
		"upgrades": [
			"array_planning", "observation_scheduling", "edge_detection",
			"wide_field", "thermal_management",
		],
	},
	{
		"name": "extended-watch", "duration": 50.0,
		"upgrades": [
			"array_planning", "observation_scheduling", "edge_detection",
			"wide_field", "thermal_management", "trajectory",
			"extended_watch_protocol",
		],
	},
	{
		"name": "continuous-rotation", "duration": 60.0,
		"upgrades": [
			"array_planning", "observation_scheduling", "edge_detection",
			"wide_field", "thermal_management", "trajectory",
			"extended_watch_protocol", "rare_detection",
			"continuous_watch_rotation",
		],
	},
	{"name": "completed-array", "duration": 60.0, "upgrades": [], "completed_tree": true},
]

var game
var row_name: String = ""
var round_announced: int = 0
var round_resolved: int = 0
var round_realized: int = 0
var round_completed: int = 0
var round_data: float = 0.0
var round_had_shower: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("DURATION_LADDER_PROBE_ENV engine=%s rounds_per_rung=%d step_seconds=%.2f seed=%d pacing_denominator=40" % [
		Engine.get_version_info(),
		ROUND_COUNT,
		STEP,
		SPAWN_SEED,
	])
	for row in ROWS:
		await _run_row(row)
	print("DURATION_LADDER_PROBE_COMPLETE")
	quit(0)


func _run_row(row: Dictionary) -> void:
	var round_duration := float(row.duration)
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare_row(row)
	var total_announced := 0
	var total_realized := 0
	var total_completed := 0
	var total_data := 0.0
	var shower_rounds := 0
	for round_number in range(1, ROUND_COUNT + 1):
		if round_number > 1:
			await _end_round_reset()
		_reset_round_metrics()
		game.spawner.set_phase_time_remaining(round_duration)
		game.spawner.start_spawning()
		game.events.start()
		var elapsed_in_round := 0.0
		while elapsed_in_round < round_duration:
			var remaining := maxf(0.0, round_duration - elapsed_in_round)
			game.spawner.set_phase_time_remaining(remaining)
			game.spawner._process(STEP)
			game.events._process(STEP)
			if game.sky_contacts.dish_active():
				game.sky_contacts._update_dishes(STEP)
			_process_meteors(STEP)
			elapsed_in_round += STEP
		if round_completed > round_realized:
			push_error("A cutoff object leaked into %s round %d" % [row_name, round_number])
			quit(1)
			return
		if game.events.shower_state != "idle":
			push_error("A shower crossed the %ds boundary in %s round %d" % [int(round_duration), row_name, round_number])
			quit(1)
			return
		var pending_announcements := maxi(0, round_announced - round_resolved)
		var unfinished_objects := maxi(0, round_realized - round_completed)
		print("DURATION_LADDER_PROBE row=%s duration=%d round=%02d announced=%d realized=%d completed=%d data=%.0f rate=%.1f pending_at_cutoff=%d unfinished_at_cutoff=%d shower=%s" % [
			row_name,
			int(round_duration),
			round_number,
			round_announced,
			round_realized,
			round_completed,
			round_data,
			round_data * 60.0 / round_duration,
			pending_announcements,
			unfinished_objects,
			"yes" if round_had_shower else "no",
		])
		total_announced += round_announced
		total_realized += round_realized
		total_completed += round_completed
		total_data += round_data
		shower_rounds += int(round_had_shower)
	var active_minutes := float(ROUND_COUNT) * round_duration / 60.0
	print("DURATION_LADDER_PROBE_SUMMARY row=%s duration=%d active_minutes=%.1f announced=%d realized=%d completed=%d data=%.0f data_per_min=%.2f shower_rounds=%d" % [
		row_name,
		int(round_duration),
		active_minutes,
		total_announced,
		total_realized,
		total_completed,
		total_data,
		total_data / active_minutes,
		shower_rounds,
	])
	game.free()
	game = null
	await process_frame


func _prepare_row(row: Dictionary) -> void:
	row_name = String(row.name)
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.sky_contacts.set_process(false)
	game.observer.set_process(false)
	game.events.reset()
	game.spawner.reset()
	game.progression.reset()
	var upgrades: Array = Array(row.get("upgrades", [])).duplicate()
	if bool(row.get("completed_tree", false)):
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
	game.spawner.rng.seed = SPAWN_SEED
	game.spawner.forecast_rng.seed = SPAWN_SEED + 1
	game.spawner.warm_contact_rng.seed = SPAWN_SEED + 2
	game.events.rng.seed = SPAWN_SEED + 3
	game.spawner.next_contact_id = 1
	game.events.run_time = 0.0


func _end_round_reset() -> void:
	game.events.pause_for_intermission()
	game.spawner.reset()
	game.sky_contacts.reset()
	game.sky_contacts.refresh_dishes()
	# Spawner.reset queues old sky objects for deletion. Flush that queue before
	# the next deterministic round so a cutoff object cannot complete in it.
	await process_frame


func _reset_round_metrics() -> void:
	round_announced = 0
	round_resolved = 0
	round_realized = 0
	round_completed = 0
	round_data = 0.0
	round_had_shower = false


func _on_contact_announced(contact: Dictionary) -> void:
	round_announced += 1
	if not game.sky_contacts.dish_active() or not _has_free_dish():
		return
	game.sky_contacts.assign_to_contact(int(contact.id))


func _on_contact_resolved(_contact: Dictionary, _meteor) -> void:
	round_resolved += 1


func _on_meteor_spawned(meteor) -> void:
	round_realized += 1
	meteor.observed.connect(_on_meteor_observed)


func _on_meteor_observed(_meteor, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	round_completed += 1
	round_data += game.progression.add_observation(reward, was_manual, multiplier)


func _on_shower_started() -> void:
	round_had_shower = true


func _has_free_dish() -> bool:
	for dish in game.sky_contacts.dishes:
		if int(dish.assigned_id) == -1 and game.sky_contacts._locked_target(dish) == null:
			return true
	return false


func _process_meteors(delta: float) -> void:
	var manual_target = _first_uncovered_meteor()
	for meteor in game.meteor_layer.get_children():
		if not is_instance_valid(meteor):
			continue
		if meteor == manual_target:
			meteor.apply_manual_observation(delta, 0.0, game.progression.get_tracking_radius())
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
