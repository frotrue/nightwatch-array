extends RefCounted

# Catalogue-derived silhouettes, using the same projection as the base chart.
# Run tools/project_constellations.py to update positions. Chart anchors remain
# compositional; membership/Bayer labels follow the linked IAU charts.
# Alpheratz is the SAME existing Andromeda star at the shared Pegasus corner.
const ORDER := ["pegasus", "lacerta", "cygnus", "aquila", "vulpecula", "delphinus", "sagitta", "equuleus", "triangulum"]
const COLORS := {
	"aquila": Color("C7A6C5"),
	"pegasus": Color("D4DAE5"), "cygnus": Color("8BB8D5"),
	"lacerta": Color("BFC4A6"),
	"vulpecula": Color("D2B090"),
	"delphinus": Color("99C7C8"),
	"sagitta": Color("D2BA90"),
	"equuleus": Color("A8BACC"),
	"triangulum": Color("BDAACD"),
}
const CONSTELLATIONS := {
	"pegasus": {
		"label_key": "ATLAS_PEGASUS", "branch": "pegasus",
		"stars": [
			{"id": "alpheratz", "name_key": "STAR_ALPHERATZ", "bayer": "α And", "local_position": Vector2(0.0000000, 0.0000000), "shared_star_key": "andromeda/alpheratz", "node_id": "", "kind": "star", "magnitude": 3.0},
			{"id": "markab", "name_key": "ATLAS_MARKAB", "bayer": "α Peg", "local_position": Vector2(0.7205237, 0.7459243), "node_id": "ext_protocol", "kind": "star", "magnitude": 3.0},
			{"id": "scheat", "name_key": "ATLAS_SCHEAT", "bayer": "β Peg", "local_position": Vector2(0.7283904, 0.0879743), "node_id": "slot_3", "kind": "star", "magnitude": 3.0},
			{"id": "algenib", "name_key": "ATLAS_ALGENIB", "bayer": "γ Peg", "local_position": Vector2(-0.1266687, 0.7137483), "node_id": "slot_4", "kind": "star", "magnitude": 3.0},
			{"id": "homam", "name_key": "ATLAS_HOMAM", "bayer": "ζ Peg", "local_position": Vector2(1.0147547, 0.9646257), "node_id": "slot_5", "kind": "star", "magnitude": 3.0},
			{"id": "enif", "name_key": "ATLAS_ENIF", "bayer": "ε Peg", "local_position": Vector2(1.7490535, 0.9699545), "node_id": "ext_record_complete", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpheratz", "scheat"], ["scheat", "markab"], ["markab", "algenib"], ["algenib", "alpheratz"], ["markab", "homam"], ["homam", "enif"]],
	},
	"cygnus": {
		"label_key": "ATLAS_CYGNUS", "branch": "cygnus",
		"stars": [
			{"id": "deneb", "name_key": "ATLAS_DENEB", "bayer": "α Cyg", "local_position": Vector2(-0.4599689, -0.6032906), "node_id": "ext_trace_study", "kind": "star", "magnitude": 3.0},
			{"id": "sadr", "name_key": "ATLAS_SADR", "bayer": "γ Cyg", "local_position": Vector2(-0.1698096, -0.1363017), "node_id": "focus", "kind": "star", "magnitude": 3.0},
			{"id": "albireo", "name_key": "ATLAS_ALBIREO", "bayer": "β Cyg", "local_position": Vector2(0.8282397, 0.9265848), "node_id": "precision", "kind": "star", "magnitude": 3.0},
			{"id": "gienah", "name_key": "ATLAS_GIENAH", "bayer": "ε Cyg", "local_position": Vector2(-0.6299966, 0.4007442), "node_id": "ext_cyg_lock", "kind": "star", "magnitude": 3.0},
			{"id": "delta_cyg", "name_key": "ATLAS_DELTA_CYG", "bayer": "δ Cyg", "local_position": Vector2(0.4315355, -0.5877367), "node_id": "ext_cyg_aperture", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["deneb", "sadr"], ["sadr", "albireo"], ["sadr", "gienah"], ["sadr", "delta_cyg"]],
	},
	"aquila": {
		"label_key": "ATLAS_AQUILA", "branch": "aquila",
		"stars": [
			{"id": "altair", "name_key": "ATLAS_ALTAIR", "bayer": "α Aql", "local_position": Vector2(-0.1844249, -0.1666635), "node_id": "ext_sweep_study", "kind": "star", "magnitude": 3.0},
			{"id": "tarazed", "name_key": "ATLAS_TARAZED", "bayer": "γ Aql", "local_position": Vector2(-0.0825437, -0.3248707), "node_id": "wide", "kind": "star", "magnitude": 3.0},
			{"id": "alshain", "name_key": "ATLAS_ALSHAIN", "bayer": "β Aql", "local_position": Vector2(-0.2877060, 0.0564261), "node_id": "ext_aql_pair", "kind": "star", "magnitude": 3.0},
			{"id": "delta_aql", "name_key": "ATLAS_DELTA_AQL", "bayer": "δ Aql", "local_position": Vector2(0.3875304, 0.3551713), "node_id": "ext_aql_stride", "kind": "star", "magnitude": 3.0},
			{"id": "theta_aql", "name_key": "ATLAS_THETA_AQL", "bayer": "θ Aql", "local_position": Vector2(-0.6563580, 0.7126522), "node_id": "ext_aql_stream", "kind": "star", "magnitude": 3.0},
			{"id": "zeta_aql", "name_key": "", "bayer": "ζ Aql", "local_position": Vector2(0.8235023, -0.6327153), "node_id": "", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["tarazed", "altair"], ["altair", "alshain"], ["altair", "delta_aql"], ["delta_aql", "theta_aql"], ["delta_aql", "zeta_aql"]],
	},
	"lacerta": {
		"label_key": "ATLAS_LACERTA", "branch": "lacerta",
		"stars": [
			{"id": "alpha_lac", "name_key": "ATLAS_ALPHA_LAC", "bayer": "α Lac", "local_position": Vector2(-0.1466536, -0.3846478), "node_id": "ext_trace_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "beta_lac", "name_key": "ATLAS_BETA_LAC", "bayer": "β Lac", "local_position": Vector2(0.0220585, -0.6506189), "node_id": "ext_sweep_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "four_lac", "name_key": "ATLAS_FOUR_LAC", "bayer": "4 Lac", "local_position": Vector2(0.0020473, -0.2723310), "node_id": "ext_link_advanced", "kind": "star", "magnitude": 3.0},
			{"id": "five_lac", "name_key": "ATLAS_FIVE_LAC", "bayer": "5 Lac", "local_position": Vector2(-0.1136494, -0.0302864), "node_id": "ext_synthesis", "kind": "star", "magnitude": 3.0},
			{"id": "one_lac", "name_key": "ATLAS_ONE_LAC", "bayer": "1 Lac", "local_position": Vector2(0.2361972, 1.3378842), "node_id": "ext_combined_watch", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_lac", "beta_lac"], ["beta_lac", "four_lac"], ["four_lac", "five_lac"], ["five_lac", "one_lac"]],
	},
	"vulpecula": {
		"label_key": "ATLAS_VULPECULA", "branch": "vulpecula",
		"stars": [
			{"id": "alpha_vul", "name_key": "ATLAS_ALPHA_VUL", "bayer": "α Vul", "local_position": Vector2(0.8639643, 0.1033295), "node_id": "ext_vul_memory", "kind": "star", "magnitude": 3.0},
			{"id": "eight_vul", "name_key": "ATLAS_EIGHT_VUL", "bayer": "8 Vul", "local_position": Vector2(0.8531300, 0.0848907), "node_id": "ext_vul_rhythm", "kind": "star", "magnitude": 3.0},
			{"id": "thirteen_vul", "name_key": "ATLAS_THIRTEEN_VUL", "bayer": "13 Vul", "local_position": Vector2(-0.1581369, 0.2257196), "node_id": "ext_vul_arc", "kind": "star", "magnitude": 3.0},
			{"id": "sixteen_vul", "name_key": "ATLAS_SIXTEEN_VUL", "bayer": "16 Vul", "local_position": Vector2(-0.5094353, 0.0645976), "node_id": "ext_vul_cadence", "kind": "star", "magnitude": 3.0},
			{"id": "twentythree_vul", "name_key": "ATLAS_TWENTYTHREE_VUL", "bayer": "23 Vul", "local_position": Vector2(-1.0495222, -0.4785375), "node_id": "ext_vul_flow", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_vul", "eight_vul"], ["eight_vul", "thirteen_vul"], ["thirteen_vul", "sixteen_vul"], ["sixteen_vul", "twentythree_vul"]],
	},
	"delphinus": {
		"label_key": "ATLAS_DELPHINUS", "branch": "delphinus",
		"stars": [
			{"id": "alpha_del", "name_key": "ATLAS_ALPHA_DEL", "bayer": "α Del", "local_position": Vector2(0.0359684, -0.4490436), "node_id": "ext_del_signal", "kind": "star", "magnitude": 3.0},
			{"id": "beta_del", "name_key": "ATLAS_BETA_DEL", "bayer": "β Del", "local_position": Vector2(0.2097047, 0.0028753), "node_id": "ext_del_companion", "kind": "star", "magnitude": 3.0},
			{"id": "gamma_del", "name_key": "ATLAS_GAMMA_DEL", "bayer": "γ Del", "local_position": Vector2(-0.5432080, -0.5239962), "node_id": "ext_del_debris", "kind": "star", "magnitude": 3.0},
			{"id": "delta_del", "name_key": "ATLAS_DELTA_DEL", "bayer": "δ Del", "local_position": Vector2(-0.2805876, -0.1619244), "node_id": "ext_del_resonance", "kind": "star", "magnitude": 3.0},
			{"id": "epsilon_del", "name_key": "ATLAS_EPSILON_DEL", "bayer": "ε Del", "local_position": Vector2(0.5781225, 1.1320889), "node_id": "ext_del_school", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_del", "beta_del"], ["beta_del", "delta_del"], ["delta_del", "gamma_del"], ["gamma_del", "alpha_del"], ["beta_del", "epsilon_del"]],
	},
	"sagitta": {
		"label_key": "ATLAS_SAGITTA", "branch": "sagitta",
		"stars": [
			{"id": "alpha_sge", "name_key": "ATLAS_ALPHA_SGE", "bayer": "α Sge", "local_position": Vector2(0.7872726, 0.2198106), "node_id": "ext_sge_cadence", "kind": "star", "magnitude": 3.0},
			{"id": "beta_sge", "name_key": "ATLAS_BETA_SGE", "bayer": "β Sge", "local_position": Vector2(0.7170095, 0.3930490), "node_id": "ext_sge_forecast", "kind": "star", "magnitude": 3.0},
			{"id": "delta_sge", "name_key": "ATLAS_DELTA_SGE", "bayer": "δ Sge", "local_position": Vector2(0.2313870, 0.0583237), "node_id": "ext_sge_solution", "kind": "star", "magnitude": 3.0},
			{"id": "gamma_sge", "name_key": "ATLAS_GAMMA_SGE", "bayer": "γ Sge", "local_position": Vector2(-0.6278745, -0.2516819), "node_id": "ext_sge_window", "kind": "star", "magnitude": 3.0},
			{"id": "eta_sge", "name_key": "ATLAS_ETA_SGE", "bayer": "η Sge", "local_position": Vector2(-1.1077947, -0.4195014), "node_id": "ext_sge_stream", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_sge", "delta_sge"], ["beta_sge", "delta_sge"], ["delta_sge", "gamma_sge"], ["gamma_sge", "eta_sge"]],
	},
	"equuleus": {
		"label_key": "ATLAS_EQUULEUS", "branch": "equuleus",
		"stars": [
			{"id": "alpha_equ", "name_key": "ATLAS_ALPHA_EQU", "bayer": "α Equ", "local_position": Vector2(0.0074848, 1.1059498), "node_id": "ext_equ_focus", "kind": "star", "magnitude": 3.0},
			{"id": "beta_equ", "name_key": "ATLAS_BETA_EQU", "bayer": "β Equ", "local_position": Vector2(-0.6849699, 0.4877149), "node_id": "ext_equ_mount", "kind": "star", "magnitude": 3.0},
			{"id": "gamma_equ", "name_key": "ATLAS_GAMMA_EQU", "bayer": "γ Equ", "local_position": Vector2(0.5397497, -0.8219231), "node_id": "ext_equ_array", "kind": "star", "magnitude": 3.0},
			{"id": "delta_equ", "name_key": "ATLAS_DELTA_EQU", "bayer": "δ Equ", "local_position": Vector2(0.1377354, -0.7717416), "node_id": "ext_equ_link", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_equ", "beta_equ"], ["beta_equ", "delta_equ"], ["delta_equ", "gamma_equ"], ["gamma_equ", "alpha_equ"]],
	},
	"triangulum": {
		"label_key": "ATLAS_TRIANGULUM", "branch": "triangulum",
		"stars": [
			{"id": "alpha_tri", "name_key": "ATLAS_ALPHA_TRI", "bayer": "α Tri", "local_position": Vector2(0.8674641, 0.9586804), "node_id": "ext_tri_photometry", "kind": "star", "magnitude": 3.0},
			{"id": "beta_tri", "name_key": "ATLAS_BETA_TRI", "bayer": "β Tri", "local_position": Vector2(-0.1912877, -0.6456792), "node_id": "ext_tri_analysis", "kind": "star", "magnitude": 3.0},
			{"id": "gamma_tri", "name_key": "ATLAS_GAMMA_TRI", "bayer": "γ Tri", "local_position": Vector2(-0.6761764, -0.3130012), "node_id": "ext_tri_catalogue", "kind": "star", "magnitude": 3.0},
		],
		"segments": [["alpha_tri", "beta_tri"], ["beta_tri", "gamma_tri"], ["gamma_tri", "alpha_tri"]],
	},
}
const PLACEMENTS := {
	"pegasus": {"anchor_angle": 2.879, "anchor_radius": 713.86, "scale": 115.0, "tilt": 4.9218285},
	"cygnus": {"anchor_angle": 2.247, "anchor_radius": 846.46, "scale": 112.0, "tilt": -0.32},
	"aquila": {"anchor_angle": 2.449, "anchor_radius": 1065.27, "scale": 100.0, "tilt": 0.10},
	"lacerta": {"anchor_angle": 3.55, "anchor_radius": 900, "scale": 95, "tilt": 0.12},
	"vulpecula": {"anchor_angle": 0.97, "anchor_radius": 930, "scale": 106, "tilt": -0.15},
	"delphinus": {"anchor_angle": 0.25, "anchor_radius": 920, "scale": 112, "tilt": 0.1},
	"sagitta": {"anchor_angle": -0.48, "anchor_radius": 910, "scale": 110, "tilt": 0.18},
	"equuleus": {"anchor_angle": -1.2, "anchor_radius": 900, "scale": 114, "tilt": 0},
	"triangulum": {"anchor_angle": -1.95, "anchor_radius": 905, "scale": 113, "tilt": -0.1},
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
