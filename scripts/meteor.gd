extends Node2D

signal observed(meteor, reward, multiplier, was_manual, quality_grade)
signal expired(meteor, was_major)
signal fragment_requested(origin, velocity, parent_type)

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

var age: float = 0.0
var observation_progress: float = 0.0
var precision_focus: float = 0.0
var last_quality: float = 0.0
var last_manual_frame: int = -100
var base_automatic_rate: float = 0.0
var secondary_assist: float = 0.0
var prediction_enabled: bool = false
var wide_field_enabled: bool = false
var precision_enabled: bool = false
var perfect_enabled: bool = false
var manual_touched: bool = false
var manual_tracking_time: float = 0.0
var quality_integral: float = 0.0
var interruption_count: int = 0
var alive: bool = true
var observed_successfully: bool = false
var split_done: bool = false
var linger_time: float = 0.0
var trail_points: Array[Vector2] = []
var trail_draw_points := PackedVector2Array()
var trail_glow_colors := PackedColorArray()
var trail_core_colors := PackedColorArray()
var prediction_draw_points := PackedVector2Array()
var travel_direction := Vector2.ZERO
var trail_sample_accumulator: float = 0.0
var wobble_phase: float = 0.0
var rng := RandomNumberGenerator.new()


func configure(spec: Dictionary, meteor_type: String, start_position: Vector2, move_velocity: Vector2, lifetime_scale: float, features: Dictionary) -> void:
	type_id = meteor_type
	display_name = String(spec.name)
	position = start_position
	velocity = move_velocity
	travel_direction = velocity.normalized()
	visible_lifetime = float(spec.lifetime) * lifetime_scale
	base_value = float(spec.value)
	required_track_time = float(spec.track_time)
	body_radius = float(spec.radius)
	primary_color = spec.color
	glow_color = spec.glow
	max_trail_points = int(float(spec.trail) * (1.22 if lifetime_scale > 1.01 else 1.0))
	prediction_enabled = bool(features.get("prediction", false))
	wide_field_enabled = bool(features.get("wide_field", false))
	precision_enabled = bool(features.get("precision", false))
	perfect_enabled = bool(features.get("perfect", false))
	base_automatic_rate = float(features.get("automation", 0.0))
	secondary_assist = float(features.get("secondary", 0.0))
	rng.seed = int(start_position.x * 193.0 + start_position.y * 877.0 + velocity.length() * 31.0) & 0x7fffffff
	wobble_phase = rng.randf_range(0.0, TAU)
	trail_points.append(start_position)
	_rebuild_prediction_draw_points()


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
		var distance := body_radius + 28.0 + index * 24.0
		prediction_draw_points.append(travel_direction * distance)
		prediction_draw_points.append(travel_direction * (distance + 10.0))


func _process(delta: float) -> void:
	if not alive:
		linger_time -= delta
		queue_redraw()
		if linger_time <= 0.0:
			queue_free()
		return

	age += delta
	var move_velocity := velocity
	if type_id == "fragment" or type_id == "fragment_piece":
		var wobble := sin(age * 8.0 + wobble_phase) * (0.045 if type_id == "fragment" else 0.085)
		move_velocity = velocity.rotated(wobble)
	position += move_velocity * delta

	trail_sample_accumulator += delta
	if trail_sample_accumulator >= 0.024:
		trail_sample_accumulator = 0.0
		trail_points.push_front(global_position)
		if trail_points.size() > max_trail_points:
			trail_points.pop_back()

	var auto_rate := base_automatic_rate + secondary_assist
	if auto_rate > 0.0:
		observation_progress += auto_rate * delta
		last_quality = maxf(last_quality * 0.96, 0.38)

	if Engine.get_process_frames() - last_manual_frame > 1 and auto_rate <= 0.0:
		observation_progress = maxf(0.0, observation_progress - delta * 0.055)

	if not split_done:
		if type_id == "fragment" and age >= visible_lifetime * 0.46:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id)
		elif type_id == "major" and age >= visible_lifetime * 0.57:
			split_done = true
			fragment_requested.emit(global_position, velocity, type_id)

	if observation_progress >= 1.0:
		_finish_observation(auto_rate)
	elif age >= visible_lifetime:
		alive = false
		linger_time = 0.32
		expired.emit(self, type_id == "major")

	queue_redraw()


func apply_manual_observation(delta: float, cursor_distance: float, tracking_radius: float) -> void:
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
	observation_progress += delta * tracking_speed / required_track_time
	precision_focus += delta * quality
	queue_redraw()


