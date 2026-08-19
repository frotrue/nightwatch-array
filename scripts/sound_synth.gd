extends Node

const SAMPLE_RATE := 44100
const VOICE_COUNT := 12

var success_stream: AudioStreamWAV
var upgrade_low_stream: AudioStreamWAV
var upgrade_high_stream: AudioStreamWAV
var warning_stream: AudioStreamWAV
var complete_low_stream: AudioStreamWAV
var complete_mid_stream: AudioStreamWAV
var complete_high_stream: AudioStreamWAV
var voice_pool: Array[AudioStreamPlayer] = []
var next_voice: int = 0


func _ready() -> void:
	# Generate the tiny placeholder sounds once during startup. Previously this
	# PCM work happened on every observation and caused visible frame spikes.
	success_stream = _make_tone(715.0, 0.13, 0.18, 1.5)
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


func play_success(multiplier: float = 1.0) -> void:
	var frequency := 620.0 + minf(multiplier, 3.0) * 95.0
	_play_stream(success_stream, frequency / 715.0)


func play_upgrade() -> void:
	_play_stream(upgrade_low_stream)
	_play_stream(upgrade_high_stream, 1.0, 0.07)


func play_warning() -> void:
	_play_stream(warning_stream)


func play_complete() -> void:
	_play_stream(complete_low_stream)
	_play_stream(complete_mid_stream, 1.0, 0.12)
	_play_stream(complete_high_stream, 1.0, 0.24)


func _play_stream(stream: AudioStreamWAV, pitch_scale: float = 1.0, delay: float = 0.0) -> void:
	if delay > 0.0:
		var timer := get_tree().create_timer(delay)
		timer.timeout.connect(func(): _play_stream(stream, pitch_scale))
		return
	var player := voice_pool[next_voice]
	next_voice = (next_voice + 1) % voice_pool.size()
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch_scale
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
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
