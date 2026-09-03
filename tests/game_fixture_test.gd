extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const MainScene = preload("res://scenes/main.tscn")
var failures: Array[String] = []

class GuardedSettings:

	extends Fixtures.NoSettings

	var disk_load_attempts := 0

	func _load_locale() -> String:
		disk_load_attempts += 1
		return "ko"

	func _load_tutorial_completed() -> bool:
		disk_load_attempts += 1
		return false

	func _load_research_chart_rotation() -> float:
		disk_load_attempts += 1
		return 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = MainScene.instantiate()
	Fixtures.configure_before_ready(game)
	_check(not game.startup_slot_prompt_enabled and not game.get_node("Tutorial").auto_start_enabled, "diagnostics skip startup interaction")
	_check(game.get_node("SaveGameController") is Fixtures.NoSaveSlots, "save service is replaced before ready")
	_check(game.get_node("GameSettings") is Fixtures.NoSettings, "settings service is replaced before ready")
	var settings := GuardedSettings.new()
	Fixtures.replace_child(game, "GameSettings", settings)
	# Even if a future caller sets a directory, fixture operations must not create it.
	var forbidden_directory := "res://build/fixture-must-not-create-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	game.get_node("SaveGameController").save_directory = forbidden_directory
	root.add_child(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var slots: Node = game.save_games
	_check(settings.disk_load_attempts == 0, "ready never calls production settings readers")
	_check(settings.locale == "en" and settings.tutorial_completed, "fixture starts in a deterministic locale without onboarding")
	_check(settings.process_mode == Node.PROCESS_MODE_ALWAYS, "settings retains the UI pause contract")
	for slot in range(1, 4):
		_check(slots.get_slot_summary(slot) == {"exists": false, "valid": true}, "fixture reports an empty slot")
		_check(slots.save_slot(slot, {"sentinel": true}) == ERR_UNAVAILABLE, "saving cannot silently claim persistence")
		_check(slots.load_slot(slot).is_empty(), "loading cannot read a real slot")
		_check(slots.reset_slot(slot) == ERR_UNAVAILABLE, "reset cannot delete a real slot")
	_check(slots.get_slot_summary(0) == {"exists": false, "valid": false}, "invalid slots retain the production validation contract")
	slots.slot_summaries.clear()
	_check(not slots.get_slot_summary(1).exists, "a cache miss still uses the isolated summary reader")
	slots.set_save_directory(forbidden_directory + "/nested")
	slots._ensure_save_directory()
	slots._reload_slot_summaries()
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(forbidden_directory)), "no fixture operation creates a save directory")
	settings.set_language("ko")
	_check(settings.locale == "ko" and TranslationServer.get_locale().left(2) == "ko", "language remains functional in memory")
	settings.set_research_chart_rotation(TAU + 0.25)
	_check(is_equal_approx(settings.research_chart_rotation, 0.25), "rotation is wrapped without persistence")
	settings.set_tutorial_completed(false)
	_check(not settings.is_tutorial_completed(), "tutorial state can be varied in memory")
	settings.set_language("en")
	var silent := Fixtures.SilentSound.new()
	root.add_child(silent)
	var voice_count := silent.get_child_count()
	silent.play_upgrade()
	silent.play_rare_target()
	_check(silent.get_child_count() == voice_count, "silent dispatch does not allocate additional voices")
	for voice in silent.voice_pool:
		_check(not voice.playing, "silent fixture never starts a pooled audio voice")
	silent.free()
	game.free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("GAME_FIXTURE_PASS: pre-ready isolation, nonpersistent slots/settings and silent diagnostics")
		quit(0)
	else:
		print("GAME_FIXTURE_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GAME_FIXTURE: " + message)
