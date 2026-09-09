extends Node2D

const UITheme = preload("res://scripts/ui_theme.gd")

# The trail leaves the head at the head's own width and loses that extra width
# fast, so the long train keeps the narrow size it was tuned to. A low exponent
# here turns rare targets back into broad bars.
const TRAIL_SHOULDER_EXPONENT := 7.5
# Triangle arrays are not antialiased, so a band under ~2 px misses pixel
# centres and rasterises as dashes - which is what broke up the common, fast
# and fragment_piece tails. Alpha is already near zero wherever this floor
# binds, so holding the geometry wide costs nothing visually.
const MIN_RIBBON_HALF_WIDTH := 1.15

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
var manual_contribution: float = 0.0
var automatic_contribution: float = 0.0
var alive: bool = true
var observed_successfully: bool = false
var split_done: bool = false
var linger_time: float = 0.0
var linger_duration: float = 0.20
var trail_points: Array[Vector2] = []
var observation_trail_points: Array[Vector2] = []
var trail_sample_times: Array[float] = []
var trail_glow_ribbon := PackedVector2Array()
var trail_glow_ribbon_colors := PackedColorArray()
var trail_core_ribbon := PackedVector2Array()
var trail_core_ribbon_colors := PackedColorArray()
var trail_strip_indices := PackedInt32Array()
var trail_strip_point_count: int = -1
var trail_station_weights := PackedFloat64Array()
var trail_weight_point_count: int = -1
var debris_draw_points := PackedVector2Array()
var travel_direction := Vector2.ZERO
var trail_sample_accumulator: float = 0.0
var wobble_phase: float = 0.0
var rng := RandomNumberGenerator.new()
var observation_view: Camera2D
var observation_visual_scale: float = 1.0
var lens_curve_enabled := false
var lens_control_position := Vector2.ZERO
var lens_center := Vector2.ZERO
var lens_radius := 0.0
var lens_activity_rect := Rect2()
var lensed_active := false


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
	manual_contribution = 0.0
	automatic_contribution = 0.0
	trail_points.clear()
	observation_trail_points.clear()
	trail_sample_times.clear()
	trail_points.append(start_position)
	observation_trail_points.append(start_position)
	trail_sample_times.append(0.0)


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
		observation_trail_points.push_front(global_position)
		trail_sample_times.push_front(age)
		if trail_points.size() > max_trail_points:
			trail_points.pop_back()
		# The interaction history covers one second regardless of the original
		# visual ribbon's type-specific point limit.
		while not trail_sample_times.is_empty() and age - trail_sample_times.back() > 1.0:
			observation_trail_points.pop_back()
			trail_sample_times.pop_back()

	var auto_rate := get_automatic_rate()
	if auto_rate > 0.0:
		var automatic_work := auto_rate * delta
		automatic_contribution += minf(automatic_work, maxf(0.0, 1.0 - observation_progress))
		observation_progress += automatic_work
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


func _wobble_frequency() -> float:
	match type_id:
		"fragment", "fragment_piece":
			# Coming apart: fast and small. The amplitude in the spec carries how
			# far it strays; this carries how unsettled it looks getting there.
			return 22.0
		_:
			return 8.0


func _update_burn_motion(delta: float) -> void:
	var previous_position := position
	var progress := get_burn_progress()
	var path_position := get_planned_position(progress)
	var path_direction := (burnout_position - entry_position).normalized()
	if burn_wobble > 0.0 and not path_direction.is_zero_approx():
		var instability := smoothstep(0.12, split_progress, progress)
		var endpoint_taper := sin(PI * progress)
		# Two incommensurate sines instead of one. A single slow wave puts about
		# one full period inside the visible trail, and a smooth curve on a
		# narrow tail reads as something swimming rather than something coming
		# apart.
		var frequency := _wobble_frequency()
		var oscillation := (
			0.62 * sin(age * frequency + wobble_phase)
			+ 0.38 * sin(age * frequency * 1.71 + wobble_phase * 1.7)
		)
		var wobble := oscillation * burn_wobble * instability * endpoint_taper
		path_position += Vector2(-path_direction.y, path_direction.x) * wobble
	position = path_position
	lensed_active = lens_curve_enabled and global_position.distance_to(lens_center) <= lens_radius
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
		* maxf(0.01, manual_speed_multiplier)
	)
	var manual_work := delta * tracking_speed / required_track_time
	manual_contribution += minf(manual_work, maxf(0.0, 1.0 - observation_progress))
	observation_progress += manual_work
	precision_focus += delta * quality
	queue_redraw()


