# 武器分型与死亡叫声 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; user already asked to directly implement sound improvements.

**Goal:** 五类武器有可辨识的动作／命中音，人物与动物在死亡边沿各叫一次，保留最新UI与破损。
**Architecture:** 本地audio bank选择武器动作／命中及物种死亡cue，反馈事件携带有界audio key；权威事件按编号传递，服务器不加载音频。保留已有三种通用击破与造物音。
**Tech Stack:** Godot4.6，PCM WAV，现有PaperCreationFeedback／PaperNetRoom。
**Spec:** ZSCB/SPEC.md与用户本轮明确声音要求。

## Global Constraints
- 保留真实扫掠、生命伤害、冷却、世界时间、图纸与UI；不部署、不改用户存档。
- 只在存活变死亡时叫；建筑、练习靶、尸体和读档不叫。
- 五类均覆盖：sword、hammer、spear、bow、firearm；远程命中由弹丸种类决定，不读射手命中时装备。
- 叫声与命中可重叠，数量有界、远处衰减，静音设置继续生效。

## Review Focus
- 连续攻击同一尸体；重生后再死亡。
- 弓箭飞行中换武器，另一个人攻击时本机装备不同。
- 挥空／取消拉弓／冷却拒绝，不虚构命中和死亡。
- 联网事件重传，叫声不重复；远方与读档无回放。
- 混音占满，死亡和造物尾音不被小声落笔抢占。

## Tasks
- [x] RED：实际武器动作cue与弹丸命中类型；NPC／玩家／动物死亡一次；联网音色不依赖本机装备，去重。
- [x] 本地样本：取得许可明确的录音并留来源，五武器动作／命中各3变体、物种死亡各多变体；trim／fade／限幅，检查可播放和非空。
- [x] audio bank与有界播放；实际调用点携带audio key，死亡边沿audio-only事件；权威记录、接收、去重，同步版本。
- [x] 专测与完整隔离回归，实机音频播放／无脚本错误；SPEC与证据更新，打开整合新UI的本地新版本。

执行记录：在线Maker素材余额不足且execution_state unknown，未重试；采用已核验CC0的音效与原创本地混音。原始source与逐文件manifest保留；专测武器19／死亡33／联网6／快照6及实际播放路径通过。首轮92/95三个旧死亡事件断言已按新增voice语义更新，第二轮95/95；独立审查的快照P2与播放池变体历史均已隔离RED→GREEN，最终96/96通过。用户要求直接实现，本地原位保留其他会话UI，不执行通用Git/Maker提交或云部署。

完成：96/96完整隔离回归、实际音频播放路径、54/54资源检查与新窗口启动通过。独立审查发现均已单次修复，未留下未解决的P1/P2或音色排重问题；证据见COMBAT_AUDIO_2026-10-25.md。
