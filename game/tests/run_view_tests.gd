extends SceneTree
## 画面测试：检查面板按钮、星图标记和规则一致。
## 不带窗口跑：godot_console --headless --path game --script res://tests/run_view_tests.gd
## 想同时存截图：去掉 --headless，在最后加 -- output=<文件夹>
## 只跑名字里带某个词的测试：在最后加 -- only=词（后面的测试可能要用到前面留下的局面，单独跑时以全跑为准）。
## 测试按 run_tests() 里写的顺序跑；新加的 test_ 函数忘了写进去，会算失败。

const TestLog := preload("res://tests/test_log.gd")

var results := TestLog.new()
var _ran: Array[String] = []
var _output := ""
var view
## 画面的几个部分（view 开好以后填上）
var map
var panel
var actions
var overlay


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			_output = arg.trim_prefix("output=")
	call_deferred("run_tests")


func check(ok: bool, message: String) -> void:
	results.check(ok, message)


## 比较两个值，不一样时失败信息里写出实际值和期望值。
func check_eq(actual, expected, message: String) -> void:
	results.check_eq(actual, expected, message)


## 跑一个测试（会等它里面的 await 都做完）。
func run(test: Callable) -> void:
	var name := test.get_method()
	_ran.append(name)
	if not results.wants(name):
		return
	results.begin(name)
	await test.call()
	results.end()


## 两个人类文明（都不由 AI 控制），各有一个单星系统，资源充足。
func fixture() -> GameState:
	var s := GameState.new()
	s.map = StarMap.new()
	for pos in [Vector3i.ZERO, Vector3i(8, 8, 8)]:
		var civ := Civ.new("你" if s.civs.is_empty() else "Other", false, pos)
		civ.energy = 1000
		civ.mineral = 1000
		s.map.stars[pos] = StarMap.Star.SINGLE
		s.system_cells.append(pos)
		s.civs.append(civ)
		s.start_turn(civ)
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	return s


func show_state(s: GameState) -> void:
	view.set_state(s)


func settled_frame() -> void:
	view._process(map.FLAT_ANIM_SECONDS)
	map._process(10.0)
	await process_frame


## from：截哪个窗口（默认游戏窗口；调试面板是单独的窗口）
func capture(label: String, from: Viewport = null) -> void:
	if _output == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_output)
	var image := (from if from != null else root).get_texture().get_image()
	check(image.save_png(_output.path_join(label + ".png")) == OK, "截图保存成功")


func run_tests() -> void:
	# 调试面板的设置用一个测试专用的空文件，不读也不改玩家自己的
	var panel_script: Script = load("res://view/debug_panel.gd")
	panel_script.set("prefs_path", "user://_test_debug.cfg")
	DirAccess.remove_absolute("user://_test_debug.cfg")
	view = load("res://view/main.tscn").instantiate()
	root.add_child(view)
	view.autosave_path = ""  # 不覆盖玩家自己的 last.replay
	map = view.map
	panel = view.panel
	actions = view.panel.actions
	overlay = view.overlay
	await process_frame
	await run(test_panel_layout)
	await run(test_panel_width)
	await run(test_ui_helpers)
	await capture("start")
	await run(test_research)
	await run(test_tech_tree)
	await run(test_v01_tree_and_numeric_state)
	await run(test_v01_shared_information_view)
	await run(test_v01_ui_resource_preview)
	await run(test_v01_ui_pointer_build_feedback)
	await run(test_v01_speed_descriptions_follow_replay_parameters)
	await run(test_v01_local_parallel_progress_display)
	await run(test_map_clarity)
	await run(test_build_and_dispatch)
	await run(test_v01_completed_build_selection_waits_for_receipt)
	await run(test_colony)
	await run(test_hover_intel)
	await run(test_hover_stored_grain)
	await run(test_camera)
	await run(test_selection)
	await run(test_grid_modes)
	await run(test_ship_paths)
	await run(test_sightings_drawn)
	await run(test_black_domain_drawn)
	await run(test_intel_on_starless_system)
	await run(test_reduction_controls)
	await run(test_v01_navigation_preview_and_ready_display)
	await run(test_v01_probe_vision_matches_received_rules)
	await run(test_v01_probe_vision_physical_scale_in_lower_dimensions)
	await run(test_flat_and_line)
	await run(test_fast_line_collapse_frames_home)
	await run(test_post_victory_collapse)
	await run(test_restart)
	await run(test_debug_view_other_civ)
	await run(test_debug_take_over_ai)
	await run(test_debug_playback)
	await run(test_debug_rewind_cache)
	await run(test_debug_edit_values)
	await run(test_debug_presets)
	await run(test_debug_after_death)
	await run(test_save_load)
	await run(test_save_across_dimensions)
	await run(test_game_shortcuts_and_compact_layout)
	await capture("debug")
	await capture("debug_panel", view.debug.window)
	view.queue_free()
	await process_frame
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_") and not _ran.has(name):
			results.fail("没写进 run_tests() 的列表，没有跑", name)
	DirAccess.remove_absolute("user://_test_debug.cfg")  # 测试时面板设置存在这里，用完删掉
	quit(results.finish("画面测试"))


func test_save_load() -> void:
	view.debug.pause()
	view.debug.replay = null
	view.debug.view_idx = 0
	var defaults := Balance.values()
	var s := GameState.new_game(1)
	s.end_turn()
	s.dev_balance("FOIL_SPREAD", 0.4)
	s.build(s.human(), "probe")  # 保存未结束回合里的操作
	show_state(s)
	var path := "user://_test_save.forest"
	check_eq(view.saves.save_file(path), OK, "普通对局可以保存")
	check_eq(view.saves.save_file(path), OK, "可以安全覆盖同名存档")
	var expected := s.checksum()
	show_state(GameState.new_game(2))
	await view.saves.load_file(path)
	check_eq(view.state.checksum(), expected, "读取恢复保存回合和回合内操作")
	check_eq(Balance.FOIL_SPREAD, 0.4, "读取恢复当时的数值")
	check(not view.debug.replaying(), "读档后能继续操作")
	view.state.end_turn()
	s.end_turn()
	check_eq(view.state.checksum(), s.checksum(), "读取后下一回合仍与原局一致")
	var kept = view.state
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = f.get_var()
	f.close()
	data["checksum"] += 1
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	await view.saves.load_file(path)
	check(view.state == kept, "校验不一致保留原对局")
	check_eq(Balance.FOIL_SPREAD, 0.4, "失败不会改变原对局数值")
	data["replay"]["commands"].append({"step": 1, "civ": 0, "ai": false, "name": "free", "args": []})
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_var(data)
	f.close()
	await view.saves.load_file(path)
	check(view.state == kept, "损坏文件不能执行非玩家操作")
	# 强制分帧，在重建期间取消，检查既不替换状态也不污染数值。
	show_state(s)
	view.saves.save_file(path)
	show_state(GameState.new_game(3))
	kept = view.state
	Balance.apply(defaults)
	view.saves.slice_msec = 0
	view.saves.load_file(path)
	check(view.saves.busy, "长读档显示进度并让出界面")
	view.saves.cancel()
	await process_frame
	check(view.state == kept and not view.saves.busy, "取消读档后保留原对局")
	check_eq(Balance.values(), defaults, "取消恢复读档前的数值")
	view.saves.slice_msec = 50
	DirAccess.remove_absolute(path)


func test_game_shortcuts_and_compact_layout() -> void:
	show_state(GameState.new_game(1))
	map.reset_view(true)
	view.debug.view_idx = 0
	var key := InputEventKey.new()
	key.pressed = true
	key.alt_pressed = true
	key.keycode = KEY_1
	view._on_key(key, root)
	check(view.tech_tree.visible, "Alt+1 打开全屏科技树")
	view.tech_tree.close_tree()
	key.keycode = KEY_RIGHT
	view._on_key(key, root)
	check_eq(panel._tabs.current_tab, 2, "选择行动快捷键打开行动页")
	var action_before: int = actions._action
	key.keycode = KEY_LEFT
	view._on_key(key, root)
	check(actions._action != action_before, "左右快捷键切换行动")
	key.alt_pressed = false
	key.ctrl_pressed = true
	key.keycode = KEY_B
	view._on_key(key, root)
	check(not panel.visible and view.panel_width() == 0.0, "Ctrl+B 收起面板并释放地图宽度")
	check_eq(map._camera.h_offset, 0.0, "收起面板后镜头居中")
	view._on_key(key, root)
	check(panel.visible and view.panel_width() > 0.0, "再次按键展开面板")
	panel._build_tiles["probe"].pressed.emit()
	for i in int(ceilf(Construction.work("probe"))):
		panel._end.pressed.emit()
	view.refresh()
	key.keycode = KEY_ENTER
	view._on_key(key, root)
	check(not view.state.human().ships[0].docked, "Ctrl+Enter 通过规则执行所选行动")
	key.ctrl_pressed = false
	key.shift_pressed = true
	var step: int = view.state.steps
	view._on_key(key, root)
	check_eq(view.state.steps, step + 1, "Shift+Enter 结束回合")
	key.ctrl_pressed = true
	key.shift_pressed = false
	key.keycode = KEY_B
	var edit: LineEdit = actions._coord_boxes[0].get_line_edit()
	edit.grab_focus()
	view._on_key(key, root)
	check(panel.visible, "在输入框里不抢操作快捷键")
	edit.release_focus()
	var old_size := root.size
	root.size = Vector2i(600, 900)
	view.window_settings._responsive_size()
	await process_frame
	view.update_layout()
	check(view.compact and not panel.visible, "竖屏自动收起面板")
	check(map._aim.is_empty(), "竖屏自动收起面板时也清除隐藏行动的预览")
	await capture("portrait_map")
	view.show_panel(2)
	await process_frame
	check(panel.get_global_rect().end.x <= root.get_visible_rect().size.x + 1, "竖屏面板在窗口以内")
	check(not overlay._top.visible, "展开面板时隐藏会重叠的地图工具")
	await capture("portrait_panel")
	root.size = old_size
	if _output != "":
		root.size = Vector2i(1280, 800)
	view.window_settings._responsive_size()
	await process_frame
	view.update_layout()
	view.show_panel(2)
	await capture("game_controls")


func test_save_across_dimensions() -> void:
	var s := GameState.new_game(1, 1)
	s.set_autoplay(s.civs[1], false)
	for c in s.civs:
		s.dev_set(c, "energy", 10000)
		s.dev_set(c, "mineral", 10000)
		s.dev_tech(c, "dimension", true)
		s.dev_set(c, "dimension_ammo", 3)
		check_eq(s.start_reduce(c)["error"],"","可回放操作冻结第一阶段迁维名册")
	for i in 6:
		s.end_turn()
	var near:=s.human().home+Vector3i(1 if s.human().home.x<8 else -1,0,0)
	var fired:=s.launch_foil(s.human(),near)
	check_eq(fired["error"],"","通过记录里的正式行动发射载荷")
	if fired["error"]!="":
		return
	for i in 7:
		s.end_turn()
	for dim in [3, 2, 1]:
		if dim != 3:
			for i in 100:
				if s.dimension==dim or s.is_over():
					break
				s.end_turn()
		check_eq(s.dimension,dim,"保存展开中、二维、一维的实际局面")
		check(not s.is_over(),"各文明提前收到自动迁维准备，可存续到下一阶段")
		show_state(s)
		var expected:=s.checksum()
		var path:="user://_test_dimension_save.forest"
		check_eq(view.saves.save_file(path),OK,"降维中或完成后可以保存")
		await view.saves.load_file(path)
		check_eq(view.state.checksum(),expected,"有限传播、准备收据和换图全部可回放")
		check_eq(view.state.foil_zones,s.foil_zones,"前沿历史和半格半径完整恢复")
		DirAccess.remove_absolute(path)
		s=view.state
		if dim==2:
			for c in s.civs:
				check_eq(s.start_reduce(c)["error"],"","二维冻结下一阶段迁维名册")
			for i in 6:
				s.end_turn()
			near=s.human().home+Vector3i(1 if s.human().home.x<26 else -1,0,0)
			check_eq(s.launch_line_foil(s.human(),near)["error"],"","二维正式发射单向著")


