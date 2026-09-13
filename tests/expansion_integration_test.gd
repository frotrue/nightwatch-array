extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
var failures: Array[String] = []
var game: Node
var research: Node
var growth_baseline: Dictionary

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
			if not game.progression.has_upgrade(node.id):
				progress = game.progression.debug_purchase_node(node.id) or progress
	game.spawner.reset()
	game._begin_observation_phase()
	game.events.canis_major_state = "resolved"
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	_check(game.progression.upgrade_level == 95, "original 95-node economy remains sufficient")
	_check(research.modules_unlocked() and research.research_owned("ext_protocol"), "coordinate research unlocks special meteors")
	growth_baseline = _growth_snapshot()
	await _check_transactions()
	await _check_target_persistence()
	await _check_research_loop()
	await _check_retirement_and_budget()
	_check_measurement()
	_check_migration()
	_check_tracking_names()
	await _check_split_module()
	await _check_new_modules()
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

func _clear_split_sky() -> void:
	game.observer.reset()
	for child in game.meteor_layer.get_children(): child.free()
	game.spawner.pending_echoes.clear()
	game.spawner.pending_contacts.clear()
	game.spawner.leonid_storm_remaining = 0

func _split_pieces() -> Array:
	return game.meteor_layer.get_children().filter(func(node): return node.get_meta("module_fragment", false))

func _check_split_module() -> void:
	_sky()
	game.spawner.running = true
	game.spawner.phase_time_remaining = 60.0
	research.modules.load_save_data({"purchased": ["focus"], "quantities": {"focus": 4}, "slots": ["focus", "focus", "focus", "focus"], "unlocked_slots": 5})
	for manual in [true, false]:
		for kind in ["common", "fast"]:
			_clear_split_sky()
			var parent = game.spawner.spawn_meteor(kind, Vector2(500, 280), Vector2(180, 0))
			# A constellation-born common/fast remains eligible, while suppressing
			# unrelated parent bursts so this checks the production completion route.
			parent.set_meta("gemini_echo", true)
			parent.set_process(false)
			_check(game.spawner.try_spawn_module_fragments(parent, 1.0) == 0, "unfinished meteor cannot split")
			if manual:
				game.observer.cursor_position = parent.global_position
				game.observer._apply_manual_contact(parent, 20.0)
				parent.simulate_tick(0.0)
			else:
				parent.set_dish_assist_rate(10.0)
				parent.simulate_tick(0.11)
			var pieces := _split_pieces()
			_check(parent.observed_successfully and pieces.size() == 2, "real manual/automatic completion creates a pair: " + kind + "/" + str(manual))
			if pieces.size() != 2: continue
			_check(pieces[0].velocity.cross(pieces[1].velocity) != 0.0, "children fly in distinct directions")
			_check(game.spawner.try_spawn_module_fragments(parent, 1.0) == 0, "same success cannot roll twice")
			var before_count: int = game.meteor_layer.get_child_count()
			var before_data: float = game.progression.total_data_earned
			for piece in pieces:
				piece.set_process(false)
				_check(is_equal_approx(piece.base_value, parent.base_value * 0.25) and piece.body_radius < parent.body_radius, "children carry a quarter base Data and smaller bodies")
				_check(piece.primary_color == parent.primary_color and piece.glow_color == parent.glow_color, "children inherit parent color")
				game.observer.cursor_position = piece.global_position
				game.observer._apply_manual_contact(piece, 20.0)
				piece.simulate_tick(0.0)
			_check(game.meteor_layer.get_child_count() == before_count and game.spawner.pending_echoes.is_empty() and game.spawner.pending_contacts.is_empty() and game.spawner.leonid_storm_remaining == 0, "children cannot resplit or launch constellation bursts")
			_check(game.progression.total_data_earned > before_data, "collecting children awards real data")
	_clear_split_sky()
	# A seeded series checks both hit and miss branches against the advertised
	# chance and keeps this new random stream independent of regular arrivals.
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 42
	game.spawner.module_rng.seed = 42
	var ordinary_rng_state: int = game.spawner.rng.state
	var hits := 0
	for index in range(120):
		var parent = game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2(180, 0))
		parent.observed_successfully = true
		var expected := 2 if expected_rng.randf() < 0.3 else 0
		_check(game.spawner.try_spawn_module_fragments(parent, 0.3) == expected, "seeded 30 percent chance matches hit/miss decision")
		hits += int(expected > 0)
		_clear_split_sky()
	_check(hits > 0 and hits < 120 and game.spawner.rng.state == ordinary_rng_state, "chance covers hits and misses without consuming arrival RNG")
	for kind in ["fragment", "fragment_piece", "fireball", "major"]:
		var parent = game.spawner.spawn_meteor(kind, Vector2(500, 280), Vector2(180, 0))
		parent.observed_successfully = true
		_check(game.spawner.try_spawn_module_fragments(parent, 1.0) == 0, "other meteor families excluded: " + kind)
		_clear_split_sky()
	var parent = game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2(180, 0))
	parent.observed_successfully = true
	research.modules.slots.fill("")
	_check(game.spawner.try_spawn_module_fragments(parent, research.modules.effect("split_chance")) == 0, "unequipping disables splitting")
	_clear_split_sky()
	parent = game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2(180, 0))
	parent.observed_successfully = true
	for i in 21: game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2.ZERO)
	_check(game.spawner.try_spawn_module_fragments(parent, 1.0) == 2 and _split_pieces().size() == 2, "module pair survives the former 22-object shared cap")
	_clear_split_sky()
	parent = game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2(180, 0))
	parent.observed_successfully = true
	var budget: int = game.spawner.SpawnPolicy.ATMOSPHERIC_SAFETY_SLOTS
	while game.meteor_layer.get_child_count() < budget - 1:
		game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2.ZERO)
	_check(game.spawner.try_spawn_module_fragments(parent, 1.0) == 0 and _split_pieces().is_empty(), "one free slot cannot create a partial pair or consume reserved capacity")
	_clear_split_sky()
	parent = game.spawner.spawn_meteor("common", Vector2(500, 280), Vector2(180, 0))
	parent.observed_successfully = true
	game.spawner.try_spawn_module_fragments(parent, 1.0)
	for piece in _split_pieces():
		piece.set_process(false)
		piece.simulate_tick(3.0)
		_check(not piece.alive and not piece.observed_successfully, "uncollected split children expire")
		piece.simulate_tick(2.0)
	await process_frame
	_check(_split_pieces().is_empty(), "expired children are freed")
	_clear_split_sky()

