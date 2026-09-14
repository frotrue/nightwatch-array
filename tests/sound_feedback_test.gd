extends SceneTree

# Mechanical audio gate: stream routing and PCM/real-time contracts, not a
# substitute for listening to the cues in the exported game.
const SoundSynth = preload("res://scripts/sound_synth.gd")
const MainScene = preload("res://scenes/main.tscn")
const EXPECTED_INTERVAL := 0.16
const SAMPLE_TOLERANCE := 1.0 / 44100.0

class Recorder:

	extends "res://scripts/sound_synth.gd"

	var calls: Array[Dictionary] = []
	var clock: float = 0.0

	func _play_stream(stream: AudioStreamWAV, pitch_scale: float = 1.0, delay: float = 0.0, volume_db: float = 0.0) -> void:
		calls.append({
			"stream": stream, "pitch": pitch_scale, "delay": delay,
			"volume_db": volume_db, "time": clock,
			"pending_count": automatic_pending_count,
		})

	func advance_real(seconds: float) -> void:
		clock += seconds
		_advance_automatic_pulse(seconds)

class MemorySlots:

	extends "res://scripts/save_game_controller.gd"

	var records: Dictionary = {}
	var fail_save: bool = false

	func _ready() -> void:
		for slot in range(1, 4):
			slot_summaries[slot] = {"exists": false, "valid": true}

	func save_slot(slot: int, run_data: Dictionary) -> Error:
		if fail_save:
			return ERR_CANT_CREATE
		records[slot] = run_data.duplicate(true)
		slot_summaries[slot] = _summary_from_run_data(run_data, 0)
		slots_changed.emit()
		return OK

	func load_slot(slot: int) -> Dictionary:
		return records.get(slot, {}).duplicate(true)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("SOUND_FEEDBACK: " + message)


func _run() -> void:
	var synth := Recorder.new()
	root.add_child(synth)
	_check(synth.process_mode == Node.PROCESS_MODE_ALWAYS, "UI sound processing survives a paused scene")
	_check(is_equal_approx(SoundSynth.AUTOMATIC_PULSE_INTERVAL_SECONDS, EXPECTED_INTERVAL), "automatic pulse window stays at 160 ms")
	_test_semantic_streams(synth)
	_test_automatic_batches(synth)
	_test_pause_and_reset(synth)
	synth.free()
	_test_game_routing()
	paused = false
	if failures.is_empty():
		print("SOUND_FEEDBACK_PASS: semantic routing, PCM envelopes, 1000-event aggregation, pause/reset and real-time cadence")
		quit(0)
	else:
		print("SOUND_FEEDBACK_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _test_semantic_streams(synth: Recorder) -> void:
	synth.play_upgrade()
	_expect_streams(synth, [synth.upgrade_low_stream, synth.upgrade_high_stream], "research keeps its two-note installation reward")
	_check(is_equal_approx(float(synth.calls[1].delay), 0.07), "research keeps its 70 ms note spacing")
	synth.calls.clear()
	synth.play_slot_confirm()
	_expect_streams(synth, [synth.slot_confirm_stream], "slot confirmation is a single separate click")
	synth.calls.clear()
	synth.play_rare_target()
	_expect_streams(synth, [synth.rare_low_stream, synth.rare_high_stream], "rare arrival uses its own two-note cue")
	_check(is_equal_approx(float(synth.calls[1].delay), 0.09), "rare notes are separated by 90 ms")
	synth.calls.clear()
	synth.play_environment_change()
	_expect_streams(synth, [synth.environment_stream], "environment transition uses a separate swell")

	var streams: Array[AudioStreamWAV] = [
		synth.slot_confirm_stream, synth.rare_low_stream, synth.rare_high_stream,
		synth.environment_stream, synth.upgrade_low_stream, synth.upgrade_high_stream,
	]
	for index in range(streams.size()):
		var stream := streams[index]
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == 44100, "semantic cue uses the expected mono PCM format")
		_check(_rms(stream, 0.0, stream.get_length()) > 0.001, "semantic cue contains audible nonzero samples")
		for other_index in range(index):
			_check(stream != streams[other_index] and stream.data != streams[other_index].data, "different meanings have distinct streams and PCM")
	_check(absf(synth.slot_confirm_stream.get_length() - 0.035) <= SAMPLE_TOLERANCE, "slot click lasts 35 ms")
	_check(absf(synth.rare_low_stream.get_length() - 0.075) <= SAMPLE_TOLERANCE, "rare low attack lasts 75 ms")
	_check(absf(synth.rare_high_stream.get_length() - 0.11) <= SAMPLE_TOLERANCE, "rare high attack lasts 110 ms")
	_check(absf(synth.environment_stream.get_length() - 0.44) <= SAMPLE_TOLERANCE, "environment swell lasts 440 ms")
	_check(absf(synth.automatic_tick_stream.get_length() - 0.07) <= SAMPLE_TOLERANCE, "automatic body lasts 70 ms and ends before the next pulse")
	_check(_rms(synth.slot_confirm_stream, 0.002, 0.010) > _rms(synth.slot_confirm_stream, 0.025, 0.034) * 5.0, "slot click is front-loaded with no ringing tail")
	_check(_rms(synth.rare_low_stream, 0.002, 0.012) > _rms(synth.rare_low_stream, 0.050, 0.070) * 5.0, "rare arrival has a sharp attack and fast decay")
	_check(_rms(synth.environment_stream, 0.100, 0.160) > _rms(synth.environment_stream, 0.0, 0.020) * 10.0, "environment swell rises slowly instead of repeating the rare attack")
	synth.calls.clear()


