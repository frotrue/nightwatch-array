extends "res://scripts/meteor.gd"

const Surface = preload("res://scenes/neutron_star_surface.tscn")
const ROTATION_PERIOD := 1.6 # Deliberately slowed for readable observation.
var surface: Node2D

func _ready() -> void:
	super._ready()
	surface = Surface.instantiate()
	add_child(surface)

func signal_strength() -> float:
	return pow(absf(sin(age * TAU / ROTATION_PERIOD + wobble_phase)), 8.0)

func signal_multiplier() -> float:
	return 0.35 + 1.65 * signal_strength()

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
	alpha *= smoothstep(0.0, 0.5, age)
	if observed_successfully: alpha = smoothstep(0.0, 0.8, linger_time)
	var visual_phase := age * TAU / ROTATION_PERIOD * completion_motion_scale + wobble_phase
	surface.present(visual_scale, alpha, visual_phase, completion_motion_scale, completion_glint_enabled)
