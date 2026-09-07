extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
var failures: Array[String] = []
var game: Node
var research: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): push_error("Expansion integration watchdog"); quit(1))
	game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	_freeze(game)
	research = game.deep_sky
	var progress := true
	while progress:
		progress = false
		for node in Balance.UPGRADE_NODES:
			if node.branch != "local_group" and not game.progression.has_upgrade(node.id):
				progress = game.progression.debug_purchase_node(node.id) or progress
	game.spawner.reset()
	game._begin_observation_phase()
	game.events.canis_major_state = "resolved"
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	_check(game.progression.upgrade_level == 95, "original 95-node economy remains sufficient")
	_m31()
	_check(research.observations == 1 and research.state.exposures == 1, "first real M31 grants protocol and one preparation exposure")
	await _check_transactions()
	await _check_target_persistence()
	await _check_full_plan_loop()
	await _check_archive_and_budget()
	_check_weighted_exposure()
	_check_measurement()
	_check_migration()
	_check_tracking_names()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("EXPANSION_INTEGRATION_PASS: real targets, all 18 fields without sample modules, transactional acquisition, persistence, bounded rewards and measurement")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _check_tracking_names() -> void:
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		for kind in ["spectrum", "afterglow", "pair"]:
			game.hud.set_tracking(0.25, "anomaly_" + kind, 1.0)
			_check(not game.hud.tracking_target.text.begins_with("METEOR_"), "localized tracking name: " + locale + "/" + kind)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _chart() -> void:
	game.upgrade_tree.open_tree()
	game.progression.observation_data = 100000000000.0

func _sky() -> void:
	game.module_popup.close()
	game.upgrade_tree.close_tree()
	paused = false
	game.observation_phase_active = true
	game.observation_phase_remaining = 60.0
	game.events.canis_major_state = "resolved"

func _m31(amount: float = 1.0) -> void:
	var target: Node = research.target
	target.cooldown = 0.0
	var rate: float = 1.2 * game.progression.get_analysis_speed_multiplier("galaxy") / 10.0
	target.apply_manual_observation(amount / rate, 0.0, 100.0)

func _manual(target: Node, amount: float = 1.0) -> void:
	var rate: float = 1.42 * game.progression.get_analysis_speed_multiplier("common") / target.required_track_time
	target.apply_manual_observation(amount / rate, 0.0, 100.0)

func _automatic(target: Node, amount: float = 1.0) -> void:
	# Use the production dish rate and target time path, with a stationary test
	# interval; spatial acquisition has its own assertion below.
	var rate: float = game.sky_contacts._dish_assist_rate(target)
	target.set_dish_assist_rate(rate)
	target._process(amount / rate + 0.00001)
	target.set_dish_assist_rate(0.0)

func _check_transactions() -> void:
	_chart()
	for id in ["ext_trace_study", "ext_sweep_study", "ext_link_study"]:
		_check(research.purchase(id), "study purchase succeeds: " + id)
	_check(research.modules.purchased.size() == 3 and research.modules.installed_ids().is_empty(), "guaranteed modules enter inventory without auto-equipping")
	research.state.award_samples(24, research.modules.purchased)
	var before: Dictionary = research.get_save_data()
	game.active_save_slot = 1 # NoSaveSlots rejects writes: this is a real error path.
	_check(not research.begin_analysis(), "failed persistence rejects analysis")
	_check(research.samples == 24 and research.pending_offer.is_empty() and research.state.analysis_serial == before.extension.analysis_serial, "failed analysis restores debit, RNG serial and pending state")
	game.active_save_slot = 0
	_check(research.begin_analysis() and research.samples == 16, "successful analysis spends exactly eight")
	var offered: Array = research.pending_offer.duplicate()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(saved)
	_chart()
	_check(research.pending_offer == offered and not research.begin_analysis(), "disk-shaped load keeps exact pending offer and prevents reroll")
	game.active_save_slot = 1
	_check(not research.choose_analysis(offered[0]) and research.pending_offer == offered and offered[0] not in research.modules.purchased, "failed choice persistence restores pending ownership")
	game.active_save_slot = 0
	_check(research.choose_analysis(offered[0]) and research.pending_offer.is_empty(), "choice grants one owned module")
	_check(not research.choose_analysis(offered[0]), "candidate cannot be claimed twice")
	# The independent full-plan fixture deliberately owns no specimen modules.
	research.load_save_data(before)
	_sky()
	await process_frame