func set_features(features: Dictionary) -> void:
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


func allows_automatic_assist() -> bool:
	return true


func set_lens_curve(control_position: Vector2, zone_center: Vector2, zone_radius: float, activity_rect: Rect2) -> void:
	lens_curve_enabled = true
	lens_control_position = control_position
	lens_center = zone_center
	lens_radius = maxf(0.0, zone_radius)
	lens_activity_rect = activity_rect


func is_lensed() -> bool:
	return lensed_active


func get_lens_curve_bounds() -> Rect2:
	var first := get_planned_position(0.0)
	var bounds := Rect2(first, Vector2.ZERO)
	for index in range(1, 33):
		bounds = bounds.expand(get_planned_position(float(index) / 32.0))
	return bounds


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


func get_manual_contribution() -> float:
	return clampf(manual_contribution / maxf(1.0, manual_contribution + automatic_contribution), 0.0, 1.0)


func get_automatic_contribution() -> float:
	return clampf(automatic_contribution / maxf(1.0, manual_contribution + automatic_contribution), 0.0, 1.0)


func get_recent_observation_trail() -> PackedVector2Array:
	var recent := PackedVector2Array()
	for index in range(mini(observation_trail_points.size(), trail_sample_times.size())):
		if age - trail_sample_times[index] <= 1.0:
			recent.append(observation_trail_points[index])
	return recent


