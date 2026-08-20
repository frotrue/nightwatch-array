extends Node2D

# Layer 2 probe: does "read uncertain signals, commit limited instruments,
# watch what you gave up" carry 90 seconds on its own?
#
# Deliberately excluded so a failure here is unambiguous: no research tree, no
# saves, no layer transition, no balance pass. Only the decision.

const Balance = preload("res://scripts/game_balance.gd")
const MeteorScript = preload("res://scripts/meteor.gd")
const SoundSynth = preload("res://scripts/sound_synth.gd")

const PROBE_DURATION := 90.0
const SIGNAL_LEAD_TIME := 4.5
const INTERCEPT_DISTANCE := 190.0
const INSTRUMENT_COUNT := 2
const SLEW_SPEED := 420.0
# Below the 390 of a fast meteor on purpose: a dish cannot hold the quick ones,
# so the player stays the only instrument that can.
const TRACK_SPEED := 330.0
const COVERAGE_RADIUS := 105.0
const SCAN_RATE := 0.45
const CURSOR_RADIUS := 46.0
const SIGNAL_HIT_RADIUS := 30.0
const MAX_ESTIMATE_ERROR := 74.0

# Signal pressure climbs so the last third is the crunch we actually want to
# read: more signals than instruments, every few seconds.
const WAVES := [
	{"until": 25.0, "interval": 5.0},
	{"until": 60.0, "interval": 3.4},
	{"until": PROBE_DURATION, "interval": 2.0},
]

# An unclassified signal is the gamble: it is usually common, sometimes the
# fireball that was worth abandoning something else for.
const CLASSIFIED_TYPES := ["common", "common", "fast"]
const UNCLASSIFIED_TYPES := ["common", "fast", "fireball", "common", "fireball"]


class SkySignal:
	extends RefCounted

	var id: int = 0
	var type_id: String = "common"
	var entry_point := Vector2.ZERO
	var travel_direction := Vector2.ZERO
	var intercept_point := Vector2.ZERO
	var shown_point := Vector2.ZERO
	var error_offset := Vector2.ZERO
	var countdown: float = 0.0
	var lead_time: float = 1.0
	var classified: bool = false
	var error_radius: float = 0.0
	var spawned: bool = false
	var abandoned_flash: float = 0.0

	# Uncertainty resolves as the object approaches, so a late commitment is
	# better informed but leaves less time to slew. Inner classes cannot reach
	# the outer script's constants, so the lead time rides on the instance.
	func certainty() -> float:
		return clampf(1.0 - countdown / maxf(lead_time, 0.001), 0.0, 1.0)

	# The estimate the player acts on, not the truth. Committing a dish early
	# means aiming at a guess that is still drifting.
	func refresh_estimate() -> void:
		shown_point = intercept_point + error_offset * (1.0 - certainty())


@onready var starfield: Node2D = $Starfield
@onready var meteor_layer: Node2D = $MeteorLayer
@onready var effects: Node2D = $EffectsLayer
@onready var hud: CanvasLayer = $ProbeHUD

var sound: Node
var rng := RandomNumberGenerator.new()
var elapsed: float = 0.0
var finished: bool = false
var next_signal_in: float = 2.0
var next_signal_id: int = 1

var signals: Array[SkySignal] = []
var instruments: Array[Dictionary] = []
var meteor_signal_ids: Dictionary = {}

var cursor_position := Vector2.ZERO
var holding: bool = false
var hovered_signal_id: int = -1

var data_earned: float = 0.0
var data_missed: float = 0.0
var observed_count: int = 0
var missed_count: int = 0
var manual_count: int = 0
var instrument_count_observed: int = 0
var miss_marks: Array[Dictionary] = []


