extends Camera2D

signal span_changed(value: float)

var observation_span := 1.0

func _ready() -> void:
	position = atmospheric_rect().get_center()
	zoom = Vector2.ONE / observation_span
	get_viewport().size_changed.connect(_refresh_camera)


func atmospheric_rect() -> Rect2:
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func visible_world_rect() -> Rect2:
	var atmospheric := atmospheric_rect()
	var visible_size := atmospheric.size * observation_span
	return Rect2(atmospheric.get_center() - visible_size * 0.5, visible_size)


func screen_to_world(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * point


func world_to_screen(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * point


func screen_length_to_world(pixels: float) -> float:
	return pixels * observation_span


func set_observation_span(value: float) -> void:
	var next_span := clampf(value, 1.0, GameBalance.GALACTIC_FINAL_OBSERVATION_SPAN)
	if is_equal_approx(next_span, observation_span):
		return
	observation_span = next_span
	_refresh_camera()
	span_changed.emit(observation_span)


func _refresh_camera() -> void:
	position = atmospheric_rect().get_center()
	zoom = Vector2.ONE / observation_span
