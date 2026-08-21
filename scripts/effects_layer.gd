extends Node2D

signal packet_landed(amount: float)

const MAX_PARTICLES := 220
const MAX_POPUPS := 16
const MAX_INCOMING_MARKERS := 24
const MAX_RINGS := 10
const MAX_SHAKE_OFFSET := 9.0
const SHAKE_DECAY := 2.6
# A packet reads as a readout first and cargo second: it lifts off the meteor,
# then commits to the counter. Without the pause the number never registers.
const PACKET_RISE_TIME := 0.26
const PACKET_FLIGHT_TIME := 0.44
const PACKET_TEXT_STRENGTH := 0.30

var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = []
var incoming_markers: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var flash_strength: float = 0.0
var flash_color := Color.WHITE
var shake_trauma: float = 0.0
var shake_offset := Vector2.ZERO
var shake_time: float = 0.0
var shake_enabled: bool = true
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	# Headless probes share this script. Leaving the canvas transform untouched
	# there keeps measurement runs identical to the pre-shake baselines.
	shake_enabled = DisplayServer.get_name() != "headless"
	queue_redraw()
	set_process(false)


func _exit_tree() -> void:
	shake_offset = Vector2.ZERO
	_apply_shake_transform()


func reset() -> void:
	particles.clear()
	popups.clear()
	incoming_markers.clear()
	rings.clear()
	flash_strength = 0.0
	shake_trauma = 0.0
	shake_time = 0.0
	shake_offset = Vector2.ZERO
	_apply_shake_transform()
	queue_redraw()
	set_process(false)


func spawn_success(world_position: Vector2, amount: float, color: Color, multiplier: float, strength: float = 0.0, grade: String = "", anchor: Vector2 = Vector2.ZERO) -> void:
	var power := clampf(strength, 0.0, 1.0)
	var burst := int(round(lerpf(10.0, 34.0, power)))
	var available_particle_slots := maxi(0, MAX_PARTICLES - particles.size())
	var speed_ceiling := lerpf(120.0, 305.0, power)
	var life_ceiling := lerpf(0.72, 1.05, power)
	var size_ceiling := lerpf(3.0, 5.2, power)
	for index in range(mini(burst, available_particle_slots)):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(38.0, speed_ceiling)
		var life := rng.randf_range(0.38, life_ceiling)
		particles.append({
			"p": world_position,
			"v": Vector2.from_angle(angle) * speed,
			"life": life,
			"max_life": life,
			"color": color,
			"size": rng.randf_range(1.0, size_ceiling)
		})

	if power >= 0.22 and rings.size() < MAX_RINGS:
		var ring_life := lerpf(0.28, 0.52, power)
		rings.append({
			"p": world_position,
			"life": ring_life,
			"max_life": ring_life,
			"radius_start": 6.0,
			"radius_end": lerpf(46.0, 148.0, power),
			"width": lerpf(1.4, 3.4, power),
			"color": color
		})

	# Below the text threshold a packet ships as a silent mote. At observation
	# rates past a few per second the numbers overlap into an unreadable stack,
	# and the flow toward the counter is the part that has to stay legible.
	var label := ""
	if power >= PACKET_TEXT_STRENGTH or multiplier > 1.01:
		var prefix := ""
		if grade == "PERFECT" or grade == "EXCELLENT":
			prefix = "%s  " % grade
		var suffix := "  x%.2f" % multiplier if multiplier > 1.01 else ""
		label = "%s+%d%s" % [prefix, int(amount), suffix]
	if popups.size() >= MAX_POPUPS:
		popups.remove_at(0)
	var start := world_position + Vector2(0, -20)
	popups.append({
		"p": start,
		"origin": start,
		"v": Vector2(rng.randf_range(-16.0, 16.0), -32.0),
		"age": 0.0,
		"alpha": 1.0,
		"text": label,
		"color": color,
		"font_size": int(round(lerpf(15.0, 26.0, power))),
		"mote_size": lerpf(2.6, 5.4, power),
		"amount": amount,
		"anchor": anchor,
		"bow": rng.randf_range(-34.0, 34.0)
	})

	flash_color = color
	flash_strength = maxf(flash_strength, lerpf(0.07, 0.26, power))
	set_process(true)
	queue_redraw()


func add_shake(amount: float) -> void:
	shake_trauma = minf(1.0, shake_trauma + maxf(amount, 0.0))
	set_process(true)


func spawn_upgrade_pulse() -> void:
	flash_color = Color("79d9ff")
	flash_strength = maxf(flash_strength, 0.07)
	add_shake(0.18)
	set_process(true)
	queue_redraw()


