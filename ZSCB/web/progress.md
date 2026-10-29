# SDD ledger — plan: ZSCB/docs/superpowers/plans/2026-10-25-playable-web.md

Ruling: 用户连续要求直接给可玩网址，按既有Godot方案直接实施，免去设计问答；额外创建一个轻量网页服务，复用已授权Railway工作区。
Ruling: 当前仓库未跟踪且多会话共享；从已部署r2固定包创建独立Web构建副本，避免覆盖开发或漏掉未提交文件。不创建Git分支／提交。
Pre-flight: 网页文件由导出器产生、静态服务只读；协议2的WSS后端不变；字体与渲染适配只作用于Web副本。

Task 1: complete — 官方4.6.3单线程模板、OFL中文字体、独立WebGL2导出完成；本机真实浏览器已进入中世纪地图、跳跃、绘画并生成物理实体。
Task 2: complete — ef13480c-f1a0-4ef8-971b-ff05b4a5a97e为SUCCESS；公网Chrome真实游戏、浏览器与原生双客户端共享造物、权限隔离、保存退出通过。网页重载后云端作品仍可打开。权威服务器部署仍为8b104ff7，未改动。
Review: 独立只读审查发现直接绘制中文未覆盖，全局字体autoload已补齐；首次导入时preload不可解析，改为运行时load后无错误导出。启动文件下载失败现有明确重试入口。PCK压缩收益仅1.4%，保留现状。

Final: HTTPS实际可玩入口已交付；本机预览和隔离测试进程已停止、独立测试用户目录已清理。复验及限制见docs/WEB_VALIDATION_2026-10-25.md。

Final font check: Chrome显式新地址重载后，HUD中文完整可读，已留图；未根据未刷新的旧画面宣称修复。
