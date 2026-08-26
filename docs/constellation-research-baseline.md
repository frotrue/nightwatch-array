# Historical 41-System Constellation Research Baseline

> Frozen pre-Gemini snapshot. The live graph has 78 systems; the measurements
> below intentionally preserve the 41-system state they recorded.

Candidate measurement recorded 2026-08-24 for the constellation-grouped
research expansion. This does **not** replace
[`duration-ladder-baseline.md`](duration-ladder-baseline.md); that file remains
the historical 21-system / pacing-denominator-20 comparison point.

## Environment

- Godot `4.7.2-stable` (`ed1daf0bf`)
- Gameplay simulations: `0.05s` fixed steps
- Windowed render probes: `gl_compatibility`, 1152×648, NVIDIA RTX 3060,
  144.05Hz VSync
- Current graph: 41 systems, pacing denominator 40, total listed cost 7,569

## Required gates

| Gate | Result |
|---|---|
| Smoke | Pass |
| Layer 2 | Pass |
| Full-tree economy, seed `20260821` | discovery 250/550/850s; 41/41 at 850s; longest no-arrival 300s |
| Full-tree economy, seed `20260837` | discovery 250/550/790s; 41/41 at 790s; longest no-arrival 300s |
| Full-tree economy, seed `20260853` | discovery 310/550/850s; 41/41 at 850s; longest no-arrival 300s |

The economy acceptance criterion is deliberately one-sided: every deterministic
scripted-engaged watch must afford 41/41 before the 1,080-second final event.
There is no approved minimum completion time yet. The measured success curve
replaced the 8/20/40 discovery draft with 200/600/980, placing Perseus, Lyra,
and Andromeda near the 1/4, 1/2, and 3/4 points without changing prices.

## Duration-ladder comparison

The completed 41-system array produced 1,540 completed observations and 111,911
Data over 18 active minutes. The retained 21-system baseline recorded 1,059 and
75,077 respectively. That is +45.4% completions and +49.1% Data. The added
density and long-value target families therefore create real production rather
than extending the run by price alone.

The earlier 8/20/40 draft bought the whole graph in 220–250 seconds and left an
830–860 second no-arrival tail. Observation-paced discovery reduces the longest
no-arrival interval to 300 seconds and moves 41/41 to 790–850 seconds. Balance
watch: the remaining 230–290 second post-research tail has no approved failure
threshold. Do not solve it by silently inflating prices; approve a no-arrival
target or add later-run content before turning it into a failing gate.

An independent candidate audit measured 118,907 total earned Data against the
7,569 listed cost, with 111,338 still banked when the final node was purchased
(about 15.7 times the tree cost earned). This surplus remains a balance watch,
not authorization to inflate prices. Unlocks also still arrive in clusters: the
existing 21 nodes fill before the Perseus gate around 250 seconds, Lyra follows
around 550 seconds, Andromeda around 790–850 seconds, and the final 230–290
seconds add no new research. Later work should add arrivals or smooth discovery
if that tail becomes a problem.

## Workload and render checks

The completed-tree contact probe reported:

- no input: p95 7 live meteors, p95 combined contact/meteor workload 8;
- scripted engaged: p95 3 live meteors, p95 combined workload 6;
- regular progression remains capped at six active contacts; shower and fragment
  burst paths remain under the existing 32-instance hard ceiling.

The research chart now renders 41 interactive stars but preserves wheel-event
coalescing:

| Phase | Avg frame | p95 | Max | Input work avg / p95 | Layout passes |
|---|---:|---:|---:|---:|---:|
| Idle | 6.94ms | 6.99ms | 7.16ms | 0 / 0ms | 0 |
| 8 wheel events/frame | 6.97ms | 7.10ms | 14.05ms | 0.041 / 0.056ms | 431 / 431 frames |
| Tooltip motion | 6.94ms | 7.02ms | 7.20ms | 0.029 / 0.042ms | 0 |

The separate 18-object render stress held p95 at 6.99–7.00ms during the measured
stationary interval. These numbers are the comparison point for later research
chart or long-target visual changes.
