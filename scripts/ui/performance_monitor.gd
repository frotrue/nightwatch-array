extends PanelContainer

const Sampler = preload("res://scripts/performance_sampler.gd")
const SAMPLE_SECONDS := 0.5
var sampler := Sampler.new()
var game: Node
var settings: Node
var _last_frame_usec := 0
var _window_usec := 0
var _frames := 0
var _worst_ms := 0.0
var _previous_tick := 0
var _previous_epoch := 0
var fps := 0.0
var frame_ms := 0.0
var worst_ms := 0.0
var ticks_per_second := 0.0

func _ready() -> void:
	set_process(false)

func bind_game(controller: Node) -> void:
	game = controller
	settings = game.settings
	settings.performance_monitor_changed.connect(set_enabled)
	settings.language_changed.connect(func(_locale: String): _refresh_labels())
	set_enabled(settings.performance_monitor_enabled)

func set_enabled(enabled: bool) -> void:
	visible = enabled and not game.hud.is_settings_open()
	set_process(enabled)
	if enabled:
		_last_frame_usec = Time.get_ticks_usec()
		_window_usec = 0
		_frames = 0
		_worst_ms = 0.0
		fps = 0.0
		frame_ms = 0.0
		worst_ms = 0.0
		ticks_per_second = 0.0
		_previous_tick = game.simulation_clock.tick
		_previous_epoch = game.simulation_clock.epoch
		%FrameGraph.clear_history()
		sampler.start()
		_refresh_labels()
	else:
		sampler.stop()

func _exit_tree() -> void:
	sampler.stop()

func _process(_delta: float) -> void:
	visible = not game.hud.is_settings_open()
	var now := Time.get_ticks_usec()
	var elapsed := now - _last_frame_usec
	_last_frame_usec = now
	_window_usec += elapsed
	_frames += 1
	_worst_ms = maxf(_worst_ms, elapsed / 1000.0)
	if _window_usec < SAMPLE_SECONDS * 1000000.0: return
	var seconds := _window_usec / 1000000.0
	fps = _frames / seconds
	frame_ms = _window_usec / 1000.0 / _frames
	worst_ms = _worst_ms
	var tick: int = game.simulation_clock.tick
	var epoch: int = game.simulation_clock.epoch
	ticks_per_second = maxf(0.0, tick - _previous_tick) / seconds if epoch == _previous_epoch else 0.0
	_previous_tick = tick
	_previous_epoch = epoch
	sampler.poll()
	%FrameGraph.add_sample(worst_ms)
	for value in %FrameGraph.history: worst_ms = maxf(worst_ms, value)
	_refresh_labels()
	_frames = 0
	_window_usec = 0
	_worst_ms = 0.0

func _refresh_labels() -> void:
	if not is_node_ready() or game == null: return
	%Title.text = tr("PERF_TITLE")
	%Frame.text = "%.0f FPS   ·   %.1f ms" % [fps, frame_ms] if fps > 0 else tr("PERF_SAMPLING")
	%Peak.text = tr("PERF_PEAK") % worst_ms
	%Usage.text = "CPU %s   GPU 3D %s" % [_percent(sampler.cpu), _percent(sampler.gpu)]
	var paused: bool = get_tree().paused or not game.observation_phase_active
	%Tick.text = tr("PERF_PAUSED") if paused else tr("PERF_TICK") % [ticks_per_second, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	%Objects.text = tr("PERF_OBJECTS") % [game.meteor_layer.get_child_count(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	%Scope.text = tr("PERF_SCOPE")

func _percent(value: float) -> String:
	return "%.1f%%" % value if value >= 0.0 else tr("PERF_UNAVAILABLE")
