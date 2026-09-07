# Maintenance verification — 2026-09-07

This pass preserves the current game flow, research conditions, prices, rewards,
module multipliers, controls, visual layout and version-1 save format. It repairs
failure handling and reduces repeated work. It is a focused audit of the recent
observation/research/module/save integration, not a claim that the entire project
has no defects.

## Findings and changes

| Finding | Implemented correction | Evidence |
|---|---|---|
| A ConfigFile read error was reported as an empty slot, permitting the new-game path for an occupied corrupt file | Distinguish missing files from invalid existing records; validate version, containers and known numeric fields before loading | Corrupt-file and malformed-payload regressions |
| Saving directly over the existing record could truncate it before a failure | Write and flush a sibling staging file with a process-specific name, then rename over the destination; keep the old summary on failure | Real Windows replacement plus injected staging-write/commit errors |
| Every module effect read rebuilt arrays and a combined dictionary | Cache by the two effective owned ids, checking both ids on every read | Explicit numeric tests, direct mutation/legacy-load invalidation, microbenchmark |
| Ordinary Data changes were forwarded as duplicate deep-sky changes | Emit dedicated changes only for unlock/record/equipment events; use the existing progression signal for balance updates | Visible balance regression; existing integration suite |
| Hidden panels rebuilt strings; static miniature geometry and M31 art were recomputed unnecessarily | Refresh hidden content when opened, cache base constellation geometry, invalidate M31 art on visual transitions | Seven before/after frames are pixel-identical |
| The validation runner's own fake executable still recognized only its older 12-gate suite | Add the current deep-sky and save-integrity gates and correct gate-order expectations | `VALIDATION_RUNNER_TEST_PASS: 80 checks` |
| Active documentation mixed the current 95-node + module path with retired 107-node content | Separate current and compatibility descriptions; move old renderer prose into history; repair links and update the document map | Local-link check plus manual comparison with current code |

## Measurement scope

Godot 4.7.2-stable `ed1daf0bf`, Windows. Timing is headless CPU work only;
image verification uses OpenGL Compatibility / NVIDIA RTX 3060, 1152×648.
No whole-game FPS or player-comfort improvement is asserted. CPU frequency and
background workload were not experimentally controlled.

The preceding feature/fix work was checkpointed as `ef2b180`, separately from
maintenance. Before-edit file copies and hashes are in
`build/cleanup-20260906-171522/before-sources.json`. The retained local comparison
script is `build/cleanup_bench.gd`; it loads the before-edit module script beside
the current implementation and reads speed/radius/target count 50,000 times each,
five samples per implementation. Both checksums are 1,500,000.

| 150,000 effect reads | Median | Five samples (microseconds) |
|---|---:|---|
| Before | 521.159 ms | 521159, 519504, 532981, 529540, 520172 |
| After | 61.067 ms | 61494, 61067, 60591, 60008, 65967 |

This specific computation takes about **88.3% less time (8.53× faster)**.
Logs: `build/cleanup-before-bench.log` and `build/cleanup-after-bench.log`.
The baseline-vs-baseline control run is in the former; the reported paired
before/after samples are in the latter. This is not an FPS multiplier.

## Visual invariants

Before: `build/deep_sky_review/1788682543/`.
After: `build/deep_sky_review/1788682867/`.
Both captures passed their stable-frame gates. PIL pixel comparisons found no
changed pixels in any of the seven frames; PNG hashes also match.

| Frame | Pixel comparison | After PNG SHA-256 |
|---|---|---|
| `en_chart_purchase.png` | 동일 | `e13a23c66a2ed548eb98f674f240cd3bd3e2c868c6da565fea6e4824d88565d7` |
| `en_module_popup.png` | 동일 | `bfbc1bdd0b393ded8908c0797f3e968d7bd4c76587d19ea497385c475ac29b64` |
| `ko_chart_locked.png` | 동일 | `f3480ea08b6d7178ad60dc130d82b7c37b78b14bf9fddddaa68d90850f29a6ff` |
| `ko_chart_purchase.png` | 동일 | `e12703162f5eb7674187032ad8db38e46c5cb660e679429c6e0d0f6293a26fd1` |
| `ko_module_popup.png` | 동일 | `ace1146fa8faf34bb56e97225d2541b77d80d03e6fd179e667cbf3ab386ccc62` |
| `ko_popup_over_chart.png` | 동일 | `ace1146fa8faf34bb56e97225d2541b77d80d03e6fd179e667cbf3ab386ccc62` |
| `ko_same_sky.png` | 동일 | `4c047b76f865989cd3dbdf4a321a679405402623865f02efe46ab84511340ced` |

## Validation and limits

The default runner now has 14 fast gates. `-FullEconomy` adds the legacy economy
gate, and `-Build` adds the Windows export. The save-integrity test uses unique
`build/` directories, never player saves. It covers exact preservation of prior
bytes and cached summaries after failed writes, successful replacement, stale
staging files, malformed records, detached reads and explicit reset.

The module regression preserves the original values and tests cache invalidation
for direct slot/ownership changes, duplicate slots and legacy load. Existing
live key/pointer, popup layering, pause recovery and round tests remain enabled.
The economy driver still measures the previous 107-node compatibility path; it
is not a complete playthrough of future M31 research. Atomic replacement is
verified at the file-operation level, not by destructive power-loss testing.

Historical research definitions and existing gameplay systems were not removed
as an optimization. Larger architecture splits remain outside this pass.

## Final run

`tools/validate.ps1 -FullEconomy -Build` passed all **16 checks** (14 fast gates,
legacy economy, Windows export). The authoritative summary is
`build/validation/20260907T055930080Z_f20df1c7/summary.json`.
The legacy economy gate passed in 112.733 seconds; this is test execution time,
not gameplay duration. The runner self-test passed 80 checks at
`build/validation/selftest_20260907T055856912Z_c26ec288/`.
README/docs local file links were checked with no missing targets. Export:
`build/windows/NightwatchArray.exe`.
