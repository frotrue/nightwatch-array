# White-hole visual refinement — 2026-09-15

User feedback: pursue a slightly realistic celestial appearance and the strong
first impression of the existing black hole. This refines the debug-only
prototype in draft PR #14, based on the three-slot change in PR #13.

## Visual changes

The flat mouth, concentric fronts and evenly arranged streaks were replaced
with a graded white-hot centre, inclined emitting gas, differential rotation,
outward advection and irregular wisps. A folded far-side image and a brighter
near-side disc crossing the lower limb add depth. The alternative retains
bipolar jets with turbulent structure instead of periodic knots.

[NASA's black-hole disc visualization](https://svs.gsfc.nasa.gov/13326/) informed
the gas lanes, asymmetric brightness and folded disc silhouette. This is an
artistic white-hole interpretation, not a prediction from a physical model;
no reference image is shipped as an asset.

The existing black-hole lens shader now refracts the background sky. Each
visible active preview adds one viewport copy and a local lens quad. Both
optical nodes draw at absolute z = -18, after the sky and before meteors and
instruments. Copies are disabled when hidden, offscreen, transparent, expired
or set to zero motion. Emission remains a procedural local quad without CPU
particles or ray marching. The maximum is still three previews.

Debug shortcuts, fixed-tick lifetime, pause and cleanup remain unchanged.
Zero motion freezes the disc and disables jets, wind and refraction; disabling
flashes removes the small brightness breath. The prototype still does not
participate in natural spawning, observation, rewards, gravity, RNG or saves.

## Validation

Godot `4.7.2.stable.official.ed1daf0bf`, Linux x86_64.

- Editor import: PASS without parse/script errors.
- All 30 fast GDScript gates: PASS after the fixture correction below. Checks
  require exit zero, the expected PASS marker and no unexpected errors. The
  existing missing-Git negative-case exemption remains unchanged.
- White-hole behavior gate additionally covers independent optical materials,
  optical draw order and disabling screen copies for hidden/offscreen/reduced
  motion previews.
- OpenGL Compatibility / Mesa llvmpipe: render review PASS; 45,334 changed
  pixels in the sample, zero outside the permitted footprint.
- Vulkan Mobile / Mesa lavapipe: render review PASS; 45,805 changed pixels,
  zero outside the footprint.
- Both reviews verify distinct effect modes, a stable reduced-motion image,
  three overlapping previews and exact return to the background after removal.
  A synthetic background star grid must refract while an opaque foreground
  marker remains pixel-identical. Both comparison captures were inspected.
- Existing background, meteor and effect-instance rendering comparisons:
  PASS on both backends, six runs with unchanged assertions.
- A four-second, 72-frame comparison was captured from the running OpenGL
  renderer and encoded as `build/white_hole/WhiteHole-Comparison.gif`.
- Full-tree economy was not repeated for this isolated visual change; the
  fast economy simulator gate passed.

### Existing draw-test fixture correction

The first aggregate run failed `deep_sky_chart_expansion_test` at debug-save
rollback equality. A seeded diagnostic reproduced it with seed 4: directly
equipping OVERCHARGE in the fixture left its introductory tutorial at EQUIP
when OVERCHARGE was also the first paid result. Save restoration correctly
synchronized that state to COMPLETE, making the before/after snapshots differ.
Ownership, quantities and the draw result were already restored correctly.

The fixture now calls its existing protocol synchronization after direct
equipment and before taking the rollback snapshot. No product logic or test
assertion changed. The seed-4 reproduction and the ordinary affected gate pass
with this correction; the initial failure log is preserved. The correction is
committed separately from the visual work.

## Windows export and limits

Windows Desktop release cross-export: PASS with matching Godot 4.7.2 templates
and ICU data, embedded PCK and a valid MZ header. Executable:

`/workspace/scratch/acfc0352bc45/nightwatch-array/build/windows/NightwatchArray-WhiteHolePreview.exe`

The executable was not run on Windows here. The Windows PowerShell runner,
MSVC-built NightwatchMetrics companion and target-PC performance are unverified.
The software-rendered checks establish rendering correctness, not a frame-time
budget on the user's PC. PR #14 remains a draft for visual feedback.

Logs, gate summary and export hash: `build/validation/white-hole-realism/`.
Captures/manifests: `build/white_hole/gl_compatibility/` and
`build/white_hole/mobile/`. See [the guide](../white-hole-preview.md) for controls
and reproduction commands, and the [initial record](white-hole-preview-2026-09-15.md)
for the superseded wavefront appearance.
