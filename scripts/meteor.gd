extends Node2D

# Topology depends only on point count; shape and colors remain live.
var graded_fan_indices: Dictionary = {}

const UITheme = preload("res://scripts/ui_theme.gd")
const TriangleBatch = preload("res://scripts/meteor_triangle_batch.gd")
const PlanetSurfaceScene = preload("res://scenes/planet_surface.tscn")
const AsteroidSurfaceMaterial = preload("res://resources/asteroid_surface.tres")
const GravityCapture = preload("res://scripts/gravity_capture.gd")
const BLACK_HOLE_PULL_RADIUS := 240.0
const StellarVisual = preload("res://scripts/stellar_visual.gd")
const StellarSurfaceScene = preload("res://scenes/stellar_surface.tscn")
var stellar_surface: Node2D
const SUPERNOVA_RADIUS := 180.0
var supernova_radius := 0.0
var gravity_capture: RefCounted
var optical_lens: Node2D
const ScanArcs = preload("res://scripts/scan_arc_instances.gd")
const HeadTexture = preload("res://scripts/meteor_head_texture.gd")
var textured_head_enabled := true
var head_texture: RefCounted

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

var simulation_tick := 0
var simulation_id := 0
var previous_simulation_position := Vector2.ZERO

var age: float = 0.0
var observation_progress: float = 0.0
var precision_focus: float = 0.0
var last_quality: float = 0.0
var last_manual_tick: int = -100
var base_automatic_rate: float = 0.0
var dish_assist_rate: float = 0.0
var lane_assist_rate: float = 0.0
var wide_field_enabled: bool = false
var precision_enabled: bool = false
var perfect_enabled: bool = false
var analysis_speed_multiplier: float = 1.0
var celestial_speed_multiplier: float = 1.0
var spectral_calibrated: bool = false
var spectral_capstone_enabled: bool = false
var manual_touched: bool = false
var manual_tracking_time: float = 0.0
var quality_integral: float = 0.0
var interruption_count: int = 0
var manual_contribution: float = 0.0
var automatic_contribution: float = 0.0
var observation_controller: Node
var alive: bool = true
var observed_successfully: bool = false
var completion_motion_scale := 1.0
var completion_glint_enabled := true
var split_done: bool = false
var linger_time: float = 0.0
var linger_duration: float = 0.20
var trail_points: Array[Vector2] = []
var trail_glow_ribbon := PackedVector2Array()
var trail_glow_ribbon_colors := PackedColorArray()
var trail_core_ribbon := PackedVector2Array()
var trail_core_ribbon_colors := PackedColorArray()
var trail_strip_indices := PackedInt32Array()
var trail_strip_point_count: int = -1
var trail_station_weights := PackedFloat64Array()
var trail_weight_point_count: int = -1
var alternate_trail_weights := PackedFloat64Array()
var alternate_trail_weight_count := -1
var trail_weight_build_count := 0
var debris_draw_points := PackedVector2Array()
var travel_direction := Vector2.ZERO
var trail_sample_accumulator: float = 0.0
var wobble_phase: float = 0.0
var rng := RandomNumberGenerator.new()
var observation_view: Camera2D
var observation_visual_scale: float = 1.0
var triangle_batch := TriangleBatch.new()
var render_layer: Node2D
var planet_surface: Node2D
var scan_arcs: RefCounted
var drawn_age := -1.0
var drawn_linger := -1.0


