extends SceneTree

const Data = preload("res://scripts/expansion_data.gd")
const State = preload("res://scripts/expansion_state.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_catalogue_shape()
	_check_research_graph()
	_check_branch_order_and_prerequisite_counts()
	_check_exposures_and_plan_switches()
	_check_analysis_pool_and_determinism()
	_check_malformed_save_normalization()
	if failures.is_empty():
		print("EXPANSION_STATE_PASS: plans, research prerequisites, exposures, partial evidence, analysis choices and save normalization")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("EXPANSION_STATE: " + message)

func _new_state(ids: Array[String] = []) -> RefCounted:
	var state: RefCounted = State.new()
	state.research_ids = ids.duplicate()
	return state

func _check_catalogue_shape() -> void:
	_check(Data.PLAN_ORDER.size() == 7, "the expansion catalogue has seven plans")
	_check(Data.field_count() == 18, "the seven plans contain eighteen observation fields")
	var seen: Array[String] = []
	for plan_id in Data.PLAN_ORDER:
		_check(Data.PLANS.has(plan_id), "plan order resolves: " + plan_id)
		_check(plan_id not in seen, "plan order has no duplicate: " + plan_id)
		seen.append(plan_id)
		_check(Data.PLANS[plan_id].fields.size() > 0, "plan has at least one field: " + plan_id)
	_check(seen.size() == Data.PLANS.size(), "plan order covers every plan definition")
	_check(Data.SAMPLE_MODULES.size() == 6, "the specimen catalogue has six unique modules")
	_check(Data.POOLS.size() == 3, "the specimen catalogue has three pools")

func _check_research_graph() -> void:
	var marks: Dictionary = {}
	for id in Data.RESEARCH:
		_check(_visit_research(id, marks), "research prerequisite graph is acyclic from " + id)
		var definition: Dictionary = Data.RESEARCH[id]
		for prerequisite in definition.requires:
			_check(Data.RESEARCH.has(prerequisite), "research prerequisite resolves: " + str(prerequisite))
			_check(prerequisite not in Data.SAMPLE_MODULES, "research never requires a specimen module: " + str(prerequisite))
		if definition.has("plan"):
			_check(Data.PLANS.has(definition.plan), "research plan result resolves: " + str(definition.plan))
	for id in Data.SAMPLE_MODULES:
		_check(id not in Data.RESEARCH, "specimen module is not a research node: " + id)

func _visit_research(id: String, marks: Dictionary) -> bool:
	if not Data.RESEARCH.has(id):
		return false
	var mark: int = int(marks.get(id, 0))
	if mark == 1:
		return false
	if mark == 2:
		return true
	marks[id] = 1
	for prerequisite in Data.RESEARCH[id].requires:
		if not _visit_research(String(prerequisite), marks):
			return false
	marks[id] = 2
	return true

func _check_branch_order_and_prerequisite_counts() -> void:
	var branches: Array[String] = ["ext_trace_study", "ext_sweep_study", "ext_link_study"]
	var orders: Array = [
		[branches[0], branches[1], branches[2]],
		[branches[0], branches[2], branches[1]],
		[branches[1], branches[0], branches[2]],
		[branches[1], branches[2], branches[0]],
		[branches[2], branches[0], branches[1]],
		[branches[2], branches[1], branches[0]],
	]
	for order in orders:
		var state := _new_state(["ext_protocol"])
		var no_owned: Array[String] = []
		for id in order:
			state.research_ids.append(id)
		_check(state.plan_available("plan_trace_1") and state.plan_available("plan_sweep_1") and state.plan_available("plan_link_1"), "all three basic plans unlock regardless of branch order")
		_check(state.sample_pool(no_owned).size() == 6, "all three branch studies expose the same six specimen candidates")

	var tier_one := ["plan_trace_1", "plan_sweep_1", "plan_link_1"]
	for count in range(4):
		var state := _new_state(["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study"])
		for index in range(count):
			_complete_plan(state, tier_one[index])
		_check(state.research_ready("ext_synthesis") == (count == 3), "synthesis requires exactly three completed basic plans at count %d" % count)

	var advanced := ["ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced"]
	var tier_two := ["plan_trace_2", "plan_sweep_2", "plan_link_2"]
	for count in range(4):
		var state := _new_state(["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study", "ext_synthesis"])
		for id in advanced:
			state.research_ids.append(id)
		for plan_id in tier_one:
			_complete_plan(state, plan_id)
		for index in range(count):
			_complete_plan(state, tier_two[index])
		_check(state.research_ready("ext_combined_watch") == (count == 3), "combined watch requires exactly three completed advanced plans at count %d" % count)

	var final_state := _new_state(["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study", "ext_synthesis", "ext_trace_advanced", "ext_sweep_advanced", "ext_link_advanced", "ext_combined_watch"])
	_check(not final_state.research_ready("ext_record_complete"), "record completion stays locked before the integrated plan")
	_complete_plan(final_state, "plan_integrated_1")
	_check(final_state.research_ready("ext_record_complete"), "record completion unlocks after the integrated plan")

func _complete_plan(state: RefCounted, plan_id: String) -> void:
	for index in range(Data.PLANS[plan_id].fields.size()):
		state.exposures = state.exposure_capacity()
		_check(state.select_plan(plan_id), "selects available plan field: " + plan_id)
		var definition: Dictionary = Data.PLANS[plan_id].fields[index]
		for event in definition.events:
			_check(state.record_evidence(plan_id, index, String(event.slot)), "records event evidence: " + plan_id + "/" + str(index))
		if definition.get("ordinary", false):
			_check(state.record_evidence(plan_id, index, "ordinary"), "records ordinary evidence: " + plan_id + "/" + str(index))
		if definition.get("parallel", false):
			state.records[plan_id][index].parallel_progress = 0.25
		_check(state.field_ready(), "prepared field becomes ready: " + plan_id + "/" + str(index))
		var result: Dictionary = state.record_m31()
		_check(result.get("plan", "") == plan_id and result.get("field", -1) == index, "M31 record returns exactly one completed field")
		_check(result.get("plan_complete", false) == (index == Data.PLANS[plan_id].fields.size() - 1), "plan completion result is exact: " + plan_id)

func _check_exposures_and_plan_switches() -> void:
	var state := _new_state(["ext_protocol", "ext_trace_study", "ext_sweep_study"])
	state.exposures = 1
	_check(state.select_plan("plan_trace_1"), "selecting a trace plan consumes an available exposure")
	_check(state.exposures == 0 and state.active_field().prepared, "an exposure prepares the active field")
	_check(state.record_evidence("plan_trace_1", 0, "trace"), "partial trace evidence is accepted")
	state.exposures = 1
	_check(state.select_plan("plan_sweep_1"), "switching plans is allowed with a fresh exposure")
	_check(state.exposures == 0 and state.active_field().prepared, "the switched-to plan consumes its own exposure")
	_check(state.select_plan("plan_trace_1"), "switching back restores the trace plan")
	_check(state.records.plan_trace_1[0].evidence.get("trace", false), "partial evidence survives an A to B to A plan switch")
	_check(state.records.plan_trace_1[0].complete == false, "partial evidence does not complete a field")

	var before_samples: int = state.samples
	var incomplete := _new_state(["ext_protocol", "ext_trace_study"])
	incomplete.exposures = 1
	incomplete.select_plan("plan_trace_1")
	var failed_record: Dictionary = incomplete.record_m31()
	_check(failed_record.is_empty(), "an incomplete field returns no record result")
	_check(incomplete.samples == before_samples, "incomplete record does not award samples")

	var synthesis := _new_state(["ext_protocol", "ext_trace_study", "ext_synthesis"])
	synthesis.exposures = 2
	_check(synthesis.select_plan("plan_trace_1"), "synthesis capacity still prepares one active field")
	_check(synthesis.exposures == 1, "synthesis leaves one exposure after preparing one field")
	var prepared_incomplete := 0
	for field in synthesis.records.plan_trace_1:
		if field.prepared and not field.complete:
			prepared_incomplete += 1
	_check(prepared_incomplete == 1, "synthesis prepares exactly one incomplete field")

func _check_analysis_pool_and_determinism() -> void:
	var studies: Array[String] = ["ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study"]
	var state := _new_state(studies)
	var no_owned: Array[String] = []
	var pool: Array[String] = state.sample_pool(no_owned)
	_check(pool.size() == 6 and pool.size() == pool.duplicate().size(), "unlocked specimen pool contains six unique unowned modules")
	var insufficient := _new_state(studies)
	insufficient.samples = Data.ANALYSIS_COST - 1
	_check(not insufficient.start_analysis(no_owned) and insufficient.samples == Data.ANALYSIS_COST - 1 and insufficient.analysis_serial == 0, "insufficient samples do not start or charge analysis")

	state.samples = Data.ANALYSIS_COST
	state.acquisition_seed = 424242
	_check(state.start_analysis(no_owned), "eight samples start analysis")
	_check(state.samples == 0 and state.samples_spent == Data.ANALYSIS_COST and state.analysis_serial == 1, "analysis charges eight samples and advances its serial")
	_check(state.pending_offer.size() == 3 and state.pending_offer.size() == state.pending_offer.duplicate().size(), "analysis offers up to three distinct candidates")
	for id in state.pending_offer:
		_check(id in pool, "analysis offer comes from the unlocked pool: " + id)
	_check(not state.start_analysis(no_owned), "pending analysis cannot be rerolled")
	_check(state.samples == 0 and state.samples_spent == Data.ANALYSIS_COST and state.analysis_serial == 1, "pending analysis does not charge or reroll")

	for remaining in [2, 1]:
		var owned: Array[String] = []
		for owned_index in range(Data.SAMPLE_MODULES.size() - remaining):
			owned.append(Data.SAMPLE_MODULES[owned_index])
		var partial := _new_state(studies)
		partial.samples = Data.ANALYSIS_COST
		_check(partial.start_analysis(owned), "analysis starts with %d remaining candidates" % remaining)
		_check(partial.pending_offer.size() == remaining, "analysis offers every candidate when only %d remain" % remaining)
		for id in partial.pending_offer:
			_check(id not in owned, "analysis never offers an owned module: " + id)

	var exhausted := _new_state(studies)
	exhausted.samples = Data.ANALYSIS_COST
	var all_owned: Array[String] = []
	for sample_id in Data.SAMPLE_MODULES:
		all_owned.append(sample_id)
	_check(not exhausted.start_analysis(all_owned) and exhausted.samples == Data.ANALYSIS_COST and exhausted.samples_spent == 0, "exhausted pool does not charge analysis")
	var pending := _new_state(studies)
	pending.samples = Data.ANALYSIS_COST
	pending.pending_offer.append("long_baseline")
	_check(not pending.start_analysis(no_owned) and pending.samples == Data.ANALYSIS_COST and pending.samples_spent == 0, "existing pending offer does not charge analysis")

	var seed_source := _new_state(studies)
	seed_source.samples = Data.ANALYSIS_COST
	seed_source.samples_earned = Data.ANALYSIS_COST
	seed_source.acquisition_seed = 314159
	seed_source.analysis_serial = 7
	var before_analysis: Dictionary = seed_source.get_save_data()
	var reload_a: RefCounted = State.new()
	var reload_b: RefCounted = State.new()
	reload_a.load_save_data(before_analysis, no_owned)
	reload_b.load_save_data(before_analysis, no_owned)
	_check(reload_a.start_analysis(no_owned) and reload_b.start_analysis(no_owned), "reloaded state can repeat deterministic analysis")
	_check(reload_a.pending_offer == reload_b.pending_offer, "same seed and serial produce the same candidates after reload")
	_check(reload_a.acquisition_seed == 314159 and reload_a.analysis_serial == 8, "analysis seed and serial persist across reload")
	var after_analysis: Dictionary = reload_a.get_save_data()
	var pending_reload: RefCounted = State.new()
	pending_reload.load_save_data(after_analysis, no_owned)
	_check(pending_reload.pending_offer == reload_a.pending_offer and pending_reload.analysis_serial == reload_a.analysis_serial, "pending candidates persist without reroll")

func _check_malformed_save_normalization() -> void:
	var owned: Array[String] = ["long_baseline"]
	var state: RefCounted = State.new()
	state.load_save_data({
		"research_ids": ["ext_protocol", "bad", 7, "ext_protocol"],
		"selected_plan": 7,
		"records": {"plan_trace_1": [{"prepared": "yes", "complete": true, "evidence": {"trace": true, "unknown": true}, "parallel_progress": NAN}]},
		"exposures": NAN,
		"samples": NAN,
		"samples_earned": NAN,
		"samples_spent": -4,
		"pending_offer": ["long_baseline", "long_baseline", "bad", "dual_processor"],
		"acquisition_seed": NAN,
		"analysis_serial": NAN,
		"rewarded_plans": ["bad", "plan_trace_1", "plan_trace_1"],
		"guided_plans": ["plan_sweep_1", 5],
		"record_complete": true,
	}, owned)
	_check(state.research_ids == ["ext_protocol"], "malformed research IDs normalize to known unique strings")
	_check(state.selected_plan.is_empty(), "malformed selected plan does not activate an unavailable plan")
	_check(state.exposures == 0 and state.samples == 0 and state.samples_spent == 0, "malformed numeric state clamps to finite nonnegative values")
	_check(state.acquisition_seed >= 1 and state.acquisition_seed <= 2147483646, "malformed acquisition seed normalizes into its valid range")
	_check(state.analysis_serial == 0, "malformed analysis serial normalizes to zero")
	_check(state.pending_offer == ["dual_processor"], "pending offer removes owned, duplicate and unknown modules")
	_check(state.rewarded_plans == ["plan_trace_1"] and state.guided_plans == ["plan_sweep_1"], "malformed plan history normalizes to known unique plans")
	_check(not state.record_complete, "record completion cannot survive without the integrated plan")
	_check(not ("long_baseline" in state.pending_offer), "owned modules are never reintroduced by malformed pending offers")
	for plan_id in Data.PLAN_ORDER:
		for field in state.records[plan_id]:
			_check(is_finite(float(field.parallel_progress)), "record progress never contains NaN: " + plan_id)
	var encoded: Dictionary = state.get_save_data()
	_check(encoded.catalogue_version == Data.CATALOGUE_VERSION, "normalized save retains the current catalogue version")
