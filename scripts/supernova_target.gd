extends Node2D

signal observed(target, reward, multiplier, was_manual, quality_grade)

const UITheme = preload("res://scripts/ui_theme.gd")
const STAGES := ["discovered", "peak", "fading", "remnant"]
const STAGE_DURATIONS := [3.0, 8.0, 12.0, -1.0]
const STAGE_MULTIPLIERS := [0.85, 1.50, 1.00, 0.68]
const BASE_REWARD := 120000000.0

var target_id := ""
var type_id := "supernova"
var stage_index := 0
var stage_remaining := 3.0
var observation_progress := 0.0
var manual_tracking_time := 0.0
var quality_integral := 0.0
var last_quality := 0.0
var active := true
var forecast_visible := false
var observation_view: Camera2D
var capture_time_override_msec: float = -1.0 # Capture-only clock; negative retains the live clock.


func configure(id: String, world_position: Vector2, phase_offset: float, show_forecast: bool, view: Camera2D = null) -> void:
	target_id = id
	global_position = world_position
	forecast_visible = show_forecast
	observation_view = view
	stage_index = 0
	stage_remaining = float(STAGE_DURATIONS[0])
	advance_time(maxf(0.0, phase_offset))
	queue_redraw()


func set_forecast_visible(value: bool) -> void:
	forecast_visible = value
	queue_redraw()


func advance_time(delta: float) -> void:
	if not active or delta <= 0.0 or stage_index >= STAGES.size() - 1:
		return
	var remaining_delta := delta
	while remaining_delta > 0.0 and stage_index < STAGES.size() - 1:
		if remaining_delta < stage_remaining:
			stage_remaining -= remaining_delta
			remaining_delta = 0.0
		else:
			remaining_delta -= stage_remaining
			stage_index += 1
			stage_remaining = float(STAGE_DURATIONS[stage_index])
	queue_redraw()


func can_be_tracked() -> bool:
	return active


func get_tracking_radius(default_radius: float) -> float:
	return maxf(default_radius, _world_px(38.0))


func apply_manual_observation(delta: float, cursor_distance: float, tracking_radius: float, manual_speed_multiplier: float = 1.0) -> void:
	if not active:
		return
	var quality := clampf(1.0 - cursor_distance / maxf(tracking_radius, 1.0), 0.0, 1.0)
	last_quality = quality
	manual_tracking_time += delta
	quality_integral += quality * delta
	observation_progress += delta * lerpf(0.70, 1.35, quality) * maxf(1.0, manual_speed_multiplier) / 1.25
	if observation_progress >= 1.0:
		_finish_observation()
	queue_redraw()


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_quality() -> float:
	return last_quality


func get_visual_color() -> Color:
	return Color("fff0c8") if get_stage() == "peak" else Color("ff9a72")


func get_predicted_multiplier() -> float:
	return float(STAGE_MULTIPLIERS[stage_index])


func get_quality_grade() -> String:
	var average := quality_integral / maxf(manual_tracking_time, 0.001)
	if average >= 0.82:
		return "PERFECT"
	if average >= 0.62:
		return "EXCELLENT"
	return "GOOD"


func get_stage() -> String:
	return String(STAGES[stage_index])


func get_save_data() -> Dictionary:
	return {
		"target_id": target_id,
		"stage_index": stage_index,
		"stage_remaining": stage_remaining,
		"observation_progress": observation_progress,
		"manual_tracking_time": manual_tracking_time,
		"quality_integral": quality_integral,
	}


func load_save_data(data: Dictionary) -> void:
	stage_index = clampi(int(data.get("stage_index", 0)), 0, STAGES.size() - 1)
	var duration := float(STAGE_DURATIONS[stage_index])
	stage_remaining = float(data.get("stage_remaining", duration))
	if duration >= 0.0:
		stage_remaining = clampf(stage_remaining, 0.001, duration)
	observation_progress = clampf(float(data.get("observation_progress", 0.0)), 0.0, 0.999)
	manual_tracking_time = maxf(0.0, float(data.get("manual_tracking_time", 0.0)))
	quality_integral = maxf(0.0, float(data.get("quality_integral", 0.0)))
	queue_redraw()


func _finish_observation() -> void:
	if not active:
		return
	active = false
	var multiplier := get_predicted_multiplier()
	var reward: float = round(BASE_REWARD * multiplier)
	observed.emit(self, reward, multiplier, true, get_quality_grade())


func _draw() -> void:
	if not active:
		return
	var scale := _world_px(1.0)
	var visual_time := capture_time_override_msec if capture_time_override_msec >= 0.0 else float(Time.get_ticks_msec())
	var pulse := 1.0 + sin(visual_time * 0.007 + float(target_id.hash() & 31)) * 0.08
	var radius := 7.0 * scale * pulse
	var color := Color("ff8f68")
	match get_stage():
		"peak": color = Color("fff0c8")
		"fading": color = Color("ffb070")
		"remnant": color = Color("b48a7a")
	draw_circle(Vector2.ZERO, radius * 3.4, Color(color, 0.055))
	draw_circle(Vector2.ZERO, radius * 1.7, Color(color, 0.16))
	draw_circle(Vector2.ZERO, radius, color)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		draw_line(direction * radius * 1.25, direction * radius * 2.35, Color(color, 0.68), 1.0 * scale, true)
	if forecast_visible and stage_index < STAGES.size() - 1:
		var duration := maxf(0.001, float(STAGE_DURATIONS[stage_index]))
		var ratio := clampf(stage_remaining / duration, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 18.0 * scale, -PI * 0.5, -PI * 0.5 + TAU * ratio, 40, Color(UITheme.ACCENT_LINE, 0.72), 1.4 * scale, true)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
