extends "res://tests/threaded_simulation_test.gd"

# CPU-only A/B/C at an identical 60 Hz workload. This is not a frame-rate test.
# The mixed eight-type grid bypasses production capacity, suppresses completions
# and natural spawning, and supplies 17 held samples/tick. 15 warmup + 60 samples.
func _run() -> void:
	check(DisplayServer.get_name() == "headless", "CPU comparison must run headless")
	for count in [22, 128, 1000]:
		var reference: Array = []
		for mode in 3:
			var game = make_game(mode, count)
			var samples: Array[float] = []
			for tick in 75:
				var started := Time.get_ticks_usec()
				step_game(game, tick)
				if tick >= 15: samples.append((Time.get_ticks_usec() - started) / 1000.0)
			var digest: Array = []
			var observed := 0
			for target in game.meteor_layer.get_children():
				digest.append([target.position, target.manual_tracking_time, target.observation_progress])
				observed += int(target.manual_tracking_time > 0)
			if mode == 0: reference = digest
			else: check(digest == reference, "CPU modes produced different target state")
			check(observed > 0, "workload must perform observation")
			samples.sort()
			print("THREADED_CPU_RESULT ", JSON.stringify({"count":count,"mode":["live","batch_main","batch_parallel"][mode],"mean_ms":samples.reduce(func(a,b):return a+b,0.0)/samples.size(),"p95_ms":samples[56],"workers":game.observer.simulation_workers.worker_count(),"observed":observed,"ticks":60,"raw_samples_per_tick":17}))
			game.free()
			await process_frame
	print("THREADED_CPU_PASS" if failures.is_empty() else "THREADED_CPU_FAIL")
	quit(0 if failures.is_empty() else 1)
