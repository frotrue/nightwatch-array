# Spawn-limit review — 2026-09-13

Baseline: clean main `4efd84bfecf1e56a76ccda415e65cc96649ed183`.
The user reported missing fragment splits, then asked to review and remove
unnecessary admission limits. The preceding reproduction showed 3/2/1/0 pieces
at 1/20/21/22 occupied atmospheric slots, for both terminal splitting and early
observation completion. The attempted split was consumed even when no piece fit.

## Decision

| Rule | Disposition |
|---|---|
| Shared 22-slot atmospheric ceiling, including fragments and linger | Removed. This silently truncated splits and rejected module pairs in ordinary dense play. |
| Live fragment pieces counted when admitting new natural targets | Retained after a rejected trial. An active fragment cloud slows fresh arrivals, but this rule never rejects a triggered split. |
| Natural atmospheric research limit, 4–18 active targets | Retained. Research remains meaningful; changing proc admission does not imply unbounded natural arrivals. |
| Five late-kind reservations + one shared extra, at most two per kind | Retained. Protects each unlocked kind from being displaced by another kind. |
| Three specimen slots and one major slot | Retained. Independent content/event reservations. |
| Bounded forecasts and two-second admission deferral | Retained. Prevents stale announcements and unbounded queues. |
| Emergency bound including proc children and fading objects | 54 atmospheric + 6 late + 3 specimens + 1 major = 64 total. |

The emergency ceiling provides 32 more atmospheric positions than the previous
bound without consuming late/event reservations. It is not a normal target count
or a promise that 64 fully active objects run at a particular frame rate. At this
last-resort ceiling, ordinary bursts still use available slots and module bursts
still require both slots. Their probability, speed, value, lifetime and one-shot
rules are unchanged. No delayed splitting queue or target eviction was introduced.

Changing admission can increase actual completions/income; it does not alter the
per-tick occurrence probabilities, research costs, reward formulas or save format.
The 18/32-object frame-pacing fixture was decoupled from `MAX_TOTAL_METEORS` so an
increased production safety ceiling does not silently change its major workload.

## Validation and measurement

Fixed-tick regression exercises terminal/early-completion splitting with 20/21/22
occupied positions, requires all three pieces and no duplicate split, checks that
natural throttling during a fragment cloud does not reject triggered fragments,
and checks emergency saturation including linger. Integration tests cover a full
module pair at the former 22-slot boundary and rejection of a partial pair at the
final safety ceiling. Existing late/major reservation and forecast deferral tests
now fill the actual safety budget rather than the removed 22-slot rule.

Logs and read-only baseline copies are in ignored `build/spawn-limits-20260913/`.
The initial baseline resource-cache wrapper could not resolve the removed
constant and was rejected before collecting results. The corrected wrapper
compiles the original spawner with a direct preload of the original policy, then
substitutes only that resource in memory before creating the game. It neither
checks out project files nor accesses player persistence.

## Rejected trial

Raising the safety budget and removing fragments from the natural active-target
count were initially tried together. On the natural late-game fixture the combined
trial increased completions from 237 to 477 and peak
meteor count from 27 to 58. Baseline/candidate/candidate/baseline Vulkan runs
measured 240.75/174.84/159.64/267.82 FPS. Candidate p95 was 17.79/29.05 ms,
versus baseline 12.09/10.77 ms. These runs do not share an identical gameplay
workload: the added admissions are the source of the extra work and income.

The active-count removal was rejected to retain the existing arrival throttle.
The final implementation keeps the original natural active-target accounting
and removes only the shared 22-slot hard cutoff. It still completed 474
observations: most of the workload increase comes from admitting formerly blocked
proc children, not from excluding them from the active count. Do not attribute
the combined trial's FPS loss solely to active-count exclusion. No economy
tuning was used to conceal the extra observations.

## Final workload evidence

Windows / Ryzen 9 5950X / RTX 3060, Godot 4.7.2 editor console runtime,
Mobile/Vulkan, 1152x648, VSync/cap off, Dummy audio driver. The real-renderer
late-game probe uses full research, 17 raw input samples per tick, 5s warmup and
25s sample. GPU runs were sequential and isolated from player persistence.

| Workload | Version/run | Completions | Peak meteors | FPS | p95 / p99 ms |
|---|---|---:|---:|---:|---|
| Standard five modules | Baseline 1 | 237 | 27 | 240.75 | 12.090 / 15.068 |
| Standard five modules | Baseline 2 | 237 | 27 | 267.82 | 10.769 / 15.343 |
| Standard five modules | Final 1 | 474 | 58 | 291.01 | 13.311 / 18.729 |
| Standard five modules | Final 2 | 474 | 58 | 310.07 | 13.350 / 18.840 |
| Four focus + slow (100% split chance) | Baseline | 208 | 28 | 355.50 | 7.970 / 10.568 |
| Four focus + slow (100% split chance) | Final | 339 | 60 | 263.39 | 14.984 / 22.399 |

All six runs maintained approximately 60 TPS and completed the workload checks.
The changing baseline FPS and different target/completion counts prohibit a
performance-gain claim. In particular the stronger split workload is more
expensive after admission is restored. Longer p95/p99 times are a material cost
of the extra visible work; this change is a functional admission adjustment,
not an optimization. These synthetic full-research/module builds are not all
playthroughs or release-EXE measurements. No GPU-utilization claim is made.

The observed 58–60 meteors include non-atmospheric kinds. Dense late builds can
reach the atmospheric safety budget; the final emergency guard is not reserved
exclusively for impossible states. A guaranteed unlimited split is explicitly
not promised. All-piece regressions cover the reported former 20–22 boundary;
partial/rejected spawning remains possible at the final ceiling. Natural RNG
probabilities and per-object rewards are unchanged, but more admitted fragments
mean more collectible rewards and can change progression timing.

Logs: `natural-before-{1,2}.log`, rejected `natural-after-{1,2}.log`,
`final-{1,2}.log`, `split-{before,after}.log`. The split stress script is a copy of
the checked-in natural probe changing only its module list to four `focus` plus
`capture_hold`; its baseline wrapper uses the original spawner/policy as above.

## Final gates

`build/validation/20260912T163529374Z_a4c8381a/summary.json`: **27 checks passed**,
including all 25 fast gates, full-tree economy (162.644 seconds wall time), and
Windows export. The native metrics helper and GPU-counter unit check passed.
`build/windows/NightwatchArray.exe` and its adjacent metrics helper were refreshed.

An initial integration run still asserted the retired 22/32 budget. Its fixture
now fills the final atmospheric ceiling and additionally admits every late kind,
the shared late extra, specimens and a major target, protecting reservations
and the combined safety budget. The targeted integration rerun and final complete
validation both passed. No progression/reward assertions or test tolerances were
weakened. Rendering implementation is unchanged; the real-renderer admission
workloads above supplement the required gameplay/economy checks.
