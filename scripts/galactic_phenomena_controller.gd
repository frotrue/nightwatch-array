extends Node2D

signal phenomenon_observed(target, reward, multiplier, quality_grade)

const UITheme = preload("res://scripts/ui_theme.gd")
const SupernovaTarget = preload("res://scripts/supernova_target.gd")
const BlackHoleTarget = preload("res://scripts/black_hole_target.gd")
const LENS_ZONE_RADIUS_SCREEN := 118.0

const TARGET_SPECS := {
	"supernova_primary": {"kind": "supernova", "screen_position": Vector2(286.0, 218.0), "phase_offset": 0.0},
	"supernova_secondary": {"kind": "supernova", "screen_position": Vector2(846.0, 286.0), "phase_offset": 5.5},
	"einstein_ring": {"kind": "arc", "screen_position": Vector2(790.0, 202.0), "radius": 62.0, "arc_start": -PI * 0.5, "arc_span": TAU, "type_id": "einstein_ring"},
	"partial_lens": {"kind": "arc", "screen_position": Vector2(342.0, 366.0), "radius": 66.0, "arc_start": -PI * 0.82, "arc_span": TAU * 0.62, "type_id": "partial_lens"},
	"lensed_supernova": {"kind": "arc", "screen_position": Vector2(760.0, 444.0), "radius": 72.0, "arc_start": -PI * 0.70, "arc_span": TAU * 0.58, "type_id": "lensed_supernova", "supernova": true},
}

var progression: Node
var observation_view: Camera2D
var meteor_layer: Node2D
var running := false
var completed_targets: Dictionary = {}


func setup(progression_controller: Node, view: Camera2D, live_meteor_layer: Node2D) -> void:
	progression = progression_controller
	observation_view = view
	meteor_layer = live_meteor_layer
	refresh_unlock_state()


func reset() -> void:
	running = false
	completed_targets.clear()
	_clear_targets()
	queue_redraw()


func begin_round() -> void:
	running = true
	refresh_unlock_state()


func end_round() -> void:
	running = false


func advance_time(delta: float) -> void:
	if not running:
		return
	for child in get_children():
		if child.has_method("advance_time"):
			child.advance_time(maxf(0.0, delta))


func refresh_unlock_state() -> void:
	if progression == null:
		return
	if not progression.galaxy_unlocked():
		_clear_targets()
		queue_redraw()
		return
	var unlocked_targets: Array[String] = []
	if progression.has_upgrade("ngc6822_supernova_watch"):
		unlocked_targets.append("supernova_primary")
	if progression.has_upgrade("ic10_supernova_overlap"):
		unlocked_targets.append("supernova_secondary")
	if progression.has_upgrade("wlm_einstein_ring"):
		unlocked_targets.append("einstein_ring")
	if progression.has_upgrade("pegasus_partial_lens"):
		unlocked_targets.append("partial_lens")
	if progression.has_upgrade("leo_a_lensed_supernova"):
		unlocked_targets.append("lensed_supernova")
	var desired_targets: Array[String] = []
	for id in unlocked_targets:
		if completed_targets.has(id):
			continue
		desired_targets.append(id)
		if desired_targets.size() >= 2:
			break
	for child in get_children():
		if String(child.get("target_id")) not in desired_targets:
			remove_child(child)
			child.queue_free()
	for id in desired_targets:
		_ensure_target(id)
	var forecast: bool = progression.has_upgrade("ic1613_supernova_ephemeris")
	for child in get_children():
		if child is SupernovaTarget:
			child.set_forecast_visible(forecast)
	for child in get_children():
		var id := String(child.get("target_id"))
		if TARGET_SPECS.has(id):
			child.global_position = _screen_point(Vector2(Dictionary(TARGET_SPECS[id]).screen_position))
	if progression.has_upgrade("phoenix_lensed_meteors") and meteor_layer != null:
		for meteor in meteor_layer.get_children():
			register_meteor(meteor)
	queue_redraw()


func register_meteor(meteor) -> bool:
	if (
		progression == null
		or not progression.has_upgrade("phoenix_lensed_meteors")
		or meteor == null
		or not meteor.has_method("set_lens_curve")
	):
		return false
	var center := get_lens_center()
	var radius := _world_px(LENS_ZONE_RADIUS_SCREEN)
	var entry := Vector2(meteor.entry_position)
	var burnout := Vector2(meteor.burnout_position)
	if _distance_to_segment(center, entry, burnout) > radius:
		return false
	var midpoint := entry.lerp(burnout, 0.5)
	var direction := (burnout - entry).normalized()
	if direction.is_zero_approx():
		return false
	var normal := Vector2(-direction.y, direction.x)
	var side := -1.0 if int(meteor.get_instance_id()) % 2 == 0 else 1.0
	var control := midpoint.lerp(center, 0.72) + normal * radius * 0.34 * side
	var activity := _meteor_activity_rect().grow(-_world_px(4.0))
	control.x = clampf(control.x, activity.position.x, activity.end.x)
	control.y = clampf(control.y, activity.position.y, activity.end.y)
	meteor.set_lens_curve(control, center, radius, activity)
	return true


