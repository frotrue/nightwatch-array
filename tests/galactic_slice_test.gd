extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const ProgressionController = preload("res://scripts/progression_controller.gd")
const ObservationView = preload("res://scripts/observation_view.gd")
const HostStarController = preload("res://scripts/host_star_controller.gd")
const HostStar = preload("res://scripts/host_star.gd")
const ComparisonStar = preload("res://scripts/comparison_star.gd")
const MeteorSpawner = preload("res://scripts/meteor_spawner.gd")

const POLICY_HORIZON := 180.0
const POLICY_STEP := 0.05

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
	var controller = HostStarController.new()
	root.add_child(progression)
	root.add_child(view)
	root.add_child(controller)
	controller.setup(progression, view)

	_check(Balance.UPGRADE_NODES.size() == 124, "the research graph contains 124 nodes")
	var lmc: Dictionary = Balance.upgrade_definition("large_magellanic_cloud")
	var smc: Dictionary = Balance.upgrade_definition("small_magellanic_cloud")
	_check(int(lmc.cost) == 550000000 and lmc.prerequisites == ["galactic_reference_frame"], "LMC costs 550M and follows the Galactic Reference Frame")
	_check(int(smc.cost) == 800000000 and smc.prerequisites == ["large_magellanic_cloud"], "SMC costs 800M and follows LMC")
	_check(HostStarController.MAX_HOST_STARS == 2 and HostStarController.MAX_ACTIVE_TRANSITS == 2, "the Local Group layer has hard caps of two hosts and two active windows")
	_check(progression.get_host_star_capacity() == 1 and progression.get_active_transit_capacity() == 1, "runtime host and active-window capacities begin at one")
	_check(MeteorSpawner.MAX_TOTAL_METEORS == 32, "the atmospheric meteor cap remains independently fixed at 32")
	_check(is_equal_approx(progression.get_observation_span(), 1.0), "observation span begins at 1.0")
	progression.purchased_nodes["large_magellanic_cloud"] = true
	_check(is_equal_approx(progression.get_observation_span(), 1.05), "LMC applies the first exact 5% span step")
	progression.purchased_nodes["small_magellanic_cloud"] = true
	_check(is_equal_approx(progression.get_observation_span(), 1.1025), "SMC compounds the second exact 5% span step")
	_check(is_equal_approx(progression.get_transit_value_multiplier(), 1.5), "SMC affects harvest value by x1.5")
	progression.purchased_nodes.erase("small_magellanic_cloud")

	controller.refresh_unlock_state()
	_check(controller.get_child_count() == 1 and controller.host_star != null, "unlocking LMC creates exactly one stationary host")
	var first_host = controller.host_star
	var first_id := int(first_host.stable_star_id)
	var first_position := Vector2(first_host.global_position)
	controller.begin_round()
	var first_wait: float = controller.next_transit_remaining
	_check(first_wait >= 8.0 and first_wait <= 12.0, "the first transit wait stays in the 8-12 second contract")
	controller.advance_time(first_wait)
	_check(String(first_host.state) == "transiting", "idle advances to transiting after the scheduled wait")

	var inside_position := first_position + Vector2(view.screen_length_to_world(100.0), 0.0)
	var outside_position := first_position + Vector2(view.screen_length_to_world(150.0), 0.0)
	var inside_bonus: Dictionary = controller.record_meteor_observation(inside_position)
	var outside_bonus: Dictionary = controller.record_meteor_observation(outside_position)
	_check(bool(inside_bonus.applied) and is_equal_approx(float(inside_bonus.multiplier), 1.25), "a meteor inside the screen-fixed reference radius receives one x1.25 bonus")
	_check(not bool(outside_bonus.applied), "a meteor outside the screen-fixed reference radius receives no bonus")
	var bonus_metrics: Dictionary = controller.get_metrics()
	_check(is_equal_approx(float(bonus_metrics.meteor_reference_bonus_ratio), 0.5), "reference-bonus ratio is measured only while a host is live")

	# Force a symmetric tie only inside this probe. Production remains capped at
	# one host; the resolver still has an explicit stable-id tie break.
	var tie_host = HostStar.new()
	tie_host.configure(first_id + 20, first_position + Vector2(view.screen_length_to_world(40.0), 0.0), 1.0, view)
	controller.add_child(tie_host)
	first_host.position = first_position - Vector2(view.screen_length_to_world(20.0), 0.0)
	tie_host.position = first_position + Vector2(view.screen_length_to_world(20.0), 0.0)
	var tie_result: Dictionary = controller.reference_bonus_for(first_position)
	_check(int(tie_result.star_id) == first_id, "equal normalized distances resolve to the lower stable star id")
	tie_host.queue_free()
	first_host.position = first_position
	await process_frame

	_complete_current_transit(first_host, view)
	_check(controller.host_star == first_host and String(first_host.state) == "idle" and int(first_host.confirmation_count) == 1, "the first completed transit keeps its host and records one confirmation")
	_check(first_host.get_harvest_reward() == 279000000.0, "one centered Perfect confirmation offers the current 279M harvest")
	_check(controller.next_transit_remaining >= 4.0 and controller.next_transit_remaining <= 6.0, "the second transit uses a shorter 4-6 second wait")
	_check(bool(controller.reference_bonus_for(first_host.global_position).applied), "waiting for more evidence preserves the reference anchor")

	controller.advance_time(controller.next_transit_remaining)
	controller.advance_time(HostStarController.TRANSIT_WINDOW)
	var missed_metrics: Dictionary = controller.get_metrics()
	_check(controller.host_star == first_host and int(first_host.confirmation_count) == 1 and String(first_host.state) == "idle", "a miss keeps the same host and its prior confirmation")
	_check(int(missed_metrics.transits_missed) == 1, "the missed transit is counted once")

	controller.advance_time(controller.next_transit_remaining)
	_complete_current_transit(first_host, view)
	_check(int(first_host.confirmation_count) == 2 and first_host.get_harvest_reward() == 376650000.0, "two Perfect confirmations offer the x1.35 376.65M harvest")
	_check(controller.next_transit_remaining >= 3.0 and controller.next_transit_remaining <= 5.0, "the third transit uses a shorter 3-5 second wait")

	controller.advance_time(controller.next_transit_remaining)
	first_host.apply_manual_observation(0.4, 0.0, first_host.get_tracking_radius(view.screen_length_to_world(36.0)), 1.0)
	var saved: Dictionary = controller.get_save_data()
	var restored = HostStarController.new()
	root.add_child(restored)
	restored.setup(progression, view)
	restored.load_save_data(saved)
	_check(restored.host_star != null and String(restored.host_star.state) == "transiting", "an active third transit survives save/load")
	_check(int(restored.host_star.confirmation_count) == 2 and int(restored.host_star.stable_star_id) == int(first_host.stable_star_id), "save/load preserves confirmations and stable host id")
	_check(is_equal_approx(restored.host_star.get_progress(), first_host.get_progress()) and is_equal_approx(restored.transit_remaining, controller.transit_remaining), "save/load preserves transit progress and window time")
	var restored_misses_before := int(restored.get_metrics().transits_missed)
	restored.begin_round()
	restored.end_round()
	_check(String(restored.host_star.state) == "idle" and int(restored.host_star.confirmation_count) == 2, "a round boundary turns an active transit into a miss without erasing completed evidence")
	_check(int(restored.get_metrics().transits_missed) == restored_misses_before + 1, "the round-boundary transit miss is measured once")

	_complete_current_transit(first_host, view)
	_check(int(first_host.confirmation_count) == 3 and first_host.get_harvest_reward() == 460350000.0, "three Perfect confirmations offer the x1.65 460.35M harvest")
	_check(is_zero_approx(controller.next_transit_remaining), "the third confirmation schedules no fourth transit")
	controller.end_round()
	controller.begin_round()
	_check(int(first_host.confirmation_count) == 3 and is_zero_approx(controller.next_transit_remaining), "confirmation evidence survives the round boundary without automatic payout")
	first_host.arm_harvest()
	first_host.apply_manual_observation(1.0, 0.0, first_host.get_tracking_radius(view.screen_length_to_world(36.0)), 1.0)
	var harvest_metrics: Dictionary = controller.get_metrics()
	_check(controller.host_star == null and int(harvest_metrics.hosts_harvested) == 1 and int(harvest_metrics.harvests_at_confirmation_3) == 1, "an explicit idle hold harvests exactly at the chosen third tier")
	_check(float(harvest_metrics.harvest_reward_total) == 460350000.0, "the measured harvest reward matches the offered third-tier value")
	var scheduled_respawn: float = controller.respawn_remaining
	_check(scheduled_respawn >= 6.0 and scheduled_respawn <= 8.0, "harvest schedules a 6-8 second host respawn gap")
	_check(not bool(controller.reference_bonus_for(first_position).applied), "harvest creates a real interval with no reference anchor")
	controller.advance_time(scheduled_respawn)
	var respawn_metrics: Dictionary = controller.get_metrics()
	_check(controller.host_star != null and int(controller.host_star.stable_star_id) != first_id, "the host respawns with a new stable id")
	_check(is_equal_approx(float(respawn_metrics.last_respawn_gap), scheduled_respawn), "the measured respawn gap matches the scheduled harvest gap")

	var policy_results := {}
	for policy in [1, 2, 3]:
		policy_results[policy] = _measure_harvest_policy(policy, progression, view)
	var policy_rates: Array[float] = []
	for policy in [1, 2, 3]:
		var policy_result: Dictionary = policy_results[policy]
		policy_rates.append(float(policy_result.reward) / POLICY_HORIZON)
		_check(int(policy_result.harvests) > 0, "confirmation-%d policy produces harvests in the fixed horizon" % policy)
	var minimum_policy_rate: float = policy_rates.min()
	var maximum_policy_rate: float = policy_rates.max()
	_check(maximum_policy_rate / minimum_policy_rate <= 1.20, "no confirmation tier dominates fixed-horizon harvest throughput by more than 20%")
	_check(float(Dictionary(policy_results[1]).time_to_250m) < float(Dictionary(policy_results[3]).time_to_250m), "one-confirmation harvest reaches a small 250M need before the third tier")
	_check(float(Dictionary(policy_results[2]).time_to_350m) < float(Dictionary(policy_results[1]).time_to_350m) and float(Dictionary(policy_results[2]).time_to_350m) < float(Dictionary(policy_results[3]).time_to_350m), "two-confirmation harvest reaches a middle 350M need before the first and third tiers")
	_check(float(Dictionary(policy_results[3]).time_to_400m) < float(Dictionary(policy_results[1]).time_to_400m), "three-confirmation harvest reaches a 400M lump need before repeated first-tier harvests")
	print("GALACTIC_POLICY_RESULT horizon=%.0f confirmation_1=%s confirmation_2=%s confirmation_3=%s" % [
		POLICY_HORIZON, str(policy_results[1]), str(policy_results[2]), str(policy_results[3]),
	])

	_verify_extended_galactic_rules(view)

	progression.reset()
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(Dictionary(definition.get("effect_contract", {})).get("kind", "")) == "observation_value_multiplier":
			progression.purchased_nodes[String(definition.id)] = true
	_check(is_equal_approx(progression.get_observation_value_multiplier("common", 0), 8192.0), "the global meteor economy remains exactly x8192")
	_check(is_equal_approx(progression.get_transit_value_multiplier(), 1.0), "the x8192 meteor product does not leak into host harvest value")

	controller.queue_free()
	restored.queue_free()
	view.queue_free()
	progression.queue_free()
	await process_frame
	if failures.is_empty():
		print("GALACTIC_SLICE_PASS: 124 nodes; eight span steps; six reusable rule families; two hosts/windows; three confirmation tiers; catch, miss, harvest, respawn, reference, policy, and save/load contracts")
		quit(0)
	else:
		push_error("GALACTIC_SLICE_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _complete_current_transit(star, view: Camera2D) -> void:
	var tracking_radius: float = star.get_tracking_radius(view.screen_length_to_world(36.0))
	for _step in range(24):
		if String(star.state) != "transiting":
			break
		star.apply_manual_observation(0.2, 0.0, tracking_radius, 1.0)


func _verify_extended_galactic_rules(view: Camera2D) -> void:
	var progression = ProgressionController.new()
	root.add_child(progression)
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if String(definition.get("branch", "")) == "local_group":
			progression.purchased_nodes[String(definition.id)] = true
	_check(is_equal_approx(progression.get_observation_span(), Balance.GALACTIC_FINAL_OBSERVATION_SPAN), "all eight galaxy steps reach the exact 1.4774554 span ceiling")
	_check(progression.get_host_star_capacity() == 2 and progression.get_active_transit_capacity() == 2, "M32 and M110 independently raise the host and active-window capacities to two")
	_check(progression.get_galactic_feature_ids().size() == 19 and progression.get_galactic_host_profile_ids().size() == 18, "the 19 rule contracts expose one permanent chain and 18 host profiles")

	var represented_rules := {}
	for profile_variant in Balance.GALACTIC_FEATURES.values():
		var profile: Dictionary = profile_variant
		for rule_variant in Array(profile.get("rules", [])):
			represented_rules[String(rule_variant)] = true
	_check(represented_rules.keys().size() == 6, "all and only the six approved reusable rule families are represented")
	var late_combination_count := 0
	for node_id in [
		"sagittarius_dwarf_spheroidal", "fornax_dwarf", "sculptor_dwarf", "carina_dwarf", "draco_dwarf",
		"ursa_minor_dwarf", "sextans_dwarf", "leo_i", "leo_ii", "andromeda_ii",
	]:
		if Array(Dictionary(Balance.GALACTIC_FEATURES[node_id]).get("rules", [])).size() >= 2:
			late_combination_count += 1
	_check(late_combination_count >= 6, "at least six of the final ten contracts combine two learned rules")

	var rules_controller = HostStarController.new()
	root.add_child(rules_controller)
	rules_controller.setup(progression, view)
	rules_controller.refresh_unlock_state()
	_check(rules_controller.host_stars.size() == 2, "M32 keeps exactly two stationary hosts live")
	var live_bonus: Dictionary = rules_controller.reference_bonus_for(rules_controller.host_stars[0].global_position)
	var weak_position: Vector2 = rules_controller._weak_reference_positions()[0]
	var weak_bonus: Dictionary = rules_controller.reference_bonus_for(weak_position)
	_check(String(live_bonus.source) == "host" and is_equal_approx(float(live_bonus.multiplier), 1.25), "a live harvestable host remains a x1.25 reference anchor")
	_check(String(weak_bonus.source) == "weak_chain" and is_equal_approx(float(weak_bonus.multiplier), 1.10), "NGC 147 provides the weaker permanent x1.10 reference chain")
	_check(float(live_bonus.multiplier) > float(weak_bonus.multiplier), "the permanent NGC 147 chain is clearly weaker than a live host")

	var decoy_controller = HostStarController.new()
	root.add_child(decoy_controller)
	decoy_controller.setup(progression, view)
	var decoy_star = decoy_controller._create_host(901, Vector2(360.0, 280.0), "ngc_185")
	decoy_star.confirmation_count = 1
	decoy_controller._start_opportunity(decoy_star)
	_check(String(decoy_star.state) == "decoy" and String(decoy_star.decoy_kind) == "nucleus", "R2 starts a brightening decoy instead of a transit on its teaching opportunity")
	decoy_controller._finish_decoy_window(decoy_star, false)
	_check(String(decoy_star.state) == "idle" and int(decoy_star.confirmation_count) == 1 and int(decoy_controller.metrics.decoys_ignored) == 1, "releasing an R2 decoy preserves prior evidence and counts an ignored decoy")

	var comparison_controller = HostStarController.new()
	root.add_child(comparison_controller)
	comparison_controller.setup(progression, view)
	var comparison_host = comparison_controller._create_host(902, Vector2(520.0, 300.0), "sagittarius_dwarf_irregular")
	comparison_controller._start_opportunity(comparison_host)
	_check(String(comparison_host.state) == "transiting" and bool(comparison_host.comparison_locked), "R3 locks a transit until its comparison baseline is observed")
	var correct_comparison = null
	var comparison_count := 0
	for child in comparison_controller.get_children():
		if child is ComparisonStar:
			comparison_count += 1
			if bool(child.correct):
				correct_comparison = child
	_check(comparison_count == 2 and correct_comparison != null, "SagDIG presents two comparison choices with exactly one color match")
	if correct_comparison != null:
		correct_comparison.apply_manual_observation(1.0, 0.0, correct_comparison.get_tracking_radius(view.screen_length_to_world(36.0)), 1.0)
	_check(not bool(comparison_host.comparison_locked) and int(comparison_controller.metrics.comparisons_locked) == 1, "observing the matching comparison star unlocks the R3 transit")

	var hidden_controller = HostStarController.new()
	root.add_child(hidden_controller)
	hidden_controller.setup(progression, view)
	hidden_controller.running = true
	var hidden_host = hidden_controller._create_host(903, Vector2(640.0, 360.0), "leo_ii")
	_check(bool(hidden_host.is_hidden) and is_equal_approx(float(hidden_host.profile.rehide_seconds), 12.0), "Leo II starts hidden with the generous 12-second reacquisition window")
	var first_reveal := hidden_controller.record_sweep_segment(hidden_host.global_position - Vector2(100.0, 0.0), hidden_host.global_position + Vector2(100.0, 0.0))
	_check(first_reveal == 1 and not bool(hidden_host.is_hidden), "one blank-sky sweep reveals Leo II")
	hidden_controller.advance_time(12.1)
	_check(bool(hidden_host.is_hidden), "Leo II re-hides only after its full 12-second window")
	var second_reveal := hidden_controller.record_sweep_segment(hidden_host.global_position - Vector2(100.0, 0.0), hidden_host.global_position + Vector2(100.0, 0.0))
	_check(second_reveal == 1 and not bool(hidden_host.is_hidden), "a fresh sweep always reacquires Leo II after re-hide")

	var forecast_controller = HostStarController.new()
	root.add_child(forecast_controller)
	forecast_controller.setup(progression, view)
	var forecast_host = forecast_controller._create_host(904, Vector2(720.0, 260.0), "pegasus_dwarf_irregular")
	forecast_controller._schedule_transit(forecast_host, 6.0)
	_check(int(forecast_host.forecast_notches) == 2 and is_equal_approx(float(forecast_host.forecast_remaining), 6.0), "R5 exposes two forecast notches before the first confirmation")
	forecast_host.confirmation_count = 1
	forecast_controller._schedule_transit(forecast_host, 4.0)
	_check(int(forecast_host.forecast_notches) == 1, "the R5 forecast narrows to one notch after confirmation")

	var capacity_progression = ProgressionController.new()
	root.add_child(capacity_progression)
	for node_id in ["large_magellanic_cloud", "messier_32", "messier_110"]:
		capacity_progression.purchased_nodes[node_id] = true
	var capacity_controller = HostStarController.new()
	root.add_child(capacity_controller)
	capacity_controller.setup(capacity_progression, view)
	capacity_controller.begin_round()
	for star in capacity_controller.host_stars:
		capacity_controller.next_waits[capacity_controller._key(star)] = 0.0
	capacity_controller.advance_time(0.1)
	var simultaneous_transits := 0
	for star in capacity_controller.host_stars:
		if String(star.state) == "transiting":
			simultaneous_transits += 1
	_check(capacity_controller.host_stars.size() == 2 and simultaneous_transits == 2, "R6 permits two real host transit windows to overlap after M32 and M110")

	for disposable in [rules_controller, decoy_controller, comparison_controller, hidden_controller, forecast_controller, capacity_controller, capacity_progression, progression]:
		disposable.queue_free()


func _measure_harvest_policy(policy: int, progression, view: Camera2D) -> Dictionary:
	var policy_controller = HostStarController.new()
	root.add_child(policy_controller)
	policy_controller.setup(progression, view)
	policy_controller.begin_round()
	var elapsed := 0.0
	var time_to_250m := -1.0
	var time_to_350m := -1.0
	var time_to_400m := -1.0
	while elapsed < POLICY_HORIZON:
		var step := minf(POLICY_STEP, POLICY_HORIZON - elapsed)
		policy_controller.advance_time(step)
		var star = policy_controller.host_star
		if star != null and String(star.state) == "transiting":
			star.apply_manual_observation(step, 0.0, star.get_tracking_radius(view.screen_length_to_world(36.0)), 1.0)
		elif star != null and int(star.confirmation_count) >= policy:
			star.arm_harvest()
			star.apply_manual_observation(step, 0.0, star.get_tracking_radius(view.screen_length_to_world(36.0)), 1.0)
		elapsed += step
		var earned := float(policy_controller.metrics.harvest_reward_total)
		if time_to_250m < 0.0 and earned >= 250000000.0:
			time_to_250m = elapsed
		if time_to_350m < 0.0 and earned >= 350000000.0:
			time_to_350m = elapsed
		if time_to_400m < 0.0 and earned >= 400000000.0:
			time_to_400m = elapsed
	var measured: Dictionary = policy_controller.get_metrics()
	var result := {
		"reward": float(measured.harvest_reward_total),
		"harvests": int(measured.hosts_harvested),
		"transits": int(measured.transits_completed),
		"rate": float(measured.harvest_reward_total) / POLICY_HORIZON,
		"time_to_250m": time_to_250m,
		"time_to_350m": time_to_350m,
		"time_to_400m": time_to_400m,
	}
	policy_controller.free()
	return result
