extends SceneTree

# Solid-body cases expect no tails after the 2026-09-11 presentation replacement.
# Geometry and unchanged palette oracle frozen from scripts/meteor.gd at 347dcf0.
# Common/fast light was redesigned on 2026-09-16; its bounds and material response
# are checked separately while all of its ribbon coordinates remain exact.
# No main scene, settings, saves, output files, or performance claims. Native
# drawing is invoked only inside Recorder._draw; this also works headlessly.
# The reference math deliberately does not call production geometry helpers or
# inspect any optimized weights/cache. Geometry and unchanged palettes must
# match bit for bit; the redesigned wake colors retain their opacity contract.
const Meteor = preload("res://scripts/meteor.gd")
const TYPES := ["common", "fast", "fragment", "fragment_piece", "fireball", "major", "satellite", "variable_star", "comet", "binary_star", "galaxy"]
const STYLES := ["ember", "snap", "split", "spark", "flare", "major", "satellite", "rock", "comet", "ice", "planet"]
const WIDTHS := [Vector2(1.82, 0.54), Vector2(1.25, 0.38), Vector2(2.45, 0.72), Vector2(1.10, 0.32), Vector2(3.20, 1.02), Vector2(5.10, 1.65), Vector2(0.72, 0.24), Vector2(0.90, 0.28), Vector2(4.10, 0.72), Vector2(1.45, 0.38), Vector2(2.50, 0.34)]
const HEAD_SCALES := [0.72, 0.62, 0.80, 0.68, 0.50, 0.43, 0.84, 0.84, 0.84, 0.84, 0.84]
const TURBULENCE := [Vector2(0.035, 7.6), Vector2(0.018, 13.0), Vector2(0.16, 9.5), Vector2(0.11, 14.0), Vector2(0.12, 6.6), Vector2(0.10, 4.2), Vector2(0.035, 7.6), Vector2(0.035, 7.6), Vector2(0.055, 3.4), Vector2(0.035, 7.6), Vector2(0.035, 7.6)]


class Recorder:

	extends Meteor

	var gate: SceneTree
	var armed := false
	var completed := false
	var callback_count := 0
	var trail_calls: Array = []
	var spark_calls: Array = []
	var asteroid_art: ShaderMaterial

	func _ready() -> void:
		super._ready()
		# This recorder swaps types without configure to stress live getters.
		# Prepare the spawn-owned art once, outside the draw callback.
		asteroid_art = AsteroidSurfaceMaterial.duplicate()
		planet_surface = PlanetSurfaceScene.instantiate()
		add_child(planet_surface)

	func _draw() -> void:
		if not armed:
			return
		armed = false
		callback_count += 1
		gate._run_cases_in_draw(self)
		completed = true

	func render_once() -> void:
		# All invocations originate in this CanvasItem's real draw callback.
		RenderingServer.canvas_item_clear(get_canvas_item())
		trail_glow_ribbon.clear()
		trail_glow_ribbon_colors.clear()
		trail_core_ribbon.clear()
		trail_core_ribbon_colors.clear()
		debris_draw_points.clear()
		trail_calls.clear()
		spark_calls.clear()
		material = asteroid_art if type_id in ["variable_star", "binary_star"] else (null if is_solid_body() else SHARED_ADDITIVE_MATERIAL)
		planet_surface.hide()
		super._draw()

	func _draw_tapered_trail(visibility: float, tail_scale: float, visual_scale: float) -> void:
		trail_calls.append([visibility, tail_scale, visual_scale])
		super._draw_tapered_trail(visibility, tail_scale, visual_scale)

	func _draw_fragment_sparks(radius: float, visibility: float) -> void:
		spark_calls.append([radius, visibility])
		super._draw_fragment_sparks(radius, visibility)


