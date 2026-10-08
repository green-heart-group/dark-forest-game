# 文档索引

这里的文档会进 git，和所有合作者共享。仓库首页的 [README](../README.md) 只写简介和怎么运行，其余都从这里找。
索引分三层：仓库首页 README → 这一页 → 各目录自己的 README（列出目录里的每个文件）。

## 每样内容只写在一个地方

别处只放链接，不抄内容。

| 想知道 | 看哪里 |
| --- | --- |
| 游戏要做成什么样、为什么 | [design/game-design.md](design/game-design.md) |
| 某条规则是谁、什么时候、为什么定的 | [决定记录](design/decision-log.md)（游戏规则）、[decisions/](decisions/README.md)（平台、分支等项目上的决定） |
| 原型现在实际怎么运行、具体数值 | [design/current-rules.md](design/current-rules.md)（数值的出处是 `game/balance.cfg`） |
| 还没定、要回答的问题 | [open-questions.md](open-questions.md) |
| 做到哪一步、测试个数、平衡模拟结果 | [status.md](status.md) |
| 接下来要做什么 | [roadmap.md](roadmap.md) |
| 每天做了什么、改了什么 | [devlog/](devlog/README.md) |
| 提议和试玩意见的原文 | [proposals/](proposals/README.md) |
| 常用命令：安装、运行、测试、平衡模拟、导出和发布 | 仓库首页 README 的 [快速开始](../README.md#快速开始)、[开发](../README.md#开发) |
| 只和某个工具有关的命令和参数（调试参数、截图、生成数值目录等） | 那个工具所在的 [指南](guides/README.md) |
| 代码怎么分工、改代码要守的规矩、导出设置 | [guides/code.md](guides/code.md) |
| 调试面板、开发者版、对局记录、数值方案 | [guides/debug-tools.md](guides/debug-tools.md) |
| 怎么用 Godot、让 AI 助手操作 Godot | [guides/](guides/README.md) |
| 怎么开分支（分支名的前缀）、提交改动、合并进 `master` | [decisions/0003](decisions/0003-github-flow.md) |
| 旧 Python 版和它的已知 bug | [decisions/0002](decisions/0002-archive-python.md) |

## 现在的事实和历史记录

文档分两类，守的规矩不一样：

- **现在的事实**：上面表里除了开发日志、提议、存档、决定记录和 `decisions/` 以外的文件，还有仓库首页 README、`AGENTS.md`。
  只写现在是什么样，过时了就改掉，不留「以前是……」。不写在哪个分支上、合没合并、自己电脑上的路径，
  不放做事用的勾选清单（[路线图](roadmap.md) 除外）。测试个数只写在 [现状](status.md)，由 `test.py` 自动写。
- **历史记录**：[devlog/](devlog/README.md)、[proposals/](proposals/README.md)、[design/archive/](design/archive/README.md)、
  [decisions/](decisions/README.md)、[决定记录](design/decision-log.md)。只往后加，写下当时的情况，以后不回头改，所以里面的数字和说法可以过时。
  做一项工作时的步骤、验证经过、交接说明，写进当月的开发日志，不另开文件。

这些规矩和编号、索引的规矩，大多由规则测试 `test_docs.gd` 检查（见 [代码结构「写测试的规矩」](guides/code.md#写测试的规矩)），
改完文档跑一次 `uv run game/tools/test.py rules --only docs`。

## 目录

- [open-questions.md](open-questions.md)：要确定的问题。所有还没定的问题都在这里，每条都有选项和推荐，答完就挪走。
- [status.md](status.md)：现状。原型做到哪一步、测试个数、平衡模拟的最新结果。
- [roadmap.md](roadmap.md)：路线图，记录接下来要做什么、做到哪一步。
- [devlog/](devlog/README.md)：开发日志，按月记录已完成的工作和它带来的变化。
- [design/](design/README.md)：设计说明：目标设计（要做成什么样）、决定记录、原型现在实际的规则和存档的旧资料。
- [proposals/](proposals/README.md)：提议和试玩意见。有新想法或意见，就在这里加一个文件。
- [decisions/](decisions/README.md)：项目上的重要决定（平台、分支等），记录选了什么、为什么这样选。
- [guides/](guides/README.md)：开发指南：代码结构、Godot 入门和编辑器设置、开发者调试模式、让 AI 助手操作 Godot。
- `images/`：仓库首页 README 用的动图（用 `game/tools/make_readme_gifs.py` 重录）。提议里的草图放在 `proposals/images/`。

代码目录里也有一份说明：[game/balance_presets/README.md](../game/balance_presets/README.md)（共享的数值方案）。

## 一个想法从提出到实现

1. 有意见或新想法，在 [proposals/](proposals/README.md) 加一个文件：随手写的意见，或者列出选项的提议。
   我们要问的问题加到 [open-questions.md](open-questions.md)。
2. 在问题下面填「决定」。整理意见和提议时还有对不上的，也挪到 open-questions.md 去问。
3. 定下来的每一条都有编号（问题编号，或试玩意见的 Fk.n），在 [决定记录](design/decision-log.md)
   加一行，写进 [design/game-design.md](design/game-design.md) 的正文并标上编号；
   讨论过程留在提议里，或挪到 [design/archive/](design/archive/README.md) 存档。
   平台、分支这类项目上的决定，另记一条 [decisions/](decisions/README.md)。
4. 实现以后，更新 [design/current-rules.md](design/current-rules.md)、[status.md](status.md)、
   [devlog/](devlog/README.md) 和 [roadmap.md](roadmap.md)。

这样任何一条规则都能往回查：正文的编号 → 决定记录里那一行 → 原话和讨论过程。
新的一批决定不属于已有的来源时，用一个新字母，并在决定记录「编号从哪里来」加一行写清来源。

## 本地文档

`docs/local/` 是每个人自己的私人目录，不进本仓库（已写进 `.gitignore`）。
可以在里面放个人开发记录、草稿和调试笔记。

共享文档里不要链接 `docs/local/` 下的文件，否则别人那边会是坏链接。