func _spawn_due() -> Array:
	research.director.end_round()
	game.spawner.reset()
	await process_frame # Allow the existing spawner's queue_free cleanup to finish.
	game.observation_phase_remaining = 60.0
	game.events.canis_major_state = "resolved"
	_check(research.director.try_opportunity(), "required observation opportunity fits safe window")
	research.director._process(4.01)
	var targets: Array = research.director.targets()
	for target in targets:
		target.set_process(false)
		target._process(target.warning_time + 0.01)
	return targets

func _check_target_persistence() -> void:
	_chart()
	research.select_plan("plan_trace_1")
	_sky()
	var targets := await _spawn_due()
	_check(targets.size() == 1, "single field creates one concrete spectrum")
	if targets.is_empty(): return
	var target: Node = targets[0]
	_manual(target)
	var position: Vector2 = target.global_position
	_manual(target)
	_check(target.stage == 1 and target.alive and is_equal_approx(target.get_progress(), 0.5), "spectrum requires a second head-to-tail contact frame")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	var ticket: String = target.reward_ticket_id
	game._apply_save_data(saved)
	_sky()
	targets = research.director.targets()
	_check(targets.size() == 1, "active component restores once")
	if targets.is_empty(): return
	target = targets[0]
	target.set_process(false)
	_check(target.reward_ticket_id == ticket and target.stage == 1 and target.global_position.is_equal_approx(position), "save restores ticket, stage, position and work")
	await process_frame
	var samples_before: int = research.samples
	_manual(target)
	_check(not target.alive and research.state.field_ready() and research.samples == samples_before + 2, "completing restored spectrum records evidence and two samples")
	var earned: int = research.state.samples_earned
	var total: float = game.progression.total_data_earned
	research.director.complete_component(target)
	_check(research.state.samples_earned == earned and game.progression.total_data_earned == total, "duplicate completion callback cannot duplicate Data or samples")
	# Check real dish allowlisting, including prior manual-only atmospheric types.
	for type_id in ["fireball", "major"]:
		var meteor: Node = game.spawner.spawn_meteor(type_id, Vector2(400, 250), Vector2.ZERO)
		_check(not game.sky_contacts._dish_can_track(meteor), "dish keeps " + type_id + " manual-only")
	game.spawner.reset()
	var serial: int = research.director.scheduler_serial
	game.events.canis_major_state = "warning"
	_check(not research.director.try_opportunity() and research.director.scheduler_serial == serial, "major warning defers without consuming RNG")
	game.events.canis_major_state = "resolved"
	game.observation_phase_remaining = 10.0
	_check(not research.director.try_opportunity(), "late opportunities defer to next round")
	game.observation_phase_remaining = 60.0
	research.director.end_round()

