extends SceneTree

const Session = preload("res://tests/support/economy_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("ECONOMY_SIMULATOR: " + message)

func _run() -> void:
	check(not Session.validate({"observation_chance": 1.1}).is_empty(), "reject invalid probability")
	check(not Session.validate({"strategy": "oops"}).is_empty(), "reject unknown strategy")
	check(not Session.validate({"seed": 1.5}).is_empty(), "reject fractional seed")
	check(not Session.validate({"type_chances": {"unknown": 1}}).is_empty(), "reject unknown target override")
	var first := await replay()
	var second := await replay()
	check(first == second, "same seed and actions reproduce economy and coverage")
	await checkpoint_replay(false)
	await checkpoint_replay(true)
	var session := Session.new()
	await session.setup(self, {"observation_chance": 0.0, "automatic_equipment": false})
	check(session.game.active_save_slot == 0, "diagnostic never owns a player save")
	var before := session.snapshot()
	var result: Dictionary = await session.act({"action": "buy", "id": "better_lens", "revision": 99})
	check(not result.ok and before == session.snapshot(), "stale command does not mutate state")
	result = await session.act({"action": "buy", "id": "better_lens", "revision": session.revision})
	check(not result.ok and before == session.snapshot(), "unaffordable purchase does not mutate state")
	result = await session.act({"action": "next_round", "revision": session.revision})
	check(result.ok and session.game.progression.total_data_earned == 0, "zero coverage with equipment off gives zero income")
	check(not session.game.observer.seen.is_empty(), "real scheduler still spawns targets")
	# Exercise production completion -> fragment creation -> next-tick work.
	session.game.suppress_phase_transition = true
	session.game.upgrade_tree.close_tree()
	session.game.suppress_phase_transition = false
	session.game._begin_observation_phase(true, -1.0, true)
	session.game.observer.configuration.type_chances = {"fragment": 1.0}
	var parent = session.game.spawner.spawn_meteor("fragment", Vector2(400, 300), Vector2(80, 0))
	session.game.simulate_tick()
	check(parent.observed_successfully, "selected parent uses real completion")
	check(session.game.observer.seen.get("fragment_piece", 0) == 0, "children not processed in parent's tick")
	session.game.simulate_tick()
	check(session.game.observer.selected.get("fragment_piece", 0) > 0, "fragments receive 100 percent coverage")
	var successes: int = session.game.progression.success_count
	session.game.simulate_tick()
	check(session.game.progression.success_count == successes, "completed objects do not pay twice")
	# Unlock through the existing diagnostic helper, then buy extension research
	# and draw/equip through the exact player transaction methods.
	session.game.progression.debug_purchase_all()
	session.game._end_observation_phase()
	session.game.hud.hide_phase_summary()
	session.game.upgrade_tree.open_tree()
	session.game.progression.add_debug_data(1000000000.0)
	result = await session.act({"action": "buy", "id": "ext_trace_study", "revision": session.revision})
	check(result.ok and session.game.deep_sky.research_owned("ext_trace_study"), "outer research purchase")
	check(session.game.deep_sky.samples == 8, "first-draw grant is present in the external session")
	result = await session.act({"action": "draw", "revision": session.revision})
	check(result.ok and session.game.deep_sky.samples == 0, "real paid module draw")
	var module_id: String = result.get("result", "")
	result = await session.act({"action": "equip", "id": module_id, "slot": 0, "revision": session.revision})
	check(result.ok and session.game.deep_sky.modules.slots[0] == module_id, "external module choice")
	session.game.observer.configuration.type_chances = {"anomaly_rare": 1.0}
	var samples_before: int = session.game.deep_sky.state.samples_earned
	session.game.suppress_phase_transition = true
	session.game.upgrade_tree.close_tree()
	session.game.suppress_phase_transition = false
	session.game._begin_observation_phase(true, -1.0, true)
	# Inject a scheduled descriptor, not a reward; occurrence itself is random.
	var director = session.game.deep_sky.director
	director._ensure_ticket("probe/rare", "rare", "natural")
	director.pending.append_array(director._event_descriptors("probe/rare", "rare", "single", 0.0))
	for tick in 60: session.game.simulate_tick()
	check(session.game.deep_sky.state.samples_earned == samples_before, "anomaly warning blocks instant observation")
	for tick in 40: session.game.simulate_tick()
	check(session.game.deep_sky.state.samples_earned > samples_before, "scheduled anomaly completes through real sample callback")
	await session.dispose()
	session = Session.new()
	await session.setup(self, {"observation_chance": 1.0, "completion_source": "automatic", "automatic_equipment": false})
	await session.act({"action": "next_round", "revision": session.revision})
	check(session.game.progression.automatic_successes > 0 and session.game.progression.manual_successes == 0, "synthetic automatic work uses automatic reward lane")
	await session.dispose()
	session = Session.new()
	await session.setup(self, {"strategy": "priority", "priority": ["observation_streak"], "auto_draw": false})
	session.game.progression.add_debug_data(100.0)
	await session.auto_purchase()
	check(session.game.progression.has_upgrade("better_lens"), "priority strategy buys needed opening research")
	check(not session.game.progression.has_upgrade("long_exposure") and session.game.progression.observation_data == 90.0, "priority strategy saves rather than spending on cheaper nonpriority research")
	session.game.progression.add_debug_data(30.0)
	await session.auto_purchase()
	check(session.game.progression.has_upgrade("observation_streak"), "saved priority is purchased once affordable")
	await session.dispose()
	if failures.is_empty():
		print("ECONOMY_SIMULATOR_PASS: seeded replay, checkpoint continuation/branching, rejected actions, real spawn/completion/fragments and outer transactions")
		quit(0)
	else:
		quit(1)

func replay() -> Dictionary:
	var session := Session.new()
	await session.setup(self, {"seed": 731, "max_rounds": 3, "strategy": "random"})
	for i in 3:
		await session.act({"action": "next_round", "revision": session.revision})
		await session.auto_purchase()
	var report := session.report().duplicate(true)
	check(absf(report.ledger_error) < 0.01, "earned minus spending equals bank")
	check(report.rounds.size() == 3 and report.active_seconds >= 60.0 - 0.000001, "rounds advance fixed game time")
	check(report.purchases.size() > 0, "automatic buyer makes legal purchases")
	await session.dispose()
	return report

func comparable(report: Dictionary) -> Dictionary:
	var result := report.duplicate(true)
	result.erase("checkpoint_lineage")
	result.erase("resumed_segment")
	for action in result.actions: action.command.erase("revision")
	return result

func checkpoint_replay(late: bool) -> void:
	var session := Session.new()
	await session.setup(self, {"seed": 42, "strategy": "random", "auto_draw": false, "auto_equip": false})
	if late:
		session.game.progression.debug_purchase_all()
		# Keep one outer research unowned so the normal stop condition allows play.
		for id in session.Expansion.RESEARCH_ORDER:
			if id != session.Expansion.RESEARCH_ORDER.back() and not session.game.deep_sky.research_owned(id):
				session.game.deep_sky.state.research_ids.append(id)
		session.game.deep_sky.modules.unlocked_slots = 5
		session.game.deep_sky.modules.grant("focus")
		session.game.deep_sky.modules.grant("overcharge")
		await session.act({"action": "equip", "id": "focus", "slot": 0, "revision": session.revision})
		await session.act({"action": "equip", "id": "overcharge", "slot": 1, "revision": session.revision})
		session.game.deep_sky.state.award_samples(30)
	for i in (3 if late else 18):
		await session.act({"action": "next_round", "revision": session.revision})
		if not late: await session.auto_purchase()
	var folder := "res://build/checkpoint-test-%d-%s" % [OS.get_process_id(), str(late)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("state.json")
	var result: Dictionary = session.save_checkpoint(path)
	check(result.ok, "save at decision boundary")
	check(session.save_checkpoint(path).ok, "atomic save replaces existing checkpoint")
	if late:
		check(not session.game.sky_contacts.dishes.is_empty(), "late checkpoint includes active dish positions")
		check(session.game.observer.seen.get("fragment_piece", 0) > 0, "late checkpoint exercises production fragments")
	var boundary := session.snapshot()
	var history := session.report().duplicate(true)
	for i in 3:
		await session.act({"action": "next_round", "revision": session.revision})
		if not late: await session.auto_purchase()
		else: await session.act({"action": "draw", "revision": session.revision})
	var expected := comparable(session.report())
	var old_revision := session.revision
	result = await session.load_checkpoint(path)
	check(result.ok, "load checkpoint: " + str(result))
	if not result.ok:
		await session.dispose()
		return
	check(session.revision > old_revision, "load invalidates old commands")
	var restored := session.snapshot()
	restored.revision = boundary.revision
	check(restored == boundary, "restored public state equals checkpoint")
	check(session.game.active_save_slot == 0, "restored session cannot save player slots")
	for i in 3:
		await session.act({"action": "next_round", "revision": session.revision})
		if not late: await session.auto_purchase()
		else: await session.act({"action": "draw", "revision": session.revision})
	var actual := comparable(session.report())
	check(session.report().resumed_segment.rounds == 3, "resumed segment excludes historical rounds")
	if actual != expected:
		for key in expected:
			if actual[key] != expected[key]: print("CHECKPOINT_DIFFERENCE late=", late, " key=", key, " expected=", expected[key], " actual=", actual[key])
	check(actual == expected, "uninterrupted and restored continuation agree, late=" + str(late))
	var before := session.snapshot()
	result = await session.load_checkpoint(path, "exact", {"quality": 0.4})
	check(not result.ok and result.error == "checkpoint_environment_mismatch" and before == session.snapshot(), "exact mode rejects changed config without mutation")
	result = await session.load_checkpoint(path, "branch", {"seed": 17})
	check(not result.ok and result.error == "checkpoint_seed_mismatch" and before == session.snapshot(), "branch cannot mislabel retained RNG as a new seed")
	var saved := session.Checkpoint.read_file(path)
	saved.data.viewport_size += Vector2.ONE
	session.Checkpoint.write_file(folder.path_join("viewport.json"), saved.data, saved.source)
	result = await session.load_checkpoint(folder.path_join("viewport.json"))
	check(not result.ok and result.error == "checkpoint_environment_mismatch" and before == session.snapshot(), "exact mode rejects different observation geometry")
	saved.data.viewport_size -= Vector2.ONE
	saved.source.engine = "different-engine"
	session.Checkpoint.write_file(folder.path_join("changed.json"), saved.data, saved.source)
	result = await session.load_checkpoint(folder.path_join("changed.json"))
	check(not result.ok and result.error == "checkpoint_environment_mismatch" and before == session.snapshot(), "exact mode rejects changed environment without mutation")
	result = await session.load_checkpoint(folder.path_join("changed.json"), "branch", {"quality": 0.4})
	check(result.ok and result.environment_changed and session.config.quality == 0.4, "branch explicitly accepts changed environment/config")
	check(session.game.progression.observation_data == boundary.data and session.report().spent == history.spent, "branch preserves historical money and spending")
	check(session.checkpoint_lineage.back().round == history.rounds.size(), "report marks start of changed-economy segment")
	before = session.snapshot()
	var invalid := FileAccess.open(folder.path_join("invalid.json"), FileAccess.WRITE)
	invalid.store_string('{"format":"nightwatch-economy-checkpoint","version":999}')
	invalid.close()
	result = await session.load_checkpoint(folder.path_join("invalid.json"))
	check(not result.ok and before == session.snapshot(), "unsupported checkpoint never mutates session")
	result = await session.load_checkpoint(folder.path_join("missing.json"))
	check(not result.ok and before == session.snapshot(), "missing checkpoint never mutates session")
	result = session.save_checkpoint(folder.path_join("missing/state.json"))
	check(not result.ok and before == session.snapshot(), "write failure does not mutate session")
	var damaged = JSON.parse_string(FileAccess.get_file_as_string(path))
	damaged.sha256 = "incorrect"
	invalid = FileAccess.open(folder.path_join("damaged.json"), FileAccess.WRITE)
	invalid.store_string(JSON.stringify(damaged))
	invalid.close()
	result = await session.load_checkpoint(folder.path_join("damaged.json"))
	check(not result.ok and result.error == "checkpoint_checksum_mismatch" and before == session.snapshot(), "corrupt checkpoint rejected before mutation")
	session.game.observation_phase_active = true
	check(not session.save_checkpoint(path).ok, "refuse mid-observation checkpoint")
	session.game.observation_phase_active = false
	await session.dispose()
