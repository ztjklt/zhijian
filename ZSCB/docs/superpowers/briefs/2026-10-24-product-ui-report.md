# Product UI responsive window delivery — 2026-10-24

Implemented the assigned UI and camera work in the existing Godot product. No commits, remote builds, deployment, user save changes, or running-user-window changes.

## Files

- New `scripts/gui_scale.gd`: shared bounded UI factor `clamp(min(width/1280, height/720), 1, 3)`; logical UI coordinates with physical input bounds. Popup Window font metrics scale separately.
- `scripts/toolbar.gd`, `backpack_panel.gd`, `experience_panel.gd`, `map_select.gd`: text, buttons, panels and paper textures scale together; live resize uses the original values and never accumulates font overrides. Backpack stays at the physical right margin and keeps reuse/paging outside scroll regions. Compact action strip uses less empty height.
- `scripts/medieval_controls.gd`, `knowledge_map_controls.gd`: same shared scale, physical blocking rectangles, compact navigation; medieval trial controls remain available through the experience menu on narrow screens.
- `scripts/touch_controls.gd`: physical movement/generation/attack rectangles and text scale together; existing finger ownership and UI hit testing retained.
- `scripts/combat_visual.gd`: only `_draw_hint`; typography and charge meter scale, hint clears the actual navigation rectangle, hides behind modals.
- `scripts/main.gd`: only agreed camera functions `_ground_margin`, `_resize_world`, `camera_target_y`, final UI-setup resize, and explicitly authorized single `_resize_world()` after knowledge-world attachment. Camera uses physical UI rectangles; medieval player anchors at 76% of playable height, leaving headroom for roof routes. World pixels/meter uses base constants times UI factor, preserving usable world size at large windows. Knowledge overview preserves its overview fit and restores the current normal zoom after a resize.
- New `tests/responsive_ui_test.gd`, `tests/responsive_ui_visual.gd`.

`paper_theme.gd` and generated textures remain intact. Network lobby/settings/cover code from the other chat was preserved.

## Fresh verification

All tests were run through `python3 tests/run_isolated.py` in independent project/user-data copies.

- `res://tests/responsive_ui_test.gd`: **178 checks, 0 failures**. Sequence: 1280×720 →1920×1080 →2560×1440 →3840×2160 →1280×720 →390×844 →844×390. Covers physical font/button growth, no zoom drift, actual GUI mouse motion/press/release choosing tools/opening bag/reusing a blueprint without drawing, global touch bounds, right anchoring, panel/scroll visibility, popup font metrics, world-coordinate roundtrip, low camera framing, initial large knowledge entry and overview resize restoration, map-select live resize. The same suite also passed **178/178 using actual Metal rendering**. Popup metrics are inspected by opening the real PopupMenu separately; viewport GUI events are routed directly through Window.push_input to avoid native OS popup-focus races in the automated press/release sequence. Final fixture embeds popups in its isolated viewport and routes each complete InputEvent mouse gesture in one frame; this avoids OS pointer motion splitting synthetic press/release pairs during rapid resizing. The final Metal run passed 178/178. Earlier multi-frame synthetic Metal gestures were intermittent and are not treated as final evidence.
- `res://tests/paper_ui_test.gd`: **264 checks, 0 failures**.
- `res://tests/experience_test.gd`: **24 checks, 0 failures**.
- `res://tests/game_ui_loop_test.gd`: **19 checks, 0 failures**.
- `res://tests/responsive_ui_visual.gd --visual`: **15 actual Metal screenshots**, no Godot errors. Renderer: Metal 4.0 Forward+ / Apple M4 Max. World, populated bag and experience modal at each of **1440×900, 2560×1440, 3840×2160, 390×844, 844×390**. Every requested pixel size was verified from the PNG header. The isolated visual window uses min_size to prevent macOS from clamping the 4K request to usable desktop height.

## Evidence

`docs/superpowers/evidence/2026-10-24-responsive-ui/manifest.json` records renderer, generator and all fifteen exact dimensions. Sibling PNGs are named `world-*`, `bag-*`, `experience-*`.

I inspected all fifteen rendered screenshots. Inspection found and corrected two issues beyond metric checks: a scaled root panel's own position also needed physical scaling to keep the bag against the right edge; the fixed combat hint overlapped narrow medieval navigation. Final large bag and narrow-world images were inspected again after those corrections. At 4K, tool font is 45 physical pixels and 44-pixel baseline targets are 132 physical pixels; 2560 uses 2×, 1920 uses 1.5×. Narrow screens retain baseline readable sizes with compact layout and scrollable secondary controls.

## Limits and integration notes

- Tested resize/input and screenshots on this macOS/Metal machine. Real touchscreen hardware and other OS display scaling remain unverified; existing finger ownership and manually routed touch-bound tests pass.
- The 844×390 view has deliberately compact tool/navigation strips and limited vertical world area; all essential actions remain reachable and the lower camera anchor remains between the actual UI bounds. Desktop/high-resolution windows retain a consistent visible world scale.
- Screenshot evidence captures the shared map state when generated; later root/art/map edits may change map art/content without changing these UI metrics. Root should use final integration screenshots for the entire product's final visual claim.
- Two isolated runs captured concurrent intermediate project edits (missing Entity.supported_kind and player polygon inference); those runs were discarded and followed by passing fresh runs. They are not UI failures or passing evidence.
