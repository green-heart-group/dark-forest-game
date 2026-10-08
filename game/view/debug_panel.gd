extends PanelContainer
## 开发者调试面板（调试版里按 F12 打开或收起；发布版要在命令行加 debug 才有，网页版在网址后面加 ?debug）。
## 网页版碰不到电脑上的文件夹，存、打开文件改成下载和上传（web_files.gd）。
## - 视角：随时换成任意文明，看它知道什么、每回合做了什么、为什么这样做；
##   任何不由 AI 控制的文明都可以直接操作（以后有多个玩家时同样适用）。
## - 播放：暂停、播放、一回合一回合前进或后退、跳到任意回合。
##   往回退时从局面缓存里最近的一份按记录补算（规则里的随机数都来自同一个种子，所以结果一样）；
##   缓存里没有时从开局算，算得久时分段算、显示进度，可以按 Esc 取消。
## - 数值：随时改 balance.cfg 的数值和任意文明的属性、科技。改动记进对局记录，回放时同样重做。
## - 记录：存下、打开对局记录；新开一局（自己玩或全由 AI 打的观战局）。
## 面板的设置（开没开、上帝视角、播放速度、在哪一页）存在 user://debug.cfg，下次打开还是一样。

const WindowSettings := preload("res://view/window_settings.gd")
const WebFiles := preload("res://view/web_files.gd")

## 播放速度：每隔几秒前进一回合
const SPEEDS := [[1.0, "1 秒/回合"], [0.5, "0.5 秒/回合"], [0.2, "0.2 秒/回合"], [0.05, "最快"]]
## 行动记录里显示最近几回合
const LOG_TURNS := 4
## 面板设置存在哪里（测试时换成别的文件，不动玩家自己的设置）
static var prefs_path := "user://debug.cfg"
## 文明属性的中文名（没列出的直接显示属性名）
const CIV_FIELD_NAMES := {"energy": "能量", "mineral": "矿石", "actions_left": "剩余行动点", "telescope": "射电望远镜等级",
	"warning_level": "预警范围等级", "has_warning": "有预警系统", "antimatter": "反物质", "times_hit": "被打中次数",
	"discovered": "发现过别人", "tier1_turn": "I 级开放的回合", "tier2_turn": "II 级开放的回合", "tier3_turn": "III 级开放的回合",
	"reduce_left": "降维还剩几回合", "reduced": "已降到二维", "line_reduced": "已降到一维",
	"singularity_left": "奇异点还剩几回合"}

var main: Node
## 现在看的是第几个文明（GameState.civs 的序号）
var view_idx := 0
## 正在回放的记录。为 null 时是「实时」：局面就是正在打的这一局，可以接着操作。
## 不为 null 时，局面停在记录中间的某一回合，往前走按记录重做。
var replay: Replay = null
## 最近一次回放时发现结果和记录不一样的回合（-1：没有）
var desync_step := -1
## 往回跳用的局面缓存。实时打的时候每回合结束存一份（自动播放时每 Snapshots.EVERY 回合一份），重算的路上也存。
var snapshots := Snapshots.new()
## 正在跳转、还没算完（这时不能操作，见 locked_reason）
var seeking := false
## 跳转每算这么多毫秒停一下，让界面处理输入、显示进度（测试时设成 0，每算一回合停一下）
var seek_slice := 100
## 每次跳转的编号：取消或开始另一次跳转时加一，正在算的那次在下一次停下时发现编号变了就不再接着算
var _seek_id := 0
## 跳转开始前的数值、回放记录和它发现的不一样的回合，取消时换回来
var _before_seek := {}
var _note := ""
var _prefs := ConfigFile.new()
var _reveal: CheckBox

var _timer := Timer.new()
var _play := Button.new()
var _speed := OptionButton.new()
var _turn_label := Label.new()
var _slider := HSlider.new()
var _slider_busy := false
var _mode := Label.new()
var _resume := Button.new()
var _cancel := Button.new()
var _warn := Label.new()
var _view_pick := OptionButton.new()
var _autoplay := CheckBox.new()
var _play_on := CheckBox.new()
var _after_death := Button.new()
var _tabs := TabContainer.new()
var _table := GridContainer.new()
var _log := RichTextLabel.new()
var _show_notes := CheckBox.new()
## 数值页：每个 balance.cfg 数值一行
var _balance_rows: Dictionary[String, Dictionary] = {}
var _balance_filter := LineEdit.new()
## balance.cfg 文件里写的数值，「↺」和「恢复默认」恢复成这个
var _balance_defaults := {}
## 数值方案（见 rules/balance_presets.gd）
var _preset_pick := OptionButton.new()
var _preset_paths: Array[String] = []
var _preset_name := LineEdit.new()
var _preset_shared := CheckBox.new()
var _preset_default := CheckBox.new()
var _preset_delete := Button.new()
var _write_back := Button.new()
var _preset_dialog := FileDialog.new()
## 文明页
var _civ_title := Label.new()
var _civ_rows: Dictionary[String, Control] = {}
var _civ_grid := GridContainer.new()
var _tech_boxes: Dictionary[String, CheckBox] = {}
var _seed := SpinBox.new()
var _file_dialog := FileDialog.new()


func setup(p_main: Node, reveal: CheckBox) -> void:
	main = p_main
	_reveal = reveal
	_prefs.load(prefs_path)
	_setup_window()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.1)
	bg.set_content_margin_all(10)
	add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	box.add_child(_small("🐞 开发者调试（F12 收起）", Color(1.0, 0.75, 0.4)))
	box.add_child(_small("快捷键：空格 播放/暂停　← → 后退/前进　Home/End 开头/结尾　1～9 换视角",
			Color(0.6, 0.6, 0.7)))
	box.add_child(_build_playback())
	box.add_child(_build_view_row())
	_tabs.custom_minimum_size.y = 300
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL  # 窗口拉高时多出来的地方给分页
	box.add_child(_tabs)
	for page in [["📋 一览", _build_overview_page()], ["🔧 数值", _build_balance_page()],
			["🧬 文明", _build_civ_page()], ["💾 记录", _build_record_page()]]:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page[1])
		_tabs.add_child(scroll)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, page[0])
	_tabs.current_tab = clampi(_prefs.get_value("panel", "tab", 0), 0, _tabs.get_tab_count() - 1)
	_tabs.tab_changed.connect(func(i): _save_pref("tab", i); refresh_panel())

	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.replay ; 对局记录"])
	_file_dialog.size = Vector2i(800, 500)
	_file_dialog.file_selected.connect(load_replay)
	add_child(_file_dialog)

	var speed: int = clampi(_prefs.get_value("panel", "speed", 1), 0, SPEEDS.size() - 1)
	_speed.select(speed)
	_timer.wait_time = SPEEDS[speed][0]
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	reveal.set_pressed_no_signal(_prefs.get_value("panel", "reveal", false))
	visibility_changed.connect(_on_visibility_changed)


