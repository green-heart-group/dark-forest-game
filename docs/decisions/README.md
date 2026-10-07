# 重要决定

项目上的决定：用什么平台、代码和分支怎么组织这类。游戏规则的决定不在这里，记在
[游戏设计 §14 决定记录](../design/game-design.md#14-决定记录)。

每个决定一个文件，文件名为 `NNNN-简短英文标题.md`（例如 `0002-archive-python.md`），编号接着往下排。
内容包括：状态和日期、背景、考虑过的选项、最终选择和理由。后来改了主意，不改旧文件的结论，
新写一条，在旧文件的状态里写「被 NNNN 取代」。

- [0001-platform.md](0001-platform.md)：开发平台用 Godot 4.7.2（已定，[A2](../design/archive/decided-questions-2026-10.md#a2-开发平台)）。
- [0002-archive-python.md](0002-archive-python.md)：旧 Python 版归档到 `archive/python` 分支，主分支只放 Godot 版。
