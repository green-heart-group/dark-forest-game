# 项目说明

## 代码

- `game/`：Godot 4.7 项目（GDScript），正在做原型。旧 Python 版只在 `archive/python` 分支上，已归档，
  不再改动，也不合并回 `master`。
- 改代码前先看 `docs/guides/code.md`：每个文件管什么，规则和画面怎么分工，改代码要守的规矩
  （数值、花费和不能做的原因只写一次、对局记录、界面缩放、截图检查画面等）。
- 运行、测试、平衡模拟的命令见根目录 `README.md`「快速开始」和「测试和平衡模拟」。
  终端里用 `godot_console`（会等程序跑完并显示输出），不用 `godot`；新增 `class_name` 后先跑一次 `--import`。
  改完代码跑 `uv run game/tools/test.py`（规则测试和画面测试都跑），两种测试都输出「0 个失败」才算通过。
  写测试的规矩（每个测试标上测的是哪条规则等）见 `docs/guides/code.md`「写测试的规矩」。
- 分支用 GitHub Flow（`docs/decisions/0003-github-flow.md`）：不直接推 `master`，从 `master` 开新分支，通过 PR squash 合并。

## 改代码时一起更新的文档

- `docs/design/current-rules.md`：原型现在实际的规则（包括 AI 的行动顺序），改了规则或数值要同步。
- `docs/status.md`：进度、测试个数、平衡模拟结果。
- `docs/open-questions.md`：只放还没定的问题；里面写到的原型「现状」也要同步，具体数字只写在 `status.md`、这里链过去。
  答完一条，把结论写进 `docs/design/game-design.md` §14 决定记录，讨论过程挪到 `docs/design/archive/`，
  再从这里删掉，在文件末尾「已经答完的」表里记一笔。
- 定下的规则都要有编号（问题编号；第 k 次试玩意见的第 n 条是 `Fk.n`），在 game-design.md §14 有一行，
  正文用到的地方括号里标编号。正文只写最新的结论，改动的经过留在 §14 和原来的提议、意见文件里。
- `docs/guides/code.md`：文件的分工或写代码的规矩变了时更新。
- `docs/roadmap.md`、`docs/devlog/YYYY-MM.md`：做完一项时更新。

## 文档

- 共享文档在 `docs/`，入口是 `docs/README.md`（里面有「每样内容只写在一个地方」的对照表），
  各目录的用法见各自的 `README.md`。同一件事只写在一处，别处放链接。
- `docs/local/` 是每个人的私人目录，已在 `.gitignore` 中忽略。
  共享文档不要链接到 `docs/local/` 下的文件。
- 新增文档时，同时更新所在目录的 `README.md` 索引。
