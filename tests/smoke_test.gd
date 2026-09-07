extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const StarfieldScript = preload("res://scripts/starfield.gd")
const StarTwinkleScript = preload("res://scripts/star_twinkle.gd")
const InputBindings = preload("res://scripts/game_input_bindings.gd")
const Fixtures = preload("res://tests/support/game_fixture.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE: " + message)


func _check_ending_map_geometry(coda, live_chart) -> void:
	_check(
		coda.constellation_figures.size() == 12 and coda.chart_star_offsets.size() == 95,
		"the ending replays twelve actual constellations and all 95 chart stars"
	)
	var expected_figure_ids: Array = ChartData.CONSTELLATIONS.keys()
	var total_stars := 0
	for figure_index in range(mini(coda.constellation_figures.size(), expected_figure_ids.size())):
		var constellation_id: String = expected_figure_ids[figure_index]
		var source: Dictionary = ChartData.CONSTELLATIONS[constellation_id]
		var placement: Dictionary = ChartData.PLACEMENTS[constellation_id]
		var figure: Dictionary = coda.constellation_figures[figure_index]
		var star_indices := {}
		_check(
			String(figure.id) == constellation_id
			and figure.points.size() == source.stars.size()
			and figure.magnitudes.size() == source.stars.size()
			and figure.edges.size() == source.segments.size(),
			"ending figure preserves the source star and edge counts: " + constellation_id
		)
		for star_index in range(source.stars.size()):
			var star: Dictionary = source.stars[star_index]
			var key := "%s/%s" % [constellation_id, star.id]
			star_indices[String(star.id)] = star_index
			# Reconstruct from the factual position and placement instead of
			# comparing the renderer to another call of its chart_offsets helper.
			var angle := float(placement.anchor_angle)
			var expected := Vector2(cos(angle), sin(angle)) * float(placement.anchor_radius)
			expected += Vector2(star.local_position).rotated(float(placement.tilt)) * float(placement.scale)
			_check(
				coda.chart_star_offsets.has(key)
				and Vector2(coda.chart_star_offsets.get(key, Vector2.INF)).is_equal_approx(expected)
				and star_index < figure.points.size()
				and Vector2(figure.points[star_index]).is_equal_approx(expected)
				and star_index < figure.magnitudes.size()
				and is_equal_approx(float(figure.magnitudes[star_index]), float(star.magnitude)),
				"ending star keeps the chart's actual placement and brightness: " + key
			)
			total_stars += 1
		for edge_index in range(mini(figure.edges.size(), source.segments.size())):
			var segment: Array = source.segments[edge_index]
			var expected_edge := Vector2i(star_indices[String(segment[0])], star_indices[String(segment[1])])
			_check(
				Vector2i(figure.edges[edge_index]) == expected_edge,
				"ending connects the source constellation segment: %s/%s-%s" % [constellation_id, segment[0], segment[1]]
			)
	_check(total_stars == 95, "the ending does not omit a constellation's stars")

	var expected_galaxy_ids: Array[String] = ["galactic_reference_frame"]
	var functional_ids := {}
	for definition in Balance.UPGRADE_NODES:
		functional_ids[String(definition.id)] = true
	var decorative_count := 0
	var maximum_source_radius := 1.0
	for galaxy in ChartData.LOCAL_GROUP_GALAXIES:
		maximum_source_radius = maxf(maximum_source_radius, Vector2(galaxy.local_position).length())
	var shared_offsets := ChartData.galactic_map_offsets()
	_check(shared_offsets.size() == 29, "the shared galaxy projection includes all 29 Local Group records")
	for galaxy in ChartData.LOCAL_GROUP_GALAXIES:
		var node_id := String(galaxy.node_id)
		expected_galaxy_ids.append(node_id)
		var source_position := Vector2(galaxy.local_position)
		var expected_radius := 124.0 + source_position.length() / maximum_source_radius * (548.0 - 124.0)
		var expected := source_position.normalized() * expected_radius
		expected.y *= 0.52
		var live_offset: Vector2 = (Vector2(live_chart.local_group_node_positions[node_id]) - live_chart.CHART_ORIGIN) * live_chart.GALACTIC_ZOOM / UITheme.SCALE
		_check(
			Vector2(shared_offsets.get(node_id, Vector2.INF)).is_equal_approx(expected)
			and Vector2(coda.galaxy_positions.get(node_id, Vector2.INF)).is_equal_approx(expected)
			and live_offset.is_equal_approx(expected),
			"ending and live chart share the source galaxy's radial placement and disc tilt: " + node_id
		)
		if bool(galaxy.get("decorative", false)):
			decorative_count += 1
			_check(not functional_ids.has(node_id), "an illuminated ending decoration is still not research: " + node_id)
	var unique_galaxy_ids := {}
	for node_id in coda.galaxy_node_ids:
		unique_galaxy_ids[String(node_id)] = true
	_check(
		coda.galaxy_node_ids == expected_galaxy_ids
		and unique_galaxy_ids.size() == 30
		and coda.galaxy_positions.size() == 30
		and Vector2(coda.galaxy_positions.get("galactic_reference_frame", Vector2.INF)).is_zero_approx()
		and decorative_count == 17
		and functional_ids.size() == 107,
		"the ending uses the Milky Way plus all 29 unique galaxies without promoting 17 decorations to research"
	)
	_check(
		coda.galaxy_arrivals.size() == 30
		and coda.galaxy_route_points.size() == 1 + 29 * coda.ROUTE_SAMPLES,
		"the ending route has an arrival and exact sampled endpoint for every galaxy marker"
	)
	for index in range(expected_galaxy_ids.size()):
		var route_index: int = index * coda.ROUTE_SAMPLES
		_check(
			route_index < coda.galaxy_route_points.size()
			and Vector2(coda.galaxy_route_points[route_index]).is_equal_approx(Vector2(coda.galaxy_positions.get(expected_galaxy_ids[index], Vector2.INF))),
			"the ending route passes through its actual galaxy marker: " + expected_galaxy_ids[index]
		)


