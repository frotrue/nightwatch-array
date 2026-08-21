extends Node

signal banner_requested(text, color)
signal sky_activity_changed(value)
signal forecast_requested(entry_points)
signal shower_started

const Balance = preload("res://scripts/game_balance.gd")

var spawner: Node
var progression: Node
var running: bool = false
var run_time: float = 0.0
var shower_state: String = "idle"
var shower_timer: float = 0.0
var shower_spawn_timer: float = 0.0
var shower_index: int = 0
var next_shower_time: float = -1.0
var final_state: String = "idle"
var final_timer: float = 0.0
var final_started: bool = false
var rng := RandomNumberGenerator.new()

const SHOWER_BOUNDARY_MARGIN := 0.12


func setup(meteor_spawner: Node, progression_controller: Node) -> void:
	spawner = meteor_spawner
	progression = progression_controller
	rng.randomize()


func start() -> void:
	running = true


func pause_for_intermission() -> void:
	running = false
	# A production shower is deferred before it starts. This fallback protects
	# the active round boundary if a debug or future path forces one late.
	if shower_state != "idle":
		shower_state = "idle"
		shower_timer = 0.0
		shower_spawn_timer = 0.0
		shower_index = 0
		next_shower_time = run_time
	if spawner != null:
		spawner.pause_regular_spawns = false


func reset() -> void:
	running = false
	run_time = 0.0
	shower_state = "idle"
	shower_timer = 0.0
	shower_spawn_timer = 0.0
	shower_index = 0
	next_shower_time = -1.0
	final_state = "idle"
	final_timer = 0.0
	final_started = false
	if spawner != null:
		spawner.pause_regular_spawns = false
	sky_activity_changed.emit(0.0)


func _process(delta: float) -> void:
	if not running:
		return
	run_time += delta
	if not final_started and run_time >= Balance.FINAL_EVENT_TIME:
		trigger_final()

	if progression.has_upgrade("shower_detector") and next_shower_time < 0.0 and shower_state == "idle":
		next_shower_time = run_time + 14.0
	if next_shower_time > 0.0 and run_time >= next_shower_time and shower_state == "idle" and not final_started:
		trigger_shower()

	_update_shower(delta)
	_update_final(delta)


func trigger_shower() -> bool:
	if final_started or shower_state != "idle":
		return false
	if not _shower_fits_current_observation():
		# Leave next_shower_time due. The first viable frame of the next round
		# starts the deferred shower without resetting its 40-58s cadence.
		if next_shower_time < 0.0:
			next_shower_time = run_time
		return false
	shower_state = "warning"
	shower_timer = Balance.SHOWER_WARNING_TIME
	shower_spawn_timer = 0.0
	shower_index = 0
	spawner.pause_regular_spawns = true
	next_shower_time = -1.0
	shower_started.emit()
	banner_requested.emit("EVENT_SHOWER_INCOMING", Color("b9a7ff"))
	if progression.has_upgrade("observatory_network"):
		var size := get_viewport().get_visible_rect().size
		forecast_requested.emit([
			Vector2(size.x * 0.18, 54.0),
			Vector2(size.x * 0.48, 54.0),
			Vector2(size.x - 54.0, size.y * 0.28),
			Vector2(54.0, size.y * 0.42)
		])
	sky_activity_changed.emit(0.55)
	return true


func _shower_fits_current_observation() -> bool:
	if spawner == null:
		return true
	var required := Balance.SHOWER_WARNING_TIME + Balance.SHOWER_DURATION + SHOWER_BOUNDARY_MARGIN
	return float(spawner.phase_time_remaining) >= required


func trigger_final() -> void:
	if final_started:
		return
	final_started = true
	final_state = "warning"
	final_timer = 4.2
	shower_state = "idle"
	next_shower_time = -1.0
	spawner.pause_regular_spawns = true
	banner_requested.emit("EVENT_ATMOSPHERIC_BLOOM", Color("ff9a66"))
	sky_activity_changed.emit(1.0)


func finish_final() -> void:
	running = false
	final_state = "resolved"
	spawner.pause_regular_spawns = true
	sky_activity_changed.emit(0.4)


func _update_shower(delta: float) -> void:
	match shower_state:
		"warning":
			shower_timer -= delta
			if shower_timer <= 0.0:
				shower_state = "active"
				shower_timer = Balance.SHOWER_DURATION
				shower_spawn_timer = 0.0
				banner_requested.emit("EVENT_SHOWER", Color("d8ccff"))
				sky_activity_changed.emit(1.0)
		"active":
			shower_timer -= delta
			shower_spawn_timer -= delta
			if shower_spawn_timer <= 0.0:
				shower_spawn_timer = 0.43
				spawner.spawn_for_shower(shower_index)
				shower_index += 1
			if shower_timer <= 0.0:
				shower_state = "idle"
				spawner.pause_regular_spawns = false
				next_shower_time = run_time + rng.randf_range(40.0, 58.0)
				sky_activity_changed.emit(0.16)
				banner_requested.emit("EVENT_SHOWER_PASSED", Color("7ee9dc"))


func _update_final(delta: float) -> void:
	if final_state != "warning":
		return
	final_timer -= delta
	if final_timer <= 0.0:
		final_state = "active"
		banner_requested.emit("EVENT_MAJOR_FIREBALL", Color("ffcb82"))
		spawner.spawn_major_fireball()
