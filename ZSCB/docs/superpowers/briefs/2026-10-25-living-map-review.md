# Living map independent review — 2026-10-25

Scope: SPEC v0.23's smoother medieval world, sparse decor, additional physical fauna and people, higher mountain ends, terrain/content revision 3 migration, and translucent compact bottom controls. Production files, user saves, windows, Git and remote services are not modified by this review.

Status: functional source review and independent six-view Metal verification complete; both concrete review findings are closed. The subsequently discovered runtime lifecycle regression is also closed after focused regression and clean direct-launch evidence; no open findings remain. Final fauna gallery, atlas regions and constant pixel-scale mapping have now also been independently inspected and accepted. No historical full-suite rerun was performed.

## Findings and closure

**P2 — Closed: validate the complete migration envelope before replacing a world.** `scripts/net/room.gd` `_import_world` validates entity records but not `terrain_version` / `content_version`; `PaperWorldStore._valid_data` does not validate this envelope either. `MedievalWorld.restore_state` additionally rejects unsupported versions and content-version-1 snapshots with more than 96 records. An otherwise valid import with terrain version 4, or 97 valid entities tagged content version 1, can therefore be persisted and replace creations before `restore_state` returns false. The return is ignored and import reports success while retaining the previous live entities. Local `SaveStore._valid_world` also accepts the latter 97-record case and `main.load_game` ignores restore failure. Share the full envelope validator among storage/import/restore, and reject before either persistence or live mutation. Suggested checks: unknown/fractional version, content-v1 97 records, unchanged live creations/entities and stored snapshot after rejection.

The shared `MedievalWorld.validate_snapshot` now checks numeric finite integral revisions, record validation and the v1 cap before storage or mutation. Call sites cover local save/load, authoritative storage/import and undo restoration. Retained fresh `/tmp/living-final-living_map_migration_test.log`: 20 checks, 0 failures. Source and evidence close this finding.

**P2 — Closed: downhill walking feet lose terrain support on the new mountain slope.** Fresh `/tmp/living-final-medieval_ground_people_contact_test.log` reports 12 failures out of 672 checks, all `villager-108` around x12.24–14.27; rendered sole gaps are 0.177–0.757 m. The body remains near the uphill footprint support. `medieval_person_visual.gd` `_support_at` (terrain branch lines159–162) requires every foot candidate to lie within0.22 m of the body origin. A legitimate downhill sole on the new -0.9 gradient can exceed this narrow band; `_adapt_grounded_feet` then resets the entire IK when a foot has no support (lines187–193). Keep the grounded-body check, and choose foot targets relative to grounded support / actual leg reach. The fix retains the strict grounded-center gate and increases only terrain foot tolerance by the local center-to-sole terrain height difference. Fresh `/tmp/living-ground-people-final.log`: 672 checks, 0 failures, `/tmp/living-people-final.log`: 1235 checks, 0 failures. Source and the same real-physics regression close the finding. `/tmp/medieval-living-fusion.log`: 51 checks, 0 failures after updating old flat/v2 fixture coordinates to v3; the earlier five failures are retained separately.

## Source review observations

- `MedievalVisibility.entity_visible` uses a full size diagonal plus 1.5 m around the current projected body anchor. The padding conservatively covers rotated props, wings and normal actor identity accessories. It only controls rendering; world actor stepping and rigid bodies remain active.
- Person rigs update visibility every process frame and refresh current body pose immediately on return. Shared head shader materials have no per-actor parameter mutations. Castle atlas tiles likewise share a shader; their cached local vertices/UVs rebuild on each added cut. Current live castle geometry changes only through added cuts; destruction hides the tile and restored entities receive new visuals.
- Static work removal skips locomotion/water calculations for already frozen scenery, while hurt flashing still advances; actors, water reactions, wagon following and impacts continue independently of visibility.
- Retired decor removal is conditional on alive, pristine health and no cuts. Dead/cut/degraded records remain. Expansion stops at 384 and does not evict preserved records. Terrain migration preserves relative elevation using the actual old profile and road decks; v3 coordinates are unchanged.
- Bottom panel has an empty style, ignored mouse input and compact children. Only button rectangles block canvas input, including disabled controls; floating status space permits drawing. Read desktop and portrait Metal captures and inspected the real-input test. Captures made during fauna integration are UI evidence only, not final map evidence.

