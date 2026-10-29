# 纸间最新版 Railway 成套发布 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. User explicitly requests deploying the latest version; execute inline with one independent final review. No new approval gate for the already authorized deployment.

**Goal:** Publish the actual current protocol6/r7 game to the existing Railway authority and website, preserving previous input ACK/prediction improvements and saved identities/worlds.

**Architecture:** Freeze current Godot runtime/tests into an isolated, hashed source snapshot. Derive matched authority and Web packages from this source; port only existing Web flow, prediction, fonts and browser adaptations. Test locally, back up the existing volume, then publish authority+static Web to the existing services and validate live recovery.

**Tech Stack:** Godot4.6.3, Python build tools, Railway CLI, Caddy, WSS.

**Spec:** `ZSCB/SPEC.md` §§5–12,14; current explicit user request to update latest to Railway.

## Global Constraints
- Display name is 纸间; preserve old browser/profile/save namespaces.
- Current runtime protocol6 / 20261025-r7 includes latest clean UI, vitals, five weapon types, damage geometry and audio. Do not ship protocol2 gameplay as latest.
- Do not modify concurrent gameplay source, user profiles, existing published bundles, regions, resources or volume settings.
- Retain old protocol2 packages for rollback; new output directories only. No Git reset/commit of shared untracked files.
- Use separate test projects and unique app_userdata; never launch tests against real user saves.

## Review Focus
- Web overlay must retain latest weapon wheel, clean UI, vitals, damage geometry and audio event cursor handling.
- Client/server/fixture protocol must agree at6; old clients must fail clearly during upgrade, not silently corrupt data.
- ACK history, explicit resets and bounded correction must still work with latest movement/combat.
- Protocol2 saved world and original owner/guest credentials must survive the protocol6 update.
- Existing Web/profile namespaces and rollback bundles remain intact; source snapshot must be internally consistent while other chats work.

### Task1: Freeze current source and adapt packaging
**Files:** `web/build_web.py`, `web/prepare_client.py`, `web/build_authority.py`, `web/tests/test_latest_prepare.py`; new `dist/纸间联机最新版-20261025-r7/`, `dist/纸间权威服务-20261025-r7/`, `dist/纸间网页版-20261025-r7/`.
**Interfaces:** frozen source contains project.godot/scripts/scenes/animations/assets/server/tests; builders consume --source/--output. Both outputs keep protocol6.
- [x] Snapshot file hashes before/after copying; reject any changing source. Never overwrite an existing unowned output.
- [x] Add preparation test proving latest protocol/features retained, ACK prediction and room UI installed; run RED against current fixed-r2 preparation.
- [x] Port exact existing overlay anchors for latest source; skip obsolete UI/font-size patches already in core; build separate authority and Web packages, GREEN/import/export clean.

### Task2: Validate matched packages
**Files:** `web/run_checks.py`, `web/tests/run_network_checks.py`, `web/tests/public_ack_probe.py`, new release evidence under `docs/previews/latest-railway-r7-2026-10-25/`.
**Interfaces:** accept matched snapshot tests/server rather than hardcoded fixed-r2 fixtures; unique profiles remain mandatory.
- [x] Run latest full Web-adapted core suite plus existing prediction/flow checks, retaining all new gameplay tests and supported Web expectations.
- [x] Run real local TCP two-client combat/vitals/weapon/damage and delayed movement checks; preloader retry and rollback guard tests.
- [x] Independent read-only review of packaging/protocol/save compatibility; fix confirmed Important issues with RED→GREEN before publication.

### Task3: Publish and verify public release
**Files:** `web/deployment.json`, `docs/LATEST_RAILWAY_R7_2026-10-25.md`, `AGENTS.md`, `SPEC.md`.
**Interfaces:** existing authority5f8d31f1 / static5ac996ca, project0b37d382, environmentb4989764; existing volume /data and domains.
- [x] Prepare a new private protocol2 cloud fixture; copy worlds and worlds_credentials to private in-volume backup, warning of brief room disconnection before publishing.
- [x] Publish matched authority, then Web. Confirm deployment SUCCESS and health checks; keep native matching snapshot available.
- [x] Restore pre-upgrade saved world and owner/guest authorship using protocol6; test actual public WSS full clients and ACK metadata.
- [x] Inspect final Web in browser using only CUA, exercise movement/drawing/save against public WSS; verify public files against manifest and record exact limits. Same final Web pack was locally served for interaction; public-origin full browser loading remains undetermined after CUA bind timeouts, as recorded.
- [x] Update release records/latest defaults and finish with playable public URL; close only own test rooms/processes.

Pre-flight: task1 protocol6 snapshot is task2 test source and task3 deployment source; do not mix fixed-r2 test servers after the protocol upgrade. Ported overlays may change presentation/prediction, not gameplay rules. Existing deployment authorization includes required compatibility fixes and backups; no extra paid resources are authorized.

Completion evidence: authority1638e5df and Web8687c1a3 SUCCESS; protocol2→6 world/owner/guest recovery PASS; two actual public medieval clients PASS; public ACK PASS. Public duel cancellation check failed after successful damage/respawn/bow stages and is explicitly retained as an unresolved limitation, not counted as a pass. Full local106/106 and matched PCK/late-client suites passed. Large uploads recovered using checked BSDIFF40 reconstruction; both PCKs exactly match the tested canonical bytes. Final report records the public-origin browser-loading evidence gap.
