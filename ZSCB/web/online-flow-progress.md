# SDD ledger — plan: ZSCB/docs/superpowers/plans/2026-10-25-online-flow.md
Ruling: 继承用户直接执行偏好；固定r2与协议2用于公网改进，协议3开发不自动部署。当前仓库全部未跟踪，多会话共享；使用独立导出目录，保留固定包，不创建Git提交。
Pre-flight: 大厅解析只公开房间码；默认服务器与恢复凭据绑定原地址。会话与退出共用同一覆盖准备器，所有锚点必须唯一匹配。
Task 1: complete — 初始失败：缺邀请解析、空码联网、重复创建、无取消；修复后ONLINE_FLOW 16 checks/0 failures，lobby_restore PASS。
Task 2: complete — ONLINE_SESSION 10 checks/0 failures；既有save_return 10/0，network_client PASS；5/5脚本通过。真实浏览器发现高DPI缩放与Tab默认样式，正复验修正和窄屏。
Ruling: 旧恢复地址测试在未取消连接时直接创建另一连接，与新的防重复规则冲突；测试明确取消后验证新连接，保持原凭据安全断言。
Task 3: complete — 独立审查提出3项Important，均已复现RED并修复：触摸按钮误落笔、退出失败重连隐藏、生命／保护HUD丢失。会话18/0，5/5脚本通过。真实桌面／390窄屏邀请、复制回执、退出确认可用。弹窗改用统一可滚动Control，待最终导出及公网复验。

公网加载复验：首轮静态部署30e1284e SUCCESS，HTML SHA一致；真实Chrome的PCK流发生HTTP2中断，原Godot加载器悬挂。补唯一锚点reader错误传播与失败兜底，Node真实ReadableStream RED→GREEN（瞬时中断第二次成功／持续中断第四次reject），新静态部署95fd4fb5进行中。

Task 4: complete — 用户追加网页卡顿优化。先增加低频DOM性能读数，真实浏览器比较画面帧时／物理／绘制与公网RTT，再选择修复；保持原流程及协议2。

性能实测：布局重排假设被测试排除（12轮仅2次resize）；复杂武器toolbar缓存96499→89字符，120轮269.249→0.379ms；300实体×60帧扫描2727000→0，134.974→14.766ms。新增帧预算60/20及每秒DOM测量。6/6回归与下载恢复2项通过；独立性能审查无Critical/Important，Minor已纳入默认检查并收窄措辞。正在同世界浏览器前后台、移动绘画及旧资料恢复验收。

Final: 联机流程与性能版均已发布；最终静态4d207091 SUCCESS，authority仍8b104ff7 SUCCESS。完整6/6与加载恢复2/2通过；实际同包前台60／后台20、后台tick持续、切回移动绘画生成及旧世界继续通过。公开Chrome载入最终纸间封面，HTTP资源版本核对通过。自动IAB公开URL超时不算帧率证据。自建窗口、55034／55035预览及独立测试用户目录已清理，临时焦点入口未发布，默认构建／测试指向perf。
