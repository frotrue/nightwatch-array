extends SceneTree

const PROBE_DURATION := 30.0
const STEP := 1.0 / 60.0
const SPAWN_SEED := 20260821
const SPAWN_SEED_ENV := "NIGHTWATCH_CONTACT_PROBE_SEED"
const TYPE_BUCKETS := ["common", "fast", "fragment", "fragment_piece", "fireball", "satellite", "variable_star", "comet", "binary_star", "galaxy", "major"]
const MODE_NO_INPUT := "no-input"
const MODE_SCRIPTED_ENGAGED := "scripted-engaged"
const MODE_BASELINE_ENGAGED := "baseline-engaged"
const MODE_FAST_MANUAL_ONE_DISH := "fast-manual-placement-one-dish"
const MODE_FAST_MANUAL_TWO_DISH := "fast-manual-placement-two-dish"
const MODE_FAST_AUTO_ONE_DISH := "fast-predictive-auto-one-dish"
const MODE_FAST_AUTO_TWO_DISH := "fast-predictive-auto-two-dish"
const MODE_ALL_ELIGIBLE_TWO_DISH := "all-eligible-two-dish"
const MODE_FRAGMENT_ASSIGNED_ONE_DISH := "fragment-assigned-one-dish"
const MODE_SELECTOR_PARTNER_FIRST := "selector-partner-first"
const MODE_SELECTOR_BANK_FIRST := "selector-bank-first"
const ROWS := [
	{
		# This row is the literal no-upgrade opening state. It deliberately uses a
		# manual-only driver so measurement does not smuggle forecast research into
		# the baseline just to make the probe interact with a target.
		"name": "duration-ladder-start",
		"upgrades": [],
		"modes": [MODE_NO_INPUT, MODE_BASELINE_ENGAGED],
	},
	{
		# The original 52-node tree still owns the 51-node progression curve.
		# Later interaction branches do not dilute it; Canis instead changes the
		# explicit regular-arrival floor and active-contact cap at the endpoint.
		"name": "duration-ladder-end",
		"upgrades": [
			"better_lens", "long_exposure", "observation_streak",
			"precision_multiplier", "perfect_observation", "edge_detection",
			"wide_field", "trajectory", "rare_detection", "fragment_analysis",
			"shower_detector", "array_planning", "observation_scheduling",
			"thermal_management", "extended_watch_protocol",
			"continuous_watch_rotation", "secondary_camera",
			"predictive_dish_control", "multi_target_analysis",
			"automated_tracking", "observatory_network", "contact_ledger",
			"companion_resolution", "radiant_plotting", "crowd_forecast",
			"burst_windowing", "debris_correlation", "cascade_sampling",
			"adaptive_exposure_grid", "perseid_survey", "filter_wheel",
			"blue_band", "amber_band", "violet_band", "lyrid_spectrograph",
			"ephemeris_marks", "satellite_catalog", "change_detection",
			"variable_watchlist", "comet_solutions", "andromeda_deep_survey",
			"echo_correlation_10", "echo_correlation_20",
			"single_echo_channel", "dual_echo_channel", "triple_echo_array",
			"leonid_radiant", "compressed_cadence", "dense_stream",
			"rapid_reacquisition", "storm_front", "leonid_storm",
			"canis_opening", "canis_cadence_i", "canis_capacity_i",
			"canis_cadence_ii", "canis_capacity_ii", "canis_cadence_iii",
			"canis_capacity_iii", "sirius_fireball",
		],
		"modes": [MODE_NO_INPUT, MODE_SCRIPTED_ENGAGED],
	},
	{
		"name": "forecast-off",
		"upgrades": ["edge_detection"],
		"modes": [MODE_NO_INPUT, MODE_SCRIPTED_ENGAGED],
	},
	{
		"name": "wide-only",
		"upgrades": ["edge_detection", "array_planning", "observation_scheduling", "wide_field"],
		"modes": [MODE_NO_INPUT, MODE_SCRIPTED_ENGAGED],
	},
	{
		"name": "wide+dish",
		# Both capacity configurations own the predictive node's prerequisites;
		# the only control difference is Predictive Dish Control itself.
		"upgrades": ["edge_detection", "array_planning", "observation_scheduling", "wide_field", "trajectory", "secondary_camera"],
		"modes": [
			MODE_NO_INPUT,
			MODE_SCRIPTED_ENGAGED,
			# The historical 16-of-30 unassigned result belongs only to the
			# predictive assignment tier. Manual placement has no reservation.
			MODE_FAST_MANUAL_ONE_DISH,
			MODE_FAST_MANUAL_TWO_DISH,
			MODE_FAST_AUTO_ONE_DISH,
			MODE_FAST_AUTO_TWO_DISH,
		],
	},
	{
		# Direct node activation deliberately isolates one automatic lane without
		# the steerable dish that is normally its prerequisite.
		"name": "wide+one-lane",
		"upgrades": ["edge_detection", "array_planning", "observation_scheduling", "wide_field", "multi_target_analysis"],
		"modes": [MODE_NO_INPUT],
	},
	{
		"name": "all-eligible+dish",
		"upgrades": [
			"edge_detection", "array_planning", "observation_scheduling", "wide_field",
			"trajectory", "fragment_analysis", "secondary_camera", "predictive_dish_control",
		],
		"modes": [MODE_ALL_ELIGIBLE_TWO_DISH],
	},
	{
		"name": "fragment+dish",
		"upgrades": [
			"edge_detection", "array_planning", "observation_scheduling", "wide_field",
			"trajectory", "fragment_analysis", "secondary_camera", "predictive_dish_control",
		],
		"modes": [MODE_FRAGMENT_ASSIGNED_ONE_DISH],
	},
	{
		# Mid-tree configuration isolates the only disputed ordering: one dish and
		# one support lane, before global passive tracking makes every target a partner.
		"name": "selector+dish+lane",
		"upgrades": [
			"edge_detection", "array_planning", "observation_scheduling", "wide_field",
			"trajectory", "fragment_analysis", "secondary_camera",
			"predictive_dish_control", "multi_target_analysis",
		],
		"modes": [MODE_SELECTOR_PARTNER_FIRST, MODE_SELECTOR_BANK_FIRST],
	},
]

