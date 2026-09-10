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
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await process_frame
	await process_frame
	game.set_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	game.progression.debug_purchase_all()
	game.deep_sky.observations = 1
	game.deep_sky.modules.load_save_data({"purchased": ["focus"], "slots": ["focus"], "unlocked_slots": 2})
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	await process_frame
	await process_frame

	var popup = game.module_popup
	_check(Modules.DEFINITIONS.size() == 10, "expanded definitions expose all ten modules")
	popup.launcher.grab_focus()
	popup.open()
	await process_frame
	_check(popup.owned_buttons.size() == Modules.DEFINITIONS.size(), "owned_buttons keeps one stable tile per definition")
	for id in Modules.DEFINITIONS:
		_check(popup.owned_buttons.has(id), "catalog retains stable tile id: " + id)

	var before: Array[String] = game.deep_sky.modules.installed_ids()
	var locked_id := "trail_integrator"
	popup.owned_buttons[locked_id].pressed.emit()
	_check(game.deep_sky.modules.installed_ids() == before, "unowned catalog tiles never equip")
	popup.show_module_tooltip(locked_id)
	_check(not popup.tooltip_panel.visible, "unowned module exposes no tooltip")

	for filter_id in popup.INVENTORY_FILTERS:
		popup.set_inventory_filter(filter_id)
		for id in Modules.DEFINITIONS:
			if id != "focus":
				_check(not popup.owned_buttons[id].visible and popup.owned_buttons[id].focus_mode == Control.FOCUS_NONE, "unowned module is hidden and unfocusable in " + filter_id + ": " + id)
		_check(popup.owned_buttons.focus.visible == (filter_id in ["all", "trace"]), "owned module respects category filter: " + filter_id)
		_check(popup.inventory_empty.visible == (filter_id in ["sweep", "link"]), "empty category explains missing owned modules: " + filter_id)
	popup.set_inventory_filter("all")
	_check(popup.owned_buttons.focus.visible and popup.owned_buttons.focus.installed, "installed module remains in storage")
	_check(not popup.owned_buttons.focus.equip_available and not popup.owned_buttons.focus.disabled, "installed-only module remains inspectable without an equip affordance")
	game.deep_sky.modules.grant_copy("focus")
	popup.refresh(false)
	_check(popup.owned_buttons.focus.equip_available, "spare module with a free slot offers equipping")
	_check(game.deep_sky.modules.owned_count("focus") == 2 and popup.inventory_count.text == tr("MODX_COUNT") % 1, "duplicates keep one type and their owned quantity")
	popup.show_module_tooltip("focus")
	_check(popup.tooltip_panel.visible, "owned module exposes its tooltip")
	game.deep_sky.equip("focus")
	game.deep_sky.modules.grant_copy("focus")
	popup.refresh(false)
	_check(game.deep_sky.modules.spare_count("focus") > 0 and not popup.owned_buttons.focus.equip_available, "full loadout removes equip affordance even with a spare copy")
	popup.owned_buttons.focus.grab_focus()
	await process_frame
	_check(popup.tooltip_panel.visible and popup.owned_buttons.focus.has_focus(), "full loadout preserves keyboard inspection")
	popup.set_inventory_filter("sweep")
	_check(not popup.tooltip_panel.visible, "filtering out hovered module dismisses its tooltip")
	popup.set_inventory_filter("all")
	popup.owned_buttons.focus.grab_focus()
	game.deep_sky.modules.load_save_data({})
	popup.refresh(false)
	_check(popup.inventory_empty.visible and popup.inventory_empty.text == tr("MODX_EMPTY"), "empty storage points to module draws")
	_check(not popup.tooltip_panel.visible and not popup.owned_buttons.focus.has_focus(), "removing ownership dismisses stale tooltip and keyboard focus")
	for tile in popup.owned_buttons.values():
		_check(not tile.visible, "empty storage has no module tiles")
	for id in Modules.DEFINITIONS:
		game.deep_sky.modules.grant_copy(id)
	popup.refresh(false)
	await process_frame
	await process_frame
	_check(not popup.inventory_empty.visible, "acquiring modules clears empty storage message")
	for tile in popup.owned_buttons.values():
		_check(tile.visible, "acquired module appears in storage")
	var scrollbar: Range = popup.inventory_scroll.get_v_scroll_bar()
	_check(scrollbar.max_value <= scrollbar.page, "all ten owned modules fit in the default storage view")
	# Retain the overflow/focus contract for constrained views or a larger catalog.
	var authored_scroll_height: float = popup.inventory_scroll.size.y
	popup.inventory_scroll.size.y = 200.0
	await process_frame
	await process_frame
	_check(scrollbar.max_value > scrollbar.page, "constrained storage remains scrollable")

	# Keyboard descriptions follow their focused item even with the pointer
	# elsewhere, including the last item brought into view by focus scrolling.
	for id in ["focus", Modules.DEFINITIONS.keys().back()]:
		var tile: Button = popup.owned_buttons[id]
		tile.grab_focus()
		await process_frame
		await process_frame
		popup._process(0.016)
		var anchor: Vector2 = popup.overlay.get_global_transform().affine_inverse() * tile.get_global_rect().get_center()
		_check(popup.tooltip_panel.visible and popup.tooltip_from_focus, "keyboard focus opens the module description")
		_check(popup.tooltip_pointer.is_equal_approx(anchor), "idle pointer cannot replace the focused module anchor")
		# Scroll offsets are integers while spec geometry retains fractional pixels.
		_check(popup.inventory_scroll.get_global_rect().grow(1.0).encloses(tile.get_global_rect()), "focused inventory item is scrolled into view: " + id)
		tile.mouse_exited.emit()
		_check(popup.tooltip_panel.visible, "pointer exit does not dismiss a keyboard description")
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(4, 0)
		tile.gui_input.emit(motion)
		popup._process(0.016)
		_check(not popup.tooltip_from_focus and popup.tooltip_pointer.is_equal_approx(popup.overlay.get_local_mouse_position()), "pointer movement takes over description placement")
		popup.close_button.grab_focus()
		_check(popup.tooltip_panel.visible, "leaving keyboard focus does not dismiss a pointer description")
		tile.mouse_exited.emit()
		_check(not popup.tooltip_panel.visible, "leaving pointer hover dismisses its description")
	popup.inventory_scroll.size.y = authored_scroll_height
	game.deep_sky.equip("focus")
	popup.slots[0].grab_focus()
	await process_frame
	popup._process(0.016)
	_check(popup.tooltip_from_focus and popup.tooltip_panel.visible, "equipped slot supports keyboard descriptions")
	_check(popup.tooltip_pointer.is_equal_approx(popup.slots[0].get_global_rect().get_center()), "slot description remains anchored to the focused slot")
	_check(Rect2(Vector2.ZERO, popup.overlay.size).encloses(popup.tooltip_panel.get_rect()), "keyboard description stays inside the viewport")

	popup.close()
	_check(not popup.is_open() and game.upgrade_tree.visible and paused, "closing the modal restores the chart pause")
	_check(game.get_viewport().gui_get_focus_owner() == popup.launcher, "closing the modal restores the previous focus")
	await _verify_information_hierarchy(game)
	game.free()

	if failures.is_empty():
		print("MODULE_INVENTORY_PASS: owned-only storage, empty states, categories, duplicates, scroll and modal focus")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("MODULE_INVENTORY: " + message)