func is_natural_observation() -> bool:
	if type_id in ["fragment", "fragment_piece"]:
		return false
	for generated_meta in ["gemini_echo", "leonid_storm", "perseid_outburst", "polar_summoned", "afterglow_archive", "shutter_ineligible"]:
		if has_meta(generated_meta):
			return false
	return true


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
	var ratio := burn_curve(progress, burn_terminal_ratio)
	if not lens_curve_enabled:
		return entry_position.lerp(burnout_position, ratio)
	var inverse := 1.0 - ratio
	return (
		entry_position * inverse * inverse
		+ lens_control_position * 2.0 * inverse * ratio
		+ burnout_position * ratio * ratio
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
		var linger_alpha := 1.0 if alive else clampf(linger_time / maxf(linger_duration, 0.001), 0.0, 1.0)
		if not alive and not observed_successfully:
			linger_alpha *= 0.12
		var trail_visibility := burn_visibility * burn_tail_scale * linger_alpha
		_draw_tapered_trail(trail_visibility, burn_tail_scale, visual_scale)
		_draw_exposure_filament(trail_visibility, visual_scale)

	var visibility := burn_visibility
	if not alive:
		visibility = clampf(linger_time / maxf(linger_duration, 0.001), 0.0, 1.0)
		if not observed_successfully:
			visibility *= 0.12
	var success_bloom := 1.0
	if observed_successfully:
		# The external success burst already carries the completion beat. Keep the
		# meteor itself directional instead of inflating it into a circular flash.
		success_bloom = 1.0 + (1.0 - visibility) * (1.15 if type_id == "major" else 0.72)
	var pulse_amount := 0.06
	if burn_style == "split":
		pulse_amount += 0.08 * smoothstep(0.25, split_progress, get_burn_progress())
	elif burn_style == "snap":
		pulse_amount = 0.035
	var pulse := 1.0 + sin(age * 13.0 + wobble_phase) * pulse_amount
	var r := body_radius * visual_scale * pulse * success_bloom * _head_scale()
	_draw_type_silhouette(r, visibility, visual_scale)

	var scan_rate := get_automatic_rate()
	if scan_rate > 0.0 and alive:
		var scan_radius := (body_radius + 12.0 + sin(age * 5.0) * 2.0) * visual_scale
		var start_angle := age * 2.5
		_draw_dashed_arc(scan_radius, start_angle, PI * 1.25, 10, Color(UITheme.INK_LOW, 0.58 * minf(1.0, burn_visibility)), 1.2 * visual_scale)
		_draw_dashed_arc(scan_radius + 5.0 * visual_scale, -start_angle * 0.7, PI * 0.55, 5, Color(UITheme.ACCENT_DEEP, 0.52 * minf(1.0, burn_visibility)), 0.9 * visual_scale)


func _draw_tapered_trail(visibility: float, tail_scale: float, visual_scale: float) -> void:
	# Two ribbons, each emitted as an explicit triangle strip. `draw_polygon`
	# triangulates an arbitrary simple polygon, and a ribbon this thin with
	# turbulence on its centre line self-intersects often enough that whole
	# triangles were dropped: the common, fast and fragment_piece trails came
	# out dashed. An index list has nothing to triangulate, so every segment
	# survives however narrow it gets.
	var point_count := mini(
		trail_points.size(),
		maxi(2, ceili(float(trail_points.size()) * maxf(0.16, tail_scale)))
	)
	if point_count < 2:
		return
	# Station 0 is the meteor itself, not the newest stored sample. Samples lag
	# the head by up to one sampling interval, so anchoring the ribbon at
	# trail_points[0] left the widest part of the trail standing off behind the
	# silhouette with a wedge of unlit sky between them.
	var stations := PackedVector2Array()
	stations.append(Vector2.ZERO)
	for index in range(point_count):
		var offset := trail_points[index] - global_position
		if index == 0 and offset.length_squared() < 0.25:
			continue
		stations.append(offset)
	var station_count := stations.size()
	if station_count < 2:
		return
	var widths := _trail_half_widths() * visual_scale
	var shoulder := _trail_shoulder_widths(visual_scale)
	_ensure_trail_station_weights(station_count)
	var turbulence_profile := _trail_turbulence_profile()
	var turbulence_phase := wobble_phase + age * turbulence_profile.y
	trail_glow_ribbon.clear()
	trail_glow_ribbon_colors.clear()
	trail_core_ribbon.clear()
	trail_core_ribbon_colors.clear()

	# Three vertices per station - edge, centre line, edge - so each ribbon falls
	# off across its width. A ribbon of one flat colour ends on two hard parallel
	# edges, and on a saturated glow colour over a cool sky that slab reads as a
	# dark chevron behind the head rather than as light.
	var core_floor := MIN_RIBBON_HALF_WIDTH * 0.7
	for index in range(station_count):
		var weight_base := index * 5
		var t := trail_station_weights[weight_base]
		var taper := trail_station_weights[weight_base + 1]
		var flare := trail_station_weights[weight_base + 2]
		var glow_width := widths.x * taper + shoulder.x * flare
		var core_width := widths.y * taper + shoulder.y * flare
		var normal := _station_normal(stations, index)
		var local_point := stations[index]
		var alpha := trail_station_weights[weight_base + 3] * visibility
		var turbulence := sin(turbulence_phase - t * 8.7) * turbulence_profile.x * trail_station_weights[weight_base + 4]
		var glow_centre := Color(glow_color, alpha * 0.34)
		var glow_edge := Color(glow_color, 0.0)
		var core_centre := Color(primary_color, alpha * 0.86)
		var core_edge := Color(primary_color, alpha * 0.10)
		trail_glow_ribbon.append(local_point + normal * maxf(MIN_RIBBON_HALF_WIDTH, glow_width * (1.0 + turbulence)))
		trail_glow_ribbon.append(local_point)
		trail_glow_ribbon.append(local_point - normal * maxf(MIN_RIBBON_HALF_WIDTH, glow_width * (1.0 - turbulence * 0.68)))
		trail_glow_ribbon_colors.append(glow_edge)
		trail_glow_ribbon_colors.append(glow_centre)
		trail_glow_ribbon_colors.append(glow_edge)
		trail_core_ribbon.append(local_point + normal * maxf(core_floor, core_width * (1.0 + turbulence * 0.38)))
		trail_core_ribbon.append(local_point)
		trail_core_ribbon.append(local_point - normal * maxf(core_floor, core_width * (1.0 - turbulence * 0.26)))
		trail_core_ribbon_colors.append(core_edge)
		trail_core_ribbon_colors.append(core_centre)
		trail_core_ribbon_colors.append(core_edge)

	var indices := _ribbon_strip_indices(station_count)
	var canvas := get_canvas_item()
	RenderingServer.canvas_item_add_triangle_array(
		canvas, indices, trail_glow_ribbon, trail_glow_ribbon_colors
	)
	RenderingServer.canvas_item_add_triangle_array(
		canvas, indices, trail_core_ribbon, trail_core_ribbon_colors
	)


func _draw_exposure_filament(visibility: float, visual_scale: float) -> void:
	# Subpixel triangle ribbons alone lose their luminous centre at the shipped
	# viewport. One antialiased filament follows their actual sampled centreline;
	# it cannot extend the lifetime, straighten a lens curve, or invent motion.
	if type_id in ["satellite", "variable_star", "binary_star", "galaxy"]:
		return
	var count := trail_core_ribbon.size() / 3
	if count < 2 or visibility <= 0.0:
		return
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var light := primary_color.lerp(Color.WHITE, 0.34)
	for index in range(count):
		points.append(trail_core_ribbon[index * 3 + 1])
		var t := float(index) / float(count - 1)
		colors.append(Color(light, pow(1.0 - t, 1.6) * visibility * 0.52))
	draw_polyline_colors(points, colors, 0.7 * visual_scale, true)


func _ensure_trail_station_weights(point_count: int) -> void:
	if trail_weight_point_count == point_count:
		return
	# Only count/index-dependent terms are cached. Float64 keeps the original
	# GDScript arithmetic precision; age, type, geometry and visibility stay live.
	# Five consecutive values per station: t, taper, shoulder, alpha, turbulence.
	trail_station_weights.resize(point_count * 5)
	for index in range(point_count):
		var t := float(index) / float(maxi(1, point_count - 1))
		var remaining := maxf(0.0, 1.0 - t)
		var weight_base := index * 5
		trail_station_weights[weight_base] = t
		trail_station_weights[weight_base + 1] = pow(remaining, 0.78)
		trail_station_weights[weight_base + 2] = pow(remaining, TRAIL_SHOULDER_EXPONENT)
		trail_station_weights[weight_base + 3] = pow(remaining, 1.28)
		trail_station_weights[weight_base + 4] = smoothstep(0.0, 0.24, t)
	trail_weight_point_count = point_count


func _ribbon_strip_indices(point_count: int) -> PackedInt32Array:
	# Vertices are appended in edge/centre/edge triples, so segment i spans
	# 3i..3i+5 as two quads either side of the centre line. Rebuilt only when
	# the visible point count changes.
	if trail_strip_point_count == point_count:
		return trail_strip_indices
	trail_strip_indices.clear()
	for segment in range(point_count - 1):
		var base := segment * 3
		for side: int in [0, 1]:
			var near: int = base + side
			var far: int = base + side + 1
			trail_strip_indices.append(near)
			trail_strip_indices.append(far)
			trail_strip_indices.append(near + 3)
			trail_strip_indices.append(far)
			trail_strip_indices.append(far + 3)
			trail_strip_indices.append(near + 3)
	trail_strip_point_count = point_count
	return trail_strip_indices


func _trail_shoulder_widths(visual_scale: float) -> Vector2:
	# Extra half width the ribbon carries where it leaves the head, so the trail
	# starts as wide as the silhouette it trails instead of necking straight
	# down to a thread. A head far wider than its own tail reads as a bulb on a
	# string rather than one burning object.
	var profile := _head_profile()
	if profile.size() < 6:
		return Vector2.ZERO
	# The spread ribbon meets the head's solid core, not its outer bloom -
	# matching the bloom turns a fireball into a hard-edged dart. The bright
	# exposure line stays a line: it only has to clear the neck.
	var head_radius := body_radius * visual_scale * _head_scale()
	var widths := _trail_half_widths() * visual_scale
	var head_core := head_radius * profile[2]
	return Vector2(
		maxf(0.0, head_core - widths.x),
		maxf(0.0, head_core * 0.34 - widths.y)
	)


func _head_profile() -> PackedFloat32Array:
	# forward, rear, half width, bloom forward, bloom rear, bloom half width -
	# every entry a multiple of the drawn head radius. Rear extents stay close
	# to the forward ones: reaching backwards is the trail's job, and a long
	# rear ovoid over a narrow tail is what made the silhouette read as a bulb
	# with a thread behind it. The two width entries are also where the trail's
	# shoulder starts, so head and trail cannot drift apart.
	match type_id:
		"fast":
			return PackedFloat32Array([1.10, 1.06, 0.34, 1.48, 1.57, 0.60])
		"fragment":
			return PackedFloat32Array([0.88, 0.85, 0.78, 1.18, 1.25, 1.08])
		"fragment_piece":
			return PackedFloat32Array([1.02, 0.98, 0.42, 1.42, 1.51, 0.66])
		"fireball":
			return PackedFloat32Array([0.96, 0.92, 0.72, 1.34, 1.42, 1.12])
		"major":
			return PackedFloat32Array([1.04, 1.00, 0.78, 1.50, 1.59, 1.20])
		"comet":
			return PackedFloat32Array([0.76, 0.73, 0.62, 1.05, 1.11, 0.98])
		"satellite", "variable_star", "binary_star", "galaxy":
			# Drawn by their own silhouettes; they have no directional head for
			# a shoulder to match.
			return PackedFloat32Array()
		_:
			return PackedFloat32Array([0.82, 0.79, 0.66, 1.12, 1.19, 1.06])


func _trail_turbulence_profile() -> Vector2:
	match type_id:
		"fast":
			return Vector2(0.018, 13.0)
		"fragment":
			return Vector2(0.16, 9.5)
		"fragment_piece":
			return Vector2(0.11, 14.0)
		"fireball":
			return Vector2(0.12, 6.6)
		"major":
			return Vector2(0.10, 4.2)
		"comet":
			return Vector2(0.055, 3.4)
		_:
			return Vector2(0.035, 7.6)


func _station_normal(stations: PackedVector2Array, index: int) -> Vector2:
	var count := stations.size()
	var tangent: Vector2
	if index <= 0:
		tangent = stations[0] - stations[1]
	elif index >= count - 1:
		tangent = stations[count - 2] - stations[count - 1]
	else:
		tangent = stations[index - 1] - stations[index + 1]
	if tangent.is_zero_approx():
		tangent = _safe_travel_direction()
	else:
		tangent = tangent.normalized()
	return Vector2(-tangent.y, tangent.x)


func _trail_half_widths() -> Vector2:
	# X is the subdued optical spread; Y is the bright exposure line. Values are
	# deliberately not derived directly from hit radius so rare targets do not
	# turn into broad neon bars.
	match type_id:
		"fast":
			return Vector2(1.25, 0.38)
		"fragment":
			return Vector2(2.45, 0.72)
		"fragment_piece":
			return Vector2(1.10, 0.32)
		"fireball":
			return Vector2(3.20, 1.02)
		"major":
			return Vector2(5.10, 1.65)
		"satellite":
			return Vector2(0.72, 0.24)
		"variable_star":
			return Vector2(0.90, 0.28)
		"comet":
			return Vector2(4.10, 0.72)
		"binary_star":
			return Vector2(1.45, 0.38)
		"galaxy":
			return Vector2(2.50, 0.34)
		_:
			return Vector2(1.82, 0.54)


func _draw_type_silhouette(radius: float, visibility: float, visual_scale: float) -> void:
	match type_id:
		"satellite":
			_draw_satellite_head(radius, visibility, visual_scale)
			return
		"variable_star":
			_draw_variable_head(radius, visibility)
			return
		"binary_star":
			_draw_binary_head(radius, visibility, visual_scale)
			return
		"galaxy":
			_draw_galaxy_head(radius, visibility)
			return

	# Shape numbers live in `_head_profile` so the trail's shoulder reads the
	# same widths this silhouette is drawn at.
	var profile := _head_profile()
	_draw_directional_head(
		radius, visibility, profile[0], profile[1], profile[2], profile[3], profile[4], profile[5]
	)
	match type_id:
		"fragment":
			_draw_fragment_sparks(radius, visibility)
		"fireball":
			_draw_irregular_debris(radius, visibility, 3)
		"major":
			_draw_irregular_debris(radius, visibility, 5)


func _draw_directional_head(
	radius: float,
	visibility: float,
	forward_scale: float,
	rear_scale: float,
	width_scale: float,
	bloom_forward_scale: float,
	bloom_rear_scale: float,
	bloom_width_scale: float
) -> void:
	var direction := _safe_travel_direction()
	var normal := Vector2(-direction.y, direction.x)
	var optical_profile := _head_optical_profile()
	var phase := age * optical_profile.y + wobble_phase
	var deformation := optical_profile.x
	var bloom_points := _organic_head_points(
		direction,
		normal,
		radius * bloom_forward_scale,
		radius * bloom_rear_scale,
		radius * bloom_width_scale,
		deformation * 0.72,
		phase + 0.36
	)
	var sheath_shift := (
		-direction * radius * 0.05
		+ normal * radius * deformation * 0.24 * sin(phase * 0.91 + 1.7)
	)
	for index in range(bloom_points.size()):
		bloom_points[index] += sheath_shift
	var optical_flicker := 0.94 + 0.06 * sin(phase * 1.71 + 0.8)
	var bright_point := direction * radius * 0.12
	# A soft asymmetric optical skirt gives small heads a visible footprint.
	# Its transparent edge stays subordinate to the compact overexposed core.
	var optical_skirt := PackedVector2Array()
	for point in bloom_points:
		optical_skirt.append(point * 2.0)
	_draw_graded_polygon(
		optical_skirt,
		bright_point + sheath_shift,
		Color(glow_color, clampf(0.10 * visibility * optical_flicker, 0.0, 0.18)),
		Color(glow_color, 0.0)
	)
	_draw_graded_polygon(
		bloom_points,
		bright_point + sheath_shift,
		Color(glow_color, clampf(0.26 * visibility * optical_flicker, 0.0, 1.0)),
		Color(glow_color, 0.0)
	)

	var core_points := _organic_head_points(
		direction,
		normal,
		radius * forward_scale,
		radius * rear_scale,
		radius * width_scale,
		deformation,
		phase
	)
	var warm_primary := primary_color.lerp(Color.WHITE, 0.18)
	_draw_graded_polygon(
		core_points,
		bright_point,
		Color(warm_primary, clampf(1.0 * visibility * optical_flicker, 0.0, 1.0)),
		Color(warm_primary, clampf(0.16 * visibility * optical_flicker, 0.0, 1.0))
	)

	# A small overexposed patch wanders inside the leading half. It supplies life
	# without turning the whole meteor into a white shaft or a concentric orb.
	var hotspot_profile := _head_hotspot_profile()
	var hotspot_axis := direction.rotated(sin(phase * 0.83) * deformation * 0.32)
	var hotspot_center := (
		direction * radius * (0.22 + 0.07 * sin(phase * 1.13 + 0.4))
		+ normal * radius * deformation * 0.72 * sin(phase * 1.47 + 1.1)
	)
	var hotspot_points := _ellipse_points(
		hotspot_axis,
		radius * hotspot_profile.x * (0.92 + 0.08 * sin(phase * 1.31)),
		radius * hotspot_profile.y * (0.90 + 0.10 * sin(phase * 1.67 + 0.5)),
		hotspot_center,
		deformation * 0.22
	)
	draw_colored_polygon(
		hotspot_points,
		Color(
			primary_color.lerp(Color.WHITE, 0.76),
			clampf((0.66 + 0.10 * sin(phase * 1.89)) * visibility, 0.0, 1.0)
		)
	)


func _draw_graded_polygon(
	points: PackedVector2Array,
	bright_point: Vector2,
	centre_color: Color,
	rim_color: Color
) -> void:
	# A flat fill ends the head on a hard outline, and a hard outline over a
	# narrow tail is what reads as a bulb tied to a thread. A fan from an
	# interior point keeps the organic silhouette and lets its edge fall off,
	# so the head dissolves into the trail instead of sitting on top of it.
	var count := points.size()
	if count < 3:
		return
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.append(bright_point)
	colors.append(centre_color)
	for index in range(count):
		vertices.append(points[index])
		colors.append(rim_color)
	var indices := PackedInt32Array()
	for index in range(count):
		indices.append(0)
		indices.append(1 + index)
		indices.append(1 + (index + 1) % count)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, vertices, colors)


