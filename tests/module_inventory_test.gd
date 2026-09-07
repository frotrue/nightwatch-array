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
	_check(popup.tooltip_panel.visible, "unowned catalog tile exposes an acquisition tooltip")

	popup.set_inventory_filter("owned")
	_check(popup.owned_buttons.focus.visible and not popup.owned_buttons[locked_id].visible, "owned filter hides unowned modules")
	popup.set_inventory_filter("trace")
	_check(popup.owned_buttons["trail_integrator"].visible and not popup.owned_buttons["afterglow_archive"].visible, "tracking filter uses definition categories")
	popup.set_inventory_filter("all")
	var scrollbar: Range = popup.inventory_scroll.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "fourteen modules create a scrollable catalog")

	popup.close()
	_check(not popup.is_open() and game.upgrade_tree.visible and paused, "closing the modal restores the chart pause")
	_check(game.get_viewport().gui_get_focus_owner() == popup.launcher, "closing the modal restores the previous focus")
	game.free()

	if failures.is_empty():
		print("MODULE_INVENTORY_PASS: fourteen-module catalog, filters, locked paths, scroll and modal focus")
		quit(0)
	else:
		push_error(str(failures))
		quit(1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error("MODULE_INVENTORY: " + message)
