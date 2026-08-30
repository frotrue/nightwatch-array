# 107-node full-tree economy baseline

Recorded 2026-08-30 with Godot 4.7.2-stable. This is the first reproducible
economy baseline for the simplified 95-node Milky Way plus 12-node Local Group
graph. It replaces the 124-node route only as a measurement reference; it does
not approve a completion-time target or any price change.

## Measurement contract

The driver runs an engaged, mistake-free scripted watch at `0.05s` simulation
steps. It uses one primary manual cursor, applies Multi-target Analysis only to
other targets inside the real cursor radius, moves predictive dishes through
the production controller, reveals hidden hosts with valid sweep directions,
selects correct comparison stars, and observes all five galactic phenomena.
Purchases happen only at intermissions.

The clock is **active observation time**. It excludes reading, deliberation,
research-chart navigation, and intermission time, so it is a lower bound rather
than a forecast of a person's wall-clock playtime. The driver stops when all
107 functional research nodes and all five galactic phenomena are complete.
That is the economy/content boundary, not the end of the shipped catalogue
flow: the driver does not play the required fully researched final watch, move
through the final summary and completed chart, display the ending record, or
choose Finish/Continue. The additional full round—or the remainder of an
already qualifying final watch—and intermission navigation are therefore absent
from the measurement boundary.

Three deterministic seeds run under three heuristic purchase orders:

| Strategy | Rule |
|---|---|
| `cheapest` | Buy the least expensive currently purchasable node |
| `automation_first` | Among nodes affordable now, prefer automation and Network nodes, then use price |
| `manual_first` | Among nodes affordable now, prefer manual-facing Optics, Taurus, Lyra, Ursa Minor, and Perseus nodes; defer automation |

These are greedy, no-reservation heuristics: they spend on lower-priority
affordable nodes instead of saving for an unaffordable preferred node. They are
comparison scenarios, not optimal builds or models of player intent. In
particular, `automation_first` is not an Automated Tracking rush.

Each node records four distinct times:

| State | Meaning |
|---|---|
| R — revealed | The node is visible rather than hidden |
| A — available | All prerequisites are installed |
| F — affordable | The current bank first reaches the price while the node is available |
| P — purchased | The node is installed at an intermission |

The gate asserts mechanical contracts only: 107/107 purchases, five/five
phenomena, final `×8192` observation value, final `1.4774554` observation span,
manual and automatic meteor income, host income, phenomenon income, complete
R/A/F/P timelines, source/cost/bank reconciliation within `0.5` Data, and no
gap above the approved 120-second research-arrival ceiling. Duration, purchase
batches, and strategy differences are diagnostics.

