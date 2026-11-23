# 模型连接、本机联机与开发

桌面试玩的下载和启动方式见[首页](README.md)。

## AI 角色

使用自己的模型时，先安装 Node.js，在仓库根目录运行：

```sh
npm ci --prefix ZSCB/tools --ignore-scripts --no-bin-links
```

在封面「设置 → AI 角色」添加服务商、模型与 API Key，再绑定游戏角色。支持 DeepSeek 官方地址和兼容服务，调用计入该 Key 对应的账户。

## 本机联机

用同一份仓库启动客户端和权威服务器。在仓库根目录运行：

```sh
python3 ZSCB/server/start_local.py
```

服务器缺省地址为 `ws://127.0.0.1:9080/ws`。服务器和客户端的设置见[联机说明](ZSCB/server/README.md)。

## 维护

发布时以本地常规试玩入口的冻结版为来源，一并更新 [README 的构建号](README.md)。每次推送到 `main` 都会从干净检出检查封面、内置试玩和队伍存档。完整原生、Web 和联机回归可在 [GitHub Actions](https://github.com/ztjklt/zhijian/actions/workflows/checks.yml) 手动运行。

[早期海报、美术底稿与历史启动器](https://github.com/ztjklt/zhijian/tree/d0d3b6f7c3d97be1bff7335f120671953e8c765f)