var game
var spawn_seed: int = SPAWN_SEED
var probe_mode: String = MODE_NO_INPUT
var announcements: int = 0
var resolutions: int = 0
var realized_objects: int = 0
var realized_objects_by_type: Dictionary = {}
var observations_completed: int = 0
var data_earned: float = 0.0
var visible_samples: Array[float] = []
var live_meteor_samples: Array[float] = []
var workload_samples: Array[float] = []
var slew_fractions: Array[float] = []
var assignment_elapsed: Dictionary = {}
var assignment_leads: Dictionary = {}
var acquired_ids: Dictionary = {}
var dish_acquisitions_by_type: Dictionary = {}
var dish_completions_by_type: Dictionary = {}
var manual_only_completions_by_type: Dictionary = {}
var dish_only_completions_by_type: Dictionary = {}
var shared_completions_by_type: Dictionary = {}
var automatic_only_completions_by_type: Dictionary = {}
var assigned_contact_ids: Dictionary = {}
var planned_target_ids: Dictionary = {}
var opportunistic_acquired_ids: Dictionary = {}
var opportunistic_completed_ids: Dictionary = {}
var opportunistic_dropped_ids: Dictionary = {}
var last_locked_by_dish: Array[int] = []
var dish_busy_steps: Array[int] = []
var total_steps: int = 0
var fast_contacts_announced: int = 0
var successful_fast_assignments: int = 0
var successful_fast_placements: int = 0
var unassigned_fast_contacts: int = 0
var fast_contacts_while_all_dishes_busy: int = 0
var eligible_contacts_announced: int = 0
var successful_eligible_assignments: int = 0
var unassigned_eligible_contacts: int = 0
var eligible_contacts_while_all_dishes_busy: int = 0
var lane_participated_ids: Dictionary = {}
var lane_covered_ids: Dictionary = {}
var lane_uncovered_ids: Dictionary = {}
var lane_completions_by_type: Dictionary = {}
var lane_covered_only_completions_by_type: Dictionary = {}
var lane_uncovered_only_completions_by_type: Dictionary = {}
var lane_mixed_completions_by_type: Dictionary = {}
var manually_positioned_dishes: Array[bool] = []
var manual_placement_count: int = 0
var manual_placement_acquired_ids: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	spawn_seed = _seed_from_environment()
	print("CONTACT_DENSITY_PROBE_ENV engine=%s duration_seconds=%.1f step_seconds=%.2f seed=%d" % [
		Engine.get_version_info(),
		PROBE_DURATION,
		STEP,
		spawn_seed,
	])
	print("CONTACT_DENSITY_PROBE_NOTE current_predictive_control=automatic-idle-dish-prepositioning legacy_reservation_rows_are_historical=true")
	for row in ROWS:
		for mode in row.modes:
			await _run_row(row, String(mode))
	print("CONTACT_DENSITY_PROBE_COMPLETE")
	quit(0)