## Evidence

Existing worker/root evidence (not independently rerun): world 41 checks including150 physical ticks, migration20 and visibility13 (including offscreen damage-cache refresh and edge visibility); UI bottom HUD 263 checks, responsive UI 178, GUI loop 19 and 12 Metal captures; mountain traversal 58 checks. Relevant source/tests inspected: `medieval_living_world_test.gd`, `living_map_migration_test.gd`, `medieval_visibility_test.gd`, `medieval_fauna_test.gd`, `bottom_hud_test.gd`.

Baseline: `docs/previews/2026-10-25-living-map/baseline-profile.json`, six 1440×900 Metal views, 356 entities; elapsed-frame medians 11.677–12.304 ms and draw-call snapshots 422–589. `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` monitors retain stale startup values in the first view (116 ms / 1459 ms), so these are not valid steady-state per-frame measurements. Compare elapsed frame intervals and draw submissions, and report hardware/load dependence rather than promising a universal frame rate.


## Independent final Metal result

Command run once in a quiet window after confirming no active isolated test processes:

`PAPER_LIVING_PROFILE_PHASE=final python3 tests/run_isolated.py --visual --script res://tests/living_map_profile.gd`

Exit 0; no script errors. Full stdout/stderr: `/tmp/living-map-profile-independent.log`. Godot 4.6.3, Metal 4.0 Forward+, Apple M4 Max, 1440×900. Output: `docs/previews/2026-10-25-living-map/final-profile.json` plus `final-{9,30,55,77,113,172}.png`. All six screenshots were opened and inspected. World has 292 entities versus baseline356, including the expanded actor population. The profile measures presentation and normal active world simulation; it does not change physics to obtain these numbers.

| View X | Median frame ms before → after | P95 frame ms before → after | Draw calls before → after |
| --- | --- | --- | --- |
| 9 | 12.033 → 5.927 | 14.671 → 12.535 | 422 → 192 |
| 30 | 11.940 → 11.148 | 13.804 → 12.738 | 482 → 256 |
| 55 | 11.677 → 10.342 | 14.243 → 11.897 | 515 → 313 |
| 77 | 11.884 → 10.603 | 13.620 → 12.029 | 589 → 289 |
| 113 | 12.304 → 8.223 | 13.572 → 11.837 | 485 → 262 |
| 172 | 12.051 → 10.972 | 14.340 → 12.632 | 471 → 210 |

Every measured view improved in elapsed-frame median (6.6–50.7%) and P95. These are short, same-machine six-view measurements, not universal hardware guarantees or a long-duration stutter benchmark. `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` remain slowly updated monitor snapshots and are deliberately excluded from CPU-cost conclusions.

Visual review: village and border actors remain grounded; castle silhouettes and identity accessories remain present; western descent and eastern mountain shoulder are visible; both rivers/bridge routes remain; background-free bottom controls stay legible. The performance-capture harness teleports the player without changing the section selector, so its persistent “丘陵树林” selector label is a capture fixture artifact. These performance captures predate the final bat atlas-region correction. The timings therefore remain evidence for that measured snapshot; no full performance rerun was performed for the subsequent bounded sprite-region mapping change. Final visual acceptance is recorded below.


## Final fauna visual closure

Independently opened `assets/medieval/fauna/review/godot-fauna-frames.png`, the final actual Godot Metal gallery with24 frames at90 px/m. Rabbit/deer locomotion, bat wing poses, hurt, fall and downed states each contain one recognizable animal; no adjacent row/frame fragments or truncated bat wing tip are visible. Scale remains consistent within each species, including the different cropped bat frame widths.

Reviewed `scripts/medieval_fauna.gd` and final `assets/medieval/fauna/frames.json`. Bat atlas rectangles use one common pixel scale, `min(entity.size.x /464, entity.size.y /370.5)`, rather than independently fitting each crop. Per-frame source origin plus the shared envelope fixes the anchor; crop size changes only the submitted texture rectangle. Downed alignment translates vertically without resizing. Rabbit and deer retain their common frame envelopes. A read-only metadata check confirms all eight bat regions are positive, mutually disjoint and within the1774×887 source image, with eight matching origins. The frame-selection mapping still uses0–3 locomotion,4 hurt,5 fall and6 downed.

