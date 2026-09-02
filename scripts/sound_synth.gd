extends Node

const SAMPLE_RATE := 44100
const VOICE_COUNT := 12
# Minor pentatonic ladder in semitones. A manual observation chain walks up
# these steps and holds at the top, so a sustained streak is audible before it
# shows up on any counter. Pentatonic keeps every rung consonant with the last.
const STREAK_LADDER := [0, 3, 5, 7, 10, 12, 15, 17, 19]
const SUCCESS_BASE_HZ := 520.0
# One pulse summarizes every automatic observation in a short window. Its
# 70 ms body ends before the next 160 ms window, leaving the manual ladder clear.
const AUTOMATIC_PULSE_INTERVAL_SECONDS := 0.16
const AUTOMATIC_PULSE_MIN_DB := -18.0
const AUTOMATIC_PULSE_MAX_DB := -12.0

var success_stream: AudioStreamWAV
var success_click_stream: AudioStreamWAV
var success_body_stream: AudioStreamWAV
var automatic_tick_stream: AudioStreamWAV
var upgrade_low_stream: AudioStreamWAV
var upgrade_high_stream: AudioStreamWAV
var warning_stream: AudioStreamWAV
var slot_confirm_stream: AudioStreamWAV
var rare_low_stream: AudioStreamWAV
var rare_high_stream: AudioStreamWAV
var environment_stream: AudioStreamWAV
var complete_low_stream: AudioStreamWAV
var complete_mid_stream: AudioStreamWAV
var complete_high_stream: AudioStreamWAV
var voice_pool: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var automatic_pending_count: int = 0
var automatic_pulse_elapsed: float = 0.0


func _ready() -> void:
	# UI confirmations must remain audible while the chart or settings pause the
	# world. Automatic batches are explicitly discarded at that pause boundary.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	# Generate PCM once, never on a live observation or a menu action.
	success_stream = _make_tone(SUCCESS_BASE_HZ, 0.15, 0.17, 1.5)
	success_click_stream = _make_click(0.022, 0.13)
	success_body_stream = _make_tone(146.0, 0.16, 0.20, 2.0)
	automatic_tick_stream = _make_tone(302.0, 0.07, 0.12, 3.0)
	upgrade_low_stream = _make_tone(440.0, 0.20, 0.15, 2.0)
	upgrade_high_stream = _make_tone(660.0, 0.24, 0.11, 2.0)
	warning_stream = _make_tone(185.0, 0.32, 0.12, 1.0)
	slot_confirm_stream = _make_slot_click()
	rare_low_stream = _make_shaped_tone(780.0, 0.075, 0.13, 2.7, 0.002, 3.4)
	rare_high_stream = _make_shaped_tone(1040.0, 0.11, 0.10, 2.7, 0.002, 3.4)
	environment_stream = _make_shaped_tone(220.0, 0.44, 0.09, 1.25, 0.14, 1.2)
	complete_low_stream = _make_tone(392.0, 0.35, 0.14, 2.0)
	complete_mid_stream = _make_tone(587.0, 0.42, 0.12, 2.0)
	complete_high_stream = _make_tone(784.0, 0.48, 0.10, 2.0)
	for index in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % index
		add_child(player)
		voice_pool.append(player)


func play_success(multiplier: float = 1.0, streak: int = 1, strength: float = 0.0) -> void:
	var power := clampf(strength, 0.0, 1.0)
	var step: int = STREAK_LADDER[clampi(streak - 1, 0, STREAK_LADDER.size() - 1)]
	var pitch := pow(2.0, float(step) / 12.0)
	# The precision multiplier brightens the note instead of adding another
	# octave. Stacking both drivers put a long chain well past 2 kHz.
	pitch *= 1.0 + minf(maxf(multiplier - 1.0, 0.0), 2.0) * 0.045
	var loudness := lerpf(-8.0, 1.0, power)
	_play_stream(success_click_stream, clampf(pitch, 0.65, 2.2), 0.0, loudness - 3.0)
	_play_stream(success_stream, pitch, 0.0, loudness)
	if power >= 0.45:
		# Only high-value observations get the low body. It is the difference
		# between a chime and a hit, and it would flatten if everything had it.
		var weight := clampf((power - 0.45) / 0.55, 0.0, 1.0)
		_play_stream(success_body_stream, 1.0, 0.0, lerpf(-10.0, -1.0, weight))


func play_automatic_tick() -> void:
	if get_tree().paused:
		return
	automatic_pending_count += 1
	set_process(true)


func _process(delta: float) -> void:
	if get_tree().paused:
		reset_streak_audio()
		return
	_advance_automatic_pulse(delta / maxf(Engine.time_scale, 0.001))


