extends RefCounted

# Read a tiny, non-blocking pipe twice a second. The optional helper samples
# Windows counters independently, so PDH never stalls the simulation/render thread.
var process: Dictionary = {}
var cpu := -1.0
var gpu := -1.0
var _pending := ""
var _last_sample_usec := 0

func start() -> void:
	stop()
	if OS.get_name() != "Windows": return
	var path := OS.get_executable_path().get_base_dir().path_join("NightwatchMetrics.exe")
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path("res://build/windows/NightwatchMetrics.exe")
	if FileAccess.file_exists(path):
		process = OS.execute_with_pipe(path, [str(OS.get_process_id())], false)

func poll() -> void:
	if process.is_empty(): return
	var pipe: FileAccess = process.stdio
	_pending += pipe.get_buffer(4096).get_string_from_utf8()
	var newline := _pending.find("\n")
	while newline >= 0:
		var sample = JSON.parse_string(_pending.left(newline))
		_pending = _pending.substr(newline + 1)
		if sample is Dictionary and sample.has("cpu") and sample.has("gpu"):
			cpu = _valid_percent(sample.cpu)
			gpu = _valid_percent(sample.gpu)
			_last_sample_usec = Time.get_ticks_usec()
		newline = _pending.find("\n")
	if _pending.length() > 4096: _pending = ""
	if Time.get_ticks_usec() - _last_sample_usec > 4000000:
		cpu = -1.0
		gpu = -1.0

func stop() -> void:
	if not process.is_empty():
		for key in ["stdio", "stderr"]:
			var pipe: FileAccess = process.get(key)
			if pipe != null: pipe.close()
		if OS.is_process_running(process.pid): OS.kill(process.pid)
	process.clear()
	_pending = ""
	_last_sample_usec = 0
	cpu = -1.0
	gpu = -1.0

static func _valid_percent(value: Variant) -> float:
	if (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 100:
		return float(value)
	return -1.0
