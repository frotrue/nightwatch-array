# GPT-6 Pro fixed-tick design review — 2026-09-11

- Explicit user request: use the gpt-pro-code-review skill with GPT-6 Pro, obtain
  the design, then implement the fixed 60 Hz / independent celestial spawning migration.
- ChatGPT browser model verified visually: `6 Pro`, reasoning picker `Pro`.
- [Review conversation](https://chatgpt.com/c/6aa3a5f0-dbb4-83e8-afb3-8d023251f571)
- Reviewed clean base: `fe3e69f22862f20a670ef1e0e1b298b1c8b096ca`.
- Bundle: `nightwatch-tick-design-gpt-pro-review-20260911T065403Z.zip`, 733438 bytes,
  198 included files, no files excluded for size.
- SHA-256: `32e428205a6a4a548d540a2f785d080a8c929003d8319e85aac46f7b38ee0e87`.
- Manifest reviewed before upload; `.codegraph/codegraph.db` and unsupported
  binary/import/font assets excluded. Source, tests, scene text and design docs included.
- Pro confirmed the bundle and delivered a complete response (35m 22s). This was
  a static design review, not a runtime or visual test. Local validation remains required.

## Local assessment of findings

| Pro ID | Assessment against the reviewed source | Treatment |
|---|---|---|
| F-001 | Confirmed. Weighted selection allocated 22.5% to the five late targets, reducing atmospheric share. | Independent per-kind rolls; common retains its own base chance. |
| F-002 | Confirmed. Game, spawner, targets, observer and contacts advanced in `_process`; manual continuity used render frame IDs; hitstop scaled the engine. | One physics driver, explicit stages, tick IDs, local hitstop. |
| F-003 | Confirmed. Pending contacts were removed before `spawn_meteor` could reject them at capacity. Reverse-array arrivals also favored later entries. | Bounded deferral, explicit cancellation, per-type rotation, partitioned object budget. |
| F-004 | Confirmed. Natural choice/interval/planning shared a stream with other work. | Per-type occurrence and entry streams with saved states. |

## Design decisions and adaptations

Adopted Pro D-001 through D-004: 60 Hz fixed clock, staged completion, timestamped
input, interpolation, independent Bernoulli probabilities and analytic calibration
of the existing research curve. All original research IDs and constellation markers remain.

Adopted D-005's 22/6/3/1 object partition, forecast deferral, bounded natural queues,
per-type fairness and atomic module pairs. Reused existing contact/event records
rather than replacing all triggered effects with a universal ticket framework.
Existing event timers and proc tags remain their source of truth.

D-006 preserves triggered content and moves clocks to fixed updates; rare specimen
opportunities receive their own probability stream. D-007 is implemented with
additive save fields and spawn-model versioning. An outer save-format version bump
is unnecessary because the legacy envelope remains readable and the new data is
optional. Unsupported future spawn-model versions are rejected before mutation.

D-008 supplies the validation criteria: rendering cadence independence, input
edge coverage, independent RNG replay, admission bounds, pause/end-of-round/save
behavior, existing regression gates and economy/performance comparisons.

Pre-change diagnostic evidence: seed 20260821/cheapest completed the 95 base nodes
at 1870.0 simulated active seconds using the old 0.05-second probe step. Windowed
observation performance at 32 objects/hold had p95 14.067 ms, mean 11.9865 ms.
These are probe measurements, not human completion time; the new economy driver
uses 1/60-second steps, so the comparison includes that methodological change.

Current implementation contract: [fixed-tick-simulation.md](../fixed-tick-simulation.md).

## Completion evidence

- Aggregate `tools/validate.ps1 -FullEconomy -Build` passed **24 checks**: 22 fast
  gates, the full economy gate and Windows export. Summary:
  `build/validation/20260911T075800574Z_02c1d13b/summary.json`.
- Economy: all three seeds (20260821, 20260837, 20260853), cheapest strategy,
  completed all 95 base nodes. Min/median/max active simulation times were
  **1630 / 1660 / 1720 seconds**. Seed 20260821 was 1720 seconds versus the
  previous single-seed 1870-second diagnostic (about 8% faster). Arrival gaps and
  manual/automatic ledgers passed the existing contracts. This is not human playtime.
- Windowed NVIDIA RTX 3060 / OpenGL: six 18/32-object synthetic samples passed.
  32/hold p95 **15.130 ms**, mean 13.286 ms, 10 manual completions. Previous
  p95 was 14.067 ms with 9 completions. The stress fixture deliberately retains
  32 meteor draws beyond the production atmospheric partition; it measures draw
  and observation load, not ordinary spawn density. The extra completion/particles
  also mean this is not a perfectly identical rendered workload.
- Rendered mixed-sky capture inspected: `build/tick-visual.png`; seven synthetic
  targets driven by the real physics loop, existing art/HUD composition intact.
  This is a visual sanity check, not a human playtest or proof of feel at every FPS.
- Export: `build/windows/NightwatchArray.exe`, 119922480 bytes,
  SHA-256 `8c2f83931fb0e04207760d841d457b1b9db9087e2ac768099e6253b6c881e5da`.

Follow-up balance work should use actual play feedback: independent additions
increase income and late-game density. No price/reward rebalance was applied to
hide this approved change.
