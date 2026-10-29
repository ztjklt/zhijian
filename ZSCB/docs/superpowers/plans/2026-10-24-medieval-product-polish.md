# Medieval Product Polish Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development with user-authorized parallel agents and exclusive file ownership.

**Goal:** 交付丰富、贯通、可逐层探索与破坏的中世纪关卡，并适配真实窗口变化。

**Architecture:** Composition owns world/terrain/placement. Artwork owns22 generated PNGs and catalog JSON. UI owns responsive controls. Root owns damage-vs-walking collision split, catalog adapter, grass and integration.

**Tech Stack:** Existing Godot4.6.3, original character.tscn, builtin image_gen, native one-way physics.

**Spec:** ../specs/2026-10-24-medieval-product-polish-design.md

## Global Constraints
- User explicitly requests parallel subagents and full delivery; execute without another approval.
- Active untracked Godotproject ZSCB only; local patches, no commits/worktrees/deploy/remote builds, preserve other-chat changes and user live windows.
- Isolated tests via tests/run_isolated.py; never run save-writing tests in actual userdata.
- Pure black ink + existing paper; no replacement human style, no generated video.
- Separate physics roles: ground/platform1, player2, damage128, NPC64; BuildObject mask201, spawn clearance91; metadata map_drop_allowed on one-way supports.

## Review Focus
- OR mask collision rules accidentally keep NPCs blocked by damage bodies.
- One-way normal wrong on Y-up rotated slopes; falling brick hits platform but loses owner damage.
- New assets/count/range break old saves or silently resurrect destroyed scenery.
- GUI scaling changes world pointer/touch mapping or clips popup/large font on resize.
- New detail causes blade hit lag or clutter blocks meaningful traversal.

### Task1: Map composition and living routes
**Brief:** ../briefs/2026-10-24-product-map.md
- [ ] Write real traversal/route/content RED tests.
- [ ] Extend and populate coherent180m districts, normalNPC/cart routes and ground-fit props; save compatible bounded state.
- [ ] Test roads, route reachability, density/diversity and restore; report.

### Task2: Complete independent GPT artwork set
**Brief:** ../briefs/2026-10-24-product-art.md
- [ ] Publish catalog contracts then generate all22distinct assets, inspect, preserve originalPNG+prompts.
- [ ] Game gallery checks black ink/transparency/readability and every requested asset delivered; report.

### Task3: Responsive interface and viewport framing
**Brief:** ../briefs/2026-10-24-product-ui.md
- [ ] Test window resize RED including large displays and pointer positions.
- [ ] Implement uniform usefulUI scale, content layouts, panels and touch bounds; expose geometry needed by camera.
- [ ] Render small/large/resize cycle and test actual click mapping; report.

### Task4: Root collision, damage, grass and integration
- [ ] Add catalog adapter and distinguish full damage polygons from one-way walking surfaces.
- [ ] Implement canopy/roof/window/castle ledge routes, NPC collision group, BuildObject and spawn queries, live damage owner routing.
- [ ] Remove cut edge drawing, localize soft art chips and damaged support. Add severed grass stubble/feedback/save.
- [ ] Lower default ground framing and integrate map/UI/asset contracts.
- [ ] Scoped reviews + fixes, full relevant regression, actual wide/narrow/large gameplay capture and complete region traversal.
- [ ] Update SPEC/README/validation, preserve user old windows; launch new latest test window only after verification.

## Rulings
- Parallel execution is explicitly requested by user; exclusive files override skill sequential worker default.
- Preserve first104m coordinates for existing works; extend to180m instead of displacing current landmarks.
- Raise validated scenery budget to384 with offscreen work bounds, rather than hiding meaningful content behind decorative-only art.
