# Medieval Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** 独立可选的黑线中世纪地图，逐件 GPT 美术、真实武器/造物伤害与局部破坏。

**Architecture:** 主工程新增 medieval_world 节点，独立物件和碰撞，不重载 knowledge_world 接口。combat 使用其统一接触接口；世界显示在 paper_canvas 的纸面之上。开始选择器进入同一 main.gd 核心；地图存档独立。

**Tech Stack:** Godot 4.6 GDScript, GPT built-in imagegen, PNG alpha assets.

**Spec:** ../specs/2026-10-24-medieval-map-design.md

## Global Constraints
- 阅读 ZSCB/AGENTS.md、SPEC.md；同期文件局部修改，无提交、部署或远端构建。
- 当前所有文件未跟踪，使用当前用户指定目录，不能创建缺少这些改动的 worktree。
- 测试只在 tests/run_isolated.py 副本运行，不能动用户存档。
- 保留同键绘画、真实扫掠、移动、课本与旧平地回归；地面不可破坏。

## Review Focus
- 阴影/白底贴图遮住纸线：检查 alpha 与真实截图。
- 破损后仍有完整碰撞或武器穿墙：验证可见缺口和最近接触。
- 场景切换遗留目标/碰撞/存档互写：独立入口与存取测试。
- 手绘物件静止贴住目标逐帧伤害：速度阈值与去重测试。
- 无效存档中的数量、NaN、ID 与越界缺口：拒绝并保留好档。

### Task 1: Map entities and world
**Files:** scripts/medieval_entity.gd, scripts/medieval_world.gd, tests/medieval_world_test.gd.
**Interfaces:** world.game; world.entities; world.draw_world(canvas); world.step(delta); world.segment_contact(a,b)->Dictionary; world.blade_contact(old,current)->Dictionary; world.damage_entity(entity,amount,point,impulse); world.save_state()->Array; world.restore_state(Array). Contacts contain entity,position,time. Entity supports health, alive and bounds/geometry. Assets res://assets/medieval/<name>.png.
- [x] Test damage/knockback, holes/collision, rigid-body impacts, death, state validation.
- [x] Implement cohesive map and actors, use transparent animated sprites.
- [x] Run isolated world tests.

### Task 2: Combat integration
**Files:** scripts/paper_combat.gd, tests/medieval_combat_test.gd.
**Interfaces:** game.medieval_world (nullable), world interfaces from Task 1. Existing `_blade_structure`, `first_structure` return nearest hit and include medieval entity. Player blade and arrows damage entity once, respect prior walls.
- [x] Write/observe failing sword/arrow/occlusion tests.
- [x] Add minimal nearest-hit integration; no changes to four-move sequencing.
- [x] Run isolated tests and existing blade regressions.

### Task 3: Assets, startup and persistence
**Files:** assets/medieval/, docs/MEDIEVAL_ASSETS.md, scripts/map_select.gd, scenes/map_select.tscn, scenes/medieval.tscn; main.gd, paper_canvas.gd, save_store.gd, project.godot, SPEC.md; tests/medieval_integration_test.gd, tests/medieval_visual.gd.
- [x] Generate each asset separately, inspect and persist prompts/source mapping.
- [x] Test then add startup selector, local map menu, independent save and sanitized state.
- [x] Draw world after paper background; step with actual physics; keep scripts from other tasks separate.
- [x] Run isolated integration and gameplay regression tests; render desktop/narrow map/death/damage screenshots and inspect.

## Execution rulings
- 用户已确认落地且扩展范围；直接继续实现，不另设流程批准。
- 使用当前目录保持未跟踪工程与并行会话改动；不创建分支或提交。
