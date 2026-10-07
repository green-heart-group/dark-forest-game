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
	for pos in [Vector3i.ZERO, Vector3i(9, 9, 9)]:
		var civ := Civ.new("你" if s.civs.is_empty() else "Other", false, pos)
		civ.energy = 1000
		civ.mineral = 1000
		s.map.stars[pos] = StarMap.Star.SINGLE
		s.system_cells.append(pos)
		s.civs.append(civ)
		s.start_turn(civ)
	return s


func show_state(s: GameState) -> void:
	view.set_state(s)


func settled_frame() -> void:
	view._process(map.FLAT_ANIM_SECONDS)
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
	await run(test_build_and_dispatch)
	await run(test_colony)
	await run(test_hover_intel)
	await run(test_camera)
	await run(test_selection)
	await run(test_grid_modes)
	await run(test_ship_paths)
	await run(test_sightings_drawn)
	await run(test_black_domain_drawn)
	await run(test_intel_on_starless_system)
	await run(test_reduction_controls)
	await run(test_flat_and_line)
	await run(test_post_victory_collapse)
	await run(test_restart)
	await run(test_debug_view_other_civ)
	await run(test_debug_take_over_ai)
	await run(test_debug_playback)
	await run(test_debug_edit_values)
	await run(test_debug_presets)
	await run(test_debug_after_death)
	await capture("debug")
	await capture("debug_panel", view.debug.window)
	view.queue_free()
	await process_frame
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_") and not _ran.has(name):
			results.fail("没写进 run_tests() 的列表，没有跑", name)
	quit(results.finish("画面测试"))


func test_panel_layout() -> void:
	# 固定种子：随机开局里约一成的局一开始就看得到邻居（I 级马上开放），下面的检查就不成立了
	show_state(GameState.new_game(1))
	check(not view.state.human().discovered, "种子 1 开局还没发现别人（不成立就换一个种子）")
	check(panel._tabs.get_tab_count() == 4, "面板有科技、建造、行动、情况四页")
	check(panel._tech_tiles.size() == Tech.ALL.size(), "每项科技一个按钮")
	check(panel._build_tiles.size() == panel.BUILD_ORDER.size() + 1, "每种建造一个按钮，外加自身降维")
	check(overlay._status.text.contains("第 1 回合"), "状态栏显示回合")
	var me: Civ = view.state.human()
	check(panel._tech_tiles["probe"].disabled and panel._tech_tiles["dyson"].disabled, "已有的和没开放的科技不能点")
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
	var tiles: Array = actions._action_tiles.values() + panel._tech_tiles.values() + panel._upgrade_tiles.values() \
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
	panel._tech_tiles["warship"].pressed.emit()
	check(not me.has_tech("warship"), "I 级没开放时按钮不起作用")
	me.tier1_turn = s.turn
	view.refresh()
	check(not panel._tech_tiles["warship"].disabled, "发现别人后可以升 I 级")
	var energy := me.energy
	panel._tech_tiles["warship"].pressed.emit()
	check(me.has_tech("warship") and me.energy == energy - Tech.cost("warship")[0], "按钮升级科技并扣资源")
	check(panel._tech_tiles["warship"].disabled and (panel._tech_tiles["warship"].get_meta("cost") as Label).text == "已有",
			"升级后显示已有")
	var actions := me.actions_left
	panel._upgrade_tiles["telescope"].pressed.emit()
	check(me.telescope == 1 and me.actions_left == actions, "升级射电望远镜不花行动点")


func test_build_and_dispatch() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	panel._build_tiles["probe"].pressed.emit()
	check(me.count(Ship.PROBE) == 1, "建造按钮造出探测器")
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


