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
	var gameplay_camera: Transform2D = game.observation_view.transform
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
	check_camera(ending)
	check_star_infall(ending)
	var progress: float = ending.observation_progress
	ending.advance(1.0, true, Vector2.ZERO)
	check(ending.observation_progress == progress, "holding away from the horizon does not finish the target")
	var reticle_radius: float = ending.observation_radius()
	ending.advance(1.0, true, center + Vector2(reticle_radius * 1.05, 0.0))
	check(ending.observation_progress == progress, "direct observation rejects input outside the distant reticle")
	ending.advance(1.0, true, center + Vector2(reticle_radius * 0.95, 0.0))
	check(ending.observation_progress > progress, "direct observation accepts input inside the distant reticle")
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
	while ending.phase < ending.Phase.COLLAPSE: ending.advance(0.1, true, center)
	ending._process(0.0)
	check(not ending.get_node("Root/Film/Menu").visible, "the automatic fall clears the menu from the view")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "the automatic fall hides the pointer")
	await press_action("nw_menu_back")
	ending._process(0.0)
	check(game.hud.is_settings_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape still exposes usable settings during the fall")
	await press_action("nw_menu_back")
	var guard := 0
	while ending.phase != ending.Phase.RECORD or ending.phase_elapsed < 12.0:
		ending.advance(0.1, true, center)
		guard += 1
		if guard > 1200: check(false, "ending failed to complete after direct observation"); break
	check(game.horizon_ending_seen, "last record persists a new completion flag")
	ending._process(0.0)
	check(ending.get_node("Root/Film/Menu").visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the final record restores menu and pointer")
	check(game._build_save_data().horizon_ending_seen, "completion is included in slot payload")
	check(game.save_games.writes == 1 and game.save_games.saved.horizon_ending_seen, "the last record autosaves completion exactly once")
	ending.advance(1.0, true, center)
	check(game.save_games.writes == 1, "holding on the record cannot repeat the completion transaction")
	check(game.progression.get_save_data() == before.progression, "ending grants no currency or research and destroys no progress")
	check(positions == game.upgrade_tree.expanded_star_positions, "cinematic leaves catalogue coordinates unchanged")
	check(game.observation_view.transform == gameplay_camera, "cinematic camera leaves the saved gameplay view unchanged")
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
	for tick in 960:
		ending.advance(0.1, true, center)
		if ending.phase == ending.Phase.COLLAPSE and ending.phase_elapsed == 0.0:
			check(ending.elapsed >= 45.0 and ending.elapsed < 46.0, "continuous observation reaches collapse after the shortened 45-second prelude")
		if ending.phase == ending.Phase.RECORD and ending.phase_elapsed >= 12.0: break
	check(ending.phase == ending.Phase.RECORD and ending.phase_elapsed >= 12.0 and ending.elapsed < 96.0, "the shortened complete ending reaches its record in about 95 seconds")
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

func check_camera(ending: Node) -> void:
	var original_phase: int = ending.phase
	var original_time: float = ending.phase_elapsed
	var original_motion: float = ending.motion_scale
	ending.motion_scale = 1.0
	var observing: Dictionary = ending.visual_state()
	check(observing.camera_zoom > 0.0 and observing.camera_zoom < 1.0 and observing.camera_zoom == ending.visual_state(0.0).camera_zoom and observing.camera_offset == Vector2.ZERO and observing.camera_roll == 0.0, "direct observation keeps a stable distant framing without moving the target")
	ending.phase = ending.Phase.LIMIT
	ending.phase_elapsed = ending.DURATIONS[ending.Phase.LIMIT]
	var limit: Dictionary = ending.visual_state()
	ending.phase = ending.Phase.COLLAPSE
	ending.phase_elapsed = 0.0
	var start: Dictionary = ending.visual_state()
	check(is_equal_approx(limit.camera_zoom, start.camera_zoom) and limit.camera_offset == start.camera_offset, "camera approach is continuous across the observation limit")
	var previous: float = start.camera_zoom
	for second in range(1, 29):
		ending.phase_elapsed = float(second)
		var frame: Dictionary = ending.visual_state()
		check(is_finite(frame.camera_zoom) and frame.camera_zoom >= previous and frame.camera_offset.is_finite(), "camera advances monotonically with finite projection")
		previous = frame.camera_zoom
	var early_travel: float = ending.visual_state(19.0).camera_zoom - ending.visual_state(18.0).camera_zoom
	var late_travel: float = ending.visual_state(27.0).camera_zoom - ending.visual_state(26.0).camera_zoom
	check(late_travel > early_travel * 4.0, "the visible final approach accelerates strongly")
	var arrival: Dictionary = ending.visual_state()
	var corner := Vector2(ending.film.size.x / ending.film.size.y * 0.5, 0.535)
	check(arrival.horizon_radius * arrival.camera_zoom > corner.length() + arrival.camera_offset.length() * arrival.camera_zoom, "the final horizon overtakes the whole viewport")
	for second in [26.0, 27.0, 27.4, 27.7, 28.0]:
		var frame: Dictionary = ending.visual_state(second)
		if frame.horizon_radius * frame.camera_zoom < corner.length() + frame.camera_offset.length() * frame.camera_zoom:
			check(frame.camera_crossing == 0.0, "the crossing fade waits until the horizon covers the viewport")
	check(arrival.camera_crossing == 1.0, "crossing fully removes foreground light at the end of the fall")
	ending.motion_scale = 0.5
	var partial_arrival: Dictionary = ending.visual_state()
	ending.phase = ending.Phase.BLACKOUT
	ending.phase_elapsed = 0.0
	var partial_blackout: Dictionary = ending.visual_state()
	check(is_equal_approx(partial_arrival.camera_rush, partial_blackout.camera_rush) and is_equal_approx(partial_arrival.camera_zoom, partial_blackout.camera_zoom), "partial motion cannot pop the light or camera on entering blackout")
	ending.motion_scale = 0.0
	var reduced: Dictionary = ending.visual_state()
	check(reduced.camera_zoom == 1.0 and reduced.camera_roll == 0.0 and reduced.camera_offset == Vector2.ZERO and reduced.camera_rush == 0.0, "zero motion removes camera travel, roll and streaks")
	ending.phase = original_phase
	ending.phase_elapsed = original_time
	ending.motion_scale = original_motion

func check_star_infall(ending: Node) -> void:
	var original := {"phase": ending.phase, "time": ending.phase_elapsed, "elapsed": ending.elapsed, "motion": ending.motion_scale}
	ending.phase = ending.Phase.COLLAPSE
	ending.phase_elapsed = 0.0
	ending.elapsed = 45.0
	ending.motion_scale = 1.0
	var lines: Node = ending.lines
	var view: Dictionary = ending.visual_state()
	check(lines.star_tracks.size() == lines.chart_points.size(), "each retained chart star has exactly one infall track")
	var last_release := -1.0
	for key: String in lines.star_tracks:
		var track: Dictionary = lines.star_tracks[key]
		var origin: Vector2 = lines.chart_points[key]
		var release: float = track.release
		var join_time: float = release + track.join
		check(release > last_release, "stars detach in individual, ordered releases")
		last_release = release
		check(lines.star_pose(key, release, view) == Vector3(origin.x, origin.y, 0.0), "a star stays on its chart until its release")
		var before_join: Vector3 = lines.star_pose(key, join_time - 0.0001, view)
		var after_join: Vector3 = lines.star_pose(key, join_time + 0.0001, view)
		check(before_join.distance_to(after_join) < 0.005, "the falling path joins its disc orbit without a position jump")
		var first: Vector3 = lines.star_pose(key, join_time + 0.15, view)
		var second: Vector3 = lines.star_pose(key, join_time + 0.25, view)
		var a := Vector2(first.x, first.y).rotated(-float(view.disc_tilt)) * Vector2(1.0, view.disc_flatten)
		var b := Vector2(second.x, second.y).rotated(-float(view.disc_tilt)) * Vector2(1.0, view.disc_flatten)
		check(first.is_finite() and second.is_finite() and a.cross(b) > 0.0 and b.length() < a.length(), "joined stars spiral inward in the disc's rotation direction")
		check(lines.star_alpha(key, join_time + track.orbit) == 0.0, "accreted stars leave no persistent points")
	check(ending.disc_rotation(2.0) > ending.disc_rotation(1.0), "the disc advances with the cinematic clock")
	ending.motion_scale = 0.0
	check(ending.disc_rotation(12.0) == 0.0, "zero motion freezes the accretion disc")
	for key: String in lines.chart_points:
		var point: Vector2 = lines.chart_points[key]
		check(lines.star_pose(key, 12.0, view) == Vector3(point.x, point.y, 0.0), "zero motion keeps chart stars fixed")
	ending.phase = original.phase
	ending.phase_elapsed = original.time
	ending.elapsed = original.elapsed
	ending.motion_scale = original.motion
