extends SceneTree
## 独立演示的数学不变量、回放与控件测试。
## --headless --path game --script res://tests/run_unfolding_tests.gd
## 去掉 --headless，并在 -- 后加 output=<目录>，同时截图检查关键帧。

const Layout := preload("res://rules/unfolding_layout.gd")
var checks := 0
var failures := 0
var output := ""
var demo


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			output = arg.trim_prefix("output=")
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	var script: Script = load("res://rules/unfolding_layout.gd")
	if not script.can_instantiate():
		push_error("布局脚本不能编译")
		quit(1)
		return
	test_bijection()
	test_expansion()
	demo = load("res://demos/dimension_unfolding.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.set_process(false)
	await test_controls()
	await test_frames()
	print("展开演示：%d 次检查，%d 个失败" % [checks, failures])
	quit(1 if failures > 0 or checks == 0 else 0)


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
	await capture("corner-wave")


func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "保存截图")
