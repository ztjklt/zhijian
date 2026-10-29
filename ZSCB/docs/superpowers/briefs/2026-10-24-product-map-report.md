# Product map composition report — 2026-10-24

Implemented in the existing Godot project; no commits, remote builds, deployments, live-window interaction, or user-save changes. Tests use `python3 tests/run_isolated.py` exclusively.

## Delivered world

The authored world extends to 180 m and retains the original 0–104 m terrain and landmark coordinates. Nine section targets are woods 3, village 25.5, market 54, castle 77, ridge 92, farm 113, mill 134, abbey 153 and camp 172. Terrain and road profiles, rendering and collision use the same source geometry. The second river has a real bed below its continuous road crossing and an additional destructible stone route below the road.

Default population is 356 entities across 38 kinds: 68 retained originals plus 288 additions. All 22 new art kinds are used. 174 foliage instances form 29 irregular six-plant patches with woodland, meadow, garden, wet-bank and wheat-field palettes. Buildings and goods are deliberately grouped: village well and benches, market cargo, castle gardens/fountains, farm forge/windmill/inn, watermill and river landing, four ruined abbey arches, and a three-tent border camp with forge and well. Four crate stacks inherit their supporting crate's transformed top face.

Additional IDs use per-kind suffixes starting at 100. New villagers 100–106, knight 100, general 100 and a second uniquely associated horse/wagon/driver set have bounded patrol regions. Ground people and horses traverse facades and use the terrain/road; upper royal patrols retain castle support. Actual damage remains based on full silhouettes, resolving owned walk-surface contacts back to the entity.

## Persistence and placement

Content version 2 is separate from terrain version 2. Legacy content gains only missing expansion IDs; existing dead entities, cuts, poses, and the old modular castle remain intact. Current snapshots round-trip exactly and never reseed destroyed additions. Validation is transactional, permits the new x bounds [-5,185] and home bounds [0,180], and caps at 384 entities. The historical 96-entity maximum plus 288 additions fits exactly; oversized legacy records are rejected without changing the existing world.

Small-prop grounding samples each PNG's actual lower opaque envelope, caches those contacts, and balances its left/right terrain contacts. This fixed a measured 7.98 cm haystack gap caused by fitting the transparent bounding rectangle. Upper crates use actual support transforms. Safe spawning checks real walk surfaces rather than impassable facade silhouettes.

Actual patrol testing exposed a slope-knot physics synchronization bug: setting the node transform did not update the rigid-body server transform before the next tick. Ground-follow now synchronizes the corrected body transform, preserving tangent motion across knots while retaining hurt/airborne behavior. The patrol obstacle ray uses the physical ink mask rather than the player's layer.

## Verification

Latest completed isolated results (routes and seam tests rerun after final composition and owned-walk registration changes):

- `medieval_product_content_test.gd`: 32 checks passed — population, distribution, content migration, deaths/cuts, exact round-trip, crate supports, transactional validation and legacy capacity.
- `medieval_product_seam_test.gd`: 4 checks passed — actual slope-knot traversal and hurt/airborne preservation.
- `medieval_product_routes_test.gd`: 50 checks passed — actual player underpasses and NPC traversal in all nine districts, both moving horse/wagon sets, measured wheel contact and driver associations.
- `medieval_product_upper_routes_test.gd`: 1,858 checks passed — dense terrain continuity and directed landing graph. This graph uses conservative 2.9 m rise / 4.2 m horizontal reach; it is geometry verification, not a claim of automated physical jumps to every roof. Root separately owns actual controller castle climb tests.
- `medieval_product_prop_ink_test.gd`: 8 checks passed — independently sampled rendered alpha contacts on sloped small props.
- `medieval_world_test.gd`: 71 checks passed — updated through-facade contract, actual bounded patrol, restored masks, real driver impact and detachment preserved.
- `medieval_fusion_test.gd`: 51 checks passed with no script errors — original terrain fixture isolates new decor; richer full-map contact behavior is tested by the product routes suite.

Ten real 1440×900 district/lower-route renders and same-frame foot diagnostics are retained in [the map evidence folder](../../previews/2026-10-24-medieval-product/map/). The capture keeps the actual runtime controller and rigid-body physics active during rendering. A prior harness error (controller paused while bodies fell, disabling grounded IK) was diagnosed and corrected. Root's subsequent IK slope reach fix is included. Final screenshots contain 42 sampled visible ground soles with maximum absolute road gap **0.019211 m**, zero exceeding 0.04 m; see [contact-summary.json](../../previews/2026-10-24-medieval-product/map/contact-summary.json). Village, castle approach and mill images were visually reread after that fix, and the content suite reran cleanly with 32/32 checks.

Final art walk-edge metadata is integrated. The upper-route graph reran with 1,858 checks passing and 1,002 actual landing samples. No remaining scoped map/capture defect is known.

## Owned files

`scripts/medieval_world.gd`, `scripts/medieval_terrain.gd`, new `scripts/medieval_composition.gd`; the five product test scripts above; `tests/medieval_product_composition_visual.gd`; and the two existing medieval regression suites explicitly reassigned by root. Entity, catalog, player, PersonVisual, main/save integration, UI/camera and asset images/manifest are owned by the other workers.


## Final-art low-platform corner regression — 2026-10-25

Root reassigned `player.gd`, `main.gd::_assist_slope`, `medieval_walk_surfaces.gd` and the route test for a focused fix. Final art introduced accurately placed low windows, benches, fences and haystack slopes; the player could become pinched at x109 or be pulled upward by wall/slope assistance when a one-way corner was approached laterally.

Each walk body now retains its actual local edge endpoints as metadata. The player uses a bounded 1.2 m physics query to classify nearby faces. A face first approached from below or beside its actual horizontal span becomes a temporary collision exception until the circular foot is above the face and horizontally within it. Faces approached from above remain eligible throughout the solver's landing penetration margin, so fast downward landings are preserved. Sensor contacts, support rays, wall-climb rays (which already use body exceptions) and slope-assist rays agree with those exceptions. Deliberate drop-through keeps independent per-face state; lower platforms remain available. No damage silhouette changed. The speculative hay/tent edge truncation and medieval-specific slope-assist branch were removed.

Focused final evidence:

- Product routes **50/50**: original nine-district player/NPC/carriage checks plus normal-height farm approach, no underside hoisting, and sensor/support consistency. Elevated fixture x109 now travels to x114.7404 in 75 physics ticks, rather than remaining pinned at x108.9885. The additional normal approach starts at x108, y=ground+0.31 and crosses over 6 m without rising above ground+0.43.
- One-way physics **8/8**: ground underpass; jump through roof from below; land on roof; deliberate drop from y3.64675 to lower sill y1.785; local roof damage removes support.
- Actual castle climb **8/8**: ground y3.685 → y6.640 → y9.595 → tower crown y12.049 through unchanged double-jump controller.
- Traversal **25/25**: independent thin surfaces, damage owner metadata, foliage/collision and local damage contracts.

Root owns the broader final regression rerun after this handoff. No live-window or user-save changes were made.
