extends RefCounted

const CATALOGUE_VERSION := 2
const DRAW_COST := 8
const SAMPLE_MODULES := ["long_baseline", "dual_processor", "afterglow_archive", "wide_correlation", "reference_bus", "shutter_weave"]
const RESEARCH_ORDER := ["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study", "ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced", "ext_synthesis", "ext_combined_watch", "ext_record_complete"]
const RESEARCH := {
	"ext_protocol": {"cost": 0.0, "requires": [], "category": "root"},
	"ext_trace_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "trace", "grant": "trail_integrator"},
	"ext_sweep_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "sweep", "grant": "sweep_optics"},
	"ext_link_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "link", "grant": "relay_bus"},
	"ext_trace_advanced": {"cost": 180000000.0, "requires": ["ext_trace_study"], "category": "trace"},
	"ext_sweep_advanced": {"cost": 180000000.0, "requires": ["ext_sweep_study"], "category": "sweep"},
	"ext_link_advanced": {"cost": 180000000.0, "requires": ["ext_link_study"], "category": "link"},
	"ext_synthesis": {"cost": 240000000.0, "requires": ["ext_trace_study", "ext_sweep_study", "ext_link_study"], "category": "root"},
	"ext_combined_watch": {"cost": 360000000.0, "requires": ["ext_synthesis", "ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced"], "category": "root"},
	"ext_record_complete": {"cost": 0.0, "requires": ["ext_combined_watch"], "category": "root"},
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