func _check_full_plan_loop() -> void:
	for plan in Data.PLAN_ORDER:
		_chart()
		var required: String = Data.PLANS[plan].research
		if required == "ext_combined_watch":
			_check(research.purchase("ext_synthesis"), "three basics unlock synthesis")
		if not research.research_owned(required):
			_check(research.purchase(required), "completed prerequisite unlocks " + required)
		_check(research.select_plan(plan), "plan can be selected: " + plan)
		_sky()
		var attempts := 0
		while not research.state.plan_complete(plan) and attempts < 5:
			attempts += 1
			if not research.state.active_field().prepared: _m31()
			var definition: Dictionary = research.state.field_definition()
			var targets: Array = await _spawn_due() if not research.state.field_ready() else []
			var mode: String = definition.get("mode", "manual")
			for target in targets:
				if target.kind == "afterglow":
					var point: Vector2 = target.global_position
					game.survey.cooldown_remaining = 0.0
					game.survey.set_scanning(true, point)
					_check(not target.can_be_tracked(), "hidden afterglow does not steal observation input")
					game.survey.apply_scan_segment(point - Vector2(5, 0), point + Vector2(5, 0), 0.1)
					_check(target.discovered, "held blank-sky sweep discovers afterglow")
				if target.kind == "pair" and mode == "split" and target.component_index == 1:
					_automatic(target)
				elif target.kind == "pair" and mode == "handoff":
					_manual(target, 0.3)
					_automatic(target, 0.71)
				elif target.kind == "pair" and mode == "parallel":
					_automatic(target, 0.05)
					_m31(0.26)
					_automatic(target)
				else:
					_manual(target)
					if target.kind == "spectrum":
						await process_frame
						_manual(target)
			if definition.get("ordinary", false):
				var meteor: Node = game.spawner.spawn_meteor("common", Vector2(400, 270), Vector2.ZERO)
				meteor.apply_manual_observation(100.0, 0.0, 100.0, 1.0)
				meteor._process(0.0) # Atmospheric completion is evaluated by its process loop.
			_check(research.state.field_ready(), "real observations satisfy " + String(definition.id))
			_m31()
		_check(research.state.plan_complete(plan), "plan completes without specimen modules: " + plan)
		_check(research.modules.purchased.size() == 3, "random acquisition never gates field progression")
		_chart()
		if research.state.completed_count(1) == 1 and research.modules.unlocked_slots == 2:
			_check(research.purchase("slot_3"), "first basic unlocks third slot")
		if research.state.completed_count(1) >= 2 and research.modules.unlocked_slots == 3:
			_check(research.purchase("slot_4"), "second basic unlocks fourth slot")
		if research.state.completed_count(2) >= 2 and research.modules.unlocked_slots == 4:
			_check(research.purchase("slot_5"), "second advanced unlocks fifth slot")
		_sky()
	var fields := 0
	for plan in Data.PLAN_ORDER: fields += research.plan_progress(plan).x
	_check(fields == 18 and research.completed_plans() == 7, "all eighteen fields complete")
	_chart()
	_check(research.purchase("ext_record_complete") and research.record_complete, "integrated plan enables optional record closure")
	_sky()
	_check(not game.completed and game.observation_phase_active, "record closure leaves same sky playable")
	var unique_completed := 0
	for ticket in research.director.tickets.values():
		if ticket.completed and ticket.origin_kind in ["plan", "natural"]: unique_completed += 1
	# 24 are an explicit acquisition fixture grant above, not event earnings.
	_check(research.state.samples_earned <= unique_completed * 2 + 18 + 24, "event specimen ceiling and once-only basic rewards hold")
	research.director.end_round()

func _check_archive_and_budget() -> void:
	game.spawner.reset()
	await process_frame
	research.modules.grant("afterglow_archive")
	research.modules.equip("afterglow_archive", 0)
	var meteor: Node = load("res://scripts/meteor.gd").new()
	meteor.configure(Balance.meteor_spec("common"), "common", Vector2(400, 270), Vector2.ZERO, 1.0, {})
	game.meteor_layer.add_child(meteor)
	game._on_meteor_spawned(meteor)
	meteor.set_process(false)
	meteor._process(100.0)
	var archived: Array = research.director.targets()
	_check(archived.size() == 1 and archived[0].origin_kind == "archive", "missed natural common creates one archive afterglow")
	if not archived.is_empty():
		var target: Node = archived[0]
		target.set_process(false)
		_check(not game.sky_contacts._dish_can_track(target), "archive remains manual-only")
		var samples: int = research.samples
		game.progression.reset_manual_combo()
		var total: float = game.progression.total_data_earned
		var expected: float = round(meteor.base_value * 0.5 * game.progression.get_observation_value_multiplier("common", game.meteor_layer.get_child_count() + research.director.object_count()))
		_manual(target)
		_check(research.samples == samples and is_equal_approx(game.progression.total_data_earned - total, expected), "archive pays half Data once and no specimens")
	research.director.end_round()
	game.spawner.reset()
	await process_frame
	for index in range(40):
		game.spawner.spawn_meteor("common", Vector2(200, 200), Vector2.ZERO)
	_check(game.meteor_layer.get_child_count() == 28, "ordinary spawn cap reserves three expansion components and one important target")
	var count: int = game.meteor_layer.get_child_count()
	_check(research.director.try_opportunity(), "extension can consume its reserved budget without removing existing meteors")
	_check(game.meteor_layer.get_child_count() == count and research.director.object_count() <= 3, "extension preserves existing targets and its three-component bound")
	game.spawner.spawn_meteor("major", Vector2(200, 200), Vector2.ZERO)
	_check(game.meteor_layer.get_child_count() + research.director.object_count() <= 32, "important target retains its reserved slot within total32")
	research.director.end_round()
	game.spawner.reset()
	await process_frame
	# Exercise the real dish's spatial acquisition for a recognized anomaly.
	research.director._ensure_ticket("n/dish_test", "pair", "natural")
	research.director._spawn_component({"ticket": "n/dish_test", "kind": "pair", "origin_kind": "natural", "component": 0, "start": Vector2(0.4, 0.4), "end": Vector2(0.4, 0.4)})
	var pair: Node = research.director.targets()[0]
	pair.set_process(false)
	pair._process(1.6)
	game.sky_contacts.refresh_dishes()
	game.sky_contacts.dishes[0].position = pair.global_position
	game.sky_contacts.dishes[0].target = pair.global_position
	game.sky_contacts.dishes[0].arrived = true
	game.sky_contacts._update_dishes(0.02)
	_check(pair.dish_assist_rate > 0.0, "actual dish acquires recognized pair in coverage")
	pair._process(0.02)
	_check(pair.get_automatic_contribution() > 0.0, "actual dish work records automatic contribution")
	research.director.end_round()

