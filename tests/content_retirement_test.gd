extends SceneTree
const Fixtures = preload("res://tests/support/game_fixture.gd")
const Balance = preload("res://scripts/game_balance.gd")
const Data = preload("res://scripts/expansion_data.gd")
const Modules = preload("res://scripts/observation_modules.gd")
var failures: Array[String] = []
func _initialize():
	_run.call_deferred()
func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)
func _run():
	var game = load("res://scenes/main.tscn").instantiate()
	Fixtures.configure_before_ready(game)
	root.add_child(game)
	game.sound.free()
	game.sound = Fixtures.SilentSound.new()
	game.add_child(game.sound)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.spawner.set_process(false)
	game.events.set_process(false)
	check(not game.deep_sky.modules_unlocked(), "modules require the coordinate research")
	game.progression.debug_purchase_all()
	check(game.progression.upgrade_level == 95 and game.progression.is_research_complete(), "debug purchases only 95 active base studies")
	check(game.deep_sky.modules_unlocked() and game.deep_sky.research_owned("ext_protocol"), "coordinate research directly unlocks modules without M31")
	check(not game.has_node("HostStarLayer") and not game.has_node("GalacticPhenomenaLayer"), "retired target layers do not exist")
	check(not game.has_method("_show_catalogue_ending") and not game.hud.has_method("show_catalogue_ending"), "retired ending has no runtime entry point")
	for node in game.deep_sky.get_children():
		check(node.get_script().resource_path != "res://scripts/andromeda_target.gd", "no M31 target")
	check(Data.SAMPLE_MODULES.size() == 8 and Modules.DEFINITIONS.size() == 8, "eight supported modules")
	check(Data.RESEARCH.size() == 55, "55 active studies include outer celestial research without restoring retired M31 studies")
	var saved: Dictionary = game._build_save_data()
	saved.progression.purchased_nodes.append_array(["lmc_transit_watch", "wlm_einstein_ring", "phoenix_lensed_meteors", "aquarius_local_group_record"])
	saved["host_stars"] = {"running":true}
	saved["galactic_phenomena"] = {"completed_targets": {"supernova_primary":true}}
	saved["catalogue_ending_seen"] = false
	saved["ending_final_watch_pending"] = true
	saved.deep_sky.modules = {"purchased":["focus","record","revisit","reference_bus","shutter_weave"],"quantities":{"record":3},"slots":["record","focus","reference_bus"],"unlocked_slots":3}
	saved.deep_sky.extension.research_ids.append_array(Data.RETIRED_RESEARCH_IDS)
	saved.deep_sky["progress"] = 0.4
	saved.deep_sky["cooldown"] = 2.0
	game._apply_save_data(saved)
	check(game.progression.upgrade_level == 95, "legacy research is discarded when loading")
	check(is_equal_approx(game.progression.get_observation_span(),1.0), "legacy saves cannot widen the field")
	check(game.deep_sky.modules.installed_ids() == ["focus"], "retired modules are unequipped on load")
	check(game.deep_sky.modules.owned_count("record") == 3, "retired ownership remains data")
	for id in Modules.RETIRED_IDS:
		check(not game.deep_sky.modules.equip(id,0), "cannot equip retired module " + id)
		check(not game.deep_sky.modules.grant_copy(id), "cannot acquire retired module " + id)
	for id in Data.RETIRED_RESEARCH_IDS:
		check(not game.deep_sky.can_purchase(id) and not game.upgrade_tree.node_buttons.has(id), "no retired research purchase or chart star: " + id)
	var state = game.deep_sky.state
	state.samples = 8000
	state.samples_earned = 8000
	for i in range(1000):
		check(state.draw_module() in Modules.DEFINITIONS, "draw returns an active module")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(game._build_save_data()))
	game._apply_save_data(roundtrip)
	check(game.deep_sky.modules.owned_count("record") == 3, "retired ownership survives repeated saves")
	var report: Dictionary = game._build_round_result()
	for id in Modules.RETIRED_IDS:
		check(id not in report.modules_acquired, "retired ownership never appears as newly acquired in the round summary")
	check(game.deep_sky.state.retired_research_ids.size() == 5, "retired extension ownership is stored separately")
	check(is_equal_approx(game.deep_sky.retired_m31.progress,0.4), "old M31 progress remains inert data")
	check(not roundtrip.has("host_stars") and not roundtrip.has("galactic_phenomena") and not roundtrip.has("ending_final_watch_pending"), "new saves omit retired runtime state")
	game.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("CONTENT_RETIREMENT_PASS: removed runtime, research, ending and lens paths; inert ownership migration; ten-module pool"); quit(0)
	else: quit(1)