func test_colony() -> void:
	var s := fixture()
	var me := s.human()
	me.techs["colony"] = true
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
	for i in 30:
		if me.owns(c):
			break
		panel._end.pressed.emit()
	check(me.owns(c), "殖民船到达后建立星系")
	check(panel._origin_pick.item_count == 2, "新星系出现在发射源列表里")
	# 别人悄悄占了的宜居星系：规则允许当目的地，画面也不能拦，免得提示泄露谁占了哪里
	var other: Civ = s.civs[1]
	s.map.habitable[other.home] = true
	panel._build_tiles["colony"].pressed.emit()
	actions.aim_at(other.home)
	check(actions._target_cell() == other.home and not actions._go.disabled, "别人悄悄占了的宜居星系也能选，画面不泄露")
	me.techs["starship"] = true
	panel._build_tiles["starship"].pressed.emit()
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
	check(not home.is_empty() and is_equal_approx(home["r"], 0.45 * 1.4), "母星系点得中，大小和画出来的光晕一样")
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
	var probe: Ship = me.ships[-1]
	s.dispatch(me, probe.id, Vector3(1, 0, 0))
	view.refresh()
	var points: Array[Vector3] = map._predict(probe, map.PATH_TURNS)
	check(points.size() == map.PATH_TURNS + 1 and points[1].x > points[0].x, "预测接下来几个回合的位置")
	var tubes: int = map._tube_parts.size()
	check(tubes >= map.PATH_TURNS, "航线画成粗线")
	panel._end.pressed.emit()
	panel._end.pressed.emit()
	check(map._trails[probe.id].size() == 3, "记下身后的轨迹")
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
	var c := Vector3i(9, 9, 9)
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


func test_sightings_drawn() -> void:
	var s := fixture()
	var me := s.human()
	show_state(s)
	# 刷新时旧标记要等到这一帧结束才真的删掉
	await process_frame
	var before: int = map._markers.get_child_count()
	me.sightings.append({"pos": Vector3(4, 4, 4), "kind": Ship.WARSHIP, "turn": s.turn})
	me.hit_dirs.append({"at": Vector3i.ZERO, "dir": Vector3(1, 0, 0), "turn": s.turn})
	s.wakes.append({"a": Vector3(5, 5, 5), "b": Vector3(6, 5, 5), "turn": s.turn, "gone": false})
	me.wakes_seen[0] = true
	me.heard[Vector3i(9, 9, 9)] = s.turn
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
		s.light[s._li(c)] = 0.5
	s.light[s._li(Vector3i(2, 0, 0))] = 0.0
	s.black_domains.append({"center": Vector3i(2, 0, 0), "left": 3})
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
	var c := Vector3i(9, 9, 9)
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
	var s := fixture()
	var me := s.human()
	me.techs["dimension"] = true
	show_state(s)
	var cost: int = Balance.COST_REDUCE_BASE + Balance.COST_REDUCE_PER_UNIT
	check(panel._reduce_info.text.contains("1 个单位") and panel._reduce_info.text.contains("%dE" % cost), "初始携带数与费用可见")
	panel._build_tiles["miner"].pressed.emit()
	check(panel._build_tiles["reduce"].disabled, "有建造中的设施时不能降维")
	check(panel._reduce_info.text.contains("请先等建造完成"), "说明为什么要等")
	panel._end.pressed.emit()
	check(not panel._build_tiles["reduce"].disabled, "建造完成后可以降维")
	cost += Balance.COST_REDUCE_PER_UNIT
	check(panel._reduce_info.text.contains("2 个单位") and panel._reduce_info.text.contains("%dE" % cost), "费用随新采矿船更新")
	check(panel._build_tiles["reduce"].tooltip_text.contains("采矿船 1"), "悬停提供按种类计费明细")
	var energy := me.energy
	panel._build_tiles["reduce"].pressed.emit()
	check(me.energy == energy - cost and me.reduce_left == Balance.REDUCE_TURNS, "按钮按展示费用扣款并开始准备")
	for kind in panel.BUILD_ORDER:
		check(panel._build_tiles[kind].disabled, "降维期间不能建造：" + kind)
	check(panel._reduce_info.text.contains("费用已支付") and panel._reduce_info.text.contains("还剩 %d 回合" % Balance.REDUCE_TURNS),
			"显示已付费用和倒计时")
	actions._action_tiles[actions.Action.FOIL].pressed.emit()
	check(actions._go.disabled and actions._go_hint.text.contains("降维期间"), "准备中不能发射二向箔")
	for i in Balance.REDUCE_TURNS:
		panel._end.pressed.emit()
	check(me.reduced and not panel._build_tiles["probe"].disabled, "完成后建造按钮恢复")
	check(panel._reduce_info.text.contains("二维生存准备已完成"), "显示完成状态")
	await process_frame


