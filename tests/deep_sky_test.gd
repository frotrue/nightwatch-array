extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
const Modules = preload("res://scripts/observation_modules.gd")
const Meteor = preload("res://scripts/meteor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_module_effect_cache()
	_check_slot_saves()
	create_timer(35.0, true, false, true).timeout.connect(func(): push_error("Deep sky watchdog"); quit(1))
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	var research = game.deep_sky
	var made_progress := true
	while made_progress:
		made_progress = false
		for definition in Balance.UPGRADE_NODES:
			if not game.progression.has_upgrade(definition.id):
				if game.progression.debug_purchase_node(definition.id):
					made_progress = true
	_check(game.progression.upgrade_level == 95 and research.available(), "the original 95-node path unlocks follow-up research directly")
	_check(game.hud.visible and game.observer.visible and game.observation_phase_active and not game.has_method("_enter_andromeda"), "the ordinary sky and observer remain active; there is no stage entry")
	var tree = game.upgrade_tree
	game.galactic_pullback_seen = true
	tree.configure_galactic_state(true, true)
	tree.open_tree()
	await process_frame
	await process_frame
	var chart = tree
	var forwarded := [0]
	research.changed.connect(func(): forwarded[0] += 1)
	game.progression.add_debug_data(17.0)
	await process_frame
	await process_frame
	_check(forwarded[0] == 0, "ordinary income does not broadcast duplicate module-state changes")
	_check(tree.node_buttons.has("ext_protocol") and tree.node_buttons.has("ext_record_complete"), "the original constellation canvas contains the continuation research stars")
	chart.select_extension("focus")
	game.progression.observation_data = 240000000.0
	_hold_chart_star(game)
	for definition in Balance.UPGRADE_NODES:
		if definition.branch == "local_group":
			_check(false, "retired research cannot be in the catalogue")
	tree.close_tree()
	_check(not paused and not tree.is_open() and game.observation_phase_active, "chart returns to the ordinary ongoing round")
	tree.open_tree()
	await process_frame
	await process_frame
	game.progression.observation_data = 60000000.0
	_check(research.purchase("ext_trace_study"), "permanent tracking research is available after coordinate research")
	game.progression.observation_data = 119999999.0
	_check(not research.purchase("focus"), "insufficient balance is rejected")
	game.progression.observation_data = 240000000.0
	chart.select_extension("focus")
	_hold_chart_star(game)
	_check(research.research_owned("focus") and research.modules.purchased.is_empty() and game.progression.observation_data == 120000000.0, "chart purchase debits once and installs permanent research without granting equipment")
	_check(not research.purchase("focus"), "duplicate purchases never charge twice")
	game.progression.observation_data = 240000000.0
	_check(research.purchase("ext_sweep_study"), "sweep predecessor purchased")
	chart.select_extension("wide")
	_hold_chart_star(game)
	# Inventory fixtures isolate the established equipment and pointer contract.
	research.modules.grant("focus")
	research.modules.grant("wide")
	var popup = game.module_popup
	popup.launcher.pressed.emit()
	_check(popup.is_open() and tree.is_open() and paused, "equipment popup overlays the chart while retaining its pause")
	_check(not tree.visible, "popup hides chart rendering while retaining its logical open state")
	_check(popup.layer > tree.layer, "the visible popup and its hit testing are above the research canvas")
	_check(not research.purchase("focus"), "purchase path is blocked while the popup owns input")
	popup.owned_buttons.focus.pressed.emit()
	popup.owned_buttons.wide.pressed.emit()
	_check(research.modules.installed_ids() == ["focus", "wide"], "both owned modules can be equipped through real popup controls")
	_check(not research.equip("focus", 1), "duplicate slot rejected")
	var escape := InputEventAction.new()
	escape.action = &"nw_menu_back"
	escape.pressed = true
	tree._input(escape)
	_check(tree.is_open(), "underlying chart does not consume popup Escape")
	popup._input(escape)
	_check(not popup.is_open() and tree.is_open() and paused, "Escape closes only the popup and keeps the chart paused")
	_check(tree.visible, "closing popup restores the same chart canvas")
	game.upgrade_tree.close_tree()
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
		game.observer.cursor_position = meteor.global_position
		game.observer.previous_cursor_position = meteor.global_position
		meteor.observation_progress = 0
		game.observer._apply_manual_contact(meteor, 0.1)
		if ids == ["", ""]:
			baseline = meteor.observation_progress
		else:
			var expected := 0.75 if "wide" in ids else 1.0
			_check(is_equal_approx(meteor.observation_progress / baseline, expected), "module multiplier applies to ordinary live meteors: " + str(ids))
	_check(is_equal_approx(game.observer._module_tracking_radius(), game.progression.get_tracking_radius() * 1.65), "wide expands the real cursor radius")
	_check(game.progression.has_upgrade("multi_target_analysis"), "existing multi-target research is retained")
	var snapshot: Dictionary = game._build_save_data()
	_check(snapshot.has("deep_sky") and not snapshot.has("andromeda"), "new saves no longer contain an active stage")
	game._apply_save_data(snapshot)
	await process_frame
	snapshot.erase("deep_sky")
	snapshot.andromeda = {"active": true, "modules": {"purchased": ["focus"], "equipped": "focus"}}
	game._apply_save_data(snapshot)
	await process_frame
	_check(research.modules.slots == ["focus", "", "", "", ""] and research.modules.unlocked_slots == 2 and game.hud.visible and not popup.is_open(), "legacy stage save restores equipment into the ordinary sky without re-entering a stage")
	await _check_ring_research(game)
	game.reset_run()
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
	_click_in_viewport(viewport, game.module_popup.owned_buttons.focus.get_global_rect().get_center())
	_check(game.deep_sky.modules.slots[0] == "focus", "visible popup receives equip clicks above the research canvas")
	_click_in_viewport(viewport, game.module_popup.slots[2].get_global_rect().get_center())
	_check(game.module_popup.tooltip_panel.visible and game.module_popup.tooltip_action.text == tr("RING_LOCKED_ACTION"), "real pointer reaches locked-slot hover without equipping")
	_check(game.deep_sky.modules.installed_ids() == ["focus"], "locked slot click leaves equipment intact")
	_click_in_viewport(viewport, game.module_popup.slots[0].get_global_rect().get_center())
	_check(game.deep_sky.modules.installed_ids().is_empty(), "real ring click removes the mounted module")
	_click_in_viewport(viewport, game.module_popup.owned_buttons.focus.get_global_rect().get_center())
	_check(game.deep_sky.modules.slots[0] == "focus", "removed module stays in inventory and refills the first clockwise gap")
	_click_in_viewport(viewport, game.module_popup.close_button.get_global_rect().get_center())
	_check(not game.module_popup.is_open() and game.upgrade_tree.is_open() and paused, "visible popup close click returns to research without passing through")
	game.deep_sky._sync_protocol()
	game.deep_sky.state.award_samples(8)
	game.module_popup.refresh()
	_click_in_viewport(viewport, game.module_popup.draw_launcher.get_global_rect().get_center())
	await _frames(2)
	_check(game.module_popup.is_draw_open(), "real pointer opens the dedicated draw window directly from the chart")
	var draw_window: Control = game.module_popup.draw_window
	_check(draw_window.acquisition_hint.visible and not draw_window.result_kind.visible and not draw_window.result_quantity.visible, "empty draw shows one acquisition hint without result metadata")
	_click_in_viewport(viewport, draw_window.action.get_global_rect().get_center())
	_check(draw_window.drawing and game.deep_sky.samples == 0, "real draw click begins one paid animation")
	game.hud.autosave_failed = true
	draw_window.refresh()
	draw_window._process(0.05)
	_check(draw_window.status.visible and draw_window.status.text == tr("AUTOSAVE_FAILURE") % game.active_save_slot, "animation cannot overwrite a save failure")
	game.hud.autosave_failed = false
	draw_window._process(0.0)
	_check(draw_window.status.text == tr("DRAW_SCAN"), "save recovery restores the current animation status")
	game.hud.autosave_failed = true
	_click_in_viewport(viewport, draw_window.skip_button.get_global_rect().get_center())
	_check(not draw_window.drawing and draw_window.result_panel.visible, "real pointer skips to the saved result")
	_check(draw_window.status.visible and draw_window.status.text == tr("AUTOSAVE_FAILURE") % game.active_save_slot, "skipping preserves an unresolved save failure")
	game.hud.autosave_failed = false
	draw_window._process(0.0)
	_check(not draw_window.status.visible and not draw_window.acquisition_hint.visible, "resolved result has no repeated acquisition or status instruction")
	_click_in_viewport(viewport, draw_window.loadout_button.get_global_rect().get_center())
	_check(game.module_popup.is_open() and not game.module_popup.is_draw_open(), "real loadout click changes surfaces without resuming the sky")
	_click_in_viewport(viewport, game.module_popup.close_button.get_global_rect().get_center())
	_click_in_viewport(viewport, game.upgrade_tree.close_button.get_global_rect().get_center())
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
	_check(is_equal_approx(model.effect("speed"), 0.75) and model.effect("targets") == 3, "combined cached effects match the existing contract")
	for index in range(20):
		_check(is_equal_approx(model.effect("radius"), 1.65), "repeated cached reads remain stable")
	model.slots[1] = ""
	_check(is_equal_approx(model.effect("split_chance"), 0.3) and model.effect("targets") == 1, "direct slot change invalidates cached effects")
	model.purchased.clear()
	_check(is_equal_approx(model.effect("split_chance"), 0.0), "direct ownership removal invalidates cached effects")
	model.purchased.append("focus")
	_check(is_equal_approx(model.effect("split_chance"), 0.3), "ownership restoration is reflected without an equip call")
	model.slots[1] = "focus"
	_check(is_equal_approx(model.effect("split_chance"), 0.3), "duplicate direct slots do not stack cached effects")
	model.load_save_data({"purchased": ["wide"], "equipped": "wide"})
	_check(is_equal_approx(model.effect("speed"), 0.75) and model.effect("missing") == null, "legacy load invalidates cache and unknown effect lookup remains null")

func _check_slot_saves() -> void:
	var model = Modules.new()
	for old in [
		{"purchased": ["focus", "wide"], "equipped": "focus", "secondary": "wide"},
		{"purchased": ["focus", "wide"], "slots": ["focus", "wide"]},
	]:
		model.load_save_data(old)
		_check(model.slots == ["focus", "wide", "", "", ""] and model.unlocked_slots == 2, "both legacy save formats restore the first two of five positions")
		_check(not model.equip("focus", 2) and not model.equip("", 4), "locked model positions reject equip and clear")
	model.load_save_data({"purchased": Modules.DEFINITIONS.keys(), "slots": ["focus", "wide", "precision", "linear_observation", "sweep_optics"], "unlocked_slots": 5})
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(model.get_save_data()))
	model.load_save_data(encoded)
	_check(model.unlocked_slots == 5 and model.slots == ["focus", "wide", "precision", "linear_observation", "sweep_optics"], "five positions and researched capacity survive real JSON serialization")
	_check(is_equal_approx(model.effect("speed"), 1.125) and is_equal_approx(model.effect("radius"), 1.155), "all five effects compose without losing original multipliers")
	model.unlocked_slots = 2
	_check(is_equal_approx(model.effect("speed"), 0.75), "capacity changes invalidate cache and exclude locked equipment")
	model.load_save_data({"purchased": ["focus", "focus", "wide", "bad", 7], "slots": ["focus", "focus", "wide", "record", "bad", "wide"], "unlocked_slots": 5})
	_check(model.purchased == ["focus", "wide"] and model.slots == ["focus", "", "wide", "", ""], "load sanitizes duplicate, unowned, unknown and extra positions")
	for invalid in ["5", null, 3.5, NAN]:
		model.load_save_data({"purchased": ["focus", "wide", "record"], "slots": ["focus", "wide", "record"], "unlocked_slots": invalid})
		_check(model.unlocked_slots == 2 and model.slots[2].is_empty(), "invalid capacity does not activate locked save contents")

