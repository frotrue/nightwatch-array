extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE: " + message)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	var startup_save_directory := "user://nightwatch_startup_smoke_saves"
	_cleanup_smoke_saves(startup_save_directory)
	game.save_games.set_save_directory(startup_save_directory)
	game.hud.open_startup_slots()
	_check(game.hud.is_startup_slots_open() and paused, "startup save-slot picker pauses the game")
	_check(game.hud.startup_slot_buttons.size() == 3, "startup picker exposes exactly three save slots")
	game._on_startup_slot_selected(2)
	_check(not game.hud.is_startup_slots_open() and not paused, "choosing a startup slot enters the game")
	_check(game.active_save_slot == 2 and game.save_games.has_slot(2), "an empty startup slot creates and activates a new save")
	_check(game._preferred_startup_slot() == 2, "quick start resumes the newest valid save without opening the slot picker")
	_check(game.hud.save_mode_label.visible and game.hud.save_mode_label.text == TranslationServer.translate("HUD_AUTOSAVED"), "autosave status appears only after a completed save")
	game.hud._process(2.3)
	_check(not game.hud.save_mode_label.visible, "autosave status hides instead of becoming persistent HUD text")
	game.progression.add_debug_data(23.0)
	game.autosave_elapsed = game.AUTOSAVE_INTERVAL_SECONDS - 0.1
	game._process(0.2)
	var autosaved_data: Dictionary = game.save_games.load_slot(2)
	var autosaved_progression: Dictionary = autosaved_data.get("progression", {})
	_check(int(autosaved_progression.get("observation_data", 0.0)) == 23, "active slot autosaves current progress after 60 seconds")
	_check(int(autosaved_data.get("observation_round", 0)) == 1, "autosave stores the current observation round")
	_check(bool(autosaved_data.get("observation_phase_active", false)), "autosave stores the active observation phase")
	_check(game.autosave_elapsed < 1.0, "autosave interval resets after writing")
	game.progression.reset()
	game._on_startup_slot_selected(2)
	_check(int(game.progression.observation_data) == 23, "choosing an occupied startup slot resumes its autosave")
	game.elapsed_time = 42.0
	game.hud.open_settings()
	_check(game.hud.save_slot_buttons[2].text == TranslationServer.translate("STARTUP_NEW_GAME"), "an empty settings slot is presented as a new game action")
	game.hud._on_save_slot_pressed(3)
	_check(game.active_save_slot == 3 and game.save_games.has_slot(3), "clicking an empty settings slot creates and activates a new save")
	_check(is_zero_approx(game.elapsed_time) and is_zero_approx(game.progression.observation_data), "an empty settings slot starts from a fresh run instead of copying current progress")
	_check(not game.hud.is_settings_open() and not paused, "starting a new game from an empty slot closes settings and resumes gameplay")
	game.hud.open_startup_slots()
	_check(game.hud.startup_reset_buttons.size() == 3 and game.hud.startup_reset_buttons[1].visible, "startup picker exposes reset for each occupied slot")
	game.hud._on_reset_slot_pressed(2)
	_check(game.hud.reset_dialog.visible, "slot reset requires confirmation")
	game.hud.reset_dialog.hide()
	game.hud._on_reset_confirmed()
	_check(not game.save_games.has_slot(2) and game.active_save_slot == 3, "resetting a non-active startup slot erases only that slot")
	_check(game.hud.is_startup_slots_open() and game.hud.startup_slot_buttons[1].text == TranslationServer.translate("STARTUP_NEW_GAME"), "reset startup slot immediately becomes available for a new game")
	game.hud.close_startup_slots()
	game.progression.add_debug_data(41.0)
	game._autosave_active_slot()
	game.hud.open_settings()
	game.hud._on_save_management_pressed()
	_check(game.hud.reset_slot_buttons.size() == 3 and game.hud.reset_slot_buttons[2].visible, "settings exposes reset for the active occupied slot")
	game.hud._on_reset_slot_pressed(3)
	game.hud.reset_dialog.hide()
	game.hud._on_reset_confirmed()
	_check(game.active_save_slot == 3 and game.save_games.has_slot(3), "resetting the active slot starts a clean save in the same slot")
	_check(is_zero_approx(game.progression.observation_data) and not game.hud.is_settings_open() and not paused, "active-slot reset restarts clean gameplay without extra overlays")
	_cleanup_smoke_saves(startup_save_directory)
	game.active_save_slot = 0
	game.hud.set_active_save_slot(0)
	var smoke_save_directory := "user://nightwatch_smoke_saves"
	_cleanup_smoke_saves(smoke_save_directory)
	game.save_games.set_save_directory(smoke_save_directory)
	game.reset_run()
	var engine_version: Dictionary = Engine.get_version_info()
	var has_high_polling_fix := (
		int(engine_version.major) > 4
		or (int(engine_version.major) == 4 and int(engine_version.minor) > 7)
		or (int(engine_version.major) == 4 and int(engine_version.minor) == 7 and int(engine_version.patch) >= 2)
	)
	_check(has_high_polling_fix, "runtime is Godot 4.7.2+ with the Windows high-polling input fix")
	# The headless display server intentionally ignores cursor-mode changes.
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "native cursor is hidden while the software cursor is active")
	var top_status: Control = game.hud.root_control.get_node("TopStatus")
	_check(_decorative_controls_ignore_mouse(top_status), "top status HUD remains mouse-filter transparent")
	_check(not game.hud.root_control.has_node("UpgradeTreeLauncher"), "persistent upgrade recommendation card is removed from the playfield")
	_check(game.hud.debug_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "display-only debug panel does not intercept tracking input")
	var settings_button_center: Vector2 = game.hud.settings_button.get_global_rect().get_center()
	_check(game.hud.is_pointer_over_hud(settings_button_center), "interactive settings HUD is recognized as a native-cursor region")
	_check(not game.hud.is_pointer_over_hud(get_root().get_visible_rect().get_center()), "open playfield keeps the software cursor")
	game.observer._set_native_cursor_visible(true)
	_check(game.observer.native_cursor_visible, "native cursor activates over HUD surfaces")
	game.observer._set_native_cursor_visible(false)
	_check(not game.observer.native_cursor_visible, "software cursor returns over the playfield")
	_check(not game.upgrade_tree.is_open(), "upgrade tree begins closed")
	_check(not game.tutorial.is_active(), "tutorial auto-start can be disabled for deterministic tests")
	game.tutorial.start_tutorial(false)
	_check(game.tutorial.current_step == 0 and paused, "tutorial starts with a paused welcome step")
	var welcome_locale: String = game.settings.locale
	game.settings.set_language("en" if welcome_locale == "ko" else "ko", false)
	_check(paused, "changing language does not release the tutorial pause")
	game.settings.set_language(welcome_locale, false)
	game.tutorial._on_primary_pressed()
	_check(game.tutorial.current_step == 1 and not paused, "tutorial enters the live observation step")
	game.tutorial.notify_observation_completed()
	_check(game.tutorial.current_step == 2, "an observation advances the tutorial")
	game.tutorial.notify_upgrade_tree_opened()
	_check(game.tutorial.current_step == 3, "opening the tree advances the tutorial")
	game.tutorial.notify_upgrade_purchased()
	_check(game.tutorial.current_step == 4, "purchasing an upgrade completes the guided steps")
	game.tutorial._on_primary_pressed()
	_check(not game.tutorial.is_active(), "finishing hides the tutorial")
	var starting_locale: String = game.settings.locale
	game.settings.set_language("ko", false)
	await process_frame
	_check(TranslationServer.get_locale().left(2) == "ko", "Korean locale activates through game settings")
	_check("설정" in game.hud.settings_button.text, "HUD refreshes with Korean text")
	_check(game.upgrade_tree.title_label.text == "관측망", "upgrade tree refreshes with Korean text")
	_check(TranslationServer.translate("HUD_AUTOSAVED") == "자동 저장됨", "Korean autosave status stays concise")
	_check(TranslationServer.translate("HUD_OBSERVATION_TIME") % [1, 0, 30] == "1차 관측  •  00:30", "Korean round countdown reads naturally")
	_check(TranslationServer.translate("TREE_INTERMISSION_SUBTITLE") % [2, 40] == "업그레이드 시간  /  2차 관측은 40초", "Korean upgrade-break guidance explains the next round")
	_check(TranslationServer.translate("PHASE_SUMMARY_TITLE") % 1 == "1차 관측 완료", "Korean phase summary title reads naturally")
	_check(TranslationServer.translate("UPGRADE_OBSERVATION_SCHEDULING_NAME") == "관측 일정 최적화", "Korean duration-research name is localized")
	_check(TranslationServer.translate("UPGRADE_ERROR_NEED_DATA") % 12 == "데이터가 12개 더 필요합니다", "Korean shortfall text is a complete sentence")
	_check(TranslationServer.translate("TREE_NEED_MORE") % [8, 12] == "◇  데이터 8 / 12", "Korean tree affordability text shows current and required Data")
	_check(TranslationServer.translate("SAVE_RESET_PROMPT") % 2 == "슬롯 2의 모든 진행 상황을 삭제합니다. 이 작업은 되돌릴 수 없습니다.", "Korean reset warning clearly explains permanent deletion")
	_check(game.hud.language_selector.get_item_metadata(1) == "ko", "language selector exposes Korean")
	game.hud.open_settings()
	_check(game.hud.is_settings_open(), "settings overlay opens")
	_check(paused, "settings overlay pauses gameplay")
	_check(not game.hud.save_management_container.visible, "save management stays collapsed in the default settings view")
	game.hud._on_save_management_pressed()
	_check(game.hud.save_management_container.visible, "save management expands on demand")
	game.hud.close_settings()
	_check(not paused, "closing settings resumes gameplay")
	game.settings.set_language("en", false)
	await process_frame
	_check(game.hud.settings_button.text.ends_with("SETTINGS"), "English can be restored at runtime")
	game.settings.set_language(starting_locale, false)
	await process_frame

	var initial: Dictionary = game.get_debug_snapshot()
	var balance = load("res://scripts/game_balance.gd")
	_check(initial.upgrade_level == 0, "run begins with no upgrades")
	_check(initial.successes == 0, "run begins with no observations")
	_check(not initial.final_started, "final event is initially inactive")
	_check(initial.observation_round == 1 and initial.observation_phase_active, "run begins in observation round 1")
	_check(absf(float(initial.observation_phase_remaining) - 30.0) < 1.0, "first observation round starts at 30 seconds")
	_check(game.progression.get_max_active() == 4, "the opening sky supports four concurrent targets so attention starts scarce")
	_check(balance.FIRST_METEOR_DELAY <= 2.0, "the opening meteor arrives before the sky feels empty")
	_check(balance.REGULAR_SPAWN_INTERVAL_MIN == 1.6 and balance.REGULAR_SPAWN_INTERVAL_MAX == 2.4, "regular spawn cadence keeps multiple choices in flight")
	_check(game.progression.get_available_nodes().size() == 3, "only three opening choices are revealed")
	_check(game.hud.array_progress_bar.max_value == 19.0, "HUD exposes the finite array completion goal")
	_check(game.hud.top_panel.size.x <= 510.0, "live HUD stays compact after removing secondary progression copy")
	_check(game.progression.get_node_state("long_exposure") == "hidden", "adjacent optics node begins hidden")
	_check(game.progression.get_node_state("observation_scheduling") == "hidden", "observation-duration research begins behind Array Planning")
	var closed_tree_style_id: int = game.upgrade_tree.node_buttons["better_lens"].get_theme_stylebox("normal").get_instance_id()
	var closed_tree_optics_position: Vector2 = game.upgrade_tree.node_buttons["better_lens"].position
	var data_before_rejected_purchase: float = game.progression.observation_data
	_check(not game.progression.request_purchase("array_planning"), "purchase fails when Observation Data is insufficient")
	_check(game.progression.observation_data == data_before_rejected_purchase, "failed purchase never deducts Data")
	game.progression.add_debug_data(100.0)
	_check(game.upgrade_tree.refresh_pending, "closed upgrade tree defers progression refreshes")
	_check(game.upgrade_tree.node_buttons["better_lens"].position == closed_tree_optics_position, "observation data does not move the fixed upgrade tree")
	_check(game.upgrade_tree.node_buttons["better_lens"].get_theme_stylebox("normal").get_instance_id() == closed_tree_style_id, "closed upgrade tree reuses node styles during observation rewards")
	_check(game.hud.data_gain_label.visible, "resource gains receive immediate HUD feedback")
	game.progression.add_debug_data(1.0)
	_check(not game.hud.root_control.has_node("UpgradeTreeLauncher"), "upgrade affordability does not add persistent HUD clutter")
	var data_before_prerequisite_bypass: float = game.progression.observation_data
	_check(not game.progression.request_purchase("long_exposure"), "hidden prerequisite cannot be bypassed with enough Data")
	_check(game.progression.observation_data == data_before_prerequisite_bypass, "prerequisite rejection never deducts Data")
	game.progression.reset()
	game.upgrade_tree.open_tree()
	await process_frame
	_check(game.upgrade_tree.is_open(), "upgrade tree opens")
	_check(not game.upgrade_tree.refresh_pending, "opening the upgrade tree applies one deferred refresh")
	_check(paused, "opening the upgrade tree pauses gameplay")
	var opening_optics: Button = game.upgrade_tree.node_buttons["better_lens"]
	var opening_detection: Button = game.upgrade_tree.node_buttons["edge_detection"]
	var opening_network: Button = game.upgrade_tree.node_buttons["array_planning"]
	var initial_tree_positions := {
		"better_lens": opening_optics.position,
		"edge_detection": opening_detection.position,
		"array_planning": opening_network.position
	}
	_check(is_equal_approx(opening_optics.position.x, opening_detection.position.x) and is_equal_approx(opening_detection.position.x, opening_network.position.x), "opening branch cards use the permanent branch-aligned layout")
	_check(opening_optics.position.y < opening_detection.position.y and opening_detection.position.y < opening_network.position.y, "opening branches are stacked like the full research tree")
	_check(game.upgrade_tree.node_buttons["long_exposure"].visible and game.upgrade_tree.node_buttons["long_exposure"].get_meta("visual_state") == "teaser", "one upcoming system is previewed as an unresolved signal")
	_check(opening_optics.size.x <= 104.0 and opening_optics.size.y <= 82.0, "research nodes use compact icon-first tiles")
	_check(game.upgrade_tree.detail_panel.visible and game.upgrade_tree.selected_node_id == "better_lens", "fixed inspector defaults to the first actionable system")
	game.upgrade_tree._on_node_hovered("edge_detection")
	_check(game.upgrade_tree.selected_node_id == "edge_detection", "hovering a node updates the fixed inspector")
	game.upgrade_tree._on_node_unhovered("better_lens")
	_check(game.upgrade_tree.detail_panel.visible and game.upgrade_tree.selected_node_id == "edge_detection", "fixed inspector remains readable after the pointer leaves a node")
	game.progression.add_debug_data(12.0)
	var upgrades_before_selection: int = int(game.progression.upgrade_level)
	game.upgrade_tree._on_node_hold_started("better_lens")
	game.upgrade_tree._process(game.upgrade_tree.HOLD_PURCHASE_SECONDS * 0.45)
	var partial_hold_bar = game.upgrade_tree.node_hold_bars["better_lens"]
	_check(partial_hold_bar.size.y >= opening_optics.size.y - 1.0 and partial_hold_bar.fill_ratio > 0.0 and partial_hold_bar.fill_ratio < 1.0, "node installation draws a partial liquid fill across the full tile")
	_check(game.progression.upgrade_level == upgrades_before_selection and partial_hold_bar.visible, "holding an affordable node fills it without purchasing early")
	game.upgrade_tree._on_node_hold_released("better_lens")
	_check(game.progression.upgrade_level == upgrades_before_selection and not partial_hold_bar.visible, "releasing a node before the meter fills cancels installation")
	game.upgrade_tree._on_node_hold_started("better_lens")
	game.upgrade_tree._process(game.upgrade_tree.HOLD_PURCHASE_SECONDS + 0.01)
	_check(game.progression.has_upgrade("better_lens") and game.upgrade_tree.held_node_id.is_empty(), "a full node hold purchases the system exactly once")
	game.progression.reset()
	var zoom_before_button: float = float(game.upgrade_tree.zoom)
	game.upgrade_tree._zoom_from_center(1.10)
	_check(game.upgrade_tree.zoom > zoom_before_button, "explicit zoom controls change the research-tree scale")
	game.upgrade_tree._reset_view()
	var pan_before_left_drag: Vector2 = game.upgrade_tree.pan_position
	var left_down := InputEventMouseButton.new()
	left_down.button_index = MOUSE_BUTTON_LEFT
	left_down.pressed = true
	game.upgrade_tree._on_tree_viewport_gui_input(left_down)
	var left_drag := InputEventMouseMotion.new()
	left_drag.relative = Vector2(23.0, -11.0)
	game.upgrade_tree._on_tree_viewport_gui_input(left_drag)
	var left_up := InputEventMouseButton.new()
	left_up.button_index = MOUSE_BUTTON_LEFT
	left_up.pressed = false
	game.upgrade_tree._on_tree_viewport_gui_input(left_up)
	_check(game.upgrade_tree.pan_position == pan_before_left_drag + left_drag.relative and not game.upgrade_tree.panning, "left-dragging empty space pans the research tree and releases cleanly")
	game.upgrade_tree.close_tree()
	_check(not paused, "closing the upgrade tree resumes gameplay")

	# A cursor that crosses a meteor entirely between two rendered frames must
	# still acquire it instead of tunnelling through the point-sampled hit area.
	var sweep_target = game.spawner.spawn_meteor("common", Vector2(500, 220), Vector2.ZERO, 3.0)
	game.observer.previous_cursor_position = Vector2(250, 220)
	game.observer.cursor_position = Vector2(750, 220)
	var swept_acquisition = game.observer._find_target_under_cursor()
	_check(swept_acquisition == sweep_target, "fast cursor sweep acquires a crossed meteor")
	sweep_target.queue_free()
	await process_frame

	# Manual tracking begins as a single-target action, then becomes an area
	# observation after Multi-Target Analysis comes online.
	var solo_target_a = game.spawner.spawn_meteor("common", Vector2(450, 220), Vector2.ZERO, 3.0)
	var solo_target_b = game.spawner.spawn_meteor("common", Vector2(470, 220), Vector2.ZERO, 3.0)
	game.observer.cursor_position = Vector2(460, 220)
	game.observer.previous_cursor_position = game.observer.cursor_position
	game.observer.selected_meteor = null
	game.observer._update_manual_tracking(0.18)
	var solo_progress_count := int(solo_target_a.get_progress() > 0.0) + int(solo_target_b.get_progress() > 0.0)
	_check(solo_progress_count == 1, "manual tracking remains single-target before Multi-Target Analysis")
	game.observer.reset()
	solo_target_a.queue_free()
	solo_target_b.queue_free()
	await process_frame

	game.progression.purchased_nodes["multi_target_analysis"] = true
	var group_target_a = game.spawner.spawn_meteor("common", Vector2(450, 220), Vector2.ZERO, 3.0)
	var group_target_b = game.spawner.spawn_meteor("common", Vector2(470, 220), Vector2.ZERO, 3.0)
	game.observer.cursor_position = Vector2(460, 220)
	game.observer.previous_cursor_position = game.observer.cursor_position
	game.observer.selected_meteor = null
	game.observer._update_manual_tracking(0.18)
	_check(group_target_a.get_progress() > 0.0 and group_target_b.get_progress() > 0.0, "Multi-Target Analysis advances every meteor inside the tracking field")
	_check(game.observer._valid_tracked_count() == 2, "group observation retains individual target rings")
	game.hud.set_tracking(0.4, "common", 1.0, game.observer._valid_tracked_count())
	_check("×2" in game.hud.tracking_name.text, "tracking HUD reports the simultaneous target count")
	game.progression.purchased_nodes.erase("multi_target_analysis")
	game.observer.reset()
	group_target_a.queue_free()
	group_target_b.queue_free()
	await process_frame

	# Exercise the real meteor observation path without relying on an OS cursor.
	_check(is_equal_approx(game.observer._software_cursor_radius(), 36.0), "software cursor starts at the real observation radius")
	var meteor = game.spawner.spawn_meteor("common", Vector2(420, 220), Vector2(20, 5), 3.0)
	meteor.apply_manual_observation(1.0, 0.0, game.progression.get_tracking_radius())
	await process_frame
	await process_frame
	_check(game.progression.success_count == 1, "manual tracking completes an observation")
	_check(game.progression.observation_data >= 14.0, "observation awards data")
	_check(game.progression.request_purchase("better_lens"), "first observation can buy Better Lens through the tree controller")
	_check(game.progression.get_tracking_radius() > 36.0, "Better Lens changes the hit radius")
	_check(is_equal_approx(game.observer._software_cursor_radius(), game.progression.get_tracking_radius()), "software cursor expands with Better Lens")
	_check(game.hud.array_progress_bar.value == 1.0, "array completion meter advances with purchases")
	_check(game.progression.get_node_state("long_exposure") == "available", "purchasing a node reveals its adjacent child")
	game.upgrade_tree.open_tree()
	await process_frame
	_check(game.upgrade_tree.node_buttons["better_lens"].position == initial_tree_positions["better_lens"] and game.upgrade_tree.node_buttons["edge_detection"].position == initial_tree_positions["edge_detection"] and game.upgrade_tree.node_buttons["array_planning"].position == initial_tree_positions["array_planning"], "purchasing a system never rearranges the research tree")
	game.upgrade_tree.close_tree()
	var data_after_better_lens: float = game.progression.observation_data
	_check(not game.progression.request_purchase("better_lens"), "a purchased node cannot be bought twice")
	_check(game.progression.observation_data == data_after_better_lens, "duplicate purchase cannot deduct Data")
	game.elapsed_time = 73.0
	game.observation_round = 3
	game.observation_phase_remaining = 17.0
	game.hud.set_observation_phase(3, 17.0)
	var saved_observation_data: float = game.progression.observation_data
	var save_error: Error = game.save_games.save_slot(1, game._build_save_data())
	_check(save_error == OK, "slot 1 save is written")
	_check(game.save_games.has_slot(1), "slot 1 becomes loadable")
	_check(not game.save_games.has_slot(2) and not game.save_games.has_slot(3), "the other two slots remain independent")
	var slot_summary: Dictionary = game.save_games.get_slot_summary(1)
	_check(int(slot_summary.elapsed_time) == 73, "slot summary stores run time")
	_check(int(slot_summary.upgrade_level) == 1, "slot summary stores upgrade count")
	_check(not game.hud.load_slot_buttons[0].disabled, "saved slot enables its load button")
	game.progression.reset()
	game.elapsed_time = 0.0
	game._apply_save_data(game.save_games.load_slot(1))
	await process_frame
	_check(absf(game.elapsed_time - 73.0) < 0.1, "loading restores run time")
	_check(game.observation_round == 3 and absf(game.observation_phase_remaining - 17.0) < 0.1, "loading restores the current round and countdown")
	_check(is_equal_approx(game.progression.observation_data, saved_observation_data), "loading restores Observation Data")
	_check(game.progression.has_upgrade("better_lens"), "loading restores purchased upgrades")
	_check(game.progression.success_count == 1, "loading restores observation statistics")

	game.progression.debug_purchase_all()
	_check(game.progression.upgrade_level == 19, "all tree nodes unlock through prerequisite-safe debug purchase")
	_check(game.progression.get_max_active() == 6, "research raises dense-sky capacity without removing the six-target performance cap")
	_check(game.hud.array_progress_bar.value == 19.0, "compact HUD resolves to full array completion")
	for legacy_id in ["better_lens", "long_exposure", "wide_field", "trajectory", "precision_multiplier", "secondary_camera", "shower_detector", "automated_tracking"]:
		_check(game.progression.has_upgrade(legacy_id), "legacy upgrade migrated: " + legacy_id)
	_check(game.progression.has_upgrade("automated_tracking"), "final automation system is active")
	_check(game.progression.get_secondary_slots() == 3, "observatory network provides three assistance lanes")
	_check(game.progression.get_automation_strength("fireball") == 0.0, "rare fireballs remain manual high-value targets")
	_check(game.progression.get_node_state("perfect_observation") == "purchased", "cross-branch Perfect Observation resolves")
	_check(game.progression.get_node_state("observatory_network") == "purchased", "cross-branch Observatory Network resolves")
	for duration_node in ["observation_scheduling", "thermal_management", "extended_watch_protocol"]:
		_check(game.progression.has_upgrade(duration_node), "observation-duration research resolves: " + duration_node)
	game.upgrade_tree.open_tree()
	await process_frame
	_check(game.upgrade_tree.node_buttons["observation_scheduling"].visible, "Observation Scheduling appears in the completed research tree")
	_check(game.upgrade_tree.node_buttons["thermal_management"].visible, "Equipment Thermal Control appears in the completed research tree")
	_check(game.upgrade_tree.node_buttons["extended_watch_protocol"].visible, "Extended Watch Protocol appears in the completed research tree")
	_check(game.upgrade_tree.node_buttons["observation_scheduling"].position.y < game.upgrade_tree.node_buttons["secondary_camera"].position.y, "duration research uses a separate network-tree lane")
	game.upgrade_tree.close_tree()
	_check(not game.hud.root_control.has_node("UpgradePanel"), "legacy upgrade purchase panel is absent")
	_check(not game.hud.root_control.has_node("UpgradeTreeLauncher"), "live playfield has no persistent upgrade entry")

	var best_multiplier_before_quality_test: float = game.progression.best_multiplier
	var quality_target = game.spawner.spawn_meteor("common", Vector2(520, 240), Vector2.ZERO, 3.0)
	quality_target.apply_manual_observation(1.0, 0.0, game.progression.get_tracking_radius())
	await process_frame
	await process_frame
	_check(game.progression.best_multiplier > maxf(2.0, best_multiplier_before_quality_test), "Perfect Observation rewards accurate manual tracking")

	# Expired targets must be released by the observation controller.
	var short_lived = game.spawner.spawn_meteor("fast", Vector2(300, 180), Vector2(0, 0), 0.001)
	game.observer.selected_meteor = short_lived
	await process_frame
	await process_frame
	_check(game.observer.selected_meteor == null, "expired target does not leave a stale tracking reference")

	game.events.trigger_shower()
	_check(game.events.shower_state == "warning", "shower begins with a warning state")
	_check(game.effects.incoming_markers.size() >= 4, "Observatory Network previews shower entry sectors")
	game.events.shower_timer = -1.0
	await process_frame
	_check(game.events.shower_state == "active", "shower enters the active state")
	game.events.shower_timer = -1.0
	await process_frame
	_check(game.events.shower_state == "idle", "shower terminates cleanly")

	game.events.trigger_final()
	game.events.trigger_final()
	game.events.final_timer = -1.0
	await process_frame
	var major_count := 0
	for child in game.meteor_layer.get_children():
		if child.has_method("is_major") and child.is_major():
			major_count += 1
	_check(major_count == 1, "final event spawns exactly one Major Fireball")
	game.events.trigger_final()
	await process_frame
	var major_count_after := 0
	for child in game.meteor_layer.get_children():
		if child.has_method("is_major") and child.is_major():
			major_count_after += 1
	_check(major_count_after == 1, "final event cannot be triggered twice")

	game.reset_run()
	await process_frame
	await process_frame
	var reset_state: Dictionary = game.get_debug_snapshot()
	_check(reset_state.data == 0.0, "reset clears Observation Data")
	_check(reset_state.successes == 0, "reset clears observation count")
	_check(reset_state.upgrade_level == 0, "reset clears progression")
	_check(reset_state.purchased_nodes.is_empty(), "reset clears purchased tree node state")
	_check(reset_state.shower_state == "idle", "reset clears shower state")
	_check(not reset_state.final_started, "reset makes the final event available again")
	_check(reset_state.observation_round == 1 and reset_state.observation_phase_active, "reset returns to the first observation round")
	_check(absf(float(reset_state.observation_phase_remaining) - 30.0) < 1.0, "reset restores the 30-second opening round")
	_check(game._observation_duration() == 30.0, "round number alone does not increase observation time")
	game.progression.success_count = 4
	game.progression.manual_successes = 3
	game.progression.automatic_successes = 1
	game.progression.total_data_earned = 55.0
	game.observation_phase_remaining = 0.05
	game.events.shower_state = "active"
	game._process(0.1)
	_check(game.observation_phase_active and not game.upgrade_tree.is_open(), "round expiry waits for an active meteor shower to finish")
	game.events.shower_state = "idle"
	game._process(0.0)
	_check(not game.observation_phase_active and game.hud.is_phase_summary_open() and not game.upgrade_tree.is_open() and paused, "round expiry pauses the sky and opens a concise phase summary")
	_check(game.hud.phase_summary_observations.text.ends_with("4"), "phase summary reports observations from the completed phase")
	_check(game.hud.phase_summary_data.text.ends_with("+55"), "phase summary reports Data earned during the completed phase")
	_check(game.hud.phase_summary_split.text == TranslationServer.translate("PHASE_SUMMARY_MANUAL_AUTO") % [3, 1], "phase summary separates manual and automatic observations")
	_check(game.upgrade_tree.intermission_next_round == 2 and game.upgrade_tree.intermission_next_duration == 30, "upgrade break keeps the next round at 30 seconds without research")
	game.hud._on_phase_summary_continue_pressed()
	_check(not game.hud.is_phase_summary_open() and game.upgrade_tree.is_open() and paused, "one summary action opens the research phase")
	_check(game.upgrade_tree.close_button.text == TranslationServer.translate("TREE_START_OBSERVATION"), "upgrade break close action is labeled as starting observation")
	game.upgrade_tree.close_tree()
	_check(not paused and game.observation_phase_active and game.observation_round == 2, "closing the upgrade tree starts round 2")
	_check(absf(game.observation_phase_remaining - 30.0) < 0.1, "round 2 remains 30 seconds without duration research")
	_check(game.progression.debug_purchase_node("array_planning"), "Array Planning can open the duration research path")
	_check(game.progression.debug_purchase_node("observation_scheduling"), "Observation Scheduling can be researched")
	_check(game._observation_duration() == 40.0, "Observation Scheduling adds 10 seconds")
	_check(absf(game.observation_phase_remaining - 30.0) < 0.1, "duration research does not alter the observation already in progress")
	game._end_observation_phase()
	_check(game.upgrade_tree.intermission_next_duration == 40, "the next upgrade break previews the researched 40-second window")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	_check(game.observation_round == 3 and absf(game.observation_phase_remaining - 40.0) < 0.1, "the researched duration applies to the next observation")
	_check(game.progression.debug_purchase_node("edge_detection"), "duration path can satisfy Edge Detection prerequisite")
	_check(game.progression.debug_purchase_node("wide_field"), "duration path can satisfy Wide Field prerequisite")
	_check(game.progression.debug_purchase_node("thermal_management"), "Equipment Thermal Control can be researched")
	_check(game._observation_duration() == 50.0, "Equipment Thermal Control adds a second 10 seconds")
	_check(game.progression.debug_purchase_node("trajectory"), "duration path can satisfy Trajectory Prediction prerequisite")
	_check(game.progression.debug_purchase_node("extended_watch_protocol"), "Extended Watch Protocol can be researched")
	_check(game._observation_duration() == 60.0, "Extended Watch Protocol reaches the 60-second maximum")
	game._end_observation_phase()
	_check(game.upgrade_tree.intermission_next_duration == 60, "upgrade break previews the maximum researched duration")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	_check(game.observation_round == 4 and absf(game.observation_phase_remaining - 60.0) < 0.1, "the maximum duration applies to the following observation")
	game.reset_run()
	await process_frame
	await process_frame

	# Render-heavy resources must stay bounded even when event and fragment paths
	# bypass the normal progression-driven active-meteor limit.
	game.spawner.pause_regular_spawns = true
	var material_meteor_a = game.spawner.spawn_meteor("common", Vector2(360, 180), Vector2.ZERO, 30.0)
	var material_meteor_b = game.spawner.spawn_meteor("common", Vector2(420, 180), Vector2.ZERO, 30.0)
	await process_frame
	var material_pair_ready := material_meteor_a != null and material_meteor_b != null
	_check(material_pair_ready, "material-sharing regression setup spawns two meteors")
	if material_pair_ready:
		_check(
			material_meteor_a.material != null and material_meteor_a.material == material_meteor_b.material,
			"meteor instances reuse one shared additive material"
		)
	game.spawner.reset()
	await process_frame
	await process_frame

	var spawner_constants: Dictionary = game.spawner.get_script().get_script_constant_map()
	var has_total_meteor_cap := spawner_constants.has("MAX_TOTAL_METEORS")
	_check(has_total_meteor_cap, "meteor spawner exposes a global MAX_TOTAL_METEORS cap")
	if has_total_meteor_cap:
		var total_meteor_cap := int(spawner_constants["MAX_TOTAL_METEORS"])
		_check(total_meteor_cap > 1, "global meteor cap leaves room for ordinary and major targets")
		if total_meteor_cap > 1:
			for index in range(total_meteor_cap + 6):
				game.spawner.spawn_for_shower(index)
			game.spawner.spawn_major_fireball()
			game.spawner._on_fragment_requested(Vector2(480, 220), Vector2(80, 0), "major")
			_check(
				game.meteor_layer.get_child_count() <= total_meteor_cap,
				"shower, major, and fragment spawn paths respect the global meteor cap"
			)
	game.spawner.reset()
	await process_frame
	await process_frame

	var effect_constants: Dictionary = game.effects.get_script().get_script_constant_map()
	var has_effect_caps := (
		effect_constants.has("MAX_PARTICLES")
		and effect_constants.has("MAX_POPUPS")
		and effect_constants.has("MAX_INCOMING_MARKERS")
	)
	_check(has_effect_caps, "effects layer exposes particle, popup, and incoming-marker caps")
	if has_effect_caps:
		var max_particles := int(effect_constants["MAX_PARTICLES"])
		var max_popups := int(effect_constants["MAX_POPUPS"])
		var max_incoming_markers := int(effect_constants["MAX_INCOMING_MARKERS"])
		var positive_effect_caps := max_particles > 0 and max_popups > 0 and max_incoming_markers > 0
		_check(positive_effect_caps, "effect caps are positive")
		if positive_effect_caps:
			var success_bursts := maxi(max_popups + 3, int(ceil(float(max_particles) / 18.0)) + 3)
			for index in range(success_bursts):
				game.effects.spawn_success(Vector2(500, 250), 10.0, Color.WHITE, 1.0)
			_check(game.effects.particles.size() <= max_particles, "success particles stay within MAX_PARTICLES")
			_check(game.effects.popups.size() <= max_popups, "success popups stay within MAX_POPUPS")
			for index in range(max_incoming_markers + 4):
				game.effects.spawn_incoming(Vector2(80 + index, 80), Vector2.RIGHT, Color.WHITE)
			_check(
				game.effects.incoming_markers.size() <= max_incoming_markers,
				"individual incoming warnings stay within MAX_INCOMING_MARKERS"
			)
			game.effects.reset()
			var forecast_points: Array[Vector2] = []
			for index in range(max_incoming_markers + 4):
				forecast_points.append(Vector2(100 + index, 100))
			game.effects.spawn_forecast(forecast_points)
			_check(
				game.effects.incoming_markers.size() <= max_incoming_markers,
				"forecast batches stay within MAX_INCOMING_MARKERS"
			)
	game.effects.reset()

	# Let short procedural audio voices and delayed chord tones release cleanly.
	await create_timer(0.85).timeout
	_cleanup_smoke_saves(smoke_save_directory)
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("SMOKE_TEST_PASS: tutorial, saves, localization, phase summary, compact HUD, observation, progression, events, performance caps, stale references, and reset")
		quit(0)
	else:
		print("SMOKE_TEST_FAIL: %d failure(s)" % failures.size())
		for failure in failures:
			print(" - " + failure)
		quit(1)


func _decorative_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _decorative_controls_ignore_mouse(child):
			return false
	return true


func _cleanup_smoke_saves(directory: String) -> void:
	var absolute_directory := ProjectSettings.globalize_path(directory)
	for slot in range(1, 4):
		var slot_path := absolute_directory.path_join("slot_%d.cfg" % slot)
		if FileAccess.file_exists(slot_path):
			DirAccess.remove_absolute(slot_path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)