func _check_ending_map_illuminated(coda, context: String) -> void:
	for index in range(coda.constellation_figures.size()):
		_check(is_equal_approx(coda.constellation_light(index), 1.0), "%s fully lights constellation %d" % [context, index])
	for index in range(coda.galaxy_node_ids.size()):
		_check(is_equal_approx(coda.galaxy_light(index), 1.0), "%s fully lights galaxy %s" % [context, coda.galaxy_node_ids[index]])
	_check(
		coda._lit_route_points() == coda.galaxy_route_points,
		context + " retains the complete connected route, including the final galaxy"
	)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	await _run_input_routing_regressions(packed)
	var game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	var observation_view = game.observation_view
	var atmospheric_rect: Rect2 = observation_view.atmospheric_rect()
	var visible_world_rect: Rect2 = observation_view.visible_world_rect()
	var identity_probe := Vector2(317.0, 211.0)
	_check(
		atmospheric_rect.position == Vector2.ZERO and atmospheric_rect.size == Vector2(1152.0, 648.0),
		"observation routing keeps the atmospheric playfield at the shipped 1152x648 rect"
	)
	_check(
		visible_world_rect.position == atmospheric_rect.position and visible_world_rect.size == atmospheric_rect.size,
		"stage-zero observation span leaves the visible world identical to the atmospheric playfield"
	)
	_check(
		observation_view.world_to_screen(identity_probe).is_equal_approx(identity_probe)
		and observation_view.screen_to_world(identity_probe).is_equal_approx(identity_probe)
		and is_equal_approx(observation_view.screen_length_to_world(36.0), 36.0),
		"stage-zero observation world and screen conversions are identity transforms"
	)
	var outer_background_reserved := false
	for star in game.starfield.outer_stars:
		if not atmospheric_rect.has_point(Vector2(star.p)):
			outer_background_reserved = true
			break
	_check(outer_background_reserved, "background stars reserve deterministic coverage outside the atmospheric playfield")
	_check(
		StarfieldScript.BACKGROUND_COVERAGE_SPAN > Balance.GALACTIC_FINAL_OBSERVATION_SPAN
		and StarTwinkleScript.BACKGROUND_COVERAGE_SPAN > Balance.GALACTIC_FINAL_OBSERVATION_SPAN,
		"background coverage derives with overscan from the single galactic observation-span ceiling"
	)
	var original_research_rotation: float = game.settings.get_research_chart_rotation()
	var startup_save_directory := "user://nightwatch_startup_smoke_saves"
	_cleanup_smoke_saves(startup_save_directory)
	game.save_games.set_save_directory(startup_save_directory)
	_check(game._preferred_startup_slot() == 1, "quick start chooses the first empty slot on a fresh installation")
	var empty_slot_summaries: Dictionary = game.save_games.slot_summaries.duplicate(true)
	for corrupt_slot in range(1, 4):
		game.save_games.slot_summaries[corrupt_slot] = {"exists": true, "valid": false}
	game._enter_preferred_save()
	_check(
		game.active_save_slot == 0 and game.hud.is_startup_slots_open() and paused,
		"quick start keeps three corrupt records on the recovery surface instead of starting an unsavable slot-zero run"
	)
	game.hud.close_startup_slots()
	game.save_games.slot_summaries = empty_slot_summaries
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
	var debug_ending_snapshot := JSON.stringify(game._build_save_data())
	var debug_ending_mouse_mode: int = Input.mouse_mode
	var debug_ending_chord := InputEventKey.new()
	debug_ending_chord.keycode = KEY_E
	debug_ending_chord.pressed = true
	debug_ending_chord.ctrl_pressed = true
	debug_ending_chord.shift_pressed = true
	var debug_ending_release := debug_ending_chord.duplicate()
	debug_ending_release.pressed = false
	game.get_viewport().push_input(debug_ending_chord)
	await process_frame
	await process_frame
	game.get_viewport().push_input(debug_ending_release)
	_check(
		game.catalogue_ending_debug_preview
		and game.completed
		and game.hud.is_end_open()
		and paused
		and game.hud.end_coda.is_processing()
		and game.hud.end_coda.constellation_progress < 1.0
		and is_zero_approx(game.hud.end_coda.pullback_progress)
		and is_zero_approx(game.hud.end_coda.route_progress)
		and is_zero_approx(game.hud.end_coda.illumination_progress)
		and is_zero_approx(game.hud.end_coda.settle_progress)
		and not game.hud.end_reveal_complete
		and game.hud.end_finish_button.disabled
		and JSON.stringify(game._build_save_data()) == debug_ending_snapshot,
		"Ctrl+Shift+E opens the animated catalogue coda without changing save data"
	)
	_check_ending_map_geometry(game.hud.end_coda, game.upgrade_tree)
	var ending_skip_mouse := InputEventMouseButton.new()
	ending_skip_mouse.button_index = MOUSE_BUTTON_LEFT
	ending_skip_mouse.pressed = true
	var ending_skip_mouse_release := ending_skip_mouse.duplicate()
	ending_skip_mouse_release.pressed = false
	var ending_skip_pad := InputEventJoypadButton.new()
	ending_skip_pad.button_index = JOY_BUTTON_A
	ending_skip_pad.pressed = true
	var ending_skip_pad_release := ending_skip_pad.duplicate()
	ending_skip_pad_release.pressed = false
	var ending_modifier_only := InputEventKey.new()
	ending_modifier_only.keycode = KEY_CTRL
	ending_modifier_only.pressed = true
	_check(
		game.hud._is_catalogue_reveal_skip_input(ending_skip_mouse)
		and game.hud._is_catalogue_reveal_skip_input(ending_skip_pad)
		and not game.hud._is_catalogue_reveal_skip_input(ending_modifier_only),
		"mouse and controller buttons qualify as skip input while modifier-only presses do not"
	)
	_check(
		game.hud.END_REVEAL_SKIP_DELAY_MSEC == 2000
		and is_equal_approx(game.hud.END_REVEAL_TOTAL_SECONDS, 8.0),
		"the approved coda keeps its two-second skip boundary and eight-second natural duration"
	)
	game.hud.end_reveal_started_msec = Time.get_ticks_msec()
	game.get_viewport().push_input(ending_skip_mouse)
	game.get_viewport().push_input(ending_skip_mouse_release)
	_check(
		not game.hud.end_reveal_complete
		and game.hud.end_finish_button.disabled,
		"a real paused-HUD mouse press before two seconds is consumed without skipping"
	)
	game.hud.end_reveal_started_msec = Time.get_ticks_msec() - game.hud.END_REVEAL_SKIP_DELAY_MSEC
	game.get_viewport().push_input(ending_skip_pad)
	game.get_viewport().push_input(ending_skip_pad_release)
	_check(
		game.hud.end_reveal_complete
		and game.catalogue_ending_debug_preview
		and game.hud.is_end_open()
		and is_equal_approx(game.hud.end_coda.constellation_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.pullback_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.route_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.illumination_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.settle_progress, 1.0)
		and not game.hud.end_coda.is_processing()
		and not game.hud.end_finish_button.disabled,
		"a real paused-HUD pad press at two seconds skips exactly once without choosing an action"
	)
	_check_ending_map_illuminated(game.hud.end_coda, "skipped debug ending")
	game._on_catalogue_finish_requested()
	_check(
		not game.catalogue_ending_debug_preview
		and not game.completed
		and not game.hud.is_end_open()
		and not paused
		and game.observation_phase_active
		and Input.mouse_mode == debug_ending_mouse_mode
		and JSON.stringify(game._build_save_data()) == debug_ending_snapshot,
		"an ending choice exits the debug preview and restores the live round without saving"
	)
	game.get_viewport().push_input(debug_ending_release)
	game.get_viewport().push_input(debug_ending_chord)
	await process_frame
	var natural_coda_tween: Tween = game.hud.end_reveal_tween
	natural_coda_tween.pause()
	natural_coda_tween.custom_step(maxf(0.0, 2.8 - natural_coda_tween.get_total_elapsed_time()))
	_check(
		is_equal_approx(game.hud.end_coda.constellation_progress, 1.0)
		and is_zero_approx(game.hud.end_coda.pullback_progress)
		and is_zero_approx(game.hud.end_coda.route_progress)
		and not game.hud.end_reveal_complete,
		"the coda first finishes the player's constellation chart before the galaxy pullback"
	)
	natural_coda_tween.custom_step(maxf(0.0, 5.2 - natural_coda_tween.get_total_elapsed_time()))
	_check(
		is_equal_approx(game.hud.end_coda.pullback_progress, 1.0)
		and game.hud.end_coda.route_progress > 0.0
		and game.hud.end_coda.route_progress < 1.0
		and is_equal_approx(game.hud.end_coda.galaxy_light(0), 1.0)
		and is_zero_approx(game.hud.end_coda.galaxy_light(29))
		and game.hud.end_finish_button.disabled,
		"the completed chart becomes the Milky Way while the full galaxy route lights progressively"
	)
	var remaining_before_coda_endpoint := maxf(
		0.0,
		game.hud.END_REVEAL_TOTAL_SECONDS - 0.1 - natural_coda_tween.get_total_elapsed_time()
	)
	natural_coda_tween.custom_step(remaining_before_coda_endpoint)
	_check(
		not game.hud.end_reveal_complete
		and game.hud.end_finish_button.disabled,
		"the natural coda remains locked immediately before its eight-second endpoint"
	)
	natural_coda_tween.custom_step(0.2)
	_check(
		game.hud.end_reveal_complete
		and is_equal_approx(game.hud.end_coda.constellation_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.pullback_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.route_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.illumination_progress, 1.0)
		and is_equal_approx(game.hud.end_coda.settle_progress, 1.0)
		and not game.hud.end_finish_button.disabled,
		"the unskipped eight-second timeline reaches the same completed coda frame"
	)
	_check_ending_map_illuminated(game.hud.end_coda, "natural debug ending")
	var debug_toggle_snapshot := JSON.stringify(game._build_save_data())
	game.get_viewport().push_input(debug_ending_release)
	game.get_viewport().push_input(debug_ending_chord)
	game.get_viewport().push_input(debug_ending_release)
	_check(
		not game.catalogue_ending_debug_preview
		and not game.completed
		and not game.hud.is_end_open()
		and not paused
		and JSON.stringify(game._build_save_data()) == debug_toggle_snapshot,
		"pressing Ctrl+Shift+E again closes the non-destructive ending preview"
	)
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
	var data_readout: Control = game.hud.root_control.get_node("DataReadout")
	_check(_decorative_controls_ignore_mouse(data_readout), "data readout HUD remains mouse-filter transparent")
	_check(not game.hud.root_control.has_node("TopStatus"), "the bordered top status plate is gone")
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
	await process_frame
	await process_frame
	_check(game.tutorial.current_step == 0 and paused, "tutorial starts with a paused welcome step")
	_check(
		game.tutorial.primary_button.focus_mode == Control.FOCUS_ALL
		and game.get_viewport().gui_get_focus_owner() == game.tutorial.primary_button,
		"the welcome modal makes its primary action the keyboard focus owner"
	)
	var welcome_locale: String = game.settings.locale
	game.settings.set_language("en" if welcome_locale == "ko" else "ko", false)
	_check(paused, "changing language does not release the tutorial pause")
	game.settings.set_language(welcome_locale, false)
	game.tutorial._on_primary_pressed()
	_check(
		game.tutorial.current_step == 1
		and not paused
		and game.tutorial.primary_button.focus_mode == Control.FOCUS_NONE
		and game.tutorial.skip_button.focus_mode == Control.FOCUS_NONE,
		"tutorial enters the live observation step without leaving modal focus targets"
	)
	var tutorial_focus_probe := Button.new()
	tutorial_focus_probe.focus_mode = Control.FOCUS_ALL
	tutorial_focus_probe.text = "focus probe"
	game.hud.root_control.add_child(tutorial_focus_probe)
	tutorial_focus_probe.grab_focus()
	game.tutorial.notify_observation_completed()
	_check(
		game.tutorial.current_step == 2
		and game.tutorial.primary_button.focus_mode == Control.FOCUS_NONE
		and game.get_viewport().gui_get_focus_owner() == tutorial_focus_probe,
		"an observation advances the tutorial without stealing live-game focus"
	)
	game.tutorial.notify_upgrade_tree_opened()
	_check(
		game.tutorial.current_step == 3
		and game.tutorial.primary_button.focus_mode == Control.FOCUS_NONE
		and game.get_viewport().gui_get_focus_owner() == tutorial_focus_probe,
		"opening the tree advances the tutorial without stealing existing focus"
	)
	game.tutorial.notify_upgrade_purchased()
	await process_frame
	await process_frame
	_check(
		game.tutorial.current_step == 4
		and game.tutorial.primary_button.focus_mode == Control.FOCUS_ALL
		and game.get_viewport().gui_get_focus_owner() == game.tutorial.primary_button,
		"purchasing an upgrade opens a keyboard-focused completion modal"
	)
	game.tutorial._on_primary_pressed()
	_check(not game.tutorial.is_active(), "finishing hides the tutorial")
	tutorial_focus_probe.queue_free()
	var starting_locale: String = game.settings.locale
	var balance = load("res://scripts/game_balance.gd")
	var secondary_camera_definition: Dictionary = balance.upgrade_definition("secondary_camera")
	var predictive_control_definition: Dictionary = balance.upgrade_definition("predictive_dish_control")
	var multi_target_definition: Dictionary = balance.upgrade_definition("multi_target_analysis")
	var observatory_definition: Dictionary = balance.upgrade_definition("observatory_network")
	var triple_echo_definition: Dictionary = balance.upgrade_definition("triple_echo_array")
	var leonid_storm_definition: Dictionary = balance.upgrade_definition("leonid_storm")
	var global_x2_ids := [
		"perfect_observation", "shower_detector", "taurus_full_gallop",
		"double_star_resolution", "perseid_outburst", "echo_delay_line",
		"galaxy_imaging", "fireball_tail",
	]
	await _run_feedback_regressions(packed, global_x2_ids)
	await _run_survey_regressions(packed, balance)
	game.settings.set_language("ko", false)
	await process_frame
	_check(TranslationServer.get_locale().left(2) == "ko", "Korean locale activates through game settings")
	_check("설정" in game.hud.settings_button.text, "HUD refreshes with Korean text")
	_check(game.upgrade_tree.title_label.text == "관측 데이터", "research chart refreshes with Korean text")
	_check(game.upgrade_tree.installed_caption.text == "설치 완료", "research chart header names the completion count")
	_check(TranslationServer.translate("STAR_TSIH") == "감마 카시오페이아", "research inspector uses the factual Tsih star name in Korean")
	_check(TranslationServer.translate("CONSTELLATION_GEMINI") == "쌍둥이자리  /  공명", "the mapped Gemini figure exposes its Korean research role")
	_check(TranslationServer.translate("CONSTELLATION_LEO") == "사자자리  /  유성 폭풍", "the mapped Leo figure exposes its Korean research role")
	_check(TranslationServer.translate("CONSTELLATION_URSA_MINOR") == "작은곰자리  /  빈 하늘 훑기", "the mapped Ursa Minor figure exposes its Korean research role")
	_check(TranslationServer.translate("CONSTELLATION_DRACO") == "용자리  /  최종 관측", "the mapped Draco figure exposes its Korean culmination role")
	_check(TranslationServer.translate("UPGRADE_OBSERVATION_STREAK_NAME") == "관측 연속", "Korean player copy uses the approved observation-streak term")
	_check(TranslationServer.translate("UPGRADE_MOMENTUM_ACQUISITION_NAME") == "관측 연속 포착", "the Taurus root keeps its distinct name while using the shared Korean term")
	_check(TranslationServer.translate("HUD_AUTOSAVED") == "자동 저장됨", "Korean autosave status stays concise")
	_check(TranslationServer.translate("HUD_OBSERVATION_TIME") % [1, 1, 0] == "1차 관측  •  01:00", "Korean round countdown reads naturally")
	_check(TranslationServer.translate("TREE_INTERMISSION_SUBTITLE") % [2, 30] == "연구 시간  /  2차 관측은 30초", "Korean research-break guidance explains the next round and duration")
	_check(TranslationServer.translate("PHASE_SUMMARY_TITLE") % 1 == "1차 관측 완료", "Korean phase summary title reads naturally")
	_check(TranslationServer.translate("PHASE_SUMMARY_SYSTEMS_CHANGED") % 130.0 == "분당 데이터 130.0  •  시스템 변경  •  다음 회차부터 비교", "Korean mixed-build summary explains the data rate and next comparison")
	_check(
		game.upgrade_tree._upgrade_description(predictive_control_definition)
		== "쉬고 있는 접시를 예상 출현 위치로 자동 이동합니다. 우클릭 배치가 우선합니다.",
		"Korean Predictive Dish Control description explains automatic movement"
	)
	_check(
		game.upgrade_tree._upgrade_description(multi_target_definition)
		== "커서 원 안의 유성을 동시 관측합니다. 자동 지원 1개(파편 추적 설치 시 조각 포함). 하늘 활동: 일반 표적 동시 출현 상한 +1개.",
		"Korean Multi-Target Tracking description names capacity and both support effects"
	)
	_check(
		game.upgrade_tree._upgrade_description(observatory_definition)
		== "접시 1 → 2대, 자동 지원 표적 1 → 2개. 유성우 진입 구역도 예고합니다.",
		"Korean Observatory Network description names the second dish and two automatically supported targets"
	)
	_check(
		game.upgrade_tree._upgrade_description(triple_echo_definition)
		== "공명 발생 시 추가 유성 2 → 3개. 공명 상관 분석 연구도 필요합니다.",
		"Korean Triple Echo Array description names the three-meteor burst"
	)
	_check(
		game.upgrade_tree._upgrade_description(leonid_storm_definition)
		== "폭풍 발동에 필요한 수동 관측 6 → 5회. 7초간 발생 유성 16 → 20개.",
		"Korean Leonid Storm description names the five-observation twenty-meteor capstone"
	)
	for multiplier_id in global_x2_ids:
		var multiplier_definition: Dictionary = balance.upgrade_definition(multiplier_id)
		var multiplier_description: String = game.upgrade_tree._upgrade_description(multiplier_definition)
		_check("데이터 2배" in multiplier_description and "자동 포함" in multiplier_description and "국부은하군 제외" in multiplier_description, "%s exposes its global multiplier in Korean" % multiplier_id)
	_check(TranslationServer.translate("UPGRADE_ERROR_NEED_DATA") % 12 == "데이터가 12개 더 필요합니다", "Korean shortfall text is a complete sentence")
	_check(TranslationServer.translate("TREE_NEED_MORE") % [8, 12] == "◇  데이터 8 / 12", "Korean tree affordability text shows current and required Data")
	_check(TranslationServer.translate("SAVE_RESET_PROMPT") % 2 == "슬롯 2의 모든 진행 상황을 삭제합니다. 이 작업은 되돌릴 수 없습니다.", "Korean reset warning clearly explains permanent deletion")
	_check(game.hud.language_selector.get_item_metadata(1) == "ko", "language selector exposes Korean")
	game.hud.open_settings()
	_check(game.hud.is_settings_open(), "settings overlay opens")
	_check(paused, "settings overlay pauses gameplay")
	_check(
		game.hud.settings_pages.has(game.hud.settings_active_page)
		and game.hud.settings_pages[game.hud.settings_active_page].visible,
		"settings reopens the last page inside the same console"
	)
	game.hud._set_settings_page("general", false)
	_check(game.hud.settings_pages["general"].visible, "General remains directly selectable")
	_check(
		game.hud.reset_bindings_dialog.title == TranslationServer.translate("CONTROLS_RESET_TITLE")
		and game.hud.reset_bindings_dialog.dialog_text == TranslationServer.translate("CONTROLS_RESET_PROMPT")
		and game.hud.reset_bindings_dialog.ok_button_text == TranslationServer.translate("CONTROLS_RESET_CONFIRM")
		and game.hud.reset_bindings_dialog.cancel_button_text == TranslationServer.translate("SAVE_CANCEL"),
		"changing locale refreshes the Controls reset confirmation as part of the live settings console"
	)
	game.hud._on_save_management_pressed()
	_check(game.hud.settings_active_page == "save" and game.hud.save_management_container.visible, "save management opens as a first-class page")
	game.hud.close_settings()
	_check(not paused, "closing settings resumes gameplay")
	game.settings.set_language("en", false)
	await process_frame
	_check("SETTINGS" in game.hud.settings_button.text and "ESC" in game.hud.settings_button.text, "English settings entry advertises the global Escape shortcut")
	_check(TranslationServer.translate("UPGRADE_OBSERVATION_STREAK_NAME") == "Observation Streak", "English player copy keeps Observation Streak as the shared term")
	_check(TranslationServer.translate("UPGRADE_MOMENTUM_ACQUISITION_NAME") == "Streak Acquisition", "the Taurus root keeps a distinct English name without reintroducing Momentum")
	_check(
		game.upgrade_tree._upgrade_description(predictive_control_definition)
		== "Automatically moves idle dishes to predicted arrival positions. Right-click placement takes priority.",
		"English Predictive Dish Control description explains automatic movement"
	)
	_check(
		game.upgrade_tree._upgrade_description(multi_target_definition)
		== "Observes all meteors inside the cursor ring together. Automatic support: 1 target, including fragments after Fragment Tracking. Sky Activity: simultaneous regular targets +1.",
		"English Multi-Target Tracking description names capacity and both support effects"
	)
	_check(
		game.upgrade_tree._upgrade_description(observatory_definition)
		== "Movable dishes: 1 → 2. Automatic support: 1 → 2 targets. Adds meteor-shower entry forecasts.",
		"English Observatory Network description names the second dish and two automatically supported targets"
	)
	_check(
		game.upgrade_tree._upgrade_description(triple_echo_definition)
		== "Meteors per echo: 2 → 3. Requires Echo Correlation research.",
		"English Triple Echo Array description names the three-meteor burst"
	)
	_check(
		game.upgrade_tree._upgrade_description(leonid_storm_definition)
		== "Storm trigger: 6 → 5 manual observations. Meteors per storm: 16 → 20 over 7 seconds.",
		"English Leonid Storm description names the five-observation twenty-meteor capstone"
	)
	for definition_variant in balance.UPGRADE_NODES:
		var localized_definition: Dictionary = definition_variant
		_check(
			game.upgrade_tree._upgrade_name(localized_definition) == String(localized_definition.name),
			"%s fallback name stays in sync with English localization" % String(localized_definition.id)
		)
		_check(
			game.upgrade_tree._upgrade_description(localized_definition) == String(localized_definition.description),
			"%s fallback description stays in sync with English localization" % String(localized_definition.id)
		)
	for multiplier_id in global_x2_ids:
		var multiplier_definition: Dictionary = balance.upgrade_definition(multiplier_id)
		var multiplier_description: String = game.upgrade_tree._upgrade_description(multiplier_definition)
		_check("Observation Data ×2" in multiplier_description and "automatic included" in multiplier_description and "Local Group excluded" in multiplier_description, "%s exposes its global multiplier in English" % multiplier_id)
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
		"Multi-Target Tracking fallback description stays in sync with rendered localization"
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
	_check(initial.canis_major_state == "idle", "Canis Major event is initially inactive")
	_check(initial.observation_round == 1 and initial.observation_phase_active, "run begins in observation round 1")
	_check(absf(float(initial.observation_phase_remaining) - 20.0) < 1.0, "first observation round starts at 20 seconds")
	_check(game.progression.get_max_active() == 4, "the opening sky supports four concurrent targets so attention starts scarce")
	_check(balance.FIRST_METEOR_DELAY <= 2.0, "the opening meteor arrives before the sky feels empty")
	_check(balance.REGULAR_SPAWN_INTERVAL_MIN == 1.6 and balance.REGULAR_SPAWN_INTERVAL_MAX == 2.4, "regular spawn cadence keeps multiple choices in flight")
	_check(game.progression.get_available_nodes().size() == 15, "the eleven legacy and four price-gated Canis roots are available from the opening sky")
	_check(game.upgrade_tree.systems_readout != null, "the research chart owns the complete system-count readout")
	_check(not game.hud.root_control.has_node("ArrayCompletionBar"), "the HUD no longer duplicates completion as a bar")
	_check(not game.hud.tracking_cluster.is_processing(), "the hidden tracking instrument does no frame work before first use")
	_check(game.progression.get_node_state("long_exposure") == "hidden", "adjacent optics node begins hidden")
	_check(game.progression.get_node_state("draco_synthesis") == "hidden", "Draco stays dark before every other constellation is complete")
	_check(not game.progression.forecast_visible(), "Andromeda forecasts are inert before Ephemeris Marks")
	_check(is_equal_approx(game.progression.get_lifetime_multiplier(), 1.0), "Perseus exposure is inert before purchase")
	_check(is_equal_approx(game.progression.get_analysis_speed_multiplier("comet"), 1.0), "Andromeda analysis speed is inert before its capstone")
	_check(is_equal_approx(game.progression.get_observation_value_multiplier("fragment_piece", 4), 1.0), "new constellation rewards are inert before purchase")
	_check(is_zero_approx(game.progression.get_observation_echo_probability()) and game.progression.get_observation_echo_count() == 0, "Gemini echoes are inert before purchase")
	_check(game.progression.get_leonid_trigger_count() == 0 and game.progression.get_leonid_storm_count() == 0 and game.progression.leonid_charge == 0, "Leonid storms are inert before purchase")
	_check(is_equal_approx(game.progression.get_manual_analysis_speed_multiplier(), 1.0) and is_zero_approx(game.progression.get_taurus_tracking_radius_bonus()), "Taurus Observation Streak is inert before its discovery root")
	var capacity_probe = load("res://scripts/progression_controller.gd").new()
	_check(capacity_probe.get_max_active() == 4, "regular active-sky capacity begins at four")
	for capacity_step in [
		["array_planning", 5],
		["multi_target_analysis", 6],
		["cascade_sampling", 7],
		["perseid_survey", 8],
	]:
		capacity_probe.purchased_nodes[String(capacity_step[0])] = true
		_check(capacity_probe.get_max_active() == int(capacity_step[1]), "%s contributes its permanent active-sky slot" % String(capacity_step[0]))
	capacity_probe.free()
	var draco_probe = load("res://scripts/progression_controller.gd").new()
	for draco_gate_definition_variant in balance.UPGRADE_NODES:
		var draco_gate_definition: Dictionary = draco_gate_definition_variant
		if String(draco_gate_definition.branch) not in ["draco", "local_group"]:
			draco_probe.purchased_nodes[String(draco_gate_definition.id)] = true
	_check(draco_probe.upgrade_level == 86 and draco_probe.get_node_state("draco_synthesis") == "available", "completing the other eleven constellations reveals Draco's first star")
	_check(draco_probe.get_node_state("draco_cadence") == "hidden", "Draco still reveals only one internal step at a time")
	_check(draco_probe.debug_purchase_node("draco_synthesis") and is_equal_approx(draco_probe.get_observation_value_multiplier("common", 1), 1024.0), "All-Sky Synthesis multiplies the legacy x256 array to x1024")
	_check(draco_probe.debug_purchase_node("draco_cadence") and is_equal_approx(draco_probe.get_regular_spawn_interval_floor(), 0.45), "Circumpolar Cadence lowers the regular-arrival floor to 0.45 seconds")
	_check(draco_probe.debug_purchase_node("draco_capacity") and draco_probe.get_max_active() == 18, "Dragon-Spine Array raises regular active capacity from twelve to eighteen")
	_check(draco_probe.debug_purchase_node("draco_sweep"), "Coiled-Sky Sweep follows the capacity step")
	_check(is_equal_approx(draco_probe.get_survey_required_distance(), 190.0) and is_equal_approx(draco_probe.get_survey_spawn_probability(), 1.0) and draco_probe.get_survey_spawn_count() == 4 and is_equal_approx(draco_probe.get_survey_cooldown_seconds(), 0.45), "Coiled-Sky Sweep applies all four declared sweep overcharge effects")
	_check(draco_probe.debug_purchase_node("draco_echo") and is_equal_approx(draco_probe.get_observation_echo_probability(), 0.65) and draco_probe.get_observation_echo_count() == 6, "Polar Resonance raises the manual echo to sixty-five percent and six entries")
	_check(draco_probe.debug_purchase_node("draco_storm") and draco_probe.get_leonid_trigger_count() == 2 and draco_probe.get_leonid_storm_count() == 30, "Radiant Convergence arms thirty-object storms after two manual observations")
	_check(draco_probe.debug_purchase_node("draco_array") and draco_probe.get_dish_count() == 4 and draco_probe.get_secondary_slots() == 4, "Total Array expands both steerable dishes and automatic lanes to four")
	_check(draco_probe.debug_purchase_node("draco_apotheosis") and is_equal_approx(draco_probe.get_observation_value_multiplier("common", 1), 8192.0), "Dragon's Eye raises the completed constellation economy to x8192")
	_check(not draco_probe.galaxy_unlocked() and draco_probe.debug_purchase_node("galactic_reference_frame") and draco_probe.galaxy_unlocked(), "the final Draco node unlocks the galactic reference frame")
	_check(not draco_probe.is_research_complete(), "the Draco culmination leaves the 12-node Local Group route uninstalled")
	var purchased_local_group_nodes := 0
	for local_definition_variant in balance.UPGRADE_NODES:
		var local_definition: Dictionary = local_definition_variant
		if String(local_definition.branch) == "local_group" and draco_probe.debug_purchase_node(String(local_definition.id)):
			purchased_local_group_nodes += 1
	_check(purchased_local_group_nodes == 12, "the prerequisite-safe Local Group route installs all 12 functional research nodes")
	_check(draco_probe.is_research_complete(), "Draco plus the full Local Group route complete the 107-node research graph")
	var draco_save_probe = load("res://scripts/progression_controller.gd").new()
	draco_save_probe.load_save_data(draco_probe.get_save_data())
	_check(draco_save_probe.galaxy_unlocked() and is_equal_approx(draco_save_probe.get_observation_value_multiplier("common", 1), 8192.0), "Draco culmination and galaxy state survive ID-based saves")
	draco_save_probe.free()
	draco_probe.free()
	var streak_display_probe = load("res://scripts/progression_controller.gd").new()
	streak_display_probe.manual_combo_count = 7
	_check(streak_display_probe.get_manual_combo_display_count() == 0, "Observation Streak stays hidden before its display research")
	streak_display_probe.purchased_nodes["observation_streak"] = true
	_check(streak_display_probe.get_manual_combo_display_count() == 7, "Observation Streak displays the raw consecutive-observation count")
	streak_display_probe.purchased_nodes["momentum_acquisition"] = true
	_check(streak_display_probe.get_manual_combo_display_count() == 7 and streak_display_probe.get_taurus_combo_stack_count() == 4, "the display count stays raw while Taurus applies its independent buff cap")
	streak_display_probe.free()
	var research_probe = load("res://scripts/progression_controller.gd").new()
	var base_probe_scale: float = research_probe.get_spawn_interval_scale()
	_check(research_probe.debug_purchase_node("momentum_acquisition"), "Taurus Observation Streak is available from the opening sky")
	for _combo_step in range(4):
		research_probe.add_observation(1.0, true, 1.0)
	_check(research_probe.manual_combo_count == 4 and research_probe.get_taurus_combo_cap() == 4 and is_equal_approx(research_probe.get_manual_combo_window(), 3.0), "Taurus opens with a three-second four-stack combo")
	_check(is_equal_approx(research_probe.get_manual_analysis_speed_multiplier(), 1.08) and is_equal_approx(research_probe.get_taurus_tracking_radius_bonus(), 4.0), "opening Observation Streak steps raise only manual speed and tracking range")
	research_probe.add_observation(1.0, false, 1.0)
	_check(research_probe.manual_combo_count == 4, "automatic observations neither build nor break Observation Streak")
	research_probe.update_manual_combo(3.01)
	_check(research_probe.manual_combo_count == 0, "Observation Streak expires when its observation window elapses")
	_check(research_probe.debug_purchase_node("wide_pursuit") and research_probe.debug_purchase_node("rapid_focus"), "Taurus side stars refine range and speed from the shared root")
	for _side_combo_step in range(4):
		research_probe.add_observation(1.0, true, 1.0)
	_check(is_equal_approx(research_probe.get_manual_analysis_speed_multiplier(), 1.12) and is_equal_approx(research_probe.get_taurus_tracking_radius_bonus(), 6.0), "Taurus side stars independently add one percent speed and half a pixel per stack")
	_check(research_probe.debug_purchase_node("cadence_memory") and research_probe.debug_purchase_node("expanded_sweep") and research_probe.debug_purchase_node("accelerated_analysis"), "Taurus follows its central figure through the mid-combo refinements")
	_check(research_probe.debug_purchase_node("sustained_charge") and research_probe.debug_purchase_node("taurus_full_gallop"), "Taurus completes its five-second ten-step Observation Streak path")
	for _full_combo_step in range(10):
		research_probe.add_observation(1.0, true, 1.0)
	_check(research_probe.get_taurus_combo_stack_count() == 10 and is_equal_approx(research_probe.get_manual_combo_window(), 5.0), "completed Taurus holds ten effective stacks for five seconds")
	_check(is_equal_approx(research_probe.get_manual_analysis_speed_multiplier(), 1.5) and is_equal_approx(research_probe.get_taurus_tracking_radius_bonus(), 25.0), "completed Taurus cumulatively reaches the declared 50-percent speed and 25-pixel range ceiling")
	var combo_save_probe = load("res://scripts/progression_controller.gd").new()
	combo_save_probe.load_save_data(research_probe.get_save_data())
	_check(combo_save_probe.has_upgrade("taurus_full_gallop") and combo_save_probe.manual_combo_count == 0, "Taurus research persists while live Observation Streak never crosses a save or round boundary")
	combo_save_probe.free()
	research_probe.reset_manual_combo()
	_check(research_probe.debug_purchase_node("radiant_plotting"), "Perseus discovery root purchases without a hidden observation gate")
	_check(research_probe.get_spawn_interval_scale() < base_probe_scale, "Radiant Plotting compresses arrivals only after purchase")
	_check(research_probe.debug_purchase_node("crowd_forecast") and research_probe.get_forecast_lead() > 2.0, "Crowd Forecast extends the warning window")
	_check(research_probe.debug_purchase_node("burst_windowing"), "Perseus density chain advances through Burst Windowing")
	_check(research_probe.debug_purchase_node("adaptive_exposure_grid") and research_probe.get_lifetime_multiplier() > 1.0, "Adaptive Exposure Grid lengthens target visibility")
	_check(research_probe.debug_purchase_node("debris_correlation"), "Perseus debris branch opens from its real Mirfak segment")
	_check(research_probe.debug_purchase_node("cascade_sampling") and research_probe.get_max_active() == 5, "Cascade Sampling opens one bounded crowded-sky channel")
	_check(research_probe.debug_purchase_node("perseid_survey") and research_probe.get_max_active() == 6, "Perseid Survey adds its slot to this two-upgrade capacity build")
	_check(not research_probe.is_perseid_survey_active(2) and research_probe.is_perseid_survey_active(3), "Perseid Survey exposes the same three-target threshold used by its cursor indicator")
	var two_target_multiplier: float = research_probe.get_observation_value_multiplier("fragment", 2)
	var three_target_multiplier: float = research_probe.get_observation_value_multiplier("fragment", 3)
	_check(is_equal_approx(three_target_multiplier, two_target_multiplier * 1.18), "Perseid Survey rewards dense fragment observations at the visible threshold")
	_check(research_probe.debug_purchase_node("ephemeris_marks") and research_probe.forecast_visible(), "Ephemeris Marks independently opens the deep-sky forecast")
	_check(research_probe.debug_purchase_node("satellite_catalog"), "Satellite Catalog opens its same-round target family")
	_check(research_probe.debug_purchase_node("change_detection"), "Change Detection advances the Andromeda chain")
	_check(research_probe.debug_purchase_node("variable_watchlist"), "Variable Watchlist opens its optional Andromeda arm")
	_check(research_probe.debug_purchase_node("comet_solutions"), "Comet Solutions opens its long-arc target family")
	_check(research_probe.debug_purchase_node("andromeda_deep_survey"), "Andromeda capstone follows the comet arm")
	_check(research_probe.forecast_classifies("comet") and research_probe.get_forecast_max_error("comet") == 22.0, "Change Detection classifies and tightens deep-target forecasts")
	_check(research_probe.get_analysis_speed_multiplier("comet") == 1.25 and is_equal_approx(research_probe.get_observation_value_multiplier("comet", 1), 2.6), "Andromeda's conditional value bonus stacks over Taurus's global x2 growth")
	_check(research_probe.debug_purchase_node("perseid_outburst"), "Perseid Outburst arrives after the completed Perseus survey")
	_check(research_probe.debug_purchase_node("filter_wheel"), "Lyra calibration framework opens before the double-star side branch")
	_check(research_probe.debug_purchase_node("double_star_resolution"), "Double-Star Resolution follows Vega without a hidden success gate")
	_check(research_probe.debug_purchase_node("galaxy_imaging"), "Galaxy Imaging follows the completed Andromeda survey")
	_check(research_probe.forecast_classifies("binary_star") and research_probe.get_forecast_max_error("binary_star") == 22.0, "Double-Star Resolution classifies and tightens binary-star forecasts")
	_check(research_probe.get_analysis_speed_multiplier("galaxy") == 1.25 and is_equal_approx(research_probe.get_observation_value_multiplier("galaxy", 1), 20.8), "Galaxy fields combine the four purchased global x2 leaves with Andromeda's conditional value bonus")
	_check(research_probe.debug_purchase_node("echo_correlation_10") and is_equal_approx(research_probe.get_observation_echo_probability(), 0.10), "Gemini correlation opens at a ten-percent manual trigger chance")
	_check(research_probe.get_observation_echo_count() == 0, "Gemini probability research cannot launch meteors before an echo channel is online")
	_check(research_probe.debug_purchase_node("single_echo_channel") and research_probe.get_observation_echo_count() == 1, "Gemini's second root opens one echo channel")
	var echo_layer := Node2D.new()
	var echo_spawner = load("res://scripts/meteor_spawner.gd").new()
	root.add_child(echo_layer)
	root.add_child(echo_spawner)
	echo_spawner.setup(echo_layer, research_probe)
	echo_spawner.running = true
	echo_spawner.set_phase_time_remaining(10.0)
	_check(echo_spawner.should_trigger_observation_echo(0.099) and not echo_spawner.should_trigger_observation_echo(0.10), "Gemini's first probability tier uses an exact ten-percent boundary")
	_check(research_probe.debug_purchase_node("echo_correlation_20") and is_equal_approx(research_probe.get_observation_echo_probability(), 0.20), "Gemini correlation rises from ten to twenty percent")
	_check(research_probe.debug_purchase_node("dual_echo_channel") and research_probe.get_observation_echo_count() == 2, "Gemini's second channel raises each burst to two meteors")
	_check(research_probe.debug_purchase_node("triple_echo_array") and research_probe.get_observation_echo_count() == 3, "Gemini's final channel raises each burst to three meteors")
	_check(echo_spawner.should_trigger_observation_echo(0.199) and not echo_spawner.should_trigger_observation_echo(0.20), "Gemini's final probability tier uses an exact twenty-percent boundary")
	_check(echo_spawner.try_spawn_observation_echo(false, false) == 0, "automatic observations never trigger Gemini echoes")
	_check(echo_spawner.try_spawn_observation_echo(true, true) == 0, "echo meteors cannot recursively trigger another Gemini burst")
	var echo_spawned: int = echo_spawner._spawn_observation_echo_burst()
	var every_echo_tagged := echo_spawned == 3
	for echo_target in echo_layer.get_children():
		every_echo_tagged = every_echo_tagged and bool(echo_target.get_meta("gemini_echo", false))
	_check(every_echo_tagged, "the completed Gemini array launches and tags exactly three additional meteors")
	var echo_children_before_split := echo_layer.get_child_count()
	echo_spawner._on_fragment_requested(Vector2(480, 220), Vector2(80, 0), "fragment", true)
	var echo_descendants_tagged := echo_layer.get_child_count() == echo_children_before_split + 3
	for child_index in range(echo_children_before_split, echo_layer.get_child_count()):
		echo_descendants_tagged = echo_descendants_tagged and bool(echo_layer.get_child(child_index).get_meta("gemini_echo", false))
	_check(echo_descendants_tagged, "fragment pieces inherit the echo tag and cannot reopen the Gemini chain")
	for old_echo_target in echo_layer.get_children():
		old_echo_target.free()
	var echo_trigger_script = load("res://scripts/meteor.gd")
	var echo_trigger = echo_trigger_script.new()
	var echo_view_size: Vector2 = echo_spawner.get_viewport().get_visible_rect().size
	echo_trigger.configure(
		balance.meteor_spec("fast"), "fast", Vector2(100.0, 120.0),
		Vector2(390.0, 70.0), 1.0, {}, Vector2(echo_view_size.x - 180.0, echo_view_size.y - 140.0)
	)
	_check(research_probe.debug_purchase_node("echo_signature_lock"), "Echo Signature Lock follows Tau Geminorum through prerequisites alone")
	var echo_trigger_snapshot: Dictionary = echo_spawner._echo_trigger_snapshot(echo_trigger)
	_check(echo_spawner._echo_type_for_trigger(echo_trigger_snapshot) == "fast", "Echo Signature Lock copies the fresh manual target class")
	_check(research_probe.debug_purchase_node("mirror_echo_solution"), "Mirror Echo Solution follows Mebsuta along the lower Castor body")
	var mirror_plan: Dictionary = echo_spawner._plan_echo_entry("fast", 1, 3, echo_trigger_snapshot)
	_check(is_equal_approx(float(Vector2(mirror_plan.start).x), echo_view_size.x - 100.0), "Mirror Echo Solution reconstructs the trigger from the opposite sky side")
	_check(research_probe.debug_purchase_node("echo_delay_line"), "Echo Delay Line follows Tejat and completes the lower Castor body")
	var delayed_required: float = echo_spawner._echo_required_phase_time("fast")
	echo_spawner.set_phase_time_remaining(delayed_required - 0.01)
	_check(not echo_spawner.can_schedule_observation_echo("fast"), "the full delayed echo sequence is rejected when it would cross the round boundary")
	echo_spawner.set_phase_time_remaining(delayed_required)
	_check(echo_spawner.can_schedule_observation_echo("fast"), "the delayed echo sequence is accepted exactly when its last target remains payable")
	_check(echo_spawner._spawn_observation_echo_burst(echo_trigger) == 3 and echo_spawner.pending_echoes.size() == 3 and echo_layer.get_child_count() == 0, "Echo Delay Line queues all three channels instead of stacking them immediately")
	echo_spawner._update_pending_echoes(0.0)
	_check(echo_layer.get_child_count() == 1 and echo_spawner.pending_echoes.size() == 2, "Echo Delay Line releases its first target immediately")
	echo_spawner._update_pending_echoes(0.74)
	_check(echo_layer.get_child_count() == 1, "Echo Delay Line holds the second target until its declared interval")
	echo_spawner._update_pending_echoes(0.02)
	echo_spawner._update_pending_echoes(0.75)
	_check(echo_layer.get_child_count() == 3 and echo_spawner.pending_echoes.is_empty(), "Echo Delay Line releases the remaining targets in sequence inside the round")
	for delayed_echo_target in echo_layer.get_children():
		delayed_echo_target.free()
	_check(research_probe.debug_purchase_node("echo_deconfliction"), "Echo Deconfliction follows Wasat on one lower Pollux branch")
	var deconflicted_points: Array[Vector2] = []
	var deconflicted_starts_right: bool = true
	for echo_index in range(3):
		var deconflicted_plan: Dictionary = echo_spawner._plan_echo_entry("fast", echo_index, 3, echo_trigger_snapshot)
		deconflicted_points.append(Vector2(deconflicted_plan.burnout))
		deconflicted_starts_right = deconflicted_starts_right and float(Vector2(deconflicted_plan.start).x) > echo_view_size.x * 0.5
	var deconflicted_separation: bool = true
	for first_echo_index in range(deconflicted_points.size()):
		for second_echo_index in range(first_echo_index + 1, deconflicted_points.size()):
			deconflicted_separation = deconflicted_separation and deconflicted_points[first_echo_index].distance_to(deconflicted_points[second_echo_index]) > 80.0
	_check(deconflicted_separation and deconflicted_starts_right, "Echo Deconfliction separates burnout cells while preserving the mirrored entry side")
	_check(research_probe.debug_purchase_node("echo_beacon"), "Echo Beacon follows Wasat on the second lower Pollux branch")
	var beacon_required: float = echo_spawner._echo_required_phase_time("fast")
	echo_spawner.set_phase_time_remaining(beacon_required)
	_check(echo_spawner._spawn_observation_echo_burst(echo_trigger) == 3 and echo_spawner.pending_contacts.size() == 3 and echo_spawner.pending_echoes.is_empty(), "Echo Beacon routes all delayed targets through the standard forecast-contact pipeline")
	var standard_echo_contacts := true
	for echo_contact_variant in echo_spawner.pending_contacts:
		var echo_contact: Dictionary = echo_contact_variant
		standard_echo_contacts = standard_echo_contacts and bool(echo_contact.gemini_echo) and bool(echo_contact.classified) and echo_contact.has("error_offset") and echo_contact.has("intercept")
	_check(standard_echo_contacts, "Echo Beacon reuses the existing red-light contact vocabulary without a second overlay language")
	echo_spawner._update_pending_contacts(echo_spawner.ECHO_BEACON_LEAD - 0.01)
	_check(echo_layer.get_child_count() == 0 and echo_spawner.pending_contacts.size() == 3, "Echo Beacon keeps every target pending through its visible warning")
	echo_spawner._update_pending_contacts(0.02)
	_check(echo_layer.get_child_count() == 1 and bool(echo_layer.get_child(0).get_meta("gemini_echo", false)), "the first beacon resolves into a tagged non-recursive echo")
	echo_spawner._update_pending_contacts(2.0)
	var every_beacon_echo_tagged := echo_layer.get_child_count() == 3
	for beacon_echo_target in echo_layer.get_children():
		every_beacon_echo_tagged = every_beacon_echo_tagged and bool(beacon_echo_target.get_meta("gemini_echo", false))
	_check(every_beacon_echo_tagged and echo_spawner.pending_contacts.is_empty(), "all beacon contacts resolve as tagged echoes before the accepted boundary")
	for beacon_echo_target in echo_layer.get_children():
		beacon_echo_target.free()
	echo_trigger.free()
	var outburst_events = load("res://scripts/event_controller.gd").new()
	root.add_child(outburst_events)
	outburst_events.setup(echo_spawner, research_probe)
	echo_spawner.set_phase_time_remaining(10.0)
	_check(outburst_events.trigger_perseid_outburst(), "a purchased Perseid outburst starts when its complete warning and active window fit")
	outburst_events._update_perseid_outburst(outburst_events.PERSEID_OUTBURST_WARNING)
	for _outburst_step in range(100):
		outburst_events._update_perseid_outburst(0.05)
		if outburst_events.outburst_state == "idle":
			break
	var tagged_outburst_targets := 0
	for outburst_target in echo_layer.get_children():
		if bool(outburst_target.get_meta("perseid_outburst", false)):
			tagged_outburst_targets += 1
	_check(tagged_outburst_targets == outburst_events.PERSEID_OUTBURST_COUNT and outburst_events.outburst_state == "idle", "Perseid Outburst delivers exactly eight tagged targets inside one bounded event")
	var outburst_children_before_split := echo_layer.get_child_count()
	echo_spawner._on_fragment_requested(Vector2(420, 210), Vector2(90, 0), "fragment", false, false, true)
	var outburst_descendants_tagged := echo_layer.get_child_count() == outburst_children_before_split + 3
	for child_index in range(outburst_children_before_split, echo_layer.get_child_count()):
		outburst_descendants_tagged = outburst_descendants_tagged and bool(echo_layer.get_child(child_index).get_meta("perseid_outburst", false))
	_check(outburst_descendants_tagged, "Perseid fragment pieces retain the proc tag and cannot charge Leo or reopen Gemini")
	for outburst_target in echo_layer.get_children():
		outburst_target.free()
	outburst_events.free()
	_check(research_probe.debug_purchase_node("leonid_radiant") and research_probe.get_leonid_trigger_count() == 10 and research_probe.get_leonid_storm_count() == 8, "Leo opens with a ten-observation eight-meteor storm")
	_check(research_probe.debug_purchase_node("compressed_cadence") and research_probe.get_leonid_trigger_count() == 9 and research_probe.get_leonid_storm_count() == 8, "Leo's second node reduces the trigger to nine")
	_check(research_probe.debug_purchase_node("dense_stream") and research_probe.get_leonid_trigger_count() == 8 and research_probe.get_leonid_storm_count() == 12, "Leo's third node reaches eight observations and twelve meteors")
	_check(research_probe.debug_purchase_node("rapid_reacquisition") and research_probe.get_leonid_trigger_count() == 7 and research_probe.get_leonid_storm_count() == 12, "Leo's fourth node reduces the trigger to seven")
	_check(research_probe.debug_purchase_node("storm_front") and research_probe.get_leonid_trigger_count() == 6 and research_probe.get_leonid_storm_count() == 16, "Leo's fifth node reaches six observations and sixteen meteors")
	_check(research_probe.debug_purchase_node("leonid_storm") and research_probe.get_leonid_trigger_count() == 5 and research_probe.get_leonid_storm_count() == 20, "Leo's capstone reaches five observations and twenty meteors")
	var legacy_leo_probe = load("res://scripts/progression_controller.gd").new()
	legacy_leo_probe.load_save_data(research_probe.get_save_data())
	_check(legacy_leo_probe.has_upgrade("leonid_storm") and not legacy_leo_probe.has_upgrade("split_radiant_model") and legacy_leo_probe.get_leonid_storm_count() == 20, "a completed legacy Leo save keeps its original storm without gaining new composition research")
	legacy_leo_probe.free()
	_check(research_probe.debug_purchase_node("split_radiant_model"), "Split Radiant Model follows Regulus through prerequisites alone")
	_check(research_probe.debug_purchase_node("fragment_front"), "Fragment Front follows Chertan along the Leo body")
	_check(research_probe.debug_purchase_node("fireball_tail"), "Fireball Tail follows Zosma and completes the Leo body")
	_check(research_probe.get_leonid_trigger_count() == 5 and research_probe.get_leonid_storm_count() == 20, "Leo composition research changes storm shape without adding hidden count multipliers")
	for _charge in range(4):
		research_probe.record_leonid_manual_success()
	_check(not research_probe.leonid_storm_ready() and research_probe.leonid_charge == 4, "four fresh manual observations do not trigger the completed Leo storm")
	var leonid_save: Dictionary = research_probe.get_save_data()
	research_probe.leonid_charge = 0
	research_probe.load_save_data(leonid_save)
	_check(research_probe.leonid_charge == 4, "Leonid charge survives save and load between observation rounds")
	research_probe.record_leonid_manual_success()
	_check(research_probe.leonid_storm_ready(), "the fifth fresh manual observation arms the completed Leo storm")
	echo_spawner.set_phase_time_remaining(8.9)
	_check(not echo_spawner.try_start_leonid_storm(), "Leonid storms defer when fewer than nine round seconds remain")
	echo_spawner.set_phase_time_remaining(10.0)
	var leonid_children_before := echo_layer.get_child_count()
	_check(echo_spawner.try_start_leonid_storm(), "an armed Leonid storm starts with enough round time")
	_check(not echo_spawner.try_start_leonid_storm(), "an active Leonid storm cannot start a second queue")
	for _storm_step in range(200):
		echo_spawner._update_leonid_storm(0.05)
		if not echo_spawner.leonid_storm_active():
			break
	var leonid_children_after := echo_layer.get_child_count()
	var every_leonid_tagged := leonid_children_after == leonid_children_before + 20
	var alternating_radiants := true
	for child_index in range(leonid_children_before, leonid_children_after):
		var leonid_target = echo_layer.get_child(child_index)
		every_leonid_tagged = (
			every_leonid_tagged
			and bool(leonid_target.get_meta("leonid_storm", false))
			and String(leonid_target.type_id) in ["common", "fast", "fragment", "fireball"]
		)
		var storm_index := child_index - leonid_children_before
		var starts_left: bool = float(leonid_target.entry_position.x) <= echo_spawner.get_viewport().get_visible_rect().size.x * 0.5
		alternating_radiants = alternating_radiants and starts_left == (storm_index % 2 == 0)
	var first_storm_target = echo_layer.get_child(leonid_children_before)
	var last_storm_target = echo_layer.get_child(leonid_children_after - 1)
	_check(every_leonid_tagged and not echo_spawner.leonid_storm_active(), "the completed Leo body evenly delivers and tags exactly twenty bounded meteors")
	_check(alternating_radiants, "Split Radiant Model alternates the bounded storm between mirrored sky sectors")
	_check(String(first_storm_target.type_id) == "fragment" and String(last_storm_target.type_id) == "fireball", "Fragment Front and Fireball Tail bookend the storm without changing its count")
	_check(is_zero_approx(research_probe.get_automation_strength("fireball")), "the Leonid tail fireball remains a manual-only product")
	var leonid_children_before_split := echo_layer.get_child_count()
	echo_spawner._on_fragment_requested(Vector2(460, 240), Vector2(90, 0), "fragment", false, true, false)
	var leonid_descendants_tagged := echo_layer.get_child_count() == leonid_children_before_split + 3
	for child_index in range(leonid_children_before_split, echo_layer.get_child_count()):
		leonid_descendants_tagged = leonid_descendants_tagged and bool(echo_layer.get_child(child_index).get_meta("leonid_storm", false))
	_check(leonid_descendants_tagged, "Leonid fragment pieces retain the proc tag and cannot charge their own storm or reopen Gemini")
	research_probe.consume_leonid_storm_charge()
	_check(not research_probe.leonid_storm_ready() and research_probe.leonid_charge == 0, "starting a Leonid storm consumes its manual-observation charge")
	echo_spawner.free()
	echo_layer.free()
	for deep_type in ["satellite", "variable_star", "comet", "binary_star", "galaxy"]:
		var deep_spec: Dictionary = balance.meteor_spec(deep_type)
		_check(float(deep_spec.lifetime) >= 20.0 and float(deep_spec.lifetime) <= 40.0, "deep target stays within one round: " + deep_type)
		_check(float(deep_spec.track_time) / 1.42 < float(deep_spec.lifetime), "deep target has a payable same-round analysis window: " + deep_type)
	var spectral_meteor_script = load("res://scripts/meteor.gd")
	var unfiltered_probe = spectral_meteor_script.new()
	unfiltered_probe.configure(balance.meteor_spec("common"), "common", Vector2.ZERO, Vector2.RIGHT * 10.0, 1.0, {}, Vector2.RIGHT * 100.0)
	_check(is_equal_approx(unfiltered_probe.get_spectral_speed_multiplier(), 1.0) and is_equal_approx(unfiltered_probe.get_spectral_value_multiplier(), 1.0), "Lyra calibration is inert before its band research")
	var calibrated_probe = spectral_meteor_script.new()
	calibrated_probe.configure(balance.meteor_spec("common"), "common", Vector2.ZERO, Vector2.RIGHT * 10.0, 1.0, {"spectral_calibrated": true}, Vector2.RIGHT * 100.0)
	_check(calibrated_probe.get_spectral_speed_multiplier() == 1.25 and calibrated_probe.get_spectral_value_multiplier() == 1.15, "purchased Lyra bands passively calibrate matching targets")
	var capstone_spectral_probe = spectral_meteor_script.new()
	capstone_spectral_probe.configure(balance.meteor_spec("common"), "common", Vector2.ZERO, Vector2.RIGHT * 10.0, 1.0, {"spectral_calibrated": true, "spectral_capstone": true}, Vector2.RIGHT * 100.0)
	_check(capstone_spectral_probe.get_spectral_speed_multiplier() == 1.45 and capstone_spectral_probe.get_spectral_value_multiplier() == 1.35, "Lyrid Spectrograph strengthens automatic spectral calibration")
	research_probe.free()
	unfiltered_probe.free()
	calibrated_probe.free()
	capstone_spectral_probe.free()
	_check(not balance.upgrade_definition("observation_scheduling").is_empty(), "duration research is present in the tree")
	_check(int(balance.upgrade_definition("observation_scheduling").cost) == 150, "the first duration step uses the measured full-tree economy price")
	_check(int(balance.upgrade_definition("thermal_management").cost) == 450, "the second duration step uses the measured full-tree economy price")
	_check(int(balance.upgrade_definition("extended_watch_protocol").cost) == 700, "the third duration step uses the measured full-tree economy price")
	_check(int(balance.upgrade_definition("continuous_watch_rotation").cost) == 1000, "the fourth duration step uses the measured full-tree economy price")
	_check(int(balance.upgrade_definition("filter_wheel").cost) == 10000, "Calibration Framework remains cheaper than its Double-Star Resolution successor")
	_check(balance.upgrade_definition("wide_field").prerequisites == ["edge_detection"], "Wide Field stays inside the detection constellation")
	_check(balance.upgrade_definition("thermal_management").prerequisites == ["observation_scheduling"], "Thermal Management stays inside Orion's duration arm")
	_check(balance.upgrade_definition("continuous_watch_rotation").prerequisites == ["extended_watch_protocol"], "Continuous Watch Rotation stays inside Orion")
	var has_success_count_reveal_gate := false
	var has_prerequisite_price_inversion := false
	for research_definition in balance.UPGRADE_NODES:
		for reveal_gate in research_definition.hidden_until:
			if reveal_gate is Dictionary and String(reveal_gate.get("type", "")) == "success_count":
				has_success_count_reveal_gate = true
		for prerequisite_variant in research_definition.prerequisites:
			var prerequisite_definition: Dictionary = balance.upgrade_definition(String(prerequisite_variant))
			if int(research_definition.cost) < int(prerequisite_definition.cost):
				has_prerequisite_price_inversion = true
	_check(not has_success_count_reveal_gate, "the research graph has no hidden success-count reveal gates")
	_check(not has_prerequisite_price_inversion, "no research node costs less than its direct prerequisite")
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
	game.upgrade_tree._reset_view(false)
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
	var gemini_research_stars := 0
	for gemini_star_variant in chart_data.CONSTELLATIONS.gemini.stars:
		if not String(Dictionary(gemini_star_variant).get("node_id", "")).is_empty():
			gemini_research_stars += 1
	_check(gemini_research_stars == 10, "Gemini maps research across both complete bodies and can light every figure segment")
	var leo_research_stars := 0
	for leo_star_variant in chart_data.CONSTELLATIONS.leo.stars:
		if not String(Dictionary(leo_star_variant).get("node_id", "")).is_empty():
			leo_research_stars += 1
	_check(leo_research_stars == 9, "Leo maps research across all nine stars and can complete every figure segment")
	var taurus_research_stars := 0
	for taurus_star_variant in chart_data.CONSTELLATIONS.taurus.stars:
		if not String(Dictionary(taurus_star_variant).get("node_id", "")).is_empty():
			taurus_research_stars += 1
	_check(taurus_research_stars == 8, "Taurus maps Observation Streak research across all eight stars and every figure segment")
	var draco_research_stars := 0
	for draco_star_variant in chart_data.CONSTELLATIONS.draco.stars:
		if not String(Dictionary(draco_star_variant).get("node_id", "")).is_empty():
			draco_research_stars += 1
	_check(draco_research_stars == 9, "Draco maps its complete culmination chain across all nine stars")
	var deep_sky_marker_kinds := {}
	for marker_constellation_id in ["orion", "taurus", "andromeda"]:
		for marker_star_variant in chart_data.CONSTELLATIONS[marker_constellation_id].stars:
			var marker_star: Dictionary = marker_star_variant
			deep_sky_marker_kinds[String(marker_star.id)] = String(marker_star.kind)
	_check(String(deep_sky_marker_kinds.trapezium) == "cluster", "the Trapezium uses a cluster marker instead of a research-state disc")
	_check(String(deep_sky_marker_kinds.pleiades) == "cluster", "the Pleiades use an asymmetric point cluster instead of a node-like disc")
	_check(String(deep_sky_marker_kinds.andromeda_galaxy) == "galaxy", "M31 uses an elongated galaxy marker instead of a node-like disc")
	var leo_mid_visual = game.upgrade_tree.node_hold_bars["storm_front"]
	var leo_endpoint_visual = game.upgrade_tree.node_hold_bars["leonid_storm"]
	_check(not leo_mid_visual.branch_endpoint and leo_endpoint_visual.branch_endpoint, "research chart distinguishes a branch endpoint from its preceding installed star")
	_check(is_equal_approx(leo_mid_visual.purchased_glow_scale(), 2.35) and is_equal_approx(leo_endpoint_visual.purchased_glow_scale(), 2.75), "installed-star glows shrink while branch endpoints retain modest emphasis")
	var chart_node_stars: Dictionary = chart_data.node_star_map()
	var adjacent_internal_edges := true
	var all_prerequisites_internal := true
	for definition in balance.UPGRADE_NODES:
		var target_node_id := String(definition.id)
		var target_location: Dictionary = chart_node_stars[target_node_id]
		for prerequisite_variant in definition.prerequisites:
			var prerequisite_node_id := String(prerequisite_variant)
			var prerequisite_location: Dictionary = chart_node_stars[prerequisite_node_id]
			if String(prerequisite_location.constellation_id) != String(target_location.constellation_id):
				if not (prerequisite_node_id == "galactic_reference_frame" and target_node_id == "lmc_transit_watch"):
					all_prerequisites_internal = false
				continue
			if String(target_location.constellation_id) == "local_group":
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
	_check(all_prerequisites_internal, "research prerequisites stay within figures except the explicit Milky Way-to-Local-Group edge")
	_check(opening_optics.position != opening_detection.position and opening_detection.position != opening_network.position, "opening research nodes occupy distinct constellation positions")
	var optics_center_before := opening_optics.position + opening_optics.size * 0.5
	var optics_radius_before := optics_center_before.distance_to(game.upgrade_tree.CHART_ORIGIN)
	game.upgrade_tree._rotate_chart(game.upgrade_tree.ROTATION_STEP)
	var optics_center_after := opening_optics.position + opening_optics.size * 0.5
	_check(is_equal_approx(optics_radius_before, optics_center_after.distance_to(game.upgrade_tree.CHART_ORIGIN)), "mouse-wheel chart rotation preserves each star's polar radius")
	_check(absf((optics_center_before - game.upgrade_tree.CHART_ORIGIN).angle_to(optics_center_after - game.upgrade_tree.CHART_ORIGIN) - game.upgrade_tree.ROTATION_STEP) < 0.001, "research chart rotation changes only the global polar angle")
	game.upgrade_tree._reset_view(false)
	_check(is_zero_approx(game.upgrade_tree.rotation_offset), "research chart reset returns to north")
	_check(game.upgrade_tree.node_buttons["long_exposure"].visible and game.upgrade_tree.node_buttons["long_exposure"].get_meta("visual_state") == "teaser", "one upcoming system is previewed as an unresolved signal")
	_check(opening_optics.size == game.upgrade_tree.STAR_HIT_SIZE, "research stars use compact transparent point hit targets")
	_check(game.upgrade_tree.tooltip_panel.visible and not game.upgrade_tree.selected_node_id.is_empty(), "research chart opens with the reference-style fixed inspector selection")
	_check(game.upgrade_tree.constellation_ledger.visible and game.upgrade_tree.constellation_ledger_counts.size() == 16, "research chart includes the original twelve and four outer constellation rows")
	_check(game.upgrade_tree.tree_canvas.find_children("*", "Label", true, false).is_empty(), "constellation chart keeps node-name text out of the central playfield")
	game.upgrade_tree._on_node_hovered("edge_detection")
	_check(game.upgrade_tree.tooltip_panel.visible and game.upgrade_tree.hovered_node_id == "edge_detection" and game.upgrade_tree.selected_node_id == "edge_detection", "hovering a node updates the fixed constellation inspector")
	_check("북두칠성" in game.upgrade_tree.tooltip_branch.text, "research inspector localizes the selected constellation")
	_check("북두칠성" in game.upgrade_tree.completion_detail_label.text, "research header follows the fixed inspector's selected constellation")
	_check("β UMa" in game.upgrade_tree.tooltip_star.text, "research inspector identifies the real star and Bayer designation")
	_check(game.upgrade_tree.tooltip_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "research inspector never intercepts the star hit target")
	var tooltip_refreshes_before_motion: int = game.upgrade_tree.tooltip_content_refreshes
	var tooltip_style_id: int = game.upgrade_tree.tooltip_panel.get_theme_stylebox("panel").get_instance_id()
	var tooltip_position_before_motion: Vector2 = game.upgrade_tree.tooltip_panel.position
	var tooltip_motion := InputEventMouseMotion.new()
	tooltip_motion.relative = Vector2.ONE
	for _index in range(64):
		game.upgrade_tree._input(tooltip_motion)
	_check(game.upgrade_tree.tooltip_content_refreshes == tooltip_refreshes_before_motion and game.upgrade_tree.tooltip_panel.position == tooltip_position_before_motion, "cursor motion leaves the fixed research inspector stable")
	_check(game.upgrade_tree.tooltip_panel.get_theme_stylebox("panel").get_instance_id() == tooltip_style_id, "cursor motion reuses the research inspector style")
	game.upgrade_tree._on_node_unhovered("edge_detection")
	_check(game.upgrade_tree.tooltip_panel.visible and game.upgrade_tree.hovered_node_id.is_empty() and game.upgrade_tree.selected_node_id == "edge_detection", "leaving a node preserves the last fixed inspector selection")
	await process_frame
	game.upgrade_tree._on_node_hovered("edge_detection")
	_check(not game.upgrade_tree.tooltip_refit_pending, "re-entering a cached research selection needs no floating-panel refit")
	game.upgrade_tree._on_node_unhovered("edge_detection")
	game.upgrade_tree._on_node_hovered("better_lens")
	_check(game.upgrade_tree.tooltip_panel.visible, "research inspector is visible before chart rotation")
	game.upgrade_tree._rotate_chart(game.upgrade_tree.ROTATION_STEP)
	_check(game.upgrade_tree.tooltip_panel.visible and not game.upgrade_tree.tooltip_suppressed_until_motion, "rotating the sky keeps the fixed research inspector stable")
	game.upgrade_tree._on_node_unhovered("better_lens")
	game.upgrade_tree._on_node_hovered("edge_detection")
	_check(game.upgrade_tree.tooltip_panel.visible and game.upgrade_tree.selected_node_id == "edge_detection", "hovering after rotation updates the persistent inspector immediately")
	game.upgrade_tree._on_node_unhovered("edge_detection")
	game.upgrade_tree._reset_view(false)
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
	game.upgrade_tree._reset_view(false)
	var rotation_before_ctrl_wheel: float = game.upgrade_tree.rotation_offset
	var zoom_before_ctrl_wheel: float = game.upgrade_tree.zoom
	var ctrl_wheel := InputEventMouseButton.new()
	ctrl_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	ctrl_wheel.pressed = true
	ctrl_wheel.ctrl_pressed = true
	ctrl_wheel.position = game.upgrade_tree.content_clip.global_position + game.upgrade_tree.content_clip.size * 0.5
	game.upgrade_tree._on_tree_viewport_gui_input(ctrl_wheel)
	_check(is_equal_approx(game.upgrade_tree.rotation_offset, rotation_before_ctrl_wheel) and game.upgrade_tree.zoom > zoom_before_ctrl_wheel, "Ctrl+wheel zooms the research chart without rotating it")
	game.upgrade_tree._reset_view(false)
	var burst_rotation_before: float = game.upgrade_tree.rotation_offset
	var burst_layouts_before: int = game.upgrade_tree.chart_layout_passes
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	for _index in range(32):
		game.upgrade_tree._on_tree_viewport_gui_input(wheel_down)
	_check(game.upgrade_tree.chart_layout_passes == burst_layouts_before and is_equal_approx(game.upgrade_tree.rotation_offset, burst_rotation_before), "same-frame wheel events defer research layout work")
	game.upgrade_tree._process(0.0)
	var expected_burst_rotation := wrapf(burst_rotation_before + game.upgrade_tree.ROTATION_STEP * 32.0, -PI, PI)
	_check(game.upgrade_tree.chart_layout_passes == burst_layouts_before + 1, "same-frame wheel events coalesce into one research layout pass")
	_check(is_equal_approx(game.upgrade_tree.rotation_offset, expected_burst_rotation), "coalesced wheel input preserves the full final research rotation")
	game.upgrade_tree._reset_view(false)
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
	_check(game.upgrade_tree.pan_position == pan_before_left_drag, "left-dragging empty sky does not move the framed research chart")
	game.upgrade_tree.close_tree()
	_check(not paused, "closing the upgrade tree resumes gameplay")
	var hidden_star_animation_stopped := true
	for star_visual_variant in game.upgrade_tree.node_hold_bars.values():
		var star_visual: Control = star_visual_variant
		if star_visual.is_processing():
			hidden_star_animation_stopped = false
	_check(hidden_star_animation_stopped, "closing research stops hidden star animation processing")

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
	game.hud.set_tracking(0.4, "common", 1.0, game.observer._valid_tracked_count(), Vector2(400.0, 300.0))
	_check(game.hud.tracking_cluster.visible and game.hud.tracking_cluster.cursor == Vector2(400.0, 300.0), "the tracking cluster follows the cursor")
	_check("40%" in game.hud.tracking_percent.text, "the cursor cluster reports tracking progress")
	var tracking_layouts_after_first_update: int = game.hud.tracking_layout_passes
	game.hud.set_tracking(0.4, "common", 1.0, game.observer._valid_tracked_count(), Vector2(400.0, 300.0))
	_check(game.hud.tracking_layout_passes == tracking_layouts_after_first_update, "unchanged tracking data skips cursor text layout")
	game.hud.set_tracking(0.4, "common", 1.0, game.observer._valid_tracked_count(), Vector2(401.0, 300.0))
	_check(game.hud.tracking_layout_passes == tracking_layouts_after_first_update + 1, "moving the tracking cursor updates layout once")
	game.hud.set_tracking(0.8, "common", 1.0, 1, Vector2(400, 300), 36.0, 0.1)
	_check(game.hud.tracking_percent.text == "80%" and game.hud.tracking_quality.text == TranslationServer.translate("HUD_AIM_EDGE"), "high completion with weak alignment reports edge aim, not an excellent grade")
	game.hud.set_tracking(0.8, "common", 1.0, 1, Vector2(400, 300), 36.0, 1.0)
	_check(game.hud.tracking_quality.text == TranslationServer.translate("HUD_AIM_CENTER"), "aim feedback changes without a progress change")
	game.hud.set_tracking(1.0, "common", 1.0, 1, Vector2(400, 300), 36.0, 0.0)
	_check(game.hud.tracking_quality.text == TranslationServer.translate("HUD_AIM_LOST"), "full progress cannot manufacture a perfect grade or hide lost aim")
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
	_check(game.progression.upgrade_level == 1, "the first purchase registers on the research chart counter")
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
	_check(game.progression.get_node_state("wide_field") == "available", "Edge Detection opens its own constellation's Wide Field path")
	game.progression.debug_purchase_node("array_planning")
	game.progression.debug_purchase_node("observation_scheduling")
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
	_check(not game.sky_contacts.dish_active(), "a pre-dish contact remains non-interactive")
	_check(float(wide_contact.lead_time) == 2.0, "Wide Field Sensor provides two seconds of warning")
	_check(float(wide_contact.max_error) == 70.0, "Wide Field Sensor begins with the baseline error envelope")
	_check(not bool(wide_contact.classified), "Wide Field Sensor contacts begin unclassified")
	_check(not bool(wide_contact.trajectory_known), "Wide Field Sensor alone does not reveal the approach vector")

	# Capacity contracts apply only to live atmospheric work. Long-lived deep
	# objects and pending forecast information must not consume the regular sky
	# budget, while a genuinely full atmospheric sky still delays the scheduler.
	game.spawner.reset()
	await process_frame
	await process_frame
	game.spawner.spawn_meteor("satellite", Vector2(240, 180), Vector2.ZERO, 20.0)
	for _forecast_index in range(game.progression.get_max_active() + 2):
		game.spawner._announce_regular_spawn()
	_check(game.spawner._regular_active_count() == 0, "deep targets stay outside the live regular-contact capacity scope")
	var pending_before_scope_probe: int = game.spawner.pending_contacts.size()
	game.spawner.running = true
	game.spawner.first_spawn_pending = false
	game.spawner.next_spawn_time = 0.0
	game.spawner.set_phase_time_remaining(30.0)
	game.spawner._process(0.05)
	_check(
		game.spawner.pending_contacts.size() == pending_before_scope_probe + 1,
		"pending forecasts and live deep targets do not suppress the next regular announcement"
	)
	game.spawner.reset()
	await process_frame
	await process_frame
	for _regular_index in range(game.progression.get_max_active()):
		game.spawner.spawn_meteor("common", Vector2(180 + _regular_index * 30, 190), Vector2.ZERO, 20.0)
	_check(game.spawner._regular_active_count() == game.progression.get_max_active(), "live atmospheric targets fill the declared regular-contact capacity")
	game.spawner.running = true
	game.spawner.first_spawn_pending = false
	game.spawner.next_spawn_time = 0.0
	game.spawner.set_phase_time_remaining(30.0)
	game.spawner._process(0.05)
	_check(game.spawner.pending_contacts.is_empty() and is_equal_approx(game.spawner.next_spawn_time, 0.45), "a full live atmospheric sky still delays the regular scheduler")
	game.spawner.reset()
	game.sky_contacts.reset()
	await process_frame
	await process_frame
	game.spawner.set_phase_time_remaining(30.0)
	game.spawner._announce_regular_spawn()

	_check(game.progression.debug_purchase_node("contact_ledger"), "Contact Ledger completes the Big Dipper approach to Trajectory Prediction")
	game.spawner._announce_regular_spawn()
	var ledger_contact: Dictionary = game.spawner.pending_contacts[1]
	_check(float(ledger_contact.max_error) == 58.0, "Contact Ledger narrows uncertainty without adding per-contact metrics text")
	game.progression.debug_purchase_node("trajectory")
	game.spawner._announce_regular_spawn()
	var trajectory_contact: Dictionary = game.spawner.pending_contacts[2]
	_check(float(trajectory_contact.max_error) < float(wide_contact.max_error), "Trajectory Prediction strictly shrinks forecast error")
	_check(float(trajectory_contact.max_error) == 40.0, "Trajectory Prediction caps the uncertainty envelope at forty pixels")
	_check(trajectory_contact.error_offset.length() >= 14.0 and trajectory_contact.error_offset.length() <= 40.0, "Trajectory Prediction samples offsets inside its upgraded envelope")
	_check(bool(trajectory_contact.trajectory_known), "Trajectory Prediction reveals the contact approach vector")
	_check(not bool(trajectory_contact.classified), "Trajectory Prediction does not classify contacts by itself")

	game.progression.debug_purchase_node("rare_detection")
	game.spawner._announce_regular_spawn()
	var classified_contact: Dictionary = game.spawner.pending_contacts[3]
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
	_check(not game.progression.dish_auto_assignment_enabled(), "dish auto-assignment remains unavailable before its research")
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
	var ready_dish: Dictionary = game.sky_contacts.dishes[0]
	ready_dish.position = ready_dish.target
	ready_dish.arrived = true
	game.sky_contacts.dishes[0] = ready_dish

	for prerequisite_id in ["edge_detection", "observation_scheduling", "wide_field", "trajectory"]:
		game.progression.debug_purchase_node(prerequisite_id)
	var pacing_ratio_before_predictive_control: float = game.progression.get_progression_ratio()
	game.progression.debug_purchase_node("predictive_dish_control")
	_check(game.progression.dish_auto_assignment_enabled(), "Predictive Dish Control unlocks automatic pre-positioning after the manual layer")
	_check(is_equal_approx(game.progression.get_progression_ratio(), pacing_ratio_before_predictive_control), "new dish interaction research does not silently retune spawn density")
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "research does not retroactively seize an existing contact")
	game.spawner._announce_regular_spawn()
	var automatic_contact: Dictionary = game.spawner.pending_contacts[1]
	_check(int(game.sky_contacts.dishes[0].assigned_id) == int(automatic_contact.id), "an idle dish automatically pre-positions for a new trackable forecast")
	_check(not bool(game.sky_contacts.dishes[0].arrived), "automatic pre-positioning still has to pay its slew time")
	game.spawner._announce_regular_spawn()
	var second_contact: Dictionary = game.spawner.pending_contacts[2]
	_check(int(game.sky_contacts.dishes[0].assigned_id) == int(automatic_contact.id), "automatic control never steals a busy dish for a newer contact")
	var cancellation_point := pointer_position + Vector2(210.0, 90.0)
	var shifted_right_click := InputEventMouseButton.new()
	shifted_right_click.button_index = MOUSE_BUTTON_RIGHT
	shifted_right_click.pressed = true
	shifted_right_click.shift_pressed = true
	shifted_right_click.position = cancellation_point
	game.sky_contacts._unhandled_input(shifted_right_click)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "right-click manual placement overrides automatic pre-positioning")
	_check(Vector2(game.sky_contacts.dishes[0].target).is_equal_approx(cancellation_point), "Shift adds no reservation gesture and obeys the same point movement")
	var settled_dish: Dictionary = game.sky_contacts.dishes[0]
	settled_dish.position = cancellation_point
	settled_dish.arrived = true
	game.sky_contacts.dishes[0] = settled_dish
	var fireball_contact: Dictionary = second_contact.duplicate(true)
	fireball_contact.id = 9001
	fireball_contact.type_id = "fireball"
	fireball_contact.classified = true
	fireball_contact.abandoned_flash = 0.0
	fireball_contact.intercept = cancellation_point + Vector2(160.0, 0.0)
	fireball_contact.error_offset = Vector2.ZERO
	game.sky_contacts.on_contact_announced(fireball_contact)
	_check(int(game.sky_contacts.dishes[0].assigned_id) == -1, "automatic control ignores manual-only fireball forecasts")
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
	var meteor_activity_rect: Rect2 = game.observation_view.meteor_activity_rect()
	var burnout_safe_rect: Rect2 = game.spawner._burnout_safe_rect(meteor_activity_rect)
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
				reachability_type, meteor_activity_rect, extreme_distance
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
				is_equal_approx(planned_start.y, meteor_activity_rect.position.y - game.spawner.ENTRY_MARGIN)
				or is_equal_approx(planned_start.x, meteor_activity_rect.position.x - game.spawner.ENTRY_MARGIN)
				or is_equal_approx(planned_start.x, meteor_activity_rect.end.x + game.spawner.ENTRY_MARGIN)
			)
			_check(allowed_entry and not is_equal_approx(planned_start.y, meteor_activity_rect.end.y + game.spawner.ENTRY_MARGIN), "%s uses only top/side entry boundaries" % burnout_type)
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
	for visibility_type in ["common", "fast", "fragment", "fragment_piece", "fireball", "major", "satellite", "variable_star", "comet", "binary_star", "galaxy"]:
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

	# Assigned rare contacts and nearby contactless major objects both remain
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
	_check(game.progression.upgrade_level == balance.research_node_count(), "all functional tree nodes unlock through prerequisite-safe debug purchase")
	_check(game.progression.is_research_complete(), "the progression controller recognizes the complete research graph")
	_check(is_equal_approx(game.progression.get_observation_value_multiplier("common", 1), 8192.0), "the eight legacy leaves and two Draco multipliers produce exact unconditional x8192 observation value growth")
	_check(game.progression.galaxy_unlocked() and game.starfield.galactic_mode, "the final Draco purchase switches the live sky into its galactic visual state")
	_check(game.events.canis_major_state == "idle", "purchasing Sirius during a live round waits until the next round to schedule its event")
	var completed_save_probe = load("res://scripts/progression_controller.gd").new()
	completed_save_probe.load_save_data(game.progression.get_save_data())
	_check(completed_save_probe.is_research_complete() and completed_save_probe.galaxy_unlocked() and is_equal_approx(completed_save_probe.get_observation_value_multiplier("common", 1), 8192.0), "ID-based completed saves retain every purchased node and the galactic x8192 endpoint")
	completed_save_probe.free()
	game.upgrade_tree._refresh()
	await process_frame
	var installed_research_segments := 0
	var all_research_segments_installed := true
	var chart_ui_theme = load("res://scripts/ui_theme.gd")
	for installed_constellation_id in chart_data.CONSTELLATIONS:
		var installed_constellation: Dictionary = chart_data.CONSTELLATIONS[installed_constellation_id]
		if not installed_constellation.has("branch"):
			continue
		for installed_segment_variant in installed_constellation.segments:
			var installed_segment: Array = installed_segment_variant
			var installed_states: PackedStringArray = game.upgrade_tree._segment_states(String(installed_constellation_id), installed_segment)
			installed_research_segments += 1
			all_research_segments_installed = (
				all_research_segments_installed
				and installed_states[0] == "purchased"
				and installed_states[1] == "purchased"
				and game.upgrade_tree._segment_color(installed_states) == Color(chart_ui_theme.LINE_INSTALLED, 0.42)
			)
	_check(installed_research_segments == 91 and all_research_segments_installed, "all ninety-one research-constellation segments reach the installed color at full completion")
	_check(game.progression.get_max_active() == 18, "the completed Draco array raises the regular active-sky cap from twelve to eighteen")
	_check(is_equal_approx(game.progression.get_regular_spawn_interval_floor(), 0.45), "the completed Draco array lowers the regular-arrival floor from 0.70 to 0.45 seconds")
	_check(game.progression.upgrade_level == balance.research_node_count(), "the run resolves to the full functional research completion")
	_check(is_equal_approx(game.progression.get_progression_ratio(), 1.0), "the original pacing topology preserves the completed-tree density endpoint")
	for legacy_id in ["better_lens", "long_exposure", "wide_field", "trajectory", "precision_multiplier", "secondary_camera", "shower_detector", "automated_tracking"]:
		_check(game.progression.has_upgrade(legacy_id), "legacy upgrade migrated: " + legacy_id)
	_check(game.progression.has_upgrade("automated_tracking"), "final automation system is active")
	_check(game.progression.get_secondary_slots() == 4, "Total Array expands automatic support from two lanes to four")
	_check(game.progression.get_dish_count() == 4, "Total Array expands steerable dish capacity from two to four")
	_check(game.sky_contacts.dishes.size() == 4, "purchasing Total Array places all four steerable dishes")
	var all_draco_dishes_on_screen := true
	for draco_dish_variant in game.sky_contacts.dishes:
		var draco_dish: Dictionary = draco_dish_variant
		all_draco_dishes_on_screen = all_draco_dishes_on_screen and float(Vector2(draco_dish.position).x) > 0.0 and float(Vector2(draco_dish.position).x) < 1152.0
	_check(all_draco_dishes_on_screen, "the four-dish home layout keeps every Total Array dish on screen")
	_check(game.progression.dish_auto_assignment_enabled(), "completed research includes automatic Predictive Dish Control")
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
	# Additive machine sources must not reopen the major-value regression. The
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
	_check(game.progression.get_node_state("perfect_observation") == "purchased", "internal optics capstone resolves")
	_check(game.progression.get_node_state("observatory_network") == "purchased", "internal Orion capstone resolves")
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

	game.spawner.canis_major_spawned_this_round = false
	game.events.canis_major_state = "idle"
	_check(game.events.trigger_canis_major_warning(), "Sirius Bloom begins with the existing atmospheric warning")
	_check(not game.spawner.pause_regular_spawns, "the Canis warning leaves ordinary arrivals running")
	_check(not game.events.trigger_canis_major_warning(), "a warning already in progress cannot be triggered twice")
	_check(not game.events.trigger_shower(), "a shower cannot overwrite the short Canis warning")
	game.events.canis_major_timer = -1.0
	await process_frame
	var major_count := 0
	for child in game.meteor_layer.get_children():
		if child.has_method("is_major") and child.is_major():
			major_count += 1
	_check(major_count == 1, "Sirius Bloom spawns exactly one Major Fireball")
	_check(game.spawner.try_spawn_canis_major_fireball() == null, "the spawner-owned round guard rejects a second Canis Major Fireball")
	await process_frame
	var major_count_after := 0
	for child in game.meteor_layer.get_children():
		if child.has_method("is_major") and child.is_major():
			major_count_after += 1
	_check(major_count_after == 1, "the Canis Major Fireball cannot be emitted twice in one round")
	var canis_consumed_save: Dictionary = game._build_save_data()
	_check(bool(canis_consumed_save.get("canis_major_spawned_this_round", false)), "an active-round save records that Sirius was already emitted")
	game._apply_save_data(canis_consumed_save)
	await process_frame
	_check(game.spawner.canis_major_spawned_this_round and game.events.canis_major_state == "resolved", "loading that round cannot schedule a second Sirius event")

	game.reset_run()
	await process_frame
	await process_frame
	var reset_state: Dictionary = game.get_debug_snapshot()
	_check(reset_state.data == 0.0, "reset clears Observation Data")
	_check(reset_state.successes == 0, "reset clears observation count")
	_check(reset_state.upgrade_level == 0, "reset clears progression")
	_check(reset_state.purchased_nodes.is_empty(), "reset clears purchased tree node state")
	_check(reset_state.shower_state == "idle", "reset clears shower state")
	_check(reset_state.canis_major_state == "idle" and not game.spawner.canis_major_spawned_this_round, "reset clears the Canis event schedule and round guard")
	_check(reset_state.observation_round == 1 and reset_state.observation_phase_active, "reset returns to the first observation round")
	_check(absf(float(reset_state.observation_phase_remaining) - 20.0) < 1.0, "reset restores the base 20-second round")
	_check(game._observation_duration() == 20.0, "the base observation window is 20 seconds")
	_check(game.progression.debug_purchase_node("array_planning"), "Array Planning opens duration research")
	_check(game.progression.debug_purchase_node("observation_scheduling") and game._observation_duration() == 30.0, "Observation Scheduling extends future rounds to 30 seconds")
	_check(game.progression.debug_purchase_node("edge_detection"), "Edge Detection opens the gated detection path")
	_check(game.progression.debug_purchase_node("wide_field"), "Edge Detection allows its internal Wide Field successor")
	_check(game.progression.debug_purchase_node("contact_ledger"), "Edge Detection opens the alternate Big Dipper ledger path")
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
	_check(
		game.upgrade_tree.close_button.text
		== TranslationServer.translate("TREE_START_OBSERVATION") % game.settings.binding_label(&"nw_chart"),
		"upgrade break close action is labeled as starting observation"
	)
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
			game.spawner._on_fragment_requested(Vector2(480, 220), Vector2(80, 0), "major", false)
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

	var open_night_game = packed.instantiate()
	open_night_game.startup_slot_prompt_enabled = false
	open_night_game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(open_night_game)
	await process_frame
	await process_frame
	open_night_game.set_process(false)
	open_night_game.save_games.set_save_directory(smoke_save_directory)
	open_night_game.active_save_slot = 1
	open_night_game.hud.set_active_save_slot(1)
	open_night_game._autosave_active_slot()
	open_night_game.events.run_time = 999999.0
	open_night_game.events._process(0.05)
	_check(open_night_game.events.canis_major_state == "idle", "elapsed run time cannot summon Sirius before its research is installed")
	open_night_game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_NORMAL and open_night_game.upgrade_tree.zoom >= open_night_game.upgrade_tree.MIN_ZOOM, "the pre-unlock research chart opens in its normal player zoom range")
	# The catalogue ending requires both semantic records. Neither side alone may
	# close the sky, and a final purchase in a live mixed-build round must wait
	# for one observation that began with the complete array.
	for target_id_variant in open_night_game.galactic_phenomena.TARGET_SPECS:
		open_night_game.galactic_phenomena.completed_targets[String(target_id_variant)] = true
	open_night_game.galactic_phenomena.refresh_unlock_state()
	open_night_game._refresh_catalogue_ending_requirement()
	_check(
		open_night_game.galactic_phenomena.is_record_complete()
		and not open_night_game.progression.is_research_complete()
		and not open_night_game._catalogue_record_complete()
		and not open_night_game.ending_final_watch_pending,
		"five galactic phenomena without the research tree cannot arm the catalogue ending"
	)
	open_night_game.galactic_phenomena.completed_targets.clear()
	open_night_game.galactic_phenomena.refresh_unlock_state()
	open_night_game.progression.debug_purchase_all()
	_check(
		open_night_game.progression.is_research_complete()
		and not open_night_game.galactic_phenomena.is_record_complete()
		and not open_night_game._catalogue_record_complete()
		and not open_night_game.ending_final_watch_pending,
		"the complete research tree without all phenomena cannot arm the catalogue ending"
	)
	for target_id_variant in open_night_game.galactic_phenomena.TARGET_SPECS:
		open_night_game.galactic_phenomena.completed_targets[String(target_id_variant)] = true
	open_night_game.galactic_phenomena.refresh_unlock_state()
	open_night_game._refresh_catalogue_ending_requirement()
	_check(
		open_night_game._catalogue_record_complete()
		and open_night_game.ending_final_watch_pending
		and not open_night_game.phase_started_with_complete_research,
		"completing the catalogue inside a mixed-build round arms one full-array final watch"
	)
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_PULLBACK and not open_night_game.galactic_pullback_seen, "buying Galactic Reference Frame in the open chart starts the one-time pull-back")
	var purchase_release := InputEventMouseButton.new()
	purchase_release.button_index = MOUSE_BUTTON_LEFT
	purchase_release.pressed = false
	open_night_game.upgrade_tree._input(purchase_release)
	open_night_game.upgrade_tree._input(InputEventMouseMotion.new())
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_PULLBACK, "the purchase release and passive pointer jitter do not skip the pull-back")
	open_night_game.upgrade_tree._advance_galactic_pullback(1.35)
	var overlap_legacy_alpha: float = open_night_game.upgrade_tree._node_presentation_alpha("better_lens")
	_check(
		is_equal_approx(overlap_legacy_alpha, 1.0) and is_zero_approx(open_night_game.upgrade_tree._local_group_alpha()),
		"the original stars remain visible as the outer constellations are revealed"
	)
	_check(open_night_game.upgrade_tree._galactic_background_alpha() < 0.01, "the sparse galactic background waits until the legacy chart has nearly cleared")
	_check(
		is_zero_approx(open_night_game.upgrade_tree._node_presentation_alpha("lmc_transit_watch")),
		"retired galaxy research remains invisible during the transition"
	)
	var pullback_skip := InputEventKey.new()
	pullback_skip.keycode = KEY_SPACE
	pullback_skip.pressed = true
	open_night_game.upgrade_tree._input(pullback_skip)
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_FINAL and open_night_game.galactic_pullback_seen, "a deliberate input skips to the same saved galactic final state")
	_check(is_equal_approx(open_night_game.upgrade_tree.zoom, 0.43) and open_night_game.upgrade_tree.zoom < open_night_game.upgrade_tree.MIN_ZOOM, "the wider constellation view fits the new outer stars")
	var visible_galactic_buttons := 0
	for galactic_button_variant in open_night_game.upgrade_tree.node_buttons.values():
		if galactic_button_variant.visible:
			visible_galactic_buttons += 1
	_check(visible_galactic_buttons > 18, "the expanded chart keeps original and outer star hit targets together")
	_check(
		open_night_game.upgrade_tree.galactic_background_stars.size() == open_night_game.upgrade_tree.GALACTIC_BACKGROUND_STAR_COUNT,
		"the final galaxy frame retains exactly 74 sparse non-interactive background stars"
	)
	var galactic_background_clear := true
	for background_star_variant in open_night_game.upgrade_tree.galactic_background_stars:
		var background_star := Vector2(background_star_variant)
		var background_offset: Vector2 = background_star - open_night_game.upgrade_tree.GALACTIC_MAP_CENTER_SPEC * open_night_game.upgrade_tree.UITheme.SCALE
		var exclusion_distance := Vector2(
			background_offset.x / (open_night_game.upgrade_tree.GALACTIC_BACKGROUND_EXCLUSION_SPEC.x * open_night_game.upgrade_tree.UITheme.SCALE),
			background_offset.y / (open_night_game.upgrade_tree.GALACTIC_BACKGROUND_EXCLUSION_SPEC.y * open_night_game.upgrade_tree.UITheme.SCALE)
		).length()
		if exclusion_distance < 1.0:
			galactic_background_clear = false
			break
	_check(galactic_background_clear, "galactic background stars stay outside the route and node exclusion ellipse")
	_check(not open_night_game.upgrade_tree.galactic_panel.visible and not open_night_game.upgrade_tree.galactic_ledger.visible and open_night_game.upgrade_tree.constellation_ledger.visible, "the expanded constellation chart keeps its original inspector and ledger")
	_check(not open_night_game.upgrade_tree.galactic_core_hit.visible and open_night_game.upgrade_tree.galactic_core_hit.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the old galactic core cannot intercept destination input")
	_check(
		not Vector2(open_night_game.upgrade_tree.node_positions["galactic_reference_frame"]).is_equal_approx(open_night_game.upgrade_tree.CHART_ORIGIN),
		"the original research coordinates are preserved instead of collapsing to one point"
	)
	open_night_game.upgrade_tree._zoom_at(open_night_game.upgrade_tree.content_clip.global_position + open_night_game.upgrade_tree.content_clip.size * 0.5, 4.0)
	var readable_chart_buttons := 0
	for chart_button_variant in open_night_game.upgrade_tree.node_buttons.values():
		if chart_button_variant.visible and chart_button_variant.mouse_filter == Control.MOUSE_FILTER_STOP:
			readable_chart_buttons += 1
	_check(open_night_game.upgrade_tree.zoom >= open_night_game.upgrade_tree.MIN_ZOOM and readable_chart_buttons > 0, "Ctrl+wheel zoom restores the completed chart hit targets and record view")
	open_night_game.upgrade_tree._zoom_at(open_night_game.upgrade_tree.content_clip.global_position + open_night_game.upgrade_tree.content_clip.size * 0.5, 0.01)
	open_night_game.upgrade_tree._reset_view(false)
	open_night_game.upgrade_tree._on_content_resized()
	await process_frame
	_check(is_equal_approx(open_night_game.upgrade_tree.zoom, 0.43) and open_night_game.upgrade_tree.galactic_chart_detail == 1.0, "reset and resize frame the expanded constellations")
	var seen_galactic_save: Dictionary = open_night_game._build_save_data()
	_check(bool(seen_galactic_save.get("galactic_pullback_seen", false)), "the completed or skipped pull-back is present in the flat game save")
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(open_night_game.events.canis_major_state == "idle", "completing research inside a live observation round does not interrupt that round")
	open_night_game._end_observation_phase()
	_check(not open_night_game.observation_phase_active, "a completed tree reaches the ordinary round summary")
	open_night_game._on_phase_summary_continue_requested()
	await process_frame
	await process_frame
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_FINAL and is_equal_approx(open_night_game.upgrade_tree.zoom, 0.43), "a seen reveal reopens the expanded chart without replaying")
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(
		open_night_game.observation_phase_active
		and open_night_game.observation_round == 2
		and open_night_game.phase_started_with_complete_research
		and open_night_game.ending_final_watch_pending
		and not open_night_game.hud.is_end_open(),
		"closing the chart after a mixed-build completion starts exactly one full-array final watch"
	)
	_check(open_night_game.events.canis_major_state == "scheduled", "the next viable round randomizes one warned Sirius event")
	open_night_game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	var open_night_chart_binding: String = open_night_game.settings.binding_label(&"nw_chart")
	_check(
		open_night_game.upgrade_tree.completion_detail_label.text != TranslationServer.translate("TREE_CATALOGUE_FINAL_WATCH_DETAIL")
		and open_night_game.upgrade_tree.close_button.text == TranslationServer.translate("TREE_CLOSE") % open_night_chart_binding
		and open_night_game.upgrade_tree.constellation_bottom_action.text == TranslationServer.translate("TREE_BOTTOM_CLOSE") % open_night_chart_binding
		and open_night_game.upgrade_tree.galactic_return_hint.text == TranslationServer.translate("TREE_GALACTIC_RETURN") % open_night_chart_binding
		and not open_night_game.upgrade_tree.data_context_label.visible,
		"an active final watch hides pending-watch copy and keeps ordinary chart-close actions"
	)
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(open_night_game.observation_phase_active and open_night_game.observation_round == 2, "reviewing the chart during the final watch resumes that same round")
	var active_final_watch_save: Dictionary = open_night_game._build_save_data()
	_check(
		bool(active_final_watch_save.get("observation_phase_active", false))
		and bool(active_final_watch_save.get("phase_started_with_complete_research", false))
		and bool(active_final_watch_save.get("ending_final_watch_pending", false)),
		"an active final-watch save retains the complete-array qualification evidence"
	)
	var tampered_final_watch_save: Dictionary = active_final_watch_save.duplicate(true)
	var tampered_phase_signature: Array = tampered_final_watch_save["phase_start_upgrade_signature"].duplicate()
	tampered_phase_signature.pop_back()
	tampered_final_watch_save["phase_start_upgrade_signature"] = tampered_phase_signature
	tampered_final_watch_save["phase_started_with_complete_research"] = true
	open_night_game._apply_save_data(tampered_final_watch_save)
	_check(
		open_night_game.observation_phase_active
		and not open_night_game.phase_started_with_complete_research
		and open_night_game.ending_final_watch_pending,
		"a true final-watch flag cannot override an incomplete validated phase-start signature"
	)
	open_night_game._apply_save_data(active_final_watch_save)
	_check(
		open_night_game.observation_phase_active
		and open_night_game.phase_started_with_complete_research
		and open_night_game.ending_final_watch_pending
		and open_night_game._catalogue_record_complete(),
		"loading an active final watch preserves its qualification through the rest of that round"
	)
	var final_phenomenon_id := String(open_night_game.galactic_phenomena.TARGET_SPECS.keys().back())
	open_night_game.galactic_phenomena.completed_targets.erase(final_phenomenon_id)
	open_night_game._refresh_catalogue_ending_requirement()
	_check(not open_night_game._catalogue_record_complete(), "the final-watch round remains non-terminal until its last phenomenon is recorded")
	open_night_game.galactic_phenomena.completed_targets[final_phenomenon_id] = true
	open_night_game._refresh_catalogue_ending_requirement()
	_check(
		open_night_game._catalogue_record_complete() and not open_night_game.ending_final_watch_pending,
		"a last phenomenon recorded during a full-research round lets that same round qualify"
	)
	open_night_game._end_observation_phase()
	_check(
		not open_night_game.observation_phase_active
		and open_night_game.hud.is_phase_summary_open()
		and not open_night_game.ending_final_watch_pending
		and open_night_game._catalogue_ending_ready(),
		"the full-array final watch reaches its ordinary summary before arming the ending"
	)
	var unseen_ending_save: Dictionary = open_night_game._build_save_data()
	_check(
		not bool(unseen_ending_save.get("catalogue_ending_seen", true))
		and not bool(unseen_ending_save.get("ending_final_watch_pending", true))
		and not bool(unseen_ending_save.get("observation_phase_active", true)),
		"an unseen ending save preserves the ready intermission without pretending it was acknowledged"
	)
	open_night_game._on_phase_summary_continue_requested()
	await process_frame
	await process_frame
	_check(
		open_night_game.upgrade_tree.is_open()
		and open_night_game.upgrade_tree.completion_detail_label.text == TranslationServer.translate("TREE_CATALOGUE_ENDING_READY_DETAIL")
		and open_night_game.upgrade_tree.close_button.text == TranslationServer.translate("TREE_CATALOGUE_SEAL_RECORD") % open_night_chart_binding
		and open_night_game.upgrade_tree.constellation_bottom_action.text == TranslationServer.translate("TREE_BOTTOM_CATALOGUE_SEAL_RECORD") % open_night_chart_binding
		and open_night_game.upgrade_tree.galactic_return_hint.text == TranslationServer.translate("TREE_BOTTOM_CATALOGUE_SEAL_RECORD") % open_night_chart_binding
		and not open_night_game.upgrade_tree.data_context_label.visible,
		"the completed chart labels both exits as sealing the record instead of advertising another observation"
	)
	var ending_round: int = int(open_night_game.observation_round)
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(
		open_night_game.completed
		and open_night_game.hud.is_end_open()
		and paused
		and not open_night_game.observation_phase_active
		and open_night_game.observation_round == ending_round,
		"closing the completed chart shows the paused catalogue ending without starting another round"
	)
	_check(
		open_night_game.hud.end_title.text == TranslationServer.translate("HUD_END_TITLE")
		and open_night_game.hud.end_body.text == TranslationServer.translate("HUD_END_BODY")
		and open_night_game.hud.end_finish_button.text == TranslationServer.translate("HUD_END_FINISH")
		and open_night_game.hud.end_continue_button.text == TranslationServer.translate("HUD_END_CONTINUE")
		and open_night_game.hud.end_stats.text.split("\n").size() == 7
		and open_night_game.hud.end_finish_button.disabled
		and open_night_game.hud.end_continue_button.disabled
		and open_night_game.hud.end_coda.visible
		and open_night_game.hud.end_coda.is_processing()
		and open_night_game.hud.end_coda.route_progress < 1.0
		and is_equal_approx(open_night_game.hud.end_actions.modulate.a, 0.0),
		"the ending begins an animated neutral record with active-time statistics and two non-destructive choices"
	)
	var reveal_tween_before_locale_refresh: Tween = open_night_game.hud.end_reveal_tween
	var refreshed_stats_probe := "REFRESHED CATALOGUE STATS"
	open_night_game.hud.refresh_catalogue_ending_text(refreshed_stats_probe)
	_check(
		open_night_game.hud.end_reveal_tween == reveal_tween_before_locale_refresh
		and open_night_game.hud.end_finish_button.disabled
		and open_night_game.hud.end_stats.text == refreshed_stats_probe,
		"refreshing translated ending copy and statistics does not restart or bypass the reveal beat"
	)
	open_night_game.hud.end_reveal_started_msec = Time.get_ticks_msec() - open_night_game.hud.END_REVEAL_SKIP_DELAY_MSEC
	open_night_game.get_viewport().push_input(debug_ending_chord)
	open_night_game.get_viewport().push_input(debug_ending_release)
	_check(
		open_night_game.completed
		and not open_night_game.catalogue_ending_debug_preview
		and not open_night_game.hud.catalogue_debug_preview_active
		and not open_night_game.hud.end_finish_button.disabled
		and not open_night_game.hud.end_continue_button.disabled
		and open_night_game.hud.end_finish_button.focus_mode == Control.FOCUS_ALL
		and open_night_game.hud.end_continue_button.focus_mode == Control.FOCUS_ALL
		and open_night_game.get_viewport().gui_get_focus_owner() == open_night_game.hud.end_finish_button
		and open_night_game.hud.end_reveal_complete
		and is_equal_approx(open_night_game.hud.end_coda.constellation_progress, 1.0)
		and is_equal_approx(open_night_game.hud.end_coda.pullback_progress, 1.0)
		and is_equal_approx(open_night_game.hud.end_coda.route_progress, 1.0)
		and is_equal_approx(open_night_game.hud.end_coda.illumination_progress, 1.0)
		and is_equal_approx(open_night_game.hud.end_coda.settle_progress, 1.0)
		and not open_night_game.hud.end_coda.is_processing()
		and open_night_game.hud.end_finish_button.get_theme_font_size("font_size") > open_night_game.hud.end_continue_button.get_theme_font_size("font_size"),
		"the actual ending treats Ctrl+Shift+E as skip input and completes with archival focus"
	)
	_check_ending_map_illuminated(open_night_game.hud.end_coda, "actual completed ending")
	open_night_game.active_save_slot = 0
	open_night_game.hud.set_active_save_slot(0)
	open_night_game._on_catalogue_finish_requested()
	open_night_game.hud.refresh_catalogue_ending_text()
	_check(
		open_night_game.completed
		and open_night_game.hud.is_end_open()
		and not open_night_game.catalogue_ending_seen
		and open_night_game.hud.end_save_failure.visible
		and open_night_game.hud.end_save_failure.text == TranslationServer.translate("HUD_END_SAVE_FAILURE")
		and not open_night_game.hud.end_finish_button.disabled
		and not open_night_game.hud.end_continue_button.disabled
		and open_night_game.get_viewport().gui_get_focus_owner() == open_night_game.hud.end_finish_button,
		"a real finish save failure keeps the ending visible, translated, and retryable"
	)
	open_night_game.active_save_slot = 1
	open_night_game.hud.set_active_save_slot(1)
	var blocked_end_u := InputEventKey.new()
	blocked_end_u.keycode = KEY_U
	blocked_end_u.pressed = true
	open_night_game._unhandled_key_input(blocked_end_u)
	_check(not open_night_game.upgrade_tree.is_open(), "ending ownership blocks research-chart input behind the overlay")
	open_night_game._on_catalogue_continue_requested()
	_check(
		open_night_game.catalogue_ending_seen
		and not open_night_game.completed
		and not open_night_game.hud.is_end_open()
		and open_night_game.observation_phase_active
		and open_night_game.observation_round == ending_round + 1
		and not paused,
		"continue observing acknowledges the ending and resumes the same completed save in the open night"
	)
	var continued_save: Dictionary = open_night_game.save_games.load_slot(1)
	_check(bool(continued_save.get("catalogue_ending_seen", false)), "continuing autosaves the one-time ending acknowledgement")
	open_night_game._end_observation_phase()
	open_night_game._on_phase_summary_continue_requested()
	await process_frame
	await process_frame
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(
		open_night_game.observation_phase_active
		and open_night_game.observation_round == ending_round + 2
		and not open_night_game.hud.is_end_open(),
		"later open-night rounds do not replay an acknowledged ending"
	)
	var legacy_galactic_save: Dictionary = seen_galactic_save.duplicate(true)
	legacy_galactic_save.erase("galactic_pullback_seen")
	legacy_galactic_save.erase("catalogue_ending_seen")
	legacy_galactic_save.erase("ending_final_watch_pending")
	legacy_galactic_save.erase("phase_started_with_complete_research")
	open_night_game._apply_save_data(legacy_galactic_save)
	_check(
		open_night_game.ending_final_watch_pending
		and not open_night_game.catalogue_ending_seen
		and not open_night_game.completed,
		"a completed legacy open-night save migrates to one safe final watch instead of ending during load"
	)
	open_night_game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_PULLBACK and not open_night_game.galactic_pullback_seen, "a completed legacy save without the presentation flag plays the pull-back once on its next chart open")
	var pullback_close := InputEventKey.new()
	pullback_close.keycode = KEY_U
	pullback_close.pressed = true
	open_night_game.upgrade_tree._input(pullback_close)
	_check(open_night_game.galactic_pullback_seen and not open_night_game.upgrade_tree.is_open(), "U completes the pull-back final state and still closes the research chart")
	open_night_game._apply_save_data(seen_galactic_save)
	open_night_game.upgrade_tree.open_tree()
	await process_frame
	await process_frame
	_check(open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_FINAL and open_night_game.galactic_pullback_seen, "a save with the presentation flag restores the final frame without replay")
	open_night_game._apply_save_data(unseen_ending_save)
	await process_frame
	await process_frame
	_check(open_night_game.upgrade_tree.is_open() and not open_night_game.hud.is_end_open(), "loading an unseen ready save returns to the completed chart before replaying the ending")
	open_night_game.upgrade_tree.close_tree()
	await process_frame
	_check(
		open_night_game.hud.is_end_open()
		and open_night_game.completed
		and not open_night_game.hud.end_save_failure.visible,
		"closing that restored chart safely replays a clean unseen ending without a stale save error"
	)
	open_night_game._on_catalogue_finish_requested()
	var finished_record_save: Dictionary = open_night_game.save_games.load_slot(1)
	_check(
		open_night_game.hud.is_startup_slots_open()
		and paused
		and open_night_game.save_games.has_slot(1)
		and bool(finished_record_save.get("catalogue_ending_seen", false)),
		"finishing archives the acknowledgement and returns to slots without deleting the active record"
	)
	open_night_game.hud.close_startup_slots()
	open_night_game.reset_run()
	_check(
		not open_night_game.galactic_pullback_seen
		and not open_night_game.progression.galaxy_unlocked()
		and open_night_game.upgrade_tree.galactic_mode == open_night_game.upgrade_tree.GALACTIC_MODE_NORMAL
		and not open_night_game.catalogue_ending_seen
		and not open_night_game.ending_final_watch_pending,
		"reset clears the galactic presentation and every catalogue-ending state"
	)
	open_night_game.queue_free()
	await process_frame

	# Let short procedural audio voices and delayed chord tones release cleanly.
	await create_timer(0.85).timeout
	_cleanup_smoke_saves(smoke_save_directory)
	game.settings.set_research_chart_rotation(original_research_rotation)
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("SMOKE_TEST_PASS: tutorial, saves, localization, phase summary, compact HUD, observation, blank-sky survey, progression, events, performance caps, stale references, and reset")
		quit(0)
	else:
		print("SMOKE_TEST_FAIL: %d failure(s)" % failures.size())
		for failure in failures:
			print(" - " + failure)
		quit(1)


