extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")
const Modules = preload("res://scripts/observation_modules.gd")

const TRACKING_BREAK_MULTIPLIER := 1.72
const TRACKING_GRACE_SECONDS := 0.14
const DEFAULT_TRACKING_RADIUS := 36.0
const SCAN_INTENT_DISTANCE := 14.0

enum InteractionMode {
	NONE,
	PENDING,
	TRACKING,
	SCANNING,
}

var meteor_layer: Node2D
var additional_target_layers: Array[Node2D] = []
var modules: RefCounted
var progression: Node
var hud: CanvasLayer
var survey: Node2D
var observation_view: Camera2D
var selected_meteor = null
var hovered_meteor = null
var tracked_meteors: Array = []
var cursor_position := Vector2.ZERO
var previous_cursor_position := Vector2.ZERO
var cursor_initialized: bool = false
var was_holding: bool = false
var tracking_grace_remaining: float = 0.0
var tracking_visual_active_last_frame: bool = false
var perseid_indicator_visible_last_frame: bool = false
var perseid_target_count_last_frame: int = -1
var native_cursor_visible: bool = false
var interaction_mode: InteractionMode = InteractionMode.NONE
var pending_blank_distance: float = 0.0
var primary_tracking_id := 0
var primary_tracking_seconds := 0.0
var _manual_frame_active := false
var _manual_frame_primary = null
var _manual_frame_secondary = null


func setup(target_layer: Node2D, progression_controller: Node, hud_layer: CanvasLayer, survey_controller: Node2D = null, view: Camera2D = null, extra_target_layer = null) -> void:
	meteor_layer = target_layer
	additional_target_layers.clear()
	if extra_target_layer is Array:
		for layer_variant in extra_target_layer:
			if layer_variant is Node2D:
				additional_target_layers.append(layer_variant)
	elif extra_target_layer is Node2D:
		additional_target_layers.append(extra_target_layer)
	progression = progression_controller
	hud = hud_layer
	survey = survey_controller
	observation_view = view
	# Keep the engine-side mouse state coalesced. Gameplay samples that state once
	# per rendered frame and does not subscribe to raw mouse-motion callbacks.
	Input.set_use_accumulated_input(true)
	# The game draws its own cursor below. Hiding the native cursor prevents the
	# OS-composited cursor from racing ahead of the rendered game during a stall.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	native_cursor_visible = false
	cursor_position = _screen_to_world(get_viewport().get_mouse_position())
	previous_cursor_position = cursor_position
	cursor_initialized = true


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_set_m31_manual_contact(false)


func reset() -> void:
	selected_meteor = null
	hovered_meteor = null
	tracked_meteors.clear()
	tracking_grace_remaining = 0.0
	was_holding = false
	tracking_visual_active_last_frame = false
	perseid_indicator_visible_last_frame = false
	perseid_target_count_last_frame = -1
	interaction_mode = InteractionMode.NONE
	pending_blank_distance = 0.0
	_reset_primary_tracking()
	_set_m31_manual_contact(false)
	if survey != null:
		survey.set_scanning(false, cursor_position)
	if hud != null:
		hud.hide_tracking()
	queue_redraw()


