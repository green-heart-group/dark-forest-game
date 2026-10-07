# Godot 入门

给第一次用 Godot 的人。安装、运行和测试命令见仓库根目录的 [README](../../README.md)，这里不重复。
为什么选 Godot 见 [decisions/0001-platform.md](../decisions/0001-platform.md)。

## Godot 是什么

- 免费、开源的游戏引擎，MIT 许可证，做出的游戏怎么卖都不用给引擎方分钱。
  游戏引擎就是做游戏的现成工具箱：画面、输入、声音、打包发布都做好了，我们只写规则和内容。
- 「4」是 2023 年发布的第 4 代大版本。我们固定用 **4.7.2**。
- 脚本语言是 GDScript，写法接近 Python（用缩进分块，用 `func` 定义函数）。
- 用 Godot 做的知名游戏：Slay the Spire 2、Buckshot Roulette（Godot 4）；Brotato、Dome Keeper（Godot 3）。

## 安装时要注意

- 官方只提供 zip 免安装版，没有安装程序。README 里的 winget 命令装的就是这个 zip，
  并且会建好 `godot` 和 `godot_console` 两个命令。
- **大家必须用同一个版本**。版本不同时，编辑器可能改写文件格式，两边互相冲突。
  所以不要用 Steam 或 itch.io 版（会自动更新），也不要随手 `winget upgrade`，升级先商量。
- 选普通版，不要 .NET 版（那是给 C# 用的，我们不用）。
- winget 版不建开始菜单快捷方式，也不关联 `.godot` 文件。想双击打开项目，
  右键 `game/project.godot`，选「打开方式」，找到 Godot 程序并勾选「始终使用此应用」。

## 基本概念

- **节点（Node）**：最小的积木，每种节点做一件事。例如 `Node3D` 是 3D 空间里的一个位置，
  `MeshInstance3D` 显示一个形状，`Camera3D` 是摄像机，`Button` 是按钮。
- **场景（Scene，`.tscn` 文件）**：一棵节点树存成的文件，可以重复使用。
- **脚本（`.gd` 文件）**：挂在节点上，决定节点的行为。常用的几个函数：
  - `_ready()`：节点进入场景时运行一次，做初始化。
  - `_process(delta)`：每一帧运行一次，`delta` 是离上一帧过了多少秒。
  - `_unhandled_input(event)`：有键盘、鼠标输入时运行。
- **信号（Signal）**：节点发出「某件事发生了」的通知，其他节点收到后做出反应。
  例如按钮被点击时发出 `pressed`。
- `res://` 指项目根目录，也就是 `game/`。`res://view/main.tscn` 就是 `game/view/main.tscn`。

## 项目文件和入口

- 项目文件是 `game/project.godot`。和 Blender 的 `.blend` 不同，Godot 的项目是**整个文件夹**，
  `project.godot` 只是标记根目录、保存项目设置（名字、窗口大小、字体等）的小文件。
- 游戏从哪里开始，由 `project.godot` 里的 `run/main_scene` 决定。我们的是 `res://view/main.tscn`，
  入口代码是挂在它上面的 `view/main.gd`，从 `_ready()` 开始执行。
  在编辑器里改：「项目 → 项目设置 → 应用 → 运行 → 主场景」。

## 编辑器

第一次打开：启动 Godot 后出现项目管理器，点「导入」，选 `game/project.godot`。

| 位置 | 名称 | 作用 |
| --- | --- | --- |
| 左上 | 场景 | 当前场景的节点树 |
| 左下 | 文件系统 | 项目里的文件 |
| 中间 | 视口 | 顶部切换 2D / 3D / 脚本 / 资源库 |
| 右侧 | 检查器 | 选中节点的属性，可以直接改 |
| 底部 | 输出 / 调试器 | `print()` 的内容和报错 |

- **F5** 运行整个游戏（从主场景开始），**F6** 只运行当前打开的场景，**F8** 停止。
- 出错时编辑器会跳到出错的那一行。
- 按住 `Ctrl` 点类名或函数名，会打开内置的说明文档。

建议的分工：改规则（`rules/`）时在 VS Code 里写、跑命令行测试，不用开编辑器；
调画面（`view/`）时开编辑器按 F5 看。编辑器会自动发现文件变化并重新加载。

## VS Code 设置

1. 安装插件 **godot-tools**（作者 geequlim）。
2. 用 VS Code **单独打开 `game/` 文件夹**写 GDScript。打开仓库根目录也能用，但会提示
   「The GDScript Language Server might not work correctly with other projects than the one opened in Godot.」，
   跳转到定义等功能可能不准。
3. 新建 `game/.vscode/settings.json`（已在 `.gitignore` 里，每人各建各的）：

   ```json
   {
       "godotTools.editorPath.godot4": "<你电脑上 Godot_v4.7.2-stable_win64.exe 的完整路径>",
       "godotTools.lsp.serverPort": 6005,
       "godotTools.lsp.headless": true
   }
   ```

   winget 装的 Godot 在
   `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\`。
   JSON 里路径的 `\` 要写成 `\\`。

4. 按 `Ctrl+Shift+P`，运行 **Developer: Reload Window**。

这几项设置的作用：

- 插件靠 Godot 的「语言服务器」提供补全、报错和跳转。语言服务器是 Godot 在后台提供的一个小服务。
- `serverPort: 6005`：Godot 4 的语言服务器端口。不设时插件可能去连 6008（Godot 3 的端口），会报
  「Couldn't connect to the GDScript language server at 127.0.0.1:6008」。
- `headless: true`：插件自己在后台启动一个不带窗口的 Godot，不用一直开着编辑器。

## 导出和分发

- 导出的原理：Godot 给每个平台准备了现成的「空壳程序」，叫**导出模板**。
  导出时把场景、代码和图片打包，和空壳拼在一起，就成了游戏。
- 第一次导出前要下载导出模板：编辑器菜单「编辑器 → 管理导出模板 → 下载并安装」，
  约 1 GB，版本必须和编辑器一样。
- 这个项目的导出设置在 `game/export_presets.cfg` 里（普通版 exe、开发者版 exe、网页版），
  在编辑器里用「项目 → 导出」，或者用命令行。本地导出和自动发布的命令见仓库首页 [README「发布」](../../README.md#发布)，
  导出设置要注意的地方见 [代码结构「导出」](code.md#导出)。
- exe 约 70 到 100 MB，大部分是引擎本身。对方电脑不用装 Godot。
- exe 没有数字签名，第一次运行时 Windows 会弹「Windows 已保护你的电脑」，
  点「更多信息 → 仍要运行」。签名证书每年要几百美元，自己人试玩没必要。
- 也能导出 Mac、Linux、安卓版，选别的平台即可。Mac 版要签名才好用，安卓版要另装安卓开发工具。

现在推送标签就会自动发到 GitHub 的 Releases 和网页上（见上面的 README）。以后想公开发布，还可以考虑：

- **itch.io**：独立游戏的发布网站，像「小号 Steam」：不用审核、不收上架费，价格自己定。
  可以上传网页版，页面设成「仅限有链接的人」或加密码。
- 正式上架 Steam 要交 100 美元，等游戏成型再说。

## 学习资料

- 官方文档（有中文）：docs.godotengine.org。先看 Getting Started 里的 Step by step（一两个小时），
  再做 Your first 3D game。
