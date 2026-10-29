# 纸间：最新版r7成套发布（2026-10-25）

用户明确要求“最新版更新到railway上”。本轮更新范围为当前核心协议6／20261025-r7，包含新纸面UI、生命／墨水、五类武器、渐进几何破损及分型音效，并携带此前网页的房间流程、输入确认／本机预测和有界纠偏。上一轮线上为协议2，不能只重新部署旧ack包后称为最新版。

## 一致来源与边界

- 原始冻结源码：`dist/纸间联机最新版-20261025-r7/`，1180文件，SOURCE_RELEASE.json逐文件SHA256；复制前后及发布前原始运行源码一致，没有混入并行编辑。
- 权威候选：`dist/纸间权威服务-20261025-r7/project/`，890文件，AUTHORITY_RELEASE.json。相对冻结源码仅为actor／room的可选input_ack、input_age、movement_reset及部署忽略文件，不重写玩法。
- 网页候选：`dist/纸间网页版-20261025-r7/`，10发布文件、108689639字节，WEB_RELEASE.json。Web覆盖层保留原生新UI／武器类型轮盘、墨水、破损切口和音效游标；只接入既有浏览器房间流程、输入预测、字体／音频／WebGL适配。
- 公网服务目标保持既有纸间项目、paper-server及zhijian-web；不改域名、单副本、区域、资源或/data持久卷。原生源码包可作为匹配协议6的参考，历史协议2客户端需要更新，浏览器需要刷新。
- 浏览器仍使用config/name=指尖及network_profile.json，原生冻结包保持纸上城堡 · 火柴人沙盒；未迁移用户资料命名空间。旧r2a和flow／perf／latency／ack发布清单均核对完整，构建器拒绝覆盖旧网页回滚目录。

## 验证

- 最新源码直接套用旧Web准备器，因“指尖”标题旧锚点失败；新增实际文件准备回归，改为按协议2／6选择已有适配，最新功能模块保留。RED→GREEN，打包／保护测试2/2。
- Web适配全量 **106/106脚本通过**，覆盖当前核心全部用例及输入ACK、错误ping、短停顿、有序1100ms积压、跳跃次数、房间流程。保留剑姿态全部断言，仅将浏览器不支持的4×2D MSAA预期改为关闭。复杂大武器预算通过，未删掉性能检查。
- 真TCP／WebSocket双完整客户端：纸面地图300ms附加往返／每向256KiB/s，通过双向近战、致死、3秒重生、草稿／装备保留、弓箭、取消拉弓、凭据重连和保存关房。
- 中世纪双完整客户端600ms附加往返／同限速，通过绘画、共享物件、私人图纸、真实握点→类型→确认装备、权限、保存关房。首轮失败源于旧generic bot直接调用两阶段equip_weapon_at，最新版需要类型选择；只在临时夹具改为驱动真实完整流程，未修改游戏绕过确认，也未削弱服务器确认断言。
- 两个真实OpenGL客户端100ms附加往返／同限速，通过生命／墨水实际同步、双向伤害、双方hit／hurt实际画面和对应音频声道播放、保存关房。初轮Web测试副本漏带继承的反馈bot；补依赖后暴露原生驱动不支持Web sample播放及旧bot只查通用hit音色。只在临时原生测试副本去掉Web专用播放模式，并按真实事件audio键查音色；最终通过。不将此路径称为浏览器人工听感验收。
- 下载中断恢复2/2；所有源、权威和Web文件清单通过。独立只读审查未确认Critical／Important产品阻塞，确认所有新玩法、音效游标及旧存档可选字段保留。

## 存档与上线前保护

已在旧协议2线上创建专用验收世界，双人、第三人拒绝、共享造物、房主权限和保存通过。初轮公网spawn等待发生连接reset，失败日志保留；第二轮完整通过，应用ping中位数399.3ms、最大752.9ms。私有fixture仅在/tmp，0600，不进入仓库。

发布前经现有SSH在既有卷中备份 `/data/backups/pre-r7-20261025T074515Z`，包括worlds及worlds_credentials共135文件。凭据未下载或打印。已提醒用户保存并说明现有房间会断线、双方需刷新。

前两次源码上传HTTP超时，分别产生ce13caa1及e26091cd失败候选；Railway元数据为“Failed to create code snapshot”，没有对应build，旧服务/healthz仍200。核对已安装5.71.0官方源码，确认上传使用可由RAILWAY_HTTP_TIMEOUT调整的HTTP客户端，本次仅对上传命令设置600秒，不改用户全局配置。排查和失败证据保留。

