# 指尖公网网页实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 交付浏览器打开即可进入实际游戏、可连接当前双人房间的HTTPS网址。

**Architecture:** 从`dist/指尖双人对战版-20261025-r2/`复制构建副本，WebGL2/单线程导出；Caddy静态服务部署到既有Railway项目的新服务，复用当前WSS后端。

**Tech Stack:** Godot4.6.3 WebAssembly/WebGL2、开源CJK字体、Caddy、Railway CLI。

**Spec:** `../specs/2026-10-25-playable-web-design.md`

## Global Constraints

- 对战协议2；不更改现有服务器或卷，不覆盖r2固定包与同期开发源码。
- 只导出游戏资源，不发布本机存档、账号／玩家凭据或测试资料。
- 用户明确要求直接实施。当前仓库均未跟踪，使用独立导出副本隔离，避免新worktree漏掉实际源码；不做无关Git提交。

## Review Focus

- 中文字体必须实际出现，覆盖封面／按钮／地图文字。
- WebGL2渲染、输入、绘画和音频不能只验证加载成功。
- 浏览器存档与房间身份区分，刷新／切换标签不得误称持续在线。
- wasm与资源文件使用正确MIME、压缩及更新策略；缺文件明确失败。
- 浏览器与原生当前协议2兼容，不能拿历史r1作验证。

### Task 1: 可运行的本机Web导出

**Files:** 创建`web/build_web.py`、`web/shell.html`及所需字体来源记录；生成独立`dist/指尖网页版-20261025/`。

- [x] 获取官方匹配模板，记录校验；只安装本次导出必需内容。
- [x] 在独立副本覆盖WebGL2、单线程、打包中文字体；不改玩法。
- [x] 生成index.html/pck/wasm/js，使用实际浏览器操作检查封面、地图、角色移动和造物。

### Task 2: 公网可玩入口

**Files:** 创建`web/Dockerfile`、`web/Caddyfile`，记录部署元数据。

- [x] 以现有CLI授权创建网页服务，设置静态健康检查及单副本，上传导出文件。
- [x] 验证HTTPS、wasm MIME、压缩、资源可读及真实页面可玩。
- [x] 浏览器创建双人房间，另一真实客户端加入，验证共享造物和正常离开。
- [x] 更新SPEC与`docs/WEB_VALIDATION_2026-10-25.md`，最终只给实际可玩的地址及必要操作。
