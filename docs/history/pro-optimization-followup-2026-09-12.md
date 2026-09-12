# Pro optimization follow-up — 2026-09-12

## Review identity and scope

- Reviewer: **GPT-6 Pro**, code-review template from `gpt-pro-code-review`.
  The live composer showed **6 Pro**, with reasoning **Pro, 5/5** and the
  latest model selected. No fallback model or delegated Codex agent was used.
- [Completed independent review](https://chatgpt.com/c/6aa51829-266c-83ee-8f71-9059987b4a70),
  22m 41s. Only the final assistant review was extracted; its IDs are retained below.
- Baseline: clean `2129b339385ea7d3bffbf61971fc9d5594716e06`.
- Archive `nightwatch-optimization-gpt-pro-review-20260912T091412Z.zip`:
  844,301 bytes; 243 source/document files, 2,592,770 uncompressed bytes.
- SHA-256: `ad87b9dcb98479a29d4add54bad1919d0f022bf21e5a176c940d21272a77722d`.
  One sensitive-extension exclusion (CodeGraph database), 149 unsupported asset,
  import/UID/font/translation exclusions, zero size-limit exclusions. Source,
  shaders, scenes and tests were included; PNG assets and raw build logs were not.
  The manifest was inspected before the user-authorized ChatGPT upload.
- Pro inspected relevant code and contracts, not every file equally. It did not
  execute the game or independently benchmark/capture it. All measurements and
  local dispositions below are Codex's, not Pro's measured results.

## Findings and disposition

| ID | Pro finding | Local verification and disposition |
|---|---|---|
| F-01 | Submission probe still requires 205,000 vertices after atlas heads left the triangle stream. | **Confirmed and fixed.** Reproduced 150,000 correct tail vertices with a false FAIL. Both head modes are now explicit; the first draw precedes motion. The independent workload is 25 stations × 6 vertices × 1,000, plus 55 head vertices each in procedural mode. Zero post-warmup geometry uploads is now required. |
| F-02 | Late-game seeding occurs after the initial forecast; anomaly RNG is omitted; counts include warmup but FPS does not. | **Confirmed and fixed in diagnostics only.** Normalize transient sky, seed before phase start, set anomaly scheduler seed, and align counters with the sample. Optional trace hashes target state, gameplay RNG and meteor spawn/contact/completion order for 1,200 ticks. No production spawning/save rules changed. |
| F-03 | One station-weight cache thrashes as N/N+1 alternate. | **Confirmed, measured and adopted.** Keep two immutable Float64 arrays, swapping on a hit. A miss replaces an array instead of mutating the other slot. Tail coordinates, head-sample threshold, sampling cadence, strip indices and filament math are unchanged. |
| F-04 | Hidden extension HUD refreshes on every observation frame. | **Confirmed** in `HUD.set_observation_phase`; **deferred/unmeasured**. Existing research/language/overlay invalidation needs its own checks. No blanket UI throttling was added. |
| F-05 | Unconditional cursor redraw defeats idle caching. | **Confirmed, deferred.** It is not a double draw, and removing only the final request would miss display-coordinate/input invalidation. The equipped overcharge module keeps the normal late-game cursor animated anyway. |
| F-06 | Particle/popup damping repeats the same pow per loop item. | **Confirmed, deferred/unmeasured** in `EffectsLayer._process/_update_popups`. No claim of meaningful whole-game impact from static inspection. |
| P-01 | Keep planet surface in an ArrayMesh and modulate opacity at draw time. | **Trial rejected.** Same triangles/order and cached colors, but Vulkan overlap differed in 9,025 channels (max 1), exceeding the existing 1,500-channel gate. Kept the original triangle submission; did not relax tolerances or proceed to a performance claim. |
| P-02 | Small contact batches may not amortize worker dispatch. | **No production change.** In the corrected 17-input natural fixture, serial batching was slower at preparation; disabling batching showed only a small single-run FPS difference. No repeatable cross-workload benefit was established. |

Pro correctly noted that GPU vertex transforms already exist. The additional
Codex experiment below removes *GDScript pose interpolation and per-frame layer
bookkeeping*, not a newly invented GPU transform or a rewrite of the renderer.

## Native parent interpolation

The layer retains the same local triangles, but each light RID is now a native
child of its meteor, behind that meteor's commands. Godot owns inherited pose,
interpolation/reset, visibility and sibling paint order. The layer reconciles
geometry on publication and counts on child/visibility changes, returning early
on unchanged frames. Pose changes do not resubmit triangles or scan the layer.
No extra scene nodes, lower redraw frequency, reduced effect/target counts,
new controls, economy/save changes, or additional workers were introduced.

Godot documents [CanvasItem parent transforms and drawing order](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html).
The planet trial used its documented `draw_mesh` modulation API, but API support
alone did not establish pixel equivalence; the local gate rejected that trial.

## Controlled stage measurements

Ryzen 9 5950X, RTX 3060, Godot 4.7.2 console editor runtime, Mobile/Vulkan,
1152×648, VSync/FPS cap off. GPU runs were sequential. These are not release-EXE
benchmarks and do not establish GPU utilization improvements.

**F-03:** 6,000 alternating 28/29-station tail preparations per run, old/new/new/old.
Identical station sum 171,000 and unchanged independent packed-array checks.
Old 77.27/76.63 us per tail; new 65.44/65.51 us, about **15% less tail preparation**.
This deliberately exercises mature tails; short/growing tails can benefit less.
The new cache regression verifies two builds followed by hits, shrink/eviction,
and exact preserved bytes. Existing 539 ribbon cases and 264 getter mutations pass.

**Native interpolation prototype:** 1,000 frozen-shape atlas meteors moving at
60Hz, 150,000 retained tail vertices, two-second warmup/five-second sample.
Old/new/new/old measured:

| Version | Submission CPU ms/frame | FPS | Post-warmup geometry uploads |
|---|---:|---:|---:|
| Old | 2.786 | 90.43 | 0 |
| Native prototype | 0.0051 | 127.11 | 0 |
| Native refined prototype | 0.0044 | 138.96 | 0 |
| Old reverse | 2.702 | 93.23 | 0 |

This isolates pose submission: geometry is frozen and actual spawning,
observation and completion are absent. It is not 1,000 simulated late-game FPS.
The near-zero script callback is expected when no geometry/layout is dirty;
the engine still renders and interpolates the objects.

## Natural workload and measurement limits

Pre-correction exploratory runs (old 402.79/397.62 FPS, native 437.15/421.94)
had different completion counts and the F-02 problems. They are **not** an accepted
whole-game gain estimate. Raw logs remain under ignored `build/pro-optimization-20260912/`.

After fixing the fixture, two renderer variants produced the same first-1,200-tick
trace `e102418360f81a95d75f2782c0b47c79bb99a307bdda1ea4dece5f9a53dc498f`.
Both measured 237 completions, peak 27 meteors and 220 particles, about 60 TPS.
The hash covers the recorded gameplay fields/events, not audio, effect trajectories,
every save field or a proof for all inputs. Trace runs are excluded from FPS A/B.

The final performance comparison uses corrected seeding/count boundaries with
trace disabled, current atlas baseline, unchanged research/modules/input and a
noncompleting planet. It retains natural render-frame effects; identical gameplay
does not force identical frame-by-frame particle positions or draw-call samples.

Corrected old/new/new/old (trace disabled):

| Version | FPS | p95 ms | p99 ms | Completions |
|---|---:|---:|---:|---:|
| Atlas baseline | 473.97 | 6.720 | 8.116 | 237 |
| Native interpolation + two-entry weights | 476.51 | 6.663 | 8.087 | 237 |
| Same candidate, repeat | 494.94 | 6.458 | 7.821 | 237 |
| Baseline reverse | 484.82 | 6.566 | 7.829 | 237 |

Means are 479.39 vs 485.73 FPS, about 1.3%, smaller than run variation.
**No established whole-game FPS gain is claimed.** Adoption is based on the
repeatable isolated CPU reductions and preserved behavior/pixels. This work
does not claim the earlier 1,000-object rendering FPS ratio for natural play.

P-02 exploratory single runs on the same corrected natural fixture:

| Contact mode | Mean batch preparation us/tick | FPS | p95 / p99 ms |
|---|---:|---:|---:|
| Current three workers + main | 258.64 | 502.58 | 6.331 / 7.770 |
| Same batch, worker_limit=0 | 379.41 | 499.00 | 6.504 / 8.102 |
| parallel_contacts_enabled=false | 1.66 | 509.22 | 6.565 / 7.938 |

All completed 237 observations at about 60 TPS. The direct path's 1.66 us
only means batch preparation was skipped: contact work moves into later direct
queries, so it is not the total contact CPU cost. Its small FPS lead and worse
p95 do not justify changing thresholds. The broader target/input/linear-mode
matrix remains unmeasured; the main-plus-three-worker contract is unchanged.

Logs: `tail-cache-bench.log`, `submission-{before,native}*.log`,
`controlled-{before,after}-{1,2}.log`, `seed-audit-{a,b}.log`, and
`contact-{parallel,serial,direct}.log` under `build/pro-optimization-20260912/`.
Submission/natural workloads live in the checked-in probes; local A/B wrappers
replaced only the baseline meteor/layer scripts in memory from the recorded Git
revision. The ignored tail microbench uses 28 samples at `(-2*i, 0)`, alternates
the head's x between 0 and 0.75, and calls `_draw_tapered_trail(1, 1, 1)` after
clearing its deferred triangle batch 6,000 times. It never renders or observes a
full game. Diagnostics never checked out over user files or wrote player saves.

## Verification

The independent meteor pixel oracle retains its original thresholds on both
renderers. Added checks cover rotation/nonuniform scale, interpolation disabled
and restored, no bookkeeping on idle/pose-only frames, plus existing opaque
ordering, hiding, moving, resets, fades, pauses, deletion and 1,000 objects.
Performance gains are attributed only to the stage/workload actually measured.

Final checks:

- Validation `build/validation/20260912T095435526Z_7d184725/summary.json`:
  all 25 fast gates plus Windows export passed. The native metrics helper also
  built and its GPU-counter test passed.
- Background, meteor and effect pixel checks passed on Vulkan and OpenGL (six
  runs). The final overlap is identical on Vulkan; OpenGL differs in five color
  channels by one level. Saved reference/candidate images were inspected at
  original resolution; the same bodies, trails and ordering are visible.
- Submission probes passed in atlas and procedural mode with exactly
  150,000/205,000 vertices and zero geometry uploads. Final atlas callback
  measured 0.0031 ms/frame; this is a later verification, not another paired gain.
- `build/windows/NightwatchArray.exe` and adjacent `NightwatchMetrics.exe` refreshed.
  Required tests were not weakened; the rejected mesh prototype remains only in
  ignored diagnostics. No physics rate, rewards, controls or save format changed.

The reproducible review ZIP/sidecar manifest were removed after the workflow;
their identity and exclusions are preserved above. The completed ChatGPT tab is
kept as a deliverable. Unmeasured F-04/F-05/F-06 and broader P-02 cases remain
future candidates, not claims that the entire game has been fully optimized.
