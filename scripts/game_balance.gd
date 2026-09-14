extends RefCounted
class_name GameBalance

const FIRST_METEOR_DELAY := 1.8
const SHOWER_WARNING_TIME := 2.6
const SHOWER_DURATION := 9.0
const BASE_OBSERVATION_DURATION := 20.0
const MAX_OBSERVATION_DURATION := 60.0
const BASE_MAX_ACTIVE_METEORS := 4
const MAX_ACTIVE_METEORS := 18
const CANIS_FINAL_ACTIVE_CAPACITY_DELTA := 2
const CANIS_FINAL_REGULAR_SPAWN_INTERVAL_FLOOR := 0.70
const REGULAR_SPAWN_INTERVAL_MIN := 1.6
const REGULAR_SPAWN_INTERVAL_MAX := 2.4
const BRANCHES := {
	"optics": {"name": "OPTICS / MANUAL", "color": Color("53d6ff")},
	"detection": {"name": "DETECTION / DISCOVERY", "color": Color("b379ff")},
	"network": {"name": "OBSERVATION NETWORK", "color": Color("52e0b1")},
	"ursa_minor": {"name": "URSA MINOR / SKY SWEEP", "color": Color("ff9f7a")},
	"perseus": {"name": "PERSEUS / DENSITY", "color": Color("ffb56b")},
	"gemini": {"name": "GEMINI / ECHO", "color": Color("ffd27d")},
	"taurus": {"name": "TAURUS / MOMENTUM", "color": Color("ffbd7a")},
	"lyra": {"name": "LYRA / SPECTRUM", "color": Color("69a9ff")},
	"andromeda": {"name": "ANDROMEDA / LONG WATCH", "color": Color("ff78c8")},
	"leo": {"name": "LEO / METEOR STORM", "color": Color("ff9a66")},
	"canis_major": {"name": "CANIS MAJOR / CADENCE", "color": Color("8ad9ff")},
	"draco": {"name": "DRACO / CULMINATION", "color": Color("e8a6ff")},
}

