extends Node2D

const Balance = preload("res://scripts/game_balance.gd")

# Keep a small overscan reserve around the final camera limit so changing the
# single balance constant cannot silently reveal an unpainted border.
const BACKGROUND_COVERAGE_SPAN := Balance.GALACTIC_FINAL_OBSERVATION_SPAN * 1.02

# The live sky shares the research chart's sparse astronomical typesetting,
# without becoming a photograph. Most stars sit in loose, authored groupings;
# a smaller field population keeps the negative space from feeling tiled.
const INNER_CLUSTER_ANCHORS := [
	Vector2(0.10, 0.22),
	Vector2(0.22, 0.55),
	Vector2(0.39, 0.30),
	Vector2(0.61, 0.18),
	Vector2(0.72, 0.52),
	Vector2(0.89, 0.34),
]
const OUTER_CLUSTER_ANCHORS := [
	Vector2(0.07, 0.18),
	Vector2(0.09, 0.54),
	Vector2(0.18, 0.86),
	Vector2(0.38, 0.08),
	Vector2(0.66, 0.09),
	Vector2(0.89, 0.24),
	Vector2(0.92, 0.68),
	Vector2(0.70, 0.90),
	Vector2(0.42, 0.92),
]
const STAR_SIZES := [0.48, 0.78, 1.18]
const STAR_ALPHAS := [0.34, 0.58, 0.82]
const STAR_TEMPERATURES := [
	Color("C7D7E5"),
	Color("E0E2DF"),
	Color("D9C7B4"),
]
const STARFIELD_SEED := 914027
const OUTER_STARFIELD_SEED := 741209

var stars: Array[Dictionary] = []
var outer_stars: Array[Dictionary] = []
var activity: float = 0.0
var galactic_mode: bool = false
var rng := RandomNumberGenerator.new()
var cached_size := Vector2.ZERO
var observation_view: Camera2D


func _ready() -> void:
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
	# TwinkleStars supplies the few animated points. This quieter static layer
	# leaves broad gaps for meteors while still covering later camera pull-back.
	var base_count := maxi(22, int(cached_size.x * cached_size.y / 23000.0))
	var count := int(round(float(base_count) * 1.65)) if galactic_mode else base_count
	rng.seed = STARFIELD_SEED
	for index in range(count):
		stars.append(_make_star(_sample_inner_point(index), index))
	var coverage := _background_coverage_rect()
	var extra_area := maxf(0.0, coverage.size.x * coverage.size.y - cached_size.x * cached_size.y)
	var outer_base_count := maxi(1, int(round(extra_area / 23000.0)))
	var outer_count := int(round(float(outer_base_count) * 1.65)) if galactic_mode else outer_base_count
	rng.seed = OUTER_STARFIELD_SEED
	for index in range(outer_count):
		outer_stars.append(_make_star(_sample_outer_point(coverage), 1000 + index))
	queue_redraw()


func _draw() -> void:
	var atmospheric := _atmospheric_rect()
	var size := atmospheric.size
	var sky_frame := _sky_frame_rect()
	var sky_size := sky_frame.size
	# The camera is still identity-scaled in stage 0, so this reserve is outside
	# the shipped frame. It prevents later pull-back steps from exposing an
	# unpainted border without changing today's sky.
	draw_rect(_background_coverage_rect(), Color("04070D"), true)
	# A low-contrast blue-black gradient gives the sky optical depth while staying
	# flat and graphic. It follows the visible world, never the fixed atmosphere.
	var bands := 120
	for index in range(bands):
		var t := float(index) / float(bands - 1)
		var band_y := sky_frame.position.y + t * sky_size.y
		var sky := Color("03060C")
		if t <= 0.52:
			sky = Color("03060C").lerp(Color("09131F"), smoothstep(0.0, 1.0, t / 0.52))
		else:
			sky = Color("09131F").lerp(Color("203746"), smoothstep(0.0, 1.0, (t - 0.52) / 0.48))
		sky = sky.lerp(Color("28191D"), activity * (0.06 + t * 0.10))
		draw_rect(Rect2(sky_frame.position.x, band_y, sky_size.x, sky_size.y / bands + 2.0), sky)

	_draw_airglow(sky_frame)

	for star in stars:
		_draw_star(atmospheric.position + Vector2(star.p) * size, star)
	for star in outer_stars:
		_draw_star(Vector2(star.p), star)

	# Quiet ridges establish distance below the playable sky. The near plateau
	# and observatory are the one authored focal shape beneath the moving light.
	_draw_distant_ridges(sky_frame)
	draw_colored_polygon(_horizon_ridge(sky_frame), Color("03070C"))
	_draw_observatory_silhouette(sky_frame)


