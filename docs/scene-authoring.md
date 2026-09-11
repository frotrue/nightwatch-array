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
  Shared control styles and fonts live in `resources/ui/`; `ui_theme.gd` loads
  the same tabular font and data-tooltip theme for runtime bindings. Its color
  constants also support procedural drawing. Palette changes must cover scene
  role overrides and drawing together; do not retune either during refactoring.

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

## Authored surfaces

All fixed UI, including the probe HUD, follows this boundary.
Controllers bind scene-owned named nodes and connect live requests. Do not add
another code-built fixed surface alongside these scenes.

| Surface | Scene under `scenes/ui/` | Runtime owner |
|---|---|---|
| Observation HUD | `hud.tscn` and its readout/banner scenes | `hud.gd` |
| Settings and six pages | `settings.tscn`, `settings_*.tscn` | `hud.gd` |
| Startup/save rows | `startup.tscn`, `startup_slot.tscn`, `save_slot.tscn` | HUD binds slot summaries/actions |
| Round summary | `phase_summary.tscn` | HUD binds result, disclosure and reveal lifecycle |
| Debug display | `debug_hud.tscn` | HUD |
| Optional performance monitor | `performance_monitor.tscn` | `ui/performance_monitor.gd`, optional Windows pipe sampler |
| Research chart | `upgrade_tree.tscn`, `chart_header.tscn`, inspector/ledger scenes | `upgrade_tree.gd` |
| Repeated research star | `research_star.tscn` | Catalogue-driven instantiation and procedural marker |
| Module loadout | `module_popup.tscn`, `module_tooltip.tscn` | `module_popup.gd` |
| Repeated module controls | `module_inventory_tile.tscn`, `module_ring_slot.tscn`, `module_action.tscn` | Catalogue/slot data and chart-relative placement |
| Module draw | `module_draw.tscn` | `module_draw_window.gd` |
| Tutorial | `tutorial_controller.tscn` | Tutorial step/pause controller |
| Layer 2 diagnostic | `probe_hud.tscn` | `probe/probe_hud.gd` |

`scripts/ui/` contains the custom ring, inventory tile and tracking control
scripts needed by these scenes. They preserve the original drawing and runtime
state. The chart still derives research content/positions from its catalogue.
Native confirmation dialogs generate their internal controls inside Godot;
HUD attaches the `native_dialog*.tres` themes to those controls after instantiation.
Option-button metadata and translated initial slot values are bound in code,
because scene serialization does not preserve that runtime metadata/localization.

Game retains all progression, round transitions, pause ownership and persistence.
The migration tools and before/after captures in `build/` are diagnostic artifacts;
no generated-tree loader or migration tool is part of the shipped runtime.

The Compatibility fallback retains a 65,536-command canvas item buffer. Showing all
14 inventory glyphs alongside Korean tooltips exceeded the default
16,384 limit and dropped UI drawing commands in reproducible captures. Keep this
headroom when changing the loadout layout; the setting is documented in
[Godot ProjectSettings](https://docs.godotengine.org/en/4.4/classes/class_projectsettings.html#class-projectsettings-property-rendering-gl-compatibility-item-buffer-size).