func _run_input_routing_regressions(packed: PackedScene) -> void:
	# This fixture owns no persistence. Snapshot every process-global surface that
	# the production settings service normally controls so the smoke test cannot
	# alter the player's profile, bindings, audio, display, locale, or cursor.
	var input_snapshot := _snapshot_nightwatch_input()
	var original_locale := TranslationServer.get_locale()
	var original_mouse_mode: int = Input.mouse_mode
	var original_pause := paused
	var original_window_mode := DisplayServer.window_get_mode()
	var master_bus := AudioServer.get_bus_index("Master")
	var original_volume_db := AudioServer.get_bus_volume_db(master_bus) if master_bus >= 0 else 0.0
	var original_bus_mute := AudioServer.is_bus_mute(master_bus) if master_bus >= 0 else false

	var routing_game = packed.instantiate()
	Fixtures.configure_before_ready(routing_game)
	root.add_child(routing_game)
	await process_frame
	await process_frame
	var settings = routing_game.settings
	var hud = routing_game.hud
	settings.reset_nightwatch_bindings(false)
	_check(
		routing_game.input_router != null
		and routing_game.input_router.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the game owns one always-processing global input router"
	)

	# Settings keyboard focus, first-class pages, and live convenience options.
	hud.open_settings()
	await process_frame
	await process_frame
	_check(
		hud.language_selector.focus_mode == Control.FOCUS_ALL
		and routing_game.get_viewport().gui_get_focus_owner() == hud.language_selector,
		"settings opens with the language selector keyboard-focused"
	)
	_check(
		hud.settings_active_page == "general"
		and hud.settings_pages.size() == 6
		and hud.settings_nav_buttons.size() == 6,
		"settings opens one six-page console on General"
	)
	var settings_type_is_readable := true
	for page_value in hud.settings_pages.values():
		var settings_page: Control = page_value
		var page_description := settings_page.get_node("PageDescription") as Label
		settings_type_is_readable = settings_type_is_readable and page_description.get_theme_font_size("font_size") >= 12
	for nav_value in hud.settings_nav_buttons.values():
		var nav_button: Button = nav_value
		settings_type_is_readable = settings_type_is_readable and nav_button.get_theme_font_size("font_size") >= 14
	_check(settings_type_is_readable, "settings keeps support copy at 12 px and navigation actions at 14 px or larger")
	var slider_focus_style := hud.master_volume_slider.get_theme_stylebox("grabber_area_highlight") as StyleBoxFlat
	_check(
		slider_focus_style != null and slider_focus_style.border_width_top > 0 and slider_focus_style.border_width_bottom > 0,
		"keyboard-focused sliders change rail shape as well as color"
	)
	var control_rows_margin := hud.settings_pages["controls"].get_node("ControlsScroll/ControlRowsMargin") as MarginContainer
	_check(
		control_rows_margin.get_theme_constant("margin_right") >= 16,
		"Controls reserves readable space between long binding labels and the scrollbar"
	)
	hud._set_settings_page("display")
	await process_frame
	await process_frame
	_check(routing_game.get_viewport().gui_get_focus_owner() == hud.fullscreen_button, "each page places focus on its first useful control")
	hud.close_settings()
	hud.open_settings()
	await process_frame
	await process_frame
	_check(
		hud.settings_active_page == "display"
		and routing_game.get_viewport().gui_get_focus_owner() == hud.fullscreen_button,
		"reopening settings restores the last page and its focus"
	)
	hud._set_settings_page("audio")
	_check(hud.audio_display_container.visible and not hud.save_management_container.visible, "Audio is one exclusive settings page")
	hud._set_settings_page("save")
	_check(hud.save_management_container.visible and not hud.audio_display_container.visible, "Save replaces Audio inside the same console")
	hud._set_settings_page("audio")
	var original_master: float = settings.get_master_volume_linear()
	var original_muted: bool = settings.is_muted()
	var original_unfocused_mute: bool = settings.should_mute_when_unfocused()
	hud.master_volume_slider.value = 37.0
	_check(
		is_equal_approx(settings.get_master_volume_linear(), 0.37)
		and hud.master_volume_value.text == "37",
		"the master slider updates both its numeric readout and settings model"
	)
	hud._on_mute_pressed()
	_check(
		settings.is_muted() != original_muted
		and hud.mute_button.text
		== TranslationServer.translate("SETTINGS_ON" if settings.is_muted() else "SETTINGS_OFF"),
		"the mute action updates both its label and settings model"
	)
	hud._on_mute_unfocused_pressed()
	_check(
		settings.should_mute_when_unfocused() != original_unfocused_mute
		and hud.mute_unfocused_button.text == TranslationServer.translate("SETTINGS_ON" if settings.should_mute_when_unfocused() else "SETTINGS_OFF"),
		"the unfocused-audio policy is a real persisted toggle rather than a second mute state"
	)
	settings.set_master_volume_linear(original_master, false)
	settings.set_muted(original_muted, false)
	settings.set_mute_when_unfocused(original_unfocused_mute, false)

	var original_vsync: bool = settings.is_vsync_enabled()
	var original_fps_limit: int = settings.get_fps_limit()
	hud._set_settings_page("display")
	hud._on_vsync_pressed()
	hud._on_fps_limit_selected(2)
	_check(
		settings.is_vsync_enabled() != original_vsync
		and settings.get_fps_limit() == 60,
		"Display exposes independent VSync and explicit frame-cap controls"
	)
	settings.set_vsync_enabled(original_vsync, false)
	settings.set_fps_limit(original_fps_limit, false)

	var original_motion: float = settings.get_motion_intensity()
	var original_flashes: bool = settings.are_screen_flashes_enabled()
	hud._set_settings_page("accessibility")
	routing_game.effects.reset()
	settings.set_motion_intensity(1.0, false)
	routing_game.effects.add_kick(Vector2.RIGHT * 20.0, 3.0)
	routing_game.effects.add_shake(0.8)
	var full_kick: float = routing_game.effects.kick_amplitude
	var full_shake: float = routing_game.effects.shake_trauma
	settings.set_motion_intensity(0.5, false)
	_check(
		is_equal_approx(routing_game.effects.kick_amplitude, full_kick * 0.5)
		and is_equal_approx(routing_game.effects.shake_trauma, full_shake * 0.5),
		"lowering camera impact immediately reduces an effect already in flight"
	)
	hud.motion_intensity_slider.value = 0.0
	hud._on_screen_flashes_pressed()
	routing_game.effects.spawn_success(Vector2.ZERO, 1.0, Color.WHITE, 1.0, 1.0, "PERFECT", Vector2.ZERO, 1.0, true)
	_check(
		is_zero_approx(settings.get_motion_intensity())
		and is_zero_approx(routing_game.effects.kick_amplitude)
		and is_zero_approx(routing_game.effects.shake_trauma),
		"0% camera impact removes both kick and shake"
	)
	_check(
		settings.are_screen_flashes_enabled() != original_flashes
		and is_zero_approx(routing_game.effects.flash_strength)
		and not routing_game.effects.rings.is_empty()
		and not routing_game.effects.particles.is_empty(),
		"screen flashes can be disabled while rings and particles retain important feedback"
	)
	settings.set_motion_intensity(original_motion, false)
	settings.set_screen_flashes_enabled(original_flashes, false)
	routing_game.effects.reset()
	hud.show_autosaved(1)
	_check(hud.last_autosave_unix > 0, "completed autosave records a timestamp for the active slot")
	hud.set_active_save_slot(2)
	_check(hud.last_autosave_unix == 0, "switching slots cannot display the previous slot's autosave timestamp")
	hud.set_active_save_slot(0)

	# Controls is a page in the same console. Escape closes the console from any
	# page, while capture still consumes its own Escape first.
	hud.open_controls()
	await process_frame
	await process_frame
	var chart_widget: Control = hud.controls_action_widgets.get("nw_chart") as Control
	_check(
		hud.is_controls_open()
		and chart_widget != null
		and routing_game.get_viewport().gui_get_focus_owner() == chart_widget,
		"controls opens with the first editable chart binding focused"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(
		not hud.is_controls_open() and not hud.is_settings_open() and not paused,
		"one Escape resumes directly from the integrated Controls page"
	)
	hud.open_controls()
	await process_frame
	await process_frame
	hud._begin_rebind(&"nw_chart")
	_check(hud.is_rebind_capture_active(), "activating an editable binding starts capture")
	var capture_fullscreen_before: bool = settings.is_fullscreen()
	await _push_key_event(routing_game.get_viewport(), KEY_F11)
	_check(
		hud.is_rebind_capture_active()
		and hud.rebind_release_keycode == 0
		and settings.is_fullscreen() == capture_fullscreen_before
		and hud.is_controls_open(),
		"a conflicting F11 candidate stays in capture and never leaks into fullscreen"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(
		not hud.is_rebind_capture_active()
		and hud.rebind_release_keycode == 0
		and hud.is_controls_open()
		and hud.is_settings_open(),
		"Escape cancels only rebind capture and consumes its matching release"
	)
	hud._begin_rebind(&"nw_chart")
	await _push_key_event(routing_game.get_viewport(), KEY_K)
	var old_chart_event := _key_event(KEY_U)
	var new_chart_event := _key_event(KEY_K)
	_check(
		not hud.is_rebind_capture_active()
		and hud.rebind_release_keycode == 0
		and hud.is_controls_open()
		and hud.is_settings_open(),
		"rebind capture consumes the candidate press and its matching release without leaving settings"
	)
	_check(
		not old_chart_event.is_action(&"nw_chart", true)
		and new_chart_event.is_action(&"nw_chart", true),
		"replacing the chart binding removes U and activates the new key"
	)
	hud._begin_rebind(&"nw_menu_back")
	await _push_key_event(routing_game.get_viewport(), KEY_V)
	var optional_back_event := _key_event(KEY_V)
	var clear_back_widget: Button = hud.controls_clear_widgets.get("nw_menu_back") as Button
	_check(
		optional_back_event.is_action(&"nw_menu_back", true)
		and clear_back_widget != null
		and clear_back_widget.visible,
		"an optional menu-back alternate exposes its individual remove action"
	)
	clear_back_widget.pressed.emit()
	_check(
		not optional_back_event.is_action(&"nw_menu_back", true)
		and _key_event(KEY_ESCAPE).is_action(&"nw_menu_back", true)
		and not clear_back_widget.visible
		and new_chart_event.is_action(&"nw_chart", true),
		"removing the optional alternate keeps locked Escape and other custom bindings"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(not hud.is_controls_open() and not hud.is_settings_open() and not paused, "one back action closes the consolidated settings console")
	await _push_key_event(routing_game.get_viewport(), KEY_U)
	_check(not routing_game.upgrade_tree.is_open(), "the old chart key no longer opens the chart after rebinding")
	await _push_key_event(routing_game.get_viewport(), KEY_K)
	_check(routing_game.upgrade_tree.is_open() and paused, "the new chart key opens the chart through the real viewport route")
	await _push_key_event(routing_game.get_viewport(), KEY_K)
	_check(not routing_game.upgrade_tree.is_open() and not paused, "the new chart key also closes the live chart")
	settings.reset_nightwatch_bindings(false)
	_check(_key_event(KEY_U).is_action(&"nw_chart", true), "reset restores the default chart binding in memory")

	# A phase summary owns pause, but menu-back may place Settings over it. Every
	# shipped continue key must still reach the router while SceneTree is paused.
	routing_game._end_observation_phase()
	_check(hud.is_phase_summary_open() and paused, "input routing fixture reaches a paused phase summary")
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(
		hud.is_phase_summary_open()
		and hud.is_settings_open()
		and hud.tutorial_replay_button.disabled
		and paused,
		"menu-back opens settings over a summary and disables tutorial replay"
	)
	routing_game._on_tutorial_replay_requested()
	_check(
		hud.is_phase_summary_open()
		and hud.is_settings_open()
		and not routing_game.tutorial.is_active(),
		"the game guard rejects tutorial replay while a summary owns the intermission"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(hud.is_phase_summary_open() and not hud.is_settings_open() and paused, "back closes summary settings without releasing the summary pause")
	var continue_keys: Array[int] = [KEY_U, KEY_ENTER, KEY_SPACE]
	for continue_index in range(continue_keys.size()):
		if continue_index > 0:
			hud.show_phase_summary({"round": 1, "duration": 20.0}, {}, "first_baseline", false)
		var focus_owner := routing_game.get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()
		await _push_key_event(routing_game.get_viewport(), continue_keys[continue_index])
		_check(
			not hud.is_phase_summary_open()
			and routing_game.upgrade_tree.is_open()
			and paused,
			"paused phase summary continues through %s" % OS.get_keycode_string(continue_keys[continue_index])
		)
		routing_game._close_upgrade_tree_without_transition()
		_check(not routing_game.upgrade_tree.is_open() and paused, "isolated summary continuation keeps intermission pause ownership")

	# UpgradeTree gets first refusal on Escape. The same next Escape then reaches
	# the global pause route, and fullscreen stays global while paused.
	paused = false
	routing_game.observation_phase_active = true
	routing_game.observation_phase_remaining = 20.0
	routing_game.upgrade_tree.open_tree()
	await process_frame
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(
		not routing_game.upgrade_tree.is_open()
		and not hud.is_settings_open()
		and not paused,
		"the chart consumes the first Escape without also opening settings"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)
	_check(hud.is_settings_open() and paused, "the next Escape opens gameplay settings")
	var fullscreen_before: bool = settings.is_fullscreen()
	await _push_key_event(routing_game.get_viewport(), KEY_F11)
	_check(
		settings.is_fullscreen() != fullscreen_before and hud.is_settings_open() and paused,
		"the fullscreen action routes globally while settings has paused the game"
	)
	settings.set_fullscreen(fullscreen_before, false)
	await _push_key_event(routing_game.get_viewport(), KEY_ESCAPE)

	# Modifier-aware exact matching prevents a legal Shift+F11 chart binding from
	# being stolen by the plain global F11 action.
	var shifted_f11 := _key_event(KEY_F11, true, true)
	var shifted_result: Dictionary = settings.set_editable_binding(&"nw_chart", shifted_f11, 0, false)
	fullscreen_before = settings.is_fullscreen()
	await _push_key_event(routing_game.get_viewport(), KEY_F11, true)
	_check(
		bool(shifted_result.get("ok", false))
		and routing_game.upgrade_tree.is_open()
		and settings.is_fullscreen() == fullscreen_before,
		"an exact Shift+F11 chart binding does not also toggle plain-F11 fullscreen"
	)
	await _push_key_event(routing_game.get_viewport(), KEY_F11, true)
	settings.reset_nightwatch_bindings(false)

	# Ending, startup recovery, and both tutorial modal steps block chart/back.
	routing_game.hud.show_catalogue_ending("", false)
	paused = true
	for blocked_key in [KEY_ESCAPE, KEY_U]:
		routing_game.hud.end_reveal_started_msec = Time.get_ticks_msec()
		await _push_key_event(routing_game.get_viewport(), blocked_key)
	_check(
		routing_game.hud.is_end_open()
		and not routing_game.upgrade_tree.is_open()
		and not routing_game.hud.is_settings_open()
		and paused,
		"the ending consumes back and chart actions without exposing a covered surface"
	)
	routing_game.hud.hide_end()
	paused = false
	routing_game.hud.open_startup_slots()
	await process_frame
	for blocked_key in [KEY_ESCAPE, KEY_U]:
		await _push_key_event(routing_game.get_viewport(), blocked_key)
	_check(
		routing_game.hud.is_startup_slots_open()
		and not routing_game.upgrade_tree.is_open()
		and not routing_game.hud.is_settings_open()
		and paused,
		"startup recovery blocks back and chart actions"
	)
	routing_game.hud.close_startup_slots()
	routing_game.tutorial.start_tutorial(false)
	await process_frame
	for blocked_key in [KEY_ESCAPE, KEY_U]:
		await _push_key_event(routing_game.get_viewport(), blocked_key)
	_check(
		routing_game.tutorial.is_modal_step()
		and routing_game.tutorial.current_step == routing_game.tutorial.STEP_WELCOME
		and not routing_game.upgrade_tree.is_open()
		and not routing_game.hud.is_settings_open()
		and paused,
		"the welcome tutorial modal blocks back and chart actions"
	)
	routing_game.tutorial._on_primary_pressed()
	routing_game.tutorial.notify_observation_completed()
	routing_game.upgrade_tree.open_tree()
	routing_game.tutorial.notify_upgrade_purchased()
	await process_frame
	for blocked_key in [KEY_ESCAPE, KEY_U]:
		await _push_key_event(routing_game.get_viewport(), blocked_key)
	_check(
		routing_game.tutorial.current_step == routing_game.tutorial.STEP_COMPLETE
		and routing_game.tutorial.is_modal_step()
		and routing_game.upgrade_tree.is_open()
		and paused,
		"the completion tutorial modal keeps its underlying chart and pause ownership intact"
	)
	routing_game.tutorial._on_primary_pressed()
	routing_game._close_upgrade_tree_without_transition()

	# Defensive cleanup and restoration even when an assertion above failed.
	if routing_game.hud.is_end_open():
		routing_game.hud.hide_end()
	if routing_game.hud.is_startup_slots_open():
		routing_game.hud.close_startup_slots()
	if routing_game.hud.is_controls_open():
		routing_game.hud._close_controls(false)
	if routing_game.hud.is_settings_open():
		routing_game.hud.close_settings()
	if routing_game.tutorial.is_active():
		routing_game.tutorial.skip_tutorial()
	if routing_game.upgrade_tree.is_open():
		routing_game._close_upgrade_tree_without_transition()
	settings.set_master_volume_linear(original_master, false)
	settings.set_muted(original_muted, false)
	settings.set_fullscreen(false, false)
	routing_game.queue_free()
	paused = original_pause
	await process_frame
	await process_frame
	_restore_nightwatch_input(input_snapshot)
	TranslationServer.set_locale(original_locale)
	Input.mouse_mode = original_mouse_mode
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, original_volume_db)
		AudioServer.set_bus_mute(master_bus, original_bus_mute)
	if DisplayServer.get_name().to_lower() != "headless" and DisplayServer.window_get_mode() != original_window_mode:
		DisplayServer.window_set_mode(original_window_mode)


func _key_event(
	keycode: int,
	pressed: bool = true,
	shift_pressed: bool = false,
	ctrl_pressed: bool = false,
	alt_pressed: bool = false
) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	event.ctrl_pressed = ctrl_pressed
	event.alt_pressed = alt_pressed
	if keycode == KEY_SPACE:
		event.unicode = 32
	elif keycode >= KEY_A and keycode <= KEY_Z:
		event.unicode = keycode if shift_pressed else keycode + 32
	return event


func _push_key_event(
	viewport: Viewport,
	keycode: int,
	shift_pressed: bool = false,
	ctrl_pressed: bool = false,
	alt_pressed: bool = false
) -> void:
	viewport.push_input(_key_event(keycode, true, shift_pressed, ctrl_pressed, alt_pressed))
	await process_frame
	viewport.push_input(_key_event(keycode, false, shift_pressed, ctrl_pressed, alt_pressed))
	await process_frame


func _snapshot_nightwatch_input() -> Dictionary:
	var snapshot := {}
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		if not InputMap.has_action(action):
			snapshot[action] = {"exists": false}
			continue
		var events: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			events.append(event.duplicate())
		snapshot[action] = {
			"exists": true,
			"deadzone": InputMap.action_get_deadzone(action),
			"events": events,
		}
	return snapshot


func _restore_nightwatch_input(snapshot: Dictionary) -> void:
	for action_value in InputBindings.action_names():
		var action := StringName(action_value)
		var action_snapshot: Dictionary = snapshot.get(action, {"exists": false})
		if not bool(action_snapshot.get("exists", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, float(action_snapshot.get("deadzone", 0.5)))
		InputMap.action_erase_events(action)
		for event_value in action_snapshot.get("events", []):
			var event := event_value as InputEvent
			if event != null:
				InputMap.action_add_event(action, event.duplicate())


func _decorative_controls_ignore_mouse(node: Node) -> bool:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _decorative_controls_ignore_mouse(child):
			return false
	return true


func _run_feedback_regressions(packed: PackedScene, global_x2_ids: Array) -> void:
	var feedback_game = packed.instantiate()
	feedback_game.startup_slot_prompt_enabled = false
	feedback_game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(feedback_game)
	await process_frame
	await process_frame
	feedback_game.set_process(false)
	feedback_game.spawner.set_process(false)
	feedback_game.events.set_process(false)
	feedback_game.sky_contacts.set_process(false)
	feedback_game.observer.set_process(false)
	feedback_game.progression.reset()
	feedback_game.effects.reset()

	# The same common observation must keep the same presentation at x1 and
	# x256 even though the second Data packet carries 256 times the amount.
	var x1_target = feedback_game.spawner.spawn_meteor(
		"common", Vector2(420.0, 240.0), Vector2.ZERO, 4.0
	)
	x1_target.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(x1_target, 22.0, 1.55, true, "GOOD")
	var x1_particle_count: int = feedback_game.effects.particles.size()
	var x1_flash_strength: float = feedback_game.effects.flash_strength
	var x1_kick_amplitude: float = feedback_game.effects.kick_amplitude
	x1_target.free()
	feedback_game.effects.reset()
	feedback_game.progression.reset_manual_combo()
	for multiplier_id in global_x2_ids:
		feedback_game.progression.purchased_nodes[String(multiplier_id)] = true
	var x256_data_before: float = feedback_game.progression.observation_data
	var x256_target = feedback_game.spawner.spawn_meteor(
		"common", Vector2(420.0, 240.0), Vector2.ZERO, 4.0
	)
	x256_target.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(x256_target, 22.0, 1.55, true, "GOOD")
	var x256_data_gain: float = feedback_game.progression.observation_data - x256_data_before
	var x256_popup: Dictionary = feedback_game.effects.popups.back()
	var last_voice_index := posmod(
		feedback_game.sound.next_voice - 1,
		feedback_game.sound.voice_pool.size()
	)
	var intrinsic_success_pitch: float = feedback_game.sound.voice_pool[last_voice_index].pitch_scale
	_check(is_equal_approx(x256_data_gain, 22.0 * 256.0), "x256 research still multiplies the actual observation Data")
	_check(
		feedback_game.effects.particles.size() == x1_particle_count
		and is_equal_approx(feedback_game.effects.flash_strength, x1_flash_strength)
		and is_equal_approx(feedback_game.effects.kick_amplitude, x1_kick_amplitude),
		"the same target keeps identical feedback strength at x1 and x256"
	)
	_check("x1.55" in String(x256_popup.text) and "x396.80" not in String(x256_popup.text), "the Data packet suffix reports intrinsic observation technique instead of research economy")
	_check(is_equal_approx(intrinsic_success_pitch, 1.0 + 0.55 * 0.045), "the success pitch reads the intrinsic observation multiplier")
	_check(is_equal_approx(feedback_game.progression.best_multiplier, 1.55), "the best manual multiplier excludes x256 research economy")
	x256_target.free()

	# Automatic completions can deliver economic Data but cannot rewrite a stat
	# whose player-facing label explicitly says it is manual.
	feedback_game.effects.reset()
	var automatic_target = feedback_game.spawner.spawn_meteor(
		"common", Vector2(420.0, 240.0), Vector2.ZERO, 4.0
	)
	automatic_target.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(automatic_target, 10.0, 0.68, false, "AUTOMATIC")
	_check(is_equal_approx(feedback_game.progression.best_multiplier, 1.55), "automatic observations never update the best manual multiplier")
	automatic_target.free()

	# A high-grade manual observation is accented even on a non-impact target.
	# That category permits view motion, while hitstop still requires a fireball.
	feedback_game.effects.reset()
	feedback_game.progression.reset_manual_combo()
	var galaxy_target = feedback_game.spawner.spawn_meteor(
		"galaxy", Vector2(420.0, 240.0), Vector2.ZERO, 8.0
	)
	galaxy_target.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(galaxy_target, 220.0, 1.0, true, "PERFECT")
	_check(not feedback_game.hitstop_active, "non-impact targets never freeze the view even at maximum strength")
	_check(feedback_game.effects.shake_trauma > 0.0, "a high-grade non-impact observation that reaches the shake floor still moves the view")
	galaxy_target.free()

	# Routine observations remain directional particles plus a packet. Neither
	# a lone completion nor a full combo promotes a GOOD common into an accent.
	feedback_game.effects.reset()
	feedback_game.progression.reset_manual_combo()
	var lone_common = feedback_game.spawner.spawn_meteor(
		"common", Vector2(420.0, 240.0), Vector2.ZERO, 4.0
	)
	lone_common.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(lone_common, 24.0, 1.0, true, "GOOD")
	_check(is_zero_approx(feedback_game.effects.shake_trauma), "a single common observation leaves the view still")
	lone_common.free()

	# The chain has to be built through the real path. Writing the count alone
	# leaves the window at zero, and the next success reads that as a broken
	# chain and starts over at one.
	feedback_game.effects.reset()
	feedback_game.progression.reset_manual_combo()
	for _link in range(11):
		feedback_game.progression.record_manual_combo_success()
	var chained_common = feedback_game.spawner.spawn_meteor(
		"common", Vector2(420.0, 240.0), Vector2.ZERO, 4.0
	)
	chained_common.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(chained_common, 24.0, 1.0, true, "GOOD")
	_check(
		is_zero_approx(feedback_game.effects.shake_trauma)
		and is_zero_approx(feedback_game.effects.kick_amplitude)
		and is_zero_approx(feedback_game.effects.flash_strength)
		and feedback_game.effects.rings.is_empty(),
		"a full manual chain cannot promote a routine common into an accented observation"
	)
	_check(not feedback_game.hitstop_active, "a full manual chain still never freezes the view on a common")
	chained_common.free()
	feedback_game.progression.reset_manual_combo()

	feedback_game.effects.reset()
	feedback_game.progression.reset_manual_combo()
	feedback_game.hitstop_cooldown_until_msec = 0
	var fireball_target = feedback_game.spawner.spawn_meteor(
		"fireball", Vector2(420.0, 240.0), Vector2.ZERO, 8.0
	)
	fireball_target.set_meta("gemini_echo", true)
	feedback_game._on_meteor_observed(fireball_target, 82.0, 1.0, true, "PERFECT")
	_check(feedback_game.effects.shake_trauma > 0.0 and feedback_game.hitstop_active, "a strong manual fireball still owns shake and hitstop")
	feedback_game._release_hitstop()
	var cooldown_deadline: int = feedback_game.hitstop_cooldown_until_msec
	feedback_game._apply_hitstop(0.05)
	_check(cooldown_deadline > Time.get_ticks_msec() and not feedback_game.hitstop_active, "hitstop cannot restart during its 400 ms real-time cooldown")
	fireball_target.free()

	var legacy_multiplier_save: Dictionary = feedback_game.progression.get_save_data()
	legacy_multiplier_save.best_multiplier = 871.21
	var legacy_multiplier_probe = load("res://scripts/progression_controller.gd").new()
	legacy_multiplier_probe.load_save_data(legacy_multiplier_save)
	_check(
		is_equal_approx(
			legacy_multiplier_probe.best_multiplier,
			legacy_multiplier_probe.MAX_INTRINSIC_OBSERVATION_MULTIPLIER
		),
		"legacy economy-contaminated best multipliers migrate to the intrinsic ceiling"
	)
	legacy_multiplier_probe.free()

	feedback_game.hitstop_cooldown_until_msec = 0
	Engine.time_scale = 1.0
	feedback_game.queue_free()
	await process_frame
	await process_frame


func _run_survey_regressions(packed: PackedScene, balance) -> void:
	var survey_game = packed.instantiate()
	Fixtures.configure_before_ready(survey_game)
	root.add_child(survey_game)
	await process_frame
	await process_frame
	survey_game.set_process(false)
	survey_game.spawner.set_process(false)
	survey_game.events.set_process(false)
	survey_game.sky_contacts.set_process(false)
	survey_game.observer.set_process(false)
	survey_game.progression.reset()
	survey_game.spawner.reset()
	survey_game.survey.reset()

	var pacing_ratio_before: float = survey_game.progression.get_progression_ratio()
	var spawner_rng_before: int = survey_game.spawner.rng.state
	var survey_rng_before: int = survey_game.survey.rng.state
	survey_game.survey.begin_round(1)
	survey_game.survey.set_scanning(true, Vector2(500.0, 400.0))
	var dormant_spawned: int = survey_game.survey.apply_scan_segment(Vector2.ZERO, Vector2(500.0, 400.0))
	_check(not survey_game.survey.scanning and dormant_spawned == 0 and is_zero_approx(survey_game.survey.charge_distance), "blank-sky sweeping is fully dormant before its research is purchased")
	_check(survey_game.spawner.rng.state == spawner_rng_before, "dormant survey setup does not consume the meteor RNG")
	_check(survey_game.survey.rng.state == survey_rng_before, "dormant survey setup does not consume its own roll stream")
	_check(survey_game.progression.get_node_state("polar_survey") == "available", "Polar Survey is available from time zero without a success-count gate")
	_check(survey_game.progression.debug_purchase_node("polar_survey"), "Polar Survey can be purchased from its prerequisite-free root")
	_check(is_equal_approx(survey_game.progression.get_progression_ratio(), pacing_ratio_before), "survey research does not change meteor-density pacing")
	spawner_rng_before = survey_game.spawner.rng.state
	survey_game.survey.begin_round(2)
	_check(survey_game.survey.active_round == 2 and is_zero_approx(survey_game.survey.charge_distance), "Polar Survey opens with empty round-local sweep charge")
	_check(survey_game.spawner.rng.state == spawner_rng_before, "survey round setup uses RNG isolated from meteor spawning")

	var observer = survey_game.observer
	var survey = survey_game.survey
	var target_position := Vector2(420.0, 260.0)
	var intent_target = survey_game.spawner.spawn_meteor("common", target_position, Vector2.ZERO, 20.0)
	observer.reset()
	observer.previous_cursor_position = target_position
	observer.cursor_position = target_position
	observer.interaction_mode = observer.InteractionMode.NONE
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and observer.selected_meteor == intent_target, "pressing on a meteor latches tracking before blank-sky scanning")
	survey_game.spawner.reset()
	observer.reset()
	observer.previous_cursor_position = Vector2(180.0, 160.0)
	observer.cursor_position = Vector2(200.0, 160.0)
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.SCANNING and survey.scanning, "blank drag enters scanning without a new press")
	var crossed_target = survey_game.spawner.spawn_meteor("common", Vector2(220.0, 160.0), Vector2.ZERO, 20.0)
	observer.previous_cursor_position = Vector2(200.0, 160.0)
	observer.cursor_position = Vector2(240.0, 160.0)
	var charge_before_crossing: float = survey.charge_distance
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and observer.selected_meteor == crossed_target and crossed_target.get_progress() > 0.0, "a held survey gesture automatically begins observing a crossed target")
	_check(not survey.scanning and charge_before_crossing > 0.0 and is_equal_approx(survey.charge_distance, charge_before_crossing), "tracking suspends scanning and preserves held-button charge")
	var closer_target = survey_game.spawner.spawn_meteor("common", observer.cursor_position, Vector2.ZERO, 20.0)
	survey_game.progression.purchased_nodes["multi_target_analysis"] = true
	observer.previous_cursor_position = observer.cursor_position
	observer._update_survey_interaction(0.016)
	_check(observer.selected_meteor == crossed_target and closer_target.get_progress() > 0.0, "multi-target support observes a closer arrival without stealing the existing primary target")
	survey_game.progression.purchased_nodes.erase("multi_target_analysis")
	observer.previous_cursor_position = Vector2(600.0, 420.0)
	observer.cursor_position = observer.previous_cursor_position
	observer._update_survey_interaction(observer.TRACKING_GRACE_SECONDS + 0.01)
	_check(observer.selected_meteor == null and is_equal_approx(survey.charge_distance, charge_before_crossing), "expired tracking grace releases the target without counting that frame as sweep travel")
	observer.previous_cursor_position = observer.cursor_position
	observer.cursor_position += Vector2(10.0, 0.0)
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.PENDING and is_equal_approx(survey.charge_distance, charge_before_crossing), "small movement after tracking keeps pending charge without jittering into scanning")
	observer.previous_cursor_position = observer.cursor_position
	observer.cursor_position += Vector2(20.0, 0.0)
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.SCANNING and survey.charge_distance > charge_before_crossing, "held movement in empty sky resumes scanning and continues the saved charge")
	var resumed_charge: float = survey.charge_distance
	observer.previous_cursor_position = crossed_target.global_position
	observer.cursor_position = observer.previous_cursor_position
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and not survey.scanning and is_equal_approx(survey.charge_distance, resumed_charge), "the same held gesture can switch back to tracking again")
	observer._clear_interaction_mode()
	_check(observer.interaction_mode == observer.InteractionMode.NONE and not survey.scanning and is_zero_approx(survey.charge_distance), "actual release clears base charge even when tracking already suspended scanning")
	survey_game.spawner.reset()
	observer.reset()
	var finishing_target = survey_game.spawner.spawn_meteor("common", Vector2(440.0, 260.0), Vector2.ZERO, 20.0)
	finishing_target.observation_progress = 0.999
	survey.charge_distance = 70.0
	observer.previous_cursor_position = Vector2(420.0, 260.0)
	observer.cursor_position = Vector2(450.0, 260.0)
	observer._update_survey_interaction(0.016)
	_check(finishing_target.observation_progress >= 1.0, "queued-for-deletion targets do not block a live target under the cursor")
	finishing_target._process(0.0)
	_check(not finishing_target.can_be_tracked() and observer.selected_meteor == null, "a completed meteor releases its selection through the real completion signal")
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and is_equal_approx(survey.charge_distance, 70.0), "a completion frame cannot also charge survey travel")
	observer.reset()
	_check(is_zero_approx(survey.charge_distance), "reset clears base charge while scanning is already suspended")
	survey_game.spawner.reset()
	# Supernovae finish synchronously inside apply_manual_observation, unlike
	# meteors that finish in _process. Both lifecycles must reserve the frame.
	var instant_layer := Node2D.new()
	survey_game.add_child(instant_layer)
	observer.additional_target_layers.append(instant_layer)
	var instant_target = load("res://scripts/supernova_target.gd").new()
	instant_layer.add_child(instant_target)
	instant_target.configure("survey_transition_probe", Vector2(440.0, 260.0), 0.0, false, survey_game.observation_view)
	instant_target.observed.connect(func(target, _reward, _multiplier, _was_manual, _quality): observer.release_target(target))
	instant_target.observation_progress = 0.999
	survey.charge_distance = 70.0
	observer.previous_cursor_position = Vector2(420.0, 260.0)
	observer.cursor_position = Vector2(450.0, 260.0)
	observer._update_survey_interaction(0.016)
	_check(not instant_target.can_be_tracked() and observer.selected_meteor == null, "automatic survey transition can acquire and synchronously finish a non-meteor target")
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and is_equal_approx(survey.charge_distance, 70.0), "synchronous completion never double-credits the frame as scanning")
	observer.additional_target_layers.erase(instant_layer)
	instant_layer.queue_free()
	observer.reset()

	survey.begin_round(3)
	var blocked_position := Vector2(560.0, 400.0)
	var blocker = survey_game.spawner.spawn_meteor("common", blocked_position, Vector2.ZERO, 20.0)
	survey.set_scanning(true, blocked_position)
	var blocked_rolls_before: int = survey.roll_count
	survey.apply_scan_segment(Vector2(40.0, 400.0), blocked_position)
	_check(not survey.is_blank_sky(blocked_position) and is_zero_approx(survey.charge_distance) and survey.roll_count == blocked_rolls_before, "a live meteor inside 150 px prevents both sweep charge and probability rolls")
	blocker.queue_free()
	await process_frame

	var summon_position := Vector2(560.0, 400.0)
	survey.rng.seed = _rng_seed_with_first_roll_below(survey_game.progression.get_survey_spawn_probability())
	spawner_rng_before = survey_game.spawner.rng.state
	survey.set_scanning(true, summon_position)
	var summoned_count: int = survey.apply_scan_segment(
		summon_position - Vector2(survey_game.progression.get_survey_required_distance(), 0.0),
		summon_position
	)
	var summoned_meteor = survey_game.meteor_layer.get_child(0) if survey_game.meteor_layer.get_child_count() > 0 else null
	_check(summoned_count == 1 and is_instance_valid(summoned_meteor), "a successful blank-sky roll calls one meteor at the cursor")
	_check(is_instance_valid(summoned_meteor) and bool(summoned_meteor.get_meta("polar_summoned", false)) and summoned_meteor.type_id == "common", "a base survey summon is tagged against recursive procs and uses the unlocked common type")
	_check(is_instance_valid(summoned_meteor) and summoned_meteor.global_position.is_equal_approx(summon_position), "a survey meteor begins at the cursor position")
	_check(survey_game.spawner.rng.state == spawner_rng_before, "survey rolls and custom summons do not advance the regular meteor RNG")
	observer.interaction_mode = observer.InteractionMode.SCANNING
	observer.previous_cursor_position = summon_position
	observer.cursor_position = summon_position
	observer._update_survey_interaction(0.016)
	_check(observer.interaction_mode == observer.InteractionMode.TRACKING and observer.selected_meteor == summoned_meteor and summoned_meteor.get_progress() > 0.0, "a summoned meteor is observed on the next held frame without release/repress")
	_check(not survey.scanning and survey.cooldown_remaining > 0.0, "observing a summoned meteor preserves its summon cooldown")
	var recursive_rolls_before: int = survey.roll_count
	var recursive_count_before: int = survey_game.meteor_layer.get_child_count()
	survey.cooldown_remaining = 0.0
	survey.set_scanning(true, summon_position)
	survey.apply_scan_segment(summon_position - Vector2(500.0, 0.0), summon_position + Vector2(100.0, 0.0))
	_check(survey.roll_count == recursive_rolls_before and survey_game.meteor_layer.get_child_count() == recursive_count_before, "a summoned live meteor blocks another nearby summon instead of forming a recursive chain")
	survey_game.spawner.reset()
	await process_frame

	survey.begin_round(4)
	survey.set_scanning(true, Vector2(400.0, 420.0))
	survey.apply_scan_segment(Vector2(200.0, 420.0), Vector2(400.0, 420.0))
	_check(survey.charge_distance > 0.0, "a partial sweep accumulates travel before release")
	survey.set_scanning(false, Vector2(400.0, 420.0))
	_check(is_zero_approx(survey.charge_distance), "base Polar Survey discards partial charge on release")
	for node_id in ["sweep_gain", "faint_recovery", "sustained_sweep"]:
		_check(survey_game.progression.debug_purchase_node(node_id), "survey prerequisite installs: " + node_id)
	_check(is_equal_approx(survey_game.progression.get_survey_required_distance(), 380.0) and is_equal_approx(survey_game.progression.get_survey_spawn_probability(), 0.42), "early Ursa Minor research reduces sweep distance and raises summon chance")
	survey.begin_round(5)
	survey.set_scanning(true, Vector2(390.0, 420.0))
	survey.apply_scan_segment(Vector2(200.0, 420.0), Vector2(390.0, 420.0))
	var retained_charge: float = survey.charge_distance
	survey.set_scanning(false, Vector2(390.0, 420.0), true)
	survey.set_scanning(false, Vector2(390.0, 420.0))
	_check(retained_charge > 0.0 and is_equal_approx(survey.charge_distance, retained_charge), "Sustained Sweep preserves charge on release even after a tracking suspension")
	survey.end_round()
	_check(is_zero_approx(survey.charge_distance) and is_zero_approx(survey.cooldown_remaining), "round cleanup removes unfinished sweep charge and cooldown")

	for node_id in ["deep_exposure", "rapid_scan", "polar_cascade"]:
		_check(survey_game.progression.debug_purchase_node(node_id), "survey capstone path installs: " + node_id)
	_check(is_equal_approx(survey_game.progression.get_survey_spawn_probability(), 0.55) and is_equal_approx(survey_game.progression.get_survey_cooldown_seconds(), 0.9) and survey_game.progression.get_survey_spawn_count() == 2, "late Ursa Minor research raises chance, shortens cooldown, and arms the two-meteor capstone")
	survey.begin_round(6)
	survey.rng.seed = _rng_seed_with_first_roll_below(survey_game.progression.get_survey_spawn_probability())
	survey.set_scanning(true, Vector2(600.0, 430.0))
	var cascade_count: int = survey.apply_scan_segment(Vector2(220.0, 430.0), Vector2(600.0, 430.0))
	var every_cascade_target_tagged := cascade_count == 2
	for target in survey_game.meteor_layer.get_children():
		every_cascade_target_tagged = every_cascade_target_tagged and bool(target.get_meta("polar_summoned", false))
	_check(every_cascade_target_tagged and is_equal_approx(survey.cooldown_remaining, 0.9), "Polar Cascade calls exactly two tagged meteors and starts the upgraded cooldown")
	survey_game.spawner.reset()
	survey.end_round()

	var legacy_ids: Array[String] = []
	for definition in balance.UPGRADE_NODES:
		if String(definition.branch) not in ["ursa_minor", "canis_major", "draco", "local_group"]:
			legacy_ids.append(String(definition.id))
	_check(legacy_ids.size() == 71, "the pre-survey research graph remains an exact 71-ID compatibility fixture")
	survey_game.progression.load_save_data({
		"purchased_nodes": legacy_ids,
		"purchase_order": legacy_ids,
		"survey_catalog_count": 99,
	})
	_check(survey_game.progression.upgrade_level == 71 and not survey_game.progression.survey_enabled(), "a 71-node save loads without inventing Ursa Minor progress or retaining removed survey state")

	survey_game.queue_free()
	await process_frame
	await process_frame


func _rng_seed_with_first_roll_below(limit: float) -> int:
	for seed in range(1, 10000):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() < limit:
			return seed
	return 1


func _cleanup_smoke_saves(directory: String) -> void:
	var absolute_directory := ProjectSettings.globalize_path(directory)
	for slot in range(1, 4):
		var slot_path := absolute_directory.path_join("slot_%d.cfg" % slot)
		if FileAccess.file_exists(slot_path):
			DirAccess.remove_absolute(slot_path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)