func _test_automatic_batches(synth: Recorder) -> void:
	synth.reset_streak_audio()
	synth.clock = 0.0
	for event_index in range(1000):
		var pending_before := synth.automatic_pending_count
		synth.play_automatic_tick()
		_check(synth.automatic_pending_count == pending_before + 1, "every automatic event is queued, including during cooldown")
		synth.advance_real(0.01)
	# The final partial window must drain even when no later observation arrives.
	synth.advance_real(EXPECTED_INTERVAL)
	var represented_events := 0
	var previous_time := -EXPECTED_INTERVAL
	for call in synth.calls:
		represented_events += int(call.pending_count)
		_check(call.stream == synth.automatic_tick_stream and is_equal_approx(float(call.pitch), 1.0), "automatic batches share one non-melodic body")
		_check(float(call.time) - previous_time + 0.000001 >= EXPECTED_INTERVAL, "automatic pulse spacing never falls below 160 ms")
		_check(float(call.volume_db) >= -18.0 and float(call.volume_db) <= -12.0, "automatic loudness stays in the bounded -18 to -12 dB range")
		previous_time = float(call.time)
	_check(represented_events == 1000 and synth.automatic_pending_count == 0, "100 observations/sec for ten seconds accounts for all 1000 events")
	_check(synth.calls.size() == 63, "1000 dense events are represented by 62 full windows and one final partial window")
	_check(not synth.is_processing(), "empty automatic queue does not keep a per-frame process alive")

	synth.calls.clear()
	synth.play_automatic_tick()
	synth.advance_real(EXPECTED_INTERVAL - 0.001)
	_check(synth.calls.is_empty() and synth.automatic_pending_count == 1, "a lone event waits for its window")
	synth.advance_real(0.001)
	_check(synth.calls.size() == 1 and int(synth.calls[0].pending_count) == 1, "a sparse final event flushes without another event")
	_check(is_equal_approx(float(synth.calls[0].volume_db), -18.0), "one event uses the automatic minimum volume")
	synth.calls.clear()
	for _index in range(10000):
		synth.play_automatic_tick()
	synth.advance_real(3.0)
	_check(synth.calls.size() == 1 and int(synth.calls[0].pending_count) == 10000, "a stalled frame drains a dense batch into one pulse, never a catch-up burst")
	_check(is_equal_approx(float(synth.calls[0].volume_db), -12.0), "very dense batches saturate at the volume ceiling")
	synth.calls.clear()


func _test_pause_and_reset(synth: Recorder) -> void:
	synth.play_automatic_tick()
	synth.advance_real(0.08)
	synth.reset_streak_audio()
	_check(synth.automatic_pending_count == 0 and is_zero_approx(synth.automatic_pulse_elapsed), "round/load reset clears both automatic count and partial window")
	synth.advance_real(1.0)
	_check(synth.calls.is_empty(), "reset cannot leak a pre-reset pulse")
	synth.play_automatic_tick()
	synth.advance_real(0.08)
	paused = true
	synth._process(0.08)
	_check(synth.automatic_pending_count == 0 and is_zero_approx(synth.automatic_pulse_elapsed), "pausing discards the pending automatic window")
	synth.play_automatic_tick()
	_check(synth.automatic_pending_count == 0, "automatic events arriving while paused are ignored")
	synth.play_slot_confirm()
	_expect_streams(synth, [synth.slot_confirm_stream], "slot UI remains audible while paused")
	synth.calls.clear()
	paused = false
	synth.advance_real(1.0)
	_check(synth.calls.is_empty(), "unpausing cannot replay discarded events")
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 0.06
	synth.play_automatic_tick()
	synth._process(0.15 * Engine.time_scale)
	_check(synth.calls.is_empty(), "hitstop does not shorten the real-time aggregation window")
	synth._process(0.01 * Engine.time_scale)
	_check(synth.calls.size() == 1, "hitstop does not stretch the aggregation window beyond 160 real ms")
	Engine.time_scale = previous_time_scale
	synth.reset_streak_audio()


