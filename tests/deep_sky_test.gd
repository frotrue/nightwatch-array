extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Meteor = preload("res://scripts/meteor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_module_effect_cache()
	create_timer(35.0, true, false, true).timeout.connect(func(): push_error("Deep sky watchdog"); quit(1))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	var research = game.deep_sky
	var target = research.target
	target.set_process(false)
	_check(not research.available() and not target.can_be_tracked(), "M31 is gated by the existing galaxy research")
	var made_progress := true
	while made_progress:
		made_progress = false
		for definition in Balance.UPGRADE_NODES:
			if definition.branch != "local_group" and not game.progression.has_upgrade(definition.id):
				if game.progression.debug_purchase_node(definition.id):
					made_progress = true
	_check(game.progression.upgrade_level == 95 and research.available(), "the original 95-node path unlocks M31 without legacy local-group research")
	target._process(0)
	_check(game.hud.visible and game.observer.visible and game.observation_phase_active and not game.has_method("_enter_andromeda"), "the ordinary sky and observer remain active; there is no stage entry")
	var tree = game.upgrade_tree
	game.galactic_pullback_seen = true
	tree.configure_galactic_state(true, true)
	tree.open_tree()
	await process_frame
	await process_frame
	var chart = tree.deep_sky_chart
	var forwarded := [0]
	research.changed.connect(func(): forwarded[0] += 1)
	game.progression.add_debug_data(17.0)
	await process_frame
	await process_frame
	_check(forwarded[0] == 0, "ordinary income does not broadcast duplicate module-state changes")
	_check(chart.balance.text.begins_with(game.UITheme.grouped_integer(int(game.progression.observation_data))), "visible research still updates its balance through progression changes")
	_check(chart.visible and chart.nodes.keys() == ["m31", "modules", "focus", "wide"], "one compact continuation replaces the destination hub")
	chart.select("focus")
	game.progression.observation_data = 240000000.0
	chart.buy_button.pressed.emit()
	_check(research.modules.purchased.is_empty(), "module purchases require an actual first observation")
	for definition in Balance.UPGRADE_NODES:
		if definition.branch == "local_group":
			_check(not tree._node_interaction_ready(definition.id), "retired research stays non-interactive")
	chart.chart_button.pressed.emit()
	_check(not chart.visible and tree.content_clip.visible, "the miniature restores the real completed constellation chart")
	tree.hub_return_button.pressed.emit()
	_check(chart.visible, "the same chart returns to its expanded continuation")
	chart.back_button.pressed.emit()
	_check(not paused and not tree.is_open() and game.observation_phase_active, "chart returns to the ordinary ongoing round")
	var before_total: float = game.progression.total_data_earned
	var before_round: int = game.observation_round
	var before_clock: float = game.observation_phase_remaining
	game.observer.previous_cursor_position = target.global_position
	game.observer.cursor_position = target.global_position
	game.observer.selected_meteor = target
	game.observer._update_manual_tracking(10.0)
	_check(research.observations == 1 and research.modules_unlocked(), "the existing observer records M31 and unlocks modules")
	_check(game.progression.total_data_earned > before_total and game._build_round_result().data > 0, "M31 income belongs to the ordinary round summary")
	_check(game.observation_round == before_round and game.observation_phase_remaining == before_clock, "recording does not replace or restart the round clock")
	tree.open_tree()
	await process_frame
	await process_frame
	game.progression.observation_data = 119999999.0
	_check(not research.purchase("focus"), "insufficient balance is rejected")
	game.progression.observation_data = 240000000.0
	chart.select("focus")
	chart.buy_button.pressed.emit()
	_check(research.modules.purchased == ["focus"] and research.modules.installed_ids().is_empty() and game.progression.observation_data == 120000000.0, "chart purchase debits once and adds to inventory without equipping")
	_check(not research.purchase("focus"), "duplicate purchases never charge twice")
	chart.select("wide")
	chart.buy_button.pressed.emit()
	var popup = game.module_popup
	popup.launcher.pressed.emit()
	_check(popup.is_open() and tree.is_open() and paused, "equipment popup overlays the chart while retaining its pause")
	_check(popup.layer > tree.layer, "the visible popup and its hit testing are above the research canvas")
	_check(not research.purchase("focus"), "purchase path is blocked while the popup owns input")
	popup.select_module("focus")
	popup.equip_button.pressed.emit()
	popup.select_slot(1)
	popup.select_module("wide")
	popup.equip_button.pressed.emit()
	_check(research.modules.installed_ids() == ["focus", "wide"], "both owned modules can be equipped through real popup controls")
	_check(not research.equip("focus", 1), "duplicate slot rejected")
	var escape := InputEventAction.new()
	escape.action = &"nw_menu_back"
	escape.pressed = true
	tree._input(escape)
	_check(tree.is_open(), "underlying chart does not consume popup Escape")
	popup._input(escape)
	_check(not popup.is_open() and tree.is_open() and paused, "Escape closes only the popup and keeps the chart paused")
	chart.back_button.pressed.emit()
	popup.open()
	_check(not popup.is_open() and not popup.launcher.is_visible_in_tree(), "equipment popup cannot open outside research")
	tree.open_tree()
	await process_frame
	popup.launcher.pressed.emit()
	_check(popup.is_open() and paused, "research launcher opens the equipment popup")
	tree.close_tree()
	_check(not popup.is_open() and not paused and game.observation_phase_active, "closing research also dismisses its popup and restores observation")
	# Compare actual meteor progress through the original observer, including the
	# below-1 wide-field multiplier which target scripts previously clamped away.
	var meteor := Meteor.new()
	meteor.configure(Balance.meteor_spec("common"), "common", Vector2(400, 240), Vector2.ZERO, 1.0, {})
	game.meteor_layer.add_child(meteor)
	meteor.set_process(false)
	game.observer.previous_cursor_position = meteor.global_position
	game.observer.cursor_position = meteor.global_position
	var baseline := 0.0
	for ids in [["", ""], ["focus", ""], ["", "wide"], ["focus", "wide"]]:
		tree.open_tree()
		popup.open()
		research.equip("", 0)
		research.equip("", 1)
		research.equip(ids[0], 0)
		research.equip(ids[1], 1)
		popup.close()
		tree.close_tree()
		meteor.observation_progress = 0
		game.observer._apply_manual_contact(meteor, 0.1)
		if ids == ["", ""]:
			baseline = meteor.observation_progress
		else:
			var expected := 1.35 if ids == ["focus", "wide"] else (1.8 if ids[0] == "focus" else 0.75)
			_check(is_equal_approx(meteor.observation_progress / baseline, expected), "module multiplier applies to ordinary live meteors: " + str(ids))
	_check(is_equal_approx(game.observer._module_tracking_radius(), game.progression.get_tracking_radius() * 1.65), "wide expands the real cursor radius")
	_check(game.progression.has_upgrade("multi_target_analysis"), "existing multi-target research is retained")
	target.progress = 0.37
	target.cooldown = 2.0
	var snapshot: Dictionary = game._build_save_data()
	_check(snapshot.has("deep_sky") and not snapshot.has("andromeda"), "new saves no longer contain an active stage")
	game._apply_save_data(snapshot)
	await process_frame
	_check(research.modules.installed_ids() == ["focus", "wide"] and research.observations == 1 and is_equal_approx(target.progress, 0.37), "game save/load preserves inventory, equipment, M31 record and partial progress")
	snapshot.erase("deep_sky")
	snapshot.andromeda = {"active": true, "modules": {"purchased": ["focus"], "equipped": "focus"}}
	game._apply_save_data(snapshot)
	await process_frame
	_check(research.modules.equipped == "focus" and research.modules.secondary.is_empty() and game.hud.visible and not popup.is_open(), "legacy stage save restores equipment into the ordinary sky without re-entering a stage")
	game.reset_run()
	_check(research.modules.purchased.is_empty() and research.observations == 0 and not target.can_be_tracked(), "reset clears the extension and hides its target")
	game.free()
	paused = false
	await process_frame
	await process_frame
	await _check_live_chart_resumption()
	await _check_popup_pointer_routing()
	if failures.is_empty():
		print("DEEP_SKY_PASS: original sky, continuous chart, first record, purchase/equip split, real effects, modal input and save migration")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("DEEP_SKY: " + message)

class ReadOnlySnapshot:
	extends Fixtures.NoSaveSlots
	var snapshot: Dictionary = {}
	func load_slot(_slot: int) -> Dictionary:
		return snapshot.duplicate(true)

func _frames(count: int) -> void:
	for index in range(count):
		await process_frame

func _chart_key() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_U
		event.pressed = pressed
		root.push_input(event)

func _check_live_chart_resumption() -> void:
	var live: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(live)
	var slots := ReadOnlySnapshot.new()
	Fixtures.replace_child(live, "SaveGameController", slots)
	root.add_child(live)
	await _frames(3)
	slots.snapshot = live._build_save_data()
	live._end_observation_phase()
	live.hud.open_settings()
	live._on_load_slot_requested(1)
	_check(not paused and live.observation_phase_active, "loading a live save from summary settings releases the obsolete summary pause")
	var clock_before: float = live.observation_phase_remaining
	await _frames(15)
	_check(live.observation_phase_remaining < clock_before, "loaded round clock actually advances across engine frames")
	# Repair a stale pause when the chart was opened after an earlier faulty load.
	paused = true
	_chart_key()
	await _frames(3)
	_check(live.upgrade_tree.is_open() and not live.upgrade_tree.paused_by_tree, "reproduction opens research over an obsolete pre-existing pause")
	_chart_key()
	await _frames(3)
	clock_before = live.observation_phase_remaining
	await _frames(15)
	_check(not live.upgrade_tree.is_open() and not paused and live.observation_phase_remaining < clock_before, "real U close recovers the stale pause and advances the round")
	live._end_observation_phase()
	var old_round: int = live.observation_round
	_chart_key()
	await _frames(3)
	_chart_key()
	await _frames(10)
	_check(not paused and live.observation_phase_active and live.observation_round == old_round + 1, "real summary-to-research-to-observation input starts the next round")
	live.hud.open_settings()
	live._resume_observation_if_unblocked()
	_check(paused and live.hud.is_settings_open(), "pause reconciliation preserves a visible settings owner")
	live.hud.close_settings()
	live.free()
	paused = false
	await _frames(2)

func _check_popup_pointer_routing() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 648)
	root.add_child(viewport)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	viewport.add_child(game)
	await _frames(2)
	game.progression.debug_purchase_all()
	game.deep_sky.modules.load_save_data({"purchased": ["focus"]})
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await _frames(3)
	game.module_popup.refresh()
	var launcher: Button = game.module_popup.launcher
	_click_in_viewport(viewport, launcher.get_global_rect().get_center())
	await _frames(2)
	_check(game.module_popup.is_open(), "real pointer click on research launcher opens the popup")
	_click_in_viewport(viewport, game.module_popup.equip_button.get_global_rect().get_center())
	_check(game.deep_sky.modules.equipped == "focus", "visible popup receives equip clicks above the research canvas")
	_click_in_viewport(viewport, game.module_popup.close_button.get_global_rect().get_center())
	_check(not game.module_popup.is_open() and game.upgrade_tree.is_open() and paused, "visible popup close click returns to research without passing through")
	_click_in_viewport(viewport, game.upgrade_tree.deep_sky_chart.back_button.get_global_rect().get_center())
	var before: float = game.observation_phase_remaining
	await _frames(10)
	_check(not paused and game.observation_phase_remaining < before, "real research return click resumes the round after popup use")
	await _frames(40)
	viewport.free()
	paused = false
	await _frames(2)

