# 联机画稿预览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 用户已连续授权直接改进，当前会话原生执行，最后独立审查。

**Goal:** 朋友可看到每笔草稿的首尾与全部笔画，抬笔／清空及时同步，静止草稿不挤占位置更新。
**Architecture:** 只为网络显示采样，保留最多128笔／500点、每笔40点；先给每笔首尾，再公平分配余量。上传在150ms节奏之外响应笔画开始／结束、工具和笔数变化，发送内容不变则跳过。新客户端协商可选preview_delta能力，服务端只向支持者省略不变预览，旧客户端保持完整帧；远端显示保留未携带字段的预览。协议10不变，不改实体／存档／计费。
**Tech Stack:** Godot4.6，GDScript，现有Web／权威本地构建。
**Spec:** ZSCB/SPEC.md §5、§12。

## Global Constraints
- 本机完整笔迹不可简化、不可自动生成。只改变临时网络预览。
- 保持128笔与服务器512点／24米校验；客户端预算500，不提高上限。
- 无碰撞、无伤害、无耗墨；按数字键确认的最终几何仍走原流程。
- 不覆盖历史冻结包、不部署公网、不启动已停止Maker预览；所有测试隔离资料。

## Review Focus
- 128笔／8192原点的尾部笔画和每笔末端均保留；一／二点和空稿安全。
- 抬笔、清空、同笔数换工具、断线重连后保留／重发当前稿。
- 静止稿不重复上传；新朋友／resync重新取得预览，空预览可清除。
- 省略字段只对协商能力者启用；旧客户端完整帧不清空或漏图。
- 最终确认与临时预览独立，原稿／图纸／权威作品笔迹保持。

### Task1: 采样与上传
Files: scripts/net/drawing_preview.gd（新）, scripts/net/session.gd, tests/network_drawing_preview_test.gd。
- [x] 通过实际session.tick与捕获出站命令写RED，覆盖128笔、末端、源稿不变和抬笔／清空。
- [x] 最小实现公平采样与生命周期上传，GREEN。

### Task2: 预览增量与实际双客户端
Files: server/server.gd, scripts/net/remote_actor.gd, tests/network_transport_test.py, tests/drawing_preview_bot.gd, tests/run_network_clients.py。
- [x] 真实TCP协商能力／旧客户端／清空／resync测试先RED，后实现省略不变预览与客户端保留。
- [x] 真实双完整客户端画128笔并观察首尾、抬笔／清空／重连／最终生成；限速100／600ms。
- [x] 全量、Web专项、传输、Python准备兼容、独立审查；冻结独立r15成套候选，记录实际结果。

## Execution ledger
Ruling: 共享checkout全部未跟踪，无法由Git工作树携带当前实现；遵循用户直接执行授权，先存/tmp基线，使用临时副本和私有用户资料测试，不切分支／提交。
Ruling: 可选preview_delta协商保留协议10旧客户端完整帧，与新源互通；只清除成功发送后的每连接缓存，快照重置缓存。
Pre-flight: Task2省略字段须与remote_actor的has(preview)一致；未协商不能省略。

Task1 complete: RED12／8→GREEN12／0；首次可见线段RED17／1→GREEN17／0；拒绝／重生缓存RED19／2→GREEN19／0。没有改本机画稿、实体和计费。
Task2 wire: 真实TCP新增协商兼容回归先RED1失败→GREEN；全传输16／16，Python4／4。原生100ms／256KiB/s真实两客户端实际128笔8192点、端点、清空／重连及64点最终生成保存通过。初次bot因测试框架复制到network_bot.gd造成继承自身的夹具错误，已使用独立脚本修正；该夹具错误见本次对话工具输出，不计玩法失败。

Fixture correction: 后续Web600／权威100在保存前失败；诊断实际捕获DRAW SAVE request=-1 ready=false syncing=false（快照已装载，Ready回执尚未到达）。机器人此前未等待Ready就发送保存；修正为条件等待Ready后发送一次保存，不改成功回执要求、不重试或改游戏保存逻辑。失败与诊断日志保留。

Task2 complete: 最终行为131/131、Web13/13、transport16/16、Python4/4；独立19/0，无具体问题。原生100／600及Web100通过，Ready夹具修正后Web600及权威100通过，每向256KiB/s。实际600ms窗口截图已查看。独立r15 source1235／Web10(108758215 bytes)／authority910，27清单和当前1235项零差异。未发布、未启动用户常驻会话，保留执行账本及失败证据。
