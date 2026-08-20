extends Node

signal meteor_spawned(meteor)
signal rare_spawned(type_id)

const Balance = preload("res://scripts/game_balance.gd")
const MeteorScript = preload("res://scripts/meteor.gd")
const MAX_TOTAL_METEORS := 32

var meteor_layer: Node2D
var progression: Node
var rng := RandomNumberGenerator.new()
var running: bool = false
var pause_regular_spawns: bool = false
var next_spawn_time: float = Balance.FIRST_METEOR_DELAY
var first_spawn_pending: bool = true
var secondary_refresh: float = 0.0


func setup(target_layer: Node2D, progression_controller: Node) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	rng.randomize()


func start_spawning() -> void:
	running = true
	pause_regular_spawns = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true


func reset() -> void:
	running = false
	for child in meteor_layer.get_children():
		child.queue_free()
	pause_regular_spawns = false
	next_spawn_time = Balance.FIRST_METEOR_DELAY
	first_spawn_pending = true
	secondary_refresh = 0.0


func _process(delta: float) -> void:
	if not running:
		return
	secondary_refresh -= delta
	if secondary_refresh <= 0.0:
		secondary_refresh = 0.35
		_refresh_secondary_camera()
	if pause_regular_spawns:
		return
	next_spawn_time -= delta
	if next_spawn_time > 0.0:
		return
	if _active_count() >= progression.get_max_active():
		next_spawn_time = 0.45
		return
	if first_spawn_pending:
		first_spawn_pending = false
		_spawn_first_meteor()
	else:
		spawn_meteor(_choose_regular_type())
	var base_interval := rng.randf_range(5.2, 7.0)
	next_spawn_time = maxf(1.15, base_interval * progression.get_spawn_interval_scale())


func spawn_meteor(type_id: String = "common", custom_start := Vector2.INF, custom_velocity := Vector2.INF, lifetime_override: float = -1.0):
	# Shower and fragment paths intentionally bypass the regular progression cap.
	# Keep one reserved slot for the final major target while bounding all burst
	# paths so a missed frame cannot turn into an ever-growing render workload.
	var instance_limit := MAX_TOTAL_METEORS if type_id == "major" else MAX_TOTAL_METEORS - 1
	if meteor_layer == null or meteor_layer.get_child_count() >= instance_limit:
		return null
	var size := get_viewport().get_visible_rect().size
	var spec := Balance.meteor_spec(type_id)
	var start := custom_start
	var move_velocity := custom_velocity
	if custom_start == Vector2.INF:
		var edge := rng.randi_range(0, 2)
		match edge:
			0:
				start = Vector2(rng.randf_range(70.0, size.x - 70.0), -24.0)
			1:
				start = Vector2(-24.0, rng.randf_range(55.0, size.y * 0.68))
			_:
				start = Vector2(size.x + 24.0, rng.randf_range(55.0, size.y * 0.62))
		var target := Vector2(
			rng.randf_range(size.x * 0.24, size.x * 0.78),
			rng.randf_range(size.y * 0.30, size.y * 0.78)
		)
		move_velocity = (target - start).normalized() * float(spec.speed) * rng.randf_range(0.9, 1.12)
	var lifetime_scale: float = progression.get_lifetime_multiplier()
	if lifetime_override > 0.0:
		lifetime_scale = lifetime_override / float(spec.lifetime)
	var meteor = MeteorScript.new()
	var features := _current_features(type_id)
	meteor.configure(spec, type_id, start, move_velocity, lifetime_scale, features)
	meteor.fragment_requested.connect(_on_fragment_requested)
	meteor_layer.add_child(meteor)
	meteor_spawned.emit(meteor)
	if type_id == "fireball" or type_id == "major":
		rare_spawned.emit(type_id)
	return meteor


func spawn_for_shower(index: int) -> void:
	var type_id := "common"
	if index % 9 == 6:
		type_id = "fireball"
	elif index % 5 == 3:
		type_id = "fragment"
	elif index % 3 == 1:
		type_id = "fast"
	spawn_meteor(type_id)


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
	var roll := rng.randf()
	if progression.has_upgrade("rare_detection") and roll < 0.075:
		return "fireball"
	if progression.has_upgrade("fragment_analysis") and roll < 0.25:
		return "fragment"
	if progression.has_upgrade("edge_detection") and roll < 0.50:
		return "fast"
	return "common"


func _current_features(type_id: String) -> Dictionary:
	return {
		"wide_field": progression.has_upgrade("wide_field"),
		"prediction": progression.has_upgrade("trajectory"),
		"precision": progression.has_upgrade("precision_multiplier"),
		"perfect": progression.has_upgrade("perfect_observation"),
		"automation": progression.get_automation_strength(type_id),
		"secondary": 0.0
	}


func _refresh_secondary_camera() -> void:
	var slots: int = progression.get_secondary_slots()
	if slots <= 0:
		return
	var candidates: Array = []
	for child_index in range(meteor_layer.get_child_count()):
		var child = meteor_layer.get_child(child_index)
		if child.has_method("set_secondary_assist"):
			child.set_secondary_assist(0.0)
		if not child.has_method("can_be_tracked") or not child.can_be_tracked():
			continue
		if child.type_id in ["fireball", "major"]:
			continue
		candidates.append(child)
	candidates.sort_custom(func(a, b): return float(a.observation_progress) > float(b.observation_progress))
	for index in range(mini(slots, candidates.size())):
		var candidate = candidates[index]
		var rate := 0.19
		if candidate.type_id == "fast":
			rate = 0.12
		elif candidate.type_id == "fragment":
			rate = 0.14
		elif candidate.type_id == "fragment_piece" and progression.has_upgrade("multi_target_analysis"):
			rate = 0.22
		candidate.set_secondary_assist(rate)


func _on_fragment_requested(origin: Vector2, parent_velocity: Vector2, parent_type: String) -> void:
	var piece_count := 4 if parent_type == "major" else 3
	var spread := 0.34 if parent_type == "major" else 0.25
	var available_slots := maxi(0, (MAX_TOTAL_METEORS - 1) - meteor_layer.get_child_count())
	for index in range(mini(piece_count, available_slots)):
		var centered := float(index) - float(piece_count - 1) * 0.5
		var direction := parent_velocity.normalized().rotated(centered * spread)
		var speed := parent_velocity.length() * rng.randf_range(0.88, 1.18)
		spawn_meteor("fragment_piece", origin + direction * 7.0, direction * speed, 3.2 if parent_type == "major" else 2.65)


func _active_count() -> int:
	var count := 0
	for child_index in range(meteor_layer.get_child_count()):
		var child = meteor_layer.get_child(child_index)
		if child.has_method("can_be_tracked") and child.can_be_tracked():
			count += 1
	return count