var failures: Array[String] = []
var checked_cases := 0
var getter_cases := 0
var nonempty_trails := 0
var solid_cases := 0
var nonempty_sparks := 0
var skipped_heads := 0
var retained_heads := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var meteor := Recorder.new()
	meteor.gate = self
	root.add_child(meteor)
	meteor.set_process(false)
	meteor.set_physics_process(false)
	meteor.armed = true
	meteor.queue_redraw()
	# A callback error must not fall through to PASS, even on dummy rendering.
	for frame in range(4):
		await process_frame
		if meteor.completed:
			break
	_check(meteor.completed and meteor.callback_count == 1, "all cases completed in a real draw callback")
	_check(checked_cases == 539, "all 539 declared render cases ran")
	_check(getter_cases == 264, "all 264 direct-mutation getter cases ran")
	_check(nonempty_trails > 280 and nonempty_sparks > 20, "ribbon and fragment geometry were actually exercised")
	_check(solid_cases == 147, "all three solid bodies render without meteor tails")
	_check(skipped_heads > 0 and retained_heads > 0, "both sides of the first-sample threshold ran")
	meteor.free()
	_test_alternating_weights()
	_test_asteroid_fractures()
	if failures.is_empty():
		print("METEOR_RENDER_CACHE_PASS: 539 ribbon/draw cases with exact geometry, 264 getter mutations, 11 types, fragment sparks and closed asteroid fractures")
		quit(0)
	else:
		print("METEOR_RENDER_CACHE_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _run_cases_in_draw(meteor: Recorder) -> void:
	var cases := _build_cases()
	_check(cases.size() == 539, "declared matrix size")
	for test_case in cases:
		_apply_case(meteor, test_case)
		var label := "%s/%s" % [meteor.type_id, test_case.label]
		var before := _gameplay_state(meteor)
		var reference := _reference_trail(meteor)
		var expected_sparks := _reference_sparks(meteor)
		meteor.render_once()
		_check(_same_bytes(meteor.trail_glow_ribbon, reference.glow), label + ": exact glow coordinates")
		_check(_same_bytes(meteor.trail_core_ribbon, reference.core), label + ": exact core coordinates")
		if meteor.type_id in ["common", "fast"]:
			_check_train_light(meteor, label)
		else:
			_check(_same_bytes(meteor.trail_glow_ribbon_colors, reference.glow_colors), label + ": exact glow colors")
			_check(_same_bytes(meteor.trail_core_ribbon_colors, reference.core_colors), label + ": exact core colors")
		if not reference.glow.is_empty():
			nonempty_trails += 1
			_check(_same_bytes(meteor.trail_strip_indices, reference.indices), label + ": exact triangle indices")
			_check(meteor.trail_strip_point_count == reference.station_count, label + ": strip cache station count")
			if reference.skipped_head:
				skipped_heads += 1
			else:
				retained_heads += 1
		var expected_calls: Array = []
		if meteor.type_id in ["variable_star", "binary_star", "galaxy"]:
			solid_cases += 1
		elif meteor.trail_points.size() > 1:
			expected_calls.append([_trail_visibility(meteor), _reference_tail_scale(meteor), meteor.observation_visual_scale])
		_check(meteor.trail_calls == expected_calls, label + ": production draw routes current burn/linger values")
		if meteor.type_id == "fragment":
			_check(meteor.spark_calls == [[_reference_radius(meteor), _head_visibility(meteor)]], label + ": fragment draw arguments")
			_check(_same_bytes(meteor.debris_draw_points, expected_sparks), label + ": exact fragment spark coordinates")
			if not expected_sparks.is_empty():
				nonempty_sparks += 1
		else:
			_check(meteor.spark_calls.is_empty(), label + ": no fragment spark call for other types")
		_check(_gameplay_state(meteor) == before, label + ": drawing does not mutate gameplay")
		_check_getters(meteor, label)
		checked_cases += 1
	_test_getter_mutations(meteor)
	# Guard the exact comparator: a small representable coordinate/color change
	# must not be admitted by an approximate-equality test or an empty oracle.
	_check(not _same_bytes(PackedVector2Array([Vector2(1.0, 2.0)]), PackedVector2Array([Vector2(1.00001, 2.0)])), "coordinate comparison rejects tiny mutations")
	_check(not _same_bytes(PackedColorArray([Color(0.5, 0.5, 0.5, 0.5)]), PackedColorArray([Color(0.5, 0.5, 0.5, 0.50001)])), "color comparison rejects tiny mutations")
	RenderingServer.canvas_item_clear(meteor.get_canvas_item())


func _test_alternating_weights() -> void:
	var target := Meteor.new()
	target._ensure_trail_station_weights(28)
	var first := target.trail_station_weights.to_byte_array()
	target._ensure_trail_station_weights(29)
	var second := target.trail_station_weights.to_byte_array()
	for i in 32:
		target._ensure_trail_station_weights(28 if i % 2 == 0 else 29)
		_check(target.trail_station_weights.to_byte_array() == (first if i % 2 == 0 else second), "alternating weights retain exact bytes")
	_check(target.trail_weight_build_count == 2, "N/N+1 reuse must stop coefficient builds after warmup")
	target._ensure_trail_station_weights(3)
	_check(target.trail_weight_build_count == 3 and target.trail_station_weights.size() == 15, "shrinking builds a new bounded entry")
	target._ensure_trail_station_weights(29)
	_check(target.trail_weight_build_count == 3 and target.trail_station_weights.to_byte_array() == second, "shrink preserves the most recent other entry")
	target.free()


func _check_train_light(meteor: Recorder, label: String) -> void:
	var glow := meteor.trail_glow_ribbon_colors
	var core := meteor.trail_core_ribbon_colors
	_check(glow.size() == meteor.trail_glow_ribbon.size() and core.size() == meteor.trail_core_ribbon.size(), label + ": one color per vertex")
	var visibility := _trail_visibility(meteor)
	for index in core.size():
		for color in [glow[index], core[index]]:
			_check(is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a), label + ": finite wake light")
			_check(color.a >= 0.0 and color.a <= visibility, label + ": wake follows burn and linger opacity")
		if index % 3 != 1:
			_check(glow[index].a == 0.0 and core[index].a <= core[index - index % 3 + 1].a, label + ": light softens across ribbon edges")
	if core.size() >= 6:
		_check(core[1].a > 0.0 if visibility > 0.0 else core[1].a == 0.0, label + ": visible head join survives")
		_check(core[core.size() - 2].a == 0.0, label + ": far end fades out")
		if visibility > 0.0:
			_check(glow[1].a < core[1].a, label + ": wake halo stays below its leading core")