func configure(spec: Dictionary, meteor_type: String, start_position: Vector2, move_velocity: Vector2, lifetime_scale: float, features: Dictionary, planned_burnout := Vector2.INF, view: Camera2D = null) -> void:
	type_id = meteor_type
	display_name = String(spec.name)
	position = start_position
	previous_simulation_position = start_position
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
	celestial_speed_multiplier = maxf(0.1, float(features.get("celestial_speed", 1.0)))
	spectral_calibrated = bool(features.get("spectral_calibrated", false))
	spectral_capstone_enabled = bool(features.get("spectral_capstone", false))
	observation_view = view
	observation_visual_scale = _current_visual_scale()
	rng.seed = int(start_position.x * 193.0 + start_position.y * 877.0 + velocity.length() * 31.0) & 0x7fffffff
	wobble_phase = rng.randf_range(0.0, TAU)
	manual_contribution = 0.0
	automatic_contribution = 0.0
	trail_points.clear()
	trail_points.append(start_position)


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
	# Solid surfaces must occlude background stars instead of adding their light.
	material = null if is_solid_body() else SHARED_ADDITIVE_MATERIAL
	if type_id in ["variable_star", "binary_star"]:
		material = AsteroidSurfaceMaterial.duplicate()
	if type_id == "galaxy":
		planet_surface = PlanetSurfaceScene.instantiate()
		add_child(planet_surface)
	if type_id == "stellar":
		stellar_surface = StellarSurfaceScene.instantiate()
		add_child(stellar_surface)
	if get_parent().has_method("submit_target"):
		render_layer = get_parent()
		triangle_batch.deferred = true
	queue_redraw()


func _process(_delta: float) -> void:
	_sync_visual_scale()
	# Tick resolution already invalidates live geometry. In between ticks Godot
	# interpolates the native lines and retained light together;
	# repeating the same procedural drawing cannot make either move more smoothly.
	# Age/linger also cover standalone previews and the post-expiry fade.
	if age != drawn_age or linger_time != drawn_linger:
		queue_redraw()


func tick_motion(delta: float, tick_id: int) -> void:
	simulation_tick = tick_id
	previous_simulation_position = global_position
	if not alive:
		linger_time -= delta
		if linger_time <= 0.0: queue_free()
		return
	var motion_delta: float = delta * observation_controller.motion_multiplier_for(self) if is_instance_valid(observation_controller) else delta
	if gravity_capture != null:
		if gravity_capture.advance(self, motion_delta): gravity_capture = null
	else:
		age += motion_delta
		if motion_delta > 0.0:
			_update_burn_motion(motion_delta)
	_sample_motion_trail(delta)


func begin_gravity_capture(centre: Vector2, world_scale: float, extra_slow_seconds: float = 0.0) -> bool:
	if not alive or is_queued_for_deletion() or type_id == "black_hole": return false
	gravity_capture = GravityCapture.new()
	gravity_capture.configure(self, centre, world_scale, extra_slow_seconds)
	return true


func motion_snapshot(delta: float) -> Dictionary:
	var motion_delta: float = delta * observation_controller.motion_multiplier_for(self) if is_instance_valid(observation_controller) else delta
	return {"age": age, "delta": motion_delta, "position": position,
		"velocity": velocity, "travel": travel_direction, "entry": entry_position,
		"burnout": burnout_position, "lifetime": visible_lifetime,
		"terminal": burn_terminal_ratio, "wobble": burn_wobble,
		"split": split_progress, "frequency": _wobble_frequency(), "phase": wobble_phase}


func apply_motion_result(result: Dictionary, delta: float, tick_id: int) -> void:
	simulation_tick = tick_id
	previous_simulation_position = global_position
	age = result.age
	position = result.position
	velocity = result.velocity
	travel_direction = result.travel
	_sample_motion_trail(delta)


func _sample_motion_trail(delta: float) -> void:

	trail_sample_accumulator += delta
	if trail_sample_accumulator >= 0.024:
		trail_sample_accumulator = fmod(trail_sample_accumulator, 0.024)
		trail_points.push_front(global_position)
		if trail_points.size() > max_trail_points:
			trail_points.pop_back()


func tick_observation(delta: float) -> void:
	if not alive: return
	var auto_rate := get_automatic_rate()
	if auto_rate > 0.0:
		var automatic_work := auto_rate * delta
		automatic_contribution += minf(automatic_work, maxf(0.0, 1.0 - observation_progress))
		observation_progress += automatic_work
		last_quality = maxf(last_quality * 0.96, 0.38)

	if simulation_tick - last_manual_tick > 1 and auto_rate <= 0.0:
		observation_progress = maxf(0.0, observation_progress - delta * 0.055)


