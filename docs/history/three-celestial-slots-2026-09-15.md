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

## Status: runtime validation and Windows export blocked

The Linux editing environment has no Godot, PowerShell or Windows build tools.
Downloading the Godot 4.7.2 Linux binary failed with a proxy CONNECT timeout.
The Windows export invocation also stopped with exit 127 (`godot: command not found`).
`git diff --check` and static resource-reference, function-name and authored
lens-order/material checks passed; they do not establish GDScript compilation.
No Godot tests, GPU captures, economy run or Windows export have passed for this
change. The added test cases are prepared, not executed. A draft PR must remain
unmerged until the following project gates run successfully.

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

On success, update this record with actual logs, captures and export path and
remove the pending-execution note from `docs/probes.md`. There is currently no
new Windows executable for this change.
