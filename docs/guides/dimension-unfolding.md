# 降维展开演示

降维时，9×9×9 的星图一列一列展开，变成 27×27 的平面，729 个格子一个不少（[U1](../design/decision-log.md#降维展开u)）。
`game/demos/` 里有一个单独的演示场景，只播这段动画，不开对局，用来看展开的样子、调画面。
对局里展开的规则见 [原型现在的规则 §9](../design/current-rules.md#9-降维)，这一页只讲演示怎么用。

## 运行

在仓库根目录运行：

```bash
godot_console --path game res://demos/dimension_unfolding.tscn
```

演示自己的测试已经包含在 `uv run game/tools/test.py` 里（「展开演示」那一组），也可以单独跑：

```bash
uv run game/tools/test.py unfolding
```

## 操作

- 打开时是暂停的，先显示一列。选「全图」看整张星图一起展开。
- 打击点（展开的起点）的 x、y、z 填 0～8；方块上的 1～9 是它原来在第几层。
- 播放、暂停、重播，前后拖动进度条，0.5 / 1 / 2 倍速。
- 左键拖动旋转，滚轮缩放，可以切到俯视或重置视角。
- 关掉「自动取景」，镜头就不再跟着展开的范围移动，仍然可以手动旋转和缩放。
- 快捷键：空格（播放 / 暂停）、左右方向键（拖进度）、R、T、V；在坐标框里打字时不响应快捷键。

## 存截图

测试命令去掉 `--headless`，末尾加上 `-- output=截图目录的绝对路径`：

```bash
godot_console --path game --script res://tests/run_unfolding_tests.gd -- output=C:/temp/unfolding
```

会存下单列和全图在 0 / 35 / 65 / 100% 时的画面，还有全图俯视和打在角上的情况。

## 用到的文件

| 文件 | 管什么 |
| --- | --- |
| `game/rules/unfolding_layout.gd` | 规则和演示共用：一列 9 格怎样排成 3×3，以及展开到一半时每个方块画在哪里 |
| `game/demos/dimension_unfolding.gd`、`.tscn` | 演示场景：方块、镜头、控件 |
| `game/tests/run_unfolding_tests.gd` | 演示的测试：格子一个不少、能还原、相邻的列展开时不重叠、控件和关键画面 |
