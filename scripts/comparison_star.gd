extends Node2D

signal comparison_completed(star)

const REQUIRED_TRACK_TIME := 0.72
const EXTRA_TRACKING_RADIUS_SCREEN_PX := 7.0

var host_id: int = 0
var correct: bool = true
var type_id: String = "comparison_star"
var observation_progress: float = 0.0
var active: bool = true
var tint := Color("ffd7a0")
var observation_view: Camera2D


func configure(id: int, world_position: Vector2, is_correct: bool, color: Color, view: Camera2D = null) -> void:
	host_id = id
	position = world_position
	correct = is_correct
	tint = color
	observation_view = view
	queue_redraw()


func can_be_tracked() -> bool:
	return active


func get_tracking_radius(base_radius: float) -> float:
	return base_radius + _screen_length(EXTRA_TRACKING_RADIUS_SCREEN_PX)


func apply_manual_observation(delta: float, _cursor_distance: float, _tracking_radius: float, manual_speed_multiplier: float = 1.0) -> void:
	if not active:
		return
	observation_progress += maxf(0.0, delta) * maxf(1.0, manual_speed_multiplier) / REQUIRED_TRACK_TIME
	if observation_progress >= 1.0:
		active = false
		comparison_completed.emit(self)
	queue_redraw()


func reset_progress() -> void:
	observation_progress = 0.0
	active = true
	queue_redraw()


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_quality() -> float:
	return 1.0


func get_visual_color() -> Color:
	return tint


func get_quality_grade() -> String:
	return "GOOD"


func get_predicted_multiplier() -> float:
	return 1.0


func _draw() -> void:
	if not active:
		return
	var scale := _screen_length(1.0)
	var radius := 3.4 * scale
	draw_circle(Vector2.ZERO, radius * 2.6, Color(tint, 0.08))
	draw_circle(Vector2.ZERO, radius, Color(tint, 0.82))
	draw_arc(Vector2.ZERO, 10.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * get_progress(), 24, Color(tint, 0.72), 1.2 * scale, true)


func _screen_length(screen_pixels: float) -> float:
	if observation_view != null and observation_view.has_method("screen_length_to_world"):
		return observation_view.screen_length_to_world(screen_pixels)
	return screen_pixels
