extends Node2D

const SimulationInput = preload("res://scripts/simulation_input.gd")
const Clock = preload("res://scripts/simulation_clock.gd")
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

var tick_input := SimulationInput.new()
var tick_segments: Array[Dictionary] = []
var input_origin := 0.0
var input_time := 0.0
var input_held := false
var simulation_holding := false
var display_cursor_position := Vector2.ZERO
var segment_start_fraction := 0.0
var segment_end_fraction := 1.0
var current_time_scale := 1.0
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
var _manual_frame_active := false
var _manual_frame_primary = null
var _tick_cache_active := false
var _tick_targets: Array = []
var _tick_radii: Dictionary = {}
var _tick_extents: Dictionary = {}
var _tick_positions: Dictionary = {}
var _tick_linear := false
var _tick_radius := 0.0
var _tick_line_width := 1.0
var _tick_primary_speed := 1.0
var _tick_secondary_speed := 1.0
var _tick_grace := 0.0
var _tick_target_limit := 1


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
	# Preserve raw motion samples; the fixed tick consumes each time interval once.
	Input.set_use_accumulated_input(false)
	# The game draws its own cursor below. Hiding the native cursor prevents the
	# OS-composited cursor from racing ahead of the rendered game during a stall.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	native_cursor_visible = false
	cursor_position = _screen_to_world(get_viewport().get_mouse_position())
	previous_cursor_position = cursor_position
	cursor_initialized = true
	reset_input_boundary()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func reset() -> void:
	reset_input_boundary()
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

	if survey != null:
		survey.set_scanning(false, cursor_position)
	if hud != null:
		hud.hide_tracking()
	queue_redraw()


func _process(_delta: float) -> void:
	if meteor_layer == null: return
	display_cursor_position = _screen_to_world(get_viewport().get_mouse_position())
	_set_native_cursor_visible(_cursor_is_on_ui())
	if _selection_is_valid():
		var predicted_multiplier: float = selected_meteor.get_predicted_multiplier()
		hud.set_tracking(
			selected_meteor.get_progress(),
			String(selected_meteor.type_id),
			predicted_multiplier,
			maxi(1, _valid_tracked_count()),
			_world_to_screen(display_cursor_position),
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
	var perseid_target_count := get_visible_atmospheric_target_count() if perseid_indicator_visible else 0
	var perseid_visual_changed := (
		perseid_indicator_visible != perseid_indicator_visible_last_frame
		or perseid_target_count != perseid_target_count_last_frame
	)
	var tracking_visual_active: bool = (
		_selection_is_valid()
		or _target_is_valid(hovered_meteor)
		or not tracked_meteors.is_empty()
		or combo_visual_active
		or (_linear_enabled() and survey != null and survey.has_visible_feedback())
		or (modules != null and modules.has("overcharge"))
	)
	if cursor_position != previous_cursor_position or tracking_visual_active or tracking_visual_active_last_frame or perseid_visual_changed:
		queue_redraw()
	tracking_visual_active_last_frame = tracking_visual_active
	perseid_indicator_visible_last_frame = perseid_indicator_visible
	perseid_target_count_last_frame = perseid_target_count
	queue_redraw()

func reset_input_boundary() -> void:
	if not is_inside_tree(): return
	cursor_position = _screen_to_world(get_viewport().get_mouse_position())
	previous_cursor_position = cursor_position
	display_cursor_position = cursor_position
	input_origin = Time.get_ticks_usec() / 1000000.0
	input_time = 0.0
	input_held = false
	simulation_holding = false
	tick_input.reset(cursor_position)
	tick_segments.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion or event is InputEventMouseButton): return
	var point: Vector2 = _screen_to_world(event.position)
	# Releases are recorded even over a Control; a UI press cannot start a drag.
	if event.is_action_released(&"nw_observe"): input_held = false
	elif event.is_action_pressed(&"nw_observe"):
		input_held = not _screen_point_is_on_ui(event.position)
	var timestamp := Time.get_ticks_usec() / 1000000.0 - input_origin
	# Slowdown drops elapsed wall time, not a backlog of delayed mouse gestures.
	if timestamp > input_time + 0.25:
		reset_input_boundary()
		timestamp = 0.0
	tick_input.push(timestamp, point, input_held and not _screen_point_is_on_ui(event.position))

