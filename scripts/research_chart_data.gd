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
			{"id": "schedar", "name_key": "STAR_SCHEDAR", "bayer": "α Cas", "magnitude": 2.24, "local_position": Vector2(-0.54, 0.34), "node_id": "better_lens", "kind": "star"},
			{"id": "tsih", "name_key": "STAR_TSIH", "bayer": "γ Cas", "magnitude": 2.47, "local_position": Vector2(0.00, -0.30), "node_id": "long_exposure", "kind": "star"},
			{"id": "ruchbah", "name_key": "STAR_RUCHBAH", "bayer": "δ Cas", "magnitude": 2.68, "local_position": Vector2(0.54, 0.31), "node_id": "precision_multiplier", "kind": "star"},
			{"id": "segin", "name_key": "STAR_SEGIN", "bayer": "ε Cas", "magnitude": 3.38, "local_position": Vector2(1.00, -0.18), "node_id": "perfect_observation", "kind": "star"}
		],
		"segments": [["caph", "schedar"], ["schedar", "tsih"], ["tsih", "ruchbah"], ["ruchbah", "segin"]]
	},
	"big_dipper": {
		"branch": "detection",
		"label_key": "CONSTELLATION_BIG_DIPPER",
		"stars": [
			{"id": "dubhe", "name_key": "STAR_DUBHE", "bayer": "α UMa", "magnitude": 1.79, "local_position": Vector2(-0.96, -0.34), "node_id": "wide_field", "kind": "star"},
			{"id": "merak", "name_key": "STAR_MERAK", "bayer": "β UMa", "magnitude": 2.37, "local_position": Vector2(-0.91, 0.35), "node_id": "edge_detection", "kind": "star"},
			{"id": "phecda", "name_key": "STAR_PHECDA", "bayer": "γ UMa", "magnitude": 2.44, "local_position": Vector2(-0.19, 0.55), "node_id": "contact_ledger", "kind": "star"},
			{"id": "megrez", "name_key": "STAR_MEGREZ", "bayer": "δ UMa", "magnitude": 3.31, "local_position": Vector2(-0.08, -0.12), "node_id": "trajectory", "kind": "star"},
			{"id": "alioth", "name_key": "STAR_ALIOTH", "bayer": "ε UMa", "magnitude": 1.77, "local_position": Vector2(0.55, -0.22), "node_id": "rare_detection", "kind": "star"},
			{"id": "mizar", "name_key": "STAR_MIZAR", "bayer": "ζ UMa", "magnitude": 2.23, "local_position": Vector2(1.10, -0.31), "node_id": "fragment_analysis", "kind": "star"},
			{"id": "alcor", "name_key": "STAR_ALCOR", "bayer": "80 UMa", "magnitude": 3.99, "local_position": Vector2(1.08, -0.43), "node_id": "companion_resolution", "kind": "star"},
			{"id": "alkaid", "name_key": "STAR_ALKAID", "bayer": "η UMa", "magnitude": 1.86, "local_position": Vector2(1.68, -0.50), "node_id": "shower_detector", "kind": "star"}
		],
		"segments": [["dubhe", "merak"], ["merak", "phecda"], ["phecda", "megrez"], ["megrez", "dubhe"], ["megrez", "alioth"], ["alioth", "mizar"], ["mizar", "alcor"], ["mizar", "alkaid"]]
	},
	"orion": {
		"branch": "network",
		"label_key": "CONSTELLATION_ORION",
		"stars": [
			{"id": "meissa", "name_key": "STAR_MEISSA", "bayer": "λ Ori", "magnitude": 3.39, "local_position": Vector2(0.00, -1.08), "node_id": "observation_scheduling", "kind": "star"},
			{"id": "betelgeuse", "name_key": "STAR_BETELGEUSE", "bayer": "α Ori", "magnitude": 0.50, "local_position": Vector2(-0.72, -0.61), "node_id": "array_planning", "kind": "star"},
			{"id": "bellatrix", "name_key": "STAR_BELLATRIX", "bayer": "γ Ori", "magnitude": 1.64, "local_position": Vector2(0.67, -0.56), "node_id": "thermal_management", "kind": "star"},
			{"id": "alnitak", "name_key": "STAR_ALNITAK", "bayer": "ζ Ori", "magnitude": 1.77, "local_position": Vector2(-0.42, -0.02), "node_id": "secondary_camera", "kind": "star"},
			{"id": "alnilam", "name_key": "STAR_ALNILAM", "bayer": "ε Ori", "magnitude": 1.69, "local_position": Vector2(0.00, 0.02), "node_id": "multi_target_analysis", "kind": "star"},
			{"id": "mintaka", "name_key": "STAR_MINTAKA", "bayer": "δ Ori", "magnitude": 2.23, "local_position": Vector2(0.43, 0.05), "node_id": "extended_watch_protocol", "kind": "star"},
			{"id": "trapezium", "name_key": "STAR_TRAPEZIUM", "bayer": "θ¹ Ori C", "magnitude": 5.13, "local_position": Vector2(0.02, 0.48), "node_id": "automated_tracking", "kind": "nebula"},
			{"id": "hatysa", "name_key": "STAR_HATYSA", "bayer": "ι Ori", "magnitude": 2.75, "local_position": Vector2(0.03, 0.76), "node_id": "observatory_network", "kind": "star"},
			{"id": "saiph", "name_key": "STAR_SAIPH", "bayer": "κ Ori", "magnitude": 2.06, "local_position": Vector2(-0.62, 1.02), "node_id": "predictive_dish_control", "kind": "star"},
			{"id": "rigel", "name_key": "STAR_RIGEL", "bayer": "β Ori", "magnitude": 0.13, "local_position": Vector2(0.72, 1.06), "node_id": "continuous_watch_rotation", "kind": "star"}
		],
		"segments": [["meissa", "betelgeuse"], ["meissa", "bellatrix"], ["betelgeuse", "alnitak"], ["bellatrix", "mintaka"], ["alnitak", "alnilam"], ["alnilam", "mintaka"], ["alnitak", "saiph"], ["mintaka", "rigel"], ["alnilam", "trapezium"], ["trapezium", "hatysa"]]
	},
	# Newly discovered research figures keep at least one star unassigned so the
	# chart still reads as a sky rather than a diagram. The remaining background
	# figures carry no branch until research is mapped onto them. Every star is a
	# real member of its figure; placement between figures stays compositional,
	# but neighbours remain the sky's real neighbours.
	"andromeda": {
		"branch": "andromeda",
		"label_key": "CONSTELLATION_ANDROMEDA",
		"stars": [
			{"id": "alpheratz", "name_key": "STAR_ALPHERATZ", "bayer": "α And", "magnitude": 2.06, "local_position": Vector2(-1.00, 0.52), "node_id": "ephemeris_marks", "kind": "star"},
			{"id": "delta_and", "name_key": "STAR_DELTA_AND", "bayer": "δ And", "magnitude": 3.27, "local_position": Vector2(-0.52, 0.34), "node_id": "satellite_catalog", "kind": "star"},
			{"id": "mirach", "name_key": "STAR_MIRACH", "bayer": "β And", "magnitude": 2.06, "local_position": Vector2(0.02, 0.14), "node_id": "change_detection", "kind": "star"},
			{"id": "mu_and", "name_key": "STAR_MU_AND", "bayer": "μ And", "magnitude": 3.86, "local_position": Vector2(-0.14, -0.34), "node_id": "comet_solutions", "kind": "star"},
			{"id": "nu_and", "name_key": "STAR_NU_AND", "bayer": "ν And", "magnitude": 4.53, "local_position": Vector2(-0.24, -0.62), "node_id": "andromeda_deep_survey", "kind": "star"},
			{"id": "andromeda_galaxy", "name_key": "STAR_ANDROMEDA_GALAXY", "bayer": "M31", "magnitude": 3.44, "local_position": Vector2(-0.36, -0.94), "node_id": "", "kind": "nebula"},
			{"id": "almach", "name_key": "STAR_ALMACH", "bayer": "γ And", "magnitude": 2.10, "local_position": Vector2(0.62, -0.10), "node_id": "variable_watchlist", "kind": "star"}
		],
		"segments": [["alpheratz", "delta_and"], ["delta_and", "mirach"], ["mirach", "almach"], ["mirach", "mu_and"], ["mu_and", "nu_and"], ["nu_and", "andromeda_galaxy"]]
	},
	"perseus": {
		"branch": "perseus",
		"label_key": "CONSTELLATION_PERSEUS",
		"stars": [
			{"id": "eta_per", "name_key": "STAR_ETA_PER", "bayer": "η Per", "magnitude": 3.77, "local_position": Vector2(-0.86, -0.72), "node_id": "radiant_plotting", "kind": "star"},
			{"id": "gamma_per", "name_key": "STAR_GAMMA_PER", "bayer": "γ Per", "magnitude": 2.93, "local_position": Vector2(-0.60, -0.44), "node_id": "crowd_forecast", "kind": "star"},
			{"id": "mirfak", "name_key": "STAR_MIRFAK", "bayer": "α Per", "magnitude": 1.79, "local_position": Vector2(-0.16, -0.10), "node_id": "burst_windowing", "kind": "star"},
			{"id": "delta_per", "name_key": "STAR_DELTA_PER", "bayer": "δ Per", "magnitude": 3.01, "local_position": Vector2(0.30, 0.10), "node_id": "adaptive_exposure_grid", "kind": "star"},
			{"id": "epsilon_per", "name_key": "STAR_EPSILON_PER", "bayer": "ε Per", "magnitude": 2.90, "local_position": Vector2(0.54, 0.62), "node_id": "perseid_survey", "kind": "star"},
			{"id": "zeta_per", "name_key": "STAR_ZETA_PER", "bayer": "ζ Per", "magnitude": 2.85, "local_position": Vector2(0.30, 0.96), "node_id": "", "kind": "star"},
			{"id": "algol", "name_key": "STAR_ALGOL", "bayer": "β Per", "magnitude": 2.12, "local_position": Vector2(-0.44, 0.46), "node_id": "debris_correlation", "kind": "star"},
			{"id": "rho_per", "name_key": "STAR_RHO_PER", "bayer": "ρ Per", "magnitude": 3.39, "local_position": Vector2(-0.68, 0.76), "node_id": "cascade_sampling", "kind": "star"}
		],
		"segments": [["eta_per", "gamma_per"], ["gamma_per", "mirfak"], ["mirfak", "delta_per"], ["delta_per", "epsilon_per"], ["epsilon_per", "zeta_per"], ["mirfak", "algol"], ["algol", "rho_per"]]
	},
	"lyra": {
		"branch": "lyra",
		"label_key": "CONSTELLATION_LYRA",
		"stars": [
			{"id": "vega", "name_key": "STAR_VEGA", "bayer": "α Lyr", "magnitude": 0.03, "local_position": Vector2(-0.62, -0.86), "node_id": "filter_wheel", "kind": "star"},
			{"id": "epsilon_lyr", "name_key": "STAR_EPSILON_LYR", "bayer": "ε Lyr", "magnitude": 4.67, "local_position": Vector2(-0.06, -0.92), "node_id": "", "kind": "star"},
			{"id": "zeta_lyr", "name_key": "STAR_ZETA_LYR", "bayer": "ζ Lyr", "magnitude": 4.36, "local_position": Vector2(-0.34, -0.48), "node_id": "blue_band", "kind": "star"},
			{"id": "sheliak", "name_key": "STAR_SHELIAK", "bayer": "β Lyr", "magnitude": 3.52, "local_position": Vector2(-0.46, 0.32), "node_id": "amber_band", "kind": "star"},
			{"id": "sulafat", "name_key": "STAR_SULAFAT", "bayer": "γ Lyr", "magnitude": 3.24, "local_position": Vector2(0.34, 0.46), "node_id": "violet_band", "kind": "star"},
			{"id": "delta_lyr", "name_key": "STAR_DELTA_LYR", "bayer": "δ Lyr", "magnitude": 4.30, "local_position": Vector2(0.26, -0.06), "node_id": "lyrid_spectrograph", "kind": "star"}
		],
		"segments": [["vega", "epsilon_lyr"], ["vega", "zeta_lyr"], ["zeta_lyr", "sheliak"], ["sheliak", "sulafat"], ["sulafat", "delta_lyr"], ["delta_lyr", "zeta_lyr"]]
	},
	"draco": {
		"label_key": "CONSTELLATION_DRACO",
		"stars": [
			{"id": "eltanin", "name_key": "STAR_ELTANIN", "bayer": "γ Dra", "magnitude": 2.24, "local_position": Vector2(-1.00, -0.34), "node_id": "", "kind": "star"},
			{"id": "rastaban", "name_key": "STAR_RASTABAN", "bayer": "β Dra", "magnitude": 2.79, "local_position": Vector2(-0.86, -0.66), "node_id": "", "kind": "star"},
			{"id": "nu_dra", "name_key": "STAR_NU_DRA", "bayer": "ν Dra", "magnitude": 4.88, "local_position": Vector2(-0.62, -0.52), "node_id": "", "kind": "star"},
			{"id": "xi_dra", "name_key": "STAR_XI_DRA", "bayer": "ξ Dra", "magnitude": 3.75, "local_position": Vector2(-0.66, -0.20), "node_id": "", "kind": "star"},
			{"id": "altais", "name_key": "STAR_ALTAIS", "bayer": "δ Dra", "magnitude": 3.07, "local_position": Vector2(-0.18, 0.10), "node_id": "", "kind": "star"},
			{"id": "zeta_dra", "name_key": "STAR_ZETA_DRA", "bayer": "ζ Dra", "magnitude": 3.17, "local_position": Vector2(0.24, -0.16), "node_id": "", "kind": "star"},
			{"id": "eta_dra", "name_key": "STAR_ETA_DRA", "bayer": "η Dra", "magnitude": 2.73, "local_position": Vector2(0.60, 0.30), "node_id": "", "kind": "star"},
			{"id": "thuban", "name_key": "STAR_THUBAN", "bayer": "α Dra", "magnitude": 3.65, "local_position": Vector2(0.88, 0.02), "node_id": "", "kind": "star"},
			{"id": "iota_dra", "name_key": "STAR_IOTA_DRA", "bayer": "ι Dra", "magnitude": 3.29, "local_position": Vector2(1.00, 0.58), "node_id": "", "kind": "star"}
		],
		"segments": [["eltanin", "xi_dra"], ["xi_dra", "nu_dra"], ["nu_dra", "rastaban"], ["rastaban", "eltanin"], ["xi_dra", "altais"], ["altais", "zeta_dra"], ["zeta_dra", "eta_dra"], ["eta_dra", "thuban"], ["thuban", "iota_dra"]]
	},
	"ursa_minor": {
		"label_key": "CONSTELLATION_URSA_MINOR",
		"stars": [
			{"id": "polaris", "name_key": "STAR_POLARIS", "bayer": "α UMi", "magnitude": 1.98, "local_position": Vector2(1.00, -0.62), "node_id": "", "kind": "star"},
			{"id": "yildun", "name_key": "STAR_YILDUN", "bayer": "δ UMi", "magnitude": 4.35, "local_position": Vector2(0.62, -0.34), "node_id": "", "kind": "star"},
			{"id": "epsilon_umi", "name_key": "STAR_EPSILON_UMI", "bayer": "ε UMi", "magnitude": 4.21, "local_position": Vector2(0.22, -0.08), "node_id": "", "kind": "star"},
			{"id": "zeta_umi", "name_key": "STAR_ZETA_UMI", "bayer": "ζ UMi", "magnitude": 4.29, "local_position": Vector2(-0.14, 0.14), "node_id": "", "kind": "star"},
			{"id": "eta_umi", "name_key": "STAR_ETA_UMI", "bayer": "η UMi", "magnitude": 4.95, "local_position": Vector2(-0.30, 0.54), "node_id": "", "kind": "star"},
			{"id": "kochab", "name_key": "STAR_KOCHAB", "bayer": "β UMi", "magnitude": 2.07, "local_position": Vector2(-0.70, 0.20), "node_id": "", "kind": "star"},
			{"id": "pherkad", "name_key": "STAR_PHERKAD", "bayer": "γ UMi", "magnitude": 3.00, "local_position": Vector2(-0.74, -0.20), "node_id": "", "kind": "star"}
		],
		"segments": [["polaris", "yildun"], ["yildun", "epsilon_umi"], ["epsilon_umi", "zeta_umi"], ["zeta_umi", "eta_umi"], ["eta_umi", "kochab"], ["kochab", "pherkad"], ["pherkad", "zeta_umi"]]
	},
	"leo": {
		"label_key": "CONSTELLATION_LEO",
		"stars": [
			{"id": "regulus", "name_key": "STAR_REGULUS", "bayer": "α Leo", "magnitude": 1.40, "local_position": Vector2(-0.72, 0.52), "node_id": "", "kind": "star"},
			{"id": "eta_leo", "name_key": "STAR_ETA_LEO", "bayer": "η Leo", "magnitude": 3.48, "local_position": Vector2(-0.76, 0.16), "node_id": "", "kind": "star"},
			{"id": "algieba", "name_key": "STAR_ALGIEBA", "bayer": "γ Leo", "magnitude": 2.08, "local_position": Vector2(-0.70, -0.16), "node_id": "", "kind": "star"},
			{"id": "zeta_leo", "name_key": "STAR_ZETA_LEO", "bayer": "ζ Leo", "magnitude": 3.44, "local_position": Vector2(-0.78, -0.46), "node_id": "", "kind": "star"},
			{"id": "mu_leo", "name_key": "STAR_MU_LEO", "bayer": "μ Leo", "magnitude": 3.88, "local_position": Vector2(-0.96, -0.70), "node_id": "", "kind": "star"},
			{"id": "epsilon_leo", "name_key": "STAR_EPSILON_LEO", "bayer": "ε Leo", "magnitude": 2.98, "local_position": Vector2(-1.00, -0.34), "node_id": "", "kind": "star"},
			{"id": "chertan", "name_key": "STAR_CHERTAN", "bayer": "θ Leo", "magnitude": 3.32, "local_position": Vector2(0.26, 0.44), "node_id": "", "kind": "star"},
			{"id": "zosma", "name_key": "STAR_ZOSMA", "bayer": "δ Leo", "magnitude": 2.56, "local_position": Vector2(0.32, -0.06), "node_id": "", "kind": "star"},
			{"id": "denebola", "name_key": "STAR_DENEBOLA", "bayer": "β Leo", "magnitude": 2.14, "local_position": Vector2(0.96, 0.10), "node_id": "", "kind": "star"}
		],
		"segments": [["regulus", "eta_leo"], ["eta_leo", "algieba"], ["algieba", "zeta_leo"], ["zeta_leo", "mu_leo"], ["mu_leo", "epsilon_leo"], ["regulus", "chertan"], ["chertan", "zosma"], ["zosma", "denebola"], ["denebola", "chertan"], ["algieba", "zosma"]]
	},
	"gemini": {
		"label_key": "CONSTELLATION_GEMINI",
		"stars": [
			{"id": "castor", "name_key": "STAR_CASTOR", "bayer": "α Gem", "magnitude": 1.58, "local_position": Vector2(-0.52, -0.94), "node_id": "", "kind": "star"},
			{"id": "pollux", "name_key": "STAR_POLLUX", "bayer": "β Gem", "magnitude": 1.14, "local_position": Vector2(0.22, -0.86), "node_id": "", "kind": "star"},
			{"id": "tau_gem", "name_key": "STAR_TAU_GEM", "bayer": "τ Gem", "magnitude": 4.41, "local_position": Vector2(-0.40, -0.52), "node_id": "", "kind": "star"},
			{"id": "mebsuta", "name_key": "STAR_MEBSUTA", "bayer": "ε Gem", "magnitude": 2.98, "local_position": Vector2(-0.56, -0.06), "node_id": "", "kind": "star"},
			{"id": "upsilon_gem", "name_key": "STAR_UPSILON_GEM", "bayer": "υ Gem", "magnitude": 4.06, "local_position": Vector2(0.14, -0.34), "node_id": "", "kind": "star"},
			{"id": "wasat", "name_key": "STAR_WASAT", "bayer": "δ Gem", "magnitude": 3.53, "local_position": Vector2(0.10, 0.22), "node_id": "", "kind": "star"},
			{"id": "tejat", "name_key": "STAR_TEJAT", "bayer": "μ Gem", "magnitude": 2.87, "local_position": Vector2(-0.86, 0.30), "node_id": "", "kind": "star"},
			{"id": "propus", "name_key": "STAR_PROPUS", "bayer": "η Gem", "magnitude": 3.28, "local_position": Vector2(-0.90, 0.56), "node_id": "", "kind": "star"},
			{"id": "alhena", "name_key": "STAR_ALHENA", "bayer": "γ Gem", "magnitude": 1.93, "local_position": Vector2(-0.10, 0.86), "node_id": "", "kind": "star"},
			{"id": "alzirr", "name_key": "STAR_ALZIRR", "bayer": "ξ Gem", "magnitude": 3.35, "local_position": Vector2(0.44, 0.94), "node_id": "", "kind": "star"}
		],
		"segments": [["castor", "pollux"], ["castor", "tau_gem"], ["tau_gem", "mebsuta"], ["mebsuta", "tejat"], ["tejat", "propus"], ["pollux", "upsilon_gem"], ["upsilon_gem", "wasat"], ["wasat", "alzirr"], ["wasat", "alhena"]]
	},
	"taurus": {
		"label_key": "CONSTELLATION_TAURUS",
		"stars": [
			{"id": "pleiades", "name_key": "STAR_PLEIADES", "bayer": "M45", "magnitude": 1.60, "local_position": Vector2(-1.00, -0.52), "node_id": "", "kind": "nebula"},
			{"id": "epsilon_tau", "name_key": "STAR_EPSILON_TAU", "bayer": "ε Tau", "magnitude": 3.53, "local_position": Vector2(-0.30, -0.30), "node_id": "", "kind": "star"},
			{"id": "delta_tau", "name_key": "STAR_DELTA_TAU", "bayer": "δ Tau", "magnitude": 3.76, "local_position": Vector2(-0.38, -0.02), "node_id": "", "kind": "star"},
			{"id": "hyadum", "name_key": "STAR_HYADUM", "bayer": "γ Tau", "magnitude": 3.65, "local_position": Vector2(-0.44, 0.24), "node_id": "", "kind": "star"},
			{"id": "theta_tau", "name_key": "STAR_THETA_TAU", "bayer": "θ Tau", "magnitude": 3.40, "local_position": Vector2(-0.16, 0.30), "node_id": "", "kind": "star"},
			{"id": "aldebaran", "name_key": "STAR_ALDEBARAN", "bayer": "α Tau", "magnitude": 0.85, "local_position": Vector2(0.08, 0.36), "node_id": "", "kind": "star"},
			{"id": "tianguan", "name_key": "STAR_TIANGUAN", "bayer": "ζ Tau", "magnitude": 3.00, "local_position": Vector2(0.88, 0.52), "node_id": "", "kind": "star"},
			{"id": "elnath", "name_key": "STAR_ELNATH", "bayer": "β Tau", "magnitude": 1.65, "local_position": Vector2(0.72, -0.62), "node_id": "", "kind": "star"}
		],
		"segments": [["pleiades", "epsilon_tau"], ["epsilon_tau", "delta_tau"], ["delta_tau", "hyadum"], ["hyadum", "theta_tau"], ["theta_tau", "aldebaran"], ["aldebaran", "tianguan"], ["epsilon_tau", "elnath"]]
	},
	"canis_major": {
		"label_key": "CONSTELLATION_CANIS_MAJOR",
		"stars": [
			{"id": "sirius", "name_key": "STAR_SIRIUS", "bayer": "α CMa", "magnitude": -1.46, "local_position": Vector2(-0.34, -0.86), "node_id": "", "kind": "star"},
			{"id": "mirzam", "name_key": "STAR_MIRZAM", "bayer": "β CMa", "magnitude": 1.98, "local_position": Vector2(-0.96, -0.62), "node_id": "", "kind": "star"},
			{"id": "muliphein", "name_key": "STAR_MULIPHEIN", "bayer": "γ CMa", "magnitude": 4.11, "local_position": Vector2(0.24, -0.72), "node_id": "", "kind": "star"},
			{"id": "omicron_cma", "name_key": "STAR_OMICRON_CMA", "bayer": "ο² CMa", "magnitude": 3.02, "local_position": Vector2(-0.16, -0.26), "node_id": "", "kind": "star"},
			{"id": "wezen", "name_key": "STAR_WEZEN", "bayer": "δ CMa", "magnitude": 1.83, "local_position": Vector2(0.18, 0.34), "node_id": "", "kind": "star"},
			{"id": "adhara", "name_key": "STAR_ADHARA", "bayer": "ε CMa", "magnitude": 1.50, "local_position": Vector2(-0.38, 0.52), "node_id": "", "kind": "star"},
			{"id": "furud", "name_key": "STAR_FURUD", "bayer": "ζ CMa", "magnitude": 3.02, "local_position": Vector2(-0.64, 0.94), "node_id": "", "kind": "star"},
			{"id": "aludra", "name_key": "STAR_ALUDRA", "bayer": "η CMa", "magnitude": 2.45, "local_position": Vector2(0.64, 0.62), "node_id": "", "kind": "star"}
		],
		"segments": [["sirius", "mirzam"], ["sirius", "muliphein"], ["sirius", "omicron_cma"], ["omicron_cma", "adhara"], ["adhara", "furud"], ["omicron_cma", "wezen"], ["wezen", "adhara"], ["wezen", "aludra"]]
	}
}

