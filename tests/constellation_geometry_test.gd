extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var chart = load("res://scripts/upgrade_tree.gd").new()
	chart._cache_chart_geometry()
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/research-stars.json")).stars
	var maximum_error := 0.0
	var total := 0
	for cid in chart.chart_constellations:
		var stars: Array = chart.chart_constellations[cid].stars
		var sky: Array[Vector3] = []
		var points: Array[Vector2] = []
		var center := Vector3.ZERO
		for star in stars:
			var key: String = cid + "/" + star.id
			_check(catalogue.has(key), "missing catalogue star: " + key)
			var record: Dictionary = catalogue[key]
			var ra := deg_to_rad(float(record.ra))
			var dec := deg_to_rad(float(record.dec))
			var direction := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
			sky.append(direction)
			center += direction
			points.append(chart.base_star_positions[key])
			total += 1
		center = center.normalized()
		var diameter := 0.0
		var angular_diameter := 0.0
		for a in stars.size():
			for b in range(a + 1, stars.size()):
				diameter = maxf(diameter, points[a].distance_to(points[b]))
				angular_diameter = maxf(angular_diameter, sky[a].angle_to(sky[b]))
		for a in stars.size():
			for b in range(a + 1, stars.size()):
				# Independent great-circle reference, not the generator's projection.
				# A flat figure has modest projection distortion, especially Draco.
				var error := absf(points[a].distance_to(points[b]) / diameter - sky[a].angle_to(sky[b]) / angular_diameter)
				maximum_error = maxf(maximum_error, error)
				_check(error < 0.025, "relative star spacing: " + cid)
				for c in range(b + 1, stars.size()):
					var sky_area := (sky[b] - sky[a]).cross(sky[c] - sky[a]).dot(center)
					if absf(sky_area) < 0.000001: continue
					var chart_area := (points[b] - points[a]).cross(points[c] - points[a])
					_check(sky_area * chart_area > 0.0, "mirrored figure: " + cid)
	_check(total == 169 and catalogue.size() == 169, "all 25 figures and shared markers are covered")
	var original: Dictionary = chart.base_star_positions.duplicate()
	_check(chart._chart_source_positions() == original, "unexpanded chart retains its original presentation")
	chart.galactic_unlocked = true
	var expanded: Dictionary = chart._chart_source_positions().duplicate()
	for cid in chart.chart_constellations:
		var stars: Array = chart.chart_constellations[cid].stars
		var scale_amount: float = 1.0 if cid in chart.ExtensionChart.ORDER else chart.COMPLETED_FIGURE_SCALE
		for a in stars.size():
			for b in range(a + 1, stars.size()):
				var key_a: String = cid + "/" + stars[a].id
				var key_b: String = cid + "/" + stars[b].id
				var expected: Vector2 = (original[key_a] - original[key_b]) * scale_amount
				_check(expected.distance_to(expanded[key_a] - expanded[key_b]) < 0.001, "expansion preserves every relative vector: " + cid)
	_check(Vector2(expanded["pegasus/alpheratz"]).is_equal_approx(expanded["andromeda/alpheratz"]), "shrinking Andromeda keeps the complete Pegasus attached")
	chart._cache_chart_geometry()
	_check(chart.base_star_positions == original and chart._chart_source_positions() == expanded, "rebuilding cannot accumulate shrink or shared-corner translation")
	chart.galactic_unlocked = false
	_check(chart._chart_source_positions() == original, "loading an unexpanded save restores full-size legacy figures")
	for cid in ["pegasus", "ursa_minor"]:
		var figure: Dictionary = chart.chart_constellations[cid]
		for a in figure.segments.size():
			for b in range(a + 1, figure.segments.size()):
				var one: Array = figure.segments[a]
				var two: Array = figure.segments[b]
				if one[0] in two or one[1] in two: continue
				var crossing = Geometry2D.segment_intersects_segment(chart.base_star_positions[cid + "/" + one[0]], chart.base_star_positions[cid + "/" + one[1]], chart.base_star_positions[cid + "/" + two[0]], chart.base_star_positions[cid + "/" + two[1]])
				_check(crossing == null, "crossed square/bowl: " + cid)
	_test_readable_spacing(chart)
	chart.free()
	for failure in failures: push_error(failure)
	print("CONSTELLATION_GEOMETRY_%s: 25 figures / 169 markers, maximum normalized angular-spacing error %.5f" % ["PASS" if failures.is_empty() else "FAIL", maximum_error])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)


func _test_readable_spacing(chart) -> void:
	var largest_shift := 0.0
	var affected := {}
	for expanded in [false, true]:
		chart.galactic_unlocked = expanded
		for scale_amount in [0.34, 0.43, 0.636, 1.0, 1.28]:
			chart.zoom = scale_amount
			var original: Dictionary = chart._chart_source_positions().duplicate()
			var positions: Dictionary = chart._readable_chart_positions().duplicate()
			for cid in chart.chart_constellations:
				var stars: Array = chart.chart_constellations[cid].stars
				for a in stars.size():
					var key: String = cid + "/" + stars[a].id
					var shift: float = Vector2(positions[key]).distance_to(original[key]) * scale_amount
					largest_shift = maxf(largest_shift, shift)
					if shift > 0.01: affected[cid] = true
					_check(shift < 36.0, "readability correction stays local: " + key)
					for b in range(a + 1, stars.size()):
						var distance: float = Vector2(positions[key]).distance_to(positions[cid + "/" + stars[b].id]) * scale_amount
						_check(distance >= chart.MIN_STAR_SCREEN_SEPARATION - 0.05, "readable spacing at every zoom: " + key + "/" + stars[b].id)
				if cid in ["pegasus", "ursa_minor"]:
					var segments: Array = chart.chart_constellations[cid].segments
					for a in segments.size():
						for b in range(a + 1, segments.size()):
							var one: Array = segments[a]
							var two: Array = segments[b]
							if one[0] in two or one[1] in two: continue
							_check(Geometry2D.segment_intersects_segment(positions[cid + "/" + one[0]], positions[cid + "/" + one[1]], positions[cid + "/" + two[0]], positions[cid + "/" + two[1]]) == null, "readability keeps square/bowl connections uncrossed: " + cid)
			_check(positions["pegasus/alpheratz"] == positions["andromeda/alpheratz"], "readable Alpheratz remains one marker")
			var keys: Array[String] = []
			for cid in chart.chart_constellations:
				if cid in chart.ExtensionChart.ORDER and not expanded: continue
				for star in chart.chart_constellations[cid].stars:
					if not star.has("shared_star_key"): keys.append(cid + "/" + star.id)
			for a in keys.size():
				for b in range(a + 1, keys.size()):
					var distance: float = Vector2(positions[keys[a]]).distance_to(positions[keys[b]]) * scale_amount
					_check(distance >= chart.MIN_STAR_SCREEN_SEPARATION - 0.05, "spacing also separates different constellations: " + keys[a] + "/" + keys[b])
			_check(chart._chart_source_positions() == original, "spacing never changes catalogue/layout source")
			chart.rotation_offset += 0.5
			_check(chart._readable_chart_positions() == positions, "rotation and repeated layout cannot shuffle close stars")
	print("READABLE_SPACING: %d figures adjusted, maximum screen displacement %.2f px" % [affected.size(), largest_shift])