func _organic_head_points(
	direction: Vector2,
	normal: Vector2,
	forward_length: float,
	rear_length: float,
	half_width: float,
	deformation: float,
	phase: float
) -> PackedVector2Array:
	var upper := 1.0 + deformation * sin(phase)
	var lower := 1.0 + deformation * 0.82 * sin(phase + 2.18)
	var front := 1.0 + deformation * 0.30 * sin(phase * 1.27 + 0.5)
	var rear_sway := normal * half_width * (0.04 + deformation * 0.72) * sin(phase * 0.73 + 1.2)
	return PackedVector2Array([
		-direction * rear_length + rear_sway + normal * half_width * 0.10,
		-direction * rear_length * 0.58 + normal * half_width * 0.38 * upper,
		-direction * rear_length * 0.14 + normal * half_width * 0.82 * upper,
		direction * forward_length * 0.42 + normal * half_width * 0.70 * upper,
		direction * forward_length * 0.84 * front + normal * half_width * 0.36 * upper,
		direction * forward_length * 0.98 * front + normal * half_width * 0.12,
		direction * forward_length * 0.97 * front - normal * half_width * 0.13,
		direction * forward_length * 0.84 * front - normal * half_width * 0.36 * lower,
		direction * forward_length * 0.55 - normal * half_width * 0.58 * lower,
		-direction * rear_length * 0.06 - normal * half_width * 0.72 * lower,
		-direction * rear_length * 0.56 - normal * half_width * 0.30 * lower,
		-direction * rear_length * 0.96 + rear_sway - normal * half_width * 0.10,
	])