func _test_asteroid_fractures() -> void:
	var target := Meteor.new()
	# An asymmetric crust independent of the production outline formula.
	var contour := PackedVector2Array([Vector2(-0.8, -0.4), Vector2(-0.3, -0.9), Vector2(0.6, -0.7), Vector2(0.9, 0.0), Vector2(0.5, 0.8), Vector2(-0.2, 0.6), Vector2(-0.7, 0.8)])
	for radius in [18.0, 75.0]:
		for angle in [-1.3, 0.0, 2.2]:
			target.wobble_phase = angle + 0.7
			var outline := PackedVector2Array()
			for point in contour: outline.append(point.rotated(angle) * radius)
			var area := _polygon_area(outline)
			for count in [7, 9]:
				var cells := target._asteroid_fracture_cells(outline, radius, angle, count)
				var total := 0.0
				_check(cells.size() == count, "fracture retains every requested chunk")
				for index in cells.size():
					var cell := cells[index]
					for point in cell: _check(point.is_finite(), "fracture vertices remain finite")
					_check(not Geometry2D.triangulate_polygon(cell).is_empty(), "fracture chunk is drawable")
					var cell_area := _polygon_area(cell)
					_check(cell_area > 0.001, "fracture chunk has positive area")
					total += cell_area
					for other in range(index):
						for overlap in Geometry2D.intersect_polygons(cell, cells[other]):
							_check(_polygon_area(overlap) <= area * 0.0001, "fracture chunks do not overlap")
				_check(absf(total - area) <= area * 0.0001, "fracture chunks cover the original crust without holes")
	target.free()


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in polygon.size():
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(area) * 0.5


