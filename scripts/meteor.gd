extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")

signal observed(meteor, reward, multiplier, was_manual, quality_grade)
signal expired(meteor, was_major)
signal fragment_requested(origin, velocity, parent_type, parent_is_echo, parent_is_leonid, parent_is_perseid)

static var SHARED_ADDITIVE_MATERIAL: CanvasItemMaterial

var type_id: String = "common"
var display_name: String = "COMMON METEOR"
var velocity := Vector2.ZERO
var visible_lifetime: float = 4.0
var base_value: float = 10.0
var required_track_time: float = 1.0
var body_radius: float = 7.0
var primary_color := Color.WHITE
var glow_color := Color("78bfff")
var max_trail_points: int = 28
var entry_position := Vector2.ZERO
var burnout_position := Vector2.ZERO
var initial_velocity := Vector2.ZERO
var burn_terminal_ratio: float = 0.25
var burn_fade_start: float = 0.68
var burn_style: String = "ember"
var burn_wobble: float = 0.0
var split_progress: float = 0.58
var burnout_linger: float = 0.20

var age: float = 0.0
var observation_progress: float = 0.0
var precision_focus: float = 0.0
var last_quality: float = 0.0
var last_manual_frame: int = -100
var base_automatic_rate: float = 0.0
var dish_assist_rate: float = 0.0
var lane_assist_rate: float = 0.0
var prediction_enabled: bool = false
var wide_field_enabled: bool = false
var precision_enabled: bool = false
var perfect_enabled: bool = false
var analysis_speed_multiplier: float = 1.0
var spectral_calibrated: bool = false
var spectral_capstone_enabled: bool = false
var manual_touched: bool = false
var manual_tracking_time: float = 0.0
var quality_integral: float = 0.0
var interruption_count: int = 0
var alive: bool = true
var observed_successfully: bool = false
var split_done: bool = false
var linger_time: float = 0.0
var linger_duration: float = 0.20
var trail_points: Array[Vector2] = []
var trail_draw_points := PackedVector2Array()
var trail_glow_colors := PackedColorArray()
var trail_core_colors := PackedColorArray()
var prediction_draw_points := PackedVector2Array()
var travel_direction := Vector2.ZERO
var trail_sample_accumulator: float = 0.0
var wobble_phase: float = 0.0
var rng := RandomNumberGenerator.new()
var observation_view: Camera2D
var observation_visual_scale: float = 1.0


func configure(spec: Dictionary, meteor_type: String, start_position: Vector2, move_velocity: Vector2, lifetime_scale: float, features: Dictionary, planned_burnout := Vector2.INF, view: Camera2D = null) -> void:
	type_id = meteor_type
	display_name = String(spec.name)
	position = start_position
	entry_position = start_position
	initial_velocity = move_velocity
	velocity = move_velocity
	travel_direction = velocity.normalized()
	visible_lifetime = float(spec.lifetime) * lifetime_scale
	base_value = float(spec.value)
	required_track_time = float(spec.track_time)
	body_radius = float(spec.radius)
	primary_color = spec.color
	glow_color = spec.glow
	max_trail_points = int(float(spec.trail) * (1.22 if lifetime_scale > 1.01 else 1.0))
	burn_terminal_ratio = clampf(float(spec.get("burn_terminal_ratio", 1.0)), 0.0, 1.0)
	burn_fade_start = float(spec.get("burn_fade_start", 0.72))
	burn_style = String(spec.get("burn_style", "ember"))
	burn_wobble = float(spec.get("burn_wobble", 0.0))
	split_progress = float(spec.get("split_progress", 0.58 if meteor_type == "fragment" else 0.57))
	burnout_linger = float(spec.get("burnout_linger", 0.20))
	if planned_burnout == Vector2.INF:
		burnout_position = start_position + travel_direction * burn_distance_for(
			move_velocity.length(), visible_lifetime, burn_terminal_ratio
		)
	else:
		burnout_position = Vector2(planned_burnout)
	var planned_direction := (burnout_position - entry_position).normalized()
	if not planned_direction.is_zero_approx():
		travel_direction = planned_direction
	prediction_enabled = bool(features.get("prediction", false))
	wide_field_enabled = bool(features.get("wide_field", false))
	precision_enabled = bool(features.get("precision", false))
	perfect_enabled = bool(features.get("perfect", false))
	base_automatic_rate = float(features.get("automation", 0.0))
	analysis_speed_multiplier = maxf(0.1, float(features.get("analysis_speed", 1.0)))
	spectral_calibrated = bool(features.get("spectral_calibrated", false))
	spectral_capstone_enabled = bool(features.get("spectral_capstone", false))
	observation_view = view
	observation_visual_scale = _current_visual_scale()
	rng.seed = int(start_position.x * 193.0 + start_position.y * 877.0 + velocity.length() * 31.0) & 0x7fffffff
	wobble_phase = rng.randf_range(0.0, TAU)
	trail_points.append(start_position)
	_rebuild_prediction_draw_points()