func _process(delta: float) -> void:
	if meteor_layer == null:
		return
	var sampled_cursor := _screen_to_world(get_viewport().get_mouse_position())
	if not cursor_initialized:
		cursor_position = sampled_cursor
		previous_cursor_position = sampled_cursor
		cursor_initialized = true
	else:
		previous_cursor_position = cursor_position
		cursor_position = sampled_cursor
	var holding: bool = Input.is_action_pressed(&"nw_observe")
	# The flag describes this rendered input frame, never a past M31 selection.
	# Resetting it before contact evaluation also prevents paused/modal state from
	# leaving Reference Bus eligible after input has stopped.
	_set_m31_manual_contact(false)
	var cursor_on_ui := _cursor_is_on_ui()
	_set_native_cursor_visible(cursor_on_ui)
	if holding and not cursor_on_ui:
		hovered_meteor = null
		if _survey_input_enabled():
			_update_survey_interaction(delta)
		else:
			_update_manual_tracking(delta)
	else:
		_clear_interaction_mode()
		hovered_meteor = null if cursor_on_ui else _find_target_under_cursor()

	if _selection_is_valid():
		var predicted_multiplier: float = selected_meteor.get_predicted_multiplier()
		hud.set_tracking(
			selected_meteor.get_progress(),
			String(selected_meteor.type_id),
			predicted_multiplier,
			maxi(1, _valid_tracked_count()),
			_world_to_screen(cursor_position),
			_screen_length(_software_cursor_radius()),
			clampf(1.0 - _target_contact_distance(selected_meteor, cursor_position) / maxf(_software_cursor_radius(), 1.0), 0.0, 1.0)
		)
	else:
		hud.hide_tracking()
	# Keep animated tracking feedback live, but leave an idle software cursor
	# cached until either it moves or a tracking visual changes state.
	var combo_visual_active: bool = (
		progression != null
		and progression.get_manual_combo_display_count() > 0
	)
	var perseid_indicator_visible: bool = (
		progression != null
		and progression.has_upgrade("perseid_survey")
	)
	var perseid_target_count := _active_atmospheric_target_count() if perseid_indicator_visible else 0
	var perseid_visual_changed := (
		perseid_indicator_visible != perseid_indicator_visible_last_frame
		or perseid_target_count != perseid_target_count_last_frame
	)
	var tracking_visual_active: bool = (
		_selection_is_valid()
		or _target_is_valid(hovered_meteor)
		or not tracked_meteors.is_empty()
		or combo_visual_active
	)
	if cursor_position != previous_cursor_position or tracking_visual_active or tracking_visual_active_last_frame or perseid_visual_changed:
		queue_redraw()
	tracking_visual_active_last_frame = tracking_visual_active
	perseid_indicator_visible_last_frame = perseid_indicator_visible
	perseid_target_count_last_frame = perseid_target_count
	was_holding = holding


func _survey_input_enabled() -> bool:
	return survey != null and progression != null and progression.survey_enabled()


func _update_survey_interaction(delta: float) -> void:
	# One held gesture can alternate freely. Tracking (including its existing
	# soft lock/grace period) owns the frame before empty-sky travel is considered.
	# A completion still owns that frame, so its cursor travel is not also charged.
	if _update_manual_tracking(delta, true):
		interaction_mode = InteractionMode.TRACKING
		pending_blank_distance = 0.0
		survey.set_scanning(false, cursor_position, true)
		return

	if interaction_mode != InteractionMode.SCANNING:
		if interaction_mode != InteractionMode.PENDING:
			pending_blank_distance = 0.0
		interaction_mode = InteractionMode.PENDING
		pending_blank_distance += previous_cursor_position.distance_to(cursor_position)
		if pending_blank_distance < _world_px(SCAN_INTENT_DISTANCE):
			survey.set_scanning(false, cursor_position, true)
			return
		interaction_mode = InteractionMode.SCANNING
	survey.set_scanning(true, cursor_position)
	survey.apply_scan_segment(previous_cursor_position, cursor_position, delta / maxf(Engine.time_scale, 0.001))


func _clear_interaction_mode() -> void:
	selected_meteor = null
	tracked_meteors.clear()
	tracking_grace_remaining = 0.0
	interaction_mode = InteractionMode.NONE
	pending_blank_distance = 0.0
	_reset_primary_tracking()
	_set_m31_manual_contact(false)
	if survey != null:
		survey.set_scanning(false, cursor_position)


func _update_manual_tracking(delta: float, keep_primary: bool = false) -> bool:
	tracked_meteors.clear()
	# On button-down, keep the previous rendered position as the sweep origin.
	# This covers fast press-and-drag motion without subscribing to raw events.
	if not _selection_is_valid():
		selected_meteor = _find_target_under_cursor()
		if _selection_is_valid():
			tracking_grace_remaining = TRACKING_GRACE_SECONDS
	if not _selection_is_valid():
		_reset_primary_tracking()
		return false

	var primary = selected_meteor
	# Synchronous completion can release selected_meteor during this pass. Keep
	# the two boosted recipients stable so successive completions cannot promote
	# every additional target into Dual Processor's second position.
	_manual_frame_active = true
	_manual_frame_primary = primary
	_manual_frame_secondary = _dual_processor_secondary() if modules != null and modules.has("dual_processor") else null
	_sync_primary_tracking(primary)
	var tracking_radius: float = primary.get_tracking_radius(_world_px(_module_tracking_radius()))
	var current_distance: float = _target_contact_distance(primary, cursor_position)
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
			_reset_primary_tracking()

	if progression.has_upgrade("multi_target_analysis") or (modules != null and int(modules.effect("targets")) > 1):
		_observe_additional_targets(delta, primary)
		var closest_tracked = _closest_valid_tracked_target()
		if closest_tracked != null and (not keep_primary or not _selection_is_valid()):
			selected_meteor = closest_tracked
	_manual_frame_active = false
	_manual_frame_primary = null
	_manual_frame_secondary = null
	return true