func _build_cases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ages := [0.0, 0.1799, 0.5799, 0.58, 0.5801, 0.68, 0.86, 0.9999]
	var age_counts := [2, 7, 28, 56, 17, 3, 28, 56]
	for type_index in range(TYPES.size()):
		for path in ["straight", "curved", "stationary"]:
			for age_index in range(ages.size()):
				result.append({"type_index": type_index, "label": "%s/age%d" % [path, age_index], "path": path, "ratio": ages[age_index], "count": age_counts[age_index], "scale": 1.0 if age_index % 2 == 0 else sqrt(1.4774554)})
		# Reuse the same instance while the visible count grows, shrinks, empties,
		# then returns. Age-based tail truncation adds different station counts.
		var counts := [0, 1, 2, 3, 8, 28, 56, 82, 100, 28, 8, 3, 2, 1, 0, 28]
		for index in range(counts.size()):
			result.append({"type_index": type_index, "label": "count%d" % index, "path": "curved", "ratio": 0.43, "count": counts[index]})
		for first_offset in [0.499, 0.5, 0.501]:
			result.append({"type_index": type_index, "label": "head%s" % first_offset, "path": "straight", "ratio": 0.46, "count": 28, "first_offset": first_offset})
		for succeeded in [false, true]:
			for linger in [0.0, 0.37, 1.0]:
				result.append({"type_index": type_index, "label": "linger%s/%s" % [succeeded, linger], "path": "curved", "ratio": 0.9999, "count": 28, "alive": false, "succeeded": succeeded, "linger": linger})
	return result


func _apply_case(meteor: Recorder, test_case: Dictionary) -> void:
	var type_index := int(test_case.type_index)
	# Deliberately do not call configure: direct public-field changes must be
	# visible immediately, without a setter or process tick invalidating caches.
	meteor.type_id = TYPES[type_index]
	meteor.burn_style = STYLES[type_index]
	meteor.visible_lifetime = 4.125 + float(type_index) * 0.73
	meteor.age = float(test_case.ratio) * meteor.visible_lifetime
	meteor.burn_fade_start = 0.68
	meteor.split_progress = 0.58
	meteor.body_radius = 7.0 + float(type_index) * 1.25
	meteor.wobble_phase = 1.23456789 + float(type_index) * 0.13
	meteor.primary_color = Color(0.91, 0.68, 0.42, 0.77)
	meteor.glow_color = Color(0.23, 0.49, 0.87, 0.66)
	meteor.observation_visual_scale = float(test_case.get("scale", 1.0))
	meteor.alive = bool(test_case.get("alive", true))
	meteor.observed_successfully = bool(test_case.get("succeeded", false))
	meteor.linger_duration = 1.1 if meteor.type_id == "major" else 0.62
	meteor.linger_time = float(test_case.get("linger", 1.0)) * meteor.linger_duration
	meteor.position = Vector2(317.25, 246.5)
	meteor.travel_direction = Vector2.ZERO if test_case.path == "stationary" else Vector2(0.93, 0.37)
	meteor.velocity = Vector2(231.75, 61.125)
	meteor.observation_progress = 0.413
	meteor.base_automatic_rate = 0.0
	meteor.trail_points.clear()
	var first_offset := float(test_case.get("first_offset", 0.0))
	for index in range(int(test_case.count)):
		var offset := Vector2(-first_offset - float(index) * 8.3, 0.0)
		if test_case.path == "curved":
			offset.y = sin(float(index) * 0.36) * 13.0 + float(index) * 0.7
		elif test_case.path == "stationary":
			offset = Vector2.ZERO
		meteor.trail_points.append(meteor.global_position + offset)


func _gameplay_state(meteor: Recorder) -> Array:
	return [meteor.type_id, meteor.age, meteor.visible_lifetime, meteor.position, meteor.velocity, meteor.alive, meteor.observed_successfully, meteor.observation_progress, meteor.split_done, meteor.linger_time, meteor.trail_points.duplicate()]


