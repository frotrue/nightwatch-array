# Agent Room AM-V3QP 기록 원문 — 2026-09-03 정리 전

이 파일은 문서 정리 전 `ef769eec3b6ce84b1099d173350a0e203b341f07`의 `docs/agent-room-feedback-checkpoint.md` 원문을
그 순서와 문구 그대로 보존한 기록이다. 원본 Git blob: `d001af273d984be22799d93189754adae8425b64`.
현재 규칙은 [현행 설계](../design.md), 문서 구분은 [문서 지도](../README.md)를 본다.

여기에는 여전히 유효한 승인과 이미 대체된 승인, 당시의 미완료 상태가 섞여 있다.
**같은 사항은 뒤에 승인된 대체 결정이 우선한다.** 옛 가격·노드 수·측정값·회의
재개 지시를 현재 사양이나 새 작업 승인으로 읽지 않는다. 원문의 날짜와 한계도
수정하지 않았다. 아래 구분선 뒤가 원문 전체다.

<!-- ORIGINAL-BEGIN -->
# Agent Room AM-V3QP checkpoint — 2026-09-03

## Current decision

Fable approved stage 2 in room message #34 after the code/threshold review and
seven gates plus eight rendered diagnostics, committed as `c114d42`.
Live 280 ms animation feel remains a human judgement, not a claim made from
frozen poses. Codex's stage-3 review rejected six false-pass/isolation/provenance
gaps, accepted by Fable in #37. The rewritten generator separates isolated
scenario fixtures from capture validation, hashes the full working tree and
checks stable nonblank frames with exact state contracts. Two dirty runs at
`c114d42` generated identical PNG hashes for all eleven scenarios, independently
visually inspected; eight correctness gates passed. The off-screen Windows
renderer alternative is agreed in #37, not display-less headless support.
Fable approved stage 3 in #42, independently checking the clock's only writer,
headless rejection and repeat PNG hashes. The twelve rejected prototype files
were removed from the reference root into a separate, marked legacy archive
(no deletion). Stage 3 is committed as `eb60697`. The clean corpus
`build/reference/eb60697cc7e4_1788399040269` passed all eleven scenarios with
`source.revision_dirty: false`; all PNGs match the visually reviewed dirty run.
The stage-2 diagnostics were refreshed as `stage2_1788399046630`; all eight
images also match the reviewed version. Stage 4 implements low-mix
branch colour in actual star/cluster/galaxy draw paths plus tutorial copy,
without changing state geometry, economy, research IDs or persistence.
The implementation passes nine gates, including 107 live branch bindings and
actual draw-callback routing. Baseline `eb60697cc7e4_dirty_1788399380830` and
post-change `eb60697cc7e4_dirty_1788399607476` isolate all 117 active palette
cells changing, the entire inactive palette remaining byte-identical, and the
nine non-chart scene images remaining identical. Two post-change captures are
byte-identical for all thirteen scenarios. The two real charts were visually
reviewed for preserved warm hierarchy; compiled EN/KO translations and the
Windows executable were refreshed. Fable approved stage 4 in #47 after direct
code and pixel review. Its frontier hues read as three broad groups, not
thirteen instantly identifiable colours; installed points retain their near-white
state. All four implementation stages are approved. Generate the final clean
thirteen-image corpus after this commit and check its passed manifest and hashes.

Follow-ups only, not part of this implementation: satellite/binary-star size,
live 280 ms installation feel, and whether a human wants stronger branch tint.
No economic, research-ID or save-format changes were made. No merge to main.

The earlier checkpoint entries below are history, not the current approval state.

## Earlier shutdown checkpoint — history

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
<!-- ORIGINAL-END -->