func _run_row(row: Dictionary, mode: String) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	game.get_node("ModuleTutorial").enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare_row(row, mode)

	var elapsed := 0.0
	while elapsed < PROBE_DURATION:
		game.spawner.set_phase_time_remaining(PROBE_DURATION - elapsed)
		game.spawner.simulate_tick(STEP)
		_update_assignment_slew(STEP)
		if game.sky_contacts.dish_active():
			game.sky_contacts._update_dishes(STEP)
			_record_dish_acquisitions()
			_record_dish_lock_transitions()
		_record_lane_participation()
		_record_dish_busy_step()
		_process_meteors(STEP)
		var forecast_contacts := float(game.sky_contacts.contacts.size())
		var live_meteors := float(_live_meteor_count())
		# p50_visible/p95_visible historically meant forecast contacts only. Keep
		# that series intact and add explicit live/workload series rather than
		# relabeling old evidence as simultaneous meteors.
		visible_samples.append(forecast_contacts)
		live_meteor_samples.append(live_meteors)
		workload_samples.append(forecast_contacts + live_meteors)
		elapsed += STEP

	_record_open_assignments()
	_print_row(String(row.name), mode)
	game.free()
	game = null
	await process_frame


func _prepare_row(row: Dictionary, mode: String) -> void:
	probe_mode = mode
	announcements = 0
	resolutions = 0
	realized_objects = 0
	realized_objects_by_type.clear()
	observations_completed = 0
	data_earned = 0.0
	visible_samples.clear()
	live_meteor_samples.clear()
	workload_samples.clear()
	slew_fractions.clear()
	assignment_elapsed.clear()
	assignment_leads.clear()
	acquired_ids.clear()
	dish_acquisitions_by_type.clear()
	dish_completions_by_type.clear()
	manual_only_completions_by_type.clear()
	dish_only_completions_by_type.clear()
	shared_completions_by_type.clear()
	automatic_only_completions_by_type.clear()
	assigned_contact_ids.clear()
	planned_target_ids.clear()
	opportunistic_acquired_ids.clear()
	opportunistic_completed_ids.clear()
	opportunistic_dropped_ids.clear()
	last_locked_by_dish.clear()
	dish_busy_steps.clear()
	total_steps = 0
	fast_contacts_announced = 0
	successful_fast_assignments = 0
	successful_fast_placements = 0
	unassigned_fast_contacts = 0
	fast_contacts_while_all_dishes_busy = 0
	eligible_contacts_announced = 0
	successful_eligible_assignments = 0
	unassigned_eligible_contacts = 0
	eligible_contacts_while_all_dishes_busy = 0
	lane_participated_ids.clear()
	lane_covered_ids.clear()
	lane_uncovered_ids.clear()
	lane_completions_by_type.clear()
	lane_covered_only_completions_by_type.clear()
	lane_uncovered_only_completions_by_type.clear()
	lane_mixed_completions_by_type.clear()
	manually_positioned_dishes.clear()
	manual_placement_count = 0
	manual_placement_acquired_ids.clear()

	game.set_process(false)

	game.set_physics_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.sky_contacts.set_process(false)
	game.observer.set_process(false)
	game.events.reset()
	game.spawner.running = false
	for meteor in game.meteor_layer.get_children():
		meteor.free()
	game.spawner.pending_contacts.clear()
	game.sky_contacts.reset()
	game.progression.reset()
	for node_id in row.upgrades:
		game.progression.purchased_nodes[String(node_id)] = true
		game.progression.purchase_order.append(String(node_id))
	if _mode_uses_predictive_assignment(mode):
		for node_id in ["trajectory", "predictive_dish_control"]:
			if not game.progression.purchased_nodes.has(node_id):
				game.progression.purchased_nodes[node_id] = true
				game.progression.purchase_order.append(node_id)
	game.sky_contacts.refresh_dishes()
	game.spawner.set_bank_unsupported_before_dish(mode == MODE_SELECTOR_BANK_FIRST)
	if _mode_uses_two_dishes(mode):
		var size: Vector2 = game.sky_contacts.get_viewport_rect().size
		var home := Vector2(size.x * 0.62, size.y * 0.55)
		game.sky_contacts.dishes.append({
			"position": home,
			"target": home,
			"assigned_id": -1,
			"locked_id": 0,
			"arrived": true,
		})
	last_locked_by_dish.resize(game.sky_contacts.dishes.size())
	last_locked_by_dish.fill(0)
	dish_busy_steps.resize(game.sky_contacts.dishes.size())
	dish_busy_steps.fill(0)
	manually_positioned_dishes.resize(game.sky_contacts.dishes.size())
	manually_positioned_dishes.fill(false)

	var game_spawn_handler := Callable(game, "_on_meteor_spawned")
	if game.spawner.meteor_spawned.is_connected(game_spawn_handler):
		game.spawner.meteor_spawned.disconnect(game_spawn_handler)
	game.spawner.contact_announced.connect(_on_contact_announced)
	game.spawner.contact_resolved.connect(_on_contact_resolved)
	game.spawner.meteor_spawned.connect(_on_meteor_spawned)
	game.spawner.spawn_policy.reseed(spawn_seed)
	game.spawner.rng.seed = spawn_seed
	game.spawner.forecast_rng.seed = spawn_seed + 1
	game.spawner.warm_contact_rng.seed = spawn_seed + 2
	game.spawner.echo_rng.seed = spawn_seed + 3
	game.spawner.next_contact_id = 1
	game.spawner.set_phase_time_remaining(PROBE_DURATION)
	game.spawner.start_spawning()
	if game.progression.leonid_storm_ready() and game.spawner.try_start_leonid_storm():
		game.progression.consume_leonid_storm_charge()