func _check_tracking_names() -> void:
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		for kind in ["rare"]:
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

func _manual(target: Node, amount: float = 1.0) -> void:
	var rate: float = 1.42 * game.progression.get_analysis_speed_multiplier("common") / target.required_track_time
	target.apply_manual_observation(amount / rate + (0.00001 if amount >= 1.0 else 0.0), 0.0, 100.0)
	target.tick_resolve()

func _automatic(target: Node, amount: float = 1.0) -> void:
	# Use the production dish rate and target time path, with a stationary test
	# interval; spatial acquisition has its own assertion below.
	var rate: float = game.sky_contacts._dish_assist_rate(target)
	target.set_dish_assist_rate(rate)
	target.simulate_tick(amount / rate + 0.00001)
	target.set_dish_assist_rate(0.0)

func _check_transactions() -> void:
	_chart()
	for id in ["ext_trace_study", "ext_sweep_study"]:
		_check(research.purchase(id), "study purchase succeeds: " + id)
	_check(research.modules.purchased.is_empty() and research.modules.installed_ids().is_empty(), "research growth does not grant or equip modules")
	research.state.award_samples(80)
	_check(research.draw_module().is_empty(), "draw requires the dedicated window")
	game.module_popup.open_draw()
	var before: Dictionary = research.get_save_data()
	game.active_save_slot = 1
	_check(research.draw_module().is_empty(), "failed persistence rejects draw")
	_check(research.samples == 80 and research.modules.purchased.is_empty() and research.state.draw_serial == before.extension.draw_serial, "failed draw restores debit, RNG and ownership")
	game.active_save_slot = 0
	var id: String = research.draw_module()
	_check(not id.is_empty() and research.samples == 72 and research.modules.owned_count(id) == 1, "successful draw spends exactly eight")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game.module_popup.close()
	game._apply_save_data(saved)
	_chart()
	game.module_popup.open_draw()
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
	research.director.simulate_tick(4.01)
	var targets: Array = research.director.targets()
	for target in targets:
		target.set_process(false)
		target.simulate_tick(target.warning_time + 0.01)
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
	var advanced := true
	while advanced:
		advanced = false
		for id in Data.RESEARCH_ORDER:
			if research.can_purchase(id):
				_check(research.purchase(id), "research purchase succeeds: " + id)
				advanced = true
	_check(research.state.research_ids.size() == 55, "all fifty-five nodes reached using only Data and predecessor research")
	_check(research.modules.unlocked_slots == 5 and research.state.draw_cost() == 6, "all five slots and final efficiency reachable")
	_check(research.modules.purchased.is_empty(), "all research completed without owning a single module")
	_check_permanent_growth()
	_sky()
	var targets := await _spawn_due()
	if not targets.is_empty():
		var target: Node = targets[0]
		_check(is_equal_approx(target.required_track_time, 1.65) and is_equal_approx(target.visible_lifetime, 17.5), "research changes actual meteor observation and visibility")
		_check(is_equal_approx(target.get_assist_rate(1.0), 1.25 / 1.65), "research changes dish rate")
		research.modules.grant("sweep_optics")
		research.modules.equip("sweep_optics", 0)
		_check(is_equal_approx(target.get_tracking_radius(40.0), 60.0), "Sweep Optics widens the real rare meteor aim radius")
		research.modules.equip("", 0)
		var samples_before: int = research.samples
		_manual(target)
		_check(research.samples == samples_before + 3, "research grants three actual samples")
	_check(is_equal_approx(research.director.get_spawn_probability(), 1.0 / (30.4 * 60.0)), "research raises the independent specimen probability by 25%")
	research.director.end_round()

