# Independent product review — 2026-10-24

Reviewed the task brief, current `AGENTS.md` / `SPEC.md`, product design, scoped current implementation against `.superpowers/sdd/2026-10-24-medieval-product-polish/baseline/scripts`, the new traversal/composition/UI test logic, asset provenance manifest, and actual rendered evidence. No production files, running windows, saves, network state, or remote services were changed. This report is the only reviewer-authored file.

## Final review status

**No open critical or important findings in the reviewed scope.** The earlier P2 below is closed after source and final rendered-evidence review. This is a scoped code/product review, not a claim of deployment or validation on every device.

## Final-art underpass follow-up — 2026-10-25

**P2 (reopened, then closed after the focused fix) — Final low ledges trapped the ground player in the farm.** The final art calibration exposed actual one-way corner pinching near x109, and a first attempted slope-assist fix also broke village traversal. These were concrete gameplay failures, so the earlier review acceptance did not cover that intermediate state.

I reviewed only the subsequent focused delta: `StickmanPlayer.update_owned_surfaces`, `_surface_clearance`, `_inside_surface_span`, the shared sensor/support exception handling, the walk-body edge metadata, and `main.gd::_assist_slope` ray exclusions. Clearance uses the actual edge plane and the player's 0.29 m circle radius. Per-player exceptions distinguish an initial below/side approach from an eligible landing, restore only after clearing the face within its real span, and retain explicit drop-through as separate state. Support rays, foot contacts, and slope assistance share those exceptions. Full final-art contours remain intact. I found no new important correctness defect in this focused change.

Fresh independent root evidence was read from `docs/previews/2026-10-24-medieval-product/regression-results.json` (current `output`, not retained `previous_output`) and `/tmp/medieval-product-targeted-final.log`:

- Actual district routes: **50 checks, 0 failures**. Village x21→26.74036 and farm x109→114.7404 both progress with the real player. The additional normal-height approach begins at x108, ground+0.31, crosses over 6 m, stays below ground+0.43, and checks that ignored undersides do not produce false support rays or foot contacts.
- One-way physics: **8 checks, 0 failures**, including a roof landing, drop to the lower sill at y1.785, and damage removing support.
- Actual castle controller climb: **8 checks, 0 failures**, y3.685→6.640→9.595→12.049.
- Traversal contracts: **25 checks, 0 failures**.
- The root's completed 16-suite focused rerun includes general movement, building physics, wall climb, knowledge integration, spawn clearance, session preservation and network gameplay; its final retained suite summary is **56/56**.

This closes the farm/village underpass P2 with actual movement and independent landing/drop evidence, rather than a landing-graph count. Earlier failed route logs remain historical evidence and are superseded by these current outputs. I did not run parallel tests or performance work during this review.

## Closed finding and verification

**P2 (closed) — Earlier district captures showed villagers walking with both feet visibly above the road.** The original village capture had a roughly 15–20 pixel gap, with similar river/farm/abbey symptoms. The capture fixture had disabled the controller while allowing physics/render frames to advance, causing downward velocity to cross the visual IK exclusion threshold. The final fixture now runs the real controller and physics during its final render frames and records same-frame sole coordinates.

I reviewed the final `medieval_person_visual.gd` changes: downward velocity alone no longer rejects support adaptation; proximity and hurt/upward-motion exclusions remain, and excessive downhill leg reach is corrected by a bounded hip adjustment. I also reviewed `WalkSurfaces.register_surfaces()` and its call from `MedievalEntity._ready()`, which cover existing actors when static props were set up before parenting. The actual-world contact test now checks both visual soles across 420 physical ticks: `/tmp/medieval-ground-contact.log` reports **384 checks, 0 failures**. This closes the weakness in the older route assertion, which only bounded NPC height from below.

I opened and read final village, castle and mill-river screenshots in `docs/previews/2026-10-24-medieval-product/map/`; the visible road/bridge walkers now meet their surfaces. I read the three corresponding foot JSONs and the summary: **42 visible ground-sole measurements, maximum absolute gap 0.0192109104468079 m, zero failures** against the 0.04 m criterion. The village and mill NPCs that made the original issue obvious now have near-zero measured gaps. No new important defect was found in these fixes.

## Other review results

- No additional critical or important correctness issue was found in the scoped changes. The collision split coherently separates damage silhouettes (128), ground NPCs (64), player (2), static walk surfaces (1), and authored ink (1 or 8). The current bitwise build/query masks correctly avoid native-agent 16. Per-segment ownership routes impact damage to the correct entity; ground actors ignore those authored walk surfaces while royalty retains elevated supports.
- The roof-ridge drop expansion and thin-shape clearance address adjacency and premature/late collision restoration without globally disabling terrain. Damage regenerates walk segments, clips the same art, wakes nearby unsupported bodies, and retains grass stubble. I found no old black damage-edge drawing in the scoped render delta.
- Expansion is authored in district groups with stable IDs, independent generated assets and source prompts, ground/river routing, extra actors, and a separate carriage association. I did not re-investigate the snapshot migration issue already owned and resolved by root.
- UI uses shared bounded scaling and distinguishes logical layout from physical hit rectangles. I read the 390×844 world/bag, 844×390 experience, and 3840×2160 world captures, plus village, farm, river, abbey and castle captures. Those sampled UI layouts have reachable controls without a newly observed clipping defect. The source report separately documents all fifteen sizes and actual GUI-input checks.
- The minor documentation issue is also closed: `docs/superpowers/specs/2026-10-24-medieval-product-polish-design.md:7` now correctly names damage layer 128 and ink contact with 128, leaving native agents on 16.

## Evidence limits

I reviewed the fresh test reports and test implementation; I did not rerun the suite while root was running final performance/validation work. I read the completed quiet performance log `/tmp/medieval-product-weapon-performance.log`: **0 failures**, highest reported CPU sample **13.331 ms**. `medieval_product_upper_routes_test.gd` is a conservative landing-reachability graph plus 1,800 terrain-continuity assertions, not 1,858 physical controller traversals. Keep that distinct from the real player house/drop/castle/district tests in the final validation account. The new map is not the already deployed Railway snapshot. No outstanding review gate remains from the grounding or quiet performance issues described in the first version of this report.
