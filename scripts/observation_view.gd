extends Camera2D

# Stage 0 is deliberately an identity transform. Later galactic research can
# raise this value through progression without changing any caller's coordinate
# assumptions.
const OBSERVATION_SPAN := 1.0

func _ready() -> void:
	position = atmospheric_rect().get_center()
	zoom = Vector2.ONE / OBSERVATION_SPAN
	get_viewport().size_changed.connect(_refresh_camera)


func atmospheric_rect() -> Rect2:
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func visible_world_rect() -> Rect2:
	var atmospheric := atmospheric_rect()
	var visible_size := atmospheric.size * OBSERVATION_SPAN
	return Rect2(atmospheric.get_center() - visible_size * 0.5, visible_size)


func screen_to_world(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * point


func world_to_screen(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * point


func screen_length_to_world(pixels: float) -> float:
	return pixels * OBSERVATION_SPAN


func _refresh_camera() -> void:
	position = atmospheric_rect().get_center()
	zoom = Vector2.ONE / OBSERVATION_SPAN
