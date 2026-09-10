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


func meteor_activity_rect() -> Rect2:
	# Pull-back opens the lateral sky to atmospheric traffic without moving
	# deadlines under the phase clock or bottom controls. At span 1 this is the
	# original atmospheric rectangle; later spans follow the full visible width.
	var atmospheric := atmospheric_rect()
	var visible := visible_world_rect()
	return Rect2(
		Vector2(visible.position.x, atmospheric.position.y),
		Vector2(visible.size.x, atmospheric.size.y)
	)


func screen_to_world(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * point


func world_to_screen(point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * point


func screen_length_to_world(pixels: float) -> float:
	return pixels * observation_span


func meteor_visual_scale() -> float:
	# Full screen compensation made meteors retain their opening size even after
	# they became the secondary layer. Half compensation lets the camera reduce
	# them gradually: their screen size is 1 / sqrt(span), about 82% at the
	# current final span. Interaction budgets remain fully screen-compensated.
	return sqrt(observation_span)


func meteor_screen_scale() -> float:
	# Directional kick and the success flash recede with the meteor rather than
	# retaining opening-stage force. The visual is drawn in world units and then
	# camera-scaled, yielding 1 / sqrt(span) on screen.
	return meteor_visual_scale() / observation_span


func meteor_shake_scale() -> float:
	# Repeated shake is more disruptive across the larger late-game view, so its
	# pixel amplitude receives full camera attenuation: 1 / span.
	return 1.0 / observation_span


func set_observation_span(value: float) -> void:
	var next_span := clampf(value, 1.0, 1.5)
	if is_equal_approx(next_span, observation_span):
		return
	observation_span = next_span
	_refresh_camera()
	span_changed.emit(observation_span)


func _refresh_camera() -> void:
	position = atmospheric_rect().get_center()
	zoom = Vector2.ONE / observation_span