func _head_optical_profile() -> Vector2:
	# X is silhouette deformation, Y is its visual-only frequency.
	match type_id:
		"fast":
			return Vector2(0.025, 12.5)
		"fragment":
			return Vector2(0.115, 9.6)
		"fragment_piece":
			return Vector2(0.095, 14.2)
		"fireball":
			return Vector2(0.082, 6.2)
		"major":
			return Vector2(0.070, 3.8)
		"comet":
			return Vector2(0.045, 3.4)
		_:
			return Vector2(0.048, 7.4)


func _head_hotspot_profile() -> Vector2:
	match type_id:
		"fast":
			return Vector2(0.54, 0.13)
		"fragment_piece":
			return Vector2(0.42, 0.16)
		"fragment":
			return Vector2(0.32, 0.24)
		"fireball":
			return Vector2(0.42, 0.24)
		"major":
			return Vector2(0.46, 0.28)
		"comet":
			return Vector2(0.34, 0.20)
		_:
			return Vector2(0.36, 0.20)


func _draw_fragment_sparks(radius: float, visibility: float) -> void:
	var split_visibility := smoothstep(0.18, split_progress, get_burn_progress()) * visibility
	if split_visibility <= 0.001:
		return
	var direction := _safe_travel_direction()
	var normal := Vector2(-direction.y, direction.x)
	var spark_flicker := 0.18 + 0.82 * pow(maxf(0.0, sin(age * 17.0 + wobble_phase)), 4.0)
	var envelope := _debris_envelope(radius)
	debris_draw_points.clear()
	for index in range(3):
		var sequence := float(index)
		var spark_phase := wobble_phase + age * (8.5 + sequence) + sequence * 2.37
		var center := (
			-direction * radius * (0.72 + sequence * 0.48)
			+ normal * envelope * sin(spark_phase) * (0.30 - sequence * 0.06)
		)
		var shard_direction := (direction + normal * 0.14 * sin(spark_phase + 0.8)).normalized()
		var shard_length := radius * (0.16 + sequence * 0.035)
		debris_draw_points.append(center - shard_direction * shard_length)
		debris_draw_points.append(center + shard_direction * shard_length * 0.52)
	draw_multiline(
		debris_draw_points,
		Color(primary_color, clampf(0.62 * split_visibility * spark_flicker, 0.0, 1.0)),
		maxf(0.48, radius * 0.10),
		true
	)


