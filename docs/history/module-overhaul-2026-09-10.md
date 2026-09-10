# Module replacement — 2026-09-10

The user approved linear observation, capture hold and overcharge, and requested
actual removal of trail integrator, relay bus, long baseline, dual processor and
afterglow archive. The five surviving modules retain their effects. The active
draw pool is eight equally likely types; acquisition costs are unchanged.

Removed module definitions, glyphs, translations and dedicated observation,
dish and afterglow behavior. Old ownership/equipment drops those five IDs;
afterglow tickets and targets cannot revive. The separate retired M31 ownership
contract remains intact. An unchosen, already paid v2 offer still refunds its
payment once, independently of today's catalogue; it never restores its item.

New defaults are documented in [current expansion design](../expansion-design.md).
Line geometry uses swept contact intervals; capture pauses motion and burnout
once per target; overcharge counts completed targets once, preserves its remaining
time across saves, and resets on round/equipment changes. Capture state persists
for the rare targets that the game already restores.

## Verification

- All 20 quick gates, the three-seed full-tree economy and Windows export passed:
  `build/validation/20260910T091542362Z_9434d159/summary.json`.
- Ten stable desktop frames, including Korean/English tooltips, were inspected:
  `build/module_review/1789031932/manifest.json`. The pre-change corpus is
  `build/deep_sky_review/1789030716/`. Images verify layout, not motion comfort.
- `module_overhaul_review.gd -- --probe` uses eight paired seeds, 30 seconds per
  configuration, fixed 0.05-second steps, scripted circular cursor movement and
  identical common-meteor arrival attempts. Automatic tracking and additional
  research-triggered arrivals are disabled. Results and source hashes are in
  `build/module_review/paired_probe.json`; engine output is in `probe.log`.
- The save-free human slice launched and exited normally, but recorded **0 seconds
  of held observation input**. No human comfort verdict was obtained. An earlier
  slice setup was stopped and corrected so its research chart closes before the
  trial and its loop exits at intermission. Scripted passes are not human feedback.

These checks establish mechanics, migration and presentation. They do not establish
long-term module balance or enjoyment. The human feedback request remains pending.

## Follow-up: continuous slowdown

The user subsequently approved replacing Capture Hold with Observation Slowdown:
30% slower movement and burnout while observing inside the current circle/band,
normal observation work, and immediate release outside the field or on input/equipment
release. Reentry can slow the target again. Copies add −30 percentage points with a
10% minimum remaining speed, matching the existing additive module contract.
The capture_hold inventory ID is retained; per-target stop timers and saved flags
are removed. Old saved timers are ignored. No additional playfield indicators were added.

Boundary, reentry, release, unequip, line geometry, stacking, real rare-target motion
and old saved-timer rejection tests passed. All 20 quick gates, the three-seed economy
and Windows export passed in `build/validation/20260910T093835141Z_b4a09376/summary.json`.
Eight paired seeds with the existing synthetic 30-second driver averaged 19.38
observations without a module and 25.88 with slowdown alone. The probe log is
`build/module_review/slow-probe.log`. This establishes a mechanical effect under the
specified workload, not a human comfort verdict. New human feedback is still absent.