func _advance_automatic_pulse(real_delta: float) -> void:
	if automatic_pending_count <= 0:
		return
	automatic_pulse_elapsed += maxf(0.0, real_delta)
	if automatic_pulse_elapsed + 0.000001 < AUTOMATIC_PULSE_INTERVAL_SECONDS:
		return
	# Count affects weight, not voice count or pitch. A dense shower must never
	# replace the manual melody with a faster, louder automatic melody.
	var weight_db := 1.5 * log(float(automatic_pending_count)) / log(2.0)
	var volume_db := minf(AUTOMATIC_PULSE_MAX_DB, AUTOMATIC_PULSE_MIN_DB + weight_db)
	_play_stream(automatic_tick_stream, 1.0, 0.0, volume_db)
	automatic_pending_count = 0
	automatic_pulse_elapsed = 0.0
	set_process(false)


func reset_streak_audio() -> void:
	automatic_pending_count = 0
	automatic_pulse_elapsed = 0.0
	set_process(false)


func play_upgrade() -> void:
	_play_stream(upgrade_low_stream)
	_play_stream(upgrade_high_stream, 1.0, 0.07)


func play_warning() -> void:
	_play_stream(warning_stream)


func play_slot_confirm() -> void:
	_play_stream(slot_confirm_stream, 1.0, 0.0, -7.0)


func play_rare_target() -> void:
	_play_stream(rare_low_stream, 1.0, 0.0, -2.0)
	_play_stream(rare_high_stream, 1.0, 0.09, -2.0)


func play_environment_change() -> void:
	_play_stream(environment_stream, 1.0, 0.0, -4.0)


func play_complete() -> void:
	_play_stream(complete_low_stream)
	_play_stream(complete_mid_stream, 1.0, 0.12)
	_play_stream(complete_high_stream, 1.0, 0.24)


func _play_stream(stream: AudioStreamWAV, pitch_scale: float = 1.0, delay: float = 0.0, volume_db: float = 0.0) -> void:
	if delay > 0.0:
		var timer := get_tree().create_timer(delay, true, false, true)
		timer.timeout.connect(func(): _play_stream(stream, pitch_scale, 0.0, volume_db))
		return
	var player := voice_pool[next_voice]
	next_voice = (next_voice + 1) % voice_pool.size()
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()


func _make_tone(frequency: float, duration: float, volume: float, harmonic: float) -> AudioStreamWAV:
	var sample_count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / float(SAMPLE_RATE)
		var envelope := pow(1.0 - float(index) / float(sample_count), 2.2)
		envelope *= minf(1.0, float(index) / 90.0)
		var wave := sin(TAU * frequency * t)
		wave += sin(TAU * frequency * harmonic * t) * 0.18
		var sample := clampi(int(wave * envelope * volume * 32767.0), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	return _wrap_stream(bytes)


func _make_click(duration: float, volume: float) -> AudioStreamWAV:
	# The attack transient the success chime never had. A pure sine ramps in over
	# 2 ms and reads as a beep; this front-loads a broadband edge so the ear
	# registers a moment of contact before the pitched body arrives.
	var noise := RandomNumberGenerator.new()
	noise.seed = 5417
	var sample_count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / float(SAMPLE_RATE)
		var progress := float(index) / float(sample_count)
		var envelope := pow(1.0 - progress, 6.0)
		var wave := noise.randf_range(-1.0, 1.0) * 0.55
		wave += sin(TAU * 2100.0 * t) * 0.45
		var sample := clampi(int(wave * envelope * volume * 32767.0), -32768, 32767)
		bytes.encode_s16(index * 2, sample)
	return _wrap_stream(bytes)


func _make_slot_click() -> AudioStreamWAV:
	# An unpitched, low-passed latch: no interval or ringing tail that could be
	# mistaken for a research reward. The short fade-in avoids a digital pop.
	var noise := RandomNumberGenerator.new()
	noise.seed = 1847
	var sample_count := int(0.035 * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var filtered := 0.0
	for index in range(sample_count):
		filtered = lerpf(filtered, noise.randf_range(-1.0, 1.0), 0.24)
		var progress := float(index) / float(sample_count)
		var envelope := minf(1.0, float(index) / 24.0) * pow(1.0 - progress, 4.0)
		bytes.encode_s16(index * 2, int(filtered * envelope * 0.18 * 32767.0))
	return _wrap_stream(bytes)


func _make_shaped_tone(frequency: float, duration: float, volume: float, harmonic: float, attack: float, decay_power: float) -> AudioStreamWAV:
	var sample_count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / float(SAMPLE_RATE)
		var envelope: float
		if t < attack:
			var rise := clampf(t / attack, 0.0, 1.0)
			envelope = rise * rise * (3.0 - 2.0 * rise)
		else:
			envelope = pow(maxf(0.0, 1.0 - (t - attack) / (duration - attack)), decay_power)
		var wave := sin(TAU * frequency * t) + sin(TAU * frequency * harmonic * t) * 0.28
		bytes.encode_s16(index * 2, clampi(int(wave * envelope * volume * 32767.0), -32768, 32767))
	return _wrap_stream(bytes)


func _wrap_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