func _check_getters(meteor: Recorder, label: String) -> void:
	_check(meteor.get_burn_progress() == _reference_progress(meteor), label + ": immediate burn progress")
	_check(meteor.get_burn_visibility() == _reference_visibility(meteor), label + ": immediate burn visibility")
	_check(meteor.get_burn_tail_scale() == _reference_tail_scale(meteor), label + ": immediate tail scale")
	_check(meteor.get_progress() == clampf(meteor.observation_progress, 0.0, 1.0), label + ": immediate observation progress")


func _test_getter_mutations(meteor: Recorder) -> void:
	for type_index in range(TYPES.size()):
		meteor.type_id = TYPES[type_index]
		meteor.burn_style = STYLES[type_index]
		for lifetime in [-2.0, 0.0, 0.0001, 0.001, 0.25, 7.0]:
			meteor.visible_lifetime = lifetime
			for next_age in [-1.0, 0.0005, 2.0, 10.0]:
				meteor.age = next_age
				meteor.observation_progress = next_age
				_check_getters(meteor, "mutation/%s/%s/%s" % [meteor.type_id, lifetime, next_age])
				getter_cases += 1


func _reference_progress(meteor: Recorder) -> float:
	return clampf(meteor.age / maxf(meteor.visible_lifetime, 0.001), 0.0, 1.0)


func _reference_visibility(meteor: Recorder) -> float:
	var progress := _reference_progress(meteor)
	var ignition := lerpf(0.82, 1.0, smoothstep(0.0, 0.22, progress))
	var fade := smoothstep(meteor.burn_fade_start, 1.0, progress)
	var brightness := ignition * lerpf(1.0, 0.10, fade)
	match meteor.burn_style:
		"flare":
			var flicker_amount := 0.11 * smoothstep(0.28, 0.82, progress)
			brightness *= 1.0 + sin(meteor.age * 14.0 + meteor.wobble_phase) * flicker_amount
			var flare_distance := (progress - 0.86) / 0.055
			brightness += 0.65 * exp(-flare_distance * flare_distance)
		"split":
			var instability := smoothstep(0.25, meteor.split_progress, progress)
			brightness *= 1.0 + sin(meteor.age * 18.0 + meteor.wobble_phase) * 0.10 * instability
		"spark":
			brightness *= 1.0 + sin(meteor.age * 20.0 + meteor.wobble_phase) * 0.07
		"major":
			brightness *= 1.0 + sin(meteor.age * 6.0 + meteor.wobble_phase) * 0.04
		"satellite":
			brightness *= 0.78 + 0.22 * smoothstep(-0.2, 0.8, sin(meteor.age * 4.5 + meteor.wobble_phase))
		"comet":
			brightness *= 1.0 + 0.08 * sin(meteor.age * 5.0 + meteor.wobble_phase)
	if progress <= meteor.burn_fade_start:
		brightness = maxf(0.78, brightness)
	return maxf(0.10, brightness)


func _reference_tail_scale(meteor: Recorder) -> float:
	var tail_fade_start := maxf(0.0, meteor.burn_fade_start - 0.10)
	return lerpf(1.0, 0.16, smoothstep(tail_fade_start, 1.0, _reference_progress(meteor)))


func _trail_visibility(meteor: Recorder) -> float:
	var linger_alpha := 1.0 if meteor.alive else clampf(meteor.linger_time / maxf(meteor.linger_duration, 0.001), 0.0, 1.0)
	if not meteor.alive and not meteor.observed_successfully:
		linger_alpha *= 0.12
	return _reference_visibility(meteor) * _reference_tail_scale(meteor) * linger_alpha


func _head_visibility(meteor: Recorder) -> float:
	var visibility := _reference_visibility(meteor)
	if not meteor.alive:
		visibility = clampf(meteor.linger_time / maxf(meteor.linger_duration, 0.001), 0.0, 1.0)
		if not meteor.observed_successfully:
			visibility *= 0.12
	return visibility


