# 项目说明

## 代码

- 旧 Python 版只在 `archive/python` 分支上，已归档，不再改动，也不合并回 `master`。
- `game/`：Godot 4.7 项目（GDScript），正在做原型。
  - `game/rules/`：规则代码，继承 `RefCounted`，不依赖任何画面节点。
  - `game/view/`：画面代码，只读取规则数据。
  - `game/tests/run_tests.gd`：规则测试，每个 `test_` 开头的函数是一个测试。
- 常用命令（Godot 4.7.2 用 winget 安装；终端里用 `godot_console`，它会等程序跑完并显示输出；`godot` 是窗口版）：
  - 第一次或新增 `class_name` 后，先生成缓存：`godot_console --headless --path game --import`
  - 跑测试：`godot_console --headless --path game --script res://tests/run_tests.gd`
  - 平衡模拟（5 个文明全由 AI 控制，打 50 局，看对局发展）：`godot_console --headless --path game --script res://tools/simulate.gd`，
    在 `--` 后面可以临时覆盖 `balance.gd` 的数值，例如 `-- COST_PROBE=8 RUNS=100`
  - 运行游戏：`godot --path game`
  - 打开编辑器：`godot --path game --editor`
- Godot 生成的 `*.uid` 文件要提交；`game/.godot/` 是缓存，不提交。
- 测试运行器：一个测试一次检查都没跑到也算失败（脚本编译出错时会这样），所以「0 个失败」才可信。
- 规则代码要点：
  - 数值都是 `Balance`（`balance.gd`）里的 `static var`，模拟时可以临时覆盖。
  - 二向箔展开后存在 `GameState.foil_zones`（中心 + 展开了几回合），`flattened` 记每个被压的格子
    和它的平面高度；形状由 `zone_covers()` 和 `FOIL_SQUISH` 决定，画面也用同一套函数。
  - 画面里的方向用 `view/angle_dial.gd`（水平角、俯仰角两个圆盘），目标 = 发射源 + 方向 × 距离。
- 截图检查画面：临时写一个 `game/tests/_shot.gd`（`extends SceneTree`，加载 `res://view/main.tscn`，
  等几帧后存图），用非 headless 的 `godot_console` 跑，窗口放到屏幕外
  （`--position -5000,-5000 --resolution 1600x900`）。脚本出错时窗口会卡住，要加超时并结束进程。
  用完删掉 `_shot.gd` 和 `_shot.gd.uid`。

## 改规则时一起更新的文档

- `docs/design/current-rules.md`：原型现在实际的规则（包括 AI 的行动顺序），改了规则或数值要同步。
- `docs/open-questions.md`：进度、测试个数、平衡模拟结果和各问题的「现状」。
- `docs/roadmap.md`、`docs/devlog/YYYY-MM.md`：做完一项时更新。

## 文档

- 共享文档在 `docs/`，入口是 `docs/README.md`。
  - 路线图：`docs/roadmap.md`，现状和待讨论的问题：`docs/open-questions.md`
  - 开发日志：`docs/devlog/YYYY-MM.md`，只写对合作者有用的结果和变化。
  - 设计说明：`docs/design/`
  - 重要决定：`docs/decisions/NNNN-标题.md`
- `docs/local/` 是每个人的私人目录，已在 `.gitignore` 中忽略。
  共享文档不要链接到 `docs/local/` 下的文件。
- 新增文档时，同时更新所在目录的 `README.md` 索引。