func test_panel_layout() -> void:
	# 固定种子：随机开局里约一成的局一开始就看得到邻居（I 级马上开放），下面的检查就不成立了
	show_state(GameState.new_game(1))
	check(not view.state.human().discovered, "种子 1 开局还没发现别人（不成立就换一个种子）")
	check(panel._tabs.get_tab_count() == 4, "面板有科技、建造、行动、情况四页")
	check(view.tech_tree.tiles.size() == Tech.ALL.size(), "每项科技一个按钮")
	check(panel._build_tiles.size() == panel.BUILD_ORDER.size() + 1, "每种建造一个按钮，外加自身降维")
	check(overlay._status.text.contains("第 1 回合"), "状态栏显示回合")
	var me: Civ = view.state.human()
	view.tech_tree.select_tech("probe")
	check(view.tech_tree._research.disabled, "已有科技不能重复研究")
	view.tech_tree.select_tech("dyson")
	check(view.tech_tree._research.disabled, "没开放的科技不能研究")
	check(not overlay._legend.visible and not overlay.show_vision.button_pressed, "开局收起图例和全体视野")
	check(panel._tier_labels[1].text.contains("未开放"), "I 级开局未开放")
	check(not panel._build_tiles["probe"].disabled, "开局可以造探测器")
	check(panel._build_tiles["warship"].disabled, "没有战舰科技不能造战舰")
	check(panel._res_values["actions"].text.begins_with(str(me.actions_left)), "显示行动点")


## 换到哪一页，右侧面板都不会被长文字撑宽（科技页的开放条件要折行）。
func test_panel_width() -> void:
	var width: float = panel.size.x
	var shown: int = panel._tabs.current_tab
	for tab in panel._tabs.get_tab_count():
		panel._tabs.current_tab = tab
		await process_frame
		check(panel.get_combined_minimum_size().x <= width + 0.5,
				"第 %d 页不把面板撑宽（最小 %.0f，面板 %.0f）" % [tab, panel.get_combined_minimum_size().x, width])
	panel._tabs.current_tab = shown
	# 方块按钮的高度跟着里面的字走，字不超出边框
	var tiles: Array = actions._action_tiles.values() + panel._upgrade_tiles.values() \
			+ panel._build_tiles.values()
	var fits := true
	for tile: Button in tiles:
		fits = fits and tile.get_combined_minimum_size().y >= tile.get_child(0).get_combined_minimum_size().y
	check(fits, "方块按钮装得下里面的图标、名字和花费")


## 悬停说明限宽换行；行动说明不占面板，放在悬停说明里；界面大小有上下限。
func test_ui_helpers() -> void:
	var tile: Button = actions._action_tiles[actions.Action.DISPATCH]
	check(tile.get_script() == view.Tip, "面板里的按钮挂上了限宽的悬停说明")
	check(tile.get_meta("cost") is Label, "挂脚本后按钮原有的数据还在")
	var long_text := "选一个单位。".repeat(20) + "\n\n现在不能用：" + "没有单位".repeat(10)
	var font := tile.get_theme_font("font", "TooltipLabel")
	var font_size := tile.get_theme_font_size("font_size", "TooltipLabel")
	var lines: PackedStringArray = view.Tip.wrap_lines(long_text, font, font_size, view.Tip.MAX_WIDTH)
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	check(widest <= view.Tip.MAX_WIDTH + 1.0, "长说明断成不超过最大宽度的行")
	check("".join(lines) == long_text.replace("\n", ""), "断行不丢字")
	check(lines.size() > 4, "长说明确实断成了多行")
	var tip: PanelContainer = view.Tip.make(tile, "短说明")
	check((tip.get_child(0) as Label).text == "短说明", "短说明不断行")
	tip.free()
	tip = view.Tip.make(tile, "")
	check(not tip.visible, "没有说明文字的地方不弹空框")
	tip.free()
	check(actions._go.tooltip_text == actions._action_specs()[actions._action][2], "行动说明在执行按钮的悬停说明里")
	check(view.get_window().title == view.WINDOW_TITLE, "窗口标题是游戏名，不是项目名")
	view.window_settings.apply_ui_scale(5.0)
	check(is_equal_approx(view.window_settings.ui_scale, view.window_settings.UI_SCALE_MAX), "界面大小有上限")
	view.window_settings.apply_ui_scale(1.0)


func test_research() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	view.tech_tree.select_tech("gravity_scan")
	view.tech_tree._research.pressed.emit()
	check(not me.has_tech("gravity_scan"), "I 级权限没开放时按钮不起作用")
	view.tech_tree.select_tech("warship")
	check(not view.tech_tree._research.disabled, "005属于0级，从开局就能付费研究")
	var energy := me.energy
	var ap := me.actions_left
	view.tech_tree.select_tech("warship")
	view.tech_tree._research.pressed.emit()
	check(not me.has_tech("warship") and me.energy == energy - Tech.cost("warship")[0], "按钮提交研究并全额托管资源，不能立即获科技")
	check_eq(me.actions_left, ap-1, "研究消耗1行动点")
	view.tech_tree.select_tech("fusion")
	check(view.tech_tree._research.disabled,"全局只有一条研究队列")
	for i in int(ceilf(Tech.work("warship"))):
		panel._end.pressed.emit()
	view.tech_tree.select_tech("warship")
	check(me.has_tech("warship"),"工作量完成且回报收到后取得科技")
	check(view.tech_tree._research.disabled and view.tech_tree.tiles["warship"].text.contains("已有"),
			"升级后显示已有")
	view.tech_tree.select_tech("beam")
	check(not view.tech_tree._research.disabled, "研究战舰后同级武器解除前置锁定")
	me.is_ai = true
	view.refresh()
	check(view.tech_tree._research.disabled, "AI 视角不能从科技树研究")
	me.is_ai = false
	view.refresh()
	var actions := me.actions_left
	panel._upgrade_tiles["telescope"].pressed.emit()
	check(me.telescope == 0 and me.actions_left == actions-1, "望远镜升级消耗1行动点并等待工程完成")
	for i in int(ceilf(Balance.TELESCOPE_UPGRADE_WORK[0])):
		panel._end.pressed.emit()
	check_eq(me.telescope,1,"望远镜完成回报到达后增加一级")


func test_build_and_dispatch() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	panel._build_tiles["probe"].pressed.emit()
	check(me.count(Ship.PROBE) == 0 and me.pending.size()==1, "建造按钮提交有工时的探测器订单")
	for i in int(Construction.work("probe")):
		panel._end.pressed.emit()
	check(me.count(Ship.PROBE) == 1, "完成工程并收到回报后出现探测器")
	check(actions._action == actions.Action.DISPATCH and actions._unit_pick.item_count == 1, "造好后行动页选中这个单位")
	var probe: Ship = me.ships[0]
	check(actions._selected_unit() == probe and actions._slow.visible, "停着的探测器可以选慢速出发")
	actions.aim_at(Vector3i(5, 0, 0))
	check(not actions._go.disabled and actions._go.text.contains("派出"), "执行按钮是「派出」")
	actions._go.pressed.emit()
	check(not probe.docked and probe.direction.is_equal_approx(Vector3(1, 0, 0)), "按钮把探测器朝选的方向派出")
	panel._end.pressed.emit()
	check(probe.pos.x > 0.0, "结束回合后探测器飞了一段")
	check(map._markers.get_child_count() > 0, "星图上画了标记")


func test_v01_completed_build_selection_waits_for_receipt() -> void:
	var s:=fixture()
	var me:=s.human()
	var at:=Vector3i(4,0,0)
	me.colonies.append(at)
	s.map.stars[at]=StarMap.Star.SINGLE
	s.system_cells.append(at)
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,at)
	Signals.advance(s,4.0)
	s.clock=4.0
	Signals.receive_due(s)
	show_state(s)
	var existing:=Ship.make(Ship.COLONY,Vector3(me.home),s.next_id())
	me.ships.append(existing)
	actions.select_unit(existing)
	view.refresh()
	panel._origin_pick.select(1)
	panel._build_tiles["probe"].pressed.emit()
	Signals.advance(s,4.0)
	s.clock=8.0
	Signals.receive_due(s)
	WorkOrder.advance(me.pending[0],100.0)
	s._finish_pending(me,0.0)
	view.refresh()
	check(panel._build_tiles["probe"].disabled,"远端真实完工未回报前，建造按钮仍等待确认")
	check(actions._selected_unit()!=null and actions._selected_unit().id==existing.id,"远端真实完工未回报时保留现有选择")
	Signals.advance(s,4.0)
	s.clock=12.0
	Signals.receive_due(s)
	view.refresh()
	check(not panel._build_tiles["probe"].disabled,"收到远端完工报告后建造按钮恢复")
	check(actions._selected_unit()!=null and actions._selected_unit().id==me.ships[-1].id,"完工及单位遥测到达后保留原交互的自动选中新单位")
	check_eq(actions._action,actions.Action.DISPATCH,"收到新探测器后自动选中派出操作")