func _observe_additional_targets(delta: float, primary) -> void:
	var limit := 100000 if progression.has_upgrade("multi_target_analysis") else int(modules.effect("targets"))
	for child in _target_children():
		if tracked_meteors.size() >= limit:
			break
		if child == primary or not _target_is_valid(child):
			continue
		if _apply_manual_contact(child, delta):
			_append_tracked_if_valid(child)


func _apply_manual_contact(target, delta: float) -> bool:
	if not _target_is_valid(target):
		return false
	var tracking_radius: float = target.get_tracking_radius(_world_px(_module_tracking_radius()))
	var manual_speed := _module_manual_speed_for_target(target)
	if target.has_method("apply_manual_cursor_path"):
		var path_contact: bool = target.apply_manual_cursor_path(
			delta,
			previous_cursor_position,
			cursor_position,
			tracking_radius,
			manual_speed
		)
		if path_contact:
			_note_manual_contact(target, delta)
		return path_contact
	var current_distance: float = _target_contact_distance(target, cursor_position)
	if current_distance <= tracking_radius:
		target.apply_manual_observation(
			delta,
			current_distance,
			tracking_radius,
			manual_speed
		)
		_note_manual_contact(target, delta)
		return true
	var swept_distance := _target_cursor_path_distance(target)
	if swept_distance <= tracking_radius:
		# Credit only the estimated fraction of the frame spent inside the
		# tracking radius; a fast flick can acquire but cannot grant free progress.
		var contact_scale := _estimate_sweep_contact_scale(tracking_radius, swept_distance)
		target.apply_manual_observation(
			delta * contact_scale,
			swept_distance,
			tracking_radius,
			manual_speed
		)
		_note_manual_contact(target, delta * contact_scale)
		return true
	if _trail_integrator_eligible(target):
		var trail_distance := _trail_cursor_path_distance(target)
		if trail_distance <= tracking_radius:
			var trail_scale := _estimate_sweep_contact_scale(tracking_radius, trail_distance)
			var trail_speed := manual_speed * float(Modules.DEFINITIONS.trail_integrator.trail_progress)
			target.apply_manual_observation(
				delta * trail_scale,
				trail_distance,
				tracking_radius,
				trail_speed
			)
			_note_manual_contact(target, delta * trail_scale)
			return true
	return false


func _note_manual_contact(target, effective_delta: float) -> void:
	# Completion handlers can release a target synchronously from the observation
	# call above. Do not recreate a live-contact flag after that release.
	if not _target_is_valid(target):
		return
	if target == selected_meteor:
		primary_tracking_seconds += maxf(0.0, effective_delta)
	if String(target.get("type_id")) == "andromeda":
		_set_m31_manual_contact(true)


func _trail_integrator_eligible(target) -> bool:
	if modules == null or not modules.has("trail_integrator"):
		return false
	if not target.has_method("get_recent_observation_trail"):
		return false
	return String(target.get("type_id")) not in ["andromeda", "fireball", "major"]


func _trail_cursor_path_distance(target) -> float:
	var closest := INF
	var trail: PackedVector2Array = target.get_recent_observation_trail()
	for point in trail:
		closest = minf(closest, _distance_to_cursor_path(point))
	return closest


func _append_tracked_if_valid(target) -> void:
	if _target_is_valid(target) and target not in tracked_meteors:
		tracked_meteors.append(target)


func _closest_valid_tracked_target():
	var closest = null
	var closest_distance := INF
	for target in tracked_meteors:
		if not _target_is_valid(target):
			continue
		var distance: float = _target_contact_distance(target, cursor_position)
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
		_reset_primary_tracking()
		_set_m31_manual_contact(false)
		if target == null:
			tracked_meteors.clear()
			interaction_mode = InteractionMode.NONE
			pending_blank_distance = 0.0
			if survey != null:
				survey.set_scanning(false, cursor_position)
		tracking_grace_remaining = 0.0
		hud.hide_tracking()
		queue_redraw()


