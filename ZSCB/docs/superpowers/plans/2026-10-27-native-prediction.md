# 原生联机移动预测 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Inline execution authorized by repeated user requests to proceed with improvements.

**Goal:** 让原生联机角色使用已有Web同源移动预测，避免每次移动／跳跃等待回传。
**Architecture:** 将现有Web预测模块作为核心唯一来源，主线session复用既有接线，主线权威附带ACK／输入年龄／重定位标识。Web准备器只为旧冻结版本注入预测，新主线直接保留；兼容旧协议10权威的无ACK回退。
**Tech Stack:** Godot4.6／GDScript，现有Python构建工具。
**Spec:** ZSCB/SPEC.md §12及§14。

## Global Constraints
- 只有本人移动可预测，不接受客户端位置，不改伤害、冷却、持久化与共享物理。
- 保持数字键、多笔草稿及绘画／拖动／握点镜头稳定。
- 不改真实用户资料，不自动部署或启动已停止Maker预览。
- 保留旧冻结包；协议10不变，增加的权威运动字段可选。

## Review Focus
- 松手与失焦立刻停止；个人面板／握点按既有规则隔离。
- 迟到站立状态不覆盖新移动；普通校正不补充跳跃。
- 死亡、重连、换世界和长状态停顿冻结并恢复权威运动。
- 复制的动态造物必须支持本地角色碰撞，但不由本机模拟造物。
- 旧r7／r13与新来源均能准备Web／权威，不能叠加两次预测／重定位。

### Task 1: 核心预测与ACK
Files: scripts/net/local_prediction.gd, session.gd, actor.gd, room.gd; tests/network_prediction_input_test.gd, movement_ack_test.gd。
- [x] 从实际原生场景编写按键／跳跃／镜头测试，运行RED。
- [x] 核心迁移既有Web预测与权威元数据，运行GREEN；移入已有ACK／抖动／跳跃回归。

### Task 2: 兼容准备与完整体验
Files: web/prepare_client.py, prepare_authority.py, web/client/scripts/net/local_prediction.gd（迁移至核心），web/tests/test_latest_prepare.py。
- [x] 在新来源准备路径验证旧注入会失败；为已含预测／ACK来源保留原代码，旧来源照常注入。
- [x] 隔离原生全量、Web专项、Python兼容及100／600ms两个完整客户端对战／共建。
- [x] 新增原生输入测量证据；独立审查后一次修正；生成独立r14本地候选及匹配Web／权威，记录SPEC和边界。

## Execution ledger
Ruling: 用户已连续授权直接推进；沿用共享当前checkout，不切换／提交无跟踪文件的仓库，修改前另存/tmp基线并在临时工程测试。该仓库无可用跟踪基线，新Git工作树无法包含当前项目。
Ruling: 采用已有Web预测，避免另写第二套控制器；同协议10仅附加可选元数据，不宣称已发布。
Pre-flight: Task2必须识别Task1新增prediction／movement_reset，既有字符串替换不能重复注入。

Task1 complete: 原生输入14项RED7失败→GREEN0；ACK RED1失败→GREEN6／0；0／300／600ms加抖动36／0，首动12–19ms。主线复用同一Web模块，删除重复覆盖层副本。
Task2 compatibility: 旧注入在新核心上实际RED报anchor changed；新准备器保留核心预测／ACK，旧r7及r13准备通过；Python4／4。冻结source1231项、Web导出10文件108755827字节、authority908项；当前尚待全套回归与独立复核结论。

Review fix pass: 一项P2移动梯子线速度／角速度缺失，经固定真实room/session夹具6项RED2失败复现；快照及增量只附可选运动元数据，复制体保持冻结，旧帧缺失回退0。另修复移植抖动测试继承路径：首轮全量128/129，唯一失败为测试路径仍指Web名称，非玩法失败。后续必须重新跑最终全量，保留首轮日志。

Task2 complete: 最终单次全量130/130，Web18/18，transport15/15，Python4/4；最后原生／Web600ms对战及Web／权威原生100ms中世纪协作全部通过，每向256KiB/s。最终首动14–20ms为受控夹具非公网。冻结source1232、Web10／108756499字节、authority908，24清单与当前源码校验通过。仅独立r14本地候选，未启动用户会话或更新公网；未创建Git提交／分支。计划保留为执行账本。
