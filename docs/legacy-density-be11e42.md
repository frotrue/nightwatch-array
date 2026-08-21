# Legacy density baseline — `be11e42`

> **Retired evidence.** This document describes the game at source commit
> `be11e4269b77c6cc3cf2a85c2f3b8309c7827255` before the visible-growth density
> ramp. These values are preserved so the old game remains interpretable. They
> are **not acceptance criteria** for later density, capacity, completion, data,
> forced-choice, or pacing work and must not be quoted as if they describe the
> current game after that ramp lands.

## Manifest

| Field | Frozen value |
|---|---|
| Source commit | `be11e4269b77c6cc3cf2a85c2f3b8309c7827255` |
| Engine | Godot `4.7.2-stable` official, hash `ed1daf0bf001b61586d9930840f2f1394092c079` |
| Contact probe | 50 deterministic seeds, inclusive `20260821..20260870` |
| Phase | 30.0 seconds, simulated at 0.05-second steps |
| Pacing renderer | `gl_compatibility`, headless CPU run |
| Pacing viewport | `1152 × 648` |
| Regular spawn interval | Uniform `1.6..2.4` seconds before progression scaling |
| Legacy interval floor | `1.15` seconds |
| Regular active cap | `4` base, `5` with Array Planning, `6` with Multi-Target Analysis |
| Burst hard cap | `MAX_TOTAL_METEORS = 32` (31 non-major slots plus the reserved major slot) |

The historical `p50_visible` and `p95_visible` columns counted only pending
forecast contacts (`sky_contacts.contacts.size()`), not meteors. The probe now
preserves that historical series while also recording:

- **live meteors** — children for which `can_be_tracked()` is true;
- **on-screen workload** — pending forecast contacts plus live meteors.

The percentile entries below are the mean of each seed's 30-second percentile,
not a percentile pooled across seeds. Counts and data are totals over all 50
seeds, with per-seed means alongside them.

## Exact configurations

### Literal start

`legacy-start` owns no upgrades. `no-input` does nothing. `baseline-engaged`
manually tracks the first uncovered meteor and deliberately does not add hidden
forecast or commitment research just to drive the probe.

### Literal completed tree

`legacy-end` owns exactly these 20 nodes:

`better_lens`, `long_exposure`, `observation_streak`,
`precision_multiplier`, `perfect_observation`, `edge_detection`, `wide_field`,
`trajectory`, `rare_detection`, `fragment_analysis`, `shower_detector`,
`array_planning`, `observation_scheduling`, `thermal_management`,
`extended_watch_protocol`, `secondary_camera`, `predictive_dish_control`,
`multi_target_analysis`, `automated_tracking`, `observatory_network`.

The engaged driver commits forecast contacts whenever a dish is free and
manually tracks the first uncovered live meteor.

### Dish-control comparison

All four rows own `edge_detection`, `wide_field`, `trajectory`,
`array_planning`, and `secondary_camera`. Predictive rows additionally own
`predictive_dish_control`. Two-dish rows add a controlled second dish directly;
no other capability, lane, density, or type mix differs inside each one-vs-two
comparison.

### Full-delegation forced choice

This row owns `edge_detection`, `wide_field`, `trajectory`,
`fragment_analysis`, `array_planning`, `secondary_camera`, and
`predictive_dish_control`; it has two controlled dishes, zero support lanes,
zero manual input, and assigns every dish-eligible forecast contact whenever a
dish is free.

## Start and completed-tree workload

| Configuration | Forecast p50 / p95 | Live meteor p50 / p95 | Workload p50 / p95 | Realized | Completed | Data |
|---|---:|---:|---:|---:|---:|---:|
| Start, no input | 0.00 / 0.00 | 2.00 / 3.00 | 2.00 / 3.00 | 715 (14.30/seed) | 0 | 0 |
| Start, engaged | 0.00 / 0.00 | 0.00 / 1.00 | 0.00 / 1.00 | 715 (14.30/seed) | 702 (14.04/seed) | 9,828 (196.56/seed) |
| Completed tree, no input | 2.82 / 4.00 | 2.00 / 4.28 | 4.92 / 6.48 | 1,083 (21.66/seed) | 913 (18.26/seed) | 11,650 (233.00/seed) |
| Completed tree, engaged | 3.00 / 4.00 | 0.68 / 1.00 | 4.00 / 4.98 | 1,100 (22.00/seed) | 1,095 (21.90/seed) | 81,416 (1,628.32/seed) |

