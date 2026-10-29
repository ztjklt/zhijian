# Living map world implementation — 2026-10-25

Status: world/terrain/composition source frozen; fauna-integrated density, real movement and migration verification passed41/41. Shared root agent owns final Metal captures, performance comparison and main/network migration integration.

## Implemented scope

- Terrain/content version3. West ground atx0 is10m; east ground atx180 is9.2m, with further mountain shoulders at the finite edges. West descent and central ridge have changing gradients; the eastern border is a raised8.4m settlement plateau.
- Village20–37, market40–54, castle68–88, farms108–128 and abbey147–160 keep level pads. Both river beds, water heights, deck geometries and physical crossings are retained.
- Fresh content has292entities: six deliberately spaced trees (previously12),88foliage (previously174),32people (previously20),6rabbits,4deer,4bats,3dragons and both horse/wagon/driver groups. IDs remain independent of record order.
- Adds28 actors:12 original-rig villagers,6 rabbits,4 deer,4 bats and2 additional dragons. Both horse/wagon/driver groups remain.
- Every actor continues full-rate simulation, gravity, water, collision and damage offscreen. Static scenery avoids repeated terrain/water calculations; its damage flash still advances. Drawing uses root's shared conservative visibility helper; terrain only submits visible hatching, bridge and water ink.

## Migration contract

`MedievalTerrain.upgrade_position(at:Vector2,from_version:int)->Vector2` accepts flatv1, exact-profilev2 and no-opv3 positions, preserving height above the old travel surface. The complete originalv2 profile is retained. Root consumes this helper for players and drawn objects.

`MedievalWorld.restore_state(records,source_terrain_version,source_content_version)` accepts1/2/3. Old untouched retired decoration is removed; damaged or dead records and cuts remain. Fixed props re-seat only when terrain changes, and crate stacks reattach to actual lower tops. Currentv3 positions retain exact roundtrip semantics. New seeding stops at384 records; it never discards protected old records to fit newcomers.

## Evidence so far

- `/tmp/medieval-living-red.log`:9 expected missing-behavior failures before implementation.
- `/tmp/medieval-living-routes.log`:58/58, actual player/NPC physics across all9districts, carriage/wheel support, low-ledges regressions, and new west/border uphill/downhill paths. Each new mountain route retains the75-tick/3.8m progress criterion.
- `/tmp/medieval-living-fusion.log`:51/51, terrain-relative uphill/brick/corpse fixtures and explicit currentv3 restore; weapon rays cross the new actual ground. Original thresholds retained; no runtime edits were needed for the five obsolete fixture failures.
- `/tmp/medieval-living-seams.log`:4/4, actual west/ridge slope seam crossing plus unchanged knockback and airborne velocity.
- `/tmp/medieval-living-content.log`:32/32, default292entities/41kinds/88foliage, stacked props, legacy content seeding, preservation and invalid-migration atomicity.
- `/tmp/medieval-living-green.log`:41/41, measured density,150actual physics ticks for added people/rabbit/deer/bat/dragon, flight altitude/gravity, version3 exact roundtrip, preserved dead/cut retired trees and384-record migration.
- `/tmp/medieval-living-diagnostic.log` preserves a genuine intermediate2-failure deer grounding regression. Both deer started with level rectangles penetrating a slope and were physically ejected beyond the follower's capture distance. Ground animals now receive their actual support pose before entering the physics tree; the passing rerun retains the same thresholds.
- `MedievalWorld.validate_snapshot(world:Dictionary)` is shared preflight for versions1–3, valid entity data and the legacy96-record cap. Root wires disk/network callers and owns atomic rejection tests.
- Final six-district Metal captures/performance comparison are owned by root; this worker does not substitute headless checks for visual evidence.

## Changed files

- scripts/medieval_composition.gd
- scripts/medieval_terrain.gd
- scripts/medieval_world.gd
- tests/medieval_living_world_test.gd (new)
- tests/medieval_product_content_test.gd (new version/density expectations)
- tests/medieval_product_routes_test.gd (four actual mountain routes)
- tests/medieval_product_seam_test.gd (west fixture follows new actual gradient break)
- tests/medieval_fusion_test.gd (terrain-relative fixtures and currentv3 snapshot restore)

No remote deployment, commits, user-save mutations or live-user-window changes. Existing TreeRoots deformation and placement are preserved.
