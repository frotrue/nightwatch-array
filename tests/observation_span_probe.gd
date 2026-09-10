extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const TEST_SEED := 20260827
const TEST_SPAN := 1.1025
const PLAN_TYPES := ["common", "fast", "fragment", "fireball", "major", "satellite", "galaxy"]
const DISTRIBUTION_SEED := 20260829
const DISTRIBUTION_SAMPLE_COUNT := 1000
const DISTRIBUTION_TYPES := [
	"common", "fast", "fragment", "fireball", "satellite",
	"variable_star", "comet", "binary_star", "galaxy",
]
const SAFE_BURNOUT_TYPES := [
	"common", "fast", "fragment", "fireball",
	"variable_star", "binary_star", "galaxy",
]
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
	_check_forecast_projection(game)
	var activity_at_one: Rect2 = view.meteor_activity_rect()
	var plans_at_one := _capture_plans(game.spawner)

	view.set_observation_span(TEST_SPAN)
	await process_frame
	await process_frame
	var atmospheric_at_test: Rect2 = view.atmospheric_rect()
	var visible_at_test: Rect2 = view.visible_world_rect()
	var activity_at_test: Rect2 = view.meteor_activity_rect()
	var plans_at_test := _capture_plans(game.spawner)

	_check(plans_at_one != plans_at_test, "fixed-seed meteor plans expand at the 1.1025 chapter milestone")
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
	game.spawner.entry_boundary_cursors.clear()
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
			"screen-space budget %.0fpx remains unchanged at span 1.1025" % screen_budget
		)

	var meteor = game.spawner.spawn_meteor("common", centre, Vector2.RIGHT, 10.0)
	await process_frame
	var meteor_screen_radius: float = meteor.body_radius * meteor.observation_visual_scale * view.zoom.x
	var expected_visual_scale := sqrt(TEST_SPAN)
	var expected_screen_scale := 1.0 / expected_visual_scale
	var expected_shake_scale := 1.0 / TEST_SPAN
	_check(
		is_equal_approx(meteor.observation_visual_scale, expected_visual_scale)
		and is_equal_approx(meteor_screen_radius, meteor.body_radius / expected_visual_scale),
		"meteor visuals receive half compensation and become gradually smaller on screen"
	)
	_check(
		is_equal_approx(view.meteor_screen_scale(), expected_screen_scale)
		and is_equal_approx(view.meteor_shake_scale(), expected_shake_scale),
		"meteor flash and kick follow its drawing while shake receives stronger attenuation"
	)
	var size_bonus := clampf((meteor.body_radius - 7.0) * 0.52, 0.0, 18.0)
	var tracking_screen_radius: float = meteor.get_tracking_radius(view.screen_length_to_world(36.0)) * view.zoom.x
	_check(
		is_equal_approx(tracking_screen_radius, 36.0 + size_bonus),
		"meteor interaction radius remains screen-fixed while its drawing shrinks"
	)
	game.effects.reset()
	game.effects.spawn_success(centre, 1.0, Color.WHITE, 1.0, 1.0, "", Vector2.ZERO, game._meteor_flash_scale("common"), true)
	_check(
		is_equal_approx(game.effects.flash_strength, 0.26 * expected_screen_scale),
		"common meteor success keeps its flash before the galaxy stage"
	)
	game.effects.reset()
	game.effects.spawn_success(centre, 1.0, Color.WHITE, 1.0, 1.0, "", Vector2.ZERO, game._meteor_flash_scale("fireball"), true)
	_check(
		is_equal_approx(game.effects.flash_strength, 0.26 * expected_screen_scale),
		"special meteor success flash recedes with the zoomed-out drawing"
	)
	_check(
		is_equal_approx(game._meteor_flash_scale("fragment"), expected_screen_scale)
		and is_equal_approx(game._meteor_flash_scale("fragment_piece"), expected_screen_scale * 0.5),
		"split pieces receive half of their parent type's flash scale"
	)
	var common_forecast := {"type_id": "common"}
	var fast_forecast := {"type_id": "fast"}
	var fragment_forecast := {"type_id": "fragment"}
	_check(
		game.sky_contacts.forecast_contact_visible(common_forecast)
		and game.sky_contacts.forecast_contact_visible(fast_forecast)
		and game.sky_contacts.forecast_contact_visible(fragment_forecast),
		"all unlocked forecast types remain visible before the galaxy stage"
	)
	game.effects.reset()
	game.effects.add_kick(centre + Vector2.RIGHT, 3.0, view.meteor_screen_scale())
	game.effects.add_shake(0.6, game._meteor_shake_scale("fragment_piece"))
	_check(
		is_equal_approx(game.effects.kick_amplitude, 3.0 * expected_screen_scale)
		and is_equal_approx(game._meteor_shake_scale("fragment"), expected_shake_scale)
		and is_equal_approx(game.effects.shake_pixel_scale, expected_shake_scale * 0.5),
		"split-piece shake is half scale while meteor kick and parent shake stay unchanged"
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
		# Authored ridge detail may add vertices; the final three still close the
		# visible right edge and both bottom corners without an exposed border.
		and is_equal_approx(horizon_ridge[-3].x, sky_frame.end.x)
		and horizon_ridge[-2].is_equal_approx(sky_frame.end)
		and horizon_ridge[-1].is_equal_approx(Vector2(sky_frame.position.x, sky_frame.end.y)),
		"horizon ridge spans the full visible frame"
	)

	view.set_observation_span(1.0)
	await process_frame
	var opening_distribution := _capture_entry_distribution(
		game.spawner, view.meteor_activity_rect()
	)
	_check_entry_distribution("opening", opening_distribution)
	# This probe needs the purchased state, not 95 overlapping upgrade sounds,
	# banners, and delayed audio callbacks while the process is about to exit.
	game.progression.upgrade_purchased.disconnect(game._on_upgrade_purchased)
	game.progression.debug_purchase_all()
	game._sync_galactic_systems()
	game.sky_contacts.refresh_dishes()
	await process_frame
	_check_forecast_projection(game)
	game.effects.reset()
	game.effects.spawn_success(centre, 1.0, Color.WHITE, 1.0, 1.0, "", Vector2.ZERO, game._meteor_flash_scale("common"), true)
	_check(
		is_zero_approx(game.effects.flash_strength)
		and is_zero_approx(game._meteor_flash_scale("fast"))
		and game._meteor_flash_scale("fireball") > 0.0,
		"galaxy entry removes common and fast meteor success flashes only"
	)
	_check(
		not game.sky_contacts.forecast_contact_visible(common_forecast)
		and not game.sky_contacts.forecast_contact_visible(fast_forecast)
		and game.sky_contacts.forecast_contact_visible(fragment_forecast),
		"galaxy entry hides only common and fast forecast visuals"
	)
	game.sky_contacts.reset()
	var hidden_contact := {
		"id": 9001,
		"type_id": "common",
		"intercept": Vector2(game.sky_contacts.dishes[0].position),
		"error_offset": Vector2.ZERO,
		"countdown": 4.0,
		"lead_time": 4.0,
	}
	game.sky_contacts.on_contact_announced(hidden_contact)
	var hidden_contact_assigned := false
	for dish_variant in game.sky_contacts.dishes:
		var dish: Dictionary = dish_variant
		if int(dish.assigned_id) == int(hidden_contact.id):
			hidden_contact_assigned = true
			break
	_check(
		game.sky_contacts.contacts.size() == 1
		and int(game.sky_contacts.contacts[0].id) == int(hidden_contact.id)
		and hidden_contact_assigned
		and game.sky_contacts._contact_at(Vector2(hidden_contact.intercept)) == -1,
		"muted routine forecasts still drive automatic dishes without a hover target"
	)
	game.effects.reset()
	var final_distribution := _capture_entry_distribution(
		game.spawner, view.meteor_activity_rect()
	)
	_check_entry_distribution("final", final_distribution)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("OBSERVATION_SPAN_PASS: lateral meteor activity, balanced entry boundaries, three rectangles, screen budgets, reduced meteor visuals and view motion, muted galactic routine forecasts, and continuous outer sky")
		quit(0)
		return
	print("OBSERVATION_SPAN_FAIL: %d failure(s)" % failures.size())
	quit(1)


