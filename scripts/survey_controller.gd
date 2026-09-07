extends Node2D

signal meteor_summoned(meteor)

const UITheme = preload("res://scripts/ui_theme.gd")
const Balance = preload("res://scripts/game_balance.gd")

const EMPTY_SKY_RADIUS := 150.0
const SURVEY_SEED_BASE := 731_927
const SPAWN_DIRECTION_SPREAD := PI / 3.0
const FAST_TYPE_CHANCE := 0.35

var progression: Node
var spawner: Node
var meteor_layer: Node2D
var modules: RefCounted
var discovery_layers: Array[Node2D] = []
var observation_view: Camera2D
var rng := RandomNumberGenerator.new()
var active_round: int = 0
var scanning: bool = false
var cursor_position := Vector2.ZERO
var charge_distance: float = 0.0
var cooldown_remaining: float = 0.0
var cooldown_duration: float = 0.0
var summoned_this_round: int = 0
var roll_count: int = 0


func setup(progression_controller: Node, meteor_spawner: Node, target_layer: Node2D, view: Camera2D = null, hidden_target_layer = null) -> void:
	progression = progression_controller
	spawner = meteor_spawner
	meteor_layer = target_layer
	observation_view = view
	discovery_layers.clear()
	if hidden_target_layer is Array:
		for layer_variant in hidden_target_layer:
			if layer_variant is Node2D:
				discovery_layers.append(layer_variant)
	elif hidden_target_layer is Node2D:
		discovery_layers.append(hidden_target_layer)
	reset()


func reset() -> void:
	active_round = 0
	scanning = false
	charge_distance = 0.0
	cooldown_remaining = 0.0
	cooldown_duration = 0.0
	summoned_this_round = 0
	roll_count = 0
	queue_redraw()


func begin_round(round_index: int) -> void:
	reset()
	active_round = maxi(1, round_index)
	if progression == null or not progression.survey_enabled():
		return
	# Survey rolls are deterministic within a round but never consume the
	# spawner's cadence, forecast, echo, or warm-contact streams.
	rng.seed = SURVEY_SEED_BASE + active_round * 7919
	queue_redraw()


func end_round() -> void:
	reset()


func advance_time(real_delta: float) -> void:
	if active_round <= 0 or cooldown_remaining <= 0.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - maxf(0.0, real_delta))
	queue_redraw()


func set_scanning(value: bool, position: Vector2, preserve_charge: bool = false) -> void:
	var enabled: bool = (
		active_round > 0
		and progression != null
		and progression.survey_enabled()
	)
	scanning = value and enabled
	cursor_position = position
	# A tracking transition suspends scanning while the button remains held.
	# A later release must still clear base charge even though scanning is already
	# false. Sustained Sweep alone preserves it across actual releases.
	if not scanning and not preserve_charge and progression != null and not progression.survey_charge_persists():
		charge_distance = 0.0
	if not enabled:
		charge_distance = 0.0
	queue_redraw()


func apply_scan_segment(from: Vector2, to: Vector2, _active_delta: float = 0.0) -> int:
	if (
		not scanning
		or active_round <= 0
		or progression == null
		or not progression.survey_enabled()
		or spawner == null
		or meteor_layer == null
	):
		return 0
	cursor_position = to
	var path_length := from.distance_to(to)
	if path_length <= 0.01 or cooldown_remaining > 0.0:
		queue_redraw()
		return 0
	# The verb belongs only to dead air. A live target inside the observation
	# neighbourhood pauses both distance accumulation and probability rolls.
	if not is_blank_sky(to):
		queue_redraw()
		return 0
	for discovery_layer in discovery_layers:
		if discovery_layer != null and discovery_layer.has_method("record_sweep_segment"):
			discovery_layer.record_sweep_segment(from, to)
	# Sweep Optics changes the charge earned by the held blank-sky gesture. The
	# empty-sky exclusion radius remains an input/readability contract.
	var charge_multiplier := float(modules.effect("sweep_charge")) if modules != null else 1.0
	charge_distance += path_length * charge_multiplier
	var required_distance: float = _world_px(progression.get_survey_required_distance())
	var spawned_count := 0
	while charge_distance >= required_distance and cooldown_remaining <= 0.0:
		charge_distance -= required_distance
		roll_count += 1
		if rng.randf() >= progression.get_survey_spawn_probability():
			continue
		spawned_count = _spawn_from_cursor(to)
		if spawned_count > 0:
			summoned_this_round += spawned_count
			cooldown_duration = progression.get_survey_cooldown_seconds()
			cooldown_remaining = cooldown_duration
			charge_distance = 0.0
			break
	queue_redraw()
	return spawned_count


