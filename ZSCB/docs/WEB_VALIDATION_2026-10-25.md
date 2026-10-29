# 指尖公网网页版验收（2026-10-25）

可玩入口：https://zhijian-web-production.up.railway.app/

## 发布边界

- 用户明确要求直接交付公网游戏页面。本轮新增Railway项目「纸间」中的独立静态服务 `zhijian-web`，未重部署权威服务器或改动其持久卷。
- 固定源码：`dist/指尖双人对战版-20261025-r2/`；协议2，与当前r2权威服务器一致。后续开发目录与r3黑红表现包的改动没有自动进入本网页版。
- 构建：在 `ZSCB/` 执行 `python3 web/build_web.py`；输出 `dist/指尖网页版-20261025/`。只复制游戏脚本、场景、动画、资产与项目配置，没有复制账号、玩家身份、本机存档、测试或后端源码。
- Godot4.6.3，Compatibility/WebGL2、单线程。Web关闭不支持的2D MSAA并标明桌面专用设置；音频设Stream。打包Noto Sans CJK SC Regular（OFL1.1），覆盖SystemFont、直接绘字及默认主题字体。
- 官方导出模板和字体来源／校验在 `web/vendor-sources.json`。只校验下载的ZIP条目及其CRC32／SHA256，没有宣称校验整个1.25GB模板压缩包。
- 静态服务Caddy，PORT8080，健康检查 `/`，单副本。`web/deployment.json` 和导出目录 `WEB_RELEASE.json` 记录服务、最终部署ID和文件校验。首次资源共约106.5MB未压缩；WASM使用gzip，PCK本身压缩收益只有约1.4%。

## 实测证据

1. 本机IAB真实网页加载，进入中世纪地图，Space跳跃、鼠标多点拖画、数字1生成物理实体，显示成功特效；字体修复后底部直接绘制中文可读。
2. Railway部署717e1d26-1a09-49be-b2a3-5ba56c6359be为SUCCESS，HTTPS首页200；公网首页SHA256与本地导出一致。WASM为application/wasm并返回Content-Encoding:gzip。资源max-age=0,must-revalidate，首页no-cache。
3. Chrome真实打开公网HTTPS游戏，浏览器创建平地房间472004F5；另一隔离用户目录的真实Godot r2客户端通过公网WSS加入。不是模拟服务器，也没有向网页注入状态。
4. 浏览器拖画并按1，服务器确认后清空草稿并触发CREATED特效；原生客户端收到该实体，个人图纸仍为6项，删除另一玩家实体被拒绝。原生客户端再生成矩形，浏览器实际看见两个人物、线条与矩形。证据：`previews/web-2026-10-25/public-dual-client.png` 与 `peer-results.json`。
5. Chrome标签显示正在播放音频；仅确认浏览器实际开始播放，未对扬声器听感作主观保证。
6. 浏览器通过作品菜单保存并返回封面，原生客户端确认owner close并正常退出。首轮临时测试脚本在同步期间直接send_op返回无效序号而超时；修正测试为等待ready_to_play后完整重跑并通过，未据此修改游戏协议。
7. 实测发现联机状态栏的默认Label字体另有缺字；默认主题修改不足以修复该Label，改为Web副本中只为HUD显式指定同一中文字体；最终部署为ef13480c-f1a0-4ef8-971b-ff05b4a5a97e。网络逻辑与r2一致，仅增加这一行字体覆盖。最终状态SUCCESS；Chrome用显式新地址重新导航后，实测状态栏“房间／画家／等待朋友加入”完整可读（public-final-font.png），保存的线条与矩形仍在。复验房间0D5B0B12已保存并退出。原权威服务部署ID仍为8b104ff7-7435-4e7c-83ea-5f8a2e307b5f，SUCCESS。

## 已知边界

- 本轮是同一台Mac上的Chrome网页加原生客户端，经公网Railway服务器联机；不同网络的两台物理设备、手机实玩、长时间后台／断网恢复没有本轮验收证据。
- IAB公网页面加载后的自动化AX／截图多次超时，切换Chrome原生UI验收成功；没有将该工具超时当作游戏通过或修复证据。最终建议直接用电脑Chrome／Edge打开。
- 浏览器站点数据保存个人身份和本地资料；清除站点数据、隐私模式、不同浏览器不会自动继承身份。关闭／后台挂起标签不能视为持续在线。
- WebGL2、内存、首次网络下载和约300–360ms实测往返会影响体验；本轮没有宣称所有设备或网络流畅。

## 技术依据

- https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html
- https://docs.godotengine.org/en/4.6/classes/class_systemfont.html
- https://docs.godotengine.org/en/4.6/classes/class_themedb.html
- https://caddyserver.com/docs/caddyfile/directives/encode

这些文档解释适配方案；运行结果以本页实测及截图为准。
