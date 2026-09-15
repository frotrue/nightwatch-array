# Three concurrent stars and black holes — validation handoff

User authorization: raise the existing one-at-a-time limit to three for both
stars and black holes. Prepared against main `285d0b155c8b6f40f3a6bb94b289aeaedcb4bb3c`.

## Changes

- Three dedicated slots per type, including completion/expiry remnants. Both
  types can occupy three slots simultaneously. Their slots do not consume the
  ordinary late types' shared extra slot. The total safety budget is 70.
- Existing occurrence probabilities, unlocks, rewards and save format remain.
- Three authored black-hole copy/lens pairs replace last-source-only tracking.
  Each active pass reads the previous pass; manual contact projection follows
  the same order. Materials, source removal and slot reuse are independent.
- Existing fixed-tick, stellar and black-hole gates gain coverage for admission,
  overlap, shared rewards, recapture, reduced motion and lens cleanup. The real
  renderer review gains three-hole and three-star-plus-three-hole scenarios.

## Validation environment recovered

Downloaded the official Godot 4.7.2 Linux editor and matching Windows export
templates from the official object-storage CDN after the GitHub download route
timed out. A failure on that first route did not establish that Godot could not
be installed. Both archives extracted successfully. Editor version:
`4.7.2.stable.official.ed1daf0bf` (full hash
`ed1daf0bf001b61586d9930840f2f1394092c079`).

- Editor: `/tmp/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64`.
- Templates: `/root/.local/share/godot/export_templates/4.7.2.stable`.
- Official source: <https://godotengine.org/download/archive/4.7.2-stable/>.
- Direct editor archive:
  <https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip>.
- Direct templates archive:
  <https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz>.

## Executed checks

The Linux headless editor import passed without parse errors. All 29 fast
GDScript gates listed in `tools/validate.ps1` passed on the downloaded Linux
engine. Each process was checked for exit zero, its required PASS marker, and
unexpected engine/script errors; the reference-capture gate's exact expected
missing-Git negative case was exempted, matching the Windows runner.

Two test-fixture issues were corrected without changing game behavior or
relaxing assertions:

- The new overlapping-star reward test now enables automatic observation on
  its source stars before expecting the automatic reward multiplier.
- `smoke_test.gd` used a diagnostic fixture fixed to English but expected Korean
  constellation text. Both failures reproduced unchanged on the main snapshot
  `285d0b1`. The test now selects Korean for those assertions and restores the
  previous locale afterward. The corrected full smoke gate passes.

The full-tree economy gate also passed in 223.57 seconds with its unchanged
default strategy `cheapest` and all three default seeds (`20260821`, `20260837`,
`20260853`). All 30 GDScript gates (29 fast plus full economy) therefore pass.
This was execution of the same scripts on Linux, not execution of the Windows
PowerShell validation runner or its native build step.

Logs and machine-readable results are in
`build/validation/three-slots-linux/`. The first smoke failure and the unchanged
baseline reproduction are retained separately from the successful retest.

## Windows export

Exporting `Windows Desktop` with the matching 4.7.2 template and its ICU data
succeeded (exit 0, no engine/script errors). The embedded-PCK executable has a
valid `MZ` header:

`/workspace/scratch/acfc0352bc45/nightwatch-array/build/windows/NightwatchArray.exe`

This is a Linux cross-export. Windows execution and the MSVC-built
`NightwatchMetrics.exe` companion were not validated or produced here; do not
interpret the export as a fully validated Windows distribution. The Linux
performance-monitor gate does not exercise the Windows telemetry helper.

## Remaining target-platform review

The PR remains draft pending real renderer and Windows validation. This
container has no usable display server; the locally extracted Xvfb could not
create listening sockets. No screenshots or GPU/frame-time results are claimed.
Headless numerical projection checks are not proof of rendered alignment.

```powershell
$godot = "C:\Users\user\AppData\Local\Temp\codex-godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
.\tools\validate.ps1 -GodotPath $godot -FullEconomy -Build
& $godot --path . --script res://tests/black_hole_review.gd
& $godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tests/black_hole_review.gd
```

Also run the project's three renderer comparison tests on both backends as
specified in `docs/probes.md`. Inspect the added captures for all three visible
lenses, overlapping primary-image alignment, six-body readability, residual
screen images and reduced-motion cleanup. Measure frame time in the six-body
scene on the target PC before making a performance claim: it can have up to
three stellar heat copies plus three lens copies, compared with two total before.
