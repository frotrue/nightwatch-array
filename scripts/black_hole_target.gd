extends Node2D

signal observed(target, reward, multiplier, was_manual, quality_grade)

const UITheme = preload("res://scripts/ui_theme.gd")
const SUPERNOVA_STAGES := ["discovered", "peak", "fading", "remnant"]
const SUPERNOVA_DURATIONS := [3.0, 8.0, 12.0, -1.0]
const SUPERNOVA_MULTIPLIERS := [0.85, 1.50, 1.00, 0.68]
const REQUIRED_HOLD_TIME := 1.65

var target_id := ""
var type_id := "einstein_ring"
var ring_radius_screen := 58.0
var arc_start := -PI * 0.5
var arc_span := TAU
var observation_progress := 0.0
var manual_tracking_time := 0.0
var quality_integral := 0.0
var last_quality := 0.0
var active := true
var lensed_supernova := false
var stage_index := 0
var stage_remaining := 3.0
var observation_view: Camera2D


func configure(id: String, target_type: String, world_position: Vector2, radius_pixels: float, visible_arc_start: float, visible_arc_span: float, view: Camera2D = null, is_lensed_supernova: bool = false) -> void:
	target_id = id
	type_id = target_type
	global_position = world_position
	ring_radius_screen = radius_pixels
	arc_start = visible_arc_start
	arc_span = clampf(visible_arc_span, 0.1, TAU)
	observation_view = view
	lensed_supernova = is_lensed_supernova
	queue_redraw()


func advance_time(delta: float) -> void:
	if not lensed_supernova or not active or delta <= 0.0 or stage_index >= SUPERNOVA_STAGES.size() - 1:
		return
	var remaining_delta := delta
	while remaining_delta > 0.0 and stage_index < SUPERNOVA_STAGES.size() - 1:
		if remaining_delta < stage_remaining:
			stage_remaining -= remaining_delta
			remaining_delta = 0.0
		else:
			remaining_delta -= stage_remaining
			stage_index += 1
			stage_remaining = float(SUPERNOVA_DURATIONS[stage_index])
	queue_redraw()


func can_be_tracked() -> bool:
	return active


func get_tracking_radius(default_radius: float) -> float:
	return maxf(default_radius * 0.72, _world_px(20.0))


func get_manual_contact_distance(point: Vector2) -> float:
	var offset := point - global_position
	var radius := _ring_radius_world()
	if offset.is_zero_approx():
		return radius
	var angle := offset.angle()
	if _angle_in_visible_arc(angle):
		return absf(offset.length() - radius)
	var start_point := global_position + Vector2.from_angle(arc_start) * radius
	var end_point := global_position + Vector2.from_angle(arc_start + arc_span) * radius
	return minf(point.distance_to(start_point), point.distance_to(end_point))


func apply_manual_observation(delta: float, cursor_distance: float, tracking_radius: float, manual_speed_multiplier: float = 1.0) -> void:
	if not active:
		return
	var quality := clampf(1.0 - cursor_distance / maxf(tracking_radius, 0.001), 0.0, 1.0)
	last_quality = quality
	manual_tracking_time += maxf(0.0, delta)
	quality_integral += quality * maxf(0.0, delta)
	var tracking_speed := lerpf(0.70, 1.35, quality) * maxf(1.0, manual_speed_multiplier)
	observation_progress += maxf(0.0, delta) * tracking_speed / REQUIRED_HOLD_TIME
	if observation_progress >= 1.0:
		_finish_observation()
	queue_redraw()


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_quality() -> float:
	return last_quality


func get_visual_color() -> Color:
	return Color("ffb07a") if lensed_supernova else Color("85d9ff")


func get_predicted_multiplier() -> float:
	return float(SUPERNOVA_MULTIPLIERS[stage_index]) if lensed_supernova else 1.0


func get_quality_grade() -> String:
	var average := quality_integral / maxf(manual_tracking_time, 0.001)
	if average >= 0.82:
		return "PERFECT"
	if average >= 0.62:
		return "EXCELLENT"
	return "GOOD"


func get_stage() -> String:
	return String(SUPERNOVA_STAGES[stage_index]) if lensed_supernova else "lens"


func get_save_data() -> Dictionary:
	return {
		"target_id": target_id,
		"observation_progress": observation_progress,
		"manual_tracking_time": manual_tracking_time,
		"quality_integral": quality_integral,
		"stage_index": stage_index,
		"stage_remaining": stage_remaining,
	}


func load_save_data(data: Dictionary) -> void:
	observation_progress = clampf(float(data.get("observation_progress", 0.0)), 0.0, 0.999)
	manual_tracking_time = maxf(0.0, float(data.get("manual_tracking_time", 0.0)))
	quality_integral = maxf(0.0, float(data.get("quality_integral", 0.0)))
	stage_index = clampi(int(data.get("stage_index", 0)), 0, SUPERNOVA_STAGES.size() - 1)
	var duration := float(SUPERNOVA_DURATIONS[stage_index])
	stage_remaining = float(data.get("stage_remaining", duration))
	if duration >= 0.0:
		stage_remaining = clampf(stage_remaining, 0.001, duration)
	queue_redraw()


func _finish_observation() -> void:
	if not active:
		return
	active = false
	var multiplier := get_predicted_multiplier()
	var base_reward: float = 190000000.0 if lensed_supernova else 150000000.0
	observed.emit(self, round(base_reward * multiplier), multiplier, true, get_quality_grade())


func _angle_in_visible_arc(angle: float) -> bool:
	if arc_span >= TAU - 0.001:
		return true
	var relative := fposmod(angle - arc_start, TAU)
	return relative <= arc_span


func _draw() -> void:
	if not active:
		return
	var scale := _world_px(1.0)
	var radius := _ring_radius_world()
	var color := Color("85d9ff")
	if lensed_supernova:
		color = Color("fff0c8") if get_stage() == "peak" else Color("ff9a72")
	draw_circle(Vector2.ZERO, 13.0 * scale, Color(0.0, 0.0, 0.0, 0.92))
	draw_circle(Vector2.ZERO, 20.0 * scale, Color(color, 0.035))
	draw_arc(Vector2.ZERO, radius, arc_start, arc_start + arc_span, maxi(20, int(64.0 * arc_span / TAU)), Color(color, 0.18), 7.0 * scale, true)
	draw_arc(Vector2.ZERO, radius, arc_start, arc_start + arc_span, maxi(20, int(64.0 * arc_span / TAU)), Color(color, 0.92), 1.7 * scale, true)
	var progress_span := arc_span * get_progress()
	if progress_span > 0.001:
		draw_arc(Vector2.ZERO, radius, arc_start, arc_start + progress_span, maxi(8, int(64.0 * progress_span / TAU)), Color(UITheme.INK_MAX, 0.95), 3.2 * scale, true)


func _ring_radius_world() -> float:
	return _world_px(ring_radius_screen)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels
