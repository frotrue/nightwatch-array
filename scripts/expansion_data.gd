extends RefCounted

const CATALOGUE_VERSION := 1
const ANALYSIS_COST := 8
const DIRECT_COST := 12
const SAMPLE_MODULES := ["long_baseline", "dual_processor", "afterglow_archive", "wide_correlation", "reference_bus", "shutter_weave"]
const POOLS := {"trace": ["long_baseline", "dual_processor"], "sweep": ["afterglow_archive", "wide_correlation"], "link": ["reference_bus", "shutter_weave"]}
const RESEARCH_ORDER := ["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study", "ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced", "ext_synthesis", "ext_combined_watch", "ext_record_complete"]
const RESEARCH := {
	"ext_protocol": {"cost": 0.0, "requires": [], "category": "root"},
	"ext_trace_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "trace", "grant": "trail_integrator"},
	"ext_sweep_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "sweep", "grant": "sweep_optics"},
	"ext_link_study": {"cost": 60000000.0, "requires": ["ext_protocol"], "category": "link", "grant": "relay_bus"},
	"ext_trace_advanced": {"cost": 180000000.0, "requires": ["ext_trace_study"], "plan": "plan_trace_1", "category": "trace"},
	"ext_sweep_advanced": {"cost": 180000000.0, "requires": ["ext_sweep_study"], "plan": "plan_sweep_1", "category": "sweep"},
	"ext_link_advanced": {"cost": 180000000.0, "requires": ["ext_link_study"], "plan": "plan_link_1", "category": "link"},
	"ext_synthesis": {"cost": 240000000.0, "requires": ["ext_protocol"], "tier": 1, "count": 3, "category": "root"},
	"ext_combined_watch": {"cost": 360000000.0, "requires": ["ext_synthesis"], "tier": 2, "count": 3, "category": "root"},
	"ext_record_complete": {"cost": 0.0, "requires": ["ext_combined_watch"], "plan": "plan_integrated_1", "category": "root"},
}
const PLAN_ORDER := ["plan_trace_1", "plan_sweep_1", "plan_link_1", "plan_trace_2", "plan_sweep_2", "plan_link_2", "plan_integrated_1"]
const PLANS := {
	"plan_trace_1": {"category": "trace", "tier": 1, "research": "ext_trace_study", "fields": [
		{"id": "trace_single", "events": [{"slot": "trace", "kind": "spectrum", "variant": "single"}]},
		{"id": "trace_diagonal", "events": [{"slot": "trace", "kind": "spectrum", "variant": "diagonal"}]},
	]},
	"plan_sweep_1": {"category": "sweep", "tier": 1, "research": "ext_sweep_study", "fields": [
		{"id": "sweep_center", "events": [{"slot": "glow", "kind": "afterglow", "variant": "center"}]},
		{"id": "sweep_outer", "events": [{"slot": "glow", "kind": "afterglow", "variant": "outer"}]},
	]},
	"plan_link_1": {"category": "link", "tier": 1, "research": "ext_link_study", "fields": [
		{"id": "link_close", "events": [{"slot": "pair", "kind": "pair", "variant": "close"}]},
		{"id": "link_diverging", "events": [{"slot": "pair", "kind": "pair", "variant": "diverging"}]},
	]},
	"plan_trace_2": {"category": "trace", "tier": 2, "research": "ext_trace_advanced", "fields": [
		{"id": "trace_parallel", "events": [{"slot": "a", "kind": "spectrum", "variant": "parallel_a"}, {"slot": "b", "kind": "spectrum", "variant": "parallel_b"}]},
		{"id": "trace_crossing", "events": [{"slot": "a", "kind": "spectrum", "variant": "cross_a"}, {"slot": "b", "kind": "spectrum", "variant": "cross_b"}]},
		{"id": "trace_staggered", "events": [{"slot": "a", "kind": "spectrum", "variant": "single"}, {"slot": "b", "kind": "spectrum", "variant": "diagonal", "delay": 4.0}]},
	]},
	"plan_sweep_2": {"category": "sweep", "tier": 2, "research": "ext_sweep_advanced", "fields": [
		{"id": "sweep_horizontal", "events": [{"slot": "a", "kind": "afterglow", "variant": "left"}, {"slot": "b", "kind": "afterglow", "variant": "right"}]},
		{"id": "sweep_vertical", "events": [{"slot": "a", "kind": "afterglow", "variant": "upper"}, {"slot": "b", "kind": "afterglow", "variant": "lower"}]},
		{"id": "sweep_mixed", "ordinary": true, "events": [{"slot": "glow", "kind": "afterglow", "variant": "outer"}]},
	]},
	"plan_link_2": {"category": "link", "tier": 2, "research": "ext_link_advanced", "fields": [
		{"id": "link_split", "mode": "split", "events": [{"slot": "pair", "kind": "pair", "variant": "diverging"}]},
		{"id": "link_handoff", "mode": "handoff", "events": [{"slot": "pair", "kind": "pair", "variant": "close"}]},
		{"id": "link_parallel", "mode": "parallel", "parallel": true, "events": [{"slot": "pair", "kind": "pair", "variant": "upper"}]},
	]},
	"plan_integrated_1": {"category": "root", "tier": 3, "research": "ext_combined_watch", "fields": [
		{"id": "integrated_trace", "events": [{"slot": "trace", "kind": "spectrum", "variant": "diagonal"}, {"slot": "pair", "kind": "pair", "variant": "lower"}]},
		{"id": "integrated_sweep", "ordinary": true, "events": [{"slot": "a", "kind": "afterglow", "variant": "left"}, {"slot": "b", "kind": "afterglow", "variant": "right"}]},
		{"id": "integrated_link", "mode": "parallel", "parallel": true, "events": [{"slot": "pair", "kind": "pair", "variant": "upper"}, {"slot": "glow", "kind": "afterglow", "variant": "lower", "delay": 3.0}]},
	]},
}

static func field_count() -> int:
	var total := 0
	for definition in PLANS.values():
		total += definition.fields.size()
	return total

static func study_for_kind(kind: String) -> String:
	return {"spectrum": "ext_trace_study", "afterglow": "ext_sweep_study", "pair": "ext_link_study"}.get(kind, "")

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
