# Agent Room AM-V3QP checkpoint — 2026-09-03

User requested commit/push/shutdown and continuation from stage 2 tomorrow.
This is a checkpoint, not completion of all four stages. Do not merge to main.

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
