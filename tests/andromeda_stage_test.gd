extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Modules = preload("res://scripts/observation_modules.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game._enter_andromeda()
	_check(not game.andromeda.is_open(), "galaxy unlock gates stage entry")
	game.progression.debug_purchase_all()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	_check(game.upgrade_tree.andromeda_button.is_visible_in_tree(), "real galaxy chart exposes Andromeda entry")
	var chart = game.upgrade_tree
	var hub = chart.galaxy_hub
	_check(hub.is_visible_in_tree() and hub.destination_buttons.keys() == ["andromeda"], "hub lists only actual playable destinations")
	_check(not chart.content_clip.visible and not chart.overlay.get_node("ChartHeader").visible, "hub removes old sky, install counts and research header")
	_check(not chart.galactic_panel.visible and not chart.galactic_ledger.visible and not chart.galactic_core_hit.visible, "old research inspector, ledger and core hitbox are gone")
	var selection_balance: float = game.progression.observation_data
	var selection_research: int = game.progression.upgrade_level
	hub.destination_buttons.andromeda.pressed.emit()
	hub.select_destination("not_implemented")
	_check(hub.selected_id == "andromeda" and game.progression.observation_data == selection_balance and game.progression.upgrade_level == selection_research, "destination selection cannot purchase research or choose an unavailable galaxy")
	for definition in chart.Balance.UPGRADE_NODES:
		if definition.branch == "local_group":
			var node_id := String(definition.id)
			_check(not chart.node_buttons[node_id].visible and not chart._node_interaction_ready(node_id), "retired research is invisible and non-interactive: " + node_id)
	hub.chart_button.pressed.emit()
	_check(not hub.visible and chart.content_clip.visible and chart._galactic_chart_is_readable(), "completed constellations remain accessible through explicit navigation")
	chart.hub_return_button.pressed.emit()
	_check(hub.visible and not chart.content_clip.visible, "completed chart returns to destination hub")
	hub.back_button.pressed.emit()
	_check(not chart.is_open() and not game.completed and not paused and game.observation_phase_active, "hub return goes to observation, not a legacy catalogue action")
	chart.open_tree()
	await process_frame
	await process_frame
	game.upgrade_tree.andromeda_button.pressed.emit()
	var stage = game.andromeda
	stage.set_process(false)
	_check(stage.is_open() and paused and not game.hud.visible and not game.upgrade_tree.is_open(), "entry suspends atmospheric scene and owns its own sky")
	var chart_key := InputEventAction.new()
	chart_key.action = &"nw_chart"
	chart_key.pressed = true
	game.input_router._unhandled_input(chart_key)
	_check(stage.modules_open and not game.upgrade_tree.is_open(), "research action routes to modules inside Andromeda")
	game.input_router._unhandled_input(chart_key)
	_check(not stage.modules_open, "research action returns to stage observation")
	var inherited_radius: float = game.progression.get_tracking_radius()
	_check(is_equal_approx(stage.tracking_radius(), inherited_radius), "existing lens radius is retained")
	var old_remaining: float = game.observation_phase_remaining
	var old_balance: float = game.progression.observation_data
	var old_round_data: float = game.progression.total_data_earned - game.phase_start_total_data
	stage.advance_observation(10.0, stage.targets[3].position * stage.ui.size, true, false)
	_check(stage.records.cluster == 1 and game.progression.observation_data > old_balance, "unmodded observation earns data")
	_check(is_equal_approx(game.progression.observation_data - old_balance, 65536000.0), "existing cumulative x8192 research applies once to 8000-base cluster data")
	_check(is_equal_approx(game.observation_phase_remaining, old_remaining), "Andromeda never consumes suspended atmospheric time")
	_check(is_equal_approx(game.progression.total_data_earned - game.phase_start_total_data, old_round_data), "stage income does not contaminate atmospheric round accounting")
	_check(not stage.purchase_module("focus"), "purchase is blocked outside module screen")
	stage.toggle_modules()
	game.progression.observation_data = 119999999.0
	_check(not stage.purchase_module("focus"), "insufficient funds cannot purchase")
	game.progression.add_debug_data(1.0)
	_check(stage.purchase_module("focus"), "first module purchased with ordinary data")
	_check(is_zero_approx(game.progression.observation_data) and stage.modules.equipped == "focus", "exact debit and first-purchase automatic equip")
	_check(not stage.purchase_module("focus") and not stage.equip_module("wide"), "duplicate charge and unowned equip rejected")
	game.progression.add_debug_data(120000000.0)
	# Exercise the other row's actual button callback, not just the model helper.
	stage.module_rows.wide.action.pressed.emit()
	_check("wide" in stage.modules.purchased and is_zero_approx(game.progression.observation_data), "wide row buys its own module")
	_check(stage.modules.equipped == "focus", "buying another module does not replace selected equipment")
	var balance_before_equip: float = game.progression.observation_data
	stage.module_rows.wide.action.pressed.emit()
	_check(stage.modules.equipped == "wide" and game.progression.observation_data == balance_before_equip, "owned module button freely changes the single slot")
	stage.equip_module("")
	stage.toggle_modules()
	stage._make_targets()
	stage.round_remaining = 60.0
	stage.advance_observation(1.0, stage.targets[3].position * stage.ui.size, true, false)
	var base_progress: float = stage.targets[3].progress
	stage.toggle_modules()
	stage.equip_module("focus")
	stage.toggle_modules()
	stage._make_targets()
	stage.advance_observation(1.0, stage.targets[3].position * stage.ui.size, true, false)
	_check(is_equal_approx(stage.targets[3].progress / base_progress, 1.8), "focus changes real observation speed by 1.8x")
	stage.toggle_modules()
	stage.equip_module("wide")
	stage.toggle_modules()
	stage._make_targets()
	stage.advance_observation(1.0, Vector2(0.28, 0.42) * stage.ui.size, true, false)
	_check(stage.tracked_indices.size() == 3 and stage.targets[0].progress > 0 and stage.targets[1].progress > 0 and stage.targets[2].progress > 0, "wide really observes three nearby stellar targets")
	_check(is_equal_approx(stage.tracking_radius(), inherited_radius * 1.65), "wide applies radius expansion on existing lens")
	stage._make_targets()
	stage.advance_observation(1.0, stage.targets[3].position * stage.ui.size, true, false)
	_check(is_equal_approx(stage.targets[3].progress / base_progress, 0.75), "wide's per-target speed tradeoff is real")
	stage._make_targets()
	stage.advance_observation(1.0, Vector2.ZERO, false, true)
	_check(stage.targets[0].progress > 0.0 and is_zero_approx(stage.targets[3].progress), "inherited dishes support basic stars without automating the cluster")
	var before_pause: float = stage.active_seconds
	stage.toggle_modules()
	stage.advance_observation(3.0, Vector2.ZERO, false)
	_check(is_equal_approx(stage.active_seconds, before_pause), "module screen pauses observations")
	stage.toggle_modules()
	stage.open_settings()
	_check(game.hud.tutorial_replay_button.disabled, "atmospheric tutorial cannot be replayed over the stage")
	stage.advance_observation(3.0, Vector2.ZERO, false)
	_check(is_equal_approx(stage.active_seconds, before_pause) and game.hud.visible and stage.layer < game.hud.layer, "settings pause and draw above the stage")
	game.hud.close_settings()
	stage._process(0.0)
	_check(not game.hud.visible and stage.layer > game.hud.layer, "closing settings restores stage display")
	stage.round_remaining = 0.1
	stage.advance_observation(1.0, Vector2.ZERO, false, false)
	_check(stage.modules_open and is_zero_approx(stage.round_remaining), "round boundary opens module preparation")
	var old_round: int = stage.round_number
	stage.continue_button.pressed.emit()
	_check(stage.round_number == old_round + 1 and stage.round_remaining == game.progression.get_observation_duration(), "next observation uses accumulated duration research")
	stage.targets[3].progress = 0.37
	stage.round_remaining = 22.0
	var snapshot: Dictionary = game._build_save_data()
	game._apply_save_data(snapshot)
	await process_frame
	await process_frame
	stage.set_process(false)
	_check(stage.is_open() and stage.modules.purchased.size() == 2 and stage.modules.equipped == "wide", "save/load restores stage and permanent module ownership")
	_check(absf(stage.targets[3].progress - 0.37) < 0.01 and absf(stage.round_remaining - 22.0) < 0.2, "save/load restores partial observation and round time")
	stage.toggle_modules()
	stage.back_button.pressed.emit()
	_check(not stage.is_open() and game.upgrade_tree.is_open() and game.hud.visible and game.upgrade_tree.galaxy_hub.visible, "stage returns to destination selection with correct UI and pause ownership")
	var malformed = Modules.new()
	malformed.load_save_data({"purchased": ["focus", "focus", "unknown", 7], "equipped": "wide"})
	_check(malformed.purchased == ["focus"] and malformed.equipped.is_empty(), "module save sanitizes unknown/duplicate/unowned fields")
	snapshot.erase("andromeda")
	game._apply_save_data(snapshot)
	await process_frame
	_check(stage.modules.purchased.is_empty() and not stage.is_open(), "old save loads without granting modules or opening stage")
	game._enter_andromeda()
	stage.set_process(false)
	game.progression.observation_data = 0.0
	stage.round_remaining = 60.0
	var purchase_seconds := 0.0
	while game.progression.observation_data < 120000000.0 and purchase_seconds < 60.0:
		var index := -1
		for candidate in [3, 0, 1, 2, 4, 5, 6]:
			if stage.targets[candidate].cooldown <= 0.0:
				index = candidate
				break
		var pointer: Vector2 = stage.targets[index].position * stage.ui.size if index >= 0 else Vector2.ZERO
		stage.advance_observation(0.1, pointer, index >= 0)
		purchase_seconds += 0.1
	_check(game.progression.observation_data >= 120000000.0, "a zero-bank unmodded arrival can earn the first module within one full observation")
	if not stage.modules_open:
		stage.toggle_modules()
	_check(stage.purchase_module("focus"), "first module is purchasable from actual stage earnings")
	print("ANDROMEDA_FIRST_PURCHASE_SECONDS: ", snappedf(purchase_seconds, 0.1), " (scripted continuous observation, not human playtime)")
	game.reset_run()
	_check(stage.modules.purchased.is_empty() and stage.records.cluster == 0, "reset clears stage progress")
	game.free()
	paused = false
	if failures.is_empty():
		print("ANDROMEDA_STAGE_PASS: entry, purchase, slot, real module effects, inherited equipment, round boundaries, settings and save/load")
		quit(0)
	else:
		print("ANDROMEDA_STAGE_FAIL: ", failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ANDROMEDA_STAGE: " + message)