## 规则：二维、单向著和奇异点，F5.2
func test_flat_and_line() -> void:
	var s := fixture()
	for civ in s.civs:
		civ.techs["dimension"] = true
		civ.reduced = true
	show_state(s)
	check(actions._action_tiles[actions.Action.FOIL].visible and not actions._action_tiles[actions.Action.LINE_FOIL].visible, "3D 只显示二向箔")
	actions._action_tiles[actions.Action.FOIL].pressed.emit()
	actions.aim_at(Vector3i(2, 2, 2))
	check(not actions._go.disabled, "二向箔执行按钮可用")
	actions._go.pressed.emit()
	check(s.human().foils.size() == 1, "通过执行按钮发射二向箔")
	s.launch_foil(s.civs[1], Vector3i(7, 7, 7))
	for i in 40:
		if s.all_flat():
			break
		panel._end.pressed.emit()
		await process_frame
	await settled_frame()
	check(s.all_flat() and not s.is_over(), "3D 结束后进入可玩的 2D")
	check(not panel._end.disabled, "二维可以继续结束回合")
	check(actions._action == actions.Action.LINE_FOIL and actions._action_tiles[actions.Action.LINE_FOIL].visible, "自动切换到单向著")
	check(not actions._action_tiles[actions.Action.FOIL].visible and not actions._pitch.get_parent().visible, "二维不再显示二向箔和俯仰输入")
	var segments: Dictionary = map._grid_segments(s.flattened, s.linearized)
	check(segments.size() == 180, "二维只剩一张完整网格")
	for segment in segments.values():
		check(segment[0].z == s.flat_plane and segment[1].z == s.flat_plane, "二维每条线段位于同一平面")
	await capture("two-dimensional")

	panel._build_tiles["reduce"].pressed.emit()
	s.start_reduce(s.civs[1])
	check(s.human().reduce_left == Balance.REDUCE_TURNS and panel._build_tiles["reduce"].disabled, "再次降维按钮启动准备并禁止重复操作")
	for i in Balance.REDUCE_TURNS:
		panel._end.pressed.emit()
	check(s.human().line_reduced and s.civs[1].line_reduced, "双方完成一维准备")
	actions.aim_at(Vector3i(2, 2, s.flat_plane))
	check(not actions._go.disabled, "单向著执行按钮可用")
	actions._go.pressed.emit()
	check(s.human().foils.size() == 1 and s.human().foils[0].to_line, "按钮发出单向著")
	s.launch_line_foil(s.civs[1], Vector3i(7, 7, s.flat_plane))
	var captured := false
	for i in 40:
		if s.all_linear():
			break
		panel._end.pressed.emit()
		await settled_frame()
		if not captured and not s.linearized.is_empty():
			await capture("collapsing-to-line")
			captured = true
	await settled_frame()
	check(s.all_linear(), "整张星图压成直线")
	actions._action_tiles[actions.Action.SINGULARITY].pressed.emit()
	check(not actions._go.disabled, "一维里可以发射奇异点")
	actions._go.pressed.emit()
	check(s.human().singularity_left == Balance.SINGULARITY_TURNS, "按钮发射奇异点")
	for i in Balance.SINGULARITY_TURNS:
		panel._end.pressed.emit()
	check(s.winner == "你" and panel._end.text.contains("再来一局") and overlay._status.text.contains("胜利"), "先降到零维的赢")
	segments = map._grid_segments(s.flattened, s.linearized)
	check(segments.size() == 9, "最终只有九条相邻线段，组成一条直线")
	for segment in segments.values():
		for point in segment:
			check(point.y == s.line_y and point.z == s.flat_plane, "最终网格没有残留平面")
	for c in s.flattened:
		var point: Vector3 = map._warp_point(Vector3(c))
		check(point.y == s.line_y and point.z == s.flat_plane, "所有原始网格点都投影到同一条直线")
	for bounds in map._line_env_new.values():
		check(bounds.x == s.line_y and bounds.y == s.line_y, "边界曲面也收拢到直线")
	# F5.2：降到零维时，直线缩成一个亮点
	check(map.animating() and map._zero_dot.visible, "降到零维时放动画")
	map.advance_animation(map.ZERO_ANIM_SECONDS * 0.5)
	check(map._markers.scale.x < 1.0 and map._markers.visible, "动画中星图缩向一点")
	map.advance_animation(map.ZERO_ANIM_SECONDS)
	check(not map.animating() and not map._markers.visible and not map._grid.visible and map._zero_dot.visible, "最后只剩一个亮点")
	map.redraw_grid()
	check(not map.animating() and map._zero_dot.visible and not map._grid.visible, "换局面时直接画成零维，不放动画")
	await capture("zero-dimensional")