func _screen_point_is_on_ui(point: Vector2) -> bool:
	return get_viewport().gui_get_hovered_control() != null or (hud != null and hud.is_pointer_over_hud(point))

func prepare_tick() -> void:
	input_time += Clock.STEP
	tick_segments = tick_input.consume(input_time)
	if not tick_segments.is_empty():
		previous_cursor_position = tick_segments[0].start
		cursor_position = tick_input.position
	simulation_holding = tick_input.held

func simulate_tick(delta: float) -> void:
	_begin_tick_cache()
	current_time_scale = delta / Clock.STEP
	var consumed := 0.0
	for segment in tick_segments:
		previous_cursor_position = segment.start
		cursor_position = segment.end
		segment_start_fraction = clampf(consumed / Clock.STEP, 0.0, 1.0)
		consumed += float(segment.duration)
		segment_end_fraction = clampf(consumed / Clock.STEP, 0.0, 1.0)
		if segment.held:
			hovered_meteor = null
			if _survey_input_enabled(): _update_survey_interaction(float(segment.duration) * current_time_scale)
			else: _update_manual_tracking(float(segment.duration) * current_time_scale)
		else: _clear_interaction_mode()
	if not tick_input.held:
		_clear_interaction_mode()
		hovered_meteor = null if _cursor_is_on_ui() else _find_target_under_cursor()
	was_holding = tick_input.held
	tick_segments.clear()
	segment_start_fraction = 0.0
	segment_end_fraction = 1.0
	_end_tick_cache()


func _begin_tick_cache() -> void:
	# Motion has finished; completion/rewards resolve after this entire input pass.
	# Keep every raw segment, but derive equipment/research and geometry only once.
	_tick_targets = _target_children()
	_tick_linear = _linear_enabled()
	_tick_radius = _world_px(_module_tracking_radius())
	_tick_line_width = modules.stacked_effect("linear_observation", "line_width") if _tick_linear else 1.0
	_tick_primary_speed = _manual_speed_for_role(true)
	_tick_secondary_speed = _manual_speed_for_role(false)
	_tick_grace = TRACKING_GRACE_SECONDS + progression.extension_effect("tracking_grace", 0.0)
	_tick_target_limit = _manual_target_limit()
	_tick_cache_active = true


func _end_tick_cache() -> void:
	_tick_cache_active = false
	_tick_targets.clear()
	_tick_radii.clear()
	_tick_extents.clear()
	_tick_positions.clear()


func _tracking_radius_for(target) -> float:
	if not _tick_cache_active:
		return target.get_tracking_radius(_world_px(_module_tracking_radius()))
	if not _tick_radii.has(target):
		_tick_radii[target] = target.get_tracking_radius(_tick_radius)
	return _tick_radii[target]


func _tracking_grace() -> float:
	return _tick_grace if _tick_cache_active else TRACKING_GRACE_SECONDS + progression.extension_effect("tracking_grace", 0.0)


func _manual_target_limit() -> int:
	if _tick_cache_active: return _tick_target_limit
	if progression.has_upgrade("multi_target_analysis") or _linear_enabled(): return 100000
	return int(modules.effect("targets")) if modules != null else 1


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
	survey.apply_scan_segment(previous_cursor_position, cursor_position, delta / maxf(current_time_scale, 0.001))


func _clear_interaction_mode() -> void:
	selected_meteor = null
	tracked_meteors.clear()
	tracking_grace_remaining = 0.0
	interaction_mode = InteractionMode.NONE
	pending_blank_distance = 0.0

	if survey != null:
		survey.set_scanning(false, cursor_position)


func _update_manual_tracking(delta: float, keep_primary: bool = false) -> bool:
	tracked_meteors.clear()
	# Retain each buffered segment origin for fast press-and-drag motion.
	if not _selection_is_valid():
		selected_meteor = _find_target_under_cursor()
		if _selection_is_valid():
			tracking_grace_remaining = _tracking_grace()
	if not _selection_is_valid():
		return false

	var primary = selected_meteor
	# Synchronous completion can release selected_meteor during this pass. Keep
	# the primary role stable so same-frame completions cannot shift the
	# remaining correlation modifiers between recipients.
	_manual_frame_active = true
	_manual_frame_primary = primary
	var tracking_radius: float = _tracking_radius_for(primary)
	var current_distance: float = _target_contact_distance(primary, cursor_position)
	if _apply_manual_contact(primary, delta):
		tracking_grace_remaining = _tracking_grace()
		_append_tracked_if_valid(primary)
	elif current_distance <= tracking_radius * TRACKING_BREAK_MULTIPLIER:
		# The soft outer ring pauses progress but keeps the target latched.
		tracking_grace_remaining = _tracking_grace()
	else:
		tracking_grace_remaining -= delta
		if tracking_grace_remaining <= 0.0:
			selected_meteor = null

	if _manual_target_limit() > 1:
		_observe_additional_targets(delta, primary)
		var closest_tracked = _closest_valid_tracked_target()
		if closest_tracked != null and (not keep_primary or not _selection_is_valid()):
			selected_meteor = closest_tracked
	_manual_frame_active = false
	_manual_frame_primary = null
	return true


