extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const ArrivalVisual = preload("res://scripts/arrival_visual.gd")
const Data = preload("res://scripts/expansion_data.gd")
const SampleSurface = preload("res://scenes/sample_meteor_surface.tscn")
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
var simulation_tick := 0
var simulation_id := 0
var previous_simulation_position := Vector2.ZERO
var start_uv := Vector2(0.30, 0.35)
var end_uv := Vector2(0.68, 0.53)
var body_position := Vector2.ZERO
var velocity := Vector2.ZERO
var base_value := 56.0
var _linger := 0.0
var _surface: Node2D

func _ready() -> void:
	_surface = SampleSurface.instantiate()
	add_child(_surface)

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
	warning_time = 1.5
	visible_lifetime = warning_time + 12.0
	required_track_time = 2.2
	base_value = 56.0
	if kind == "rare":
		required_track_time = 2.2 * (0.75 if research.research_owned("ext_trace_advanced") else 1.0)
		if research.research_owned("ext_combined_watch"):
			visible_lifetime += 4.0
	_update_position(0.0)
	queue_redraw()

func can_be_tracked() -> bool:
	return research != null and research.game.observation_phase_active and alive and age >= warning_time

func allows_automatic_assist() -> bool:
	return can_be_tracked()

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

func get_visual_color() -> Color:
	return Color("91D9DA")

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

	return credited

func _process(_delta: float) -> void:
	queue_redraw()

func tick_motion(delta: float, tick_id: int) -> void:
	simulation_tick = tick_id
	previous_simulation_position = global_position
	if research == null or not research.game.observation_phase_active: return
	if not alive:
		_linger -= delta
		if _linger <= 0.0: queue_free()
		return
	var motion_delta: float = delta * research.game.observer.motion_multiplier_for(self)
	age += motion_delta
	_update_position(motion_delta)

func tick_observation(delta: float) -> void:
	if can_be_tracked() and allows_automatic_assist() and dish_assist_rate > 0.0:
		_advance(dish_assist_rate * delta, false)

func complete_from_supernova() -> void:
	if not can_be_tracked() or is_queued_for_deletion(): return
	# Explosion credit is automatic even if this target was previously touched.
	automatic_work += maxf(0.0, 1.0 - stage_progress)
	manual_work = 0.0
	discovered = false
	stage_progress = 1.0
	tick_resolve()

func tick_resolve() -> void:
	if not alive: return
	if stage_progress >= 1.0:
		alive = false
		_linger = 0.45
		research.director.complete_component(self)
	elif age >= visible_lifetime:
		research.director.expire_component(self)
		alive = false
		_linger = 0.35

func simulate_tick(delta: float) -> void:
	tick_motion(delta, simulation_tick + 1)
	tick_observation(delta)
	tick_resolve()


func _update_position(delta: float) -> void:
	if research == null or not is_inside_tree():
		return
	var previous := global_position
	var rect: Rect2 = research.game.observation_view.atmospheric_rect()
	var factor := clampf((age - warning_time) / maxf(1.0, visible_lifetime - warning_time), 0.0, 1.0)
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
	var rect: Rect2 = research.game.observation_view.atmospheric_rect()
	var direction := ((end_uv - start_uv) * rect.size).normalized()
	_surface.present(self, scale_factor, direction, color.a)
	var label_origin := Vector2.ZERO
	if age < warning_time:
		color = UITheme.ACCENT_LINE
		var view_rect: Rect2 = research.game.observation_view.visible_world_rect()
		var marker := to_local(ArrivalVisual.edge_point(global_position, view_rect, scale_factor))
		label_origin = marker / scale_factor
		ArrivalVisual.draw_direction(self, marker, direction, scale_factor, UITheme.ACCENT_LINE, lerpf(0.55, 1.0, clampf(age / maxf(warning_time, 0.001), 0.0, 1.0)))
	if alive and get_progress() > 0.0:
		draw_arc(Vector2.ZERO, 15.0 * scale_factor, -PI / 2, -PI / 2 + TAU * get_progress(), 40, Color.WHITE, scale_factor, true)
	var key := "EXT_TARGET_RARE"
	var font: Font = UITheme.sans()
	var text := tr(key)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	var label_position := label_origin + Vector2(-width * 0.5, 28)
	if age < warning_time:
		var bounds: Rect2 = research.game.observation_view.visible_world_rect().grow(-16.0 * scale_factor)
		label_position.x = clampf(label_position.x, (bounds.position.x - global_position.x) / scale_factor, (bounds.end.x - global_position.x) / scale_factor - width)
	draw_string(font, label_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color, color.a * 0.85))
	draw_set_transform(Vector2.ZERO)

func get_save_data() -> Dictionary:
	return {"kind": kind, "origin_kind": origin_kind, "event_id": event_id, "ticket": reward_ticket_id, "component": component_index, "variant": variant, "start": [start_uv.x, start_uv.y], "end": [end_uv.x, end_uv.y], "age": age, "stage_progress": stage_progress, "manual_work": manual_work, "automatic_work": automatic_work, "manual_tracking_time": manual_tracking_time, "quality_integral": quality_integral, "quality": quality, "discovered": discovered, "complete": not alive and get_progress() >= 0.9999}

func restore_progress(data: Dictionary, restart_lifetime: bool = false) -> void:
	age = 0.0 if restart_lifetime else Data.number(data.get("age", 0), visible_lifetime)
	stage_progress = Data.number(data.get("stage_progress", 0), 1.0)
	manual_work = Data.number(data.get("manual_work", 0), 1.0)
	automatic_work = Data.number(data.get("automatic_work", 0), 1.0 - manual_work)
	manual_tracking_time = Data.number(data.get("manual_tracking_time", 0), 100000.0)
	quality_integral = Data.number(data.get("quality_integral", 0), manual_tracking_time)
	quality = Data.number(data.get("quality", 0), 1.0)
	discovered = Data.flag(data.get("discovered", false))
	_update_position(0.0)
	queue_redraw()

func get_display_position() -> Vector2:
	return previous_simulation_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
