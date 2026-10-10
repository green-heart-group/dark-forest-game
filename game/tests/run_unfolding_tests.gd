extends SceneTree
## 独立演示的数学不变量、回放与控件测试。
## --headless --path game --script res://tests/run_unfolding_tests.gd
## 去掉 --headless，并在 -- 后加 output=<目录>，同时截图检查关键帧。

const Layout := preload("res://rules/unfolding_layout.gd")
const TestLog := preload("res://tests/test_log.gd")
var results := TestLog.new()
var output := ""
var demo
## 跑过的测试名字（没写进 run() 的测试会被查出来）
var _ran: Array[String] = []


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			output = arg.trim_prefix("output=")
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	results.check(ok, message)


func check_eq(actual, expected, message: String) -> void:
	results.check_eq(actual, expected, message)


func run_test(test: Callable) -> void:
	var name := test.get_method()
	_ran.append(name)
	if not results.wants(name):
		return
	results.begin(name)
	await test.call()
	results.end()


func run() -> void:
	var script: Script = load("res://rules/unfolding_layout.gd")
	if not script.can_instantiate():
		push_error("布局脚本不能编译")
		quit(1)
		return
	await run_test(test_bijection)
	await run_test(test_expansion)
	await run_test(test_fixed_mapping)
	await run_test(test_spread)
	await run_test(test_spread_origins)
	await run_test(test_anticipatory_motion)
	demo = load("res://demos/dimension_unfolding.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	await run_test(test_controls)
	await run_test(test_frames)
	await run_test(test_curve_display)
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_") and not _ran.has(name):
			results.fail("没写进 run() 的列表，没有跑", name)
	quit(results.finish("展开演示"))


func test_bijection() -> void:
	for i in 8:
		check(Vector2(Layout.RING[i]).cross(Vector2(Layout.RING[(i + 1) % 8])) < 0, "从上方看顺时针排列")
	for layer in 9:
		var destinations := {}
		var ids := {}
		for x in 9:
			for y in 9:
				for z in 9:
					var c := Vector3i(x, y, z)
					var p := Layout.to_plane(c, layer)
					check(p.x >= 0 and p.x < 27 and p.y >= 0 and p.y < 27, "二维范围")
					check(not destinations.has(p), "每个目标位置唯一")
					check(Layout.from_plane(p, layer) == c, "映射可逆")
					destinations[p] = true
					ids[Layout.cell_id(c)] = true
		check(destinations.size() == 729 and ids.size() == 729, "不丢格子或编号")
		check(Layout.slot(layer, layer) == Vector2i.ZERO, "锚点层在局部中心")


func test_expansion() -> void:
	for anchor in [Vector3i(4, 4, 4), Vector3i(0, 0, 0), Vector3i(8, 4, 8), Vector3i(8, 8, 2)]:
		var initial := Layout.sample(0.0, anchor)
		var final := Layout.sample(1.0, anchor)
		var anchor_index := Layout.cell_id(anchor)
		check(final["finished"] == 81, "所有列都展开")
		for i in 729:
			var c: Vector3i = initial["cells"][i]
			check(initial["positions"][i].is_equal_approx(Vector3(c)), "初始是原三维格子")
			var p := Layout.to_plane(c, anchor.z)
			var a := Layout.to_plane(anchor, anchor.z)
			var expected := Vector3(anchor.x + p.x - a.x, anchor.y + p.y - a.y, anchor.z)
			check(final["positions"][i].is_equal_approx(expected), "终态与逻辑映射一致")
		for step in 101:
			var t := step / 100.0
			var sample := Layout.sample(t, anchor)
			check(sample["positions"][anchor_index].is_equal_approx(Vector3(anchor)), "锚点始终固定")
			check(sample["cells"] == initial["cells"], "回放编号顺序不变")
			for x in 9:
				for y in 9:
					var extent := Layout.spread(sample["q"][x * 9 + y])
					if x < 8:
						var neighbor := Layout.spread(sample["q"][(x + 1) * 9 + y])
						check(sample["cx"][x + 1] - sample["cx"][x] >= 1 + extent + neighbor - 0.00001,
								"相邻列有足够横向空间")
					if y < 8:
						var neighbor := Layout.spread(sample["q"][x * 9 + y + 1])
						check(sample["cy"][y + 1] - sample["cy"][y] >= 1 + extent + neighbor - 0.00001,
								"相邻列有足够纵向空间")
		# 对终场前后的连续性单独检查，防止最后一帧突然挪动外圈。
		var almost := Layout.sample(0.9999, anchor)
		for i in 729:
			check(almost["positions"][i].distance_to(final["positions"][i]) < 0.001, "终场没有跳变")
		var forward := Layout.sample(0.43, anchor)
		Layout.sample(0.91, anchor)
		check(forward == Layout.sample(0.43, anchor), "向后拖动完全可重现")
	for layer in 9:
		var anchor := Vector3i(4, 4, layer)
		for step in 21:
			var sample := Layout.sample(step / 20.0, anchor, true)
			check(sample["positions"].size() == 9, "单列始终是九个格子")
			check(sample["positions"][layer].is_equal_approx(Vector3(anchor)), "单列任意锚点层固定")
			# 真正的方块（不只中心点）在同一列展开时也不应穿插。
			var q: float = sample["amounts"][0]
			var side := lerpf(0.48, 0.87, Layout.spread(q))
			var size := Vector3(side, side, lerpf(0.48, 0.055, q * q))
			for a in 9:
				for b in range(a + 1, 9):
					var separation: Vector3 = (sample["positions"][a] - sample["positions"][b]).abs()
					check(separation.x >= size.x or separation.y >= size.y or separation.z >= size.z,
							"单列方块没有相交")


func test_fixed_mapping() -> void:
	var cubes := {}
	var planes := {}
	for i in Layout.COUNT:
		var c := Layout.line_origin(i)
		var p := Layout.fixed_plane(c)
		check(c.clamp(Vector3i.ZERO, Vector3i.ONE * 8) == c, "三维坐标在 9×9×9 里")
		check(p.clamp(Vector2i.ZERO, Vector2i.ONE * 26) == p, "二维坐标在 27×27 里")
		check(not cubes.has(c) and not planes.has(p), "三维、二维都没有重复的格子")
		cubes[c] = true
		planes[p] = true
		check_eq(Layout.line_index(c), i, "三维到一维可还原")
		check_eq(Layout.plane_to_line(p), i, "二维到一维和三维到一维一致")
		check_eq(Layout.plane_origin(p), c, "二维可还原到原来的三维格子")
		if i > 0:
			var before := Layout.line_origin(i - 1)
			check_eq(absi(c.x - before.x) + absi(c.y - before.y) + absi(c.z - before.z), 1, "直线上相邻的格子在三维里也相邻")
			var flat := Layout.fixed_plane(before)
			check_eq(absi(p.x - flat.x) + absi(p.y - flat.y), 1, "直线上相邻的格子在平面上也相邻")
	check(cubes.size() == 729 and planes.size() == 729, "不丢格子")
	# 选这种排法的原因：原来相距 4 格以上、展开后在平面上紧挨着的格子对很少（按列展开时有 378 对）。
	var far_neighbors := 0
	for p in planes:
		for step in [Vector2i(1, 0), Vector2i(0, 1)]:
			if planes.has(p + step) and Vector3(Layout.plane_origin(p) - Layout.plane_origin(p + step)).length() >= 4.0:
				far_neighbors += 1
	check(far_neighbors <= 18, "原来远的格子很少在平面上变成紧挨着（%d 对）" % far_neighbors)


func test_spread() -> void:
	var cases: Array = [
		[{"at": Vector3i(4, 4, 4), "start": 0.0}],
		[{"at": Vector3i(0, 0, 8), "start": 0.0}],
		[{"at": Vector3i(1, 2, 3), "start": 0.0}, {"at": Vector3i(7, 6, 6), "start": 0.0}],
		[{"at": Vector3i(1, 2, 3), "start": 0.0}, {"at": Vector3i(7, 6, 6), "start": 5.0}],
		[{"at": Vector3i(4, 4, 4), "start": 0.0}, {"at": Vector3i(6, 5, 6), "start": 1.5}],
	]
	for origins in cases:
		var start: Dictionary = Layout.sample_spread(-Layout.SPACE_LEAD, origins)
		var end := Layout.spread_duration(origins)
		var final := Layout.sample_spread(end, origins)
		var base: Vector3 = final["base"]
		check_eq(final["finished"], Layout.COUNT, "最后每个格子都落到平面")
		var spots := {}
		for i in Layout.COUNT:
			var c: Vector3i = final["cells"][i]
			check(start["positions"][i].is_equal_approx(Vector3(c)), "开始时是原来的三维格子")
			var p := Layout.fixed_plane(c)
			check(final["positions"][i].is_equal_approx(Vector3(p.x + base.x, p.y + base.y, base.z)),
					"最后落在固定映射的位置")
			spots[final["positions"][i]] = true
		check_eq(spots.size(), Layout.COUNT, "最后没有两个格子重叠")
		var almost := Layout.sample_spread(end - 0.001, origins)
		for i in Layout.COUNT:
			check(almost["positions"][i].distance_to(final["positions"][i]) < 0.01, "结束前后没有跳变")
		var reversed: Array = origins.duplicate()
		reversed.reverse()
		for time in [1.0, 3.7, end]:
			var a := Layout.sample_spread(time, origins)
			var b := Layout.sample_spread(time, reversed)
			var same: bool = a["amounts"] == b["amounts"]
			for i in Layout.COUNT:
				same = same and a["positions"][i].is_equal_approx(b["positions"][i])
			check(same, "原点的先后顺序不改变结果")
	# 同时展开的原点 z 平均是半整数时往上取
	check_eq(Layout.base_plane([{"at": Vector3i(1, 2, 3), "start": 0.0}, {"at": Vector3i(7, 6, 6), "start": 0.0}]).z,
			5.0, "基准平面取同时展开的原点 z 的平均，.5 往上")
	check_eq(Layout.base_plane([{"at": Vector3i(1, 2, 3), "start": 0.0}, {"at": Vector3i(7, 6, 6), "start": 2.0}]).z,
			3.0, "后来的原点不改变基准平面")


func test_spread_origins() -> void:
	var near := {"at": Vector3i(2, 2, 2), "start": 0.0}
	var late := {"at": Vector3i(8, 8, 8), "start": 6.0}
	var hit := Layout.arrivals([near, late])
	var alone := Layout.arrivals([near])
	var owners := {}
	for c in hit["owner"]:
		owners[hit["owner"][c]] = true
		var own: Dictionary = [near, late][hit["owner"][c]]
		check(is_equal_approx(hit["time"][c], own["start"] + Vector3(c - own["at"]).length()), "波及时间按自己的原点算")
		check(hit["time"][c] <= alone["time"][c] + 1e-6, "多一个原点只会让格子更早或同时被波及")
		if hit["owner"][c] == 0:
			check(is_equal_approx(hit["time"][c], alone["time"][c]), "先被近处原点波及的格子不受另一个原点影响")
	check(owners.size() == 2, "两个原点各自波及一部分格子")
	# 远处的格子不会因为另一个原点的动画提前铺平
	for time in [2.0, 5.0]:
		var both := Layout.sample_spread(time, [near, late])
		var single := Layout.sample_spread(time, [near])
		check(both["amounts"] == single["amounts"], "第二个原点开始前，展开进度和只有一个原点时一样")
	var same_time := Layout.arrivals([{"at": Vector3i(2, 4, 4), "start": 0.0}, {"at": Vector3i(6, 4, 4), "start": 0.0}])
	check_eq(same_time["owner"][Vector3i(4, 4, 4)], 0, "同时到达时归坐标小的原点")


func test_controls() -> void:
	check(not demo.playing and demo.single, "启动暂停，先展示单列")
	demo.play_button.pressed.emit()
	demo._process(3.0)
	check(demo.playing and is_equal_approx(demo.progress, 0.25), "播放按时间前进")
	demo.play_button.pressed.emit()
	demo._process(2.0)
	check(not demo.playing and is_equal_approx(demo.progress, 0.25), "暂停保持位置")
	demo.timeline.value = 0.75
	check(not demo.playing and is_equal_approx(demo.progress, 0.75), "拖动进度暂停")
	demo.replay_button.pressed.emit()
	check(demo.playing and demo.progress == 0.0, "重播从头播放")
	demo._process(20.0)
	check(not demo.playing and demo.progress == 1.0, "终场自动暂停")
	demo.mode.item_selected.emit(1)
	check(not demo.single and demo.progress == 0.0, "切换全图重置时间")
	check(demo.instances.multimesh.visible_instance_count == 729, "全图绘制729个实例")
	demo.anchor_inputs[0].value = 0
	demo.anchor_inputs[2].value = 8
	check(demo.anchor == Vector3i(0, 4, 8), "控件修改实际锚点")
	demo.seek(0.65)
	# headless 的 Dummy 渲染器不保存 MultiMesh 变换；实际渲染时验证 GPU 缓冲。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for i in demo.layout["positions"].size():
			check(demo.instances.multimesh.get_instance_transform(i).origin.is_equal_approx(demo.layout["positions"][i]),
					"渲染位置与布局一致")
	demo.top_view()
	check(is_equal_approx(demo.pitch, 89.9), "俯视")
	demo.reset_view()
	check(is_equal_approx(demo.pitch, 32.0) and demo.zoom == 1.0, "视角复位")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	demo._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2(100, 20)
	demo._unhandled_input(motion)
	check(is_equal_approx(demo.yaw, 0.0) and is_equal_approx(demo.pitch, 39.0), "拖动旋转")
	press.pressed = false
	demo._input(press)
	demo._unhandled_input(motion)
	check(is_equal_approx(demo.yaw, 0.0), "在控件上松开也停止旋转")
	press.pressed = true
	press.button_index = MOUSE_BUTTON_WHEEL_UP
	demo._unhandled_input(press)
	check(is_equal_approx(demo.zoom, 0.9), "滚轮缩放")
	demo.reset_view()
	await process_frame
	var viewport := root.get_visible_rect()
	for widget in [demo.play_button, demo.replay_button, demo.mode, demo.timeline, demo.anchor_inputs[2]]:
		check(viewport.encloses(widget.get_global_rect()), "主要控件位于屏幕内")


func test_frames() -> void:
	demo.anchor_inputs[0].value = 4
	demo.anchor_inputs[2].value = 4
	for mode_index in 2:
		demo.set_mode(mode_index)
		for t in [0.0, 0.35, 0.65, 1.0]:
			demo.seek(t)
			await capture("%s-%03d" % ["column" if demo.single else "universe", roundi(t * 100)])
	demo.top_view()
	await capture("universe-top")
	demo.anchor_inputs[0].value = 0
	demo.anchor_inputs[1].value = 0
	demo.anchor_inputs[2].value = 8
	demo.reset_view()
	demo.seek(0.55)
	check(is_equal_approx(demo.progress, 0.55), "关键帧场景停在指定进度")
	await capture("corner-wave")
	demo.anchor_inputs[0].value = 2
	demo.anchor_inputs[1].value = 3
	demo.anchor_inputs[2].value = 2
	for scene in demo.SCENES.size():
		demo.set_mode(scene + 2)
		check_eq(demo.origins().size(), 1 if scene == 0 else 2, "场景的原点个数")
		for t in [0.3, 0.6, 1.0]:
			demo.seek(t)
			check(demo.instances.multimesh.visible_instance_count == 729, "球形扩张也画 729 个格子")
			await capture("spread%d-%03d" % [scene, roundi(t * 100)])
		check_eq(demo.layout["finished"], 729, "播完时全部落到平面")


func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "保存截图")