func _debris_envelope(radius: float) -> float:
	# The width shed material is allowed to wander across: the head's own core
	# half width, which is also where the trail's shoulder starts. Anything
	# outside that is outside the trail.
	var profile := _head_profile()
	if profile.size() < 6:
		return radius * 0.66
	return radius * profile[2]


func _draw_irregular_debris(radius: float, visibility: float, count: int) -> void:
	var direction := _safe_travel_direction()
	var normal := Vector2(-direction.y, direction.x)
	# Shed material keeps the path it was shed from: shards run along travel with
	# only a slight yaw, and stay inside the trail they came out of. Steeper
	# angles and a wider scatter put them across the tail, where they read as
	# scratches on the lens rather than as burning debris.
	var envelope := _debris_envelope(radius)
	debris_draw_points.clear()
	for index in range(count):
		var sequence := float(index)
		var shard_phase := wobble_phase + sequence * 2.17 + age * (2.4 + sequence * 0.08)
		var distance := radius * (1.62 + sequence * 0.76 + 0.18 * sin(shard_phase * 0.72 + sequence * 0.63))
		var spread := envelope * maxf(0.10, 0.34 - sequence * 0.045)
		var side_offset := sin(shard_phase) * spread
		var center := -direction * distance + normal * side_offset
		var shard_length := radius * (0.16 + 0.12 * (0.5 + 0.5 * sin(wobble_phase * 0.7 + sequence * 1.91)))
		var shard_direction := (direction + normal * 0.12 * sin(shard_phase + 0.9)).normalized()
		debris_draw_points.append(center - shard_direction * shard_length * 0.72)
		debris_draw_points.append(center + shard_direction * shard_length)
	if debris_draw_points.is_empty():
		return
	# Both passes are batched, so a seven-piece Major Fireball costs two draw
	# commands instead of a circle command per fragment.
	var debris_flicker := 0.72 + 0.28 * (0.5 + 0.5 * sin(age * (5.2 if type_id == "fireball" else 3.6) + wobble_phase))
	draw_multiline(
		debris_draw_points,
		Color(glow_color, clampf(0.25 * visibility * debris_flicker, 0.0, 1.0)),
		maxf(0.72, radius * 0.17),
		true
	)
	draw_multiline(
		debris_draw_points,
		Color(primary_color, clampf(0.58 * visibility * debris_flicker, 0.0, 1.0)),
		maxf(0.44, radius * 0.065),
		true
	)