技术依据：[Railway CLI上传](https://docs.railway.com/cli/up)、[该版本HTTP超时解析](https://github.com/railwayapp/cli/blob/v5.71.0/src/client.rs)、[上传与忽略文件实现](https://github.com/railwayapp/cli/blob/v5.71.0/src/controllers/upload.rs)。忽略宿主.godot导入缓存，Linux构建仍由同一固定Godot4.6.3重新导入。

## 上传超时后的紧凑部署

600秒客户端超时仍收到网关524，原始源码上传体积128529532字节，第三个候选6240bd92也失败且未构建。为降低请求传输体积，改从已验证权威源码导出Linux PCK，所有图片／纹理资源保留（地面贴合依赖alpha读取，不能剥离它们）。`web/build_server_pack.py`生成 `dist/纸间权威资源包-20261025-r7/deploy/`，game.pck为56165644字节；固定Godot4.6.3的Linux二进制及校验和不变，Python网关、/healthz、端口和/data路径不变。

原来的目录启动器用于PCK独立目录会找不到res://server/server.gd，已先实际复现RED；生成的部署启动器使用Godot官方--main-pack后GREEN。用该实际PCK独立启动服务，经两个完整客户端分别完成中世纪造物／完整武器流程／权限／保存及纸面完整对战／重生／重连／保存关房，服务日志无ERROR。PCK清单及源权威清单均核对。打包层改变，不改玩法源码或把Web包当服务器；证据packed-runtime-check.log、packed-authority.log和PACK_RELEASE.json。

技术依据：[Godot4.6导出资源包](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html)。

## 增量传输恢复

紧凑55MB上传仍524（b99559d4），HTTP/1.1改传也在4.5MB处reset（ea7bfd97）。为绕过本地大文件上传中断，部署层使用标准BSDIFF40增量：从不可改写的旧ack Web PCK分别生成新服务器PCK与新Web PCK，补丁2422722／2363248字节。用系统bspatch及实际生成的rebuild.py各自还原，输出SHA256与已经完整验证的最终PCK逐字节一致，Web的其余发布文件也核对一致。游戏代码、音频、贴图、字体和协议均没有删减。

`web/build_delta_deploy.py`生成独立`dist/纸间增量部署-20261025-r7/`，上传只含补丁及构建脚本。Railway构建时从现有公开网页下载旧PCK／同一WASM，先验基线SHA256，再用Debian bspatch还原，再验最终SHA256；任何下载失败或不一致直接构建失败。新版静态镜像额外保留公开基线`releases/20261025-ack/index.pck`及`index.wasm`，保证域名根目录变更后仍可重建。最终游戏PCK仍分别为56165644／70632248字节，不以补丁体积宣称浏览器下载体积改善。

官方CLI5.71.0源码确认现有OAuth授权字段和上传端点后，仅本轮使用curl HTTP/1.1向同一Railway端点上传；授权只在本机进程内存和curl标准输入，不进参数、日志或仓库，不改全局配置。服务器增量上传HTTP200，候选1638e5df随后实际构建及部署成功；最终结果见下节。标准补丁来源：[bsdiff4项目](https://pypi.org/project/bsdiff4/)。

## 发布结果

已实际成套部署完成，两个现有服务均SUCCESS，健康检查通过：

| 服务 | 新部署 | 协议／构建产物 |
| --- | --- | --- |
| paper-server | `1638e5df-a58c-49c7-8aed-4f3be903838a` | 协议6；Linux PCK SHA256 `b5a00170e4ec5db2d5bdf08e48a331067636389167b46c3e42cf2447d8e44a6a` |
| zhijian-web | `8687c1a3-7f77-4d67-a557-0b3365b09c6b` | 协议6；Web PCK SHA256 `f03e80274eb8bfac4b0884eeb0fa58f57f076ac3dc81ff6dbfaadb94da890c9e` |

入口：[纸间最新版](https://zhijian-web-production.up.railway.app/?release=8687c1a3)。查询参数便于重新打开，不能当作固定版本托管。权威WSS、服务数量、单副本区域、资源设置、PORT和/data均保持原配置。实际Railway构建日志确认基线与完整输出校验、Linux容器启动、Godot4.6.3以及/healthz健康检查；独立对增量构建再次只读复核，未确认Critical／Important问题。

- **跨更新恢复PASS**：发布前协议2创建的专用世界，发布后用协议6恢复；世界、原房主、原访客身份和访客作者权限均通过，最后正常保存／关房。私有fixture留在/tmp的0600文件，不进证据目录。
- **真实公网两完整客户端PASS**：中世纪地图绘画、共享物件、私人图纸、完整武器装备确认、权限、确认保存及房主关房；不是两个协议探针代替完整客户端。
- **公网ACK PASS**：欢迎协议6，输入17有input_ack=17、input_age非负、movement_reset；TLS证书验证开启。
- **公网对战该轮未全通过**：实际双向剑伤、致死、3031ms重生及弓箭伤害已经发生，但guest在“打开图纸取消蓄力”观察窗由HP76继续降为52，该轮失败，不能算全套对战PASS。相似高延迟取消检查在旧协议2的专项报告也有未通过记录；本轮未定位其根因、未修改玩法或削弱断言来凑通过。对照本机300ms全套对战PASS，公网失败原日志保留为public-duel-failed.log。后续仍须处理此项，不宣称战斗延迟已全部消除。
- **最终静态文件核对PASS**：公网HTML／JS／worklet／图标／许可6个文件完整SHA256与清单一致；新PCK／WASM及保留基线的64KiB前缀SHA和Content-Range完整长度一致。大文件没有冒称完成公网全量下载哈希，完整PCK哈希由实际Railway构建校验提供。

发布前已有07:45的协议2私有卷备份；09:23又在现有卷中复制worlds及worlds_credentials135文件至`/data/backups/pre-r7-cutover-20261025T092339Z`（此时新容器已经启动，因此第二份是发布后的额外备份，不能冒称协议2原始快照）。凭据未下载／打印。旧原始包、r2a及旧Web回滚包均保留。

当前工作目录1180个运行源码文件在发布前再次与冻结清单核对，0变化；本轮只修改Web打包、测试适配与文档，未覆盖并行玩法工作。双方必须刷新页面；旧协议2原生客户端需要换成匹配的协议6源码／最新版客户端。

## 浏览器画面

同一最终包在本机55038静态托管，已用真实浏览器检查封面、选图、新UI／生命墨水、握点及五类武器轮盘。选择火枪、确认装备、R发射可见扣墨及实际命中反馈；画面见web-weapon-wheel.png、web-firearm-local.png。这些先行检查为单人，不冒充公网联机。发布后用该同一最终Web资源包继续连接真实公网WSS，创建中世纪房间，按D／空格／A走动跳跃，画四笔矩形并按1确认，权威对象数从0变为1，实际物件出现；保存并结束获得确认后回到大厅。截图web-public-online.png、web-public-saved-lobby.png及只读DOM指标web-public-metrics.json保留，ACK预测已启用，观察RTT约283–368ms。指标显示本机该场景60fps，不推广成所有设备帧率或零延迟。

这组交互画面使用本机静态托管的逐字节相同最终Web包和真实公网权威，不能称为最终公网静态域名完整加载验收。新开公网域名的浏览器标签已创建，但CUA绑定该标签两次超时，未取得引擎运行画面，最终公网静态域名的完整浏览器加载仍为UNDETERMINED；已完成的公网静态文件校验、远端健康检查和实际WSS交互证据分别保留。

不同网络两台物理设备实玩仍未验收。模拟RTT、原生音频组件检查、同机公网双进程与浏览器画面各自记录，不承诺零延迟或把局部计数称为用户设备整体帧率。

证据目录：`docs/previews/latest-railway-r7-2026-10-25/`。

```sh
python3 ZSCB/web/build_authority.py
python3 ZSCB/web/build_web.py
python3 ZSCB/web/run_checks.py --all
python3 -m unittest discover -s ZSCB/web/tests -p 'test_*.py'
python3 ZSCB/web/tests/run_network_checks.py --duel --map paper --latency-ms 300 --bandwidth-kbps 256
python3 ZSCB/web/tests/run_network_checks.py --map medieval-v1 --latency-ms 600 --bandwidth-kbps 256
python3 ZSCB/web/tests/run_network_checks.py --vitals --map paper --latency-ms 100 --bandwidth-kbps 256
```

重现构建会替换当前候选的生成目录；将来更新先使用新的输出目录／冻结源码，不能改写历史回滚包。

收尾：最终再次读取两服务均SUCCESS，/healthz仍HTTP200 ready；六份来源／输出清单共2104项SHA256逐一通过，当前运行源码仍与1180项冻结来源一致。测试世界已正常保存关房，只停止本轮55038本机HTTP服务，不关闭用户其他游戏或浏览器。最终状态见证据final-status.json。
