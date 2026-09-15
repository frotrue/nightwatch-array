extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Policy = preload("res://scripts/spawn_policy.gd")
const STEP := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BLACK_HOLE: " + message)

func _game():
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	return game

func _run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("Black hole test timeout"); quit(1))
	for manual in [false, true]:
		var game = _game()
		var source = game.spawner.spawn_meteor("black_hole", Vector2(550, 300), Vector2(30, 0), 30.0)
		check(source != null, "black hole uses reserved capacity")
		var near = game.spawner.spawn_meteor("common", Vector2(750, 300), Vector2(20, 0), 20.0)
		var far = game.spawner.spawn_meteor("fast", Vector2(800, 300), Vector2(20, 0), 20.0)
		var boundary = game.spawner.spawn_meteor("binary_star", Vector2(550, 540), Vector2(20, 0), 20.0)
		var dead = game.spawner.spawn_meteor("fragment_piece", Vector2(560, 300), Vector2(20, 0), 20.0)
		dead.alive = false
		near.observation_progress = 0.4
		var before: Vector2 = source.position
		source.tick_motion(STEP, 1)
		check(source.position != before and near.gravity_capture == null, "live black hole moves without attracting")
		# Set the completion pose exactly for the inclusive radius assertion.
		source.position = Vector2(550, 300)
		source.manual_touched = manual
		source.observation_progress = 1.0
		source.tick_resolve()
		check(near.gravity_capture != null and boundary.gravity_capture != null, "manual/automatic completion gathers inside and boundary targets")
		check(far.gravity_capture == null and dead.gravity_capture == null and source.gravity_capture == null, "outside, dead and black holes are excluded")
		var capture = near.gravity_capture
		var reward: float = game.progression.observation_data
		source.tick_resolve()
		check(capture == near.gravity_capture and reward == game.progression.observation_data, "completion and capture fire once")
		source.free()
		check(not game.black_hole_lens.lens.visible and game.black_hole_lens.background_copy.copy_mode == 0, "lens copy releases with source")
		var age: float = near.age
		for tick in 51: near.tick_motion(STEP, tick + 2)
		check(near.position.distance_to(Vector2(550, 300)) < 70.0, "gather survives source deletion and reaches a loose central cluster")
		check(is_equal_approx(near.age, age), "pull preserves the remaining observation window")
		check(near.observation_progress == 0.4 and near.alive and game.progression.observation_data == reward, "pull never consumes, completes or pays for targets")
		for tick in 70:
			var previous: Vector2 = near.position
			near.tick_motion(STEP, tick + 53)
			check(near.position.distance_to(previous) < 3.0, "release and normal motion have no path snap")
		check(near.gravity_capture == null, "temporary gravity state expires")
		# Repeated captures rebase from the current position, with no discontinuity.
		var start: Vector2 = near.position
		near.begin_gravity_capture(Vector2(500, 300), 1.0)
		check(near.position == start, "recapture starts at current position")
		var save: Dictionary = game._build_save_data()
		game._apply_save_data(save)
		await process_frame
		check(game.meteor_layer.get_child_count() == 0, "load clears transient captured sky")
		game.free()
	_test_policy()
	_test_outer_research()
	_test_lensed_contacts()
	_test_three_lenses()
	await _test_worker_parity()
	if failures.is_empty(): print("BLACK_HOLE_PASS: unlock, reserved spawn, completion, radius, capture/release, save cleanup and worker parity")
	quit(0 if failures.is_empty() else 1)

func _test_policy() -> void:
	var game = _game()
	var policy := Policy.new(87)
	check(policy.probability("black_hole", game.progression) == 0.0, "black hole locked initially")
	game.progression.purchased_nodes["galaxy_imaging"] = true
	check(policy.probability("black_hole", game.progression) == 0.0, "old base research no longer unlocks black hole")
	game.progression.purchased_nodes["galactic_reference_frame"] = true
	game.deep_sky.state.research_ids.append("ext_sgr_black_hole")
	check(policy.probability("black_hole", game.progression) > 0.0, "Sagittarius research unlocks black hole")
	var old_save := policy.save_state()
	old_save.occurrence.erase("black_hole")
	old_save.entries.erase("black_hole")
	policy.restore_state(old_save)
	var other := Policy.new(87)
	other.restore_state(old_save)
	for tick in 1200:
		check(policy.roll(game.progression) == other.roll(game.progression), "old saves deterministically initialize the added stream")
	# Admission follows the ordinary forecast pipeline, rather than a special event.
	game.spawner._announce_regular_spawn(null, "black_hole")
	game.spawner.pending_contacts.back().countdown = 0.0
	game.spawner._update_pending_contacts(STEP)
	check(game.spawner._slot_count(["black_hole"]) == 1, "ordinary forecast admits black hole")
	game.free()

