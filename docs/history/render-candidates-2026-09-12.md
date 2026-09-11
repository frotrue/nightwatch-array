# Sequential rendering candidates — 2026-09-12

Baseline: `5c1294e1f0c16ef4c84a3dfd69053908d5fa7755`. The user requested trying
each candidate separately and retaining only improvements. No density, quality,
input, simulation, progression, save or worker-count changes were authorized or
made. Experiments ran locally without another agent or another Pro submission.

## Decisions

| Candidate | Outcome | Decisive evidence |
|---|---|---|
| 1. Fixed meteor head topology | Adopt | Repeated alternating CPU comparisons of three 12-point fans: before 9.10–9.84 us, after 6.13–6.67 us. Independent pre-change arithmetic produces identical packed vertices, colors and indices across reused, shortened and empty inputs. Only immutable fan indices are cached; changing geometry/colors stay live. |
| 2. Retained arrival strokes | Adopt | Native polyline commands remain resident; only opacity changes during fades. A 24-marker real-renderer fixture measured about 374–444 us/draw before and 67–77 us after. Independent effect draw reference matched pixels exactly on Vulkan and OpenGL, including fade, changed direction/type/position, removal, flash ordering, canvas transforms/modulation, camera span and reset. |
| 3. Separate cached cursor circles | Reject this implementation | A prototype drew the fixed full circles in a separate retained child while moving its transform. Subpixel movement and idle/active transitions produced maximum channel differences of 13–14, above the existing bound of 2. Active samples matched, but idle samples did not. No cursor implementation changes were retained. This does not rule out a different future implementation. |
| 4. GPU target transforms with resident local geometry | Adopt | Keep one native light buffer per target and update its interpolated canvas transform between geometry publications. Isolated submission CPU cost fell from 6.7–6.8 ms to 2.2–2.8 ms on Vulkan and 7.7 to 2.8 ms on OpenGL. The native renderer pixel oracle passed on both backends. Natural workload comparisons below also support adoption. |

These are stage timings, not percentages of total game FPS. The tiny fan
benchmark is a geometry-construction benchmark; the 1,000-target benchmark
freezes shapes and bypasses gameplay capacity. Neither predicts fully simulated,
fully observed 1,000-target performance. Rejected implementations live only in
ignored diagnostics; they are not included in the exported game.

## Implementation and tradeoffs

The final target renderer supersedes the previous shared-run merging cache. It
no longer transforms/concatenates all vertices and resubmits all triangles every
render frame. Each target keeps a native RID, local triangles and Godot-derived
bounds. CPU still interpolates one transform per target; the renderer transforms
its vertices. Geometry publication invalidates only that target. Visibility,
ordering, reset interpolation, opaque boundaries and resource cleanup are covered
by the existing independent native pixel tests.

This increases retained light items (1 → 1,000 in the isolated fixture). The
`render_batch_count` diagnostic now counts those visible items, not GPU draw
calls. The 1,000-object correctness case still compares all pixels and geometry
load; it no longer pretends to exercise one global 32-bit-index batch because
indices are now local to each target. Draw-call tradeoffs were measured on both
supported backends rather than inferred from item counts.

Arrival marks use [RenderingServer's native polyline API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-canvas-item-add-polyline)
and a later flash RID, preserving the previous paint order. There are no new
scene children, custom shaders, separate render threads or engine patches.

## Measurements

Same machine: Ryzen 9 5950X, RTX 3060, NVIDIA 591.74, official Godot 4.7.2
`ed1daf0bf`, Mobile/Vulkan unless stated, 1152x648, vsync/FPS cap disabled. Tests
were sequential. Baselines were loaded from saved source snapshots in isolated
processes, without changing player persistence. Measurements use the console
editor runtime, not the standalone release engine.

### Candidate 4, submission isolation

1,000 common meteors, 205,000 vertices, 60 Hz pose-only motion; two-second warmup
and five-second sample. Geometry is frozen while positions move.

| Backend/run | Before CPU ms/frame | After CPU ms/frame | Before FPS | After FPS |
|---|---:|---:|---:|---:|
| Vulkan before → initial prototype | 6.782 | 2.234 | 92.40 | 132.73 |
| Vulkan refined prototype → before | 6.672 | 2.771 | 93.64 | 121.17 |
| OpenGL before → prototype | 7.656 | 2.777 | 47.19 | 48.87 |

OpenGL shows a substantial CPU saving but little FPS improvement; another stage
limits that workload. We do not infer increased GPU utilization from these data.
The refinement avoided redundant visibility/order updates; run variation exceeds
its small effect, so it is not claimed to explain the timing difference.
Logs: `build/candidate-pose-{before,after}.log`, `*-{before,after}-2.log` and
`build/candidate-pose-gl-{before,after}.log`.

### Natural late-game runs

The checked-in late-game probe used a read-only copy of the same save, all 95 + 42
research nodes, one noncompleting planet, fixed spawn seeds, 17 input samples/tick,
five-second warmup and 25-second sample. Every run sustained approximately 60 TPS
and reached 220 particles and 27–28 targets. Completion counts still vary: these
are matching workload configurations, not identical frame-by-frame replays.

| Order/state | FPS | p95 ms | p99 ms |
|---|---:|---:|---:|
| Original baseline, first run | 232.01 | 9.396 | 11.390 |
| Candidates 1 + 2 | 250.89 | 9.001 | 10.611 |
| Add candidate 4 prototype | 266.65 | 9.056 | 11.095 |
| Candidate 4 prototype repeat | 261.22 | 9.654 | 11.759 |
| Return to candidates 1 + 2 | 251.06 | 9.091 | 11.876 |
| Final integrated production code | 297.11 | 8.160 | 9.727 |
| Reverse check: original baseline restored | 244.63 | 9.231 | 11.170 |
| Final production repeat after validation/export | 293.65 | 8.458 | 10.056 |

The candidate-4 paired repeats support about a 4–6% FPS benefit in this workload,
while p95/p99 changes overlap. Final production runs averaged 295.38 FPS versus
238.32 for the original baseline runs (about 24% in this workload). This is not a
universal improvement estimate: the natural runs have different completion counts
and there is run-to-run variation. Stage savings are the more controlled evidence.
Logs: `build/candidate-natural-*.log`,
`build/candidate-pose-natural*.log`, `build/candidate-fan.log`, and
`build/candidate-markers-*.log`. Cursor rejection: `build/candidate-cursor.log`.

## Verification

`meteor_fan_cache_test.gd` retains the independent fan oracle and joins the fast
gate. `arrival_marks_render_test.gd` retains the pre-change effect drawing method
and runs with the real renderer. The existing meteor test keeps its independent
native rendering path and unchanged pixel tolerances. Vulkan/OpenGL meteor,
arrival mark, particle effect and background comparisons all passed (eight runs).
The complete validation/export result and reverse baseline are recorded below.

Validation `build/validation/20260911T163010306Z_6edb98e6/summary.json` passed
all 26 checks (25 fast gates plus Windows export). The native GPU counter test
also passed while compiling the sampler. `NightwatchArray.exe` and adjacent
`NightwatchMetrics.exe` were refreshed. The final isolated submission probe
reported 124.15 FPS, 2.694 ms/frame submission CPU and zero geometry uploads
during the moving sample (`build/candidate-submission-final.log`).
