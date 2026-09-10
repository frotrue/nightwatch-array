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
