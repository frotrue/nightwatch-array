extends "res://scripts/meteor.gd"

const Surface = preload("res://scenes/neutron_star_surface.tscn")
const ROTATION_PERIOD := 1.6 # Deliberately slowed for readable observation.
const RELEASE_BEAM_LENGTH := 190.0
const BEAM_WORK_PER_SECOND := 4.0
const BEAM_TARGET_TYPES := ["common", "fast", "fragment", "fragment_piece", "fireball", "major",
	"satellite", "comet", "variable_star", "binary_star", "galaxy"]
var surface: Node2D

func _ready() -> void:
	super._ready()
	surface = Surface.instantiate()
	add_child(surface)

func signal_strength() -> float:
	return pow(absf(sin(age * TAU / ROTATION_PERIOD + wobble_phase)), 8.0)

func signal_multiplier() -> float:
	return 0.35 + 1.65 * signal_strength()

static func magnetic_axis(phase: float) -> Vector3:
	return Vector3(0.82 * cos(phase), 0.48, 0.82 * sin(phase)).normalized()

func illuminate_targets(targets: Array, bounds: Rect2) -> void:
	if not observed_successfully or linger_time <= 0.0 or is_queued_for_deletion(): return
	var axis := magnetic_axis(age * TAU / ROTATION_PERIOD + wobble_phase)
	var projected := Vector2(axis.x, axis.y)
	var direction := projected.normalized()
	# Beam contact follows the visible surface as the observation camera pulls back.
	var unit := _current_visual_scale()
	var reach := RELEASE_BEAM_LENGTH * projected.length() * unit
	var fade := smoothstep(0.0, 0.8, linger_time)
	for target in targets:
		if target.type_id not in BEAM_TARGET_TYPES or not target.alive or target.is_queued_for_deletion(): continue
		if not target.can_be_tracked() or not bounds.has_point(target.global_position): continue
		var offset: Vector2 = target.global_position - global_position
		var radius: float = maxf(target.get_observation_body_radius(), target.body_radius * target._current_visual_scale())
		var along := maxf(0.0, absf(offset.dot(direction)) - radius)
		if along >= reach: continue
		var across := maxf(0.0, absf(offset.cross(direction)) - radius)
		var width := 4.0 * unit + along * 0.075
		var strength := exp(-pow(across / width, 2.0)) * (1.0 - smoothstep(reach * 0.2, reach, along)) * fade
		if strength < 0.02: continue
		target.pulsar_assist_rate += BEAM_WORK_PER_SECOND * strength

func apply_manual_observation(delta: float, distance: float, tracking_radius: float, speed: float = 1.0) -> void:
	super.apply_manual_observation(delta, distance, tracking_radius, speed * signal_multiplier())

func get_automatic_rate() -> float:
	return super.get_automatic_rate() * signal_multiplier()

func tick_observation(delta: float) -> void:
	var accumulated := observation_progress
	super.tick_observation(delta)
	# A missed pulse or interrupted tracking never erases collected signal.
	observation_progress = maxf(accumulated, observation_progress)

func _finish_observation(auto_rate: float, force_automatic: bool = false) -> void:
	if not alive: return
	super._finish_observation(auto_rate, force_automatic)
	linger_duration = 3.0
	linger_time = linger_duration

func tick_motion(delta: float, tick_id: int) -> void:
	if observed_successfully:
		previous_simulation_position = global_position
		position += initial_velocity * delta
		age += delta
		linger_time -= delta
		if linger_time <= 0.0:
			hide()
			queue_free()
		return
	super.tick_motion(delta, tick_id)

func _draw_type_silhouette(_radius: float, alpha: float, visual_scale: float) -> void:
	if not is_instance_valid(surface): return
	alpha *= smoothstep(0.0, 0.16, age)
	if observed_successfully: alpha = smoothstep(0.0, 0.8, linger_time)
	# Dim the moving beam with accessibility intensity, but keep its aim on the live contact.
	var visual_phase := age * TAU / ROTATION_PERIOD + wobble_phase if completion_motion_scale > 0.0 else wobble_phase
	surface.present(visual_scale, alpha, visual_phase, completion_motion_scale, completion_glint_enabled,
		age, magnetic_axis(visual_phase), RELEASE_BEAM_LENGTH if observed_successfully else 150.0, observed_successfully)
