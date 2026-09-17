extends CanvasLayer

signal record_reached
const Expansion = preload("res://scripts/expansion_data.gd")
enum Phase { QUIET, ARRIVAL, OBSERVE, LIMIT, COLLAPSE, BLACKOUT, RECORD }
const DURATIONS := [12.0, 18.0, 50.0, 10.0, 28.0, 10.0, 12.0]
const STATUS_KEYS := ["ENDING_QUIET", "ENDING_ARRIVAL", "ENDING_OBSERVE", "ENDING_LIMIT", "ENDING_COLLAPSE", "", ""]
const HINT_KEYS := ["ENDING_QUIET_HINT", "ENDING_ARRIVAL_HINT", "ENDING_OBSERVE_HINT", "ENDING_LIMIT_HINT", "ENDING_COLLAPSE_HINT", "", ""]

@onready var launch: Button = $Root/Launch
@onready var film: Control = $Root/Film
@onready var sky: ColorRect = $Root/Film/Sky
@onready var lines: Control = $Root/Film/Lines
@onready var status: Label = $Root/Film/Status
@onready var hint: Label = $Root/Film/Hint
@onready var readout: Label = $Root/Film/Readout
@onready var track: ColorRect = $Root/Film/ProgressTrack
@onready var fill: ColorRect = $Root/Film/ProgressTrack/Fill
@onready var record: VBoxContainer = $Root/Film/Record
@onready var actions: HBoxContainer = $Root/Film/Record/Actions
@onready var drone: AudioStreamPlayer = $Drone
@onready var rupture: AudioStreamPlayer = $Rupture
var game: Node
var active := false
var preview := false
var eligible := false
var phase := Phase.QUIET
var phase_elapsed := 0.0
var elapsed := 0.0
var observation_progress := 0.0
var tracking := false
var motion_scale := 1.0
var flashes := true
var _previous_pause := false
var _previous_hud_layer := 80
var _previous_hud_visible := true
var _announced_record := false

func _ready() -> void:
	launch.pressed.connect(start)
	$Root/Film/Menu.pressed.connect(open_settings)
	$Root/Film/Record/Actions/Return.pressed.connect(return_to_chart)
	$Root/Film/Record/Actions/Replay.pressed.connect(replay)
	drone.stream = drone.stream.duplicate()
	drone.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	drone.stream.loop_end = 22050 * 12

func setup(owner_game: Node) -> void:
	game = owner_game
	game.progression.state_changed.connect(refresh_availability)
	game.deep_sky.changed.connect(refresh_availability)
	refresh_availability()

func refresh_availability() -> void:
	if game == null: return
	eligible = game.progression.is_research_complete()
	if eligible:
		for id in Expansion.RESEARCH_ORDER:
			if not game.deep_sky.research_owned(id): eligible = false; break
	_update_launch()

func _update_launch() -> void:
	if game == null: return
	launch.visible = eligible and not active and game.observation_phase_active and not game.get_tree().paused and not game.upgrade_tree.is_open()
	launch.text = tr("ENDING_REPLAY") if game.horizon_ending_seen else tr("ENDING_LAUNCH")

func start(debug_preview: bool = false) -> bool:
	if active or game == null: return false
	refresh_availability()
	if not debug_preview and not eligible: return false
	if game.hud.is_settings_open() or game.hud.is_startup_slots_open() or game.tutorial.is_modal_step() or game.module_tutorial.active or game.module_popup.is_open() or game.hud.is_phase_summary_open(): return false
	game._close_upgrade_tree_without_transition()
	preview = debug_preview
	_previous_pause = get_tree().paused
	_previous_hud_layer = game.hud.layer
	_previous_hud_visible = game.hud.visible
	active = true
	game.hud.final_observation_active = true
	game.hud.hide()
	phase = Phase.QUIET
	phase_elapsed = 0.0
	elapsed = 0.0
	observation_progress = 0.0
	_announced_record = false
	tracking = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.sound.reset_streak_audio()
	film.show()
	launch.hide()
	lines.configure(self, game.upgrade_tree)
	drone.play()
	_present()
	return true

func cancel() -> void:
	if not active: return
	active = false
	game.hud.final_observation_active = false
	film.hide()
	drone.stop()
	rupture.stop()
	game.hud.layer = _previous_hud_layer
	game.hud.visible = _previous_hud_visible
	get_tree().paused = _previous_pause
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _previous_pause else Input.MOUSE_MODE_HIDDEN
	_update_launch()

func return_to_chart() -> void:
	if not active or phase != Phase.RECORD or phase_elapsed < DURATIONS[Phase.RECORD]: return
	cancel()
	game.upgrade_tree.open_tree()

func replay() -> void:
	if not active or phase != Phase.RECORD or phase_elapsed < DURATIONS[Phase.RECORD]: return
	var was_preview := preview
	cancel()
	start(was_preview)

func open_settings() -> void:
	if not active: return
	game.hud.layer = layer + 10
	game.hud.show()
	game.hud.open_settings()