func _check_ring_research(game: Node) -> void:
	var research = game.deep_sky
	var popup = game.module_popup
	var chart = game.upgrade_tree
	research.reset()
	research.observations = 1
	research._sync_protocol()
	game.progression.observation_data = 5000000000.0
	game.upgrade_tree.open_tree()
	await _frames(2)
	popup.open()
	_check(popup.draw_button.text == tr("DRAW_OPEN"), "empty inventory links to the dedicated draw window")
	popup.close()
	_check(research.research_ready("slot_3") and not research.purchase("slot_4") and not research.purchase("slot_5"), "module capacity is a sequential permanent research branch")
	# Acquisition is tested by the draw integration gate. These known five
	# copies let this gate isolate equip, slot holds, JSON and legacy effects.
	for id in ["focus", "wide", "precision", "linear_observation", "sweep_optics"]:
		research.modules.grant(id)
	popup.open()
	popup.owned_buttons.focus.pressed.emit()
	popup.owned_buttons.wide.pressed.emit()
	popup.show_module_tooltip("precision")
	_check(popup.tooltip_action.text == tr("RING_FULL_ACTION"), "full inventory tooltip explains why the click cannot equip")
	popup.owned_buttons.precision.pressed.emit()
	popup.owned_buttons.focus.pressed.emit()
	_check(research.modules.slots == ["focus", "wide", "", "", ""], "full and already-mounted tile clicks never replace equipment")
	_check(not research.equip("linear_observation", 2) and not research.purchase("slot_3"), "popup cannot equip a locked position or purchase chart research")
	popup.show_module_tooltip("focus")
	_check(popup.tooltip_action.text == tr("RING_EQUIPPED_ACTION"), "mounted inventory tile explains its no-op")
	popup.slots[0].pressed.emit()
	popup.owned_buttons.precision.pressed.emit()
	_check(research.modules.slots == ["precision", "wide", "", "", ""], "removal leaves a gap that the next inventory click fills")
	popup.set_process(false)
	for locale in ["ko", "en"]:
		game.settings.set_language(locale, false)
		popup.show_module_tooltip("linear_observation")
		await _frames(3)
		popup.tooltip_pointer = popup.overlay.size - Vector2.ONE
		popup._place_tooltip()
		_check(absf(popup.tooltip_panel.size.x - 240.0) <= 1.0 and Rect2(Vector2.ZERO, popup.overlay.size).encloses(popup.tooltip_panel.get_rect()), "tooltip remains within viewport: " + locale)
	popup.close()
	for id in ["slot_3", "slot_4", "slot_5"]:
		chart.select_extension(id)
		var before: float = game.progression.observation_data
		_hold_chart_star(game)
		_check(research.research_owned(id) and is_equal_approx(before - game.progression.observation_data, research.research_cost(id)), "held star unlocks and charges for capacity: " + id)
		_check(not research.purchase(id) and game.progression.observation_data == before - research.research_cost(id), "duplicate slot purchase cannot charge again: " + id)
	_check(research.modules.unlocked_slots == 5 and research.modules.purchased.size() == 5, "slot research leaves the equipment fixture intact")
	popup.open()
	for index in range(5):
		popup.remove_module(index)
	for id in Modules.DEFINITIONS:
		popup.owned_buttons[id].pressed.emit()
	_check(research.modules.slots == ["focus", "wide", "precision", "sweep_optics", "linear_observation"], "five unlocked positions fill clockwise through popup controls")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	popup.close()
	game.upgrade_tree.close_tree()
	game._apply_save_data(snapshot)
	await _frames(2)
	_check(research.modules.unlocked_slots == 5 and research.modules.installed_ids().size() == 5 and not paused, "full game JSON restores researched capacity and observation")
	_check(not research.research_owned("linear_observation") and not research.research_owned("sweep_optics"), "new inventory ownership does not grant permanent research on load")
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)

func _hold_chart_star(game: Node) -> void:
	var tree: Node = game.upgrade_tree
	tree._on_node_hold_started(tree.selected_node_id)
	tree._process(tree.HOLD_PURCHASE_SECONDS)
	tree._on_node_hold_released(tree.selected_node_id)