func tick_resolve() -> void:
	if not alive: return
	if not split_done:
		if type_id == "fragment" and get_burn_progress() >= split_progress:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))
		elif type_id == "major" and get_burn_progress() >= split_progress:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))

	if observation_progress >= 1.0:
		_finish_observation(get_automatic_rate())
	elif age >= visible_lifetime:
		alive = false
		linger_duration = burnout_linger
		linger_time = linger_duration
		expired.emit(self, type_id == "major")

	queue_redraw()


func simulate_tick(delta: float) -> void:
	tick_motion(delta, simulation_tick + 1)
	tick_observation(delta)
	tick_resolve()


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
	var current_frame := simulation_tick
	if manual_touched and current_frame - last_manual_tick > 1:
		interruption_count += 1
	last_manual_tick = current_frame
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
	var previous_automatic_rate := base_automatic_rate
	wide_field_enabled = bool(features.get("wide_field", wide_field_enabled))
	precision_enabled = bool(features.get("precision", precision_enabled))
	perfect_enabled = bool(features.get("perfect", perfect_enabled))
	base_automatic_rate = float(features.get("automation", base_automatic_rate))
	analysis_speed_multiplier = maxf(0.1, float(features.get("analysis_speed", analysis_speed_multiplier)))
	celestial_speed_multiplier = maxf(0.1, float(features.get("celestial_speed", celestial_speed_multiplier)))
	spectral_calibrated = bool(features.get("spectral_calibrated", spectral_calibrated))
	spectral_capstone_enabled = bool(features.get("spectral_capstone", spectral_capstone_enabled))
	if base_automatic_rate != previous_automatic_rate:
		queue_redraw()


func get_spectral_speed_multiplier() -> float:
	if not spectral_calibrated:
		return 1.0
	return 1.45 if spectral_capstone_enabled else 1.25


func get_spectral_value_multiplier() -> float:
	if not spectral_calibrated:
		return 1.0
	return 1.35 if spectral_capstone_enabled else 1.15


func set_dish_assist_rate(value: float) -> void:
	if dish_assist_rate == value: return
	dish_assist_rate = value
	queue_redraw()


func set_lane_assist_rate(value: float) -> void:
	if lane_assist_rate == value: return
	lane_assist_rate = value
	queue_redraw()


func get_automatic_rate() -> float:
	return (base_automatic_rate + dish_assist_rate + lane_assist_rate) * celestial_speed_multiplier


func allows_automatic_assist() -> bool:
	return true


func has_dish_assist() -> bool:
	return dish_assist_rate > 0.0


func has_non_dish_lane_partner() -> bool:
	var manual_is_live := manual_touched and simulation_tick - last_manual_tick <= 1
	return base_automatic_rate > 0.0 or manual_is_live


func get_assist_rate(duration_multiplier: float) -> float:
	return 1.0 / maxf(required_track_time * duration_multiplier, 0.001)


func can_be_tracked() -> bool:
	return alive


func get_tracking_radius(base_radius: float) -> float:
	if is_solid_body():
		return base_radius + get_observation_body_radius()
	var size_bonus := clampf((body_radius - 7.0) * 0.52, 0.0, 18.0)
	return base_radius + size_bonus * _interaction_scale()


func is_solid_body() -> bool:
	# Stable save IDs; the former star/galaxy artwork is no longer rendered.
	return type_id in ["variable_star", "binary_star", "galaxy", "black_hole", "stellar"]


func get_observation_body_radius() -> float:
	return body_radius * _head_scale() * _current_visual_scale() if is_solid_body() else 0.0


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_manual_contribution() -> float:
	return clampf(manual_contribution / maxf(1.0, manual_contribution + automatic_contribution), 0.0, 1.0)


func get_automatic_contribution() -> float:
	return clampf(automatic_contribution / maxf(1.0, manual_contribution + automatic_contribution), 0.0, 1.0)



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
		"comet":
			brightness *= 1.0 + 0.08 * sin(age * 5.0 + wobble_phase)
	if progress <= burn_fade_start:
		brightness = maxf(0.78, brightness)
	return maxf(0.10, brightness)


