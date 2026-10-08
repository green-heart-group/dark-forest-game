extends Node3D
## 独立的空间展开演示。只控制演示布局和相机，不创建或修改正式对局。

const Layout := preload("res://demos/unfolding_layout.gd")
const DURATION := 12.0
const COLORS: Array[Color] = [Color("5375bd"), Color("647dd4"), Color("7d8ee0"),
		Color("929ee8"), Color("64b9c7"), Color("54ccb9"), Color("8ad7b2"),
		Color("b4df9b"), Color("d7df9b")]
const GOLD := Color("ffc875")

var progress := 0.0
var playing := false
var single := true
var anchor := Vector3i(4, 4, 4)
var speed := 1.0
var layout := {}
var yaw := 35.0
var pitch := 32.0
var zoom := 1.0
var auto_frame := true
var _dragging := false
var _last_pointer := Vector2.ZERO
var _world := Node3D.new()
var camera := Camera3D.new()
var instances := MultiMeshInstance3D.new()
var _guides := MeshInstance3D.new()
var _numbers: Array[Label] = []
var _number_points := PackedVector3Array()
var _focus := Vector3.ZERO
var _frame_size := 15.0
var play_button: Button
var replay_button: Button
var mode: OptionButton
var timeline: HSlider
var anchor_inputs: Array[SpinBox] = []
var _status: Label
var _counter: Label
var _percent: Label
var _note: Label


func _ready() -> void:
	_world.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	add_child(_world)
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.far = 300.0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("0c1220")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b6d6f2")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.7
	var box := BoxMesh.new()
	instances.multimesh = MultiMesh.new()
	instances.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instances.multimesh.use_colors = true
	instances.multimesh.mesh = box
	instances.multimesh.instance_count = Layout.COUNT
	instances.material_override = material
	_world.add_child(instances)
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.vertex_color_use_as_albedo = true
	lines.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guides.material_override = lines
	_world.add_child(_guides)
	_build_ui()
	get_viewport().size_changed.connect(_update_camera)
	set_progress(0.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Theme.new()
	ui.theme.default_font = load("res://view/ui_font.tres")
	ui.theme.default_font_size = 17
	layer.add_child(ui)
	_number_points.resize(9)
	for z in 9:
		var number := _label(ui, str(z + 1), 20, Color.WHITE)
		number.add_theme_color_override("font_outline_color", Color("0c1220"))
		number.add_theme_constant_override("outline_size", 5)
		_numbers.append(number)
	var heading := VBoxContainer.new()
	heading.position = Vector2(30, 24)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(heading)
	_label(heading, "DARK FOREST  /  MOTION STUDY 01", 14, Color("81a1bd"))
	_label(heading, "空间展开", 32, Color("edf4ff"))
	_label(heading, "9×9×9 → 27×27 · 每个格子保留自己的位置编号", 17, Color("9cacbf"))
	var metrics := VBoxContainer.new()
	metrics.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	metrics.position = Vector2(-290, 28)
	metrics.size.x = 260
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(metrics)
	_counter = _label(metrics, "", 24, GOLD)
	_status = _label(metrics, "", 16, Color("acbecf"))
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = -182
	panel.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color("151f30")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	panel.add_child(stack)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 12)
	stack.add_child(transport)
	play_button = _button(transport, "播放", toggle_play)
	replay_button = _button(transport, "重播", replay)
	timeline = HSlider.new()
	timeline.min_value = 0.0
	timeline.max_value = 1.0
	timeline.step = 0.001
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.custom_minimum_size.x = 200
	timeline.tooltip_text = "拖动进度可前后检查；拖动后暂停播放"
	timeline.value_changed.connect(func(value: float): seek(value))
	transport.add_child(timeline)
	_percent = _label(transport, "0%", 18, GOLD)
	_percent.custom_minimum_size.x = 52
	var rate := OptionButton.new()
	for text in ["0.5×", "1×", "2×"]:
		rate.add_item(text)
	rate.select(1)
	rate.item_selected.connect(func(index: int): speed = [0.5, 1.0, 2.0][index])
	transport.add_child(rate)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 12)
	stack.add_child(options)
	mode = OptionButton.new()
	mode.add_item("单列 · 9 → 3×3")
	mode.add_item("全图 · 729 → 27×27")
	mode.custom_minimum_size = Vector2(220, 40)
	mode.item_selected.connect(set_mode)
	options.add_child(mode)
	_label(options, "锚点", 16, Color("acbecf"))
	for axis in 3:
		_label(options, ["x", "y", "z"][axis], 16, Color("acbecf"))
		var input := SpinBox.new()
		input.min_value = 0
		input.max_value = 8
		input.value = anchor[axis]
		input.custom_minimum_size.x = 68
		input.value_changed.connect(func(value: float): set_anchor_axis(axis, int(value)))
		options.add_child(input)
		anchor_inputs.append(input)
	var framing := CheckButton.new()
	framing.text = "自动取景"
	framing.button_pressed = true
	framing.tooltip_text = "关闭后相机不跟随展开，适合减少镜头运动"
	framing.toggled.connect(func(value: bool): auto_frame = value; _update_camera())
	options.add_child(framing)
	_button(options, "俯视", top_view)
	_button(options, "重置视角", reset_view)
	_note = _label(stack, "", 15, Color("9cacbf"))


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(76, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func set_mode(index: int) -> void:
	single = index == 0
	mode.select(index)
	playing = false
	reset_view()
	set_progress(0.0)


func set_anchor_axis(axis: int, value: int) -> void:
	anchor[axis] = clampi(value, 0, 8)
	playing = false
	set_progress(progress)


func seek(value: float) -> void:
	playing = false
	set_progress(value)


func toggle_play() -> void:
	if progress >= 1.0:
		set_progress(0.0)
	playing = not playing
	play_button.text = "暂停" if playing else "播放"


func replay() -> void:
	set_progress(0.0)
	playing = true
	play_button.text = "暂停"


func _process(delta: float) -> void:
	if playing:
		set_progress(progress + delta * speed / DURATION)


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	if progress >= 1.0:
		playing = false
	layout = Layout.sample(progress, anchor, single)
	var points: PackedVector3Array = layout["positions"]
	instances.multimesh.visible_instance_count = points.size()
	for i in points.size():
		var c: Vector3i = layout["cells"][i]
		var q: float = layout["amounts"][i]
		var side := lerpf(0.48, 0.87, Layout.spread(q))
		var size := Vector3(side, side, lerpf(0.48, 0.055, q * q))
		instances.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(size), points[i]))
		var color := GOLD if c == anchor else COLORS[c.z]
		instances.multimesh.set_instance_color(i, color)
		if c.x == anchor.x and c.y == anchor.y:
			_number_points[c.z] = points[i] + Vector3(0, 0, size.z / 2.0 + 0.08)
			_numbers[c.z].visible = single
	_draw_guides()
	timeline.set_value_no_signal(progress)
	_percent.text = "%d%%" % floori(progress * 100)
	play_button.text = "暂停" if playing else "播放"
	_counter.text = "%d 格 · 全部保留" % points.size()
	_status.text = "%d / %d 列已展开" % [layout["finished"], 1 if single else 81]
	_note.text = "金色为固定锚点 · 颜色对应原 z 层 · 拖动旋转 / 滚轮缩放 · 空格播放 · ← → 逐步查看"
	_update_camera()


