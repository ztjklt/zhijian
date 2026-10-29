# Sandbox Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct carrying/drop lifecycle, adapt protocol11 Web, unify verification, and connect existing activities after first-work completion.
**Architecture:** Shared carry placement and a small carry controller behind compatible main methods; isolated Web preparation; portable offline test orchestration; optional existing-activity panel.
**Tech Stack:** Godot4.6.3/GDScript, Python3 stdlib, GitHub Actions.
**Spec:** ../specs/2026-10-29-sandbox-reliability-design.md and ZSCB/SPEC.md.

## Global Constraints

- Never touch real profiles, credentials or user world saves. All tests use disposable copies/private namespaces.
- Keep protocol11, stable IDs, server authority, existing drawing/weapon/structure rules and persistence schema.
- Preserve historical r7 and other fixed bundles; no cloud deployment or Maker build.
- Work in /tmp/zhijian-reliability-worktree; compare primary source before copying reviewed changes back.
- Keep previously failed evidence and report native/Web/browser verification separately.

## Review Focus

- Blocked/invalid drop must keep collision suppression and identity; test in Task1.
- Carry surviving deletion/rebuild must resolve stable identity, not index; test in Task2.
- Remote carry visual state on repeated same-id snapshots cannot restore prediction collisions; test in Task2/3.
- A failed Python/Web stage must make aggregate verification fail, with private profile cleanup; test in Task3.
- Optional follow-up actions must not change maps, drawings, equipment or saved world silently; test in Task4.

### Task 1: Safe local/authority drop

**Files:** Create scripts/carry_placement.gd; modify scripts/main.gd and scripts/net/room.gd; create tests/carry_drop_test.gd and tests/network_carry_drop_test.gd (all within ZSCB).
**Interfaces:** `PaperCarryPlacement.resolve(world, candidate:Dictionary)->Dictionary` returns ok/object/offset/error and never mutates original world data on failure.
- [ ] Write real obstruction/ground-offset and invalid-geometry drop cases; require no overlap after success and zero held collision after failure.
- [ ] Run isolated tests; capture RED matching audit probes.
- [ ] Apply returned safe coordinates to both dictionary and actual body; share resolver; retain state on rejected drops and use safe release on lifecycle exits.
- [ ] Run new tests plus old carry, spawn, structure and profile/save checks. Commit verified task locally.

### Task 2: Carry lifecycle / limited main decomposition

**Files:** Create scripts/carry_controller.gd; main.gd facade, net/session.gd snapshot hook, net/room.gd world activity ownership; add carry_lifecycle_test.gd and network_carry_replica_test.gd.
**Interfaces:** Main carry methods and carried_id/carried_previous remain compatible; controller owns local pick/step/drop/reapply/clear; shared placement from Task1.
- [ ] Add RED cases: switch drawing/overlay while held, delete other/current piece, object reorder/distinct IDs, rebuild/resync same-id and authority tick.
- [ ] Extract carry implementation; separate pointer cancellation from explicit world departure; retain disabled collisions on reapplication and ordinary replica freeze.
- [ ] Run Task1/2 tests plus existing input, undo, map, cooperation and carry tests. Commit verified task locally.

### Task 3: Web protocol11 and portable aggregate checks

**Files:** web/prepare_client.py, web/build_web.py/build_authority.py/run_checks.py, tests/runtime_tools.py, existing isolated/full/network runners, tests/run_checks.py; Python tests; .github/workflows/checks.yml.
**Interfaces:** `resolve_godot(explicit=None)->str`; offline `python3 ZSCB/tests/run_checks.py --godot PATH` runs native+Python+Web, returns nonzero on any failure, emits bounded summary. Optional stage selection is explicit.
- [ ] Capture RED current-protocol preparation and aggregate failure/portable runtime cases.
- [ ] Adapt 11 with preserved source gameplay/carry hooks; preserve unknown-protocol refusal and historical regression fixtures without requiring private dist to run current checks.
- [ ] Resolve runtime using --godot/GODOT_BIN/PATH/installed mac fallback; use unique user namespaces on all platforms; aggregate builds a disposable matched Web client and runs checks against it.
- [ ] Add offline CI with pinned Godot4.6.3 and no publishing or real-cloud tests.
- [ ] Verify Python suite, full native and matched Web suite, independent source-byte checks, real two-client tests on matched temporary projects. Commit locally.

### Task 4: Optional next activities

**Files:** scripts/next_steps.gd (panel), scripts/main.gd, first_work.gd, toolbar.gd; tests/next_steps_test.gd and responsive/input test.
**Interfaces:** `game.open_next_steps()`; panel actions open existing weapon lab, select structure tools, or show existing mill-trial map route; never auto-create or change map.
- [ ] Write RED for real first-work completion entry, menu reopening, dismissal, live-world preservation, wrong-map trial guard, actual activity callback and small-screen layout/input isolation.
- [ ] Add compact paper panel with clear close/continue action; connect completed guide action and works menu. Preserve guide stage/persistence and multiplayer isolation.
- [ ] Verify native/Web focused tests plus real rendered wide/narrow/portrait UI.
- [ ] Update SPEC v0.55 and release label r22 (protocol11), AGENTS and validation notes; final whole-change review, single fix pass if needed, full aggregate GREEN before integration.

## Completion

- [ ] Fresh read-only whole-change review and fix findings with RED→GREEN.
- [ ] Record exact commands/results and outstanding external validation limits.
- [ ] Refresh source checksums; scan credentials; verify primary-source drift before applying reviewed changes back. No automatic cloud deployment.
