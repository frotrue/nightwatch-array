extends RefCounted
class_name GameBalance

const FIRST_METEOR_DELAY := 1.8
const FINAL_EVENT_TIME := 1080.0 # 18 minutes; Ctrl+Shift+F skips to it.
const SHOWER_WARNING_TIME := 2.6
const SHOWER_DURATION := 9.0
const BASE_OBSERVATION_DURATION := 20.0
const MAX_OBSERVATION_DURATION := 60.0
const BASE_MAX_ACTIVE_METEORS := 4
const MAX_ACTIVE_METEORS := 6
const REGULAR_SPAWN_INTERVAL_MIN := 1.6
const REGULAR_SPAWN_INTERVAL_MAX := 2.4
const PERSEUS_DISCOVERY_SUCCESSES := 200
const LYRA_DISCOVERY_SUCCESSES := 600
const ANDROMEDA_DISCOVERY_SUCCESSES := 980

const BRANCHES := {
	"optics": {"name": "OPTICS / MANUAL", "color": Color("53d6ff")},
	"detection": {"name": "DETECTION / DISCOVERY", "color": Color("b379ff")},
	"network": {"name": "OBSERVATION NETWORK", "color": Color("52e0b1")},
	"perseus": {"name": "PERSEUS / DENSITY", "color": Color("ffb56b")},
	"lyra": {"name": "LYRA / SPECTRUM", "color": Color("69a9ff")},
	"andromeda": {"name": "ANDROMEDA / DEEP SURVEY", "color": Color("ff78c8")}
}