func _capture_plans(spawner: Node) -> Array[String]:
	spawner.rng.seed = TEST_SEED
	spawner.burnout_cell_cursors.clear()
	spawner.entry_boundary_cursors.clear()
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


func _capture_entry_distribution(spawner: Node, activity: Rect2) -> Dictionary:
	var distribution := {}
	for type_id in DISTRIBUTION_TYPES:
		spawner.rng.seed = DISTRIBUTION_SEED
		spawner.burnout_cell_cursors.clear()
		spawner.entry_boundary_cursors.clear()
		var top_count := 0
		var left_count := 0
		var right_count := 0
		var upper_half_count := 0
		var exact_travel_distance := true
		var burnout_stays_safe := true
		var safe_rect: Rect2 = spawner._burnout_safe_rect(activity)
		for _index in range(DISTRIBUTION_SAMPLE_COUNT):
			var plan: Dictionary = spawner.plan_entry(type_id)
			var start := Vector2(plan.start)
			var burnout := Vector2(plan.burnout)
			if is_equal_approx(start.y, activity.position.y - spawner.ENTRY_MARGIN):
				top_count += 1
			elif is_equal_approx(start.x, activity.position.x - spawner.ENTRY_MARGIN):
				left_count += 1
			elif is_equal_approx(start.x, activity.end.x + spawner.ENTRY_MARGIN):
				right_count += 1
			if start.y < activity.get_center().y:
				upper_half_count += 1
			exact_travel_distance = exact_travel_distance and is_equal_approx(
				start.distance_to(burnout), float(plan.burn_distance)
			)
			if type_id in SAFE_BURNOUT_TYPES:
				# Full lifetime upgrades can exceed the fixed field. In that case
				# the existing crossing plan must exit rather than shorten travel.
				var furthest_safe := 0.0
				for cell in range(spawner.BURNOUT_GRID_COLUMNS * spawner.BURNOUT_GRID_ROWS):
					var region: Rect2 = spawner._burnout_cell_sample_rect(activity, cell)
					for corner in [region.position, region.end, Vector2(region.position.x, region.end.y), Vector2(region.end.x, region.position.y)]:
						furthest_safe = maxf(furthest_safe, start.distance_to(corner))
				burnout_stays_safe = burnout_stays_safe and (safe_rect.has_point(burnout) or float(plan.burn_distance) > furthest_safe)
		distribution[type_id] = {
			"top": float(top_count) / DISTRIBUTION_SAMPLE_COUNT,
			"left": float(left_count) / DISTRIBUTION_SAMPLE_COUNT,
			"right": float(right_count) / DISTRIBUTION_SAMPLE_COUNT,
			"upper_half": float(upper_half_count) / DISTRIBUTION_SAMPLE_COUNT,
			"exact_travel_distance": exact_travel_distance,
			"burnout_stays_safe": burnout_stays_safe,
		}
	return distribution


