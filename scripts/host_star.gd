extends Node2D

signal transit_completed(star, multiplier, was_manual, quality_grade)
signal harvest_completed(star)
signal decoy_completed(star)

const UITheme = preload("res://scripts/ui_theme.gd")
const REQUIRED_TRACK_TIME := 2.8
const HARVEST_HOLD_TIME := 0.85
const EXTRA_TRACKING_RADIUS_SCREEN_PX := 10.0
const MAX_CONFIRMATIONS := 3
const HARVEST_TIER_MULTIPLIERS := [0.0, 1.0, 1.35, 1.65]

var stable_star_id: int = 0
var type_id: String = "exoplanet_transit"
var base_value: float = 180000000.0
var state: String = "idle"
var confirmation_count: int = 0
var confirmation_quality_total: float = 0.0
var observation_progress: float = 0.0
var harvest_progress: float = 0.0
var harvest_ready: bool = false
var manual_tracking_time: float = 0.0
var quality_integral: float = 0.0
var last_quality: float = 0.0
var interruption_count: int = 0
var last_manual_frame: int = -100
var manual_touched: bool = false
var transit_phase_ratio: float = 0.0
var visual_age: float = 0.0
var observation_view: Camera2D
var profile_id: String = "basic"
var profile: Dictionary = {}
var anchor_position := Vector2.ZERO
var is_hidden: bool = false
var reveal_hits: int = 0
var reveal_angles: Array[float] = []
var comparison_locked: bool = false
var decoy_kind: String = ""
var forecast_remaining: float = 0.0
var forecast_total: float = 0.0
var forecast_notches: int = 0
var linked_group_id: int = 0


func configure(id: int, world_position: Vector2, reward: float, view: Camera2D = null) -> void:
	stable_star_id = id
	position = world_position
	anchor_position = world_position
	base_value = reward
	observation_view = view
	queue_redraw()


func configure_profile(id: String, definition: Dictionary) -> void:
	profile_id = id
	profile = definition.duplicate(true)
	is_hidden = bool(profile.get("hidden", false))
	reveal_hits = 0
	reveal_angles.clear()
	linked_group_id = int(profile.get("linked_group_id", 0))
	queue_redraw()


func _process(delta: float) -> void:
	visual_age += delta
	var drift_radius := _screen_length(float(profile.get("drift_radius_screen", 0.0)))
	if drift_radius > 0.0:
		var phase := visual_age * float(profile.get("drift_speed", 0.0)) + float(stable_star_id) * 0.71
		position = anchor_position + Vector2(cos(phase), sin(phase * 0.73) * 0.46) * drift_radius
	queue_redraw()


func begin_transit() -> void:
	if confirmation_count >= MAX_CONFIRMATIONS:
		return
	state = "transiting"
	type_id = "exoplanet_transit"
	observation_progress = 0.0
	harvest_progress = 0.0
	harvest_ready = false
	manual_tracking_time = 0.0
	quality_integral = 0.0
	last_quality = 0.0
	interruption_count = 0
	last_manual_frame = -100
	manual_touched = false
	transit_phase_ratio = 0.0
	decoy_kind = ""
	queue_redraw()


func begin_decoy(kind: String) -> void:
	state = "decoy"
	type_id = "transit_decoy"
	decoy_kind = kind
	observation_progress = 0.0
	harvest_progress = 0.0
	harvest_ready = false
	manual_tracking_time = 0.0
	quality_integral = 0.0
	last_quality = 0.0
	interruption_count = 0
	last_manual_frame = -100
	manual_touched = false
	transit_phase_ratio = 0.0
	queue_redraw()


func cancel_transit() -> void:
	state = "idle"
	type_id = "exoplanet_candidate" if confirmation_count > 0 else "exoplanet_transit"
	observation_progress = 0.0
	harvest_progress = 0.0
	harvest_ready = false
	manual_tracking_time = 0.0
	quality_integral = 0.0
	last_quality = 0.0
	manual_touched = false
	transit_phase_ratio = 0.0
	queue_redraw()


func cancel_decoy() -> void:
	if state != "decoy":
		return
	cancel_transit()
	decoy_kind = ""


func arm_harvest() -> void:
	if state == "idle" and confirmation_count > 0:
		harvest_ready = true
		type_id = "exoplanet_candidate"
		queue_redraw()


func set_transit_phase(value: float) -> void:
	transit_phase_ratio = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_forecast(remaining: float, total: float, notches: int) -> void:
	forecast_remaining = maxf(0.0, remaining)
	forecast_total = maxf(0.0, total)
	forecast_notches = maxi(0, notches)
	queue_redraw()


func set_hidden(value: bool) -> void:
	is_hidden = value
	if is_hidden:
		harvest_ready = false
		reveal_hits = 0
		reveal_angles.clear()
	queue_redraw()