# Existing upgrade ids are preserved so every gameplay consumer migrates without
# losing its original effect. Presentation coordinates live in research_chart_data.gd.
const UPGRADE_NODES: Array[Dictionary] = [
	{
		"id": "better_lens", "name": "Better Lens", "icon": "◉", "cost": 12,
		"description": "A wider focus ring makes manual tracking more forgiving.",
		"branch": "optics", "prerequisites": [],
		"hidden_until": [], "effect_type": "passive", "effect_parameters": {"tracking_radius": 52.0},
		"major": false
	},
	{
		"id": "long_exposure", "name": "Long Exposure", "icon": "◐", "cost": 28,
		"description": "Meteors stay visible 35% longer and leave denser trails.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_parameters": {"lifetime_multiplier": 1.35},
		"major": false
	},
	{
		"id": "observation_streak", "name": "Observation Streak", "icon": "×3", "cost": 64,
		"description": "Consecutive manual observations build a modest reward chain; automation breaks it.",
		"branch": "optics", "prerequisites": ["better_lens"],
		"hidden_until": ["better_lens"], "effect_type": "transformation", "effect_parameters": {"step": 0.08, "maximum": 0.5},
		"major": false
	},
	{
		"id": "precision_multiplier", "name": "Precision Spectrometer", "icon": "⌾", "cost": 150,
		"description": "Centered manual tracking builds a reward multiplier.",
		"branch": "optics", "prerequisites": ["long_exposure"],
		"hidden_until": ["long_exposure"], "effect_type": "transformation", "effect_parameters": {"precision_gain": 0.58},
		"major": false
	},
	{
		"id": "perfect_observation", "name": "Perfect Observation", "icon": "✦", "cost": 260,
		"description": "Grades manual tracking. Excellent and Perfect runs earn a decisive quality bonus.",
		"branch": "optics", "prerequisites": ["precision_multiplier"],
		"hidden_until": ["precision_multiplier"], "effect_type": "transformation", "effect_parameters": {"excellent_bonus": 1.25, "perfect_bonus": 1.55},
		"major": true
	},
	{
		"id": "edge_detection", "name": "Edge Detection", "icon": "≋", "cost": 16,
		"description": "Classifies high-speed entry signatures and introduces fast meteors.",
		"branch": "detection", "prerequisites": [],
		"hidden_until": [], "effect_type": "discovery", "effect_parameters": {"meteor_type": "fast"},
		"major": false
	},
	{
		"id": "wide_field", "name": "Wide Field Sensor", "icon": "⌗", "cost": 55,
		"description": "Reveals incoming contacts before they enter the sky so you can pre-position.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "unlock", "effect_parameters": {"entry_warning": true},
		"major": false
	},
	{
		"id": "trajectory", "name": "Trajectory Prediction", "icon": "➤", "cost": 95,
		"description": "Tightens forecast uncertainty and reveals each contact's approach.",
		"branch": "detection", "prerequisites": ["wide_field", "contact_ledger"],
		"hidden_until": ["wide_field"], "effect_type": "unlock", "effect_parameters": {"trajectory_line": true},
		"major": true
	},
	{
		"id": "rare_detection", "name": "Rare Meteor Detection", "icon": "★", "cost": 155,
		"description": "Reveals rare fireballs and identifies every forecast contact before entry.",
		"branch": "detection", "prerequisites": ["trajectory"],
		"hidden_until": ["trajectory"], "effect_type": "discovery", "effect_parameters": {"meteor_type": "fireball"},
		"major": true
	},
	{
		"id": "fragment_analysis", "name": "Fragment Analysis", "icon": "◆", "cost": 240,
		"description": "Discovers splitting meteors; network analysis can assist with their fragments.",
		"branch": "detection", "prerequisites": ["rare_detection"],
		"hidden_until": ["rare_detection"], "effect_type": "discovery", "effect_parameters": {"meteor_type": "fragment"},
		"major": true
	},
	{
		"id": "shower_detector", "name": "Meteor Shower Forecast", "icon": "☄", "cost": 370,
		"description": "Unlocks warned meteor-shower events across the whole sky.",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "discovery", "effect_parameters": {"event": "meteor_shower"},
		"major": true
	},
	{
		"id": "array_planning", "name": "Array Planning", "icon": "⬡", "cost": 20,
		"description": "Adds another observation channel for a crowded sky.",
		"branch": "network", "prerequisites": [],
		"hidden_until": [], "effect_type": "unlock", "effect_parameters": {"max_active": 1},
		"major": false
	},
	{
		"id": "observation_scheduling", "name": "Observation Scheduling", "icon": "◷", "cost": 60,
		"description": "Plans longer shifts and extends each future observation window by 10 seconds.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "passive", "effect_parameters": {"observation_duration_bonus": 10.0},
		"major": false
	},
	{
		"id": "thermal_management", "name": "Equipment Thermal Control", "icon": "❄", "cost": 180,
		"description": "Controls sensor heat during longer shifts and adds another 10 seconds to future observation windows.",
		"branch": "network", "prerequisites": ["observation_scheduling"],
		"hidden_until": ["observation_scheduling"], "effect_type": "passive", "effect_parameters": {"observation_duration_bonus": 10.0},
		"major": false
	},
	{
		"id": "extended_watch_protocol", "name": "Extended Watch Protocol", "icon": "◴", "cost": 280,
		"description": "Coordinates a long-watch protocol and extends each future observation window by 10 seconds.",
		"branch": "network", "prerequisites": ["thermal_management"],
		"hidden_until": ["thermal_management"], "effect_type": "transformation", "effect_parameters": {"observation_duration_bonus": 10.0},
		"major": true
	},
	{
		"id": "continuous_watch_rotation", "name": "Continuous Watch Rotation", "icon": "↻", "cost": 380,
		"description": "Coordinates uninterrupted handoffs and extends future observation windows to their 60-second maximum.",
		"branch": "network", "prerequisites": ["extended_watch_protocol"],
		"hidden_until": ["extended_watch_protocol"], "effect_type": "transformation", "effect_parameters": {"observation_duration_bonus": 10.0},
		"major": true
	},
	{
		"id": "secondary_camera", "name": "Secondary Camera", "icon": "▣", "cost": 240,
		"description": "Forecasts incoming objects and gives you a dish. Right-click anywhere to move the nearest dish.",
		"branch": "network", "prerequisites": ["array_planning"],
		"hidden_until": ["array_planning"], "effect_type": "automation", "effect_parameters": {"assist_slots": 1},
		"major": true
	},
	{
		"id": "predictive_dish_control", "name": "Predictive Dish Control", "icon": "⌁", "cost": 285,
		"description": "Automatically pre-positions an idle dish for trackable forecast contacts; right-click placement still overrides it.",
		"branch": "network", "prerequisites": ["secondary_camera"],
		"hidden_until": ["secondary_camera"], "effect_type": "automation", "effect_parameters": {"dish_auto_assignment": true},
		"major": true
	},
	{
		"id": "multi_target_analysis", "name": "Multi-Target Analysis", "icon": "⊕", "cost": 330,
		"description": "All meteors inside the manual tracking field advance together; also adds one support camera lane that accelerates active analysis and fragment assistance.",
		"branch": "network", "prerequisites": ["secondary_camera", "extended_watch_protocol"],
		"hidden_until": ["secondary_camera"], "effect_type": "transformation", "effect_parameters": {"assist_slots": 2, "manual_group_tracking": true},
		"major": true
	},
	{
		"id": "automated_tracking", "name": "Automated Common Tracking", "icon": "⚙", "cost": 550,
		"description": "Common targets are analyzed automatically; rare and high-value targets still need you.",
		"branch": "network", "prerequisites": ["multi_target_analysis"],
		"hidden_until": ["multi_target_analysis"], "effect_type": "automation", "effect_parameters": {"common_rate": 0.29},
		"major": true
	},
	{
		"id": "observatory_network", "name": "Observatory Network", "icon": "✧", "cost": 720,
		"description": "Links the whole array; previews shower entry sectors; adds a second steerable dish; and keeps two support camera lanes that accelerate active analysis.",
		"branch": "network", "prerequisites": ["automated_tracking"],
		"hidden_until": ["automated_tracking"], "effect_type": "transformation", "effect_parameters": {"assist_slots": 3, "shower_preview": true},
		"major": true
	},
	{
		"id": "contact_ledger", "name": "Contact Ledger", "icon": "≣", "cost": 70,
		"description": "Cross-references incoming contacts to narrow their forecast uncertainty without adding another sky label.",
		"branch": "detection", "prerequisites": ["edge_detection"],
		"hidden_until": ["edge_detection"], "effect_type": "transformation", "effect_parameters": {"forecast_error_scale": 0.82},
		"major": false
	},
	{
		"id": "companion_resolution", "name": "Companion Resolution", "icon": "∴", "cost": 310,
		"description": "Resolves fragment companions as a single family and raises the value of recovered pieces.",
		"branch": "detection", "prerequisites": ["fragment_analysis"],
		"hidden_until": ["fragment_analysis"], "effect_type": "transformation", "effect_parameters": {"fragment_piece_value_multiplier": 1.35},
		"major": true
	},
	{
		"id": "radiant_plotting", "name": "Radiant Plotting", "icon": "✺", "cost": 18,
		"description": "Plots the Perseid radiant after sustained successful observations and slightly compresses arrival intervals.",
		"branch": "perseus", "prerequisites": [],
		"hidden_until": [{"type": "success_count", "minimum": PERSEUS_DISCOVERY_SUCCESSES}], "effect_type": "discovery", "effect_parameters": {"spawn_interval_multiplier": 0.94},
		"major": false
	},
	{
		"id": "crowd_forecast", "name": "Crowd Forecast", "icon": "⌁", "cost": 42,
		"description": "Extends contact warning time when the sky is building toward a crowded interval.",
		"branch": "perseus", "prerequisites": ["radiant_plotting"],
		"hidden_until": ["radiant_plotting"], "effect_type": "unlock", "effect_parameters": {"forecast_lead_bonus": 0.8},
		"major": false
	},
	{
		"id": "burst_windowing", "name": "Burst Windowing", "icon": "⋮", "cost": 76,
		"description": "Schedules short high-density windows by compressing regular arrival intervals.",
		"branch": "perseus", "prerequisites": ["crowd_forecast"],
		"hidden_until": ["crowd_forecast"], "effect_type": "transformation", "effect_parameters": {"spawn_interval_multiplier": 0.88},
		"major": false
	},
	{
		"id": "debris_correlation", "name": "Debris Correlation", "icon": "⟡", "cost": 118,
		"description": "Correlates fragments that cross the same radiant and raises their recovered data.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "transformation", "effect_parameters": {"fragment_value_multiplier": 1.2},
		"major": false
	},
	{
		"id": "cascade_sampling", "name": "Cascade Sampling", "icon": "⠿", "cost": 170,
		"description": "Keeps one additional contact viable during dense fragment cascades.",
		"branch": "perseus", "prerequisites": ["debris_correlation"],
		"hidden_until": ["debris_correlation"], "effect_type": "passive", "effect_parameters": {"max_active": 1},
		"major": true
	},
	{
		"id": "adaptive_exposure_grid", "name": "Adaptive Exposure Grid", "icon": "▦", "cost": 245,
		"description": "Adapts exposure across a crowded frame so every target remains visible longer.",
		"branch": "perseus", "prerequisites": ["burst_windowing"],
		"hidden_until": ["burst_windowing"], "effect_type": "passive", "effect_parameters": {"lifetime_multiplier": 1.12},
		"major": true
	},
	{
		"id": "perseid_survey", "name": "Perseid Survey", "icon": "✹", "cost": 360,
		"description": "Completes the density survey, opening a second crowded-sky channel and rewarding simultaneous contacts.",
		"branch": "perseus", "prerequisites": ["adaptive_exposure_grid"],
		"hidden_until": ["adaptive_exposure_grid"], "effect_type": "transformation", "effect_parameters": {"max_active": 1, "crowd_value_multiplier": 1.18},
		"major": true
	},
	{
		"id": "filter_wheel", "name": "Spectral Classifier", "icon": "◒", "cost": 24,
		"description": "Installs automatic spectral classification and opens passive band calibration research.",
		"branch": "lyra", "prerequisites": [],
		"hidden_until": [{"type": "success_count", "minimum": LYRA_DISCOVERY_SUCCESSES}], "effect_type": "unlock", "effect_parameters": {"automatic_spectral_analysis": true},
		"major": false
	},
	{
		"id": "blue_band", "name": "Blue Band", "icon": "B", "cost": 58,
		"description": "Automatically calibrates analysis for blue-band targets, improving their speed and value.",
		"branch": "lyra", "prerequisites": ["filter_wheel"],
		"hidden_until": ["filter_wheel"], "effect_type": "passive", "effect_parameters": {"calibration": "blue"},
		"major": false
	},
	{
		"id": "amber_band", "name": "Amber Band", "icon": "A", "cost": 96,
		"description": "Automatically calibrates analysis for amber-band targets, improving their speed and value.",
		"branch": "lyra", "prerequisites": ["blue_band"],
		"hidden_until": ["blue_band"], "effect_type": "passive", "effect_parameters": {"calibration": "amber"},
		"major": false
	},
	{
		"id": "violet_band", "name": "Violet Band", "icon": "V", "cost": 145,
		"description": "Automatically calibrates analysis for violet-band targets, improving their speed and value.",
		"branch": "lyra", "prerequisites": ["amber_band"],
		"hidden_until": ["amber_band"], "effect_type": "passive", "effect_parameters": {"calibration": "violet"},
		"major": true
	},
	{
		"id": "lyrid_spectrograph", "name": "Lyrid Spectrograph", "icon": "≋", "cost": 245,
		"description": "Strengthens every calibrated spectral band for faster analysis and a decisive data bonus.",
		"branch": "lyra", "prerequisites": ["violet_band"],
		"hidden_until": ["violet_band"], "effect_type": "transformation", "effect_parameters": {"calibrated_speed": 1.45, "calibrated_value": 1.35},
		"major": true
	},
	{
		"id": "ephemeris_marks", "name": "Ephemeris Marks", "icon": "⊹", "cost": 30,
		"description": "Marks long-lived paths after the late-run survey milestone and opens an independent deep-sky forecast.",
		"branch": "andromeda", "prerequisites": [],
		"hidden_until": [{"type": "success_count", "minimum": ANDROMEDA_DISCOVERY_SUCCESSES}], "effect_type": "discovery", "effect_parameters": {"deep_forecast": true},
		"major": false
	},
	{
		"id": "satellite_catalog", "name": "Satellite Catalog", "icon": "▰", "cost": 72,
		"description": "Adds slow artificial satellites to the same-round survey catalog.",
		"branch": "andromeda", "prerequisites": ["ephemeris_marks"],
		"hidden_until": ["ephemeris_marks"], "effect_type": "discovery", "effect_parameters": {"target_type": "satellite"},
		"major": false
	},
	{
		"id": "change_detection", "name": "Change Detection", "icon": "Δ", "cost": 130,
		"description": "Classifies long-lived forecast contacts and narrows their ephemeris uncertainty.",
		"branch": "andromeda", "prerequisites": ["satellite_catalog"],
		"hidden_until": ["satellite_catalog"], "effect_type": "transformation", "effect_parameters": {"deep_classification": true},
		"major": false
	},
	{
		"id": "variable_watchlist", "name": "Variable Watchlist", "icon": "≈", "cost": 190,
		"description": "Adds pulsing variable stars that must be completed within their current watch.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "discovery", "effect_parameters": {"target_type": "variable_star"},
		"major": true
	},
	{
		"id": "comet_solutions", "name": "Comet Solutions", "icon": "☄", "cost": 260,
		"description": "Adds long-arc comets that remain in the current observation round for a complete solution.",
		"branch": "andromeda", "prerequisites": ["change_detection"],
		"hidden_until": ["change_detection"], "effect_type": "discovery", "effect_parameters": {"target_type": "comet"},
		"major": true
	},
	{
		"id": "andromeda_deep_survey", "name": "Andromeda Deep Survey", "icon": "◎", "cost": 420,
		"description": "Completes the deep survey and increases the value and analysis speed of long-lived targets.",
		"branch": "andromeda", "prerequisites": ["comet_solutions"],
		"hidden_until": ["comet_solutions"], "effect_type": "transformation", "effect_parameters": {"deep_speed": 1.25, "deep_value": 1.3},
		"major": true
	}
]


static func upgrade_definition(id: String) -> Dictionary:
	for definition in UPGRADE_NODES:
		if String(definition.id) == id:
			return definition
	return {}

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
				"burn_wobble": 11.0, "split_progress": 0.46, "burnout_linger": 0.24,
			}
		"fragment_piece":
			return {
				"name": "FRAGMENT", "speed": 280.0, "lifetime": 2.9,
				"radius": 5.0, "trail": 22, "value": 11.0, "track_time": 0.62,
				"color": Color("e8d9ff"), "glow": Color("bf8cff"),
				"spectral_band": "violet",
				"burn_terminal_ratio": 0.12, "burn_fade_start": 0.72, "burn_style": "spark",
				"burn_wobble": 7.0, "burnout_linger": 0.16,
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
		_:
			return {
				"name": "COMMON METEOR", "speed": 220.0, "lifetime": 5.0,
				"radius": 7.5, "trail": 28, "value": 14.0, "track_time": 0.95,
				"color": Color("f3fbff"), "glow": Color("78bfff"),
				"spectral_band": "blue",
				"burn_terminal_ratio": 0.25, "burn_fade_start": 0.68, "burn_style": "ember",
				"burnout_linger": 0.20,
			}
