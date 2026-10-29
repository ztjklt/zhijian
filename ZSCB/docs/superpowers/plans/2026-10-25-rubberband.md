# 纸间移动回拉修复 Implementation Plan

> Execute inline with systematic-debugging, TDD and verification-before-completion; one independent final review. User authorizes improving/publishing the current public game; existing authorization persists.

**Goal:** Moving forward must not abruptly rewind when ping varies or a short state-stream gap recovers.
**Architecture:** Add backwards-compatible input ACK/age and explicit movement-reset metadata to the fixed protocol2 authority. Match client movement history to the actual acknowledged input, not a guessed ping. Ordinary recovery/corrections remain rate limited; only explicit server relocation/life/world transitions may snap. Preserve server damage, geometry, saves and legacy clients.
**Spec:** ZSCB/SPEC.md §§9–12 and current user rubberband report.
**Scope:** owned Web overlay and isolated r2 authority candidate; never deploy concurrent protocol5 main project.

## Review focus
- Wrong or changing ping cannot select a different movement history for an acknowledged input.
- Pending direction/jump changes cannot be overwritten by pre-change server frames.
- A short state gap cannot snap back2m; paused prediction still recovers correct airborne velocity.
- Real teleports/death/world changes must remain authoritative; correction must converge without allowing indefinite drift.
- Legacy protocol2 clients and saved worlds remain compatible; duplicate input cannot reset input age or mutate state.

- [x] Reproduce current rubberband with actual controller/history; record RED magnitude.
- [x] Add authority ACK/age/reset regression; RED before additive fixed-r2 metadata patch.
- [x] Implement ACK history + bounded correction/recovery; preserve immediate controls, jumps, collisions, drafting.
- [x] Test wrong ping, jitter/bursts, stale pending input, input timeout and teleport, plus default/full suites.
- [x] Independent review; important fixes RED→GREEN.
- [x] Build separate client/authority candidates, test TCP two-client combat/saves, legacy compatibility, snapshot restore.
- [x] Back up existing volume, warn of brief server reconnection; publish compatible authority and static client, validate actual public flow and source manifests.

Ruling: Input ACK references the server's existing input sequence and simulation age; no client position or timestamp is trusted. New actor state fields are optional and protocol2 rules/persistence remain unchanged.
Ruling: Existing published latency bundle remains immutable rollback. New outputs are `dist/纸间网页版-20261025-ack/` and `dist/纸间服务校正版-20261025-r2a/`; no generic Git mutation of shared untracked work.

Release: authority c20f8952 and Web e45d62fa SUCCESS; existing-volume backup, public ACK, full clients and identity recovery verified. First public probe/restore-close failures retained and bounded follow-up passed. See WEB_RUBBERBAND_2026-10-25.md for evidence and remaining WAN/high-latency combat limitations.
