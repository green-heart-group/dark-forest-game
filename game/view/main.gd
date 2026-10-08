extends Node3D
## 画面的入口：开局、把各部分接起来、结束回合、重开、快捷键，每次规则状态变了以后统一刷新。
## 只读取 GameState，所有行动都通过 GameState 的方法完成。
## 各部分：星图 map_view.gd，右侧面板 side_panel.gd（「行动」页在 action_page.gd），
## 左侧叠加层 overlay.gd，窗口和界面大小 window_settings.gd，调试面板 debug_panel.gd。
## 它们都通过 main（这个节点）拿 state、viewed() 和别的部分。

const MapView := preload("res://view/map_view.gd")
const SidePanel := preload("res://view/side_panel.gd")
const Overlay := preload("res://view/overlay.gd")
const WindowSettings := preload("res://view/window_settings.gd")
const DebugPanel := preload("res://view/debug_panel.gd")
const Tip := preload("res://view/tip.gd")
const WebFiles := preload("res://view/web_files.gd")

## 游戏窗口的标题。项目名（project.godot 的 config/name）是 dark-forest，只用作存档文件夹的名字。
const WINDOW_TITLE := "黑暗森林 · Dark Forest"

var state: GameState
var map := MapView.new()
var panel := SidePanel.new()
var overlay := Overlay.new()
var window_settings := WindowSettings.new()
## 调试面板（调试版或带 debug 参数时才有，平时为 null）
var debug: DebugPanel = null
## 上帝视角开关：画出所有文明和星系。放在调试面板里，平时不显示。
var reveal := CheckBox.new()
## 面板、叠加层和调试面板的窗口都放在这一层
var _layer := CanvasLayer.new()
## 自动存对局记录的位置（空：不存，画面测试用）
var autosave_path := Replay.DIR.path_join("last.replay")


func _ready() -> void:
	get_window().title = WINDOW_TITLE
	var seed_value := randi() % 1000000
	# 命令行参数（写在 `--` 后面）：
	#   seed=123            指定种子，重现同一张星图
	#   debug               打开调试面板（调试版里也可以按 F12 打开）
	#   watch               开一局全由 AI 打的观战局（同时打开调试面板）
	#   replay=<文件>       打开对局记录，从开局开始回放（同时打开调试面板）
	# 网页版写在网址的 ? 后面，用 & 隔开，例如 index.html?debug&seed=123
	# 开发者版 exe（导出设置「Windows Desktop (dev)」带 dev 标记）不用加参数，等于带了 debug
	var args := OS.get_cmdline_user_args() + WebFiles.url_args()
	if OS.has_feature("dev"):
		args.append("debug")
	var replay_path := ""
	for arg in args:
		if arg.begins_with("seed="):
			seed_value = arg.trim_prefix("seed=").to_int()
		elif arg.begins_with("replay="):
			replay_path = arg.trim_prefix("replay=")
	state = GameState.new_game(seed_value)
	state.add_log(new_game_note(seed_value))
	add_child(map)
	map.setup(self)
	map.cell_clicked.connect(_on_map_click)
	get_tree().node_added.connect(_on_node_added)
	add_child(_layer)
	overlay.setup(self)
	_layer.add_child(overlay)
	panel.setup(self)
	_layer.add_child(panel)
	add_child(window_settings)
	window_settings.setup(self)
	if OS.is_debug_build() or args.has("debug") or args.has("watch") or replay_path != "":
		debug = DebugPanel.new()
		debug.setup(self, reveal)
		debug.visible = args.has("debug") or args.has("watch") or replay_path != "" or debug.was_open()
		debug.set_ui_scale(window_settings.effective_ui_scale())
		debug.window.window_input.connect(func(event): _on_key(event, debug.window))
		_layer.add_child(debug.window)
		debug.place_window()
	refresh()
	if args.has("watch"):
		debug.new_game(seed_value, true)
	elif replay_path != "":
		debug.load_replay(replay_path)
	elif debug != null and debug.default_preset() != "":
		debug.new_game(seed_value, false)  # 用调试面板里设的「新开一局时用的方案」


## 画面显示的是哪个文明看到的（平时是玩家，调试时可以换成任意文明）。
func viewed() -> Civ:
	return debug.viewed() if debug != null else state.human()


