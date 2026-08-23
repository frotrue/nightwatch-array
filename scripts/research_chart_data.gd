extends RefCounted
class_name ResearchChartData

# Presentation-only astronomy data. Local positions preserve the recognizable
# silhouette of each figure without coupling factual star data to screen space.
const CONSTELLATIONS := {
	"cassiopeia": {
		"branch": "optics",
		"label_key": "CONSTELLATION_CASSIOPEIA",
		"stars": [
			{"id": "caph", "name_key": "STAR_CAPH", "bayer": "β Cas", "magnitude": 2.28, "local_position": Vector2(-1.00, -0.12), "node_id": "observation_streak", "kind": "star"},
			{"id": "schedar", "name_key": "STAR_SCHEDAR", "bayer": "α Cas", "magnitude": 2.24, "local_position": Vector2(-0.54, 0.34), "node_id": "perfect_observation", "kind": "star"},
			{"id": "navi", "name_key": "STAR_NAVI", "bayer": "γ Cas", "magnitude": 2.47, "local_position": Vector2(0.00, -0.30), "node_id": "precision_multiplier", "kind": "star"},
			{"id": "ruchbah", "name_key": "STAR_RUCHBAH", "bayer": "δ Cas", "magnitude": 2.68, "local_position": Vector2(0.54, 0.31), "node_id": "long_exposure", "kind": "star"},
			{"id": "segin", "name_key": "STAR_SEGIN", "bayer": "ε Cas", "magnitude": 3.38, "local_position": Vector2(1.00, -0.18), "node_id": "better_lens", "kind": "star"}
		],
		"segments": [["caph", "schedar"], ["schedar", "navi"], ["navi", "ruchbah"], ["ruchbah", "segin"]]
	},
	"big_dipper": {
		"branch": "detection",
		"label_key": "CONSTELLATION_BIG_DIPPER",
		"stars": [
			{"id": "dubhe", "name_key": "STAR_DUBHE", "bayer": "α UMa", "magnitude": 1.79, "local_position": Vector2(-0.96, -0.34), "node_id": "wide_field", "kind": "star"},
			{"id": "merak", "name_key": "STAR_MERAK", "bayer": "β UMa", "magnitude": 2.37, "local_position": Vector2(-0.91, 0.35), "node_id": "trajectory", "kind": "star"},
			{"id": "phecda", "name_key": "STAR_PHECDA", "bayer": "γ UMa", "magnitude": 2.44, "local_position": Vector2(-0.19, 0.55), "node_id": "", "kind": "star"},
			{"id": "megrez", "name_key": "STAR_MEGREZ", "bayer": "δ UMa", "magnitude": 3.31, "local_position": Vector2(-0.08, -0.12), "node_id": "edge_detection", "kind": "star"},
			{"id": "alioth", "name_key": "STAR_ALIOTH", "bayer": "ε UMa", "magnitude": 1.77, "local_position": Vector2(0.55, -0.22), "node_id": "rare_detection", "kind": "star"},
			{"id": "mizar", "name_key": "STAR_MIZAR", "bayer": "ζ UMa", "magnitude": 2.23, "local_position": Vector2(1.10, -0.31), "node_id": "fragment_analysis", "kind": "star"},
			{"id": "alcor", "name_key": "STAR_ALCOR", "bayer": "80 UMa", "magnitude": 3.99, "local_position": Vector2(1.08, -0.43), "node_id": "", "kind": "star"},
			{"id": "alkaid", "name_key": "STAR_ALKAID", "bayer": "η UMa", "magnitude": 1.86, "local_position": Vector2(1.68, -0.50), "node_id": "shower_detector", "kind": "star"}
		],
		"segments": [["dubhe", "merak"], ["merak", "phecda"], ["phecda", "megrez"], ["megrez", "dubhe"], ["megrez", "alioth"], ["alioth", "mizar"], ["mizar", "alkaid"]]
	},
	"orion": {
		"branch": "network",
		"label_key": "CONSTELLATION_ORION",
		"stars": [
			{"id": "meissa", "name_key": "STAR_MEISSA", "bayer": "λ Ori", "magnitude": 3.39, "local_position": Vector2(0.00, -1.08), "node_id": "array_planning", "kind": "star"},
			{"id": "betelgeuse", "name_key": "STAR_BETELGEUSE", "bayer": "α Ori", "magnitude": 0.50, "local_position": Vector2(-0.72, -0.61), "node_id": "thermal_management", "kind": "star"},
			{"id": "bellatrix", "name_key": "STAR_BELLATRIX", "bayer": "γ Ori", "magnitude": 1.64, "local_position": Vector2(0.67, -0.56), "node_id": "observation_scheduling", "kind": "star"},
			{"id": "alnitak", "name_key": "STAR_ALNITAK", "bayer": "ζ Ori", "magnitude": 1.77, "local_position": Vector2(-0.42, -0.02), "node_id": "secondary_camera", "kind": "star"},
			{"id": "alnilam", "name_key": "STAR_ALNILAM", "bayer": "ε Ori", "magnitude": 1.69, "local_position": Vector2(0.00, 0.02), "node_id": "multi_target_analysis", "kind": "star"},
			{"id": "mintaka", "name_key": "STAR_MINTAKA", "bayer": "δ Ori", "magnitude": 2.23, "local_position": Vector2(0.43, 0.05), "node_id": "observatory_network", "kind": "star"},
			{"id": "trapezium", "name_key": "STAR_TRAPEZIUM", "bayer": "θ¹ Ori C", "magnitude": 5.13, "local_position": Vector2(0.02, 0.48), "node_id": "automated_tracking", "kind": "nebula"},
			{"id": "hatysa", "name_key": "STAR_HATYSA", "bayer": "ι Ori", "magnitude": 2.75, "local_position": Vector2(0.03, 0.76), "node_id": "predictive_dish_control", "kind": "star"},
			{"id": "saiph", "name_key": "STAR_SAIPH", "bayer": "κ Ori", "magnitude": 2.06, "local_position": Vector2(-0.62, 1.02), "node_id": "extended_watch_protocol", "kind": "star"},
			{"id": "rigel", "name_key": "STAR_RIGEL", "bayer": "β Ori", "magnitude": 0.13, "local_position": Vector2(0.72, 1.06), "node_id": "continuous_watch_rotation", "kind": "star"}
		],
		"segments": [["meissa", "betelgeuse"], ["meissa", "bellatrix"], ["betelgeuse", "alnitak"], ["bellatrix", "mintaka"], ["alnitak", "alnilam"], ["alnilam", "mintaka"], ["alnitak", "saiph"], ["mintaka", "rigel"], ["alnilam", "trapezium"], ["trapezium", "hatysa"]]
	}
}