func _draw_star(point: Vector2, star: Dictionary) -> void:
	var level := int(star.level)
	var star_color: Color = STAR_TEMPERATURES[int(star.temperature)]
	star_color.a = clampf(float(star.alpha) + sin(float(star.phase)) * 0.035 + activity * 0.08, 0.18, 0.92)
	# No cross rays. They were the reason a background star could occupy more
	# pixels than a meteor's head, and the sky has to stay quieter than the
	# thing the player is trying to see in it.
	draw_circle(point, _world_px(float(star.size)), star_color)
	if level == 2:
		var soft_edge := star_color
		soft_edge.a *= 0.07
		draw_circle(point, _world_px(float(star.size) * 2.15), soft_edge)


func _make_star(point: Vector2, index: int) -> Dictionary:
	var level := 0
	if index % 13 == 0:
		level = 2
	elif index % 4 == 0:
		level = 1
	var temperature_pattern := (index * 7 + 3) % 10
	var temperature := 1
	if temperature_pattern <= 2:
		temperature = 0
	elif temperature_pattern >= 8:
		temperature = 2
	return {
		"p": point,
		"level": level,
		"size": float(STAR_SIZES[level]) * rng.randf_range(0.92, 1.08),
		"alpha": float(STAR_ALPHAS[level]) * rng.randf_range(0.92, 1.04),
		"phase": rng.randf_range(0.0, TAU),
		"temperature": temperature,
	}


func _sample_inner_point(index: int) -> Vector2:
	# Three in four points belong to a loose cluster. The remaining point uses a
	# low-discrepancy walk so the field population cannot form random clumps.
	if index % 4 != 3:
		var anchor: Vector2 = INNER_CLUSTER_ANCHORS[index % INNER_CLUSTER_ANCHORS.size()]
		var offset := Vector2(_bell_sample() * 0.085, _bell_sample() * 0.060)
		return Vector2(
			clampf(anchor.x + offset.x, 0.025, 0.975),
			clampf(anchor.y + offset.y, 0.035, 0.855)
		)
	var sequence_index := float(index + 1)
	return Vector2(
		0.03 + fmod(0.173 + sequence_index * 0.61803398875, 1.0) * 0.94,
		0.04 + fmod(0.419 + sequence_index * 0.38196601125, 1.0) * 0.80
	)


func _bell_sample() -> float:
	return (rng.randf() + rng.randf() + rng.randf() - 1.5) / 1.5


func _draw_airglow(frame: Rect2) -> void:
	# Broad, nearly transparent bands suggest a real atmosphere. Their smooth
	# geometry is deliberate: no photographic Milky Way, grain, or sensor noise.
	draw_colored_polygon(_airglow_band(frame, 0.69, 0.012, 0.105), Color(0.09, 0.17, 0.24, 0.018))
	draw_colored_polygon(_airglow_band(frame, 0.74, 0.009, 0.060), Color(0.10, 0.19, 0.27, 0.022))
	draw_colored_polygon(_airglow_band(frame, 0.79, 0.006, 0.025), Color(0.12, 0.21, 0.29, 0.018))


func _airglow_band(frame: Rect2, base: float, amplitude: float, thickness: float) -> PackedVector2Array:
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var segments := 12
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		var curve := sin(t * TAU + base * 5.0) * amplitude
		curve += sin(t * PI * 1.4 + 0.8) * amplitude * 0.35
		var x := frame.position.x + frame.size.x * t
		var y := frame.position.y + frame.size.y * (base + curve)
		upper.append(Vector2(x, y - frame.size.y * thickness * 0.5))
		lower.append(Vector2(x, y + frame.size.y * thickness * 0.5))
	for index in range(lower.size() - 1, -1, -1):
		upper.append(lower[index])
	return upper