static func burn_distance_for(initial_speed: float, lifetime: float, terminal_ratio: float) -> float:
	var ratio := clampf(terminal_ratio, 0.0, 1.0)
	return initial_speed * lifetime * (1.0 + ratio) * 0.5


static func burn_curve(progress: float, terminal_ratio: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var ratio := clampf(terminal_ratio, 0.0, 1.0)
	return (p - (1.0 - ratio) * p * p * 0.5) / ((1.0 + ratio) * 0.5)


static func burn_speed_ratio(progress: float, terminal_ratio: float) -> float:
	var ratio := clampf(terminal_ratio, 0.0, 1.0)
	return 1.0 - (1.0 - ratio) * clampf(progress, 0.0, 1.0)


func _ready() -> void:
	# Every meteor uses the same additive state. A material per spawn forced extra
	# renderer state changes and made shower/fragment bursts compile and bind many
	# identical resources on the main thread.
	if SHARED_ADDITIVE_MATERIAL == null:
		SHARED_ADDITIVE_MATERIAL = CanvasItemMaterial.new()
		SHARED_ADDITIVE_MATERIAL.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = SHARED_ADDITIVE_MATERIAL
	queue_redraw()


func _rebuild_prediction_draw_points() -> void:
	prediction_draw_points.clear()
	for index in range(7):
		var distance := (body_radius + 28.0 + index * 24.0) * observation_visual_scale
		prediction_draw_points.append(travel_direction * distance)
		prediction_draw_points.append(travel_direction * (distance + 10.0 * observation_visual_scale))


func _process(delta: float) -> void:
	_sync_visual_scale()
	if not alive:
		linger_time -= delta
		queue_redraw()
		if linger_time <= 0.0:
			queue_free()
		return

	age += delta
	_update_burn_motion(delta)

	trail_sample_accumulator += delta
	if trail_sample_accumulator >= 0.024:
		trail_sample_accumulator = 0.0
		trail_points.push_front(global_position)
		if trail_points.size() > max_trail_points:
			trail_points.pop_back()

	var auto_rate := get_automatic_rate()
	if auto_rate > 0.0:
		observation_progress += auto_rate * delta
		last_quality = maxf(last_quality * 0.96, 0.38)

	if Engine.get_process_frames() - last_manual_frame > 1 and auto_rate <= 0.0:
		observation_progress = maxf(0.0, observation_progress - delta * 0.055)

	if not split_done:
		if type_id == "fragment" and get_burn_progress() >= split_progress:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))
		elif type_id == "major" and get_burn_progress() >= split_progress:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))

	if observation_progress >= 1.0:
		_finish_observation(auto_rate)
	elif age >= visible_lifetime:
		alive = false
		linger_duration = burnout_linger
		linger_time = linger_duration
		expired.emit(self, type_id == "major")

	queue_redraw()


func _update_burn_motion(delta: float) -> void:
	var previous_position := position
	var progress := get_burn_progress()
	var path_position := entry_position.lerp(
		burnout_position,
		burn_curve(progress, burn_terminal_ratio)
	)
	var path_direction := (burnout_position - entry_position).normalized()
	if burn_wobble > 0.0 and not path_direction.is_zero_approx():
		var instability := smoothstep(0.12, split_progress, progress)
		var endpoint_taper := sin(PI * progress)
		var wobble := sin(age * 8.0 + wobble_phase) * burn_wobble * instability * endpoint_taper
		path_position += Vector2(-path_direction.y, path_direction.x) * wobble
	position = path_position
	if delta > 0.000001:
		velocity = (position - previous_position) / delta
		if not velocity.is_zero_approx():
			travel_direction = velocity.normalized()


func apply_manual_observation(
	delta: float,
	cursor_distance: float,
	tracking_radius: float,
	manual_speed_multiplier: float = 1.0
) -> void:
	if not alive:
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
	var tracking_speed := lerpf(0.72, 1.42, quality)
	tracking_speed *= (
		analysis_speed_multiplier
		* get_spectral_speed_multiplier()
		* maxf(1.0, manual_speed_multiplier)
	)
	observation_progress += delta * tracking_speed / required_track_time
	precision_focus += delta * quality
	queue_redraw()