func get_burn_tail_scale() -> float:
	var tail_fade_start := maxf(0.0, burn_fade_start - 0.10)
	return lerpf(1.0, 0.16, smoothstep(tail_fade_start, 1.0, get_burn_progress()))


func get_planned_position(progress: float) -> Vector2:
	return entry_position.lerp(burnout_position, burn_curve(progress, burn_terminal_ratio))


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


func complete_from_supernova() -> void:
	if not alive or is_queued_for_deletion() or type_id in ["stellar", "black_hole"]: return
	automatic_contribution += maxf(0.0, 1.0 - observation_progress)
	observation_progress = 1.0
	_finish_observation(1.0, true)


func _finish_observation(auto_rate: float, force_automatic: bool = false) -> void:
	if not alive:
		return
	if type_id == "fragment" and not split_done:
		split_done = true
		fragment_requested.emit(global_position, velocity, type_id, bool(get_meta("gemini_echo", false)), bool(get_meta("leonid_storm", false)), bool(get_meta("perseid_outburst", false)))
	alive = false
	observed_successfully = true
	linger_duration = 0.62 if type_id != "major" else 1.1
	if type_id == "black_hole": linger_duration = 1.05
	if type_id == "stellar": linger_duration = 0.9
	linger_time = linger_duration
	var was_manual := manual_touched and not force_automatic
	var multiplier := get_predicted_multiplier()
	if not was_manual and auto_rate > 0.0:
		multiplier = 0.68
	var reward := maxf(1.0, round(base_value * multiplier))
	observed.emit(self, reward, multiplier, was_manual, "AUTOMATIC" if force_automatic else get_quality_grade())
	queue_redraw()


func _draw() -> void:
	if head_texture != null: head_texture.hide()
	if scan_arcs != null: scan_arcs.clear()
	drawn_age = age
	drawn_linger = linger_time
	triangle_batch.begin()
	if render_layer != null:
		render_layer.begin_target(self)
	var visual_scale := observation_visual_scale
	if is_solid_body():
		var body_visibility := get_burn_visibility() if alive else clampf(linger_time / maxf(linger_duration, 0.001), 0.0, 1.0)
		_draw_type_silhouette(body_radius * visual_scale * _head_scale(), body_visibility, visual_scale)
		return
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
	triangle_batch.flush(get_canvas_item())

	var scan_rate := get_automatic_rate()
	if scan_rate > 0.0 and alive:
		var scan_radius := (body_radius + 12.0 + sin(age * 5.0) * 2.0) * visual_scale
		var start_angle := age * 2.5
		_draw_dashed_arc(scan_radius, start_angle, PI * 1.25, 10, Color(UITheme.INK_LOW, 0.58 * minf(1.0, burn_visibility)), 1.2 * visual_scale)
		_draw_dashed_arc(scan_radius + 5.0 * visual_scale, -start_angle * 0.7, PI * 0.55, 5, Color(UITheme.ACCENT_DEEP, 0.52 * minf(1.0, burn_visibility)), 0.9 * visual_scale)
	if render_layer != null:
		render_layer.submit_target(self, triangle_batch)


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
	triangle_batch.append(indices, trail_glow_ribbon, trail_glow_ribbon_colors)
	triangle_batch.append(indices, trail_core_ribbon, trail_core_ribbon_colors)
	triangle_batch.flush(get_canvas_item())


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
	# Sampling alternates between N and N+1 stations as the head moves away
	# from its newest trail sample. Keep both immutable arrays, bounded to two.
	var previous_weights := trail_station_weights
	var previous_count := trail_weight_point_count
	if alternate_trail_weight_count == point_count:
		trail_station_weights = alternate_trail_weights
		trail_weight_point_count = point_count
		alternate_trail_weights = previous_weights
		alternate_trail_weight_count = previous_count
		return
	alternate_trail_weights = previous_weights
	alternate_trail_weight_count = previous_count
	trail_station_weights = PackedFloat64Array()
	trail_weight_build_count += 1
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
	if textured_head_enabled and type_id in ["common", "fast"]:
		if head_texture == null: head_texture = HeadTexture.new(get_canvas_item())
		var phase := age * (12.5 if type_id == "fast" else 7.4) + wobble_phase
		head_texture.draw(type_id, radius, _safe_travel_direction(), primary_color, glow_color, visibility, phase, self_modulate)
		return
	match type_id:
		"satellite":
			_draw_satellite_head(radius, visibility, visual_scale)
			return
		"variable_star":
			_draw_asteroid_head(radius, visibility, false)
			return
		"binary_star":
			_draw_asteroid_head(radius, visibility, true)
			return
		"galaxy":
			_draw_planet_head(radius, visibility)
			return
		"stellar":
			StellarVisual.draw(self, radius, visibility)
			return
		"black_hole":
			_draw_black_hole_head(radius, visibility)
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
	triangle_batch.flush(get_canvas_item())
	var hotspot_color := Color(
			primary_color.lerp(Color.WHITE, 0.76),
			clampf((0.66 + 0.10 * sin(phase * 1.89)) * visibility, 0.0, 1.0)
		)
	if triangle_batch.deferred:
		var hotspot_colors := PackedColorArray()
		hotspot_colors.resize(hotspot_points.size())
		hotspot_colors.fill(hotspot_color)
		triangle_batch.append(Geometry2D.triangulate_polygon(hotspot_points), hotspot_points, hotspot_colors)
	else:
		draw_colored_polygon(hotspot_points, hotspot_color)


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
	if not graded_fan_indices.has(count):
		var built := PackedInt32Array()
		for index in range(count):
			built.append(0)
			built.append(1 + index)
			built.append(1 + (index + 1) % count)
		graded_fan_indices[count] = built
	var indices: PackedInt32Array = graded_fan_indices[count]
	triangle_batch.append(indices, vertices, colors)

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


