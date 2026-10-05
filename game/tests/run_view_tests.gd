extends SceneTree
## Headless scene checks or native rendering:
## godot --path game --script res://tests/run_view_tests.gd -- output=/tmp/dark-forest-shots

var _failures := 0
var _checks := 0
var _output := ""
var view

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			_output = arg.trim_prefix("output=")
	call_deferred("run_tests")

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func fixture() -> GameState:
	var s := GameState.new()
	s.map = StarMap.new()
	for pos in [Vector3i.ZERO, Vector3i(9, 9, 9)]:
		var civ := Civ.new("你" if s.civs.is_empty() else "Other", false, pos)
		civ.reduced = true
		civ.energy = 1000
		s.map.stars[pos] = StarMap.Star.SINGLE
		s.civs.append(civ)
		s.start_turn(civ)
	return s

func show_state(s: GameState) -> void:
	view.state = s
	view._draw_grid()
	view.refresh()

func settled_frame() -> void:
	view._process(view.FLAT_ANIM_SECONDS)
	await process_frame

func capture(label: String) -> void:
	if _output == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_output)
	check(root.get_texture().get_image().save_png(_output.path_join(label + ".png")) == OK, "截图保存成功")

func run_tests() -> void:
	view = load("res://view/main.tscn").instantiate()
	root.add_child(view)
	await process_frame
	await test_reduction_controls()
	var s := fixture()
	show_state(s)
	check(view._action_tiles[view.Action.FOIL].visible and not view._action_tiles[view.Action.LINE_FOIL].visible, "3D 只显示二向箔")
	view._action_tiles[view.Action.FOIL].pressed.emit()
	view._aim_at(Vector3i(2, 2, 2))
	view._go.pressed.emit()
	check(s.human().foils.size() == 1, "通过执行按钮发射二向箔")
	s.launch_foil(s.civs[1], Vector3i(7, 7, 7))
	for i in 30:
		if s.all_flat():
			break
		view._end.pressed.emit()
		await process_frame
	await settled_frame()
	check(s.all_flat() and not s.is_over(), "3D 结束后进入可玩的 2D")
	check(not view._end.disabled, "二维可以继续结束回合")
	check(view._action == view.Action.LINE_FOIL and view._action_tiles[view.Action.LINE_FOIL].visible, "自动切换到单向箔")
	check(not view._action_tiles[view.Action.FOIL].visible and not view._pitch.get_parent().visible, "二维不再显示二向箔和俯仰输入")
	var segments: Dictionary = view._grid_segments(s.flattened, s.linearized)
	check(segments.size() == 180, "二维只剩一张完整网格")
	for segment in segments.values():
		check(segment[0].z == s.flat_plane and segment[1].z == s.flat_plane, "二维每条线段位于同一平面")
	await capture("two-dimensional")

	view._build_tiles["reduce"].pressed.emit()
	s.start_reduce(s.civs[1])
	check(s.human().reduce_left == Balance.REDUCE_TURNS and view._build_tiles["reduce"].disabled, "再次降维按钮启动准备并禁止重复操作")
	for i in Balance.REDUCE_TURNS:
		view._end.pressed.emit()
	check(s.human().line_reduced and s.civs[1].line_reduced, "双方完成一维准备")
	view._aim_at(Vector3i(2, 2, s.flat_plane))
	check(not view._go.disabled, "单向箔执行按钮可用")
	view._go.pressed.emit()
	check(s.human().foils.size() == 1 and s.human().foils[0].to_line, "按钮发出单向箔")
	s.launch_line_foil(s.civs[1], Vector3i(7, 7, s.flat_plane))
	var captured := false
	for i in 30:
		if s.all_linear():
			break
		view._end.pressed.emit()
		await settled_frame()
		if not captured and not s.linearized.is_empty():
			await capture("collapsing-to-line")
			captured = true
	await settled_frame()
	check(s.all_linear() and s.winner == "平局", "双方幸存的一维结局")
	check(view._end.disabled and view._status.text.contains("直线"), "一维结束状态和禁用按钮正确")
	segments = view._grid_segments(s.flattened, s.linearized)
	check(segments.size() == 9, "最终只有九条相邻线段，组成一条直线")
	for segment in segments.values():
		for point in segment:
			check(point.y == s.line_y and point.z == s.flat_plane, "最终网格没有残留平面")
	for c in s.flattened:
		var point: Vector3 = view._warp_point(Vector3(c))
		check(point.y == s.line_y and point.z == s.flat_plane, "所有原始网格点都投影到同一条直线")
	for bounds in view._line_env_new.values():
		check(bounds.x == s.line_y and bounds.y == s.line_y, "边界曲面也收拢到直线")
	await capture("one-dimensional")

	# No button presses after combat: the normal frame loop must finish the collapse.
	s = fixture()
	s.civs[1].reduced = false
	s._unfold_foil(s.civs[1].home)
	show_state(s)
	check(s.is_over() and s.collapse_pending(), "提前胜负测试确实还有空间待压缩")
	var turn := s.turn
	var energy := s.human().energy
	for i in 40:
		view._process(view.FLAT_ANIM_SECONDS)
		await process_frame
		if not s.collapse_pending() and view._warp_t >= 1.0:
			break
	check(s.all_flat() and s.turn == turn and s.human().energy == energy, "结束后的动画驱动空间完成，不产生额外回合或收入")
	await capture("post-victory-collapse")
	view.queue_free()
	await process_frame
	print("View checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures else 0)


func test_reduction_controls() -> void:
	var s := fixture()
	var me := s.human()
	me.reduced = false
	me.mineral = 100
	show_state(s)
	check(view._reduce_info.text.contains("1 个单位") and view._reduce_info.text.contains("15E"), "初始携带数与费用可见")
	view._build_tiles["miner"].pressed.emit()
	check(view._build_tiles["reduce"].disabled, "有建造队列时禁用降维按钮")
	check(view._reduce_info.text.contains("请先完成"), "可见说明解释等待建造的原因")
	view._end.pressed.emit()
	check(not view._build_tiles["reduce"].disabled, "建造完成后可以启动降维")
	check(view._reduce_info.text.contains("2 个单位") and view._reduce_info.text.contains("20E"), "费用随新采矿船更新")
	check(view._build_tiles["reduce"].tooltip_text.contains("采矿船 1"), "悬停提供按种类计费明细")
	await process_frame
	var scroll := view._reduce_info.get_parent().get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(view._reduce_info)
	await capture("reduction-costs")
	var energy := me.energy
	view._build_tiles["reduce"].pressed.emit()
	check(me.energy == energy - 20 and me.reduce_left == Balance.REDUCE_TURNS, "按钮按展示费用扣款并启动三回合准备")
	for kind in view._build_tiles:
		check(view._build_tiles[kind].disabled, "降维期间禁用建造按钮：" + kind)
	check(view._reduce_info.text.contains("费用已支付") and view._reduce_info.text.contains("还剩 3 回合"), "显示已付费用和倒计时")
	for action in [view.Action.WARSHIP, view.Action.COLONY, view.Action.DOMAIN, view.Action.FOIL]:
		view._action_tiles[action].pressed.emit()
		check(view._go.disabled and view._go_hint.text.contains("降维期间"), "准备中无法通过界面投放新单位")
	view._action_tiles[view.Action.SCOUT].pressed.emit()
	check(not view._go.disabled, "准备中仍可探测")
	await process_frame
	scroll.ensure_control_visible(view._reduce_info)
	await capture("reduction-in-progress")
	for i in Balance.REDUCE_TURNS - 1:
		view._end.pressed.emit()
		check(not me.reduced and view._reduce_info.text.contains("还剩 %d 回合" % me.reduce_left), "每回合更新剩余时间")
	view._end.pressed.emit()
	check(me.reduced and not view._build_tiles["probe"].disabled, "完成后建造按钮恢复")
	check(view._reduce_info.text.contains("二维生存准备已完成"), "显示完成状态")