func set_features(features: Dictionary) -> void:
	prediction_enabled = bool(features.get("prediction", prediction_enabled))
	wide_field_enabled = bool(features.get("wide_field", wide_field_enabled))
	precision_enabled = bool(features.get("precision", precision_enabled))
	perfect_enabled = bool(features.get("perfect", perfect_enabled))
	base_automatic_rate = float(features.get("automation", base_automatic_rate))
	analysis_speed_multiplier = maxf(0.1, float(features.get("analysis_speed", analysis_speed_multiplier)))
	spectral_calibrated = bool(features.get("spectral_calibrated", spectral_calibrated))
	spectral_capstone_enabled = bool(features.get("spectral_capstone", spectral_capstone_enabled))


func get_spectral_speed_multiplier() -> float:
	if not spectral_calibrated:
		return 1.0
	return 1.45 if spectral_capstone_enabled else 1.25


func get_spectral_value_multiplier() -> float:
	if not spectral_calibrated:
		return 1.0
	return 1.35 if spectral_capstone_enabled else 1.15


func set_dish_assist_rate(value: float) -> void:
	dish_assist_rate = value


func set_lane_assist_rate(value: float) -> void:
	lane_assist_rate = value


func get_automatic_rate() -> float:
	return base_automatic_rate + dish_assist_rate + lane_assist_rate


func has_dish_assist() -> bool:
	return dish_assist_rate > 0.0


func has_non_dish_lane_partner() -> bool:
	var manual_is_live := manual_touched and Engine.get_process_frames() - last_manual_frame <= 1
	return base_automatic_rate > 0.0 or manual_is_live


func get_assist_rate(duration_multiplier: float) -> float:
	return 1.0 / maxf(required_track_time * duration_multiplier, 0.001)


func can_be_tracked() -> bool:
	return alive


func get_tracking_radius(base_radius: float) -> float:
	var size_bonus := clampf((body_radius - 7.0) * 0.52, 0.0, 18.0)
	return base_radius + size_bonus * _interaction_scale()


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_burn_progress() -> float:
	return clampf(age / maxf(visible_lifetime, 0.001), 0.0, 1.0)


func get_burn_visibility() -> float:
	var progress := get_burn_progress()
	var ignition := lerpf(0.82, 1.0, smoothstep(0.0, 0.22, progress))
	var fade := smoothstep(burn_fade_start, 1.0, progress)
	var brightness := ignition * lerpf(1.0, 0.10, fade)
	match burn_style:
		"flare":
			var flicker_amount := 0.11 * smoothstep(0.28, 0.82, progress)
			brightness *= 1.0 + sin(age * 14.0 + wobble_phase) * flicker_amount
			var flare_distance := (progress - 0.86) / 0.055
			brightness += 0.65 * exp(-flare_distance * flare_distance)
		"split":
			var instability := smoothstep(0.25, split_progress, progress)
			brightness *= 1.0 + sin(age * 18.0 + wobble_phase) * 0.10 * instability
		"spark":
			brightness *= 1.0 + sin(age * 20.0 + wobble_phase) * 0.07
		"major":
			brightness *= 1.0 + sin(age * 6.0 + wobble_phase) * 0.04
		"satellite":
			brightness *= 0.78 + 0.22 * smoothstep(-0.2, 0.8, sin(age * 4.5 + wobble_phase))
		"variable":
			brightness *= 0.72 + 0.38 * (0.5 + 0.5 * sin(age * 2.7 + wobble_phase))
		"comet":
			brightness *= 1.0 + 0.08 * sin(age * 5.0 + wobble_phase)
		"binary":
			brightness *= 0.86 + 0.14 * (0.5 + 0.5 * sin(age * 3.4 + wobble_phase))
		"galaxy":
			brightness *= 0.90 + 0.10 * sin(age * 1.7 + wobble_phase)
	if progress <= burn_fade_start:
		brightness = maxf(0.78, brightness)
	return maxf(0.10, brightness)


func get_burn_tail_scale() -> float:
	var tail_fade_start := maxf(0.0, burn_fade_start - 0.10)
	return lerpf(1.0, 0.16, smoothstep(tail_fade_start, 1.0, get_burn_progress()))


func get_planned_position(progress: float) -> Vector2:
	return entry_position.lerp(
		burnout_position,
		burn_curve(progress, burn_terminal_ratio)
	)