func record_reveal_sweep(angle: float) -> bool:
	if not is_hidden:
		return true
	for previous_angle in reveal_angles:
		var difference := absf(wrapf(angle - previous_angle, -PI, PI))
		if difference < deg_to_rad(35.0):
			return false
	reveal_angles.append(angle)
	reveal_hits = reveal_angles.size()
	if reveal_hits >= maxi(1, int(profile.get("reveal_hits", 1))):
		is_hidden = false
		queue_redraw()
		return true
	queue_redraw()
	return false


func set_comparison_locked(value: bool) -> void:
	comparison_locked = value
	queue_redraw()


func can_be_tracked() -> bool:
	if is_hidden:
		return false
	return (state in ["transiting", "decoy"] and not comparison_locked) or (state == "idle" and confirmation_count > 0 and harvest_ready)


func get_tracking_radius(base_radius: float) -> float:
	return base_radius + _screen_length(EXTRA_TRACKING_RADIUS_SCREEN_PX)


func apply_manual_observation(
	delta: float,
	cursor_distance: float,
	tracking_radius: float,
	manual_speed_multiplier: float = 1.0
) -> void:
	if not can_be_tracked():
		return
	if state == "idle":
		harvest_progress += maxf(0.0, delta) * maxf(1.0, manual_speed_multiplier) / HARVEST_HOLD_TIME
		last_quality = clampf(1.0 - cursor_distance / maxf(tracking_radius, 1.0), 0.0, 1.0)
		if harvest_progress >= 1.0:
			_finish_harvest()
		queue_redraw()
		return
	var current_frame := Engine.get_process_frames()
	if manual_touched and current_frame - last_manual_frame > 1:
		interruption_count += 1
	last_manual_frame = current_frame
	manual_touched = true
	var quality := clampf(1.0 - cursor_distance / maxf(tracking_radius, 1.0), 0.0, 1.0)
	last_quality = quality
	manual_tracking_time += delta
	quality_integral += quality * delta
	var tracking_speed := lerpf(0.72, 1.42, quality) * maxf(1.0, manual_speed_multiplier)
	var required_time := REQUIRED_TRACK_TIME * maxf(0.1, float(profile.get("tracking_time_multiplier", 1.0)))
	observation_progress += delta * tracking_speed / required_time
	if observation_progress >= 1.0:
		if state == "decoy":
			_finish_decoy()
		else:
			_finish_transit()
	queue_redraw()


func get_progress() -> float:
	return clampf(harvest_progress if state == "idle" and confirmation_count > 0 else observation_progress, 0.0, 1.0)


func get_quality() -> float:
	return 1.0 if state == "idle" and confirmation_count > 0 else last_quality


func get_visual_color() -> Color:
	return Color("ffd7a0")


func get_quality_grade() -> String:
	if state == "idle" and confirmation_count > 0:
		return get_harvest_quality_grade()
	return _current_transit_quality_grade()


func get_predicted_multiplier() -> float:
	if state == "idle" and confirmation_count > 0:
		return get_harvest_multiplier()
	return _quality_multiplier_for_grade(_current_transit_quality_grade())


func get_harvest_multiplier() -> float:
	if confirmation_count <= 0:
		return 0.0
	var average_quality_multiplier := confirmation_quality_total / float(confirmation_count)
	return float(HARVEST_TIER_MULTIPLIERS[confirmation_count]) * average_quality_multiplier


func get_harvest_reward() -> float:
	return maxf(1.0, round(base_value * get_harvest_multiplier()))


func get_harvest_quality_grade() -> String:
	if confirmation_count <= 0:
		return "GOOD"
	var average_multiplier := confirmation_quality_total / float(confirmation_count)
	if average_multiplier >= 1.50:
		return "PERFECT"
	if average_multiplier >= 1.20:
		return "EXCELLENT"
	return "GOOD"


func get_save_data() -> Dictionary:
	return {
		"stable_star_id": stable_star_id,
		"position": [position.x, position.y],
		"state": state,
		"confirmation_count": confirmation_count,
		"confirmation_quality_total": confirmation_quality_total,
		"observation_progress": observation_progress,
		"harvest_progress": harvest_progress,
		"manual_tracking_time": manual_tracking_time,
		"quality_integral": quality_integral,
		"last_quality": last_quality,
		"interruption_count": interruption_count,
		"manual_touched": manual_touched,
		"transit_phase_ratio": transit_phase_ratio,
		"profile_id": profile_id,
		"profile": profile.duplicate(true),
		"hidden": is_hidden,
		"reveal_hits": reveal_hits,
		"reveal_angles": reveal_angles.duplicate(),
		"comparison_locked": comparison_locked,
		"decoy_kind": decoy_kind,
		"forecast_remaining": forecast_remaining,
		"forecast_total": forecast_total,
		"forecast_notches": forecast_notches,
		"linked_group_id": linked_group_id,
	}