func _on_contact_announced(contact: Dictionary) -> void:
	announcements += 1
	var type_id := String(contact.type_id)
	if type_id == "fast":
		fast_contacts_announced += 1
	if not game.sky_contacts.dish_active():
		return
	var all_eligible_mode: bool = _is_all_eligible_mode()
	var dish_eligible: bool = game.sky_contacts._dish_can_track_type(type_id)
	var fast_capacity_contact := _is_fast_capacity_mode() and type_id == "fast"
	if fast_capacity_contact:
		eligible_contacts_announced += 1
		if _all_dishes_busy():
			fast_contacts_while_all_dishes_busy += 1
			eligible_contacts_while_all_dishes_busy += 1
		if _is_manual_placement_capacity_mode():
			var placed_index: int = game.sky_contacts.move_dish_to(game.sky_contacts._estimate_of(contact))
			if placed_index < 0:
				unassigned_fast_contacts += 1
				unassigned_eligible_contacts += 1
				return
			manual_placement_count += 1
			successful_fast_placements += 1
			successful_eligible_assignments += 1
			manually_positioned_dishes[placed_index] = true
			return
	if all_eligible_mode and dish_eligible:
		eligible_contacts_announced += 1
		if _all_dishes_busy():
			eligible_contacts_while_all_dishes_busy += 1
	var should_assign: bool = (
		probe_mode == MODE_SCRIPTED_ENGAGED
		or fast_capacity_contact
		or (all_eligible_mode and dish_eligible)
		or (probe_mode == MODE_FRAGMENT_ASSIGNED_ONE_DISH and type_id == "fragment")
	)
	if not should_assign:
		return
	var contact_id := int(contact.id)
	if _dish_assigned_to_contact(contact_id) < 0:
		if fast_capacity_contact:
			unassigned_fast_contacts += 1
			unassigned_eligible_contacts += 1
		if all_eligible_mode and dish_eligible:
			unassigned_eligible_contacts += 1
		return
	assigned_contact_ids[contact_id] = type_id
	assignment_elapsed[contact_id] = 0.0
	assignment_leads[contact_id] = float(contact.lead_time)
	if fast_capacity_contact:
		successful_fast_assignments += 1
		successful_eligible_assignments += 1
	if all_eligible_mode and dish_eligible:
		successful_eligible_assignments += 1