func _click_in_viewport(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)

func _check_module_effect_cache() -> void:
	var model = load("res://scripts/observation_modules.gd").new()
	model.load_save_data({"purchased": ["focus", "wide"], "slots": ["focus", "wide"]})
	_check(is_equal_approx(model.effect("speed"), 1.35) and model.effect("targets") == 3, "combined cached effects match the existing contract")
	for index in range(20):
		_check(is_equal_approx(model.effect("radius"), 1.65), "repeated cached reads remain stable")
	model.secondary = ""
	_check(is_equal_approx(model.effect("speed"), 1.8) and model.effect("targets") == 1, "direct slot change invalidates cached effects")
	model.purchased.clear()
	_check(is_equal_approx(model.effect("speed"), 1.0), "direct ownership removal invalidates cached effects")
	model.purchased.append("focus")
	_check(is_equal_approx(model.effect("speed"), 1.8), "ownership restoration is reflected without an equip call")
	model.secondary = "focus"
	_check(is_equal_approx(model.effect("speed"), 1.8), "duplicate direct slots do not stack cached effects")
	model.load_save_data({"purchased": ["wide"], "equipped": "wide"})
	_check(is_equal_approx(model.effect("speed"), 0.75) and model.effect("missing") == null, "legacy load invalidates cache and unknown effect lookup remains null")
