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
	var bands := 36
	for index in range(bands):
		var t := float(index) / float(bands - 1)
		var top := Color("050a1c").lerp(Color("102747"), t)
		var storm_tint := Color("291e45")
		top = top.lerp(storm_tint, activity * (0.08 + t * 0.12))
		draw_rect(Rect2(0.0, t * size.y, size.x, size.y / bands + 2.0), top)

	for star in stars:
		var p: Vector2 = star.p * size
		var pulse := 0.62 + sin(float(star.phase)) * 0.16
		pulse += activity * 0.12
		var star_color := Color("c8ddff").lerp(Color("ffffff"), float(star.blue))
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
	draw_colored_polygon(ridge, Color("030713"))
	var dome_center := Vector2(size.x * 0.16, horizon_y - 3)
	draw_circle(dome_center, 23.0, Color("060b19"))
	draw_rect(Rect2(dome_center.x - 25.0, dome_center.y, 50.0, 25.0), Color("060b19"))
	draw_line(dome_center + Vector2(0, -22), dome_center + Vector2(14, -36), Color("111e30"), 3.0)
	draw_circle(dome_center + Vector2(15, -37), 2.0, Color("6b8cae"))