func _on_contact_resolved(contact: Dictionary, meteor) -> void:
	resolutions += 1
	_record_slew_fraction(int(contact.id))
	if meteor != null and assigned_contact_ids.has(int(contact.id)):
		planned_target_ids[meteor.get_instance_id()] = int(contact.id)


func _on_meteor_spawned(meteor) -> void:
	realized_objects += 1
	_increment_type_count(realized_objects_by_type, String(meteor.type_id))
	meteor.observed.connect(_on_meteor_observed)


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	observations_completed += 1
	var type_id := String(meteor.type_id)
	var dish_participated := acquired_ids.has(meteor.get_instance_id())
	if dish_participated:
		_increment_type_count(dish_completions_by_type, type_id)
	if was_manual and dish_participated:
		_increment_type_count(shared_completions_by_type, type_id)
	elif was_manual:
		_increment_type_count(manual_only_completions_by_type, type_id)
	elif dish_participated:
		_increment_type_count(dish_only_completions_by_type, type_id)
	else:
		_increment_type_count(automatic_only_completions_by_type, type_id)
	var meteor_id: int = meteor.get_instance_id()
	if lane_participated_ids.has(meteor_id):
		_increment_type_count(lane_completions_by_type, type_id)
		var had_covered_lane := lane_covered_ids.has(meteor_id)
		var had_uncovered_lane := lane_uncovered_ids.has(meteor_id)
		if had_covered_lane and had_uncovered_lane:
			_increment_type_count(lane_mixed_completions_by_type, type_id)
		elif had_covered_lane:
			_increment_type_count(lane_covered_only_completions_by_type, type_id)
		else:
			_increment_type_count(lane_uncovered_only_completions_by_type, type_id)
	if opportunistic_acquired_ids.has(meteor_id):
		opportunistic_completed_ids[meteor_id] = type_id
	data_earned += game.progression.add_observation(reward, was_manual, multiplier)
	var is_proc_meteor := (
		bool(meteor.get_meta("gemini_echo", false))
		or bool(meteor.get_meta("leonid_storm", false))
		or bool(meteor.get_meta("perseid_outburst", false))
	)
	if was_manual and not is_proc_meteor and not meteor.is_major():
		game.progression.record_leonid_manual_success()
		if game.progression.leonid_storm_ready() and game.spawner.try_start_leonid_storm():
			game.progression.consume_leonid_storm_charge()
	if not meteor.is_major():
		game.spawner.try_spawn_observation_echo(
			was_manual,
			is_proc_meteor,
			meteor
		)


func _is_fast_capacity_mode() -> bool:
	return probe_mode in [
		MODE_FAST_MANUAL_ONE_DISH,
		MODE_FAST_MANUAL_TWO_DISH,
		MODE_FAST_AUTO_ONE_DISH,
		MODE_FAST_AUTO_TWO_DISH,
	]


func _is_manual_placement_capacity_mode() -> bool:
	return probe_mode in [MODE_FAST_MANUAL_ONE_DISH, MODE_FAST_MANUAL_TWO_DISH]


func _mode_uses_predictive_assignment(mode: String) -> bool:
	return mode in [
		MODE_SCRIPTED_ENGAGED,
		MODE_FAST_AUTO_ONE_DISH,
		MODE_FAST_AUTO_TWO_DISH,
		MODE_ALL_ELIGIBLE_TWO_DISH,
		MODE_FRAGMENT_ASSIGNED_ONE_DISH,
		MODE_SELECTOR_PARTNER_FIRST,
		MODE_SELECTOR_BANK_FIRST,
	]


