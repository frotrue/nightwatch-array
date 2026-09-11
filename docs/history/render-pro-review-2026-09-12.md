# Rendering review — 2026-09-12

## Evidence identity

- Reviewer: **GPT-6 Pro**, code review template from the local
  `gpt-pro-code-review` skill. The live composer displayed **6 Pro**; the reasoning
  menu selected Pro at position 5/5. No fallback model was used.
- [Completed independent review](https://chatgpt.com/c/6aa41bf1-69b8-83ee-8611-aa1351d23b8c).
  It completed after 18m 19s. Only its final assistant review was extracted.
- Baseline: clean `f9c80576d97d5d4351ef38d061fa0f81ef3c3fad`.
- Archive: `nightwatch-rendering-gpt-pro-review-20260911T151531Z.zip`,
  814,838 bytes, 231 source/text files (2,528,234 uncompressed bytes).
- SHA-256: `ad079e60bc2ce50b8660dd60e6a472dde6023fc7088c464460e9b619c55184f7`.
- One sensitive-extension exclusion (CodeGraph database), 138 unsupported-type
  exclusions (including binary font/assets and import metadata), zero size-limit
  exclusions. Build outputs, runtime logs and screenshots were not attached.
- Pro inspected the rendering/tick/observation paths and related evidence; this
  was not an audit of every included file. Pro did not execute code, benchmark,
  capture GPU traces or perform pixel comparisons. Measurements below are Codex's.

## Independent recommendations and local disposition

| ID | Pro conclusion | Codex validation and disposition |
|---|---|---|
| F-001 | Unconditional cursor redraw defeats idle redraw caching. Low severity; not the likely cause of dense active observation slowdown. | **Confirmed** in `ObservationController._process`: an unconditional `queue_redraw()` follows conditional invalidation. Deferred from this rendering patch, as Pro recommended. Removing that line alone would miss render-cursor/button/radius/camera invalidation. FPS impact remains unmeasured. |
| P-001 | First measure pre-sized ribbon output buffers instead of repeated append. Preserve arithmetic and independently compare all bytes. | **Uncertain benefit; trial not adopted.** The first isolated 1,000-target trial measured tail construction at 68.0 us/target versus 65.2 us before. This does not establish a general regression or refute pre-sizing; it fails to establish the required improvement. Production `meteor.gd` is unchanged. |
| P-002 | Retain merged colors/topology across interpolation frames; invalidate for geometry publication, ordering, visibility, boundaries and index-offset changes. Keep CPU pose transform and current triangle submission first. | **Confirmed repeated work; implemented and measured.** The baseline isolated submission used 14.7 ms/frame. Cache retention removes redundant color/index merges and source-index comparisons when geometry/layout is unchanged. See the repeated measurements and limitations in `performance-probes.md`. |
| P-003 | Later compare GPU pose transforms while keeping CPU procedural geometry; do not rewrite the entire renderer first. | **Uncertain whole-game benefit; deferred.** A tiny RGBAF pose-texture triangle proof matched CPU pixels on both backends. It does not validate full-scene culling, upload cost or performance. No shader/engine change is included. |
| P-004 | If observation dominates, replace repeated tracked-array membership scans with a synchronized membership dictionary while preserving array order. | **Confirmed linear membership scan** in `_append_tracked_if_valid`; **uncertain performance priority** in natural play. Deferred; no observation/simulation behavior changed. |

Pro's preferred first patch was P-001, conditional on a measured improvement.
Codex's initial trial did not demonstrate it, while separate profiling established
substantial submission cost. The implemented patch therefore follows P-002.
These proposals are performance hypotheses, not five confirmed product defects.

## Implementation boundary

`MeteorRenderLayer` retains each contiguous additive run's merged colors and
indices. A dirty flag is set by geometry removal/publication, target removal and
child-order changes; visible-state changes are checked before any run is submitted.
Rebuilds are deliberately global for simplicity: any affected target invalidates
the merged data for all runs. Run arrays own their published data; scratch arrays
are replaced instead of clearing aliased PackedArrays stored in dictionaries.

Draw indices are sent only when changed. Interpolated positions are still updated
every render frame, and the complete triangle array is still submitted. This
patch does **not** reduce GPU upload bytes or claim increased GPU utilization.
Opaque order boundaries, native filament/scan arcs, shape/color arithmetic,
target counts, 60 Hz simulation and worker limits remain intact.

The real-renderer regression now covers cached pose updates, leading topology
changes, hide/show, opaque reordering/insertion/removal and retained-data cleanup,
in addition to the existing independent native renderer comparison. The separate
submission probe makes the controlled workload reproducible without player saves.

## Interpretation

GPU utilization alone cannot identify the limiting stage. This review found
avoidable CPU work, but substantial procedural redraw and full GPU submissions
remain. Natural late-game and deliberately over-capacity 1,000-target diagnostics
must not be conflated. In particular, the existing observed/unobserved stress
branches also differ in whether they run the game simulation; their FPS ratio is
not an isolated measurement of observation logic.

See [performance evidence](../performance-probes.md) for local A/B results and
[probe contracts](../probes.md) for required correctness checks. The external review
is a source-based second opinion; Codex owns implementation and verification.

## Local measurements

The review above identified redundant per-render-frame color/index merging
(P-002). The layer now
retains merged data until geometry, ordering or visibility changes. Vertex
interpolation and full triangle-array submission remain; GPU upload reduction
and increased GPU utilization are not claimed.

Baseline is `f9c80576d97d5d4351ef38d061fa0f81ef3c3fad`, not the older OpenGL
renderer. Same Ryzen 9 5950X / RTX 3060 / driver 591.74, official Godot 4.7.2
console runtime, Mobile/Vulkan, safe render thread, 1152x648, vsync/FPS limit off.
Runs were sequential. Baseline code was loaded into the same engine from the
captured revision, without changing game/settings/save files. These are editor
runtime measurements, not standalone release-EXE benchmarks.

### Submission-only diagnostic

`meteor_submission_performance_probe.gd` freezes local procedural geometry and
moves 1,000 common meteors at 60 Hz. It submits one run with 205,000 vertices.
Two seconds warmup, five seconds measurement; no game simulation, observation,
completion effects or natural spawning. Capacity is intentionally bypassed.

| Run | Before submission CPU ms/frame | After submission CPU ms/frame | Before FPS | After FPS |
|---|---:|---:|---:|---:|
| Initial diagnostic | 14.688 | 7.153 | 49.45 | 86.16 |
| Paired repeat, before then after | 13.408 | 6.745 | 54.63 | 91.81 |
| Paired repeat, after then before | 13.230 | 6.730 | 55.69 | 92.40 |

The repeated comparison reduces submission CPU cost by about **49–50%**. The
after samples rebuilt merged batch data zero times while positions continued
changing. Synthetic FPS improved because this isolates the optimized stage;
it is not a claim about 1,000 fully simulated/observed meteors.

Logs: `build/pro-submission-{before,cache}.log` and
`build/pro-cache-submission-{before,after}-{2,3}.log`.

### Natural late-game workload

The existing natural late-game probe used the same isolated read-only save copy,
all 95 + 42 research nodes, one forced noncompleting planet, seed streams from
the checked-in probe, 17 held-input samples/tick, five-second warmup and 25-second
sample. Paired order was before-1, after-1, after-2, before-2.

| Run | FPS | p95 ms | p99 ms | Peak targets | Completions | ticks/s |
|---|---:|---:|---:|---:|---:|---:|
| Before 1 | 195.62 | 10.823 | 13.694 | 27 | 334 | 59.994 |
| After 1 | 210.33 | 10.421 | 12.597 | 27 | 295 | 59.992 |
| After 2 | 201.62 | 10.535 | 12.602 | 27 | 306 | 59.982 |
| Before 2 | 219.00 | 10.198 | 12.828 | 28 | 299 | 59.979 |

Every run reached 220 particles. **No consistent whole-game FPS improvement is
established:** before averaged 207.31 FPS, after 205.97, within overlapping run
variation. Completion counts also vary despite seeded spawn streams, so these
are comparable natural workload runs, not identical frame-by-frame replays.
An earlier unpaired baseline was only 141.11 FPS (p95 15.147 ms); it is retained
in `build/pro-render-before.log` and not used to inflate the A/B improvement.
Paired logs: `build/pro-cache-natural-{before,after}-{1,2}.log`.

The optimization is retained for its reproducible submission-stage saving and
pixel-equivalent behavior. Natural play still spends time generating changing
procedural geometry, executing simulation/observation and submitting triangles.
A future GPU pose experiment must establish full-scene culling, precision and
frame-time benefits separately before replacing this path.

### Correctness

The real meteor comparison retains the same independent native path and pixel
tolerances, adding cached pose updates, changed leading topology, hide/show,
opaque reorder/insert/remove and cleanup checks. Neither procedural shape math
nor the independent ribbon oracle was changed. Vulkan and Compatibility results
are recorded in `build/pro-final-<backend>-<probe>.log` for meteor, effect and
background comparisons. Required aggregate and export results are recorded below.

All six real-renderer comparisons passed without engine/script errors. The
required validation run `build/validation/20260911T154728785Z_6e2d35d2/summary.json`
passed all 25 checks (24 fast gates and Windows export). This includes the
independent 539-case ribbon arithmetic oracle and cached gameplay getter checks.
The native GPU counter regression also passed during helper compilation.
`build/windows/NightwatchArray.exe` and its adjacent `NightwatchMetrics.exe` were
refreshed. The reproducible external-upload ZIP and sidecar manifest were removed
after completing the review; the signed-in ChatGPT review tab remains available.
