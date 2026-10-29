# 联机保存请求 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. 用户已授权直接逐步改进，在当前会话执行，最后独立复核。

**Goal:** 手动保存与保存返回在同步期间不丢请求，重复点击只发一次，真实确认后才报成功，失败／不确定时保留画面与草稿。
**Architecture:** RefCounted保存请求状态机由session拥有，绑定当前epoch/world；Ready等待最多10秒，发出后沿用3秒确认期限。重复请求合并，同步／重连时未发送请求可等待；已发出后断线结果不确定，不自动重放。匹配迟到确认可更新提示，但不会迟到自动返回。保存返回复用同一请求完成结果，再走既有leave确认。
**Tech Stack:** 项目固定Godot4.6.3／GDScript，现有WebSocket和原子世界存储，不采用技能示例4.7新API，不迁移引擎。
**Spec:** SPEC.md §9／10／12。

## Global Constraints
- 不改云端存档格式、权限、物理、计费、协议10或部署。
- 等待／发出／成功／失败／结果未知均有明确文字；没有服务器成功回执不能说成功。
- 只对当前世界保存一次；换世界、结束或主动离开取消未发送请求。已发请求不盲目重发。
- 旧保存返回必须继续通过；客人不越权保存世界。
- 临时副本／私有用户资料验证；不自动启动已停Maker预览，历史包保留。

## Review Focus
- 连点、手动保存后立刻保存返回只关联一个实际save请求。
- Ready等待与实际发出分开计时，快照结束但Ready尚未到达仍不能发送。
- 超时和迟到成功不假报失败／成功、不迟到切场景；旧序号不能覆盖新请求状态。
- 断线前后、换epoch／world不把旧保存发送到新世界。
- Web覆盖层兼容旧来源，当前通知不被旧回执误报成功。

### Task1: 保存状态机与入口
Files: scripts/net/save_request.gd（新）, session.gd, main.gd; tests/network_save_request_test.gd。
- [x] 实际game.save_game入口测试RED：同步后一次发送、去重、重试、超时、迟到回执、换世界、客人隔离。
- [x] 最小状态机和session接线，保存返回加入同一请求；GREEN并跑原network_save_return测试。

### Task2: Web与完整验收
Files: web/client/scripts/net/online_panel.gd及相应回归，真实网络机器人／既有双客户端测试。
- [x] Web通知使用当前请求状态，旧来源沿用原处理；专项和真实100／600ms保存验证。
- [x] 全量、Python构建兼容、独立复核；独立r16本地成套冻结，记录SPEC与未发布边界。

## Execution ledger
Ruling: 用户连续授权直接修改；当前仓库无已跟踪源码，保留共享checkout并另存/tmp基线，不切分支／提交，所有测试隔离。
Pre-flight: Task2 Web legacy来源没有新helper，必须has_method能力检查；保存返回仍需leave成功才跳转。

Task1: 核心RED12／5→GREEN12／0；Ready重放顺序与提示覆盖RED16／2→GREEN16／0；扩充断线和world标识后20／0。原保存返回10／0，排队手动保存加入保存返回5／0。真实机器人初次在进入保存前因沿用旧握点直接装备夹具失败，已改为当前3绘图→握点→类型→装备流程；不更改武器实现。

Review fix pass: 两项P2。同帧迟到成功覆盖超时完成导致保存返回仍离开，经队列退出测试RED7／1→GREEN7／0，完成结果首次终态冻结，反馈仍可更新。Web房间菜单保存旧guard绕过新队列，经实际按钮测试RED6／2，改为能力分支接新请求，旧来源保留guard。后续最终Web及全量须重跑；不再次请求审查。

Final validation: 核心20／0、队列退出7／0、原保存返回10／0、当前Web14／14、实际旧冻结来源Web4／0、Python4／4。审查后成套原生600ms／Web适配600ms／冻结权威配原生100ms全部PASS，每向256KiB/s；实际菜单点击发生于真实resync。Web导出10文件108761447字节，权威912文件，原生源码1239文件一致，30份冻结清单零差异。最终全量132／133，唯一large_weapon_performance_test前两配置32.28／28.928ms超过16.67ms；其他检查退出后单独复测16配置全部通过，最高12.136ms。保留失败，不把两次结果合称单次133／133，不断言并行负载是已证明原因。截图与phase文字已读取核对。Maker预览stopped，未启动、未远程构建、未部署。
