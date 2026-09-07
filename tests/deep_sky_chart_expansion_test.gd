extends SceneTree

# This isolates the chart surface from the live target scheduler. Expansion
# state has its own contract test; here the concern is that every continuation
# path remains reachable through the real controls without auto-equipping an
# acquired module.
const Chart = preload("res://scripts/deep_sky_chart.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
const Modules = preload("res://scripts/observation_modules.gd")

var failures: Array[String] = []


class MockProgression:
	extends Node

	var purchased_nodes: Dictionary = {}
	var observation_data := 1000000000.0

	func has_upgrade(id: String) -> bool:
		return purchased_nodes.has(id)


class MockHud:
	extends Node

	var autosave_failed := false


class MockGame:
	extends Node

	var progression: MockProgression
	var hud: MockHud
	var active_save_slot := 1
	var module_popup: Node

	func _init() -> void:
		progression = MockProgression.new()
		hud = MockHud.new()


class MockResearch:
	extends Node

	signal changed

	var game: MockGame
	var modules = Modules.new()
	var observations := 1
	var owned: Dictionary = {"ext_protocol": true}
	var selected_plan := "plan_trace_1"
	var progress: Dictionary = {"plan_trace_1": Vector2i(1, 2)}
	var samples := 8
	var pending_offer: Array[String] = []
	var purchase_calls: Array[String] = []

	func _init() -> void:
		game = MockGame.new()

	func modules_unlocked() -> bool:
		return observations > 0

	func available() -> bool:
		return true

	func research_owned(id: String) -> bool:
		return owned.has(id) or modules.research_owned(id)

	func research_ready(id: String) -> bool:
		return id in ["focus", "ext_protocol", "ext_trace_study", "ext_sweep_study", "ext_link_study"]

	func research_cost(id: String) -> float:
		if Data.RESEARCH.has(id):
			return float(Data.RESEARCH[id].cost)
		return 120000000.0

	func can_purchase(id: String) -> bool:
		return research_ready(id) and not research_owned(id)

	func purchase(id: String) -> bool:
		if not can_purchase(id):
			return false
		purchase_calls.append(id)
		if Modules.DEFINITIONS.has(id):
			modules.grant(id)
		else:
			owned[id] = true
		changed.emit()
		return true

	func paid_research_count() -> int:
		var count := 0
		for id in owned:
			if Data.RESEARCH.has(id) and Data.RESEARCH[id].cost > 0.0:
				count += 1
		return count

	func research_name(id: String) -> String:
		return "Study " + id

	func research_description(id: String) -> String:
		return "Description for " + id

	func prerequisite_text(id: String) -> String:
		return "Prerequisite for " + id

	func plan_available(id: String) -> bool:
		return id in ["plan_trace_1", "plan_sweep_1", "plan_link_1"]

	func select_plan(id: String) -> bool:
		if not plan_available(id):
			return false
		selected_plan = id
		changed.emit()
		return true

	func active_plan() -> String:
		return selected_plan

	func plan_progress(id: String) -> Vector2i:
		return progress.get(id, Vector2i.ZERO)

	func plan_name(id: String) -> String:
		return "Plan " + id

	func plan_detail(id: String) -> String:
		return "Field record for " + id

	func current_objective() -> String:
		return "Prepare the next field"

	func sample_pool() -> Array[String]:
		var pool: Array[String] = []
		for id in Data.SAMPLE_MODULES:
			if id not in modules.purchased:
				pool.append(id)
		return pool

	func collection_complete() -> bool:
		return sample_pool().is_empty()

	func begin_analysis() -> bool:
		if not pending_offer.is_empty() or samples < Data.ANALYSIS_COST:
			return false
		var pool := sample_pool()
		if pool.is_empty():
			return false
		pending_offer.assign(pool.slice(0, mini(3, pool.size())))
		samples -= Data.ANALYSIS_COST
		changed.emit()
		return true

	func choose_analysis(id: String) -> bool:
		if id not in pending_offer or not modules.grant(id):
			return false
		pending_offer.clear()
		changed.emit()
		return true

	func direct_analysis(id: String) -> bool:
		if not pending_offer.is_empty() or samples < Data.DIRECT_COST or id not in sample_pool() or not modules.grant(id):
			return false
		samples -= Data.DIRECT_COST
		changed.emit()
		return true


class MockTree:
	extends Node

	const Balance = preload("res://scripts/game_balance.gd")

	var progression: MockProgression
	var base_star_positions: Dictionary = {}

	func _init(value: MockProgression) -> void:
		progression = value

	func _is_local_group_node(id: String) -> bool:
		for definition in Balance.UPGRADE_NODES:
			if String(definition.id) == id:
				return String(definition.branch) == "local_group"
		return false


func _initialize() -> void:
	var chart_translation: Translation = load("res://localization/chart_expansion.en.translation")
	TranslationServer.set_locale("en")
	if chart_translation != null:
		TranslationServer.add_translation(chart_translation)
	_run.call_deferred()


func _run() -> void:
	var research := MockResearch.new()
	var tree := MockTree.new(research.game.progression)
	for definition in Balance.UPGRADE_NODES:
		if String(definition.branch) != "local_group":
			research.game.progression.purchased_nodes[String(definition.id)] = true
	var chart := Chart.new()
	chart.size = Vector2(1152, 648)
	root.add_child(chart)
	await process_frame
	chart.bind(research, tree)
	await process_frame

	_check(chart.nodes.size() == 20, "research tab exposes M31, the legacy eight, and ten continuation research nodes")
	for id in Modules.RESEARCH_IDS + Data.RESEARCH_ORDER:
		_check(chart.nodes.has(id), "research node remains reachable by its stable id: " + id)
	_check(chart._visible_base_owned_count() == 95, "continuation progress excludes retained Local Group records from the visible 95-node base array")

	chart.select("focus")
	_check(chart.detail_title.text == "Study focus" and chart.buy_button.visible, "legacy research selection still uses the shared detail and purchase path")
	chart.buy_button.pressed.emit()
	_check(research.purchase_calls == ["focus"] and research.modules.research_owned("focus"), "legacy research purchase is forwarded once through the chart")
	chart.select("ext_trace_study")
	_check(chart.detail_title.text == "Study ext_trace_study" and chart.buy_button.visible, "continuation research selection shares the inspector and purchase control")
	chart.buy_button.pressed.emit()
	_check(research.purchase_calls == ["focus", "ext_trace_study"] and research.owned.has("ext_trace_study"), "continuation research purchase is forwarded once through the chart")

	chart.tab_buttons[1].pressed.emit()
	await process_frame
	_check(chart.plans_panel.visible and not chart.research_panel.visible, "Plans tab replaces the research surface")
	_check(not chart.detail_title.is_visible_in_tree() and not chart.detail_body.is_visible_in_tree() and not chart.status.is_visible_in_tree() and not chart.price.is_visible_in_tree() and not chart.buy_button.is_visible_in_tree(), "Plans tab hides the research inspector instead of leaving stale purchase detail beside plan records")
	_check(chart.plan_buttons.size() == Data.PLAN_ORDER.size() and Data.field_count() == 18, "Plans tab lists all seven plans and the data model retains eighteen fields")
	chart.plan_buttons["plan_sweep_1"].pressed.emit()
	_check(research.active_plan() == "plan_sweep_1" and chart.plan_title.text == "Plan plan_sweep_1", "available plan controls select the plan and refresh its detail")

	chart.tab_buttons[2].pressed.emit()
	await process_frame
	_check(chart.analysis_panel.visible and chart.analysis_button.visible and chart.direct_button.disabled, "Analysis tab exposes the eight-sample draw while targeted analysis waits for twelve samples")
	_check(not chart.detail_title.is_visible_in_tree() and not chart.detail_body.is_visible_in_tree() and not chart.status.is_visible_in_tree() and not chart.price.is_visible_in_tree() and not chart.buy_button.is_visible_in_tree(), "Analysis tab hides the research inspector instead of leaving stale purchase detail beside specimen choices")
	research.samples = 8
	chart.refresh_text()
	chart.analysis_button.pressed.emit()
	var offer: Array[String] = research.pending_offer.duplicate()
	_check(offer.size() == 3 and research.samples == 0, "eight-sample analysis creates three saved candidates and debits once")
	chart.refresh_text()
	_check(research.pending_offer == offer and chart.candidate_buttons[0].visible and chart.direct_button.disabled, "refreshing preserves the unresolved offer and blocks targeted analysis")
	chart.candidate_buttons[0].pressed.emit()
	_check(research.pending_offer.is_empty() and research.modules.research_owned(offer[0]) and research.modules.installed_ids().is_empty(), "choosing an analysis candidate acquires it without auto-equipping it")

	research.samples = 12
	chart.refresh_text()
	_check(not chart.direct_button.disabled, "targeted analysis becomes available at twelve samples")
	var targeted_id: String = str(chart.direct_selector.get_item_metadata(chart.direct_selector.selected))
	chart.direct_button.pressed.emit()
	_check(research.samples == 0 and research.modules.research_owned(targeted_id) and research.modules.installed_ids().is_empty(), "targeted analysis acquires the selected module without auto-equipping it")

	var signal_counts := {"return": 0, "constellation": 0}
	chart.observatory_requested.connect(func(): signal_counts["return"] += 1)
	chart.constellations_requested.connect(func(): signal_counts["constellation"] += 1)
	chart.tab_buttons[0].pressed.emit()
	chart.chart_button.pressed.emit()
	chart.back_button.pressed.emit()
	_check(signal_counts["constellation"] == 1 and signal_counts["return"] == 1, "research tab keeps the completed-constellation and observatory return controls: " + str(signal_counts))

	var mock_game := research.game
	var mock_hud := mock_game.hud
	var mock_progression := mock_game.progression
	chart.free()
	research.free()
	tree.free()
	mock_hud.free()
	mock_progression.free()
	mock_game.free()
	await process_frame
	if failures.is_empty():
		print("DEEP_SKY_CHART_EXPANSION_PASS: tabs, continuation research, plans, saved specimen choices and return controls")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("DEEP_SKY_CHART_EXPANSION: " + message)