func _test_outer_research() -> void:
	var game = _game()
	var p = game.progression
	var state = game.deep_sky.state
	var policy := Policy.new(201)
	for id in ["variable_watchlist", "double_star_resolution", "galaxy_imaging"]: p.purchased_nodes[id] = true
	for kind in Policy.OUTER_UNLOCKS:
		check(policy.probability(kind, p) == 0.0, "legacy base purchase does not unlock " + kind)
	var old_multiplier: float = p.get_observation_value_multiplier("common", 1)
	check(is_equal_approx(p.get_analysis_speed_multiplier("satellite"), 1.3) and is_equal_approx(p.get_analysis_speed_multiplier("comet"), 1.3), "base tracking benefits existing small targets")
	p.purchased_nodes["galactic_reference_frame"] = true
	state.research_ids.append("ext_protocol")
	# Cross-figure progression follows only the selected path, not full completion.
	for id in ["ext_sge_cadence", "ext_sge_forecast", "ext_sge_solution", "ext_cnc_planet", "ext_cnc_tracking", "ext_sgr_black_hole"]:
		check(state.research_ready(id), "minimal path reaches " + id)
		state.research_ids.append(id)
	for kind in Policy.OUTER_UNLOCKS:
		var unlocked: bool = Policy.OUTER_UNLOCKS[kind] in state.research_ids
		check((policy.probability(kind, p) > 0.0) == unlocked, "only the researched celestial branch admits " + kind)
	check(not state.research_ids.has("ext_sge_stream") and not state.research_ids.has("ext_cnc_survey"), "capstones are optional for the next figure")
	var baseline := {}
	for kind in ["variable_star", "binary_star", "galaxy", "black_hole"]:
		baseline[kind] = {"chance": policy.probability(kind, p), "value": p.get_observation_value_multiplier(kind, 1)}
	for id in game.deep_sky.Data.RESEARCH_ORDER:
		if game.deep_sky.Data.RESEARCH[id].get("branch", "") in ["sagitta", "cancer", "sagittarius"] and id not in state.research_ids: state.research_ids.append(id)
	for kind in baseline:
		var spawn_gain := 1.35 * 1.3 if kind == "galaxy" else (1.35 if kind == "black_hole" else 1.0)
		var value_gain := 1.5 * 1.3 if kind == "galaxy" else 1.5
		check(is_equal_approx(policy.probability(kind, p) / baseline[kind].chance, spawn_gain), "independent spawn gain for " + kind)
		check(is_equal_approx(p.get_observation_value_multiplier(kind, 1) / baseline[kind].value, value_gain), "reward gain for " + kind)
		var target = game.spawner.spawn_meteor(kind, Vector2(500, 300), Vector2.RIGHT, 30.0)
		check(is_equal_approx(target.analysis_speed_multiplier, p.get_analysis_speed_multiplier(kind)), "manual speed reaches live " + kind)
		target.base_automatic_rate = 0.1
		target.dish_assist_rate = 0.2
		target.tick_observation(0.1)
		check(is_equal_approx(target.observation_progress, 0.039), "automatic work gains exactly 30 percent for " + kind)
		target.free()
	check(is_equal_approx(p.get_observation_value_multiplier("common", 1), old_multiplier), "base data bonuses remain and outer family buffs do not leak into common meteors")
	var hole = game.spawner.spawn_meteor("black_hole", Vector2(500, 300), Vector2.RIGHT, 30.0)
	var inside = game.spawner.spawn_meteor("common", Vector2(859, 300), Vector2.RIGHT, 30.0)
	var outside = game.spawner.spawn_meteor("common", Vector2(861, 300), Vector2.RIGHT, 30.0)
	hole.observation_progress = 1.0
	hole.tick_resolve()
	check(inside.gravity_capture != null and outside.gravity_capture == null, "live completion applies the upgraded 360 pixel radius")
	if inside.gravity_capture != null:
		check(is_equal_approx(inside.gravity_capture.slow_seconds, 3.0), "two duration researches add two seconds to capture")
		for tick in 170: inside.tick_motion(STEP, tick)
		check(inside.gravity_capture != null, "upgraded slowing outlasts the original duration")
		for tick in 65: inside.tick_motion(STEP, tick + 170)
		check(inside.gravity_capture == null, "upgraded slowing still expires")
	var before: Array = state.research_ids.duplicate()
	var save: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game.deep_sky.state.research_ids.clear()
	game._apply_save_data(save)
	check(game.deep_sky.state.research_ids == before and p.has_upgrade("galaxy_imaging") and p.has_extension_research("ext_sgr_black_hole"), "save roundtrip retains base and outer research ownership")
	for invalid in [0, 4.5, 5, true, "4"]:
		check(not game.deep_sky.supports_save({"version": invalid}), "reject malformed or future save version")
	save.deep_sky.extension.catalogue_version = 4
	save.deep_sky.extension.research_ids = ["ext_protocol", "ext_sge_cadence", "ext_sge_forecast", "ext_sge_solution"]
	game._apply_save_data(save)
	check(p.has_extension_research("ext_sge_solution") and is_equal_approx(p.get_celestial_multiplier("variable_star", "spawn"), 1.35), "v4 Sagitta purchases retain their IDs and gain their new effects")
	check(policy.probability("galaxy", p) == 0.0 and policy.probability("black_hole", p) == 0.0 and p.has_upgrade("galaxy_imaging"), "v4 base records survive without granting Cancer or Sagittarius")
	game.free()