## 规则：二维、单向著和奇异点
## 远处体素在波前到达之前逐回合向固定终点移动，不把主要位移挤在末尾。
func test_anticipatory_motion() -> void:
	for to_line in [false, true]:
		var origin := Vector3i(13, 13, 4) if to_line else Vector3i(4, 4, 4)
		var far := Vector3i(26, 26, 4) if to_line else Vector3i(8, 8, 8)
		var origins := [{"at": origin, "start": 0.0}]
		var initial := Layout.sample_spread(0.0, origins, to_line)
		var index: int = initial["cells"].find(far)
		var end := Layout.sample_spread(Layout.spread_duration(origins, to_line), origins, to_line)
		var target: Vector3 = end["positions"][index]
		var before: Vector3 = initial["positions"][index]
		for time in [0.5, 1.0, 1.5, 2.0]:
			var sample := Layout.sample_spread(time, origins, to_line)
			var point: Vector3 = sample["positions"][index]
			check(sample["amounts"][index] > 0.0, "波前到达前已经开始朝终点展开")
			check(point.distance_to(target) < before.distance_to(target), "连续半格扩散都更接近最终位置")
			before = point
		var halfway := Layout.sample_spread(Vector3(far - origin).length() / 2.0, origins, to_line)
		check(halfway["amounts"][index] > 0.1, "扩散走到一半时远处体素已有明显进度")


