extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const State = preload("res://scripts/expansion_state.gd")
var failures: Array[String] = []
var game: Node
var capture := false

class RecordingSlots:
	extends Fixtures.NoSaveSlots
	var fail := false
	var saved: Dictionary = {}
	func save_slot(_slot: int, run_data: Dictionary) -> Error:
		if fail: return ERR_CANT_CREATE
		saved = JSON.parse_string(JSON.stringify(run_data))
		return OK

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	Fixtures.replace_child(game, "SaveGameController", RecordingSlots.new())
	game.get_node("ModuleTutorial").enabled = true
	root.add_child(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await _frames()
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	var guide = game.module_tutorial
	var deep = game.deep_sky
	var popup = game.module_popup
	var saves = game.save_games
	_check(not guide.active and deep.samples == 0, "locked systems do not grant or interrupt")
	game.active_save_slot = 1
	game.progression.debug_purchase_all()
	_check(deep.samples == 8 and deep.state.module_intro_stage == State.Intro.DRAW, "unlock funds the first draw once")
	_check(saves.saved.deep_sky.extension.samples == 8 and saves.saved.deep_sky.extension.module_intro_stage == State.Intro.DRAW, "unlock purchase autosaves its grant before any UI input")
	deep._sync_protocol()
	_check(deep.samples == 8, "repeated unlock notifications cannot duplicate samples")
	await _frames()
	_check(not guide.active, "galaxy reveal retains its controls before the guide")
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	await _frames()
	_check(guide.active and guide.phase == "OPEN" and paused, "first module launcher receives the paused guide")
	game._autosave_active_slot()
	var funded: Dictionary = saves.saved.duplicate(true)
	await _capture("open")
	await _key(KEY_U)
	_check(game.upgrade_tree.is_open() and guide.active, "chart shortcut cannot bypass guide")
	await _click(Vector2(1100, 30))
	_check(guide.phase == "OPEN", "off-target clicks cannot advance")
	await _click(guide.target.get_global_rect().get_center())
	_check(popup.is_draw_open() and guide.phase == "DRAW", "real launcher click opens first draw")
	await _capture("draw")
	saves.fail = true
	await _click(guide.target.get_global_rect().get_center())
	_check(deep.samples == 8 and deep.state.draw_serial == 0 and deep.state.module_intro_stage == State.Intro.DRAW, "failed persistence rolls back tutorial, debit and draw")
	_check(guide.phase == "DRAW" and game.hud.autosave_failed, "failed draw remains retryable")
	await _key(KEY_ESCAPE)
	_check(game.hud.is_settings_open() and game.hud.layer > guide.layer and not guide.screen.visible and paused, "settings remain reachable after a failed save")
	_check(game.hud.tutorial_replay_button.disabled, "onboarding tutorials cannot overlap from settings")
	await _key(KEY_ESCAPE)
	_check(not game.hud.is_settings_open() and game.hud.layer == 80 and guide.screen.visible and paused, "settings return to the same paused tutorial")
	saves.fail = false
	await _key(KEY_ENTER)
	_check(deep.samples == 0 and deep.state.draw_serial == 1 and deep.state.module_intro_stage == State.Intro.EQUIP, "keyboard draw commits one result before reveal")
	var drawn_id: String = deep.state.module_intro_id
	var drawn: Dictionary = saves.saved.duplicate(true)
	_check(drawn.deep_sky.extension.module_intro_id == drawn_id, "saved result includes tutorial identity")
	_check(popup.draw_window.drawing, "normal motion starts the reveal")
	await _key(KEY_SPACE)
	_check(guide.phase == "RESULT", "highlighted skip reveals without rerolling")
	await _capture("result")
	await _click(popup.draw_window.action.get_global_rect().get_center())
	_check(deep.state.draw_serial == 1, "repeat draw is blocked until first equip")
	await _click(guide.target.get_global_rect().get_center())
	_check(guide.phase == "EQUIP" and not popup.slots[0].disabled, "result confirmation exposes the guided empty slot")
	await _capture("equip")
	saves.fail = true
	await _click(guide.target.get_global_rect().get_center())
	_check(deep.modules.installed_ids().is_empty() and deep.state.module_intro_stage == State.Intro.EQUIP and guide.active, "failed equip restores pending guide")
	saves.fail = false
	await _click(guide.target.get_global_rect().get_center())
	_check(deep.modules.slots[0] == drawn_id and deep.state.module_intro_stage == State.Intro.COMPLETE and not guide.active, "first slot click installs and completes")
	_check(popup.is_open() and paused, "completion preserves loadout pause for free editing")
	_check(popup.hint.visible and popup.hint.text == tr("MODULE_INTRO_DONE"), "completion feedback is visible inside the loadout")
	var complete: Dictionary = saves.saved.duplicate(true)
	await _click(popup.slots[0].get_global_rect().get_center())
	_check(deep.modules.installed_ids().is_empty() and not guide.active, "normal unequip is restored after completion")
	await _restore(drawn)
	_check(guide.phase == "RESULT" and deep.state.module_intro_id == drawn_id and deep.state.draw_serial == 1 and deep.samples == 0, "load during reveal resumes saved result without reroll or reward")
	await _restore(funded)
	_check(guide.phase == "OPEN" and deep.samples == 8, "load before first draw restores one funded attempt")
	game.settings.motion_intensity = 0.0
	await _click(guide.target.get_global_rect().get_center())
	await _click(guide.target.get_global_rect().get_center())
	_check(guide.phase == "RESULT" and not popup.draw_window.drawing, "reduced motion immediately reaches result")
	await _restore(complete)
	_check(not guide.active and deep.state.module_intro_stage == State.Intro.COMPLETE, "completed save never restarts intro")
	var legacy := complete.duplicate(true)
	legacy.deep_sky.extension.erase("module_intro_stage")
	legacy.deep_sky.extension.erase("module_intro_id")
	await _restore(legacy)
	_check(not guide.active and deep.samples == 0, "legacy player with modules gets no forced guide or gift")
	legacy = funded.duplicate(true)
	legacy.deep_sky.extension.erase("module_intro_stage")
	legacy.deep_sky.extension.erase("module_intro_id")
	await _restore(legacy)
	_check(guide.active and deep.samples == 16, "unused legacy modules receive the first-draw grant")
	game._autosave_active_slot()
	await _restore(saves.saved.duplicate(true))
	_check(deep.samples == 16, "saving migrated intro makes the gift idempotent")
	legacy = drawn.duplicate(true)
	legacy.deep_sky.extension.module_intro_id = "retired_invalid"
	await _restore(legacy)
	_check(not guide.active and deep.samples == 0, "invalid saved target cannot softlock or pay again")
	await _restore(funded)
	await _key(KEY_ESCAPE)
	game._start_fresh_slot()
	await _frames()
	_check(not guide.active and game.hud.layer == 80 and deep.samples == 0, "fresh run clears guide and temporary settings layer")
	paused = false
	game.queue_free()
	await _frames()
	if failures.is_empty():
		print("MODULE_TUTORIAL_PASS: guided real input, transactional first draw/equip, save resume, legacy migration, settings escape and reduced motion")
	else:
		for failure in failures: printerr("MODULE_TUTORIAL_FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _restore(data: Dictionary) -> void:
	game.hud.close_settings()
	game._apply_save_data(data.duplicate(true))
	await _frames()

func _frames() -> void:
	for _i in 4: await process_frame

func _click(point: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event, true)
	await _frames()

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
	await _frames()

func _capture(label: String) -> void:
	if not capture: return
	for locale in ["en", "ko"]:
		TranslationServer.set_locale(locale)
		game.deep_sky.changed.emit()
		await _frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/module_intro_%s_%s.png" % [label, locale])
	TranslationServer.set_locale("en")
	game.deep_sky.changed.emit()
	await _frames()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
