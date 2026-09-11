extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const ArrivalVisual = preload("res://scripts/arrival_visual.gd")
const CircleInstances = preload("res://scripts/circle_instances.gd")

signal packet_landed(amount: float)

const MAX_PARTICLES := 220
const MAX_POPUPS := 16
const MAX_INCOMING_MARKERS := 24
const MAX_RINGS := 10
const MAX_SHAKE_OFFSET := 9.0
const SHAKE_DECAY := 2.6
# A separate channel from trauma. Trauma is squared before it reaches pixels, so
# a small value lands under half a pixel and shows nothing; a directional punch
# stays legible down here, and at low amplitude direction reads as force where
# random jitter reads as a rendering fault.
const MAX_KICK_OFFSET := 3.4
const KICK_DURATION := 0.15
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
var shake_pixel_scale: float = 1.0
var shake_offset := Vector2.ZERO
var shake_time: float = 0.0
var shake_enabled: bool = true
var motion_intensity: float = 1.0
var screen_flashes_enabled: bool = true
var kick_direction := Vector2.ZERO
var kick_amplitude: float = 0.0
var kick_time: float = 0.0
var kick_offset := Vector2.ZERO
var view_offset := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var observation_view: Camera2D
var particle_instances: RefCounted


func _ready() -> void:
	rng.randomize()
	# Headless probes share this script. Leaving the canvas transform untouched
	# there keeps measurement runs identical to the pre-shake baselines.
	shake_enabled = DisplayServer.get_name() != "headless"
	queue_redraw()
	set_process(false)


func setup(view: Camera2D) -> void:
	observation_view = view
	_apply_view_transform()


func set_accessibility_effects(requested_motion_intensity: float, flashes_enabled: bool) -> void:
	var previous_motion_intensity := motion_intensity
	var next_motion_intensity := clampf(requested_motion_intensity, 0.0, 1.0)
	if next_motion_intensity < previous_motion_intensity and previous_motion_intensity > 0.0:
		var reduction := next_motion_intensity / previous_motion_intensity
		shake_trauma *= reduction
		kick_amplitude *= reduction
		_update_shake(0.0)
		_update_kick(0.0)
		_update_view_offset()
	motion_intensity = next_motion_intensity
	screen_flashes_enabled = flashes_enabled
	if not screen_flashes_enabled:
		flash_strength = 0.0
	if is_zero_approx(motion_intensity):
		shake_trauma = 0.0
		shake_offset = Vector2.ZERO
		kick_amplitude = 0.0
		kick_offset = Vector2.ZERO
		view_offset = Vector2.ZERO
		_apply_view_transform()
	queue_redraw()


func _exit_tree() -> void:
	shake_offset = Vector2.ZERO
	kick_offset = Vector2.ZERO
	view_offset = Vector2.ZERO
	_apply_view_transform()


func reset() -> void:
	particles.clear()
	popups.clear()
	incoming_markers.clear()
	rings.clear()
	flash_strength = 0.0
	shake_trauma = 0.0
	shake_pixel_scale = 1.0
	shake_time = 0.0
	shake_offset = Vector2.ZERO
	kick_direction = Vector2.ZERO
	kick_amplitude = 0.0
	kick_time = 0.0
	kick_offset = Vector2.ZERO
	view_offset = Vector2.ZERO
	_apply_view_transform()
	queue_redraw()
	set_process(false)