# Existing upgrade ids are preserved so every gameplay consumer migrates without
# losing its original effect. Presentation coordinates live in research_chart_data.gd.
# `runtime_parameters` is production input, `effect_notes` is never executed,
# and `effect_contract` is an independent test oracle. Do not collapse the three:
# a test that derives its expected result from production input cannot detect drift.
const UPGRADE_NODES: Array[Dictionary] = [
	{
		"id": "better_lens", "name": "Better Lens", "icon": "◉", "cost": 10,
		"description": "Base observation radius increases by about 44%.",
		"branch": "optics", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"tracking_radius": 52.0},
		"major": false
	},
	{
		"id": "long_exposure", "name": "Long Exposure", "icon": "◐", "cost": 50,
		"description": "Meteor lifetime +35%.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_notes": {"lifetime_multiplier": 1.35},
		"major": false
	},
	{
		"id": "observation_streak", "name": "Observation Streak", "icon": "×3", "cost": 120,
		"description": "Observation Streak: manual successes add 8% Data per step after the first, up to +50%. Base time limit: 2.6 seconds.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_notes": {"step": 0.08, "maximum": 0.5},
		"major": false
	},
	{
		"id": "precision_multiplier", "name": "Precision Spectrometer", "icon": "⌾", "cost": 300,
		"description": "Centered manual tracking increases Data, up to 3 times.",
		"branch": "optics", "prerequisites": ["long_exposure"],
		"hidden_until": ["long_exposure"], "effect_type": "transformation", "effect_notes": {"precision_gain": 0.58},
		"major": false
	},
	{
		"id": "perfect_observation", "name": "Perfect Observation", "icon": "✦", "cost": 800,
		"description": "Manual grade bonus: Excellent +25% Data, Perfect +55%. All Observation Data ×2 (automatic included).",
		"branch": "optics", "prerequisites": ["precision_multiplier"],
		"hidden_until": ["precision_multiplier"], "effect_type": "transformation",
		"effect_notes": {"excellent_bonus": 1.25, "perfect_bonus": 1.55},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true
	},
	{
		"id": "edge_detection", "name": "Edge Detection", "icon": "≋", "cost": 50,
		"description": "Unlocks fast meteors.",
		"branch": "detection", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"meteor_type": "fast"},
		"major": false
	},
	{
		"id": "wide_field", "name": "Wide Field Sensor", "icon": "⌗", "cost": 100,
		"description": "Shows predicted arrival positions at least 2 seconds before meteors appear.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "unlock", "effect_notes": {"entry_warning": true},
		"major": false
	},
	{
		"id": "trajectory", "name": "Arrival Position Calibration", "icon": "➤", "cost": 220,
		"description": "Base maximum arrival-position error decreases by about 31%. Shows approach direction before arrival.",
		"branch": "detection", "prerequisites": ["wide_field", "contact_ledger"],
		"hidden_until": ["wide_field"], "effect_type": "unlock", "effect_notes": {"trajectory_line": true},
		"major": true
	},
	{
		"id": "rare_detection", "name": "Rare Meteor Detection", "icon": "★", "cost": 450,
		"description": "Unlocks luminous meteors and identifies incoming target types.",
		"branch": "detection", "prerequisites": ["trajectory"],
		"hidden_until": ["trajectory"], "effect_type": "discovery", "effect_notes": {"meteor_type": "fireball"},
		"major": true
	},
	{
		"id": "fragment_analysis", "name": "Fragment Tracking", "icon": "◆", "cost": 900,
		"description": "Unlocks splitting meteors and observable fragments.",
		"branch": "detection", "prerequisites": ["rare_detection"],
		"hidden_until": ["rare_detection"], "effect_type": "discovery", "effect_notes": {"meteor_type": "fragment"},
		"major": true
	},
	{
		"id": "shower_detector", "name": "Meteor Shower Forecast", "icon": "☄", "cost": 3000,
		"description": "Unlocks meteor showers: 2.6-second warning, 9-second duration. All Observation Data ×2 (automatic included).",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "discovery",
		"effect_notes": {"event": "meteor_shower"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true
	},
	{
		"id": "array_planning", "name": "Array Planning", "icon": "⬡", "cost": 110,
		"description": "Sky Activity: simultaneous regular targets +1.",
		"branch": "network", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"max_active": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": false
	},
	{
		"id": "observation_scheduling", "name": "Observation Scheduling", "icon": "◷", "cost": 150,
		"description": "Adds 10 seconds to each future observation window.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "passive",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": false
	},
	{
		"id": "thermal_management", "name": "Equipment Thermal Control", "icon": "❄", "cost": 450,
		"description": "Adds 10 seconds to each future observation window.",
		"branch": "network", "prerequisites": ["observation_scheduling"],
		"hidden_until": ["observation_scheduling"], "effect_type": "passive",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": false
	},
	{
		"id": "extended_watch_protocol", "name": "Extended Watch Protocol", "icon": "◴", "cost": 1000,
		"description": "Adds 10 seconds to each future observation window.",
		"branch": "network", "prerequisites": ["thermal_management"],
		"hidden_until": ["thermal_management"], "effect_type": "transformation",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": true
	},
	{
		"id": "continuous_watch_rotation", "name": "Continuous Watch Rotation", "icon": "↻", "cost": 1800,
		"description": "Adds 10 seconds to each future observation window, up to 60 seconds.",
		"branch": "network", "prerequisites": ["extended_watch_protocol"],
		"hidden_until": ["extended_watch_protocol"], "effect_type": "transformation",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": true
	},
	{
		"id": "secondary_camera", "name": "Secondary Camera", "icon": "▣", "cost": 600,
		"description": "Adds 1 movable observation dish and arrival warnings. Right-click to position it; luminous meteors require manual observation.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "automation", "effect_notes": {"assist_slots": 1},
		"major": true
	},
	{
		"id": "predictive_dish_control", "name": "Predictive Dish Control", "icon": "⌁", "cost": 1200,
		"description": "Automatically moves idle dishes to predicted arrival positions. Right-click placement takes priority.",
		"branch": "network", "prerequisites": ["secondary_camera"],
		"hidden_until": ["secondary_camera"], "effect_type": "automation", "effect_notes": {"dish_auto_assignment": true},
		"major": true
	},
	{
		"id": "multi_target_analysis", "name": "Multi-Target Tracking", "icon": "⊕", "cost": 2200,
		"description": "Observe every meteor in the cursor circle together. Auto-assist: 1 target. Sky Activity: simultaneous regular targets +1.",
		"branch": "network", "prerequisites": ["secondary_camera", "extended_watch_protocol"],
		"hidden_until": ["secondary_camera"], "effect_type": "transformation", "effect_notes": {"assist_slots": 2, "manual_group_tracking": true},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "automated_tracking", "name": "Automated Common Tracking", "icon": "⚙", "cost": 3500,
		"description": "Automatically fills ordinary meteor observation gauges. Rare targets still need manual observation.",
		"branch": "network", "prerequisites": ["multi_target_analysis"],
		"hidden_until": ["multi_target_analysis"], "effect_type": "automation", "effect_notes": {"common_rate": 0.29},
		"major": true
	},
	{
		"id": "observatory_network", "name": "Observatory Network", "icon": "✧", "cost": 6000,
		"description": "Movable dishes: 1 → 2. Automatic support: 1 → 2 targets. Adds meteor-shower entry forecasts.",
		"branch": "network", "prerequisites": ["automated_tracking"],
		"hidden_until": ["automated_tracking"], "effect_type": "transformation", "effect_notes": {"assist_slots": 3, "shower_preview": true},
		"major": true
	},
	{
		"id": "contact_ledger", "name": "Forecast Log", "icon": "≣", "cost": 180,
		"description": "Base maximum arrival-position error decreases by about 17%.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "transformation", "effect_notes": {"forecast_error_scale": 0.82},
		"major": false
	},
	{
		"id": "companion_resolution", "name": "Companion Resolution", "icon": "∴", "cost": 1800,
		"description": "Data from fragment pieces +35%.",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "transformation", "effect_notes": {"fragment_piece_value_multiplier": 1.35},
		"major": true
	},
	{
		"id": "polar_survey", "name": "Sky Sweep", "icon": "✣", "cost": 120,
		"description": "Each sweep of about 40% screen width has a 30% summon chance. Keep holding to switch between empty-sky sweeping and target observation.",
		"branch": "ursa_minor", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"survey_distance": 460.0, "survey_probability": 0.30},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sweep_gain", "name": "Sweep Gain", "icon": "⌁", "cost": 180,
		"description": "Sky Sweep distance per attempt decreases by about 17%.",
		"branch": "ursa_minor", "prerequisites": ["polar_survey"],
		"hidden_until": ["polar_survey"], "effect_type": "passive", "effect_notes": {"survey_distance": 380.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "faint_recovery", "name": "Faint Recovery", "icon": "◌", "cost": 600,
		"description": "Sky Sweep success chance: 30% → 42%.",
		"branch": "ursa_minor", "prerequisites": ["sweep_gain"],
		"hidden_until": ["sweep_gain"], "effect_type": "passive", "effect_notes": {"survey_probability": 0.42},
		"major": false, "affects_pacing": false
	},
	{
		"id": "sustained_sweep", "name": "Sustained Sweep", "icon": "▧", "cost": 1200,
		"description": "Keeps Sky Sweep charge after releasing the button. Resets at round end.",
		"branch": "ursa_minor", "prerequisites": ["faint_recovery"],
		"hidden_until": ["faint_recovery"], "effect_type": "transformation", "effect_notes": {"persistent_survey_charge": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "deep_exposure", "name": "Deep Exposure", "icon": "+", "cost": 2200,
		"description": "Sky Sweep success chance: 42% → 55%.",
		"branch": "ursa_minor", "prerequisites": ["sustained_sweep"],
		"hidden_until": ["sustained_sweep"], "effect_type": "passive", "effect_notes": {"survey_probability": 0.55},
		"major": false, "affects_pacing": false
	},
	{
		"id": "rapid_scan", "name": "Rapid Scan", "icon": "↻", "cost": 3500,
		"description": "Sky Sweep cooldown after success: 1.5 → 0.9 seconds.",
		"branch": "ursa_minor", "prerequisites": ["deep_exposure"],
		"hidden_until": ["deep_exposure"], "effect_type": "passive", "effect_notes": {"survey_cooldown": 0.9},
		"major": false, "affects_pacing": false
	},
	{
		"id": "polar_cascade", "name": "Polar Cascade", "icon": "✦", "cost": 6000,
		"description": "Meteors per successful Sky Sweep: 1 → 2.",
		"branch": "ursa_minor", "prerequisites": ["rapid_scan"],
		"hidden_until": ["rapid_scan"], "effect_type": "transformation", "effect_notes": {"survey_spawn_count": 2},
		"major": true, "affects_pacing": false
	},
	{
		"id": "radiant_plotting", "name": "Arrival Cadence", "icon": "✺", "cost": 10000,
		"description": "Regular meteor arrival interval −6%.",
		"branch": "perseus", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"spawn_interval_multiplier": 0.94},
		"major": false
	},
	{
		"id": "crowd_forecast", "name": "Crowd Forecast", "icon": "⌁", "cost": 18000,
		"description": "Arrival warnings appear 0.8 seconds earlier.",
		"branch": "perseus", "prerequisites": ["radiant_plotting"],
		"hidden_until": ["radiant_plotting"], "effect_type": "unlock", "effect_notes": {"forecast_lead_bonus": 0.8},
		"major": false
	},
	{
		"id": "burst_windowing", "name": "Arrival Compression", "icon": "⋮", "cost": 25000,
		"description": "Regular meteor arrival interval −12%.",
		"branch": "perseus", "prerequisites": ["crowd_forecast"],
		"hidden_until": ["crowd_forecast"], "effect_type": "transformation", "effect_notes": {"spawn_interval_multiplier": 0.88},
		"major": false
	},
	{
		"id": "debris_correlation", "name": "Debris Correlation", "icon": "⟡", "cost": 35000,
		"description": "Data from splitting meteors and fragment pieces +20%.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "transformation", "effect_notes": {"fragment_value_multiplier": 1.2},
		"major": false
	},
	{
		"id": "cascade_sampling", "name": "Cascade Sampling", "icon": "⠿", "cost": 100000,
		"description": "Sky Activity: simultaneous regular targets +1.",
		"branch": "perseus", "prerequisites": ["debris_correlation"],
		"hidden_until": ["debris_correlation"], "effect_type": "passive", "effect_notes": {"max_active": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "adaptive_exposure_grid", "name": "Adaptive Exposure Grid", "icon": "▦", "cost": 30000,
		"description": "Meteor and long-target lifetime +12%.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "passive", "effect_notes": {"lifetime_multiplier": 1.12},
		"major": true
	},
	{
		"id": "perseid_survey", "name": "Perseid Watch", "icon": "✹", "cost": 45000,
		"description": "3 visible targets grant +18% meteor Data. Sky Activity: simultaneous regular targets +1.",
		"branch": "perseus", "prerequisites": ["adaptive_exposure_grid"],
		"hidden_until": ["adaptive_exposure_grid"], "effect_type": "transformation", "effect_notes": {"max_active": 1, "crowd_value_multiplier": 1.18},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "filter_wheel", "name": "Calibration Framework", "icon": "◒", "cost": 15000,
		"description": "Unlocks band calibration and ice-asteroid research.",
		"branch": "lyra", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"opens_band_calibration": true},
		"implementation_connection": "prerequisite_only",
		"major": false
	},
	{
		"id": "blue_band", "name": "Blue Band", "icon": "B", "cost": 25000,
		"description": "Common meteors, giant meteors and satellites: manual speed +25%, manual Data +15%.",
		"branch": "lyra", "prerequisites": ["filter_wheel"],
		"hidden_until": ["filter_wheel"], "effect_type": "passive", "effect_notes": {"calibration": "blue"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": false
	},
	{
		"id": "amber_band", "name": "Amber Band", "icon": "A", "cost": 35000,
		"description": "Fragments, luminous meteors, comets and planets: manual speed +25%, manual Data +15%.",
		"branch": "lyra", "prerequisites": ["blue_band"],
		"hidden_until": ["blue_band"], "effect_type": "passive", "effect_notes": {"calibration": "amber"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": false
	},
	{
		"id": "violet_band", "name": "Violet Band", "icon": "V", "cost": 45000,
		"description": "Fast meteors, fragment pieces, asteroids and ice asteroids: manual speed +25%, manual Data +15%.",
		"branch": "lyra", "prerequisites": ["amber_band"],
		"hidden_until": ["amber_band"], "effect_type": "passive", "effect_notes": {"calibration": "violet"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": true
	},
	{
		"id": "lyrid_spectrograph", "name": "Lyrid Spectrograph", "icon": "≋", "cost": 120000,
		"description": "All bands: manual speed bonus +25% → +45%, manual Data bonus +15% → +35%.",
		"branch": "lyra", "prerequisites": ["violet_band"],
		"hidden_until": ["violet_band"], "effect_type": "transformation", "effect_notes": {"calibrated_speed": 1.45, "calibrated_value": 1.35},
		"major": true
	},
	{
		"id": "ephemeris_marks", "name": "Ephemeris Marks", "icon": "⊹", "cost": 20000,
		"description": "Arrival warnings appear 1 second earlier, including dish forecasts.",
		"branch": "andromeda", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"deep_forecast": true},
		"major": false
	},
	{
		"id": "satellite_catalog", "name": "Satellite Catalog", "icon": "▰", "cost": 30000,
		"description": "Unlocks slow-moving satellites for observation.",
		"branch": "andromeda", "prerequisites": ["ephemeris_marks"],
		"hidden_until": ["ephemeris_marks"], "effect_type": "discovery", "effect_notes": {"target_type": "satellite"},
		"major": false
	},
	{
		"id": "change_detection", "name": "Change Detection", "icon": "Δ", "cost": 40000,
		"description": "Identifies satellites, asteroids, comets and planets. Maximum forecast error: about 2% of screen width.",
		"branch": "andromeda", "prerequisites": ["satellite_catalog"],
		"hidden_until": ["satellite_catalog"], "effect_type": "transformation", "effect_notes": {"deep_classification": true},
		"major": false
	},
	{
		"id": "variable_watchlist", "name": "Long-Target Tracking", "icon": "≈", "cost": 150000,
		"description": "Satellite and comet manual observation speed +30%.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "transformation", "effect_notes": {"small_body_tracking": 1.3},
		"major": true
	},
	{
		"id": "comet_solutions", "name": "Comet Tracking", "icon": "☄", "cost": 50000,
		"description": "Unlocks slow comets that remain until the round ends.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "discovery", "effect_notes": {"target_type": "comet"},
		"major": true
	},
	{
		"id": "andromeda_deep_survey", "name": "Long-Target Survey", "icon": "◎", "cost": 65000,
		"description": "Satellites, asteroids, comets and planets: manual speed +25%, Data +30% (automatic included).",
		"branch": "andromeda", "prerequisites": ["comet_solutions"],
		"hidden_until": ["comet_solutions"], "effect_type": "transformation", "effect_notes": {"deep_speed": 1.25, "deep_value": 1.3},
		"major": true
	},
	{
		"id": "echo_correlation_10", "name": "Echo Discovery", "icon": "10%", "cost": 12000,
		"description": "Manual observation has a 10% chance to summon 1 extra meteor (Echo).",
		"branch": "gemini", "prerequisites": [],
		"hidden_until": [], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.10, "echo_count": 1},
		"major": false
	},
	{
		"id": "echo_correlation_20", "name": "Echo Amplification", "icon": "20%", "cost": 18000,
		"description": "Echo chance after manual observation: 10% → 20%.",
		"branch": "gemini", "prerequisites": ["echo_correlation_10"],
		"hidden_until": ["echo_correlation_10"], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.20},
		"major": true
	},
	{
		"id": "single_echo_channel", "name": "Echo Channel I", "icon": "+1", "cost": 25000,
		"description": "Meteors per Echo: 1 → 2.",
		"branch": "gemini", "prerequisites": ["echo_correlation_10"],
		"hidden_until": [], "effect_type": "transformation", "effect_notes": {"echo_count": 2},
		"major": false
	},
	{
		"id": "dual_echo_channel", "name": "Echo Channel II", "icon": "+2", "cost": 35000,
		"description": "Meteors per Echo: 2 → 3.",
		"branch": "gemini", "prerequisites": ["single_echo_channel"],
		"hidden_until": ["single_echo_channel"], "effect_type": "transformation", "effect_notes": {"echo_count": 3},
		"major": false
	},
	{
		"id": "triple_echo_array", "name": "Echo Channel III", "icon": "+3", "cost": 50000,
		"description": "Meteors per Echo: 3 → 4.",
		"branch": "gemini", "prerequisites": ["dual_echo_channel"],
		"hidden_until": ["dual_echo_channel"], "effect_type": "transformation", "effect_notes": {"echo_count": 4},
		"major": true
	},
	{
		"id": "leonid_radiant", "name": "Leonid Radiant", "icon": "10", "cost": 25000,
		"description": "Every 10 manual observations of natural targets trigger 8 meteors over 7 seconds. Giant meteors do not count.",
		"branch": "leo", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"manual_trigger": 10, "storm_count": 8},
		"major": true
	},
	{
		"id": "compressed_cadence", "name": "Compressed Cadence", "icon": "9", "cost": 35000,
		"description": "Storm trigger: 10 → 9 manual observations. Meteors per storm: 8.",
		"branch": "leo", "prerequisites": ["leonid_radiant"],
		"hidden_until": ["leonid_radiant"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 9, "storm_count": 8},
		"major": false
	},
	{
		"id": "dense_stream", "name": "Dense Stream", "icon": "8", "cost": 50000,
		"description": "Storm trigger: 9 → 8 manual observations. Meteors per storm: 8 → 12.",
		"branch": "leo", "prerequisites": ["compressed_cadence"],
		"hidden_until": ["compressed_cadence"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 8, "storm_count": 12},
		"major": true
	},
	{
		"id": "rapid_reacquisition", "name": "Rapid Reacquisition", "icon": "7", "cost": 65000,
		"description": "Storm trigger: 8 → 7 manual observations. Meteors per storm: 12.",
		"branch": "leo", "prerequisites": ["dense_stream"],
		"hidden_until": ["dense_stream"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 7, "storm_count": 12},
		"major": false
	},
	{
		"id": "storm_front", "name": "Storm Front", "icon": "6", "cost": 80000,
		"description": "Storm trigger: 7 → 6 manual observations. Meteors per storm: 12 → 16.",
		"branch": "leo", "prerequisites": ["rapid_reacquisition"],
		"hidden_until": ["rapid_reacquisition"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 6, "storm_count": 16},
		"major": true
	},
	{
		"id": "leonid_storm", "name": "Storm Zenith", "icon": "5", "cost": 250000,
		"description": "Storm trigger: 6 → 5 manual observations. Meteors per storm: 16 → 20 over 7 seconds.",
		"branch": "leo", "prerequisites": ["storm_front"],
		"hidden_until": ["storm_front"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 5, "storm_count": 20},
		"major": true
	},
	{
		"id": "perseid_outburst", "name": "Perseid Outburst", "icon": "✺", "cost": 80000,
		"description": "Unlocks Perseid bursts: 8 meteors over 3.4 seconds, after a warning. All Observation Data ×1.5 (automatic included).",
		"branch": "perseus", "prerequisites": ["perseid_survey"],
		"hidden_until": ["perseid_survey"], "effect_type": "discovery",
		"effect_notes": {"event": "perseid_outburst"},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "double_star_resolution", "name": "Precision Analysis", "icon": "⁚", "cost": 20000,
		"description": "Accurate ice asteroid forecasts. All Observation Data ×1.5 (automatic included).",
		"branch": "lyra", "prerequisites": ["filter_wheel"],
		"hidden_until": ["filter_wheel"], "effect_type": "discovery",
		"effect_notes": {"precise_forecast": true},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "galaxy_imaging", "name": "Deep-Sky Analysis", "icon": "M31", "cost": 100000,
		"description": "All Observation Data ×1.5 (automatic included).",
		"branch": "andromeda", "prerequisites": ["andromeda_deep_survey"],
		"hidden_until": ["andromeda_deep_survey"], "effect_type": "discovery",
		"effect_notes": {"deep_analysis": true},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "split_radiant_model", "name": "Split Radiant Model", "icon": "⋔", "cost": 35000,
		"description": "Storm meteors alternate between 2 mirrored entry areas.",
		"branch": "leo", "prerequisites": ["leonid_radiant"],
		"hidden_until": ["leonid_radiant"], "effect_type": "transformation", "effect_notes": {"storm_radiants": 2},
		"major": false, "affects_pacing": false
	},
	{
		"id": "fragment_front", "name": "Fragment Front", "icon": "◆", "cost": 50000,
		"description": "Each meteor storm starts with a splitting meteor.",
		"branch": "leo", "prerequisites": ["split_radiant_model"],
		"hidden_until": ["split_radiant_model"], "effect_type": "discovery", "effect_notes": {"storm_lead_type": "fragment"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "fireball_tail", "name": "Luminous Meteor Tail", "icon": "★", "cost": 80000,
		"description": "Each meteor storm ends with a manual-only luminous meteor. All Observation Data ×1.5 (automatic included).",
		"branch": "leo", "prerequisites": ["fragment_front"],
		"hidden_until": ["fragment_front"], "effect_type": "discovery",
		"effect_notes": {"storm_tail_type": "fireball"},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_signature_lock", "name": "Echo Signature Lock", "icon": "≡", "cost": 25000,
		"description": "Echoes repeat the observed meteor type: common, fast, fragment or luminous meteor. Other types give a random meteor.",
		"branch": "gemini", "prerequisites": ["echo_correlation_20"],
		"hidden_until": ["echo_correlation_20"], "effect_type": "transformation", "effect_notes": {"echo_signature_lock": true},
		"major": false, "affects_pacing": false
	},
	{
		"id": "mirror_echo_solution", "name": "Opposite-Side Echo", "icon": "⇋", "cost": 35000,
		"description": "Echo meteors appear from the opposite side on a mirrored path.",
		"branch": "gemini", "prerequisites": ["echo_signature_lock"],
		"hidden_until": ["echo_signature_lock"], "effect_type": "transformation", "effect_notes": {"mirror_echo_path": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_delay_line", "name": "Echo Delay Line", "icon": "⋯", "cost": 60000,
		"description": "Echo meteors arrive 0.75 seconds apart. All Observation Data ×1.5 (automatic included).",
		"branch": "gemini", "prerequisites": ["mirror_echo_solution"],
		"hidden_until": ["mirror_echo_solution"], "effect_type": "unlock",
		"effect_notes": {"echo_delay_line": true},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_deconfliction", "name": "Echo Spacing", "icon": "⌗", "cost": 200000,
		"description": "Spreads echo meteors apart to prevent overlap.",
		"branch": "gemini", "prerequisites": ["triple_echo_array"],
		"hidden_until": ["triple_echo_array"], "effect_type": "automation", "effect_notes": {"echo_deconfliction": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_beacon", "name": "Echo Beacon", "icon": "⌁", "cost": 250000,
		"description": "Warns of echo arrival positions 1.25 seconds in advance.",
		"branch": "gemini", "prerequisites": ["triple_echo_array"],
		"hidden_until": ["triple_echo_array"], "effect_type": "unlock", "effect_notes": {"echo_forecast": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "momentum_acquisition", "name": "Streak Acquisition", "icon": "×4", "cost": 25000,
		"description": "Observation Streak: lasts 3 seconds, up to 4 bonuses. Each adds +2% manual speed and about 2.8% of the starting radius.",
		"branch": "taurus", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"combo_window": 3.0, "combo_cap": 4, "speed_per_stack": 0.02, "radius_per_stack": 1.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "wide_pursuit", "name": "Wide Pursuit", "icon": "+1.5", "cost": 250000,
		"description": "Each Observation Streak step adds about 1.4% of the starting observation radius.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "passive", "effect_notes": {"radius_bonus_per_stack": 0.5},
		"major": false, "affects_pacing": false
	},
	{
		"id": "rapid_focus", "name": "Rapid Focus", "icon": "+3%", "cost": 300000,
		"description": "Observation Streak: manual-speed bonus +1% per step, added to other speed bonuses.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "passive", "effect_notes": {"speed_bonus_per_stack": 0.01},
		"major": false, "affects_pacing": false
	},
	{
		"id": "cadence_memory", "name": "Cadence Memory", "icon": "3.5s", "cost": 40000,
		"description": "Observation Streak time limit: 3 → 3.5 seconds. Bonus steps: 4 → 5.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "transformation", "effect_notes": {"combo_window": 3.5, "combo_cap": 5},
		"major": false, "affects_pacing": false
	},
	{
		"id": "expanded_sweep", "name": "Expanded Sweep", "icon": "+2", "cost": 60000,
		"description": "Observation Streak: doubles its basic radius bonus. Wide Pursuit adds separately.",
		"branch": "taurus", "prerequisites": ["cadence_memory"],
		"hidden_until": ["cadence_memory"], "effect_type": "passive", "effect_notes": {"radius_per_stack": 2.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "accelerated_analysis", "name": "Faster Observation", "icon": "+4%", "cost": 80000,
		"description": "Observation Streak: each success adds +4% manual speed instead of +2%. Rapid Focus adds separately.",
		"branch": "taurus", "prerequisites": ["expanded_sweep"],
		"hidden_until": ["expanded_sweep"], "effect_type": "transformation", "effect_notes": {"speed_per_stack": 0.04},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sustained_charge", "name": "Sustained Charge", "icon": "×7", "cost": 100000,
		"description": "Observation Streak time limit: 3.5 → 4 seconds. Bonus steps: 5 → 7.",
		"branch": "taurus", "prerequisites": ["accelerated_analysis"],
		"hidden_until": ["accelerated_analysis"], "effect_type": "transformation", "effect_notes": {"combo_window": 4.0, "combo_cap": 7},
		"major": true, "affects_pacing": false
	},
	{
		"id": "taurus_full_gallop", "name": "Full Gallop", "icon": "×10", "cost": 180000,
		"description": "Observation Streak time limit: 4 → 5 seconds. Bonus steps: 7 → 10. All Observation Data ×1.5 (automatic included).",
		"branch": "taurus", "prerequisites": ["sustained_charge"],
		"hidden_until": ["sustained_charge"], "effect_type": "transformation",
		"effect_notes": {"combo_window": 5.0, "combo_cap": 10},
		"runtime_parameters": {"observation_value_multiplier": 1.5},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 1.5, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_opening", "name": "Canis Relay", "icon": "CMa", "cost": 150000,
		"description": "Unlocks Canis Major research.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"canis_major_branch": true},
		"implementation_connection": "prerequisite_only",
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_cadence_i", "name": "Swift Signal", "icon": "×2.00", "cost": 200000,
		"description": "Sky Activity: raise the base natural spawn rate ceiling to ×2.00.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 1.0},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 1.0, "scope": "regular_meteor_arrivals"},
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_capacity_i", "name": "Long Leash", "icon": "+1", "cost": 180000,
		"description": "Sky Activity: simultaneous regular targets +1.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"max_active_delta": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_cadence_ii", "name": "Running Cadence", "icon": "×2.35", "cost": 400000,
		"description": "Sky Activity: raise the base natural spawn rate ceiling to ×2.35.",
		"branch": "canis_major", "prerequisites": ["canis_capacity_i"],
		"hidden_until": ["canis_capacity_i"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.85},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.85, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_capacity_ii", "name": "Twin Watch", "icon": "+1", "cost": 600000,
		"description": "Sky Activity: simultaneous regular targets +1.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"max_active_delta": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_cadence_iii", "name": "White-Star Tempo", "icon": "×2.86", "cost": 800000,
		"description": "Sky Activity: raise the base natural spawn rate ceiling to ×2.86.",
		"branch": "canis_major", "prerequisites": ["canis_opening", "canis_cadence_ii"],
		"hidden_until": ["canis_opening", "canis_cadence_ii"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.70},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.70, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_capacity_iii", "name": "Pack Array", "icon": "+2", "cost": 1000000,
		"description": "Sky Activity: simultaneous regular targets +2.",
		"branch": "canis_major", "prerequisites": ["canis_cadence_iii"],
		"hidden_until": ["canis_cadence_iii"], "effect_type": "passive", "effect_notes": {"max_active_delta": 2},
		"effect_contract": {"kind": "max_active_delta", "value": 2, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sirius_fireball", "name": "Sirius Bloom", "icon": "★", "cost": 1500000,
		"description": "Unlocks a giant meteor, up to 1 per round with enough time left. Manual observation required.",
		"branch": "canis_major", "prerequisites": ["canis_capacity_ii", "canis_cadence_i", "canis_capacity_iii"],
		"hidden_until": ["canis_capacity_ii", "canis_cadence_i", "canis_capacity_iii"], "effect_type": "unlock", "effect_notes": {"major_fireball_per_round": 1},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_synthesis", "name": "All-Sky Synthesis", "icon": "×4", "cost": 800000,
		"description": "All Observation Data ×4 (automatic included).",
		"branch": "draco", "prerequisites": [],
		"hidden_until": [{"type": "other_constellations_complete", "excluded_branch": "draco"}],
		"effect_type": "transformation", "effect_notes": {"culmination_gate": true},
		"runtime_parameters": {"observation_value_multiplier": 4.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 4.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_cadence", "name": "Circumpolar Cadence", "icon": "×4.44", "cost": 1500000,
		"description": "Sky Activity: raise the base natural spawn rate ceiling to ×4.44.",
		"branch": "draco", "prerequisites": ["draco_synthesis"],
		"hidden_until": ["draco_synthesis"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.45},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.45, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_capacity", "name": "Dragon-Spine Array", "icon": "+6", "cost": 4000000,
		"description": "Sky Activity: simultaneous regular targets +6.",
		"branch": "draco", "prerequisites": ["draco_cadence"],
		"hidden_until": ["draco_cadence"], "effect_type": "transformation", "effect_notes": {"max_active_delta": 6},
		"effect_contract": {"kind": "max_active_delta", "value": 6, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_sweep", "name": "Coiled-Sky Sweep", "icon": "4×", "cost": 6000000,
		"description": "Sky Sweep: distance −50%, success 100%, 4 meteors, 0.45-second cooldown.",
		"branch": "draco", "prerequisites": ["draco_capacity"],
		"hidden_until": ["draco_capacity"], "effect_type": "transformation", "effect_notes": {"survey_distance": 190.0, "survey_probability": 1.0, "survey_count": 4, "survey_cooldown": 0.45},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_echo", "name": "Polar Resonance", "icon": "6×", "cost": 8000000,
		"description": "Echo chance 20% → 65%. Meteors per Echo 4 → 6.",
		"branch": "draco", "prerequisites": ["draco_sweep"],
		"hidden_until": ["draco_sweep"], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.65, "echo_count": 6},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_storm", "name": "Radiant Convergence", "icon": "30", "cost": 10000000,
		"description": "Storm trigger: 5 → 2 manual observations. Meteors per storm: 20 → 30.",
		"branch": "draco", "prerequisites": ["draco_echo"],
		"hidden_until": ["draco_echo"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 2, "storm_count": 30},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_array", "name": "Total Array", "icon": "4+4", "cost": 12000000,
		"description": "Movable dishes: 2 → 4. Automatic support: 2 → 4 targets.",
		"branch": "draco", "prerequisites": ["draco_storm"],
		"hidden_until": ["draco_storm"], "effect_type": "transformation", "effect_notes": {"dish_count": 4, "support_lanes": 4},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_apotheosis", "name": "Dragon's Eye", "icon": "×4", "cost": 15000000,
		"description": "All Observation Data ×4 (automatic included).",
		"branch": "draco", "prerequisites": ["draco_array"],
		"hidden_until": ["draco_array"], "effect_type": "transformation", "effect_notes": {"culmination_multiplier": true},
		"runtime_parameters": {"observation_value_multiplier": 4.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 4.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "galactic_reference_frame", "name": "Galactic Reference Frame", "icon": "MW", "cost": 50000000,
		"description": "Unlocks outer research, rare meteors and modules.",
		"branch": "draco", "prerequisites": ["draco_apotheosis"],
		"hidden_until": ["draco_apotheosis"], "effect_type": "unlock", "effect_notes": {"galactic_survey": true},
		"major": true, "affects_pacing": false
	},
]


static var _upgrade_definitions_by_id: Dictionary = _build_upgrade_definition_index()


static func _build_upgrade_definition_index() -> Dictionary:
	# Definitions are constant, so this index never needs progression/locale/save
	# invalidation. Keep the ordered array as the source of truth for all consumers
	# that enumerate research; only ID lookup avoids scanning all 107 definitions.
	var definitions: Dictionary = {}
	for definition in UPGRADE_NODES:
		var node_id := String(definition.id)
		if not definitions.has(node_id):
			definitions[node_id] = definition
	definitions.make_read_only()
	return definitions


static func upgrade_definition(id: String) -> Dictionary:
	if _upgrade_definitions_by_id.has(id):
		return _upgrade_definitions_by_id[id]
	# Preserve the old fresh mutable result on a miss; do not share a fallback.
	return {}


static func research_node_count() -> int:
	return UPGRADE_NODES.size()


# Legacy target IDs preserve purchased research and existing saves.
# variable_star / binary_star / galaxy now mean asteroid / ice asteroid / planet.
static func meteor_spec(type_id: String) -> Dictionary:
	match type_id:
		"fast":
			return {
				"name": "FAST METEOR", "speed": 390.0, "lifetime": 3.65,
				"radius": 6.0, "trail": 30, "value": 24.0, "track_time": 0.82,
				"color": Color("8eeaff"), "glow": Color("46aaff"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.08, "burn_fade_start": 0.84, "burn_style": "snap",
				"burnout_linger": 0.12,
			}
		"fragment":
			return {
				"name": "FRAGMENTING METEOR", "speed": 255.0, "lifetime": 5.1,
				"radius": 9.0, "trail": 34, "value": 30.0, "track_time": 1.08,
				"color": Color("d8c5ff"), "glow": Color("a26cff"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.20, "burn_fade_start": 0.60, "burn_style": "split",
				"burn_wobble": 4.5, "split_progress": 0.46, "burnout_linger": 0.24,
			}
		"fragment_piece":
			return {
				"name": "FRAGMENT", "speed": 280.0, "lifetime": 2.9,
				"radius": 5.0, "trail": 22, "value": 11.0, "track_time": 0.62,
				"color": Color("e8d9ff"), "glow": Color("bf8cff"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.12, "burn_fade_start": 0.72, "burn_style": "spark",
				"burn_wobble": 3.2, "burnout_linger": 0.16,
			}
		"fireball":
			return {
				"name": "LUMINOUS METEOR", "speed": 190.0, "lifetime": 7.4,
				"radius": 19.0, "trail": 52, "value": 82.0, "track_time": 1.75,
				"color": Color("fff2b0"), "glow": Color("ff7438"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.12, "burn_fade_start": 0.74, "burn_style": "flare",
				"burnout_linger": 0.38,
			}
		"major":
			return {
				"name": "GIANT METEOR", "speed": 128.0, "lifetime": 14.0,
				"radius": 35.0, "trail": 82, "value": 650.0, "track_time": 3.0,
				"color": Color("fff8d6"), "glow": Color("ff4d32"),
				"spectral_band": "blue",
				"burn_terminal_ratio": 0.90, "burn_fade_start": 0.96, "burn_style": "major",
				"split_progress": 0.57, "burnout_linger": 0.42,
			}
		"satellite":
			return {
				"name": "ARTIFICIAL SATELLITE", "speed": 72.0, "lifetime": 28.0,
				"radius": 8.0, "trail": 18, "value": 62.0, "track_time": 2.4,
				"color": Color("d6edff"), "glow": Color("68b9ff"),
				"spectral_band": "blue",
				"burn_terminal_ratio": 1.0, "burn_fade_start": 0.94, "burn_style": "satellite",
				"burnout_linger": 0.24,
			}
		"variable_star":
			return {
				"name": "ASTEROID", "speed": 24.0, "lifetime": 34.0,
				"radius": 43.0, "trail": 10, "value": 96.0, "track_time": 3.4,
				"color": Color("a89b8b"), "glow": Color("d4bda2"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.82, "burn_fade_start": 0.95, "burn_style": "rock",
				"burnout_linger": 0.32,
			}
		"comet":
			return {
				"name": "LONG-ARC COMET", "speed": 54.0, "lifetime": 40.0,
				"radius": 17.0, "trail": 70, "value": 145.0, "track_time": 4.2,
				"color": Color("fff4cf"), "glow": Color("72e0d2"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.74, "burn_fade_start": 0.92, "burn_style": "comet",
				"burn_wobble": 2.0, "burnout_linger": 0.42,
			}
		"binary_star":
			return {
				"name": "ICE ASTEROID", "speed": 32.0, "lifetime": 34.0,
				"radius": 48.0, "trail": 12, "value": 118.0, "track_time": 3.8,
				"color": Color("b0e5ef"), "glow": Color("80cbdc"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.88, "burn_fade_start": 0.95, "burn_style": "ice",
				"burnout_linger": 0.34,
			}
		"galaxy":
			return {
				"name": "PLANET", "speed": 20.0, "lifetime": 40.0,
				"radius": 64.0, "trail": 8, "value": 220.0, "track_time": 5.2,
				"color": Color("b7a181"), "glow": Color("e3c8a0"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.94, "burn_fade_start": 0.97, "burn_style": "planet",
				"burnout_linger": 0.48,
			}
		"black_hole":
			return {
				"name": "BLACK HOLE", "speed": 28.0, "lifetime": 32.0,
				"radius": 38.0, "trail": 0, "value": 240.0, "track_time": 4.8,
				"color": Color("b5b1ce"), "glow": Color("8685aa"),
				"spectral_band": "amber", "burn_terminal_ratio": 0.94,
				"burn_fade_start": 0.96, "burn_style": "black_hole", "burnout_linger": 0.4,
			}
		_:
			return {
				"name": "COMMON METEOR", "speed": 220.0, "lifetime": 5.0,
				"radius": 7.5, "trail": 28, "value": 14.0, "track_time": 0.95,
				"color": Color("f3fbff"), "glow": Color("78bfff"),
				"spectral_band": "blue",
				"burn_terminal_ratio": 0.25, "burn_fade_start": 0.68, "burn_style": "ember",
				"burnout_linger": 0.20,
			}
