# 大型武器最近接触筛选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans，当前会话直接执行，最后一次独立复核。

**Goal:** 减少完整手绘武器碰墙后的最近握点接触排序开销，保持接触时间、位置、全部笔迹和伤害规则。
**Architecture:** 只在PaperCombat._blade_geometry_contact已确定首次接触时，用保守包围框拒绝远离目标的线段；其余沿用相同Geometry2D精确交点／距离及原遍历顺序。每次调用重建边界，无跨帧缓存。
**Tech Stack:** 固定Godot4.6.3／GDScript，协议10，存档不变。
**Spec:** SPEC.md §4 v0.14／v0.17性能要求、§7完整剑模。

## Global Constraints
- 不抽稀8192点／128笔，不改采样间距、MAX_SAMPLES、伤害、遮挡、握点排序或16.67ms预算。
- 所有测试用临时工程与私有资料，保留历史包和失败记录，不接触用户作品。
- 不启动已停预览、不远程构建、不部署。

## Review Focus
- 边缘半径内的近而不相交接触、零宽／零高边界不得漏检。
- 时间先后优先，同一时间多个接触按握点距离；同距按原顺序。
- 多笔空洞保留，不用总包围框充当命中；左右反向及移动模型一致。
- 非有限origin保留旧早退；路径拓扑变化按现有at_time回退。
- 性能用实际8192点复杂武器，另用独立完整遍历oracle对照；不将CPU微基准称作整体FPS。

### Task1: 测量、RED及最小优化
- [x] 引擎--profiling实测当前大型武器场景。课本160次最近接触函数total502.864ms／self414.019ms，为主要脚本成本。
- [x] 新测试：独立完整遍历对照、手算半径边界／最近握点／多笔空洞／非有限origin；真实PaperCombat最大点数性能保留16.67ms，运行RED。
- [x] 只添加保守筛选，运行GREEN和同场景前后profiling。

### Task2: 验证与冻结
- [x] 全量隔离、Web适配命中专项、原有性能及真实窗口检查。
- [x] 一次独立只读复核，重要问题仅一轮修正并RED→GREEN。
- [x] SPEC／AGENTS／专项证据、r17独立本地成套冻结及历史完整性校验。

## Execution ledger
Ruling: 用户已连续要求直接渐进改进，保留Godot现有架构；不重复设计确认。无已跟踪源码可切工作树，保留共享checkout，改动前文件另存/tmp。技能的Git提交／分支流程不适用，当前用户未请求提交。
Pre-flight: 唯一生产接口为_blade_geometry_contact(old:Array,current:Array,geometry:Array,origin:Vector2)->Dictionary；初始blade_contact与同时间排序语义保持，不改其他系统。
Evidence: r16完整132／133的首次32.28／28.928ms失败保留；单独复测12.136ms不证明负载原因。本轮profiling单独最高6.849ms，未复现旧尖峰，但确实识别到重复精确比较热点，作为减少冗余工作而非宣称根治系统调度。

Task1: 新74检查，初始两失败中一项手算夹具忽略原0.05m半径的中点接触；手算改为x=-1/42后RED74／1，仅性能42.042ms超预算。最小保守框筛选后GREEN74／0，最大点数同夹具2.930ms。精确算法／0.05m阈值不变，筛选另加1e-5m舍入余量。

Profile: 同场景课本160次排序total502.864→198.953ms／self414.019→91.711ms；课本最坏step6.849→4.081ms，中世纪15.277→13.617ms。后者受其他成本主导，记录全部而非FPS承诺。Web导出10文件108761895字节，权威912文件，原生1240文件。独立只读复核未发现可复现P0／P1／P2；另在隔离空工程探测500000组±200m／≤2.7m／约0.05m边界，无精确接受而保守框拒绝案例。

Task2 complete: 单次完整原生134／134、Web适配10／10、Python4／4。真实Metal97点武器渲染观测：最高p95间隔11.923ms、最高combat.step5.163ms、draw calls180，仅观测非整体性能保证。冻结权威100ms／Web适配600ms两组完整双客户端PASS，每向256KiB/s，双向近战、致死重生、保留画稿／装备、弓箭／取消、凭据重连、确认保存关房均实际验证。原生1240文件、Web10文件108761895字节、权威912文件，33清单零差异、当前源码一致。审查无可复现重要问题，无额外修正；探针归档来源限制见PROVENANCE。Maker预览stopped未启动，未远程构建／部署，保留共享checkout与历史包，不执行Git提交／合并流程。
