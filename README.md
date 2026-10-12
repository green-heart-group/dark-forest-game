<div align="center">

# 黑暗森林 · Dark Forest

**以《三体》黑暗森林法则为背景的 3D 回合制策略游戏**

「宇宙就是一座黑暗森林，每个文明都是带枪的猎人。」

[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)](https://godotengine.org/)
[![GDScript](https://img.shields.io/badge/language-GDScript-355570)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/)
[![Status: prototype](https://img.shields.io/badge/status-prototype-orange)](docs/roadmap.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[**在浏览器里玩**](https://green-heart-group.github.io/dark-forest-game/) ·
[下载桌面版](https://github.com/green-heart-group/dark-forest-game/releases) ·
[完整规则](docs/design/current-rules.md)

<table>
  <tr>
    <td align="center" width="50%">
      <img src="https://github.com/user-attachments/assets/bc278161-e36d-429d-9cbd-3c326392e903" alt="三维星图：自己的视野和探测器" width="100%"><br>
      <b>藏在三维星图里</b><br>
      只看得到自己周围一小片，探测器飞出去看，情报按光速传回
    </td>
    <td align="center" width="50%">
      <img src="https://github.com/user-attachments/assets/d19784f3-cef3-4a9e-9a4d-e9007e2234a2" alt="黑域在母星系周围扩散" width="100%"><br>
      <b>黑域</b><br>
      有限范围的光速抑制；舰船与信息受影响，场到期后恢复
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="https://github.com/user-attachments/assets/407011eb-fd03-4d1f-b756-638c955fb8dc" alt="二向箔把三维星图压成平面" width="100%"><br>
      <b>二向箔</b><br>
      展开以后一圈圈扩散，把整张星图压成一个平面
    </td>
    <td align="center" width="50%">
      <img src="https://github.com/user-attachments/assets/0a2ad7a6-ef57-4820-bb71-1184aba50eeb" alt="平面压成直线，最后缩成一个点" width="100%"><br>
      <b>降到零维</b><br>
      单向著把平面压成直线，奇异点按传播前沿终止空间，胜负依据剩余生存锚点
    </td>
  </tr>
</table>

</div>

## 简介

在一个 9×9×9 的星图里，你和 4 个 AI 文明各自藏好自己的位置。谁先暴露，谁就可能被消灭。

玩法有点像「海战棋」：你看不见对手，只能派探测器出去看，看到的消息按光速慢慢传回来。
星图外面还藏着 15 个看不见的「隐藏文明」，你可以广播别人的坐标，让它们替你动手。

> [!NOTE]
> 项目还在原型阶段，画面只用方块和线条，规则和数值都在边玩边调。

## 玩法亮点

- 🔭 **视野和光速情报**：星系和舰船只看得到周围一小片。探测器边飞边看，看到的情报按光速传回，越旧越不可靠。
- 🔬 **科技树**：实际收到的发现、接触、侦察战报与净经常产能共同决定等级权限。
- ✨ **多种打击手段**：光粒一击毁掉整个星系，但要飞好几个回合；战舰守住附近、清除殖民船；
  二向箔把整张星图压成平面，单向著再把平面压成直线；奇异点也按实际空间传播与存续结算。
- 🕳️ **防守和躲藏**：黑域让一片空间的光速变慢，光粒在里面没有杀伤力，但舰船、情报也跟着变慢，困久了会出不来。
  预警系统报告来袭，反物质拦战舰，掩体挡光粒，实体收到准备资格后可在前沿到达时迁维。
- 📢 **借刀杀人**：广播别人的坐标，可能引来隐藏文明的打击，自己却不暴露。
- 🛸 **星舰文明**：星系全丢了，只要还有星舰就能活下去，通过付费运输与落地工程恢复殖民。
- ⭐ **恒星和行星**：裂变、聚变、戴森球与真实采矿提供收入，固定维护制约扩张；每年固定行动点，母星可并行施工，具体容量见[建造规则](docs/design/current-rules.md#建造)。

完整规则见 [原型现在的规则](docs/design/current-rules.md)。

## 快速开始

### 直接玩（不需要安装 Godot）

[网页版](https://green-heart-group.github.io/dark-forest-game/)可以直接打开。桌面试玩包见 [Releases](https://github.com/green-heart-group/dark-forest-game/releases) 的 **Assets**；也要看标记 **Pre-release** 的版本，GitHub 的 Latest 不一定是最新试玩包。

| 电脑 | 下载试玩版 v0.0.2-test |
| --- | --- |
| Mac，Apple Silicon（M 系列），macOS 13 或更新 | [dark-forest-macos-apple-silicon.zip](https://github.com/green-heart-group/dark-forest-game/releases/download/v0.0.2-test/dark-forest-macos-apple-silicon.zip) |
| Mac，Intel，macOS 11 或更新 | [dark-forest-macos-intel.zip](https://github.com/green-heart-group/dark-forest-game/releases/download/v0.0.2-test/dark-forest-macos-intel.zip) |
| Windows | [dark-forest-windows.zip](https://github.com/green-heart-group/dark-forest-game/releases/download/v0.0.2-test/dark-forest-windows.zip) |

Mac 在「 → 关于本机」看芯片，下载对应 ZIP，双击解压，把 `dark-forest.app` 拖到「应用程序」后打开。当前试玩包尚未经过 Apple 公证，首次打开可能被系统阻止；处理方法见 [Apple 的官方说明](https://support.apple.com/102445)，也可以先玩网页版。不要下载 Source code 或名字带 `-dev` 的包来代替普通游戏。

公开的 v0.0.2-test 不含当前源码新增的自动继续、原生 Mac 菜单和触控板改进；这些功能需要新版本发布。操作入门见下方 [操作](#操作)。

### 准备

以下适用于从源码运行或参与开发。

需要 [Godot 4.7.2](https://godotengine.org/download)（普通版，不是 .NET 版）。Windows 上可以用 winget 安装：

```bash
winget install --id GodotEngine.GodotEngine --exact --version 4.7.2
```

运行测试和导出工具还需要 uv，安装方法见 [uv 官方安装指南](https://docs.astral.sh/uv/getting-started/installation/)。
`game/tools/` 里的 Python 脚本都用 `uv run` 跑，它会自动准备 Python 3.12 和依赖；直接用 `python` 跑时，脚本会提示改用 uv。

### 运行

在仓库根目录：

```bash
# 第一次运行前生成缓存
godot_console --headless --path game --import

# 开始游戏
godot --path game

# 打开编辑器
godot --path game --editor
```

> `godot` 是窗口版；`godot_console` 是命令行版，会等程序跑完并显示输出，适合跑测试。

### 操作

- 左键拖动旋转，滚轮缩放；单击星图选中目标，右侧面板分科技、建造、行动、情况四页，最后按「结束回合」。
  研究、建造、派出单位、发射武器各花 1 个行动点；研究和建造还须完成工时。鼠标停在按钮上能看到说明。
- 看星图、存档读档、快捷键、界面大小见 [操作说明](docs/guides/controls.md)。
- 按 F12 打开开发者调试面板，`godot --path game -- watch seed=123` 开一局全由 AI 打的观战局，详见 [调试模式](docs/guides/debug-tools.md)。

## 开发

### 目录结构

```text
game/
├── balance.cfg  所有数值（调数值只改这个文件）
├── rules/    规则代码：不依赖任何画面节点
├── view/     画面代码：只读取规则数据
├── tests/    规则测试（rules/ 里按规则分文件）和画面测试
├── tools/    跑测试、导出打包、变异测试、平衡模拟、更新文档里的数字、做网页字体、录 README 的动图
└── balance_presets/  共享的数值方案（和 balance.cfg 不一样的一组数值）
docs/         设计、要确定的问题、现状、路线图、开发日志、提议和重要决定（入口 docs/README.md）
```

每个文件管什么、改代码要守的规矩见 [代码结构](docs/guides/code.md)。
改动都从新分支通过 PR 合并进 `master`，见 [分支和合并](docs/decisions/0003-github-flow.md)。

### 测试和平衡模拟

```bash
# 跑全部测试：先导入，再同时开几个进程跑规则测试和画面测试（GitHub 上跑的也是这一条）
uv run game/tools/test.py

# 只跑规则测试里名字带 ai 的（rules 换成 view 就是画面测试；--no-import 跳过导入；--jobs 1 只用一个进程）
uv run game/tools/test.py rules --only ai

# 也可以直接用 Godot 跑某一种测试，最后加 -- only=词 只跑名字里带这个词的
godot_console --headless --path game --script res://tests/run_tests.gd
godot_console --headless --path game --script res://tests/run_view_tests.gd

# 变异测试：给 game/rules/ 里的文件故意造小错，看测试能不能发现，列出没发现的（很慢，只在本地跑）
# 文件名换成 all 是全部文件；加 --view 时规则测试没发现的再跑画面测试；--out 文件 另存结果
uv run game/tools/mutate.py geometry.gd

# 平衡模拟：5 个文明全由 AI 控制，打 50 局（默认分给几个进程同时跑，JOBS=1 时只用一个）
godot_console --headless --path game --script res://tools/simulate.gd

# 找哪里慢：最后列出回合里每一步一共花了多少秒
godot_console --headless --path game --script res://tools/simulate.gd -- PROFILE=1 RUNS=10

# 临时覆盖 balance.cfg 里的数值（整数或小数；数组、字典要用数值方案）
godot_console --headless --path game --script res://tools/simulate.gd -- TIER3_ENERGY=40 RUNS=100

# 用一个数值方案（game/balance_presets/ 里的，或调试面板里存的自己的方案）
godot_console --headless --path game --script res://tools/simulate.gd -- PRESET=方案名
```

### 发布

推送 `v` 开头的标签（如 `v0.1.0`）后，GitHub 自动跑测试，导出 Windows、macOS 和网页版，挂到 [Releases](https://github.com/green-heart-group/dark-forest-game/releases) 并部署网页版。
本地导出要先在 Godot 里装好同版本导出模板。各版本的产物、Mac 签名和手动试导出见 [导出和发布](docs/guides/export.md)。

```bash
# 发布一个版本
git tag v0.1.0
git push origin v0.1.0

# 本地导出全部版本（也可以只导出 web、windows、windows-dev、macos 等，--help 查看）
uv run game/tools/export.py
```

## 文档

所有文档从 [docs/README.md](docs/README.md) 进。常看的几份：

- [原型现在的规则](docs/design/current-rules.md)：试玩时对照。
- [现状](docs/status.md)：做到哪一步、测试和平衡模拟结果。
- [路线图](docs/roadmap.md)：接下来要做什么。
- [要确定的问题](docs/open-questions.md)：还没定、要大家回答的问题。
- [决定记录](docs/design/decision-log.md)：每条规则是谁、什么时候、为什么定的。

## 旧版本

最早的 Python 版（Tkinter + Matplotlib）已归档在 [`archive/python`](https://github.com/green-heart-group/dark-forest-game/tree/archive/python) 分支，不再更新。

## 致谢

灵感来自刘慈欣的科幻小说《三体》。本项目是爱好者作品，与原著及其版权方无关。

## 许可证

[MIT](LICENSE)