func _activate_focused_control() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _verify_information_hierarchy(game: Node) -> void:
	var chart = game.upgrade_tree
	var popup = game.module_popup
	var hud = game.hud
	var data_before: float = game.progression.observation_data
	# Outer chart fixture: explicitly install one displayed research star.
	game.deep_sky.state.research_ids.append("ext_trace_study")
	chart.select_extension("ext_trace_study")
	_check(not chart.inspector_details.visible and not chart.tooltip_star.is_visible_in_tree(), "star reference details start collapsed")
	_check(not chart.controls_label.is_visible_in_tree() and chart.inspector_details.is_ancestor_of(chart.constellation_horizon_hint), "chart guidance belongs in collapsed contextual help")
	_check(chart.tooltip_state.visible and not chart.tooltip_action.visible and not chart.tooltip_cost.visible, "installed research states completion once without a live purchase cost: %s / %s / %s / %s" % [chart.tooltip_state.text, chart.tooltip_state.visible, chart.tooltip_action.visible, chart.tooltip_cost.visible])
	chart.inspector_details_button.grab_focus()
	await _activate_focused_control()
	_check(chart.inspector_details.visible and chart.tooltip_star.is_visible_in_tree(), "keyboard opens star identity and legend without buying research")
	_check(chart.controls_label.is_visible_in_tree() and not chart.controls_label.text.is_empty(), "expanded help retains the chart controls")
	_check(game.progression.observation_data == data_before, "opening research help never spends Data")
	await _activate_focused_control()
	_check(not chart.inspector_details.visible, "keyboard closes star help")

	popup.open()
	_check(not popup.hint.visible, "loadout has no persistent instruction block")
	_check(not hud.data_label.is_visible_in_tree(), "loadout suppresses the underlying observation readouts")
	hud.autosave_failed = true
	popup.refresh(false)
	_check(popup.hint.visible and popup.hint.text == tr("AUTOSAVE_FAILURE") % game.active_save_slot, "loadout still reports a failed save without a details panel")
	hud.autosave_failed = false
	popup.refresh(false)
	_check(not popup.hint.visible, "resolved save warning leaves no instruction text")
	popup.close()
	_check(not hud.external_readouts_covered, "closing loadout releases its HUD visibility ownership")
	_check(game.deep_sky.current_objective().is_empty(), "learned module acquisition route is absent from the observation HUD")
	hud._refresh_extension()
	_check(not hud.extension_samples_label.visible, "sample balance belongs beside the draw action")
	chart.close_tree()

	hud.reset_tutorial()
	game.tutorial.start_tutorial(false)
	game.tutorial._on_primary_pressed()
	_check(not hud.tutorial_label.visible and not game.tutorial.hint_label.visible, "guided observation shows one instruction surface")
	game.tutorial.skip_tutorial()
	_check(hud.tutorial_label.visible, "skipping guidance restores the first-observation fallback")
	hud.banner_root.hide()
	hud.show_discovery_banner("test_quality", "First quality", Color.WHITE, 1.5)
	_check(hud.banner_label.text == "First quality", "first routine event may introduce its meaning")
	hud.banner_root.hide()
	hud.show_discovery_banner("test_quality", "Repeated quality", Color.WHITE, 1.5)
	_check(not hud.banner_root.visible, "repeated routine success does not reopen the global banner")
	hud.show_banner("Save warning", Color.WHITE, 3.0)
	hud.show_discovery_banner("test_echo", "Echo", Color.WHITE, 1.5)
	_check(hud.banner_label.text == "Save warning", "routine discoveries never overwrite an active warning")
	hud.banner_root.hide()

	paused = true
	hud.show_phase_summary({"round": 3, "duration": 60.0, "data": 120, "rate": 120.0, "observations": 7, "manual": 5, "automatic": 2}, {"rate": 100.0}, "comparison", true)
	_check(not hud.summary_details.visible and hud.summary_lead.text.contains("+20%"), "summary starts with a comparable rate change and collapsed breakdown")
	hud.summary_details_button.grab_focus()
	await _activate_focused_control()
	_check(hud.is_phase_summary_open() and hud.summary_details.visible, "Space opens summary details instead of accidentally continuing")
	_check(hud.phase_summary_split.is_visible_in_tree() and not hud.summary_lead.visible, "expanded result exposes manual/automatic work without repeating the compact comparison")
	hud.show_phase_summary({"round": 4, "rate": 130.0}, {"rate": 100.0}, "systems_changed", false)
	_check(not hud.summary_details.visible and not hud.summary_details_button.button_pressed and not hud.summary_lead.text.contains("%"), "next round collapses details and preserves non-comparable build context")
	hud.hide_phase_summary()
	paused = false
