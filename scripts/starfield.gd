extends Node2D

const Balance = preload("res://scripts/game_balance.gd")

# Keep a small overscan reserve around the final camera limit so changing the
# single balance constant cannot silently reveal an unpainted border.
const BACKGROUND_COVERAGE_SPAN := Balance.GALACTIC_FINAL_OBSERVATION_SPAN * 1.02

var stars: Array[Dictionary] = []
var outer_stars: Array[Dictionary] = []
var activity: float = 0.0
var galactic_mode: bool = false
var rng := RandomNumberGenerator.new()
var cached_size := Vector2.ZERO
var observation_view: Camera2D


func _ready() -> void:
	rng.seed = 914027
	_rebuild_stars()
	get_viewport().size_changed.connect(_rebuild_stars)
	queue_redraw()


func setup(view: Camera2D) -> void:
	observation_view = view
	if not observation_view.span_changed.is_connected(_on_observation_span_changed):
		observation_view.span_changed.connect(_on_observation_span_changed)
	queue_redraw()


func _on_observation_span_changed(_value: float) -> void:
	queue_redraw()


func set_activity(value: float) -> void:
	var next_activity := clampf(value, 0.0, 1.0)
	if is_equal_approx(next_activity, activity):
		return
	activity = next_activity
	# The expensive full background is rebuilt only when event tint changes.
	queue_redraw()


func set_galactic_mode(enabled: bool) -> void:
	if galactic_mode == enabled:
		return
	galactic_mode = enabled
	_rebuild_stars()


func _rebuild_stars() -> void:
	cached_size = _atmospheric_rect().size
	stars.clear()
	outer_stars.clear()
	# Density is measured per megapixel against the design capture. The twinkle
	# layer draws its own stars on top, so this divisor is set for the pair
	# rather than for this layer alone, and the floor stays under it so a small
	# viewport is not proportionally denser than the reference.
	var base_count := maxi(24, int(cached_size.x * cached_size.y / 17000.0))
	var count := int(round(float(base_count) * 1.65)) if galactic_mode else base_count
	for index in range(count):
		var normalized := Vector2(rng.randf(), pow(rng.randf(), 1.1) * 0.88)
		stars.append({
			"p": normalized,
			"size": rng.randf_range(0.45, 1.30),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.35, 1.2),
			"blue": rng.randf_range(0.0, 1.0)
		})
	var coverage := _background_coverage_rect()
	var extra_area := maxf(0.0, coverage.size.x * coverage.size.y - cached_size.x * cached_size.y)
	var outer_base_count := int(round(extra_area / 17000.0))
	var outer_count := int(round(float(outer_base_count) * 1.65)) if galactic_mode else outer_base_count
	for _index in range(outer_count):
		var point := _sample_outer_point(coverage)
		outer_stars.append({
			"p": point,
			"size": rng.randf_range(0.45, 1.30),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.35, 1.2),
			"blue": rng.randf_range(0.0, 1.0)
		})
	queue_redraw()


func _draw() -> void:
	var atmospheric := _atmospheric_rect()
	var size := atmospheric.size
	var sky_frame := _sky_frame_rect()
	var sky_size := sky_frame.size
	# The camera is still identity-scaled in stage 0, so this reserve is outside
	# the shipped frame. It prevents later pull-back steps from exposing an
	# unpainted border without changing today's sky.
	draw_rect(_background_coverage_rect(), Color("05070C"), true)
	# Layered bands give a restrained vertical night-sky gradient without textures.
	# A radial well centred just below the frame, so the sky is darkest overhead
	# and the red-light information layer never competes with a blue field.
	var bands := 120
	var origin := sky_frame.position + Vector2(sky_size.x * 0.5, sky_size.y * 1.08)
	var reach := Vector2(sky_size.x * 1.2, sky_size.y * 0.9).length() * 0.5
	for index in range(bands):
		var t := float(index) / float(bands - 1)
		var band_y := sky_frame.position.y + (1.0 - t) * sky_size.y
		var distance := clampf(absf(band_y - origin.y) / maxf(reach, 1.0), 0.0, 1.0)
		var sky := Color("05070C")
		if distance <= 0.34:
			sky = Color("14202D").lerp(Color("050911"), smoothstep(0.0, 1.0, distance / 0.34))
		elif distance <= 0.72:
			sky = Color("050911").lerp(Color("05070C"), smoothstep(0.0, 1.0, (distance - 0.34) / 0.38))
		sky = sky.lerp(Color("2A1A1E"), activity * (0.06 + (1.0 - t) * 0.10))
		draw_rect(Rect2(sky_frame.position.x, band_y - sky_size.y / bands, sky_size.x, sky_size.y / bands + 2.0), sky)

	for star in stars:
		_draw_star(Vector2(star.p) * size, star)
	for star in outer_stars:
		_draw_star(Vector2(star.p), star)

	# A quiet, low-contrast horizon line, and nothing on it. The observatory that
	# used to sit here read as a foreground object in a frame whose whole subject
	# is the empty sky above it.
	draw_colored_polygon(_horizon_ridge(sky_frame), Color("03050A"))


func _draw_star(point: Vector2, star: Dictionary) -> void:
	var pulse := 0.62 + sin(float(star.phase)) * 0.16
	pulse += activity * 0.12
	var star_color := Color("d9dee6").lerp(Color("ffffff"), float(star.blue))
	star_color.a = clampf(pulse, 0.22, 1.0)
	# No cross rays. They were the reason a background star could occupy more
	# pixels than a meteor's head, and the sky has to stay quieter than the
	# thing the player is trying to see in it.
	draw_circle(point, _world_px(float(star.size)), star_color)


func _atmospheric_rect() -> Rect2:
	if observation_view != null:
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _background_coverage_rect() -> Rect2:
	var atmospheric := _atmospheric_rect()
	var coverage_size := atmospheric.size * BACKGROUND_COVERAGE_SPAN
	return Rect2(atmospheric.get_center() - coverage_size * 0.5, coverage_size)


func _sky_frame_rect() -> Rect2:
	if observation_view != null:
		return observation_view.visible_world_rect()
	return _atmospheric_rect()


func _horizon_ridge(frame: Rect2) -> PackedVector2Array:
	var horizon_y := frame.position.y + frame.size.y * 0.91
	return PackedVector2Array([
		Vector2(frame.position.x, horizon_y + 8.0),
		Vector2(frame.position.x + frame.size.x * 0.12, horizon_y - 5.0),
		Vector2(frame.position.x + frame.size.x * 0.27, horizon_y + 2.0),
		Vector2(frame.position.x + frame.size.x * 0.44, horizon_y - 12.0),
		Vector2(frame.position.x + frame.size.x * 0.62, horizon_y + 3.0),
		Vector2(frame.position.x + frame.size.x * 0.81, horizon_y - 7.0),
		Vector2(frame.end.x, horizon_y + 4.0),
		frame.end,
		Vector2(frame.position.x, frame.end.y),
	])


func _sample_outer_point(coverage: Rect2) -> Vector2:
	var atmospheric := _atmospheric_rect()
	for _attempt in range(32):
		var point := Vector2(
			rng.randf_range(coverage.position.x, coverage.end.x),
			rng.randf_range(coverage.position.y, coverage.end.y)
		)
		if not atmospheric.has_point(point):
			return point
	return coverage.position


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