func spawn_incoming(start_position: Vector2, velocity: Vector2, color: Color) -> void:
	var size := get_viewport_rect().size
	var marker_position := Vector2(
		clampf(start_position.x, 34.0, size.x - 34.0),
		clampf(start_position.y, 34.0, size.y - 76.0)
	)
	if incoming_markers.size() >= MAX_INCOMING_MARKERS:
		incoming_markers.remove_at(0)
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
		if incoming_markers.size() >= MAX_INCOMING_MARKERS:
			break
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
	flash_strength = move_toward(flash_strength, 0.0, delta * (0.42 + flash_strength * 3.4))
	_update_shake(delta)
	for index in range(particles.size() - 1, -1, -1):
		var particle := particles[index]
		particle.life = float(particle.life) - delta
		particle.p = Vector2(particle.p) + Vector2(particle.v) * delta
		particle.v = Vector2(particle.v) * pow(0.12, delta)
		particles[index] = particle
		if float(particle.life) <= 0.0:
			particles.remove_at(index)
	for index in range(rings.size() - 1, -1, -1):
		var ring := rings[index]
		ring.life = float(ring.life) - delta
		rings[index] = ring
		if float(ring.life) <= 0.0:
			rings.remove_at(index)
	_update_packets(delta)
	for index in range(incoming_markers.size() - 1, -1, -1):
		var marker := incoming_markers[index]
		marker.life = float(marker.life) - delta
		incoming_markers[index] = marker
		if float(marker.life) <= 0.0:
			incoming_markers.remove_at(index)
	queue_redraw()
	if particles.is_empty() and popups.is_empty() and incoming_markers.is_empty() and rings.is_empty() and flash_strength <= 0.001 and shake_trauma <= 0.0:
		set_process(false)


func _update_shake(delta: float) -> void:
	if shake_trauma <= 0.0:
		if shake_offset != Vector2.ZERO:
			shake_offset = Vector2.ZERO
			_apply_shake_transform()
		return
	shake_time += delta
	shake_trauma = maxf(0.0, shake_trauma - delta * SHAKE_DECAY)
	# Squaring trauma keeps small hits subtle while leaving headroom for a major.
	var magnitude := shake_trauma * shake_trauma * MAX_SHAKE_OFFSET
	shake_offset = Vector2(
		sin(shake_time * 73.0) * magnitude,
		sin(shake_time * 61.0 + 1.9) * magnitude
	)
	_apply_shake_transform()


func _apply_shake_transform() -> void:
	if not shake_enabled or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	# canvas_transform is a render-only offset. No global_position on any node
	# moves, so cursor distance, tracking quality and dish coverage are untouched
	# by a shake, and the HUD holds still because CanvasLayers carry their own
	# transform. The drawn cursor lives in this canvas too, so it shakes with the
	# sky and stays exactly where the game thinks it is relative to a meteor.
	var canvas := viewport.canvas_transform
	canvas.origin = shake_offset
	viewport.canvas_transform = canvas


func _update_packets(delta: float) -> void:
	for index in range(popups.size() - 1, -1, -1):
		var popup := popups[index]
		var age := float(popup.age) + delta
		popup.age = age
		var anchor: Vector2 = popup.anchor
		if anchor == Vector2.ZERO:
			# No delivery target bound: drift and fade like the old readout.
			popup.p = Vector2(popup.p) + Vector2(popup.v) * delta
			popup.v = Vector2(popup.v) * pow(0.2, delta)
			popup.alpha = clampf((1.35 - age) / 0.45, 0.0, 1.0)
			popups[index] = popup
			if age >= 1.35:
				popups.remove_at(index)
			continue
		if age < PACKET_RISE_TIME:
			popup.p = Vector2(popup.p) + Vector2(popup.v) * delta
			popup.v = Vector2(popup.v) * pow(0.2, delta)
			popup.origin = popup.p
			popup.alpha = 1.0
			popups[index] = popup
			continue
		var flight := clampf((age - PACKET_RISE_TIME) / PACKET_FLIGHT_TIME, 0.0, 1.0)
		var eased := flight * flight * (3.0 - 2.0 * flight)
		var origin: Vector2 = popup.origin
		var target := anchor - shake_offset
		var straight := origin.lerp(target, eased)
		var travel := target - origin
		var side := Vector2(-travel.y, travel.x).normalized()
		popup.p = straight + side * sin(eased * PI) * float(popup.bow)
		popup.alpha = 1.0 - eased * 0.30
		popups[index] = popup
		if flight >= 1.0:
			popups.remove_at(index)
			packet_landed.emit(float(popup.amount))


func _draw() -> void:
	for particle in particles:
		var alpha := clampf(float(particle.life) / maxf(float(particle.max_life), 0.001), 0.0, 1.0)
		draw_circle(particle.p, float(particle.size) * alpha, Color(particle.color, alpha * 0.9))
	for ring in rings:
		var progress := 1.0 - clampf(float(ring.life) / maxf(float(ring.max_life), 0.001), 0.0, 1.0)
		var radius := lerpf(float(ring.radius_start), float(ring.radius_end), progress)
		draw_arc(ring.p, radius, 0.0, TAU, 44, Color(ring.color, (1.0 - progress) * 0.55), float(ring.width), true)
	for popup in popups:
		var alpha := clampf(float(popup.alpha), 0.0, 1.0)
		var text := String(popup.text)
		if text.is_empty():
			var mote := float(popup.mote_size)
			draw_circle(popup.p, mote * 2.4, Color(popup.color, alpha * 0.16))
			draw_circle(popup.p, mote, Color(popup.color, alpha * 0.92))
			continue
		var font := ThemeDB.fallback_font
		draw_string(font, popup.p, text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(popup.font_size), Color(popup.color, alpha))
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
		# Grown by the shake budget so a displaced canvas cannot expose an
		# unpainted strip along the edge the screen shook away from.
		var margin := Vector2.ONE * (MAX_SHAKE_OFFSET + 2.0)
		draw_rect(Rect2(-margin, get_viewport_rect().size + margin * 2.0), Color(flash_color, flash_strength), true)
