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
	var balance = load("res://scripts/game_balance.gd")
	var secondary_camera_definition: Dictionary = balance.upgrade_definition("secondary_camera")
	var predictive_control_definition: Dictionary = balance.upgrade_definition("predictive_dish_control")
	var multi_target_definition: Dictionary = balance.upgrade_definition("multi_target_analysis")
	var observatory_definition: Dictionary = balance.upgrade_definition("observatory_network")
	game.settings.set_language("ko", false)
	await process_frame
	_check(TranslationServer.get_locale().left(2) == "ko", "Korean locale activates through game settings")
	_check("설정" in game.hud.settings_button.text, "HUD refreshes with Korean text")
	_check(game.upgrade_tree.title_label.text == "관측망", "upgrade tree refreshes with Korean text")
	_check(TranslationServer.translate("CONSTELLATION_CASSIOPEIA") == "카시오페이아자리  /  광학", "research chart localizes constellation branch labels")
	_check(TranslationServer.translate("STAR_TSIH") == "감마 카시오페이아", "research inspector uses the factual Tsih star name in Korean")
	_check(TranslationServer.translate("HUD_AUTOSAVED") == "자동 저장됨", "Korean autosave status stays concise")
	_check(TranslationServer.translate("HUD_OBSERVATION_TIME") % [1, 1, 0] == "1차 관측  •  01:00", "Korean round countdown reads naturally")
	_check(TranslationServer.translate("TREE_INTERMISSION_SUBTITLE") % [2, 30] == "업그레이드 시간  /  2차 관측은 30초", "Korean upgrade-break guidance explains the next round and duration")
	_check(TranslationServer.translate("PHASE_SUMMARY_TITLE") % 1 == "1차 관측 완료", "Korean phase summary title reads naturally")
	_check(TranslationServer.translate("PHASE_SUMMARY_SYSTEMS_CHANGED") % 130.0 == "실현 처리량 130.0 데이터/분  •  시스템 변경  •  다음 라운드에서 새 기준 기록", "Korean mixed-build summary explains realized productivity and the next baseline")
	_check(TranslationServer.translate("CONTACT_COMMIT_HINT") == "Shift+우클릭: 접시 예약", "Korean predictive-control hint teaches its separate gesture")
	_check(TranslationServer.translate("CONTACT_MANUAL_ONLY_HINT") == "수동 관측 전용", "Korean rare-contact hint reserves the target for manual observation")
	_check(
		game.upgrade_tree._upgrade_description(predictive_control_definition)
		== "예보 신호를 Shift+우클릭하면 접시를 예약해 천체 진입 시 표적을 자동으로 인계합니다.",
		"Korean Predictive Dish Control description explains reservation and handoff"
	)
	_check(
		game.upgrade_tree._upgrade_description(multi_target_definition)
		== "수동 관측 범위 안의 모든 유성을 함께 분석합니다. 진행 중인 분석을 가속하는 지원 카메라 채널 하나와 파편 분석 지원도 추가합니다.",
		"Korean Multi-Target Analysis description names one support lane"
	)
	_check(
		game.upgrade_tree._upgrade_description(observatory_definition)
		== "전체 관측망을 연결해 유성우 진입 구역을 예측하고 직접 조준하는 두 번째 접시를 추가하며 진행 중인 분석을 가속하는 지원 카메라 채널 두 개를 유지합니다.",
		"Korean Observatory Network description names the second dish and two support lanes"
	)
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
	_check(TranslationServer.translate("CONTACT_COMMIT_HINT") == "SHIFT+RIGHT-CLICK: COMMIT DISH", "English predictive-control hint teaches its separate gesture")
	_check(TranslationServer.translate("CONTACT_MANUAL_ONLY_HINT") == "MANUAL OBSERVATION ONLY", "English rare-contact hint reserves the target for manual observation")
	_check(
		game.upgrade_tree._upgrade_description(predictive_control_definition)
		== "Shift-right-click a forecast contact to reserve a dish and hand it directly to the object on entry.",
		"English Predictive Dish Control description explains reservation and handoff"
	)
	_check(
		game.upgrade_tree._upgrade_description(multi_target_definition)
		== "All meteors inside the manual tracking field advance together; also adds one support camera lane that accelerates active analysis and fragment assistance.",
		"English Multi-Target Analysis description names one support lane"
	)
	_check(
		game.upgrade_tree._upgrade_description(observatory_definition)
		== "Links the whole array; previews shower entry sectors; adds a second steerable dish; and keeps two support camera lanes that accelerate active analysis.",
		"English Observatory Network description names the second dish and two support lanes"
	)
	_check(
		String(secondary_camera_definition.description)
		== game.upgrade_tree._upgrade_description(secondary_camera_definition),
		"Secondary Camera fallback description stays in sync with rendered localization"
	)
	_check(
		String(predictive_control_definition.description)
		== game.upgrade_tree._upgrade_description(predictive_control_definition),
		"Predictive Dish Control fallback description stays in sync with rendered localization"
	)
	_check(
		String(multi_target_definition.description)
		== game.upgrade_tree._upgrade_description(multi_target_definition),
		"Multi-Target Analysis fallback description stays in sync with rendered localization"
	)
	_check(
		String(observatory_definition.description)
		== game.upgrade_tree._upgrade_description(observatory_definition),
		"Observatory Network fallback description stays in sync with rendered localization"
	)
	game.settings.set_language(starting_locale, false)
	await process_frame

	var initial: Dictionary = game.get_debug_snapshot()
	_check(initial.upgrade_level == 0, "run begins with no upgrades")
	_check(initial.successes == 0, "run begins with no observations")
	_check(not initial.final_started, "final event is initially inactive")
	_check(initial.observation_round == 1 and initial.observation_phase_active, "run begins in observation round 1")
	_check(absf(float(initial.observation_phase_remaining) - 20.0) < 1.0, "first observation round starts at 20 seconds")
	_check(game.progression.get_max_active() == 4, "the opening sky supports four concurrent targets so attention starts scarce")
	_check(balance.FIRST_METEOR_DELAY <= 2.0, "the opening meteor arrives before the sky feels empty")
	_check(balance.REGULAR_SPAWN_INTERVAL_MIN == 1.6 and balance.REGULAR_SPAWN_INTERVAL_MAX == 2.4, "regular spawn cadence keeps multiple choices in flight")
	_check(game.progression.get_available_nodes().size() == 3, "only three opening choices are revealed")
	_check(game.hud.array_progress_bar.max_value == 21.0, "HUD exposes the full 21-system completion goal")
	_check(game.hud.top_panel.size.x <= 510.0, "live HUD stays compact after removing secondary progression copy")
	_check(game.progression.get_node_state("long_exposure") == "hidden", "adjacent optics node begins hidden")
	_check(not balance.upgrade_definition("observation_scheduling").is_empty(), "duration research is present in the tree")
	_check(int(balance.upgrade_definition("observation_scheduling").cost) == 60, "the mandatory first duration gate stays inexpensive")
	_check(int(balance.upgrade_definition("thermal_management").cost) == 180, "the second duration step uses its measured price")
	_check(int(balance.upgrade_definition("extended_watch_protocol").cost) == 280, "the third duration step uses its measured price")
	_check(int(balance.upgrade_definition("continuous_watch_rotation").cost) == 380, "the fourth duration step uses its measured price")
	_check("observation_scheduling" in balance.upgrade_definition("wide_field").prerequisites, "Wide Field requires Observation Scheduling")
	_check(balance.upgrade_definition("thermal_management").prerequisites == ["wide_field"], "Thermal Management relies on Wide Field without a redundant edge")
	_check(balance.upgrade_definition("continuous_watch_rotation").prerequisites == ["extended_watch_protocol", "rare_detection"], "Continuous Watch Rotation closes the duration/detection alternation")
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
	var chart_data = load("res://scripts/research_chart_data.gd")
	var expected_chart_node_ids: Array[String] = []
	for definition in balance.UPGRADE_NODES:
		expected_chart_node_ids.append(String(definition.id))
	var chart_validation_errors: Array[String] = chart_data.validation_errors(expected_chart_node_ids)
	_check(chart_validation_errors.is_empty(), "research chart maps every upgrade exactly once with valid constellation segments")
	var chart_node_stars: Dictionary = chart_data.node_star_map()
	var adjacent_internal_edges := true
	for definition in balance.UPGRADE_NODES:
		var target_node_id := String(definition.id)
		var target_location: Dictionary = chart_node_stars[target_node_id]
		for prerequisite_variant in definition.prerequisites:
			var prerequisite_node_id := String(prerequisite_variant)
			var prerequisite_location: Dictionary = chart_node_stars[prerequisite_node_id]
			if String(prerequisite_location.constellation_id) != String(target_location.constellation_id):
				continue
			var constellation: Dictionary = chart_data.CONSTELLATIONS[target_location.constellation_id]
			var prerequisite_star_id := String(prerequisite_location.star.id)
			var target_star_id := String(target_location.star.id)
			var edge_matches_segment := false
			for segment_variant in constellation.segments:
				var segment: Array = segment_variant
				if (String(segment[0]) == prerequisite_star_id and String(segment[1]) == target_star_id) or (String(segment[1]) == prerequisite_star_id and String(segment[0]) == target_star_id):
					edge_matches_segment = true
					break
			if not edge_matches_segment:
				adjacent_internal_edges = false
	_check(adjacent_internal_edges, "same-constellation prerequisites follow declared figure segments instead of cutting across them")
	_check(opening_optics.position != opening_detection.position and opening_detection.position != opening_network.position, "opening research nodes occupy distinct constellation positions")
	var optics_center_before := opening_optics.position + opening_optics.size * 0.5
	var optics_radius_before := optics_center_before.distance_to(game.upgrade_tree.CHART_ORIGIN)
	game.upgrade_tree._rotate_chart(game.upgrade_tree.ROTATION_STEP)
	var optics_center_after := opening_optics.position + opening_optics.size * 0.5
	_check(is_equal_approx(optics_radius_before, optics_center_after.distance_to(game.upgrade_tree.CHART_ORIGIN)), "mouse-wheel chart rotation preserves each star's polar radius")
	_check(absf((optics_center_before - game.upgrade_tree.CHART_ORIGIN).angle_to(optics_center_after - game.upgrade_tree.CHART_ORIGIN) - game.upgrade_tree.ROTATION_STEP) < 0.001, "research chart rotation changes only the global polar angle")
	game.upgrade_tree._reset_view()
	_check(is_zero_approx(game.upgrade_tree.rotation_offset), "research chart reset returns to north")
	_check(game.upgrade_tree.node_buttons["long_exposure"].visible and game.upgrade_tree.node_buttons["long_exposure"].get_meta("visual_state") == "teaser", "one upcoming system is previewed as an unresolved signal")
	_check(opening_optics.size == game.upgrade_tree.STAR_HIT_SIZE, "research stars use compact transparent point hit targets")
	_check(game.upgrade_tree.detail_panel.visible and game.upgrade_tree.selected_node_id == "better_lens", "fixed inspector defaults to the first actionable system")
	_check("α Cas" in game.upgrade_tree.detail_star.text, "research inspector identifies the real star behind the selected system")
	game.upgrade_tree._on_node_hovered("edge_detection")
	_check(game.upgrade_tree.selected_node_id == "edge_detection", "hovering a node updates the fixed inspector")
	game.upgrade_tree._on_node_unhovered("better_lens")
	_check(game.upgrade_tree.detail_panel.visible and game.upgrade_tree.selected_node_id == "edge_detection", "fixed inspector remains readable after the pointer leaves a node")
	game.progression.add_debug_data(12.0)
	var upgrades_before_selection: int = int(game.progression.upgrade_level)
	game.upgrade_tree._on_node_hold_started("better_lens")
	game.upgrade_tree._process(game.upgrade_tree.HOLD_PURCHASE_SECONDS * 0.45)
	var partial_hold_bar = game.upgrade_tree.node_hold_bars["better_lens"]
	_check(partial_hold_bar.size == opening_optics.size and partial_hold_bar.hold_ratio > 0.0 and partial_hold_bar.hold_ratio < 1.0, "node installation draws a partial radial arc around the star")
	_check(game.progression.upgrade_level == upgrades_before_selection, "holding an affordable star advances its arc without purchasing early")
	game.upgrade_tree._on_node_hold_released("better_lens")
	_check(game.progression.upgrade_level == upgrades_before_selection and is_zero_approx(partial_hold_bar.hold_ratio), "releasing a star before the arc completes cancels installation")
	game.upgrade_tree._on_node_hold_started("better_lens")
	game.upgrade_tree._process(game.upgrade_tree.HOLD_PURCHASE_SECONDS + 0.01)
	_check(game.progression.has_upgrade("better_lens") and game.upgrade_tree.held_node_id.is_empty(), "a full node hold purchases the system exactly once")
	_check(partial_hold_bar.visual_state == "purchased", "purchasing research turns its mapped star fully bright")
	var first_frontier: Array[PackedStringArray] = game.upgrade_tree._frontier_connections()
	_check(PackedStringArray(["better_lens", "long_exposure"]) in first_frontier and PackedStringArray(["better_lens", "observation_streak"]) in first_frontier, "a purchased star lights connections to its newly available frontier")
	game.progression.reset()
	var zoom_before_button: float = float(game.upgrade_tree.zoom)
	game.upgrade_tree._zoom_from_center(1.10)
	_check(game.upgrade_tree.zoom > zoom_before_button, "explicit zoom controls change the research-tree scale")
	game.upgrade_tree._reset_view()
	var rotation_before_ctrl_wheel: float = game.upgrade_tree.rotation_offset
	var zoom_before_ctrl_wheel: float = game.upgrade_tree.zoom
	var ctrl_wheel := InputEventMouseButton.new()
	ctrl_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	ctrl_wheel.pressed = true
	ctrl_wheel.ctrl_pressed = true
	ctrl_wheel.position = game.upgrade_tree.content_clip.global_position + game.upgrade_tree.content_clip.size * 0.5
	game.upgrade_tree._on_tree_viewport_gui_input(ctrl_wheel)
	_check(is_equal_approx(game.upgrade_tree.rotation_offset, rotation_before_ctrl_wheel) and game.upgrade_tree.zoom > zoom_before_ctrl_wheel, "Ctrl+wheel zooms the research chart without rotating it")
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
	game.last_clean_round_result = {
		"round": 2,
		"duration": 20.0,
		"data": 42,
		"rate": 126.0,
		"observations": 3,
		"manual": 2,
		"automatic": 1,
		"systems_installed": 0,
		"systems_since_baseline": [],
		"shower": false,
		"build_changed": false,
		"build_signature": [],
	}
	game.best_round_rate = 153.0
	game.phase_had_shower = true
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
	_check(game.phase_resumed_from_save and game.phase_had_shower, "loading marks the reset-sky sample as resumed and restores its shower context")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 126.0) and is_equal_approx(game.best_round_rate, 153.0), "clean-round rate history and best realized rate survive save/load")

	_check(not game.spawner.forecast_enabled(), "objects arrive unannounced before forecast research")
	_check(not game.progression.forecast_visible(), "the opening array has no forecast feed")
	_check(not game.progression.dish_active(), "the opening array has no player-aimed dish")
	_check(game.progression.get_forecast_lead() == 2.0, "a forecast without dish hardware uses the two-second cursor warning")
	_check(game.progression.get_forecast_max_error() == 70.0, "baseline forecasts expose a seventy-pixel uncertainty envelope")
	_check(not game.progression.forecast_classifies(), "baseline forecasts do not classify contacts")
	game.progression.debug_purchase_node("edge_detection")
	_check(game.progression.get_node_state("wide_field") == "locked", "Wide Field cannot bypass its mandatory duration gate")
	game.progression.debug_purchase_node("array_planning")
	game.progression.debug_purchase_node("observation_scheduling")
	_check(game.progression.get_node_state("wide_field") == "available", "Observation Scheduling opens the Wide Field path")
	game.progression.debug_purchase_node("wide_field")
	game.sky_contacts.refresh_dishes()
	_check(game.spawner.forecast_enabled(), "Wide Field Sensor reveals incoming contacts")
	_check(game.sky_contacts.forecast_visible() and not game.sky_contacts.dish_active(), "Wide Field Sensor reveals contacts without adding hardware")

	game.spawner.pending_contacts.clear()
	game.sky_contacts.contacts.clear()
	game.spawner.rng.seed = 10101
	game.spawner.forecast_rng.seed = 20202
	game.spawner.warm_contact_rng.seed = 30303
	game.spawner.set_phase_time_remaining(game.progression.get_forecast_lead() + game.spawner.MINIMUM_PAYABLE_TRACK_TIME - 0.01)
	game.spawner._announce_regular_spawn()
	_check(game.spawner.pending_contacts.is_empty(), "a contact is not announced when the phase cannot honor its forecast")
	var shower_count_before_cutoff: int = game.meteor_layer.get_child_count()
	game.spawner.spawn_for_shower(0)
	_check(game.meteor_layer.get_child_count() == shower_count_before_cutoff + 1, "the regular-contact cutoff does not suppress shower objects")
	game.meteor_layer.get_child(game.meteor_layer.get_child_count() - 1).queue_free()
	await process_frame
	game.spawner.set_phase_time_remaining(30.0)
	game.spawner._announce_regular_spawn()
	_check(game.spawner.pending_contacts.size() == 1, "a wide-field forecast is queued before its object exists")
	var wide_contact: Dictionary = game.spawner.pending_contacts[0]
	_check(game.sky_contacts.contacts.size() == 1, "a wide-field contact is retained without a dish")
	_check(not game.sky_contacts.assign_to_contact(int(wide_contact.id)), "a pre-dish contact remains non-interactive")
	_check(float(wide_contact.lead_time) == 2.0, "Wide Field Sensor provides two seconds of warning")
	_check(float(wide_contact.max_error) == 70.0, "Wide Field Sensor begins with the baseline error envelope")
	_check(not bool(wide_contact.classified), "Wide Field Sensor contacts begin unclassified")
	_check(not bool(wide_contact.trajectory_known), "Wide Field Sensor alone does not reveal the approach vector")

	game.progression.debug_purchase_node("trajectory")
	game.spawner._announce_regular_spawn()
	var trajectory_contact: Dictionary = game.spawner.pending_contacts[1]
	_check(float(trajectory_contact.max_error) < float(wide_contact.max_error), "Trajectory Prediction strictly shrinks forecast error")
	_check(float(trajectory_contact.max_error) == 40.0, "Trajectory Prediction caps the uncertainty envelope at forty pixels")
	_check(trajectory_contact.error_offset.length() >= 14.0 and trajectory_contact.error_offset.length() <= 40.0, "Trajectory Prediction samples offsets inside its upgraded envelope")
	_check(bool(trajectory_contact.trajectory_known), "Trajectory Prediction reveals the contact approach vector")
	_check(not bool(trajectory_contact.classified), "Trajectory Prediction does not classify contacts by itself")

	game.progression.debug_purchase_node("rare_detection")
	game.spawner._announce_regular_spawn()
	var classified_contact: Dictionary = game.spawner.pending_contacts[2]
	_check(bool(classified_contact.classified), "Rare Meteor Detection classifies every forecast deterministically")

	# Secondary Camera remains independently useful through the network branch:
	# it reveals the same feed when Wide Field Sensor is absent and adds the dish.
	game.spawner.pending_contacts.clear()
	game.sky_contacts.reset()
	game.progression.reset()
	game.progression.debug_purchase_node("array_planning")
	game.progression.debug_purchase_node("secondary_camera")
	game.sky_contacts.refresh_dishes()
	_check(not game.progression.has_upgrade("wide_field"), "Secondary Camera compatibility does not depend on the detection branch")
	_check(game.spawner.forecast_enabled(), "the dish research independently turns on the forecast")
	_check(game.sky_contacts.forecast_visible() and game.sky_contacts.dish_active(), "the dish research reveals contacts and enables interaction")
	_check(game.sky_contacts.dishes.size() == 1, "the dish research places one dish")
	_check(game.progression.get_forecast_lead() == 4.0, "dish hardware extends the warning to four seconds for slew time")

	game.spawner.pending_contacts.clear()
	game.sky_contacts.contacts.clear()
	game.spawner._announce_regular_spawn()
	_check(game.spawner.pending_contacts.size() == 1, "a forecast is queued before its object exists")
	var contact: Dictionary = game.spawner.pending_contacts[0]
	_check(float(contact.countdown) == 4.0 and float(contact.lead_time) == 4.0, "a dish contact leads its object by four seconds")
	_check(game.sky_contacts.contacts.size() == 1, "an announced contact reaches the sky array")
	_check(
		game.sky_contacts._estimate_of(contact).distance_to(Vector2(contact.intercept)) > 1.0,
		"an early estimate remains offset even though the current dish footprint contains its full envelope"
	)
	# Plain right-click is one spatial rule at every contact type: move the
	# nearest dish to the clicked point without reserving the contact.
	var pointer_position: Vector2 = game.sky_contacts.get_viewport().get_mouse_position()
	contact.intercept = pointer_position
	contact.error_offset = Vector2.ZERO
	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	left_click.position = pointer_position
	game.sky_contacts._unhandled_input(left_click)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "left-clicking a contact does not assign the dish")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = pointer_position
	game.sky_contacts._unhandled_input(right_click)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "plain right-click over a contact never reserves it")
	_check(Vector2(game.sky_contacts.dishes[0].target).is_equal_approx(pointer_position), "plain right-click moves the nearest dish to the clicked contact point")
	_check(game.sky_contacts.dish_movement_learned, "the first dish movement dismisses its independent teaching hint")
	_check(not game.sky_contacts.dish_commitment_learned, "manual placement does not dismiss the researched commitment lesson")
	_check(not game.sky_contacts.assign_to_contact(int(contact.id)), "contact commitment remains unavailable before its research")
	var isolated_contact_position := Vector2(-1000.0, -1000.0)
	contact.intercept = isolated_contact_position
	game.observer.cursor_position = isolated_contact_position
	game.observer.previous_cursor_position = isolated_contact_position
	game.observer.selected_meteor = null
	game.observer.tracking_grace_remaining = 0.0
	var hud_was_visible: bool = game.hud.visible
	game.hud.visible = false
	_check(
		game.sky_contacts._contact_at(isolated_contact_position) == int(contact.id),
		"the observation regression cursor is positioned over the forecast contact"
	)
	_check(not game.observer._cursor_is_on_ui(), "a forecast contact does not suppress manual observation tracking")
	game.observer._update_manual_tracking(0.016)
	_check(
		game.observer.selected_meteor == null and is_zero_approx(game.observer.tracking_grace_remaining),
		"left-button tracking fallthrough on an empty contact leaves selection and grace clean"
	)
	game.hud.visible = hud_was_visible

	for prerequisite_id in ["edge_detection", "observation_scheduling", "wide_field", "trajectory"]:
		game.progression.debug_purchase_node(prerequisite_id)
	var pacing_ratio_before_predictive_control: float = game.progression.get_progression_ratio()
	game.progression.debug_purchase_node("predictive_dish_control")
	_check(game.progression.dish_commitment_enabled(), "Predictive Dish Control unlocks contact commitment after the manual layer")
	_check(is_equal_approx(game.progression.get_progression_ratio(), pacing_ratio_before_predictive_control), "new dish interaction research does not silently retune spawn density")
	contact.intercept = pointer_position
	var commit_click := InputEventMouseButton.new()
	commit_click.button_index = MOUSE_BUTTON_RIGHT
	commit_click.pressed = true
	commit_click.shift_pressed = true
	commit_click.position = pointer_position
	game.sky_contacts._unhandled_input(commit_click)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == int(contact.id), "the researched Shift-right-click gesture reserves a forecast contact")
	_check(game.sky_contacts.dish_commitment_learned, "successful researched commitment dismisses only its own lesson")
	_check(not bool(game.sky_contacts.dishes[0].arrived), "a committed dish has to slew before direct handoff")
	game.spawner._announce_regular_spawn()
	var second_contact: Dictionary = game.spawner.pending_contacts[1]
	game.sky_contacts.assign_to_contact(int(second_contact.id))
	_check(float(contact.abandoned_flash) > 0.0, "re-tasking the only dish marks the contact it abandoned")
	_check(int(game.sky_contacts.dishes[0].assigned_id) == int(second_contact.id), "one dish cannot hold two contacts")
	var cancellation_point := pointer_position + Vector2(210.0, 90.0)
	right_click.position = cancellation_point
	game.sky_contacts._unhandled_input(right_click)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "plain right-click cancels a researched contact reservation")
	_check(Vector2(game.sky_contacts.dishes[0].target).is_equal_approx(cancellation_point), "reservation cancellation still obeys literal point movement")
	var fireball_contact: Dictionary = second_contact.duplicate(true)
	fireball_contact.id = 9001
	fireball_contact.type_id = "fireball"
	fireball_contact.classified = true
	fireball_contact.abandoned_flash = 0.0
	fireball_contact.intercept = cancellation_point + Vector2(160.0, 0.0)
	fireball_contact.error_offset = Vector2.ZERO
	game.sky_contacts.contacts.append(fireball_contact)
	_check(game.sky_contacts.assign_to_contact(int(fireball_contact.id)), "researched commitment accepts a classified fireball without a movement-layer type refusal")
	_check(int(game.sky_contacts.dishes[0].assigned_id) == int(fireball_contact.id), "rare contact commitment reserves movement but not tracking eligibility")
	right_click.position = Vector2(fireball_contact.intercept)
	game.sky_contacts._unhandled_input(right_click)
	_check(Vector2(game.sky_contacts.dishes[0].target).is_equal_approx(Vector2(fireball_contact.intercept)), "plain right-click over a classified fireball still moves the dish")
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "moving onto a fireball does not create a hidden reservation")
	var placed_fireball = game.spawner.spawn_meteor("fireball", Vector2(fireball_contact.intercept), Vector2.ZERO, 1.0)
	var placed_dish: Dictionary = game.sky_contacts.dishes[0]
	placed_dish.position = Vector2(fireball_contact.intercept)
	placed_dish.target = placed_dish.position
	placed_dish.arrived = true
	game.sky_contacts.dishes[0] = placed_dish
	game.sky_contacts._update_dishes(0.1)
	_check(int(game.sky_contacts.dishes[0].locked_id) == 0 and is_zero_approx(placed_fireball.dish_assist_rate), "a dish placed on a fireball grants no assistance")
	placed_fireball.queue_free()
	await process_frame
	game.spawner.pending_contacts.clear()
	game.sky_contacts.reset()
	_check(game.sky_contacts.contacts.is_empty() and int(game.sky_contacts.dishes[0].assigned_id) == -1, "resetting clears contacts and frees the dish")

	# An arrived dish must actually record, not merely sit on the mark.
	var scanned = game.spawner.spawn_meteor("common")
	var dish: Dictionary = game.sky_contacts.dishes[0]
	dish.position = scanned.global_position
	dish.target = scanned.global_position
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	game.sky_contacts._update_dishes(0.1)
	_check(int(game.sky_contacts.dishes[0].locked_id) == scanned.get_instance_id(), "an arrived dish acquires an object inside its coverage")
	scanned.set_lane_assist_rate(scanned.get_assist_rate(game.spawner.LANE_TIME_MULTIPLIER))
	var progress_before: float = scanned.observation_progress
	game.sky_contacts._update_dishes(0.2)
	var combined_assist_rate: float = scanned.dish_assist_rate + scanned.lane_assist_rate
	_check(scanned.dish_assist_rate > 0.0 and scanned.lane_assist_rate > 0.0, "dish and support-lane contributions coexist on one target")
	_check(is_equal_approx(scanned.get_automatic_rate(), combined_assist_rate), "machine contributions sum instead of overwriting each other")
	scanned._process(0.2)
	_check(is_equal_approx(scanned.observation_progress - progress_before, combined_assist_rate * 0.2), "a dish and support lane advance their shared target additively")
	game.spawner._refresh_secondary_camera()
	_check(is_zero_approx(scanned.lane_assist_rate) and scanned.dish_assist_rate > 0.0, "a disabled lane source clears only its own contribution")
	dish = game.sky_contacts.dishes[0]
	var retask_point := Vector2(dish.position) + Vector2(500.0, 0.0)
	_check(game.sky_contacts.move_dish_to(retask_point) == 0, "plain movement retasks the nearest dish away from a live lock")
	_check(is_zero_approx(scanned.dish_assist_rate), "moving away from a live lock immediately clears that meteor's dish contribution")
	_check(game.sky_contacts.abandoned_target_id == scanned.get_instance_id() and game.sky_contacts.abandoned_target_flash > 0.0, "moving away records a transient meteor abandonment marker")
	scanned.queue_free()
	await process_frame
	game.sky_contacts.reset()

	# Burnout planning must spread readable endpoints across the safe sky while
	# preserving the old entry speed as a mathematical identity.
	var meteor_script = load("res://scripts/meteor.gd")
	game.spawner.rng.seed = 20260822
	game.spawner.burnout_cell_cursors.clear()
	var viewport_size: Vector2 = game.spawner.get_viewport().get_visible_rect().size
	var burnout_safe_rect: Rect2 = game.spawner._burnout_safe_rect(viewport_size)
	var minimum_reachable_cells := {
		"common": 10,
		"fast": 8,
		"fragment": 10,
		"fragment_piece": 10,
		"fireball": 10,
	}
	for reachability_type in minimum_reachable_cells:
		var reachability_spec: Dictionary = balance.meteor_spec(reachability_type)
		for speed_factor in [game.spawner.PLAN_SPEED_FACTOR_MIN, game.spawner.PLAN_SPEED_FACTOR_MAX]:
			var extreme_distance: float = meteor_script.burn_distance_for(
				float(reachability_spec.speed) * speed_factor,
				float(reachability_spec.lifetime),
				float(reachability_spec.burn_terminal_ratio)
			)
			var reachable_cells: Array[int] = game.spawner._reachable_burnout_cells(
				reachability_type, viewport_size, extreme_distance
			)
			_check(reachable_cells.size() >= int(minimum_reachable_cells[reachability_type]), "%s keeps enough burnout cells at planning speed %.2f" % [reachability_type, speed_factor])
			if reachability_type in ["common", "fast"]:
				var outer_profile_only := true
				for reachable_cell in reachable_cells:
					if reachable_cell not in game.spawner.OUTER_BURNOUT_CELLS:
						outer_profile_only = false
				_check(outer_profile_only, "%s never uses deep-center burnout cells" % reachability_type)
	for burnout_type in ["common", "fast", "fragment", "fragment_piece", "fireball"]:
		var covered_columns: Dictionary = {}
		var covered_rows: Dictionary = {}
		for _plan_index in range(12):
			var entry_plan: Dictionary = game.spawner.plan_entry(burnout_type)
			var planned_start: Vector2 = entry_plan.start
			var planned_burnout: Vector2 = entry_plan.burnout
			_check(burnout_safe_rect.has_point(planned_burnout), "%s burnout stays inside the safe sky" % burnout_type)
			var allowed_entry := (
				is_equal_approx(planned_start.y, -game.spawner.ENTRY_MARGIN)
				or is_equal_approx(planned_start.x, -game.spawner.ENTRY_MARGIN)
				or is_equal_approx(planned_start.x, viewport_size.x + game.spawner.ENTRY_MARGIN)
			)
			_check(allowed_entry and not is_equal_approx(planned_start.y, viewport_size.y + game.spawner.ENTRY_MARGIN), "%s uses only top/side entry boundaries" % burnout_type)
			_check(absf(planned_start.distance_to(planned_burnout) - float(entry_plan.burn_distance)) < 0.05, "%s entry reaches its exact planned burnout distance" % burnout_type)
			var normalized_in_safe := (planned_burnout - burnout_safe_rect.position) / burnout_safe_rect.size
			covered_columns[clampi(int(normalized_in_safe.x * game.spawner.BURNOUT_GRID_COLUMNS), 0, game.spawner.BURNOUT_GRID_COLUMNS - 1)] = true
			covered_rows[clampi(int(normalized_in_safe.y * game.spawner.BURNOUT_GRID_ROWS), 0, game.spawner.BURNOUT_GRID_ROWS - 1)] = true
		_check(covered_columns.size() >= 3 and covered_rows.size() >= 2, "%s burnout plans span multiple sky rows and columns" % burnout_type)
	var major_crossing_plan: Dictionary = game.spawner.plan_entry("major")
	_check(absf(Vector2(major_crossing_plan.start).distance_to(Vector2(major_crossing_plan.burnout)) - float(major_crossing_plan.burn_distance)) < 0.05, "major planning falls back to an exact crossing path")

	var motion_plan: Dictionary = game.spawner.plan_entry("common")
	var motion_probe = meteor_script.new()
	game.meteor_layer.add_child(motion_probe)
	motion_probe.process_mode = Node.PROCESS_MODE_DISABLED
	motion_probe.configure(
		balance.meteor_spec("common"), "common", motion_plan.start,
		motion_plan.velocity, 1.0, {}, motion_plan.burnout
	)
	var identity_distance: float = meteor_script.burn_distance_for(
		motion_probe.initial_velocity.length(), motion_probe.visible_lifetime,
		motion_probe.burn_terminal_ratio
	)
	_check(absf(identity_distance - motion_probe.entry_position.distance_to(motion_probe.burnout_position)) < 0.05, "burn curve preserves the configured entry speed by identity")
	var sampled_speeds: Array[float] = []
	for _motion_step in range(5):
		motion_probe._process(motion_probe.visible_lifetime * 0.2)
		sampled_speeds.append(motion_probe.velocity.length())
	var speed_is_monotonic := true
	for speed_index in range(1, sampled_speeds.size()):
		if sampled_speeds[speed_index] > sampled_speeds[speed_index - 1] + 0.01:
			speed_is_monotonic = false
	_check(speed_is_monotonic, "burn curve speed decreases monotonically")
	_check(motion_probe.position.distance_to(motion_probe.burnout_position) < 0.05, "burn curve ends at the planned burnout point")
	motion_probe.free()
	for visibility_type in ["common", "fast", "fragment", "fragment_piece", "fireball", "major"]:
		var visibility_spec: Dictionary = balance.meteor_spec(visibility_type)
		var visibility_probe = meteor_script.new()
		visibility_probe.configure(
			visibility_spec, visibility_type, Vector2.ZERO,
			Vector2(float(visibility_spec.speed), 0.0), 1.0, {}
		)
		visibility_probe.age = visibility_probe.visible_lifetime * maxf(0.0, visibility_probe.burn_fade_start - 0.001)
		_check(visibility_probe.get_burn_visibility() >= 0.78, "%s stays readable before its terminal fade" % visibility_type)
		visibility_probe.age = visibility_probe.visible_lifetime * 0.999
		_check(visibility_probe.get_burn_visibility() >= 0.10, "%s remains faintly visible until burnout" % visibility_type)
		visibility_probe.free()

	# Forecast pre-positioning gives the dish a distinct routine/high-motion job.
	# Preserve the verified legacy fast ceiling as a stronger servo invariant than
	# the current planned ceiling (390 * 1.08).
	var fastest = game.spawner.spawn_meteor("fast", Vector2(220, 260), Vector2(436.8, 0.0), 3.6)
	dish = game.sky_contacts.dishes[0]
	dish.position = fastest.global_position
	dish.target = fastest.global_position
	dish.assigned_id = -1
	dish.locked_id = 0
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	for _step in range(55):
		game.sky_contacts._update_dishes(0.05)
		fastest._process(0.05)
		if not fastest.alive:
			break
	_check(fastest.observed_successfully and not fastest.manual_touched, "a dish completes a fast meteor at the real velocity ceiling without manual help")
	fastest.queue_free()
	await process_frame

	# Assigned rare contacts and nearby contactless finale objects both remain
	# manual prizes, even though the dish servo is now fast enough to follow them.
	var fireball = game.spawner.spawn_meteor("fireball", Vector2(-1000, -1000), Vector2.ZERO, 1.0)
	dish = game.sky_contacts.dishes[0]
	dish.position = fireball.global_position
	dish.target = fireball.global_position
	dish.assigned_id = 9001
	dish.locked_id = 0
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	game.sky_contacts.on_contact_resolved({"id": 9001}, fireball)
	game.sky_contacts._update_dishes(0.2)
	fireball._process(0.2)
	_check(int(game.sky_contacts.dishes[0].locked_id) == 0 and is_zero_approx(fireball.dish_assist_rate), "an assigned fireball never receives dish assistance through the resolved-contact path")
	_check(is_zero_approx(fireball.observation_progress), "dish rejection cannot degrade a rare fireball into an automatic observation")

	var major = game.spawner.spawn_meteor("major", Vector2(-2000, -2000), Vector2.ZERO, 1.0)
	dish = game.sky_contacts.dishes[0]
	dish.position = major.global_position
	dish.target = major.global_position
	dish.assigned_id = -1
	dish.locked_id = 0
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	game.sky_contacts._update_dishes(0.2)
	major._process(0.2)
	_check(int(game.sky_contacts.dishes[0].locked_id) == 0 and is_zero_approx(major.dish_assist_rate), "a dish parked beside a contactless major cannot acquire it opportunistically")
	_check(is_zero_approx(major.observation_progress), "the dish cannot reduce the contactless major prize to an automatic reward")
	_check(not game.sky_contacts._dish_can_track(fireball) and not game.sky_contacts._dish_can_track(major), "rare objects are outside the dish role by type")
	for rare_target in [fireball, major]:
		rare_target.queue_free()
	await process_frame
	game.sky_contacts.reset()

	# Completing a fragment before its timer must release all three pieces at the
	# completion point. Keep both the timing precondition and piece count
	# unconditional so a failed setup cannot silently skip the regression.
	game.spawner.rng.seed = 48612
	var early_fragment = game.spawner.spawn_meteor(
		"fragment", Vector2(-3000, -3000), Vector2(245.0, 0.0), 5.0
	)
	var early_split_threshold: float = early_fragment.visible_lifetime * early_fragment.split_progress
	for _step in range(100):
		if not early_fragment.alive:
			break
		early_fragment.apply_manual_observation(
			0.05, 0.0, game.progression.get_tracking_radius()
		)
		early_fragment._process(0.05)
	_check(early_fragment.observed_successfully, "manual setup completes the fragment observation")
	_check(early_fragment.age < early_split_threshold, "fragment observation completes strictly before its split timer")
	var early_piece_count := 0
	for split_target in game.meteor_layer.get_children():
		if String(split_target.type_id) == "fragment_piece":
			early_piece_count += 1
	_check(early_piece_count == 3, "an early fragment observation releases exactly three child pieces")
	for split_target in game.meteor_layer.get_children():
		if String(split_target.type_id) in ["fragment", "fragment_piece"]:
			split_target.queue_free()
	await process_frame

	# A forecasted fragment can hand its remaining split to the same parked dish.
	# This is deterministic and verifies the parent-to-piece synergy, rather than
	# merely asserting that a standalone piece appears on an allowlist.
	game.spawner.rng.seed = 77119
	var splitting = game.spawner.spawn_meteor(
		"fragment", Vector2(-3000, -3000), Vector2(245.0, 0.0), 5.0
	)
	dish = game.sky_contacts.dishes[0]
	dish.position = splitting.global_position
	# Keep the parked target at the parent's expected completion point so the
	# waiting dish can immediately scan the nearby split instead of slewing home.
	dish.target = splitting.get_planned_position(splitting.split_progress)
	dish.assigned_id = -1
	dish.locked_id = splitting.get_instance_id()
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	var split_piece_created := false
	var split_piece_acquired := false
	var split_piece_completed := false
	for _step in range(100):
		game.sky_contacts._update_dishes(0.05)
		var locked = game.sky_contacts._locked_target(game.sky_contacts.dishes[0])
		if locked != null and String(locked.type_id) == "fragment_piece":
			split_piece_acquired = true
		for split_target in game.meteor_layer.get_children():
			if not is_instance_valid(split_target):
				continue
			if String(split_target.type_id) == "fragment_piece":
				split_piece_created = true
			split_target._process(0.05)
			if String(split_target.type_id) == "fragment_piece" and split_target.observed_successfully and not split_target.manual_touched:
				split_piece_completed = true
		if split_piece_completed:
			break
	_check(split_piece_created, "a fragment creates child pieces during its observation window")
	_check(split_piece_acquired, "a dish acquires a nearby piece after its fragment parent splits")
	_check(split_piece_completed, "a dish completes a split piece without manual help")
	for split_target in game.meteor_layer.get_children():
		if String(split_target.type_id) in ["fragment", "fragment_piece"]:
			split_target.queue_free()
	await process_frame
	game.sky_contacts.reset()

	game.progression.debug_purchase_all()
	_check(game.progression.upgrade_level == 21, "all tree nodes unlock through prerequisite-safe debug purchase")
	_check(game.progression.get_max_active() == 6, "research raises dense-sky capacity without removing the six-target performance cap")
	_check(game.hud.array_progress_bar.value == 21.0, "compact HUD resolves to the full 21-system array completion")
	_check(is_equal_approx(game.progression.get_progression_ratio(), 1.0), "21-node topology normalization preserves the completed-tree density endpoint")
	for legacy_id in ["better_lens", "long_exposure", "wide_field", "trajectory", "precision_multiplier", "secondary_camera", "shower_detector", "automated_tracking"]:
		_check(game.progression.has_upgrade(legacy_id), "legacy upgrade migrated: " + legacy_id)
	_check(game.progression.has_upgrade("automated_tracking"), "final automation system is active")
	_check(game.progression.get_secondary_slots() == 2, "observatory network keeps its two automatic lanes when dish capacity grows")
	_check(game.progression.get_dish_count() == 2, "observatory network adds a second steerable dish for late-game capacity")
	_check(game.sky_contacts.dishes.size() == 2, "purchasing the observatory network places both steerable dishes")
	_check(game.progression.dish_commitment_enabled(), "completed research includes Predictive Dish Control")
	_check(game.progression.get_automation_strength("fireball") == 0.0, "rare fireballs remain manual high-value targets")
	# Literal nearest is intentionally spatial, not availability-aware: a busy
	# near dish moves even while a farther dish is idle.
	var nearest_target = game.spawner.spawn_meteor("common", Vector2(220.0, 210.0), Vector2.ZERO, 2.0)
	dish = game.sky_contacts.dishes[0]
	dish.position = nearest_target.global_position
	dish.target = dish.position
	dish.assigned_id = -1
	dish.locked_id = nearest_target.get_instance_id()
	dish.arrived = true
	game.sky_contacts.dishes[0] = dish
	var far_dish: Dictionary = game.sky_contacts.dishes[1]
	far_dish.position = Vector2(1000.0, 620.0)
	far_dish.target = far_dish.position
	far_dish.assigned_id = -1
	far_dish.locked_id = 0
	far_dish.arrived = true
	game.sky_contacts.dishes[1] = far_dish
	game.sky_contacts._update_dishes(0.05)
	var far_target_before: Vector2 = game.sky_contacts.dishes[1].target
	var nearest_move_point := Vector2(270.0, 210.0)
	_check(game.sky_contacts.move_dish_to(nearest_move_point) == 0, "a busy near dish wins over an idle far dish by literal distance")
	_check(Vector2(game.sky_contacts.dishes[1].target).is_equal_approx(far_target_before), "literal nearest movement leaves the farther idle dish untouched")
	_check(is_zero_approx(nearest_target.dish_assist_rate), "literal nearest movement releases the busy dish's old target immediately")
	nearest_target.free()
	# Additive machine sources must not reopen the finale-value regression. The
	# major receives its intended 49% passive lifetime coverage, while dish and
	# lane type guards keep every limited hardware contribution at zero.
	var machine_only_major = game.spawner.spawn_meteor(
		"major", Vector2(-5000, -5000), Vector2.ZERO, 14.0
	)
	machine_only_major.split_done = true
	var game_major_expiry_handler := Callable(game, "_on_meteor_expired")
	if machine_only_major.expired.is_connected(game_major_expiry_handler):
		machine_only_major.expired.disconnect(game_major_expiry_handler)
	for dish_index in range(game.sky_contacts.dishes.size()):
		dish = game.sky_contacts.dishes[dish_index]
		dish.position = machine_only_major.global_position
		dish.target = machine_only_major.global_position
		dish.assigned_id = -1
		dish.locked_id = 0
		dish.arrived = true
		game.sky_contacts.dishes[dish_index] = dish
	for _step in range(281):
		game.spawner._refresh_secondary_camera()
		game.sky_contacts._update_dishes(0.05)
		machine_only_major._process(0.05)
		if not machine_only_major.alive:
			break
	_check(is_zero_approx(machine_only_major.dish_assist_rate) and is_zero_approx(machine_only_major.lane_assist_rate), "every limited machine source excludes the major target")
	_check(not machine_only_major.observed_successfully and machine_only_major.observation_progress > 0.47 and machine_only_major.observation_progress < 0.51, "all active machine systems leave a major target at its intended passive coverage without manual input")
	machine_only_major.free()
	_check(game.progression.get_node_state("perfect_observation") == "purchased", "cross-branch Perfect Observation resolves")
	_check(game.progression.get_node_state("observatory_network") == "purchased", "cross-branch Observatory Network resolves")
	for duration_node in ["observation_scheduling", "thermal_management", "extended_watch_protocol", "continuous_watch_rotation"]:
		_check(game.progression.has_upgrade(duration_node) and game.upgrade_tree.node_buttons.has(duration_node), "duration research has a live purchased tree surface: " + duration_node)
	game.upgrade_tree.open_tree()
	await process_frame
	_check(game.upgrade_tree.node_buttons["predictive_dish_control"].visible, "Predictive Dish Control appears in the completed research tree")
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
	_check(absf(float(reset_state.observation_phase_remaining) - 20.0) < 1.0, "reset restores the base 20-second round")
	_check(game._observation_duration() == 20.0, "the base observation window is 20 seconds")
	_check(game.progression.debug_purchase_node("array_planning"), "Array Planning opens duration research")
	_check(game.progression.debug_purchase_node("observation_scheduling") and game._observation_duration() == 30.0, "Observation Scheduling extends future rounds to 30 seconds")
	_check(game.progression.debug_purchase_node("edge_detection"), "Edge Detection opens the gated detection path")
	_check(game.progression.debug_purchase_node("wide_field"), "the mandatory duration gate allows Wide Field")
	_check(game.progression.debug_purchase_node("thermal_management") and game._observation_duration() == 40.0, "Thermal Management extends future rounds to 40 seconds")
	_check(game.progression.debug_purchase_node("trajectory"), "Trajectory Prediction opens the next duration pairing")
	_check(game.progression.debug_purchase_node("extended_watch_protocol") and game._observation_duration() == 50.0, "Extended Watch Protocol extends future rounds to 50 seconds")
	_check(game.progression.debug_purchase_node("rare_detection"), "Rare Meteor Detection opens the final duration pairing")
	_check(game.progression.debug_purchase_node("continuous_watch_rotation") and game._observation_duration() == 60.0, "Continuous Watch Rotation reaches the 60-second maximum")
	var duration_save: Dictionary = game.progression.get_save_data()
	duration_save.observation_data = 7.0
	game.progression.load_save_data(duration_save)
	_check(is_equal_approx(game.progression.observation_data, 7.0), "restored duration systems load without retirement refunds")
	_check(game.progression.has_upgrade("continuous_watch_rotation") and game._observation_duration() == 60.0, "restored saves retain the full duration ladder")
	game.progression.reset()
	game.phase_start_upgrade_signature = game._current_build_signature()
	# The first common is a deliberate measured-round anchor. Consume it once
	# before the regular weighted type chooser takes over.
	game.spawner.reset()
	game.spawner.start_spawning()
	game.spawner.set_phase_time_remaining(20.0)
	game.spawner._process(balance.FIRST_METEOR_DELAY + 0.01)
	_check(game.meteor_layer.get_child_count() == 1 and String(game.meteor_layer.get_child(0).type_id) == "common", "each measured round opens with exactly one forced common anchor")
	_check(not game.spawner.first_spawn_pending, "the forced common anchor is consumed only once per round")
	game.spawner.reset()
	game.spawner.start_spawning()
	game.spawner.set_phase_time_remaining(20.0)
	# A due shower remains due when too little time is left, then starts as soon
	# as a fresh round can contain its warning and active duration.
	game.elapsed_time = 100.0
	game.events.run_time = game.elapsed_time
	game.events.next_shower_time = 100.0
	game.spawner.set_phase_time_remaining(balance.SHOWER_WARNING_TIME + balance.SHOWER_DURATION)
	_check(not game.events.trigger_shower() and game.events.shower_state == "idle", "a shower that cannot finish before zero is deferred")
	_check(is_equal_approx(game.events.next_shower_time, 100.0), "a deferred shower preserves its due time")
	game.spawner.set_phase_time_remaining(20.0)
	_check(game.events.trigger_shower() and game.events.shower_state == "warning", "a deferred shower starts in the next viable observation window")
	_check(game.phase_had_shower, "the measured round records its meteor-shower badge")
	game.events.pause_for_intermission()
	game.events.start()
	game.events.next_shower_time = game.events.run_time + 37.0
	game.progression.success_count = 4
	game.progression.manual_successes = 3
	game.progression.automatic_successes = 1
	game.progression.total_data_earned = 55.0
	game.observation_phase_remaining = 0.05
	game._process(0.1)
	_check(not game.observation_phase_active and game.hud.is_phase_summary_open() and not game.upgrade_tree.is_open() and paused, "round expiry pauses the sky and opens the comparison summary")
	_check(game.hud.phase_summary_observations.text == TranslationServer.translate("PHASE_SUMMARY_OBSERVATIONS") % 4, "phase summary reports observations from the measured round")
	_check(game.hud.phase_summary_data.text == TranslationServer.translate("PHASE_SUMMARY_OUTPUT") % 55, "phase summary keeps total round Data as the headline")
	_check(game.hud.phase_summary_split.text == TranslationServer.translate("PHASE_SUMMARY_MANUAL_AUTO") % [3, 1], "phase summary separates manual and automatic observations")
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_FIRST_BASELINE") % 165.0, "the first round establishes a realized-productivity baseline")
	_check(TranslationServer.translate("PHASE_SUMMARY_BADGE_SHOWER") in game.hud.phase_summary_badges.text and TranslationServer.translate("PHASE_SUMMARY_BADGE_BEST") in game.hud.phase_summary_badges.text, "summary badges explain shower context and a new best")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 165.0) and is_equal_approx(game.best_round_rate, 165.0), "first clean rate and best realized productivity persist in game state")
	_check(is_equal_approx(game.events.next_shower_time, 137.0), "the 40-58s shower schedule survives the research intermission")
	_check(game.upgrade_tree.intermission_next_round == 2 and game.upgrade_tree.intermission_next_duration == 20, "upgrade break identifies the next round and duration")
	game.hud._on_phase_summary_continue_pressed()
	_check(not game.hud.is_phase_summary_open() and game.upgrade_tree.is_open() and paused, "one summary action opens the research phase")
	_check(game.upgrade_tree.close_button.text == TranslationServer.translate("TREE_START_OBSERVATION"), "upgrade break close action is labeled as starting observation")
	_check(game.progression.debug_purchase_node("array_planning"), "research intermission can open Observation Scheduling")
	_check(game.progression.debug_purchase_node("observation_scheduling"), "research intermission can buy the mandatory first duration node")
	_check(game.upgrade_tree.intermission_next_duration == 30, "research subtitle updates the next round duration immediately")
	game.upgrade_tree.close_tree()
	_check(not paused and game.observation_phase_active and game.observation_round == 2, "closing the upgrade tree starts round 2")
	_check(absf(game.observation_phase_remaining - 30.0) < 0.1, "the purchased duration step applies to the next round")
	game.progression.success_count += 6
	game.progression.manual_successes += 2
	game.progression.automatic_successes += 4
	game.progression.total_data_earned += 70.0
	game._end_observation_phase()
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_COMPARE") % [140.0, "-25.0", "-15"], "different-length rounds compare realized Data per minute rather than totals")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 140.0) and is_equal_approx(game.best_round_rate, 165.0), "a higher total but lower rate replaces the clean baseline without creating a false best")
	_check(TranslationServer.translate("PHASE_SUMMARY_BADGE_BEST") not in game.hud.phase_summary_badges.text, "a longer round does not earn a best badge from total output alone")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	_check(game.observation_round == 3 and absf(game.observation_phase_remaining - 30.0) < 0.1, "round 3 retains the researched duration")
	_check(game.progression.debug_purchase_node("better_lens"), "a live research purchase changes the active build signature")
	game.progression.success_count += 5
	game.progression.manual_successes += 3
	game.progression.automatic_successes += 2
	game.progression.total_data_earned += 65.0
	game._end_observation_phase()
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_SYSTEMS_CHANGED") % 130.0, "a mixed-build round suppresses its percentage comparison")
	_check("VS PREVIOUS" not in game.hud.phase_summary_comparison.text, "a mixed-build round never presents a misleading comparison")
	_check(game.hud.phase_summary_badges.text == TranslationServer.translate("PHASE_SUMMARY_SINCE_BASELINE") % TranslationServer.translate("UPGRADE_BETTER_LENS_NAME").to_upper(), "a live purchase names the system installed since the clean baseline")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 140.0), "a mixed-build round does not replace the last clean baseline")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	_check(game.progression.debug_purchase_node("edge_detection"), "a second mixed minute can add another root system")
	game.progression.success_count += 4
	game.progression.manual_successes += 2
	game.progression.automatic_successes += 2
	game.progression.total_data_earned += 60.0
	game._end_observation_phase()
	var cumulative_system_names := ", ".join(PackedStringArray([
		TranslationServer.translate("UPGRADE_BETTER_LENS_NAME").to_upper(),
		TranslationServer.translate("UPGRADE_EDGE_DETECTION_NAME").to_upper(),
	]))
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_SYSTEMS_CHANGED") % 120.0, "consecutive mixed rounds remain non-comparable")
	_check(game.hud.phase_summary_badges.text == TranslationServer.translate("PHASE_SUMMARY_SINCE_BASELINE") % cumulative_system_names, "consecutive mixed minutes list every install since the clean baseline")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 140.0), "consecutive mixed rounds retain the older clean baseline")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	game.progression.success_count += 7
	game.progression.manual_successes += 4
	game.progression.automatic_successes += 3
	game.progression.total_data_earned += 80.0
	game._end_observation_phase()
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_COMPARE") % [160.0, "+20.0", "+14"], "the next stable build compares realized productivity against the last clean baseline")
	_check(TranslationServer.translate("PHASE_SUMMARY_SINCE_BASELINE") % cumulative_system_names in game.hud.phase_summary_badges.text, "the stable comparison retains cumulative install context")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 160.0) and is_equal_approx(game.best_round_rate, 165.0), "the stable post-change round establishes a new clean baseline without erasing the higher rate best")
	game._on_phase_summary_continue_requested()
	game.upgrade_tree.close_tree()
	game.observation_phase_remaining = 12.0
	var resumed_round_save: Dictionary = game._build_save_data()
	game.last_clean_round_result.clear()
	game.best_round_rate = 0.0
	game._apply_save_data(resumed_round_save)
	_check(game.phase_resumed_from_save and absf(game.observation_phase_remaining - 12.0) < 0.1, "round saves resume the remaining measured sample")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 160.0) and is_equal_approx(game.best_round_rate, 165.0), "resuming restores clean-baseline rate history")
	game.progression.success_count += 3
	game.progression.manual_successes += 2
	game.progression.automatic_successes += 1
	game.progression.total_data_earned += 40.0
	game._end_observation_phase()
	_check(game.hud.phase_summary_comparison.text == TranslationServer.translate("PHASE_SUMMARY_SESSION_RESUMED") % 80.0, "a reset-sky resumed sample is labeled as a new baseline")
	_check(is_equal_approx(float(game.last_clean_round_result.get("rate", 0.0)), 80.0) and is_equal_approx(game.best_round_rate, 165.0), "a resumed sample replaces the session baseline without erasing the all-run rate best")
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
