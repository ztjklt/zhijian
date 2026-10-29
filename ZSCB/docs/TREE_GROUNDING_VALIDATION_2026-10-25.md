# 树根贴地修订验收

日期：2026-10-25，Asia/Shanghai。范围为当前 `ZSCB/` Godot 工程。

## 问题与修正

树木原先只把实体中心放到地形高度，PNG 内的根部仍保持水平。坡地上不同位置的根须会悬空或埋入；放大后的橡树偏差超过一米。树木 PNG 的透明留边也不等于实际根部位置，旧作品会继续保存错误的落点。

`medieval_tree_roots.gd` 按原素材底部的有效墨线测量根部包络，对根部局部适配真实土壤曲线，保持上部树干和树冠姿态。橡树、松树和果树使用同一路径；上坡、下坡和坡顶均覆盖。可见网格和碰撞采用同一坐标映射，受击点逆变换回原素材坐标后沿用既有损伤存储格式。

初始放置与旧作品读档都重新定位树根，同时保留血量、损伤、死亡状态和实体 ID。网格在放置／受损时缓存重建，不在每帧读取图片或重新构造。简化网格同时限制轮廓误差和条带宽度，避免内部树皮的显示位置与受击坐标偏离。两个调用方显式预加载新模块，已检查原工程未更新的全局类缓存下仍能编译。

## 专项验证

- `python3 tests/run_isolated.py --script res://tests/medieval_tree_grounding_test.gd`：93 项通过。测量实际渲染网格中的根部墨线，相对于物理土壤的误差要求不超过 2.5cm；包括全部现有树、两倍大小橡树在平地／上坡／下坡／坡顶的情况，以及错误旧落点恢复、重复读档不漂移、已有损伤与血量保留。
- 同一测试包含上坡果树真实树皮点的内部网格／受击对齐回归：渲染映射偏差小于 6mm，逆变换误差小于 12mm。它能捕获只有根部接触行正确、内部三角形插值却偏移的问题。
- `python3 tests/run_isolated.py --script res://tests/medieval_tree_damage_performance_test.gd`：橡树／松树／果树连续 12 次根部受击，分别检查平均 CPU 重建耗时低于 12ms。初版逐像素裁切此项实际失败，最终采用有误差约束的条带简化；最终数值见随附回归日志。
- 原工程直接执行 `Godot --headless --path ZSCB --check-only --script res://scripts/medieval_world.gd`，输出无脚本错误。

以上行为测试使用临时工程和隔离用户目录，没有直接执行会改写玩家资料的测试。完整回归结果记录在本文件旁的验收日志。

## 完整回归与性能边界

`python3 tests/run_headless_suite.py` 最终快照为 **64/65** 通过：本轮树根、砍树性能，以及地图通行、碰撞、城堡、马车、保存／读档、双人房间、UI、绘画与武器功能测试均通过。同期另一任务的自动寻找生成空位功能也在该快照通过。

唯一未过为 `large_weapon_performance_test.gd` 的单帧 16.67ms 性能阈值；该轮在课本与中世纪地图均出现超标，不能称整套单次全绿。为核查来源，在同一个已导入的隔离工程里依次恢复修改前的两个树木调用文件、再换回当前代码，单独运行同一性能测试，两次均为零失败：旧版两地图最大 CPU 单帧约 13.607ms，当前版约 13.908ms。因此记录为全量运行时的性能波动，独立复测通过；这些结果不承诺任何设备或负载下恒定60帧。

最终砍树专项独立记录为橡树 11.483ms／松树 5.432ms／果树 6.863ms 平均 CPU 重建耗时，三项均低于12ms阈值；该记录是在同时存在资源导入负载时取得。全量回归中的三项亦通过。

日志位于 [本次验收目录](previews/2026-10-25-tree-grounding/)：`tree-grounding.log`、`tree-damage-performance.log`、`full-suite.log`、`weapon-before.log`、`weapon-after.log`。原工程编译和四尺寸之外的图像不因本次测试自动视为重新验收；本次实际截图为四个1440×900场景。

## 实际画面

执行 `TREE_CAPTURE_DIR=/tmp/paper-tree-grounding-final python3 tests/run_isolated.py --visual --script res://tests/medieval_tree_grounding_visual.gd`，使用真实 Godot 4.6.3／Metal 渲染当前中世纪场景。四张最终画面已逐张读取检查。

| 地形与树种 | 修改前 | 修改后 |
| --- | --- | --- |
| 大橡树上坡 | [截图](previews/2026-10-25-tree-grounding/before/woodland-uphill.png) | [截图](previews/2026-10-25-tree-grounding/after/woodland-uphill.png) |
| 大橡树下坡 | [截图](previews/2026-10-25-tree-grounding/before/woodland-downhill.png) | [截图](previews/2026-10-25-tree-grounding/after/woodland-downhill.png) |
| 松树山脊 | [截图](previews/2026-10-25-tree-grounding/before/pine-ridge.png) | [截图](previews/2026-10-25-tree-grounding/after/pine-ridge.png) |
| 果树上坡 | [截图](previews/2026-10-25-tree-grounding/before/orchard-uphill.png) | [截图](previews/2026-10-25-tree-grounding/after/orchard-uphill.png) |

本次修改未更新 Railway 服务和固定联机验证包。原来打开的游戏进程没有被关闭；需先保存作品，再重新运行当前最新版工程，才能在该窗口使用磁盘上的新代码。