## 上次关掉游戏时面板开着没有。
func was_open() -> bool:
	return _prefs.get_value("panel", "open", false)


func _save_pref(key: String, value: Variant) -> void:
	_prefs.set_value("panel", key, value)
	_prefs.save(prefs_path)


# ---------- 独立窗口 ----------

## 面板放在一个独立的系统窗口里，可以拖到游戏窗口外面，不挡星图。
## 面板的 visible 还是「开着没有」，窗口跟着它显示或隐藏；点窗口的关闭按钮等于按 F12 收起。
## 窗口的位置和大小存在 debug.cfg，下次打开还在原处。
var window := Window.new()
## 窗口默认大小（界面坐标，乘上缩放才是屏幕像素）
const WINDOW_SIZE := Vector2(560, 820)
const WINDOW_MIN := Vector2(480, 560)


func _setup_window() -> void:
	window.title = "开发者调试（F12 收起）"
	window.visible = false  # 先藏起来才能改 force_native
	window.force_native = true  # 主窗口的弹框都画在里面，只有这个窗口单独出来
	window.close_requested.connect(func(): visible = false)
	window.add_child(self)


func _on_visibility_changed() -> void:
	_save_pref("open", visible)
	if not visible and window.visible:
		_save_window_rect()
	window.visible = visible


## 主窗口放进场景以后调用：放好窗口的位置，再按 visible 显示或隐藏。
func place_window() -> void:
	var rect: Rect2i = _prefs.get_value("panel", "window_rect", Rect2i())
	if not WindowSettings.title_bar_on_screen(rect):
		# 第一次打开（或者原来的屏幕拔掉了）：放在游戏窗口右边，放不下就叠在游戏窗口左上角
		var game := Rect2i(main.get_window().position, main.get_window().size)
		var screen := DisplayServer.screen_get_usable_rect(main.get_window().current_screen)
		var size := Vector2i(WINDOW_SIZE * window.content_scale_factor)
		if screen.size.y > 40:  # 不带窗口跑测试时屏幕大小是 0
			size.y = mini(size.y, screen.size.y - 40)
		rect = Rect2i(Vector2i(game.end.x + 8, game.position.y), size)
		if screen.has_area() and not screen.encloses(rect):
			rect.position = game.position + Vector2i(40, 40)
	window.position = rect.position
	window.size = rect.size
	window.visible = visible


func _save_window_rect() -> void:
	_save_pref("window_rect", Rect2i(window.position, window.size))


## 跟着游戏的界面大小缩放（Ctrl + 加号 / 减号也管这个窗口）
func set_ui_scale(value: float) -> void:
	var old := window.content_scale_factor
	window.content_scale_factor = value
	window.min_size = Vector2i(WINDOW_MIN * value)
	if window.visible and old != value:
		window.size = Vector2i(Vector2(window.size) * value / old)


func _notification(what: int) -> void:
	# 关游戏时窗口还开着：记下位置
	if what == NOTIFICATION_EXIT_TREE and window.visible:
		_save_window_rect()


# ---------- 面板各部分 ----------

func _build_playback() -> VBoxContainer:
	var col := VBoxContainer.new()
	var row := HBoxContainer.new()
	for spec in [["⏮", "回到开局（Home）", func(): seek(0)],
			["◀", "后退一回合（←）", func(): seek(main.state.steps - 1)],
			["", "播放/暂停（空格）", toggle_play],
			["▶|", "前进一回合（→）", func(): pause(); step_forward(true)],
			["⏭", "跳到记录的最后（End）", func(): seek(_last_step())]]:
		var b: Button = _play if spec[0] == "" else Button.new()
		b.text = spec[0] if spec[0] != "" else "▶"
		b.tooltip_text = spec[1]
		b.custom_minimum_size.x = 40
		b.pressed.connect(spec[2])
		row.add_child(b)
	for s in SPEEDS:
		_speed.add_item(s[1])
	_speed.item_selected.connect(func(i): _timer.wait_time = SPEEDS[i][0]; _save_pref("speed", i))
	row.add_child(_speed)
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_turn_label)
	col.add_child(row)

	# 拖动进度条跳到某一回合（松手时才重算）
	_slider.step = 1
	_slider.drag_ended.connect(func(_changed): seek(int(_slider.value)))
	_slider.value_changed.connect(func(v): if not _slider_busy: _turn_label.text = "松手跳到第 %d 回合" % (int(v) + 1))
	col.add_child(_slider)

	var mode_row := HBoxContainer.new()
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode.add_theme_font_size_override("font_size", 13)
	mode_row.add_child(_mode)
	_resume.text = "从这里接着玩"
	_resume.tooltip_text = "丢掉这一回合以后的记录，从这里开始操作（另开一条路）"
	_resume.pressed.connect(resume_here)
	mode_row.add_child(_resume)
	_cancel.text = "取消"
	_cancel.tooltip_text = "停止重算，留在原来的回合（Esc）"
	_cancel.pressed.connect(cancel_seek)
	mode_row.add_child(_cancel)
	col.add_child(mode_row)
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_font_size_override("font_size", 13)
	_warn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	col.add_child(_warn)
	return col


func _build_view_row() -> VBoxContainer:
	var col := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_child(_small("👁 视角"))
	_view_pick.item_selected.connect(set_view)
	row.add_child(_view_pick)
	_autoplay.text = "由 AI 控制"
	_autoplay.tooltip_text = "勾上：这个文明交给 AI 打；去掉：你来操作它（会记进对局记录）"
	_autoplay.toggled.connect(_on_autoplay)
	row.add_child(_autoplay)
	col.add_child(row)
	_reveal.text = "上帝视角：显示所有文明和星系"
	_reveal.add_theme_font_size_override("font_size", 13)
	_reveal.toggled.connect(func(on): _save_pref("reveal", on); main.refresh())
	col.add_child(_reveal)
	_play_on.text = "你灭亡后对局不结束，其余文明接着打"
	_play_on.add_theme_font_size_override("font_size", 13)
	_play_on.toggled.connect(func(on): _dev(func(s: GameState): return s.set_play_on_after_death(on)))
	col.add_child(_play_on)
	_after_death.text = "💀 你已灭亡：继续往下看"
	_after_death.tooltip_text = "重算你灭亡的那一回合，这次不结束对局，其余文明接着打"
	_after_death.pressed.connect(continue_after_death)
	col.add_child(_after_death)
	return col