func _is_all_eligible_mode() -> bool:
	return probe_mode in [
		MODE_ALL_ELIGIBLE_TWO_DISH,
		MODE_SELECTOR_PARTNER_FIRST,
		MODE_SELECTOR_BANK_FIRST,
	]


func _mode_uses_two_dishes(mode: String) -> bool:
	return mode in [
		MODE_FAST_MANUAL_TWO_DISH,
		MODE_FAST_AUTO_TWO_DISH,
		MODE_ALL_ELIGIBLE_TWO_DISH,
	]


func _dish_assigned_to_contact(contact_id: int) -> int:
	for index in range(game.sky_contacts.dishes.size()):
		if int(game.sky_contacts.dishes[index].assigned_id) == contact_id:
			return index
	return -1


func _has_free_dish() -> bool:
	for dish in game.sky_contacts.dishes:
		if int(dish.assigned_id) == -1 and game.sky_contacts._locked_target(dish) == null:
			return true
	return false


func _all_dishes_busy() -> bool:
	return not game.sky_contacts.dishes.is_empty() and not _has_free_dish()


func _update_assignment_slew(delta: float) -> void:
	for contact_id in assignment_elapsed.keys():
		assignment_elapsed[contact_id] = float(assignment_elapsed[contact_id]) + delta
	for dish in game.sky_contacts.dishes:
		var contact_id := int(dish.assigned_id)
		if contact_id >= 0 and bool(dish.arrived):
			_record_slew_fraction(contact_id)


func _record_slew_fraction(contact_id: int) -> void:
	if not assignment_elapsed.has(contact_id):
		return
	var lead: float = maxf(float(assignment_leads.get(contact_id, 0.0)), 0.001)
	slew_fractions.append(clampf(float(assignment_elapsed[contact_id]) / lead, 0.0, 1.0))
	assignment_elapsed.erase(contact_id)
	assignment_leads.erase(contact_id)


func _record_open_assignments() -> void:
	for contact_id in assignment_elapsed.keys():
		_record_slew_fraction(int(contact_id))


func _record_dish_acquisitions() -> void:
	for dish_index in range(game.sky_contacts.dishes.size()):
		var dish: Dictionary = game.sky_contacts.dishes[dish_index]
		var locked_id := int(dish.locked_id)
		if locked_id == 0 or acquired_ids.has(locked_id):
			continue
		var target = instance_from_id(locked_id)
		if target != null and is_instance_valid(target) and target.can_be_tracked():
			var type_id := String(target.type_id)
			acquired_ids[locked_id] = type_id
			_increment_type_count(dish_acquisitions_by_type, type_id)
			if not planned_target_ids.has(locked_id):
				opportunistic_acquired_ids[locked_id] = type_id
				if dish_index < manually_positioned_dishes.size() and manually_positioned_dishes[dish_index]:
					manual_placement_acquired_ids[locked_id] = type_id


func _record_dish_lock_transitions() -> void:
	for index in range(game.sky_contacts.dishes.size()):
		var current_id := int(game.sky_contacts.dishes[index].locked_id)
		var previous_id := last_locked_by_dish[index]
		if previous_id != 0 and previous_id != current_id:
			if (
				opportunistic_acquired_ids.has(previous_id)
				and not opportunistic_completed_ids.has(previous_id)
			):
				opportunistic_dropped_ids[previous_id] = opportunistic_acquired_ids[previous_id]
		last_locked_by_dish[index] = current_id


func _record_dish_busy_step() -> void:
	total_steps += 1
	for index in range(game.sky_contacts.dishes.size()):
		var dish: Dictionary = game.sky_contacts.dishes[index]
		if int(dish.assigned_id) >= 0 or int(dish.locked_id) != 0 or not bool(dish.arrived):
			dish_busy_steps[index] += 1


func _record_lane_participation() -> void:
	for meteor in game.meteor_layer.get_children():
		if not is_instance_valid(meteor) or not meteor.can_be_tracked():
			continue
		if float(meteor.lane_assist_rate) <= 0.0:
			continue
		var meteor_id: int = meteor.get_instance_id()
		var type_id := String(meteor.type_id)
		lane_participated_ids[meteor_id] = type_id
		if float(meteor.dish_assist_rate) > 0.0:
			lane_covered_ids[meteor_id] = type_id
		else:
			lane_uncovered_ids[meteor_id] = type_id


