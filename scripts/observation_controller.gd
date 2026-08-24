extends Node2D

const TRACKING_BREAK_MULTIPLIER := 1.72
const TRACKING_GRACE_SECONDS := 0.14
const DEFAULT_TRACKING_RADIUS := 36.0

var meteor_layer: Node2D
var progression: Node
var hud: CanvasLayer
var selected_meteor = null
var hovered_meteor = null
var tracked_meteors: Array = []
var cursor_position := Vector2.ZERO
var previous_cursor_position := Vector2.ZERO
var cursor_initialized: bool = false
var was_holding: bool = false
var tracking_grace_remaining: float = 0.0
var tracking_visual_active_last_frame: bool = false
var native_cursor_visible: bool = false


func setup(target_layer: Node2D, progression_controller: Node, hud_layer: CanvasLayer) -> void:
	meteor_layer = target_layer
	progression = progression_controller
	hud = hud_layer
	# Keep the engine-side mouse state coalesced. Gameplay samples that state once
	# per rendered frame and does not subscribe to raw mouse-motion callbacks.
	Input.set_use_accumulated_input(true)
	# The game draws its own cursor below. Hiding the native cursor prevents the
	# OS-composited cursor from racing ahead of the rendered game during a stall.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	native_cursor_visible = false
	cursor_position = get_viewport().get_mouse_position()
	previous_cursor_position = cursor_position
	cursor_initialized = true


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func reset() -> void:
	selected_meteor = null
	hovered_meteor = null
	tracked_meteors.clear()
	tracking_grace_remaining = 0.0
	was_holding = false
	tracking_visual_active_last_frame = false
	if hud != null:
		hud.hide_tracking()
	queue_redraw()


func _process(delta: float) -> void:
	if meteor_layer == null:
		return
	var sampled_cursor := get_viewport().get_mouse_position()
	if not cursor_initialized:
		cursor_position = sampled_cursor
		previous_cursor_position = sampled_cursor
		cursor_initialized = true
	else:
		previous_cursor_position = cursor_position
		cursor_position = sampled_cursor
	var holding: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var cursor_on_ui := _cursor_is_on_ui()
	_set_native_cursor_visible(cursor_on_ui)
	if holding and not cursor_on_ui:
		hovered_meteor = null
		_update_manual_tracking(delta)
	else:
		selected_meteor = null
		tracked_meteors.clear()
		tracking_grace_remaining = 0.0
		hovered_meteor = null if cursor_on_ui else _find_target_under_cursor()

	if _selection_is_valid():
		var predicted_multiplier: float = selected_meteor.get_predicted_multiplier()
		hud.set_tracking(
			selected_meteor.get_progress(),
			String(selected_meteor.type_id),
			predicted_multiplier,
			maxi(1, _valid_tracked_count()),
			cursor_position
		)
	else:
		hud.hide_tracking()
	# Keep animated tracking feedback live, but leave an idle software cursor
	# cached until either it moves or a tracking visual changes state.
	var tracking_visual_active := (
		_selection_is_valid()
		or _target_is_valid(hovered_meteor)
		or not tracked_meteors.is_empty()
	)
	if cursor_position != previous_cursor_position or tracking_visual_active or tracking_visual_active_last_frame:
		queue_redraw()
	tracking_visual_active_last_frame = tracking_visual_active
	was_holding = holding


func _update_manual_tracking(delta: float) -> void:
	tracked_meteors.clear()
	# On button-down, keep the previous rendered position as the sweep origin.
	# This covers fast press-and-drag motion without subscribing to raw events.
	if not _selection_is_valid():
		selected_meteor = _find_target_under_cursor()
		if _selection_is_valid():
			tracking_grace_remaining = TRACKING_GRACE_SECONDS
	if not _selection_is_valid():
		return

	var primary = selected_meteor
	var tracking_radius: float = primary.get_tracking_radius(progression.get_tracking_radius())
	var current_distance: float = cursor_position.distance_to(primary.global_position)
	if _apply_manual_contact(primary, delta):
		tracking_grace_remaining = TRACKING_GRACE_SECONDS
		_append_tracked_if_valid(primary)
	elif current_distance <= tracking_radius * TRACKING_BREAK_MULTIPLIER:
		# The soft outer ring pauses progress but keeps the target latched.
		tracking_grace_remaining = TRACKING_GRACE_SECONDS
	else:
		tracking_grace_remaining -= delta
		if tracking_grace_remaining <= 0.0:
			selected_meteor = null

	if progression.has_upgrade("multi_target_analysis"):
		_observe_additional_targets(delta, primary)
		var closest_tracked = _closest_valid_tracked_target()
		if closest_tracked != null:
			selected_meteor = closest_tracked