func _draw_binary_head(radius: float, visibility: float, visual_scale: float) -> void:
	var direction := _safe_travel_direction()
	var normal := Vector2(-direction.y, direction.x)
	var separation := radius * (0.66 + 0.11 * sin(age * 2.6 + wobble_phase))
	var first := normal * separation + direction * radius * 0.10
	var second := -normal * separation - direction * radius * 0.12
	var component_lines := PackedVector2Array([
		first - direction * radius * 0.42,
		first + direction * radius * 0.55,
		second - direction * radius * 0.34,
		second + direction * radius * 0.46,
	])
	draw_line(first, second, Color(glow_color, clampf(0.10 * visibility, 0.0, 1.0)), maxf(0.50, radius * 0.08), true)
	draw_multiline(component_lines, Color(glow_color, clampf(0.16 * visibility, 0.0, 1.0)), maxf(1.0 * visual_scale, radius * 0.48), true)
	draw_multiline(component_lines, Color(primary_color.lerp(Color.WHITE, 0.48), clampf(0.92 * visibility, 0.0, 1.0)), maxf(0.55 * visual_scale, radius * 0.18), true)


func _draw_galaxy_head(radius: float, visibility: float) -> void:
	var axis := _safe_travel_direction().rotated(0.28)
	var center := axis * radius * 0.10 + Vector2(-axis.y, axis.x) * radius * 0.04
	var outer := _ellipse_points(axis, radius * 3.05, radius * 0.86, center, 0.10)
	var body := _ellipse_points(axis, radius * 2.34, radius * 0.48, center, 0.06)
	var core := _ellipse_points(axis, radius * 0.72, radius * 0.23, center + axis * radius * 0.08, 0.02)
	draw_colored_polygon(outer, Color(glow_color, clampf(0.075 * visibility, 0.0, 1.0)))
	draw_colored_polygon(body, Color(primary_color, clampf(0.36 * visibility, 0.0, 1.0)))
	draw_colored_polygon(core, Color(primary_color.lerp(Color.WHITE, 0.65), clampf(0.76 * visibility, 0.0, 1.0)))