func get_lens_center() -> Vector2:
	return _screen_point(Vector2(576.0, 314.0))


func get_lens_radius() -> float:
	return _world_px(LENS_ZONE_RADIUS_SCREEN)


func is_record_complete() -> bool:
	for target_id_variant in TARGET_SPECS.keys():
		if not completed_targets.has(String(target_id_variant)):
			return false
	return true


func get_completed_record_count() -> int:
	var count := 0
	for target_id_variant in TARGET_SPECS.keys():
		if completed_targets.has(String(target_id_variant)):
			count += 1
	return count


func get_record_target_count() -> int:
	return TARGET_SPECS.size()


func get_save_data() -> Dictionary:
	var targets: Array[Dictionary] = []
	for child in get_children():
		if child.has_method("get_save_data"):
			targets.append(child.get_save_data())
	return {
		"completed_targets": completed_targets.keys(),
		"targets": targets,
	}


func load_save_data(data: Dictionary) -> void:
	completed_targets.clear()
	var saved_completed = data.get("completed_targets", [])
	if saved_completed is Array:
		for id_variant in saved_completed:
			var id := String(id_variant)
			if TARGET_SPECS.has(id):
				completed_targets[id] = true
	_clear_targets()
	refresh_unlock_state()
	var saved_targets = data.get("targets", [])
	if saved_targets is Array:
		for target_variant in saved_targets:
			if not (target_variant is Dictionary):
				continue
			var target_data: Dictionary = target_variant
			var target = _target_by_id(String(target_data.get("target_id", "")))
			if target != null:
				target.load_save_data(target_data)


func get_metrics() -> Dictionary:
	var active_supernovae := 0
	var active_arcs := 0
	for child in get_children():
		if child is SupernovaTarget:
			active_supernovae += 1
		elif child is BlackHoleTarget:
			active_arcs += 1
	return {
		"active_supernovae": active_supernovae,
		"active_arcs": active_arcs,
		"completed_targets": completed_targets.size(),
		"lens_field_unlocked": progression != null and progression.has_upgrade("phoenix_lensed_meteors"),
	}


func _ensure_target(id: String) -> void:
	if completed_targets.has(id) or _target_by_id(id) != null:
		return
	var spec: Dictionary = TARGET_SPECS[id]
	var target
	if String(spec.kind) == "supernova":
		target = SupernovaTarget.new()
		add_child(target)
		target.configure(
			id,
			_screen_point(Vector2(spec.screen_position)),
			float(spec.get("phase_offset", 0.0)),
			progression.has_upgrade("ic1613_supernova_ephemeris"),
			observation_view
		)
	else:
		target = BlackHoleTarget.new()
		add_child(target)
		target.configure(
			id,
			String(spec.type_id),
			_screen_point(Vector2(spec.screen_position)),
			float(spec.radius),
			float(spec.arc_start),
			float(spec.arc_span),
			observation_view,
			bool(spec.get("supernova", false))
		)
	target.observed.connect(_on_target_observed)


func _on_target_observed(target, reward: float, multiplier: float, _was_manual: bool, quality_grade: String) -> void:
	if progression == null:
		return
	var id := String(target.target_id)
	completed_targets[id] = true
	var final_reward: float = progression.add_galactic_observation(reward, multiplier)
	phenomenon_observed.emit(target, final_reward, multiplier, quality_grade)
	target.call_deferred("queue_free")
	refresh_unlock_state.call_deferred()


func _target_by_id(id: String):
	for child in get_children():
		if String(child.get("target_id")) == id:
			return child
	return null


func _clear_targets() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _draw() -> void:
	if progression == null or not progression.has_upgrade("phoenix_lensed_meteors"):
		return
	var center := get_lens_center() - global_position
	var radius := get_lens_radius()
	var scale := _world_px(1.0)
	draw_circle(center, radius, Color(UITheme.ACCENT_DEEP, 0.018))
	for index in range(18):
		var start := TAU * float(index) / 18.0
		draw_arc(center, radius, start, start + TAU * 0.027, 5, Color(UITheme.ACCENT_LINE, 0.32), 1.2 * scale, true)
	draw_circle(center, 10.0 * scale, Color(0.0, 0.0, 0.0, 0.82))


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _screen_point(point: Vector2) -> Vector2:
	if observation_view != null:
		return observation_view.screen_to_world(point)
	return point


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels


func _meteor_activity_rect() -> Rect2:
	if observation_view != null:
		return observation_view.meteor_activity_rect()
	return get_viewport_rect()
