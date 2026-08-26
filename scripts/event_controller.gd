extends Node

const UITheme = preload("res://scripts/ui_theme.gd")

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
var outburst_state: String = "idle"
var outburst_timer: float = 0.0
var outburst_spawn_timer: float = 0.0
var outburst_index: int = 0
var next_outburst_time: float = -1.0
var final_state: String = "idle"
var final_timer: float = 0.0
var final_started: bool = false
var rng := RandomNumberGenerator.new()

const SHOWER_BOUNDARY_MARGIN := 0.12
const PERSEID_OUTBURST_WARNING := 1.8
const PERSEID_OUTBURST_DURATION := 3.4
const PERSEID_OUTBURST_INTERVAL := 0.42
const PERSEID_OUTBURST_COUNT := 8


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
	if outburst_state != "idle":
		outburst_state = "idle"
		outburst_timer = 0.0
		outburst_spawn_timer = 0.0
		outburst_index = 0
		next_outburst_time = run_time
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
	outburst_state = "idle"
	outburst_timer = 0.0
	outburst_spawn_timer = 0.0
	outburst_index = 0
	next_outburst_time = -1.0
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

	if progression.has_upgrade("shower_detector") and next_shower_time < 0.0 and shower_state == "idle" and outburst_state == "idle":
		next_shower_time = run_time + 14.0
	if next_shower_time > 0.0 and run_time >= next_shower_time and shower_state == "idle" and outburst_state == "idle" and not final_started:
		trigger_shower()
	if progression.has_upgrade("perseid_outburst") and next_outburst_time < 0.0 and outburst_state == "idle":
		next_outburst_time = run_time + 8.0
	if next_outburst_time > 0.0 and run_time >= next_outburst_time and outburst_state == "idle" and shower_state == "idle" and not final_started:
		trigger_perseid_outburst()

	_update_shower(delta)
	_update_perseid_outburst(delta)
	_update_final(delta)


func trigger_shower() -> bool:
	if final_started or shower_state != "idle" or outburst_state != "idle":
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
	banner_requested.emit("EVENT_SHOWER_INCOMING", UITheme.ACCENT_TEXT)
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


func trigger_perseid_outburst() -> bool:
	if final_started or shower_state != "idle" or outburst_state != "idle":
		return false
	var required := PERSEID_OUTBURST_WARNING + PERSEID_OUTBURST_DURATION + SHOWER_BOUNDARY_MARGIN
	if spawner != null and float(spawner.phase_time_remaining) < required:
		if next_outburst_time < 0.0:
			next_outburst_time = run_time
		return false
	outburst_state = "warning"
	outburst_timer = PERSEID_OUTBURST_WARNING
	outburst_spawn_timer = 0.0
	outburst_index = 0
	next_outburst_time = -1.0
	spawner.pause_regular_spawns = true
	banner_requested.emit("EVENT_PERSEID_OUTBURST_INCOMING", UITheme.ACCENT_TEXT)
	sky_activity_changed.emit(0.48)
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
	outburst_state = "idle"
	next_outburst_time = -1.0
	spawner.pause_regular_spawns = true
	banner_requested.emit("EVENT_ATMOSPHERIC_BLOOM", UITheme.ACCENT_PIP)
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
				banner_requested.emit("EVENT_SHOWER", UITheme.BANNER_TITLE)
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
				banner_requested.emit("EVENT_SHOWER_PASSED", UITheme.BANNER_SUB)


func _update_perseid_outburst(delta: float) -> void:
	match outburst_state:
		"warning":
			outburst_timer -= delta
			if outburst_timer <= 0.0:
				outburst_state = "active"
				outburst_timer = PERSEID_OUTBURST_DURATION
				outburst_spawn_timer = 0.0
				banner_requested.emit("EVENT_PERSEID_OUTBURST", UITheme.BANNER_TITLE)
				sky_activity_changed.emit(0.82)
		"active":
			outburst_timer -= delta
			outburst_spawn_timer -= delta
			if outburst_index < PERSEID_OUTBURST_COUNT and outburst_spawn_timer <= 0.0:
				outburst_spawn_timer += PERSEID_OUTBURST_INTERVAL
				spawner.spawn_for_perseid_outburst(outburst_index)
				outburst_index += 1
			if outburst_timer <= 0.0:
				outburst_state = "idle"
				spawner.pause_regular_spawns = false
				next_outburst_time = run_time + rng.randf_range(48.0, 64.0)
				sky_activity_changed.emit(0.16)
				banner_requested.emit("EVENT_PERSEID_OUTBURST_PASSED", UITheme.BANNER_SUB)


func _update_final(delta: float) -> void:
	if final_state != "warning":
		return
	final_timer -= delta
	if final_timer <= 0.0:
		final_state = "active"
		banner_requested.emit("EVENT_MAJOR_FIREBALL", UITheme.INK_MAX)
		spawner.spawn_major_fireball()
