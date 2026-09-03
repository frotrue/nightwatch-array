# Agent Room AM-V3QP checkpoint — 2026-09-03

## Current decision

Fable approved stage 2 in room message #34 after the code/threshold review and
seven gates plus eight rendered diagnostics. Commit the stage-2 changes before
continuing. Live 280 ms animation feel remains a human judgement, not a claim
made from frozen poses. Stage 3 is now open for Codex's independent review of
Fable's separate `tests/capture_reference.gd` implementation; it is not approved
yet. Stage 4 has not started. The earlier checkpoint entries below are history,
not the current approval state.

User requested commit/push/shutdown and continuation from stage 2 tomorrow.
This is a checkpoint, not completion of all four stages. Do not merge to main.

## Resumed review — 2026-09-03

The user has resumed work through stage 4 with a Fable review at each gate.
HEAD `162c61d` is the pushed stage-2 WIP, not an approved stage-2 commit.
The working tree fixes the installation pulse being hidden behind the open
chart: the active constellation/galaxy inspector now owns its existing 1 px
rule, while the closed-chart path retains the HUD rule. A non-drawing container
slot prevents deferred VBox layout from resetting the constellation pulse.
Reference Frame keeps its existing pull-back instead of a hidden pulse.

Independent reruns of research contract, smoke, Layer 2, sound feedback, effect
feedback and observation span pass, and the Windows executable was refreshed.
Smoke's two focus warnings and the probe's exit-leak warning remain pre-existing.
Room message #27 requests Fable's code review; no stage-2 approval is recorded.
The remaining visual check uses focused, windowed stage-2 diagnostics (#28),
not the stage-3 headless/manifest generator. Stages 3 and 4 remain unstarted.

The additional galactic-slice regression passes. The windowed diagnostic
`tests/effect_feedback_preview.gd` produced all eight PNG/JSON pairs in
`build/effect_feedback_review` with run ID `stage2_1788395904457` at 1152x648.
Codex inspected all eight fresh images: routine/accented effects are visibly
distinct, and both inspector rules render above the chart. The constellation
rule occupies 35/157/175 actual pixels at start/mid/end. Frozen poses do not
establish perceived live pacing. Fable's review remains required before closing
stage 2, committing it as approved, or starting stage 3.

Room-state diagnosis after the report: Fable's `last_read_id` is still 22
while the latest room message is 29. The room's active-agent count is a stored
participant count, not a heartbeat. Thus the current-session review requests
have not been consumed by Fable; the user needs to resume that agent's room
listener. Do not waive its review or silently advance to stage 3.

The user subsequently reported reconnecting Fable, and Codex resumed listening
in room message #31. A separate diagnostic audit found the mutable fixture file
missing from the capture source-hash list; it is now included. The replacement
run `stage2_1788397194202` writes all eight PNG/JSON pairs, and all eight PNG
hashes are identical to the visually reviewed run above. Its sidecars additionally
identify `tests/effect_feedback_test.gd`. No production behavior changed.

## Stage 1 — approved

- Commit: `13e7ad3` (semantic audio + 160 ms automatic aggregation).
- Fable approved in room message #15 after reviewing the debug-key duplicate
  warning fix and the Perseid incoming route. Trailing aggregation is accepted;
  a human may still request a leading-edge change after listening.
- Research contract, smoke, Layer 2, and sound-feedback tests pass.
- Live WASAPI playback reached a nonzero Master peak; its surround-device
  recorder captured a silent final stereo pair. The separate stereo WAV is
  explicitly a Dummy-driver software-mixer artifact, not hardware capture.
- Local audition: `build/audio_feedback_audition.wav` and `.json`; reproducible
  with `tests/sound_feedback_preview.gd` as documented in `docs/probes.md`.

## Stage 2 — work in progress, NOT approved

Started before the user's interruption. Production edits currently gate rings,
flashes and manual camera motion on rare identity or high manual quality, keep
routine particles directional, and replace sky-wide installation effects with
the existing HUD banner rule's local extension. Existing smoke/span expectations
were updated. These edits are kept in a separate WIP commit from stage 1.

Checkpoint verification: research contract, smoke, Layer 2, sound-feedback,
effect-feedback and observation-span gates all passed; Windows export succeeded. Smoke focus warnings
and Layer 2 exit-leak warnings remain and are not represented as new fixes.
`build/windows/NightwatchArray.exe` contains the WIP checkpoint;
`build/windows/NightwatchArray.stage1-13e7ad3.exe` preserves the approved stage-1
export separately. Both are local ignored build artifacts.

Resume by reading room messages #16 onward, the working diff against `13e7ad3`,
and the new stage-2 design section. Review the new focused effect regression gate,
check all event call sites, review the documentation for stale descriptions,
run the full required tests and span probe, refresh the Windows export, and
obtain Fable's stage-2 review before starting stage 3. No visual quality verdict
has been made for stage 2.

## Remaining stages

3. Deterministic capture generator: scenario manifest, IDs, viewport, source
   revision, state/count checks and fresh PNGs. Investigate true headless render
   feasibility; report constraints rather than silently passing without images.
4. Branch-color rendering through actual star/galaxy/cluster draw paths and
   truthful tutorial copy. Only after capture gate, then Fable review.

Keep research IDs, economy, save format and the observational negative space.
Every commit uses exactly the required Claude co-author trailer.