func _find_target_under_cursor():
	var closest = null
	var closest_distance := INF
	for child in _target_children():
		if not _target_is_valid(child):
			continue
		var tracking_radius: float = child.get_tracking_radius(_world_px(_module_tracking_radius()))
		# Swept point-to-segment distance prevents fast mouse movement from
		# tunnelling straight through a target between two rendered frames.
		var distance: float = _target_cursor_path_distance(child)
		if _trail_integrator_eligible(child):
			distance = minf(distance, _trail_cursor_path_distance(child))
		if distance <= tracking_radius and distance < closest_distance:
			closest = child
			closest_distance = distance
	return closest


func _target_children() -> Array:
	var targets: Array = []
	if meteor_layer != null:
		targets.append_array(meteor_layer.get_children())
	for layer in additional_target_layers:
		if layer != null:
			targets.append_array(layer.get_children())
	return targets


func _target_contact_distance(target, point: Vector2) -> float:
	if target.has_method("get_manual_contact_distance"):
		return float(target.get_manual_contact_distance(point))
	return point.distance_to(target.global_position)


func _target_cursor_path_distance(target) -> float:
	if target.has_method("get_cursor_path_contact_distance"):
		return float(target.get_cursor_path_contact_distance(previous_cursor_position, cursor_position))
	return _distance_to_cursor_path(target.global_position)


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


func _sync_primary_tracking(target) -> void:
	if target == null or not is_instance_valid(target):
		_reset_primary_tracking()
		return
	var target_id: int = target.get_instance_id()
	if primary_tracking_id != target_id:
		primary_tracking_id = target_id
		primary_tracking_seconds = 0.0


func _reset_primary_tracking() -> void:
	primary_tracking_id = 0
	primary_tracking_seconds = 0.0


func _set_m31_manual_contact(active: bool) -> void:
	if modules != null and modules.has_method("set_m31_manual_active"):
		modules.set_m31_manual_active(active)


func _cursor_is_on_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE:
		return true
	return hud != null and hud.has_method("is_pointer_over_hud") and hud.is_pointer_over_hud(_world_to_screen(cursor_position))


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
	var visual_scale := _world_px(1.0)
	var tracking := _selection_is_valid()
	var progress: float = selected_meteor.get_progress() if tracking else 0.0
	# The cursor and the progress gauge are one circle. They used to be two rings
	# a few pixels apart, both centred here, drawing the same place twice.
	#
	# It is also where the neutral white belongs. Idle, this is the player's hand
	# and stays in red light; the moment it latches onto a target it becomes the
	# live instrument and is the only neutral-white thing on screen. The colour
	# change is what says "you are measuring now".
	var shadow_color := Color(0.02, 0.025, 0.035, 0.56)
	var cursor_color := UITheme.INSTRUMENT_ARC if tracking else UITheme.INK_HIGH
	var reticle_alpha := 0.17 if tracking else (0.42 if was_holding else 0.26)
	# An unfilled optical field leaves the target's light and colour intact.
	# The real interaction radius remains visible without a heavy circular bezel.
	draw_arc(cursor_position, observation_radius, 0.0, TAU, 64, shadow_color, 2.6 * visual_scale, true)
	draw_arc(cursor_position, observation_radius, 0.0, TAU, 64, Color(cursor_color, reticle_alpha), 0.85 * visual_scale, true)
	if tracking and progress > 0.0:
		draw_arc(
			cursor_position,
			observation_radius,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			64,
			Color(cursor_color, 0.76),
			1.25 * visual_scale,
			true
		)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var range_tick_start: Vector2 = cursor_position + direction * (observation_radius + 2.0 * visual_scale)
		var range_tick_end: Vector2 = cursor_position + direction * (observation_radius + 6.0 * visual_scale)
		draw_line(range_tick_start, range_tick_end, shadow_color, 2.6 * visual_scale, true)
		draw_line(range_tick_start, range_tick_end, Color(cursor_color, 0.48), 1.0 * visual_scale, true)
		if not tracking:
			var center_mark_start: Vector2 = cursor_position + direction * 4.0 * visual_scale
			var center_mark_end: Vector2 = cursor_position + direction * 8.0 * visual_scale
			draw_line(center_mark_start, center_mark_end, shadow_color, 4.0 * visual_scale, true)
			draw_line(center_mark_start, center_mark_end, Color(cursor_color, reticle_alpha), 1.6 * visual_scale, true)
	if not tracking:
		draw_circle(cursor_position, 4.0 * visual_scale, shadow_color)
		draw_circle(cursor_position, 1.8 * visual_scale, cursor_color)
	_draw_manual_combo(observation_radius)
	_draw_perseid_survey_indicator(observation_radius)