func _draw_observatory_silhouette(frame: Rect2) -> void:
	var scale := frame.size.y / 648.0
	var base := frame.position + frame.size * Vector2(0.79, 0.947)
	var dome_center := base + Vector2(0.0, -15.0) * scale
	var radius := 25.0 * scale
	var shell := Color("0B131C")
	var rim := Color("30414C")
	var ground := Color("03070C")
	var dome := PackedVector2Array()
	for index in range(33):
		var angle := PI + PI * float(index) / 32.0
		dome.append(dome_center + Vector2.from_angle(angle) * radius)
	draw_colored_polygon(dome, shell)
	draw_arc(dome_center, radius, PI * 1.08, PI * 1.87, 28, Color(rim, 0.62), 0.8 * scale, true)
	draw_rect(Rect2(base + Vector2(-28.0, -15.0) * scale, Vector2(56.0, 17.0) * scale), shell)
	draw_line(base + Vector2(-29.0, -15.0) * scale, base + Vector2(29.0, -15.0) * scale, Color(rim, 0.42), 1.0 * scale, true)
	# The open shutter, its lip and the low service wing identify a real dome.
	var shutter := PackedVector2Array([
		dome_center + Vector2(-7.0, -24.0) * scale,
		dome_center + Vector2(-2.0, -25.0) * scale,
		dome_center + Vector2(8.0, -3.0) * scale,
		dome_center + Vector2(2.0, -1.0) * scale,
	])
	draw_colored_polygon(shutter, ground)
	draw_line(shutter[1], shutter[2], Color(rim, 0.5), 0.8 * scale, true)
	draw_rect(Rect2(base + Vector2(-48.0, -9.0) * scale, Vector2(22.0, 12.0) * scale), Color("070D14"))
	draw_line(base + Vector2(-49.0, -9.0) * scale, base + Vector2(-28.0, -9.0) * scale, Color(rim, 0.34), 0.8 * scale, true)
	# One sheltered red window ties the physical station to its instrument ink.
	draw_rect(Rect2(base + Vector2(-40.0, -5.0) * scale, Vector2(7.0, 2.0) * scale), Color("714334"))
	draw_rect(Rect2(base + Vector2(13.0, -8.0) * scale, Vector2(5.0, 10.0) * scale), ground)

	var dish_base := base + Vector2(78.0, 0.0) * scale
	var pivot := dish_base + Vector2(0.0, -23.0) * scale
	var aim := Vector2(-0.62, -0.78)
	var tangent := Vector2(-aim.y, aim.x)
	var bowl := PackedVector2Array()
	for index in range(17):
		var along := lerpf(-12.0, 12.0, float(index) / 16.0)
		bowl.append(pivot + (tangent * along + aim * (along * along / 32.0)) * scale)
	draw_colored_polygon(bowl, Color("0A121A"))
	draw_polyline(bowl, Color(rim, 0.56), 0.8 * scale, true)
	draw_line(dish_base, pivot, shell, 2.5 * scale, true)
	draw_line(dish_base + Vector2(-9.0, 0.0) * scale, pivot, shell, 1.5 * scale, true)
	draw_line(pivot, pivot + aim * 13.0 * scale, Color(rim, 0.58), 1.0 * scale, true)
	draw_line(bowl[0], pivot + aim * 13.0 * scale, Color(rim, 0.36), 0.7 * scale, true)


func _draw_distant_ridges(frame: Rect2) -> void:
	var back := PackedVector2Array()
	var near := PackedVector2Array()
	# Low irregular landforms, all outside the meteor burnout safety region.
	var heights := [0.930, 0.923, 0.912, 0.919, 0.904, 0.914, 0.926, 0.919, 0.908, 0.917, 0.906, 0.917, 0.913, 0.921, 0.915, 0.924, 0.929]
	for index in range(heights.size()):
		var x := float(index) / float(heights.size() - 1)
		back.append(frame.position + frame.size * Vector2(x, float(heights[index])))
		near.append(frame.position + frame.size * Vector2(x, float(heights[(index + 5) % heights.size()]) + 0.018))
	for index in range(2):
		var ridge: PackedVector2Array = back if index == 0 else near
		ridge.append(frame.end)
		ridge.append(Vector2(frame.position.x, frame.end.y))
		draw_colored_polygon(ridge, Color("152531") if index == 0 else Color("0C1721"))


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
	var horizon_y := frame.position.y + frame.size.y * 0.952
	return PackedVector2Array([
		Vector2(frame.position.x, horizon_y + 2.0),
		Vector2(frame.position.x + frame.size.x * 0.12, horizon_y - 1.0),
		Vector2(frame.position.x + frame.size.x * 0.27, horizon_y + 1.0),
		Vector2(frame.position.x + frame.size.x * 0.44, horizon_y - 2.0),
		Vector2(frame.position.x + frame.size.x * 0.62, horizon_y + 1.0),
		Vector2(frame.position.x + frame.size.x * 0.74, horizon_y - frame.size.y * 0.005),
		Vector2(frame.position.x + frame.size.x * 0.88, horizon_y - frame.size.y * 0.005),
		Vector2(frame.end.x, horizon_y + 2.0),
		frame.end,
		Vector2(frame.position.x, frame.end.y),
	])


func _sample_outer_point(coverage: Rect2) -> Vector2:
	var atmospheric := _atmospheric_rect()
	for _attempt in range(48):
		var anchor: Vector2 = OUTER_CLUSTER_ANCHORS[rng.randi_range(0, OUTER_CLUSTER_ANCHORS.size() - 1)]
		var normalized := anchor + Vector2(_bell_sample() * 0.065, _bell_sample() * 0.055)
		normalized.x = clampf(normalized.x, 0.015, 0.985)
		normalized.y = clampf(normalized.y, 0.025, 0.950)
		var point := coverage.position + normalized * coverage.size
		if not atmospheric.has_point(point):
			return point
	return coverage.position + coverage.size * Vector2(0.02, 0.02)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