func _ready() -> void:
	rng.randomize()
	sound = SoundSynth.new()
	sound.name = "SoundSynth"
	add_child(sound)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	cursor_position = get_viewport().get_mouse_position()
	var size := get_viewport_rect().size
	for index in range(INSTRUMENT_COUNT):
		instruments.append({
			"position": Vector2(size.x * (0.34 + 0.32 * float(index)), size.y * 0.55),
			"target": Vector2(size.x * (0.34 + 0.32 * float(index)), size.y * 0.55),
			"assigned_id": -1,
			"locked_id": 0,
			"arrived": true,
		})
	hud.bind_probe(self)
	starfield.set_activity(0.08)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	cursor_position = get_viewport().get_mouse_position()
	if finished:
		queue_redraw()
		return

	elapsed += delta
	if elapsed >= PROBE_DURATION:
		_finish()
		return

	holding = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_update_signals(delta)
	_update_instruments(delta)
	_update_manual_tracking(delta)
	_update_miss_marks(delta)
	hovered_signal_id = _signal_under_cursor()

	next_signal_in -= delta
	if next_signal_in <= 0.0:
		_emit_signal_contact()
		next_signal_in = _current_interval() * rng.randf_range(0.82, 1.18)

	hud.refresh()
	queue_redraw()


func _current_interval() -> float:
	for wave in WAVES:
		if elapsed < float(wave.until):
			return float(wave.interval)
	return float(WAVES[WAVES.size() - 1].interval)


func _emit_signal_contact() -> void:
	var size := get_viewport_rect().size
	var contact := SkySignal.new()
	contact.id = next_signal_id
	next_signal_id += 1
	contact.classified = rng.randf() > 0.4
	var pool: Array = CLASSIFIED_TYPES if contact.classified else UNCLASSIFIED_TYPES
	contact.type_id = String(pool[rng.randi_range(0, pool.size() - 1)])

	match rng.randi_range(0, 2):
		0:
			contact.entry_point = Vector2(rng.randf_range(90.0, size.x - 90.0), -20.0)
		1:
			contact.entry_point = Vector2(-20.0, rng.randf_range(70.0, size.y * 0.62))
		_:
			contact.entry_point = Vector2(size.x + 20.0, rng.randf_range(70.0, size.y * 0.62))
	var aim := Vector2(
		rng.randf_range(size.x * 0.24, size.x * 0.76),
		rng.randf_range(size.y * 0.32, size.y * 0.74)
	)
	contact.travel_direction = (aim - contact.entry_point).normalized()
	contact.intercept_point = contact.entry_point + contact.travel_direction * INTERCEPT_DISTANCE
	contact.countdown = SIGNAL_LEAD_TIME
	contact.lead_time = SIGNAL_LEAD_TIME
	contact.error_offset = Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(34.0, MAX_ESTIMATE_ERROR)
	contact.refresh_estimate()
	signals.append(contact)
	sound.play_warning()


func _update_signals(delta: float) -> void:
	for index in range(signals.size() - 1, -1, -1):
		var contact := signals[index]
		contact.abandoned_flash = maxf(0.0, contact.abandoned_flash - delta)
		if contact.spawned:
			if contact.abandoned_flash <= 0.0:
				signals.remove_at(index)
			continue
		contact.countdown -= delta
		contact.error_radius = lerpf(MAX_ESTIMATE_ERROR, 6.0, contact.certainty())
		contact.refresh_estimate()
		if contact.countdown <= 0.0:
			contact.spawned = true
			_spawn_from_signal(contact)


func _spawn_from_signal(contact: SkySignal) -> void:
	var spec := Balance.meteor_spec(contact.type_id)
	var meteor = MeteorScript.new()
	meteor.configure(
		spec,
		contact.type_id,
		contact.entry_point,
		contact.travel_direction * float(spec.speed),
		1.0,
		{"wide_field": false, "prediction": true, "precision": false,
		 "perfect": false, "automation": 0.0, "secondary": 0.0}
	)
	meteor.observed.connect(_on_meteor_observed)
	meteor.expired.connect(_on_meteor_expired)
	meteor_layer.add_child(meteor)
	meteor_signal_ids[meteor.get_instance_id()] = contact.id


