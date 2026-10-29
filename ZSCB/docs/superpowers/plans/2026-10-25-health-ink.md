# Health and Ink Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline for this approved design.

**Goal:** Add authoritative regenerating ink, personal upper-left vitals, and accurate health loss.
**Architecture:** One RefCounted reserve owns cost/spend/regen. Local success paths and server command commits share it; clients render replicated state. A dedicated Control owns the HUD.
**Tech Stack:** Godot4.6.3/GDScript, existing WSS rooms and isolation runners.
**Spec:** ../specs/2026-10-25-health-ink-design.md

## Global Constraints

- HP100, ink300, recovery delay2s, recovery25/s, arrow4; melee free.
- Preserve drafts and existing equipment on rejection; do not charge failed operations.
- Preserve shared work and real saves; run isolated copies.
- Protocol3 requires matching authority; do not switch users to an incompatible client.

## Review Focus

- Split delta across the recovery delay without losing time (model test).
- Numbered retry, forged prices and invalid spawn never change balance (authority test).
- Cancelled draw and insufficient ink never emit an arrow (combat test).
- Death/reconnect retains reserve; overkill reports actual HP loss (authority test).
- Upper-left HUD and connection controls remain separate in four sizes (visual capture).

### Task 1: Shared reserve and atomic local/server usage

Files: scripts/ink_reserve.gd, scripts/main.gd, scripts/paper_combat.gd, scripts/net/{actor,room,session,codec}.gd; tests/ink_reserve_test.gd, tests/network_ink_test.gd.
Interfaces: cost(object:Dictionary)->float, spend(cost:float)->bool, step(delta:float); amount/wait/last_cost/recent fields.
- [x] Add failing model and authority tests; run to observe missing functionality.
- [x] Implement model and commit hooks, deduct at actual arrow release, replicate reserve fields.
- [x] Verify model, authority, retry and bow cancellation tests.

### Task 2: Resource HUD and health loss

Files: scripts/vitals_hud.gd, main.gd, paper_canvas.gd, paper_combat.gd, native_agent.gd, net/actor.gd.
- [x] Add actual lethal damage and HUD state tests, run RED.
- [x] Implement actual-loss reporting and passive HUD with responsive positioning.
- [x] Render desktop/compact/portrait, inspect screenshots, run local and network checks.

### Task 3: Frozen release and verification

- [x] Update SPEC and implementation evidence; freeze matching protocol3 source without private data.
- [x] Run full isolated suite, real two-client authority checks and archive manifest.
- [x] Prepare share package; keep protocol2 launcher until matching authority release is authorized and succeeds.

Shared checkout is untracked and used by other conversations; preserve it with local patches, no generic Git commits.

Ruling: shared development docs contain incomplete PNG screenshots from the parallel Web task. Verify from frozen r4 based on r3 and explicit changed files; do not modify or import that task’s temporary evidence.
Ruling: current public browser still uses protocol2. Prepare a separate r4 Web export; server/native/browser must move together after release approval. Keep live launchers and services unchanged until then.
Review: three P2 findings independently reproduced RED, fixed once, GREEN: near-closed filled-area price, online medieval event loss, practice target lethal sword/arrow numbers.

Final: 80/80 full suite, 15/15 transport, two actual local Metal clients verified replicated ink and hit/hurt audio. Web protocol3 export checked; cloud release remains pending user authorization.
