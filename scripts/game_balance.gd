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
const GALACTIC_OBSERVATION_SPAN_STEP := 1.1025
# These are the galaxy nodes that move the observation camera. Keeping the list
# here makes the automatic screen-space compensation and the research effects
# share one source of truth.
const GALACTIC_SPAN_NODE_IDS: Array[String] = [
	"m33_transit_network",
	"ic1613_supernova_ephemeris",
	"phoenix_lensed_meteors",
	"aquarius_local_group_record",
]
const GALACTIC_OBSERVATION_PROFILES := {
	"lmc_transit_watch": {
		"tracking_time_multiplier": 1.0, "visual_scale": 1.0,
		"brightness": 1.0, "reward_multiplier": 1.0,
	},
	"smc_reference_baseline": {
		"tracking_time_multiplier": 1.35, "visual_scale": 0.82,
		"brightness": 0.70, "reward_multiplier": 1.15,
	},
	"m31_hidden_decoy_survey": {
		"tracking_time_multiplier": 1.12, "visual_scale": 1.36,
		"brightness": 0.90, "reward_multiplier": 1.25,
		"drift_radius_screen": 30.0, "drift_speed": 0.34,
	},
	"m33_transit_network": {
		"tracking_time_multiplier": 1.0, "visual_scale": 1.04,
		"brightness": 1.0, "reward_multiplier": 1.30,
	},
}
# pow(1.1025, 4): the single upper bound for the four chapter milestones.
# Like CANIS_FINAL_REGULAR_SPAWN_INTERVAL_FLOOR, this is the rollback handle:
# setting it to 1.0 disables the whole observation expansion without touching
# research ids, prices, or saves.
const GALACTIC_FINAL_OBSERVATION_SPAN := 1.4774554
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
	"local_group": {"name": "LOCAL GROUP / PHENOMENA", "color": Color("ffd7a0")}
}