func test_colony() -> void:
	var s := fixture()
	var me := s.human()
	me.techs["colony"] = true
	me.techs["interstellar_travel"] = true
	var c := Vector3i(3, 0, 0)
	s.map.stars[c] = StarMap.Star.SINGLE
	s.map.rocky[c] = 1
	s.map.habitable[c] = true
	s.system_cells.append(c)
	var unseen := Vector3i(6, 6, 0)
	s.map.stars[unseen] = StarMap.Star.SINGLE
	s.map.habitable[unseen] = true
	s.system_cells.append(unseen)
	me.intel[c] = s.snapshot(c)
	show_state(s)
	panel._build_tiles["colony"].pressed.emit()
	for i in int(ceilf(Construction.work("colony"))):
		panel._end.pressed.emit()
	check(actions._action == actions.Action.COLONY and actions._target_box.visible, "造好殖民船后切到殖民，要选目标")
	check(map._colony_targets(me).has(c), "看到过的宜居星系列为殖民目标")
	check(not map._colony_targets(me).has(unseen), "没看到过的宜居星系不画（F4.4）")
	check(_pickable_at(unseen).is_empty(), "没看到过的宜居星系指不中，也就不泄露")
	actions.aim_at(unseen)
	check(not actions._go.disabled, "没看到过的格子也能盲飞")
	actions.aim_at(c)
	check(actions._target_cell() == c and not actions._go.disabled, "点宜居星系当目的地")
	actions._go.pressed.emit()
	var ship := me.ships[0]
	check(ship.has_target and Vector3i(ship.target) == c, "殖民船出发去目的地")
	for i in 80:
		var reported:=Signals.reported_ship(s,me,ship.id)
		if reported!=null and reported.cell()==c and reported.waiting():
			break
		panel._end.pressed.emit()
	check(ship.cell()==c and ship.waiting() and not me.owns(c), "运输船到达后待命，尚未付费落地")
	actions._action_tiles[actions.Action.LANDING].pressed.emit()
	check(not actions._go.disabled,"收到待命遥测后可通过原行动页付费落地")
	var resources:=[me.energy,me.mineral]
	actions._go.pressed.emit()
	check_eq([me.energy,me.mineral],[resources[0]-3,resources[1]-4],"落地按钮按109工程报价托管3E和4M")
	for i in 14:
		if Knowledge.colonies(s,me).has(c):
			break
		panel._end.pressed.emit()
	check(me.owns(c) and me.ship_by_id(ship.id)==null, "落地工程完工消耗运输船并建立锚点")
	check(panel._origin_pick.item_count == 2, "新星系出现在发射源列表里")
	# 别人悄悄占了的宜居星系：规则允许当目的地，画面也不能拦，免得提示泄露谁占了哪里
	var other: Civ = s.civs[1]
	s.map.habitable[other.home] = true
	panel._origin_pick.select(0)
	panel._build_tiles["colony"].pressed.emit()
	for i in int(ceilf(Construction.work("colony"))):
		panel._end.pressed.emit()
	actions.aim_at(other.home)
	check(actions._target_cell() == other.home and not actions._go.disabled, "别人悄悄占了的宜居星系也能选，画面不泄露")
	me.techs["starship"] = true
	panel._build_tiles["starship"].pressed.emit()
	for i in int(ceilf(Construction.work("starship"))):
		panel._end.pressed.emit()
	actions._action_tiles[actions.Action.STARSHIP].pressed.emit()
	actions.aim_at(other.home)
	check(actions._target_cell() == other.home and not actions._go.disabled, "星舰的目的地也不泄露别人悄悄占着哪里")
	me.known[other.home] = s.turn
	view.refresh()
	check(actions._go.disabled and actions._go_hint.text.contains("已知的敌方星系"), "已知的敌方星系不能当星舰的目的地")
	me.known.erase(other.home)


## F4.1：视角可以平移、旋转、缩放，H 回到母星，V 重置；拖动和按键都只改目标，相机平滑追上。
func test_camera() -> void:
	var s := fixture()
	show_state(s)
	map.reset_view(true)
	var center: Vector3 = map._focus
	map._pan(100.0, 0.0)
	check(map._goal_focus.distance_to(center) > 0.1, "平移改变视角中心")
	map._pan(1e6, 1e6)
	check(map._goal_focus == map._clamp_focus(map._goal_focus), "视角中心不会移出星图太远")
	map._zoom(0.0)
	check(map._goal_distance == map.CAM_MIN_DISTANCE, "拉近有下限")
	map._turn(0.0, -500.0)
	check(map._goal_pitch >= -89.0, "俯仰角有上下限")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_H
	check(map._camera_key(key), "H 是视角键")
	check(map._goal_focus.is_equal_approx(Vector3(s.human().home)), "H 回到母星")
	key.physical_keycode = KEY_V
	map._camera_key(key)
	check(map._goal_focus.is_equal_approx(center) and map._goal_distance == map.CAM_DISTANCE, "V 重置视角")
	map._process(10.0)
	check(map._focus.is_equal_approx(center), "相机追上目标")
	key.physical_keycode = KEY_J
	check(not map._camera_key(key), "别的键不归星图管")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(100, 100)
	map._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(150, 120)
	var yaw: float = map._goal_yaw
	map._unhandled_input(motion)
	check(is_equal_approx(map._goal_yaw, yaw - 15.0), "没有 relative 位移的原生拖动事件也能旋转")
	press.pressed = false
	press.position = motion.position
	map._unhandled_input(press)
	check(map._drag_button == MOUSE_BUTTON_NONE, "松开鼠标结束旋转")


## 只有星图上画出来的东西点得中；选中圈贴着东西的轮廓，东西小圈也小，不闪；点到空处、换局面时取消。
func test_selection() -> void:
	var s := fixture()
	show_state(s)
	var me := s.human()
	var c := me.home
	var find := func(key: String) -> Dictionary:
		for o in map._pickables():
			if o["key"] == key:
				return o
		return {}
	var home: Dictionary = find.call("c%s" % c)
	check(not home.is_empty() and is_equal_approx(home["r"], 0.35 * 1.4), "母星系点得中，大小和画出来的方块轮廓一样")
	var hidden_system: Vector3i = map.NO_CELL
	for sc in s.system_cells:
		if s.map.star_at(sc) != StarMap.Star.NONE and not me.intel.has(sc) and not me.owns(sc) and not me.known.has(sc):
			hidden_system = sc
			break
	check(hidden_system != map.NO_CELL and (find.call("c%s" % hidden_system) as Dictionary).is_empty(), "没看到过的星系点不中")
	map.focus_on(Vector3(c))
	map._snap_camera()
	var screen: Vector2 = map._camera.unproject_position(map._world.to_global(map._warp_point(Vector3(c))))
	check((map._pick_object(screen) as Dictionary).get("key", "") == home["key"], "点在母星系上就点中它")
	check((map._pick_object(Vector2(3, 3)) as Dictionary).is_empty(), "点在空处什么也不选")
	map.select_object(home)
	check(map.selected_cell() == c and map._selection.visible and map._selection_ring != null, "选中画出圆圈")
	var ring := map._selection_ring.mesh as TorusMesh
	check(is_equal_approx(ring.inner_radius, home["r"] + map.OUTLINE_GAP), "圆圈贴着轮廓")
	check(map._selection_label.text == map._cell_info(c), "下面写着坐标和情报")
	map._process(0.5)
	check(map._selection.scale == Vector3.ONE, "圆圈不闪也不变大小")
	me.sightings.append({"pos": Vector3(c) + Vector3(2.3, 0.2, 0), "kind": Ship.WARSHIP, "turn": s.turn})
	view.refresh()
	check(map._selected_key() == home["key"] and map._selection.visible, "刷新以后还选着")
	var ship: Dictionary = find.call("v%s%d" % [Vector3(c) + Vector3(2.3, 0.2, 0), s.turn])
	map.select_object(ship)
	check((map._selection_ring.mesh as TorusMesh).inner_radius < ring.inner_radius, "小东西的圈也小")
	map._set_hover(ship)
	check(not map._cursor_label.visible and map._cursor_ring != null, "鼠标指着选中的东西时不重复写信息")
	map._set_hover({})
	check(map._cursor_ring == null and not map._cursor.visible, "指着空处什么都不画")
	me.sightings.clear()
	view.refresh()
	check(map.selected.is_empty() and not map._selection.visible, "选中的东西不在星图上了，取消选中")
	map.select_object(home)
	map.redraw_grid()
	check(map.selected.is_empty(), "换局面时取消选中")

## F4.2：网格四种画法，G 键轮换；视野内的点亮一些。
func test_grid_modes() -> void:
	var s := fixture()
	show_state(s)
	var old: int = map.grid_mode
	map.set_grid_mode(map.Grid.DOTS)
	check(map._dots.visible and map._dots.multimesh.instance_count == StarMap.SIZE ** 3, "点阵：每格一个点")
	check(map._grid.mesh.get_surface_count() == 0, "点阵模式不画网格线")
	# 不带窗口跑时读不回点的颜色，直接检查用来选颜色的判断
	check(map._in_eyes(Vector3(1, 0, 0)) and not map._in_eyes(Vector3(5, 5, 5)), "按自己的视野分出视野内外，视野内的点亮一些")
	map.set_grid_mode(map.Grid.VISION_LINES)
	check(not map._dots.visible and map._grid.mesh.get_surface_count() == 1, "视野内网格线：有线，没有点")
	var vision_lines: int = map._grid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	map.set_grid_mode(map.Grid.ALL_LINES)
	check(map._grid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > vision_lines, "完整网格线比视野内的多")
	check(overlay._grid_pick.get_selected_id() == map.Grid.ALL_LINES, "图例旁的网格菜单跟着变")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_G
	map._camera_key(key)
	check(map.grid_mode == map.Grid.DOTS, "G 轮换到下一种")
	map.set_grid_mode(old)


## F4.3：在飞的单位画出航线：下一回合的实线、之后几个回合的落点、通到目的地的虚线、身后的轨迹。
func test_ship_paths() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	panel._build_tiles["probe"].pressed.emit()
	for i in int(ceilf(Construction.work("probe"))):
		panel._end.pressed.emit()
	var probe: Ship = me.ships[-1]
	s.dispatch(me, probe.id, Vector3(1, 0, 0))
	view.refresh()
	for obj in map._pickables():
		if obj["key"] == "s%d" % probe.id:
			map.select_object(obj)
	var points: Array[Vector3] = s.predict_path(me, probe, map.PATH_TURNS)
	check(points.size() == map.PATH_TURNS + 1 and points[1].x > points[0].x, "预测接下来几个回合的位置")
	var tubes: int = map._tube_parts.size()
	check(tubes >= map.PATH_TURNS, "航线画成粗线")
	panel._end.pressed.emit()
	panel._end.pressed.emit()
	check_eq(map._trails[probe.id].size(),2,"两年后只能收到第一年位置，第二年遥测尚在回程")
	check_eq(map._trails[probe.id][-1],Signals.reported_ship(s,me,probe.id).pos,"轨迹末端来自已收遥测")
	check((map._trails[probe.id][-1] as Vector3).distance_to(probe.pos)>Balance.COLLISION_EPSILON,"地图没有提前追上远端真实位置")
	check(map._tube_parts.size() > tubes, "身后的轨迹也画出来")


## 星图上画出来、鼠标能指中的 c 格里的东西（没有就是空的字典）。
func _pickable_at(c: Vector3i) -> Dictionary:
	for o in map._pickables():
		if o["cell"] == c:
			return o
	return {}


func test_hover_intel() -> void:
	var s := fixture()
	var me := s.human()
	var c := Vector3i(8, 8, 8)
	s.map.stars[c] = StarMap.Star.SINGLE
	me.intel[c] = s.snapshot(c)
	me.known[c] = 1
	show_state(s)
	map._set_hover(_pickable_at(c))
	var text: String = map._cursor_label.text
	check(text.contains("第 1 回合看到") and text.contains("属于 Other"), "鼠标停在格子上显示情报")
	for i in 10:
		panel._end.pressed.emit()
	map._set_hover({})
	map._set_hover(_pickable_at(c))
	check(map._cursor_label.text.contains("10 回合前") and map._cursor_label.modulate.a < 1.0, "旧情报写明多久以前，字变淡")


