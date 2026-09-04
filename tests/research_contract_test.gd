extends SceneTree

const Balance = preload("res://scripts/game_balance.gd")
const ProgressionController = preload("res://scripts/progression_controller.gd")

const EXPECTED_NODE_COUNT := 107
const EXPECTED_RUNTIME_PARAMETER_KEYS := [
	"observation_duration_bonus",
	"observation_value_multiplier",
]
const EXPECTED_CONTRACT_COUNTS := {
	"observation_value_multiplier": 10,
	"observation_duration_bonus": 4,
	"max_active_delta": 8,
	"regular_spawn_interval_floor": 4,
	"galactic_observation_profile": 3,
	"galactic_chapter_milestone": 4,
	"supernova_watch": 1,
	"supernova_overlap": 1,
	"lens_observation": 2,
	"lensed_supernova": 1,
}
const EXPECTED_DYNAMIC_CONNECTION_IDS := [
	"amber_band",
	"blue_band",
	"violet_band",
]
const EXPECTED_PREREQUISITE_ONLY_IDS := ["canis_opening", "filter_wheel"]
const EXPECTED_SKY_ACTIVITY_IDS := [
	"array_planning",
	"multi_target_analysis",
	"cascade_sampling",
	"perseid_survey",
	"canis_cadence_i",
	"canis_capacity_i",
	"canis_cadence_ii",
	"canis_capacity_ii",
	"canis_cadence_iii",
	"canis_capacity_iii",
	"draco_cadence",
	"draco_capacity",
]
const EXPECTED_OBSERVATION_STREAK_TERM_IDS := [
	"observation_streak",
	"momentum_acquisition",
	"wide_pursuit",
	"rapid_focus",
	"cadence_memory",
	"expanded_sweep",
	"accelerated_analysis",
	"sustained_charge",
	"taurus_full_gallop",
]

