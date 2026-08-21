extends SceneTree

const PROBE_DURATION := 30.0
const STEP := 0.05
const SPAWN_SEED := 20260821
const SPAWN_SEED_ENV := "NIGHTWATCH_CONTACT_PROBE_SEED"
const TYPE_BUCKETS := ["common", "fast", "fragment", "fragment_piece", "fireball", "major"]
const MODE_NO_INPUT := "no-input"
const MODE_SCRIPTED_ENGAGED := "scripted-engaged"
const MODE_FAST_ASSIGNED_ONLY := "fast-assigned-only"
const ROWS := [
	{"name": "forecast-off", "upgrades": ["edge_detection"]},
	{"name": "wide-only", "upgrades": ["edge_detection", "wide_field"]},
	{"name": "wide+dish", "upgrades": ["edge_detection", "wide_field", "array_planning", "secondary_camera"]},
]

var game
var spawn_seed: int = SPAWN_SEED
var probe_mode: String = MODE_NO_INPUT
var announcements: int = 0
var resolutions: int = 0
var realized_objects: int = 0
var observations_completed: int = 0
var data_earned: float = 0.0
var visible_samples: Array[float] = []
var slew_fractions: Array[float] = []
var assignment_elapsed: Dictionary = {}
var assignment_leads: Dictionary = {}
var acquired_ids: Dictionary = {}
var dish_acquisitions_by_type: Dictionary = {}
var dish_completions_by_type: Dictionary = {}
var manual_only_completions_by_type: Dictionary = {}
var dish_only_completions_by_type: Dictionary = {}
var shared_completions_by_type: Dictionary = {}


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
	for row in ROWS:
		await _run_row(row, MODE_NO_INPUT)
		await _run_row(row, MODE_SCRIPTED_ENGAGED)
		if String(row.name) == "wide+dish":
			await _run_row(row, MODE_FAST_ASSIGNED_ONLY)
	print("CONTACT_DENSITY_PROBE_COMPLETE")
	quit(0)


func _run_row(row: Dictionary, mode: String) -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	_prepare_row(row, mode)

	var elapsed := 0.0
	while elapsed < PROBE_DURATION:
		game.spawner.set_phase_time_remaining(PROBE_DURATION - elapsed)
		game.spawner._process(STEP)
		_update_assignment_slew(STEP)
		if game.sky_contacts.dish_active():
			game.sky_contacts._update_dishes(STEP)
			_record_dish_acquisitions()
		_process_meteors(STEP)
		visible_samples.append(float(game.sky_contacts.contacts.size()))
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
	observations_completed = 0
	data_earned = 0.0
	visible_samples.clear()
	slew_fractions.clear()
	assignment_elapsed.clear()
	assignment_leads.clear()
	acquired_ids.clear()
	dish_acquisitions_by_type.clear()
	dish_completions_by_type.clear()
	manual_only_completions_by_type.clear()
	dish_only_completions_by_type.clear()
	shared_completions_by_type.clear()

	game.set_process(false)
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
	game.sky_contacts.refresh_dishes()

	var game_spawn_handler := Callable(game, "_on_meteor_spawned")
	if game.spawner.meteor_spawned.is_connected(game_spawn_handler):
		game.spawner.meteor_spawned.disconnect(game_spawn_handler)
	game.spawner.contact_announced.connect(_on_contact_announced)
	game.spawner.contact_resolved.connect(_on_contact_resolved)
	game.spawner.meteor_spawned.connect(_on_meteor_spawned)
	game.spawner.rng.seed = spawn_seed
	game.spawner.forecast_rng.seed = spawn_seed + 1
	game.spawner.warm_contact_rng.seed = spawn_seed + 2
	game.spawner.next_contact_id = 1
	game.spawner.set_phase_time_remaining(PROBE_DURATION)
	game.spawner.start_spawning()


func _on_contact_announced(contact: Dictionary) -> void:
	announcements += 1
	if not game.sky_contacts.dish_active():
		return
	var should_assign := (
		probe_mode == MODE_SCRIPTED_ENGAGED
		or (probe_mode == MODE_FAST_ASSIGNED_ONLY and String(contact.type_id) == "fast")
	)
	if not should_assign:
		return
	var dish: Dictionary = game.sky_contacts.dishes[0]
	var dish_is_free := (
		int(dish.assigned_id) == -1
		and game.sky_contacts._locked_target(dish) == null
	)
	if not dish_is_free or not game.sky_contacts.assign_to_contact(int(contact.id)):
		return
	assignment_elapsed[int(contact.id)] = 0.0
	assignment_leads[int(contact.id)] = float(contact.lead_time)


func _on_contact_resolved(contact: Dictionary, _meteor) -> void:
	resolutions += 1
	_record_slew_fraction(int(contact.id))


func _on_meteor_spawned(meteor) -> void:
	realized_objects += 1
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
	data_earned += game.progression.add_observation(reward, was_manual, multiplier)


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
	for dish in game.sky_contacts.dishes:
		var locked_id := int(dish.locked_id)
		if locked_id == 0 or acquired_ids.has(locked_id):
			continue
		var target = instance_from_id(locked_id)
		if target != null and is_instance_valid(target) and target.can_be_tracked():
			var type_id := String(target.type_id)
			acquired_ids[locked_id] = type_id
			_increment_type_count(dish_acquisitions_by_type, type_id)


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


func _process_meteors(delta: float) -> void:
	var manual_target = null
	if probe_mode == MODE_SCRIPTED_ENGAGED:
		manual_target = _first_uncovered_meteor()
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


func _print_row(row_name: String, mode: String) -> void:
	var sorted_visible: Array[float] = visible_samples.duplicate()
	sorted_visible.sort()
	var average_slew := 0.0
	for fraction in slew_fractions:
		average_slew += fraction
	if not slew_fractions.is_empty():
		average_slew /= float(slew_fractions.size())
	print("CONTACT_DENSITY_PROBE row=%s mode=%s announcements=%d resolutions=%d p50_visible=%.1f p95_visible=%.1f dish_slew_fraction=%.3f dish_acquisitions=%d dish_acquisitions_by_type=%s dish_completions_by_type=%s dish_conversion_by_type=%s manual_only_completions_by_type=%s dish_only_completions_by_type=%s shared_completions_by_type=%s realized_objects_30s=%d observations_completed=%d data_earned=%.0f" % [
		row_name,
		mode,
		announcements,
		resolutions,
		_percentile(sorted_visible, 0.50),
		_percentile(sorted_visible, 0.95),
		average_slew,
		acquired_ids.size(),
		_type_counts_text(dish_acquisitions_by_type),
		_type_counts_text(dish_completions_by_type),
		_dish_conversion_text(),
		_type_counts_text(manual_only_completions_by_type),
		_type_counts_text(dish_only_completions_by_type),
		_type_counts_text(shared_completions_by_type),
		realized_objects,
		observations_completed,
		data_earned,
	])


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