func _update_instruments(delta: float) -> void:
	for child_index in range(meteor_layer.get_child_count()):
		var meteor = meteor_layer.get_child(child_index)
		if meteor.has_method("set_secondary_assist"):
			meteor.set_secondary_assist(0.0)

	for index in range(instruments.size()):
		var instrument: Dictionary = instruments[index]
		var locked = _locked_target(instrument)

		if locked != null:
			# An acquired object is followed, but a dish has a slew ceiling of
			# its own: a fast meteor outruns it and breaks the lock.
			var offset: Vector2 = locked.global_position - Vector2(instrument.position)
			var track_step := TRACK_SPEED * delta
			instrument.position = Vector2(instrument.position) + (
				offset if offset.length() <= track_step else offset.normalized() * track_step
			)
			instrument.arrived = true
			if Vector2(instrument.position).distance_to(locked.global_position) > COVERAGE_RADIUS:
				instrument.locked_id = 0
				instrument.assigned_id = -1
			else:
				locked.set_secondary_assist(SCAN_RATE)
			instruments[index] = instrument
			continue

		instrument.locked_id = 0
		var position: Vector2 = instrument.position
		var target: Vector2 = instrument.target
		if not position.is_equal_approx(target):
			var step := SLEW_SPEED * delta
			var slew := target - position
			if slew.length() <= step:
				instrument.position = target
				instrument.arrived = true
			else:
				instrument.position = position + slew.normalized() * step
				instrument.arrived = false
		else:
			instrument.arrived = true

		# A slewing dish records nothing. Arriving before the object does is
		# what the commitment actually buys.
		if bool(instrument.arrived):
			var acquired = _acquire_target(instrument, index)
			if acquired != null:
				instrument.locked_id = acquired.get_instance_id()
				acquired.set_secondary_assist(SCAN_RATE)
		instruments[index] = instrument


func _locked_target(instrument: Dictionary):
	var locked_id := int(instrument.get("locked_id", 0))
	if locked_id == 0:
		return null
	var locked = instance_from_id(locked_id)
	if locked == null or not is_instance_valid(locked):
		return null
	if not locked.has_method("can_be_tracked") or not locked.can_be_tracked():
		return null
	return locked


func _acquire_target(instrument: Dictionary, own_index: int):
	var closest = null
	var closest_distance := INF
	for child_index in range(meteor_layer.get_child_count()):
		var meteor = meteor_layer.get_child(child_index)
		if not meteor.has_method("can_be_tracked") or not meteor.can_be_tracked():
			continue
		var already_taken := false
		for other_index in range(instruments.size()):
			if other_index == own_index:
				continue
			if int(instruments[other_index].get("locked_id", 0)) == meteor.get_instance_id():
				already_taken = true
				break
		if already_taken:
			continue
		var distance: float = Vector2(instrument.position).distance_to(meteor.global_position)
		if distance <= COVERAGE_RADIUS and distance < closest_distance:
			closest = meteor
			closest_distance = distance
	return closest


func _update_manual_tracking(delta: float) -> void:
	if not holding:
		return
	var target = _meteor_under_cursor()
	if target == null:
		return
	var distance: float = cursor_position.distance_to(target.global_position)
	target.apply_manual_observation(delta, distance, CURSOR_RADIUS)


func _meteor_under_cursor():
	var closest = null
	var closest_distance := INF
	for child_index in range(meteor_layer.get_child_count()):
		var meteor = meteor_layer.get_child(child_index)
		if not meteor.has_method("can_be_tracked") or not meteor.can_be_tracked():
			continue
		var distance: float = cursor_position.distance_to(meteor.global_position)
		if distance <= CURSOR_RADIUS and distance < closest_distance:
			closest = meteor
			closest_distance = distance
	return closest


func _signal_under_cursor() -> int:
	for contact in signals:
		if contact.spawned:
			continue
		if cursor_position.distance_to(contact.shown_point) <= SIGNAL_HIT_RADIUS:
			return contact.id
	return -1


func _find_signal(id: int) -> SkySignal:
	for contact in signals:
		if contact.id == id:
			return contact
	return null


# Prefer an idle dish that can still make it; otherwise the nearest one, which
# means the click itself is the act of abandoning whatever it was covering.
func candidate_instrument_for(contact: SkySignal) -> int:
	var best_free := -1
	var best_free_time := INF
	var best_any := -1
	var best_any_time := INF
	for index in range(instruments.size()):
		var instrument: Dictionary = instruments[index]
		var travel: float = Vector2(instrument.position).distance_to(contact.shown_point) / SLEW_SPEED
		if travel < best_any_time:
			best_any_time = travel
			best_any = index
		if int(instrument.assigned_id) == -1 and travel <= contact.countdown and travel < best_free_time:
			best_free_time = travel
			best_free = index
	return best_free if best_free >= 0 else best_any


