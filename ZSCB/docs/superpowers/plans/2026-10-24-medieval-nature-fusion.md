# Medieval Nature Fusion Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans. Independent terrain and character tasks use dispatching-parallel-agents with separate file ownership.

**Goal:** 融合山野与中世纪的真实山水地图，NPC回归原主角火柴人风格。

**Architecture:** MedievalTerrain owns shared ground/water/bridge geometry and physics. MedievalWorld places existing props on it and exposes ground/contact/migration contracts. Separate people renderer instantiates the exact hero scene for villager/driver; main/core only routes map terrain and save schema.

**Tech Stack:** Existing Godot4.6.3, GDScript, original Skeleton2D rig, existing GPT prop PNGs.

**Spec:** ../specs/2026-10-24-medieval-nature-fusion-design.md

## Global Constraints
- Current untracked workspace is the user’s active project; local patches, no commits/worktrees/deploy/build.
- Read ZSCB AGENTS/SPEC, preserve other-chat changes and original knowledge/nature fixtures.
- Tests via tests/run_isolated.py only; no real user-save writes.
- Terrain is geometry with real collision, no new AI image backdrop. All people use original character.tscn assets and bones in every state.

## Review Focus
- Legacy flat collider left underneath river; phantom support or arrow collision.
- Props/NPCs/cart stay at old flat Y; roof/ground overlap or patrol stuck on inclines.
- Save migration repeats height offset, erases cuts/deaths or breaks old nature workspaces.
- NPC art matches idle but changes to old sprite for hurt/dead; mounted/dead rig lifecycle leaks.
- Broad phase terrain contacts lose nearest occlusion or complex weapons exceed frame budget.

### Task1: Shared terrain, world placement and core physics
**Own:** scripts/medieval_terrain.gd, medieval_world.gd, main.gd, medieval_controls.gd, paper_combat.gd; tests/medieval_fusion_test.gd plus relevant world/performance fixtures.
- [x] Observe RED for nonflat support, river geometry, terrain occlusion, migration and safe spawn.
- [x] Add shared surface_height(x), travel_height(x), collision_geometry, build_physics(parent), draw_world(canvas,game), in-water response. MedievalWorld exposes terrain, surface_height, safe_spawn_position and full nearest terrain/entity contacts.
- [x] Remove medieval hidden flat floor. Keep actual terrain at all active NPC/object positions, ground_height_at and terrain_spawn correct, safe Home/return below-map handling.
- [x] Reposition houses/market/castle to plateaus, other props at sampled ground; grounded actors follow slopes while injured/airborne actors retain physics; horse/cart/driver follow correct elevation.
- [x] Save terrain_version=2; legacy missing version migrates once retaining cuts/death; new saves restore unchanged.
- [x] Isolated terrain, combat, world and performance tests.

### Task2: Original fire-stick character NPC renderer
**Own:** scripts/medieval_entity.gd, medieval_person_visual.gd, medieval_person_outfit.gd; tests/medieval_people_test.gd. No Task1 files or shared character_visual.gd edits without coordination.
- [x] Observe RED for absence of original character rig/legacy people textures.
- [x] Instantiate original character.tscn for villager and driver with same limbs/head/eye resources and Skeleton2D, animation. Fit physics size and root anchor to same person scale as hero.
- [x] Original rig stays for walking/hurt/flying/dead/mounted/detached states. Add restrained hat/clothes overlays bound to bones, no replacement human body. Avoid native-agent material recolor changing identity; no held weapons on villagers.
- [x] Correct creation/cleanup during restore, map sessions and deferred impact detach. Expose person_visual for world tests; keep entity API and record schema backward compatible.
- [x] Isolated visual-consistency and existing combat/world tests.

### Task3: Start menu, spec, save validation and visual acceptance
**Own root:** map_select.gd, knowledge_map_controls.gd, experience_panel.gd, save_store.gd, SPEC/README/docs and tests/medieval_fusion_visual.gd, integration tests.
- [x] Current start menu has fused medieval+knowledge choices; old nature saves retain explicit legacy continue access.
- [x] Validate bounded terrain version with both current/inactive world data; preserve all old paths and rejection behavior.
- [x] Update actual world descriptions to real implemented mountain/river routes and original stickmen.
- [x] Run current relevant and full isolated suite once; inspect wide/narrow hills/river/castle and original-player/villager/death screenshots, fresh scoped review.

## Rulings
- User directly requested this correction and explained the desired form; implementation proceeds on that authorization without another confirmation step.
- Terrain and people are independent modules with exclusive write sets; root handles integration after their interfaces settle.

### Task4: User-added role models and grand castle
- [x] People agent: alpha-derived head contact for hats, gentle eyes, six role profiles using the original rig, pose/state tests and actual visual lineup.
- [x] Castle agent: deterministic contiguous tile layout derived from a unified GPT castle concept, within96-entity save bound, physical giant-brick impact verification.
- [x] Root: integrate role population/layout, review and rerender actual wide/narrow castle and people.

## Completion evidence

Completed 2026-10-24. Main fusion visual capture uses Metal at1440×900 and390×844, with the hero genuinely settled before photographs. A full43-script isolated run plus the new77-check raster-contact suite are green (44 suites total); obsolete nature-card assertion was corrected and its saved-work continuation rerun. New castle uses32 contiguous atlas tiles from a GPT master, rather than stacking the previous inconsistent standalone parts. Final wheel and royal support findings resolved; horse/dragon pivot mirroring additionally corrected after visual inspection. Full evidence and test logs: docs/MEDIEVAL_FUSION_VALIDATION_2026-10-24.md and docs/previews/2026-10-24-medieval-fusion/.