func _ellipse_points(
	axis: Vector2,
	half_length: float,
	half_width: float,
	center: Vector2,
	irregularity: float
) -> PackedVector2Array:
	var normal := Vector2(-axis.y, axis.x)
	var points := PackedVector2Array()
	for index in range(16):
		var angle := TAU * float(index) / 16.0
		var distortion := 1.0 + irregularity * sin(angle * 3.0 + wobble_phase)
		points.append(
			center
			+ axis * cos(angle) * half_length * distortion
			+ normal * sin(angle) * half_width * (2.0 - distortion)
		)
	return points


func _draw_satellite_head(radius: float, visibility: float, visual_scale: float) -> void:
	var direction := _safe_travel_direction()
	var normal := Vector2(-direction.y, direction.x)
	var wing_points := PackedVector2Array([
		-normal * radius * 0.95,
		normal * radius * 0.95,
		-direction * radius * 0.46,
		direction * radius * 0.58,
	])
	draw_multiline(wing_points, Color(glow_color, clampf(0.22 * visibility, 0.0, 1.0)), maxf(1.3 * visual_scale, radius * 0.24), true)
	draw_line(-direction * radius * 0.32, direction * radius * 0.46, Color(primary_color, clampf(0.92 * visibility, 0.0, 1.0)), maxf(0.65 * visual_scale, radius * 0.15), true)


func _draw_variable_head(radius: float, visibility: float) -> void:
	var pulse := 0.86 + 0.14 * (0.5 + 0.5 * sin(age * 2.7 + wobble_phase))
	var points := PackedVector2Array()
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + PI * 0.125
		var point_radius := radius * pulse * (1.22 if index % 2 == 0 else 0.31)
		points.append(Vector2.from_angle(angle) * point_radius)
	var outer_points := PackedVector2Array()
	for point in points:
		outer_points.append(point * 1.48)
	draw_colored_polygon(outer_points, Color(glow_color, clampf(0.075 * visibility, 0.0, 1.0)))
	draw_colored_polygon(points, Color(primary_color.lerp(Color.WHITE, 0.28), clampf(0.82 * visibility, 0.0, 1.0)))


func _safe_travel_direction() -> Vector2:
	if travel_direction.is_zero_approx():
		return Vector2.RIGHT
	return travel_direction.normalized()


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
	queue_redraw()
