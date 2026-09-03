extends SceneTree

const Capture = preload("res://tests/capture_reference.gd")
const Scenarios = preload("res://tests/support/reference_capture_scenarios.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_image_rejection()
	_test_manifest_rejection()
	var git_errors: Array[String] = []
	var missing_git := ProjectSettings.globalize_path("res://build/nonexistent-reference-capture-git.exe")
	_check(Capture.source_snapshot(git_errors, missing_git).is_empty() and not git_errors.is_empty(), "unavailable Git cannot become an unknown clean revision")
	var valid_git_errors: Array[String] = []
	var identity: Dictionary = Capture.source_snapshot(valid_git_errors)
	_check(valid_git_errors.is_empty() and Capture.valid_digest(String(identity.get("revision", "")), 40), "actual project source has a full Git identity")
	if not identity.is_empty():
		_check(identity.files_sha256.has("tests/support/reference_capture_scenarios.gd"), "source identity includes the capture fixture")
		_check(Capture.valid_digest(String(identity.source_digest), 64), "full file map has a source digest")
	var fixture := Scenarios.new()
	var ids: Array = []
	for scenario in Scenarios.SCENARIOS:
		var id := String(scenario.id)
		_check(not id in ids, "scenario IDs are unique")
		ids.append(id)
		var game: Node = await fixture.prepare(self, id)
		_check(game != null, "scenario creates game: " + id)
		if game == null:
			break
		var before: Dictionary = fixture.inspect(game, id)
		_check(Capture.inspection_matches(before, id), "scenario returns a matching nonempty inspection: " + id)
		for _frame in range(4):
			await process_frame
		var after: Dictionary = fixture.inspect(game, id)
		_check(Capture.inspection_matches(after, id), "post-frame inspection remains valid: " + id)
		_check(before == after, "frozen state survives engine frames: " + id)
		game.free()
		paused = false
		await process_frame
	failures.append_array(fixture.failures)
	if failures.is_empty():
		print("REFERENCE_CAPTURE_TEST_PASS: blank/size/manifest/Git failures rejected; %d isolated scenario contracts stay frozen" % ids.size())
		quit(0)
	else:
		for message in failures:
			push_error("REFERENCE_CAPTURE_TEST_FAIL: " + message)
		quit(1)


func _test_image_rejection() -> void:
	_check(not Capture.image_is_usable(null), "null image rejected")
	_check(not Capture.image_is_usable(Image.new()), "empty image rejected")
	var image := Image.create(1152, 648, false, Image.FORMAT_RGBA8)
	for color in [Color.BLACK, Color.WHITE, Color.TRANSPARENT]:
		image.fill(color)
		_check(not Capture.image_is_usable(image), "uniform/transparent image rejected")
	image.fill(Color.BLACK)
	for x in range(24):
		image.set_pixel(x * 8, 0, Color.WHITE)
	_check(Capture.image_is_usable(image), "nonblank expected-size image accepted")
	image.resize(576, 324)
	_check(not Capture.image_is_usable(image), "wrong-size image rejected")


func _test_manifest_rejection() -> void:
	var good := {"id": "one", "sha256": "a".repeat(64), "size": [1152, 648], "state_contract_valid": true, "observed": {"id": "one"}}
	_check(Capture.manifest_is_complete([good], ["one"]), "one complete declared record accepted")
	_check(not Capture.manifest_is_complete([], ["one"]), "missing record rejected")
	_check(not Capture.manifest_is_complete([good, good], ["one", "two"]), "duplicate cannot replace a missing scenario")
	var bad: Dictionary = good.duplicate()
	bad.state_contract_valid = false
	_check(not Capture.manifest_is_complete([bad], ["one"]), "wrong scenario state rejected")
	bad = good.duplicate()
	bad.sha256 = "unknown"
	_check(not Capture.manifest_is_complete([bad], ["one"]), "unverified image rejected")
	bad = good.duplicate()
	bad.size = [576, 324]
	_check(not Capture.manifest_is_complete([bad], ["one"]), "wrong viewport record rejected")
	bad = good.duplicate()
	bad.observed = {}
	_check(not Capture.manifest_is_complete([bad], ["one"]), "empty inspection after a script error cannot pass")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
