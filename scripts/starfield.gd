extends Node2D

var stars: Array[Dictionary] = []
var activity: float = 0.0
var rng := RandomNumberGenerator.new()
var cached_size := Vector2.ZERO


func _ready() -> void:
	rng.seed = 914027
	_rebuild_stars()
	get_viewport().size_changed.connect(_rebuild_stars)
	queue_redraw()


func set_activity(value: float) -> void:
	var next_activity := clampf(value, 0.0, 1.0)
	if is_equal_approx(next_activity, activity):
		return
	activity = next_activity
	# The expensive full background is rebuilt only when event tint changes.
	queue_redraw()


func _rebuild_stars() -> void:
	cached_size = get_viewport_rect().size
	stars.clear()
	var count := maxi(160, int(cached_size.x * cached_size.y / 4800.0))
	for index in range(count):
		var normalized := Vector2(rng.randf(), pow(rng.randf(), 1.1) * 0.88)
		stars.append({
			"p": normalized,
			"size": rng.randf_range(0.55, 1.75),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.35, 1.2),
			"blue": rng.randf_range(0.0, 1.0)
		})
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	# Layered bands give a restrained vertical night-sky gradient without textures.
	# A radial well centred just below the frame, so the sky is darkest overhead
	# and the red-light information layer never competes with a blue field.
	var bands := 120
	var origin := Vector2(size.x * 0.5, size.y * 1.08)
	var reach := Vector2(size.x * 1.2, size.y * 0.9).length() * 0.5
	for index in range(bands):
		var t := float(index) / float(bands - 1)
		var band_y := (1.0 - t) * size.y
		var distance := clampf(absf(band_y - origin.y) / maxf(reach, 1.0), 0.0, 1.0)
		var sky := Color("05070C")
		if distance <= 0.34:
			sky = Color("14202D").lerp(Color("050911"), smoothstep(0.0, 1.0, distance / 0.34))
		elif distance <= 0.72:
			sky = Color("050911").lerp(Color("05070C"), smoothstep(0.0, 1.0, (distance - 0.34) / 0.38))
		sky = sky.lerp(Color("2A1A1E"), activity * (0.06 + (1.0 - t) * 0.10))
		draw_rect(Rect2(0.0, band_y - size.y / bands, size.x, size.y / bands + 2.0), sky)

	for star in stars:
		var p: Vector2 = star.p * size
		var pulse := 0.62 + sin(float(star.phase)) * 0.16
		pulse += activity * 0.12
		var star_color := Color("d9dee6").lerp(Color("ffffff"), float(star.blue))
		star_color.a = clampf(pulse, 0.22, 1.0)
		var radius := float(star.size)
		draw_circle(p, radius, star_color)
		if radius > 1.35 and pulse > 0.72:
			draw_line(p - Vector2(radius * 2.2, 0), p + Vector2(radius * 2.2, 0), Color(star_color, pulse * 0.2), 0.7)

	# A quiet, low-contrast horizon and small observatory establish scale.
	var horizon_y := size.y * 0.91
	var ridge := PackedVector2Array([
		Vector2(0, horizon_y + 8), Vector2(size.x * 0.12, horizon_y - 5),
		Vector2(size.x * 0.27, horizon_y + 2), Vector2(size.x * 0.44, horizon_y - 12),
		Vector2(size.x * 0.62, horizon_y + 3), Vector2(size.x * 0.81, horizon_y - 7),
		Vector2(size.x, horizon_y + 4), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	draw_colored_polygon(ridge, Color("03050A"))
	var dome_center := Vector2(size.x * 0.16, horizon_y - 3)
	draw_circle(dome_center, 23.0, Color("06080F"))
	draw_rect(Rect2(dome_center.x - 25.0, dome_center.y, 50.0, 25.0), Color("06080F"))
	draw_line(dome_center + Vector2(0, -22), dome_center + Vector2(14, -36), Color("1A1712"), 3.0)
	draw_circle(dome_center + Vector2(15, -37), 2.0, Color("A15D3E"))
