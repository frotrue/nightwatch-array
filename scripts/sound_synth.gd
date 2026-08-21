extends Node

const SAMPLE_RATE := 44100
const VOICE_COUNT := 12
# Minor pentatonic ladder in semitones. A manual observation chain walks up
# these steps and holds at the top, so a sustained streak is audible before it
# shows up on any counter. Pentatonic keeps every rung consonant with the last.
const STREAK_LADDER := [0, 3, 5, 7, 10, 12, 15, 17, 19]
const SUCCESS_BASE_HZ := 520.0
# Automatic observations share the sky with manual ones. Without a floor on the
# gap they stack into a buzz during a shower and bury the manual ladder.
const AUTOMATIC_TICK_MIN_GAP_MSEC := 55

var success_stream: AudioStreamWAV
var success_click_stream: AudioStreamWAV
var success_body_stream: AudioStreamWAV
var automatic_tick_stream: AudioStreamWAV
var upgrade_low_stream: AudioStreamWAV
var upgrade_high_stream: AudioStreamWAV
var warning_stream: AudioStreamWAV
var complete_low_stream: AudioStreamWAV
var complete_mid_stream: AudioStreamWAV
var complete_high_stream: AudioStreamWAV
var voice_pool: Array[AudioStreamPlayer] = []
var next_voice: int = 0
var last_automatic_tick_msec: int = -10000


func _ready() -> void:
	# Generate the tiny placeholder sounds once during startup. Previously this
	# PCM work happened on every observation and caused visible frame spikes.
	success_stream = _make_tone(SUCCESS_BASE_HZ, 0.15, 0.17, 1.5)
	success_click_stream = _make_click(0.022, 0.13)
	success_body_stream = _make_tone(146.0, 0.16, 0.20, 2.0)
	automatic_tick_stream = _make_tone(302.0, 0.07, 0.12, 3.0)
	upgrade_low_stream = _make_tone(440.0, 0.20, 0.15, 2.0)
	upgrade_high_stream = _make_tone(660.0, 0.24, 0.11, 2.0)
	warning_stream = _make_tone(185.0, 0.32, 0.12, 1.0)
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
	var now := Time.get_ticks_msec()
	if now - last_automatic_tick_msec < AUTOMATIC_TICK_MIN_GAP_MSEC:
		return
	last_automatic_tick_msec = now
	_play_stream(automatic_tick_stream, 1.0, 0.0, -13.0)


func reset_streak_audio() -> void:
	last_automatic_tick_msec = -10000


func play_upgrade() -> void:
	_play_stream(upgrade_low_stream)
	_play_stream(upgrade_high_stream, 1.0, 0.07)


func play_warning() -> void:
	_play_stream(warning_stream)


func play_complete() -> void:
	_play_stream(complete_low_stream)
	_play_stream(complete_mid_stream, 1.0, 0.12)
	_play_stream(complete_high_stream, 1.0, 0.24)


func _play_stream(stream: AudioStreamWAV, pitch_scale: float = 1.0, delay: float = 0.0, volume_db: float = 0.0) -> void:
	if delay > 0.0:
		var timer := get_tree().create_timer(delay)
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


func _wrap_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