func _check_weighted_exposure() -> void:
	for id in ["record", "revisit"]: research.modules.grant(id)
	research.modules.slots.assign(["", "", "", "", ""])
	research.target.progress = 0.0
	research.target.integrated_progress = 0.0
	research.target.value_integral = 0.0
	research.target.cooldown_integral = 0.0
	_m31(0.5)
	research.modules.slots[0] = "record"
	research.modules.slots[1] = "revisit"
	var before: float = game.progression.total_data_earned
	_m31(0.5)
	var expected: float = 8000.0 * game.progression.get_observation_value_multiplier("common", 1) * 1.25
	_check(absf((game.progression.total_data_earned - before) - expected) <= 1.0, "half record exposure yields integrated x1.25")
	_check(is_equal_approx(research.target.cooldown, 5.6), "half revisit exposure yields integrated x0.8 cooldown")
	research.modules.slots[1] = ""
	_check(is_equal_approx(research.target.cooldown, 5.6), "removing revisit cannot alter a cooldown already started")

func _check_measurement() -> void:
	game._begin_observation_phase()
	var original: String = research.modules.slots[0]
	research.modules.slots[0] = ""
	research.changed.emit()
	research.modules.slots[0] = original
	research.changed.emit()
	_check(game._build_round_result().equipment_changed, "A-to-B-to-A equipment remains a mixed round")
	game._begin_observation_phase()
	research.modules.grant("long_baseline")
	research.changed.emit()
	var result: Dictionary = game._build_round_result()
	_check(not result.equipment_changed and result.modules_acquired == ["long_baseline"], "uninstalled acquisition is growth, not a changed loadout")
	var study: String = research.state.research_ids.pop_back()
	research.changed.emit()
	_check(game._build_round_result().build_changed, "extension research is part of the build measurement")
	research.state.research_ids.append(study)
	research.state.selected_plan = "plan_trace_1"
	research.changed.emit()
	research.state.selected_plan = "plan_integrated_1"
	research.changed.emit()
	_check(game._build_round_result().plan_changed, "plan switch history survives return to original context")

func _check_migration() -> void:
	var before: Dictionary = research.get_save_data()
	_check(not research.load_save_data({"version": 99}) and research.get_save_data() == before, "unknown deep-sky version cannot reset state")
	var save: Dictionary = game._build_save_data()
	save.deep_sky.version = 99
	game._apply_save_data(save)
	_check(research.get_save_data() == before, "whole game rejects future version before applying any mutation")
	research.load_save_data({"version": 1, "observations": 2, "progress": 0.4, "cooldown": 2.0, "modules": {"purchased": ["record", "revisit"], "slots": ["record", "revisit", "", "", ""], "unlocked_slots": 5}})
	_check(research.modules.unlocked_slots == 5 and research.state.completed_count() == 0 and research.state.exposures == 1, "v1 preserves capacity without inventing plans")
	_check(is_equal_approx(research.target.value_integral, 0.6) and is_equal_approx(research.target.cooldown_integral, 0.24), "v1 partial exposure initializes its existing equipment weights")
