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
var canis_major_state: String = "idle"
var canis_major_timer: float = 0.0
var rng := RandomNumberGenerator.new()

const SHOWER_BOUNDARY_MARGIN := 0.12
const PERSEID_OUTBURST_WARNING := 1.8
const PERSEID_OUTBURST_DURATION := 3.4
const PERSEID_OUTBURST_INTERVAL := 0.42
const PERSEID_OUTBURST_COUNT := 8
const CANIS_MAJOR_WARNING_TIME := 2.6
const CANIS_MAJOR_BOUNDARY_MARGIN := 0.12
const CANIS_MAJOR_MINIMUM_DELAY := 0.6


func setup(meteor_spawner: Node, progression_controller: Node) -> void:
	spawner = meteor_spawner
	progression = progression_controller
	rng.randomize()


func start() -> void:
	running = true
	_schedule_canis_major_for_round()


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
	canis_major_state = "idle"
	canis_major_timer = 0.0
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
	canis_major_state = "idle"
	canis_major_timer = 0.0
	if spawner != null:
		spawner.pause_regular_spawns = false
	sky_activity_changed.emit(0.0)


func _process(delta: float) -> void:
	if not running:
		return
	run_time += delta

	if progression.has_upgrade("shower_detector") and next_shower_time < 0.0 and shower_state == "idle" and outburst_state == "idle":
		next_shower_time = run_time + 14.0
	if next_shower_time > 0.0 and run_time >= next_shower_time and shower_state == "idle" and outburst_state == "idle":
		trigger_shower()
	if progression.has_upgrade("perseid_outburst") and next_outburst_time < 0.0 and outburst_state == "idle":
		next_outburst_time = run_time + 8.0
	if next_outburst_time > 0.0 and run_time >= next_outburst_time and outburst_state == "idle" and shower_state == "idle":
		trigger_perseid_outburst()

	_update_shower(delta)
	_update_perseid_outburst(delta)
	_update_canis_major(delta)


func trigger_shower() -> bool:
	if shower_state != "idle" or outburst_state != "idle" or canis_major_state == "warning":
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
	if shower_state != "idle" or outburst_state != "idle" or canis_major_state == "warning":
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


func trigger_canis_major_warning() -> bool:
	if progression == null or not progression.has_upgrade("sirius_fireball"):
		return false
	if canis_major_state in ["warning", "resolved", "deferred"]:
		return false
	if shower_state != "idle" or outburst_state != "idle":
		return false
	if not _canis_major_fits_current_observation():
		canis_major_state = "deferred"
		return false
	canis_major_state = "warning"
	canis_major_timer = CANIS_MAJOR_WARNING_TIME
	banner_requested.emit("EVENT_ATMOSPHERIC_BLOOM", UITheme.ACCENT_PIP)
	return true


func _schedule_canis_major_for_round() -> void:
	canis_major_state = "idle"
	canis_major_timer = 0.0
	if progression == null or not progression.has_upgrade("sirius_fireball"):
		return
	if not _canis_major_fits_current_observation():
		canis_major_state = "deferred"
		return
	var available_delay := maxf(
		0.0,
		float(spawner.phase_time_remaining) - _canis_major_required_time()
	)
	var minimum_delay := minf(CANIS_MAJOR_MINIMUM_DELAY, available_delay)
	canis_major_timer = rng.randf_range(minimum_delay, available_delay)
	canis_major_state = "scheduled"


func _canis_major_required_time() -> float:
	return CANIS_MAJOR_WARNING_TIME + float(Balance.meteor_spec("major").lifetime) + CANIS_MAJOR_BOUNDARY_MARGIN


func _canis_major_fits_current_observation() -> bool:
	return spawner == null or float(spawner.phase_time_remaining) >= _canis_major_required_time()


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


func _update_canis_major(delta: float) -> void:
	match canis_major_state:
		"scheduled":
			canis_major_timer -= delta
			if canis_major_timer <= 0.0:
				trigger_canis_major_warning()
		"warning":
			canis_major_timer -= delta
			if canis_major_timer > 0.0:
				return
			var meteor = spawner.try_spawn_canis_major_fireball()
			if meteor == null:
				if float(spawner.phase_time_remaining) < float(Balance.meteor_spec("major").lifetime) + CANIS_MAJOR_BOUNDARY_MARGIN:
					canis_major_state = "deferred"
				return
			canis_major_state = "resolved"
			banner_requested.emit("EVENT_MAJOR_FIREBALL", UITheme.INK_MAX)
