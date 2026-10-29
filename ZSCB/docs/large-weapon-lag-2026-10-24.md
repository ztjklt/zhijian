# 大尺寸手持武器卡顿修复 · 2026-10-24

用户确认卡顿发生于大尺寸手持武器，尤其右键、反向挥动。当前旧窗口进程于上海时间 20:17:23 启动，尚未加载其后更新的中世纪战斗优化。先通过游戏菜单保存实际作品，另在根目录 `logs/weapon-lag-2026-10-24/user-work-before-restart.json` 留下备份。

## 原因与修复

大武器跨帧运动较远，时间采样数量随之增加。中世纪碰撞虽然已经筛掉远处物体，仍在每个时间样本重建整把武器，并遍历目标附近所有笔画。宽大、空心、多笔武器的许多线段从未接触该目标，这部分开销随笔画数与采样次数相乘。

`scripts/medieval_world.gd` 现在先依据每段笔画前后帧端点形成的保守包围范围，筛选该帧可能接触每个目标的线段，缓存其四个端点；时间采样只插值候选段。没有握点参数的兼容调用仍按完整模型计算参考中心。继续使用原采样间距、次数上限、点在多边形内检测、实际线段相交、最早时间及握点最近位置排序。浮点包围范围增加 0.00001 米余量，仅防止筛选误排除边界接触，不扩张实际命中范围。

## 验证

所有自动验证通过 `tests/run_isolated.py`，使用临时工程及独立用户目录。日志位于项目父目录 `logs/weapon-lag-2026-10-24/`。

- `large_weapon_performance_test.gd`：真实课本／中世纪场景，16 笔、每笔 72 点的大空心轮廓，双向四式。修复前中世纪向左重斩战斗计算峰值约 21.00 ms；修复后约 13.36 ms。本机该轮所有组合低于 16.67 ms。此数字是战斗 CPU 耗时，不是整帧或所有复杂度的保证。
- `saved_weapon_performance.gd --visual`：恢复用户实际保存的 2 笔、76 点武器，使用 Metal 真实渲染、双向四式。各组合战斗计算峰值 0.579–1.219 ms；除第一组启动预热外，观察到的渲染帧间隔 P95 约 8.6 ms。没有将帧间隔等同于 GPU 单项耗时。
- `large_weapon_contact_test.gd`：35 项。独立完整遍历算法对照随机多笔轮廓、地形、跨帧运动、有限／缺省握点、边界接触及前后顶点数变化，验证命中存在性、最早时间和位置。
- `medieval_combat_test.gd` 32 项、`medieval_performance_test.gd` 4 项、`blade_spatial_test.gd` 97 项、`blade_model_test.gd` 22 项、`weapon_motion_test.gd` 1188 项、`weapon_grip_test.gd` 33 项、`numeric_controls_test.gd` 30 项、`test_runner.gd` 93 项；连同上述 35 项，共 9 组、1534 项通过。

重启前先保存原作品与备份，重新导入实际工程的新资源，再启动当前源码并从地图入口读取原作品。原来的大手绘武器已恢复，在实际窗口验证右键左右挥击及 R 攻击；运行日志无脚本错误。测试未进行云部署、Maker 构建或多人性能验收。

实际保存武器复现命令（从项目父目录执行）：

```sh
PAPER_CASTLE_WEAPON_FIXTURE="$PWD/logs/weapon-lag-2026-10-24/user-work-before-restart.json" python3 ZSCB/tests/run_isolated.py --visual --script res://tests/saved_weapon_performance.gd
```