func _increment_type_count(counts: Dictionary, type_id: String) -> void:
	counts[type_id] = int(counts.get(type_id, 0)) + 1


func _type_counts_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for type_id in TYPE_BUCKETS:
		parts.append("%s:%d" % [type_id, int(counts.get(type_id, 0))])
	return "|".join(parts)


func _dish_conversion_text() -> String:
	var parts: PackedStringArray = []
	for type_id in TYPE_BUCKETS:
		parts.append("%s:%d/%d" % [
			type_id,
			int(dish_completions_by_type.get(type_id, 0)),
			int(dish_acquisitions_by_type.get(type_id, 0)),
		])
	return "|".join(parts)


func _lane_conversion_text() -> String:
	var participated_by_type := _counts_by_recorded_type(lane_participated_ids)
	var parts: PackedStringArray = []
	for type_id in TYPE_BUCKETS:
		parts.append("%s:%d/%d" % [
			type_id,
			int(lane_completions_by_type.get(type_id, 0)),
			int(participated_by_type.get(type_id, 0)),
		])
	return "|".join(parts)


func _dish_busy_fraction_text() -> String:
	var parts: PackedStringArray = []
	for index in range(dish_busy_steps.size()):
		parts.append("%d:%.3f" % [
			index,
			0.0 if total_steps == 0 else float(dish_busy_steps[index]) / float(total_steps),
		])
	return "none" if parts.is_empty() else "|".join(parts)


func _process_meteors(delta: float) -> void:
	game.progression.update_manual_combo(delta)
	var manual_target = null
	if probe_mode in [MODE_SCRIPTED_ENGAGED, MODE_BASELINE_ENGAGED]:
		manual_target = _first_uncovered_meteor()
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
		meteor.simulate_tick(delta)
		if not meteor.alive:
			meteor.free()


func _live_meteor_count() -> int:
	var count := 0
	for meteor in game.meteor_layer.get_children():
		if is_instance_valid(meteor) and meteor.can_be_tracked():
			count += 1
	return count


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


func _dish_control_text() -> String:
	if game.sky_contacts.dishes.is_empty():
		return "none"
	if _is_manual_placement_capacity_mode():
		return "manual-point-placement-no-reservation"
	if _mode_uses_predictive_assignment(probe_mode):
		return "predictive-automatic-prepositioning"
	return "none"


func _capacity_evidence_scope_text() -> String:
	if _is_manual_placement_capacity_mode():
		return "new-baseline"
	if probe_mode in [MODE_FAST_AUTO_ONE_DISH, MODE_FAST_AUTO_TWO_DISH]:
		return "legacy-comparable-researched-tier-only"
	return "not-a-capacity-row"


