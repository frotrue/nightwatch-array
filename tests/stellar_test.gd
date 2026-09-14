extends SceneTree

const Fixtures = preload("res://tests/support/game_fixture.gd")
const Policy = preload("res://scripts/spawn_policy.gd")
const Meteor = preload("res://scripts/meteor.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error("STELLAR: " + message)

func _game():
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.running = false
	game.events.running = false
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	return game

func _run() -> void:
	await _test_unlock_and_save()
	for manual in [false, true]:
		for scale in [1.0, 0.6]:
			_test_blast(manual, scale)
	_test_fragments_and_samples()
	if failures.is_empty(): print("STELLAR_PASS: early unlock, upgrades, save/RNG compatibility, manual/auto supernova, scaled boundaries, exclusions, samples and fragment isolation")
	quit(0 if failures.is_empty() else 1)

func _test_unlock_and_save() -> void:
	var game = _game()
	var p = game.progression
	var policy := Policy.new(31)
	check(policy.probability("stellar", p) == 0.0, "star locked before expansion")
	p.debug_purchase_all()
	game.upgrade_tree.open_tree()
	p.observation_data = 500000000.0
	check(game.deep_sky.can_purchase("ext_sct_stellar"), "first star research immediately available after expansion")
	check(game.deep_sky.purchase("ext_sct_stellar"), "normal research transaction unlocks stars")
	check(policy.probability("stellar", p) > 0.0 and policy.probability("black_hole", p) == 0.0, "star unlock does not grant late black holes")
	var before: float = policy.probability("stellar", p)
	for id in ["ext_sct_reach", "ext_sct_tracking", "ext_sct_arrivals", "ext_sct_supernova"]:
		check(game.deep_sky.purchase(id), "reachable Scutum study: " + id)
	check(is_equal_approx(policy.probability("stellar", p) / before, 1.35), "stellar spawn upgrade applied once")
	check(is_equal_approx(p.get_celestial_multiplier("stellar", "speed"), 1.3), "stellar speed upgrade")
	check(is_equal_approx(p.get_celestial_multiplier("stellar", "value"), 1.25), "stellar value upgrade")
	check(is_equal_approx(Meteor.SUPERNOVA_RADIUS * p.extension_effect("supernova_radius"), 300.0), "range progresses to 300")
	check(is_equal_approx(p.get_celestial_multiplier("galaxy", "value"), 1.0), "stellar studies do not boost planets")
	var star = game.spawner.spawn_meteor("stellar", Vector2(500, 300), Vector2.RIGHT, 30.0)
	check(star != null and game.spawner.spawn_meteor("stellar") == null, "one reserved star including its linger")
	star.base_automatic_rate = 1.0
	star.tick_observation(0.1)
	check(is_equal_approx(star.observation_progress, 0.13), "automatic work uses stellar speed")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(saved)
	check(game.deep_sky.research_owned("ext_sct_stellar") and game.deep_sky.research_owned("ext_sct_supernova"), "research survives JSON save/load")
	await process_frame
	check(game.meteor_layer.get_child_count() == 0, "load clears star and transient explosion")
	saved.deep_sky.extension.catalogue_version = 5
	saved.deep_sky.extension.research_ids = ["ext_protocol"]
	saved.simulation.spawner.rng.occurrence.erase("stellar")
	saved.simulation.spawner.rng.entries.erase("stellar")
	game._apply_save_data(saved)
	check(not game.deep_sky.research_owned("ext_sct_stellar") and game.deep_sky.research_owned("ext_protocol"), "old saves retain ownership without granting stars")
	var restored: Dictionary = game.spawner.spawn_policy.save_state()
	for kind in saved.simulation.spawner.rng.occurrence:
		check(restored.occurrence[kind] == saved.simulation.spawner.rng.occurrence[kind], "old RNG stream preserved: " + kind)
	check(restored.occurrence.has("stellar"), "missing new stream has a seeded fallback")
	game.free()
	paused = false

func _test_blast(manual: bool, view_scale: float) -> void:
	var game = _game()
	game.observation_phase_active = true
	game.effects.motion_intensity = 0.0 # Accessibility cannot disable the mechanic.
	game.effects.screen_flashes_enabled = false
	game.observation_view.zoom = Vector2.ONE * view_scale
	var unit: float = game.observation_view.screen_length_to_world(1.0)
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(550, 300))
	var radius := Meteor.SUPERNOVA_RADIUS * unit
	var star = game.spawner.spawn_meteor("stellar", centre, Vector2.RIGHT, 30.0)
	var targets: Array = []
	for kind in ["common", "fast", "fragment_piece", "fireball", "satellite", "comet", "variable_star", "binary_star", "galaxy", "major"]:
		targets.append(game.spawner.spawn_meteor(kind, centre + Vector2.RIGHT * 70.0 * unit, Vector2.RIGHT, 30.0))
	var edge = game.spawner.spawn_meteor("common", centre + Vector2.RIGHT * radius, Vector2.RIGHT, 30.0)
	var far = game.spawner.spawn_meteor("fast", centre + Vector2.RIGHT * (radius + 1.0), Vector2.RIGHT, 30.0)
	var hole = game.spawner.spawn_meteor("black_hole", centre, Vector2.RIGHT, 30.0)
	var other = Meteor.new() # Deliberate fixture bypasses the one-star reservation.
	other.configure(Balance.meteor_spec("stellar"), "stellar", centre, Vector2.RIGHT, 1.0, {})
	game.meteor_layer.add_child(other)
	game._on_meteor_spawned(other)
	var expired = game.spawner.spawn_meteor("fast", centre, Vector2.RIGHT, 30.0)
	expired.alive = false
	star.manual_touched = manual
	star.manual_tracking_time = 1.0 if manual else 0.0
	star.base_automatic_rate = 1.0
	star.observation_progress = 1.0
	var earned: float = game.progression.total_data_earned
	var expected_reward: float = round(star.base_value * (1.0 if manual else 0.68))
	for target in targets: expected_reward += maxf(1.0, round(target.base_value * 0.68))
	expected_reward += maxf(1.0, round(edge.base_value * 0.68))
	targets[0].manual_touched = true
	var manual_count: int = game.progression.manual_successes
	star.tick_resolve()
	check(star.observed_successfully and is_equal_approx(star.supernova_radius, radius), "completion triggers scaled blast")
	for target in targets: check(target.observed_successfully and not target.alive, "blast completes " + target.type_id)
	check(edge.observed_successfully and far.alive, "inclusive boundary and outside exclusion")
	check(hole.alive and other.alive and not expired.observed_successfully, "holes, other stars and expired targets excluded")
	check(game.progression.total_data_earned - earned == expected_reward, "every blast target pays the automatic reward exactly once")
	check(game.progression.manual_successes - manual_count == (1 if manual else 0), "blast does not turn prior touches into manual completions")
	var paid: float = game.progression.total_data_earned
	star.tick_resolve()
	edge.complete_from_supernova()
	check(game.progression.total_data_earned == paid, "completion cannot pay twice")
	check(not star.completion_glint_enabled and star.completion_motion_scale == 0.0, "completion respects accessibility")
	other.age = other.visible_lifetime
	other.tick_resolve()
	check(not other.observed_successfully and other.supernova_radius == 0.0, "expiry is not a supernova")
	game.free()
	paused = false