func _reference_radius(meteor: Recorder) -> float:
	var success_bloom := 1.0
	if meteor.observed_successfully:
		success_bloom = 1.0 + (1.0 - _head_visibility(meteor)) * (1.15 if meteor.type_id == "major" else 0.72)
	var pulse_amount := 0.06
	if meteor.burn_style == "split":
		pulse_amount += 0.08 * smoothstep(0.25, meteor.split_progress, _reference_progress(meteor))
	elif meteor.burn_style == "snap":
		pulse_amount = 0.035
	var pulse := 1.0 + sin(meteor.age * 13.0 + meteor.wobble_phase) * pulse_amount
	return meteor.body_radius * meteor.observation_visual_scale * pulse * success_bloom * HEAD_SCALES[TYPES.find(meteor.type_id)]


func _reference_head_profile(type_id: String) -> PackedFloat32Array:
	match type_id:
		"fast": return PackedFloat32Array([1.10, 1.06, 0.34, 1.48, 1.57, 0.60])
		"fragment": return PackedFloat32Array([0.88, 0.85, 0.78, 1.18, 1.25, 1.08])
		"fragment_piece": return PackedFloat32Array([1.02, 0.98, 0.42, 1.42, 1.51, 0.66])
		"fireball": return PackedFloat32Array([0.96, 0.92, 0.72, 1.34, 1.42, 1.12])
		"major": return PackedFloat32Array([1.04, 1.00, 0.78, 1.50, 1.59, 1.20])
		"comet": return PackedFloat32Array([0.76, 0.73, 0.62, 1.05, 1.11, 0.98])
		"satellite", "variable_star", "binary_star", "galaxy": return PackedFloat32Array()
		_: return PackedFloat32Array([0.82, 0.79, 0.66, 1.12, 1.19, 1.06])


func _reference_direction(meteor: Recorder) -> Vector2:
	if meteor.travel_direction.is_zero_approx():
		return Vector2.RIGHT
	return meteor.travel_direction.normalized()


func _reference_normal(meteor: Recorder, stations: PackedVector2Array, index: int) -> Vector2:
	var count := stations.size()
	var tangent: Vector2
	if index <= 0:
		tangent = stations[0] - stations[1]
	elif index >= count - 1:
		tangent = stations[count - 2] - stations[count - 1]
	else:
		tangent = stations[index - 1] - stations[index + 1]
	if tangent.is_zero_approx():
		tangent = _reference_direction(meteor)
	else:
		tangent = tangent.normalized()
	return Vector2(-tangent.y, tangent.x)


