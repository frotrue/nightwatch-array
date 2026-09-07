# Visual and Audio Validation

Use this page for changes to layout, markers, fonts, palette, effects or sound.
Run from the repository root with `$godot` from the [README](../README.md#실행과-빌드).
Mechanical gates and isolation requirements are in [probes.md](probes.md).

## Rendering and evidence

This Windows Godot build uses dummy rendering in headless mode. Captures need a
logged-in desktop and the real Windows/OpenGL Compatibility renderer. A typical command is:

```powershell
& $godot --display-driver windows --rendering-driver opengl3 `
    --rendering-method gl_compatibility --audio-driver Dummy `
    --position '-4000,-4000' --resolution 1152x648 `
    --path . --script res://tests/capture_reference.gd
```

Capture before and after a visual change. Inspect layout, clipping, hierarchy,
legibility and unintended differences at 1152×648; stable pixels are not a design verdict.
Use English and Korean where copy is involved. Source identity, fixture state and
actual file hashes establish what a capture shows; filenames such as `current` do not.
Real-time motion, density, sound quality and input comfort still require appropriate playback/playtests.

## Reference corpus

`tests/capture_reference.gd` produces thirteen reference images under a unique
`build/reference/<revision>[_dirty]_<timestamp>/`. It rejects `--headless`.

The scenarios cover active observation, synthetic density, both meteor families,
sky sweep, summary, research chart, expanded sky, legacy transit/map/ending and
two synthetic research palettes. The palette plates each contain 117 markers:
thirteen branches × three marker kinds × three states. They are diagnostics, not gameplay screens.

The fixture replaces persistence before `_ready()`, disables hardware input,
fixes RNG/positions/clocks and checks expected state before and after rendering.
Images must have the right dimensions, visible dark/light pixels and identical
pixel hashes on two consecutive frames within twelve attempts. A 90s watchdog bounds the run.

Accept only a complete manifest with `status: passed`, matching JSON sidecars and
matching PNG hashes. These record Git HEAD, dirty state, tracked/non-ignored source
hashes, source digest, engine/renderer/viewport and scenario state.
`REFERENCE_CAPTURE_PASS` confirms mechanical completion; partial directories are invalid.
`REFERENCE_CAPTURE_DIRTY` means base HEAD plus the recorded working tree, not a clean commit.
Refresh after commit when a clean revision baseline is needed.

For a palette change, compare active cells and require the unchanged inactive plate
to remain identical. Use normal scene states to judge context. The headless
`reference_capture_test.gd` gate checks state and error handling, not PNG rendering.

## Targeted previews

Run without `--headless`; the same renderer flags above can be used.

| Script under `tests/` | Output and coverage | Marker |
|---|---|---|
| `deep_sky_preview.gd` | Sixteen stable frames in `build/deep_sky_review/<timestamp>/`: original sky/M31, chart gates/purchases, module popup, locked/equipped/full states and edge tooltips in en/ko | `DEEP_SKY_PREVIEW_PASS` |
| `effect_feedback_preview.gd` | Six PNG/JSON pairs in `build/effect_feedback_review/`: routine/accent poses, visible installation-rule start/mid/end, continuation selection | `EFFECT_PREVIEW_PASS` |
| `research_chart_preview.gd` | `build/research_chart_preview.png`; synthetic 81/107 research, 1,284,000 Data, fifth-round/80s pose | `PREVIEW_SAVED` |
| `hud_preview.gd` | `build/hud_preview.png` or selected diagnostic pose below | `PREVIEW_SAVED` |

Deep-sky capture has a 45s watchdog and validates frozen fixtures, source/image hashes
and stable frames. The effect preview checks real production purchase/completion routes.
Preview marker semantics differ: legacy `PREVIEW_SAVED` only confirms a file write.
The chart's 80s diagnostic label does not change playable round duration.

Set only the variables needed for a pose and remove/restore them afterwards:

| Script | Variable | Result |
|---|---|---|
| Chart | `NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW=1` | `galactic_research_preview.png` |
| Chart | `NIGHTWATCH_GALACTIC_RESEARCH_PREVIEW_TIME=0.65` with the flag above | Intermediate pull-back; time 0–3.6s |
| HUD | `NIGHTWATCH_SURVEY_PREVIEW=1` | `survey_preview.png`, partially charged sweep |
| HUD | `NIGHTWATCH_GALACTIC_PREVIEW=1` | `galactic_preview.png`, completed-research diagnostic sky |
| HUD | `NIGHTWATCH_TRANSIT_PREVIEW=1` | `transit_preview.png`, legacy first transit at 48% |
| HUD | `NIGHTWATCH_ENDING_PREVIEW=1` | `ending_preview.png`, non-persistent legacy ending |
| Ending | `NIGHTWATCH_ENDING_PREVIEW_STEP` | 2.8s constellations / 5.2s transition / 8.1s final (default) |
| Ending | `NIGHTWATCH_ENDING_PREVIEW_LOCALE=en` or `ko` | Localized ending capture |

Legacy HUD/chart poses may overwrite the same filename. Inspect or copy a frame
before another run. Legacy previews do not define new M31 content.

## Settings and display

After changing settings copy, scale, spacing or focusable controls, inspect all six
pages, including English/Korean Controls and Accessibility.

```powershell
$env:NIGHTWATCH_SETTINGS_PREVIEW = 'controls'
$env:NIGHTWATCH_SETTINGS_LOCALE = 'ko'
try {
    & $godot --path . --script res://tests/settings_preview.gd
} finally {
    Remove-Item Env:NIGHTWATCH_SETTINGS_PREVIEW -ErrorAction SilentlyContinue
    Remove-Item Env:NIGHTWATCH_SETTINGS_LOCALE -ErrorAction SilentlyContinue
}
& $godot --path . --script res://tests/settings_windowed_test.gd
```

Page values: `general`, `audio`, `display`, `accessibility`, `controls`, `save`.
Output is `build/settings_<page>[_ko]_preview.png`. `SETTINGS_PREVIEW_SAVED` requires
two stable non-empty frames. `SETTINGS_WINDOWED_PASS` checks startup focus, the actual
FPS cap and both VSync states, which headless fixtures cannot establish.

## Audio audition

`sound_feedback_test.gd` checks dispatch and PCM properties. Listen to the audition
for perceived distinction and gaps between automatic pulses:

```powershell
& $godot --path . --script res://tests/sound_feedback_preview.gd
```

It plays research, slot, rare-target and environment cues, then isolated and
batched automatic successes with manual events. It writes
`build/audio_feedback_audition.wav` and a JSON manifest with timestamps/source hash.
The fixture records its own Master bus, not microphone/OS loopback, and preserves
player saves/settings and original bus state. `SOUND_AUDITION_SAVED` requires a
complete schedule and non-silent PCM, not a perceptual pass.

On this machine WASAPI exposes four stereo pairs and recording can select a silent pair.
Use the explicit software-mixer path instead of changing Windows speaker configuration:

```powershell
$env:NIGHTWATCH_AUDITION_ALLOW_DUMMY = '1'
try {
    & $godot --headless --audio-driver Dummy --path . --script res://tests/sound_feedback_preview.gd
} finally {
    Remove-Item Env:NIGHTWATCH_AUDITION_ALLOW_DUMMY -ErrorAction SilentlyContinue
}
```

Its manifest declares `driver: Dummy` and `hardware_output: false`. The WAV is
listenable evidence, not proof of hardware output. The isolated automatic pulse
retains its intentional 160ms aggregation delay; manual success stays immediate.
