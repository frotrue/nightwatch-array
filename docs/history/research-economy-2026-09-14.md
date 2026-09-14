# Research economy tuning — 2026-09-14

This is the first price/reward pass toward usually buying one or two research
nodes per round. The user approved all 95 base and 55 outer nodes, clean prices
and reward increments, occasional larger/smaller purchase counts, and no target
for total game length. This pass does not redesign research effects or paths.

## Changes

- Adjusted 78 base and 53 paid outer prices; the other 17 base prices and two
  free outer entries retain their values. Every changed price has at most two
  significant decimal digits. The full base price comparison is in the evidence.
- Six midgame global multipliers change from ×2 to ×1.5:
  `taurus_full_gallop`, `double_star_resolution`, `perseid_outburst`,
  `echo_delay_line`, `galaxy_imaging`, and `fireball_tail`.
- `draco_apotheosis` changes from ×8 to ×4. Opening ×2 rewards and
  `draco_synthesis` ×4 remain. The unconditional final base reward product is
  ×729; target-specific and outer modifiers apply separately.
- Midgame prices rise to spread purchases out. Late base and outer prices fall
  alongside the lower accumulated income multiplier. For example, Echo Delay
  Line changes from 22K/×2 to 60K/×1.5, Galactic Reference Frame from 400M to
  50M, and module-slot research from 240/360/480M to 45/60/80M.
- IDs, prerequisites, geometry, observation duration, spawning, nonmonetary
  effects, module draw rules, and player save format are unchanged. Owned
  research uses current rewards on load; prior spending is not refunded.

## Method and intermediate evidence

The matched baseline uses source commit `d2b741c`, Godot 4.7.2 stable, Windows
headless, seed 42, and the simulator's `cheapest` strategy. The adapter observes
eligible targets at probability 0.7, fragments at 1.0, and quality 0.75, with
real automatic equipment, rewards, events, purchases, draws, and equipment
transactions. Purchases are unlimited (`purchase_limit=0`).

A first candidate resumed the baseline's 15-base-node checkpoint in `branch`
mode. It completed all 150 nodes in 123 rounds, with 106/123 rounds buying one
or two nodes and a maximum batch of three. Its later base segment had seven
empty purchase rounds, so late prices were reduced before fresh verification.
This checkpoint run retains its old opening history and is not a fresh-game
comparison.

The next candidate failed the independent real-observation driver's existing
120-second new-research availability contract: Canis entry caused gaps of
180/240/180 seconds across its three seeds. Lower Canis entry prices reduced
those gaps to 120/180/120 seconds. Long Leash was then reduced from 250K to 180K
for the final pass. The contract, research graph, and observation rules were kept.
The intermediate 250K version's completed cheapest run reached 150 nodes in 114
rounds (84.2% one/two, maximum four). Interrupted intermediate simulations are
excluded from the final results below.

## Fresh final simulations

| Version / strategy / seed | Rounds | 1–2 purchases | 3+ purchases | No purchase | Maximum batch | Active seconds |
|---|---:|---:|---:|---:|---:|---:|
| Before / cheapest / 42 | 70 | 45/70 (64.3%) | 19/70 (27.1%) | 6 | 8 | 3,600 |
| Final / cheapest / 42 | 115 | 100/115 (87.0%) | 6/115 (5.2%) | 9 | 4 | 6,290 |
| Final / income_first / 43 | 104 | 87/104 (83.7%) | 9/104 (8.7%) | 8 | 5 | 5,670 |
| Final / random / 44 | 120 | 103/120 (85.8%) | 6/120 (5.0%) | 11 | 4 | 6,560 |

Every run completed 95 base + 55 outer research with zero ledger error. The
matched cheapest run reduces the one-round maximum from eight to four and
raises the one/two-purchase share from 64.3% to 87.0%. Its longest empty
purchase stretch is one round. Occasional larger batches remain intentional;
there is no hard purchase limit.

Full purchase-count histograms:

