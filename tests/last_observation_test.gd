extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
var failures: Array[String] = []

class RecordingSlots:
	extends Fixtures.NoSaveSlots
	var writes := 0
	var saved: Dictionary = {}
	func save_slot(_slot: int, data: Dictionary) -> Error:
		writes += 1
		saved = data.duplicate(true)
		return OK

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message); push_error(message)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	Fixtures.replace_child(game, "SaveGameController", RecordingSlots.new())
	root.add_child(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await process_frame
	game.ending.set_process(false)
	check(not game.ending.start(), "ending is locked before all research")
	game.progression.debug_purchase_all()
	game.galactic_pullback_seen = true
	game.upgrade_tree.configure_galactic_state(true, true)
	game._close_upgrade_tree_without_transition()
	check(not game.ending.start(), "base research alone cannot unlock ending")
	game.deep_sky.debug_purchase_all_research()
	game.ending.refresh_availability()
	check(game.ending.eligible and not game.ending.active, "all 162 nodes expose an optional final observation")
	game.active_save_slot = 1
	var before: Dictionary = game._build_save_data()
	var positions: Dictionary = game.upgrade_tree.expanded_star_positions.duplicate()
	check(game.ending.start(), "complete run can start final observation")
	check(not game.ending.start(), "duplicate starts are rejected")
	check(not game.hud.visible and game.ending.film.mouse_filter == Control.MOUSE_FILTER_STOP, "film prevents pointer and focus access to the underlying HUD")
	game._resume_observation_if_unblocked()
	check(paused, "ordinary pause reconciliation respects the final observation")
	await press_action("nw_chart")
	check(not game.upgrade_tree.is_open(), "chart binding cannot escape the ending")
	var original_fullscreen: bool = game.settings.is_fullscreen()
	await press_action("nw_fullscreen")
	check(game.settings.is_fullscreen() != original_fullscreen, "fullscreen remains available during ending")
	await press_action("nw_fullscreen")
	game.simulate_tick()
	check(game.observation_phase_remaining == before.observation_phase_remaining, "ordinary observation clock freezes")
	var ending: Node = game.ending
	var center: Vector2 = ending.film.size * Vector2(0.5, 0.465)
	for i in 300: ending.advance(0.1, false, Vector2.ZERO)
	# Float boundary may require one more tick to enter observation.
	while ending.phase < ending.Phase.OBSERVE: ending.advance(0.1, false, Vector2.ZERO)
	for i in 1500: ending.advance(0.1, false, Vector2.ZERO)
	check(ending.phase == ending.Phase.OBSERVE and is_equal_approx(ending.observation_progress, 0.85), "equipment cannot finish without the player's last observation")
	var progress: float = ending.observation_progress
	ending.advance(1.0, true, Vector2.ZERO)
	check(ending.observation_progress == progress, "holding away from the horizon does not finish the target")
	await press_action("nw_menu_back")
	check(game.hud.is_settings_open(), "menu-back opens settings over the ending")
	check(game.hud.visible, "settings restore HUD visibility over the film")
	check(game.hud.tutorial_replay_button.disabled, "settings prevent an overlapping tutorial")
	game._on_tutorial_replay_requested()
	check(game.hud.is_settings_open() and not game.tutorial.is_modal_step(), "tutorial replay cannot dismiss the ending pause owner")
	var elapsed: float = ending.elapsed
	ending.advance(10.0, true, center)
	check(ending.elapsed == elapsed and ending.drone.stream_paused, "settings pause both cinematic and audio")
	await press_action("nw_menu_back")
	check(not game.hud.is_settings_open(), "menu-back closes settings during ending")
	check(paused, "closing settings must not resume ordinary gameplay during ending")
	var guard := 0
	while ending.phase != ending.Phase.RECORD or ending.phase_elapsed < 12.0:
		ending.advance(0.1, true, center)
		guard += 1
		if guard > 1200: check(false, "ending failed to complete after direct observation"); break
	check(game.horizon_ending_seen, "last record persists a new completion flag")
	check(game._build_save_data().horizon_ending_seen, "completion is included in slot payload")
	check(game.save_games.writes == 1 and game.save_games.saved.horizon_ending_seen, "the last record autosaves completion exactly once")
	ending.advance(1.0, true, center)
	check(game.save_games.writes == 1, "holding on the record cannot repeat the completion transaction")
	check(game.progression.get_save_data() == before.progression, "ending grants no currency or research and destroys no progress")
	check(positions == game.upgrade_tree.expanded_star_positions, "cinematic leaves catalogue coordinates unchanged")
	check(ending.lines.chart_points.size() == positions.size(), "cinematic uses the existing chart's stars")
	ending.return_to_chart()
	check(not ending.active and game.upgrade_tree.is_open(), "record returns to the chart")
	check(game.hud.visible and not game.hud.final_observation_active, "return restores normal HUD interaction")
	game._close_upgrade_tree_without_transition()
	game._resume_observation_if_unblocked()
	check(not paused and game.observation_phase_remaining == before.observation_phase_remaining, "return resumes the same round")
	check(ending.start(), "completed ending can replay")
	game._apply_save_data(before)
	check(not ending.active and not game.horizon_ending_seen, "loading a different slot clears film and its completion")
	var old := before.duplicate(true)
	old.erase("horizon_ending_seen")
	game._apply_save_data(old)
	check(not game.horizon_ending_seen, "legacy slots default to unseen")
	old.horizon_ending_seen = "true"
	game._apply_save_data(old)
	check(not game.horizon_ending_seen, "malformed ending flag is not accepted")
	check(ending.start(true), "debug preview can start")
	var writes_before_preview: int = game.save_games.writes
	ending.phase = ending.Phase.RECORD
	ending.phase_elapsed = 12.0
	ending.advance(0.1, false, center)
	check(not game.horizon_ending_seen, "debug preview never marks or saves completion")
	check(game.save_games.writes == writes_before_preview, "debug preview never writes the player's slot")
	game.reset_run()
	check(not ending.active and not ending.eligible, "reset clears the ending and its launch state")
	game.queue_free()
	paused = false
	await process_frame
	await process_frame
	# Let the dummy mixer release stopped playback references after scene teardown.
	await create_timer(0.15).timeout
	if failures.is_empty(): print("LAST_OBSERVATION_PASS: unlock, input, pause, preservation, replay, load and record"); quit(0)
	else: quit(1)

func press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	await process_frame
	event.pressed = false
	root.push_input(event)
	await process_frame
