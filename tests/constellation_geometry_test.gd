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
	_check(total == 139 and catalogue.size() == 139, "all 21 figures and shared markers are covered")
	for cid in ["pegasus", "ursa_minor"]:
		var figure: Dictionary = chart.chart_constellations[cid]
		for a in figure.segments.size():
			for b in range(a + 1, figure.segments.size()):
				var one: Array = figure.segments[a]
				var two: Array = figure.segments[b]
				if one[0] in two or one[1] in two: continue
				var crossing = Geometry2D.segment_intersects_segment(chart.base_star_positions[cid + "/" + one[0]], chart.base_star_positions[cid + "/" + one[1]], chart.base_star_positions[cid + "/" + two[0]], chart.base_star_positions[cid + "/" + two[1]])
				_check(crossing == null, "crossed square/bowl: " + cid)
	chart.free()
	for failure in failures: push_error(failure)
	print("CONSTELLATION_GEOMETRY_%s: 21 figures / 139 markers, maximum normalized angular-spacing error %.5f" % ["PASS" if failures.is_empty() else "FAIL", maximum_error])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
