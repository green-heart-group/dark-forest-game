# 项目说明

给 AI 助手（Claude Code、Codex 等）和第一次来改代码的人看。`CLAUDE.md` 只引用这个文件，规矩都写在这里。

## 代码

- `game/`：Godot 4.7 项目（GDScript），正在做原型。旧 Python 版只在 `archive/python` 分支上，已归档，
  不再改动，也不合并回 `master`。
- 改代码前先看 `docs/guides/code.md`：每个文件管什么，规则和画面怎么分工，改代码要守的规矩
  （数值、花费和不能做的原因只写一次、对局记录、界面缩放、截图检查画面等）。
- 运行、测试、平衡模拟的命令见根目录 `README.md`「快速开始」和「测试和平衡模拟」。
  终端里用 `godot_console`（会等程序跑完并显示输出），不用 `godot`；新增 `class_name` 后先跑一次 `--import`。
  改完代码跑 `uv run game/tools/test.py`（规则、画面和展开演示测试都跑），每组都输出「0 个失败」才算通过。
  全部通过时它会更新几处文档（见下一节），这些改动要一起提交。
  写测试的规矩（每个测试标上测的是哪条规则等）见 `docs/guides/code.md`「写测试的规矩」。
- 分支用 GitHub Flow（`docs/decisions/0003-github-flow.md`）：不直接推 `master`，从 `master` 开新分支，通过 PR squash 合并。

## 改代码时一起更新的文档

**自动的，不用管**：`uv run game/tools/test.py` 会更新下面这些（文档要全部通过才更新），把它改的文件一起提交就行
（GitHub 上跑完测试，`docs/` 或 `balance.gd` 有变化就算失败）：

- `game/rules/balance.gd` 里的数值声明（每次跑测试前按 `game/balance.cfg` 生成，`game/tools/sync_balance.py`）。
- `docs/status.md` 的测试个数。
- `docs/design/current-rules.md` 里标了数值名的数字、§4 科技表（`game/tools/update_docs.py`）。
  新写一个来自 `balance.cfg` 的数字时，在后面加上标记 `<!-- 数值名 -->`（见 `docs/guides/code.md`「写测试的规矩」）。

**会被测试查出来的**：忘了会让规则测试失败（`game/tests/rules/test_docs.gd`），按提示改：

- 编号没在决定记录（`docs/design/decision-log.md`）「编号从哪里来」登记来源；答完的问题还留在 `docs/open-questions.md`。
- 新文件没写进所在目录的 `README.md`。
- 「现在的事实」里写了分支名、合没合并、本机路径、勾选清单，或者在 `status.md` 以外写了测试个数。

**要自己记得改的**（机器查不了，看的是意思）：

- 改了规则：`docs/design/current-rules.md` 的文字（包括 AI 的行动顺序）。规则来自一个新决定时，
  在决定记录加一行、给它编号（问题编号；第 k 次试玩意见的第 n 条是 `Fk.n`；新的一批决定用新字母），
  再写进 `docs/design/game-design.md` 正文，用到的地方括号里标编号。正文只写最新的结论，改动的经过留在决定记录和原来的提议、意见文件里。
- 答完 `docs/open-questions.md` 的一条：结论写进决定记录，讨论过程挪到 `docs/design/archive/`，再从问题清单里删掉，
  在文件末尾「已经答完的」表里记一笔。问题清单里写到的原型「现状」也要跟着改，具体数字只写在 `status.md`、这里链过去。
- 跑了平衡模拟：结果写进 `docs/status.md`。
- 文件的分工或写代码的规矩变了：`docs/guides/code.md`。
- 做完一项：`docs/roadmap.md`、当月的 `docs/devlog/YYYY-MM.md`。

## 文档

- 共享文档在 `docs/`，入口是 `docs/README.md`（里面有「每样内容只写在一个地方」的对照表），
  各目录的用法见各自的 `README.md`。同一件事只写在一处，别处放链接。
- 文档分两类（见 `docs/README.md`「现在的事实和历史记录」）：
  - **现在的事实**只写现在是什么样：不写在哪个分支上、合没合并、本机路径，不放勾选清单，测试个数只在 `status.md`。
  - **历史记录**（`devlog/`、`design/archive/`、`proposals/`、`decisions/`、决定记录）只往后加。
    做一项工作时的步骤、验证经过、交接说明，写进当月的 `devlog/`，不要另开一个文件。
- `docs/local/` 是每个人的私人目录，已在 `.gitignore` 中忽略。
  共享文档不要链接到 `docs/local/` 下的文件。
- 新增文档时，同时更新所在目录的 `README.md` 索引。
- 用普通人第一次读就懂的话写；避免难懂的术语，躲不开时在第一次出现的地方用一句话解释。