# Code-drawn sky art is an intentional authoring exception. A shared faceted
# body makes the two asteroid materials readable without new overlay markers.
func _draw_asteroid_head(radius: float, visibility: float, icy: bool) -> void:
	var visual_age := age * clampf(completion_motion_scale, 0.0, 1.0)
	var rotation_phase := visual_age * (0.11 if icy else 0.085) + wobble_phase
	rotation_phase += sin(visual_age * 0.37 + wobble_phase) * 0.055
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("rotation_phase", rotation_phase)
	material.set_shader_parameter("age", visual_age)
	material.set_shader_parameter("phase", wobble_phase)
	material.set_shader_parameter("charge", observation_progress)
	material.set_shader_parameter("icy", 1.0 if icy else 0.0)
	material.set_shader_parameter("flashes", 1.0 if completion_glint_enabled else 0.0)
	material.set_shader_parameter("completion", 1.0 - visibility if observed_successfully and not alive and completion_motion_scale > 0.0 else 0.0)
	var points := PackedVector2Array()
	var count := 9 if icy else 13
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var roughness := 0.84 + 0.11 * sin(angle * 3.0 + wobble_phase) + 0.05 * cos(angle * 5.0)
		points.append((Vector2(cos(angle), sin(angle) * 0.85) * radius * roughness).rotated(rotation_phase))
	if observed_successfully and not alive and completion_motion_scale > 0.0:
		_draw_asteroid_completion(points, radius, visibility, icy, rotation_phase)
		return
	draw_colored_polygon(points, Color(primary_color.darkened(0.58), visibility))
	var core := Vector2(-0.14, -0.12).rotated(rotation_phase) * radius
	for index in range(count):
		var next := (index + 1) % count
		var midpoint := (points[index] + points[next]) * 0.5
		var light := clampf(0.53 - midpoint.normalized().dot(Vector2(0.6, 0.8)) * 0.31, 0.18, 0.88)
		var face_color := primary_color.darkened(1.0 - light)
		if icy and index % 3 == 0:
			face_color = primary_color.lerp(Color.WHITE, 0.16)
		draw_colored_polygon(PackedVector2Array([core, points[index], points[next]]), Color(face_color, visibility))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(primary_color, visibility * 0.6), 0.9, true)
	if icy:
		var crack := PackedVector2Array([
			Vector2(-0.62, -0.32), Vector2(-0.23, -0.12), Vector2(-0.09, 0.16),
			Vector2(0.20, 0.32), Vector2(0.38, 0.63)])
		for index in range(crack.size()): crack[index] = (crack[index] * radius).rotated(rotation_phase)
		draw_polyline(crack, Color("417f99", visibility * 0.75), maxf(1.6, radius * 0.07), true)
		draw_polyline(crack, Color("d9f6ff", visibility * (0.55 + observation_progress * 0.35)), maxf(0.8, radius * 0.025), true)
		draw_line(crack[2], Vector2(0.50, -0.16).rotated(rotation_phase) * radius, Color(glow_color, visibility * 0.7), maxf(0.7, radius * 0.02), true)
	else:
		for crater in [Vector3(-0.32, -0.19, 0.16), Vector3(0.30, 0.10, 0.21), Vector3(-0.13, 0.40, 0.10)]:
			var centre := Vector2(crater.x, crater.y).rotated(rotation_phase) * radius
			draw_circle(centre, radius * crater.z * 1.15, Color(primary_color.darkened(0.43), visibility), true, -1.0, true)
			draw_circle(centre + Vector2(0.02, 0.02) * radius, radius * crater.z, Color("35302a", visibility), true, -1.0, true)
			draw_circle(centre + Vector2(0.025, 0.025) * radius, radius * crater.z * 0.66, Color("292623", visibility), true, -1.0, true)
			draw_arc(centre, radius * crater.z * 1.06, PI * 0.95, PI * 1.75, 16, Color(primary_color, visibility * (0.54 + observation_progress * 0.18)), maxf(0.8, radius * 0.028), true)
		for index in 7:
			var angle := float(index) * 2.4 + wobble_phase
			var pit := Vector2.from_angle(angle) * radius * (0.42 + 0.17 * sin(index * 3.7))
			draw_circle(pit.rotated(rotation_phase), radius * (0.024 + 0.012 * sin(index * 2.1)), Color("39352f", visibility * 0.7), true, -1.0, true)