func spawn_success(world_position: Vector2, amount: float, color: Color, multiplier: float, strength: float = 0.0, grade: String = "", anchor: Vector2 = Vector2.ZERO, flash_scale: float = 1.0, accented: bool = false, direction: Vector2 = Vector2.ZERO) -> void:
	var power := clampf(strength, 0.0, 1.0)
	var burst := int(round(lerpf(10.0, 34.0, power)))
	var available_particle_slots := maxi(0, MAX_PARTICLES - particles.size())
	var speed_ceiling := lerpf(120.0, 305.0, power)
	var life_ceiling := lerpf(0.72, 1.05, power)
	var size_ceiling := lerpf(3.0, 5.2, power)
	for index in range(mini(burst, available_particle_slots)):
		# Routine completions continue the target's travel instead of making a
		# radial explosion. Identity/quality, not accumulated power, owns accent.
		var heading := direction.angle() if not direction.is_zero_approx() else -PI * 0.5
		var angle := rng.randf_range(0.0, TAU) if accented else heading + rng.randf_range(-0.55, 0.55)
		var speed := rng.randf_range(38.0, speed_ceiling)
		var life := rng.randf_range(0.38, life_ceiling)
		particles.append({
			"p": world_position,
			"v": Vector2.from_angle(angle) * _world_px(speed),
			"life": life,
			"max_life": life,
			"color": color,
			"size": rng.randf_range(1.0, size_ceiling)
		})

	if accented and power >= 0.22 and rings.size() < MAX_RINGS:
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

	# Ungraded/automatic packets below the text threshold ship as silent motes. At observation
	# rates past a few per second the numbers overlap into an unreadable stack,
	# and the flow toward the counter is the part that has to stay legible.
	var label := ""
	var has_manual_grade := grade in ["GOOD", "EXCELLENT", "PERFECT"]
	if has_manual_grade or power >= PACKET_TEXT_STRENGTH or multiplier > 1.01:
		var prefix := ""
		if has_manual_grade:
			prefix = "%s  " % tr("QUALITY_%s" % grade)
		var suffix := "  x%.2f" % multiplier if multiplier > 1.01 else ""
		label = "%s+%d%s" % [prefix, int(amount), suffix]
	if popups.size() >= MAX_POPUPS:
		popups.remove_at(0)
	var start := world_position + Vector2(0, -_world_px(20.0))
	popups.append({
		"p": start,
		"origin": start,
		"v": Vector2(_world_px(rng.randf_range(-16.0, 16.0)), -_world_px(32.0)),
		"age": 0.0,
		"alpha": 1.0,
		"text": label,
		"color": color,
		"font_size": int(round(lerpf(15.0, 26.0, power))),
		"mote_size": lerpf(2.6, 5.4, power),
		"amount": amount,
		"anchor": anchor,
		"bow": _world_px(rng.randf_range(-34.0, 34.0))
	})

	var scaled_flash := lerpf(0.07, 0.26, power) * maxf(0.0, flash_scale)
	if screen_flashes_enabled and accented and scaled_flash > 0.0:
		flash_color = color
		flash_strength = maxf(flash_strength, scaled_flash)
	set_process(true)
	queue_redraw()


func add_shake(amount: float, pixel_scale: float = 1.0) -> void:
	var addition := maxf(amount, 0.0) * motion_intensity
	if addition <= 0.0:
		return
	shake_trauma = minf(1.0, shake_trauma + addition)
	shake_pixel_scale = maxf(0.0, pixel_scale)
	set_process(true)


func add_kick(from_point: Vector2, amount: float, pixel_scale: float = 1.0) -> void:
	var scaled_amount := amount * maxf(0.0, pixel_scale) * motion_intensity
	if scaled_amount <= 0.0:
		return
	# Overwrite instead of accumulating. A manual chain lands several
	# observations a second and a summing kick would fuse them into one drift
	# instead of reading as separate hits.
	if absf(_kick_envelope()) * kick_amplitude > scaled_amount:
		return
	var away := from_point - _atmospheric_rect().get_center()
	kick_direction = away.normalized() if away.length() > 1.0 else Vector2.UP
	kick_amplitude = minf(scaled_amount, MAX_KICK_OFFSET)
	kick_time = 0.0
	set_process(true)


