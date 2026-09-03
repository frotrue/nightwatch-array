extends SceneTree

# A rendered reference gate, not a headless gate. This Windows Godot build
# supports only the dummy renderer under --headless. Use the documented
# off-screen Windows/OpenGL command; a logged-in desktop session is required.
const Scenarios = preload("res://tests/support/reference_capture_scenarios.gd")
const OUTPUT_ROOT := "res://build/reference"
const VIEWPORT_SIZE := Vector2i(1152, 648)
const SETTLE_ATTEMPTS := 12
const WATCHDOG_SECONDS := 90.0

var results: Array[Dictionary] = []
var failures: Array[String] = []
var source: Dictionary = {}
var run_dir := ""
var active_game: Node
var aborted := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_abort("Headless disables rendering. Use the documented off-screen Windows/OpenGL desktop command.")
		return
	if Vector2i(root.get_visible_rect().size) != VIEWPORT_SIZE:
		_abort("Expected viewport 1152x648; use --resolution 1152x648.")
		return
	root.gui_disable_input = true
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(
		func(): _abort("Renderer/scenario watchdog expired after 90 seconds.")
	)
	source = source_snapshot(failures)
	if source.is_empty():
		failures.append("Source inspection returned no identity.")
	if not failures.is_empty():
		_finish_failure()
		return
	var run_id := "%s%s_%d" % [
		String(source.revision).left(12), "_dirty" if source.revision_dirty else "",
		int(Time.get_unix_time_from_system() * 1000.0),
	]
	run_dir = OUTPUT_ROOT.path_join(run_id)
	var absolute_dir := ProjectSettings.globalize_path(run_dir)
	if DirAccess.dir_exists_absolute(absolute_dir):
		_abort("Run directory already exists; refusing to overwrite a corpus.")
		return
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK:
		_abort("Cannot create output directory: " + error_string(dir_error))
		return

	var fixture := Scenarios.new()
	var expected_ids: Array = []
	for scenario in Scenarios.SCENARIOS:
		var id := String(scenario.id)
		if id.is_empty() or not id.is_valid_identifier() or id in expected_ids:
			failures.append("Scenario IDs must be unique safe identifiers: " + id)
			break
		expected_ids.append(id)
		if not scenario.has("stage") or not scenario.has("density") or not scenario.has("overlays"):
			failures.append("Scenario manifest is missing stage/density/overlays: " + id)
			break
	if not failures.is_empty():
		_finish_failure()
		return
	for scenario in Scenarios.SCENARIOS:
		var id := String(scenario.id)
		active_game = await fixture.prepare(self, id)
		if active_game == null or not fixture.failures.is_empty():
			failures.append_array(fixture.failures)
			if active_game == null:
				failures.append("Scenario did not create a game: " + id)
			break
		var before: Dictionary = fixture.inspect(active_game, id)
		if not inspection_matches(before, id):
			failures.append("Scenario inspection returned no matching state: " + id)
		if not fixture.failures.is_empty():
			failures.append_array(fixture.failures)
		if not failures.is_empty():
			break
		var frame: Image = await _capture_settled_frame()
		var after: Dictionary = fixture.inspect(active_game, id)
		if not inspection_matches(after, id):
			failures.append("Post-render inspection returned no matching state: " + id)
		if not fixture.failures.is_empty():
			failures.append_array(fixture.failures)
		if before != after:
			failures.append("Scenario state advanced while rendering: " + id)
		if frame == null:
			failures.append("No stable nonblank image with the expected dimensions: " + id)
		if not failures.is_empty():
			break
		var image_path := run_dir.path_join(id + ".png")
		var png_error := frame.save_png(image_path)
		if png_error != OK:
			failures.append("Cannot save %s: %s" % [id, error_string(png_error)])
			break
		var png_hash := FileAccess.get_sha256(image_path)
		if not valid_digest(png_hash, 64):
			failures.append("Cannot verify the written PNG: " + id)
			break
		results.append({
			"id": id, "scenario": scenario, "file": id + ".png",
			"sidecar": id + ".json", "sha256": png_hash,
			"size": [frame.get_width(), frame.get_height()],
			"state_contract_valid": true, "observed": after,
		})
		active_game.free()
		active_game = null
		paused = false
		await process_frame
	if is_instance_valid(active_game):
		active_game.free()
		active_game = null
	paused = false
	var final_source := source_snapshot(failures)
	if source != final_source:
		failures.append("Source revision, status or files changed during capture; discard this run.")
	if not manifest_is_complete(results, expected_ids):
		failures.append("Expected each scenario exactly once with a verified PNG and state contract.")
	if not failures.is_empty():
		_finish_failure()
		return

	var common := {
		"status": "passed", "run_id": run_id,
		"captured_utc": Time.get_datetime_string_from_system(true),
		"viewport": [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"godot": Engine.get_version_info(),
		"display_driver": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"source": source,
		"limitation": "Rendered off-screen desktop capture, not display-less CI or a live-pacing verdict.",
	}
	# Publish per-image provenance only after all states and the unchanged
	# source snapshot pass. A partial/invalid run gets only a failed manifest.
	for result in results:
		var sidecar: Dictionary = common.duplicate(true)
		sidecar["capture"] = result
		if not _write_json(run_dir.path_join(String(result.sidecar)), sidecar):
			_finish_failure()
			return
	var manifest: Dictionary = common.duplicate(true)
	manifest["expected_count"] = expected_ids.size()
	manifest["expected_ids"] = expected_ids
	manifest["scenarios"] = results
	if not _write_json(run_dir.path_join("manifest.json"), manifest):
		_finish_failure()
		return
	if source.revision_dirty:
		print("REFERENCE_CAPTURE_DIRTY: base revision plus recorded working-tree file hashes")
	print("REFERENCE_CAPTURE_PASS: %d/%d at %s; %s" % [
		results.size(), expected_ids.size(), source.revision, absolute_dir,
	])
	quit(0)


func _capture_settled_frame() -> Image:
	var prior_hash := ""
	for _attempt in range(SETTLE_ATTEMPTS):
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = root.get_texture().get_image()
		if not image_is_usable(frame):
			prior_hash = ""
			continue
		var current_hash := digest_bytes(frame.get_data())
		if current_hash == prior_hash:
			return frame
		prior_hash = current_hash
	# Never return a rejected last image. Non-null does not mean rendered.
	return null


static func image_is_usable(frame: Image) -> bool:
	if frame == null or frame.is_empty() or frame.get_size() != VIEWPORT_SIZE:
		return false
	var bright := 0
	var dark := 0
	for y in range(0, frame.get_height(), 8):
		for x in range(0, frame.get_width(), 8):
			var pixel := frame.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var value := maxf(pixel.r, maxf(pixel.g, pixel.b))
			if value >= 0.35:
				bright += 1
			elif value <= 0.10:
				dark += 1
			if bright >= 24 and dark >= 24:
				return true
	return false


static func manifest_is_complete(entries: Array, expected_ids: Array) -> bool:
	if entries.size() != expected_ids.size() or expected_ids.is_empty():
		return false
	var seen: Array = []
	for entry in entries:
		if not entry is Dictionary:
			return false
		var id := String(entry.get("id", ""))
		if id not in expected_ids or id in seen:
			return false
		if not bool(entry.get("state_contract_valid", false)):
			return false
		if not inspection_matches(entry.get("observed", {}), id):
			return false
		if not valid_digest(String(entry.get("sha256", "")), 64):
			return false
		if entry.get("size", []) != [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y]:
			return false
		seen.append(id)
	return seen.size() == expected_ids.size()


static func inspection_matches(state: Dictionary, id: String) -> bool:
	# A GDScript runtime error can return an empty typed Dictionary without
	# exiting the process. Two empty before/after snapshots are not evidence.
	return not state.is_empty() and String(state.get("id", "")) == id


static func valid_digest(value: String, length: int) -> bool:
	return value.length() == length and value.is_valid_hex_number(false)


static func digest_bytes(bytes: PackedByteArray) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()


static func source_snapshot(errors: Array[String], git_executable: String = "git") -> Dictionary:
	var revision := _git(["rev-parse", "HEAD"], errors, git_executable).strip_edges()
	if not valid_digest(revision, 40):
		errors.append("Git must supply a full 40-character HEAD; unknown is not a revision.")
	if not errors.is_empty():
		return {}
	var status := _git(["status", "--porcelain=v1", "--untracked-files=all"], errors, git_executable).strip_edges()
	var tracked := _git(["-c", "core.quotePath=false", "ls-files", "--cached", "--others", "--exclude-standard"], errors, git_executable)
	if not errors.is_empty():
		return {}
	var paths := tracked.split("\n", false)
	paths.sort()
	var hashes := {}
	for raw_path in paths:
		var path := String(raw_path).trim_suffix("\r")
		# Escaped/newline names need a different Git decoder; never silently
		# produce an incomplete source identity if such a path is introduced.
		if path.begins_with("\"") or path.begins_with("/") or ".." in path.split("/"):
			errors.append("Unsupported source path reported by Git: " + path)
			return {}
		var local_path := "res://" + path
		if not FileAccess.file_exists(local_path):
			hashes[path] = "<deleted>"
			continue
		var value := FileAccess.get_sha256(local_path)
		if not valid_digest(value, 64):
			errors.append("Cannot hash source file: " + path)
			return {}
		hashes[path] = value
	if hashes.is_empty():
		errors.append("Git reported no source files.")
		return {}
	return {
		"revision": revision,
		"revision_dirty": not status.is_empty(),
		"git_status_porcelain": status,
		"files_sha256": hashes,
		"source_digest": digest_bytes(JSON.stringify(hashes).to_utf8_buffer()),
	}


static func _git(arguments: Array, errors: Array[String], git_executable: String) -> String:
	var output: Array = []
	var args := PackedStringArray(["-C", ProjectSettings.globalize_path("res://")])
	args.append_array(PackedStringArray(arguments))
	var code := OS.execute(git_executable, args, output, true)
	if code != 0:
		errors.append("Git query failed (%d): %s" % [code, " ".join(PackedStringArray(arguments))])
		return ""
	return "".join(output)


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("Cannot open JSON output: " + path)
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	var error := file.get_error()
	file.close()
	if error != OK:
		failures.append("Cannot finish JSON output: " + path)
		return false
	return true


func _finish_failure() -> void:
	if not run_dir.is_empty():
		_write_json(run_dir.path_join("manifest.json"), {
			"status": "failed", "source": source, "failures": failures,
			"scenarios": results,
		})
	for message in failures:
		push_error("REFERENCE_CAPTURE_FAIL: " + message)
	quit(1)


func _abort(message: String) -> void:
	if aborted:
		return
	aborted = true
	failures.append(message)
	_finish_failure()