func is_blank_sky(position: Vector2) -> bool:
	if meteor_layer == null:
		return false
	for child in meteor_layer.get_children():
		if (
			is_instance_valid(child)
			and not child.is_queued_for_deletion()
			and child.has_method("can_be_tracked")
			and child.can_be_tracked()
			and position.distance_to(child.global_position) <= _world_px(EMPTY_SKY_RADIUS)
		):
			return false
	for discovery_layer in discovery_layers:
		if discovery_layer == null:
			continue
		for child in discovery_layer.get_children():
			if (
				is_instance_valid(child)
				and not child.is_queued_for_deletion()
				and child.has_method("can_be_tracked")
				and child.can_be_tracked()
				and position.distance_to(child.global_position) <= _world_px(EMPTY_SKY_RADIUS)
			):
				return false
	return true


func get_charge_progress() -> float:
	if progression == null or not progression.survey_enabled():
		return 0.0
	return clampf(charge_distance / maxf(1.0, _world_px(progression.get_survey_required_distance())), 0.0, 1.0)


func get_cooldown_progress() -> float:
	if cooldown_duration <= 0.0 or cooldown_remaining <= 0.0:
		return 0.0
	return clampf(1.0 - cooldown_remaining / cooldown_duration, 0.0, 1.0)


func _spawn_from_cursor(position: Vector2) -> int:
	var spawned_count := 0
	var spawn_count: int = progression.get_survey_spawn_count()
	for _index in range(spawn_count):
		var type_id := "common"
		if progression.has_upgrade("trajectory") and rng.randf() < FAST_TYPE_CHANCE:
			type_id = "fast"
		var toward_centre := (_atmospheric_rect().get_center() - position).normalized()
		if toward_centre.is_zero_approx():
			toward_centre = Vector2.UP
		var direction := toward_centre.rotated(rng.randf_range(-SPAWN_DIRECTION_SPREAD, SPAWN_DIRECTION_SPREAD))
		var speed := float(Balance.meteor_spec(type_id).speed)
		# Leaving custom burnout as INF lets Meteor.configure derive a full burn
		# path from this start and direction instead of ending at the cursor.
		var meteor = spawner.spawn_meteor(type_id, position, direction * speed)
		if meteor == null:
			break
		meteor.set_meta("polar_summoned", true)
		meteor.set_meta("polar_summon_round", active_round)
		meteor_summoned.emit(meteor)
		spawned_count += 1
	return spawned_count


func _draw() -> void:
	if active_round <= 0 or progression == null or not progression.survey_enabled():
		return
	if not scanning and charge_distance <= 0.0 and cooldown_remaining <= 0.0:
		return
	var visual_scale := _world_px(1.0)
	var radius: float = _world_px(progression.get_tracking_radius() + 16.0)
	var blocked := scanning and not is_blank_sky(cursor_position)
	var track_alpha := 0.16 if blocked else 0.30
	draw_arc(cursor_position, radius, 0.0, TAU, 64, Color(UITheme.SHADOW, 0.44), 2.5 * visual_scale, true)
	draw_arc(cursor_position, radius, 0.0, TAU, 64, Color(UITheme.ACCENT_DEEP, track_alpha), 0.85 * visual_scale, true)
	var progress := get_charge_progress()
	var arc_color := Color(UITheme.ACCENT_LINE, 0.38 if blocked else 0.92)
	if cooldown_remaining > 0.0:
		progress = get_cooldown_progress()
		arc_color = Color(UITheme.ACCENT_PIP, 0.82)
	if progress <= 0.0:
		return
	draw_arc(
		cursor_position,
		radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * progress,
		64,
		arc_color,
		1.3 * visual_scale,
		true
	)


func _atmospheric_rect() -> Rect2:
	if observation_view != null:
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