## 一览页：各文明的数据（点名字换视角），和看着的文明最近做了什么、为什么。
func _build_overview_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	_table.columns = 8
	_table.add_theme_constant_override("h_separation", 10)
	page.add_child(_table)
	var head := HBoxContainer.new()
	head.add_child(_small("📜 这个文明最近几回合做了什么"))
	_show_notes.text = "显示 AI 的想法"
	_show_notes.button_pressed = true
	_show_notes.add_theme_font_size_override("font_size", 13)
	_show_notes.toggled.connect(func(_on): refresh_panel())
	head.add_child(_show_notes)
	page.add_child(head)
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	page.add_child(_log)
	return page


## 数值页：balance.cfg 的每个数值一行，改了马上生效（也记进对局记录）。
func _build_balance_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	_balance_defaults = Balance.file_values()
	page.add_child(_build_preset_box())
	var top := HBoxContainer.new()
	_balance_filter.placeholder_text = "🔍 按名字或说明筛选"
	_balance_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_balance_filter.text_changed.connect(func(_t): _filter_balance())
	top.add_child(_balance_filter)
	var only_changed := CheckBox.new()
	only_changed.text = "只看改过的"
	only_changed.toggled.connect(func(_on): _filter_balance())
	top.add_child(only_changed)
	page.add_child(top)
	_balance_filter.set_meta("only_changed", only_changed)
	page.add_child(_small("改动从这一回合起生效；整局重算时也会在同一回合改。灰色说明来自 balance.cfg 的注释。",
			Color(0.6, 0.6, 0.7)))
	var grid := GridContainer.new()
	grid.columns = 3
	page.add_child(grid)
	var docs := _balance_docs()
	for name in _balance_defaults:
		var value = _balance_defaults[name]
		# 名字下面一行灰字是说明，太长时截断，鼠标停上去看全文
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", -2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.tooltip_text = docs.get(name, "")
		var label := _small(name)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.add_child(label)
		if docs.get(name, "") != "":
			var doc := _small(docs[name], Color(0.55, 0.55, 0.65))
			doc.add_theme_font_size_override("font_size", 11)
			doc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			doc.custom_minimum_size.x = 300
			doc.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(doc)
		grid.add_child(cell)
		var editor := _value_editor(value, func(v): _on_balance_edit(name, v))
		editor.tooltip_text = docs.get(name, "")
		grid.add_child(editor)
		var reset := Button.new()
		reset.text = "↺"
		reset.tooltip_text = "恢复成 balance.cfg 里的 %s" % str(value)
		reset.pressed.connect(func(): _on_balance_edit(name, _balance_defaults[name]))
		grid.add_child(reset)
		_balance_rows[name] = {"cell": cell, "label": label, "editor": editor, "reset": reset, "doc": docs.get(name, "")}
	return page