func load_save_data(data: Dictionary) -> void:
	state = String(data.get("state", "idle"))
	if state not in ["idle", "transiting", "decoy"]:
		state = "idle"
	confirmation_count = clampi(int(data.get("confirmation_count", 0)), 0, MAX_CONFIRMATIONS)
	confirmation_quality_total = clampf(
		float(data.get("confirmation_quality_total", float(confirmation_count))),
		float(confirmation_count),
		float(confirmation_count) * 1.55
	)
	observation_progress = clampf(float(data.get("observation_progress", 0.0)), 0.0, 0.999)
	harvest_progress = clampf(float(data.get("harvest_progress", 0.0)), 0.0, 0.999)
	harvest_ready = false
	manual_tracking_time = maxf(0.0, float(data.get("manual_tracking_time", 0.0)))
	quality_integral = maxf(0.0, float(data.get("quality_integral", 0.0)))
	last_quality = clampf(float(data.get("last_quality", 0.0)), 0.0, 1.0)
	interruption_count = maxi(0, int(data.get("interruption_count", 0)))
	manual_touched = bool(data.get("manual_touched", false))
	transit_phase_ratio = clampf(float(data.get("transit_phase_ratio", 0.0)), 0.0, 1.0)
	profile_id = String(data.get("profile_id", "basic"))
	var saved_profile = data.get("profile", {})
	profile = saved_profile.duplicate(true) if saved_profile is Dictionary else {}
	is_hidden = bool(data.get("hidden", false))
	reveal_hits = maxi(0, int(data.get("reveal_hits", 0)))
	reveal_angles.clear()
	var saved_angles = data.get("reveal_angles", [])
	if saved_angles is Array:
		for angle_variant in saved_angles:
			reveal_angles.append(float(angle_variant))
	comparison_locked = bool(data.get("comparison_locked", false))
	decoy_kind = String(data.get("decoy_kind", ""))
	forecast_remaining = maxf(0.0, float(data.get("forecast_remaining", 0.0)))
	forecast_total = maxf(0.0, float(data.get("forecast_total", 0.0)))
	forecast_notches = maxi(0, int(data.get("forecast_notches", 0)))
	linked_group_id = int(data.get("linked_group_id", 0))
	type_id = "transit_decoy" if state == "decoy" else ("exoplanet_transit" if state == "transiting" or confirmation_count == 0 else "exoplanet_candidate")
	queue_redraw()


func _current_transit_quality_grade() -> String:
	if not manual_touched or manual_tracking_time <= 0.05:
		return "AUTOMATIC"
	var average_quality := quality_integral / maxf(manual_tracking_time, 0.001)
	if average_quality >= 0.82 and interruption_count <= 1:
		return "PERFECT"
	if average_quality >= 0.62 and interruption_count <= 3:
		return "EXCELLENT"
	return "GOOD"


func _quality_multiplier_for_grade(grade: String) -> float:
	match grade:
		"PERFECT":
			return 1.55
		"EXCELLENT":
			return 1.25
		_:
			return 1.0


func _finish_transit() -> void:
	if state != "transiting":
		return
	var quality_grade := _current_transit_quality_grade()
	var multiplier := _quality_multiplier_for_grade(quality_grade)
	confirmation_count = mini(MAX_CONFIRMATIONS, confirmation_count + 1)
	confirmation_quality_total += multiplier
	state = "idle"
	type_id = "exoplanet_candidate"
	observation_progress = 0.0
	harvest_progress = 0.0
	harvest_ready = false
	transit_phase_ratio = 0.0
	transit_completed.emit(self, multiplier, true, quality_grade)


func _finish_harvest() -> void:
	if state != "idle" or confirmation_count <= 0:
		return
	state = "harvested"
	harvest_progress = 1.0
	harvest_completed.emit(self)


func _finish_decoy() -> void:
	if state != "decoy":
		return
	state = "idle"
	type_id = "exoplanet_candidate" if confirmation_count > 0 else "exoplanet_transit"
	observation_progress = 0.0
	transit_phase_ratio = 0.0
	decoy_completed.emit(self)
	queue_redraw()