func _reference_trail(meteor: Recorder) -> Dictionary:
	var result := {"glow": PackedVector2Array(), "core": PackedVector2Array(), "glow_colors": PackedColorArray(), "core_colors": PackedColorArray(), "indices": PackedInt32Array(), "station_count": 0, "skipped_head": false}
	if meteor.type_id in ["variable_star", "binary_star", "galaxy"] or meteor.trail_points.size() <= 1:
		return result
	var tail_scale := _reference_tail_scale(meteor)
	var visibility := _trail_visibility(meteor)
	var visual_scale := meteor.observation_visual_scale
	var point_count := mini(meteor.trail_points.size(), maxi(2, ceili(float(meteor.trail_points.size()) * maxf(0.16, tail_scale))))
	if point_count < 2:
		return result
	var stations := PackedVector2Array()
	stations.append(Vector2.ZERO)
	for index in range(point_count):
		var offset := meteor.trail_points[index] - meteor.global_position
		if index == 0 and offset.length_squared() < 0.25:
			result.skipped_head = true
			continue
		stations.append(offset)
	var station_count := stations.size()
	result.station_count = station_count
	if station_count < 2:
		return result
	var type_index := TYPES.find(meteor.type_id)
	var widths: Vector2 = WIDTHS[type_index] * visual_scale
	var shoulder := Vector2.ZERO
	var profile := _reference_head_profile(meteor.type_id)
	if profile.size() >= 6:
		var head_radius: float = meteor.body_radius * visual_scale * HEAD_SCALES[type_index]
		var head_core := head_radius * profile[2]
		shoulder = Vector2(maxf(0.0, head_core - widths.x), maxf(0.0, head_core * 0.34 - widths.y))
	var core_floor := 1.15 * 0.7
	for index in range(station_count):
		var t := float(index) / float(maxi(1, station_count - 1))
		var remaining := maxf(0.0, 1.0 - t)
		var taper := pow(remaining, 0.78)
		var flare := pow(remaining, 7.5)
		var glow_width := widths.x * taper + shoulder.x * flare
		var core_width := widths.y * taper + shoulder.y * flare
		var normal := _reference_normal(meteor, stations, index)
		var local_point := stations[index]
		var alpha := pow(remaining, 1.28) * visibility
		var turbulence_profile: Vector2 = TURBULENCE[type_index]
		var turbulence := sin(meteor.wobble_phase + meteor.age * turbulence_profile.y - t * 8.7) * turbulence_profile.x * smoothstep(0.0, 0.24, t)
		var glow_centre := Color(meteor.glow_color, alpha * 0.34)
		var glow_edge := Color(meteor.glow_color, 0.0)
		var core_centre := Color(meteor.primary_color, alpha * 0.86)
		var core_edge := Color(meteor.primary_color, alpha * 0.10)
		result.glow.append(local_point + normal * maxf(1.15, glow_width * (1.0 + turbulence)))
		result.glow.append(local_point)
		result.glow.append(local_point - normal * maxf(1.15, glow_width * (1.0 - turbulence * 0.68)))
		result.glow_colors.append(glow_edge)
		result.glow_colors.append(glow_centre)
		result.glow_colors.append(glow_edge)
		result.core.append(local_point + normal * maxf(core_floor, core_width * (1.0 + turbulence * 0.38)))
		result.core.append(local_point)
		result.core.append(local_point - normal * maxf(core_floor, core_width * (1.0 - turbulence * 0.26)))
		result.core_colors.append(core_edge)
		result.core_colors.append(core_centre)
		result.core_colors.append(core_edge)
	for segment in range(station_count - 1):
		var base := segment * 3
		for side: int in [0, 1]:
			var near: int = base + side
			var far: int = base + side + 1
			result.indices.append(near)
			result.indices.append(far)
			result.indices.append(near + 3)
			result.indices.append(far)
			result.indices.append(far + 3)
			result.indices.append(near + 3)
	return result


func _reference_sparks(meteor: Recorder) -> PackedVector2Array:
	var result := PackedVector2Array()
	if meteor.type_id != "fragment":
		return result
	var visibility := _head_visibility(meteor)
	var split_visibility := smoothstep(0.18, meteor.split_progress, _reference_progress(meteor)) * visibility
	if split_visibility <= 0.001:
		return result
	var radius := _reference_radius(meteor)
	var direction := _reference_direction(meteor)
	var normal := Vector2(-direction.y, direction.x)
	for index in range(3):
		var sequence := float(index)
		var spark_phase := meteor.wobble_phase + meteor.age * (8.5 + sequence) + sequence * 2.37
		var profile := _reference_head_profile(meteor.type_id)
		var envelope := radius * profile[2]
		var center := (
			-direction * radius * (0.72 + sequence * 0.48)
			+ normal * envelope * sin(spark_phase) * (0.30 - sequence * 0.06)
		)
		var shard_direction := (direction + normal * 0.14 * sin(spark_phase + 0.8)).normalized()
		var shard_length := radius * (0.16 + sequence * 0.035)
		result.append(center - shard_direction * shard_length)
		result.append(center + shard_direction * shard_length * 0.52)
	return result


func _same_bytes(actual: Variant, expected: Variant) -> bool:
	return typeof(actual) == typeof(expected) and actual.to_byte_array() == expected.to_byte_array()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("METEOR_RENDER_CACHE: " + message)
