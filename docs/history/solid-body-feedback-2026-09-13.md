# Solid-body completion feedback — 2026-09-13

User-approved presentation change: asteroids break apart after observation;
the planet receives a restrained surface sweep. Original live art, unobserved
expiry, completion reward, target admission and 0.62-second linger are unchanged.
Seven rock pieces or nine ice shards reuse procedural faces on the original
meteor. No new nodes, targets, particle budget or sound channels are introduced.
Motion intensity zero retains the original body fade; disabling flashes also
disables local glints and the planet sweep. Changes apply to current lingerers.

Validation:

- `tools/validate.ps1 -Build`: 25 gates and Windows export PASS.
  Run: `build/validation/20260913T032713104Z_542119a5/summary.json`.
- Background, meteor and effect GPU comparisons PASS on Vulkan and OpenGL;
  original tolerances retained.
- `tests/solid_body_feedback_review.gd`: five real-renderer frozen captures
  using actual completion signals; inspected original-resolution PNGs in
  `build/solid_body_feedback_review/`. The 230ms/430ms poses show separated
  rock/ice faces and the planet sweep; reduced motion keeps intact bodies.
  Captures isolate body art from the separately tested normal reward particles.
  These are diagnostic poses, not a verdict on the feel of live play.
- `effect_feedback_test.gd` additionally checks one completion, no gameplay
  fragments/extra rewards/targets, accessibility propagation and linger cleanup.

Focused cost experiment (Ryzen 9 5950X / RTX 3060, Vulkan, 1152×648):
six simultaneous lingering bodies, two of each type, forced redraw each frame.
The old-fade baseline disables successful-completion artwork in a diagnostic
subclass; it is not a full game benchmark. Two runs per mode, 20 warm-up and
180 measured frames each, ordered old/new/new/old:

| Body `_draw` CPU time for all six | Median ms | p95 ms |
| --- | --- | --- |
| Old fade, run 1 | 0.771 | 0.928 |
| New feedback, run 1 | 0.828 | 0.943 |
| New feedback, run 2 | 0.826 | 0.905 |
| Old fade, run 2 | 0.752 | 0.909 |

The measured extra median submission work is about 0.07ms for six simultaneous
completions. This excludes GPU execution and other game systems; no overall FPS
improvement or guarantee is claimed. Temporary probe: ignored
`build/solid_body_feedback_review/cost_probe.gd`.
