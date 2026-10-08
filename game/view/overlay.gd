extends Control
## 盖在星图左侧的一层：回合状态和「重开」、图例、视角操作、显示开关和网格画法（左上），日志（左下），
## 星图上方正中的短暂提示。这一层只有里面的按钮接鼠标，其余地方照样可以拖动、缩放星图。

const Widgets := preload("res://view/widgets.gd")
const MapView := preload("res://view/map_view.gd")

var main: Node
var state: GameState:
	get: return main.state

var _status := Label.new()
## 状态栏旁边的「重开」，随时可以按；对局中途会先弹 _restart_dialog 问一下
var _restart := Button.new()
var _restart_dialog := ConfirmationDialog.new()
var _legend := RichTextLabel.new()
## 显示自己的视野范围
var show_vision := CheckBox.new()
## 网格画法（F4.2），G 键也能切换
var _grid_pick := OptionButton.new()
var _log := RichTextLabel.new()
## 改界面大小后在星图上方短暂显示的提示
var _toast := Label.new()


func setup(p_main: Node) -> void:
	main = p_main
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_right = -Widgets.PANEL_WIDTH - 16
	top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var status_row := HBoxContainer.new()
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_theme_constant_override("separation", 12)
	_status.add_theme_font_size_override("font_size", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	_restart.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_restart.text = "🔄 重开"
	_restart.tooltip_text = "换新星图，或在同一张星图上重打。对局中途会先确认。"
	_restart.add_theme_font_size_override("font_size", 14)
	_restart.pressed.connect(_ask_restart)
	status_row.add_child(_restart)
	top.add_child(status_row)
	_restart_dialog.title = "重开一局"
	_restart_dialog.ok_button_text = "🗺️ 新的星图"
	_restart_dialog.cancel_button_text = "取消"
	_restart_dialog.add_button("🔁 同一张星图", false, "same")  # 放左边，「取消」留在最右
	_restart_dialog.confirmed.connect(func(): main.new_game(randi() % 1000000))
	_restart_dialog.custom_action.connect(func(_action):
		_restart_dialog.hide()
		main.new_game(state.seed_value))
	add_child(_restart_dialog)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	_legend.add_theme_font_size_override("normal_font_size", 13)
	_legend.text = MapView.legend_text()
	var fold := Widgets.fold_title("🗺️ 图例", _legend)
	fold.add_theme_font_size_override("font_size", 13)
	top.add_child(fold)
	top.add_child(_legend)
	# 视角操作说明，平时收起
	var controls := Label.new()
	controls.text = MapView.CONTROLS_TEXT
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_theme_font_size_override("font_size", 13)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.visible = false
	var controls_fold := Widgets.fold_title("⌨️ 视角操作", controls)
	controls_fold.add_theme_font_size_override("font_size", 13)
	controls_fold.focus_mode = Control.FOCUS_NONE
	top.add_child(controls_fold)
	top.add_child(controls)
	show_vision.text = "显示自己的视野"
	show_vision.button_pressed = true
	show_vision.add_theme_font_size_override("font_size", 13)
	show_vision.toggled.connect(func(_on): main.refresh())
	top.add_child(show_vision)
	var grid_row := HBoxContainer.new()
	grid_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid_label := Label.new()
	grid_label.text = "网格"
	grid_label.add_theme_font_size_override("font_size", 13)
	grid_row.add_child(grid_label)
	for mode in MapView.GRID_NAMES:
		_grid_pick.add_item(MapView.GRID_NAMES[mode], mode)
	_grid_pick.add_theme_font_size_override("font_size", 13)
	_grid_pick.tooltip_text = "星图上的网格怎么画。视野里的线和点更亮。按 G 切换。"
	_grid_pick.focus_mode = Control.FOCUS_NONE  # 不抢键盘焦点，WASD 照样移动视角
	_grid_pick.item_selected.connect(func(i): main.map.set_grid_mode(_grid_pick.get_item_id(i)))
	grid_row.add_child(_grid_pick)
	top.add_child(grid_row)
	sync_grid_mode()

	var log_panel := PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 16
	log_panel.offset_right = 16 + 460
	log_panel.offset_top = -170
	log_panel.offset_bottom = -16
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_content_margin_all(10)
	bg.set_corner_radius_all(6)
	log_panel.add_theme_stylebox_override("panel", bg)
	add_child(log_panel)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	log_panel.add_child(_log)

	# 星图区域上方正中的短暂提示（界面大小、网格画法）
	_toast.anchor_left = 0.0
	_toast.anchor_right = 1.0
	_toast.offset_right = -Widgets.PANEL_WIDTH
	_toast.offset_top = 56
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


## 网格菜单跟着星图现在的画法（按 G 换了以后也要对上）。
func sync_grid_mode() -> void:
	_grid_pick.select(_grid_pick.get_item_index(main.map.grid_mode))


## 在星图上方正中显示一句话，一会儿后淡出。
func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


## 刷新状态栏和日志。me：正在看的文明。
func refresh(me: Civ) -> void:
	var alive_ai := state.civs.filter(func(c): return c.is_ai and c.alive).size()
	_status.text = "第 %d 回合　剩 %d 个 AI 文明" % [state.turn, alive_ai]
	if state.winner == "无":
		_status.text = "所有文明都灭亡了（第 %d 回合）" % state.turn
	elif state.winner == "平局":
		_status.text = "🤝 平局：整张星图已压成一条直线（第 %d 回合）" % state.turn
	elif state.winner != "" and state.winner_by_name():
		_status.text = "🏆 %s 胜利（第 %d 回合）" % [state.winner, state.turn]
	elif state.winner == "你":
		_status.text = "🏆 你胜利了！（第 %d 回合）" % state.turn
	elif state.winner != "":
		_status.text = "💀 你失败了（第 %d 回合）" % state.turn
	if not state.is_over() and state.all_flat():
		_status.text += "　729 格一维空间" if state.all_linear() else "　27×27 二维空间 · 重新探索"
	if not state.is_over() and state.collapse_pending():
		_status.text += "\n空间展开中 · 回合按当前坐标结算"
	if state.is_over() and state.collapse_pending():
		_status.text = "空间坍缩继续中…（战斗行动已停止）"
	if not state.is_over() and not state.spectator and not state.human().alive:
		_status.text += "　💀 你已灭亡"
	if me != state.human():
		_status.text += "　👁 %s 的视角" % me.name
	if state.dev_used:
		_status.text += "　🛠 改过数值"

	_log.clear()
	_log.get_parent().visible = not state.log_lines.is_empty()
	for line in state.log_lines.slice(-8):
		_log.append_text(line + "\n")


## 「重开」：对局已经结束就直接给两个选择；打到一半先说清楚这一局会丢掉。
func _ask_restart() -> void:
	_restart_dialog.dialog_text = "新开一局，还是在同一张星图（种子 %d）上从头再打？" % state.seed_value
	if not state.is_over():
		_restart_dialog.dialog_text += "\n\n这一局还没打完，重开后就回不来了。"
	_restart_dialog.popup_centered()