## 现在不能操作的原因（调试时在看别人的视角、在回放，或者交给 AI 代打了）。可以操作时为空。
func locked_reason() -> String:
	var reason := debug.locked_reason() if debug != null else ""
	if reason == "" and viewed().is_ai:
		reason = "%s 现在由 AI 控制（调试面板里可以接管）" % viewed().name
	return reason


## 被锁住时在面板上说明原因，返回 true。
func blocked() -> bool:
	var reason := locked_reason()
	if reason != "":
		panel.set_feedback(reason)
	return reason != ""


## 规则状态变了以后调用：刷新面板，重画星图上的标记，刷新叠加层。
func refresh() -> void:
	var me := viewed()
	panel.refresh(me)
	map.refresh(me, panel.actions.preview(), overlay.show_vision.button_pressed, reveal.button_pressed)
	overlay.refresh(me)
	if debug != null:
		debug.refresh_panel()


## 换一个局面（新开一局、回放跳到别的回合）：重画网格，不播放压平的动画。
func set_state(s: GameState) -> void:
	state = s
	panel.set_feedback("")
	panel.actions.reset()
	map.redraw_grid()
	refresh()


## 自动把这一局的记录存成 last.replay，出了问题可以把它发给别人重现。
func autosave() -> void:
	if autosave_path != "":
		Replay.from_state(state).save(autosave_path)


## 结束回合对所有文明都一样，在看别人的视角时也可以按（回放中不行）。对局结束后变成「再来一局」。
func end_turn() -> void:
	if debug != null and (debug.replaying() or debug.seeking):
		return
	if state.is_over():
		new_game(randi() % 1000000)
		return
	panel.set_feedback("")
	state.end_turn()
	if debug != null:
		debug.remember_turn(state)
	autosave()
	refresh()


## 开局时写进日志的第一行：种子，以及怎样重玩这张星图。
static func new_game_note(seed_value: int) -> String:
	var how := "网址后面加 ?seed=%d" if WebFiles.is_web() else "用 -- seed=%d"
	return ("新的一局，种子 %d（" + how + " 可以重玩这张星图）") % [seed_value, seed_value]


## 新开一局（seed_value 一样就是同一张星图）。观战局重开后还是观战局。
func new_game(seed_value: int) -> void:
	if debug != null:
		debug.new_game(seed_value, state.spectator)  # 调试面板还要换回数值、清掉回放
		return
	var s := GameState.new_game(seed_value)
	s.add_log(new_game_note(seed_value))
	set_state(s)
	autosave()


## 点了星图上的格子：两个角度转到「从起点指向这个格子」；要目标的行动，距离也填好。
func _on_map_click(c: Vector3i) -> void:
	if not state.is_over():
		panel.actions.aim_at(c)


## 压平的动画放完以后，如果胜负已分但空间还没压完，每帧再压一步（不再有回合和收入）。
func _process(delta: float) -> void:
	if map.animating():
		map.advance_animation(delta)
		return
	if state.is_over() and state.collapse_pending():
		state.advance_collapse()
		refresh()


func _input(event: InputEvent) -> void:
	_on_key(event, get_viewport())


## 快捷键。调试面板是单独的窗口，焦点在它上面时按键也转到这里（from 是收到按键的那个窗口）。
func _on_key(event: InputEvent, from: Viewport) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.ctrl_pressed and key.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT, KEY_0, KEY_KP_0]:
		var step := 0.0 if key.keycode in [KEY_0, KEY_KP_0] else (-0.1 if key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] else 0.1)
		window_settings.set_ui_scale(window_settings.default_ui_scale() if step == 0.0
				else window_settings.ui_scale + step)
		from.set_input_as_handled()
		return
	if debug == null:
		return
	if key.keycode == KEY_F12:
		debug.visible = not debug.visible
		debug.refresh_panel()
		if not debug.visible:
			get_window().grab_focus()  # 收起后焦点回到游戏窗口，快捷键接着能用
		from.set_input_as_handled()
		return
	# 正在输入数字（坐标框、种子框、数值框）时不抢按键
	if from.gui_get_focus_owner() is LineEdit:
		return
	if debug.handle_key(key):
		from.set_input_as_handled()


## 界面里新加的控件：没有脚本的挂上 tip.gd，让它的悬停说明限宽换行。
## Godot 自己内部的子控件（下拉菜单、滚动条等）不动。
func _on_node_added(node: Node) -> void:
	if node is Control and node.get_script() == null and _layer.is_ancestor_of(node) \
			and node.get_parent().get_children().has(node):
		node.set_script.call_deferred(Tip)
