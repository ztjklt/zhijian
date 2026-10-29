# 联机造物确认保护 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans，当前会话直接执行，最后独立只读复核一次。

**Goal:** 迟到的造物／武器确认只完成原请求，保护后来新操作；容量竞态保留待收入图纸，腾位后仅本地补存、不重发造物／装备、不二次扣墨。
**Architecture:** net/creation_receipts.gd持有最多两个已确认待归档项，捕获请求的世界／epoch／制作上下文；main制作流程改变递增context。服务器仍唯一决定生成和计费。session在原Ready/回执/pending机制外只接个人图纸完成逻辑。
**Tech Stack:** 固定Godot4.6.3／GDScript；协议10和存档不变。
**Spec:** SPEC.md §5完整草稿、§7失败保留／只扣一次、§8个人背包。

## Global Constraints
- 不改数字键、3四阶段、造物位置／物理／权限／耗墨，未Ready仍不发送生成请求，不自动生成。
- 每种仍最多一个在途spawn/equip_drawing；有已确认待归档项时拒绝新的造物请求，最多两项。
- 待归档为会话临时记录；原草稿保留，个人图纸成功保存后才清对应稿。已确认图纸可在重同步／重连时本地归档；世界变更后不清新场景稿。
- 只整理原上下文／原内容；不取消新轮盘／新放置，不清新模式草稿／填充偏好。旧成功完成消息不得改写新操作提示。
- 临时工程／私有资料，保留共享checkout和历史冻结包，不部署、不Maker远程构建，不启动已停预览。

## Review Focus
- 原请求成功时用户已切换工具、新选图纸、取消并重开同稿轮盘，均保留新工作。
- 背包127→128在途竞态，不假称图纸入包；腾出一格只补存一次，不再次发送网络命令。
- 同时spawn/equip两项待归档、逐格腾位、重复回执／重复点击不重复图纸／生成／扣墨。
- 失败／Ready未到仍保留全部稿和原装备；匹配旧模式缓存可清，但当前改稿不清。
- 重连／世界替换时已确认个人图纸归档不误清新世界；待归档不承诺跨进程保存。

### Task1: 真实入口RED与实现
- [x] 新network_creation_receipt_test.gd：真实main/session入口复现新放置被清、新轮盘关闭及容量竞态，未Ready／失败／重复保护。
- [x] 最小context及creation_receipts helper，局部接session回执，GREEN，原weapon_type_ack及保存测试通过。

### Task2: 完整验收与成套冻结
- [x] 实际双客户端在真实回执到达前修改本机上下文／填满背包，服务器物件／耗墨只一次，腾位后个人图纸补存。
- [x] 独立复核一次、必要的一轮RED→GREEN修正，完整原生／Web／Python验证。
- [x] SPEC v0.51、r18独立本地成套包、完整性和失败证据归档。

## Execution ledger
Ruling: 用户已授权直接按顺序改进，沿用现有Godot和输入；不重复确认设计。共享未跟踪源码保留，改动前文件另存/tmp，不切分支／提交。容量竞态如果仅保留稿让用户再按生成会造成第二件造物和重复扣墨，因此选已确认本地图纸补存；不做网络盲重试或扩容。
Pre-flight: session pending去重／重连重放保持；原武器容量失败测试继续兼容实际入口的补存，不强制再发equip。迟到回执只持有请求snapshot/context，不把新状态当作原状态。

Task1: 实际入口RED19／11→GREEN19／0。扩充旧世界补存不能在新世界放成功特效，RED20／1，已加scope保护等待最终20／0。旧weapon_type_ack的原6项语义保留；容量恢复改成局部补存，不再伪造第二equip回执，新增不发网络断言后7／0。

Review fix pass: 独立复核3个P2：实际pointer补画按住期间、素材候选切换、背包选择。新子回归复用现有真实夹具RED6／3→GREEN6／0；制作context覆盖落笔和素材流程，背包选择单独计数，不把选卡当成新画稿。原20项最终20／0。第一次真实网络机器人在本地图纸补存后未等Ready即装备，超时，首轮未记录equip发送序号；夹具时序是推断，保留失败；夹具增加实际Ready条件后100ms完整通过，不改游戏Ready策略。

Final receipt feedback: 补存发生于新上下文时，避免残留自身未保存提示，RED22／1；仅当前文字仍等于helper自身notice时替换为补存成功，保留后来用户操作提示。源／Web／权威最终包需重建。

Final reuse boundary: 第一轮完整136／136后补充同工具复用自由造物图纸，不应清掉与复用无关的未完成稿，RED24／1。只结束原图纸放置意图，保护当前／缓存稿，不额外入图纸。最终包更新并重跑全量，不能用前一全量冒充最终来源。

Final verification: 最终生产源码单次136／136、Web11／11、Python4／4。原生实际窗口流程已完成，但初次退出create.wav活动播放造成资源未释放，verbose确认AudioStreamWAV及Playback；机器人改为像正常导航先queue_free游戏／session，让原_exit_tree清理音频后再quit，成套100ms／256KiB/s通过。只改测试清理，生产源码／已导出运行包字节不变，不把夹具修正说成游戏资源修复。只更新冻结来源中的该机器人及其哈希，完整行为回归不包含该机器人；实际成套重新运行验证。

Final complete: 最终核心24／0、上下文6／0、原武器确认7／0、完整最终源码136／136、Web11／11、Python4／4。冻结权威原生100ms实际窗口／Web适配600ms双完整客户端均PASS，每向256KiB/s，服务器落盘物件数1。原生实际等待／完成PNG及waiting/commands/bag元数据已读取。原生源码1244文件、Web10文件108764915字节、权威914文件，36份清单零差异，当前源码一致。Maker预览stopped未启动，无远端构建／部署／Git提交。