## 数值页上面的「方案」：一组数值存成文件，可以切换、导入导出、设成新局默认、写回 balance.cfg。
func _build_preset_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_child(_small("📦 方案"))
	_preset_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_pick.tooltip_text = "📁 共享的（game/balance_presets/，进 git）　👤 自己的（user://balance_presets/）"
	_preset_pick.item_selected.connect(func(_i): _on_preset_picked())
	row.add_child(_preset_pick)
	for spec in [["用上", "把数值换成这个方案的（没写的数值用 balance.cfg 里的），从这一回合起生效", apply_preset],
			["恢复默认", "所有数值换回 balance.cfg 里的", func(): _apply_values({}, "balance.cfg 里的数值")]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[1]
		b.pressed.connect(spec[2])
		row.add_child(b)
	_preset_delete.text = "🗑"
	_preset_delete.tooltip_text = "删掉这个方案文件"
	_preset_delete.pressed.connect(_delete_preset)
	row.add_child(_preset_delete)
	box.add_child(row)

	_preset_default.text = "新开一局时用选中的方案"
	_preset_default.tooltip_text = "勾上后，打开游戏和新开一局都先换成这个方案（只在调试面板在的时候）"
	_preset_default.add_theme_font_size_override("font_size", 13)
	_preset_default.toggled.connect(func(on):
		_save_pref("default_preset", _selected_preset() if on else "")
		_note = "新开一局时用「%s」" % _selected_preset().get_file().get_basename() if on else "新开一局时用 balance.cfg 里的数值"
		refresh_panel())
	box.add_child(_preset_default)

	var save_row := HBoxContainer.new()
	_preset_name.placeholder_text = "方案名"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.text_submitted.connect(func(_t): save_preset())
	save_row.add_child(_preset_name)
	_preset_shared.text = "共享（进 git）"
	_preset_shared.tooltip_text = "存到 game/balance_presets/，提交后大家都能用。只有用编辑器版运行时能存。"
	_preset_shared.disabled = not BalancePresets.can_write_back()
	save_row.add_child(_preset_shared)
	var save := Button.new()
	save.text = "存成方案"
	save.tooltip_text = "把现在和 balance.cfg 不一样的数值存成方案（同名的会覆盖）"
	save.pressed.connect(save_preset)
	save_row.add_child(save)
	box.add_child(save_row)

	var file_row := HBoxContainer.new()
	var import := Button.new()
	import.text = "导入文件…"
	import.tooltip_text = "选一个别人发来的 .cfg 方案，复制到自己的方案里"
	import.pressed.connect(func():
		if WebFiles.is_web():
			WebFiles.pick("." + BalancePresets.EXT, import_preset)
			return
		_preset_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		_preset_dialog.popup_centered())
	WebFiles.make_pick_button(import)
	file_row.add_child(import)
	var folder := Button.new()
	if not WebFiles.is_web():
		folder.text = "打开文件夹"
		folder.tooltip_text = "打开存自己方案的文件夹（导出 = 把里面的 .cfg 发给别人）"
		folder.pressed.connect(func():
			DirAccess.make_dir_recursive_absolute(BalancePresets.USER_DIR)
			OS.shell_open(ProjectSettings.globalize_path(BalancePresets.USER_DIR)))
	else:
		# 网页版打不开文件夹，改成把选中的方案下载下来
		folder.text = "下载"
		folder.tooltip_text = "把选中的方案下载成 .cfg 文件，可以发给别人"
		folder.pressed.connect(func():
			if _selected_preset() == "":
				_note = "先选一个方案"
				refresh_panel()
			else:
				WebFiles.download(_selected_preset()))
	file_row.add_child(folder)
	_write_back.text = "写回 balance.cfg"
	_write_back.tooltip_text = "把现在的数值写进 game/balance.cfg（只改值，注释留着）。之后跑 uv run game/tools/update_docs.py 更新文档里的数字"
	_write_back.visible = BalancePresets.can_write_back()
	_write_back.pressed.connect(write_back)
	file_row.add_child(_write_back)
	box.add_child(file_row)

	_preset_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_preset_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_preset_dialog.filters = PackedStringArray(["*.cfg ; 数值方案"])
	_preset_dialog.size = Vector2i(800, 500)
	_preset_dialog.file_selected.connect(import_preset)
	add_child(_preset_dialog)
	box.add_child(HSeparator.new())
	_refresh_presets()
	return box


## 重新列出方案。select 是要选中的文件路径（空的时候选新局默认的那个）。
func _refresh_presets(select := "") -> void:
	if select == "":
		select = default_preset()
	_preset_pick.clear()
	_preset_paths.clear()
	_preset_pick.add_item("（选一个方案）")
	_preset_paths.append("")
	for p in BalancePresets.list():
		_preset_pick.add_item(("📁 " if p["shared"] else "👤 ") + p["name"])
		_preset_paths.append(p["path"])
	_preset_pick.select(maxi(_preset_paths.find(select), 0))
	_on_preset_picked()


func _selected_preset() -> String:
	return _preset_paths[maxi(_preset_pick.selected, 0)]


func _on_preset_picked() -> void:
	var path := _selected_preset()
	_preset_delete.disabled = path == "" or (path.begins_with("res://") and not BalancePresets.can_write_back())
	_preset_default.disabled = path == ""
	_preset_default.set_pressed_no_signal(path != "" and path == default_preset())
	if path != "":
		_preset_name.text = path.get_file().get_basename()
		_preset_shared.set_pressed_no_signal(path.begins_with("res://") and BalancePresets.can_write_back())
		var p := BalancePresets.read(path)
		_preset_pick.tooltip_text = "%s\n%s" % [p.get("note", ""), ProjectSettings.globalize_path(path)]


## 新开一局时用的方案文件路径（没设或文件已经没了时为空）。
func default_preset() -> String:
	var path: String = _prefs.get_value("panel", "default_preset", "")
	return path if path != "" and FileAccess.file_exists(path) else ""


## 换成选中的方案。
func apply_preset() -> void:
	var path := _selected_preset()
	if path == "":
		_note = "先选一个方案"
		refresh_panel()
		return
	var p := BalancePresets.read(path)
	if p.is_empty():
		_note = "读不出这个方案：%s" % path
		refresh_panel()
		return
	_apply_values(p["values"], "方案「%s」" % path.get_file().get_basename(), p["warnings"])


## 把数值换成 balance.cfg 里的、再盖上 values。只改和现在不一样的，每一项都记进对局记录。
func _apply_values(values: Dictionary, what: String, warnings: Array = []) -> void:
	if seeking or replaying():
		_note = "正在重算要跳去的回合，算完才能改" if seeking else "回放中不能改数值，先按「从这里接着玩」"
		refresh_panel()
		return
	var now := Balance.values()
	var changed: Array[String] = []
	var errors: Array[String] = []
	for name in _balance_defaults:
		var target = values.get(name, _balance_defaults[name])
		if typeof(target) == typeof(now[name]) and target == now[name]:
			continue
		var r: Dictionary = main.state.dev_balance(name, target)
		if r["error"] == "":
			changed.append(name)
		else:
			errors.append(r["error"])
	main.autosave()
	_note = "换成了%s：%s" % [what, "，".join(changed) if changed else "没有要改的"]
	for w in warnings + errors:
		_note += "\n⚠ " + w
	main.refresh()


## 把现在和 balance.cfg 不一样的数值存成方案。
func save_preset() -> void:
	var name := _preset_name.text.strip_edges()
	if name == "":
		_note = "先写一个方案名"
		refresh_panel()
		return
	var path := BalancePresets.path_for(name, _preset_shared.button_pressed)
	var values := Balance.values()
	var err := BalancePresets.save(path, values, "")
	if err == OK:
		var count: int = BalancePresets.read(path)["values"].size()
		_note = "已存方案「%s」（%d 个数值和 balance.cfg 不一样）：%s" % [name, count, ProjectSettings.globalize_path(path)]
		if path.begins_with("res://"):
			_note += "\n记得把这个文件提交进 git"
	else:
		_note = "保存失败：%s" % error_string(err)
	_refresh_presets(path)
	refresh_panel()


## 导入别人发来的方案文件：检查读得出来，再复制到自己的方案里。
func import_preset(path: String) -> void:
	var p := BalancePresets.read(path)
	if p.is_empty():
		_note = "读不出这个方案：%s" % path
		refresh_panel()
		return
	var target := BalancePresets.path_for(path.get_file().get_basename(), false)
	DirAccess.make_dir_recursive_absolute(BalancePresets.USER_DIR)
	var err := DirAccess.copy_absolute(path, target)
	_note = "导入了「%s」（%d 个数值），按「用上」生效" % [target.get_file().get_basename(), p["values"].size()] \
			if err == OK else "导入失败：%s" % error_string(err)
	for w in p["warnings"]:
		_note += "\n⚠ " + w
	_refresh_presets(target)
	refresh_panel()


func _delete_preset() -> void:
	var path := _selected_preset()
	if path == "":
		return
	var err := DirAccess.remove_absolute(path)
	_note = "删掉了「%s」" % path.get_file().get_basename() if err == OK else "删不掉：%s" % error_string(err)
	_refresh_presets()
	refresh_panel()


## 把现在的数值写进 balance.cfg（只在编辑器版里能用）。之后「默认」就是新写进去的值。
func write_back() -> void:
	var r := BalancePresets.write_back(Balance.values())
	if r["error"] != "":
		_note = "没写回：" + r["error"]
	elif r["changed"].is_empty():
		_note = "现在的数值和 balance.cfg 一样，不用写"
	else:
		_balance_defaults = Balance.file_values()
		_note = "已写回 balance.cfg：%s\n记得跑 uv run game/tools/update_docs.py 更新文档里的数字，看看这些数值旁边的注释还对不对" \
				% "，".join(r["changed"])
	refresh_panel()


## 文明页：直接改看着的这个文明的属性和科技。
func _build_civ_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	_civ_title.add_theme_font_size_override("font_size", 14)
	page.add_child(_civ_title)
	var quick := HFlowContainer.new()
	for spec in [["+100 能量", func(c): return [["energy", c.energy + 100]]],
			["+100 矿石", func(c): return [["mineral", c.mineral + 100]]],
			["行动点加满", func(c): return [["actions_left", c.action_points(main.state.map)]]],
			["开放 I～III 级", func(c): return [["tier1_turn", 0], ["tier2_turn", 0], ["tier3_turn", 0]]]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(func():
			for kv in spec[1].call(viewed()):
				_dev(func(s: GameState): return s.dev_set(viewed(), kv[0], kv[1])))
		quick.add_child(b)
	var all_tech := Button.new()
	all_tech.text = "全部科技"
	all_tech.pressed.connect(func():
		for id in Tech.ALL:
			if not viewed().has_tech(id):
				_dev(func(s: GameState): return s.dev_tech(viewed(), id, true)))
	quick.add_child(all_tech)
	page.add_child(quick)

	_civ_grid.columns = 2
	page.add_child(_civ_grid)
	var probe := Civ.new("", false, Vector3i.ZERO)
	for p in probe.get_property_list():
		var field: String = p["name"]
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) or GameState.DEV_SET_LOCKED.has(field):
			continue
		if not p["type"] in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			continue
		var label := _small(CIV_FIELD_NAMES.get(field, field))
		label.tooltip_text = field
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_civ_grid.add_child(label)
		var editor := _value_editor(probe.get(field),
				func(v): _dev(func(s: GameState): return s.dev_set(viewed(), field, v)))
		_civ_grid.add_child(editor)
		_civ_rows[field] = editor

	page.add_child(_small("🔬 科技（勾上直接得到，不花资源）"))
	var techs := GridContainer.new()
	techs.columns = 2
	for id in Tech.ALL:
		var cb := CheckBox.new()
		cb.text = Tech.title(id)
		cb.add_theme_font_size_override("font_size", 13)
		cb.toggled.connect(func(on): _dev(func(s: GameState): return s.dev_tech(viewed(), id, on)))
		techs.add_child(cb)
		_tech_boxes[id] = cb
	page.add_child(techs)
	return page


## 记录页：存、打开对局记录，新开一局。
func _build_record_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_child(_small("每结束一回合，这一局的记录会自动存成 last.replay；出问题时把它发给别人就能重现。",
			Color(0.6, 0.6, 0.7)))
	var file_row := HBoxContainer.new()
	var folder_button := ["📁 打开文件夹", func():
		DirAccess.make_dir_recursive_absolute(Replay.DIR)
		OS.shell_open(ProjectSettings.globalize_path(Replay.DIR))]
	if WebFiles.is_web():
		# 网页版打不开文件夹，改成把自动存的记录下载下来
		folder_button = ["⬇️ 下载 last.replay", func():
			if FileAccess.file_exists(main.autosave_path):
				WebFiles.download(main.autosave_path)
			else:
				_note = "还没有 last.replay（结束一回合后才有）"
				refresh_panel()]
	for spec in [["💾 保存记录", save_replay], ["📂 打开记录", _open_dialog], folder_button]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		if spec[1] == _open_dialog:
			WebFiles.make_pick_button(b)
		file_row.add_child(b)
	page.add_child(file_row)
	if WebFiles.is_web():
		page.add_child(_small("网页版的记录存在浏览器里；「保存记录」同时下载一份到电脑上。\n" +
				"网址后面加 ?debug 打开这个面板，?watch&seed=123 观战", Color(0.6, 0.6, 0.7)))
	else:
		page.add_child(_small("命令行：-- replay=<文件> 打开记录；-- watch seed=123 观战；-- debug 打开这个面板",
				Color(0.6, 0.6, 0.7)))

	var new_row := HBoxContainer.new()
	new_row.add_child(_small("种子"))
	_seed.max_value = 999999
	# 命令行的 -- seed= 可以是任何整数，框里也要放得下，不然新开一局会悄悄换了种子
	_seed.allow_greater = true
	_seed.allow_lesser = true
	_seed.value = main.state.seed_value
	new_row.add_child(_seed)
	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "随机换一个种子"
	dice.pressed.connect(func(): _seed.value = randi() % 1000000)
	new_row.add_child(dice)
	page.add_child(new_row)
	var buttons := HBoxContainer.new()
	for spec in [["👀 新开观战局（全是 AI）", true], ["🙋 新开一局自己玩", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(func(): new_game(int(_seed.value), spec[1]))
		buttons.add_child(b)
	page.add_child(buttons)
	return page


# ---------- 给主画面用的 ----------

## 正在看的文明。
func viewed() -> Civ:
	return main.state.civs[clampi(view_idx, 0, main.state.civs.size() - 1)]


## 局面停在记录中间（回放中）。
func replaying() -> bool:
	return replay != null and main.state.steps < replay.last_step()


## 现在不能操作的原因（可以操作时为空）。文明由 AI 控制时由主画面另外判断。
func locked_reason() -> String:
	if seeking:
		return "正在重算要跳去的回合，算完才能操作（Esc 取消）"
	if replaying():
		return "正在回放第 %d 回合。要从这里操作，按调试面板里的「从这里接着玩」" % main.state.turn
	return ""


## 调试快捷键。处理了返回 true。
func handle_key(event: InputEventKey) -> bool:
	if not visible:
		return false
	if seeking:
		if event.keycode == KEY_ESCAPE:
			cancel_seek()
			return true
		return false
	match event.keycode:
		KEY_SPACE:
			toggle_play()
		KEY_RIGHT:
			pause()
			step_forward(true)
		KEY_LEFT:
			seek(main.state.steps - 1)
		KEY_HOME:
			seek(0)
		KEY_END:
			seek(_last_step())
		_:
			var i: int = event.keycode - KEY_1
			if i < 0 or i >= main.state.civs.size():
				return false
			set_view(i)
	return true


## 主画面刷新时一起刷新面板。只刷新看得到的那一页。
func refresh_panel() -> void:
	if not visible:
		return
	var s: GameState = main.state
	var last := _last_step()
	_slider_busy = true
	_slider.max_value = maxi(1, last)
	_slider.value = s.steps
	_slider_busy = false
	_turn_label.text = "第 %d / %d 回合" % [s.turn, last + 1]
	_play.text = "⏸" if not _timer.is_stopped() else "▶"
	if replaying():
		_mode.text = "⏪ 回放中：往前走会按记录重做当时的操作"
	elif s.spectator:
		_mode.text = "👀 观战局：所有文明由 AI 控制（可以取消勾选「由 AI 控制」来接管）"
	else:
		_mode.text = "🟢 实时：正在打的这一局"
	if s.dev_used:
		_mode.text += "　🛠 这局改过数值"
	if _note != "":
		_mode.text += "\n" + _note
	_resume.visible = replaying() and not seeking
	_cancel.visible = seeking
	_warn.visible = desync_step >= 0
	if desync_step >= 0:
		_warn.text = "⚠️ 第 %d 回合的结果和记录不一样（记录以后规则或数值改过）。之后的局面不是当时的样子。" \
				% (desync_step + 1)

	if s.play_on_after_death and not s.human().alive and not s.is_over():
		_mode.text += "\n💀 你已灭亡，其余文明接着打"
	_play_on.set_pressed_no_signal(s.play_on_after_death)
	_play_on.visible = not s.spectator
	_play_on.disabled = replaying() or s.is_over()
	_after_death.visible = can_continue_after_death()
	var me := viewed()
	_autoplay.set_pressed_no_signal(me.is_ai)
	_autoplay.disabled = replaying() or not me.alive
	_view_pick.clear()
	for i in s.civs.size():
		var c: Civ = s.civs[i]
		_view_pick.add_item("%d. %s%s%s" % [i + 1, c.name, "" if c.is_ai else "（玩家）", "" if c.alive else "（灭亡）"])
	_view_pick.select(clampi(view_idx, 0, s.civs.size() - 1))
	match _tabs.current_tab:
		0:
			_refresh_table(s)
			_refresh_log(s)
		1:
			_refresh_balance()
		2:
			_refresh_civ(me)


# ---------- 播放 ----------

func toggle_play() -> void:
	if seeking:
		return
	if _timer.is_stopped():
		_note = ""
		_timer.start()
	else:
		_timer.stop()
	refresh_panel()


func pause() -> void:
	_timer.stop()


func _on_tick() -> void:
	if not step_forward(false):
		pause()
		refresh_panel()


## 前进一回合。manual 为 false（自动播放）时，有文明等着玩家操作就停下。前进不了返回 false。
## redraw 为 false 时不刷新画面（连续跳很多回合时只在最后刷新一次）。
func step_forward(manual: bool, redraw := true) -> bool:
	var s: GameState = main.state
	if seeking:
		return false
	if s.is_over():
		_note = "对局已经结束"
		return false
	if replaying():
		if not replay.step(s) and desync_step < 0:
			desync_step = replay.desync_step
		remember_turn(s)
		if s.steps >= replay.last_step():
			replay.apply_pending(s)
			replay = null  # 走到记录末尾，回到实时
		elif s.is_over():
			replay = null  # 重算走偏、提前分出胜负：后面的记录用不上了，回到实时
	else:
		var waiting := s.civs.filter(func(c): return c.alive and not c.is_ai)
		if not manual and not waiting.is_empty():
			_note = "轮到 %s 操作了，播放停下（▶| 直接结束这一回合）" % waiting[0].name
			return false
		s.end_turn()
		remember_turn(s)
		main.autosave()
	_note = ""
	if redraw:
		main.refresh()
	return true


## 刚结束一回合（还没做下一回合的操作）时调用：把局面存进往回跳用的缓存。
## 自动播放时只存每 Snapshots.EVERY 回合一份，打包一份要几十毫秒，每回合都存会让播放慢一倍。
func remember_turn(s: GameState) -> void:
	if _timer.is_stopped() or s.steps % Snapshots.EVERY == 0:
		snapshots.remember(s, desync_step)


## 跳到结束过 n 回合的局面：从局面缓存里不晚于 n 的最近一份（往后跳时也可能就是现在的局面）按记录一回合一回合补算。
## 补算超过 seek_slice 毫秒时分段算，段和段之间让界面处理输入、显示进度。
## 算完才换局面，取消（cancel_seek）时留在原来的局面。
func seek(n: int) -> void:
	pause()
	cancel_seek()
	var s: GameState = main.state
	n = clampi(n, 0, _last_step())
	if n == s.steps:
		refresh_panel()
		return
	if not s.history.any(func(h): return h["step"] == s.steps):
		snapshots.remember(s, desync_step)  # 这一回合还没人操作过：存下来，跳走以后跳回来不用再算
	_before_seek = {"balance": Balance.values(), "replay": replay, "desync": replay.desync_step if replay != null else -1}
	if replay == null:
		replay = Replay.from_state(s)
	var r := replay
	var started := Time.get_ticks_msec()
	var again: GameState
	if n > s.steps and snapshots.nearest(n, r) <= s.steps:
		again = StateCopy.copy(s)  # 往后跳、现在的局面比缓存近：从它接着走（走的是复制品，取消时原来的不动）
	else:
		again = r.begin(n, snapshots)
	var from := again.steps
	_seek_id += 1
	var id := _seek_id
	seeking = true
	var slice := Time.get_ticks_msec()
	var paused := false
	while again.steps < mini(n, r.last_step()) and not again.is_over():
		r.advance(again, snapshots, n)
		if Time.get_ticks_msec() - slice >= seek_slice:
			_note = "正在从第 %d 回合补算到第 %d 回合：%d / %d（Esc 或「取消」停下）" \
					% [from + 1, n + 1, again.steps - from, n - from]
			if paused:
				refresh_panel()
			else:
				main.refresh()  # 第一次停下时整个画面刷新一次，结束回合等按钮变成不能按
				paused = true
			await get_tree().process_frame
			if id != _seek_id:
				return  # 取消了，或者又开始了另一次跳转
			slice = Time.get_ticks_msec()
	seeking = false
	r.finish(again)
	if r.desync_step >= 0 and desync_step < 0:
		desync_step = r.desync_step
	if n >= r.last_step() or again.is_over():
		replay = null
	main.set_state(again)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if again.steps == from:
		_note = "直接取了缓存里的局面（%.2f 秒）" % seconds
	else:
		_note = "从%s补算了 %d 回合，用了 %.1f 秒" % ["开局" if from == 0 else "第 %d 回合" % (from + 1), again.steps - from, seconds]
	refresh_panel()


## 停下正在算的跳转，留在原来的局面，数值和回放记录也换回跳转以前的。没有在算时什么都不做。
func cancel_seek() -> void:
	if not seeking:
		return
	seeking = false
	_seek_id += 1
	Balance.apply(_before_seek["balance"])
	replay = _before_seek["replay"]
	if replay != null:
		replay.desync_step = _before_seek["desync"]
	_note = "取消了跳转，还在第 %d 回合" % main.state.turn
	main.refresh()


## 丢掉之后的记录，从现在的局面接着打。
func resume_here() -> void:
	if seeking:
		return
	pause()
	replay = null
	snapshots.drop_after(main.state.steps)  # 之后的是丢掉的那条路
	_note = "已从第 %d 回合另开一条路，之后的记录丢掉了" % main.state.turn
	main.autosave()
	main.refresh()

## 对局因为你灭亡而结束，而且还有不止一个文明活着。
func can_continue_after_death() -> bool:
	var s: GameState = main.state
	return s.winner == "AI" and not s.human().alive and not replaying() and not seeking and s.steps > 0 \
			and s.civs.filter(func(c): return c.alive).size() >= 2


## 重算你灭亡的那一回合：先打开「灭亡后接着打」，再结束这一回合，对局就不会结束。
## 改动记进对局记录，以后回放时同样在这一回合打开。
func continue_after_death() -> void:
	if not can_continue_after_death():
		return
	pause()
	var s: GameState = main.state
	var r := Replay.from_state(s)
	var again := r.play_to(s.steps - 1, snapshots)
	r.apply_pending(again)
	again.set_play_on_after_death(true)
	again.end_turn()
	snapshots.drop_after(again.steps - 1)  # 原来灭亡的那一回合是另一条路
	remember_turn(again)
	replay = null
	view_idx = clampi(view_idx, 0, again.civs.size() - 1)
	main.set_state(again)
	main.autosave()
	_note = "已重算第 %d 回合，你灭亡后对局继续" % (again.turn - 1)
	refresh_panel()


func set_view(i: int) -> void:
	view_idx = clampi(i, 0, main.state.civs.size() - 1)
	main.refresh()


func _on_autoplay(on: bool) -> void:
	if replaying() or seeking:
		return
	main.state.set_autoplay(viewed(), on)
	main.autosave()
	main.refresh()


## 记录里一共结束过几回合（实时时就是现在）。
func _last_step() -> int:
	return replay.last_step() if replay != null else main.state.steps


# ---------- 改数值 ----------

## 做一次调试改动（回放中不能改）。action 收到 GameState，返回规则的结果。
func _dev(action: Callable) -> void:
	if seeking:
		_note = "正在重算要跳去的回合，算完才能改"
	elif replaying():
		_note = "回放中不能改数值，先按「从这里接着玩」"
	else:
		snapshots.drop_after(main.state.steps)  # 实时局面以后的缓存（如果有）不再是这条路
		var r: Dictionary = action.call(main.state)
		_note = "改不了：" + r["error"] if r["error"] != "" else ""
		main.autosave()
	main.refresh()


func _on_balance_edit(name: String, value: Variant) -> void:
	_dev(func(s: GameState): return s.dev_balance(name, value))


func _filter_balance() -> void:
	var words := _balance_filter.text.strip_edges().to_lower()
	var only_changed: bool = (_balance_filter.get_meta("only_changed") as CheckBox).button_pressed
	var now := Balance.values()
	for name in _balance_rows:
		var row := _balance_rows[name]
		var hit: bool = words == "" or name.to_lower().contains(words) or String(row["doc"]).to_lower().contains(words)
		if only_changed:
			hit = hit and now[name] != _balance_defaults[name]
		for key in ["cell", "editor", "reset"]:
			row[key].visible = hit


func _refresh_balance() -> void:
	var now := Balance.values()
	for name in _balance_rows:
		var row := _balance_rows[name]
		_set_editor(row["editor"], now[name])
		var changed: bool = now[name] != _balance_defaults[name]
		(row["label"] as Label).add_theme_color_override("font_color",
				Color(1.0, 0.7, 0.3) if changed else Color(0.85, 0.85, 0.9))
		(row["reset"] as Button).disabled = not changed
	_filter_balance()


func _refresh_civ(me: Civ) -> void:
	_civ_title.text = "%s%s%s" % [me.name, "（AI）" if me.is_ai else "（玩家）", "" if me.alive else "（已灭亡）"]
	for field in _civ_rows:
		_set_editor(_civ_rows[field], me.get(field))
	for id in _tech_boxes:
		_tech_boxes[id].set_pressed_no_signal(me.has_tech(id))


## 按数值的类型做一个输入框：整数、小数用数字框，开关用勾选框，数组用文字框（写成 [1, 2, 3]）。
func _value_editor(value: Variant, on_change: Callable) -> Control:
	if value is bool:
		var cb := CheckBox.new()
		cb.toggled.connect(on_change)
		return cb
	if value is int or value is float:
		var spin := SpinBox.new()
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.min_value = -1000
		spin.max_value = 1000
		spin.step = 1 if value is int else 0.01
		spin.custom_minimum_size.x = 110
		spin.value_changed.connect(func(v): on_change.call(int(v) if value is int else v))
		return spin
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 140
	edit.text_submitted.connect(func(t):
		var parsed = str_to_var(t)
		if typeof(parsed) == typeof(value):
			on_change.call(parsed)
		else:
			_note = "格式不对，要写成和原来一样的样子：%s" % str(value)
			main.refresh())
	return edit


func _set_editor(editor: Control, value: Variant) -> void:
	if editor is CheckBox:
		(editor as CheckBox).set_pressed_no_signal(value)
	elif editor is SpinBox:
		(editor as SpinBox).set_value_no_signal(value)
	elif editor is LineEdit and not editor.has_focus():
		(editor as LineEdit).text = str(value)


## 每个数值的说明（取自 balance.cfg 的注释）。
func _balance_docs() -> Dictionary:
	return Balance.docs()


# ---------- 对局记录 ----------

func save_replay() -> void:
	var r := replay if replay != null else Replay.from_state(main.state)
	var path := Replay.DIR.path_join("%s-seed%d-t%d.replay" % [
			Time.get_datetime_string_from_system().replace(":", ""), r.seed_value, r.last_step() + 1])
	var err := r.save(path)
	_note = "已存到 %s" % ProjectSettings.globalize_path(path) if err == OK else "保存失败：%s" % error_string(err)
	if err == OK and WebFiles.is_web():
		WebFiles.download(path)
		_note = "已下载 %s" % path.get_file()
	refresh_panel()


func _open_dialog() -> void:
	if WebFiles.is_web():
		WebFiles.pick(".replay", load_replay)
		return
	DirAccess.make_dir_recursive_absolute(Replay.DIR)
	_file_dialog.current_dir = ProjectSettings.globalize_path(Replay.DIR)
	_file_dialog.popup_centered()


## 打开记录，停在开局。记录时的数值和现在不一样时，换成记录时的（只在这次运行里有效）。
func load_replay(path: String) -> void:
	pause()
	cancel_seek()
	var r := Replay.load_file(path)
	if r == null:
		_note = "打不开这个文件（损坏或规则版本不兼容）：%s" % path
		refresh_panel()
		return
	var diff := r.balance_diff()
	replay = r if r.last_step() > 0 else null
	snapshots.clear()
	desync_step = -1
	view_idx = 0
	var s := r.play_to(0)
	_seed.value = r.seed_value
	main.set_state(s)
	_note = "打开了 %s（种子 %d，%d 回合）" % [path.get_file(), r.seed_value, r.last_step() + 1]
	if not diff.is_empty():
		_note += "\n数值换成了记录开局时的：" + "，".join(diff.keys())
	refresh_panel()


## 新开一局。watch 为 true 时所有文明都由 AI 控制。
## 数值换回 balance.cfg 里的；设了「新开一局时用的方案」时再换成那个方案。
func new_game(seed_value: int, watch: bool) -> void:
	pause()
	cancel_seek()
	replay = null
	snapshots.clear()
	desync_step = -1
	view_idx = 1 if watch else 0
	Balance.apply(_balance_defaults)
	var preset := default_preset()
	if preset != "":
		Balance.apply(BalancePresets.read(preset).get("values", {}))
	var s := GameState.new_game(seed_value, Balance.AI_COUNT, watch)
	s.add_log("新的一局，种子 %d%s%s" % [seed_value, "（观战）" if watch else "",
			"，数值方案「%s」" % preset.get_file().get_basename() if preset != "" else ""])
	_seed.set_value_no_signal(seed_value)
	_note = ""
	main.set_state(s)
	main.autosave()


# ---------- 一览页 ----------

func _refresh_table(s: GameState) -> void:
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	for head in ["文明", "星系", "能量", "矿石", "科技", "单位", "已知", "被打"]:
		_table.add_child(_small(head, Color(0.6, 0.6, 0.7)))
	for i in s.civs.size():
		var c: Civ = s.civs[i]
		var b := Button.new()
		b.text = ("👁 " if i == view_idx else "") + c.name + ("" if c.is_ai else " 🙋")
		b.flat = i != view_idx
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", Color.WHITE if c.alive else Color(0.5, 0.5, 0.5))
		b.tooltip_text = "看 %s 的视角（数字键 %d）" % [c.name, i + 1]
		b.pressed.connect(set_view.bind(i))
		_table.add_child(b)
		if not c.alive:
			_table.add_child(_small("灭亡", Color(0.6, 0.4, 0.4)))
			for k in 6:
				_table.add_child(_small(""))
			continue
		var flying := c.ships.filter(func(sh): return not sh.docked).size()
		for text in [str(c.colonies.size()), "%d +%d" % [c.energy, s.energy_income(c)],
				"%d +%d" % [c.mineral, s.mineral_income(c)], str(c.techs.size()),
				"%d（飞 %d）" % [c.ships.size(), flying], str(c.known.size()), str(c.times_hit)]:
			_table.add_child(_small(text))


func _refresh_log(s: GameState) -> void:
	var civ := viewed()
	var idx := clampi(view_idx, 0, s.civs.size() - 1)
	var lines: Array[String] = []
	var shown_step := -1
	for h in s.history:
		if h["step"] < s.steps - LOG_TURNS + 1 or (h["civ"] != idx and h["civ"] >= 0):
			continue
		if h["name"] == "note" and not _show_notes.button_pressed:
			continue
		if h["step"] != shown_step:
			shown_step = h["step"]
			lines.append("[color=#8899bb]第 %d 回合[/color]" % (shown_step + 1))
		var text := describe(civ, h)
		if h["name"] == "note":
			text = "[color=#9a9ab0]💭 %s[/color]" % text
		elif not h["ai"]:
			text = "🙋 " + text
		lines.append("　" + text)
	if lines.is_empty():
		lines.append("[color=#777777]最近 %d 回合没有操作[/color]" % LOG_TURNS)
	_log.clear()
	_log.append_text("\n".join(lines))


## 一条操作记录写成一句话。
static func describe(civ: Civ, h: Dictionary) -> String:
	var a: Array = h["args"]
	match h["name"]:
		"note":
			return a[0]
		"research":
			return "🔬 升级科技「%s」" % Tech.title(a[0])
		"upgrade":
			return "⬆️ 升级%s" % ("射电望远镜" if a[0] == "telescope" else "预警范围")
		"build":
			return "🏗️ 在 %s 建造%s" % [_cell(a[1]), GameState.BUILD_NAMES[a[0]]]
		"dispatch":
			return "🚀 派出%s，方向 %s%s" % [_ship(civ, a[0]), _dir(a[1]), "（慢速出发）" if a[2] else ""]
		"turn_ship":
			return "↪️ %s转向 %s" % [_ship(civ, a[0]), _dir(a[1])]
		"send_colony":
			return "🌱 %s前往 %s" % [_ship(civ, a[0]), _cell(a[1])]
		"send_sophon":
			return "👁️ %s前往 %s" % [_ship(civ, a[0]), _cell(a[1])]
		"move_starship":
			return "🛸 星舰前往 %s" % _cell(a[0])
		"settle_starship":
			return "🛸 星舰停下建立星系"
		"launch_grain":
			return "💥 从 %s 发射光粒，方向 %s" % [_cell(a[1]), _dir(a[0])]
		"use_antimatter":
			return "☢️ 用反物质打附近的战舰"
		"broadcast":
			return "📡 从 %s 广播坐标 %s" % [_cell(a[1]), _cell(a[0])]
		"launch_foil":
			return "🌀 从 %s 朝 %s 发射二向箔" % [_cell(a[1]), _cell(a[0])]
		"launch_line_foil":
			return "🌀 从 %s 朝 %s 发射单向著" % [_cell(a[1]), _cell(a[0])]
		"start_reduce":
			return "⬇️ 开始自身降维"
		"launch_singularity":
			return "⚫ 发射奇异点"
		"launch_black_domain":
			return "⬛ 在 %s 投放黑域" % _cell(a[0])
		"set_autoplay":
			return "🤖 交给 AI 控制" if a[0] else "🙋 改由玩家操作"
		"set_play_on_after_death":
			return "🛠 %s「你灭亡后对局不结束」" % ("打开" if a[0] else "关掉")
		"dev_balance":
			return "🛠 把数值 %s 改成 %s" % [a[0], str(a[1])]
		"dev_set":
			return "🛠 把%s改成 %s" % [CIV_FIELD_NAMES.get(a[0], a[0]), str(a[1])]
		"dev_tech":
			return "🛠 %s科技「%s」" % ["直接得到" if a[1] else "拿掉", Tech.title(a[0])]
	return "%s %s" % [h["name"], a]


static func _cell(c: Vector3i) -> String:
	if c == GameState.AT_HOME:
		return "母星"
	return "(%d, %d, %d)" % [c.x, c.y, c.z]


static func _dir(d: Vector3) -> String:
	var n := d.normalized()
	return "(%.2f, %.2f, %.2f)" % [n.x, n.y, n.z]


static func _ship(civ: Civ, id: int) -> String:
	var sh := civ.ship_by_id(id)
	return sh.label() if sh != null else "#%d" % id


func _small(text: String, color := Color(0.85, 0.85, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	return l
