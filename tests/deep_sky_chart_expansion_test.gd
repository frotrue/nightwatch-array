extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func(): push_error("Draw window watchdog"); quit(1))
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
	var window: Control = popup.draw_window
	for locale in ["en", "ko"]:
		game.settings.set_language(locale, false)
		popup.draw_launcher.pressed.emit()
		_check(popup.is_draw_open() and not popup.surface.visible and not game.upgrade_tree.visible and paused, "dedicated draw launcher owns the paused modal")
		_check(window.action.disabled, "insufficient currency disables draw")
		game.deep_sky.state.award_samples(8)
		popup.refresh()
		window.action.pressed.emit()
		window.set_process(false)
		var id: String = game.deep_sky.state.last_draw
		var serial: int = game.deep_sky.state.draw_serial
		_check(window.drawing and not window.result_panel.visible and not id.is_empty(), "paid result stays hidden during animation")
		window.begin_draw()
		_check(game.deep_sky.state.draw_serial == serial and game.deep_sky.samples == 0, "double activation cannot pay twice")
		window._process(window.REVEAL_SECONDS * 0.6)
		_check(window.drawing and window.status.text == tr("DRAW_ALIGN"), "animation moves from scan to signal alignment")
		window.skip_button.pressed.emit()
		_check(not window.drawing and window.result_panel.visible and window.result_name.text == tr("MODULE_%s_NAME" % id.to_upper()), "skip reveals the actual localized saved result")
		_check(not window.subtitle.text.contains("DRAW_") and not window.result_effect.text.contains("MODULE_"), "draw contents are localized")
		window.loadout_button.pressed.emit()
		_check(not popup.is_draw_open() and popup.surface.visible and paused, "loadout is a separate surface in the same pause boundary")
		_check(game.deep_sky.draw_module().is_empty(), "loadout surface cannot draw directly")
		game.deep_sky.modules.grant_copy(id)
		popup.refresh()
		popup.owned_buttons[id].pressed.emit()
		popup.owned_buttons[id].pressed.emit()
		_check(game.deep_sky.modules.installed_count(id) == 2, "drawn copies equip through the inventory")
		popup.slots[0].pressed.emit()
		popup.slots[1].pressed.emit()
		popup.close()
		_check(game.upgrade_tree.visible and paused, "close returns to the same chart")
	# Closing halfway through is presentation-only. Reopening must not roll.
	game.deep_sky.state.award_samples(16)
	popup.open_draw()
	window.begin_draw()
	var paid_result: String = game.deep_sky.state.last_draw
	var paid_serial: int = game.deep_sky.state.draw_serial
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	popup.close()
	game._apply_save_data(saved)
	game.upgrade_tree.open_tree()
	popup.open_draw()
	_check(window.result_id == paid_result and not window.drawing and game.deep_sky.samples == 8 and game.deep_sky.state.draw_serial == paid_serial, "closing/reloading during reveal retains exactly one saved draw")
	game.settings.motion_intensity = 0.0
	window.begin_draw()
	_check(not window.drawing and window.result_panel.visible and game.deep_sky.samples == 0, "reduced motion reveals immediately with one debit")
	# Persistence failure must not reveal a speculative reward or change RNG.
	game.deep_sky.state.award_samples(8)
	var before: Dictionary = game.deep_sky.get_save_data()
	game.active_save_slot = 1
	window.begin_draw()
	_check(not window.drawing and game.deep_sky.get_save_data() == before, "failed autosave rejects animation and rolls the transaction back")
	game.active_save_slot = 0
	popup.close()
	game.free()
	paused = false
	if failures.is_empty(): print("DEEP_SKY_CHART_EXPANSION_PASS: dedicated draw, animation, skip, double click, reduced motion, close/save rollback and bilingual modal routing")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
