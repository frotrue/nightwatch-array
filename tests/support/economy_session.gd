extends RefCounted

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Driver = preload("res://tests/support/economy_observer.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Expansion = preload("res://scripts/expansion_data.gd")
const Checkpoint = preload("res://tests/support/economy_checkpoint.gd")
const TARGET_TYPES := ["common", "fast", "fragment", "fragment_piece", "fireball", "major",
	"satellite", "variable_star", "binary_star", "comet", "galaxy", "black_hole", "stellar", "white_hole", "anomaly_rare"]
const DEFAULTS := {
	"seed": 42, "observation_chance": 0.7, "fragment_chance": 1.0,
	"type_chances": {}, "quality": 0.75, "completion_source": "manual",
	"automatic_equipment": true, "strategy": "cheapest", "priority": [],
	"max_rounds": 300, "max_active_seconds": 14400.0,
	"purchase_limit": 0, "auto_draw": true, "auto_equip": true,
}
# A documented heuristic, not an income oracle or look-ahead optimizer.
const INCOME_PRIORITY := ["observation_streak", "perfect_observation", "shower_detector",
	"taurus_full_gallop", "double_star_resolution", "perseid_outburst", "echo_delay_line",
	"galaxy_imaging", "fireball_tail", "draco_synthesis", "draco_apotheosis",
	"ext_tri_photometry", "ext_tri_catalogue", "ext_sge_stream", "ext_cnc_yield", "ext_sgr_yield"]

var game
var tree: SceneTree
var config: Dictionary = {}
var purchase_rng := RandomNumberGenerator.new()
var rounds: Array[Dictionary] = []
var purchases: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var spent := 0.0
var revision := 0
var ready_for_decision := true
var original_locale := ""
var original_mouse_mode := 0
var checkpoint_lineage: Array[Dictionary] = []
var source_manifest: Dictionary = {}

func save_checkpoint(path: String) -> Dictionary:
	if not ready_for_decision or game.observation_phase_active:
		return {"ok": false, "error": "not_at_decision_boundary"}
	var result := Checkpoint.write_file(path, Checkpoint.capture(self), source_manifest)
	result["revision"] = revision
	return result

func load_checkpoint(path: String, mode: String = "exact", overrides: Dictionary = {}) -> Dictionary:
	if not ready_for_decision or game.observation_phase_active:
		return {"ok": false, "error": "not_at_decision_boundary"}
	if mode not in ["exact", "branch"]: return {"ok": false, "error": "invalid_resume_mode"}
	if Checkpoint.source_manifest() != source_manifest:
		return {"ok": false, "error": "restart_required", "hint": "Source files changed during this process. Save, restart Godot, then resume in branch mode."}
	var saved := Checkpoint.read_file(path)
	if not saved.ok: return saved
	var problem := Checkpoint.validate(saved.data, self)
	if not problem.is_empty(): return {"ok": false, "error": problem}
	var settings: Dictionary = saved.data.config.duplicate(true)
	settings.merge(overrides, true)
	var errors := validate(settings)
	if not errors.is_empty(): return {"ok": false, "error": "invalid_checkpoint_config", "details": errors}
	if settings.seed != saved.data.config.seed:
		return {"ok": false, "error": "checkpoint_seed_mismatch", "hint": "A checkpoint preserves its RNG history. Start a fresh run to change seed."}
	var source := source_manifest
	var changed: bool = saved.source != source or settings != saved.data.config or saved.data.viewport_size != game.get_viewport_rect().size
	if mode == "exact" and changed:
		return {"ok": false, "error": "checkpoint_environment_mismatch", "hint": "Use mode=branch to apply current code/config while retaining historical progress."}
	# Construct a fresh isolated game so loading never inherits later runtime
	# state. Only replace this session after the checkpoint has been validated.
	var replacement = get_script().new()
	await replacement.setup(tree, settings)
	Checkpoint.restore(replacement, saved.data)
	await tree.process_frame
	await dispose()
	game = replacement.game
	config = replacement.config
	purchase_rng = replacement.purchase_rng
	rounds = replacement.rounds
	purchases = replacement.purchases
	actions = replacement.actions
	spent = replacement.spent
	# Loading mutates the current protocol state: never revive an old revision.
	revision = maxi(revision, replacement.revision) + 1
	checkpoint_lineage = replacement.checkpoint_lineage
	checkpoint_lineage.append({"path": ProjectSettings.globalize_path(path), "sha256": saved.sha256,
		"mode": mode, "environment_changed": changed, "round": rounds.size(),
		"active_seconds": game.elapsed_time, "earned": game.progression.total_data_earned,
		"spent": spent, "bank": game.progression.observation_data,
		"purchase_count": purchases.size(),
		"saved_viewport": [saved.data.viewport_size.x, saved.data.viewport_size.y],
		"loaded_viewport": [game.get_viewport_rect().size.x, game.get_viewport_rect().size.y],
		"saved_source": saved.source, "loaded_source": source,
		"saved_config": saved.data.config.duplicate(true), "loaded_config": config.duplicate(true)})
	tree.paused = true
	TranslationServer.set_locale("en")
	return {"ok": true, "revision": revision, "mode": mode, "environment_changed": changed,
		"rounds_completed": rounds.size(), "path": ProjectSettings.globalize_path(path)}

static func validate(input: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in input:
		if not DEFAULTS.has(key): errors.append("Unknown setting: " + str(key))
	for key in ["observation_chance", "fragment_chance", "quality"]:
		if not _number_between(input.get(key, DEFAULTS[key]), 0.0, 1.0): errors.append(key + " must be in [0, 1]")
	for key in ["seed", "max_rounds", "purchase_limit"]:
		var value = input.get(key, DEFAULTS[key])
		if not _number_between(value, 0.0, 2147483646.0) or float(value) != floorf(float(value)):
			errors.append(key + " must be a nonnegative integer")
	if not _number_between(input.get("max_active_seconds", 14400.0), 1.0, 86400.0):
		errors.append("max_active_seconds must be in [1, 86400]")
	if input.get("strategy", "cheapest") not in ["cheapest", "random", "income_first", "priority", "external"]:
		errors.append("Unknown strategy")
	if input.get("completion_source", "manual") not in ["manual", "automatic"]:
		errors.append("Unknown completion_source")
	for key in ["automatic_equipment", "auto_draw", "auto_equip"]:
		if not input.get(key, DEFAULTS[key]) is bool: errors.append(key + " must be boolean")
	var overrides = input.get("type_chances", {})
	if not overrides is Dictionary:
		errors.append("type_chances must be an object")
	else:
		for kind in overrides:
			if kind not in TARGET_TYPES: errors.append("Unknown target: " + str(kind))
			if not _number_between(overrides[kind], 0.0, 1.0): errors.append("Invalid chance: " + str(kind))
	var priority = input.get("priority", [])
	if not priority is Array:
		errors.append("priority must be an array of research IDs")
	else:
		for id in priority:
			if not id is String or (Balance.upgrade_definition(id).is_empty() and not Expansion.RESEARCH.has(id)):
				errors.append("Unknown priority research: " + str(id))
	return errors

static func _number_between(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func setup(scene_tree: SceneTree, settings: Dictionary) -> void:
	tree = scene_tree
	config = DEFAULTS.duplicate(true)
	config.merge(settings, true)
	original_locale = TranslationServer.get_locale()
	original_mouse_mode = Input.mouse_mode
	game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	game.get_node("ObservationController").set_script(Driver)
	tree.root.add_child(game)
	# Only explicit simulate_tick calls advance game time, including across yields.
	game.set_physics_process(false)
	game.set_process(false)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	game.settings.motion_intensity = 0.0
	game._apply_accessibility_settings()
	game.observer.configuration = config
	game.observer.coverage_rng.seed = int(config.seed) + 6000
	purchase_rng.seed = int(config.seed) + 7000
	game.events.reset()
	game.spawner.reset()
	game.spawner.spawn_policy.reseed(int(config.seed))
	game.spawner.rng.seed = int(config.seed)
	game.spawner.forecast_rng.seed = int(config.seed) + 1000
	game.spawner.warm_contact_rng.seed = int(config.seed) + 2000
	game.events.rng.seed = int(config.seed) + 3000
	game.spawner.echo_rng.seed = int(config.seed) + 4000
	game.spawner.module_rng.seed = int(config.seed) + 5000
	game.deep_sky.director.scheduler_seed = int(config.seed) + 8000
	game.deep_sky.director.reset()
	game.deep_sky.state.acquisition_seed = int(config.seed) + 9000
	# First round has not begun for this tool: expose a decision boundary at t=0.
	game.observation_phase_active = false
	game.spawner.reset()
	game.events.pause_for_intermission()
	game.upgrade_tree.open_tree()
	await tree.process_frame
	source_manifest = Checkpoint.source_manifest()

func visible_research() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in Balance.UPGRADE_NODES:
		var id: String = definition.id
		var state: String = game.progression.get_node_state(id)
		if state == "hidden": continue
		result.append({"id": id, "name": tr("UPGRADE_%s_NAME" % id.to_upper()),
			"description": tr("UPGRADE_%s_DESC" % id.to_upper()), "cost": definition.cost,
			"state": state, "affordable": game.progression.can_purchase(id),
			"requires": definition.prerequisites, "branch": definition.branch})
	if game.deep_sky.available():
		for id in Expansion.RESEARCH_ORDER:
			var owned: bool = game.deep_sky.research_owned(id)
			result.append({"id": id, "name": game.deep_sky.research_name(id),
				"description": game.deep_sky.research_description(id), "cost": game.deep_sky.research_cost(id),
				"state": "purchased" if owned else ("available" if game.deep_sky.research_ready(id) else "locked"),
				"affordable": game.deep_sky.can_purchase(id), "requires": Expansion.RESEARCH[id].requires,
				"branch": Expansion.RESEARCH[id].branch})
	return result

func snapshot() -> Dictionary:
	var inventory: Array[Dictionary] = []
	if game.deep_sky.modules_unlocked():
		for id in game.deep_sky.modules.purchased:
			inventory.append({"id": id, "count": game.deep_sky.modules.owned_count(id),
				"name": tr("MODULE_%s_NAME" % id.to_upper()), "description": tr("MODULE_%s_DESC" % id.to_upper())})
	return {"protocol": 1, "revision": revision, "phase": "decision" if ready_for_decision else "observation",
		"checkpoint_modes": ["exact", "branch"],
		"active_seconds": game.elapsed_time, "rounds_completed": rounds.size(),
		"next_round_seconds": game.progression.get_observation_duration(),
		"data": game.progression.observation_data, "research": visible_research(),
		"modules_unlocked": game.deep_sky.modules_unlocked(), "samples": game.deep_sky.samples,
		"draw_cost": game.deep_sky.state.draw_cost() if game.deep_sky.modules_unlocked() else null,
		"inventory": inventory, "slots": game.deep_sky.modules.slots.duplicate(),
		"slot_capacity": game.deep_sky.modules.unlocked_slots,
		"last_round": rounds.back().duplicate(true) if not rounds.is_empty() else {},
		"stop_reason": stop_reason()}

func stop_reason() -> String:
	if game.progression.is_research_complete() and game.deep_sky.state.research_ids.size() == Expansion.RESEARCH_ORDER.size():
		return "all_research_complete"
	if rounds.size() >= int(config.max_rounds): return "round_limit"
	if game.elapsed_time >= float(config.max_active_seconds) - 0.000001: return "active_time_limit"
	return ""

func act(command: Dictionary) -> Dictionary:
	if not ready_for_decision: return {"ok": false, "error": "not_at_decision_boundary"}
	if command.get("revision") != revision: return {"ok": false, "error": "stale_revision", "revision": revision}
	var action = command.get("action", "")
	if action in ["save", "load"]:
		if not command.get("path") is String: return {"ok": false, "error": "invalid_checkpoint_path"}
		if action == "save": return save_checkpoint(command.path)
		if not command.get("mode", "exact") is String or not command.get("config", {}) is Dictionary:
			return {"ok": false, "error": "invalid_resume_options"}
		return await load_checkpoint(command.path, command.get("mode", "exact"), command.get("config", {}))
	if action not in ["buy", "draw", "equip", "next_round"]: return {"ok": false, "error": "unknown_action"}
	var ok := false
	var detail := ""
	if action == "next_round":
		if not stop_reason().is_empty(): return {"ok": false, "error": stop_reason()}
		await _run_round()
		ok = true
	elif action == "buy":
		var samples_before: int = game.deep_sky.state.samples_earned
		var id = command.get("id", "")
		if not id is String: return {"ok": false, "error": "invalid_id"}
		var cost := 0.0
		if not Balance.upgrade_definition(id).is_empty():
			cost = float(Balance.upgrade_definition(id).cost)
			ok = game.progression.request_purchase(id)
		elif Expansion.RESEARCH.has(id):
			cost = game.deep_sky.research_cost(id)
			ok = game.deep_sky.purchase(id)
		if ok:
			spent += cost
			purchases.append({"id": id, "cost": cost, "active_seconds": game.elapsed_time, "round": rounds.size()})
			if not rounds.is_empty():
				# Unlock grants happen between rounds, outside the observation ledger.
				var bonus: int = game.deep_sky.state.samples_earned - samples_before
				rounds.back().samples += bonus
				rounds.back()["sample_bonus"] = int(rounds.back().get("sample_bonus", 0)) + bonus
				rounds.back().purchases.append(id)
				rounds.back().bank_after_purchases = game.progression.observation_data
	elif action == "draw":
		game.module_popup.open_draw()
		detail = game.deep_sky.draw_module()
		ok = not detail.is_empty()
		game.module_popup.close()
	elif action == "equip":
		var id = command.get("id", "")
		var slot = command.get("slot", -1)
		if not id is String or not _number_between(slot, 0, 4) or float(slot) != floorf(float(slot)):
			return {"ok": false, "error": "invalid_equipment"}
		game.module_popup.open()
		ok = game.deep_sky.equip(id, int(slot))
		game.module_popup.close()
	if not ok: return {"ok": false, "error": "action_rejected", "revision": revision}
	actions.append({"command": command.duplicate(true), "active_seconds": game.elapsed_time, "result": detail})
	revision += 1
	return {"ok": true, "revision": revision, "result": detail}

func _run_round() -> void:
	ready_for_decision = false
	# Close through the real transition owner. Suppress its implicit round start
	# because the runner starts exactly one round below.
	game.suppress_phase_transition = true
	game.upgrade_tree.close_tree()
	game.suppress_phase_transition = false
	game._begin_observation_phase(not rounds.is_empty(), -1.0, true)
	var start: float = game.elapsed_time
	var earned_before: float = game.progression.total_data_earned
	var samples_before: int = game.deep_sky.state.samples_earned
	var manual_before: int = game.progression.manual_successes
	var auto_before: int = game.progression.automatic_successes
	var ticks := 0
	while game.observation_phase_active and game.elapsed_time < float(config.max_active_seconds) - 0.000001:
		game.simulate_tick()
		ticks += 1
		if ticks % 120 == 0:
			await tree.process_frame
	var partial: bool = game.observation_phase_active
	if partial: game._end_observation_phase()
	game.hud.hide_phase_summary()
	game.upgrade_tree.open_tree()
	var affordable := 0
	for node in visible_research():
		if node.affordable: affordable += 1
	rounds.append({"round": rounds.size() + 1, "active_seconds": game.elapsed_time,
		"duration": game.elapsed_time - start, "partial": partial,
		"income": game.progression.total_data_earned - earned_before,
		"samples": game.deep_sky.state.samples_earned - samples_before,
		"manual_completions": game.progression.manual_successes - manual_before,
		"automatic_completions": game.progression.automatic_successes - auto_before,
		"affordable_at_end": affordable, "bank_before_purchases": game.progression.observation_data,
		"bank_after_purchases": game.progression.observation_data, "purchases": []})
	ready_for_decision = true
	await tree.process_frame

func auto_purchase() -> void:
	var count := 0
	while int(config.purchase_limit) == 0 or count < int(config.purchase_limit):
		var candidates: Array[Dictionary] = []
		for node in visible_research():
			if node.affordable: candidates.append(node)
		if candidates.is_empty(): break
		candidates.sort_custom(func(a, b): return a.cost < b.cost if a.cost != b.cost else a.id < b.id)
		var chosen: Dictionary = candidates.front()
		if config.strategy == "random":
			chosen = candidates[purchase_rng.randi_range(0, candidates.size() - 1)]
		elif config.strategy in ["income_first", "priority"]:
			var order: Array = INCOME_PRIORITY if config.strategy == "income_first" else config.priority
			var waiting := false
			for id in order:
				for node in visible_research():
					if node.id != id or node.state != "available": continue
					if config.strategy == "priority" and not node.affordable: waiting = true
					if node.affordable: chosen = node; waiting = true
					break
				if waiting: break
			if waiting and config.strategy == "priority" and not _priority_affordable(order): break
		var result: Dictionary = await act({"action": "buy", "id": chosen.id, "revision": revision})
		if not result.ok: break
		count += 1
	if config.auto_draw and game.deep_sky.modules_unlocked():
		while game.deep_sky.samples >= game.deep_sky.state.draw_cost():
			var result: Dictionary = await act({"action": "draw", "revision": revision})
			if not result.ok: break
	if config.auto_equip and game.deep_sky.modules_unlocked():
		for slot in range(game.deep_sky.modules.unlocked_slots):
			if game.deep_sky.modules.slots[slot] != "": continue
			for id in game.deep_sky.modules.purchased:
				if game.deep_sky.modules.spare_count(id) > 0:
					await act({"action": "equip", "id": id, "slot": slot, "revision": revision})
					break

func _priority_affordable(order: Array) -> bool:
	for id in order:
		for node in visible_research():
			if node.id == id and node.state == "available": return node.affordable
	return true

func report() -> Dictionary:
	var longest_empty := 0
	var empty := 0
	var maximum_batch := 0
	for row in rounds:
		empty = empty + 1 if row.purchases.is_empty() else 0
		longest_empty = maxi(longest_empty, empty)
		maximum_batch = maxi(maximum_batch, row.purchases.size())
	var segment := {}
	if not checkpoint_lineage.is_empty():
		var origin: Dictionary = checkpoint_lineage.back()
		segment = {"rounds": rounds.size() - int(origin.round),
			"active_seconds": game.elapsed_time - float(origin.active_seconds),
			"earned": game.progression.total_data_earned - float(origin.earned),
			"spent": spent - float(origin.spent), "purchases": purchases.size() - int(origin.purchase_count)}
	return {"config": config, "engine": Engine.get_version_info(), "source": source_manifest, "stop_reason": stop_reason(),
		"checkpoint_lineage": checkpoint_lineage,
		"resumed_segment": segment,
		"active_seconds": game.elapsed_time, "rounds": rounds, "purchases": purchases,
		"actions": actions, "earned": game.progression.total_data_earned,
		"spent": spent, "bank": game.progression.observation_data,
		"ledger_error": game.progression.total_data_earned - spent - game.progression.observation_data,
		"base_research": game.progression.purchased_nodes.size(),
		"extension_research": game.deep_sky.state.research_ids.size(),
		"maximum_purchase_batch": maximum_batch, "longest_no_purchase_rounds": longest_empty,
		"targets_seen": game.observer.seen, "targets_selected": game.observer.selected,
		"model": "instant_work; equivalent tracking quality; no cursor geometry or survey; equipment optional",
		"limitations": "Synthetic economy only: speed, radius, slowdown and overcharge uptime are not human-play estimates."}

func dispose() -> void:
	game.queue_free()
	await tree.process_frame
	tree.paused = false
	TranslationServer.set_locale(original_locale)
	Input.mouse_mode = original_mouse_mode
