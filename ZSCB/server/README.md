# 纸上城堡联机服务

Godot 4.6.3 负责实际世界与物理，Python 标准库网关只负责 HTTP/WebSocket 转发。Railway「纸间」已发布，公网双客户端及重启恢复通过；不同网络两台设备实玩仍待验收。证据见 [Railway验收](../docs/RAILWAY_VALIDATION_2026-10-24.md)。

## 本机启动

先用 Godot 4.6.3 导入本工程，或执行 `godot --headless --editor --path . --import --quit`。在 `ZSCB/` 运行：

```sh
python3 server/start_local.py
```

服务地址为 `ws://127.0.0.1:9080/ws`，健康检查为 `http://127.0.0.1:9080/healthz`。可用 `GODOT_BIN` 指定 Godot 可执行文件。Ctrl+C 停止网关和 Godot。启动器不会自动打开游戏、提交代码或连接云端。

| 配置 | 默认值 | 用途 |
| --- | --- | --- |
| `PORT` | `9080` | 网关监听 `0.0.0.0`，公网入口唯一端口 |
| `NET_PORT` | `9081` | Godot 只监听 `127.0.0.1` |
| `NET_DATA_DIR` | 启动器使用 `~/.local/share/paper-castle-server/worlds` | 世界存储目录 |
| `NET_MAX_ROOMS` | `4` | 总房间上限，允许 1–16 |
| `NET_MAX_CONNECTIONS` | `32` | Godot 总连接上限，允许 4–128 |

房间人数固定为两人。世界文件和相邻的 `worlds_credentials/` 凭据目录都必须持久化；凭据不写入仓库或日志。客户端使用服务器下发的玩家凭据，不以房间码、连接编号或客户端提交的 ID 取得管理权限。

## 当前 Railway 服务