func _observe_additional_targets(delta: float, primary) -> void:
	var limit := _manual_target_limit()
	for child in _target_children():
		if tracked_meteors.size() >= limit:
			break
		if child == primary or not _target_is_valid(child):
			continue
		if _apply_manual_contact(child, delta):
			_append_tracked_if_valid(child)


func _target_position_at(target, fraction: float) -> Vector2:
	if _tick_cache_active:
		if not _tick_positions.has(target):
			var end: Vector2 = target.global_position
			var start: Vector2 = target.previous_simulation_position if "previous_simulation_position" in target else end
			_tick_positions[target] = Vector4(start.x, start.y, end.x, end.y)
		var points: Vector4 = _tick_positions[target]
		return Vector2(lerpf(points.x, points.z, fraction), lerpf(points.y, points.w, fraction))
	return target.previous_simulation_position.lerp(target.global_position, fraction) if "previous_simulation_position" in target else target.global_position

func _circle_contact_interval(target, radius: float) -> Vector2:
	var start := previous_cursor_position - _target_position_at(target, segment_start_fraction)
	var motion := cursor_position - _target_position_at(target, segment_end_fraction) - start
	var a := motion.length_squared()
	if a < 0.000001: return Vector2(0, 1) if start.length_squared() <= radius * radius else Vector2(-1, -1)
	var b := 2.0 * start.dot(motion)
	var c := start.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0: return Vector2(-1, -1)
	var enter := maxf(0.0, (-b - sqrt(discriminant)) / (2.0 * a))
	var leave := minf(1.0, (-b + sqrt(discriminant)) / (2.0 * a))
	return Vector2(enter, leave) if leave > enter else Vector2(-1, -1)

func _apply_manual_contact(target, delta: float) -> bool:
	if not _target_is_valid(target) or delta <= 0.0: return false
	var radius: float = _tracking_radius_for(target)
	var interval := _linear_contact_interval(target, radius) if _linear_enabled() else _circle_contact_interval(target, radius)
	if interval.x < 0.0 or interval.y <= interval.x: return false
	var fraction := (interval.x + interval.y) * 0.5
	var relative := previous_cursor_position.lerp(cursor_position, fraction) - _target_position_at(target, lerpf(segment_start_fraction, segment_end_fraction, fraction))
	var distance := relative.length()
	if _linear_enabled():
		var extent := _linear_target_extents(target, radius)
		distance = maxf(absf(relative.x) / extent.x, absf(relative.y) / extent.y) * radius
	target.apply_manual_observation(delta * (interval.y - interval.x), distance, radius, _module_manual_speed_for_target(target))
	return true


func motion_multiplier_for(target) -> float:
	# This is a live field query, not an effect attached to a meteor. Leaving the
	# field, releasing observation, changing equipment or pausing removes it.
	if modules == null or progression == null or not progression.galaxy_unlocked() or not modules.has("capture_hold"):
		return 1.0
	if not simulation_holding or not _target_is_valid(target):
		return 1.0
	if is_inside_tree() and (get_tree().paused or _cursor_is_on_ui()):
		return 1.0
	var radius: float = _tracking_radius_for(target)
	if _target_contact_distance(target, cursor_position) > radius:
		return 1.0
	return modules.stacked_effect("capture_hold", "motion_speed")

func _linear_enabled() -> bool:
	if _tick_cache_active: return _tick_linear
	return modules != null and progression != null and progression.galaxy_unlocked() and modules.has("linear_observation")

func _linear_extents(radius: float) -> Vector2:
	if _tick_cache_active: return Vector2(radius * _tick_line_width, radius * 0.45)
	return Vector2(radius * modules.stacked_effect("linear_observation", "line_width"), radius * 0.45)

