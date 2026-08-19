extends Node2D

var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var incoming_markers: Array[Dictionary] = []
var flash_strength: float = 0.0
var flash_color := Color.WHITE
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	queue_redraw()
	set_process(false)


func reset() -> void:
	particles.clear()
	popups.clear()
	incoming_markers.clear()
	flash_strength = 0.0
	queue_redraw()
	set_process(false)


func spawn_success(world_position: Vector2, amount: float, color: Color, multiplier: float) -> void:
	for index in range(18):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(38.0, 145.0)
		particles.append({
			"p": world_position,
			"v": Vector2.from_angle(angle) * speed,
			"life": rng.randf_range(0.38, 0.72),
			"max_life": 0.72,
			"color": color,
			"size": rng.randf_range(1.0, 3.0)
		})
	var suffix := "  x%.2f" % multiplier if multiplier > 1.01 else ""
	popups.append({
		"p": world_position + Vector2(0, -20),
		"v": Vector2(0, -30),
		"life": 1.35,
		"text": "OBSERVED  +%d%s" % [int(amount), suffix],
		"color": color
	})
	flash_color = color
	flash_strength = maxf(flash_strength, 0.11)
	set_process(true)
	queue_redraw()


func spawn_upgrade_pulse() -> void:
	flash_color = Color("79d9ff")
	flash_strength = maxf(flash_strength, 0.07)
	set_process(true)
	queue_redraw()


func spawn_incoming(start_position: Vector2, velocity: Vector2, color: Color) -> void:
	var size := get_viewport_rect().size
	var marker_position := Vector2(
		clampf(start_position.x, 34.0, size.x - 34.0),
		clampf(start_position.y, 34.0, size.y - 76.0)
	)
	incoming_markers.append({
		"p": marker_position,
		"dir": velocity.normalized(),
		"life": 1.45,
		"color": color,
		"forecast": false
	})
	set_process(true)
	queue_redraw()


func spawn_forecast(entry_points: Array) -> void:
	var center := get_viewport_rect().size * 0.5
	for point in entry_points:
		incoming_markers.append({
			"p": point,
			"dir": (center - point).normalized(),
			"life": 3.0,
			"color": Color("c3a9ff"),
			"forecast": true
		})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	flash_strength = move_toward(flash_strength, 0.0, delta * 0.42)
	for index in range(particles.size() - 1, -1, -1):
		var particle := particles[index]
		particle.life = float(particle.life) - delta
		particle.p = Vector2(particle.p) + Vector2(particle.v) * delta
		particle.v = Vector2(particle.v) * pow(0.12, delta)
		particles[index] = particle
		if float(particle.life) <= 0.0:
			particles.remove_at(index)
	for index in range(popups.size() - 1, -1, -1):
		var popup := popups[index]
		popup.life = float(popup.life) - delta
		popup.p = Vector2(popup.p) + Vector2(popup.v) * delta
		popup.v = Vector2(popup.v) * pow(0.2, delta)
		popups[index] = popup
		if float(popup.life) <= 0.0:
			popups.remove_at(index)
	for index in range(incoming_markers.size() - 1, -1, -1):
		var marker := incoming_markers[index]
		marker.life = float(marker.life) - delta
		incoming_markers[index] = marker
		if float(marker.life) <= 0.0:
			incoming_markers.remove_at(index)
	queue_redraw()
	if particles.is_empty() and popups.is_empty() and incoming_markers.is_empty() and flash_strength <= 0.001:
		set_process(false)


func _draw() -> void:
	for particle in particles:
		var alpha := clampf(float(particle.life) / float(particle.max_life), 0.0, 1.0)
		draw_circle(particle.p, float(particle.size) * alpha, Color(particle.color, alpha * 0.9))
	for popup in popups:
		var alpha := clampf(float(popup.life) / 0.45, 0.0, 1.0)
		var font := ThemeDB.fallback_font
		draw_string(font, popup.p, String(popup.text), HORIZONTAL_ALIGNMENT_CENTER, -1.0, 17, Color(popup.color, alpha))
	for marker in incoming_markers:
		var alpha := clampf(float(marker.life) / 0.4, 0.0, 1.0)
		var pulse := 1.0 + sin(float(marker.life) * 16.0) * 0.12
		var p: Vector2 = marker.p
		var direction: Vector2 = marker.dir
		var side := Vector2(-direction.y, direction.x)
		var tip := p + direction * 13.0 * pulse
		var arrow := PackedVector2Array([tip, p - direction * 7.0 + side * 7.0, p - direction * 7.0 - side * 7.0])
		draw_colored_polygon(arrow, Color(marker.color, alpha * 0.72))
		draw_arc(p, 23.0 * pulse, 0.0, TAU, 28, Color(marker.color, alpha * 0.28), 1.4, true)
		if bool(marker.get("forecast", false)):
			draw_arc(p, 34.0 * pulse, -PI * 0.75, PI * 0.75, 24, Color(marker.color, alpha * 0.5), 2.0, true)
			draw_line(p + direction * 18.0, p + direction * 58.0, Color(marker.color, alpha * 0.22), 1.2, true)
	if flash_strength > 0.001:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(flash_color, flash_strength), true)