func _test_fragments_and_samples() -> void:
	var game = _game()
	game.progression.debug_purchase_all()
	game.observation_phase_active = true
	game.spawner.running = true
	game.spawner.phase_time_remaining = 30.0
	game.observation_phase_remaining = 60.0
	game.events.canis_major_state = "idle"
	for i in 4: game.deep_sky.modules.grant_copy("focus")
	game.deep_sky.modules.unlocked_slots = 5
	game.deep_sky.modules.slots.assign(["focus", "focus", "focus", "focus", ""])
	var centre: Vector2 = game.observation_view.screen_to_world(Vector2(550, 300))
	var star = game.spawner.spawn_meteor("stellar", centre, Vector2.RIGHT, 30.0)
	var parent = game.spawner.spawn_meteor("common", centre, Vector2.RIGHT * 120.0, 30.0)
	var fragment = game.spawner.spawn_meteor("fragment", centre, Vector2.RIGHT * 120.0, 30.0)
	var director = game.deep_sky.director
	director.remaining = 0.0
	director.try_opportunity()
	# Advance only the fixture's scheduler to materialize the special meteor.
	for descriptor in director.pending.duplicate(): director._spawn_component(descriptor)
	director.pending.clear()
	var rare_targets: Array = director.targets()
	check(not rare_targets.is_empty(), "special meteor fixture exists")
	for target in rare_targets:
		target.age = target.warning_time
		target.position = centre
	var samples: int = game.deep_sky.state.samples
	star.observation_progress = 1.0
	star.tick_resolve()
	check(parent.observed_successfully and fragment.observed_successfully, "original parents complete")
	var children := 0
	for child in game.meteor_layer.get_children():
		if child.type_id == "fragment_piece":
			children += 1
			check(child.alive and not child.observed_successfully, "new fragment survives the same explosion")
	check(children == 5, "three normal fragments and two module fragments")
	check(game.deep_sky.state.samples > samples, "special meteor awards samples")
	var paid_samples: int = game.deep_sky.state.samples
	for target in rare_targets: target.complete_from_supernova()
	check(game.deep_sky.state.samples == paid_samples, "special samples paid once")
	game.free()
	paused = false
