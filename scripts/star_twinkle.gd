extends Node2D

const Balance = preload("res://scripts/game_balance.gd")

const TWINKLE_FPS := 30.0
const TWINKLE_COUNT := 16
const BACKGROUND_COVERAGE_SPAN := Balance.GALACTIC_FINAL_OBSERVATION_SPAN * 1.02

var stars: Array[Dictionary] = []
var outer_stars: Array[Dictionary] = []
var time: float = 0.0
var redraw_accumulator: float = 0.0
var rng := RandomNumberGenerator.new()
var observation_view: Camera2D


func _ready() -> void:
	rng.seed = 527913
	_rebuild_stars()
	queue_redraw()


func setup(view: Camera2D) -> void:
	observation_view = view
	if not observation_view.span_changed.is_connected(_on_observation_span_changed):
		observation_view.span_changed.connect(_on_observation_span_changed)
	queue_redraw()


func _on_observation_span_changed(_value: float) -> void:
	queue_redraw()


func _rebuild_stars() -> void:
	stars.clear()
	outer_stars.clear()
	for index in range(TWINKLE_COUNT):
		stars.append({
			"p": Vector2(rng.randf(), pow(rng.randf(), 1.15) * 0.86),
			"size": rng.randf_range(0.75, 1.55),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.7, 1.8)
		})
	var coverage := _background_coverage_rect()
	var atmospheric := _atmospheric_rect()
	var area_ratio := coverage.size.x * coverage.size.y / maxf(1.0, atmospheric.size.x * atmospheric.size.y)
	var outer_count := maxi(0, int(round(float(TWINKLE_COUNT) * (area_ratio - 1.0))))
	for _index in range(outer_count):
		outer_stars.append({
			"p": _sample_outer_point(coverage),
			"size": rng.randf_range(0.75, 1.55),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.7, 1.8)
		})
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	redraw_accumulator += delta
	if redraw_accumulator >= 1.0 / TWINKLE_FPS:
		redraw_accumulator = fmod(redraw_accumulator, 1.0 / TWINKLE_FPS)
		queue_redraw()


func _draw() -> void:
	var viewport_size := _atmospheric_rect().size
	for star in stars:
		_draw_star(Vector2(star.p) * viewport_size, star)
	for star in outer_stars:
		_draw_star(Vector2(star.p), star)


func _draw_star(point: Vector2, star: Dictionary) -> void:
	var pulse := 0.48 + sin(time * float(star.speed) + float(star.phase)) * 0.38
	var alpha := clampf(pulse, 0.08, 0.86)
	# Rays removed with the starfield's, for the same reason: a background
	# star must never take up more of the frame than a meteor does.
	draw_circle(point, _world_px(float(star.size)), Color(0.76, 0.89, 1.0, alpha))


func _atmospheric_rect() -> Rect2:
	if observation_view != null:
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _background_coverage_rect() -> Rect2:
	var atmospheric := _atmospheric_rect()
	var coverage_size := atmospheric.size * BACKGROUND_COVERAGE_SPAN
	return Rect2(atmospheric.get_center() - coverage_size * 0.5, coverage_size)


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
