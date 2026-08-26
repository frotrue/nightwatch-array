extends SceneTree

# Human-driven 60-second slice for the first blank-sky survey tier. This is a
# feel test, not a correctness gate: move between meteor tracking and blank-sky
# strokes, then judge whether their opportunity cost reads without extra HUD.

const SLICE_SECONDS := 60.0

var completed_samples: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	root.add_child(game)
	await process_frame
	await process_frame
	game.active_save_slot = 0
	game.progression.success_count = 40
	game.progression.debug_purchase_node("polar_survey")
	game.survey.begin_round(1)
	game.survey.sample_completed.connect(_on_sample_completed)
	game.observation_phase_duration = SLICE_SECONDS
	game.observation_phase_remaining = SLICE_SECONDS
	game.spawner.set_phase_time_remaining(SLICE_SECONDS)
	game.hud.set_observation_phase(1, SLICE_SECONDS, SLICE_SECONDS)
	var starting_data: float = game.progression.total_data_earned
	var starting_successes: int = game.progression.success_count
	print("SURVEY_SLICE_READY: track meteors or drag blank sky; release before changing intent")
	await create_timer(SLICE_SECONDS).timeout
	print("SURVEY_SLICE_RESULT seconds=%.0f samples=%d meteor_observations=%d total_data=%.0f" % [
		SLICE_SECONDS,
		completed_samples,
		game.progression.success_count - starting_successes,
		game.progression.total_data_earned - starting_data,
	])
	quit()


func _on_sample_completed(_slot: int, _position: Vector2, _reward: float, _catalogued: bool) -> void:
	completed_samples += 1