func _unhandled_input(event: InputEvent) -> void:
	if finished:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			_restart()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var contact_id := _signal_under_cursor()
	if contact_id < 0:
		return
	_assign_to_signal(contact_id)
	get_viewport().set_input_as_handled()


func _assign_to_signal(contact_id: int) -> void:
	var contact := _find_signal(contact_id)
	if contact == null or contact.spawned:
		return
	var index := candidate_instrument_for(contact)
	if index < 0:
		return
	var instrument: Dictionary = instruments[index]
	var previous_id := int(instrument.assigned_id)
	if previous_id == contact_id:
		return
	if previous_id != -1:
		var dropped := _find_signal(previous_id)
		if dropped != null:
			dropped.abandoned_flash = 0.9
	instrument.assigned_id = contact_id
	# Aims at the current estimate, not the truth. An early commit is a bet on
	# a number that is still moving.
	instrument.target = contact.shown_point
	instrument.arrived = false
	instruments[index] = instrument
	sound.play_upgrade()


func _release_instrument_for_signal(contact_id: int) -> void:
	for index in range(instruments.size()):
		var instrument: Dictionary = instruments[index]
		if int(instrument.assigned_id) == contact_id:
			instrument.assigned_id = -1
			instrument.locked_id = 0
			instruments[index] = instrument


func _on_meteor_observed(meteor, reward: float, multiplier: float, was_manual: bool, _quality_grade: String) -> void:
	data_earned += reward
	observed_count += 1
	if was_manual:
		manual_count += 1
	else:
		instrument_count_observed += 1
	effects.spawn_success(meteor.global_position, reward, meteor.get_visual_color(), multiplier)
	sound.play_success(multiplier)
	_release_instrument_for_signal(int(meteor_signal_ids.get(meteor.get_instance_id(), -1)))
	meteor_signal_ids.erase(meteor.get_instance_id())


func _on_meteor_expired(meteor, _was_major: bool) -> void:
	var lost: float = meteor.base_value
	data_missed += lost
	missed_count += 1
	# The whole point of the layer: the thing you gave up is shown to you.
	miss_marks.append({
		"p": meteor.global_position,
		"life": 1.6,
		"text": "−%d" % int(lost),
		"color": meteor.get_visual_color(),
	})
	_release_instrument_for_signal(int(meteor_signal_ids.get(meteor.get_instance_id(), -1)))
	meteor_signal_ids.erase(meteor.get_instance_id())


func _update_miss_marks(delta: float) -> void:
	for index in range(miss_marks.size() - 1, -1, -1):
		var mark: Dictionary = miss_marks[index]
		mark.life = float(mark.life) - delta
		mark.p = Vector2(mark.p) + Vector2(0, -14.0) * delta
		miss_marks[index] = mark
		if float(mark.life) <= 0.0:
			miss_marks.remove_at(index)


func _finish() -> void:
	finished = true
	elapsed = PROBE_DURATION
	for child in meteor_layer.get_children():
		child.queue_free()
	signals.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_summary()


func _restart() -> void:
	finished = false
	elapsed = 0.0
	next_signal_in = 2.0
	next_signal_id = 1
	signals.clear()
	miss_marks.clear()
	meteor_signal_ids.clear()
	data_earned = 0.0
	data_missed = 0.0
	observed_count = 0
	missed_count = 0
	manual_count = 0
	instrument_count_observed = 0
	for child in meteor_layer.get_children():
		child.queue_free()
	effects.reset()
	var size := get_viewport_rect().size
	for index in range(instruments.size()):
		instruments[index] = {
			"position": Vector2(size.x * (0.34 + 0.32 * float(index)), size.y * 0.55),
			"target": Vector2(size.x * (0.34 + 0.32 * float(index)), size.y * 0.55),
			"assigned_id": -1,
			"locked_id": 0,
			"arrived": true,
		}
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.hide_summary()


func coverage_ratio() -> float:
	var total := observed_count + missed_count
	return 0.0 if total == 0 else float(observed_count) / float(total)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for instrument in instruments:
		_draw_instrument(instrument)
	for contact in signals:
		if not contact.spawned:
			_draw_signal(contact, font)
	for mark in miss_marks:
		var alpha := clampf(float(mark.life) / 0.6, 0.0, 1.0)
		var p: Vector2 = mark.p
		draw_arc(p, 26.0 - alpha * 6.0, 0.0, TAU, 28, Color(1.0, 0.42, 0.38, alpha * 0.5), 1.6, true)
		draw_string(font, p + Vector2(-14.0, -30.0), String(mark.text),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 19, Color(1.0, 0.46, 0.42, alpha))
	if not finished:
		_draw_cursor()