func _check_retirement_and_budget() -> void:
	game.spawner.reset()
	await process_frame
	# Archived module targets must not revive from an old save or consume capacity.
	research.director.load_save_data({"tickets": {"a/old": {"kind": "afterglow", "origin_kind": "archive", "components": {}}}, "active": [{"kind": "afterglow", "origin_kind": "archive", "ticket": "a/old"}]})
	research.director.resume_targets()
	_check(research.director.object_count() == 0 and research.director.tickets.is_empty(), "removed archive target is discarded without reward or reserved space")
	for index in range(game.spawner.MAX_TOTAL_METEORS + 6):
		game.spawner.spawn_meteor("common", Vector2(200, 200), Vector2.ZERO)
	_check(game.meteor_layer.get_child_count() == game.spawner.SpawnPolicy.ATMOSPHERIC_SAFETY_SLOTS, "atmospheric safety ceiling preserves six late, three specimen and one major slots")
	for kind in game.spawner.SpawnPolicy.LATE_TYPES:
		_check(game.spawner.spawn_meteor(kind) != null, "late reservation survives a saturated atmospheric sky: " + kind)
	_check(game.spawner.spawn_meteor("galaxy") != null and game.spawner.spawn_meteor("galaxy") == null, "late shared extra still respects the per-kind ceiling")
	var count: int = game.meteor_layer.get_child_count()
	_check(research.director.try_opportunity(), "extension can consume its reserved budget without removing existing meteors")
	_check(game.meteor_layer.get_child_count() == count and research.director.object_count() <= 3, "extension preserves existing targets and its three-component bound")
	_check(game.spawner.spawn_meteor("major", Vector2(200, 200), Vector2.ZERO) != null, "important target retains its reserved slot")
	_check(game.meteor_layer.get_child_count() + research.director.object_count() <= game.spawner.MAX_TOTAL_METEORS, "combined targets stay within the final safety budget")
	research.director.end_round()
	game.spawner.reset()
	await process_frame
	# Exercise the real dish's spatial acquisition for a recognized anomaly.
	research.director._ensure_ticket("n/dish_test", "rare", "natural")
	research.director._spawn_component({"ticket": "n/dish_test", "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.4, 0.4), "end": Vector2(0.4, 0.4)})
	var pair: Node = research.director.targets()[0]
	pair.set_process(false)
	pair.simulate_tick(1.6)
	game.sky_contacts.refresh_dishes()
	game.sky_contacts.dishes[0].position = pair.global_position
	game.sky_contacts.dishes[0].target = pair.global_position
	game.sky_contacts.dishes[0].arrived = true
	game.sky_contacts._update_dishes(0.02)
	_check(pair.dish_assist_rate > 0.0, "actual dish acquires recognized pair in coverage")
	pair.simulate_tick(0.02)
	_check(pair.get_automatic_contribution() > 0.0, "actual dish work records automatic contribution")
	research.director.end_round()

func _growth_snapshot() -> Dictionary:
	game.progression.reset_manual_combo()
	var meteor: Node = load("res://scripts/meteor.gd").new()
	meteor.configure(Balance.meteor_spec("common"), "common", Vector2(480, 290), Vector2.ZERO, game.progression.get_lifetime_multiplier(), game.spawner._current_features("common"))
	game.meteor_layer.add_child(meteor)
	meteor.set_process(false)
	game.observer.reset()
	game.observer.selected_meteor = meteor
	game.observer.previous_cursor_position = meteor.global_position
	game.observer.cursor_position = meteor.global_position
	game.observer._apply_manual_contact(meteor, 0.05)
	var result := {
		"manual": meteor.get_progress(), "dish": game.sky_contacts._dish_assist_rate(meteor),
		"radius": game.observer._module_tracking_radius(), "dishes": game.sky_contacts.dishes.size(),
		"sweep_distance": game.progression.get_survey_required_distance(), "sweep_count": game.progression.get_survey_spawn_count(),
		"sweep_cooldown": game.progression.get_survey_cooldown_seconds(), "spawn_floor": game.progression.get_regular_spawn_interval_floor(),
		"echo_chance": game.progression.get_observation_echo_probability(), "echo_count": game.progression.get_observation_echo_count(),
		"forecast_lead": game.progression.get_forecast_lead(), "forecast_error": game.progression.get_forecast_max_error("common"),
		"data": game.progression.get_observation_value_multiplier("common", 1), "lifetime": meteor.visible_lifetime,
	}
	game.observer.reset()
	meteor.free()
	return result

func _check_permanent_growth() -> void:
	var current := _growth_snapshot()
	_check(is_equal_approx(current.manual / growth_baseline.manual, 1.15 * 1.10), "empty loadout gains actual manual work from Cygnus and Triangulum")
	_check(is_equal_approx(current.radius / growth_baseline.radius, 1.12 * 1.18), "Cygnus grows the actual cursor radius without modules")
	_check(is_equal_approx(current.dish / growth_baseline.dish, 1.15 * 1.20) and current.dishes == growth_baseline.dishes + 1, "Equuleus improves real dish rate and creates a fifth dish")
	_check(current.sweep_count == growth_baseline.sweep_count + 1 and current.sweep_distance < growth_baseline.sweep_distance and current.sweep_cooldown < growth_baseline.sweep_cooldown, "Aquila changes the production sweep inputs")
	_check(is_equal_approx(current.echo_chance - growth_baseline.echo_chance, 0.1) and current.echo_count == growth_baseline.echo_count + 2, "Delphinus increases the production echo opportunity and burst")
	_check(is_equal_approx(game.progression.get_celestial_multiplier("variable_star", "spawn"), 1.35) and is_equal_approx(game.progression.get_celestial_multiplier("binary_star", "speed"), 1.3) and is_equal_approx(game.progression.get_celestial_multiplier("variable_star", "value"), 1.5), "Sagitta improves both asteroid types through production multipliers")
	_check(is_equal_approx(current.data / growth_baseline.data, 1.10 * 1.15), "Triangulum improves real observation reward calculation")
	for index in range(12): game.progression.record_manual_combo_success()
	_check(game.progression.get_taurus_tracking_radius_bonus() > 25.0 and game.progression.get_taurus_combo_stack_count() == 12 and game.progression.get_manual_combo_window() == 7.0, "Vulpecula grows the live twelve-stack observation rhythm")
	game.progression.reset_manual_combo()
	var before: Dictionary = JSON.parse_string(JSON.stringify(research.get_save_data()))
	research.load_save_data(before)
	_check(research.modules.purchased.is_empty() and game.progression.extension_state == research.state and _growth_snapshot() == current, "JSON restores every permanent effect without inventing modules or retaining a stale state owner")
	# A newly acquired legacy module ID is inventory, not a free research node.
	research.state.research_ids.erase("focus")
	research.modules.grant("focus")
	var current_save: Dictionary = JSON.parse_string(JSON.stringify(research.get_save_data()))
	research.load_save_data(current_save)
	_check(not research.research_owned("focus") and research.modules.owned_count("focus") == 1, "new-catalogue ownership never backfills an old direct-purchase research ID")
	research.load_save_data(before)

func _check_measurement() -> void:
	research.modules.grant("focus")
	research.modules.equip("focus", 0)
	game._begin_observation_phase()
	var original: String = research.modules.slots[0]
	research.modules.slots[0] = ""
	research.changed.emit()
	research.modules.slots[0] = original
	research.changed.emit()
	_check(game._build_round_result().equipment_changed, "A-to-B-to-A equipment remains a mixed round")
	game._begin_observation_phase()
	research.modules.grant("overcharge")
	research.changed.emit()
	var result: Dictionary = game._build_round_result()
	_check(not result.equipment_changed and result.modules_acquired == ["overcharge"], "uninstalled acquisition is growth, not a changed loadout")
	var study: String = research.state.research_ids.pop_back()
	research.changed.emit()
	_check(game._build_round_result().build_changed, "extension research is part of the build measurement")
	research.state.research_ids.append(study)
	research.modules.grant_copy("overcharge")
	research.modules.equip("overcharge", 0)
	research.modules.equip("overcharge", 1)
	game._begin_observation_phase()
	var disk_result: Dictionary = JSON.parse_string(JSON.stringify(game._build_round_result()))
	var clean: Dictionary = game._sanitize_round_result(disk_result)
	_check(clean.equipment_signature.count("overcharge") == 2, "round comparison keeps duplicate installed copies")
	_check(game._validated_module_ids(research.modules.purchased).size() == research.modules.purchased.size(), "ownership history keeps more than five module types")

func _check_migration() -> void:
	var before: Dictionary = research.get_save_data()
	_check(not research.load_save_data({"version": 99}) and research.get_save_data() == before, "unknown deep-sky version cannot reset state")
	_check(not research.load_save_data({"version": 3, "extension": {"catalogue_version": 99}}) and research.get_save_data() == before, "future catalogue cannot be migrated or overwritten")
	var save: Dictionary = game._build_save_data()
	save.deep_sky.version = 99
	game._apply_save_data(save)
	_check(research.get_save_data() == before, "whole game rejects future version before applying any mutation")
	research.load_save_data({"version": 1, "observations": 2, "progress": 0.4, "cooldown": 2.0, "modules": {"purchased": ["record", "revisit"], "slots": ["record", "revisit", "", "", ""], "unlocked_slots": 5}})
	_check(research.modules.unlocked_slots == 5 and research.research_owned("ext_protocol"), "v1 preserves capacity without inventing plans")

	var old: Dictionary = research.get_save_data()
	old.version = 2
	old.anomalies = {"active": [{"ticket": "p/old", "kind": "spectrum", "origin_kind": "plan", "stage": 1, "stage_progress": 0.4, "start": [0.3, 0.4], "end": [0.7, 0.5]}], "tickets": {"p/old": {"components": {}, "sample_units": 0, "completed": false}}}
	research.load_save_data(old)
	research.resume_targets()
	var migrated: Array = research.director.targets()
	_check(migrated.size() == 1 and migrated[0].kind == "rare" and is_equal_approx(migrated[0].get_progress(), 0.7), "v2 active spectrum keeps normalized progress as a rare meteor")
	research.director.end_round()

func _check_new_modules() -> void:
	Input.action_press(&"nw_observe")
	game.observer.simulation_holding = true
	_sky()
	research.director.end_round()
	_clear_split_sky()
	research.modules.load_save_data({"purchased": ["linear_observation", "capture_hold", "overcharge"], "slots": ["linear_observation", "capture_hold", "overcharge"], "unlocked_slots": 5})
	game._begin_observation_phase()
	game.spawner.module_rng.seed = 123
	# Exercise real manual and automatic completion signals, rather than calling
	# the module counter directly. Generated targets remain a valid charge source.
	for index in range(30):
		var meteor = game.spawner.spawn_meteor("common", Vector2(500, 300), Vector2(150, 0), 10.0)
		meteor.set_meta("gemini_echo", true)
		meteor.set_process(false)
		if index % 2 == 0:
			game.observer.cursor_position = meteor.global_position
			game.observer.previous_cursor_position = meteor.global_position
			game.observer._apply_manual_contact(meteor, 20.0)
			meteor.simulate_tick(0.0)
		else:
			meteor.set_dish_assist_rate(10.0)
			meteor.simulate_tick(0.11)
		_check(meteor.observed_successfully, "real completion reaches the accounting route")
		meteor.free()
	_check(research.modules.burst_remaining == 9.0, "thirty mixed real completions charge the burst")
	research.modules.advance_time(1.5)
	research.director._ensure_ticket("n/captured", "rare", "natural")
	research.director._spawn_component({"ticket": "n/captured", "kind": "rare", "origin_kind": "natural", "component": 0, "start": Vector2(0.3, 0.4), "end": Vector2(0.7, 0.4)})
	var rare = research.director.targets()[0]
	rare.set_process(false)
	rare.simulate_tick(1.6)
	game.observer.cursor_position = rare.position
	game.observer.previous_cursor_position = rare.position
	game.observer._apply_manual_contact(rare, 0.00001)
	game.observer.simulation_holding = true
	var rare_age: float = rare.age
	rare.simulate_tick(0.5)
	_check(is_equal_approx(rare.age - rare_age, 0.35), "rare meteor movement and lifetime run at 70% inside the field")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(saved)
	_freeze(game)
	_check(research.modules.burst_remaining == 7.5, "whole-game save restore preserves remaining burst time")
	var restored = research.director.targets()[0]
	restored.restore_progress({"age": 2.0, "captured_once": true, "capture_remaining": 6.0})
	game.observer.cursor_position = restored.position + Vector2(10000, 0)
	var restored_age: float = restored.age
	restored.simulate_tick(0.5)
	_check(is_equal_approx(restored.age - restored_age, 0.5), "old saved capture timers cannot freeze restored targets outside the field")
	_check(not restored.get_save_data().has("capture_remaining"), "new saves contain no lingering capture timer")
	Input.action_release(&"nw_observe")
	game.observer.simulation_holding = false
	game.upgrade_tree.open_tree()
	var remaining: float = research.modules.burst_remaining
	game.set_process(true)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	_check(research.modules.burst_remaining == remaining, "chart pause does not drain the burst clock")
	game.upgrade_tree.close_tree()
	game._begin_observation_phase(true)
	_check(research.modules.burst_remaining == 0.0, "next round cannot inherit an active burst")
	research.director.end_round()
	_clear_split_sky()
	await process_frame