# Existing upgrade ids are preserved so every gameplay consumer migrates without
# losing its original effect. Presentation coordinates live in research_chart_data.gd.
# `runtime_parameters` is production input, `effect_notes` is never executed,
# and `effect_contract` is an independent test oracle. Do not collapse the three:
# a test that derives its expected result from production input cannot detect drift.
const UPGRADE_NODES: Array[Dictionary] = [
	{
		"id": "better_lens", "name": "Better Lens", "icon": "◉", "cost": 10,
		"description": "A wider focus ring makes manual tracking more forgiving.",
		"branch": "optics", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"tracking_radius": 52.0},
		"major": false
	},
	{
		"id": "long_exposure", "name": "Long Exposure", "icon": "◐", "cost": 50,
		"description": "Meteors stay visible 35% longer and leave denser trails.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_notes": {"lifetime_multiplier": 1.35},
		"major": false
	},
	{
		"id": "observation_streak", "name": "Observation Streak", "icon": "×3", "cost": 120,
		"description": "Manual observations completed before the combo timer expires build a modest reward chain.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_notes": {"step": 0.08, "maximum": 0.5},
		"major": false
	},
	{
		"id": "precision_multiplier", "name": "Precision Spectrometer", "icon": "⌾", "cost": 300,
		"description": "Centered manual tracking builds a reward multiplier.",
		"branch": "optics", "prerequisites": ["long_exposure"],
		"hidden_until": ["long_exposure"], "effect_type": "transformation", "effect_notes": {"precision_gain": 0.58},
		"major": false
	},
	{
		"id": "perfect_observation", "name": "Perfect Observation", "icon": "✦", "cost": 800,
		"description": "Grades manual tracking; Excellent and Perfect runs earn ×1.25 and ×1.55 quality bonuses. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "optics", "prerequisites": ["precision_multiplier"],
		"hidden_until": ["precision_multiplier"], "effect_type": "transformation",
		"effect_notes": {"excellent_bonus": 1.25, "perfect_bonus": 1.55},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true
	},
	{
		"id": "edge_detection", "name": "Edge Detection", "icon": "≋", "cost": 30,
		"description": "Identifies fast arrivals and introduces fast meteors.",
		"branch": "detection", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"meteor_type": "fast"},
		"major": false
	},
	{
		"id": "wide_field", "name": "Wide Field Sensor", "icon": "⌗", "cost": 100,
		"description": "Shows where incoming objects are expected to appear so you have time to prepare.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "unlock", "effect_notes": {"entry_warning": true},
		"major": false
	},
	{
		"id": "trajectory", "name": "Trajectory Prediction", "icon": "➤", "cost": 220,
		"description": "Makes expected entry positions more accurate and shows each object's direction.",
		"branch": "detection", "prerequisites": ["wide_field", "contact_ledger"],
		"hidden_until": ["wide_field"], "effect_type": "unlock", "effect_notes": {"trajectory_line": true},
		"major": true
	},
	{
		"id": "rare_detection", "name": "Rare Meteor Detection", "icon": "★", "cost": 450,
		"description": "Reveals rare fireballs and shows the type of every incoming object before it appears.",
		"branch": "detection", "prerequisites": ["trajectory"],
		"hidden_until": ["trajectory"], "effect_type": "discovery", "effect_notes": {"meteor_type": "fireball"},
		"major": true
	},
	{
		"id": "fragment_analysis", "name": "Fragment Tracking", "icon": "◆", "cost": 900,
		"description": "Discovers splitting meteors; the observation network can help track their fragments.",
		"branch": "detection", "prerequisites": ["rare_detection"],
		"hidden_until": ["rare_detection"], "effect_type": "discovery", "effect_notes": {"meteor_type": "fragment"},
		"major": true
	},
	{
		"id": "shower_detector", "name": "Meteor Shower Forecast", "icon": "☄", "cost": 1800,
		"description": "Unlocks warned meteor-shower events across the whole sky. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "discovery",
		"effect_notes": {"event": "meteor_shower"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true
	},
	{
		"id": "array_planning", "name": "Array Planning", "icon": "⬡", "cost": 50,
		"description": "Allows one more regular target to remain in the sky at once.",
		"branch": "network", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"max_active": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": false
	},
	{
		"id": "observation_scheduling", "name": "Observation Scheduling", "icon": "◷", "cost": 150,
		"description": "Plans longer shifts and extends each future observation window by 10 seconds.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "passive",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": false
	},
	{
		"id": "thermal_management", "name": "Equipment Thermal Control", "icon": "❄", "cost": 450,
		"description": "Controls sensor heat during longer shifts and adds another 10 seconds to future observation windows.",
		"branch": "network", "prerequisites": ["observation_scheduling"],
		"hidden_until": ["observation_scheduling"], "effect_type": "passive",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": false
	},
	{
		"id": "extended_watch_protocol", "name": "Extended Watch Protocol", "icon": "◴", "cost": 700,
		"description": "Coordinates a long-watch protocol and extends each future observation window by 10 seconds.",
		"branch": "network", "prerequisites": ["thermal_management"],
		"hidden_until": ["thermal_management"], "effect_type": "transformation",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": true
	},
	{
		"id": "continuous_watch_rotation", "name": "Continuous Watch Rotation", "icon": "↻", "cost": 1000,
		"description": "Coordinates uninterrupted handoffs and adds 10 seconds to future observation windows, reaching their 60-second maximum.",
		"branch": "network", "prerequisites": ["extended_watch_protocol"],
		"hidden_until": ["extended_watch_protocol"], "effect_type": "transformation",
		"runtime_parameters": {"observation_duration_bonus": 10.0},
		"effect_contract": {"kind": "observation_duration_bonus", "value": 10.0, "scope": "future_observation_windows"},
		"major": true
	},
	{
		"id": "secondary_camera", "name": "Secondary Camera", "icon": "▣", "cost": 600,
		"description": "Forecasts incoming objects and gives you a dish. Right-click anywhere to move the nearest dish.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "automation", "effect_notes": {"assist_slots": 1},
		"major": true
	},
	{
		"id": "predictive_dish_control", "name": "Predictive Dish Control", "icon": "⌁", "cost": 800,
		"description": "Automatically moves an idle dish toward trackable incoming objects; manual right-click placement still takes priority.",
		"branch": "network", "prerequisites": ["secondary_camera"],
		"hidden_until": ["secondary_camera"], "effect_type": "automation", "effect_notes": {"dish_auto_assignment": true},
		"major": true
	},
	{
		"id": "multi_target_analysis", "name": "Multi-Target Tracking", "icon": "⊕", "cost": 1200,
		"description": "Tracks every meteor inside the manual observation area together and allows one more regular target in the sky. Automatically supports one target; with Fragment Tracking, it can also help with fragment pieces.",
		"branch": "network", "prerequisites": ["secondary_camera", "extended_watch_protocol"],
		"hidden_until": ["secondary_camera"], "effect_type": "transformation", "effect_notes": {"assist_slots": 2, "manual_group_tracking": true},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "automated_tracking", "name": "Automated Common Tracking", "icon": "⚙", "cost": 2200,
		"description": "Common targets are observed automatically; rare and high-value targets still need you.",
		"branch": "network", "prerequisites": ["multi_target_analysis"],
		"hidden_until": ["multi_target_analysis"], "effect_type": "automation", "effect_notes": {"common_rate": 0.29},
		"major": true
	},
	{
		"id": "observatory_network", "name": "Observatory Network", "icon": "✧", "cost": 3500,
		"description": "Links the array and previews shower entry areas. Adds a second steerable dish and raises automatic support from one target to two.",
		"branch": "network", "prerequisites": ["automated_tracking"],
		"hidden_until": ["automated_tracking"], "effect_type": "transformation", "effect_notes": {"assist_slots": 3, "shower_preview": true},
		"major": true
	},
	{
		"id": "contact_ledger", "name": "Forecast Log", "icon": "≣", "cost": 180,
		"description": "Combines incoming records to make expected entry positions more accurate without adding another sky label.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "transformation", "effect_notes": {"forecast_error_scale": 0.82},
		"major": false
	},
	{
		"id": "companion_resolution", "name": "Companion Resolution", "icon": "∴", "cost": 1000,
		"description": "Resolves fragment companions as a single family and raises the value of recovered pieces.",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "transformation", "effect_notes": {"fragment_piece_value_multiplier": 1.35},
		"major": true
	},
	{
		"id": "polar_survey", "name": "Sky Sweep", "icon": "✣", "cost": 80,
		"description": "Opens blank-sky sweeping: travel 460 px through quiet sky for a 30% chance to call a meteor at the cursor.",
		"branch": "ursa_minor", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"survey_distance": 460.0, "survey_probability": 0.30},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sweep_gain", "name": "Sweep Gain", "icon": "⌁", "cost": 180,
		"description": "Reduces the blank-sky travel needed for each summon roll from 460 px to 380 px.",
		"branch": "ursa_minor", "prerequisites": ["polar_survey"],
		"hidden_until": ["polar_survey"], "effect_type": "passive", "effect_notes": {"survey_distance": 380.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "faint_recovery", "name": "Faint Recovery", "icon": "◌", "cost": 400,
		"description": "Raises each blank-sky summon chance from 30% to 42%.",
		"branch": "ursa_minor", "prerequisites": ["sweep_gain"],
		"hidden_until": ["sweep_gain"], "effect_type": "passive", "effect_notes": {"survey_probability": 0.42},
		"major": false, "affects_pacing": false
	},
	{
		"id": "sustained_sweep", "name": "Sustained Sweep", "icon": "▧", "cost": 800,
		"description": "Keeps partial sweep charge when the button is released, until the current observation round ends.",
		"branch": "ursa_minor", "prerequisites": ["faint_recovery"],
		"hidden_until": ["faint_recovery"], "effect_type": "transformation", "effect_notes": {"persistent_survey_charge": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "deep_exposure", "name": "Deep Exposure", "icon": "+", "cost": 1500,
		"description": "Raises each blank-sky summon chance from 42% to 55%.",
		"branch": "ursa_minor", "prerequisites": ["sustained_sweep"],
		"hidden_until": ["sustained_sweep"], "effect_type": "passive", "effect_notes": {"survey_probability": 0.55},
		"major": false, "affects_pacing": false
	},
	{
		"id": "rapid_scan", "name": "Rapid Scan", "icon": "↻", "cost": 2500,
		"description": "Reduces the cooldown after a successful summon from 1.5 seconds to 0.9 seconds.",
		"branch": "ursa_minor", "prerequisites": ["deep_exposure"],
		"hidden_until": ["deep_exposure"], "effect_type": "passive", "effect_notes": {"survey_cooldown": 0.9},
		"major": false, "affects_pacing": false
	},
	{
		"id": "polar_cascade", "name": "Polar Cascade", "icon": "✦", "cost": 4000,
		"description": "Calls two meteors from one successful blank-sky summon roll.",
		"branch": "ursa_minor", "prerequisites": ["rapid_scan"],
		"hidden_until": ["rapid_scan"], "effect_type": "transformation", "effect_notes": {"survey_spawn_count": 2},
		"major": true, "affects_pacing": false
	},
	{
		"id": "radiant_plotting", "name": "Radiant Cadence", "icon": "✺", "cost": 8000,
		"description": "Permanently shortens regular arrival intervals by 6%.",
		"branch": "perseus", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"spawn_interval_multiplier": 0.94},
		"major": false
	},
	{
		"id": "crowd_forecast", "name": "Crowd Forecast", "icon": "⌁", "cost": 12000,
		"description": "Shows every incoming object 0.8 seconds earlier.",
		"branch": "perseus", "prerequisites": ["radiant_plotting"],
		"hidden_until": ["radiant_plotting"], "effect_type": "unlock", "effect_notes": {"forecast_lead_bonus": 0.8},
		"major": false
	},
	{
		"id": "burst_windowing", "name": "Arrival Compression", "icon": "⋮", "cost": 18000,
		"description": "Permanently compresses regular arrival intervals by 12%.",
		"branch": "perseus", "prerequisites": ["crowd_forecast"],
		"hidden_until": ["crowd_forecast"], "effect_type": "transformation", "effect_notes": {"spawn_interval_multiplier": 0.88},
		"major": false
	},
	{
		"id": "debris_correlation", "name": "Debris Correlation", "icon": "⟡", "cost": 26000,
		"description": "Raises Data recovered from every fragment and fragment piece by 20%.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "transformation", "effect_notes": {"fragment_value_multiplier": 1.2},
		"major": false
	},
	{
		"id": "cascade_sampling", "name": "Cascade Sampling", "icon": "⠿", "cost": 120000,
		"description": "Allows one more regular target to remain in the sky at once.",
		"branch": "perseus", "prerequisites": ["debris_correlation"],
		"hidden_until": ["debris_correlation"], "effect_type": "passive", "effect_notes": {"max_active": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "adaptive_exposure_grid", "name": "Adaptive Exposure Grid", "icon": "▦", "cost": 24000,
		"description": "Keeps every target visible 12% longer.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "passive", "effect_notes": {"lifetime_multiplier": 1.12},
		"major": true
	},
	{
		"id": "perseid_survey", "name": "Perseid Watch", "icon": "✹", "cost": 30000,
		"description": "Allows one more regular target in the sky. While at least three targets are present, every observation earns 18% more Data.",
		"branch": "perseus", "prerequisites": ["adaptive_exposure_grid"],
		"hidden_until": ["adaptive_exposure_grid"], "effect_type": "transformation", "effect_notes": {"max_active": 1, "crowd_value_multiplier": 1.18},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true
	},
	{
		"id": "filter_wheel", "name": "Calibration Framework", "icon": "◒", "cost": 10000,
		"description": "Opens automatic band-calibration and binary-star research.",
		"branch": "lyra", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"opens_band_calibration": true},
		"implementation_connection": "prerequisite_only",
		"major": false
	},
	{
		"id": "blue_band", "name": "Blue Band", "icon": "B", "cost": 18000,
		"description": "Automatically calibrates blue-band targets, improving observation speed and value.",
		"branch": "lyra", "prerequisites": ["filter_wheel"],
		"hidden_until": ["filter_wheel"], "effect_type": "passive", "effect_notes": {"calibration": "blue"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": false
	},
	{
		"id": "amber_band", "name": "Amber Band", "icon": "A", "cost": 22000,
		"description": "Automatically calibrates amber-band targets, improving observation speed and value.",
		"branch": "lyra", "prerequisites": ["blue_band"],
		"hidden_until": ["blue_band"], "effect_type": "passive", "effect_notes": {"calibration": "amber"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": false
	},
	{
		"id": "violet_band", "name": "Violet Band", "icon": "V", "cost": 26000,
		"description": "Automatically calibrates violet-band targets, improving observation speed and value.",
		"branch": "lyra", "prerequisites": ["amber_band"],
		"hidden_until": ["amber_band"], "effect_type": "passive", "effect_notes": {"calibration": "violet"},
		"implementation_connection": "dynamic_upgrade_id",
		"major": true
	},
	{
		"id": "lyrid_spectrograph", "name": "Lyrid Spectrograph", "icon": "≋", "cost": 180000,
		"description": "Strengthens every calibrated spectral band for faster observations and a decisive data bonus.",
		"branch": "lyra", "prerequisites": ["violet_band"],
		"hidden_until": ["violet_band"], "effect_type": "transformation", "effect_notes": {"calibrated_speed": 1.45, "calibrated_value": 1.35},
		"major": true
	},
	{
		"id": "ephemeris_marks", "name": "Ephemeris Marks", "icon": "⊹", "cost": 16000,
		"description": "Shows every incoming object three seconds before it appears.",
		"branch": "andromeda", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_notes": {"deep_forecast": true},
		"major": false
	},
	{
		"id": "satellite_catalog", "name": "Satellite Catalog", "icon": "▰", "cost": 20000,
		"description": "Adds slow artificial satellites that can appear during the current observation round.",
		"branch": "andromeda", "prerequisites": ["ephemeris_marks"],
		"hidden_until": ["ephemeris_marks"], "effect_type": "discovery", "effect_notes": {"target_type": "satellite"},
		"major": false
	},
	{
		"id": "change_detection", "name": "Change Detection", "icon": "Δ", "cost": 24000,
		"description": "Identifies Andromeda targets and predicts where they will appear within 8–22 px.",
		"branch": "andromeda", "prerequisites": ["satellite_catalog"],
		"hidden_until": ["satellite_catalog"], "effect_type": "transformation", "effect_notes": {"deep_classification": true},
		"major": false
	},
	{
		"id": "variable_watchlist", "name": "Variable Watchlist", "icon": "≈", "cost": 220000,
		"description": "Adds pulsing variable stars that must be completed within their current watch.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "discovery", "effect_notes": {"target_type": "variable_star"},
		"major": true
	},
	{
		"id": "comet_solutions", "name": "Comet Tracking", "icon": "☄", "cost": 28000,
		"description": "Adds slow comets that draw long trails and remain until the current observation round ends.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "discovery", "effect_notes": {"target_type": "comet"},
		"major": true
	},
	{
		"id": "andromeda_deep_survey", "name": "Andromeda Long Watch", "icon": "◎", "cost": 32000,
		"description": "Raises observation speed by 25% and Data by 30% for satellites, variable stars, comets, and distant galaxies; binary stars are excluded.",
		"branch": "andromeda", "prerequisites": ["comet_solutions"],
		"hidden_until": ["comet_solutions"], "effect_type": "transformation", "effect_notes": {"deep_speed": 1.25, "deep_value": 1.3},
		"major": true
	},
	{
		"id": "echo_correlation_10", "name": "Echo Correlation I", "icon": "10%", "cost": 8000,
		"description": "Sets a 10% manual-observation chance to open a Gemini echo once an echo channel is online.",
		"branch": "gemini", "prerequisites": [],
		"hidden_until": [], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.10},
		"major": false
	},
	{
		"id": "echo_correlation_20", "name": "Echo Correlation II", "icon": "20%", "cost": 11000,
		"description": "Raises the manual-observation echo chance from 10% to 20%.",
		"branch": "gemini", "prerequisites": ["echo_correlation_10"],
		"hidden_until": ["echo_correlation_10"], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.20},
		"major": true
	},
	{
		"id": "single_echo_channel", "name": "Single Echo Channel", "icon": "+1", "cost": 12000,
		"description": "Opens one echo channel that launches one additional meteor when Echo Correlation reacts.",
		"branch": "gemini", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"echo_count": 1},
		"major": false
	},
	{
		"id": "dual_echo_channel", "name": "Dual Echo Channels", "icon": "+2", "cost": 16000,
		"description": "Raises each Gemini echo burst from one additional meteor to two.",
		"branch": "gemini", "prerequisites": ["single_echo_channel"],
		"hidden_until": ["single_echo_channel"], "effect_type": "transformation", "effect_notes": {"echo_count": 2},
		"major": false
	},
	{
		"id": "triple_echo_array", "name": "Triple Echo Array", "icon": "+3", "cost": 20000,
		"description": "Raises each Gemini echo burst from two additional meteors to three.",
		"branch": "gemini", "prerequisites": ["dual_echo_channel"],
		"hidden_until": ["dual_echo_channel"], "effect_type": "transformation", "effect_notes": {"echo_count": 3},
		"major": true
	},
	{
		"id": "leonid_radiant", "name": "Leonid Radiant", "icon": "10", "cost": 16000,
		"description": "Starts a seven-second, eight-meteor Leonid storm after 10 fresh manual observations.",
		"branch": "leo", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"manual_trigger": 10, "storm_count": 8},
		"major": true
	},
	{
		"id": "compressed_cadence", "name": "Compressed Cadence", "icon": "9", "cost": 20000,
		"description": "A Leonid storm now charges after nine fresh manual observations; it still carries eight meteors.",
		"branch": "leo", "prerequisites": ["leonid_radiant"],
		"hidden_until": ["leonid_radiant"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 9, "storm_count": 8},
		"major": false
	},
	{
		"id": "dense_stream", "name": "Dense Stream", "icon": "8", "cost": 24000,
		"description": "Eight fresh manual observations now launch a 12-meteor Leonid storm.",
		"branch": "leo", "prerequisites": ["compressed_cadence"],
		"hidden_until": ["compressed_cadence"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 8, "storm_count": 12},
		"major": true
	},
	{
		"id": "rapid_reacquisition", "name": "Rapid Reacquisition", "icon": "7", "cost": 28000,
		"description": "Seven fresh manual observations now relaunch the 12-meteor Leonid storm.",
		"branch": "leo", "prerequisites": ["dense_stream"],
		"hidden_until": ["dense_stream"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 7, "storm_count": 12},
		"major": false
	},
	{
		"id": "storm_front", "name": "Storm Front", "icon": "6", "cost": 32000,
		"description": "Six fresh manual observations now launch a 16-meteor Leonid storm.",
		"branch": "leo", "prerequisites": ["rapid_reacquisition"],
		"hidden_until": ["rapid_reacquisition"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 6, "storm_count": 16},
		"major": true
	},
	{
		"id": "leonid_storm", "name": "Storm Zenith", "icon": "5", "cost": 300000,
		"description": "Five fresh manual observations now launch 20 meteors over seven seconds.",
		"branch": "leo", "prerequisites": ["storm_front"],
		"hidden_until": ["storm_front"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 5, "storm_count": 20},
		"major": true
	},
	{
		"id": "perseid_outburst", "name": "Perseid Outburst", "icon": "✺", "cost": 50000,
		"description": "Unlocks short Perseid bursts that arrive after a warning. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "perseus", "prerequisites": ["perseid_survey"],
		"hidden_until": ["perseid_survey"], "effect_type": "discovery",
		"effect_notes": {"event": "perseid_outburst"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "double_star_resolution", "name": "Double-Star Resolution", "icon": "⁚", "cost": 12000,
		"description": "Adds binary stars, identifies them before they appear, and predicts where they will appear within 8–22 px. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "lyra", "prerequisites": ["filter_wheel"],
		"hidden_until": ["filter_wheel"], "effect_type": "discovery",
		"effect_notes": {"target_type": "binary_star"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "galaxy_imaging", "name": "Distant Galaxy Imaging", "icon": "M31", "cost": 90000,
		"description": "Adds distant galaxies that need long observation but can be completed within the current round. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "andromeda", "prerequisites": ["andromeda_deep_survey"],
		"hidden_until": ["andromeda_deep_survey"], "effect_type": "discovery",
		"effect_notes": {"target_type": "galaxy"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "split_radiant_model", "name": "Split Radiant Model", "icon": "⋔", "cost": 20000,
		"description": "Alternates Leonid storm entries between two mirrored radiant sectors.",
		"branch": "leo", "prerequisites": ["leonid_radiant"],
		"hidden_until": ["leonid_radiant"], "effect_type": "transformation", "effect_notes": {"storm_radiants": 2},
		"major": false, "affects_pacing": false
	},
	{
		"id": "fragment_front", "name": "Fragment Front", "icon": "◆", "cost": 24000,
		"description": "Leads each Leonid storm with a fragmenting meteor that announces the front's arrival.",
		"branch": "leo", "prerequisites": ["split_radiant_model"],
		"hidden_until": ["split_radiant_model"], "effect_type": "discovery", "effect_notes": {"storm_lead_type": "fragment"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "fireball_tail", "name": "Fireball Tail", "icon": "★", "cost": 32000,
		"description": "Closes each Leonid storm with a manual-only fireball after the regular stream. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "leo", "prerequisites": ["fragment_front"],
		"hidden_until": ["fragment_front"], "effect_type": "discovery",
		"effect_notes": {"storm_tail_type": "fireball"},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_signature_lock", "name": "Echo Signature Lock", "icon": "≡", "cost": 14000,
		"description": "Echoes copy the type of a freshly observed common, fast, fragmenting, or fireball target. Other targets still produce a random unlocked regular type.",
		"branch": "gemini", "prerequisites": ["echo_correlation_20"],
		"hidden_until": ["echo_correlation_20"], "effect_type": "transformation", "effect_notes": {"echo_signature_lock": true},
		"major": false, "affects_pacing": false
	},
	{
		"id": "mirror_echo_solution", "name": "Mirror Echo Solution", "icon": "⇋", "cost": 17000,
		"description": "Reconstructs copied echoes from the mirrored side of the triggering target's path.",
		"branch": "gemini", "prerequisites": ["echo_signature_lock"],
		"hidden_until": ["echo_signature_lock"], "effect_type": "transformation", "effect_notes": {"mirror_echo_path": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_delay_line", "name": "Echo Delay Line", "icon": "⋯", "cost": 22000,
		"description": "Staggers each Gemini burst into a readable sequence that still finishes inside the current watch. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "gemini", "prerequisites": ["mirror_echo_solution"],
		"hidden_until": ["mirror_echo_solution"], "effect_type": "unlock",
		"effect_notes": {"echo_delay_line": true},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_deconfliction", "name": "Echo Spacing", "icon": "⌗", "cost": 340000,
		"description": "Spreads each echo burst across separate parts of the sky so its targets do not overlap.",
		"branch": "gemini", "prerequisites": ["triple_echo_array"],
		"hidden_until": ["triple_echo_array"], "effect_type": "automation", "effect_notes": {"echo_deconfliction": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "echo_beacon", "name": "Echo Beacon", "icon": "⌁", "cost": 380000,
		"description": "Shows delayed echoes as ordinary incoming alerts so dishes can move into position early.",
		"branch": "gemini", "prerequisites": ["triple_echo_array"],
		"hidden_until": ["triple_echo_array"], "effect_type": "unlock", "effect_notes": {"echo_forecast": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "momentum_acquisition", "name": "Momentum Acquisition", "icon": "×4", "cost": 18000,
		"description": "Manual observations within three seconds build up to four Momentum stacks; each adds 2% observation speed and 1 px of tracking range.",
		"branch": "taurus", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"combo_window": 3.0, "combo_cap": 4, "speed_per_stack": 0.02, "radius_per_stack": 1.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "wide_pursuit", "name": "Wide Pursuit", "icon": "+1.5", "cost": 420000,
		"description": "Adds 0.5 px of tracking range per Momentum stack on top of Expanded Sweep.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "passive", "effect_notes": {"radius_bonus_per_stack": 0.5},
		"major": false, "affects_pacing": false
	},
	{
		"id": "rapid_focus", "name": "Rapid Focus", "icon": "+3%", "cost": 460000,
		"description": "Adds 1% manual-observation speed per Momentum stack on top of Faster Observation.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "passive", "effect_notes": {"speed_bonus_per_stack": 0.01},
		"major": false, "affects_pacing": false
	},
	{
		"id": "cadence_memory", "name": "Cadence Memory", "icon": "3.5s", "cost": 30000,
		"description": "Extends the Momentum window from three seconds to 3.5 seconds and lets five stacks affect its buffs.",
		"branch": "taurus", "prerequisites": ["momentum_acquisition"],
		"hidden_until": ["momentum_acquisition"], "effect_type": "transformation", "effect_notes": {"combo_window": 3.5, "combo_cap": 5},
		"major": false, "affects_pacing": false
	},
	{
		"id": "expanded_sweep", "name": "Expanded Sweep", "icon": "+2", "cost": 45000,
		"description": "Sets the central Momentum tracking gain to 2 px per stack; Wide Pursuit adds 0.5 px on top.",
		"branch": "taurus", "prerequisites": ["cadence_memory"],
		"hidden_until": ["cadence_memory"], "effect_type": "passive", "effect_notes": {"radius_per_stack": 2.0},
		"major": false, "affects_pacing": false
	},
	{
		"id": "accelerated_analysis", "name": "Faster Observation", "icon": "+4%", "cost": 65000,
		"description": "Sets the central Momentum manual-observation gain to 4% per stack; Rapid Focus adds 1% on top.",
		"branch": "taurus", "prerequisites": ["expanded_sweep"],
		"hidden_until": ["expanded_sweep"], "effect_type": "transformation", "effect_notes": {"speed_per_stack": 0.04},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sustained_charge", "name": "Sustained Charge", "icon": "×7", "cost": 95000,
		"description": "Extends the Momentum window to four seconds and lets seven stacks affect its buffs.",
		"branch": "taurus", "prerequisites": ["accelerated_analysis"],
		"hidden_until": ["accelerated_analysis"], "effect_type": "transformation", "effect_notes": {"combo_window": 4.0, "combo_cap": 7},
		"major": true, "affects_pacing": false
	},
	{
		"id": "taurus_full_gallop", "name": "Full Gallop", "icon": "×10", "cost": 140000,
		"description": "Extends Momentum to five seconds and ten stacks; with both flank upgrades, they grant up to 50% manual-observation speed and 25 px of tracking range. Doubles all observation Data, including automatic completions. All eight ×2 systems combine to ×256.",
		"branch": "taurus", "prerequisites": ["sustained_charge"],
		"hidden_until": ["sustained_charge"], "effect_type": "transformation",
		"effect_notes": {"combo_window": 5.0, "combo_cap": 10},
		"runtime_parameters": {"observation_value_multiplier": 2.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 2.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_opening", "name": "Canis Relay", "icon": "CMa", "cost": 620000,
		"description": "Opens the Canis Major research chain without changing how often meteors currently appear.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_notes": {"canis_major_branch": true},
		"implementation_connection": "prerequisite_only",
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_cadence_i", "name": "Swift Signal", "icon": "1.00s", "cost": 760000,
		"description": "Sets the shortest time between regular meteors to 1.00 seconds.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 1.0},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 1.0, "scope": "regular_meteor_arrivals"},
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_capacity_i", "name": "Long Leash", "icon": "+1", "cost": 900000,
		"description": "Allows one more regular target in the sky, raising the limit from eight to nine.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"max_active_delta": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": false, "affects_pacing": false
	},
	{
		"id": "canis_cadence_ii", "name": "Running Cadence", "icon": "0.85s", "cost": 1150000,
		"description": "Sets the shortest time between regular meteors to 0.85 seconds.",
		"branch": "canis_major", "prerequisites": ["canis_capacity_i"],
		"hidden_until": ["canis_capacity_i"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.85},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.85, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_capacity_ii", "name": "Twin Watch", "icon": "+1", "cost": 1400000,
		"description": "Allows one more regular target in the sky, raising the limit from nine to ten.",
		"branch": "canis_major", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_notes": {"max_active_delta": 1},
		"effect_contract": {"kind": "max_active_delta", "value": 1, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_cadence_iii", "name": "White-Star Tempo", "icon": "0.70s", "cost": 1750000,
		"description": "Sets the shortest time between regular meteors to 0.70 seconds.",
		"branch": "canis_major", "prerequisites": ["canis_opening", "canis_cadence_ii"],
		"hidden_until": ["canis_opening", "canis_cadence_ii"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.70},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.70, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "canis_capacity_iii", "name": "Pack Array", "icon": "+2", "cost": 2100000,
		"description": "Allows two more regular targets in the sky, raising the limit from ten to twelve.",
		"branch": "canis_major", "prerequisites": ["canis_cadence_iii"],
		"hidden_until": ["canis_cadence_iii"], "effect_type": "passive", "effect_notes": {"max_active_delta": 2},
		"effect_contract": {"kind": "max_active_delta", "value": 2, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "sirius_fireball", "name": "Sirius Bloom", "icon": "★", "cost": 10000000,
		"description": "One Major Fireball may appear after a warning in observation rounds with enough time left.",
		"branch": "canis_major", "prerequisites": ["canis_capacity_ii", "canis_cadence_i", "canis_capacity_iii"],
		"hidden_until": ["canis_capacity_ii", "canis_cadence_i", "canis_capacity_iii"], "effect_type": "unlock", "effect_notes": {"major_fireball_per_round": 1},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_synthesis", "name": "All-Sky Synthesis", "icon": "×4", "cost": 2000000,
		"description": "Multiplies all observation Data by 4, including automatic completions.",
		"branch": "draco", "prerequisites": [],
		"hidden_until": [{"type": "other_constellations_complete", "excluded_branch": "draco"}],
		"effect_type": "transformation", "effect_notes": {"culmination_gate": true},
		"runtime_parameters": {"observation_value_multiplier": 4.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 4.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_cadence", "name": "Circumpolar Cadence", "icon": "0.45s", "cost": 8000000,
		"description": "Sets the shortest time between regular meteors to 0.45 seconds.",
		"branch": "draco", "prerequisites": ["draco_synthesis"],
		"hidden_until": ["draco_synthesis"], "effect_type": "transformation", "effect_notes": {"regular_spawn_interval_floor": 0.45},
		"effect_contract": {"kind": "regular_spawn_interval_floor", "value": 0.45, "scope": "regular_meteor_arrivals"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_capacity", "name": "Dragon-Spine Array", "icon": "+6", "cost": 30000000,
		"description": "Allows six more regular targets in the sky, raising the limit from twelve to eighteen.",
		"branch": "draco", "prerequisites": ["draco_cadence"],
		"hidden_until": ["draco_cadence"], "effect_type": "transformation", "effect_notes": {"max_active_delta": 6},
		"effect_contract": {"kind": "max_active_delta", "value": 6, "scope": "regular_active_contacts"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_sweep", "name": "Coiled-Sky Sweep", "icon": "4×", "cost": 40000000,
		"description": "Every 190 px of blank-sky sweeping now calls four meteors, always succeeds, and can trigger again after 0.45 seconds.",
		"branch": "draco", "prerequisites": ["draco_capacity"],
		"hidden_until": ["draco_capacity"], "effect_type": "transformation", "effect_notes": {"survey_distance": 190.0, "survey_probability": 1.0, "survey_count": 4, "survey_cooldown": 0.45},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_echo", "name": "Polar Resonance", "icon": "6×", "cost": 55000000,
		"description": "Raises manual-observation echo chance to 65% and launches six echoes at once.",
		"branch": "draco", "prerequisites": ["draco_sweep"],
		"hidden_until": ["draco_sweep"], "effect_type": "transformation", "effect_notes": {"echo_probability": 0.65, "echo_count": 6},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_storm", "name": "Radiant Convergence", "icon": "30", "cost": 70000000,
		"description": "Arms a 30-object Leonid storm after two eligible manual observations.",
		"branch": "draco", "prerequisites": ["draco_echo"],
		"hidden_until": ["draco_echo"], "effect_type": "transformation", "effect_notes": {"manual_trigger": 2, "storm_count": 30},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_array", "name": "Total Array", "icon": "4+4", "cost": 70000000,
		"description": "Expands the observatory to four steerable dishes that can automatically support four targets.",
		"branch": "draco", "prerequisites": ["draco_storm"],
		"hidden_until": ["draco_storm"], "effect_type": "transformation", "effect_notes": {"dish_count": 4, "support_lanes": 4},
		"major": true, "affects_pacing": false
	},
	{
		"id": "draco_apotheosis", "name": "Dragon's Eye", "icon": "×8", "cost": 85000000,
		"description": "Multiplies all observation Data by 8, including automatic completions.",
		"branch": "draco", "prerequisites": ["draco_array"],
		"hidden_until": ["draco_array"], "effect_type": "transformation", "effect_notes": {"culmination_multiplier": true},
		"runtime_parameters": {"observation_value_multiplier": 8.0},
		"effect_contract": {"kind": "observation_value_multiplier", "value": 8.0, "scope": "all_observation_data"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "galactic_reference_frame", "name": "Galaxy Map", "icon": "MW", "cost": 400000000,
		"description": "Pulls the completed research chart back to galactic scale and reveals the Local Group route.",
		"branch": "draco", "prerequisites": ["draco_apotheosis"],
		"hidden_until": ["draco_apotheosis"], "effect_type": "unlock", "effect_notes": {"galactic_survey": true},
		"major": true, "affects_pacing": false
	},
	{
		"id": "lmc_transit_watch", "name": "LMC Distant Watch", "icon": "LMC", "cost": 550000000,
		"description": "Opens the first distant-galaxy target. Observe it with the same aim-and-hold gesture used everywhere else.",
		"branch": "local_group", "prerequisites": ["galactic_reference_frame"],
		"hidden_until": ["galactic_reference_frame"], "effect_type": "unlock",
		"effect_notes": {"distant_targets": 1, "active_targets": 1},
		"effect_contract": {"kind": "galactic_observation_profile", "value": 1.0, "max_host_stars": 1, "max_active_transits": 1, "scope": "aim_and_hold"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "smc_reference_baseline", "name": "SMC Faint Watch", "icon": "SMC", "cost": 800000000,
		"description": "Adds a fainter distant target that takes 35% longer to observe, without adding a new interaction rule.",
		"branch": "local_group", "prerequisites": ["lmc_transit_watch"],
		"hidden_until": ["lmc_transit_watch"], "effect_type": "unlock",
		"effect_contract": {"kind": "galactic_observation_profile", "value": 1.35, "scope": "faint_aim_and_hold"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "m31_hidden_decoy_survey", "name": "M31 Drift Watch", "icon": "M31", "cost": 1100000000,
		"description": "Adds a large target that drifts slowly across the sky and is observed by ordinary tracking.",
		"branch": "local_group", "prerequisites": ["smc_reference_baseline"], "hidden_until": ["smc_reference_baseline"],
		"effect_type": "unlock", "effect_contract": {"kind": "galactic_observation_profile", "value": 30.0, "scope": "drifting_aim_and_hold"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "m33_transit_network", "name": "M33 Twin Watch", "icon": "M33", "cost": 3200000000,
		"description": "Lets two ordinary distant targets appear together and widens the field by 10.25%.",
		"branch": "local_group", "prerequisites": ["m31_hidden_decoy_survey"], "hidden_until": ["m31_hidden_decoy_survey"],
		"effect_type": "transformation", "effect_contract": {"kind": "galactic_chapter_milestone", "value": 1.1025, "max_host_stars": 2, "max_active_transits": 2, "scope": "visible_world+host_star_layer"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "ngc6822_supernova_watch", "name": "NGC 6822 Supernova Watch", "icon": "SN-I", "cost": 3600000000,
		"description": "Introduces a persistent supernova with peak, fade, and recoverable remnant phases.",
		"branch": "local_group", "prerequisites": ["m33_transit_network"], "hidden_until": ["m33_transit_network"],
		"effect_type": "unlock", "effect_contract": {"kind": "supernova_watch", "value": 1.0, "scope": "galactic_phenomena_layer"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "ic10_supernova_overlap", "name": "IC 10 Supernova Overlap", "icon": "SN-II", "cost": 4000000000,
		"description": "Keeps two supernova light curves active at once for a timing choice.",
		"branch": "local_group", "prerequisites": ["ngc6822_supernova_watch"], "hidden_until": ["ngc6822_supernova_watch"],
		"effect_type": "unlock", "effect_contract": {"kind": "supernova_overlap", "value": 2.0, "scope": "galactic_phenomena_layer"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "ic1613_supernova_ephemeris", "name": "IC 1613 Supernova Ephemeris", "icon": "SN-III", "cost": 4300000000,
		"description": "Shows the remaining phase around active supernovae and widens the field by 10.25%.",
		"branch": "local_group", "prerequisites": ["ic10_supernova_overlap"], "hidden_until": ["ic10_supernova_overlap"],
		"effect_type": "transformation", "effect_contract": {"kind": "galactic_chapter_milestone", "value": 1.1025, "scope": "visible_world+supernova_ephemeris"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "wlm_einstein_ring", "name": "WLM Einstein Ring", "icon": "ER-I", "cost": 4600000000,
		"description": "Adds a full lens ring that completes through the same aim-and-hold observation used for every target.",
		"branch": "local_group", "prerequisites": ["ic1613_supernova_ephemeris"], "hidden_until": ["ic1613_supernova_ephemeris"],
		"effect_type": "unlock", "effect_contract": {"kind": "lens_observation", "value": 1.0, "scope": "aim_and_hold"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "pegasus_partial_lens", "name": "Pegasus Partial Lens", "icon": "ER-II", "cost": 4600000000,
		"description": "Adds a partial lens ring with a smaller visible contact area but the same aim-and-hold observation.",
		"branch": "local_group", "prerequisites": ["wlm_einstein_ring"], "hidden_until": ["wlm_einstein_ring"],
		"effect_type": "transformation", "effect_contract": {"kind": "lens_observation", "value": 0.62, "scope": "aim_and_hold"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "phoenix_lensed_meteors", "name": "Phoenix Lensed Paths", "icon": "LENS", "cost": 4600000000,
		"description": "Bends meteor paths as a visual tracking variation without changing observation or automation rules, and widens the field by 10.25%.",
		"branch": "local_group", "prerequisites": ["pegasus_partial_lens"], "hidden_until": ["pegasus_partial_lens"],
		"effect_type": "transformation", "effect_contract": {"kind": "galactic_chapter_milestone", "value": 1.1025, "scope": "visible_world+lensed_meteor_field"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "leo_a_lensed_supernova", "name": "Leo A Lensed Supernova", "icon": "LSN", "cost": 4600000000,
		"description": "Combines supernova timing with a partial lens shape while keeping the same aim-and-hold observation.",
		"branch": "local_group", "prerequisites": ["phoenix_lensed_meteors"], "hidden_until": ["phoenix_lensed_meteors"],
		"effect_type": "transformation", "effect_contract": {"kind": "lensed_supernova", "value": 1.0, "scope": "galactic_phenomena_layer"},
		"major": true, "affects_pacing": false
	},
	{
		"id": "aquarius_local_group_record", "name": "Local Group Record", "icon": "REC", "cost": 4600000000,
		"description": "Completes the four-chapter record and widens the field by the final 10.25% to its ceiling.",
		"branch": "local_group", "prerequisites": ["leo_a_lensed_supernova"], "hidden_until": ["leo_a_lensed_supernova"],
		"effect_type": "capstone", "effect_contract": {"kind": "galactic_chapter_milestone", "value": 1.1025, "scope": "visible_world+local_group_record"},
		"major": true, "affects_pacing": false
	}
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


static func local_group_functional_node_count() -> int:
	var count := 0
	for definition in UPGRADE_NODES:
		if String(definition.get("branch", "")) == "local_group":
			count += 1
	return count

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
				"name": "RARE FIREBALL", "speed": 190.0, "lifetime": 7.4,
				"radius": 19.0, "trail": 52, "value": 82.0, "track_time": 1.75,
				"color": Color("fff2b0"), "glow": Color("ff7438"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.12, "burn_fade_start": 0.74, "burn_style": "flare",
				"burnout_linger": 0.38,
			}
		"major":
			return {
				"name": "MAJOR FIREBALL", "speed": 128.0, "lifetime": 14.0,
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
				"name": "VARIABLE STAR", "speed": 24.0, "lifetime": 34.0,
				"radius": 13.0, "trail": 10, "value": 96.0, "track_time": 3.4,
				"color": Color("f0dcff"), "glow": Color("c46cff"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.82, "burn_fade_start": 0.95, "burn_style": "variable",
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
				"name": "BINARY STAR", "speed": 32.0, "lifetime": 34.0,
				"radius": 12.0, "trail": 12, "value": 118.0, "track_time": 3.8,
				"color": Color("e8e0ff"), "glow": Color("8ea9ff"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.88, "burn_fade_start": 0.95, "burn_style": "binary",
				"burnout_linger": 0.34,
			}
		"galaxy":
			return {
				"name": "DISTANT GALAXY", "speed": 20.0, "lifetime": 40.0,
				"radius": 18.0, "trail": 8, "value": 220.0, "track_time": 5.2,
				"color": Color("ffe8d2"), "glow": Color("dc84ff"),
				"spectral_band": "amber",
				"burn_terminal_ratio": 0.94, "burn_fade_start": 0.97, "burn_style": "galaxy",
				"burnout_linger": 0.48,
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
