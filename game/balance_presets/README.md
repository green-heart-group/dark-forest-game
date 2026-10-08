# 共享的数值方案

这里放大家都能用的数值方案（`.cfg` 文件），会提交进 git。只放值得分享的方案（比如某一轮试玩用的数值）；
自己临时试的方案存在个人目录 `user://balance_presets/`，不进 git。

每个方案只记和 `game/balance.cfg` 不一样的数值，是普通文本，可以直接看、直接改：

```ini
[info]
note="E7F6 第二轮试玩：能量多一点"
saved="2026-10-06T21:30:00"

[values]
START_ENERGY=30
STAR_WEIGHTS=[6, 3, 1]
```

怎么用：

- 游戏里：调试面板（F12）的「🔧 数值」页，选方案、存方案、导入文件、设成新开一局时默认用的方案，
  用编辑器版运行时还能把方案写回 `balance.cfg`。详见 [调试模式](../../docs/guides/debug-tools.md)。
- 平衡模拟：`godot_console --headless --path game --script res://tools/simulate.gd -- PRESET=方案名`，
  后面再写的数值（比如 `COST_PROBE=8`）会盖过方案里的。

方案定下来要成为正式数值时，写回 `balance.cfg`，再跑 `uv run game/tools/update_docs.py` 更新文档里的数字，
然后可以把这个方案文件删掉。