func set_features(features: Dictionary) -> void:
	prediction_enabled = bool(features.get("prediction", prediction_enabled))
	wide_field_enabled = bool(features.get("wide_field", wide_field_enabled))
	precision_enabled = bool(features.get("precision", precision_enabled))
	perfect_enabled = bool(features.get("perfect", perfect_enabled))
	base_automatic_rate = float(features.get("automation", base_automatic_rate))
	secondary_assist = float(features.get("secondary", secondary_assist))


func set_secondary_assist(value: float) -> void:
	secondary_assist = value


func get_assist_rate(duration_multiplier: float) -> float:
	return 1.0 / maxf(required_track_time * duration_multiplier, 0.001)


func can_be_tracked() -> bool:
	return alive


func get_tracking_radius(base_radius: float) -> float:
	var size_bonus := clampf((body_radius - 7.0) * 0.52, 0.0, 18.0)
	return base_radius + size_bonus


func get_progress() -> float:
	return clampf(observation_progress, 0.0, 1.0)


func get_quality() -> float:
	return last_quality


func get_visual_color() -> Color:
	return glow_color


func get_predicted_multiplier() -> float:
	if not precision_enabled or not manual_touched:
		return 1.0
	var multiplier := 1.0 + minf(2.0, precision_focus * 0.58)
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
	alive = false
	observed_successfully = true
	linger_time = 0.62 if type_id != "major" else 1.1
	var was_manual := manual_touched
	var multiplier := get_predicted_multiplier()
	if not was_manual and auto_rate > 0.0:
		multiplier = 0.68
	var reward := maxf(1.0, round(base_value * multiplier))
	observed.emit(self, reward, multiplier, was_manual, get_quality_grade())
	queue_redraw()


func _draw() -> void:
	if trail_points.size() > 1:
		trail_draw_points.clear()
		trail_glow_colors.clear()
		trail_core_colors.clear()
		var linger_alpha := 1.0 if alive else clampf(linger_time * 2.4, 0.0, 1.0)
		for index in range(trail_points.size()):
			var t := float(index) / float(maxi(1, trail_points.size() - 1))
			var alpha := pow(1.0 - t, 1.35) * linger_alpha
			trail_draw_points.append(trail_points[index] - global_position)
			trail_glow_colors.append(Color(glow_color, alpha * 0.42))
			trail_core_colors.append(Color(primary_color, alpha * 0.82))
		# Two batched Canvas commands replace two draw_line calls per segment.
		draw_polyline_colors(trail_draw_points, trail_glow_colors, maxf(1.6, body_radius * 1.18), true)
		draw_polyline_colors(trail_draw_points, trail_core_colors, maxf(0.8, body_radius * 0.42), true)

	if prediction_enabled and alive:
		draw_multiline(prediction_draw_points, Color(glow_color, 0.22), 1.4, true)

	var visibility := 1.0 if alive else clampf(linger_time * 2.2, 0.0, 1.0)
	var success_bloom := 1.0
	if observed_successfully:
		success_bloom = 1.0 + (1.0 - visibility) * 3.0
	var pulse := 1.0 + sin(age * 13.0 + wobble_phase) * 0.06
	var r := body_radius * pulse * success_bloom
	draw_circle(Vector2.ZERO, r * 3.4, Color(glow_color, 0.065 * visibility))
	draw_circle(Vector2.ZERO, r * 1.95, Color(glow_color, 0.17 * visibility))
	draw_arc(Vector2.ZERO, r + 8.0 + sin(age * 4.0) * 1.5, 0.0, TAU, 28, Color(glow_color, 0.16 * visibility), 1.2, true)
	draw_circle(Vector2.ZERO, r, Color(primary_color, visibility))
	draw_circle(-travel_direction * r * 0.22, r * 0.45, Color(1.0, 1.0, 1.0, visibility))

	if type_id == "fireball" or type_id == "major":
		var flame_dir := -travel_direction
		for index in range(3 if type_id == "fireball" else 6):
			var side := Vector2(-flame_dir.y, flame_dir.x) * sin(age * 8.0 + index * 1.7) * r * 0.35
			var center := flame_dir * r * (1.0 + index * 0.42) + side
			draw_circle(center, r * (0.52 - index * 0.045), Color(glow_color, (0.28 - index * 0.025) * visibility))

	var scan_rate := base_automatic_rate + secondary_assist
	if scan_rate > 0.0 and alive:
		var scan_radius := body_radius + 12.0 + sin(age * 5.0) * 2.0
		var start_angle := age * 2.5
		draw_arc(Vector2.ZERO, scan_radius, start_angle, start_angle + PI * 1.25, 30, Color("63f2d2"), 1.6, true)
		draw_arc(Vector2.ZERO, scan_radius + 5.0, -start_angle * 0.7, -start_angle * 0.7 + PI * 0.55, 18, Color(0.38, 0.95, 0.82, 0.38), 1.0, true)
