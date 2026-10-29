# 纸间联机输入延迟 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline work. The user's existing instruction is to implement and publish the usable game; avoid repeated approval gates.

**Goal:** 本机方向／跳跃立刻响应，落笔不被联机镜头拖动，并保持云端协议2裁决与存档。
**Architecture:** 在固定r2的Web覆盖层恢复同源角色控制器的本地物理预测；保留约1.5秒本地位置历史，将迟到权威状态与对应历史比较，平滑纠偏。仅预测本人移动，造物／伤害仍须服务器确认；断线、死亡、世界切换清除预测。方向改变立即发送，20Hz作为保持心跳。绘画／拖动／选握点时锁定镜头，沿用单人行为。
**Tech Stack:** Godot4.6.3 / GDScript / existing WSS protocol2 / Python exporter.
**Spec:** ZSCB/SPEC.md §§5,12; user 2026-10-25 confirms high input latency despite successful connections.

## Global constraints
- Existing r2 authority and old identity/save paths remain compatible; do not deploy protocol4 main development.
- Isolated export output `dist/纸间网页版-20261025-latency/`; preserve prior perf build as rollback.
- No local prediction of damage, successful creation, or shared world authority.

## Review focus
- Delayed old ground frames must not cancel a fresh local jump or restart after release.
- Frozen authoritative objects must still provide local support/collision.
- Death, reconnection, teleport and epoch changes must discard old motion history.
- Focus loss, typing, dialogs and bag stop directional input immediately.
- Long strokes retain coordinates while the camera is held.

### Task1: Input response and correction
- [x] Add real game/session regression: press right without new frames -> displacement within2 physics ticks; release stops, jump rises; old frame does not reset; death freezes.
- [x] Run against published perf project and record RED.
- [x] Implement `scripts/net/local_prediction.gd` overlay + anchored session preparation. Same locomotion, conservative collision layers, bounded history, authority correction and lifecycle reset.
- [x] Add 300/600ms delayed real authority comparison (first motion time, correction error, stop/landing convergence), observe pass.

### Task2: Drawing stability
- [x] Add regression: active stroke/camera coordinate stays stable during player movement; regular camera follows again when stroke ends; local stroke grows without network receipt.
- [x] Run RED, then correct camera guard and send changed controls immediately; remove unnecessary repeated input serialization where appropriate.
- [x] Full Web regression suite and fixed-r2 gameplay/locomotion checks.

### Task3: Publish and verify
- [x] Export dedicated latency candidate, check output errors and loader recovery.
- [x] One fresh independent review required by execution skill; fix important findings with tests.
- [x] Real browser drawing/movement via existing public authority; two-client compatibility and normal save/exit.
- [x] Deploy static service only, verify public resources and deployment status, update deployment metadata and validation.

Ruling: Use owned Web overlay / isolated export, no Git reset/commit/worktree — shared repository is untracked and concurrent main protocol4 work must not be included.
Ruling: Client history timing uses observed WSS RTT; avoid server restart/migration for a client-response fix. Measure jitter/correction limits and document that network transit time remains.

Final review: four Important findings fixed in one RED→GREEN pass: routine resync jump rewind; held jump budget/latches on correction/hurt; authoritative airborne recovery after pause; bounded recoil derived from historical input. Transition6/6 + immediate15/15 + controlled delay36/36 + Web9/9 scripts. No deferred minor finding.

Final verification: Web-adapted full suite82/82; loader2/2; final actualTCP paper duel300ms and medieval flow600ms+256KiB/s passed. PublicWSS paper two-client flow passed; medieval public automatic fixture intermittently timed out (old-client control also failed). FinalWeb single-client medieval movement/jump/drawing verified; this remaining public sync limit is documented. Statica2695bc4 SUCCESS, authority8b104ff7 unchanged.