## 规则：界面和操作，光粒
## 光粒库存按有无记录，不能像戴森球、采矿船一样直接和整数比较。
func test_hover_stored_grain() -> void:
	var s := fixture()
	var me := s.human()
	me.dysons[me.home] = 2
	me.miners[me.home] = 3
	show_state(s)
	map._set_hover(_pickable_at(me.home))
	check(not map._cursor_label.text.contains("光粒"), "无库存时不显示光粒")
	me.grains[me.home] = true
	var checksum := s.checksum()
	view.refresh()
	var text: String = map._cursor_label.text
	check(text.contains("光粒 ×1"), "有库存时悬停显示一颗光粒")
	check(text.contains("戴森球 ×2") and text.contains("采矿船 ×3"), "计数设施仍显示真实数量")
	map.select_object(_pickable_at(me.home))
	check(map._selection_label.text.contains("光粒 ×1"), "选择同一星系也能显示光粒库存")
	check_eq(s.checksum(), checksum, "悬停与选择不改变库存或对局状态")
	await capture("hover-stored-grain")
	me.grains.erase(me.home)
	view.refresh()
	check(not map._cursor_label.text.contains("光粒") and not map._selection_label.text.contains("光粒"), "库存用掉后刷新移除悬停与选择提示中的光粒")
	map._set_hover({})
	map.select_object({})


func test_sightings_drawn() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	# 刷新时旧标记要等到这一帧结束才真的删掉
	await process_frame
	var before: int = map._markers.get_child_count()
	me.sightings.append({"pos": Vector3(4, 4, 4), "kind": Ship.WARSHIP, "turn": s.turn})
	me.hit_dirs.append({"at": Vector3i.ZERO, "dir": Vector3(1, 0, 0), "turn": s.turn})
	me.wake_reports[1234]={
		0:{"data":{"pos":Vector3(5,5,5),"turn":s.turn}},
		1:{"data":{"pos":Vector3(6,5,5),"turn":s.turn}}}
	me.heard[Vector3i(8, 8, 8)] = s.turn
	view.refresh()
	await process_frame
	check(map._markers.get_child_count() >= before + 2 and not map._tube_parts.is_empty(), "航迹、打击方向、听到的广播都画出来")


## G14：光速变慢的格子画成半透明方块，光速为 0 的中心加边框；鼠标停在上面写出光速。
func test_black_domain_drawn() -> void:
	var s := fixture()
	show_state(s)
	await process_frame
	var before: int = map._markers.get_child_count()
	s._ensure_light()
	for c in [Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i.ZERO]:
		s.set_light_at(c, 0.5)
	s.set_light_at(Vector3i(2, 0, 0), 0.0)
	# 使用已收环境快照；隐藏的真实场不能直接进入普通地图。
	for c in [Vector3i(2,0,0),Vector3i(3,0,0)]:
		s.human().intel[c]=s.snapshot(c)
	view.refresh()
	await process_frame
	check(map._markers.get_child_count() == before + 2, "黑域的格子和中心的边框都画出来")
	var cubes := 0
	for node in map._markers.get_children():
		if node is MultiMeshInstance3D and node.multimesh.mesh is BoxMesh and node.multimesh.mesh.size == Vector3.ONE:
			cubes = node.multimesh.instance_count
	check(cubes == 3, "光速低于 %.2f 的三格都画了方块" % Balance.GRAIN_MIN_LIGHT)
	map._set_hover(_pickable_at(Vector3i.ZERO))
	check(map._cursor_label.text.contains("光速 0.50"), "鼠标停在黑域里的星系上写出光速")
	map._set_hover({})


func test_intel_on_starless_system() -> void:
	# 看到过的星系后来恒星被打光了：仍按情报画，画面不能出错
	var s := fixture()
	var me := s.human()
	var c := Vector3i(8, 8, 8)
	s.map.stars[c] = StarMap.Star.DOUBLE
	me.intel[c] = s.snapshot(c)
	show_state(s)
	await process_frame
	var before: int = map._markers.get_child_count()
	s.map.stars[c] = StarMap.Star.NONE
	view.refresh()
	await process_frame
	check(map._markers.get_child_count() == before, "情报里的星系现在没有恒星了，星图照样画完")


func test_reduction_controls() -> void:
	var s:=fixture()
	var me:=s.human()
	me.techs["dimension"]=true
	s.map.rocky[me.home]=1
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	show_state(s)
	check(panel._reduce_info.text.contains("携带 1 项") and panel._reduce_info.text.contains("15E / 10M"),"初始锚点名册和双资源报价可见")
	panel._build_tiles["miner"].pressed.emit()
	check(not panel._build_tiles["reduce"].disabled,"母星首槽忙时第二槽仍可进行迁维准备")
	for i in int(ceilf(Construction.work("miner"))):
		panel._end.pressed.emit()
	check(not panel._build_tiles["reduce"].disabled,"矿船完成后可开迁维工程")
	check(panel._reduce_info.text.contains("携带 2 项") and panel._reduce_info.text.contains("18E / 12M"),"已知新矿船纳入可选名册，报价同步")
	var quote: Dictionary=panel.advanced.quote()
	var roster: Array=panel.advanced.roster().duplicate()
	var stock:=[me.energy,me.mineral]
	var ap:=me.actions_left
	panel._build_tiles["reduce"].pressed.emit()
	check_eq([me.energy,me.mineral],[stock[0]-quote["cost"][0],stock[1]-quote["cost"][1]],"按展示报价全额托管准备费")
	check_eq(me.actions_left,ap-1,"准备消耗1AP")
	var id: int=me.conversions.keys()[0]
	check_eq(me.conversions[id]["roster"],roster,"计划冻结当时名册")
	check(panel.advanced._execute.disabled and not panel._build_tiles["probe"].disabled,"准备回执尚未收到时不能执行，母星另一个槽仍可建造")
	for i in int(ceilf(quote["work"])):
		panel._end.pressed.emit()
	check_eq(me.conversions[id]["ready_at"].size(),2,"当地锚点和矿船均收到准备，回执已回传")
	check_eq(Assets.dimension(me,"anchor",me.home),3,"准备完成没有擅自执行实体转换")
	check(not panel.advanced._execute.disabled,"收到回执后原建造页可点击执行")
	stock=[me.energy,me.mineral]
	panel.advanced._execute.pressed.emit()
	check_eq(Assets.dimension(me,"anchor",me.home),2,"执行按钮转换已准备锚点")
	check_eq(Assets.dimension(me,"miner",me.home),2,"同一冻结名册中的矿船分别转换")
	check_eq([me.energy_millis,me.mineral_millis],[floori(WorkOrder.units(stock[0])*0.75),floori(WorkOrder.units(stock[1])*0.75)],"首次实际转换只扣一次库存损耗")
	check_eq(s.dimension,3,"实体适配与世界换图是两件事")
	check(not panel._build_tiles["probe"].disabled,"完成后宿主建造队列恢复")
	await process_frame


## 规则：二维、单向著和奇异点
## 正式稿第24–25页：原目的地选择接入对照预览，实体ready显示不读实际舰上状态。
func test_v01_navigation_preview_and_ready_display() -> void:
	if view.get("migration_preview")==null or panel.advanced.get("_preview_go")==null:
		check(false,"迁维地图预览入口尚未实现")
		return
	var s:=fixture()
	var me:=s.human()
	var ship:=Ship.make(Ship.STARSHIP,Vector3(me.home),s.next_id())
	me.ships.append(ship)
	show_state(s)
	actions.select_unit(ship)
	view.refresh()
	actions.aim_at(Vector3i(8,8,8))
	actions._target_info.pressed.emit()
	await process_frame
	var preview=view.migration_preview
	check(preview.visible,"点击原目的地位置打开对照预览")
	check(preview._current.text.contains("格距") and preview._current.text.contains("ETA"),"预览明确显示物理格距与目的地ETA")
	check(preview._current.text.contains("1 ly/格") and preview._next.text.contains("0.5 ly/格"),"当前和下一维并排显示")
	check(preview._ranges.text.contains("0.1 ly") and preview._anchors.text.contains("#"),"预览列出武器射程与已知锚点")
	await capture("migration-preview-3d")
	preview.close_preview()
	check(not preview.visible,"返回关闭预览，恢复原星图操作")
	me.techs["dimension"]=true
	var local_id:=Signals.controller(me)
	me.conversions[100]={"id":100,"roster":[local_id,ship.id],"host":local_id,"from_dim":3,"ready_at":{local_id:7.0},"status":"preparing","ready_reports":{local_id:{"t_observed":7.0,"t_received":7.0,"epoch":0}}}
	ship.ready["3>2"]={"at":8.0,"plan":100}
	view.refresh()
	var ready_text: String=panel.advanced._ready.text
	check(ready_text.contains("7 年") and ready_text.contains("待确认"),"每项分别显示已确认ready时间或待确认")
	me.conversions[100]["status"]="destroyed"
	view.refresh()
	check_eq(panel.advanced._ready.text,ready_text,"未收到的准备状态变化不改变界面")


## 正式稿第10–12页：图示、网格和观测使用同一个完整张角，按物理格距换算。
func test_v01_probe_vision_matches_received_rules() -> void:
	var s:=fixture()
	var me:=s.human()
	var probe:=Ship.make(Ship.PROBE,Vector3(5,4,4),s.next_id())
	probe.docked=false
	probe.direction=Vector3.RIGHT
	me.ships.append(probe)
	me.telemetry[probe.id]={"data":Signals.ship_status(probe),"t_observed":0.0,"t_received":5.0,"epoch":0}
	show_state(s)
	await process_frame
	map.refresh(me,{},true,false)
	var cone: MeshInstance3D
	for child in map._markers.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and child.mesh.top_radius<=0.001:
			cone=child
			break
	check(cone!=null,"绘制探测器圆锥")
	if cone!=null:
		check(absf(cone.mesh.bottom_radius-(tan(deg_to_rad(7.5))+Balance.COLLISION_EPSILON))<1e-6,"显示15度全张角，不额外膨胀半格")
	check(not map._in_eyes(Vector3(6,4.3,4)),"锥外格点不因旧公式变为可观测")
	check(map._in_eyes(Vector3(6,4.1,4)),"锥内格点按实际规则高亮")
	probe.pos=Vector3(7,7,7)
	map.refresh(me,{},true,false)
	var eyes: Array=map._grid_eyes.filter(func(o):return o.get("id",-1)==probe.id)
	check_eq(eyes.size(),1,"图示使用有永久ID的实际观测器定义")
	if eyes.size()==1:
		check_eq(eyes[0]["pos"],Vector3(5,4,4),"图示位置只使用收到的遥测")
	for kind in [Ship.NUCLEAR_PROBE,Ship.DROPLET]:
		me.telemetry[probe.id]["data"]["kind"]=kind
		map.refresh(me,{},true,false)
		var cones:=0
		for child in map._markers.get_children():
			if child is MeshInstance3D and child.get_meta("vision_observer",-1)==probe.id and child.mesh is CylinderMesh:
				cones+=1
		check_eq(cones,1,"新增%s应有方向圆锥，不能显示成球体"%Ship.NAMES[kind])
	await process_frame
	await capture("probe-vision-15-degrees")


