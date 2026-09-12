# HUD/effect optimization — 2026-09-12

Baseline: `60a9193f38db06078245e2daed87da446c38f342`, clean main.
Follow-up to the previously deferred F-04/F-06 in the
[GPT-6 Pro review](pro-optimization-followup-2026-09-12.md). This task did not
request another external review. Implementation and measurements were local.

## Adopted changes

- Stop polling the extension HUD on every observation frame. Existing research,
  load and locale notifications refresh it; phase entry/exit refreshes it as well.
  Overlay visibility still has independent updates. Do not format the permanently
  hidden HUD sample count; the module UI continues to show it.
- Share particle/popup damping coefficients per update. Skip empty collections.
  Integrator ordering, frame delta, expiry, packet delivery and effect counts
  are unchanged. An initial trial computed coefficients even with empty arrays;
  its slight idle regression was corrected before adoption.
- Add a reproducible dense render diagnostic, plus HUD regression coverage in
  the existing smoke gate. No production worker policy, simulation rate,
  target capacity, input, save or economy changes.

## Isolated timings

Windows host, Ryzen 9 5950X / RTX 3060, Godot 4.7.2 console editor runtime.
Sequential baseline/candidate/candidate/baseline, no simultaneous GPU/CPU jobs.
Headless function timings, not FPS or release-EXE performance.

| Workload | Baseline runs (us/call) | Candidate runs (us/call) |
|---|---|---|
| HUD clock updates | 7.791 / 7.969 | 0.805 / 0.814 |
| Empty effect update | 1.330 / 1.350 | 1.202 / 1.218 |
| 40 particles | 22.758 / 22.755 | 17.904 / 17.931 |
| 220 particles | 118.389 / 119.440 | 91.305 / 91.148 |

HUD polling cost fell about 90%; full 220-particle update cost fell about 23%.
The latter includes dictionary integration and queueing, not GPU rendering.
Absolute savings are small: about 0.007 ms per HUD call and 0.028 ms per
220-particle update. Do not translate those percentages into total FPS gains.

Reproduction: ignored `build/hud-effects-20260912/cpu_probe.gd`, log `cpu-final.log`.
HUD uses 60,000 clock calls at 300 calls per simulated second, cycling the same
60-second round. Effects use 20,000 calls at delta 0.001, persistent particles
with life 10,000 and initial velocity (20,-10), no popups; setup is untimed.
Original and current scripts load side by side from the recorded baseline.

## Natural full-game comparison

Mobile/Vulkan, 1152x648, VSync/cap off, Dummy audio driver with game sound code,
5-second warmup + 25-second sample. Existing corrected natural fixture, 17 raw
samples/tick, full research and the same five modules. Baseline/candidate/
candidate/baseline runs all completed 237 observations, peak 27 targets and 220
particles, approximately 60 TPS. No player save/settings persistence.

| Run | FPS | p95 ms | p99 ms |
|---|---:|---:|---:|
| Baseline 1 | 511.75 | 6.239 | 7.638 |
| Candidate 1 | 521.79 | 6.217 | 7.599 |
| Candidate 2 | 517.43 | 6.276 | 7.611 |
| Baseline 2 | 514.04 | 6.212 | 7.569 |

Mean FPS: 512.89 -> 519.61, about 1.3%. This small four-run difference does not
establish a large or universally noticeable improvement; p95 did not improve
consistently. Adoption rests on the repeatable isolated savings and preserved
behavior. Full deterministic gameplay traces were not repeated for these UI/
effect-only changes; equal workload counters are not a proof of identical state.

Logs: `natural-{before,after}-{1,2}.log` under the same ignored directory.
Baseline wrappers retain the old HUD/effect resources under their original
resource paths in memory before scene instantiation; no project checkout or
player data is rewritten. Dense runs also print actual loaded source hashes.

## Dense stress and remaining bottleneck

`tests/dense_render_performance_probe.gd` keeps 128/1,000 common/fast targets,
real movement and held observation. It bypasses normal capacity, lengthens life,
moves targets slowly to retain the grid, suppresses completion/expiry, natural
events and survey summons, and injects success visuals at most every 0.05 wall
seconds. Full base research, WIDE/SLOW/BURST modules, 17 input samples/tick.
It is intentionally different from normal play and from frozen-shape submission.

Final sequential baseline/candidate diagnostics (2s warmup + 6s sample):

| Targets | Baseline FPS | Candidate FPS | Candidate tick ms | Candidate meteor draw ms/frame |
|---|---:|---:|---:|---:|
| 128 | 6.39 | 6.46 | 5.85 | 93.92 |
| 1,000 | 0.739 | 0.737 | 49.10 | 854.43 |

No dense-workload improvement established. Count stayed exact; 116/255 targets
received manual observation. The 1,000-target run only delivered about 5.9 TPS
and four measured frames; p95/p99 are deliberately null below 100 samples.
This is evidence of severe overload, not a meaningful FPS improvement ratio or
a statement that normal gameplay runs at these speeds. Earlier exploratory
logs printed percentiles despite few frames; superseded by `dense-final-*.log`.

At 1,000 targets, motion and observer calls took about 18.13/16.13 ms per tick,
both included in the 49.10 ms total. `_draw()` wall time includes GDScript geometry
preparation and native rendering submissions; it is not GPU execution timing and
does not isolate driver waits. The 854 ms aggregate shows that regenerating/
submitting all dynamic meteor geometry is a more substantial next investigation
than HUD tuning. Do not extrapolate the previous frozen-geometry FPS result to
this actual simulation/redraw workload. No native/GPU rewrite was attempted here.

## Verification

- Existing smoke gate includes phase transitions, no per-frame/second polling,
  research notification, objective removal under an overlay, restored visibility
  and locale invalidation.
- Original/current effect dictionaries match exactly for 180 mixed-delta steps
  (0, 1/300, 1/60, 1/23), including expiry and eight ordered packet deliveries.
  Seed 12345, 16 seeded success effects, half anchored and half drifting.
- Five Vulkan HUD captures (observation, covered, restored, upgrade and Korean)
  are pixel-identical. Captured HUD preview inspected at original resolution.
  `hud-*-{before,after}.png` and diagnostic scripts/logs remain ignored in build.
- Validation `build/validation/20260912T143908883Z_ec81f2e8/summary.json`:
  all 25 fast gates plus Windows export passed. The Windows metrics helper
  built and its GPU-counter test passed as well.
- Background, meteor and effect GPU comparisons passed on both Vulkan and
  OpenGL (six checks), with their original pixel tolerances unchanged.
- `build/windows/NightwatchArray.exe` and adjacent metrics helper refreshed.
