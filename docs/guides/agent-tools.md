# 让 AI 助手操作 Godot

2026-10-03 调查的结果。AI 助手指 Claude Code 这类能自己运行命令、改代码的工具，下面简称 agent。
这一页只讲 agent 能用哪些办法操作 Godot；运行和测试命令见仓库根目录的 [README](../../README.md)，调试面板见 [调试模式](debug-tools.md)。

Godot 官方没有 MCP，第三方做的很多（目录网站上有 30 多个）。
MCP（Model Context Protocol）是一种标准接口，让 agent 能直接操作外部程序，比如运行游戏、读报错、截图。

## 方法一：命令行（主力）

agent 最擅长运行命令、读输出。测试、平衡模拟的命令见仓库根目录的 [README](../../README.md#测试和平衡模拟)，
导出见 [Godot 入门](godot.md#导出和分发)。另外一个有用的：只检查一个脚本有没有写错，不运行它：

```bash
godot_console --headless --path game --check-only --script res://rules/civ.gd
```

- `--headless` 表示不开窗口在后台运行。要用 `godot_console`，不要用 `godot`：`godot` 是窗口程序，
  在终端里直接运行时可能不等它跑完就返回，也看不到输出。
- 规则代码不依赖画面，所以规则的改动 agent 都能自己跑测试验证。
- 命令行做不到的是**看画面**。不装 MCP 的办法：写一个小脚本把画面存成 PNG，让 agent 读图片，
  做法见 [代码结构：截图检查画面](code.md#截图检查画面)。

## 方法二：第三方 MCP（补上「看画面」）

| 名称 | 能做什么 | 费用 | 要装编辑器插件 |
| --- | --- | --- | --- |
| [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) | 启动编辑器、运行游戏、读报错、改场景。约 5900 星，用 `npx` 启动（要 Node.js） | 免费 | 不要 |
| [hi-godot/godot-ai](https://github.com/hi-godot/godot-ai) | 见下 | 免费 | 要 |
| GDAI MCP | 功能完整，直接操作编辑器 | 一次性 19 美元 | 要 |
| [slangwald/godot-mcp](https://github.com/slangwald/godot-mcp) 等 | 运行中截图、模拟点击、看运行时的节点树 | 免费 | 要 |

这些都是个人维护的项目，能在你的电脑上执行任意代码。装之前看看代码和维护情况。

### hi-godot/godot-ai

目前看起来最合适的一个。

- 名字像官方，但**和 Godot 官方无关**。主要靠一位作者（dsarno）维护。
- 2026 年 4 月创建，约 2800 星，MIT 许可证，免费，不用注册。更新很勤（v4.2.3 发布于 2026-09-24）。
- 要求 Godot 4.7 以上，和我们的 4.7.2 匹配。
- 有用的工具：`project_run`（运行游戏）、`logs_read`（读编辑器和游戏的报错、`print` 输出）、
  `editor_screenshot`（截编辑器的 3D 视图，或运行中的游戏画面），还有节点、信号、界面、材质、动画等操作。
- 结构：agent ⇄ Python 服务（用 uv 运行）⇄ Godot 编辑器里的插件。
- 代价：
  - **编辑器必须开着**。
  - 插件要放在 `game/addons/godot_ai/`。不是每个人都用的话，加进 `.gitignore` 只在本地用。
  - 默认发送使用统计（安装编号、用了哪个工具、成败、耗时），不发代码和场景内容。
    设置环境变量 `GODOT_AI_DISABLE_TELEMETRY=true` 可以关掉。
  - 项目才半年，以后可能有不兼容的改动。
- 装法：从它的 Releases 页面下载插件放进 `game/addons/`，在「项目 → 项目设置 → 插件」里启用，
  然后在它的面板里点 Claude Code 旁边的 Configure，按生成的命令注册。

## 结论

- 原型阶段只用命令行就够了：重点是规则和数值，测试和模拟都在命令行里。
- 开始认真调画面时，再考虑装 godot-ai（只在本地、加进 `.gitignore`、关掉统计）。
