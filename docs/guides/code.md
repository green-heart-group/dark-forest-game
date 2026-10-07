# 代码结构

给改代码的人（包括 AI 助手）看：每个文件管什么、改代码时要守哪些规矩。
安装、运行和测试命令见仓库根目录的 [README](../../README.md)；Godot 的基本概念（节点、场景、信号）见 [Godot 入门](godot.md)。

代码都在 `game/`（Godot 4.7 项目，GDScript）。最重要的一条：**规则和画面分开**。
规则代码不知道画面存在，所以能不开窗口跑测试和平衡模拟；画面只读规则数据，要改局面就调用规则的函数。

## 规则代码（`game/rules/`）

都继承 `RefCounted`（不挂在场景里的普通对象），不依赖任何画面节点。每个文件开头有一段说明。

| 文件 | 管什么 |
| --- | --- |
| `game_state.gd` | 一局的全部状态和所有规则：行动、回合结算、交战、广播、降维、胜负 |
| `civ.gd` | 一个文明：星系、单位、科技，以及它知道的别人的事 |
| `ship.gd` | 会动的单位（探测器、战舰、殖民船、星舰、吞噬者、智子、飞行中的光粒）；战舰带的武器和受的伤 |
| `foil.gd` | 飞行中的二向箔、单向著 |
| `star_map.gd` | 星图生成 |
| `tech.gd` | 科技树：编号、名字、等级、前置 |
| `geometry.gd` | 沿方向飞行、视野圆锥用到的几何计算 |
| `ai.gd` | AI 每回合怎么行动（顺序见 [原型现在的规则 §11](../design/current-rules.md#11-ai-怎么行动)） |
| `balance.gd` | 所有数值 |
| `balance_presets.gd` | 数值方案：存、读、写回 `balance.gd`；生成数值目录 |
| `balance_index.gd` | 数值目录（自动生成，不要手改）：有哪些数值、每个的说明、`balance.gd` 里写的值 |
| `replay.gd` | 对局记录 |

要守的规矩：

- **数值**都是 `Balance`（`balance.gd`）里的 `static var`，平衡模拟和调试面板可以临时改。
  调试面板的「写回 balance.gd」会改这个文件，它认的格式是：每行一个 `static var 名字 := 值  # 注释`，
  多行的字典以单独一行的 `}` 结尾。改这个文件时别破坏这个样子。
  每个数值的说明取自同一行后面的注释；没有的话，取上面那段注释（连着几行合成一段），
  这段注释算作下面连着的一组数值共同的说明，直到空行为止。所以只适合组里某一个数值的说明，要写在那一行后面。
  数值方案只存和 `balance.gd` 不一样的值。
  Godot 在运行时列不出 `static var`，所以对局记录、调试面板的数值页、数值方案都从**数值目录** `balance_index.gd` 里取名字、说明和原来的值，
  运行时不读 `balance.gd` 的原文。**加、删数值，改注释或值以后**，运行
  `godot_console --headless --path game --script res://tools/make_balance_index.gd` 重新生成目录（调试面板写回时会自动生成）；
  忘了的话规则测试会失败，GitHub 发布前也跑规则测试，所以过时的目录发布不出去。
- **行动要花多少、为什么不能做，只写一次**，写在 `GameState` 里：
  - 花费：`action_cost(规则函数名)`、`dispatch_cost(单位)`、`upgrade_cost(种类)`；
  - 不能做的原因：每个行动一个 `xxx_error()`，能做时返回空字符串。行动函数自己先调用它，画面也调用它来显示按钮能不能按、为什么。
  - 目标还没选时传 `GameState.ANY_TARGET`，只检查和目标无关的条件（钱、行动点、科技）。
  - AI 也用这些函数。`ai.gd` 会比较「能量不足」「矿石不足」这两句原话，改 `research_error` 的提示时要一起改。
- **对局记录**靠「同样的种子 + 同样的玩家操作 = 同样的对局」，规则代码要守的几条
  （随机数只用 `GameState.rng`、操作成功时 `_record()` 等）见 [调试模式：写规则代码时要注意](debug-tools.md#写规则代码时要注意)。
- **提速**不能改变规则的结果。先用平衡模拟的 `PROFILE=1` 找出慢在哪；改完以后，同样的 `RUNS` 跑出来的统计和最后一行「所有对局的校验值」都要和改之前一模一样。
  现在有的几处捷径：回合末所有文明看一遍之前，`_begin_view_cache()` 先把这段时间里不会变的东西算好
  （星系格子按位置分好、光速几乎为 0 的格子、星系快照），看完就清空；光走的时间不会比直线距离短，所以直线距离已经太远的不细算（`_light_within`）；
  `Geometry._along` 只扫线段附近的小方盒。`test_speedups_match_plain_checks` 检查这些捷径和直接算的结果一样。
- **二向箔**展开后存在 `GameState.foil_zones`（中心 + 展开了几回合），`flattened` 记每个被压的格子和它的平面高度；
  压成什么形状由 `zone_covers()` 和 `Balance.FOIL_SQUISH` 决定，画面画压平的区域也用同一套函数。

## 画面代码（`game/view/`）

入口是 `main.tscn`，上面挂着 `main.gd`。

| 文件 | 管什么 |
| --- | --- |
| `main.gd` | 把下面几部分接起来：开局、刷新、结束回合、重开、快捷键 |
| `map_view.gd` | 3D 星图：相机和视角快捷键、网格（几种画法）、压平和降到零维的动画、坐标轴、所有标记和航线；单击选中画出来的东西（`select_object`，贴着轮廓画黄圈，看不到的选不中），点了格子发出 `cell_clicked`。半透明颜色都经过 `_shown()`，网页版里才不会变淡 |
| `side_panel.gd` | 右侧面板：资源、发射源、科技 / 建造 / 行动 / 情况四页、结束回合 |
| `action_page.gd` | 右侧面板的「行动」页：选行动、给方向或目标、执行 |
| `angle_dial.gd` | 「行动」页上调方向的两个圆盘（水平角、俯仰角）。目标 = 发射源 + 方向 × 距离 |
| `overlay.gd` | 盖在星图左边的一层：回合状态、重开、图例、视角操作说明、网格画法、日志、短暂提示 |
| `window_settings.gd` | 窗口位置和大小、界面大小，存在 `user://settings.cfg`；网页版改用随游戏带的字体 |
| `debug_panel.gd` | 开发者调试面板（用法见 [调试模式](debug-tools.md)） |
| `web_files.gd` | 网页版专用：读网址里的参数（`?debug&seed=123`），把文件下载到电脑、让玩家上传文件 |
| `widgets.gd` | 面板和叠加层共用的小控件（标题、方块按钮、表格等） |
| `tip.gd` | 鼠标悬停说明，限宽换行 |

各部分都通过 `main` 拿 `state`（当前的 `GameState`）和别的部分，例如 `main.panel`、`main.overlay`。
规则状态变了以后调用 `main.refresh()`，它按顺序刷新面板、星图和叠加层。

要守的规矩：

- **画面不能直接改规则数据**，只能调用 `GameState` 的函数，不然对局记录重算不出来
  （调试改数值怎么走，见 [调试模式：写规则代码时要注意](debug-tools.md#写规则代码时要注意)）。
- **能不能做、要花多少，问规则**（上一节的 `xxx_error()`、`action_cost()`），不在画面里另写判断。
- **按「正在看的文明」画**：用 `main.viewed()`，不要写死 `state.human()`。调试时可以换成别的文明的视角，
  以后多人对战也靠它。
- **调试面板**放在一个单独的系统窗口里（`window`，`force_native`）。焦点在那个窗口上时，按键交给 `main.gd` 的 `_on_key` 处理。
- **快捷键**：Ctrl 组合键和调试面板的键（空格、左右方向键、Home、End、数字键）在 `main.gd` 的 `_on_key`；
  视角键在 `map_view.gd`（按住的 WASD 等每帧查，H、V、T、G 在 `_camera_key`）。新加快捷键前先看这两处，别撞键；
  认键的位置（`physical_keycode`），在输入框里打字时不响应。
- **界面大小**：按 1280×800 等比缩放（项目设置 `canvas_items` + `expand`），再乘上 `ui_scale`
  （Ctrl + 加号 / 减号，0.6～1.3）。`ui_scale` 不超过 1 时界面坐标至少有 1280×800，不用为更小的窗口另排版；
  玩家自己放大时（最大 1.3 倍，界面坐标约 985×615）面板要滚动才看得全。
  刚打开时界面是 1.1 倍（`UI_TARGET`），右侧面板只有约 727 高：「行动」页最高的情况（要选单位又要给目标，比如殖民）
  也要不滚动就看得到执行按钮。加东西前先看能不能放进悬停说明，或者和已有的一行并排；改完在网页版或截图里按 1280×800 看一眼。
- **方块按钮**（`Widgets.tile()`）的高度跟着里面的字走，不写死：网页版带的字体行高更大，写死会让字超出边框。
  会折行的长文字（比如科技页每级的开放条件）要开 `autowrap_mode`，不然会把右侧面板撑宽。画面测试检查这两条。
- **窗口位置**：存在 `user://settings.cfg`（Windows 上在 `%APPDATA%\Godot\app_userdata\dark-forest\`）。
  这几种情况不摆窗口、也不记窗口大小：不带窗口跑测试；在编辑器的「游戏」页里运行（`Engine.is_embedded_in_editor()`）；
  命令行给了 `--resolution`、全屏或最大化。只给 `--position` 不算，因为编辑器用单独的窗口运行游戏时总会带上它。
- **说明文字**：长说明放进 `tooltip_text`，面板上只留一行提示。没脚本的控件由 `main.gd` 自动挂上 `tip.gd`；
  自己有脚本的控件要写 `_make_custom_tooltip`，在里面调 `Tip.make()`。
- **盖在星图上的容器**设成 `MOUSE_FILTER_IGNORE`，免得挡住星图的拖动和滚轮。
- **网页版**：命令行参数在网页里写在网址后面，`main.gd` 把两者合在一起读。要用到电脑上的文件时，
  网页版走 `web_files.gd` 的下载和上传；会弹出选文件窗口的按钮要用 `make_pick_button()`，
  因为浏览器只在处理点击的那一刻才肯弹窗口。

## 导出

- 导出设置有三个：`Windows Desktop`（普通版 exe）、`Windows Desktop (dev)`（开发者版 exe）、`Web`。
  开发者版和普通版只差一个 `dev` 标记（导出设置的「自定义特性」），`main.gd` 看到它就打开调试面板，等于带了 `-- debug`。
  网页版只导出一份，开发者入口 `/dev/` 是发布时生成的一个小网页，转到 `?debug`。

- 导出设置（`game/export_presets.cfg`）里脚本按原文导出（`script_export_mode=0`）。运行时已经不读原文（见上面「数值」），
  改成编译成二进制也能用，但没必要改，免得这个文件来回变。
  这个文件按 Godot 4.7.2 编辑器自己写出的完整格式保存。编辑器只在打开「项目 → 导出」窗口以后才会重写它，
  写的是编辑器内存里的那一份，所以拉取前先关掉编辑器，不然它会把拉下来的新版本盖回旧的。
  编辑器把它改了（多半是版本不同），又不是有意改导出设置，就先放弃这些改动再拉取；不然每次拉取都要把它暂存再放回，远程一改这个文件就冲突。
  规则测试会检查 `game/` 里的文件有没有没处理的冲突标记。

## 测试和工具

| 文件 | 做什么 |
| --- | --- |
| `game/tools/test.py` | 一条命令跑全部测试：先导入，再跑规则测试和画面测试。本地和 GitHub 上跑的都是它 |
| `game/tests/run_tests.gd` | 规则测试的运行器：找出 `game/tests/rules/` 里每个 `test_*.gd`，跑里面每个 `test_` 开头的函数 |
| `game/tests/rules/test_*.gd` | 规则测试，按规则分组（星图、移动、科技、交战、黑域、降维、AI、回放……），一组一个文件 |
| `game/tests/rules/rule_suite.gd` | 规则测试的共同底子：`check`、`check_eq`，和摆测试局面的小工具（`_two_civs`、`_ship` 等） |
| `game/tests/run_view_tests.gd` | 画面测试：检查界面和星图显示的东西和规则一致。按 `run_tests()` 里写的顺序跑 |
| `game/tests/test_log.gd` | 两种测试共用的记结果的部分：数测试和检查、失败时写出是哪个测试、`only=` 过滤、最后的汇总 |
| `game/tools/simulate.gd` | 平衡模拟：5 个文明全由 AI 控制，打很多局，统计对局怎么发展 |
| `game/tools/make_balance_index.gd` | 从 `balance.gd` 重新生成数值目录 `balance_index.gd`（见上面「数值」） |
| `game/tools/make_web_fonts.py` | 做网页版带的字体（网页里用不了电脑上装的字体）：只留游戏文字用到的字，存到 `game/view/web_fonts/`（不进仓库） |
| `game/tools/make_readme_gifs.py`、`record_gifs.gd` | 重新录 README 里的四段动图（`docs/images/*.gif`）：Godot 在屏幕外把每帧存成 PNG，ffmpeg 拼成 GIF。画面改了以后跑 `uv run game/tools/make_readme_gifs.py` |

- 一个测试一次检查都没跑到也算失败（脚本编译出错时会这样），所以只有输出「0 个失败」才可信。
- 新增 `class_name` 以后，要先跑一次 `godot_console --headless --path game --import`，让 Godot 认识这个新名字
  （`test.py` 每次都先导入）。
- 在终端里用 `godot_console`，不要用 `godot`（原因见 [让 AI 助手操作 Godot](agent-tools.md#方法一命令行主力)）。

### 写测试的规矩

- **改规则就改测试**：改了规则或数值，先改（或加）测试让它失败，再改代码让它通过。
- **修错误先写测试**：修一个错误之前，先写一个能把它重现出来的测试，修好以后它一直留着，免得同样的错误再出现。
- **能做和不能做都要测**：比如建造，既要测钱够时建得成，也要测钱不够、没科技、超过上限时建不成，而且不扣钱。
  边界值（刚好够、差一点、上限）最容易出错。
- **一个测试只测一件事**，名字写清楚测的是什么（`test_torpedo_needs_two_hits`）。检查的说明写「应该怎样」，失败时一看就懂。
  比较两个值时用 `check_eq(实际, 期望, 说明)`，失败时会写出两边的值。
- **结果每次都一样**：用固定的种子（`GameState.new_game(5)`、`StarMap.generate(42)`），不靠运气。
  测试里改了 `Balance` 的数值，测完要改回来（见 `_restore_balance`）。
- **测试局面自己摆**：用 `rule_suite.gd` 里的 `_two_civs`、`_set_star`、`_ship` 摆出只有要测的东西的小局面，比开一整局更快、更好懂。
  新的小工具只有一个文件用就写在那个文件里，几个文件都用再挪进 `rule_suite.gd`。
- **新文件**：在 `game/tests/rules/` 里新建 `test_xxx.gd`，第一行 `extends "res://tests/rules/rule_suite.gd"`，运行器会自动找到。
  画面测试的新函数要写进 `run_view_tests.gd` 的 `run_tests()` 列表，忘了写会算失败。
- **写上测的是哪条规则**：测试函数上面加一行 `## 规则：节标题，编号`（几项用「，」隔开）。
  节标题照抄 [原型现在的规则](../design/current-rules.md) 里最小一级的标题（去掉「3. 」这样的序号），编号是 T23、F3.5 这样的。
  `test_repo.gd` 的 `test_every_rule_has_a_test` 会检查：规则文档里每个最小的一节（「还没做的」除外）和正文里出现的每个编号，
  都至少有一个测试写到；测试上写的标题和编号在文档里都找得到。所以改了规则文档的标题、加了新的一节或新的编号，测试也要跟上。
  GDScript 还没有好用的工具统计「测试跑到了哪些代码行」，这个检查是用来代替它的：至少保证每条规则都有测试。
- **测试要快**：规则测试全部跑完十几秒。汇总下面会列出超过 1 秒的测试，变慢了想想能不能把局面摆小一点。

### 截图检查画面

命令行看不到画面。要检查画面时，临时写一个 `game/tests/_shot.gd`（`extends SceneTree`，加载 `res://view/main.tscn`，
等几帧后把画面存成 PNG），用不带 `--headless` 的 `godot_console` 运行，把窗口放到屏幕外：
`--position -5000,-5000 --resolution 1600x900`。脚本出错时窗口会卡住，要给命令设超时、到时结束进程。
用完删掉 `_shot.gd` 和 `_shot.gd.uid`。

## 提交

- Godot 给每个脚本生成的 `*.uid` 文件要提交（Godot 靠它找文件）。
- `game/.godot/` 是缓存，不提交。
