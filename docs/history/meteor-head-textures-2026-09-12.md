# Common/fast head texture trial — 2026-09-12

The user requested trying textures for the currently procedural common/fast
heads. Baseline: `efdf6e8`. No spawn, reward, timing, input, save, object-count or
worker changes are included.

## Representation

`tools/bake_meteor_heads.gd` calls the existing directional-head geometry and
captures 64 phases for each type. Its RGB output holds independent additive
glow, core and hotspot masks, not a fixed palette. The shared shader interpolates
adjacent cells; a quad and palette materials are reused across instances.
Each meteor holds one native child canvas RID with its own instance parameters.
The head is generated once during authoring, never rendered into a new image
per meteor during play. The source PNG is about 120 KiB; its 1024x2048 size is
8 MiB at RGBA8 residency, excluding engine overhead. No mipmaps are generated.

Runtime radius/pulse, direction, palette and fading remain live. The optical
shape is an approximation: a sampled 8π loop replaces the original unbounded
combination of sine phases, and the hotspot's tiny per-object irregularity uses
the bake's canonical phase. Tails still follow their original procedural path.
This is a limited common/fast trial, not conversion of fragments or larger bodies.

Regenerate with the README's Godot executable, a real Mobile/Vulkan renderer,
and `--path . --script res://tools/bake_meteor_heads.gd`, then import the PNG.
Keep the baked source and `.import` settings together. The bake preserves the
existing drawing functions as its authoring source; no generated-image service
or player persistence is involved.

## Measurements

Ryzen 9 5950X / RTX 3060 / Godot 4.7.2 console editor runtime, Mobile/Vulkan,
1152x648, VSync and FPS cap disabled. Runs are sequential. The natural fixture
uses 95+42 research flags, default module loadout, seeded natural spawning,
17 pointer samples/tick, a noncompleting planet, 5s warmup and 25s sample.

| Natural run order | Average FPS | p95 ms | p99 ms |
|---|---:|---:|---:|
| Before | 363.25 | 8.129 | 10.617 |
| Atlas | 324.22 | 9.143 | 12.288 |
| Atlas | 355.25 | 8.109 | 10.540 |
| Before | 314.62 | 8.830 | 11.192 |

The two means are 338.93 versus 339.73 FPS: no established whole-game FPS gain.
Every run peaks at 27 targets and 220 particles and sustains about 60 TPS.
Completion counts vary, so these are matched workloads, not identical replays.
Measured viewport GPU time is roughly 0.11ms; this is a viewport duration,
not utilization or a measurement of every driver/compositor cost.

The dedicated 1,000-head fixture excludes trails, actual motion/observation,
spawning and completion effects. It changes optical age at 60Hz, warms for 2s
and samples for 5s. Alternating procedural/atlas/atlas/procedural runs measured
33.59/8.65/8.75/34.12 microseconds per head draw callback, about 74% less CPU
preparation. Its overloaded procedural path does not sustain the requested
update cadence, so its FPS ratio is not a realistic game improvement estimate.
The final integrated head callback measured 7.51 microseconds in one repeat.
No claim of a large natural-game FPS improvement is made.

After tint/float16 fixes, natural repeats measured 467.50 FPS, followed by a
reverse pair of 488.64 procedural and 463.89 atlas. The reverse pair had 273
versus 300 completions. These results reinforce the lack of an established
natural-game FPS benefit; they must not be presented as a universal gain.

To separate the rendering change from different natural completion loads, the
existing `observation_performance_probe.gd` was copied into an ignored diagnostic
with only the per-meteor `textured_head_enabled` switch and disabled FPS/VSync
limits. Procedural/atlas/atlas/procedural runs each execute six 360-frame phases
after 60 warm-up frames. Counts, ages, input and replenishment are fixed.

| Fixed targets / action | Before mean ms | Atlas mean ms | Equivalent FPS change |
|---|---:|---:|---:|
| 18 / still | 3.65 | 3.45 | +6.0% |
| 18 / moving pointer | 3.60 | 3.41 | +5.8% |
| 18 / held observation | 3.97 | 3.66 | +8.5% |
| 32 / still | 6.16 | 5.66 | +8.9% |
| 32 / moving pointer | 6.40 | 5.94 | +7.7% |
| 32 / held observation | 6.87 | 6.00 | +14.4% |

Each held phase completed exactly 10 observations and 350 tracking frames in
every run; every fixture passed. This is still synthetic: it advances one
simulation tick per rendered frame and omits natural spawning/automation/audio.
The optimization is retained for the repeatable head CPU reduction and these
controlled full-scene improvements, not for a claimed natural-game speedup.
Logs: `build/head-texture-observation-{1-0,2-1,3-1,4-0}.log`;
summary: `build/head-texture-observation-summary.json`.

Logs are `build/head-texture-natural-{1-before,2-after,3-after,4-before}.log`
and `build/head-texture-isolated-{1-0,2-1,3-1,4-0}.log`. Final integrated repeats
use `build/head-texture-{natural,isolated}-final.log`.

## Visual and behavioral verification

`meteor_head_texture_test.gd` compares each head's light against the procedural
reference at three sizes, full/faded states and nine phases, including the loop
boundary. It checks inherited tint, self-modulation, palette/type changes and
retained-item reuse. The accepted energy range is 80–120% per isolated head;
this is an appearance check for an intentionally sampled image, not an exact
pixel oracle. `build/head-original.png` and `build/head-textured.png` show the
reference and new heads at phase 1.9; inspection shows the same cool directional
head/glow with slightly smoother raster edges.

The existing independent ribbon arithmetic checks and the renderer's strict
pixel tolerances are unchanged. The latter tests overlap, transforms, opaque
ordering, hiding, fades, deletion and 1,000 objects on Vulkan and OpenGL.
Atlas tests also run on both renderers. Signed type encoding protects the
common/fast boundary from OpenGL's float16 instance-data rounding.

Final validation `build/validation/20260912T085749887Z_4df7848d/summary.json`
passed all 25 fast gates and Windows export. The head appearance and existing
batch renderer tests passed separately on Vulkan and OpenGL (four GPU runs).
