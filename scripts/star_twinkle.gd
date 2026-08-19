extends Node2D

const TWINKLE_FPS := 30.0
const TWINKLE_COUNT := 28

var stars: Array[Dictionary] = []
var time: float = 0.0
var redraw_accumulator: float = 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 527913
	for index in range(TWINKLE_COUNT):
		stars.append({
			"p": Vector2(rng.randf(), pow(rng.randf(), 1.15) * 0.86),
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
	var viewport_size := get_viewport_rect().size
	for star in stars:
		var pulse := 0.48 + sin(time * float(star.speed) + float(star.phase)) * 0.38
		var alpha := clampf(pulse, 0.08, 0.86)
		var position: Vector2 = star.p * viewport_size
		var radius := float(star.size)
		draw_circle(position, radius, Color(0.76, 0.89, 1.0, alpha))
		if pulse > 0.72:
			draw_line(position - Vector2(radius * 2.0, 0), position + Vector2(radius * 2.0, 0), Color(0.75, 0.9, 1.0, alpha * 0.18), 0.7)
