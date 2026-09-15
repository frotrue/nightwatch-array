extends SceneTree
const State = preload("res://scripts/expansion_state.gd")
const Data = preload("res://scripts/expansion_data.gd")
const Modules = preload("res://scripts/observation_modules.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var state = State.new()
	_check(state.draw_module().is_empty(), "protocol required")
	state.research_ids.append("ext_protocol")
	var advanced := true
	while advanced:
		advanced = false
		for id in Data.RESEARCH_ORDER:
			if state.research_ready(id):
				state.research_ids.append(id)
				advanced = true
	_check(state.research_ids.size() == 67, "all 67 research nodes reachable by predecessor alone")
	_check(state.draw_cost() == 6 and state.sample_reward() == 3, "late research changes cost and reward")
	state = State.new()
	state.research_ids.append("ext_protocol")
	state.acquisition_seed = 314159
	state.award_samples(7)
	_check(state.draw_module().is_empty() and state.samples == 7 and state.draw_serial == 0, "insufficient balance does not mutate")
	state.award_samples(8000)
	var restored = State.new()
	restored.load_save_data(JSON.parse_string(JSON.stringify(state.get_save_data())))
	var counts := {}
	for index in range(1000):
		var id: String = state.draw_module()
		_check(id in Data.SAMPLE_MODULES and id == restored.draw_module(), "deterministic replacement draw")
		counts[id] = int(counts.get(id, 0)) + 1
	_check(counts.size() == Data.SAMPLE_MODULES.size() and state.samples == 7 and state.samples_spent == 8000, "collection continues after every type has been drawn")
	var model = Modules.new()
	model.grant_copy("overcharge")
	model.grant_copy("overcharge")
	_check(model.owned_count("overcharge") == 2 and model.equip("overcharge", 0) and model.equip("overcharge", 1), "two copies equip together")
	_check(is_equal_approx(model.effect("new_speed"), 1.0) and is_equal_approx(model.stacked_effect("overcharge", "burst_speed"), 3.0), "same module bonuses and penalties add")
	model.unlocked_slots = 5
	_check(not model.equip("overcharge", 2), "cannot equip a third unowned copy")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(model.get_save_data()))
	model.load_save_data(saved)
	_check(model.owned_count("overcharge") == 2 and model.installed_count("overcharge") == 2, "quantity and duplicate slots survive JSON")
	model.load_save_data({"purchased": ["overcharge"], "slots": ["overcharge", "overcharge"]})
	_check(model.owned_count("overcharge") == 1 and model.installed_count("overcharge") == 1, "legacy inventory means one copy")
	model.load_save_data({"purchased": ["focus"], "quantities": {"focus": NAN}, "slots": ["focus", "focus"]})
	_check(model.owned_count("focus") == 1 and model.installed_count("focus") == 1, "malformed quantity cannot activate duplicate")
	state.load_save_data({"research_ids": ["bad", "ext_protocol", "ext_protocol"], "samples": INF, "samples_earned": NAN, "samples_spent": -3, "draw_serial": 0.5})
	_check(state.samples == 0 and state.draw_serial == 0 and state.research_ids == ["ext_protocol"], "numeric and research normalization")
	state.load_save_data({"samples": 4, "samples_earned": 12, "samples_spent": 8, "pending_offer": ["long_baseline"]}, true)
	_check(state.samples == 12 and state.samples_spent == 0, "paid v2 candidate is refunded")
	restored.load_save_data(JSON.parse_string(JSON.stringify(state.get_save_data())))
	_check(restored.samples == 12, "refund does not repeat")
	if failures.is_empty(): print("EXPANSION_STATE_PASS: predecessor research, replacement draws, additive copies, JSON and migration")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