func _draw_instrument(instrument: Dictionary) -> void:
	var position: Vector2 = instrument.position
	var arrived: bool = bool(instrument.arrived)
	var color := Color("64e6c2") if arrived else Color("d8b45c")
	draw_circle(position, COVERAGE_RADIUS, Color(color, 0.05 if arrived else 0.02))
	draw_arc(position, COVERAGE_RADIUS, 0.0, TAU, 56, Color(color, 0.42 if arrived else 0.20),
		1.8 if arrived else 1.1, true)
	if not arrived:
		var target: Vector2 = instrument.target
		draw_line(position, target, Color(color, 0.34), 1.2, true)
		draw_arc(target, COVERAGE_RADIUS, 0.0, TAU, 56, Color(color, 0.14), 1.0, true)
	draw_circle(position, 7.0, Color(0.02, 0.05, 0.09, 0.95))
	draw_circle(position, 4.4, color)


func _draw_signal(contact: SkySignal, font) -> void:
	var urgency := contact.certainty()
	var base_color := Color("8fb6ff").lerp(Color("ffd27a"), urgency)
	if contact.abandoned_flash > 0.0:
		base_color = Color("ff6a5e")
	var hovered := contact.id == hovered_signal_id
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08

	if contact.error_radius > 7.0:
		draw_arc(contact.shown_point, contact.error_radius * pulse, 0.0, TAU, 40,
			Color(base_color, 0.20), 1.0, true)
	draw_arc(contact.shown_point, 20.0 * pulse, 0.0, TAU, 32,
		Color(base_color, 0.85 if hovered else 0.6), 2.0 if hovered else 1.5, true)
	draw_line(contact.shown_point, contact.shown_point + contact.travel_direction * 34.0,
		Color(base_color, 0.45), 1.2, true)

	var label := "?" if not contact.classified else _short_type_name(contact.type_id)
	draw_string(font, contact.shown_point + Vector2(-40.0, -28.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, 15, Color(base_color, 0.95))
	draw_string(font, contact.shown_point + Vector2(-40.0, 40.0), "%.1fs" % maxf(0.0, contact.countdown),
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, 13, Color(base_color, 0.7))

	# Hovering shows which dish answers this call, and therefore what it drops.
	if not hovered:
		return
	var index := candidate_instrument_for(contact)
	if index < 0:
		return
	var instrument: Dictionary = instruments[index]
	draw_line(Vector2(instrument.position), contact.shown_point, Color("ffe9a8"), 1.4, true)
	draw_arc(contact.shown_point, COVERAGE_RADIUS, 0.0, TAU, 56, Color("ffe9a8"), 1.0, true)
	var previous_id := int(instrument.assigned_id)
	if previous_id == -1 or previous_id == contact.id:
		return
	var dropped := _find_signal(previous_id)
	if dropped != null:
		draw_arc(dropped.shown_point, 27.0, 0.0, TAU, 32, Color("ff6a5e"), 2.2, true)
		draw_line(dropped.shown_point + Vector2(-13, -13), dropped.shown_point + Vector2(13, 13),
			Color("ff6a5e"), 2.0, true)
		draw_line(dropped.shown_point + Vector2(13, -13), dropped.shown_point + Vector2(-13, 13),
			Color("ff6a5e"), 2.0, true)


func _short_type_name(type_id: String) -> String:
	match type_id:
		"fast": return "FAST"
		"fireball": return "FIREBALL"
		_: return "COMMON"


func _draw_cursor() -> void:
	var color := Color("7dffe0") if holding else Color("b8f3ff")
	draw_circle(cursor_position, CURSOR_RADIUS, Color(color, 0.06 if holding else 0.025))
	draw_arc(cursor_position, CURSOR_RADIUS, 0.0, TAU, 48, Color(color, 0.9 if holding else 0.6), 1.6, true)
	draw_circle(cursor_position, 2.0, Color("f4ffff"))
