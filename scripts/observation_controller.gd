extends Node2D

const TRACKING_BREAK_MULTIPLIER := 1.72
const TRACKING_GRACE_SECONDS := 0.14

var meteor_layer: Node2D
var progression: Node
var hud: CanvasLayer
var selected_meteor = null
var cursor_position := Vector2.ZERO
var previous_cursor_position := Vector2.ZERO
var cursor_initialized: bool = false
var was_holding: bool = false
var tracking_grace_remaining: float = 0.0


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
	cursor_position = get_viewport().get_mouse_position()
	previous_cursor_position = cursor_position
	cursor_initialized = true


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func reset() -> void:
	selected_meteor = null
	tracking_grace_remaining = 0.0
	was_holding = false
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
	if holding and not _cursor_is_on_interactive_ui():
		# On button-down, keep the previous rendered position as the sweep origin.
		# This covers fast press-and-drag motion without subscribing to raw events.
		if not _selection_is_valid():
			selected_meteor = _find_target_under_cursor()
			if _selection_is_valid():
				tracking_grace_remaining = TRACKING_GRACE_SECONDS
		if _selection_is_valid():
			var tracking_radius: float = selected_meteor.get_tracking_radius(progression.get_tracking_radius())
			var current_distance: float = cursor_position.distance_to(selected_meteor.global_position)
			var swept_distance := _distance_to_cursor_path(selected_meteor.global_position)
			if current_distance <= tracking_radius:
				selected_meteor.apply_manual_observation(delta, current_distance, tracking_radius)
				tracking_grace_remaining = TRACKING_GRACE_SECONDS
			elif swept_distance <= tracking_radius:
				# Credit only the estimated fraction of the frame spent inside the
				# tracking radius; a fast flick can acquire but cannot grant free progress.
				var contact_scale := _estimate_sweep_contact_scale(tracking_radius, swept_distance)
				selected_meteor.apply_manual_observation(delta * contact_scale, swept_distance, tracking_radius)
				tracking_grace_remaining = TRACKING_GRACE_SECONDS
			elif current_distance <= tracking_radius * TRACKING_BREAK_MULTIPLIER:
				# The soft outer ring pauses progress but keeps the target latched.
				tracking_grace_remaining = TRACKING_GRACE_SECONDS
			else:
				tracking_grace_remaining -= delta
				if tracking_grace_remaining <= 0.0:
					selected_meteor = null
	else:
		selected_meteor = null
		tracking_grace_remaining = 0.0

	if _selection_is_valid():
		var predicted_multiplier: float = selected_meteor.get_predicted_multiplier()
		hud.set_tracking(
			selected_meteor.get_progress(),
			String(selected_meteor.type_id),
			predicted_multiplier
		)
	else:
		hud.hide_tracking()
	# The restored software cursor follows the latest sampled position.
	queue_redraw()
	was_holding = holding


func release_target(target = null) -> void:
	if target == null or selected_meteor == target:
		selected_meteor = null
		tracking_grace_remaining = 0.0
		hud.hide_tracking()
		queue_redraw()


func _find_target_under_cursor():
	var closest = null
	var closest_distance := INF
	for child in meteor_layer.get_children():
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
	return is_instance_valid(selected_meteor) and not selected_meteor.is_queued_for_deletion() and selected_meteor.can_be_tracked()


func _cursor_is_on_interactive_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Lightweight software cursor and tracking feedback.
	var cursor_tint := Color(0.62, 0.81, 1.0, 0.34)
	draw_arc(cursor_position, 9.0, 0.0, TAU, 24, cursor_tint, 1.0, true)
	draw_line(cursor_position + Vector2(-14, 0), cursor_position + Vector2(-7, 0), cursor_tint, 1.0)
	draw_line(cursor_position + Vector2(7, 0), cursor_position + Vector2(14, 0), cursor_tint, 1.0)
	draw_line(cursor_position + Vector2(0, -14), cursor_position + Vector2(0, -7), cursor_tint, 1.0)
	draw_line(cursor_position + Vector2(0, 7), cursor_position + Vector2(0, 14), cursor_tint, 1.0)
	if _selection_is_valid():
		var tracking_radius: float = selected_meteor.get_tracking_radius(progression.get_tracking_radius())
		var quality: float = selected_meteor.get_quality()
		var ring_color := Color("82d7ff").lerp(Color("77ffd0"), quality)
		draw_arc(selected_meteor.global_position, tracking_radius, 0.0, TAU, 48, Color(ring_color, 0.22), 1.5, true)
		draw_arc(
			selected_meteor.global_position,
			tracking_radius - 4.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * selected_meteor.get_progress(),
			48,
			Color(ring_color, 0.9),
			2.4,
			true
		)
		draw_line(cursor_position, selected_meteor.global_position, Color(ring_color, 0.12), 1.0, true)