# Placement is deliberately separate from factual star data. Anchors are polar
# coordinates around the chart's bottom-centre horizon origin.
const PLACEMENTS := {
	"cassiopeia": {"anchor_angle": -2.72, "anchor_radius": 285.0, "scale": 130.0, "tilt": -0.08},
	"big_dipper": {"anchor_angle": -1.57, "anchor_radius": 430.0, "scale": 145.0, "tilt": 0.02},
	"orion": {"anchor_angle": -0.55, "anchor_radius": 345.0, "scale": 134.0, "tilt": -0.02},
	# The three mapped figures above keep the anchors the chart shipped with.
	# The nine background figures are spread around the **whole circle** at
	# roughly 0.5 rad apart, not pushed outward: radius is not the spacing
	# budget, angle is. Only half the circle is above the horizon at a time, so
	# six figures are on screen and six are underfoot, and the wheel trades
	# them. Pushing them outward instead only moved them off the frame and left
	# the far side of the sky empty.
	#
	# Above the horizon at the default rotation, left to right:
	#   cassiopeia -2.72 · draco -2.15 · big_dipper -1.57 · gemini -1.00
	#   orion -0.55 · canis_major -0.04
	# Below it, in the order the wheel brings them up:
	# The three sharing the dome with the research figures sit at radii that
	# clear them. Cassiopeia, the Plough and Orion are the wide ones, so a
	# neighbour at the same radius collides no matter how the angle is nudged.
	"draco": {"anchor_angle": -2.15, "anchor_radius": 330.0, "scale": 108.0, "tilt": -0.04},
	"gemini": {"anchor_angle": -1.10, "anchor_radius": 280.0, "scale": 104.0, "tilt": 0.03},
	"canis_major": {"anchor_angle": -0.30, "anchor_radius": 560.0, "scale": 100.0, "tilt": 0.04},
	"taurus": {"anchor_angle": 0.48, "anchor_radius": 400.0, "scale": 106.0, "tilt": -0.07},
	"perseus": {"anchor_angle": 0.99, "anchor_radius": 470.0, "scale": 104.0, "tilt": 0.06},
	"leo": {"anchor_angle": 1.51, "anchor_radius": 520.0, "scale": 110.0, "tilt": -0.05},
	"ursa_minor": {"anchor_angle": 2.02, "anchor_radius": 430.0, "scale": 96.0, "tilt": 0.14},
	"lyra": {"anchor_angle": 2.53, "anchor_radius": 360.0, "scale": 92.0, "tilt": 0.10},
	"andromeda": {"anchor_angle": 3.05, "anchor_radius": 470.0, "scale": 100.0, "tilt": -0.08}
}


