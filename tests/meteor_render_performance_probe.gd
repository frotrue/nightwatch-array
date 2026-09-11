extends SceneTree
# Synthetic wall-time diagnostic: capacity bypass, isolated saves, no natural
# spawning or target completions, 17 held input samples per 60 Hz tick. The
# eight-step catch-up ceiling is reported as achieved ticks/sec; FPS at overload
# does not imply the simulation sustained real time. Run with a real renderer,
# sequentially against the baseline, never alongside other performance probes.
const Fixtures = preload("res://tests/support/game_fixture.gd")
const STEP := 1.0 / 60.0
const WARMUP := 2.0
const SAMPLE := 5.0
var failures: Array[String] = []
class ScriptedObserver:
    extends "res://scripts/observation_controller.gd"
    var point := Vector2(576, 300)
    func _screen_to_world(_value: Vector2) -> Vector2: return point
    func _cursor_is_on_ui() -> bool: return false
func _initialize():
    _run.call_deferred()
func _run():
    root.gui_disable_input = true
    for scenario in [{"count":0,"observe":true},{"count":100,"observe":true},{"count":1000,"observe":false},{"count":1000,"observe":true}]:
        var game = load("res://scenes/main.tscn").instantiate()
        Fixtures.configure_before_ready(game)
        var observer := ScriptedObserver.new()
        observer.z_index = 50
        Fixtures.replace_child(game, "ObservationController", observer)
        root.add_child(game)
        game.set_physics_process(false)
        game.set_process(false)
        observer.set_process_input(false)
        game.spawner.running = false
        game.events.running = false
        for node in game.Balance.UPGRADE_NODES: game.progression.purchased_nodes[node.id] = true
        for id in game.deep_sky.Data.RESEARCH: game.deep_sky.state.research_ids.append(id)
        var modules = game.deep_sky.modules
        modules.unlocked_slots = 5
        for id in ["linear_observation", "capture_hold", "wide", "overcharge", "wide_correlation"]:
            modules.grant_copy(id)
            modules.equip(id)
        game.observation_phase_duration = 1000
        game.observation_phase_remaining = 1000
        var targets: Array = []
        for i in int(scenario.count):
            var columns := 40 if int(scenario.count) == 1000 else 10
            var rows := ceili(float(scenario.count) / columns)
            var start := Vector2(45 + (i % columns) * (1060.0 / (columns-1)), 100 + (i / columns) * (430.0 / maxf(rows-1,1)))
            var target = game.spawner.MeteorScript.new()
            var spec: Dictionary = game.Balance.meteor_spec("common")
            target.configure(spec, "common", start, Vector2(1, 0), 1000.0 / float(spec.lifetime), game.spawner._current_features("common"), start + Vector2(30,0), game.observation_view)
            target.simulation_id = game.allocate_simulation_id()
            game.meteor_layer.add_child(target)
            game._on_meteor_spawned(target)
            target.reset_physics_interpolation()
            target.required_track_time = 1000000.0
            target.base_automatic_rate = 0.0
            target.age = 2.0
            for j in range(target.max_trail_points): target.trail_points.append(start - Vector2(j * 2.5,0))
            targets.append(target)
        game.effects.reset()
        observer.tick_input.reset(observer.point)
        observer.input_time = 0
        observer.tick_input.push(0.0, observer.point, bool(scenario.observe))
        Engine.max_fps = 0
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        print("THOUSAND_START ", scenario)
        var frames: Array[float] = []
        var cpu: Array[float] = []
        var elapsed := 0.0
        var accumulator := 0.0
        var last := Time.get_ticks_usec()
        var ticks := 0
        var measured_ticks := 0
        while elapsed < WARMUP + SAMPLE:
            await process_frame
            var now := Time.get_ticks_usec()
            var delta := (now-last)/1000000.0
            last = now
            elapsed += delta
            if elapsed > WARMUP: frames.append(delta*1000)
            var started := Time.get_ticks_usec()
            if scenario.observe:
                accumulator = minf(accumulator + delta, 8*STEP)
                while accumulator >= STEP:
                    for j in 17:
                        var at := (ticks + float(j+1)/17.0) * STEP
                        observer.point = Vector2(576 + sin(at * 4)*70, 300 + cos(at*3)*20)
                        observer.tick_input.push(at, observer.point, true)
                    game.simulate_tick()
                    ticks += 1
                    if elapsed > WARMUP: measured_ticks += 1
                    accumulator -= STEP
            else:
                for target in targets: target.age += delta
            if elapsed > WARMUP: cpu.append((Time.get_ticks_usec()-started)/1000.0)
        var observed := 0
        for target in targets:
            if target.manual_tracking_time > 0: observed += 1
        if targets.size() != int(scenario.count): failures.append("Wrong target count")
        if scenario.observe and scenario.count > 0 and observed == 0: failures.append("No observation")
        if Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) <= 0: failures.append("No rendered geometry")
        frames.sort()
        cpu.sort()
        var mean: float = frames.reduce(func(a,b):return a+b,0.0)/frames.size()
        print("THOUSAND_RESULT ",JSON.stringify({"count":scenario.count,"observe":scenario.observe,"frames":frames.size(),"fps":1000/mean,"mean_ms":mean,"p95_ms":frames[floori((frames.size()-1)*0.95)],"simulation_mean_ms_per_frame":cpu.reduce(func(a,b):return a+b,0.0)/cpu.size(),"measured_ticks":measured_ticks,"achieved_ticks_per_sec":measured_ticks/(frames.reduce(func(a,b):return a+b,0.0)/1000),"targets_observed":observed,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}))
        game.free()
        await process_frame
    for failure in failures: push_error(failure)
    print("THOUSAND_PASS" if failures.is_empty() else "THOUSAND_FAIL")
    quit(0 if failures.is_empty() else 1)
