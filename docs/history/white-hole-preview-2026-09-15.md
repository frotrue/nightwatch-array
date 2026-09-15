# White-hole debug preview — 2026-09-15

User request: implement a white-hole effect prototype that can only be summoned
through debug controls, with its visual direction still open for comparison.
Based on PR #13 head `7e525ac20b9fcd6815681b9a126033c82cff3c65`; this change is a
separate branch/PR on top of that three-slot change.

## Scope and visual decision

The default is an outward wavefront with a compact white mouth, cyan-white rim,
three expanding fronts and radial streaks. A second mode offers bipolar jets
with outward travelling knots. Both use one local shader quad per preview,
with separate material instances and no screen reads or copied backbuffers.
The shader uses simulation-driven time instead of global TIME.

Ctrl+Shift+W summons at the cursor; Ctrl+Shift+E switches modes on every live
preview. The layer admits at most three, ages them during active simulation,
and clears on round end, run reset/start and load. Reduced motion removes the
animated fronts/jets/streaks while preserving the static mouth and lifetime.
These are non-observable visual previews, outside MeteorLayer, spawn admission,
reward, gravity, natural RNG and saved-run data.

## Validation

Godot `4.7.2.stable.official.ed1daf0bf`, Linux x86_64.

- Editor import: PASS, no parse/script errors.
- All 30 fast GDScript gates in `tools/validate.ps1`: PASS, checked for exit zero,
  the expected PASS marker and unexpected errors. The exact reference-capture
  missing-Git negative case retains the existing runner exemption.
- New white-hole gate: PASS for routing, capacity, independent materials, saved
  run/RNG isolation, pause, accessibility, expiry/reuse and boundary cleanup.
- Full-tree economy was not repeated: this prototype is isolated from real
  spawning, targets and rewards. The fast economy simulator gate passed.
- OpenGL Compatibility on Mesa llvmpipe: white-hole render review PASS.
  36,479 changed pixels in the emission sample, zero changed pixels outside
  the allowed footprint; reduced motion and removal returned stable images.
- Vulkan Forward Mobile on Mesa lavapipe/llvmpipe: same review PASS.
  36,026 changed pixels, zero outside the footprint. The two backend comparison
  captures were also inspected visually; no shader errors or clipping were seen.
- Existing background, meteor and effect-instance pixel comparison gates:
  PASS on both OpenGL and Vulkan (six runs).
- Comparison captions initially used the system font, which lacked Korean
  glyphs. Switched the diagnostic labels to the project's IBM Plex Sans KR,
  then recaptured and inspected both backends.
- A four-second, 72-frame OpenGL comparison sequence was captured directly
  from Godot and encoded to `build/white_hole/WhiteHole-Comparison.gif`.

The display uses an authenticated Xvfb TCP connection. Xvfb and Godot run
within the same command's network namespace; separate command processes cannot
reach each other's loopback listeners in this environment. This recovered
actual rendering after the earlier session's display blocker. Software renderer
results are correctness evidence, not a target-PC performance benchmark.

## Windows export and remaining limits

Windows Desktop release cross-export: PASS (exit 0, no engine/script errors,
embedded PCK, MZ header), using matching Godot 4.7.2 export templates and ICU data.

`/workspace/scratch/acfc0352bc45/nightwatch-array/build/windows/NightwatchArray-WhiteHolePreview.exe`

The executable was not run on Windows here. The Windows PowerShell runner,
MSVC-built NightwatchMetrics companion and target-PC frame times remain
unverified. The PR stays draft as an art prototype awaiting the user's visual
choice; it does not add a researched or naturally occurring celestial type.

Logs: `build/validation/white-hole-linux/`.
Captures/manifests: `build/white_hole/gl_compatibility/` and
`build/white_hole/mobile/`. Reproduction commands are in
[the prototype guide](../white-hole-preview.md).