## 正式稿第12、24页：低维图示把ly转换为格，一维望远镜升级保留后向视野。
func test_v01_probe_vision_physical_scale_in_lower_dimensions() -> void:
	var s:=fixture()
	var me:=s.human()
	me.telescope=2
	var probe:=Ship.make(Ship.NUCLEAR_PROBE,Vector3(5,4,4),s.next_id())
	probe.docked=false
	probe.direction=Vector3.RIGHT
	me.ships.append(probe)
	me.telemetry[probe.id]={"data":Signals.ship_status(probe),"t_observed":0.0,"t_received":5.0,"epoch":0}
	s.fold_anchor=Vector3i.ZERO
	DimensionSpace.commit(s,false)
	show_state(s)
	map.refresh(me,{},true,false)
	var shapes: Array=map._markers.get_children().filter(func(child):return child.get_meta("vision_observer",-1)==probe.id)
	check_eq(shapes.size(),1,"二维有一份探测图示")
	if shapes.size()==1:
		check(shapes[0].mesh is ImmediateMesh,"二维绘制平面方向范围")
	var eyes: Array=map._grid_eyes.filter(func(o):return o["id"]==probe.id)
	check_eq([eyes[0]["radius"],eyes[0]["angle"]],[2.0,45.0],"两级望远镜使用2ly及45度全角")
	s.line_anchor=Vector3i.ZERO
	DimensionSpace.commit(s,true)
	show_state(s)
	map.refresh(me,{},true,false)
	shapes=map._markers.get_children().filter(func(child):return child.get_meta("vision_observer",-1)==probe.id)
	check_eq(shapes.size(),1,"一维有一份前后方向图示")
	if shapes.size()==1:
		check_eq(shapes[0].mesh.size.x,96.0,"2ly前向+1ly后向，按1/32ly格距绘制96格")
	var observer: Dictionary=map._grid_eyes.filter(func(o):return o["id"]==probe.id)[0]
	check(Signals.in_view(map.state,observer,observer["pos"]-observer["dir"]*32.0),"两级一维望远镜后向1ly有效")
	check(not Signals.in_view(map.state,observer,observer["pos"]-observer["dir"]*33.0),"后向范围外不能高亮")


func test_flat_and_line() -> void:
	var s := fixture()
	for civ in s.civs:
		civ.techs["dimension"] = true
		civ.dimension_ammo=3
		for asset in civ.assets:
			asset["entity_dim"]=2
	show_state(s)
	check(actions._action_tiles[actions.Action.FOIL].visible and not actions._action_tiles[actions.Action.LINE_FOIL].visible, "3D 只显示二向箔")
	actions._action_tiles[actions.Action.FOIL].pressed.emit()
	actions.aim_at(Vector3i(2, 2, 2))
	check(not actions._go.disabled, "有预制弹药后二向箔执行按钮可用")
	actions._go.pressed.emit()
	check(s.human().foils.size()==1 and s.human().dimension_ammo==2,"执行按钮扣除一枚弹药并发射载荷")
	# 传播、相交和729格提交由规则测试覆盖；这里直接摆出前沿完成的画面夹具。
	s.payloads.clear()
	s.human().foils.clear()
	map._set_hover(_pickable_at(s.human().home))
	_finish_view_front(s,Vector3i(4,4,4))
	view.refresh()
	await settled_frame()
	check(s.all_flat() and not s.is_over(), "3D 结束后进入可玩的 2D")
	check(not panel._end.disabled, "二维可以继续结束回合")
	check(not map._cursor.visible, "换图清除旧坐标的悬停提示")
	check(overlay._restart.get_global_rect().end.x <= panel.get_global_rect().position.x, "二维状态栏不侵入操作面板")
	var goal: Vector3i = actions._target_cell()
	check(Vector3i(actions._coord_boxes[0].value, actions._coord_boxes[1].value, actions._coord_boxes[2].value) == goal, "换图后的坐标输入和实际目标一致")
	var home: Vector3 = map._warp_point(Vector3(s.human().home))
	var screen: Vector2 = map._camera.unproject_position(map._world.to_global(home))
	check(map._pick_object(screen).get("cell") == s.human().home, "换图后在新位置可以点中母星")
	check(actions._action == actions.Action.LINE_FOIL and actions._action_tiles[actions.Action.LINE_FOIL].visible, "自动切换到单向著")
	check(not actions._action_tiles[actions.Action.FOIL].visible and not actions._pitch_box.visible, "二维不再显示二向箔和俯仰输入")
	var segments: Dictionary = map._grid_segments()
	check(segments.size() == 1404, "二维网格连接全部 729 个格子")
	check(actions._coord_boxes[0].max_value == 26 and actions._coord_boxes[1].max_value == 26, "二维输入允许 0 到 26")
	actions.aim_at(Vector3i(26, 26, s.flat_plane))
	check(actions._target_cell() == Vector3i(26, 26, s.flat_plane), "远端二维目标选取准确")
	for segment in segments.values():
		check(segment[0].z == s.flat_plane and segment[1].z == s.flat_plane, "二维每条线段位于同一平面")
	_check_flat_helpers(s, "二维", 48, func(p: Vector3, at: Vector3) -> bool: return absf(p.z - at.z) < 1e-4)
	await capture("two-dimensional")

	for civ in s.civs:
		for asset in civ.assets:
			asset["entity_dim"]=1
		civ.actions_left=2
	view.refresh()
	actions._action_tiles[actions.Action.LINE_FOIL].pressed.emit()
	actions.aim_at(Vector3i(2,2,s.flat_plane))
	check(not actions._go.disabled,"下一阶段的单向著执行按钮可用")
	actions._go.pressed.emit()
	check(s.human().foils.size()==1 and s.human().foils[0].to_line,"按钮发出有限传播单向著")
	s.payloads.clear()
	s.human().foils.clear()
	_finish_view_front(s,Vector3i(13,13,s.flat_plane))
	view.refresh()
	await settled_frame()
	check(s.all_linear(), "整张星图压成直线")
	_check_flat_helpers(s, "一维", 3, func(p: Vector3, at: Vector3) -> bool:
		return absf(p.z - at.z) < 1e-4 and absf(p.y - at.y) <= 0.6 + 1e-4)
	await _check_line_camera_and_controls(s)
	segments = map._grid_segments()
	check(segments.size() == 728, "最终有 728 条相邻线段，连接 729 个格子")
	for segment in segments.values():
		for point in segment:
			check(point.y == s.line_y and point.z == s.flat_plane, "最终网格没有残留平面")
	for c in s.map.cells():
		var point: Vector3 = map._warp_point(Vector3(c)) - s.visual_offset
		check(point.y == s.line_y and point.z == s.flat_plane, "729 个格子全部位于同一条直线")
	check(actions._coord_boxes[0].max_value == 728 and actions._coord_boxes[1].min_value == s.line_y, "坐标输入支持一维的新范围")
	s.human().actions_left=2
	view.refresh()
	actions._action_tiles[actions.Action.SINGULARITY].pressed.emit()
	check(not actions._go.disabled,"一维有弹药时可以发射奇异点")
	actions._go.pressed.emit()
	check(s.payloads.size()==1 and not s.is_over(),"奇异点先发出载荷，不提供倒计时胜利")
	for i in 3:
		if s.is_over():
			break
		panel._end.pressed.emit()
	check(s.winner=="AI" and not s.human().alive,"本地零维终止摧毁自己唯一锚点，另一文明存续获胜")
	check(panel._end.text.contains("再来一局") and overlay._status.text.contains("失败"),"合法败局显示结算和重开入口")
	await capture("singularity-terminal")


## 只摆画面用的完成前沿：保留729格实际换图，不用旧文明布尔标记代替实体维度。
func _finish_view_front(s: GameState,center: Vector3i) -> void:
	SpaceEvents.unfold(s,center)
	for cell in s.map.cells():
		SpaceEvents.convert_cell(s,cell)
	SpaceEvents.resolve(s)


## 二维和一维中的已收广播、视野保持在当前空间内。

func _check_flat_helpers(s: GameState, label: String, rings: int, in_space: Callable) -> void:
	var me := s.human()
	var from := Vector3(me.home)
	me.broadcast_reports[9999]={"id":9999,"from":from,"target":me.home,"exposed":false,
		"sent":s.clock-3.0*s.physical_cell_size()/s.background_light()}
	view.overlay.show_vision.button_pressed = true
	view.refresh()
	var at: Vector3 = map._warp_point(from)
	var parts: Array = map._tube_parts.filter(func(p): return p[2] == Color(map.COLOR_BROADCAST, 0.45))
	check_eq(parts.size(), rings, "%s的广播画 %d 根粗线" % [label, rings])
	for p in parts:
		check(in_space.call(p[0], at) and in_space.call(p[1], at), "%s的广播圆圈不伸出%s（%s → %s）" % [label, label, p[0], p[1]])
	var balls := 0
	for node in map._markers.get_children():
		if node is MeshInstance3D and node.mesh is SphereMesh:
			balls += 1
	check(balls == 0, "%s的视野不画成球" % label)
	me.broadcast_reports.erase(9999)
	view.refresh()


## 一维的镜头和操作：进入一维时对准自己的据点、直线横着；拖动沿直线走，能从一头走到另一头；
## 近看能点中母星；方向只有 -x、+x 两个按钮，没有角度圆盘和 y、z 输入。
func _check_line_camera_and_controls(s: GameState) -> void:
	var me := s.human()
	map._snap_camera()
	var home: Vector3 = map._warp_point(Vector3(me.home))
	check(absf(map._goal_yaw) < 1e-4 and map._goal_distance == map.LINE_DISTANCE, "进入一维时直线横着、离得近")
	check(map._goal_focus.distance_to(home) < 1e-3, "进入一维时对准自己的母星")
	var screen: Vector2 = map._camera.unproject_position(map._world.to_global(home))
	check(map._pick_object(screen).get("cell") == me.home, "一维近看时能点中母星")
	var bounds: AABB = map._visual_bounds()
	for side in [1.0, -1.0]:
		var end: float = bounds.end.x if side > 0.0 else bounds.position.x
		for i in 3000:
			if (map._goal_focus.x - end) * side >= 0.0:
				break
			map._pan(-300.0 * side, 0.0)
		check((map._goal_focus.x - end) * side >= 0.0, "拖动能沿直线走到 x = %.0f 那一头（停在 %.1f）" % [end, map._goal_focus.x])
		check(absf(map._goal_focus.y - home.y) < 1e-3 and absf(map._goal_focus.z - home.z) < 1e-3, "拖动只沿直线走")
	# 转过视角以后左右拖动仍沿直线走，包括顺着直线看（水平角 90°）
	for yaw in [45.0, 89.0, 90.0, 180.0, -90.0]:
		map.reset_view(true)
		map._goal_yaw = yaw
		map._snap_camera()
		var before: Vector3 = map._goal_focus
		map._pan(-300.0, 0.0)
		check(absf(map._goal_focus.x - before.x) > 1.0, "水平角 %.0f° 时左右拖动沿直线走" % yaw)
		check(absf(map._goal_focus.y - before.y) < 1e-3 and absf(map._goal_focus.z - before.z) < 1e-3, "水平角 %.0f° 时仍只沿直线走" % yaw)
	map.reset_view(true)
	check(map._focus.distance_to(home) < 1e-3, "V 回到自己的母星")
	check(absf(map._yaw) < 1e-4, "V 也把视角转回来")
	actions._action_tiles[actions.Action.DISPATCH].pressed.emit()
	check(actions._line_dirs.visible and not actions._yaw_box.visible and not actions._pitch_box.visible, "一维只有 -x、+x 两个方向按钮")
	check(not actions._coord_boxes[1].visible and not actions._coord_boxes[2].visible, "一维不显示 y、z 输入")
	actions._line_left.pressed.emit()
	check_eq(actions._direction(), Vector3(-1, 0, 0), "按 -x 朝 x 变小的一边")
	actions._line_right.pressed.emit()
	check_eq(actions._direction(), Vector3(1, 0, 0), "按 +x 朝 x 变大的一边")
	check(actions._line_right.button_pressed and not actions._line_left.button_pressed, "按钮显示现在的方向")
	await capture("one-dimensional")