控制台：[纸间](https://railway.com/project/0b37d382-be77-4457-b91d-bb52569b243d)。服务 `paper-server`，一个副本，持久卷挂载 `/data`。游戏地址 `wss://paper-server-production-4b68.up.railway.app/ws`，HTTPS `/healthz` 返回 `ready`。域名提供游戏协议入口，不能作为浏览器游戏页面使用。

当前平台给容器的 `PORT=8080`，域名目标端口为8080。网关读取平台 `PORT`；本机默认9080不能直接当作公网端口。实际持久卷位于sfo，应用跟随该卷部署。本次链路应用ping中位数约273–330ms，不是约100ms手感验收。

新服务已经不能启用旧 `railway.json` / `railway.toml`。本次用官方 CLI/API 直接配置，字段记录在 `railway-service-settings.json`；该文件是服务设置清单，不会被 Railway 自动读取。后续若采用 IaC，应按[现行官方文档](https://docs.railway.com/infrastructure-as-code)迁移，先检查计划，避免删除现有服务或存档卷。

上传时只取 `project.godot`、`scripts/`、`scenes/`、`animations/`、`assets/` 及服务器运行文件作为独立构建根，不上传本机用户存档、凭据、测试资料或其他工程。Dockerfile路径为 `server/Dockerfile`，构建根相当于 `ZSCB/`：

```sh
docker build --platform linux/amd64 -f server/Dockerfile -t paper-castle-server .
docker run --rm -p 9080:9080 -v paper-castle-data:/data paper-castle-server
```

Docker 固定官方 Godot 4.6.3 Linux x86_64 包和 SHA512，清除宿主机 `.godot` 后重新导入资源，并安装 Noto CJK 字体。Railway维持一个副本；须挂载持久卷 `/data`。不要给同一存储增加多个副本。Railway TLS 入口对客户端提供 `wss://<域名>/ws`；容器内网关使用明文 loopback WebSocket，不自行管理证书。不能把 Godot 的内部端口直接作为公网端口。

`/healthz` 只有在 Godot 接受并正确完成真实 WebSocket 握手时返回 200。启动失败、编译依赖失败或停止 Godot 均不应得到健康状态。更新和重启会断线；创建者凭 `world_id` 和自己的凭据重开已保存世界，获得新房间码。

## 协议

WebSocket 文本帧，内容由 `PaperNetCodec` 编解码 JSON；二维向量使用 `{"_v":[x,y]}`，颜色使用 `{"_c":[r,g,b,a]}`。客户端不能使用对象反序列化格式。

1. 新世界：`{type:"create",map_id,name}`。已保存世界：增加 `world_id` 与 `owner_token`。允许地图为 `paper`、`knowledge-v1`、`nature-v1`、`medieval-v1`。
2. 加入：`{type:"join",code,name,token?,known_tokens?}`。`token` 用于已签发身份的重连；同一服务地址已保存的 `known_tokens` 可提供 `world_id → credential` 对照（最多256项），只选取当前世界的凭据并由房间验证，用于重开房间后保留作者身份。
3. 响应 `welcome` 包含 `code,player_id,token,owner,world_id,epoch`。必须安全保存自己的凭据；快照不包含这些秘密。
4. 接收 `snapshot_begin {epoch,chunks}`、多个 `snapshot_chunk {epoch,index,data}`、`snapshot_end {epoch}`。按从零开始的索引拼接 `data` 字符串，然后解码一次，不能分别解码片段。
5. 完整应用快照后发送 `{type:"ready",epoch}`，收到 `ready` 后才能提交命令。服务器发最新状态；快照期间的变动由最新帧的 `revision` 边界检查补齐。发现版本或对象目录不匹配时发送 `{type:"resync"}`，重新完成快照和 Ready；每连接重同步最多每秒一次。常规重同步只阻止该连接提交新操作，已有角色仍可受击，输入按原超时归零。
6. 操作：`{type:"command",epoch,seq,op,...}`，必须显式携带当前世界 `epoch`；回应 `result` 带 `seq,epoch,ok,error,op,...`。玩家身份始终由连接已认证状态取得，忽略报文伪造的玩家 ID。输入操作为 `op:"input"` 及 `left,right,up,down,jump` 布尔值；无移动时也应发输入心跳。输入与其他操作各自使用严格递增正整数序号；房间保留有限的操作结果去重缓存。
7. 导入成功更换 `epoch`；服务器先发 `world_changed {epoch}`，再发送新快照。旧版或缺少 epoch 的命令会以关联原 `seq/op` 的 `result {ok:false,error:"stale_epoch"}` 拒绝，等待 Ready 的命令回应 `not_ready`。客户端收到版本变更后清理旧版待确认操作，不能重放到新世界。
8. 约 20 Hz 的 `frame` 包含 `epoch,tick,revision,actors,bodies,entities` 等最新状态。慢连接跳过过期位置帧；WebSocket 仍然是可靠有序 TCP，不能据此宣称 UDP 低延迟。
9. 应用心跳 `{type:"ping"}` 回应 `pong`。至少每 5 秒发送一次心跳或操作；20 秒无应用报文关闭连接。握手后 10 秒未加入、60 秒仍未 Ready 也会关闭。意外断线的角色立即停用，由房间保留 30 秒席位。
10. `error {error}` 表示拒绝；`closed {error}` 表示房间结束。创建者 `op:"leave"` 保存关房，客人收到明确结束原因；客人主动离开只退出本人。

网关限制 8 KiB HTTP 头、64 个并发连接、每方向 256 KiB 转发缓冲。Godot 限制 1 MiB 入站报文、每秒 100 条及 2 MiB、32 条可靠队列和 2 MiB 应用队列及出站缓冲；完整快照最多 16 MiB，以 8192 字符分片流式发送。超限拒绝或断开，不能通过延长队列累积旧状态。

## 验证

```sh
python3 tests/network_transport_test.py
python3 tests/network_transport_test.py --godot
```

前者用真实 TCP/WebSocket 上游验证网关；后者在临时工程副本、独立存储目录中启动真实 Godot 及网关，验证 Ready、双人限制、身份、分片、房间隔离等，不触碰本机真实作品。测试失败时检查 Godot 错误输出。它们不能替代 Docker 实际构建、Railway 部署、跨网络两设备或拥塞手感验收。

依据：[Godot 4.6 WebSocketPeer](https://docs.godotengine.org/en/4.6/classes/class_websocketpeer.html)、[Godot 专用服务器](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_dedicated_servers.html)、[官方 4.6.3 发布](https://github.com/godotengine/godot/releases/tag/4.6.3-stable)、[Railway 公网规格](https://docs.railway.com/networking/public-networking/specs-and-limits)、[Railway 配置文件](https://docs.railway.com/config-as-code/reference)。
