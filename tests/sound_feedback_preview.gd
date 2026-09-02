extends SceneTree

# Save-free live audition, not a perceptual pass/fail test. Run without
# --headless so Godot uses its normal output driver. Only this process's
# Master mix is captured; no microphone, settings, or save slots are accessed.
# On surround outputs Godot's recorder can expose only the last (silent) pair.
# An explicitly opted-in Dummy-driver run records the same mixer in stereo,
# but is not evidence of hardware playback. Do not change OS speaker settings.
const SoundSynthScript = preload("res://scripts/sound_synth.gd")
const WAV_PATH := "res://build/audio_feedback_audition.wav"
const MANIFEST_PATH := "res://build/audio_feedback_audition.json"
const SPARSE_AUTOMATIC_AT := 5.5
const STRESS_START := 7.0
const STRESS_SECONDS := 10.0
const AUTOMATIC_EVENTS := 1000
const END_SECONDS := 17.7
const MANUAL_OFFSETS := [1.0, 3.5, 6.0, 8.5]

var synth: Node
var recorder: AudioEffectRecord
var recorder_index := -1
var started_usec := 0
var events: Array[Dictionary] = []
var automatic_times: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if AudioServer.get_driver_name() == "Dummy" and OS.get_environment("NIGHTWATCH_AUDITION_ALLOW_DUMMY") != "1":
		push_error("SOUND_AUDITION_FAIL: a live audio driver is required; omit --headless")
		quit(1)
		return
	root.title = "Nightwatch Array - sound feedback audition"
	root.mode = Window.MODE_WINDOWED if OS.get_environment("NIGHTWATCH_AUDITION_VISIBLE") == "1" else Window.MODE_MINIMIZED
	synth = SoundSynthScript.new()
	root.add_child(synth)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	if error != OK:
		push_error("SOUND_AUDITION_FAIL: could not create build directory (%s)" % error_string(error))
		quit(1)
		return
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	await create_timer(0.25).timeout
	recorder.set_recording_active(true)
	started_usec = Time.get_ticks_usec()
	print("SOUND_AUDITION_ENV: Godot=%s driver=%s mix_rate=%s bus_channels=%d automatic_events=%d stress_seconds=%.1f" % [Engine.get_version_info().string, AudioServer.get_driver_name(), AudioServer.get_mix_rate(), AudioServer.get_bus_channels(0), AUTOMATIC_EVENTS, STRESS_SECONDS])
	var cue_index := 0
	var automatic_index := 0
	var manual_index := 0
	var stress_announced := false
	var sparse_automatic_played := false
	var max_bus_peak_db := -200.0
	var cue_methods := ["play_upgrade", "play_slot_confirm", "play_rare_target", "play_environment_change"]
	var cue_labels := ["research", "slot_confirmation", "rare_target", "environment_change"]
	while _elapsed() < END_SECONDS:
		var elapsed := _elapsed()
		max_bus_peak_db = maxf(max_bus_peak_db, AudioServer.get_bus_peak_volume_left_db(0, 0))
		if cue_index < cue_methods.size() and elapsed >= 0.5 + 1.2 * cue_index:
			_note(cue_labels[cue_index], elapsed)
			synth.call(cue_methods[cue_index])
			print("SOUND_AUDITION_VOICE: playing=%s bytes=%d" % [synth.voice_pool[(synth.next_voice + synth.voice_pool.size() - 1) % synth.voice_pool.size()].playing, synth.voice_pool[(synth.next_voice + synth.voice_pool.size() - 1) % synth.voice_pool.size()].stream.data.size()])
			cue_index += 1
		if not sparse_automatic_played and elapsed >= SPARSE_AUTOMATIC_AT:
			sparse_automatic_played = true
			_note("single_automatic_event_160ms_batch_latency", elapsed)
			synth.play_automatic_tick()
		if elapsed >= STRESS_START:
			if not stress_announced:
				stress_announced = true
				_note("automatic_stress_start_100_per_second", elapsed)
			# A render frame can contain multiple 10 ms arrivals. Preserve the
			# cumulative event count without changing SoundSynth's real _process.
			while automatic_index < AUTOMATIC_EVENTS and elapsed >= STRESS_START + float(automatic_index) / 100.0:
				synth.play_automatic_tick()
				automatic_times.append(elapsed)
				automatic_index += 1
			if manual_index < MANUAL_OFFSETS.size() and elapsed >= STRESS_START + MANUAL_OFFSETS[manual_index]:
				_note("manual_success_%d" % (manual_index + 1), elapsed)
				synth.play_success(2.0, 1 + manual_index * 2, 0.65)
				manual_index += 1
		await process_frame
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	AudioServer.remove_bus_effect(0, recorder_index)
	recorder_index = -1
	if recording == null or recording.format != AudioStreamWAV.FORMAT_16_BITS or recording.data.is_empty():
		push_error("SOUND_AUDITION_FAIL: recorder returned no 16-bit PCM")
		quit(1)
		return
	var pcm := _measure_pcm(recording.data)
	if int(pcm.nonzero_samples) == 0 or automatic_index != AUTOMATIC_EVENTS:
		push_error("SOUND_AUDITION_FAIL: recording is silent or automatic schedule is incomplete (PCM=%s events=%d bus_mute=%s bus_gain=%s max_bus_peak_db=%s)" % [pcm, automatic_index, AudioServer.is_bus_mute(0), AudioServer.get_bus_volume_db(0), max_bus_peak_db])
		quit(1)
		return
	error = recording.save_to_wav(ProjectSettings.globalize_path(WAV_PATH))
	if error != OK:
		push_error("SOUND_AUDITION_FAIL: WAV write failed (%s)" % error_string(error))
		quit(1)
		return
	var manifest := {
		"engine": Engine.get_version_info().string,
		"driver": AudioServer.get_driver_name(),
		"hardware_output": AudioServer.get_driver_name() != "Dummy",
		"bus_stereo_pairs": AudioServer.get_bus_channels(0),
		"sound_synth_sha256": FileAccess.get_sha256("res://scripts/sound_synth.gd"),
		"wav": ProjectSettings.globalize_path(WAV_PATH),
		"capture": "Godot Master-bus AudioEffectRecord; no microphone or OS loopback. Dummy-driver recordings are software mixer output, not hardware playback.",
		"timing_note": "Wall-clock dispatch seconds relative to recording start, not sample-accurate WAV offsets. Mixer latency and Dummy-driver wall/sample-clock drift are not corrected.",
		"perceptual_status": "Not evaluated by this script; listen to judge semantic separation and fatigue",
		"mix_rate": recording.mix_rate,
		"stereo": recording.stereo,
		"recorded_seconds": recording.get_length(),
		"pcm": pcm,
		"max_bus_peak_db": max_bus_peak_db,
		"events": events,
		"sparse_automatic_events": 1,
		"automatic_stress": {"start_seconds": STRESS_START, "duration_seconds": STRESS_SECONDS, "rate_per_second": 100, "count": automatic_index, "dispatch_seconds": automatic_times},
	}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SOUND_AUDITION_FAIL: manifest write failed")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("SOUND_AUDITION_SAVED: %s duration=%.3fs nonzero_samples=%d peak=%.6f automatic_events=%d" % [ProjectSettings.globalize_path(WAV_PATH), recording.get_length(), pcm.nonzero_samples, pcm.peak, automatic_index])
	print("SOUND_AUDITION_MANIFEST: %s" % ProjectSettings.globalize_path(MANIFEST_PATH))
	quit(0)


func _elapsed() -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000000.0


func _note(label: String, elapsed: float) -> void:
	events.append({"label": label, "dispatch_seconds": elapsed})
	print("SOUND_AUDITION_CUE: %.3fs %s" % [elapsed, label])


func _measure_pcm(bytes: PackedByteArray) -> Dictionary:
	var nonzero := 0
	var peak := 0.0
	var square_sum := 0.0
	var sample_count := bytes.size() / 2
	for index in range(sample_count):
		var sample := float(bytes.decode_s16(index * 2)) / 32768.0
		if sample != 0.0:
			nonzero += 1
		peak = maxf(peak, absf(sample))
		square_sum += sample * sample
	return {"sample_count": sample_count, "nonzero_samples": nonzero, "peak": peak, "rms": sqrt(square_sum / maxf(1.0, sample_count))}
