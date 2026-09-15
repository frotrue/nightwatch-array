extends RefCounted

const CATALOGUE_VERSION := 7
const RETIRED_RESEARCH_IDS := ["ext_link_study", "record", "revisit", "ext_cep_core", "ext_cep_depth"]
const DRAW_COST := 8
const SAMPLE_MODULES := ["focus", "wide", "precision", "sweep_optics", "wide_correlation", "linear_observation", "capture_hold", "overcharge"]
const MODULE_BRANCHES := ["pegasus", "lacerta"]
const LEGACY_PURCHASE_IDS := ["focus", "wide", "precision", "record", "revisit"]
const LEGACY_GRANTS := {"ext_sweep_study": "sweep_optics"}
const RESEARCH_ORDER := ["ext_sct_stellar", "ext_sct_reach", "ext_sct_tracking", "ext_sct_arrivals", "ext_sct_supernova", "ext_protocol", "slot_3", "slot_4", "slot_5", "ext_record_complete", "ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced", "ext_synthesis", "ext_combined_watch", "ext_trace_study", "focus", "precision", "ext_cyg_lock", "ext_cyg_aperture", "ext_sweep_study", "wide", "ext_aql_pair", "ext_aql_stride", "ext_aql_stream", "ext_vul_memory", "ext_vul_rhythm", "ext_vul_arc", "ext_vul_cadence", "ext_vul_flow", "ext_del_signal", "ext_del_companion", "ext_del_debris", "ext_del_resonance", "ext_del_school", "ext_sge_cadence", "ext_sge_forecast", "ext_sge_solution", "ext_sge_window", "ext_sge_stream", "ext_equ_focus", "ext_equ_mount", "ext_equ_array", "ext_equ_link", "ext_tri_photometry", "ext_tri_analysis", "ext_tri_catalogue", "ext_cnc_planet", "ext_cnc_arrivals", "ext_cnc_tracking", "ext_cnc_yield", "ext_cnc_survey", "ext_sgr_black_hole", "ext_sgr_reach", "ext_sgr_hold", "ext_sgr_tracking", "ext_sgr_yield", "ext_sgr_arrivals", "ext_sgr_wide", "ext_sgr_linger", "ext_phe_white_hole", "ext_phe_ejecta", "ext_phe_tracking", "ext_phe_arrivals", "ext_phe_yield", "ext_phe_outflow"]
const RESEARCH := {
	"ext_sct_stellar": {"cost": 15000000.0, "requires": ["ext_protocol"], "branch": "scutum", "effects": {}},
	"ext_sct_reach": {"cost": 25000000.0, "requires": ["ext_sct_stellar"], "branch": "scutum", "effects": {"supernova_radius": 1.3333333333333333}},
	"ext_sct_tracking": {"cost": 30000000.0, "requires": ["ext_sct_stellar"], "branch": "scutum", "effects": {"stellar_speed": 1.3}},
	"ext_sct_arrivals": {"cost": 35000000.0, "requires": ["ext_sct_tracking"], "branch": "scutum", "effects": {"stellar_spawn": 1.35}},
	"ext_sct_supernova": {"cost": 45000000.0, "requires": ["ext_sct_reach", "ext_sct_arrivals"], "branch": "scutum", "effects": {"supernova_radius": 1.25, "stellar_value": 1.25}},
	"ext_protocol": {"cost": 0.0, "requires": [], "branch": "pegasus", "effects": {}},
	"slot_3": {"cost": 45000000.0, "requires": ["ext_protocol"], "branch": "pegasus", "effects": {"slot_capacity": 3}},
	"slot_4": {"cost": 60000000.0, "requires": ["slot_3"], "branch": "pegasus", "effects": {"slot_capacity": 4}},
	"slot_5": {"cost": 80000000.0, "requires": ["slot_4"], "branch": "pegasus", "effects": {"slot_capacity": 5}},
	"ext_record_complete": {"cost": 0.0, "requires": ["slot_5", "ext_combined_watch"], "branch": "pegasus", "effects": {}},
	"ext_trace_advanced": {"cost": 40000000.0, "requires": ["ext_protocol"], "branch": "lacerta", "effects": {}},
	"ext_sweep_advanced": {"cost": 40000000.0, "requires": ["ext_protocol"], "branch": "lacerta", "effects": {}},
	"ext_link_advanced": {"cost": 40000000.0, "requires": ["ext_protocol"], "branch": "lacerta", "effects": {}},
	"ext_synthesis": {"cost": 45000000.0, "requires": ["ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced"], "branch": "lacerta", "effects": {}},
	"ext_combined_watch": {"cost": 60000000.0, "requires": ["ext_synthesis"], "branch": "lacerta", "effects": {}},
	"ext_trace_study": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "cygnus", "effects": {"manual_speed": 1.15}},
	"focus": {"cost": 30000000.0, "requires": ["ext_trace_study"], "branch": "cygnus", "effects": {"tracking_radius": 1.12}},
	"precision": {"cost": 40000000.0, "requires": ["focus"], "branch": "cygnus", "effects": {"secondary_speed": 1.2}},
	"ext_cyg_lock": {"cost": 40000000.0, "requires": ["focus"], "branch": "cygnus", "effects": {"tracking_grace": 0.25}},
	"ext_cyg_aperture": {"cost": 50000000.0, "requires": ["precision", "ext_cyg_lock"], "branch": "cygnus", "effects": {"tracking_radius": 1.18}},
	"ext_sweep_study": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "aquila", "effects": {"survey_distance": 0.9}},
	"wide": {"cost": 30000000.0, "requires": ["ext_sweep_study"], "branch": "aquila", "effects": {"survey_cooldown": 0.7}},
	"ext_aql_pair": {"cost": 40000000.0, "requires": ["wide"], "branch": "aquila", "effects": {"survey_count": 1}},
	"ext_aql_stride": {"cost": 40000000.0, "requires": ["wide"], "branch": "aquila", "effects": {"survey_distance": 0.88}},
	"ext_aql_stream": {"cost": 50000000.0, "requires": ["ext_aql_pair", "ext_aql_stride"], "branch": "aquila", "effects": {"survey_cooldown": 0.7}},
	"ext_vul_memory": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "vulpecula", "effects": {"combo_window": 1.0}},
	"ext_vul_rhythm": {"cost": 30000000.0, "requires": ["ext_vul_memory"], "branch": "vulpecula", "effects": {"combo_speed": 0.015}},
	"ext_vul_arc": {"cost": 40000000.0, "requires": ["ext_vul_memory"], "branch": "vulpecula", "effects": {"combo_radius": 1.0}},
	"ext_vul_cadence": {"cost": 45000000.0, "requires": ["ext_vul_rhythm", "ext_vul_arc"], "branch": "vulpecula", "effects": {"combo_cap": 2}},
	"ext_vul_flow": {"cost": 50000000.0, "requires": ["ext_vul_cadence"], "branch": "vulpecula", "effects": {"combo_window": 1.0, "combo_speed": 0.01}},
	"ext_del_signal": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "delphinus", "effects": {"echo_probability": 0.05}},
	"ext_del_companion": {"cost": 30000000.0, "requires": ["ext_del_signal"], "branch": "delphinus", "effects": {"echo_count": 1}},
	"ext_del_debris": {"cost": 40000000.0, "requires": ["ext_del_signal"], "branch": "delphinus", "effects": {"fragment_data": 1.15}},
	"ext_del_resonance": {"cost": 45000000.0, "requires": ["ext_del_companion", "ext_del_debris"], "branch": "delphinus", "effects": {"echo_probability": 0.05}},
	"ext_del_school": {"cost": 50000000.0, "requires": ["ext_del_resonance"], "branch": "delphinus", "effects": {"echo_count": 1}},
	"ext_sge_cadence": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "sagitta", "effects": {}},
	"ext_sge_forecast": {"cost": 30000000.0, "requires": ["ext_sge_cadence"], "branch": "sagitta", "effects": {"asteroid_spawn": 1.35}},
	"ext_sge_solution": {"cost": 40000000.0, "requires": ["ext_sge_forecast"], "branch": "sagitta", "effects": {}},
	"ext_sge_window": {"cost": 40000000.0, "requires": ["ext_sge_cadence"], "branch": "sagitta", "effects": {"asteroid_speed": 1.3}},
	"ext_sge_stream": {"cost": 50000000.0, "requires": ["ext_sge_solution", "ext_sge_window"], "branch": "sagitta", "effects": {"asteroid_value": 1.5}},
	"ext_equ_focus": {"cost": 25000000.0, "requires": ["ext_protocol"], "branch": "equuleus", "effects": {"dish_speed": 1.15}},
	"ext_equ_mount": {"cost": 35000000.0, "requires": ["ext_equ_focus"], "branch": "equuleus", "effects": {"dish_move": 1.2, "dish_radius": 1.1}},
	"ext_equ_array": {"cost": 50000000.0, "requires": ["ext_equ_mount"], "branch": "equuleus", "effects": {"dish_count": 1}},
	"ext_equ_link": {"cost": 60000000.0, "requires": ["ext_equ_array"], "branch": "equuleus", "effects": {"dish_speed": 1.2}},
	"ext_tri_photometry": {"cost": 30000000.0, "requires": ["ext_protocol"], "branch": "triangulum", "effects": {"data": 1.1}},
	"ext_tri_analysis": {"cost": 40000000.0, "requires": ["ext_tri_photometry"], "branch": "triangulum", "effects": {"analysis_speed": 1.1}},
	"ext_tri_catalogue": {"cost": 60000000.0, "requires": ["ext_tri_analysis"], "branch": "triangulum", "effects": {"data": 1.15}},
	"ext_cnc_planet": {"cost": 45000000.0, "requires": ["ext_sge_solution"], "branch": "cancer", "effects": {}},
	"ext_cnc_arrivals": {"cost": 50000000.0, "requires": ["ext_cnc_planet"], "branch": "cancer", "effects": {"planet_spawn": 1.35}},
	"ext_cnc_tracking": {"cost": 60000000.0, "requires": ["ext_cnc_planet"], "branch": "cancer", "effects": {"planet_speed": 1.3}},
	"ext_cnc_yield": {"cost": 80000000.0, "requires": ["ext_cnc_tracking"], "branch": "cancer", "effects": {"planet_value": 1.5}},
	"ext_cnc_survey": {"cost": 100000000.0, "requires": ["ext_cnc_arrivals", "ext_cnc_yield"], "branch": "cancer", "effects": {"planet_spawn": 1.3, "planet_value": 1.3}},
	"ext_sgr_black_hole": {"cost": 80000000.0, "requires": ["ext_cnc_tracking"], "branch": "sagittarius", "effects": {}},
	"ext_sgr_reach": {"cost": 60000000.0, "requires": ["ext_sgr_black_hole"], "branch": "sagittarius", "effects": {"gravity_radius": 1.25}},
	"ext_sgr_hold": {"cost": 80000000.0, "requires": ["ext_sgr_reach"], "branch": "sagittarius", "effects": {"gravity_slow_seconds": 1.0}},
	"ext_sgr_tracking": {"cost": 60000000.0, "requires": ["ext_sgr_black_hole"], "branch": "sagittarius", "effects": {"black_hole_speed": 1.3}},
	"ext_sgr_yield": {"cost": 80000000.0, "requires": ["ext_sgr_tracking"], "branch": "sagittarius", "effects": {"black_hole_value": 1.5}},
	"ext_sgr_arrivals": {"cost": 100000000.0, "requires": ["ext_sgr_yield"], "branch": "sagittarius", "effects": {"black_hole_spawn": 1.35}},
	"ext_sgr_wide": {"cost": 100000000.0, "requires": ["ext_sgr_hold"], "branch": "sagittarius", "effects": {"gravity_radius": 1.2}},
	"ext_sgr_linger": {"cost": 120000000.0, "requires": ["ext_sgr_wide", "ext_sgr_arrivals"], "branch": "sagittarius", "effects": {"gravity_slow_seconds": 1.0}},
	"ext_phe_white_hole": {"cost": 120000000.0, "requires": ["ext_sgr_yield"], "branch": "phoenix", "effects": {}},
	"ext_phe_ejecta": {"cost": 100000000.0, "requires": ["ext_phe_white_hole"], "branch": "phoenix", "effects": {"white_hole_ejecta_count": 12}},
	"ext_phe_tracking": {"cost": 80000000.0, "requires": ["ext_phe_white_hole"], "branch": "phoenix", "effects": {"white_hole_speed": 1.5}},
	"ext_phe_arrivals": {"cost": 100000000.0, "requires": ["ext_phe_tracking"], "branch": "phoenix", "effects": {"white_hole_spawn": 1.5}},
	"ext_phe_yield": {"cost": 100000000.0, "requires": ["ext_phe_ejecta"], "branch": "phoenix", "effects": {"white_hole_ejecta_value": 1.5}},
	"ext_phe_outflow": {"cost": 120000000.0, "requires": ["ext_phe_arrivals", "ext_phe_yield"], "branch": "phoenix", "effects": {"white_hole_ejecta_count": 12}},
}

static func number(value, maximum: float, fallback: float = 0.0) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), 0.0, maximum)

static func integer(value, maximum: int, fallback: int = 0) -> int:
	if not (value is float or value is int) or not is_finite(float(value)) or floorf(float(value)) != float(value):
		return fallback
	return int(clampf(float(value), 0.0, float(maximum)))

static func flag(value) -> bool:
	return value is bool and value