# Placement is deliberately separate from factual star data. Anchors are polar
# coordinates around the chart's bottom-centre horizon origin.
const PLACEMENTS := {
	"cassiopeia": {"anchor_angle": -2.36, "anchor_radius": 430.0, "scale": 128.0, "tilt": -0.08},
	"big_dipper": {"anchor_angle": -1.57, "anchor_radius": 395.0, "scale": 142.0, "tilt": 0.02},
	"orion": {"anchor_angle": -0.78, "anchor_radius": 430.0, "scale": 132.0, "tilt": -0.02}
}


static func node_star_map() -> Dictionary:
	var result := {}
	for constellation_id in CONSTELLATIONS:
		var constellation: Dictionary = CONSTELLATIONS[constellation_id]
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var node_id := String(star.get("node_id", ""))
			if not node_id.is_empty():
				result[node_id] = {"constellation_id": constellation_id, "star": star}
	return result


static func validation_errors(expected_node_ids: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	var mapped_counts := {}
	for constellation_id in CONSTELLATIONS:
		if not PLACEMENTS.has(constellation_id):
			errors.append("Missing placement for %s" % constellation_id)
		var constellation: Dictionary = CONSTELLATIONS[constellation_id]
		var star_ids := {}
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var star_id := String(star.get("id", ""))
			if star_id.is_empty() or star_ids.has(star_id):
				errors.append("Invalid or duplicate star id in %s: %s" % [constellation_id, star_id])
			star_ids[star_id] = true
			var node_id := String(star.get("node_id", ""))
			if not node_id.is_empty():
				mapped_counts[node_id] = int(mapped_counts.get(node_id, 0)) + 1
		for segment_variant in constellation.segments:
			var segment: Array = segment_variant
			if segment.size() != 2 or not star_ids.has(String(segment[0])) or not star_ids.has(String(segment[1])):
				errors.append("Invalid segment in %s: %s" % [constellation_id, segment])
	for node_id in expected_node_ids:
		if int(mapped_counts.get(node_id, 0)) != 1:
			errors.append("Expected exactly one star for node %s" % node_id)
	for node_id in mapped_counts:
		if node_id not in expected_node_ids:
			errors.append("Unknown mapped node id %s" % node_id)
	return errors