func _observe_additional_targets(delta: float, primary) -> void:
	var child_count := meteor_layer.get_child_count()
	for child_index in range(child_count):
		var child := meteor_layer.get_child(child_index)
		if child == primary or not _target_is_valid(child):
			continue
		if _apply_manual_contact(child, delta):
			_append_tracked_if_valid(child)


func _apply_manual_contact(target, delta: float) -> bool:
	if not _target_is_valid(target):
		return false
	var tracking_radius: float = target.get_tracking_radius(progression.get_tracking_radius())
	var current_distance: float = cursor_position.distance_to(target.global_position)
	if current_distance <= tracking_radius:
		target.apply_manual_observation(delta, current_distance, tracking_radius)
		return true
	var swept_distance := _distance_to_cursor_path(target.global_position)
	if swept_distance <= tracking_radius:
		# Credit only the estimated fraction of the frame spent inside the
		# tracking radius; a fast flick can acquire but cannot grant free progress.
		var contact_scale := _estimate_sweep_contact_scale(tracking_radius, swept_distance)
		target.apply_manual_observation(delta * contact_scale, swept_distance, tracking_radius)
		return true
	return false


func _append_tracked_if_valid(target) -> void:
	if _target_is_valid(target) and target not in tracked_meteors:
		tracked_meteors.append(target)


func _closest_valid_tracked_target():
	var closest = null
	var closest_distance := INF
	for target in tracked_meteors:
		if not _target_is_valid(target):
			continue
		var distance: float = cursor_position.distance_squared_to(target.global_position)
		if distance < closest_distance:
			closest = target
			closest_distance = distance
	return closest


func _valid_tracked_count() -> int:
	var count := 0
	for target in tracked_meteors:
		if _target_is_valid(target):
			count += 1
	return count


func release_target(target = null) -> void:
	if target != null:
		tracked_meteors.erase(target)
		if hovered_meteor == target:
			hovered_meteor = null
	if target == null or selected_meteor == target:
		selected_meteor = null
		if target == null:
			tracked_meteors.clear()
		tracking_grace_remaining = 0.0
		hud.hide_tracking()
		queue_redraw()


func _find_target_under_cursor():
	var closest = null
	var closest_distance := INF
	var child_count := meteor_layer.get_child_count()
	for child_index in range(child_count):
		var child := meteor_layer.get_child(child_index)
		if not child.has_method("can_be_tracked") or not child.can_be_tracked():
			continue
		var tracking_radius: float = child.get_tracking_radius(progression.get_tracking_radius())
		# Swept point-to-segment distance prevents fast mouse movement from
		# tunnelling straight through a target between two rendered frames.
		var distance: float = _distance_to_cursor_path(child.global_position)
		if distance <= tracking_radius and distance < closest_distance:
			closest = child
			closest_distance = distance
	return closest


func _distance_to_cursor_path(point: Vector2) -> float:
	var segment := cursor_position - previous_cursor_position
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(cursor_position)
	var projection := clampf((point - previous_cursor_position).dot(segment) / length_squared, 0.0, 1.0)
	var closest_point := previous_cursor_position + segment * projection
	return point.distance_to(closest_point)


func _estimate_sweep_contact_scale(radius: float, distance_to_path: float) -> float:
	var path_length := previous_cursor_position.distance_to(cursor_position)
	if path_length <= 0.001:
		return 1.0
	var half_chord := sqrt(maxf(0.0, radius * radius - distance_to_path * distance_to_path))
	var estimated_inside_fraction := (half_chord * 2.0) / path_length
	return clampf(estimated_inside_fraction, 0.12, 1.0)


func _selection_is_valid() -> bool:
	return _target_is_valid(selected_meteor)


func _target_is_valid(target) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.has_method("can_be_tracked") and target.can_be_tracked()