The last art caveat is closed. No new functionality, production edits or additional performance runs were introduced by this review.


## Runtime lifecycle finding — closed

**P2 — Closed: released one-way-surface RIDs remain in collision exceptions.** Root's actual original-project direct scene launch reported repeated `Parameter body null` from `player.support_bodies` → native `get_collision_exceptions`. Script-instantiated scenes initially missed this startup path. The native getter was preserved; the fix corrects exception lifetimes instead of suppressing errors.

Two causes were established. First, physics queries can still return an already removed/queued roof before server synchronization, after its `tree_exiting` cleanup has fired. Both `PaperCollisionLifetime.add` and the player's passing-surface loop now reject targets outside the tree or queued for deletion. Second, the initial shared static `_release.bind(actor,target)` was deduplicated by the signal for different actors. The trace `/tmp/lifecycle-probe-trace.log` shows registration for actor18 followed by `exists true` for actor19, with only actor18 receiving release callbacks. The initial static-review assumption that bound actor arguments distinguished the callback was incorrect; runtime trace corrected it.

Final source review: `scripts/collision_lifetime.gd` now connects `Callable(actor,"remove_collision_exception_with").bind(target)` to each target's one-shot `tree_exiting`. The actor instance is the receiver, so different actors receive distinct cleanup and Godot disconnects the callable if its actor is destroyed first. Target removal cleans the exception while its RID still exists. Repeated registration for the same actor/target remains deduplicated. Existing passing/drop behavior and native getters remain intact. No remaining important lifecycle/type issue found in this scoped fix.

Independently read the actual retained final logs (these runs were executed by root/world worker, not rerun by the reviewer):

- `/tmp/medieval-surface-lifecycle-final2.log`: 15 checks, 0 failures; both player and NPC stale exception arrays are empty after rebuild and removal.
- `/tmp/living-lifecycle-final-medieval_one_way_physics_test.log`: 8 checks, 0 failures.
- `/tmp/living-lifecycle-final-medieval_product_routes_test.log`: 58 checks, 0 failures, including mountain and farm walking routes.
- `/tmp/living-lifecycle-final-player_movement_test.log`: 31 assertions, 0 failures.
- `/tmp/living-runtime-direct-final.log`: actual original-project Metal direct scene startup with `--maximized --quit-after300`; only normal engine/device/startup output, no null-body or script errors; root reported exit0.
- `docs/previews/2026-10-25-living-map/game-v0.23-final.log`: normal Metal startup only, no errors at review time. Root separately confirmed the final v0.23 user window title/maximized screenshot through CUA; this reviewer did not manipulate that window or the user's saves.

The P2 is closed on the corrected source, reproduced callback failure, focused final regressions and clean actual direct launch. The earlier six-view performance values are retained exactly and explicitly precede this final lifecycle fix. The helper's added work is confined to exception registration/retirement; no post-fix full performance run or new timing claim was made.


## Cached-session return follow-up — accepted

Reviewed the two re-entry hooks added for v0.23.1. `StickmanPlayer._enter_tree` defers restoration from the retained passing/drop lists; it checks that the player is back in-tree, skips invalid bodies, and uses the common helper's retired-target guard and per-actor callback. `MedievalWorld._enter_tree` restores permanent NPC surface exceptions only for an existing populated world, deferring until its children have re-entered; fresh population is unchanged. Thus `tree_exiting` cleanup on parking/reparenting no longer permanently removes the live session's exclusions. No important issue found in these scoped hooks.

Read `/tmp/medieval-surface-lifecycle-resume.log`: 19 checks, 0 failures, including the four added park/return assertions. Read `/tmp/living-lifecycle-ui-return.log`: complete GUI return/continue loop, 19 checks, 0 failures. These are root/worker executions, not reviewer reruns. Cached-session follow-up is closed; no open review findings remain. Root distinguishes the updated runtime as v0.23.1 and retains the older window to avoid discarding unsaved work. Earlier performance measurements remain unchanged and predate these registration/retirement/re-entry hooks.