func _print_row(row_name: String, mode: String) -> void:
	var sorted_visible: Array[float] = visible_samples.duplicate()
	sorted_visible.sort()
	var sorted_live_meteors: Array[float] = live_meteor_samples.duplicate()
	sorted_live_meteors.sort()
	var sorted_workload: Array[float] = workload_samples.duplicate()
	sorted_workload.sort()
	var average_slew := 0.0
	for fraction in slew_fractions:
		average_slew += fraction
	if not slew_fractions.is_empty():
		average_slew /= float(slew_fractions.size())
	print("CONTACT_DENSITY_PROBE row=%s mode=%s lane_config=dishes:%d|automatic_lanes:%d|manual:%s dish_control=%s capacity_evidence_scope=%s announcements=%d resolutions=%d p50_visible=%.1f p95_visible=%.1f p50_live_meteors=%.1f p95_live_meteors=%.1f p50_workload=%.1f p95_workload=%.1f dish_slew_fraction=%.3f fast_contacts_announced=%d successful_fast_assignments=%d successful_fast_placements=%d unassigned_fast_contacts=%d fast_contacts_while_all_dishes_busy=%d eligible_contacts_announced=%d successful_eligible_assignments=%d unassigned_eligible_contacts=%d eligible_contacts_while_all_dishes_busy=%d dish_busy_fraction=%s dish_acquisitions=%d dish_acquisitions_by_type=%s dish_completions_by_type=%s dish_conversion_by_type=%s lane_participations=%d lane_participations_by_type=%s lane_completions=%d lane_completions_by_type=%s lane_conversion_by_type=%s lane_covered_only_completions_by_type=%s lane_uncovered_only_completions_by_type=%s lane_mixed_completions_by_type=%s opportunistic_acquisitions=%d opportunistic_acquisitions_by_type=%s manual_placements=%d manual_placement_opportunistic_acquisitions=%d manual_placement_opportunistic_acquisitions_by_type=%s opportunistic_completions=%d opportunistic_completions_by_type=%s opportunistic_dropped_without_completion=%d opportunistic_dropped_by_type=%s manual_only_completions_by_type=%s dish_only_completions_by_type=%s shared_completions_by_type=%s automatic_only_completions_by_type=%s realized_objects_30s=%d realized_objects_by_type=%s observations_completed=%d data_earned=%.0f" % [
		row_name,
		mode,
		game.sky_contacts.dishes.size(),
		game.progression.get_secondary_slots(),
		"on" if mode == MODE_SCRIPTED_ENGAGED else "off",
		_dish_control_text(),
		_capacity_evidence_scope_text(),
		announcements,
		resolutions,
		_percentile(sorted_visible, 0.50),
		_percentile(sorted_visible, 0.95),
		_percentile(sorted_live_meteors, 0.50),
		_percentile(sorted_live_meteors, 0.95),
		_percentile(sorted_workload, 0.50),
		_percentile(sorted_workload, 0.95),
		average_slew,
		fast_contacts_announced,
		successful_fast_assignments,
		successful_fast_placements,
		unassigned_fast_contacts,
		fast_contacts_while_all_dishes_busy,
		eligible_contacts_announced,
		successful_eligible_assignments,
		unassigned_eligible_contacts,
		eligible_contacts_while_all_dishes_busy,
		_dish_busy_fraction_text(),
		acquired_ids.size(),
		_type_counts_text(dish_acquisitions_by_type),
		_type_counts_text(dish_completions_by_type),
		_dish_conversion_text(),
		lane_participated_ids.size(),
		_type_counts_text(_counts_by_recorded_type(lane_participated_ids)),
		_lane_completion_count(),
		_type_counts_text(lane_completions_by_type),
		_lane_conversion_text(),
		_type_counts_text(lane_covered_only_completions_by_type),
		_type_counts_text(lane_uncovered_only_completions_by_type),
		_type_counts_text(lane_mixed_completions_by_type),
		opportunistic_acquired_ids.size(),
		_type_counts_text(_counts_by_recorded_type(opportunistic_acquired_ids)),
		manual_placement_count,
		manual_placement_acquired_ids.size(),
		_type_counts_text(_counts_by_recorded_type(manual_placement_acquired_ids)),
		opportunistic_completed_ids.size(),
		_type_counts_text(_counts_by_recorded_type(opportunistic_completed_ids)),
		opportunistic_dropped_ids.size(),
		_type_counts_text(_counts_by_recorded_type(opportunistic_dropped_ids)),
		_type_counts_text(manual_only_completions_by_type),
		_type_counts_text(dish_only_completions_by_type),
		_type_counts_text(shared_completions_by_type),
		_type_counts_text(automatic_only_completions_by_type),
		realized_objects,
		_type_counts_text(realized_objects_by_type),
		observations_completed,
		data_earned,
	])


func _lane_completion_count() -> int:
	var total := 0
	for count in lane_completions_by_type.values():
		total += int(count)
	return total


func _counts_by_recorded_type(records: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for type_id in records.values():
		_increment_type_count(counts, String(type_id))
	return counts


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(ceil(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]


func _seed_from_environment() -> int:
	if not OS.has_environment(SPAWN_SEED_ENV):
		return SPAWN_SEED
	var configured := OS.get_environment(SPAWN_SEED_ENV).strip_edges()
	if not configured.is_valid_int():
		push_warning("Ignoring invalid %s=%s" % [SPAWN_SEED_ENV, configured])
		return SPAWN_SEED
	return configured.to_int()