## 规则：二维、单向著和奇异点
## 同一条曲线覆盖全部体素，中间展开不产生新端点，二维到一维沿用原编号。
func test_curve_display() -> void:
	for input in demo.anchor_inputs:
		input.value = 4
	for mode_index in [demo.CURVE_MODE, demo.LINE_MODE]:
		demo.set_mode(mode_index)
		check(demo.curve_toggle.button_pressed, "曲线场景默认显示连线")
		for t in [0.0, 0.4, 1.0]:
			demo.seek(t)
			check_eq(demo.curve_points.size(), 729, "连线始终经过全部 729 个体素")
			var expected := {}
			for i in demo.layout["cells"].size():
				expected[demo.layout["cells"][i]] = demo.layout["positions"][i]
			for i in 729:
				var cell := Layout.line_origin(i)
				if mode_index == demo.LINE_MODE:
					var p := Layout.fixed_plane(cell)
					cell = Vector3i(p.x, p.y, demo.anchor.z)
				check(demo.curve_points[i].is_equal_approx(expected[cell]), "曲线按原始线序连接当前体素中心")
			if DisplayServer.get_name() != "headless":
				var vertices: PackedVector3Array = demo._curve.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				check_eq(vertices.size(), 1456, "渲染网格实际包含 728 段")
				for i in 728:
					check(vertices[i * 2].is_equal_approx(demo.curve_points[i]) and vertices[i * 2 + 1].is_equal_approx(demo.curve_points[i + 1]), "实际绘制连续链，不额外分支或跳格")
			check_eq(demo._ends.size(), 2, "界面只标两个真正的端点")
			if mode_index == demo.LINE_MODE and t == 1.0:
				for i in 728:
					check(demo.curve_points[i + 1].is_equal_approx(demo.curve_points[i] + Vector3.RIGHT), "终态是一格相连的唯一线段")
			await capture("curve-%s-%03d" % ["line" if mode_index == demo.LINE_MODE else "3d", roundi(t * 100)])
	demo.cells_toggle.button_pressed = false
	check(not demo.instances.visible, "可以隐藏体素单独检查连线")
	demo.curve_toggle.button_pressed = false
	check(not demo._curve.visible and not demo._ends[0].visible, "关连线也收起端点标签")
	demo.cells_toggle.button_pressed = true
	demo.set_mode(0)
	check(not demo._curve.visible, "旧单列模式不残留曲线")
