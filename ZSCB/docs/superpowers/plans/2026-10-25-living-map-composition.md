# Living Map Composition Implementation Plan

> For agentic workers: execute this assigned slice natively; no additional agents, commits, remote builds or user-window changes.

**Goal:** A clearer medieval world with fewer trees and repeated plants, more moving life, higher mountain ends and safe existing saves.
**Architecture:** Preserve stable entity identities. Retain version2 terrain coordinates for elevation-relative migration; version3 content filters old authored decoration without reindexing IDs. Full-rate actor physics continues while static processing and rendering are bounded by actual need.
**Tech Stack:** Godot4.6, GDScript, isolated project tests.
**Spec:** ZSCB/SPEC.md plus latest user request delegated by root on2026-10-25.

## Constraints and interfaces
- Owned files: medieval_composition.gd, medieval_terrain.gd, medieval_world.gd and related tests.
- Terrain.VERSION3, upgrade_position(at:Vector2,from_version:int)->Vector2 supports1/2/3.
- World.CONTENT_VERSION3, restore_state accepts1/2/3 and retains damage/death/cut data.
- Root owns main/save/net and shared MedievalVisibility.entity_visible(game,entity,margin_m=1.5).
- Art worker supplies rabbit/deer/bat and is_ground_animal(); ground contacts .05m and .335*width support.
- Six trees;88 plants;28 extra actors:12people,6rabbit,4deer,4bat,2dragon.384-record ceiling.

## Review focus
- Old damaged or dead retired decoration must remain saved.
- v3 load must not shift height twice.
- Maximum legacy records must not overflow384.
- Raised settlements must stay on flat pads; bridges/water remain physically aligned.
- Culling must never disable actor physics, damage, water or network simulation.

## Execution
- [x] Read current world, terrain, composition, tree-root integration and requirements.
- [x] Write living-world density/terrain/migration RED fixture; run via run_isolated.
- [x] Preserve exact v2 profile, implement v3 profile and migration.
- [x] Thin defaults by stable identity; add actors and patrol ranges.
- [x] Integrate restoration, cap-safe seeding, static-step and draw optimization.
- [x] Run focused migration/content41+32, real patrol/routes58 and seam4 checks; root covers broader water/tree regressions.
- [x] Hand off exact world report and quiet CPU window; root owns final six-district Metal samples/performance comparison.