## 回合推得很快、展开动画还没播完就进入一维时，镜头仍对准自己据点最后的位置。
func test_fast_line_collapse_frames_home() -> void:
	var s:=fixture()
	for civ in s.civs:
		for asset in civ.assets:
			asset["entity_dim"]=1
	show_state(s)
	view.set_process(false)
	map.set_process(false)
	_finish_view_front(s,Vector3i(4,4,4))
	view.refresh()
	check(s.all_flat(),"测试准备：进入二维")
	# 不等待第一段动画，立刻再换一次图。
	_finish_view_front(s,Vector3i(0,13,s.flat_plane))
	view.refresh()
	check(s.all_linear(),"测试准备：进入一维")
	view.set_process(true)
	map.set_process(true)
	await settled_frame()
	var home: Vector3=map._warp_point(Vector3(s.human().home))
	check(map._goal_focus.distance_to(home)<1e-3,"两段动画追上以后镜头对准母星")
	map._snap_camera()
	var screen: Vector2=map._camera.unproject_position(map._world.to_global(home))
	check(map._pick_object(screen).get("cell")==s.human().home,"近看能点中母星")
	map._pan(-300.0,0.0)
	await settled_frame()
	check(map._goal_focus.distance_to(home)>1.0,"之后手动平移不会被拉回去")


## 胜负结束后仅环境动画继续，不增加回合和收入。


func test_post_victory_collapse() -> void:
	# 扩散得慢时，有的步一个格子也没多压没（边界面还是变了），这样才测得到这种步
	var old_spread := Balance.FOIL_SPREAD
	Balance.FOIL_SPREAD = 0.3
	var s := fixture()
	for asset in s.civs[0].assets:
		asset["entity_dim"]=2
	s._unfold_foil(s.civs[1].home)
	# 已收到的前沿历史驱动画面；这里不测试完整远端回传。
	s.human().front_reports[9999]={"front_type":"foil","epoch":s.space_epoch,"t_observed":s.clock,"data":s.foil_zones[0].duplicate(true)}
	show_state(s)
	check(s.is_over() and s.collapse_pending(), "提前胜负测试确实还有空间待压缩")
	var turn := s.turn
	var energy := s.human().energy
	var steps := 0
	var animated := 0
	view.set_process(false)  # 只由这里一帧一帧地推，免得引擎每帧自己再推一步
	for i in 80:
		if map._warp_t >= 1.0 and s.collapse_pending():
			view._process(0.0)  # 上一步的动画放完了，这一帧压下一步
			steps += 1
			if map._warp_t < 1.0:
				animated += 1
		view._process(map.FLAT_ANIM_SECONDS)
		await process_frame
		if not s.collapse_pending() and map._warp_t >= 1.0:
			break
	check(s.all_flat() and s.turn == turn and s.human().energy == energy, "结束后的动画驱动空间完成，不产生额外回合或收入")
	check(steps > 0 and animated == steps, "每压一步都放一次动画，没压没新格子的那一步也不一闪而过")
	view.set_process(true)
	Balance.FOIL_SPREAD = old_spread
	await capture("post-victory-collapse")


## 重开一局：对局中途要先确认；结束以后「结束回合」变成「再来一局」。
func test_restart() -> void:
	show_state(GameState.new_game(5))
	view.state.end_turn()
	overlay._restart.pressed.emit()
	check(overlay._restart_dialog.visible and overlay._restart_dialog.dialog_text.contains("还没打完"), "对局中途重开先问一下")
	overlay._restart_dialog.custom_action.emit("same")
	check(view.state.seed_value == 5 and view.state.turn == 1, "可以在同一张星图上从头再打")
	check(not overlay._restart_dialog.visible, "选完对话框关掉")
	view.state.winner = "你"
	view.refresh()
	check(not panel._end.disabled and panel._end.text.contains("再来一局"), "对局结束后结束回合变成再来一局")
	var old: GameState = view.state
	panel._end.pressed.emit()
	check(view.state != old and not view.state.is_over() and view.state.turn == 1, "按了以后开始新的一局")
	check(panel._end.text.contains("结束回合"), "新的一局里按钮变回结束回合")


# ---------- 调试面板 ----------

## 打开调试面板，换成一局新的对局。
func _debug_game(seed_value: int, watch: bool) -> GameState:
	view.debug.visible = true
	view.debug.new_game(seed_value, watch)
	return view.state


func test_debug_view_other_civ() -> void:
	check(view.debug != null, "调试版里有调试面板")
	check(view.debug.get_parent() == view.debug.window, "调试面板在单独的窗口里")
	view.debug.visible = false
	check(not view.debug.window.visible, "收起面板时窗口也藏起来")
	view.debug.window.close_requested.emit()
	check(not view.debug.visible, "点窗口的关闭按钮等于收起")
	var s := _debug_game(21, false)
	check(view.debug.window.visible, "打开面板时窗口也显示")
	var ai: Civ = s.civs[2]
	view.debug.set_view(2)
	check(view.viewed() == ai, "换成 AI-2 的视角")
	check(panel._res_values["energy"].text.get_slice("  ",0) == panel.Widgets.number(ai.energy), "资源栏显示 AI-2 的能量")
	check(overlay._status.text.contains(ai.name), "状态栏写着正在看谁的视角")
	check(actions._go.disabled and actions._go_hint.text.contains("AI"), "AI 控制的文明只能看不能操作")
	var probes := ai.count(Ship.PROBE)
	panel._build_tiles["probe"].pressed.emit()
	check(ai.count(Ship.PROBE) == probes, "按建造按钮也不起作用")
	check(not panel._end.disabled, "看别人的视角时也可以结束回合")
	view.debug.set_view(0)
	check(view.viewed() == s.human(), "换回自己")


func test_debug_take_over_ai() -> void:
	var s := _debug_game(22, false)
	var ai: Civ = s.civs[1]
	view.debug.set_view(1)
	view.debug._autoplay.toggled.emit(false)
	check(not ai.is_ai, "取消「由 AI 控制」就接管了这个文明")
	ai.energy = 100
	ai.mineral = 100
	view.refresh()
	panel._build_tiles["probe"].pressed.emit()
	check(ai.pending.size() == 1 and ai.count(Ship.PROBE)==0, "接管后可以替它提交建造工程")
	for i in int(ceilf(Construction.work("probe"))):
		panel._end.pressed.emit()
	check_eq(ai.count(Ship.PROBE),1,"接管文明的工程同样要完成工作量")
	check(s.history.any(func(h): return h["civ"] == 1 and h["name"] == "build" and not h["ai"]), "这次建造算玩家的操作")
	view.debug._autoplay.toggled.emit(true)
	check(ai.is_ai, "再勾上就交还给 AI")
	view.debug.set_view(0)


## 往回跳用局面缓存：缓存里有的直接取；没有的分段补算，能看到进度、能取消；改过数值也能退回去。
func test_debug_rewind_cache() -> void:
	var d = view.debug
	var s := _debug_game(26, true)
	for i in 25:
		d.step_forward(true, false)
	var sums: Array[int] = s.checksums.duplicate()
	d.seek(24)
	check(view.state.steps == 24 and view.state.checksum() == sums[23] and d._note.contains("缓存"),
			"退一回合直接取缓存里的局面")
	d.seek(23)
	d.seek(22)
	check(view.state.checksum() == sums[21] and d._note.contains("缓存"), "连着往回退也直接取")
	d.seek(25)
	check(view.state.checksum() == s.checksum() and not d.replaying(), "再跳回最后，和原来一样，回到实时")
	# 缓存清空后从开局补算：每算一回合停一下，能看到进度；中途取消，留在原来的局面
	d.snapshots.clear()
	d.seek_slice = 0
	var before: GameState = view.state
	d.seek(12)
	check(d.seeking and d._note.contains("补算") and d.locked_reason() != "" and panel._end.disabled,
			"算的时候显示进度，不能操作")
	await process_frame
	await process_frame
	d.cancel_seek()
	for i in 5:
		await process_frame
	check(not d.seeking and view.state == before and not d.replaying() and view.state.steps == 25,
			"取消后留在原来的局面")
	d.seek(12)
	while d.seeking:
		await process_frame
	check(view.state.steps == 12 and view.state.checksum() == sums[11] and d.replaying(), "不取消就算完再换局面")
	# 从中间接着玩、改数值，再往回退：数值回到当时的，局面和当时一样
	d.seek_slice = 100
	d.resume_here()
	var energy := Balance.ENERGY_PER_STAR
	d._dev(func(st): return st.dev_balance("ENERGY_PER_STAR", energy + 5))
	for i in 3:
		d.step_forward(true, false)
	var changed_sum: int = view.state.checksum()
	d.seek(11)
	check(Balance.ENERGY_PER_STAR == energy and view.state.checksum() == sums[10], "改数值以前的回合，数值也是当时的")
	d.seek(15)
	check(Balance.ENERGY_PER_STAR == energy + 5 and view.state.checksum() == changed_sum, "跳回改数值以后，数值又是改过的")


func test_debug_playback() -> void:
	var s := _debug_game(23, true)
	check(s.spectator and s.human().is_ai, "观战局里所有文明都由 AI 控制")
	for i in 6:
		check(view.debug.step_forward(false), "观战局可以一直往前播放")
	var end_sum: int = view.state.checksum()
	view.debug.seek(2)
	check(view.state.steps == 2 and view.debug.replaying(), "可以退回第 3 回合，进入回放")
	check(panel._end.disabled, "回放中不能结束回合")
	view.debug.seek(6)
	check(not view.debug.replaying() and view.state.checksum() == end_sum, "再走到最后，局面和原来一样，回到实时")
	view.debug.seek(3)
	view.debug.resume_here()
	check(not view.debug.replaying() and view.state.steps == 3, "从中间接着玩：丢掉之后的记录")
	check(view.debug.desync_step == -1, "重算没有走偏")
	# 自己玩的局：播放到轮到玩家时停下
	_debug_game(24, false)
	check(not view.debug.step_forward(false), "轮到玩家操作时自动播放停下")
	check(view.debug.step_forward(true), "手动前进一回合（相当于结束回合）")
	# 每条记录都能写成一句话
	var s2 := _debug_game(25, true)
	for i in 30:
		view.debug.step_forward(true, false)
	var unknown := 0
	for h in s2.history:
		var text: String = view.debug.describe(s2.civs[maxi(0, h["civ"])], h)
		if text.begins_with(h["name"]):
			unknown += 1
	check(unknown == 0, "调试面板认得每一种操作")
	view.debug._tabs.current_tab = 0
	view.refresh()
	check(view.debug._log.get_parsed_text().contains("回合"), "行动记录里有内容")


