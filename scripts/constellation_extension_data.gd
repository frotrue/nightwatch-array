extends RefCounted

# Stylized figure geometry, not an equatorial coordinate projection. Figure
# membership/Bayer labels follow the IAU charts linked in expansion-design.md.
# Alpheratz is the SAME existing Andromeda star at the shared Pegasus corner.
const ORDER := ["pegasus", "cygnus", "cepheus", "aquila"]
const COLORS := {
	"pegasus": Color("D4DAE5"), "cygnus": Color("8BB8D5"),
	"cepheus": Color("D9C78E"), "aquila": Color("C7A6C5"),
}
const CONSTELLATIONS := {
	"pegasus": {
		"label_key": "ATLAS_PEGASUS", "branch": "pegasus",
		"stars": [
			{"id": "alpheratz", "name_key": "STAR_ALPHERATZ", "bayer": "α And", "local_position": Vector2(0, 0), "shared_star_key": "andromeda/alpheratz", "node_id": "", "kind": "star", "magnitude": 3.0},
			{"id": "markab", "name_key": "ATLAS_MARKAB", "bayer": "α Peg", "local_position": Vector2(-1.0, -0.7), "node_id": "ext_protocol", "kind": "star", "magnitude": 3.0},
			{"id": "scheat", "name_key": "ATLAS_SCHEAT", "bayer": "β Peg", "local_position": Vector2(-1.0, 1.1), "node_id": "ext_synthesis", "kind": "star", "magnitude": 3.0},
			{"id": "algenib", "name_key": "ATLAS_ALGENIB", "bayer": "γ Peg", "local_position": Vector2(0.8, 1.1), "node_id": "ext_combined_watch", "kind": "star", "magnitude": 3.0},
			{"id": "homam", "name_key": "ATLAS_HOMAM", "bayer": "ζ Peg", "local_position": Vector2(-1.65, 0.0), "node_id": "slot_5", "kind": "star", "magnitude": 3.0},
			{"id": "enif", "name_key": "ATLAS_ENIF", "bayer": "ε Peg", "local_position": Vector2(-2.6, -0.35), "node_id": "ext_record_complete", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpheratz", "markab"], ["markab", "scheat"], ["scheat", "algenib"], ["algenib", "alpheratz"], ["markab", "homam"], ["homam", "enif"]],
	},
	"cygnus": {
		"label_key": "ATLAS_CYGNUS", "branch": "cygnus",
		"stars": [
			{"id": "deneb", "name_key": "ATLAS_DENEB", "bayer": "α Cyg", "local_position": Vector2(0.0, -1.0), "node_id": "ext_trace_study", "kind": "star", "magnitude": 3.0},
			{"id": "sadr", "name_key": "ATLAS_SADR", "bayer": "γ Cyg", "local_position": Vector2(0.0, -0.15), "node_id": "focus", "kind": "star", "magnitude": 3.0},
			{"id": "albireo", "name_key": "ATLAS_ALBIREO", "bayer": "β Cyg", "local_position": Vector2(0.05, 1.35), "node_id": "precision", "kind": "star", "magnitude": 3.0},
			{"id": "gienah", "name_key": "ATLAS_GIENAH", "bayer": "ε Cyg", "local_position": Vector2(1.0, 0.25), "node_id": "ext_trace_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "delta_cyg", "name_key": "ATLAS_DELTA_CYG", "bayer": "δ Cyg", "local_position": Vector2(-1.05, 0.12), "node_id": "slot_3", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["deneb", "sadr"], ["sadr", "albireo"], ["sadr", "gienah"], ["sadr", "delta_cyg"]],
	},
	"cepheus": {
		"label_key": "ATLAS_CEPHEUS", "branch": "cepheus",
		"stars": [
			{"id": "alderamin", "name_key": "ATLAS_ALDERAMIN", "bayer": "α Cep", "local_position": Vector2(-0.85, 0.8), "node_id": "ext_link_study", "kind": "star", "magnitude": 3.0},
			{"id": "alfirk", "name_key": "ATLAS_ALFIRK", "bayer": "β Cep", "local_position": Vector2(-0.9, -0.2), "node_id": "record", "kind": "star", "magnitude": 3.0},
			{"id": "errai", "name_key": "ATLAS_ERRAI", "bayer": "γ Cep", "local_position": Vector2(0.0, -1.15), "node_id": "revisit", "kind": "star", "magnitude": 3.0},
			{"id": "iota_cep", "name_key": "ATLAS_IOTA_CEP", "bayer": "ι Cep", "local_position": Vector2(0.8, -0.2), "node_id": "ext_link_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "zeta_cep", "name_key": "ATLAS_ZETA_CEP", "bayer": "ζ Cep", "local_position": Vector2(0.75, 0.9), "node_id": "slot_4", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alderamin", "alfirk"], ["alfirk", "errai"], ["errai", "iota_cep"], ["iota_cep", "zeta_cep"], ["zeta_cep", "alderamin"]],
	},
	"aquila": {
		"label_key": "ATLAS_AQUILA", "branch": "aquila",
		"stars": [
			{"id": "altair", "name_key": "ATLAS_ALTAIR", "bayer": "α Aql", "local_position": Vector2(0.0, -0.45), "node_id": "ext_sweep_study", "kind": "star", "magnitude": 3.0},
			{"id": "tarazed", "name_key": "ATLAS_TARAZED", "bayer": "γ Aql", "local_position": Vector2(-0.65, -0.85), "node_id": "wide", "kind": "star", "magnitude": 3.0},
			{"id": "alshain", "name_key": "ATLAS_ALSHAIN", "bayer": "β Aql", "local_position": Vector2(0.6, -0.05), "node_id": "ext_sweep_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "delta_aql", "name_key": "", "bayer": "δ Aql", "local_position": Vector2(-0.75, 0.45), "node_id": "", "kind": "star", "magnitude": 3.0},
			{"id": "theta_aql", "name_key": "", "bayer": "θ Aql", "local_position": Vector2(0.7, 1.1), "node_id": "", "kind": "star", "magnitude": 3.0},
			{"id": "zeta_aql", "name_key": "", "bayer": "ζ Aql", "local_position": Vector2(-1.4, -0.5), "node_id": "", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["tarazed", "altair"], ["altair", "alshain"], ["altair", "delta_aql"], ["delta_aql", "theta_aql"], ["delta_aql", "zeta_aql"]],
	},
}
const PLACEMENTS := {
	"pegasus": {"anchor_angle": 2.879, "anchor_radius": 713.86, "scale": 115.0, "tilt": 0.0},
	"cygnus": {"anchor_angle": 2.247, "anchor_radius": 846.46, "scale": 112.0, "tilt": -0.32},
	"cepheus": {"anchor_angle": 1.681, "anchor_radius": 905.54, "scale": 102.0, "tilt": -0.25},
	"aquila": {"anchor_angle": 2.449, "anchor_radius": 1065.27, "scale": 100.0, "tilt": 0.10},
}

static func node_star_map() -> Dictionary:
	var result := {}
	for id in ORDER:
		for star in CONSTELLATIONS[id].stars:
			if not String(star.node_id).is_empty():
				result[star.node_id] = {"constellation_id": id, "star": star}
	return result

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ORDER:
		for star in CONSTELLATIONS[id].stars:
			if not String(star.node_id).is_empty():
				result.append({"id": star.node_id, "branch": id})
	return result
