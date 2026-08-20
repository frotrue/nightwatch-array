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
	_check(game.autosave_elapsed < 1.0, "autosave interval resets after writing")
	game.progression.reset()
	game._on_startup_slot_selected(2)
	_check(int(game.progression.observation_data) == 23, "choosing an occupied startup slot resumes its autosave")
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
	_check(_decorative_controls_ignore_mouse(top_status), "top status HUD does not intercept tracking input")
	_check(game.hud.tree_button.mouse_filter == Control.MOUSE_FILTER_STOP, "upgrade tree launcher remains interactive")
	_check(game.hud.debug_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "display-only debug panel does not intercept tracking input")
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
	_check(TranslationServer.translate("UPGRADE_ERROR_NEED_DATA") % 12 == "데이터가 12개 더 필요합니다", "Korean shortfall text is a complete sentence")
	_check(TranslationServer.translate("TREE_NEED_MORE") % [8, 12] == "◇  보유 데이터 8    /    12개 더 필요", "Korean tree shortfall text includes its unit")
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
	_check(initial.upgrade_level == 0, "run begins with no upgrades")
	_check(initial.successes == 0, "run begins with no observations")
	_check(not initial.final_started, "final event is initially inactive")
	_check(game.progression.get_available_nodes().size() == 3, "only three opening choices are revealed")
	_check(game.hud.array_progress_bar.max_value == 16.0, "HUD exposes the finite array completion goal")
	_check(not game.hud.next_header.visible and not game.hud.next_progress_row.visible, "next-system details stay collapsed until an upgrade is affordable")
	_check(game.hud.next_system_name_label.text == TranslationServer.translate("UPGRADE_BETTER_LENS_NAME"), "HUD recommends the nearest affordable-path system")
	_check(game.hud.next_system_bar.max_value == 12.0 and game.hud.next_system_bar.value == 0.0, "next-system card shows progress toward its Data cost")
	_check(game.progression.get_node_state("long_exposure") == "hidden", "adjacent optics node begins hidden")
	var closed_tree_style_id: int = game.upgrade_tree.node_buttons["better_lens"].get_theme_stylebox("normal").get_instance_id()
	var closed_tree_layout_level: int = game.upgrade_tree.layout_upgrade_level
	var data_before_rejected_purchase: float = game.progression.observation_data
	_check(not game.progression.request_purchase("array_planning"), "purchase fails when Observation Data is insufficient")
	_check(game.progression.observation_data == data_before_rejected_purchase, "failed purchase never deducts Data")
	game.progression.add_debug_data(100.0)
	_check(game.upgrade_tree.refresh_pending, "closed upgrade tree defers progression refreshes")
	_check(game.upgrade_tree.layout_upgrade_level == closed_tree_layout_level, "observation data does not relayout a closed upgrade tree")
	_check(game.upgrade_tree.node_buttons["better_lens"].get_theme_stylebox("normal").get_instance_id() == closed_tree_style_id, "closed upgrade tree reuses node styles during observation rewards")
	_check(game.hud.data_gain_label.visible, "resource gains receive immediate HUD feedback")
	_check(game.hud.next_header.visible and game.hud.next_progress_row.visible, "affordable upgrades expand the contextual tree prompt")
	_check(game.hud.next_progress_row is VBoxContainer and game.hud.next_system_bar.custom_minimum_size.x == 0.0, "expanded upgrade copy reflows below the progress bar instead of clipping horizontally")
	_check(game.hud.tree_panel.offset_right - game.hud.tree_panel.offset_left >= 340.0, "expanded upgrade prompt reserves enough width for localized labels")
	_check(game.hud.next_system_bar.value == game.hud.next_system_bar.max_value, "next-system cost bar fills when an upgrade is affordable")
	var ready_panel_style_id: int = game.hud.tree_panel.get_theme_stylebox("panel").get_instance_id()
	game.progression.add_debug_data(1.0)
	_check(game.hud.tree_panel.get_theme_stylebox("panel").get_instance_id() == ready_panel_style_id, "unchanged ready HUD state reuses its panel style")
	var data_before_prerequisite_bypass: float = game.progression.observation_data
	_check(not game.progression.request_purchase("long_exposure"), "hidden prerequisite cannot be bypassed with enough Data")
	_check(game.progression.observation_data == data_before_prerequisite_bypass, "prerequisite rejection never deducts Data")
	game.progression.reset()
	game.upgrade_tree.open_tree()
	await process_frame
	_check(game.upgrade_tree.is_open(), "upgrade tree opens")
	_check(not game.upgrade_tree.refresh_pending, "opening the upgrade tree applies one deferred refresh")
	_check(paused, "opening the upgrade tree pauses gameplay")
	_check(game.upgrade_tree.opening_layout_active, "the untouched tree presents the three opening branches as a focused choice")
	var opening_optics: Button = game.upgrade_tree.node_buttons["better_lens"]
	var opening_detection: Button = game.upgrade_tree.node_buttons["edge_detection"]
	var opening_network: Button = game.upgrade_tree.node_buttons["array_planning"]
	_check(is_equal_approx(opening_optics.position.y, opening_detection.position.y) and is_equal_approx(opening_detection.position.y, opening_network.position.y), "opening branch cards share one readable horizontal row")
	_check(not game.upgrade_tree.node_buttons["long_exposure"].visible, "follow-up systems stay hidden until the first opening choice is installed")
	_check(game.upgrade_tree.detail_panel.anchor_top == 0.0 and game.upgrade_tree.detail_panel.size.x >= 390.0, "node detail follows the selected card instead of using a detached bottom corner")
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
	var meteor = game.spawner.spawn_meteor("common", Vector2(420, 220), Vector2(20, 5), 3.0)
	meteor.apply_manual_observation(1.0, 0.0, game.progression.get_tracking_radius())
	await process_frame
	await process_frame
	_check(game.progression.success_count == 1, "manual tracking completes an observation")
	_check(game.progression.observation_data >= 14.0, "observation awards data")
	_check(game.progression.request_purchase("better_lens"), "first observation can buy Better Lens through the tree controller")
	_check(game.progression.get_tracking_radius() > 36.0, "Better Lens changes the hit radius")
	_check(game.hud.array_progress_bar.value == 1.0, "array completion meter advances with purchases")
	_check(game.progression.get_node_state("long_exposure") == "available", "purchasing a node reveals its adjacent child")
	var data_after_better_lens: float = game.progression.observation_data
	_check(not game.progression.request_purchase("better_lens"), "a purchased node cannot be bought twice")
	_check(game.progression.observation_data == data_after_better_lens, "duplicate purchase cannot deduct Data")
	game.elapsed_time = 73.0
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
	_check(is_equal_approx(game.progression.observation_data, saved_observation_data), "loading restores Observation Data")
	_check(game.progression.has_upgrade("better_lens"), "loading restores purchased upgrades")
	_check(game.progression.success_count == 1, "loading restores observation statistics")

	game.progression.debug_purchase_all()
	_check(game.progression.upgrade_level == 16, "all tree nodes unlock through prerequisite-safe debug purchase")
	_check(game.hud.next_system_name_label.text == TranslationServer.translate("HUD_NETWORK_STABLE"), "HUD resolves to a completed-array state")
	for legacy_id in ["better_lens", "long_exposure", "wide_field", "trajectory", "precision_multiplier", "secondary_camera", "shower_detector", "automated_tracking"]:
		_check(game.progression.has_upgrade(legacy_id), "legacy upgrade migrated: " + legacy_id)
	_check(game.progression.has_upgrade("automated_tracking"), "final automation system is active")
	_check(game.progression.get_secondary_slots() == 3, "observatory network provides three assistance lanes")
	_check(game.progression.get_automation_strength("fireball") == 0.0, "rare fireballs remain manual high-value targets")
	_check(game.progression.get_node_state("perfect_observation") == "purchased", "cross-branch Perfect Observation resolves")
	_check(game.progression.get_node_state("observatory_network") == "purchased", "cross-branch Observatory Network resolves")
	_check(not game.hud.root_control.has_node("UpgradePanel"), "legacy upgrade purchase panel is absent")
	_check(game.hud.root_control.has_node("UpgradeTreeLauncher"), "tree launcher is the only HUD upgrade entry")

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
		print("SMOKE_TEST_PASS: tutorial, saves, localization, observation, progression, events, performance caps, stale references, and reset")
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