func _test_lensed_contacts() -> void:
	var game = _game()
	var hole = game.spawner.spawn_meteor("black_hole", Vector2(500, 300), Vector2(1, 0), 30.0)
	hole.age = 4.0
	var sample = game.spawner.spawn_meteor("common", Vector2(540, 300), Vector2(1, 0), 30.0)
	var physical: Vector2 = sample.global_position
	var apparent: Vector2 = sample.get_observation_position(1.0)
	check(apparent.distance_to(physical) > 8.0 and sample.global_position == physical, "optical image shifts without moving the physical target")
	check(game.observer._target_contact_distance(sample, apparent) < 0.001, "visual centre receives centred manual quality")
	game.observer.previous_cursor_position = apparent
	game.observer.cursor_position = apparent
	check(game.observer._circle_contact_interval(sample, 1.0) == Vector2(0, 1), "circle contact follows the lensed image")
	check(game.observer._linear_contact_interval(sample, 1.0) == Vector2(0, 1), "linear contact follows the lensed image")
	game.observer._begin_tick_cache()
	var cached: Vector2 = game.observer._target_position_at(sample, 0.4)
	game.observer._end_tick_cache()
	check(cached == game.observer._target_position_at(sample, 0.4), "cached and uncached optical contact poses match")
	game.black_hole_lens.motion_scale = 0.0
	check(sample.get_observation_position(1.0) == physical, "reduced motion restores original image and contact centre")
	game.black_hole_lens.motion_scale = 1.0
	check(hole.get_observation_position(1.0) == hole.global_position, "black hole never lenses itself")
	var close: Vector2 = hole.global_position + Vector2(2, 0)
	var close_image: Vector2 = game.black_hole_lens.project_position(close, 1.0)
	check(close_image.is_finite() and close_image.distance_to(hole.global_position) > hole.body_radius, "near-aligned primary image remains visible outside the shadow")
	var distant: Vector2 = hole.global_position + Vector2(1000, 0)
	check(game.black_hole_lens.project_position(distant, 1.0) == distant, "far-field contacts are unchanged")
	game.black_hole_lens.motion_scale = 0.5
	var half_strength: Vector2 = sample.get_observation_position(1.0)
	check(half_strength.x > physical.x and half_strength.x < apparent.x, "reduced lens strength returns the apparent centre continuously")
	hole.free()
	check(sample.get_observation_position(1.0) == physical, "removing the lens clears optical selection offsets")
	game.free()

func _test_worker_parity() -> void:
	var games: Array = []
	for parallel in [false, true]:
		var game = _game()
		game.parallel_motion_enabled = parallel
		for index in 132:
			var target = game.spawner.MeteorScript.new()
			target.configure(game.Balance.meteor_spec("common"), "common", Vector2(300 + index, 300), Vector2(20, 0), 10.0, {})
			target.wobble_phase = 0.0
			target.simulation_id = index
			game.meteor_layer.add_child(target)
			if index < 3: target.begin_gravity_capture(Vector2(250, 300), 1.0)
		games.append(game)
	for tick in 130:
		for game in games: game._tick_target_motion(game.meteor_layer.get_children(), STEP)
		for index in 132:
			var left = games[0].meteor_layer.get_child(index)
			var right = games[1].meteor_layer.get_child(index)
			check(left.position.distance_to(right.position) < 0.0001 and is_equal_approx(left.age, right.age), "threaded and serial capture/release match")
	for game in games: game.free()
	await process_frame