func _draw() -> void:
	if state == "harvested" or is_hidden:
		return
	var scale := _screen_length(1.0)
	var dip := 1.0
	if state == "transiting":
		var transit_distance := (transit_phase_ratio - 0.5) / 0.19
		dip = 1.0 - 0.34 * exp(-transit_distance * transit_distance)
	elif state == "decoy":
		var decoy_distance := (transit_phase_ratio - 0.5) / 0.22
		dip = 1.0 + 0.30 * exp(-decoy_distance * decoy_distance)
	var pulse := 1.0 + sin(visual_age * 2.3 + float(stable_star_id)) * 0.04
	var visual_scale := maxf(0.5, float(profile.get("visual_scale", 1.0)))
	var brightness := clampf(float(profile.get("brightness", 1.0)), 0.25, 1.0)
	var radius := 4.6 * scale * pulse * visual_scale
	var color := get_visual_color()
	draw_circle(Vector2.ZERO, radius * 3.4, Color(color, 0.08 * dip * brightness))
	draw_circle(Vector2.ZERO, radius * 1.8, Color(color, 0.20 * dip * brightness))
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.93, 0.76, dip * brightness))
	draw_circle(Vector2(-1.0, -1.0) * scale, radius * 0.34, Color(1.0, 1.0, 1.0, dip * brightness))
	for confirmation_index in range(MAX_CONFIRMATIONS):
		var pip_position := Vector2((float(confirmation_index) - 1.0) * 8.0, -24.0) * scale
		var pip_color := Color(color, 0.92) if confirmation_index < confirmation_count else Color(color, 0.18)
		draw_circle(pip_position, 2.1 * scale, pip_color)
	_draw_profile_marks(scale, color)
	if state in ["transiting", "decoy"]:
		var chord := 18.0 * scale
		var planet_position := Vector2(lerpf(-chord, chord, transit_phase_ratio), 0.0)
		draw_line(Vector2(-chord, 0.0), Vector2(chord, 0.0), Color(UITheme.ACCENT_LINE, 0.20), 1.0 * scale, true)
		var alert_radius := (18.0 + sin(visual_age * 4.0) * 1.2) * scale
		var alert_angle := visual_age * 0.75
		draw_arc(Vector2.ZERO, alert_radius, alert_angle, alert_angle + PI * 0.72, 18, Color(color, 0.48), 1.4 * scale, true)
		draw_arc(Vector2.ZERO, alert_radius, alert_angle + PI, alert_angle + PI * 1.72, 18, Color(color, 0.48), 1.4 * scale, true)
		if state == "transiting":
			draw_circle(planet_position, 3.4 * scale, Color(color, 0.42))
			draw_circle(planet_position, 2.0 * scale, Color(UITheme.SHADOW, 0.96))
		else:
			draw_circle(Vector2.ZERO, 8.4 * scale, Color(color, 0.13))
		draw_arc(Vector2.ZERO, 13.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * get_progress(), 32, Color(color, 0.78), 1.4 * scale, true)
	elif confirmation_count > 0:
		var harvest_radius := 18.0 * scale
		draw_arc(Vector2.ZERO, harvest_radius, 0.0, TAU, 40, Color(color, 0.18), 1.2 * scale, true)
		if harvest_progress > 0.0:
			draw_arc(Vector2.ZERO, harvest_radius, -PI * 0.5, -PI * 0.5 + TAU * harvest_progress, 40, Color(color, 0.86), 2.0 * scale, true)
	if state == "idle" and forecast_notches > 0 and forecast_total > 0.0:
		var forecast_ratio := 1.0 - clampf(forecast_remaining / forecast_total, 0.0, 1.0)
		for notch_index in range(forecast_notches):
			var offset := (float(notch_index) - float(forecast_notches - 1) * 0.5) * 0.34
			var angle := -PI * 0.5 + forecast_ratio * TAU + offset
			var start := Vector2.from_angle(angle) * 20.0 * scale
			var finish := Vector2.from_angle(angle) * 25.0 * scale
			draw_line(start, finish, Color(color, 0.68), 1.5 * scale, true)


func _draw_profile_marks(scale: float, color: Color) -> void:
	if bool(profile.get("cluster", false)):
		for offset in [Vector2(-11.0, 7.0), Vector2(10.0, 8.0), Vector2(0.0, 13.0)]:
			draw_circle(offset * scale, 1.8 * scale, Color(color, 0.44))
	if bool(profile.get("linked_pair", false)):
		draw_circle(Vector2(11.0, -3.0) * scale, 2.2 * scale, Color(color, 0.54))
	if bool(profile.get("stream", false)):
		draw_line(Vector2(-21.0, 12.0) * scale, Vector2(21.0, -12.0) * scale, Color(color, 0.18), 1.0 * scale, true)
	if comparison_locked:
		draw_arc(Vector2.ZERO, 15.0 * scale, 0.0, TAU, 24, Color(color, 0.20), 1.0 * scale, true)


func _screen_length(screen_pixels: float) -> float:
	if observation_view != null and observation_view.has_method("screen_length_to_world"):
		return observation_view.screen_length_to_world(screen_pixels)
	return screen_pixels