# This exact baseline makes the remaining contract debt visible without making
# `unverified` a free escape hatch. New nodes and verified-node regressions fail
# until this set is deliberately reviewed and updated.
const EXPECTED_UNVERIFIED_IDS := [
	"better_lens",
	"long_exposure",
	"observation_streak",
	"precision_multiplier",
	"edge_detection",
	"wide_field",
	"trajectory",
	"rare_detection",
	"fragment_analysis",
	"secondary_camera",
	"predictive_dish_control",
	"automated_tracking",
	"observatory_network",
	"contact_ledger",
	"companion_resolution",
	"polar_survey",
	"sweep_gain",
	"faint_recovery",
	"sustained_sweep",
	"deep_exposure",
	"rapid_scan",
	"polar_cascade",
	"radiant_plotting",
	"crowd_forecast",
	"burst_windowing",
	"debris_correlation",
	"adaptive_exposure_grid",
	"filter_wheel",
	"blue_band",
	"amber_band",
	"violet_band",
	"lyrid_spectrograph",
	"ephemeris_marks",
	"satellite_catalog",
	"change_detection",
	"variable_watchlist",
	"comet_solutions",
	"andromeda_deep_survey",
	"echo_correlation_10",
	"echo_correlation_20",
	"single_echo_channel",
	"dual_echo_channel",
	"triple_echo_array",
	"leonid_radiant",
	"compressed_cadence",
	"dense_stream",
	"rapid_reacquisition",
	"storm_front",
	"leonid_storm",
	"split_radiant_model",
	"fragment_front",
	"echo_signature_lock",
	"mirror_echo_solution",
	"echo_deconfliction",
	"echo_beacon",
	"momentum_acquisition",
	"wide_pursuit",
	"rapid_focus",
	"cadence_memory",
	"expanded_sweep",
	"accelerated_analysis",
	"sustained_charge",
	"canis_opening",
	"sirius_fireball",
	"draco_sweep",
	"draco_echo",
	"draco_storm",
	"draco_array",
	"galactic_reference_frame",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("RESEARCH_CONTRACT: " + message)


func _run() -> void:
	var scripts_source := _collect_gd_sources("res://scripts")
	var progression_source := FileAccess.get_file_as_string("res://scripts/progression_controller.gd")
	var balance_source := FileAccess.get_file_as_string("res://scripts/game_balance.gd")
	var gameplay_source := scripts_source.replace(balance_source, "")
	var definitions_by_id: Dictionary = {}
	var contract_ids_by_kind: Dictionary = {}
	var runtime_keys: Dictionary = {}
	var dynamic_connection_ids: Array[String] = []
	var prerequisite_only_ids: Array[String] = []
	var actual_unverified_ids: Array[String] = []

	_check(Balance.UPGRADE_NODES.size() == EXPECTED_NODE_COUNT, "research definition count is exactly 107")
	_check(Balance.research_node_count() == 107, "every research definition is installable")
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var node_id := String(definition.get("id", ""))
		_check(not node_id.is_empty(), "every research definition has an id")
		_check(not definitions_by_id.has(node_id), "research id is unique: " + node_id)
		definitions_by_id[node_id] = definition
		var looked_up := Balance.upgrade_definition(node_id)
		_check(looked_up == definition, node_id + " lookup preserves every definition field")
		_check(looked_up.is_read_only(), node_id + " lookup preserves the read-only definition")
		_check(not definition.has("effect_parameters"), node_id + " does not use the retired ambiguous effect_parameters field")

		var runtime_parameters: Dictionary = definition.get("runtime_parameters", {})
		var effect_notes: Dictionary = definition.get("effect_notes", {})
		for key_variant in runtime_parameters.keys():
			var runtime_key := String(key_variant)
			runtime_keys[runtime_key] = true
			_check(not effect_notes.has(runtime_key), node_id + " keeps runtime key out of effect_notes: " + runtime_key)

		var contract: Dictionary = definition.get("effect_contract", {})
		if contract.is_empty():
			actual_unverified_ids.append(node_id)
		elif not contract.is_empty():
			var kind := String(contract.get("kind", ""))
			_check(EXPECTED_CONTRACT_COUNTS.has(kind), node_id + " uses a registered contract kind: " + kind)
			_check(contract.has("value") and contract.has("scope"), node_id + " contract declares value and scope")
			if kind in EXPECTED_RUNTIME_PARAMETER_KEYS:
				_check(runtime_parameters.has(kind), node_id + " data-driven contract has an independent runtime parameter: " + kind)
			else:
				_check(runtime_parameters.is_empty(), node_id + " accessor-driven contract does not masquerade as runtime data")
			if not contract_ids_by_kind.has(kind):
				contract_ids_by_kind[kind] = []
			contract_ids_by_kind[kind].append(node_id)
			if runtime_parameters.has(kind):
				_check(
					is_equal_approx(float(runtime_parameters[kind]), float(contract.get("value", 0.0))),
					node_id + " runtime value agrees with its independent contract oracle"
				)

		var connection := String(definition.get("implementation_connection", ""))
		match connection:
			"":
				pass
			"dynamic_upgrade_id":
				dynamic_connection_ids.append(node_id)
			"prerequisite_only":
				prerequisite_only_ids.append(node_id)
			_:
				_check(false, node_id + " uses an unknown implementation_connection: " + connection)

	_verify_definition_lookup_misses()
	_verify_exact_string_set(actual_unverified_ids, EXPECTED_UNVERIFIED_IDS, "unverified contract id baseline")
	_verify_exact_string_set(runtime_keys.keys(), EXPECTED_RUNTIME_PARAMETER_KEYS, "runtime parameter key registry")
	_verify_exact_string_set(dynamic_connection_ids, EXPECTED_DYNAMIC_CONNECTION_IDS, "dynamic implementation declarations")
	_verify_exact_string_set(prerequisite_only_ids, EXPECTED_PREREQUISITE_ONLY_IDS, "prerequisite-only design declarations")

	for kind_variant in EXPECTED_CONTRACT_COUNTS.keys():
		var kind := String(kind_variant)
		var ids: Array = contract_ids_by_kind.get(kind, [])
		_check(ids.size() == int(EXPECTED_CONTRACT_COUNTS[kind]), "%s contract count is %d" % [kind, int(EXPECTED_CONTRACT_COUNTS[kind])])

	_check("\"effect_notes\"" not in gameplay_source, "gameplay code never reads non-executing effect_notes")
	_check("\"effect_contract\"" not in gameplay_source, "gameplay code never reads test-oracle effect_contract data")
	for key_variant in EXPECTED_RUNTIME_PARAMETER_KEYS:
		var runtime_key := String(key_variant)
		var consumer_anchor := "parameters.get(\"%s\"" % runtime_key
		_check(consumer_anchor in progression_source, "runtime parameter has a production consumer: " + runtime_key)

	var literal_upgrade_ids := _literal_has_upgrade_ids(scripts_source)
	for literal_id_variant in literal_upgrade_ids.keys():
		var literal_id := String(literal_id_variant)
		_check(definitions_by_id.has(literal_id), "has_upgrade literal resolves to a research node: " + literal_id)
	_check("has_upgrade(\"%s_band\" % spectral_band)" in scripts_source, "declared spectral-band ids have a live dynamic lookup")
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var node_id := String(definition.id)
		var connected := (
			literal_upgrade_ids.has(node_id)
			or not Dictionary(definition.get("runtime_parameters", {})).is_empty()
			or not String(definition.get("implementation_connection", "")).is_empty()
			or node_id in Balance.GALACTIC_SPAN_NODE_IDS
			or Balance.GALACTIC_OBSERVATION_PROFILES.has(node_id)
		)
		_check(connected, node_id + " has a literal, runtime-parameter, dynamic-id, or prerequisite-only implementation connection")

	for prerequisite_id_variant in EXPECTED_PREREQUISITE_ONLY_IDS:
		var prerequisite_id := String(prerequisite_id_variant)
		_check(_is_prerequisite_for_any(prerequisite_id), prerequisite_id + " is a declared prerequisite-only design with live dependents")

	var progression = ProgressionController.new()
	root.add_child(progression)
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if not Dictionary(definition.get("effect_contract", {})).is_empty():
			_verify_contract_behavior(progression, definition)
	_verify_combined_value_multiplier(progression, contract_ids_by_kind.get("observation_value_multiplier", []))
	progression.queue_free()

	_verify_claims_bidirectionally(contract_ids_by_kind)
	print("RESEARCH_CONTRACT_UNVERIFIED: %d exact ids" % actual_unverified_ids.size())
	if failures.is_empty():
		print("RESEARCH_CONTRACT_PASS: 107 installable research nodes, 38 executable contracts, 69 exact unverified ids, and bidirectional en/ko claims")
		quit(0)
	else:
		push_error("RESEARCH_CONTRACT_FAIL: %d failure(s)" % failures.size())
		quit(1)


func _verify_definition_lookup_misses() -> void:
	# Misses are fresh mutable dictionaries, not shared state that a caller can
	# accidentally populate for the next lookup. IDs remain case-sensitive.
	var missing := Balance.upgrade_definition("__missing_research__")
	_check(missing.is_empty(), "unknown research returns an empty definition")
	_check(not missing.is_read_only(), "unknown research keeps its mutable empty result")
	missing["probe_only"] = true
	_check(Balance.upgrade_definition("__missing_research__").is_empty(), "unknown research results are not shared")
	_check(Balance.upgrade_definition("").is_empty(), "empty research id does not resolve")
	for definition in Balance.UPGRADE_NODES:
		_check(Balance.upgrade_definition(String(definition.id).to_upper()).is_empty(), "research id lookup is case-sensitive: " + String(definition.id))


func _verify_contract_behavior(progression, definition: Dictionary) -> void:
	var node_id := String(definition.id)
	var contract: Dictionary = definition.effect_contract
	var kind := String(contract.kind)
	var expected_value := float(contract.value)
	progression.reset()
	match kind:
		"observation_value_multiplier":
			_check(String(contract.scope) == "all_observation_data", node_id + " multiplier contract has global observation-data scope")
			var before: float = progression.get_observation_value_multiplier("common", 0)
			progression.purchased_nodes[node_id] = true
			var after: float = progression.get_observation_value_multiplier("common", 0)
			_check(is_equal_approx(after / before, expected_value), node_id + " runtime multiplier matches its independent contract")
		"observation_duration_bonus":
			_check(String(contract.scope) == "future_observation_windows", node_id + " duration contract has future-window scope")
			var before: float = progression.get_observation_duration()
			progression.purchased_nodes[node_id] = true
			var after: float = progression.get_observation_duration()
			_check(is_equal_approx(after - before, expected_value), node_id + " runtime duration delta matches its independent contract")
		"max_active_delta":
			_check(String(contract.scope) == "regular_active_contacts", node_id + " capacity contract has regular-contact scope")
			var before: int = progression.get_max_active()
			progression.purchased_nodes[node_id] = true
			var after: int = progression.get_max_active()
			_check(is_equal_approx(float(after - before), expected_value), node_id + " runtime active-cap delta matches its independent contract")
		"regular_spawn_interval_floor":
			_check(String(contract.scope) == "regular_meteor_arrivals", node_id + " interval-floor contract has regular-arrival scope")
			progression.purchased_nodes[node_id] = true
			_check(is_equal_approx(progression.get_regular_spawn_interval_floor(), expected_value), node_id + " runtime interval floor matches its independent contract")
		"galactic_observation_profile":
			_check("aim_and_hold" in String(contract.scope), node_id + " profile keeps the shared observation gesture")
			progression.purchased_nodes[node_id] = true
			_check(node_id in progression.get_galactic_observation_profile_ids(), node_id + " becomes an ordinary Local Group target profile")
			if node_id == "lmc_transit_watch":
				_check(progression.host_stars_unlocked(), node_id + " opens the distant-target layer")
				_check(int(contract.max_host_stars) == 1 and int(contract.max_active_transits) == 1, node_id + " begins with one target and one active observation")
		"galactic_chapter_milestone":
			_check("visible_world" in String(contract.scope), node_id + " chapter milestone has visible-world scope")
			var before_span: float = progression.get_observation_span()
			progression.purchased_nodes[node_id] = true
			_check(is_equal_approx(progression.get_observation_span() / before_span, expected_value), node_id + " applies one exact 10.25% span step")
			if node_id == "m33_transit_network":
				_check(progression.get_host_star_capacity() == 2 and progression.get_active_transit_capacity() == 2, node_id + " also raises both host capacities to two")
		"supernova_watch", "supernova_overlap", "lensed_supernova":
			_check(String(contract.scope) == "galactic_phenomena_layer", node_id + " phenomenon contract is owned by the dedicated layer")
			progression.purchased_nodes[node_id] = true
			_check(progression.has_upgrade(node_id), node_id + " has a live progression gate consumed by the phenomena layer")
		"lens_observation":
			_check(String(contract.scope) == "aim_and_hold", node_id + " lens contract keeps the ordinary observation gesture")
			progression.purchased_nodes[node_id] = true
			_check(progression.has_upgrade(node_id), node_id + " has a live progression gate consumed by the phenomena layer")
		_:
			_check(false, node_id + " has no executable adapter for contract kind: " + kind)


func _verify_combined_value_multiplier(progression, multiplier_ids: Array) -> void:
	progression.reset()
	var expected_product := 1.0
	for node_id_variant in multiplier_ids:
		var node_id := String(node_id_variant)
		progression.purchased_nodes[node_id] = true
		var contract: Dictionary = Balance.upgrade_definition(node_id).effect_contract
		expected_product *= float(contract.value)
	var actual_product: float = progression.get_observation_value_multiplier("common", 0)
	_check(is_equal_approx(expected_product, 8192.0), "ten multiplier contracts combine to x8192")
	_check(is_equal_approx(actual_product, expected_product), "runtime global multiplier matches the independent x8192 contract product")


func _verify_claims_bidirectionally(contract_ids_by_kind: Dictionary) -> void:
	var claimed_ids_by_kind := {
		"observation_value_multiplier": [],
		"observation_duration_bonus": [],
		"max_active_delta": [],
		"regular_spawn_interval_floor": [],
		"galactic_observation_profile": [],
		"galactic_chapter_milestone": [],
		"supernova_watch": [],
		"supernova_overlap": [],
		"lens_observation": [],
		"lensed_supernova": [],
	}
	var original_locale := TranslationServer.get_locale()
	var sky_activity_claim_ids: Array[String] = []
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		var node_id := String(definition.id)
		var english := _localized_description(node_id, "en")
		var korean := _localized_description(node_id, "ko")
		var claims_sky_activity := "Sky Activity" in english or "하늘 활동" in korean
		if claims_sky_activity:
			sky_activity_claim_ids.append(node_id)
			_check("Sky Activity" in english and "하늘 활동" in korean, node_id + " exposes the shared Sky Activity term in both locales")
		if node_id in EXPECTED_OBSERVATION_STREAK_TERM_IDS:
			_check("Observation Streak" in english, node_id + " uses the shared English Observation Streak term")
			_check("관측 연속" in korean, node_id + " uses the shared Korean observation-streak term")
			_check("Momentum" not in english and "모멘텀" not in korean, node_id + " removes the retired Momentum term from player copy")
		var contract: Dictionary = definition.get("effect_contract", {})
		if _claims_global_multiplier(english, korean):
			claimed_ids_by_kind["observation_value_multiplier"].append(node_id)
		if _claims_duration_bonus(english, korean):
			claimed_ids_by_kind["observation_duration_bonus"].append(node_id)
		if _claims_max_active_delta(english, korean):
			claimed_ids_by_kind["max_active_delta"].append(node_id)
		if _claims_regular_spawn_interval_floor(english, korean):
			claimed_ids_by_kind["regular_spawn_interval_floor"].append(node_id)
		if not contract.is_empty():
			match String(contract.kind):
				"observation_value_multiplier":
					var value := int(round(float(contract.value)))
					if value == 2:
						_check("Doubles all observation Data" in english and "automatic completions" in english and "×256" in english, node_id + " English copy exposes global x2, automation scope, and legacy x256 combination")
						_check("모든 관측 데이터를 2배" in korean and "자동 완료" in korean and "×256" in korean, node_id + " Korean copy exposes global x2, automation scope, and legacy x256 combination")
					else:
						_check("Multiplies all observation Data by %d" % value in english and "automatic completions" in english, node_id + " English copy exposes its global multiplier and automation scope")
						_check("모든 관측 데이터를 %d배" % value in korean and "자동 완료" in korean, node_id + " Korean copy exposes its global multiplier and automation scope")
				"observation_duration_bonus":
					_check("10 seconds" in english and "future observation window" in english, node_id + " English copy exposes the 10-second future-window delta")
					_check("10초" in korean and "다음 관측부터 관측 시간을" in korean, node_id + " Korean copy exposes the 10-second future-window delta")
				"max_active_delta":
					var delta_words := {1: "one", 2: "two", 6: "six"}
					var delta_value := int(round(float(contract.value)))
					var english_delta := String(delta_words.get(delta_value, str(delta_value)))
					var korean_delta := "%d개" % delta_value
					_check("allows " + english_delta + " more regular target" in english.to_lower(), node_id + " English copy exposes its regular active-contact delta")
					_check("일반 표적의 상한을 " + korean_delta + " 늘립니다" in korean, node_id + " Korean copy exposes its regular active-contact delta")
				"regular_spawn_interval_floor":
					var seconds := "%.2f" % float(contract.value)
					_check("shortest time between regular meteors to " + seconds + " seconds" in english, node_id + " English copy exposes the exact regular-arrival floor")
					_check("일반 유성의 최소 출현 간격을 " + seconds + "초로" in korean, node_id + " Korean copy exposes the exact regular-arrival floor")
				"galactic_observation_profile":
					_check(("aim-and-hold" in english or "tracking" in english or "35% longer" in english), node_id + " English copy exposes an ordinary observation variation")
					_check("관측" in korean, node_id + " Korean copy keeps observation as the player verb")
					claimed_ids_by_kind["galactic_observation_profile"].append(node_id)
				"galactic_chapter_milestone":
					_check("10.25%" in english and "10.25%" in korean, node_id + " exposes the exact chapter span in both locales")
					claimed_ids_by_kind["galactic_chapter_milestone"].append(node_id)
				"supernova_watch":
					_check("supernova" in english.to_lower() and "초신성" in korean, node_id + " exposes the persistent supernova verb in both locales")
					claimed_ids_by_kind["supernova_watch"].append(node_id)
				"supernova_overlap":
					_check("two supernova" in english.to_lower() and "두 초신성" in korean, node_id + " exposes the overlapping timing choice in both locales")
					claimed_ids_by_kind["supernova_overlap"].append(node_id)
				"lens_observation":
					_check(("ring" in english.to_lower() or "lens" in english.to_lower()) and "aim-and-hold" in english and "관측" in korean, node_id + " exposes lens shape without a new verb")
					claimed_ids_by_kind["lens_observation"].append(node_id)
				"lensed_supernova":
					_check("supernova" in english.to_lower() and "lens" in english.to_lower() and "초신성" in korean and "렌즈" in korean, node_id + " exposes the combined coda verb in both locales")
					claimed_ids_by_kind["lensed_supernova"].append(node_id)
	TranslationServer.set_locale(original_locale)
	_verify_exact_string_set(
		sky_activity_claim_ids,
		EXPECTED_SKY_ACTIVITY_IDS,
		"shared Sky Activity player-term ids"
	)

	# The reverse comparison is essential: the 2026-08-26 audit checked that all
	# eight x2 contracts had claims but missed a ninth false claim on leonid_storm.
	# Exact set equality prevents both missing claims and effects advertised where
	# no matching runtime contract exists.
	for kind_variant in EXPECTED_CONTRACT_COUNTS.keys():
		var kind := String(kind_variant)
		_verify_exact_string_set(
			claimed_ids_by_kind[kind],
			contract_ids_by_kind.get(kind, []),
			kind + " bidirectional English/Korean claim ids"
		)


func _claims_global_multiplier(english: String, korean: String) -> bool:
	return (
		"Doubles all observation Data" in english
		or "Multiplies all observation Data by " in english
		or "×256" in english
		or "모든 관측 데이터를 2배" in korean
		or "모든 관측 데이터를 4배" in korean
		or "모든 관측 데이터를 8배" in korean
		or "×256" in korean
	)


func _claims_duration_bonus(english: String, korean: String) -> bool:
	return "future observation window" in english or "다음 관측부터 관측 시간을" in korean


func _claims_max_active_delta(english: String, korean: String) -> bool:
	var plain_english := english.to_lower()
	return (
		"allows one more regular target" in plain_english
		or "allows two more regular targets" in plain_english
		or "allows six more regular targets" in plain_english
		or ("일반 표적의 상한을 " in korean and "개 늘립니다" in korean)
	)


func _claims_regular_spawn_interval_floor(english: String, korean: String) -> bool:
	return "shortest time between regular meteors to " in english or "일반 유성의 최소 출현 간격을 " in korean


func _localized_description(node_id: String, locale: String) -> String:
	TranslationServer.set_locale(locale)
	return String(TranslationServer.translate("UPGRADE_%s_DESC" % node_id.to_upper()))


func _literal_has_upgrade_ids(source: String) -> Dictionary:
	var ids: Dictionary = {}
	var regex := RegEx.new()
	var compile_result := regex.compile("has_upgrade\\s*\\(\\s*\"([^\"]+)\"\\s*\\)")
	_check(compile_result == OK, "has_upgrade literal scanner compiles")
	if compile_result != OK:
		return ids
	for result in regex.search_all(source):
		ids[result.get_string(1)] = true
	return ids


func _is_prerequisite_for_any(node_id: String) -> bool:
	for definition_variant in Balance.UPGRADE_NODES:
		var definition: Dictionary = definition_variant
		if node_id in Array(definition.get("prerequisites", [])):
			return true
	return false


func _verify_exact_string_set(actual_values: Array, expected_values: Array, label: String) -> void:
	var actual := _sorted_strings(actual_values)
	var expected := _sorted_strings(expected_values)
	_check(actual == expected, "%s matches exact baseline; actual=%s expected=%s" % [label, actual, expected])


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value_variant in values:
		result.append(String(value_variant))
	result.sort()
	return result


func _collect_gd_sources(path: String) -> String:
	var source := ""
	for file_name_variant in DirAccess.get_files_at(path):
		var file_name := String(file_name_variant)
		if file_name.ends_with(".gd"):
			source += FileAccess.get_file_as_string(path.path_join(file_name)) + "\n"
	for directory_variant in DirAccess.get_directories_at(path):
		source += _collect_gd_sources(path.path_join(String(directory_variant)))
	return source