func _check_forecast_projection(game: Node) -> void:
	var view: Camera2D = game.observation_view
	var screen_size: Vector2 = root.get_visible_rect().size
	var central_playfield := Rect2(screen_size * 0.25, screen_size * 0.5)
	var world: Rect2 = view.visible_world_rect()
	for uv in [Vector2(0.5, 0.5), Vector2(0.1, 0.2), Vector2(0.9, 0.7), Vector2(0.4, 0.1), Vector2(0.6, 0.9)]:
		var contact := {"intercept": world.position + world.size * uv, "error_offset": Vector2(12, -8), "lead_time": 3.0, "countdown": 1.5}
		var before := contact.duplicate(true)
		var estimate: Vector2 = game.sky_contacts._estimate_of(contact)
		var marker: Vector2 = game.sky_contacts._display_position_of(contact)
		var screen: Vector2 = view.world_to_screen(marker)
		_check(Rect2(Vector2.ZERO, screen_size).has_point(screen) and not central_playfield.has_point(screen), "forecast stays on-screen outside the central playfield at span %s" % view.observation_span)
		_check(contact == before and game.sky_contacts._estimate_of(contact).is_equal_approx(estimate), "edge projection never changes physical forecast data")


func _check_entry_distribution(label: String, distribution: Dictionary) -> void:
	for type_id in DISTRIBUTION_TYPES:
		var shares: Dictionary = distribution[type_id]
		var top_share := float(shares.top)
		var left_share := float(shares.left)
		var right_share := float(shares.right)
		var upper_half_share := float(shares.upper_half)
		_check(
			top_share >= 0.26 and top_share <= 0.34
			and left_share >= 0.30 and left_share <= 0.40
			and right_share >= 0.30 and right_share <= 0.40,
			"%s %s entries retain the 30/35/35 top-left-right boundary mix" % [label, type_id]
		)
		_check(
			upper_half_share >= 0.48 and upper_half_share <= 0.70,
			"%s %s starts stay vertically balanced instead of crowding the upper half" % [label, type_id]
		)
		_check(
			bool(shares.exact_travel_distance) and bool(shares.burnout_stays_safe),
			"%s %s keeps its exact lifetime distance and safe burnout or unavoidable field-exit contract" % [label, type_id]
		)