func get_quality() -> float:
	return last_quality


func get_visual_color() -> Color:
	return glow_color


func get_predicted_multiplier() -> float:
	var multiplier := get_spectral_value_multiplier()
	if precision_enabled and manual_touched:
		multiplier *= 1.0 + minf(2.0, precision_focus * 0.58)
		if perfect_enabled:
			match get_quality_grade():
				"PERFECT": multiplier *= 1.55
				"EXCELLENT": multiplier *= 1.25
	return multiplier


func get_quality_grade() -> String:
	if not manual_touched or manual_tracking_time <= 0.05:
		return "AUTOMATIC"
	var average_quality := quality_integral / maxf(manual_tracking_time, 0.001)
	if average_quality >= 0.82 and interruption_count <= 1:
		return "PERFECT"
	if average_quality >= 0.62 and interruption_count <= 3:
		return "EXCELLENT"
	return "GOOD"


func is_major() -> bool:
	return type_id == "major"


func _finish_observation(auto_rate: float) -> void:
	if not alive:
		return
	if type_id == "fragment" and not split_done:
		split_done = true
		fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))
	alive = false
	observed_successfully = true
	linger_duration = 0.62 if type_id != "major" else 1.1
	linger_time = linger_duration
	var was_manual := manual_touched
	var multiplier := get_predicted_multiplier()
	if not was_manual and auto_rate > 0.0:
		multiplier = 0.68
	var reward := maxf(1.0, round(base_value * multiplier))
	observed.emit(self, reward, multiplier, was_manual, get_quality_grade())
	queue_redraw()