## 胜负分出以后不再按按钮，画面每帧自己把还没压完的空间压完。
func test_post_victory_collapse() -> void:
	# 扩散得慢时，有的步一个格子也没多压没（边界面还是变了），这样才测得到这种步
	var old_spread := Balance.FOIL_SPREAD
	Balance.FOIL_SPREAD = 0.3
	var s := fixture()
	s.civs[0].reduced = true
	s._unfold_foil(s.civs[1].home)
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
	check(panel._res_values["energy"].text.begins_with(str(ai.energy)), "资源栏显示 AI-2 的能量")
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
	check(ai.count(Ship.PROBE) == 1, "接管后可以替它建造")
	check(s.history.any(func(h): return h["civ"] == 1 and h["name"] == "build" and not h["ai"]), "这次建造算玩家的操作")
	view.debug._autoplay.toggled.emit(true)
	check(ai.is_ai, "再勾上就交还给 AI")
	view.debug.set_view(0)


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
	check(Balance.COST_TURN == turn_cost - 3, "「恢复默认」换回 balance.gd 里的数值")
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
	check(Balance.COST_TURN == turn_cost - 3, "不用方案时新开一局是 balance.gd 里的数值")
	check(dbg._write_back.visible == BalancePresets.can_write_back(), "只有编辑器版才有「写回 balance.gd」")
	dbg._tabs.current_tab = 0


## 自己玩的局里你灭亡了：面板出现「继续往下看」，按了以后其余文明接着打，可以一直播放。
func test_debug_after_death() -> void:
	var found := false
	for seed_value in 30:
		var s := _debug_game(seed_value, false)
		while not view.state.is_over() and view.debug.step_forward(true, false):
			pass
		if view.debug.can_continue_after_death():
			found = true
			break
	check(found, "找得到你先灭亡、还剩几个 AI 的对局")
	if not found:
		return
	view.refresh()
	check(view.debug._after_death.visible, "你灭亡后面板上有「继续往下看」")
	check(not view.debug.step_forward(false), "这时对局已经结束，不能往前走")
	var steps: int = view.state.steps
	view.debug._after_death.pressed.emit()
	check(not view.state.is_over() and not view.state.human().alive, "按了以后对局继续，你还是灭亡的")
	check(view.state.steps == steps and not view.debug._after_death.visible, "重算的是你灭亡的那一回合")
	check(overlay._status.text.contains("你已灭亡"), "状态栏写着你已灭亡")
	check(view.debug.step_forward(false), "可以接着自动播放（没有要等的玩家）")
	view.debug.set_view(1)
	check(view.viewed() == view.state.civs[1], "可以换成活着的 AI 的视角接着看")
	view.debug.set_view(0)
