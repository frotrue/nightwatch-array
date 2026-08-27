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
	var plans_at_one := _capture_plans(game.spawner)

	view.set_observation_span(TEST_SPAN)
	await process_frame
	await process_frame
	var atmospheric_at_test: Rect2 = view.atmospheric_rect()
	var visible_at_test: Rect2 = view.visible_world_rect()
	var plans_at_test := _capture_plans(game.spawner)

	_check(plans_at_one == plans_at_test, "fixed-seed atmospheric plans stay byte-for-byte identical at span 1.05")
	_check(atmospheric_at_one == atmospheric_at_test, "atmospheric rectangle is independent of observation span")
	_check(
		visible_at_test.get_center().is_equal_approx(atmospheric_at_test.get_center())
		and visible_at_test.size.is_equal_approx(atmospheric_at_test.size * TEST_SPAN),
		"visible world expands five percent around the fixed atmospheric centre"
	)

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
	_check(
		is_equal_approx(meteor.observation_visual_scale, TEST_SPAN)
		and is_equal_approx(meteor_screen_radius, meteor.body_radius),
		"meteor visual radius remains screen-fixed at span 1.05"
	)
	_check(
		game.starfield._background_coverage_rect().encloses(visible_at_test)
		and game.effects._visible_world_rect().is_equal_approx(visible_at_test),
		"background and full-screen feedback cover the expanded visible world"
	)
	_check(
		is_equal_approx(Balance.GALACTIC_OBSERVATION_SPAN_STEP, TEST_SPAN)
		and is_equal_approx(Balance.GALACTIC_FINAL_OBSERVATION_SPAN, pow(TEST_SPAN, 8)),
		"the five-percent step and eight-step ceiling share the approved balance contract"
	)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("OBSERVATION_SPAN_PASS: atmospheric plans, two rectangles, screen budgets, meteor visuals, and outer coverage")
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
