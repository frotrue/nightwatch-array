extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await process_frame
	game.progression.debug_purchase_all()
	game.deep_sky.observations = 1
	game.deep_sky._sync_protocol()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game.upgrade_tree.open_tree()
	var popup: Node = game.module_popup
	popup.open()
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		game.deep_sky.state.samples = 0
		popup.refresh()
		_check(popup.draw_button.disabled, "insufficient currency disables draw")
		game.deep_sky.state.award_samples(80)
		popup.refresh()
		popup.draw_button.pressed.emit()
		var id: String = game.deep_sky.state.last_draw
		_check(not id.is_empty() and popup.draw_result.text.contains(tr("MODULE_%s_SHORT" % id.to_upper())), "draw action shows localized actual result")
		game.deep_sky.modules.grant_copy(id)
		popup.refresh()
		popup.owned_buttons[id].pressed.emit()
		popup.owned_buttons[id].pressed.emit()
		_check(game.deep_sky.modules.installed_count(id) == 2, "same inventory tile equips two owned copies")
		popup.slots[0].pressed.emit()
		_check(game.deep_sky.modules.installed_count(id) == 1, "removal returns one copy")
		popup.slots[1].pressed.emit()
		_check(popup.draw_button.text != "MODX_DRAW" and not popup.draw_result.text.contains("MODX_"), "draw UI localized")
		await process_frame
		_check(not popup.draw_button.get_global_rect().intersects(popup.inventory_scroll.get_global_rect()), "draw controls do not overlap inventory")
	popup.close()
	_check(game.upgrade_tree.visible and paused and game.upgrade_tree.atlas_actions.size() == 1, "modal returns to constellation chart without auxiliary screens")
	game.free()
	paused = false
	if failures.is_empty(): print("DEEP_SKY_CHART_EXPANSION_PASS: integrated draw, copies, localized controls and chart return")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