The start/no-input live-meteor p95 was exactly 3 in every seed. The completed
tree/no-input live-meteor p95 ranged from 2 to 7 and averaged 4.28; its workload
p95 ranged from 6 to 8 and averaged 6.48. Therefore the older room shorthand
“simultaneous visible objects are p95 3 at both ends” was not supported by the
old forecast-contact column and is retired with the rest of this evidence.

## Manual placement and researched commitment

`Eligible` means fast forecast contacts in these controlled rows. A manual
placement action cannot be refused, so its success/unassigned fields are not
comparable to predictive reservation, which can be refused while all dishes
are committed.

| Control tier | Eligible | Successful action | Unassigned | Dish-only completions | Mean dish busy fraction | All opportunistic acquisitions | Placement-attributable acquisitions |
|---|---:|---:|---:|---:|---:|---:|---:|
| Manual, 1 dish | 330 | 330 moves | 0 | 110 | 0.509 | 214 | 196 |
| Manual, 2 dishes | 335 | 335 moves | 0 | 302 | 0.416 / 0.440 | 420 | 328 |
| Predictive, 1 dish | 332 | 143 reservations | 189 | 188 | 0.764 | 112 | 0 |
| Predictive, 2 dishes | 335 | 244 reservations | 91 | 341 | 0.663 / 0.700 | 190 | 0 |

Type attribution, ordered `common / fast / fragment / fragment_piece / fireball / major`:

| Control tier | Dish-only completions by type | All opportunistic acquisitions by type | Placement-attributable acquisitions by type |
|---|---|---|---|
| Manual, 1 dish | `42 / 68 / 0 / 0 / 0 / 0` | `83 / 131 / 0 / 0 / 0 / 0` | `65 / 131 / 0 / 0 / 0 / 0` |
| Manual, 2 dishes | `138 / 164 / 0 / 0 / 0 / 0` | `199 / 221 / 0 / 0 / 0 / 0` | `114 / 214 / 0 / 0 / 0 / 0` |
| Predictive, 1 dish | `45 / 143 / 0 / 0 / 0 / 0` | `81 / 31 / 0 / 0 / 0 / 0` | `0 / 0 / 0 / 0 / 0 / 0` |
| Predictive, 2 dishes | `105 / 236 / 0 / 0 / 0 / 0` | `160 / 30 / 0 / 0 / 0 / 0` | `0 / 0 / 0 / 0 / 0 / 0` |

## Forced choice

The originally quoted result was **26 of 63 eligible contacts (41.3%)** across
five seeds in the full-delegation configuration above. The 50-seed freeze
measured **245 of 599 (40.9%)** announced while both dishes were already busy;
those 245 were unassigned by the perfect immediate assigner. This percentage
describes that zero-lane, zero-manual, all-eligible policy only. It is now a
retired description, not a capacity target.

## Eighteen-object pacing

The legacy stress fixture paused regular spawns, created 18 long-lived meteors
(common, fragment, and fireball), and prefilled every trail to its maximum. A
six-second headless run at `1152 × 648` on `gl_compatibility` reported per-second
p95 frame times of `6.93`, `6.92`, `6.92`, `6.93`, and `6.93` ms with no 1.5×
spikes. Because headless reported zero draw calls and primitives, this is CPU
simulation evidence only and does not establish a real Windows GL renderer
ceiling.

## Reproduction

Run one contact seed:

```powershell
$env:NIGHTWATCH_CONTACT_PROBE_SEED = '20260821'
& 'Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/contact_density_probe.gd
Remove-Item Env:NIGHTWATCH_CONTACT_PROBE_SEED
```

Run the 18-object CPU fixture:

```powershell
$env:NIGHTWATCH_PROBE_SECONDS = '6'
& 'Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/frame_pacing_probe.gd
Remove-Item Env:NIGHTWATCH_PROBE_SECONDS
```

The seed range, exact node sets, balance constants, instrumentation definitions,
and source revision above are part of the evidence. Changing any of them creates
a different baseline.
