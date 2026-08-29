extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const ChartData = preload("res://scripts/research_chart_data.gd")
const ProgressionController = preload("res://scripts/progression_controller.gd")
const ObservationView = preload("res://scripts/observation_view.gd")
const HostStarController = preload("res://scripts/host_star_controller.gd")
const MeteorSpawner = preload("res://scripts/meteor_spawner.gd")
const Meteor = preload("res://scripts/meteor.gd")
const PhenomenaController = preload("res://scripts/galactic_phenomena_controller.gd")
const SkyContacts = preload("res://scripts/sky_contacts.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GALACTIC_SLICE: " + message)


func _run() -> void:
	var progression = ProgressionController.new()
	var view = ObservationView.new()
	root.add_child(progression)
	root.add_child(view)

	_verify_research_shape(progression)
	_verify_single_observation_hosts(progression, view)
	_verify_simple_phenomena(view)
	_verify_global_regressions(progression)

	view.queue_free()
	progression.queue_free()
	await process_frame
	if failures.is_empty():
		print("GALACTIC_SLICE_PASS: 12 functional nodes; 17 non-interactive map records; one aim-and-hold verb; four visual target profiles; persistent supernovae; hold-observed lens shapes; visual-only lensed meteor paths; four span milestones")
		quit(0)
	else:
		push_error("GALACTIC_SLICE_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _verify_research_shape(progression) -> void:
	_check(Balance.UPGRADE_NODES.size() == 107, "only the 107 installable research definitions remain")
	_check(Balance.research_node_count() == 107 and Balance.local_group_functional_node_count() == 12, "the Local Group contributes exactly 12 functional nodes")
	_check(ChartData.LOCAL_GROUP_GALAXIES.size() == 29, "the astronomical map still carries all 29 Local Group records")
	var decoration_count := 0
	for galaxy_variant in ChartData.LOCAL_GROUP_GALAXIES:
		var galaxy: Dictionary = galaxy_variant
		var node_id := String(galaxy.node_id)
		if ChartData.is_local_group_decoration(node_id):
			decoration_count += 1
			_check(Balance.upgrade_definition(node_id).is_empty(), node_id + " is map data rather than a research definition")
			_check(progression.get_node_state(node_id) == "missing" and not progression.can_purchase(node_id), node_id + " cannot enter purchase state")
	_check(decoration_count == 17, "seventeen galaxies are non-interactive background records")

	var expected_ids := [
		"lmc_transit_watch", "smc_reference_baseline", "m31_hidden_decoy_survey", "m33_transit_network",
		"ngc6822_supernova_watch", "ic10_supernova_overlap", "ic1613_supernova_ephemeris",
		"wlm_einstein_ring", "pegasus_partial_lens", "phoenix_lensed_meteors",
		"leo_a_lensed_supernova", "aquarius_local_group_record",
	]
	var actual_ids: Array[String] = []
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(definition.get("branch", "")) == "local_group":
			actual_ids.append(String(definition.id))
	_check(actual_ids == expected_ids, "the twelve-node Local Group route stays linear and explicit")
	_check(Balance.GALACTIC_SPAN_NODE_IDS == ["m33_transit_network", "ic1613_supernova_ephemeris", "phoenix_lensed_meteors", "aquarius_local_group_record"], "one milestone at the end of each chapter owns field expansion")

	_check(Balance.GALACTIC_OBSERVATION_PROFILES.keys().size() == 4, "chapter one exposes four visual observation profiles")
	for profile_variant in Balance.GALACTIC_OBSERVATION_PROFILES.values():
		var profile: Dictionary = profile_variant
		for removed_key in ["rules", "decoy", "hidden", "comparison_candidates", "forecast_notches", "linked_pair"]:
			_check(not profile.has(removed_key), "observation profiles do not expose removed rule " + removed_key)
	_check(is_equal_approx(float(Balance.GALACTIC_OBSERVATION_PROFILES.smc_reference_baseline.tracking_time_multiplier), 1.35), "SMC varies observation duration instead of adding a comparison task")
	_check(float(Balance.GALACTIC_OBSERVATION_PROFILES.m31_hidden_decoy_survey.drift_radius_screen) == 30.0, "M31 varies target motion instead of adding hidden-sky or decoy rules")


func _verify_single_observation_hosts(progression, view: Camera2D) -> void:
	progression.reset()
	progression.purchased_nodes["lmc_transit_watch"] = true
	var controller = HostStarController.new()
	root.add_child(controller)
	controller.setup(progression, view)
	controller.begin_round()
	_check(controller.host_stars.size() == 1 and String(controller.host_star.profile_id) == "lmc_transit_watch", "LMC opens one ordinary distant target")
	_check(progression.get_host_star_capacity() == 1 and progression.get_active_transit_capacity() == 1, "chapter one begins with one target and one active observation")
	_check(not bool(controller.reference_bonus_for(controller.host_star.global_position).applied), "distant targets do not add a separate reference-star reward rule")

	var first_host = controller.host_star
	var first_wait := float(controller.next_transit_remaining)
	_check(first_wait >= 8.0 and first_wait <= 12.0, "the first distant observation arrives on the existing 8-12 second cadence")
	controller.advance_time(first_wait)
	_check(String(first_host.state) == "transiting" and first_host.can_be_tracked(), "the target becomes observable without reveal comparison or decoy gates")
	_complete_current_target(first_host, view)
	var first_metrics: Dictionary = controller.get_metrics()
	_check(controller.host_star == null and int(first_metrics.hosts_harvested) == 1, "one completed hold pays and retires the target without a second harvest gesture")
	_check(float(first_metrics.harvest_reward_total) > 0.0, "the same observation completion emits the distant-target reward")

	progression.purchased_nodes["smc_reference_baseline"] = true
	var respawn := float(controller.respawn_remaining)
	_check(respawn >= 6.0 and respawn <= 8.0, "the next distant target keeps the measured respawn interval")
	controller.advance_time(respawn)
	_check(controller.host_star != null and String(controller.host_star.profile_id) == "smc_reference_baseline", "SMC enters the target rotation as the second visual profile")
	_check(is_equal_approx(float(controller.host_star.profile.tracking_time_multiplier), 1.35) and float(controller.host_star.profile.brightness) < 1.0, "SMC is fainter and longer but uses the same tracking method")

	progression.purchased_nodes["m31_hidden_decoy_survey"] = true
	var moving_host = controller._create_host(900, Vector2(500.0, 300.0), "m31_hidden_decoy_survey")
	var anchor := Vector2(moving_host.position)
	moving_host._process(1.0)
	_check(not moving_host.position.is_equal_approx(anchor) and not moving_host.is_hidden and not moving_host.comparison_locked, "M31 creates visible slow drift without a discovery gate")
	controller._remove_host(moving_host, false)

	progression.purchased_nodes["m33_transit_network"] = true
	controller.refresh_unlock_state()
	_check(controller.host_stars.size() == 2 and progression.get_host_star_capacity() == 2 and progression.get_active_transit_capacity() == 2, "M33 allows two ordinary observation targets at once")
	for star in controller.host_stars:
		controller.next_waits[controller._key(star)] = 0.0
	controller.advance_time(0.1)
	var simultaneous := 0
	for star in controller.host_stars:
		if String(star.state) == "transiting":
			simultaneous += 1
	_check(simultaneous == 2, "both M33-era targets can be observed concurrently without priority or linked-abandon rules")

	var saved := controller.get_save_data()
	var restored = HostStarController.new()
	root.add_child(restored)
	restored.setup(progression, view)
	restored.load_save_data(saved)
	_check(restored.host_stars.size() == 2, "the simplified two-target observation state survives save/load")
	controller.queue_free()
	restored.queue_free()


func _verify_simple_phenomena(view: Camera2D) -> void:
	var progression = ProgressionController.new()
	root.add_child(progression)
	progression.purchased_nodes["galactic_reference_frame"] = true
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(definition.get("branch", "")) == "local_group":
			progression.purchased_nodes[String(definition.id)] = true
	_check(is_equal_approx(progression.get_observation_span(), Balance.GALACTIC_FINAL_OBSERVATION_SPAN), "four 10.25% milestones reach the exact 1.4774554 ceiling")

	var meteor_layer := Node2D.new()
	var phenomena = PhenomenaController.new()
	root.add_child(meteor_layer)
	root.add_child(phenomena)
	phenomena.setup(progression, view, meteor_layer)
	phenomena.begin_round()
	var metrics: Dictionary = phenomena.get_metrics()
	_check(int(metrics.active_supernovae) == 2 and int(metrics.active_arcs) == 0, "the phenomenon queue exposes at most the first two observation targets")

	var primary_supernova = phenomena._target_by_id("supernova_primary")
	primary_supernova.advance_time(30.0)
	_check(primary_supernova.get_stage() == "remnant" and primary_supernova.can_be_tracked(), "an unobserved supernova remains recoverable as a remnant")
	var saved_supernovae := phenomena.get_save_data()
	var restored_supernovae = PhenomenaController.new()
	root.add_child(restored_supernovae)
	restored_supernovae.setup(progression, view, meteor_layer)
	restored_supernovae.load_save_data(saved_supernovae)
	_check(restored_supernovae._target_by_id("supernova_primary").get_stage() == "remnant", "supernova phase survives save/load")
	restored_supernovae.queue_free()

	phenomena.completed_targets["supernova_primary"] = true
	phenomena.completed_targets["supernova_secondary"] = true
	phenomena.refresh_unlock_state()
	metrics = phenomena.get_metrics()
	_check(int(metrics.active_supernovae) == 0 and int(metrics.active_arcs) == 2, "completing the two supernovae advances the queue to two lens observations")

	var partial_lens = phenomena._target_by_id("partial_lens")
	_check(not partial_lens.has_method("apply_manual_cursor_path"), "lens shapes do not expose a dedicated cursor-path verb")
	var radius: float = view.screen_length_to_world(float(partial_lens.ring_radius_screen))
	var contact: Vector2 = partial_lens.global_position + Vector2.from_angle(float(partial_lens.arc_start) + 0.12) * radius
	var distance: float = partial_lens.get_manual_contact_distance(contact)
	var band: float = partial_lens.get_tracking_radius(view.screen_length_to_world(36.0))
	partial_lens.apply_manual_observation(0.4, distance, band, 1.0)
	var hold_progress := float(partial_lens.get_progress())
	_check(hold_progress > 0.0 and hold_progress < 1.0, "holding on the visible lens shape advances ordinary observation progress")

	var saved_phenomena := phenomena.get_save_data()
	var restored_phenomena = PhenomenaController.new()
	root.add_child(restored_phenomena)
	restored_phenomena.setup(progression, view, meteor_layer)
	restored_phenomena.load_save_data(saved_phenomena)
	_check(is_equal_approx(restored_phenomena._target_by_id("partial_lens").get_progress(), hold_progress), "ordinary lens hold progress survives save/load")
	phenomena.completed_targets["einstein_ring"] = true
	phenomena.completed_targets["partial_lens"] = true
	phenomena.refresh_unlock_state()
	_check(phenomena.get_metrics().active_arcs == 1 and phenomena._target_by_id("lensed_supernova") != null, "the final lensed supernova waits behind earlier observations instead of adding screen clutter")

	var center := phenomena.get_lens_center()
	var lens_radius := phenomena.get_lens_radius()
	var meteor = Meteor.new()
	meteor_layer.add_child(meteor)
	var entry := center - Vector2(lens_radius * 1.45, 0.0)
	var burnout := center + Vector2(lens_radius * 1.45, 0.0)
	meteor.configure(Balance.meteor_spec("common"), "common", entry, Vector2.RIGHT * 220.0, 1.0, {"automation": 1.0}, burnout, view)
	_check(phenomena.register_meteor(meteor), "an intersecting meteor receives the visual lens curve")
	_check(meteor.get_planned_position(0.0).is_equal_approx(entry) and meteor.get_planned_position(1.0).is_equal_approx(burnout), "visual lensing preserves entry and burnout")
	_check(view.meteor_activity_rect().encloses(meteor.get_lens_curve_bounds()), "the curved path remains inside the meteor activity rectangle")
	meteor.age = meteor.visible_lifetime * 0.5
	meteor._update_burn_motion(0.016)
	_check(meteor.is_lensed() and meteor.get_automatic_rate() > 0.0 and meteor.allows_automatic_assist(), "visual lensing does not create an automation exception")

	var major = Meteor.new()
	meteor_layer.add_child(major)
	major.configure(Balance.meteor_spec("major"), "major", entry, Vector2.RIGHT * 220.0, 1.0, {}, burnout, view)
	_check(phenomena.register_meteor(major), "the visual curve has no lens-specific meteor-type exclusion")
	_check(MeteorSpawner.MAX_TOTAL_METEORS == 32 and SkyContacts.TRACK_SPEED > 436.8, "the atmospheric cap and fast-dish regression remain unchanged")

	phenomena.queue_free()
	restored_phenomena.queue_free()
	meteor_layer.queue_free()
	progression.queue_free()


func _verify_global_regressions(progression) -> void:
	progression.reset()
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(Dictionary(definition.get("effect_contract", {})).get("kind", "")) == "observation_value_multiplier":
			progression.purchased_nodes[String(definition.id)] = true
	_check(is_equal_approx(progression.get_observation_value_multiplier("common", 0), 8192.0), "the legacy meteor economy remains exactly x8192")
	_check(is_equal_approx(progression.get_transit_value_multiplier(), 1.0), "the meteor multiplier does not leak into distant-target rewards")


func _complete_current_target(target, view: Camera2D) -> void:
	var tracking_radius: float = target.get_tracking_radius(view.screen_length_to_world(36.0))
	for _step in range(32):
		if not target.can_be_tracked():
			break
		target.apply_manual_observation(0.2, 0.0, tracking_radius, 1.0)