func _draw_asteroid_completion(points: PackedVector2Array, radius: float, visibility: float, icy: bool, rotation_phase: float) -> void:
	# Reuse the body's faces during its existing linger; these are never targets.
	var elapsed := 1.0 - visibility
	var release := clampf((elapsed - 0.12) / 0.88, 0.0, 1.0)
	var core := Vector2(-0.14, -0.12).rotated(rotation_phase) * radius
	var stride := 1 if icy else 2
	for index in range(0, points.size(), stride):
		var face := PackedVector2Array([core])
		for corner in range(mini(stride, points.size() - index) + 1):
			face.append(points[(index + corner) % points.size()])
		var centre := Vector2.ZERO
		for point in face: centre += point
		centre /= float(face.size())
		var drift := centre.normalized() * (1.05 if icy else 0.65) + _safe_travel_direction() * 0.28
		var offset := drift * radius * release * completion_motion_scale
		var spin := sin(float(index) * 2.4 + wobble_phase) * release * (0.65 if icy else 0.35) * completion_motion_scale
		for corner in range(face.size()):
			face[corner] = (face[corner] - centre).rotated(spin) + centre + offset
		var light := clampf(0.42 - centre.normalized().dot(Vector2(0.6, 0.8)) * 0.25, 0.13, 0.75)
		var tint := primary_color.darkened(1.0 - light)
		if icy and index % 3 == 0: tint = primary_color.lerp(Color.WHITE, 0.23)
		if completion_glint_enabled:
			var glint := sin(clampf(elapsed / 0.32, 0.0, 1.0) * PI)
			tint = tint.lerp(glow_color, glint * (0.55 if icy else 0.28))
		tint = tint.darkened(release * (0.12 if icy else 0.38))
		draw_colored_polygon(face, Color(tint, visibility))
		face.append(face[0])
		draw_polyline(face, Color(glow_color if icy else primary_color, visibility * (0.45 if icy else 0.25)), 0.8, true)
	# Local dust/frost accents share the existing linger and never spawn targets.
	for index in 12:
		var angle := float(index) * 2.399 + wobble_phase
		var outward := Vector2.from_angle(angle)
		var distance := radius * (0.62 + release * (1.35 if icy else 0.90)) * completion_motion_scale
		var point := outward * distance + _safe_travel_direction() * radius * release * 0.18
		var opacity := sin(elapsed * PI) * visibility * (0.65 if icy else 0.48)
		var tint := primary_color
		if icy and completion_glint_enabled: tint = tint.lerp(Color.WHITE, 0.5)
		var speck := maxf(0.7, radius * (0.018 + 0.009 * sin(index * 3.1)))
		draw_circle(point, speck, Color(tint, opacity), true, -1.0, true)


