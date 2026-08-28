extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const TEST_SEED := 20260827
const TEST_SPAN := 1.05
const PLAN_TYPES := ["common", "fast", "fragment", "fireball", "major", "satellite", "galaxy"]
const SCREEN_BUDGETS := [36.0, 14.0, 150.0, 460.0, 190.0]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("OBSERVATION_SPAN: " + message)


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame

	var view: Camera2D = game.observation_view
	view.set_observation_span(1.0)
	await process_frame
	var atmospheric_at_one: Rect2 = view.atmospheric_rect()
	var activity_at_one: Rect2 = view.meteor_activity_rect()
	var plans_at_one := _capture_plans(game.spawner)

	view.set_observation_span(TEST_SPAN)
	await process_frame
	await process_frame
	var atmospheric_at_test: Rect2 = view.atmospheric_rect()
	var visible_at_test: Rect2 = view.visible_world_rect()
	var activity_at_test: Rect2 = view.meteor_activity_rect()
	var plans_at_test := _capture_plans(game.spawner)

	_check(plans_at_one != plans_at_test, "fixed-seed meteor plans expand when observation span reaches 1.05")
	_check(atmospheric_at_one == atmospheric_at_test, "atmospheric rectangle is independent of observation span")
	_check(activity_at_one.is_equal_approx(atmospheric_at_one), "stage-zero meteor activity matches the original atmospheric rectangle")
	_check(
		visible_at_test.get_center().is_equal_approx(atmospheric_at_test.get_center())
		and visible_at_test.size.is_equal_approx(atmospheric_at_test.size * TEST_SPAN),
		"visible world expands five percent around the fixed atmospheric centre"
	)
	_check(
		is_equal_approx(activity_at_test.position.x, visible_at_test.position.x)
		and is_equal_approx(activity_at_test.size.x, visible_at_test.size.x)
		and is_equal_approx(activity_at_test.position.y, atmospheric_at_test.position.y)
		and is_equal_approx(activity_at_test.size.y, atmospheric_at_test.size.y),
		"meteor activity follows the visible width while retaining the safe atmospheric height"
	)
	var expanded_plan_reaches_outer_sky := false
	game.spawner.rng.seed = TEST_SEED
	game.spawner.burnout_cell_cursors.clear()
	for type_id in PLAN_TYPES:
		for _index in range(4):
			var plan: Dictionary = game.spawner.plan_entry(type_id)
			var start := Vector2(plan.start)
			var allowed_entry := (
				is_equal_approx(start.y, activity_at_test.position.y - game.spawner.ENTRY_MARGIN)
				or is_equal_approx(start.x, activity_at_test.position.x - game.spawner.ENTRY_MARGIN)
				or is_equal_approx(start.x, activity_at_test.end.x + game.spawner.ENTRY_MARGIN)
			)
			_check(allowed_entry, "%s enters through the expanded top/side activity boundary" % type_id)
			if start.x < atmospheric_at_test.position.x or start.x > atmospheric_at_test.end.x:
				expanded_plan_reaches_outer_sky = true
	_check(expanded_plan_reaches_outer_sky, "expanded meteor plans occupy lateral sky outside the atmospheric rectangle")

	var centre := atmospheric_at_test.get_center()
	for screen_budget in SCREEN_BUDGETS:
		var world_length: float = view.screen_length_to_world(screen_budget)
		var screen_distance: float = view.world_to_screen(centre).distance_to(
			view.world_to_screen(centre + Vector2.RIGHT * world_length)
		)
		_check(
			is_equal_approx(world_length, screen_budget * TEST_SPAN)
			and is_equal_approx(screen_distance, screen_budget),
			"screen-space budget %.0fpx remains unchanged at span 1.05" % screen_budget
		)

	var meteor = game.spawner.spawn_meteor("common", centre, Vector2.RIGHT, 10.0)
	await process_frame
	var meteor_screen_radius: float = meteor.body_radius * meteor.observation_visual_scale * view.zoom.x
	var expected_visual_scale := sqrt(TEST_SPAN)
	var expected_screen_scale := 1.0 / expected_visual_scale
	_check(
		is_equal_approx(meteor.observation_visual_scale, expected_visual_scale)
		and is_equal_approx(meteor_screen_radius, meteor.body_radius / expected_visual_scale),
		"meteor visuals receive half compensation and become gradually smaller on screen"
	)
	_check(
		is_equal_approx(view.meteor_screen_scale(), expected_screen_scale),
		"meteor camera feedback derives from the same reduced screen scale as its drawing"
	)
	var size_bonus := clampf((meteor.body_radius - 7.0) * 0.52, 0.0, 18.0)
	var tracking_screen_radius: float = meteor.get_tracking_radius(view.screen_length_to_world(36.0)) * view.zoom.x
	_check(
		is_equal_approx(tracking_screen_radius, 36.0 + size_bonus),
		"meteor interaction radius remains screen-fixed while its drawing shrinks"
	)
	game.effects.reset()
	game.effects.add_kick(centre + Vector2.RIGHT, 3.0, view.meteor_screen_scale())
	game.effects.add_shake(0.6, view.meteor_screen_scale())
	_check(
		is_equal_approx(game.effects.kick_amplitude, 3.0 * expected_screen_scale)
		and is_equal_approx(game.effects.shake_pixel_scale, expected_screen_scale),
		"meteor kick and shake amplitude recede with the meteor while preserving their timing"
	)
	game.effects.reset()
	_check(
		game.starfield._background_coverage_rect().encloses(visible_at_test)
		and game.effects._visible_world_rect().is_equal_approx(visible_at_test),
		"background and full-screen feedback cover the expanded visible world"
	)
	var sky_frame: Rect2 = game.starfield._sky_frame_rect()
	var horizon_ridge: PackedVector2Array = game.starfield._horizon_ridge(sky_frame)
	_check(
		sky_frame.is_equal_approx(visible_at_test)
		and sky_frame.position.x < atmospheric_at_test.position.x
		and sky_frame.end.x > atmospheric_at_test.end.x,
		"sky gradient follows the visible frame instead of exposing the atmospheric boundary"
	)
	_check(
		is_equal_approx(horizon_ridge[0].x, sky_frame.position.x)
		and is_equal_approx(horizon_ridge[6].x, sky_frame.end.x)
		and horizon_ridge[7].is_equal_approx(sky_frame.end)
		and is_equal_approx(horizon_ridge[8].x, sky_frame.position.x),
		"horizon ridge spans the full visible frame"
	)
	_check(
		is_equal_approx(Balance.GALACTIC_OBSERVATION_SPAN_STEP, TEST_SPAN)
		and is_equal_approx(Balance.GALACTIC_FINAL_OBSERVATION_SPAN, pow(TEST_SPAN, 8)),
		"the five-percent step and eight-step ceiling share the approved balance contract"
	)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("OBSERVATION_SPAN_PASS: lateral meteor activity, three rectangles, screen budgets, reduced meteor visuals and view motion, and continuous outer sky")
		quit(0)
		return
	print("OBSERVATION_SPAN_FAIL: %d failure(s)" % failures.size())
	quit(1)


func _capture_plans(spawner: Node) -> Array[String]:
	spawner.rng.seed = TEST_SEED
	spawner.burnout_cell_cursors.clear()
	var serialized: Array[String] = []
	for type_id in PLAN_TYPES:
		for _index in range(4):
			var plan: Dictionary = spawner.plan_entry(type_id)
			serialized.append(var_to_str({
				"type": type_id,
				"start": plan.start,
				"burnout": plan.burnout,
				"velocity": plan.velocity,
			}))
	return serialized
