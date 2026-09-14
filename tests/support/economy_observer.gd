extends "res://scripts/observation_controller.gd"

# Diagnostic input adapter only. Game.simulate_tick still owns spawn, motion,
# completion ordering, rewards, events and round boundaries.
var configuration: Dictionary = {}
var coverage_rng := RandomNumberGenerator.new()
var seen: Dictionary = {}
var selected: Dictionary = {}

func prepare_tick() -> void:
	pass

func simulate_tick(_delta: float) -> void:
	var targets: Array = meteor_layer.get_children()
	for layer in additional_target_layers:
		if layer.has_method("available"):
			targets.append_array(layer.director.targets())
	targets.sort_custom(func(a, b): return a.simulation_id < b.simulation_id)
	for target in targets:
		if target.is_queued_for_deletion() or not target.alive:
			continue
		if not configuration.get("automatic_equipment", true):
			target.set_dish_assist_rate(0.0)
			if target.has_method("set_lane_assist_rate"):
				target.set_lane_assist_rate(0.0)
				target.base_automatic_rate = 0.0
		# Anomalies must finish their real warning before receiving work. Child
		# fragments only enter this snapshot on the tick after their creation.
		if not target.can_be_tracked() or target.has_meta("economy_coverage_rolled"):
			continue
		target.set_meta("economy_coverage_rolled", true)
		var kind: String = target.type_id
		seen[kind] = int(seen.get(kind, 0)) + 1
		var chance: float = configuration.get("observation_chance", 0.7)
		if kind == "fragment_piece":
			chance = configuration.get("fragment_chance", 1.0)
		chance = float(configuration.get("type_chances", {}).get(kind, chance))
		if coverage_rng.randf() >= chance:
			continue
		selected[kind] = int(selected.get(kind, 0)) + 1
		_complete_work(target)

func _complete_work(target: Node) -> void:
	if configuration.get("completion_source", "manual") == "automatic":
		# Set a positive automatic rate as well as work so the production reward
		# path uses its automatic coefficient. No observed signal is forged.
		target.set_dish_assist_rate(60.0)
		if target.type_id == "anomaly_rare":
			target._advance(1.0, false)
		else:
			target.automatic_contribution += maxf(0.0, 1.0 - target.observation_progress)
			target.observation_progress = 1.0
		return
	var quality: float = configuration.get("quality", 0.75)
	var speed := 1.0
	var remaining := 1.0
	if target.type_id == "anomaly_rare":
		speed = progression.get_analysis_speed_multiplier("common")
		remaining = maxf(0.0, 1.0 - target.stage_progress)
	else:
		speed = target.analysis_speed_multiplier * target.get_spectral_speed_multiplier()
		remaining = maxf(0.0, 1.0 - target.observation_progress)
	# Equivalent uninterrupted tracking work, not real elapsed time. This keeps
	# production grading/precision arithmetic bounded instead of injecting an
	# enormous delta, but cannot evaluate speed/radius/sweep upgrades fairly.
	var work_seconds: float = remaining * target.required_track_time / maxf(0.000001, lerpf(0.72, 1.42, quality) * speed)
	target.apply_manual_observation(work_seconds + 0.000001, 1.0 - quality, 1.0, 1.0)
