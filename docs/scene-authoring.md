# Scene and resource authoring

Use this project rule when adding or refactoring Godot UI and reusable objects.
It adapts the approach in [Godot Scene Authoring Boundary](https://github.com/macian-games/godot-scene-authoring-boundary)
to Nightwatch Array. It does not change the visual direction or gameplay contract.

## Ownership

- Author stable node hierarchies, layout, default appearance and reusable child
  composition in `.tscn`. Keep reusable styles, fonts and configuration in
  resources when that removes duplication. A scene-local resource is sufficient
  until another scene actually needs it.
- Let GDScript instantiate those scenes, bind live data, route requests and update
  state, focus, visibility and animation. Prefer named scene nodes over fragile
  child indices. Separate views by a coherent responsibility, not by every label.
- Keep shared presentation consistent with `ui_theme.gd`. Authored values use the
  existing 1152×648 viewport units (1920×1080 design values × `UITheme.SCALE`).
  A future shared-theme migration must cover both authored and existing code UI;
  do not independently retune one copy during a structural refactor.

## Deliberate exceptions

Keep the existing procedural sky, constellation geometry, instrument drawing,
module glyphs, transient effects and diagnostic fixtures in code where appropriate.
Their custom drawing is intentional game art, not evidence of a missing asset.
Do not replace it with rectangular placeholders to satisfy a generic rule.
Runtime layout that depends on viewport, localization, pointer or live content
also remains code when needed. Explain new exceptions in normal English code
comments, following this repository's convention.

The upstream scanner is optional review assistance. It uses patterns rather than
semantic analysis; constructors, `add_child`, drawing and theme changes are not
automatic violations. Do not make zero scanner warnings a build requirement.

## Behavior-preserving migration

Move one bounded surface at a time. Preserve text, fonts, dimensions, colors,
layer/order, mouse filters, focus and keyboard routing, pause ownership, animation
timing and save behavior. Do not combine migration with visual improvements.
Capture the old and new implementation with identical fixture state in Korean
and English, including collapsed/expanded or other relevant states. Inspect the
images and compare stable pixels; run relevant interaction/lifecycle checks and
the required Windows export. A match in screenshots does not prove input behavior.

## First migrated surface

`scenes/ui/phase_summary.tscn` owns the round summary's fixed structure and styles.
`hud.gd` instantiates it and binds named nodes; it retains result formatting,
detail disclosure, reveal cancellation and the continue request. Game still owns
round transitions, pause and saves. Other HUD surfaces remain on their existing
construction path until separately migrated.