func _draw_manual_combo(observation_radius: float) -> void:
	if progression == null:
		return
	var streak_count: int = progression.get_manual_combo_display_count()
	if streak_count <= 0:
		return
	var visual_scale := _world_px(1.0)
	var timer_radius := observation_radius + 8.0 * visual_scale
	var timer_progress: float = progression.get_manual_combo_progress()
	var timer_color := UITheme.ACCENT_LINE.lerp(UITheme.INK_MAX, clampf(float(streak_count) / 10.0, 0.0, 1.0))
	draw_arc(cursor_position, timer_radius, 0.0, TAU, 64, Color(UITheme.SHADOW, 0.44), 2.5 * visual_scale, true)
	draw_arc(
		cursor_position,
		timer_radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * timer_progress,
		64,
		Color(timer_color, 0.92),
		1.3 * visual_scale,
		true
	)
	var font: Font = UITheme.sans("medium")
	var font_size := int(round(float(UITheme.size_px(22.0)) * visual_scale))
	var label := tr("HUD_STREAK_COUNT") % streak_count
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var label_position := cursor_position + Vector2(timer_radius + 7.0 * visual_scale, float(font_size) * 0.35)
	var screen_size := get_viewport().get_visible_rect().size
	if _world_to_screen(label_position).x + _screen_length(label_width) > screen_size.x - 8.0:
		label_position.x = cursor_position.x - timer_radius - 7.0 * visual_scale - label_width
	var screen_position := _world_to_screen(label_position)
	screen_position.x = clampf(screen_position.x, 8.0, maxf(8.0, screen_size.x - _screen_length(label_width) - 8.0))
	screen_position.y = clampf(screen_position.y, _screen_length(font_size) + 8.0, screen_size.y - 8.0)
	label_position = _screen_to_world(screen_position)
	draw_string(
		font,
		label_position,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(timer_color, 0.94)
	)


func _draw_perseid_survey_indicator(observation_radius: float) -> void:
	if progression == null or not progression.has_upgrade("perseid_survey"):
		return
	var target_count := _active_atmospheric_target_count()
	var threshold: int = progression.PERSEID_SURVEY_TARGET_THRESHOLD
	var threshold_reached: bool = progression.is_perseid_survey_active(target_count)
	var visual_scale := _world_px(1.0)
	var pip_gap := 9.0 * visual_scale
	var pip_y := observation_radius + 15.0 * visual_scale
	var start_x := -float(threshold - 1) * pip_gap * 0.5
	var filled_count := mini(target_count, threshold)
	var filled_color: Color = UITheme.ACCENT_TEXT if threshold_reached else UITheme.ACCENT_LINE
	for index in range(threshold):
		var pip_position := cursor_position + Vector2(start_x + float(index) * pip_gap, pip_y)
		draw_circle(pip_position, 3.6 * visual_scale, Color(UITheme.SHADOW, 0.82))
		if index < filled_count:
			draw_circle(pip_position, 2.1 * visual_scale, Color(filled_color, 0.94))
		else:
			draw_arc(
				pip_position,
				2.0 * visual_scale,
				0.0,
				TAU,
				16,
				Color(UITheme.ACCENT_DEEP, 0.72),
				1.0 * visual_scale,
				true
			)


func _active_atmospheric_target_count() -> int:
	if meteor_layer == null:
		return 0
	var count := 0
	for candidate in meteor_layer.get_children():
		if _target_is_valid(candidate):
			count += 1
	return count


func _software_cursor_radius() -> float:
	return _world_px(_module_tracking_radius() if progression != null else DEFAULT_TRACKING_RADIUS)


func _draw_tracking_ring(target, is_primary: bool) -> void:
	if target.has_method("get_manual_contact_distance"):
		return
	var visual_scale := _world_px(1.0)
	var tracking_radius: float = target.get_tracking_radius(_world_px(_module_tracking_radius()))
	var quality: float = target.get_quality()
	# Quality rides brightness inside the palette: a poorly centred track sits
	# at the accent line, a perfectly centred one climbs to the brightest ink.
	var ring_color := UITheme.ACCENT_LINE.lerp(UITheme.INK_MAX, quality)
	# The primary target draws no ring at all. The cursor is the gauge for it and
	# is sitting on it, so a circle here only doubles the one already there. When
	# the cursor drifts inside the grace radius the connector line is what says
	# which object is still latched.
	if is_primary:
		if cursor_position.distance_to(target.global_position) > 2.0 * visual_scale:
			draw_line(cursor_position, target.global_position, Color(UITheme.ACCENT_DEEP, 0.45), 1.0 * visual_scale, true)
		return
	# Secondary targets keep a ring of their own, on one radius: the dim full
	# circle is the track and the bright arc fills it. The cursor gauge only ever
	# reports the primary, so these have nothing else showing their progress.
	draw_circle(target.global_position, tracking_radius, Color(ring_color, 0.018))
	draw_arc(target.global_position, tracking_radius, 0.0, TAU, 48, Color(ring_color, 0.16), 0.9 * visual_scale, true)
	draw_arc(
		target.global_position,
		tracking_radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * target.get_progress(),
		48,
		Color(ring_color, 0.76),
		1.8 * visual_scale,
		true
	)


