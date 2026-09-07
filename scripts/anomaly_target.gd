extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const Data = preload("res://scripts/expansion_data.gd")
var research: Node
var kind := "rare"
var type_id := "anomaly_rare"
var origin_kind := "natural"
var event_id := ""
var reward_ticket_id := ""
var component_index := 0
var variant := "single"
var alive := true
var age := 0.0
var warning_time := 1.5
var visible_lifetime := 13.5
var required_track_time := 1.8
var stage_progress := 0.0
var manual_work := 0.0
var automatic_work := 0.0
var manual_tracking_time := 0.0
var quality_integral := 0.0
var quality := 0.0
var discovered := false
var dish_assist_rate := 0.0
var last_auto_frame := -10
var start_uv := Vector2(0.30, 0.35)
var end_uv := Vector2(0.68, 0.53)
var body_position := Vector2.ZERO
var velocity := Vector2.ZERO
var history: Array[Dictionary] = []
var base_value := 56.0
var archive_value := 0.0
var _linger := 0.0

func configure(controller: Node, description: Dictionary) -> void:
	research = controller
	kind = description.get("kind", "rare")
	type_id = "anomaly_" + kind
	origin_kind = description.get("origin_kind", "natural")
	event_id = description.get("event_id", "")
	reward_ticket_id = description.get("ticket", event_id)
	component_index = description.get("component", 0)
	variant = description.get("variant", "single")
	start_uv = description.get("start", Vector2(0.30, 0.35))
	end_uv = description.get("end", Vector2(0.68, 0.53))
	warning_time = 3.0 if kind == "afterglow" else 1.5
	visible_lifetime = warning_time + 12.0
	required_track_time = 2.4 if kind == "afterglow" else 2.2
	base_value = 56.0
	if kind == "rare":
		required_track_time = 2.2 * (0.75 if research.research_owned("ext_trace_advanced") else 1.0)
		if research.research_owned("ext_combined_watch"):
			visible_lifetime += 4.0
	if origin_kind == "archive":
		warning_time = 0.0
		visible_lifetime = 8.0
		discovered = true
		archive_value = description.get("archive_value", 7.0)
	_update_position(0.0)
	queue_redraw()

func can_be_tracked() -> bool:
	return research != null and research.game.observation_phase_active and alive and age >= warning_time and (kind != "afterglow" or discovered)

func allows_automatic_assist() -> bool:
	return origin_kind != "archive" and can_be_tracked()

func set_dish_assist_rate(value: float) -> void:
	dish_assist_rate = maxf(0.0, value) if allows_automatic_assist() else 0.0

func get_assist_rate(duration_multiplier: float) -> float:
	return (1.25 if kind == "rare" and research.research_owned("ext_link_advanced") else 1.0) / maxf(required_track_time * duration_multiplier, 0.001)

func get_tracking_radius(base: float) -> float:
	return base * (float(research.modules.effect("rare_radius")) if kind == "rare" else 1.0)

func get_progress() -> float:
	return stage_progress

func get_quality() -> float:
	return quality

func get_predicted_multiplier() -> float:
	return 1.0

func get_manual_contribution() -> float:
	return manual_work

func get_automatic_contribution() -> float:
	return automatic_work

func is_natural_observation() -> bool:
	return origin_kind == "natural"

func get_recent_observation_trail() -> PackedVector2Array:
	var result := PackedVector2Array()
	if kind == "afterglow":
		return result
	for sample in history:
		if age - float(sample.age) <= 1.0:
			result.append(sample.position)
	return result

func get_visual_color() -> Color:
	return Color("91D9DA") if kind == "rare" else Color("C5ACC8")

func apply_manual_observation(delta: float, distance: float, radius: float, speed: float = 1.0) -> void:
	if not can_be_tracked() or delta <= 0.0:
		return
	quality = clampf(1.0 - distance / maxf(radius, 1.0), 0.0, 1.0)
	var rate: float = lerpf(0.72, 1.42, quality) * speed * research.game.progression.get_analysis_speed_multiplier("common") / required_track_time
	var credited := _advance(delta * rate, true)
	if credited > 0.0:
		manual_tracking_time += delta
		quality_integral += quality * delta
	queue_redraw()

func _advance(amount: float, manual: bool) -> float:
	if not can_be_tracked():
		return 0.0
	var credited := clampf(amount, 0.0, 1.0 - stage_progress)
	stage_progress += credited
	var fraction := credited
	if manual:
		manual_work += fraction
	else:
		automatic_work += fraction
		if credited > 0.0:
			last_auto_frame = Engine.get_process_frames()
	if stage_progress >= 1.0:
		alive = false
		_linger = 0.45
		research.director.complete_component(self)
	return credited