func spawn_incoming(start_position: Vector2, velocity: Vector2, color: Color) -> void:
	var atmospheric := _atmospheric_rect()
	var marker_position := Vector2(
		clampf(start_position.x, atmospheric.position.x + _world_px(34.0), atmospheric.end.x - _world_px(34.0)),
		clampf(start_position.y, atmospheric.position.y + _world_px(34.0), atmospheric.end.y - _world_px(76.0))
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
	var center := _atmospheric_rect().get_center()
	for point in entry_points:
		if incoming_markers.size() >= MAX_INCOMING_MARKERS:
			break
		incoming_markers.append({
			"p": point,
			"dir": (center - point).normalized(),
			"life": 3.0,
			"color": UITheme.ACCENT_TEXT,
			"forecast": true
		})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	flash_strength = move_toward(flash_strength, 0.0, delta * (0.42 + flash_strength * 3.4))
	_update_shake(delta)
	_update_kick(delta)
	_update_view_offset()
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
	if particles.is_empty() and popups.is_empty() and incoming_markers.is_empty() and rings.is_empty() and flash_strength <= 0.001 and shake_trauma <= 0.0 and kick_amplitude <= 0.0:
		set_process(false)


func _update_shake(delta: float) -> void:
	if shake_trauma <= 0.0:
		shake_pixel_scale = 1.0
		shake_offset = Vector2.ZERO
		return
	shake_time += delta
	shake_trauma = maxf(0.0, shake_trauma - delta * SHAKE_DECAY)
	# Squaring trauma keeps small hits subtle while leaving headroom for a major.
	var magnitude := shake_trauma * shake_trauma * MAX_SHAKE_OFFSET * shake_pixel_scale
	shake_offset = Vector2(
		sin(shake_time * 73.0) * magnitude,
		sin(shake_time * 61.0 + 1.9) * magnitude
	)


func _kick_envelope() -> float:
	if kick_time >= KICK_DURATION:
		return 0.0
	# One snap out and back rather than a decay to zero. A plain decay at two
	# pixels reads as the view sliding; the return through zero reads as a hit.
	return exp(-kick_time * 21.0) * cos(kick_time * 40.0)


func _update_kick(delta: float) -> void:
	if kick_amplitude <= 0.0:
		kick_offset = Vector2.ZERO
		return
	kick_time += delta
	if kick_time >= KICK_DURATION:
		kick_amplitude = 0.0
		kick_offset = Vector2.ZERO
		return
	# Negated: the view recoils away from where the observation landed.
	kick_offset = -kick_direction * kick_amplitude * _kick_envelope()


func _update_view_offset() -> void:
	var combined := shake_offset + kick_offset
	if combined == view_offset:
		return
	view_offset = combined
	_apply_view_transform()


func _apply_view_transform() -> void:
	if not shake_enabled or not is_inside_tree():
		return
	if is_instance_valid(observation_view):
		# Camera2D offset moves the camera, so negate it to move the rendered
		# world in the same screen direction as the former canvas origin.
		observation_view.offset = -view_offset * _world_px(1.0)
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
	canvas.origin = view_offset
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
		var target: Vector2 = observation_view.screen_to_world(anchor) if is_instance_valid(observation_view) else anchor - view_offset
		var straight := origin.lerp(target, eased)
		var travel: Vector2 = target - origin
		var side := Vector2(-travel.y, travel.x).normalized()
		popup.p = straight + side * sin(eased * PI) * float(popup.bow)
		popup.alpha = 1.0 - eased * 0.30
		popups[index] = popup
		if flight >= 1.0:
			popups.remove_at(index)
			packet_landed.emit(float(popup.amount))


func _draw() -> void:
	var visual_scale := _world_px(1.0)
	_draw_particles(visual_scale)
	for ring in rings:
		var progress := 1.0 - clampf(float(ring.life) / maxf(float(ring.max_life), 0.001), 0.0, 1.0)
		var radius := lerpf(float(ring.radius_start), float(ring.radius_end), progress)
		draw_arc(ring.p, radius * visual_scale, 0.0, TAU, 44, Color(ring.color, (1.0 - progress) * 0.55), float(ring.width) * visual_scale, true)
	for popup in popups:
		var alpha := clampf(float(popup.alpha), 0.0, 1.0)
		var text := String(popup.text)
		if text.is_empty():
			var mote := float(popup.mote_size)
			draw_circle(popup.p, mote * 2.4 * visual_scale, Color(popup.color, alpha * 0.16))
			draw_circle(popup.p, mote * visual_scale, Color(popup.color, alpha * 0.92))
			continue
		var font := UITheme.sans()
		draw_string(font, popup.p, text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(round(float(popup.font_size) * visual_scale)), Color(popup.color, alpha))
	for marker in incoming_markers:
		var alpha := clampf(float(marker.life) / 0.4, 0.0, 1.0)
		var forecast := bool(marker.get("forecast", false))
		var duration := 3.0 if forecast else 1.45
		alpha *= smoothstep(0.0, 0.12, duration - float(marker.life))
		var p := ArrivalVisual.edge_point(Vector2(marker.p), _visible_world_rect(), visual_scale)
		var direction: Vector2 = marker.dir
		# One fading stroke is enough to indicate the entry direction.
		var ink := UITheme.ACCENT_LINE
		var reach := 38.0 if forecast else 26.0
		ArrivalVisual.draw_direction(self, p, direction, visual_scale, ink, alpha, reach)
	if flash_strength > 0.001:
		# Grown by the shake budget so a displaced canvas cannot expose an
		# unpainted strip along the edge the screen shook away from.
		var margin := Vector2.ONE * _world_px(MAX_SHAKE_OFFSET + MAX_KICK_OFFSET + 2.0)
		draw_rect(_visible_world_rect().grow(margin.x), Color(flash_color, flash_strength), true)


func _draw_particles(visual_scale: float) -> void:
	if particle_instances == null:
		particle_instances = CircleInstances.new(MAX_PARTICLES)
	particle_instances.begin()
	for particle in particles:
		var alpha := clampf(float(particle.life) / maxf(float(particle.max_life), 0.001), 0.0, 1.0)
		particle_instances.append(particle.p, float(particle.size) * alpha * visual_scale, Color(particle.color, alpha * 0.9))
	particle_instances.draw(self)


func _atmospheric_rect() -> Rect2:
	if is_instance_valid(observation_view):
		return observation_view.atmospheric_rect()
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _visible_world_rect() -> Rect2:
	if is_instance_valid(observation_view):
		return observation_view.visible_world_rect()
	return _atmospheric_rect()


func _world_px(pixels: float) -> float:
	if is_instance_valid(observation_view):
		return observation_view.screen_length_to_world(pixels)
	return pixels