func test_debug_edit_values() -> void:
	var s := _debug_game(26, false)
	var me := s.human()
	view.debug._tabs.current_tab = 2
	view.refresh()
	var energy_box: SpinBox = view.debug._civ_rows["energy"]
	check(energy_box.value == me.energy, "文明页显示现在的能量")
	energy_box.value = 345
	check(me.energy == 345 and s.dev_used, "在文明页改能量马上生效")
	view.debug._tech_boxes["warship"].toggled.emit(true)
	check(me.has_tech("warship"), "在文明页勾上科技就得到")
	view.debug._tabs.current_tab = 1
	view.refresh()
	var before: int = Balance.COST_TURN
	var row: Dictionary = view.debug._balance_rows["COST_TURN"]
	(row["editor"] as SpinBox).value = before + 5
	check(Balance.COST_TURN == before + 5, "在数值页改数值马上生效")
	view.refresh()
	check(not (row["reset"] as Button).disabled, "改过的数值可以恢复")
	(row["reset"] as Button).pressed.emit()
	check(Balance.COST_TURN == before, "按 ↺ 恢复原来的数值")
	check(s.history.filter(func(h): return String(h["name"]).begins_with("dev_")).size() == 4, "每次改动都记下来")
	view.debug._balance_filter.text = "COST_TURN"
	view.debug._filter_balance()
	check(row["cell"].visible and not view.debug._balance_rows["COST_PROBE"]["cell"].visible, "可以按名字筛选数值")
	view.debug._balance_filter.text = ""
	view.debug._tabs.current_tab = 0


## 数值方案：存下现在的数值，恢复默认，再用上方案；设成新局默认后，新开一局就用这个方案。
func test_debug_presets() -> void:
	var s := _debug_game(27, false)
	var dbg = view.debug
	var base: int = Balance.START_ENERGY
	dbg._tabs.current_tab = 1
	s.dev_balance("COST_TURN", Balance.COST_TURN + 3)
	var turn_cost: int = Balance.COST_TURN
	dbg._preset_name.text = "_view_test"
	dbg._preset_shared.button_pressed = false
	dbg.save_preset()
	var path := BalancePresets.path_for("_view_test", false)
	check(FileAccess.file_exists(path), "按「存成方案」存出文件")
	check(dbg._selected_preset() == path, "存完自动选中这个方案")
	dbg._apply_values({}, "默认")
	check(Balance.COST_TURN == turn_cost - 3, "「恢复默认」换回 balance.cfg 里的数值")
	dbg.apply_preset()
	check(Balance.COST_TURN == turn_cost, "「用上」换成方案里的数值")
	check(s.history.filter(func(h): return h["name"] == "dev_balance").size() == 3, "切换方案也记进对局记录")
	dbg._preset_default.button_pressed = true
	check(dbg.default_preset() == path, "可以设成新开一局时用的方案")
	var s2 := _debug_game(28, false)
	check(Balance.COST_TURN == turn_cost and Balance.START_ENERGY == base, "新开一局用了这个方案")
	check(s2.start_balance["COST_TURN"] == turn_cost and not s2.dev_used, "开局就用的方案记在开局数值里，不算改过数值")
	dbg._preset_default.button_pressed = false
	dbg._delete_preset()
	check(not FileAccess.file_exists(path) and dbg._selected_preset() == "", "可以删掉方案")
	_debug_game(29, false)
	check(Balance.COST_TURN == turn_cost - 3, "不用方案时新开一局是 balance.cfg 里的数值")
	check(dbg._write_back.visible == BalancePresets.can_write_back(), "只有编辑器版才有「写回 balance.cfg」")
	dbg._tabs.current_tab = 0


## 自己玩的局里你灭亡了：面板出现「继续往下看」，按了以后其余文明接着打，可以一直播放。
func test_debug_after_death() -> void:
	var s:=_debug_game(30,false)
	for cell in s.human().colonies.duplicate():
		s._lose_system(cell,s.human(),"界面测试夹具")
	s._check_winner()
	check(not s.human().alive and not s.is_over(),"V0.1玩家失去锚点后，多AI对局自动继续")
	view.refresh()
	check(not view.debug._after_death.visible,"无需旧版二次确认继续按钮")
	check(overlay._status.text.contains("你已灭亡"),"状态栏说明玩家已灭亡")
	check(not panel._end.disabled,"可继续观察其余文明")
	var steps:=s.steps
	check(view.debug.step_forward(false),"玩家无需再输入操作，调试播放可继续")
	check_eq(s.steps,steps+1,"继续操作实际推进一个回合")
	view.debug.set_view(1)
	check(view.viewed()==s.civs[1],"可切换存续AI的视角")
	view.debug.set_view(0)


## 规则：界面和操作
## 全屏依赖树：实际前置始终从左到右，查看锁定节点不扣资源，模态界面不触发星图快捷键。
func test_tech_tree() -> void:
	var s := fixture()
	show_state(s)
	var tree = view.tech_tree
	tree.open_tree()
	await process_frame
	check(tree.visible and tree.size.is_equal_approx(root.get_visible_rect().size), "科技树覆盖整个逻辑画布")
	var count := 0
	for id in Tech.ALL:
		for need in Tech.ALL[id]["needs"]:
			count += 1
			check(tree.edges.has([need, id]), "真实前置都有连线：" + id)
			check(tree.tiles[need].position.x + tree.tiles[need].size.x < tree.tiles[id].position.x, "前置始终在目标左边：" + id)
	check_eq(tree.edges.size(), count, "没有凭空添加前置连线")
	tree.tiles["domain"].pressed.emit()
	check(tree._research.disabled and tree._details.text.contains("曲率引擎"), "锁定节点可查看前置和研究条件")
	var before := s.checksum()
	tree._research.pressed.emit()
	var key := InputEventKey.new()
	key.pressed = true
	key.shift_pressed = true
	key.keycode = KEY_ENTER
	view._on_key(key, root)
	check_eq(s.checksum(), before, "锁定研究和结束回合快捷键不会修改局面")
	key.physical_keycode = KEY_G
	var grid: int = map.grid_mode
	check(not map._camera_key(key) and map.grid_mode == grid, "全屏科技树阻止地图快捷键")
	s.human().tier1_turn = s.turn
	s.human().energy = 0
	tree.select_tech("warship")
	check(tree._research.disabled and tree._details.text.contains(s.research_error(s.human(), "warship")), "资源不足说明来自规则")
	view.window_settings.apply_ui_scale(1.0)
	root.size = Vector2i(1280, 800)
	await process_frame
	tree.select_tech("warship")
	s.human().energy = 1000
	view.refresh()
	await capture("tech-tree")
	root.size = Vector2i(600, 900)
	await process_frame
	await process_frame
	check(tree.size.x <= root.get_visible_rect().size.x + 1, "窄屏科技树在屏幕内，图可滚动")
	tree._scroll.ensure_control_visible(tree.tiles["domain"])
	await capture("tech-tree-portrait")
	key.shift_pressed = false
	key.keycode = KEY_ESCAPE
	view._on_key(key, root)
	check(not tree.visible, "Esc 返回星图")
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	view.show_panel(2)


## 规则：科技树，每回合的收入，界面和操作
func test_v01_tree_and_numeric_state() -> void:
	var s := fixture()
	var me := s.human()
	me.energy = 0.375
	show_state(s)
	check(panel._res_values["energy"].text.contains("0.375"), "现有资源栏显示.001精度，不能把可用余额截成0")
	var tree = view.tech_tree
	tree.open_tree()
	await process_frame
	check_eq(tree.tiles.size(), 34, "原全屏组件承载34个节点")
	check_eq(tree.edges.size(), 21, "仅使用21条正式依赖")
	var ids: Array = tree.tiles.keys()
	for i in ids.size():
		check(not panel._tech_desc(ids[i]).is_empty(), "每项科技保留鼠标悬停说明：" + ids[i])
		for j in range(i+1, ids.size()):
			check(not tree.tiles[ids[i]].get_rect().intersects(tree.tiles[ids[j]].get_rect()), "节点不重叠：%s/%s" % [ids[i], ids[j]])
	me.energy = 1000
	tree.select_tech("warship")
	tree._research.pressed.emit()
	check(not me.has_tech("warship") and not me.research_project.is_empty(), "原研究按钮提交有工期的研究")
	check(tree.tiles["warship"].text.contains("研究中"), "研究中的节点在原位置显示进度状态")
	check(tree._research.disabled, "在制研究不能重复提交")
	view.window_settings.apply_ui_scale(1.0)
	root.size = Vector2i(1280, 800)
	await process_frame
	await capture("v01-tech-tree")
	tree.close_tree()
	check(not tree.visible, "返回星图操作保留")


## 规则：情报传回，界面和操作
func test_v01_shared_information_view() -> void:
	var a:=fixture()
	a.ensure_cells()
	var me:=a.human()
	var remote:=Vector3i(4,0,0)
	a.map.stars[remote]=StarMap.Star.SINGLE
	a.map.rocky[remote]=1
	a.system_cells.append(remote)
	me.colonies.append(remote)
	me.miners[remote]=1
	me.warnings[remote]=1
	for civ in a.civs:
		Assets.ensure(a,civ)
	var ship:=Ship.make(Ship.WARSHIP,Vector3(5,0,0),a.next_id())
	ship.docked=false
	ship.direction=Vector3.RIGHT
	me.ships.append(ship)
	Knowledge.report_site(a,me,remote)
	Signals.report_ship(a,me,ship)
	Signals.advance(a,5.0)
	a.clock=5.0
	Signals.receive_due(a)
	var b:=StateCopy.copy(a)
	b._destroy(b.human(),b.human().ships[0],"未收到的损毁")
	b._lose_system(remote,b.human(),"未收到的失守")
	Hazards.activate(b,Vector3(6,6,6))
	SpaceEvents.unfold(b,Vector3i(7,7,7))
	view.reveal.button_pressed=false
	show_state(a)
	await settled_frame()
	var displayed:=[map._pickables(),DimensionSpace.frame(map.state),panel._stats(me),overlay._status.text]
	var host_ids: Array=[]
	for i in panel.advanced._hosts.item_count:
		host_ids.append(panel.advanced._hosts.get_item_metadata(i))
	await capture("v01-information-before")
	check(panel.get_global_rect().end.x<=root.get_visible_rect().size.x+1.0,"资源栏和新增控件不把原右侧面板撑出屏幕")
	show_state(b)
	await settled_frame()
	check_eq([map._pickables(),DimensionSpace.frame(map.state),panel._stats(b.human()),overlay._status.text],displayed,"隐藏失守、舰毁、黑域与前沿不改变正常画面信息")
	var after_ids: Array=[]
	for i in panel.advanced._hosts.item_count:
		after_ids.append(panel.advanced._hosts.get_item_metadata(i))
	check_eq(after_ids,host_ids,"未收到回报前不删除操作宿主")
	check(map.state!=b and map.state.black_domains.is_empty(),"正常星图绑定历史投影")
	await capture("v01-information-hidden-change")
	view.reveal.button_pressed=true
	view.refresh()
	check(map.state==b and not map.state.black_domains.is_empty(),"独立debug全视野仍可显示真实世界")
	view.reveal.button_pressed=false
	view.refresh()