func _draw_black_hole_head(radius: float, visibility: float) -> void:
	# Reference direction: a dark spherical silhouette with a faint cool rim.
	# The background supplies the lensed light; there is no equatorial disc.
	var completion := observed_successfully and not alive
	var pulse := sin((1.0 - visibility) * PI) if completion and completion_glint_enabled else 0.0
	var ink := Color("a9a9c6").lerp(Color("e7e6f4"), pulse * 0.45)
	# Layered narrow arcs soften the limb without a large emissive halo.
	for layer in range(4, 0, -1):
		draw_arc(Vector2.ZERO, radius * (1.0 + float(layer) * 0.018), 0.0, TAU, 64, Color(ink, visibility * (0.018 + pulse * 0.012)), radius * 0.075, true)
	draw_circle(Vector2.ZERO, radius, Color("030309", visibility), true, -1.0, true)
	# A barely visible violet reflection keeps the interior dark at game scale.
	for layer in 5:
		var fraction := float(layer) / 5.0
		draw_circle(Vector2(-0.12, 0.12) * radius, radius * (0.84 - fraction * 0.10), Color("393047", visibility * 0.022), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius * 1.014, 0.0, TAU, 64, Color(ink, visibility * (0.23 + pulse * 0.23)), maxf(0.65, radius * 0.022), true)
	draw_arc(Vector2.ZERO, radius * 1.026, PI * 0.92, PI * 1.72, 36, Color(ink, visibility * (0.22 + pulse * 0.10)), maxf(0.65, radius * 0.026), true)
	if completion and completion_motion_scale > 0.0:
		var ripple := radius * lerpf(1.75, 1.0, 1.0 - visibility)
		draw_arc(Vector2.ZERO, ripple, 0.0, TAU, 48, Color(ink, sin(visibility * PI) * 0.12), 0.8, true)


func _draw_planet_head(radius: float, visibility: float) -> void:
	planet_surface.present(self, radius, visibility)


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
		"satellite", "variable_star", "comet", "binary_star", "galaxy", "black_hole", "stellar":
			return 0.84
		_:
			return 0.72


func _draw_dashed_arc(radius: float, start_angle: float, arc_length: float, dash_count: int, color: Color, width: float) -> void:
	var standard_arc := (dash_count == 10 and arc_length == PI * 1.25) or (dash_count == 5 and arc_length == PI * 0.55)
	if standard_arc and width > 0.0 and width < 2.0:
		if scan_arcs == null: scan_arcs = ScanArcs.new(get_canvas_item())
		scan_arcs.draw(radius, start_angle, arc_length, dash_count, color, width)
		return
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

func get_observation_position(fraction: float) -> Vector2:
	var point := previous_simulation_position.lerp(global_position, fraction)
	if type_id != "black_hole" and is_instance_valid(optical_lens):
		return optical_lens.project_position(point, fraction)
	return point

func get_display_position() -> Vector2:
	return get_observation_position(Engine.get_physics_interpolation_fraction())