func _input(event: InputEvent) -> void:
	if not active or game.hud.is_settings_open(): return
	if event.is_action_pressed("nw_menu_back", false, true):
		open_settings()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active:
		_update_launch()
		return
	game.hud.layer = layer + 10 if game.hud.is_settings_open() else _previous_hud_layer
	game.hud.visible = game.hud.is_settings_open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	advance(minf(delta, 0.1), Input.is_action_pressed("nw_observe"), film.get_local_mouse_position())

func advance(delta: float, observing: bool, pointer: Vector2) -> void:
	if not active or game.hud.is_settings_open():
		drone.stream_paused = active
		rupture.stream_paused = active
		return
	drone.stream_paused = false
	rupture.stream_paused = false
	motion_scale = game.settings.get_motion_intensity()
	flashes = game.settings.are_screen_flashes_enabled()
	var step := maxf(delta, 0.0)
	elapsed += step
	phase_elapsed += step
	tracking = false
	if phase == Phase.OBSERVE:
		tracking = observing and pointer.distance_to(film.size * Vector2(0.5, 0.465)) <= film.size.y * 0.205
		if tracking: observation_progress = minf(1.0, observation_progress + step / DURATIONS[Phase.OBSERVE])
		else: observation_progress = maxf(observation_progress, minf(0.85, observation_progress + step * 0.35 / DURATIONS[Phase.OBSERVE]))
		if observation_progress >= 0.999999 and phase_elapsed >= DURATIONS[Phase.OBSERVE]: _next_phase()
	elif phase < Phase.RECORD and phase_elapsed >= DURATIONS[phase]:
		_next_phase()
	if phase == Phase.RECORD and phase_elapsed >= DURATIONS[Phase.RECORD] and not _announced_record:
		_announced_record = true
		if not preview: record_reached.emit()
		$Root/Film/Record/Actions/Return.grab_focus()
	_present()

func _next_phase() -> void:
	phase += 1
	phase_elapsed = 0.0
	if phase == Phase.COLLAPSE: rupture.play()
	if phase == Phase.RECORD: drone.stop(); rupture.stop()

func visual_state() -> Dictionary:
	var part := clampf(phase_elapsed / DURATIONS[phase], 0.0, 1.0)
	var presence := 0.0
	var charge := 0.0
	var fall := 0.0
	var dark := 0.0
	if phase == Phase.QUIET: presence = smoothstep(0.4, 1.0, part) * 0.08
	elif phase == Phase.ARRIVAL: presence = lerpf(0.08, 1.0, smoothstep(0.0, 1.0, part))
	else: presence = 1.0
	if phase == Phase.OBSERVE: charge = observation_progress * 0.60
	elif phase == Phase.LIMIT: charge = lerpf(0.60, 1.0, smoothstep(0.0, 1.0, part))
	elif phase > Phase.LIMIT: charge = 1.0
	if phase == Phase.COLLAPSE: fall = smoothstep(0.0, 1.0, part)
	elif phase > Phase.COLLAPSE: fall = 1.0
	if phase == Phase.BLACKOUT: dark = smoothstep(0.0, 0.72, part)
	elif phase == Phase.RECORD: dark = 1.0
	return {"presence": presence, "charge": charge, "collapse": fall, "blackout": dark}

func _present() -> void:
	if not active: return
	var state := visual_state()
	for key in state: sky.material.set_shader_parameter(key, state[key])
	sky.material.set_shader_parameter("aspect", film.size.x / maxf(film.size.y, 1.0))
	sky.material.set_shader_parameter("clock", elapsed)
	sky.material.set_shader_parameter("motion", motion_scale)
	sky.material.set_shader_parameter("flare", 1.0 if flashes else 0.0)
	film.modulate.a = smoothstep(0.0, 2.0, elapsed)
	status.text = tr(STATUS_KEYS[phase]) if not STATUS_KEYS[phase].is_empty() else ""
	hint.text = tr(HINT_KEYS[phase]) if not HINT_KEYS[phase].is_empty() else ""
	track.visible = phase == Phase.OBSERVE
	fill.size.x = track.size.x * observation_progress
	readout.text = (tr("ENDING_TRACKING") if tracking else tr("ENDING_AUTO")) + "  /  %02d%%" % mini(99, int(observation_progress * 100.0)) if phase == Phase.OBSERVE else ""
	var text_alpha := 1.0 - smoothstep(0.35, 0.80, float(state.collapse))
	status.modulate.a = text_alpha
	hint.modulate.a = text_alpha
	$Root/Film/Header.modulate.a = 1.0 - float(state.collapse)
	record.visible = phase == Phase.RECORD
	$Root/Film/Record/Text.text = tr("ENDING_RECORD_TEXT").replace("\\n", "\n")
	record.modulate.a = smoothstep(1.0, 5.0, phase_elapsed) if phase == Phase.RECORD else 0.0
	actions.visible = phase == Phase.RECORD and phase_elapsed >= DURATIONS[Phase.RECORD]
	lines.queue_redraw()
	drone.volume_db = lerpf(-28.0, -15.0, float(state.charge)) - float(state.blackout) * 35.0
	rupture.volume_db = -15.0 - float(state.blackout) * 30.0