func _draw() -> void:
	var visual_scale := observation_visual_scale
	var burn_visibility := get_burn_visibility()
	var burn_tail_scale := get_burn_tail_scale()
	if trail_points.size() > 1:
		trail_draw_points.clear()
		trail_glow_colors.clear()
		trail_core_colors.clear()
		var linger_alpha := 1.0 if alive else clampf(linger_time / maxf(linger_duration, 0.001), 0.0, 1.0)
		if not alive and not observed_successfully:
			linger_alpha *= 0.12
		var trail_visibility := burn_visibility * burn_tail_scale * linger_alpha
		for index in range(trail_points.size()):
			var t := float(index) / float(maxi(1, trail_points.size() - 1))
			var alpha := pow(1.0 - t, 1.35) * trail_visibility
			trail_draw_points.append(trail_points[index] - global_position)
			trail_glow_colors.append(Color(glow_color, alpha * 0.30))
			trail_core_colors.append(Color(primary_color, alpha * 0.72))
		# Two batched Canvas commands replace two draw_line calls per segment.
		draw_polyline_colors(trail_draw_points, trail_glow_colors, maxf(0.5, body_radius * 0.72 * burn_tail_scale) * visual_scale, true)
		draw_polyline_colors(trail_draw_points, trail_core_colors, maxf(0.32, body_radius * 0.24 * burn_tail_scale) * visual_scale, true)

	if prediction_enabled and alive:
		draw_multiline(prediction_draw_points, Color(UITheme.ACCENT_LINE, 0.30 * minf(1.0, burn_visibility)), 1.0 * visual_scale, true)

	var visibility := burn_visibility
	if not alive:
		visibility = clampf(linger_time / maxf(linger_duration, 0.001), 0.0, 1.0)
		if not observed_successfully:
			visibility *= 0.12
	var success_bloom := 1.0
	if observed_successfully:
		success_bloom = 1.0 + (1.0 - visibility) * 3.0
	var pulse_amount := 0.06
	if burn_style == "split":
		pulse_amount += 0.08 * smoothstep(0.25, split_progress, get_burn_progress())
	elif burn_style == "snap":
		pulse_amount = 0.035
	var pulse := 1.0 + sin(age * 13.0 + wobble_phase) * pulse_amount
	var r := body_radius * visual_scale * pulse * success_bloom * _head_scale()
	if type_id == "galaxy":
		var galaxy_axis := Vector2(1.0, 0.34).rotated(travel_direction.angle()).normalized()
		draw_line(-galaxy_axis * r * 2.7, galaxy_axis * r * 2.7, Color(glow_color, 0.12 * visibility), r * 1.4, true)
		draw_line(-galaxy_axis * r * 2.2, galaxy_axis * r * 2.2, Color(primary_color, 0.72 * visibility), maxf(1.0 * visual_scale, r * 0.34), true)
		draw_circle(Vector2.ZERO, r * 0.48, Color(1.0, 1.0, 1.0, 0.82 * visibility))
	elif type_id == "binary_star":
		var binary_axis := Vector2(-travel_direction.y, travel_direction.x)
		var separation := r * (0.58 + 0.16 * sin(age * 2.6 + wobble_phase))
		for side in [-1.0, 1.0]:
			var component: Vector2 = binary_axis * separation * float(side)
			draw_circle(component, r * 2.3, Color(glow_color, clampf(0.08 * visibility, 0.0, 1.0)))
			draw_circle(component, r * 0.62, Color(primary_color, clampf(visibility, 0.0, 1.0)))
			draw_circle(component - travel_direction * r * 0.14, r * 0.24, Color(1.0, 1.0, 1.0, clampf(visibility, 0.0, 1.0)))
	else:
		draw_circle(Vector2.ZERO, r * 2.55, Color(glow_color, clampf(0.045 * visibility, 0.0, 1.0)))
		draw_circle(Vector2.ZERO, r * 1.55, Color(glow_color, clampf(0.12 * visibility, 0.0, 1.0)))
		draw_circle(Vector2.ZERO, r, Color(primary_color, clampf(visibility, 0.0, 1.0)))
		draw_circle(-travel_direction * r * 0.20, r * 0.34, Color(1.0, 1.0, 1.0, clampf(0.90 * visibility, 0.0, 1.0)))
		if burn_style == "split":
			var split_visibility := smoothstep(0.18, split_progress, get_burn_progress()) * visibility
			var split_axis := Vector2(-travel_direction.y, travel_direction.x)
			for side in [-1.0, 1.0]:
				var spark_center := -travel_direction * r * 0.85 + split_axis * r * 0.58 * float(side)
				draw_circle(spark_center, r * 0.19, Color(primary_color, clampf(split_visibility * 0.78, 0.0, 1.0)))

	if type_id == "fireball" or type_id == "major":
		var flame_dir := -travel_direction
		for index in range(3 if type_id == "fireball" else 6):
			var side := Vector2(-flame_dir.y, flame_dir.x) * sin(age * 8.0 + index * 1.7) * r * 0.24
			var center := flame_dir * r * (1.15 + index * 0.55) + side
			draw_circle(center, r * maxf(0.12, 0.30 - index * 0.028), Color(glow_color, clampf((0.24 - index * 0.024) * visibility, 0.0, 1.0)))

	var scan_rate := get_automatic_rate()
	if scan_rate > 0.0 and alive:
		var scan_radius := (body_radius + 12.0 + sin(age * 5.0) * 2.0) * visual_scale
		var start_angle := age * 2.5
		_draw_dashed_arc(scan_radius, start_angle, PI * 1.25, 10, Color(UITheme.INK_LOW, 0.58 * minf(1.0, burn_visibility)), 1.2 * visual_scale)
		_draw_dashed_arc(scan_radius + 5.0 * visual_scale, -start_angle * 0.7, PI * 0.55, 5, Color(UITheme.ACCENT_DEEP, 0.52 * minf(1.0, burn_visibility)), 0.9 * visual_scale)


func _head_scale() -> float:
	match type_id:
		"fast":
			return 0.62
		"fragment_piece":
			return 0.68
		"fragment":
			return 0.80
		"fireball":
			return 0.50
		"major":
			return 0.43
		"satellite", "variable_star", "comet", "binary_star", "galaxy":
			return 0.84
		_:
			return 0.72


func _draw_dashed_arc(radius: float, start_angle: float, arc_length: float, dash_count: int, color: Color, width: float) -> void:
	var cell := arc_length / float(dash_count)
	for index in range(dash_count):
		var dash_start := start_angle + cell * float(index)
		draw_arc(Vector2.ZERO, radius, dash_start, dash_start + cell * 0.46, 5, color, width, true)


func _current_visual_scale() -> float:
	if observation_view != null:
		if observation_view.has_method("meteor_visual_scale"):
			return observation_view.meteor_visual_scale()
		return observation_view.screen_length_to_world(1.0)
	return 1.0


func _interaction_scale() -> float:
	if observation_view != null:
		return observation_view.screen_length_to_world(1.0)
	return 1.0


func _sync_visual_scale() -> void:
	var next_scale := _current_visual_scale()
	if is_equal_approx(next_scale, observation_visual_scale):
		return
	observation_visual_scale = next_scale
	_rebuild_prediction_draw_points()
	queue_redraw()