func _test_three_lenses() -> void:
	var game = _game()
	var optics = game.black_hole_lens
	var holes: Array = []
	var samples: Array = []
	for i in 3:
		var centre := Vector2(200 + i * 360, 300)
		var hole = game.spawner.spawn_meteor("black_hole", centre, Vector2.RIGHT, 30.0)
		hole.age = 4.0
		holes.append(hole)
		samples.append(game.spawner.spawn_meteor("common", centre + Vector2(40, 0), Vector2.RIGHT, 30.0))
	check(game.spawner.spawn_meteor("black_hole") == null, "fourth black hole is rejected")
	optics._process(0.0)
	for i in 3:
		check(optics.targets[i] == holes[i] and optics.lenses[i].visible, "every black hole retains its own visible lens")
		check(optics.background_copies[i].copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "each active pass refreshes the previous lens image")
		check(samples[i].get_observation_position(1.0).distance_to(samples[i].global_position) > 8.0, "each lens shifts its nearby manual contact")
	check(optics.lenses[0].material != optics.lenses[1].material and optics.lenses[1].material != optics.lenses[2].material, "lens parameters are independent")
	# Two lenses overlap. Reverse the shader sampling analytically to recover
	# the physical point from the composed primary image.
	holes[1].position = Vector2(260, 300)
	holes[1].previous_simulation_position = holes[1].position
	var physical := Vector2(310, 300)
	var projected: Vector2 = optics.project_position(physical, 1.0)
	var recovered := projected
	for i in range(2, -1, -1):
		var hole = holes[i]
		var extent: float = hole.body_radius * hole._head_scale() * hole._current_visual_scale() * optics.EXTENT_RADII
		var offset: Vector2 = recovered - hole.global_position
		var radius := offset.length() / extent
		if radius < 1.0 and radius > 0.001:
			var bend: float = optics.EINSTEIN_RADIUS * optics.EINSTEIN_RADIUS / maxf(radius, 0.12) * (1.0 - smoothstep(optics.TAPER_START, 1.0, radius))
			recovered -= offset.normalized() * bend * extent * hole.get_burn_visibility()
	check(recovered.distance_to(physical) < 0.1, "overlapping manual projection matches the shader pass order")
	optics.motion_scale = 0.0
	optics._process(0.0)
	check(optics.project_position(physical, 1.0) == physical, "reduced motion disables all lens contact offsets")
	for copy in optics.background_copies:
		check(copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "reduced motion disables every screen copy")
	optics.motion_scale = 1.0
	optics._process(0.0)
	holes[1].free()
	check(not optics.lenses[1].visible and optics.background_copies[1].copy_mode == 0, "deleting the middle source disables only its pass")
	check(optics.lenses[0].visible and optics.lenses[2].visible, "other lens passes survive middle-source removal")
	var replacement = game.spawner.spawn_meteor("black_hole", Vector2(560, 300), Vector2.RIGHT, 30.0)
	check(replacement != null and optics.targets[1] == replacement, "a new hole reuses the released lens slot")
	# Two real completion callbacks recapture a shared target without duplicating
	# its reward or leaving a reference to a freed source.
	var common = game.spawner.spawn_meteor("common", Vector2(380, 300), Vector2.RIGHT, 30.0)
	holes[0].observation_progress = 1.0
	holes[0].tick_resolve()
	var first_capture = common.gravity_capture
	check(first_capture != null, "first black hole captures the shared target")
	replacement.observation_progress = 1.0
	replacement.tick_resolve()
	check(common.gravity_capture != null and common.gravity_capture != first_capture and common.alive, "second black hole safely rebases the same live target")
	check(game.spawner.spawn_meteor("black_hole") == null, "completion remnants continue occupying black hole slots")
	holes[0].free()
	replacement.free()
	holes[2].free()
	for copy in optics.background_copies:
		check(copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "all screen copies stop after the last source exits")
	check(not optics.is_processing() and optics.project_position(physical, 1.0) == physical, "last-source removal stops processing and restores contacts")
	game.free()
