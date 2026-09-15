extends "res://scripts/meteor.gd"

# Uses the normal target pipeline; only its appearance and timed ejection differ.
const Surface = preload("res://scenes/white_hole_preview.tscn")
const RELEASE_DURATION := 1.4
const EJECTA_COUNT := 24
const POSE_WOBBLE := 0.055
signal ejecta_requested(source, index)
var surface: Node2D
var visual_time := 0.0
var completion_pose_time := 0.0
var release_axis := Vector2.RIGHT
var emitted_count := 0
var ejecta_count := EJECTA_COUNT
var preview_mode := 0

func _ready() -> void:
	super._ready()
	surface = Surface.instantiate()
	add_child(surface)

func tick_motion(delta: float, tick_id: int) -> void:
	visual_time += delta * completion_motion_scale
	super.tick_motion(delta, tick_id)

func tick_resolve() -> void:
	super.tick_resolve()
	# Resolve after observation so newborn ejecta receive no work on their birth tick.
	_release_due_ejecta()

func apply_motion_result(result: Dictionary, delta: float, tick_id: int) -> void:
	visual_time += delta * completion_motion_scale
	super.apply_motion_result(result, delta, tick_id)

func _finish_observation(auto_rate: float, force_automatic: bool = false) -> void:
	if not alive: return
	completion_pose_time = visual_time
	var base_angle := PI * 0.5 - initial_velocity.angle()
	var pose := base_angle + sin(completion_pose_time * 0.36) * POSE_WOBBLE
	release_axis = Vector2.from_angle(PI * 0.5 - pose)
	super._finish_observation(auto_rate, force_automatic)
	linger_duration = RELEASE_DURATION
	linger_time = RELEASE_DURATION

func _release_due_ejecta() -> void:
	if not observed_successfully or is_queued_for_deletion(): return
	var elapsed := RELEASE_DURATION - linger_time
	# Research adds complete pairs to six waves without extending the beam.
	var wave_size := ejecta_count / 6
	while emitted_count < ejecta_count and elapsed + 0.00001 >= 0.10 + float(emitted_count / wave_size) * 0.18:
		var index := emitted_count
		emitted_count += 1
		ejecta_requested.emit(self, index)

func _draw_type_silhouette(_radius: float, alpha: float, visual_scale: float) -> void:
	if not is_instance_valid(surface): return
	var completion := 0.0
	if observed_successfully:
		completion = clampf(1.0 - linger_time / RELEASE_DURATION, 0.0, 1.0)
		alpha = 1.0 - smoothstep(0.82, 1.0, completion)
	else:
		alpha *= smoothstep(0.0, 0.6, age)
	surface.scale = Vector2.ONE * visual_scale
	surface.present_target(alpha, visual_time, PI * 0.5 - initial_velocity.angle(),
		completion_pose_time if observed_successfully else visual_time, POSE_WOBBLE,
		get_progress(), completion, completion_motion_scale, completion_glint_enabled, preview_mode)
