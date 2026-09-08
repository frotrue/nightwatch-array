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
	_check(Modules.DEFINITIONS.size() == 14, "expanded definitions expose all fourteen modules")
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
	game.deep_sky.modules.grant_copy("focus")
	popup.refresh(false)
	_check(game.deep_sky.modules.owned_count("focus") == 2 and popup.inventory_count.text == tr("MODX_COUNT") % 1, "duplicates keep one type and their owned quantity")
	popup.show_module_tooltip("focus")
	_check(popup.tooltip_panel.visible, "owned module exposes its tooltip")
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
	_check(scrollbar.max_value > scrollbar.page, "fourteen owned modules create scrollable storage")

	popup.close()
	_check(not popup.is_open() and game.upgrade_tree.visible and paused, "closing the modal restores the chart pause")
	_check(game.get_viewport().gui_get_focus_owner() == popup.launcher, "closing the modal restores the previous focus")
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
