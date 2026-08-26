# Observation Duration Ladder Baseline

> **Stale after the 2026-08-26 economy redesign.** This file preserves the old
> duration prices and prerequisite topology as historical evidence. The live
> graph's prices changed with the `×256` value curve, its success-count reveal
> gates were removed, and the fixed 1,080-second finale no longer exists. Use
> `full_tree_economy_test.gd` for current acceptance.

This is the deterministic engineering baseline for the 20 → 30 → 40 → 50 →
60-second observation ladder. It is scripted simulation, not player telemetry.
The historical `be11e42` evidence remains frozen in
`docs/legacy-density-be11e42.md` and is not an acceptance target for this tree.

## Measurement contract

- The round headline is total Data earned inside that round.
- `Data/min` is **realized productivity**: round Data multiplied by `60 / round
  duration`. It includes startup, round-boundary clearing, forecast cutoff, and
  shower-deferral efficiency. It is not a duration-invariant player skill score.
- Clean rounds compare realized productivity with the previous clean build.
  A round that changes systems does not replace that comparison baseline.
- Every round clears unfinished live objects and pending forecasts at zero.
  A meteor shower starts only when its warning and active phase fit before zero;
  otherwise its production cadence remains due for the next viable round.

## Topology and prices

| System | Future duration | Minimum prerequisites | Price |
|---|---:|---|---:|
| Observation Scheduling | 30s | Array Planning | 60 |
| Equipment Thermal Control | 40s | Wide Field Sensor | 180 |
| Extended Watch Protocol | 50s | Thermal Management + Trajectory Prediction | 280 |
| Continuous Watch Rotation | 60s | Extended Watch Protocol + Rare Meteor Detection | 380 |

Wide Field Sensor requires both Edge Detection and Observation Scheduling, so
20-second play cannot continue into the forecast layer. Thermal Management does
not repeat Observation Scheduling as a direct prerequisite: Wide Field already
implies that ordering and the tree renderer draws every direct edge.

The tree contains 21 systems. Twenty advance the pacing curve; Predictive Dish
Control remains interaction-only. The progression ratio therefore uses a
denominator of 20 and reaches exactly `1.0` at the completed tree. This is
topology normalization caused by the added pacing node, not a separate density
tune; compared with denominator 19 it reduces equivalent mid-tree density by
about five percent.

## Price evidence

The approved prices were measured at each node's minimum prerequisite build
using 10 deterministic seeds and 600 simulated seconds per cell at `0.05s`
steps. Marginal total is the extra Data produced by the longer post-purchase
round, including the node's pacing contribution.

| Step | Before → after rate | Before → after round total | Marginal total | Price | Payback |
|---|---:|---:|---:|---:|---:|
| 20 → 30 | 396.20 → 421.12 | 132.07 → 210.56 | 78.49 | 60 | 0.76 rounds |
| 30 → 40 | 594.04 → 629.22 | 297.02 → 419.48 | 122.46 | 180 | 1.47 rounds |
| 40 → 50 | 648.38 → 689.46 | 432.25 → 574.55 | 142.30 | 280 | 1.97 rounds |
| 50 → 60 | 877.98 → 922.80 | 731.65 → 922.80 | 191.15 | 380 | 1.99 rounds |

The first step is deliberately cheaper because it is a mandatory Wide Field
gate rather than an optional economic branch.

## Production-ladder re-baseline

Command:

```powershell
& 'Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/duration_ladder_probe.gd
```

The probe uses Godot `4.7.2-stable`, seed `20260821`, `0.05s` steps, 18 rounds
per stable build, production spawn/event logic, one scripted manual target at a
time, forecast-dish assignment when available, and production automation. Each
row owns the named duration node and only its minimum prerequisite build; the
last row owns all 21 systems.

| Stable build | Duration | Active minutes | Announced | Realized | Completed | Total Data | Data/min | Shower rounds |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Base | 20s | 6.0 | 0 | 172 | 167 | 2,338 | 389.67 | 0 |
| Observation Scheduling | 30s | 9.0 | 0 | 275 | 272 | 3,808 | 423.11 | 0 |
| Equipment Thermal Control | 40s | 12.0 | 384 | 402 | 402 | 7,438 | 619.83 | 0 |
| Extended Watch Protocol | 50s | 15.0 | 532 | 550 | 550 | 10,370 | 691.33 | 0 |
| Continuous Watch Rotation | 60s | 18.0 | 707 | 725 | 725 | 16,092 | 894.00 | 0 |
| Completed 21-system array | 60s | 18.0 | 666 | 1,062 | 1,059 | 75,077 | 4,170.94 | 18 |

No forecast contact remained pending at any cutoff and no shower crossed a
round boundary. Five base objects and three Observation Scheduling objects were
unfinished at zero and were cleared rather than leaking into the next sample;
all objects completed before zero in the three minimum-prerequisite forecast
rows. The completed array had three unfinished objects across 18 rounds.