func _process(delta: float) -> void:
	if research == null or not research.game.observation_phase_active:
		return
	var real_delta := maxf(0.0, delta / maxf(Engine.time_scale, 0.001))
	if not alive:
		_linger -= real_delta
		queue_redraw()
		if _linger <= 0.0:
			queue_free()
		return
	age += real_delta
	_update_position(real_delta)
	history.append({"age": age, "position": global_position})
	while not history.is_empty() and age - float(history[0].age) > 1.0:
		history.pop_front()
	if can_be_tracked() and allows_automatic_assist() and dish_assist_rate > 0.0:
		_advance(dish_assist_rate * real_delta, false)
	if alive and age >= visible_lifetime:
		research.director.expire_component(self)
		alive = false
		_linger = 0.35
	queue_redraw()

func _update_position(delta: float) -> void:
	if research == null or not is_inside_tree():
		return
	var previous := global_position
	var rect: Rect2 = research.game.observation_view.atmospheric_rect()
	var factor := clampf((age - warning_time) / maxf(1.0, visible_lifetime - warning_time), 0.0, 1.0)
	if kind == "afterglow":
		factor = clampf(age / maxf(warning_time, 0.01), 0.0, 1.0)
	var uv := start_uv.lerp(end_uv, factor)
	body_position = rect.position + uv * rect.size
	position = body_position
	if delta > 0.00001:
		velocity = (global_position - previous) / delta

func _draw() -> void:
	if research == null:
		return
	var scale_factor: float = research.game.observation_view.screen_length_to_world(1.0)
	var color := get_visual_color()
	if not alive:
		color.a = clampf(_linger / 0.45, 0.0, 1.0)
	var pulse := 0.75 + sin(age * 3.0) * 0.1
	if age < warning_time and kind != "afterglow":
		draw_arc(Vector2.ZERO, 15.0 * scale_factor, 0.0, TAU, 32, Color(color, 0.4), scale_factor, true)
		draw_line(Vector2(-22, 0) * scale_factor, Vector2(22, 0) * scale_factor, Color(color, 0.25), scale_factor, true)
	else:
		if kind == "afterglow":
			var opacity := 0.7 if discovered else 0.27
			for offset in range(-3, 4):
				draw_line(Vector2(-25, offset * 2) * scale_factor, Vector2(25, offset * 2 + 8) * scale_factor, Color(color, opacity * (1.0 - absf(offset) / 5.0) * pulse), scale_factor, true)
			if discovered:
				draw_circle(Vector2.ZERO, 3.0 * scale_factor, color)
		else:
			var head := body_position - global_position
			var direction := (end_uv - start_uv).normalized()
			draw_line(head - direction * 74.0 * scale_factor, head, Color(color, 0.22), 3.0 * scale_factor, true)
			draw_circle(head, 3.5 * scale_factor, color)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -6) * scale_factor, Vector2(4, 0) * scale_factor, Vector2(0, 6) * scale_factor, Vector2(-4, 0) * scale_factor]), color)
			draw_circle(Vector2.ZERO, 9.0 * scale_factor, Color(color, 0.12))
	if alive and get_progress() > 0.0:
		draw_arc(Vector2.ZERO, 15.0 * scale_factor, -PI / 2, -PI / 2 + TAU * get_progress(), 40, Color.WHITE, scale_factor, true)
	var key := "EXT_TARGET_%s" % kind.to_upper()
	if kind == "afterglow" and not discovered and age >= warning_time:
		key = "EXT_TARGET_SWEEP"
	var font: Font = UITheme.sans()
	var text := tr(key)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	draw_string(font, Vector2(-width * 0.5, 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color, 0.85))
	draw_set_transform(Vector2.ZERO)

func get_save_data() -> Dictionary:
	return {"kind": kind, "origin_kind": origin_kind, "event_id": event_id, "ticket": reward_ticket_id, "component": component_index, "variant": variant, "start": [start_uv.x, start_uv.y], "end": [end_uv.x, end_uv.y], "age": age, "stage_progress": stage_progress, "manual_work": manual_work, "automatic_work": automatic_work, "manual_tracking_time": manual_tracking_time, "quality_integral": quality_integral, "quality": quality, "discovered": discovered, "complete": not alive and get_progress() >= 0.9999, "archive_value": archive_value}

func restore_progress(data: Dictionary, restart_lifetime: bool = false) -> void:
	age = 0.0 if restart_lifetime else Data.number(data.get("age", 0), visible_lifetime)
	stage_progress = Data.number(data.get("stage_progress", 0), 1.0)
	manual_work = Data.number(data.get("manual_work", 0), 1.0)
	automatic_work = Data.number(data.get("automatic_work", 0), 1.0 - manual_work)
	manual_tracking_time = Data.number(data.get("manual_tracking_time", 0), 100000.0)
	quality_integral = Data.number(data.get("quality_integral", 0), manual_tracking_time)
	quality = Data.number(data.get("quality", 0), 1.0)
	discovered = Data.flag(data.get("discovered", false)) or origin_kind == "archive"
	_update_position(0.0)
	queue_redraw()