func _test_game_routing() -> void:
	var game = MainScene.instantiate()
	game.startup_slot_prompt_enabled = false
	game.get_node("Tutorial").auto_start_enabled = false
	game.get_node("ModuleTutorial").enabled = false
	# Replace persistence before _ready: this routing test must never touch slots.
	var original_slots := game.get_node("SaveGameController")
	game.remove_child(original_slots)
	original_slots.free()
	var slots := MemorySlots.new()
	slots.name = "SaveGameController"
	game.add_child(slots)
	root.add_child(game)
	game.sound.free()
	var synth := Recorder.new()
	game.add_child(synth)
	game.sound = synth
	game._on_save_slot_requested(1)
	_expect_streams(synth, [synth.slot_confirm_stream], "successful manual save routes to slot confirmation")
	synth.calls.clear()
	game._on_load_slot_requested(1)
	_expect_streams(synth, [synth.slot_confirm_stream], "successful load routes to the same slot confirmation")
	synth.calls.clear()
	slots.fail_save = true
	game._on_save_slot_requested(2)
	game._on_load_slot_requested(3)
	_check(synth.calls.is_empty(), "failed save and failed load do not claim success with sound")
	slots.fail_save = false
	game._on_upgrade_purchased({"id": "better_lens"})
	_expect_streams(synth, [synth.upgrade_low_stream, synth.upgrade_high_stream], "research installation retains the reward chord")
	synth.calls.clear()
	game._on_rare_spawned("fireball")
	_expect_streams(synth, [synth.rare_low_stream, synth.rare_high_stream], "rare target dispatches its specific cue")
	synth.calls.clear()
	game._on_rare_spawned("major")
	_check(synth.calls.is_empty(), "major spawn does not duplicate its earlier environment warning")
	for event_key in ["EVENT_SHOWER_INCOMING", "EVENT_ATMOSPHERIC_BLOOM", "EVENT_PERSEID_OUTBURST_INCOMING"]:
		game._on_event_banner(event_key, Color.WHITE)
		_expect_streams(synth, [synth.environment_stream], "environment warning dispatches its swell: " + event_key)
		synth.calls.clear()
	game._on_event_banner("EVENT_SHOWER_STARTED", Color.WHITE)
	_check(synth.calls.is_empty(), "ordinary event banners do not acquire an extra environment cue")
	_test_debug_event_routing(game, synth)
	game.active_save_slot = 0
	game.free()


func _test_debug_event_routing(game, synth: Recorder) -> void:
	# Enter through the actual debug-key handler, then its connected event
	# banner, to detect an extra warning layered over the environment sound.
	var key := InputEventKey.new()
	key.pressed = true
	key.ctrl_pressed = true
	key.shift_pressed = true
	game.events.reset()
	game.spawner.phase_time_remaining = 60.0
	key.keycode = KEY_S
	game.handle_debug_key_input(key)
	_check(game.events.shower_state == "warning", "Ctrl+Shift+S enters the real shower warning path")
	_expect_streams(synth, [synth.environment_stream], "Ctrl+Shift+S produces exactly one environment cue with no layered warning")
	synth.calls.clear()
	game.handle_debug_key_input(key)
	_check(synth.calls.is_empty(), "a rejected repeated shower key does not emit feedback")

	game.events.reset()
	game.progression.purchased_nodes["sirius_fireball"] = true
	key.keycode = KEY_F
	game.handle_debug_key_input(key)
	_check(game.events.canis_major_state == "warning", "Ctrl+Shift+F enters the real Canis warning path")
	_expect_streams(synth, [synth.environment_stream], "Ctrl+Shift+F produces exactly one environment cue with no layered warning")
	synth.calls.clear()
	game.handle_debug_key_input(key)
	_check(synth.calls.is_empty(), "a rejected repeated Canis key does not emit feedback")

	game.events.reset()
	_check(game.events.trigger_perseid_outburst(), "the Perseid warning fixture starts a real outburst")
	_expect_streams(synth, [synth.environment_stream], "the connected Perseid incoming banner produces exactly one environment cue")
	synth.calls.clear()
	game.events.reset()
	game.spawner.phase_time_remaining = 0.1
	_check(not game.events.trigger_perseid_outburst(), "a late Perseid warning is deferred at the round boundary")
	_check(synth.calls.is_empty(), "a deferred outburst cannot announce an environment change")


func _expect_streams(synth: Recorder, expected: Array, message: String) -> void:
	var actual: Array = []
	for call in synth.calls:
		actual.append(call.stream)
	_check(actual == expected, message)


func _rms(stream: AudioStreamWAV, from_seconds: float, to_seconds: float) -> float:
	var first := clampi(int(from_seconds * stream.mix_rate), 0, stream.data.size() / 2)
	var last := clampi(int(to_seconds * stream.mix_rate), first, stream.data.size() / 2)
	var squares := 0.0
	for sample_index in range(first, last):
		var amplitude := float(stream.data.decode_s16(sample_index * 2)) / 32768.0
		squares += amplitude * amplitude
	return sqrt(squares / maxf(1.0, float(last - first)))