## Reproduction

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$env:NIGHTWATCH_ECONOMY_STRATEGIES = "cheapest,automation_first,manual_first"
& $godot --headless --path . --script res://tests/full_tree_economy_test.gd
```

`NIGHTWATCH_ECONOMY_SEEDS` accepts a comma-separated seed list. With no
environment variables, the driver uses seeds `20260821,20260837,20260853` and
the `cheapest` strategy. Preserve the `FULL_TREE_ECONOMY_ENV` line with any
future result.

## Results

The functional research price total is `41,332,301,070` Data. Research and
galactic-content completion occurred in the same round in all nine samples;
all five phenomena were already complete when the last research was installed.
Under the later catalogue-ending contract, each of these routes would next play
one full round that starts with all research installed before the ending can be
shown. The table deliberately preserves the original `107/107 + 5/5` stopping
times rather than retroactively adding that round.

| Strategy | Seed | Active time | Rounds | Earned Data | Bank after 107/107 | Automatic income | Largest batch |
|---|---:|---:|---:|---:|---:|---:|---:|
| cheapest | 20260821 | 2,990s (49:50) | 55 | 41,489,467,063 | 157,165,993 | 0.59% | 9 |
| cheapest | 20260837 | 2,980s (49:40) | 55 | 41,400,490,320 | 68,189,250 | 0.57% | 9 |
| cheapest | 20260853 | 3,040s (50:40) | 56 | 41,463,236,737 | 130,935,667 | 0.59% | 10 |
| automation first | 20260821 | 3,180s (53:00) | 57 | 41,425,898,937 | 93,597,867 | 0.57% | 9 |
| automation first | 20260837 | 3,300s (55:00) | 59 | 41,525,565,845 | 193,264,775 | 0.58% | 8 |
| automation first | 20260853 | 3,300s (55:00) | 59 | 43,926,884,091 | 2,594,583,021 | 0.57% | 9 |
| manual first | 20260821 | 3,020s (50:20) | 57 | 41,411,809,795 | 79,508,725 | 0.56% | 7 |
| manual first | 20260837 | 3,010s (50:10) | 57 | 41,431,248,826 | 98,947,756 | 0.54% | 9 |
| manual first | 20260853 | 3,060s (51:00) | 58 | 41,501,002,974 | 168,701,904 | 0.57% | 8 |

| Strategy | Minimum | Median | Maximum | Mean | Delta from cheapest median |
|---|---:|---:|---:|---:|---:|
| cheapest | 2,980s | 2,990s | 3,040s | 3,003s | — |
| manual first | 3,010s | 3,020s | 3,060s | 3,030s | +30s (+1.0%) |
| automation first | 3,180s | 3,300s | 3,300s | 3,260s | +310s (+10.4%) |

Pooled across all nine samples, the source ledger was:

| Source | Share of all earned Data |
|---|---:|
| Manual host observations | 80.67% |
| Manual meteors | 16.97% |
| Galactic phenomena | 1.78% |
| Automatic meteors | 0.57% |

Hosts are manual-only in the current production contract, so zero automatic
host income is expected. Source-income error and final bank error were exactly
zero in every sample.

## Pacing observations

- The largest R→A delay was 80 seconds. The largest A→F delay was 1,278.95
  seconds on the prerequisite-free but expensive `canis_capacity_ii`; this does
  not mean the whole tree was stalled, because other nodes remained actionable.
- The largest F→P deferral was 535.85 seconds on `leonid_radiant` under the
  manual-first heuristic. It describes that strategy's opportunity cost, not a
  cash wall.
- The longest gap between newly available nodes was 120 seconds in every run,
  exactly the current `2 × MAX_OBSERVATION_DURATION` reference with no safety
  margin. Unlike the completion-time diagnostics, this is an approved design
  contract and therefore remains asserted by the gate.
- Whole-tree intermissions installed as many as 7–10 nodes at once. Local Group
  intermissions remained at one node, so the batching problem is concentrated
  before the final chapter.
- The Local Group occupied 1,080–1,140 active seconds. During that segment,
  hosts used 14.03–14.19% of cursor time, meteors 82.31–83.61%, and phenomena
  0.50–0.52%. Nevertheless, hosts supplied 80.67% of total-run income.
- Each phenomenon was completed 0.9–1.2 seconds after its unlock node was
  purchased by this perfect driver. The content is mechanically exercised but
  does not create a long experiential beat in the scripted route.

## What to investigate before tuning prices

1. **Late reward concentration.** Host rewards dominate the ledger despite a
   modest attention cost. Measure source share per round and test smoother host
   payouts or a broader meteor/phenomenon contribution before changing the
   total price curve.
2. **Automation return on investment.** The automation-first scenario was
   10.4% slower at the median while automatic completions supplied only about
   0.57% of income. Run paired, node-by-node counterfactual ROI probes before
   deciding whether the problem is price, timing, target eligibility, or the
   deliberately active driver.
3. **Upgrade identity.** Seven-to-ten-node purchase bursts make individual
   research rewards hard to notice. Prefer staggering meaningful unlocks or
   improving intermission choices over adding a blanket price multiplier.
4. **Final-chapter cadence.** The Local Group repeatedly sits on the 120-second
   arrival reference and its phenomena resolve almost immediately. A human
   playtest should check whether host work and presentation fill that interval;
   the automated gate cannot judge feel.
5. **Campaign length and ending boundary.** The measured content boundary is
   roughly 50–55 active minutes, well short of the design's eventual two-hour
   goal. The shipped catalogue ending adds one normal fully researched watch,
   but this baseline does not measure its screen flow or human intermission
   time. Continue to add meaningful content first; price walls and the final
   watch should not be used to manufacture the missing hour.

No runtime balance value was changed while recording this baseline.