func _draw_hover_ring(target) -> void:
	if target.has_method("get_manual_contact_distance"):
		return
	var visual_scale := _world_px(1.0)
	var tracking_radius: float = target.get_tracking_radius(_world_px(_module_tracking_radius()))
	# A hint, not a gauge, so it stays below the tracking ring.
	var ring_color := UITheme.INK_MID
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.06
	var radius := tracking_radius * pulse
	draw_arc(target.global_position, radius, 0.0, TAU, 40, Color(ring_color, 0.34), 1.8 * visual_scale, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.from_angle(angle)
		draw_line(
			target.global_position + direction * (radius - 5.0 * visual_scale),
			target.global_position + direction * (radius + 5.0 * visual_scale),
			Color(ring_color, 0.62),
			2.0 * visual_scale,
			true
		)


func _world_px(pixels: float) -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(pixels)
	return pixels


func _screen_length(world_length: float) -> float:
	return world_length / maxf(_world_px(1.0), 0.001)


func _screen_to_world(point: Vector2) -> Vector2:
	if observation_view != null:
		return observation_view.screen_to_world(point)
	return point


func _world_to_screen(point: Vector2) -> Vector2:
	if observation_view != null:
		return observation_view.world_to_screen(point)
	return point

func _module_tracking_radius() -> float:
	return progression.get_tracking_radius() * (float(modules.effect("radius")) if modules != null and progression.galaxy_unlocked() else 1.0)

func _module_manual_speed() -> float:
	# Compatibility helper retained for existing callers/tests. Conditional module
	# effects require a live target and are evaluated below.
	return progression.get_manual_analysis_speed_multiplier() * (float(modules.effect("speed")) if modules != null and progression.galaxy_unlocked() else 1.0)


func _module_manual_speed_for_target(target) -> float:
	var legacy_speed := _module_manual_speed()
	if modules == null or progression == null or not progression.galaxy_unlocked():
		return legacy_speed
	var new_multiplier := float(modules.effect("new_speed"))
	var is_primary: bool = target == (_manual_frame_primary if _manual_frame_active else selected_meteor)
	if modules.has("long_baseline") and is_primary and primary_tracking_seconds >= 1.0:
		new_multiplier *= float(Modules.DEFINITIONS.long_baseline.baseline_speed)
	if modules.has("dual_processor"):
		if is_primary or target == (_manual_frame_secondary if _manual_frame_active else _dual_processor_secondary()):
			new_multiplier *= float(Modules.DEFINITIONS.dual_processor.primary_speed)
		else:
			new_multiplier *= float(Modules.DEFINITIONS.dual_processor.secondary_speed)
	if modules.has("wide_correlation"):
		new_multiplier *= float(Modules.DEFINITIONS.wide_correlation.primary_speed if is_primary else Modules.DEFINITIONS.wide_correlation.secondary_speed)
	if String(target.get("type_id")) == "andromeda":
		if modules.has("reference_bus"):
			new_multiplier *= float(Modules.DEFINITIONS.reference_bus.m31_manual_speed)
		if modules.has_method("shutter_active") and modules.shutter_active():
			new_multiplier *= float(Modules.DEFINITIONS.shutter_weave.shutter_speed)
	# New mechanics may combine only inside this bounded range. The old module
	# multiplier remains outside it so existing loadouts retain exact behavior.
	return legacy_speed * clampf(new_multiplier, 0.25, 2.5)


func _dual_processor_secondary():
	var closest = null
	var closest_distance := INF
	for target in _target_children():
		if target == selected_meteor or not _target_is_valid(target):
			continue
		var distance := _target_contact_distance(target, cursor_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = target
	return closest
