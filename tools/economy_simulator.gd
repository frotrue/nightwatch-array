extends SceneTree

const Session = preload("res://tests/support/economy_session.gd")
const PREFIX := "SIM_JSON "

func _initialize() -> void:
	call_deferred("_run")

func _emit(kind: String, payload: Dictionary) -> void:
	print(PREFIX + JSON.stringify({"kind": kind, "payload": payload}))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var configuration := {}
	var output := ""
	var index := 0
	while index < args.size():
		if args[index] == "--help":
			print("--config FILE.json --output REPORT.json; strategy=external accepts JSON lines on stdin. See docs/economy-simulator.md")
			quit(0)
			return
		if args[index] not in ["--config", "--output"] or index + 1 >= args.size():
			_emit("error", {"message": "Expected --config FILE or --output FILE"})
			quit(2)
			return
		if args[index] == "--config":
			var json := JSON.new()
			var file := FileAccess.open(args[index + 1], FileAccess.READ)
			if file == null or json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
				_emit("error", {"message": "Cannot read configuration object"})
				quit(2)
				return
			configuration = json.data
		else:
			output = args[index + 1]
		index += 2
	var errors := Session.validate(configuration)
	if not errors.is_empty():
		_emit("error", {"errors": errors})
		quit(2)
		return
	var session := Session.new()
	await session.setup(self, configuration)
	if session.config.strategy == "external":
		_emit("state", session.snapshot())
		while true:
			# Blocking only while the simulation is paused. EOF is a clean stop.
			var line := OS.read_string_from_stdin()
			if line.is_empty(): break
			var json := JSON.new()
			if json.parse(line) != OK or not json.data is Dictionary:
				_emit("error", {"message": "Expected a JSON object"})
				continue
			var command: Dictionary = json.data
			if command.get("action") == "quit": break
			if command.get("action") == "state":
				_emit("state", session.snapshot())
				continue
			if command.get("action") == "report":
				_emit("report", session.report())
				continue
			_emit("result", await session.act(command))
			_emit("state", session.snapshot())
	else:
		while session.stop_reason().is_empty():
			await session.auto_purchase()
			if not session.stop_reason().is_empty(): break
			var result: Dictionary = await session.act({"action": "next_round", "revision": session.revision})
			if not result.ok:
				_emit("error", result)
				await session.dispose()
				quit(1)
				return
			_emit("round", session.rounds.back())
		# Purchase after the final full round too, so its batch is measured.
		await session.auto_purchase()
	var report := session.report()
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			_emit("error", {"message": "Cannot write report", "path": output})
			await session.dispose()
			quit(2)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	_emit("report", report)
	await session.dispose()
	quit(0)