## 规则：每回合的收入，情报传回，界面和操作
func test_v01_ui_resource_preview() -> void:
	var s := fixture()
	var me := s.human()
	s.map.rocky[me.home] = 3
	me.miners[me.home] = 1
	Assets.ensure(s,me)
	show_state(s)
	check(panel._res_values["energy"].text.contains("+3"),"资源栏恢复下一回合预计能量增长")
	check(panel._res_values["mineral"].text.contains("+2"),"资源栏恢复下一回合预计矿石增长")
	var tip: String = panel._res_values["energy"].get_parent().get_parent().tooltip_text
	check(tip.contains("总收入") and tip.contains("维护") and tip.contains("预计净变化"),"悬停分别解释收入、维护和净变化")
	check(not (panel._upgrade_tiles["warning"].get_meta("cost") as Label).text.contains("-1/"),"未建预警系统不能显示内部的负一级")
	panel._on_build("probe")
	tip = panel._res_values["mineral"].get_parent().get_parent().tooltip_text
	check(tip.contains("已预付") and tip.contains("已从余额扣除"),"工程资源不重复计入可用余额，并明确解释预付")
	var remote := Vector3i(4,0,0)
	me.colonies.append(remote)
	s.map.rocky[remote] = 2
	s.map.stars[remote] = StarMap.Star.SINGLE
	s.system_cells.append(remote)
	me.miners[remote] = 1
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,remote)
	Signals.advance(s,4.0)
	s.clock = 4.0
	Signals.receive_due(s)
	show_state(s)
	var before: Array = [panel._res_values["energy"].text,panel._res_values["mineral"].text,panel._res_values["energy"].get_parent().get_parent().tooltip_text]
	var hidden := StateCopy.copy(s)
	hidden.map.rocky[remote] = 0
	hidden.human().miners[remote] = 0
	Assets.ensure(hidden,hidden.human())
	show_state(hidden)
	check_eq([panel._res_values["energy"].text,panel._res_values["mineral"].text,panel._res_values["energy"].get_parent().get_parent().tooltip_text],before,"未回传的远端产出变化不能泄露到预计收入")
	await capture("v01-resource-preview")


## 通过 Viewport 的真实 GUI 分发点按，不直接调用按钮回调。
func pointer_click(control: Control) -> void:
	await process_frame
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event,true)
	await process_frame


## 规则：建造，界面和操作
func test_v01_ui_pointer_build_feedback() -> void:
	var s := fixture()
	var me := s.human()
	s.map.rocky[me.home] = 3
	show_state(s)
	view.tech_tree.close_tree()
	view.window_settings.apply_ui_scale(1.0)
	root.size = Vector2i(1280,800)
	view.show_panel(1)
	await process_frame
	await process_frame
	await pointer_click(panel._build_tiles["probe"])
	check_eq(me.pending.size(),1,"实际鼠标点按能提交合法建造，无覆盖控件拦截")
	check(panel._feedback.text.contains("已开始") or panel._feedback.text.contains("已发送"),"成功下单有可见反馈")
	check(not panel._build_tiles["warning"].disabled,"首单下完母星仍有第二槽可用")
	await pointer_click(panel._build_tiles["probe"])
	check_eq(me.pending.size(),2,"第二次真实点击受理另一独立订单")
	check(panel._build_tiles["warning"].disabled,"两槽都占用时按钮等待")
	check(panel._build_hint.text.contains("2 / 2"),"既有建造页显示两槽占用")
	check(panel._res_values["actions"].text.contains("1 / 3"),"资源条显示第三AP仍可用")
	var paid := [me.energy,me.mineral,me.actions_left]
	await pointer_click(panel._build_tiles["warning"])
	check(panel._feedback.visible and panel._feedback.text.contains("施工"),"点击不可用建造说明当地工程占用，不只是灰掉")
	check_eq([me.energy,me.mineral,me.actions_left],paid,"受限第三单不会扣费")
	await pointer_click(panel._end)
	check_eq(me.count(Ship.PROBE),2,"鼠标结束回合同时完成两个探测器工程")
	check(not panel._build_tiles["warning"].disabled,"当地工程完成后按钮恢复")
	me.mineral = 0
	view.refresh()
	await pointer_click(panel._build_tiles["probe"])
	check(panel._feedback.visible and panel._feedback.text.contains("矿石不足"),"资源不足的真实点击给出具体原因")
	check_eq(me.count(Ship.PROBE),2,"失败点击不建造也不扣费")
	await capture("v01-build-feedback")


## 规则：界面和操作
## 密集局面：停泊聚合、航线按需、广播有上限，同时保留全部可见舰船和敌情。
func test_v01_speed_descriptions_follow_replay_parameters() -> void:
	show_state(fixture())
	var specs := [[Ship.PROBE,"probe","30%","立即匀速"],[Ship.NUCLEAR_PROBE,"interstellar_probe","50%","2 年"],
			[Ship.COLONY,"interstellar_travel","40%","5 年"],[Ship.DEVOURER,"devourer","30%","5 年"]]
	for spec in specs:
		var build_tip: String = panel._build_desc(spec[0])
		check(build_tip.contains(spec[2]) and build_tip.contains(spec[3]),"四类建造悬停说明使用当前速度分档")
		check(build_tip.contains("同步降低"),"速度说明解释降维与黑域缩放")
		var tech_tip: String = panel._tech_desc(spec[1])
		check(tech_tip.contains(spec[2]) and tech_tip.contains(spec[3]),"关联科技说明与建造航速一致")
	var values := Balance.values().duplicate(true)
	var old := Replay.new()
	old.balance = values.duplicate(true)
	old.balance.erase("SHIP_SPEED_RELATIVE")
	old.balance["PROBE_MOVE"] = [0.01,0.0]
	old.balance["IPROBE_MOVE"] = [0.1,0.01]
	old.apply_balance()
	check(panel._tech_desc("probe").contains("0.01 光年/年"),"读入旧记录后说明保留旧化学航速")
	check(panel._tech_desc("interstellar_probe").contains("10 年"),"读入旧记录后说明保留旧核脉冲加速时间")
	Balance.apply(values)
	check(panel._tech_desc("probe").contains("30%"),"恢复新参数后说明同步更新")
	view.refresh()
	await capture("tiered-speed-description")


## 规则：建造，情报传回，界面和操作
func test_v01_local_parallel_progress_display() -> void:
	var s := fixture()
	var me := s.human()
	s.map.rocky[me.home] = 3
	Assets.ensure(s,me)
	Signals.sample(s)
	var a := s.build(me,"miner")
	var b := s.build(me,"miner")
	check_eq([a["error"],b["error"]],["",""],"双槽工程均合法下单")
	s.end_turn()
	show_state(s)
	view.show_panel(1)
	check_eq(panel._build_progress.text.count("进度 1 / 2"),2,"年末两个本地工程均显示已收的1/2进度")
	check_eq(panel._build_progress.text.count("观测 1 年 · 收到 1 年"),2,"工程显示已收报告的观测和接收时刻")
	for id in [a["order"],b["order"]]:
		check_eq(me.order_reports[id]["done"],1000,"显示依据的已收报告为1W")
	var rows := ""
	for i in panel.advanced._orders.item_count:
		rows += panel.advanced._orders.get_item_text(i)+"\n"
	check_eq(rows.count("1/2"),2,"工程菜单进度与建造页一致")
	check(panel._res_values["mineral"].text.contains("+0"),"尚未完工的矿船不提前计入收入")
	me.order_reports[a["order"]]["done"] = 50
	me.order_reports[a["order"]]["t_observed"] = 0.05
	me.order_reports[a["order"]]["t_received"] = 0.05
	view.refresh()
	check(panel._build_progress.text.contains("进度 0.05 / 2；观测 0.05 年 · 收到 0.05 年"),"历史报告明确标注时间，不拿未采样的施工真值补数")
	await capture("local-parallel-progress-current")


func test_map_clarity() -> void:
	var s := fixture()
	var me := s.human()
	s.turn = 25
	s.clock = 24.0
	for i in 36:
		var ship := Ship.make(Ship.PROBE if i % 2 == 0 else Ship.WARSHIP, Vector3.ZERO, s.next_id())
		if i >= 12:
			ship.pos = Vector3(1 + i % 6, 1 + (i / 6) % 4, 2 + i % 3)
			ship.docked = false
			ship.direction = Vector3.RIGHT
		me.ships.append(ship)
		me.telemetry[ship.id]={"data":Signals.ship_status(ship),"t_observed":s.clock,"t_received":s.clock,"epoch":0}
	me.dysons[me.home] = 3
	me.miners[me.home] = 4
	me.broadcasters[me.home] = true
	for i in 8:
		me.broadcast_reports[i]={"id":i,"from":Vector3(me.home),"target":Vector3i(8,8,8),"sent":s.clock-(1.0+i*0.5),"exposed":me.home}
	me.sightings.append({"pos": Vector3(5, 4, 4), "kind": Ship.WARSHIP, "turn": s.turn})
	me.alerts.append({"pos": Vector3(2, 2, 2)})
	me.known[Vector3i(8, 8, 8)] = s.turn
	me.intel[Vector3i(8, 8, 8)] = s.snapshot(Vector3i(8, 8, 8))
	show_state(s)
	view.show_panel(3)
	overlay.show_details.button_pressed = false
	overlay.show_vision.button_pressed = false
	view.refresh()
	map.reset_view(true)
	var overview: int = map._tube_parts.size()
	var keys: Array = map._pickables().map(func(obj): return obj["key"])
	check_eq(map._wave_nodes.size(), 3, "八条传播只显示最近三条，每条一个圈")
	for i in map._wave_nodes.size():
		check(is_equal_approx((map._wave_nodes[i].mesh as TorusMesh).outer_radius, 3.51 + i * 0.5), "显示的是最新广播的半径")
	s.broadcasts.append({"from": Vector3(8, 8, 8), "target": Vector3i.ZERO, "sender": s.civs[1], "radius": 2.0})
	view.refresh()
	check_eq(map.active_broadcasts(me).size(), 8, "概览不会泄露未听到的敌方广播")
	check_eq(map._wave_nodes.size(), 3, "敌方广播不会挤掉己方波前")
	check(overlay._broadcast_summary.text.contains("8 条"), "摘要说明实际传播条数")
	check_eq(keys.filter(func(key): return key.begins_with("s")).size(), 24, "所有飞行单位仍可见可选")
	check(keys.any(func(key): return key.begins_with("a")), "简洁模式保留预警")
	check(map._cell_info(me.home).contains("×6") and map._cell_info(me.home).contains("戴森球"), "聚合舰队及设施仍有具体信息")
	var dock_labels := 0
	for child in map._markers.get_children():
		if child is Label3D and child.text == "停泊 12":
			dock_labels += 1
	check_eq(dock_labels, 1, "十二艘停泊舰船合并成一个数量标记")
	await capture("midgame-overview")
	overlay.show_details.button_pressed = true
	check(map._tube_parts.size() > overview + 24, "详细模式展开全体航线")
	check_eq(map._pickables().map(func(obj): return obj["key"]), keys, "显示密度不改变可见情报和点选对象")
	await capture("midgame-detail")
	overlay.show_details.button_pressed = false
	for obj in map._pickables():
		if obj["key"] == "s%d"%me.ships[12].id:
			map.select_object(obj)
	check(map._tube_parts.size() > overview, "点击单位立即显示其航线")
	check(map._tube_parts.size() < overview + 24, "选中单位不会展开整支舰队的航线")
	map.select_object({})
	check_eq(map._tube_parts.size(), overview, "取消选择立即收起航线")
	view.show_panel(2)
