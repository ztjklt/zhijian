# 第一件作品 Implementation Plan

> Use superpowers:executing-plans inline. 用户已授权按既定顺序直接实施，沿用本会话执行，不重复索取审批。

**Goal:** 可跳过的单人小目标：有效画稿→确认真实生成→站上／亲手搬动→实际保存成功。
**Architecture:** 新`first_work.gd`只观察真实单人动作，保留原`PaperOnboarding`兼容接口。无新物理、资源或网络规则；协议10兼容r12，新增r13本地候选，公网不更新。
**Tech Stack:** Godot4.6.3/GDScript及既有Web适配，不安装依赖。
**Spec:** SPEC v0.45第13节授权第六阶段，本轮细化v0.46。

## Global Constraints
- 不替玩家画线、不替换形状、不自动生成／保存、不清空已有作品／草稿／装备，不锁移动或暂停世界。
- 自动入口尊重旧guide.seen偏好；单人首次显示，中世纪默认入口同样可用，老玩家可从作品菜单主动重开。
- 三种造物工具1／2／5的真实成功可计入；武器、旧物件、图纸放置、失败／预览不冒充新绘制成功。
- 使用只认目标真实站稳0.3秒或4工具实际拖动≥0.25米，重力下落不计。目标消失／换图／读取世界时回到绘制目标，不假完成。
- 只有实际本机保存成功才完成；保存失败保留当前目标和重试入口。进度不写世界，只记旧seen与个人完成偏好。
- 线上不自动或手动启动此单人课程，不改变房间；现有联机协议／权威保持10，沿用r12兼容事实。
- 共享未跟踪主线局部补丁，备份/tmp/paper-first-work-original-20261026；所有测试隔离，不切分支／提交／部署。

## Review Focus
- 保存失败、旧作品载入、目标被删／破坏／撤销、切图不能假完成；实际目标随落点及刚体移动更新。
- 不同工具草稿、候选预览、武器与图纸保留；下一步按钮必须匹配真实操作和草稿所在工具。
- 偏好尊重旧跳过用户，持久化不覆盖其他设置；测试关闭persist时绝不写真实资料。
- 桌面详细提示，窄屏复用工具栏现有状态行与两个短按钮，不额外盖住操作区／摇杆。
- 新引导不破坏旧onboarding接口／测试和Web覆盖层；头less权威与联网不会出现新教程状态。

### Task1 真实动作目标与状态
Files: new scripts/first_work.gd, tests/first_work_test.gd; main.gd/paper_canvas.gd.
Interfaces: start(), dismiss(), note_drawn(mode), note_created(object), note_moved(object,from,to), note_saved(ok), step(delta), action(); fields stage/visible/target_key/map/mode/notice/persist.
- [x] RED：仅本轮真实笔画／生成、错误类型／预览／旧物件拒绝、拖动阈值、真实站稳、对象消失／世界变更、实际保存与失败、跳过和资料隔离。
- [x] 实现观察模块、接入真实生成／拖动／保存；GREEN，不改物理规则。

### Task2 不打断的引导与入口
Files: toolbar.gd, experience_panel.gd, first_work_ui_test.gd/first_work_visual.gd.
- [x] RED：作品入口、上下文下一步、跳过、原草稿保留、四尺寸实际控件／触控可达。
- [x] 桌面复用旧引导卡，窄屏复用现有状态行，实际渲染验收；GREEN。

### Task3 成套验证与审查
- [x] 真实整条绘制→生成→使用→保存→读回验证，失败重试；独立只读审查。
- [x] 本机全量及匹配Web专项，协议10不变，r13源码／Web／权威SHA及历史包校验。
- [x] SPEC／AGENTS／报告／证据同步，预览保持停止，清理测试进程；六项渐进改进完成。

## Execution ledger
- Pre-flight: Task1只通过成功回调接入，Task2上下文按钮复用原操作，不可提前推进；Task3从隔离用户目录读取真实保存结果。
- Ruling: 第一件作品选择矮踏板，允许站上或亲手搬动两种使用方式，避免任意自由画形状使新手卡死；不注入预制平台，保留自由玩法。
- Ruling: 不重写旧PaperOnboarding阶段接口，避免历史测试／旧偏好迁移产生副作用；新目标单独模块并在运行时抑制旧课程持久化。

- Task1 complete: 核心23/0，真实支撑／保存失败重试11/0，偏好与联网边界10/0；复用player.support_bodies，不另写近似支撑几何。
- Task2 complete: 17/0实际UI与触控，三阶段×四尺寸真实渲染并检查；窄屏使用现有footer，工具按钮显示真实数字键。
- Review fixed P2: 清空1稿、2重画后旧drawing_mode导致课程回空稿；真实事件RED23项2失败→GREEN23/0，其他17/11/10均绿。跟随最新有效笔画，原稿空时回绘制，其余稿不清空。
- Fixture ruling: 空路径图纸在原保存规则合法，不能作为失败夹具；改用非法hotbar长度，不改SaveStore。实际失败无文件、重试读回通过。
- Verification: Web匹配14/14、Python2/2；r13完整双客户端共建100ms/256KiB/s回归通过。协议10，headless没有课程，联网不启动。
- Candidate: 源码1222、Web站点10、权威906；r7至r13共21清单SHA无差异。未发布，预览保持停止，历史高延迟失败不抹去。

- Final complete: 本机121/121完整通过，Web专项14/14，真实视觉三阶段x四尺寸与实际保存读回通过；21清单零差异。测试进程已结束，六轮本地渐进改进均已接入，未发布公网。