# Two stars from different figures this close read as one clump, and a research
# star's 44x44 hit box would swallow the intruder. Stars inside one figure are
# exempt: Mizar and Alcor are a real pair and are meant to sit on top of each
# other. Measured minimum across the twelve figures is 48px.
const MIN_STAR_SEPARATION := 40.0


static func chart_offsets() -> Array[Dictionary]:
	# Positions relative to the chart origin. The origin itself cancels out of
	# every distance, so this stays free of the renderer's layout constants.
	var offsets: Array[Dictionary] = []
	for constellation_id in CONSTELLATIONS:
		var constellation: Dictionary = CONSTELLATIONS[constellation_id]
		if not PLACEMENTS.has(constellation_id):
			continue
		var placement: Dictionary = PLACEMENTS[constellation_id]
		var anchor := Vector2.RIGHT.rotated(float(placement.anchor_angle)) * float(placement.anchor_radius)
		for star_variant in constellation.stars:
			var star: Dictionary = star_variant
			var offset: Vector2 = anchor + Vector2(star.local_position).rotated(float(placement.tilt)) * float(placement.scale)
			offsets.append({"constellation_id": constellation_id, "star_id": String(star.get("id", "")), "offset": offset})
	return offsets


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
	var offsets := chart_offsets()
	for first in range(offsets.size()):
		for second in range(first + 1, offsets.size()):
			var left: Dictionary = offsets[first]
			var right: Dictionary = offsets[second]
			if String(left.constellation_id) == String(right.constellation_id):
				continue
			var separation: float = Vector2(left.offset).distance_to(Vector2(right.offset))
			if separation < MIN_STAR_SEPARATION:
				errors.append("Stars %s/%s and %s/%s are %.1fpx apart" % [
					left.constellation_id, left.star_id,
					right.constellation_id, right.star_id,
					separation
				])
	return errors
