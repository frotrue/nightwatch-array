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
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
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
	_check(research.observations == 1 and research.research_owned("ext_protocol"), "first real M31 unlocks special meteors")
	await _check_transactions()
	await _check_target_persistence()
	await _check_research_loop()
	await _check_archive_and_budget()
	_check_weighted_exposure()
	_check_measurement()
	_check_migration()
	_check_tracking_names()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("EXPANSION_INTEGRATION_PASS: real targets, all research without sample modules, transactional acquisition, persistence, bounded rewards and measurement")
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
		for kind in ["rare", "afterglow"]:
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
	_check(research.modules.purchased.size() == 3 and research.modules.installed_ids().is_empty(), "guaranteed modules enter inventory")
	research.state.award_samples(80)
	_check(research.draw_module().is_empty(), "draw requires the loadout popup")
	game.module_popup.open()
	var before: Dictionary = research.get_save_data()
	game.active_save_slot = 1
	_check(research.draw_module().is_empty(), "failed persistence rejects draw")
	_check(research.samples == 80 and research.modules.purchased.size() == 3 and research.state.draw_serial == before.extension.draw_serial, "failed draw restores debit, RNG and ownership")
	game.active_save_slot = 0
	var id: String = research.draw_module()
	_check(not id.is_empty() and research.samples == 72 and research.modules.owned_count(id) == 1, "successful draw spends exactly eight")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game.module_popup.close()
	game._apply_save_data(saved)
	_chart()
	game.module_popup.open()
	_check(research.state.last_draw == id and research.samples == 72, "disk-shaped save restores paid result")
	for index in range(8): research.draw_module()
	var copies := 0
	for module_id in Data.SAMPLE_MODULES: copies += research.modules.owned_count(module_id)
	_check(copies == 9 and research.modules.installed_ids().is_empty(), "all draws are copies without auto-equipping")
	game.module_popup.close()
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
	var targets := await _spawn_due()
	_check(targets.size() == 1 and targets[0].kind == "rare", "one conventional special meteor")
	if targets.is_empty(): return
	var target: Node = targets[0]
	var samples_before: int = research.samples
	var data_before: float = game.progression.total_data_earned
	research.director.complete_component(target)
	_check(research.samples == samples_before and game.progression.total_data_earned == data_before, "unfinished target cannot pay")
	_manual(target, 0.4)
	_check(target.alive and is_equal_approx(target.get_progress(), 0.4), "partial ordinary tracking")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(research.get_save_data()))
	research.load_save_data(saved)
	research.resume_targets()
	target = research.director.targets()[0]
	target.set_process(false)
	_check(is_equal_approx(target.get_progress(), 0.4), "active target restores progress")
	_manual(target, 0.6)
	_check(not target.alive and research.samples == samples_before + 2, "completion grants two samples")
	var paid: float = game.progression.total_data_earned
	research.director.complete_component(target)
	_check(research.samples == samples_before + 2 and game.progression.total_data_earned == paid, "no duplicate samples or Data")
	targets = await _spawn_due()
	if not targets.is_empty():
		target = targets[0]
		_automatic(target)
		_check(not target.alive and research.samples == samples_before + 4, "automatic observation grants same samples")
	research.director.end_round()