| Run | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Before / cheapest / 42 | 6 | 25 | 20 | 8 | 5 | 1 | 2 | 1 | 2 |
| Final / cheapest / 42 | 9 | 72 | 28 | 3 | 3 | 0 | 0 | 0 | 0 |
| Final / income_first / 43 | 8 | 59 | 28 | 4 | 3 | 2 | 0 | 0 | 0 |
| Final / random / 44 | 11 | 77 | 26 | 4 | 2 | 0 | 0 | 0 | 0 |

For the matched cheapest runs, rounds starting with 25–74 explicit purchases
fall from 3.79 to 1.55 purchases per round; rounds starting with at least 95
explicit purchases fall from 2.65 to 1.20. These buckets include the round
crossing each threshold. Total duration is recorded as an outcome, not tuned
to a completion-time target.

Purchase counts include zero-cost explicit purchases and exclude the one
automatically owned outer protocol entry: 149 explicit transactions complete
150 research nodes. Histograms count every completed round, including empty
ones and the final round. Strategies buy all affordable legal choices repeatedly;
they do not enforce the intended one-to-two purchase count.

These are synthetic observation results, not a human playtime or game-feel
claim. Seeds and strategies change subsequent event opportunities; a matched
seed does not mean the entire sky remains identical after purchases diverge.
The extra strategies are robustness examples, not a statistical population.

## Verification and reproduction

The final `tools/validate.ps1 -FullEconomy -Build` run passed all 29 checks:
27 fast gates, the independent 95-node economy gate, and Windows export. The
performance telemetry helper was built and its GPU usage test passed. Run ID:
`20260914T061528873Z_d8c101bc`.

| Real-observation driver seed | Base research | Active completion seconds | Longest new-research gap | Largest purchase batch |
|---|---:|---:|---:|---:|
| 20260821 | 95/95 | 2,560 | 120s | 5 |
| 20260837 | 95/95 | 2,470 | 120s | 5 |
| 20260853 | 95/95 | 2,560 | 120s | 5 |

All three samples reconcile source income and bank with zero error. This driver
uses actual observation work plus continuous sweeping and differs from the
instant-observation simulator; its largest batch is not the simulator's metric.
Neither driver measures human judgment, mouse input handling, or game feel.

The independent scope audit confirms all 150 IDs, graph edges, and nonmonetary
effects are unchanged and all revised prices are clean. All 55 outer price rows
match production. Regression budgets and exact reward expectations were updated
for approved prices/×1.5 rewards; insufficient-funds, duplicate-charge, save,
feedback, income reconciliation, and research-arrival checks remain active.

Windows executable:
`C:\Users\user\Documents\ChatGPT\star\build\windows\NightwatchArray.exe`
(120,336,152 bytes, SHA-256
`3e2be749206053d7a7b5e75ba178769a9fba7b9b7a5ec37bd678eaa09f19cdf9`).

Use the console engine and the public simulator to reproduce a fresh run:

```powershell
& $godot --headless --disable-render-loop --path . --script res://tools/economy_simulator.gd -- --config build/economy-config.json --output build/economy-report.json
```

Set the config to `{"strategy":"cheapest","seed":42,"max_rounds":160}` (or
`income_first`/43 and `random`/44); all other fields use documented defaults.
The archived diagnostic wrapper performs the same purchases/rounds and also
saves checkpoints at 15/40/80/95 base nodes. For an economy branch comparison,
use a new engine process with the archived baseline checkpoint and `--resume`
plus `--resume-mode branch`, as described in [the simulator guide](../economy-simulator.md).

The [evidence archive](research-economy-2026-09-14-evidence.zip) contains original
completed reports/configs/logs, the baseline 15-node checkpoint, final checkpoints
at 15/40/80/95 base nodes for all three strategies, before/final economic source
files, candidate price maps, the diagnostic runner, price comparison, scope
audit, and intermediate/final validation logs. `manifest.json` provides SHA-256
for each entry. Intermediate folders originally named `final-*` are archived as
`candidate-3-*` to distinguish them from the actual `verified-*` final runs.

Archive: 114 entries, 453,194 bytes, SHA-256
`991fd0e956fe196f0867e7b36a6baece6b3b0fc26106c4b36155663a88832577`.
The ZIP was read back and every entry was checked against its manifest. Build
binaries are excluded; the executable remains in the ignored Windows build
folder. Final report source hashes were checked against the working source.