func _linear_target_extents(target, radius: float) -> Vector2:
	if _tick_cache_active and _tick_extents.has(target): return _tick_extents[target]
	# Solid bodies extend both sides of the field by their visible radius. Do not
	# multiply their size by LINE's width or squeeze it into the thin band height.
	var body := float(target.get_observation_body_radius()) if target.has_method("get_observation_body_radius") else 0.0
	var extent := _linear_extents(maxf(0.0, radius - body)) + Vector2.ONE * body
	if _tick_cache_active: _tick_extents[target] = extent
	return extent

func _linear_contact_interval(target, radius: float) -> Vector2:
	# Clip the cursor segment against the target-centered rectangle. This credits
	# actual time inside the band, including diagonal sweeps and corner misses.
	var extent := _linear_target_extents(target, radius)
	var start := previous_cursor_position - _target_position_at(target, segment_start_fraction)
	var motion := cursor_position - _target_position_at(target, segment_end_fraction) - start
	var enter := 0.0
	var leave := 1.0
	for axis in range(2):
		if absf(motion[axis]) < 0.00001:
			if absf(start[axis]) > extent[axis]:
				return Vector2(-1, -1)
		else:
			var first: float = (-extent[axis] - start[axis]) / motion[axis]
			var last: float = (extent[axis] - start[axis]) / motion[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter > leave:
				return Vector2(-1, -1)
	return Vector2(enter, leave)


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
		var tracking_radius: float = _tracking_radius_for(child)
		# Swept point-to-segment distance prevents fast mouse movement from
		# tunnelling straight through a target between two rendered frames.
		var distance: float = _target_cursor_path_distance(child)
		if distance <= tracking_radius and distance < closest_distance:
			closest = child
			closest_distance = distance
	return closest


func _target_children() -> Array:
	if _tick_cache_active:
		# Sky Sweep can summon a target between two buffered input segments.
		# Reuse the list while membership is stable, but retain immediate discovery.
		var count := meteor_layer.get_child_count() if meteor_layer != null else 0
		for layer in additional_target_layers:
			if layer != null: count += layer.get_child_count()
		if count == _tick_targets.size(): return _tick_targets
	var targets: Array = []
	if meteor_layer != null:
		targets.append_array(meteor_layer.get_children())
	for layer in additional_target_layers:
		if layer != null:
			targets.append_array(layer.get_children())
	if _tick_cache_active: _tick_targets = targets
	return targets


func _target_contact_distance(target, point: Vector2) -> float:
	if _linear_enabled():
		var radius: float = _tracking_radius_for(target)
		var relative: Vector2 = (point - target.global_position).abs() / _linear_target_extents(target, radius)
		return maxf(relative.x, relative.y) * radius
	if target.has_method("get_manual_contact_distance"):
		return float(target.get_manual_contact_distance(point))
	return point.distance_to(target.global_position)


func _target_cursor_path_distance(target) -> float:
	if _linear_enabled():
		var radius: float = _tracking_radius_for(target)
		var interval := _linear_contact_interval(target, radius)
		return minf(radius, _target_contact_distance(target, cursor_position)) if interval.x >= 0.0 else INF
	if target.has_method("get_cursor_path_contact_distance"):
		return float(target.get_cursor_path_contact_distance(previous_cursor_position, cursor_position))
	var start := previous_cursor_position - _target_position_at(target, segment_start_fraction)
	var motion := cursor_position - _target_position_at(target, segment_end_fraction) - start
	var fraction := clampf(-start.dot(motion) / maxf(motion.length_squared(), 0.000001), 0.0, 1.0)
	return (start + motion * fraction).length()


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
	if hovered != null and hovered.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE and not UITheme.is_passive_data_readout(hovered):
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
		_draw_primary_tracking_link()


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
	if modules != null and modules.burst_remaining > 0.0:
		cursor_color = UITheme.ACCENT_TEXT
	var reticle_alpha := 0.17 if tracking else (0.42 if was_holding else 0.26)
	if _linear_enabled():
		_draw_linear_cursor(observation_radius, cursor_color, progress, tracking)
		_draw_overcharge(observation_radius * 0.45)
		_draw_perseid_survey_indicator(observation_radius * 0.45)
		_draw_manual_combo(observation_radius * 0.45)
		return
	_draw_overcharge(observation_radius)
	# An unfilled optical field leaves the target's light and colour intact.
	# The real interaction radius remains visible without a heavy circular bezel.
	draw_arc(display_cursor_position, observation_radius, 0.0, TAU, 64, shadow_color, 2.6 * visual_scale, true)
	draw_arc(display_cursor_position, observation_radius, 0.0, TAU, 64, Color(cursor_color, reticle_alpha), 0.85 * visual_scale, true)
	if tracking and progress > 0.0:
		draw_arc(
			display_cursor_position,
			observation_radius,
			-PI * 0.5,
			-PI * 0.5 + TAU * progress,
			64,
			Color(cursor_color, 0.76),
			1.25 * visual_scale,
			true
		)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var range_tick_start: Vector2 = display_cursor_position + direction * (observation_radius + 2.0 * visual_scale)
		var range_tick_end: Vector2 = display_cursor_position + direction * (observation_radius + 6.0 * visual_scale)
		draw_line(range_tick_start, range_tick_end, shadow_color, 2.6 * visual_scale, true)
		draw_line(range_tick_start, range_tick_end, Color(cursor_color, 0.48), 1.0 * visual_scale, true)
		if not tracking:
			var center_mark_start: Vector2 = display_cursor_position + direction * 4.0 * visual_scale
			var center_mark_end: Vector2 = display_cursor_position + direction * 8.0 * visual_scale
			draw_line(center_mark_start, center_mark_end, shadow_color, 4.0 * visual_scale, true)
			draw_line(center_mark_start, center_mark_end, Color(cursor_color, reticle_alpha), 1.6 * visual_scale, true)
	if not tracking:
		draw_circle(display_cursor_position, 4.0 * visual_scale, shadow_color)
		draw_circle(display_cursor_position, 1.8 * visual_scale, cursor_color)
	_draw_manual_combo(observation_radius)
	_draw_perseid_survey_indicator(observation_radius)


func _draw_linear_cursor(radius: float, ink: Color, progress: float, tracking: bool) -> void:
	# A single authored-by-geometry instrument field replaces the circular field.
	var extent := _linear_extents(radius)
	var scale_factor := _world_px(1.0)
	var bounds := Rect2(display_cursor_position - extent, extent * 2.0)
	draw_rect(bounds, Color(ink, 0.015 if was_holding else 0.008))
	draw_rect(bounds, Color(ink, 0.7 if tracking else 0.42), false, scale_factor, true)
	if tracking:
		draw_line(bounds.position, bounds.position + Vector2(bounds.size.x * progress, 0), Color(ink, 0.95), 2.0 * scale_factor, true)
	if survey != null:
		var feedback: Dictionary = survey.get_visual_feedback()
		if not feedback.is_empty() and feedback.progress > 0.0:
			var start := bounds.position + Vector2(0, bounds.size.y)
			draw_line(start, start + Vector2(bounds.size.x * feedback.progress, 0), feedback.ink, 1.3 * scale_factor, true)
	for side in [-1.0, 1.0]:
		draw_line(display_cursor_position + Vector2(side * 4, 0) * scale_factor, display_cursor_position + Vector2(side * 10, 0) * scale_factor, ink, scale_factor, true)

func _draw_overcharge(radius: float) -> void:
	if modules == null or not modules.has("overcharge"):
		return
	var active: bool = modules.burst_remaining > 0.0
	var ratio: float = modules.burst_remaining / Modules.OVERCHARGE_SECONDS if active else float(modules.charge_count) / Modules.OVERCHARGE_COUNT
	var scale_factor := _world_px(1.0)
	var start := display_cursor_position + Vector2(-24.0 * scale_factor, -radius - 12.0 * scale_factor)
	draw_line(start, start + Vector2(48, 0) * scale_factor, Color(UITheme.ACCENT_DEEP, 0.5), 2.0 * scale_factor)
	draw_line(start, start + Vector2(48.0 * ratio, 0) * scale_factor, UITheme.ACCENT_TEXT if active else UITheme.ACCENT_LINE, 2.0 * scale_factor)


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
	if _linear_enabled():
		var extent := _linear_extents(_software_cursor_radius())
		var left := display_cursor_position + Vector2(-extent.x, extent.y + 5.0 * visual_scale)
		draw_line(left, left + Vector2(2.0 * extent.x * timer_progress, 0), timer_color, visual_scale, true)
	else:
		draw_arc(display_cursor_position, timer_radius, 0.0, TAU, 64, Color(UITheme.SHADOW, 0.44), 2.5 * visual_scale, true)
		draw_arc(
			display_cursor_position,
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
	var label_position := display_cursor_position + Vector2(timer_radius + 7.0 * visual_scale, float(font_size) * 0.35)
	var screen_size := get_viewport().get_visible_rect().size
	if _world_to_screen(label_position).x + _screen_length(label_width) > screen_size.x - 8.0:
		label_position.x = display_cursor_position.x - timer_radius - 7.0 * visual_scale - label_width
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
	var target_count := get_visible_atmospheric_target_count()
	var threshold: int = progression.PERSEID_SURVEY_TARGET_THRESHOLD
	var threshold_reached: bool = progression.is_perseid_survey_active(target_count)
	var visual_scale := _world_px(1.0)
	var pip_gap := 9.0 * visual_scale
	var pip_y := observation_radius + 15.0 * visual_scale
	var start_x := -float(threshold - 1) * pip_gap * 0.5
	var filled_count := mini(target_count, threshold)
	var filled_color: Color = UITheme.ACCENT_TEXT if threshold_reached else UITheme.ACCENT_LINE
	for index in range(threshold):
		var pip_position := display_cursor_position + Vector2(start_x + float(index) * pip_gap, pip_y)
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


func get_visible_atmospheric_target_count(completed_target = null) -> int:
	if meteor_layer == null:
		return 0
	var count := 0
	for candidate in meteor_layer.get_children():
		# Completion marks the emitting target inactive before paying its reward.
		# Use the same screen-space rule for the cursor pips and that final count.
		if (_target_is_valid(candidate) or candidate == completed_target) and candidate is Node2D and get_viewport_rect().has_point(candidate.get_global_transform_with_canvas().origin):
			count += 1
	return count


func _software_cursor_radius() -> float:
	return _world_px(_module_tracking_radius() if progression != null else DEFAULT_TRACKING_RADIUS)


func _draw_primary_tracking_link() -> void:
	# Progress belongs to the cursor alone, including multi-target observation.
	# Keep only the primary latch link when the cursor drifts inside its grace area.
	if selected_meteor.has_method("get_manual_contact_distance"):
		return
	var visual_scale := _world_px(1.0)
	if display_cursor_position.distance_to(selected_meteor.get_display_position()) > 2.0 * visual_scale:
		draw_line(display_cursor_position, selected_meteor.get_display_position(), Color(UITheme.ACCENT_DEEP, 0.45), 1.0 * visual_scale, true)


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
	return progression.get_tracking_radius() * (float(modules.effect("radius")) if modules != null and progression.galaxy_unlocked() else 1.0) * (modules.burst_multiplier("burst_radius") if modules != null and progression.galaxy_unlocked() else 1.0)

func _module_manual_speed() -> float:
	# Compatibility helper retained for existing callers/tests. Conditional module
	# effects require a live target and are evaluated below.
	return progression.get_manual_analysis_speed_multiplier() * (float(modules.effect("speed")) if modules != null and progression.galaxy_unlocked() else 1.0) * (modules.burst_multiplier("burst_speed") if modules != null and progression.galaxy_unlocked() else 1.0)


func _module_manual_speed_for_target(target) -> float:
	var is_primary: bool = target == (_manual_frame_primary if _manual_frame_active else selected_meteor)
	if _tick_cache_active: return _tick_primary_speed if is_primary else _tick_secondary_speed
	return _manual_speed_for_role(is_primary)


func _manual_speed_for_role(is_primary: bool) -> float:
	var legacy_speed := _module_manual_speed()
	if modules == null or progression == null or not progression.galaxy_unlocked():
		return legacy_speed
	var new_multiplier := float(modules.effect("new_speed"))
	if not is_primary:
		legacy_speed *= progression.extension_effect("secondary_speed")
	if modules.has("wide_correlation"):
		new_multiplier *= modules.stacked_effect("wide_correlation", "primary_speed" if is_primary else "secondary_speed")
	# New mechanics may combine only inside this bounded range. The old module
	# multiplier remains outside it so existing loadouts retain exact behavior.
	return legacy_speed * clampf(new_multiplier, 0.25, 2.5)