func _check_research_loop() -> void:
	_chart()
	for id in Data.RESEARCH_ORDER:
		if not research.research_owned(id): _check(research.purchase(id), "research needs only predecessors and Data: " + id)
	for id in research.Modules.RESEARCH_IDS:
		if not research.research_owned(id): _check(research.purchase(id), "module and slot research reachable: " + id)
	_check(research.modules.unlocked_slots == 5 and research.state.draw_cost() == 6, "all five slots and final efficiency reachable")
	_check(research.modules.purchased.size() == 8, "all research completed without random modules")
	_sky()
	var targets := await _spawn_due()
	if not targets.is_empty():
		var target: Node = targets[0]
		_check(is_equal_approx(target.required_track_time, 1.65) and is_equal_approx(target.visible_lifetime, 17.5), "research changes actual meteor observation and visibility")
		_check(is_equal_approx(target.get_assist_rate(1.0), 1.25 / 1.65), "research changes dish rate")
		research.modules.equip("sweep_optics", 0)
		_check(is_equal_approx(target.get_tracking_radius(40.0), 60.0), "Sweep Optics widens the real rare meteor aim radius")
		research.modules.equip("", 0)
		var samples_before: int = research.samples
		_manual(target)
		_check(research.samples == samples_before + 3, "research grants three actual samples")
	for index in range(10):
		var interval: float = research.director._next_interval()
		_check(interval >= 25.6 and interval <= 35.2, "research shortens spawn interval")
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
	research.director._ensure_ticket("n/dish_test", "rare", "natural")
	research.director._spawn_component({"ticket": "n/dish_test", "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.4, 0.4), "end": Vector2(0.4, 0.4)})
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
	research.modules.grant_copy("long_baseline")
	research.modules.equip("long_baseline", 0)
	research.modules.equip("long_baseline", 1)
	game._begin_observation_phase()
	var disk_result: Dictionary = JSON.parse_string(JSON.stringify(game._build_round_result()))
	var clean: Dictionary = game._sanitize_round_result(disk_result)
	_check(clean.equipment_signature.count("long_baseline") == 2, "round comparison keeps duplicate installed copies")
	_check(game._validated_module_ids(research.modules.purchased).size() == research.modules.purchased.size(), "ownership history keeps more than five module types")

func _check_migration() -> void:
	var before: Dictionary = research.get_save_data()
	_check(not research.load_save_data({"version": 99}) and research.get_save_data() == before, "unknown deep-sky version cannot reset state")
	var save: Dictionary = game._build_save_data()
	save.deep_sky.version = 99
	game._apply_save_data(save)
	_check(research.get_save_data() == before, "whole game rejects future version before applying any mutation")
	research.load_save_data({"version": 1, "observations": 2, "progress": 0.4, "cooldown": 2.0, "modules": {"purchased": ["record", "revisit"], "slots": ["record", "revisit", "", "", ""], "unlocked_slots": 5}})
	_check(research.modules.unlocked_slots == 5 and research.research_owned("ext_protocol"), "v1 preserves capacity without inventing plans")
	_check(is_equal_approx(research.target.value_integral, 0.6) and is_equal_approx(research.target.cooldown_integral, 0.24), "v1 partial exposure initializes its existing equipment weights")

	# Two shutter copies preserve the longer M31 cooldown across disk saves.
	research.modules.load_save_data({"purchased": ["shutter_weave"], "quantities": {"shutter_weave": 2}, "slots": ["shutter_weave", "shutter_weave"]})
	research.target.progress = 0.0
	research.target.integrated_progress = 0.0
	research.target.value_integral = 0.0
	research.target.cooldown_integral = 0.0
	_m31()
	_check(is_equal_approx(research.target.cooldown, 10.5), "two cooldown penalties add on actual completion")
	research.load_save_data(JSON.parse_string(JSON.stringify(research.get_save_data())))
	_check(is_equal_approx(research.target.cooldown, 10.5), "duplicate cooldown is not truncated on load")
	var old: Dictionary = research.get_save_data()
	old.version = 2
	old.anomalies = {"active": [{"ticket": "p/old", "kind": "spectrum", "origin_kind": "plan", "stage": 1, "stage_progress": 0.4, "start": [0.3, 0.4], "end": [0.7, 0.5]}], "tickets": {"p/old": {"components": {}, "sample_units": 0, "completed": false}}}
	research.load_save_data(old)
	research.resume_targets()
	var migrated: Array = research.director.targets()
	_check(migrated.size() == 1 and migrated[0].kind == "rare" and is_equal_approx(migrated[0].get_progress(), 0.7), "v2 active spectrum keeps normalized progress as a rare meteor")
	research.director.end_round()