func _cursor_is_on_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
		return true
	return hud != null and hud.has_method("is_pointer_over_hud") and hud.is_pointer_over_hud(cursor_position)


func _set_native_cursor_visible(visible: bool) -> void:
	var desired_mode := Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_HIDDEN
	var mode_changed := native_cursor_visible != visible
	native_cursor_visible = visible
	if Input.mouse_mode != desired_mode:
		Input.mouse_mode = desired_mode
	if mode_changed:
		queue_redraw()


func _draw() -> void:
	if not native_cursor_visible:
		_draw_software_cursor()
	if _selection_is_valid():
		_draw_tracking_ring(selected_meteor, true)
	elif _target_is_valid(hovered_meteor):
		_draw_hover_ring(hovered_meteor)
	for target in tracked_meteors:
		if target != selected_meteor and _target_is_valid(target):
			_draw_tracking_ring(target, false)


func _draw_software_cursor() -> void:
	# The cursor is the observation field itself, so Better Lens communicates its
	# wider range directly instead of relying on a separate crosshair.
	var observation_radius := _software_cursor_radius()
	var shadow_color := Color(0.01, 0.025, 0.05, 0.94)
	var cursor_color := Color("7dffe0") if was_holding else Color("b8f3ff")
	var field_alpha := 0.065 if was_holding else 0.026
	draw_circle(cursor_position, observation_radius, Color(cursor_color, field_alpha))
	draw_arc(cursor_position, observation_radius, 0.0, TAU, 64, shadow_color, 4.2, true)
	draw_arc(cursor_position, observation_radius, 0.0, TAU, 64, Color(cursor_color, 0.96 if was_holding else 0.72), 1.8, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var range_tick_start: Vector2 = cursor_position + direction * (observation_radius - 4.0)
		var range_tick_end: Vector2 = cursor_position + direction * (observation_radius + 5.0)
		draw_line(range_tick_start, range_tick_end, shadow_color, 4.2, true)
		draw_line(range_tick_start, range_tick_end, cursor_color, 1.8, true)
		var center_mark_start: Vector2 = cursor_position + direction * 4.0
		var center_mark_end: Vector2 = cursor_position + direction * 8.0
		draw_line(center_mark_start, center_mark_end, shadow_color, 4.0, true)
		draw_line(center_mark_start, center_mark_end, cursor_color, 1.6, true)
	draw_circle(cursor_position, 4.0, shadow_color)
	draw_circle(cursor_position, 1.8, Color("f4ffff"))


func _software_cursor_radius() -> float:
	return progression.get_tracking_radius() if progression != null else DEFAULT_TRACKING_RADIUS


func _draw_tracking_ring(target, is_primary: bool) -> void:
	var tracking_radius: float = target.get_tracking_radius(progression.get_tracking_radius())
	var quality: float = target.get_quality()
	var ring_color := Color("82d7ff").lerp(Color("77ffd0"), quality)
	var outer_alpha := 0.48 if is_primary else 0.22
	var progress_alpha := 1.0 if is_primary else 0.76
	draw_circle(target.global_position, tracking_radius + 4.0, Color(ring_color, 0.035 if is_primary else 0.018))
	draw_arc(target.global_position, tracking_radius, 0.0, TAU, 48, Color(ring_color, outer_alpha), 2.0 if is_primary else 1.3, true)
	draw_arc(
		target.global_position,
		tracking_radius - 4.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * target.get_progress(),
		48,
		Color(ring_color, progress_alpha),
		3.5 if is_primary else 2.1,
		true
	)
	if is_primary:
		draw_line(cursor_position, target.global_position, Color(ring_color, 0.18), 1.0, true)


func _draw_hover_ring(target) -> void:
	var tracking_radius: float = target.get_tracking_radius(progression.get_tracking_radius())
	var ring_color := Color("82d7ff")
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.06
	var radius := tracking_radius * pulse
	draw_arc(target.global_position, radius, 0.0, TAU, 40, Color(ring_color, 0.34), 1.8, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		draw_line(
			target.global_position + direction * (radius - 5.0),
			target.global_position + direction * (radius + 5.0),
			Color(ring_color, 0.62),
			2.0,
			true
		)
