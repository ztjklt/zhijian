# 纸间 · Railway 双人联机验收

日期：2026-10-24，上海时区。当前已有实际云端运行和公网双客户端证据。不同网络两台电脑的人类实玩、Windows安装包及拥塞手感仍未验收。

## 现在怎样玩

同一工程的地图扩展与UI任务仍在同步写入。为保持客户端与本次云端版本一致，双击工程里的 `打开纸间联机验证版.command`，它打开根目录 `dist/纸间联机验证版-20261024/` 中固定的实际部署版本。该版本使用首次公网验收时完整的地图，另接入云端地址及凭据恢复修复；进行中的180米地图扩展没有纳入。此启动器使用本机已安装的Godot4.6.3，不停止原游戏窗口或改写旧作品。

大厅默认连接 `wss://paper-server-production-4b68.up.railway.app/ws`；保留旧地址的用户可点击“使用纸间云服务器”。一人创建双人房间，朋友用相同版本客户端及同一服务器地址输入房间码。创建者离开保存并关房，下次从“我的云端作品”重开。每房最多两人，服务器最多四房；单人入口继续存在。

可分享的同版本文件为 `releases/纸间联机验证版-20261024.zip`（约24.6MB，SHA256 `de1b69c4c3f1dc4d018423b9cfdd842c134bce167006bf42769bf962c0716826`）。本包需要Godot4.6.3，Windows可导入其中`project.godot`运行。该域名是客户端的WebSocket服务地址，直接在浏览器打开不是网页版游戏。当前没有交付Windows `.exe` 或浏览器客户端。

## 实际部署

| 项目 | 结果 |
| --- | --- |
| Railway项目 | [纸间](https://railway.com/project/0b37d382-be77-4457-b91d-bb52569b243d) |
| 服务 | `paper-server`，`5f8d31f1-46d1-43c9-8922-9b23989a5e3a` |
| 环境 | production，`b4989764-9594-4552-9649-fbcc086db739` |
| 首次发布 | `18fc1c3a-aaf1-4512-82ac-89cdddcb7ad0`，SUCCESS |
| 过程中同步检查 | `f3573cbc-feb0-40a6-891d-15cea6c63476`；实际画面检查发现同期地图局部素材未完成，随后用完整基线替换 |
| 最终固定客户端版本 | `a840fc9c-16e7-4460-858a-b182eaf37f29`，SUCCESS |
| 运行时 | Debian Linux x86_64、Godot4.6.3固定官方SHA512、Python标准库网关 |
| 公网 | 有效TLS证书的WSS；HTTPS `/healthz` 返回200与 `ready` |
| 端口 | Railway提供 `PORT=8080`，域名目标8080；Godot内部127.0.0.1:9081 |
| 存储 | `/data`持久卷，5000MB容量，sfo；世界与私有成员凭据分目录 |
| 副本 | 一个；不允许以增加副本的方式共享本地内存房间 |
| 上传内容 | 仅游戏源码／资源与服务器运行文件；不含本机用户存档、Railway凭据或测试身份 |
| 固定源码清单 | `previews/railway-2026-10-24/final/deployed-source.sha256`；manifest SHA256 `0821585417739a128ee2bf5bb90a6406f53e6b72747696dfbf651c0182b97001` |

Railway CLI已通过用户确认的当前工作区OAuth授权恢复。应用连接器仍提示重新认证，因此使用官方CLI完成部署。订阅页显示Hobby有效；没有升级套餐或修改支付信息。

新建服务已禁止启用旧`railway.json`，本次以CLI/API配置，实际设置清单为 `server/railway-service-settings.json`，该文件不会被平台自动读取。首轮502来自域名仍指向本机默认9080；日志确认容器使用8080后改正路由，公网200及WSS均已复验。

## 实际验证

- 两个完整Godot客户端通过公网WSS连接同一房间；中世纪与课本均通过生成建筑、共享对象、个人背包隔离、按真实握点装备、远端装备、拒绝删除他人作品、保存确认及创建者关房。中世纪包含真实Metal渲染，截图已读取检查。
- 独立WSS协议检查验证证书、两人入房、第三人`room_full`、客人生成造物、客人不能执行所有者保存及应用ping。
- 首发服务实际执行一次Railway restart后，世界、创建者凭据、客人凭据和客人造物归属均恢复；客人可删除自己重启前的造物。
- 再次发布固定源码前创建另一份测试作品；发布后重新打开同一世界，仍能验证所有者、客人身份及原造物编辑归属。证据在 `cloud-update-prepare.log` 与 `cloud-update-restore.log`。凭据只保存在临时私有文件，未进入此记录或仓库。
- 最终版本再次使用固定客户端分别通过中世纪、课本的公网完整流程，并再次执行真实Railway restart；`cloud-final-prepare.log` / `cloud-final-restore.log`验证世界和作者恢复。最终构建与运行日志没有引擎脚本错误，513个上传源码／资源文件与固定客户端清单逐项一致，ZIP完整性检查通过。
- 新增入口恢复地址回归：修改地址栏后，“重连上次房间”使用原服务器；新建房间使用当前地址且不携带旧凭据。修复前测试实际失败，修复后通过。
- 1280×800与390×844大厅实际渲染通过，支持滚动访问房间按钮。

可复验命令：

```sh
python3 tests/run_network_clients.py --project-source '../dist/纸间联机验证版-20261024' --address wss://paper-server-production-4b68.up.railway.app/ws --map medieval-v1 --visual --evidence-dir docs/previews/railway-2026-10-24/frozen
python3 tests/run_network_clients.py --project-source '../dist/纸间联机验证版-20261024' --address wss://paper-server-production-4b68.up.railway.app/ws --map knowledge-v1
```

持久化验证脚本为 `tests/network_cloud_test.py`，显式分 `prepare` / `restore` 两阶段。fixture必须放在仓库外临时目录；由操作人按已授权范围重启／发布服务后再运行restore，脚本自身不会操作Railway账号或重启服务。

截图：[中世纪公网客户端](previews/railway-2026-10-24/frozen/online-medieval-v1.png)。日志与部署快照位于 `previews/railway-2026-10-24/`。

## 验收边界

同一电脑两个客户端经过真实公网Railway，不能替代不同网络两台物理设备。三轮10次应用ping中位数约330ms、276ms和273ms，最大约655ms、525ms和640ms；该线路仍需实玩评估，不能称为约100ms或拥塞下流畅。

共享开发工程的一次全量回归为49/50：`medieval_product_content_test.gd`的180米地图、九区、新素材数量等七项检查未通过。该地图任务当时仍在另一会话写入；后续一次即时副本还捕获到其`MedievalEntity.supported_kind()`依赖未落地的编译错误。没有把这组进行中的源码当作本次稳定联机版交付，也没有改写该任务的内容或测试。固定联机版和云端同源；当前工作目录后续变动不会自动发布。

本机原有46项行为与12项传输验证详见 `MULTIPLAYER_VALIDATION_2026-10-24.md`。新联机测试、WSS和持久化结果不能替代整个项目的全部产品验收。