func _draw_guides() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, layout["cells"].size(), 9):
		var c: Vector3i = layout["cells"][i]
		var q: float = layout["amounts"][i]
		var color := Color("668eaa")
		color.a = (1.0 - q) * 0.32
		for z in 8:
			for p in [layout["positions"][i + z], layout["positions"][i + z + 1]]:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(p)
		var center := Vector3(layout["cx"][c.x], layout["cy"][c.y], anchor.z - 0.04)
		var half := 0.5 + Layout.spread(q)
		var corners := [Vector3(-half, -half, 0), Vector3(half, -half, 0),
				Vector3(half, half, 0), Vector3(-half, half, 0)]
		color = GOLD if c.x == anchor.x and c.y == anchor.y else Color("63849e")
		color.a = q * 0.4
		for edge in 4:
			for p in [corners[edge], corners[(edge + 1) % 4]]:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(center + p)
	mesh.surface_end()
	_guides.mesh = mesh


func reset_view() -> void:
	yaw = 35.0
	pitch = 32.0
	zoom = 1.0
	_update_camera()


func top_view() -> void:
	pitch = 89.9
	yaw = 0.0
	_update_camera()


func _update_camera() -> void:
	if layout.is_empty():
		return
	var bounds := AABB(_world.to_global(layout["positions"][0]), Vector3.ZERO)
	for p in layout["positions"]:
		bounds = bounds.expand(_world.to_global(p))
	bounds = bounds.grow(0.7)
	if auto_frame:
		_focus = bounds.get_center()
	var orbit := Vector3(cos(deg_to_rad(pitch)) * sin(deg_to_rad(yaw)),
			sin(deg_to_rad(pitch)), cos(deg_to_rad(pitch)) * cos(deg_to_rad(yaw)))
	camera.position = _focus + orbit * 80.0
	camera.look_at(_focus)
	if auto_frame:
		var projected := AABB(camera.to_local(bounds.position), Vector3.ZERO)
		for i in 8:
			projected = projected.expand(camera.to_local(bounds.get_endpoint(i)))
		var viewport := get_viewport().get_visible_rect().size
		var aspect := viewport.x / maxf(1.0, viewport.y)
		_frame_size = maxf(projected.size.y / 0.57, projected.size.x / (aspect * 0.85))
	camera.size = maxf(5.0, _frame_size) * zoom
	# 留出下方控制栏；相机在自己的向上方向平移，物体在画面里上移。
	camera.v_offset = -camera.size * 0.035
	for z in 9:
		_numbers[z].position = camera.unproject_position(_world.to_global(_number_points[z])) - _numbers[z].size / 2.0


func _input(event: InputEvent) -> void:
	# 在控件上松开鼠标也要结束旋转；拖动状态以按下 / 松开事件为准。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_last_pointer = event.position
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampf(zoom * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.4, 3.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var movement: Vector2 = event.position - _last_pointer
		_last_pointer = event.position
		yaw -= movement.x * 0.35
		pitch = clampf(pitch + movement.y * 0.35, 8.0, 89.9)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		match event.physical_keycode:
			KEY_SPACE: toggle_play()
			KEY_R: replay()
			KEY_T: top_view()
			KEY_V: reset_view()
			KEY_LEFT: seek(progress - 0.02)
			KEY_RIGHT: seek(progress + 0.02)
