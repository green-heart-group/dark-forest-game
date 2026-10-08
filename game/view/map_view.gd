extends Node3D
## 3D 星图：相机、空间网格和压平动画、坐标轴、鼠标所指和选中的东西，以及每次刷新重画的标记。
## 只画正在看的文明知道的东西：自己的星系和单位、视野、传回来的情报、看到的舰船和航迹。
## 视角操作见 CONTROLS_TEXT（F4.1）。单击星图上画出来的东西把它选中（贴着轮廓画一个圆圈），并发出 cell_clicked；
## 单击空处不选中任何东西，只发出 cell_clicked（瞄准空格子用）。

const Widgets := preload("res://view/widgets.gd")
const WindowSettings := preload("res://view/window_settings.gd")

## 点了星图上的格子（松开鼠标时没怎么动才算点击，否则是拖动旋转）
signal cell_clicked(c: Vector3i)

const STAR_COLORS := {
	StarMap.Star.SINGLE: Color(0.72, 0.77, 0.85, 0.35),
	StarMap.Star.DOUBLE: Color(0.72, 0.77, 0.85, 0.35),
	StarMap.Star.TRIPLE: Color(0.72, 0.77, 0.85, 0.35),
}
const COLOR_MINE := Color(0.3, 0.6, 1.0)
const COLOR_KNOWN := Color(1.0, 0.15, 0.15)
const COLOR_HIDDEN_AI := Color(0.7, 0.7, 0.7)
const COLOR_CONE := Color(0.2, 1.0, 1.0, 0.18)
const COLOR_BEAM := Color(1.0, 0.3, 1.0, 0.18)
const COLOR_RECORD_HIT := Color(1.0, 0.9, 0.0)
## 方向预览画多远：足够穿过整张星图
const SHIP_PREVIEW_LENGTH := 16.0
const COLOR_RECORD_EMPTY := Color(0.5, 0.5, 0.6, 0.5)
const COLOR_COLONY_SHIP := Color(0.3, 1.0, 0.5)
const COLOR_FOIL := Color(1.0, 1.0, 1.0)
const COLOR_FOIL_COLUMN := Color(1.0, 1.0, 1.0, 0.1)
## 被压平的区域：画成一层薄片
const COLOR_FLAT := Color(0.8, 0.75, 1.0, 0.35)
const COLOR_DYSON := Color(1.0, 0.8, 0.2)
const COLOR_MINER := Color(0.75, 0.55, 0.35)
const COLOR_STARSHIP := Color(0.3, 0.9, 1.0)
const COLOR_DOMAIN := Color(0.25, 0.22, 0.38, 0.16)
const COLOR_DOMAIN_EDGE := Color(0.55, 0.45, 0.9)
const COLOR_BROADCAST := Color(1.0, 0.5, 0.8)
const COLOR_BUNKER := Color(0.6, 0.65, 0.75)
## 自己的视野：星系和星舰是球，探测器是圆锥
const COLOR_VISION := Color(0.3, 0.6, 1.0, 0.035)
const COLOR_PROBE_VISION := Color(0.2, 1.0, 1.0, 0.06)
## 二维、一维里视野和预警范围画成的圆片、长条有多厚
const FLAT_THICKNESS := 0.08
## 看到的别人的舰船、航迹，预警系统报告的东西，被打时知道的打击方向
const COLOR_SIGHTING := Color(1.0, 0.35, 0.35)
const COLOR_WAKE := Color(1.0, 0.45, 0.45)
const COLOR_ALERT := Color(1.0, 0.6, 0.1)
const COLOR_HIT_DIR := Color(1.0, 0.25, 0.25)
## 自己的单位，按种类上色
const SHIP_COLORS := {
	Ship.PROBE: Color(0.2, 1.0, 1.0),
	Ship.WARSHIP: Color(1.0, 0.55, 0.1),
	Ship.COLONY: Color(0.3, 1.0, 0.5),
	Ship.STARSHIP: Color(0.3, 0.9, 1.0),
	Ship.DEVOURER: Color(0.8, 0.45, 1.0),
	Ship.GRAIN: Color(1.0, 0.3, 1.0),
	Ship.SOPHON: Color(1.0, 1.0, 0.6),
}
## 坐标轴颜色：x 红、y 绿、z 蓝。面板里的 x、y、z 输入框用同样的颜色。
const AXIS_COLORS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.4, 1.0, 0.4), Color(0.4, 0.6, 1.0)]

const NO_CELL := Vector3i(-1, -1, -1)
## 东西画得很小（离得远）时，鼠标离它多近（像素）也算点中
const PICK_MIN_PX := 10.0
## 瞄准空格子时，鼠标离格子中心多近（像素）才算指着它
const PICK_PX := 24.0
## 选中圈、鼠标所指的圈离东西的轮廓多远
const OUTLINE_GAP := 0.04
## 情报过了多少回合以后画得最淡
const INTEL_FADE_TURNS := 20.0
const FLAT_ANIM_SECONDS := 1.2
## 降到零维的动画（F5.2）：整条直线越缩越快，缩成一个亮点
const ZERO_ANIM_SECONDS := 2.0

## 相机：开局的角度（课本上常见的画法：x 轴朝左前方，y 轴朝右，z 轴朝上）、远近的范围
const CAM_PITCH := -25.0
const CAM_YAW := 115.0
const CAM_DISTANCE := 17.0
const CAM_MIN_DISTANCE := 4.0
const CAM_MAX_DISTANCE := 2400.0
## 展开时自动拉远到能看全整张图，但不超过这么远（再远星系就看不清了）
const FIT_MAX_DISTANCE := 120.0
## 一维的视角：俯仰角和远近（看得到附近四五十格）
const LINE_PITCH := -30.0
const LINE_DISTANCE := 30.0
## 视角中心最多移出星图多远（格）
const CAM_MARGIN := 3.0
## 相机追上目标位置的快慢（越大越快）
const CAM_SMOOTH := 14.0
## 按住键时：每秒转多少度、每秒平移多少个画面高度、每秒拉近拉远多少倍
const KEY_TURN_SPEED := 90.0
const KEY_PAN_SPEED := 0.6
const KEY_ZOOM_SPEED := 1.8
## 视角操作说明（星图左上角「操作」里显示）
const CONTROLS_TEXT := "左键拖动：旋转　右键 / 中键拖动：平移　滚轮：缩放　双击格子：移到中心\nWASD：平移　Q / E：旋转　R / F：俯仰　Z / X：缩放　按住 Shift 更快\nH：回到母星　V：重置视角　T：俯视　G：切换网格\n一维时：拖动和 A / D 沿直线走，V 回到自己的据点"

## 网格怎么画（F4.2）：点阵；视野内画网格线；点阵加视野内的网格线；完整网格线
enum Grid { DOTS, VISION_LINES, DOTS_AND_VISION, ALL_LINES }
const GRID_NAMES := {Grid.DOTS: "点阵", Grid.VISION_LINES: "视野内网格线",
		Grid.DOTS_AND_VISION: "点阵 + 视野内网格线", Grid.ALL_LINES: "完整网格线"}
## 选中的东西：贴着轮廓的黄色圆圈
const COLOR_SELECTED := Color(1.0, 0.95, 0.35)
const COLOR_GRID_LINE := Color(1, 1, 1, 0.025)
const COLOR_GRID_LINE_VISION := Color(0.6, 0.8, 1.0, 0.07)
const COLOR_DOT := Color(1, 1, 1, 0.22)
const COLOR_DOT_VISION := Color(0.7, 0.85, 1.0, 0.6)

## 波前数量只限制显示，不限制传播。
const BROADCAST_LIMIT := 3
## 航迹（F4.3）：在飞的单位往后预测几个回合、身后留几个回合的轨迹、线有多粗
const PATH_TURNS := 4
const TRAIL_TURNS := 6
const PATH_WIDTH := 0.03

## 概览保留全部可见单位与敌情，航线和设施按选择展开。
var detailed := false
var _wave_nodes: Array[MeshInstance3D] = []

var main: Node
var state: GameState:
	get: return main.state

var _pivot := Node3D.new()
## 星图的所有内容（网格、坐标轴、标记）都放在这个节点下，直接用规则里的坐标。
## 规则用右手系、z 轴向上；Godot 是 y 轴向上，所以把这个节点绕 x 轴转一下：
## 规则的 x、y、z 分别对应 Godot 的 x、-z、y。
var _world := Node3D.new()
var _camera := Camera3D.new()
## 相机现在的位置：视角中心（规则坐标）、水平角、俯仰角、离中心多远。
## 操作只改 _goal_xxx，每帧让现在的值平滑地追上去。
var _focus := Vector3.ZERO
var _yaw := CAM_YAW
var _pitch := CAM_PITCH
var _distance := CAM_DISTANCE
var _goal_focus := Vector3.ZERO
var _goal_yaw := CAM_YAW
var _goal_pitch := CAM_PITCH
var _goal_distance := CAM_DISTANCE
## 正在用哪个鼠标键拖动（没在拖动时为 MOUSE_BUTTON_NONE）：左键旋转，右键、中键平移
var _drag_button := MOUSE_BUTTON_NONE
var _last_pointer := Vector2.ZERO
## 网格画法（Grid 里的一个）
var grid_mode := Grid.DOTS
## 空间网格的点阵
var _dots := MultiMeshInstance3D.new()
## 网格按谁的视野画：上次画网格时的视野（observers 的结果），变了才重画
var _grid_eyes: Array[Dictionary] = []
## 自己单位身后的轨迹：单位编号 -> 最近几个回合的位置（只是画面记的，换局面时清空）
var _trails: Dictionary[int, Array] = {}
## 这次刷新要画的粗线（航线、轨迹、看到的航迹）：每项是 [起点, 终点, 颜色, 粗细]，最后一起画
var _tube_parts: Array[Array] = []
## 每次刷新重画的标记
var _markers := Node3D.new()
## 空间网格。保留所有格子，位置随着布局变化。
var _grid := MeshInstance3D.new()
## 每个原格子展开后留下独立薄片。
var _funnel := MeshInstance3D.new()
## 过渡进度，0 到 1
var _warp_t := 1.0
## 降到零维：有没有文明已经降到零维、动画进度（0 到 1）、缩向哪一点、最后剩下的亮点
var _zero_on := false
var _zero_t := 1.0
var _zero_point := Vector3.ZERO
var _zero_dot := MeshInstance3D.new()
## 上次画的压缩形状（见 _collapse_shape），变了才放过渡动画
var _shape := []
var _layout_old := {}
var _layout_new := {}
var _amounts := {}
var _layout_epoch := -1
var _axes := Node3D.new()
var _last_show_vision := false
## 进入一维后已经对准过自己的据点（_frame_line）
var _framed_line := false
## 鼠标点选：按下的位置
var _press_pos := Vector2.ZERO
## 鼠标停在哪个格子上（没有时为 NO_CELL），指着的东西（_pickables 里的一项，指着空格子时为空）
var _hover := NO_CELL
var _hover_obj := {}
## 鼠标所指的东西：淡淡的圆圈（空格子只画一个小点），旁边写着坐标和情报
var _cursor := Node3D.new()
var _cursor_ring: MeshInstance3D = null
var _cursor_label := _info_label(Color.WHITE)
## 单击选中的东西（_pickables 里的一项，没有时为空）：贴着轮廓的黄色圆圈，下面写着坐标和情报
var selected := {}
var _selection := Node3D.new()
var _selection_ring: MeshInstance3D = null
var _selection_label := _info_label(COLOR_SELECTED)
## 上次刷新时行动页的瞄准（见 ActionPage.preview()）和上帝视角开关，点选格子时也要用
var _aim := {}
var _reveal := false


func setup(p_main: Node) -> void:
	main = p_main
	_world.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	add_child(_world)
	_setup_camera()
	var grid_mat := _flat_material(Color.WHITE)
	grid_mat.vertex_color_use_as_albedo = true
	_grid.material_override = grid_mat
	_world.add_child(_grid)
	var dot_mat := _flat_material(Color.WHITE)
	dot_mat.vertex_color_use_as_albedo = true
	_dots.material_override = dot_mat
	_world.add_child(_dots)
	_load_grid_mode()
	var funnel_mat := _flat_material(Color(COLOR_FLAT, 0.1))
	funnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_funnel.material_override = funnel_mat
	_world.add_child(_funnel)
	_world.add_child(_axes)
	redraw_grid()
	_world.add_child(_markers)
	_build_cursor()
	_build_selection()
	_build_zero_dot()
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()


# ---------- 相机 ----------

func _setup_camera() -> void:
	add_child(_pivot)
	_pivot.add_child(_camera)
	reset_view(true)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.05)
	add_child(env)


## 把相机摆到现在的值：中心、角度、远近。相机还向右平移，让中心落在面板左边那块画面的正中
## （平移量是右侧面板宽度的一半，按画面高度换算成星图里的长度）。
func _update_camera() -> void:
	_pivot.position = _world.transform * _focus
	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)
	_camera.h_offset = main.panel_width() / 2.0 * _world_per_px()
	for wave in _wave_nodes:
		_orient(wave, _world.global_basis.inverse() * _camera.global_basis.z)


## 视角中心那里，画面上 1 像素相当于星图里多长。
func _world_per_px() -> float:
	var view := get_viewport().get_visible_rect().size
	return 2.0 * _distance * tan(deg_to_rad(_camera.fov / 2.0)) / view.y


## 重置视角：看整张星图，用开局的角度；一维时对准自己的据点（_frame_line）。instant：不放过渡，直接跳过去。
func reset_view(instant := false) -> void:
	if state != null and state.dimension == 1:
		_frame_line()
		if instant:
			_snap_camera()
		return
	var bounds := _visual_bounds()
	_goal_focus = bounds.get_center()
	_goal_yaw = CAM_YAW
	_goal_pitch = CAM_PITCH
	_goal_distance = maxf(CAM_DISTANCE, bounds.size.length() * CAM_DISTANCE / (Vector3.ONE * (StarMap.SIZE - 1)).length())
	if instant:
		_snap_camera()


## 一维的视角：直线在画面上左右横着（x 往右变大），中心对准正在看的文明的第一个据点，
## 远近只看得到附近一段（整条线有 729 格，全放进画面就看不清了，要看远处就平移或缩小）。
func _frame_line() -> void:
	var me: Civ = main.viewed() if main != null else null
	var origins: Array[Vector3i] = me.origins() if me != null else []
	var at := Vector3(origins[0]) if not origins.is_empty() else _visual_bounds().get_center()
	# 用展开动画终点的位置：回合推得快、动画还没播完时，现在画的位置是旧的
	_goal_focus = _clamp_focus(_warp_point(at, 1.0))
	_goal_yaw = 0.0
	_goal_pitch = LINE_PITCH
	_goal_distance = LINE_DISTANCE
	_framed_line = true


## 视角中心移到 c（规则坐标），远近和角度不变。
func focus_on(c: Vector3) -> void:
	_goal_focus = _clamp_focus(_warp_point(c))


## 相机直接跳到目标位置。
func _snap_camera() -> void:
	_focus = _goal_focus
	_yaw = _goal_yaw
	_pitch = _goal_pitch
	_distance = _goal_distance
	_update_camera()


func _clamp_focus(p: Vector3) -> Vector3:
	var bounds := _visual_bounds()
	var lo := bounds.position - Vector3.ONE * CAM_MARGIN
	var hi := bounds.end + Vector3.ONE * CAM_MARGIN
	return p.clamp(lo, hi)


## 像抓着星图拖动一样平移：星图在画面上往右移 right 像素、往上移 up 像素（视角中心反着走）。
func _pan(right: float, up: float) -> void:
	var to_rule := _world.transform.basis.inverse()
	var basis := _pivot.global_transform.basis
	var move := to_rule * (basis.x * right + basis.y * up) * _world_per_px()
	if state != null and state.dimension == 1:
		# 一维只能沿直线走。左右拖动（和 A / D）总是沿直线走，往 +x 在画面上偏的那一边拖就往 +x 看；
		# 转到顺着直线看时，直线在画面上竖着，上下拖动（和 W / S）也沿直线走。
		# 直线在画面上显得短时按它的长度放大，拖多远就走多远。
		var x_on_screen := to_rule.inverse() * Vector3.RIGHT
		var line := Vector2(x_on_screen.dot(basis.x), x_on_screen.dot(basis.y))
		var pixels := right * (-1.0 if line.x < -1e-3 else 1.0)
		if absf(line.y) > absf(line.x):
			pixels += up * signf(line.y)
		move = Vector3(pixels * _world_per_px() / maxf(line.length(), 0.2), 0.0, 0.0)
	_goal_focus = _clamp_focus(_goal_focus - move)


func _turn(yaw: float, pitch: float) -> void:
	_goal_yaw += yaw
	_goal_pitch = clampf(_goal_pitch + pitch, -89, 89)


func _zoom(factor: float) -> void:
	_goal_distance = clampf(_goal_distance * factor, CAM_MIN_DISTANCE, CAM_MAX_DISTANCE)


## 每帧：按住的键移动视角，现在的值平滑地追上目标。
func _process(delta: float) -> void:
	_face_camera(_selection_ring)
	_face_camera(_cursor_ring)
	_poll_camera_keys(delta)
	var k := 1.0 - exp(-CAM_SMOOTH * delta)
	var moved := not (_focus.is_equal_approx(_goal_focus) and is_equal_approx(_yaw, _goal_yaw)
			and is_equal_approx(_pitch, _goal_pitch) and is_equal_approx(_distance, _goal_distance))
	if not moved:
		return
	_focus = _focus.lerp(_goal_focus, k)
	_yaw = lerpf(_yaw, _goal_yaw, k)
	_pitch = lerpf(_pitch, _goal_pitch, k)
	_distance = lerpf(_distance, _goal_distance, k)
	if _focus.distance_to(_goal_focus) < 1e-3 and absf(_yaw - _goal_yaw) < 0.01 \
			and absf(_pitch - _goal_pitch) < 0.01 and absf(_distance - _goal_distance) < 1e-3:
		_snap_camera()
		return
	_update_camera()


## 按住不放的视角键（WASD、Q/E、R/F、Z/X）。在输入框里打字、按着 Ctrl 或 Alt、焦点在别的窗口时不管。
func _poll_camera_keys(delta: float) -> void:
	if main.tech_tree.visible:
		return
	if not get_window().has_focus() or get_viewport().gui_get_focus_owner() is LineEdit \
			or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META):
		return
	var held := func(key: Key) -> float: return 1.0 if Input.is_physical_key_pressed(key) else 0.0
	var fast := 2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var view_h := get_viewport().get_visible_rect().size.y
	var pan := Vector2(held.call(KEY_D) - held.call(KEY_A), held.call(KEY_W) - held.call(KEY_S))
	if pan != Vector2.ZERO:
		pan *= KEY_PAN_SPEED * view_h * fast * delta
		_pan(-pan.x, -pan.y)
	var turn: float = held.call(KEY_E) - held.call(KEY_Q)
	var tilt: float = held.call(KEY_R) - held.call(KEY_F)
	if turn != 0.0 or tilt != 0.0:
		_turn(-turn * KEY_TURN_SPEED * fast * delta, -tilt * KEY_TURN_SPEED * fast * delta)
	var zoom: float = held.call(KEY_X) - held.call(KEY_Z)
	if zoom != 0.0:
		_zoom(pow(KEY_ZOOM_SPEED, zoom * fast * delta))


## 一次性的视角键：H 回到母星、V 重置、T 俯视、G 切换网格。在输入框里打字时不管。
func _camera_key(key: InputEventKey) -> bool:
	if main.tech_tree.visible:
		return false
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed or get_viewport().gui_get_focus_owner() is LineEdit:
		return false
	match key.physical_keycode:
		KEY_H:
			var me: Civ = main.viewed()
			var origins := me.origins()
			focus_on(Vector3(origins[0] if not origins.is_empty() else me.home))
		KEY_V:
			reset_view()
		KEY_T:
			# 从正上方往下看；已经是俯视时回到开局的斜角
			_goal_pitch = CAM_PITCH if _goal_pitch < -80.0 else -89.0
		KEY_G:
			set_grid_mode((grid_mode + 1) % Grid.size())
			main.overlay.show_toast("网格：%s（G 切换）" % GRID_NAMES[grid_mode])
		_:
			return false
	return true


## 窗口大小变了：界面本身由项目设置里的缩放（canvas_items）跟着窗口一起放大缩小，
## 这里只要重新算相机偏移，并让星图上的坐标文字和界面文字一样大。
func _on_resized() -> void:
	_update_camera()
	var px_per_unit := float(get_window().size.y) / get_viewport().get_visible_rect().size.y
	_cursor_label.pixel_size = 0.0006 * px_per_unit
	_selection_label.pixel_size = _cursor_label.pixel_size


## 鼠标是不是停在界面（面板、按钮、日志等）上。停在界面上时滚轮和悬停不作用于星图。
func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _unhandled_input(event: InputEvent) -> void:
	if main.tech_tree.visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and _camera_key(key):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if mb.pressed and not _over_ui():  # 面板滚到头以后，多出来的滚轮不能变成星图缩放
				_zoom(0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88)
			return
		if not mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			return
		if mb.pressed:
			if _drag_button == MOUSE_BUTTON_NONE:
				_drag_button = mb.button_index
				_press_pos = mb.position
				_last_pointer = mb.position
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
				var obj := _pick_object(mb.position)
				var c := _nearest_cell(mb.position)
				if not obj.is_empty():
					focus_on(obj["pos"])
				elif c != NO_CELL:
					focus_on(Vector3(c))
		elif mb.button_index == _drag_button:
			_drag_button = MOUSE_BUTTON_NONE
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_press_pos) < 5.0:
				# 点中东西才算选中；点到空处取消选中，但还是可以瞄准那一格
				var obj := _pick_object(mb.position)
				select_object(obj)
				var c: Vector3i = obj["cell"] if not obj.is_empty() else _nearest_cell(mb.position)
				if c != NO_CELL:
					cell_clicked.emit(c)
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var mm := event as InputEventMouseMotion
		var movement := mm.position - _last_pointer
		_last_pointer = mm.position
		if _drag_button == MOUSE_BUTTON_LEFT:
			_turn(-movement.x * 0.3, -movement.y * 0.3)
			_yaw = _goal_yaw  # 拖动旋转直接跟手，不用追
			_pitch = _goal_pitch
		else:
			_pan(movement.x, -movement.y)
			_focus = _goal_focus
		_update_camera()
	elif event is InputEventMouseMotion:
		var pos := (event as InputEventMouseMotion).position
		var obj := {} if _over_ui() else _pick_object(pos)
		_set_hover(obj)


# ---------- 在星图上点选 ----------

## 鼠标所指的东西。只有正在看的文明画在星图上的东西才点得中（见 _pickables），点在屏幕上离东西的
## 轮廓最近的那个；附近没有东西时返回空的字典。
func _pick_object(pos: Vector2) -> Dictionary:
	if pos.x > get_viewport().get_visible_rect().size.x - main.panel_width():
		return {}
	var best := {}
	var best_score := INF
	for o in _pickables():
		var p := _world.to_global(_warp_point(o["pos"]))
		if _camera.is_position_behind(p):
			continue
		var center := _camera.unproject_position(p)
		var edge := _camera.unproject_position(p + _camera.global_basis.x * float(o["r"]))
		var reach := maxf(center.distance_to(edge), PICK_MIN_PX)
		var d := center.distance_to(pos)
		if d > reach:
			continue
		var score := d / reach
		if score < best_score:
			best_score = score
			best = o
	return best


## 鼠标附近的格子（瞄准空格子用，例如殖民船盲飞、广播任意坐标）。不算选中，也不画框。
## 选屏幕上离鼠标最近的格子；差不多近时选离相机近的（前面的）。点不准时可以在面板里直接输入坐标。
func _nearest_cell(pos: Vector2) -> Vector3i:
	if pos.x > get_viewport().get_visible_rect().size.x - main.panel_width():
		return NO_CELL
	var best := NO_CELL
	var best_score := INF
	for c in state.map.cells():
		var p := _world.to_global(_warp_point(Vector3(c)))
		if _camera.is_position_behind(p):
			continue
		var d := _camera.unproject_position(p).distance_to(pos)
		if d > PICK_PX:
			continue
		var score := d + 0.5 * _camera.global_position.distance_to(p)
		if score < best_score:
			best_score = score
			best = c
	return best


## 能点中的东西：正在看的文明星图上画出来的星系和单位，看不到的点不中。
## 每项是 {"key": 认它的名字, "pos": 规则坐标, "r": 画出来的半径, "cell": 所在的格子, "text": 文字（空时写格子的情报）}。
## 半径和 _draw_own、_draw_intel 里画的大小一致，选中框才贴着它的轮廓。
func _pickables() -> Array[Dictionary]:
	var me: Civ = main.viewed()
	var list: Array[Dictionary] = []
	var seen := {}
	var add := func(key: String, pos: Vector3, r: float, text := "") -> void:
		if seen.has(key):
			return
		var cell := Vector3i(pos.round())
		if not state.cell_exists(cell):
			return
		seen[key] = true
		list.append({"key": key, "pos": pos, "r": r, "cell": cell, "text": text})
	# 星系方块的外接轮廓半径约 0.35（母星系放大 1.4 倍）
	for c in me.colonies:
		add.call("c%s" % c, Vector3(c), 0.35 * (1.4 if c == me.home else 1.0))
	for c in me.known:
		add.call("c%s" % c, Vector3(c), 0.35)
	if _reveal:
		for civ in state.civs:
			if civ != me and civ.alive:
				for c in civ.colonies:
					add.call("c%s" % c, Vector3(c), 0.35)
	# 看到过的星系：半径 0.1 的小球，选殖民目的地时宜居的放大 1.6 倍
	var big := {}
	if _picking_colony():
		for c in _colony_targets(me):
			big[c] = true
	for c in me.intel:
		if me.intel[c]["stars"] != StarMap.Star.NONE:
			add.call("c%s" % c, Vector3(c), 0.16 if big.has(c) else 0.1)
	if _reveal:
		for c in state.system_cells:
			if state.map.star_at(c) != StarMap.Star.NONE:
				add.call("c%s" % c, Vector3(c), 0.1)
	# 自己的单位：星舰、在飞的（停着的算在星系里）
	for s in me.ships:
		if s.dead:
			continue
		if s.kind == Ship.STARSHIP:
			add.call("s%d" % s.id, s.pos, 0.28, "你的星舰")
		elif not s.docked:
			add.call("s%d" % s.id, s.position(), 0.18 if s.kind == Ship.GRAIN else 0.24, "你的" + s.label())
	if _reveal:
		for civ in state.civs:
			if civ != me and civ.alive:
				for s in civ.ships:
					if not s.dead and not s.docked:
						add.call("s%d" % s.id, s.position(), 0.24, "%s的%s" % [civ.name, s.label()])
	# 看到的别人的舰船、预警报告的东西
	for sight in me.sightings:
		add.call("v%s%d" % [sight["pos"], sight["turn"]], sight["pos"], 0.18, "第 %d 回合看到的舰船" % sight["turn"])
	for alert in me.alerts:
		add.call("a%s" % alert["pos"], alert["pos"], 0.29, "预警")
	return list


## 选中的行动是不是要选宜居星系当目的地（殖民船、星舰）。
func _picking_colony() -> bool:
	return _aim.get("kind", "") == "colony"


## 贴着东西轮廓的圆圈：朝着相机的细圆环，半径比东西大一点点。
func _outline_ring(r: float, width: float, color: Color) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = r + OUTLINE_GAP
	ring.outer_radius = r + OUTLINE_GAP + width
	ring.rings = 48
	ring.ring_segments = 6
	var node := MeshInstance3D.new()
	node.mesh = ring
	node.material_override = _flat_material(color)
	return node


func _info_label(color: Color) -> Label3D:
	var l := Label3D.new()
	l.font_size = 40
	l.pixel_size = 0.0006
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	l.modulate = color
	return l


## 鼠标所指的东西：淡淡的圆圈，旁边写坐标和情报。指着空处什么都不画。
func _build_cursor() -> void:
	_cursor_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM  # 字往上排，不压住东西
	_cursor.add_child(_cursor_label)
	_cursor.visible = false
	_world.add_child(_cursor)


## 选中的东西：贴着轮廓的黄色细圆圈，下面写坐标和情报。
func _build_selection() -> void:
	_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP  # 字往下排，不压住东西
	_selection.add_child(_selection_label)
	_selection.visible = false
	_world.add_child(_selection)


## 选中 obj（_pickables 里的一项；空的字典：取消选中）。
func select_object(obj: Dictionary, redraw := true) -> void:
	selected = obj
	_selection.visible = not obj.is_empty()
	_cursor_label.visible = _hover_key() != _selected_key()  # 同一个东西不写两遍
	if _selection_ring != null:
		_selection_ring.queue_free()
		_selection_ring = null
	if redraw:
		main.refresh()
		return
	if obj.is_empty():
		return
	var r: float = obj["r"]
	_selection.position = _warp_point(obj["pos"])
	_selection_ring = _outline_ring(r, 0.025, COLOR_SELECTED)
	_selection.add_child(_selection_ring)
	_face_camera(_selection_ring)
	_selection_label.position = Vector3(0, 0, -(r + 0.12))
	_selection_label.text = _object_text(obj)


## 刷新以后重新找选中的东西：它还在星图上就跟着它（单位会移动），不在了（被毁、看不到了）就取消。
func _reselect() -> void:
	if selected.is_empty():
		return
	for o in _pickables():
		if o["key"] == selected["key"]:
			select_object(o, false)
			return
	select_object({}, false)


func _selected_key() -> String:
	return selected.get("key", "")


func _hover_key() -> String:
	return _hover_obj.get("key", "")


## 选中的东西所在的格子（没有选中时为 NO_CELL）。
func selected_cell() -> Vector3i:
	return selected.get("cell", NO_CELL)


func _object_text(obj: Dictionary) -> String:
	var c: Vector3i = obj["cell"]
	if obj["text"] == "":
		return _cell_info(c)
	return "%s　(%d, %d, %d)" % [obj["text"], c.x, c.y, c.z]


## 圆圈总是正对相机，看起来就是东西的轮廓。
func _face_camera(node: Node3D) -> void:
	if node == null or not node.is_inside_tree():
		return
	var eye := _world.to_local(_camera.global_position)
	_orient(node, eye - node.get_parent().position)


## 鼠标指着 obj（_pickables 里的一项）；指着空处时为空的字典，什么都不画。
func _set_hover(obj: Dictionary) -> void:
	if obj.get("key", "") == _hover_obj.get("key", ""):
		return
	_hover_obj = obj
	_hover = obj.get("cell", NO_CELL)
	_cursor.visible = not obj.is_empty()
	_cursor_label.visible = _hover_key() != _selected_key()
	if _cursor_ring != null:
		_cursor_ring.queue_free()
		_cursor_ring = null
	if obj.is_empty():
		return
	var c := _hover
	var r: float = obj["r"]
	_cursor.position = _warp_point(obj["pos"])
	_cursor_ring = _outline_ring(r, 0.015, Color(1, 1, 1, 0.45))
	_cursor.add_child(_cursor_ring)
	_face_camera(_cursor_ring)
	_cursor_label.text = _object_text(obj)
	_cursor_label.position = Vector3(0, 0, r + 0.12)
	var me: Civ = main.viewed()
	var fade := 0.0
	if me.intel.has(c) and not me.owns(c):
		fade = clampf((state.turn - int(me.intel[c]["turn"])) / INTEL_FADE_TURNS, 0.0, 1.0)
	# 情报越旧，字越淡
	_cursor_label.modulate.a = 1.0 - 0.6 * fade


## 鼠标停在格子上时显示的文字：坐标、是谁的，以及传回来的情报。
func _cell_info(c: Vector3i) -> String:
	var me: Civ = main.viewed()
	var head := "(%d, %d, %d)" % [c.x, c.y, c.z]
	if me.owns(c):
		head += "　你的母星系" if c == me.home else "　你的星系"
	var ss := me.starship()
	if ss != null and ss.cell() == c:
		head += "　你的星舰"
	var lines: Array[String] = [head]
	if me.owns(c):
		var counts := {}
		for ship in me.ships:
			if not ship.dead and ship.docked and ship.cell() == c:
				var kind: String = "星际探测器" if ship.kind == Ship.PROBE and ship.interstellar else Ship.NAMES[ship.kind]
				counts[kind] = counts.get(kind, 0) + 1
		var units: Array[String] = []
		for kind in counts:
			units.append("%s ×%d" % [kind, counts[kind]])
		if not units.is_empty():
			lines.append("停泊：" + "、".join(units))
		var facilities: Array[String] = []
		for spec in [["戴森球", me.dysons], ["采矿船", me.miners], ["光粒", me.grains]]:
			if spec[1].get(c, 0) > 0:
				facilities.append("%s ×%d" % [spec[0], spec[1][c]])
		if me.broadcasters.has(c):
			facilities.append("恒星广播器")
		if me.bunkers.has(c):
			facilities.append("掩体")
		if not facilities.is_empty():
			lines.append("设施：" + "、".join(facilities))
	if state.in_black_domain(c):
		lines.append("在黑域里：光速 %.2f" % state.light_at(c))
	if me.intel.has(c) and not me.owns(c):
		lines.append(_intel_text(me.intel[c]))
	return "\n".join(lines)


## 一条情报写成文字：第几回合看到的，那时候星系是什么样。
func _intel_text(info: Dictionary) -> String:
	var seen: int = info["turn"]
	var age := state.turn - seen
	var head := "第 %d 回合看到（%s）" % [seen, "这一回合" if age == 0 else "%d 回合前" % age]
	if info["stars"] == StarMap.Star.NONE:
		return head + "：没有恒星"
	var parts: Array[String] = ["%d 颗恒星" % StarMap.star_count(info["stars"]),
			"类地 %d" % info["rocky"], "类木 %d" % info["gas"]]
	if info.get("habitable", false):
		parts.append("宜居")
	var owner: int = info["owner"]
	parts.append("属于 %s" % state.civs[owner].name if owner >= 0 else "无主")
	if info["dysons"] > 0:
		parts.append("戴森球 %d" % info["dysons"])
	if info["warships"] > 0:
		parts.append("停着战舰 %d" % info["warships"])
	if info["broadcaster"]:
		parts.append("有恒星广播器")
	if info["bunker"]:
		parts.append("有掩体")
	if info["grain"]:
		parts.append("存着光粒")
	if info["foil"]:
		parts.append("在准备单向著" if state.all_flat() else "在准备二向箔")
	return head + "\n" + "，".join(parts)


# ---------- 固定的背景：网格和坐标轴 ----------

## 换局面（新开一局、回放跳转）时直接采样当前布局，不放过渡动画。
func redraw_grid() -> void:
	var frame := DimensionSpace.frame(state)
	_layout_new = frame["positions"]
	_layout_old = _layout_new.duplicate()
	_amounts = frame["amounts"]
	_layout_epoch = state.space_epoch
	_draw_axes()
	_shape = _collapse_shape()
	_warp_t = 1.0
	_zero_on = state.zero_winner != null
	if _zero_on:
		_zero_point = _zero_center()
	_zero_t = 1.0
	_apply_zero()
	_trails.clear()
	select_object({}, false)
	_rebuild_warped()
	# 换到一个一维的局面（比如回放跳过去）时对准自己的据点一次；之后由玩家自己移
	if state.dimension != 1:
		_framed_line = false
	elif not _framed_line:
		_frame_line()
		_snap_camera()


## 逻辑坐标按稳定格子身份跟随空间展开；所有标记、航线和选中共用它。
func _warp_point(p: Vector3, blend := -1.0) -> Vector3:
	var c := Vector3i(p.round())
	if not _layout_new.has(c):
		return p + state.visual_offset
	var t := DimensionSpace.Layout.smooth_amount(_warp_t if blend < 0.0 else blend)
	var local := p - Vector3(c)
	return Vector3(_layout_old.get(c, _layout_new[c])).lerp(_layout_new[c], t) + local


func _visual_bounds() -> AABB:
	if _layout_new.is_empty():
		return AABB(Vector3(state.map.origin), Vector3(state.map.extent - Vector3i.ONE))
	var bounds := AABB(Vector3(_layout_new.values()[0]), Vector3.ZERO)
	for p in _layout_new.values():
		bounds = bounds.expand(p)
	return bounds


## 按现在的过渡进度和网格画法重画网格（线和点阵）和压平区域边上的曲面。
## 视野里的线和点亮一些，看得出自己看得到哪里（F4.2）。
func _rebuild_warped() -> void:
	var mesh := ImmediateMesh.new()
	if grid_mode != Grid.DOTS:
		var vision_only := grid_mode != Grid.ALL_LINES
		var started := false
		var segs := _grid_segments()
		for mid in segs:
			var seen := _in_eyes(mid)
			if vision_only and not seen:
				continue
			if not started:
				mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				started = true
			var color := _shown(COLOR_GRID_LINE_VISION if seen else COLOR_GRID_LINE)
			for p in segs[mid]:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(_warp_point(p, _warp_t))
		if started:
			mesh.surface_end()
	_grid.mesh = mesh
	_dots.visible = (grid_mode == Grid.DOTS or grid_mode == Grid.DOTS_AND_VISION) and not (_zero_on and _zero_t >= 1.0)
	if _dots.visible:
		_dots.multimesh = _dot_mesh()
	_funnel.mesh = _funnel_mesh()


## 点阵：每个还在的格子中心一个小点。
func _dot_mesh() -> MultiMesh:
	var points: Array[Vector3] = []
	for c in state.map.cells():
		points.append(Vector3(c))
	var dot := SphereMesh.new()
	dot.radius = 0.028
	dot.height = 0.056
	dot.radial_segments = 6
	dot.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dot
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), _warp_point(points[i], _warp_t)))
		mm.set_instance_color(i, _shown(COLOR_DOT_VISION if _in_eyes(points[i]) else COLOR_DOT))
	return mm


## 点 p 在不在正在看的文明的视野里（按上次刷新时的视野，不管黑域挡不挡）。
func _in_eyes(p: Vector3) -> bool:
	for o in _grid_eyes:
		if GameState.in_view(o, p):
			return true
	return false


## 换网格画法（F4.2），存进玩家设置，下次打开还是这样。
func set_grid_mode(mode: int) -> void:
	grid_mode = mode as Grid
	_rebuild_warped()
	if DisplayServer.get_name() != "headless":
		var cfg := ConfigFile.new()
		cfg.load(WindowSettings.SETTINGS_PATH)
		cfg.set_value("view", "grid", grid_mode)
		cfg.save(WindowSettings.SETTINGS_PATH)
	if main.overlay != null:
		main.overlay.sync_grid_mode()


func _load_grid_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.load(WindowSettings.SETTINGS_PATH)
	grid_mode = clampi(cfg.get_value("view", "grid", Grid.DOTS), 0, Grid.size() - 1) as Grid


## 每个展开格子画独立薄片，保留全部层，不能再用重叠的漏斗面。
func _funnel_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if state.dimension == 3 and state.foil_zones.is_empty():
		return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in state.map.cells():
		var t: float = _amounts.get(c, 0.0)
		if state.dimension == 3 and t <= 0.0:
			continue
		var center := _warp_point(Vector3(c))
		var width := 0.43
		var depth := 0.025 if state.all_linear() else 0.43
		var a := center + Vector3(-width, -depth, -0.04)
		var b := center + Vector3(width, -depth, -0.04)
		var d := center + Vector3(-width, depth, -0.04)
		var e := center + Vector3(width, depth, -0.04)
		for point in [a, b, e, a, e, d]:
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh


## 当前整数坐标中的邻接线；完成换图后自动变成 27² 或 729 的网格。
func _grid_segments() -> Dictionary:
	var segs := {}
	for c in state.map.cells():
		for axis in [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]:
			var next: Vector3i = c + axis
			if state.cell_exists(next):
				segs[(Vector3(c) + Vector3(next)) / 2.0] = [Vector3(c), Vector3(next)]
	return segs


## 波前每回合继续扩散，即使本回合没有扫过新的整数格，布局也要更新。
func _collapse_shape() -> Array:
	return [state.space_epoch, state.flattened.size(), state.linearized.size(),
			state.foil_zones.map(func(z): return z["age"]), state.line_zones.map(func(z): return z["age"])]


## 从当前屏幕位置过渡到下一回合布局；快速连点不会跳回旧动画的起点。
func _animate_flattening() -> void:
	var shape := _collapse_shape()
	if shape == _shape:
		return
	_shape = shape
	_set_hover({})
	var current := {}
	for c in _layout_new:
		current[c] = _warp_point(Vector3(c))
	if _layout_epoch != state.space_epoch:
		var translated := {}
		for c in current:
			translated[state.last_mapping.get(c, c)] = current[c]
		current = translated
		_layout_epoch = state.space_epoch
		_trails.clear()
		select_object({})
	var frame := DimensionSpace.frame(state)
	_layout_old = current
	_layout_new = frame["positions"]
	_amounts = frame["amounts"]
	_warp_t = 0.0
	# 展开时把整张图放进画面；压成直线时整条线太长，放进画面就什么都看不清，镜头留给玩家自己移，
	# 进入一维时再对准自己的据点
	var bounds := _visual_bounds()
	if state.dimension == 1:
		_frame_line()
	elif bounds.size.length() * 1.55 <= FIT_MAX_DISTANCE:
		_goal_focus = bounds.get_center()
		_goal_distance = maxf(_goal_distance, bounds.size.length() * 1.55)
	_draw_axes()



## 压平或降到零维的动画还没放完。
func animating() -> bool:
	return _warp_t < 1.0 or _zero_t < 1.0


## 动画往前放 delta 秒。由 main.gd 每帧调用。
func advance_animation(delta: float) -> void:
	if _warp_t < 1.0:
		_warp_t = minf(1.0, _warp_t + delta / FLAT_ANIM_SECONDS)
		_rebuild_warped()
		refresh(main.viewed(), _aim, _last_show_vision, _reveal)
	if _zero_t < 1.0:
		_zero_t = minf(1.0, _zero_t + delta / ZERO_ANIM_SECONDS)
		_apply_zero()


# ---------- 降到零维（F5.2） ----------

func _build_zero_dot() -> void:
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	_zero_dot.mesh = ball
	_zero_dot.material_override = _flat_material(Color(1.0, 0.97, 0.85))
	_zero_dot.visible = false
	_world.add_child(_zero_dot)


## 宇宙缩向的那一点：降到零维的文明的星系（没有星系时是星舰）。
func _zero_center() -> Vector3:
	var w: Civ = state.zero_winner
	if not w.colonies.is_empty():
		return _warp_point(Vector3(w.colonies[0]))
	if w.has_starship():
		return _warp_point(w.starship().pos)
	return Vector3.ONE * (StarMap.SIZE - 1) / 2.0


## 刚有文明降到零维：开始放动画，视角移过去。回放退回到降维以前：直接恢复。
func _animate_zero() -> void:
	var on := state.zero_winner != null
	if on == _zero_on:
		return
	_zero_on = on
	_zero_t = 0.0 if on else 1.0
	if on:
		_zero_point = _zero_center()
		_goal_focus = _zero_point
	_apply_zero()


## 按动画进度把网格和所有标记缩向那一点（越缩越快），快缩完时亮一下，最后只剩一个亮点。
func _apply_zero() -> void:
	var s := 1.0
	if _zero_on:
		s = lerpf(1.0, 0.001, pow(_zero_t, 3.0))
	var squeeze := Transform3D(Basis.from_scale(Vector3.ONE * s), _zero_point * (1.0 - s))
	for node: Node3D in [_grid, _dots, _funnel, _markers]:
		node.transform = squeeze
		node.visible = not (_zero_on and _zero_t >= 1.0)
	_dots.visible = _dots.visible and (grid_mode == Grid.DOTS or grid_mode == Grid.DOTS_AND_VISION)
	_zero_dot.visible = _zero_on
	_zero_dot.position = _zero_point
	var flash := sin(PI * clampf((_zero_t - 0.6) / 0.4, 0.0, 1.0))
	_zero_dot.scale = Vector3.ONE * (0.12 + 0.6 * flash)


## 从当前地图原点沿仍然存在的轴画刻度；展开期间隐藏旧坐标轴，
## 让玩家看得出每个格子的坐标。文字总是朝向相机。
func _draw_axes() -> void:
	_axes.visible = not state.collapse_pending()
	for node in _axes.get_children():
		node.free()
	var origin := Vector3(state.map.origin) + state.visual_offset
	var start := origin - Vector3.ONE * 0.6
	for i in 3:
		if state.map.extent[i] <= 1:
			continue
		var axis := Vector3.ZERO
		axis[i] = 1.0
		var n := state.map.extent[i] - 1
		var color := AXIS_COLORS[i]
		_axes.add_child(_segment(start, start + axis * (n + 1.8), Color(color, 0.35), false))
		_axes.add_child(_label3d(["x", "y", "z"][i], start + axis * (n + 2.3), Color(color, 0.7), 48))
		var step := maxi(1, ceili(n / 9.0))
		for k in range(0, n + 1, step):
			_axes.add_child(_label3d(str(k + state.map.origin[i]), start + axis * (k + 0.6), Color(color, 0.4), 30))


# ---------- 会变化的部分：标记 ----------

## 重画星图上会变的标记。me：正在看的文明；aim：行动页的瞄准（见 ActionPage.preview()）；
## show_vision：画自己的视野；reveal：上帝视角，画出所有星系和别人的舰船。
func refresh(me: Civ, aim: Dictionary, show_vision: bool, reveal: bool) -> void:
	_wave_nodes.clear()
	for child in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()
	_last_show_vision = show_vision
	_aim = aim
	_reveal = reveal
	_animate_flattening()
	_animate_zero()
	var eyes: Array[Dictionary] = []
	if me.alive:
		eyes = state.observers(me)
	if eyes != _grid_eyes:
		_grid_eyes = eyes
		_rebuild_warped()
	_remember_trails(me)
	_tube_parts.clear()
	# 鼠标所指的、选中的东西可能移动了、被毁了、看不到了，情报也可能变了：重新找一遍
	var hover_key: String = _hover_obj.get("key", "")
	_hover = NO_CELL
	_hover_obj = {}
	var hover_obj := {}
	if hover_key != "":
		for o in _pickables():
			if o["key"] == hover_key:
				hover_obj = o
	_set_hover(hover_obj)
	_reselect()
	if me.alive and not state.is_over():
		_draw_preview(me)
	if show_vision and me.alive:
		_draw_vision(me)
	_draw_space()
	_draw_own(me)
	_draw_intel(me)
	_markers.add_child(_tubes())


## 选中行动的预览：方向画范围和箭头，目标画方框和连线。
func _draw_preview(me: Civ) -> void:
	var from: Vector3 = _aim.get("from", Vector3.ZERO)
	var direction: Vector3 = _aim.get("direction", Vector3.ZERO)
	var target: Vector3i = _aim.get("target", NO_CELL)
	var area: Array[Vector3i] = []
	var color := COLOR_CONE
	match _aim.get("kind", ""):
		"dispatch":
			var s: Ship = _aim.get("unit")
			if s == null:
				return
			if s.kind == Ship.PROBE:
				var cone := state.cone_of(me, s)
				area = Geometry.cone_cells(from, direction, cone[0], cone[1], state.map.bounds())
			else:
				area = Geometry.cylinder_cells(from, direction, SHIP_PREVIEW_LENGTH, 0.0, state.map.bounds())
				color = Color(SHIP_COLORS[s.kind], 0.1)
		"grain":
			area = Geometry.cylinder_cells(from, direction, SHIP_PREVIEW_LENGTH, Balance.GRAIN_RADIUS, state.map.bounds())
			color = COLOR_BEAM
		"colony":
			_markers.add_child(_colony_candidates(me))
			_markers.add_child(_target_mark(target, Color(COLOR_COLONY_SHIP, 0.3)))
			_markers.add_child(_segment(from, Vector3(target), COLOR_COLONY_SHIP))
			return
		"sophon":
			_markers.add_child(_target_mark(target, Color(SHIP_COLORS[Ship.SOPHON], 0.3)))
			_markers.add_child(_segment(from, Vector3(target), SHIP_COLORS[Ship.SOPHON]))
			return
		"broadcast":
			_markers.add_child(_broadcast_mark(target, 1.0))
			_markers.add_child(_segment(from, Vector3(target), COLOR_BROADCAST))
			return
		"domain":
			_markers.add_child(_domain_box(target, Color(COLOR_DOMAIN_EDGE, 0.25)))
			_markers.add_child(_segment(from, Vector3(target), COLOR_DOMAIN_EDGE))
			return
		"foil", "line_foil":
			_draw_foil_preview(from, target, _aim["kind"] == "line_foil")
			return
		_:
			return
	area = area.filter(func(c): return state.cell_exists(c))
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.03) if state.all_flat() else Vector3.ONE * 0.9
	_markers.add_child(_instances(box, area, _fill(area.size(), color), _fill_f(area.size(), 1.0)))
	_markers.add_child(_arrow(from, direction, _length_inside(from, direction), Color(color, 1.0)))


## 二向箔预览：从发射源到目标的直线，目标那一层（展开后最先压平、扩散最远的平面）。
func _draw_foil_preview(from: Vector3, target: Vector3i, line_mode: bool) -> void:
	var layer: Array[Vector3i] = []
	for x in state.map.extent.x:
		if line_mode:
			layer.append(Vector3i(x, state.line_y_for(target), state.flat_plane))
		else:
			for y in state.map.extent.y:
				layer.append(Vector3i(x, y, state.foil_plane_for(target)))
	var tile := BoxMesh.new()
	tile.size = Vector3(1.0, 0.06 if line_mode else 1.0, 0.03)
	_markers.add_child(_instances(tile, layer, _fill(layer.size(), COLOR_FOIL_COLUMN), _fill_f(layer.size(), 1.0)))
	_markers.add_child(_target_mark(target, Color(COLOR_FOIL, 0.3)))
	_markers.add_child(_segment(from, Vector3(target), COLOR_FOIL))


## 自己的视野：星系和星舰是球，在飞的舰船是小球，探测器是圆锥。预警系统的范围是橙色的球。
func _draw_vision(me: Civ) -> void:
	for o in state.observers(me):
		var r: float = o["r"]
		var pos: Vector3 = o["pos"]
		var dir: Vector3 = o["dir"]
		if dir == Vector3.ZERO:
			_markers.add_child(_bubble(pos, r, COLOR_VISION))
			continue
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r * tan(deg_to_rad(o["angle"] / 2.0)) + Geometry.CELL_HALF
		cone.height = r
		var node := MeshInstance3D.new()
		node.mesh = cone
		var mat := _flat_material(COLOR_PROBE_VISION)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
		node.position = _warp_point(pos + dir * r / 2.0)
		# 圆锥的尖朝 +y；尖要在探测器那头，所以 +y 朝反方向
		_orient(node, -dir)
		_markers.add_child(node)
	if me.has_warning:
		for c in me.colonies:
			_markers.add_child(_bubble(Vector3(c), me.warning_range(), Color(COLOR_ALERT, 0.03)))


## 星图上大家都看得到的东西：压平的空间、黑域。
func _draw_space() -> void:
	# 黑域（G14）：光速低到光粒没有杀伤力的格子画成半透明的方块，光速越低越不透明；中心还保持光速为 0 的再加一圈边框
	var slow_cells: Array[Vector3i] = []
	var slow_colors: Array[Color] = []
	if not state.light.is_empty():
		for c in state.map.cells():
			if state.in_black_domain(c):
				slow_cells.append(c)
				slow_colors.append(Color(COLOR_DOMAIN, COLOR_DOMAIN.a * (1.0 - state.light_at(c))))
	if not slow_cells.is_empty():
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		_markers.add_child(_instances(cube, slow_cells, slow_colors, _fill_f(slow_cells.size(), 1.0)))
	for d in state.black_domains:
		_markers.add_child(_domain_box(d["center"], Color(COLOR_DOMAIN, 0.0)))


## 自己的东西：舰船、设施、降维箔、准备中的黑域、自己发出的广播。
func _draw_own(me: Civ) -> void:
	for s in me.ships:
		if s.dead:
			continue
		if not s.docked and (detailed or _selected_key() == "s%d" % s.id or _aim.get("unit") == s):
			_draw_path(s, COLOR_MINE)
		if s.kind == Ship.STARSHIP:
			var gem := SphereMesh.new()
			gem.radius = 0.28
			gem.height = 0.56
			gem.radial_segments = 4
			gem.rings = 2
			var ship_node := MeshInstance3D.new()
			ship_node.mesh = gem
			ship_node.material_override = _flat_material(COLOR_STARSHIP)
			ship_node.position = _warp_point(s.pos)
			_markers.add_child(ship_node)
		elif not s.docked:
			_draw_ship(s, SHIP_COLORS[s.kind] if detailed else COLOR_MINE)

	# 停泊单位按星系聚合，不再一艘一个彩色方块；种类和数量在悬停说明里。
	var per_cell := {}
	for s in me.ships:
		if not s.dead and s.docked and s.kind != Ship.STARSHIP:
			per_cell[s.cell()] = per_cell.get(s.cell(), 0) + 1
	for c in per_cell:
		_markers.add_child(_label3d("停泊 %d" % per_cell[c], _warp_point(Vector3(c)) + Vector3(0, 0, -0.48), Color(COLOR_MINE, 0.8), 30))

	# 戴森球：星系外面套金色圆环，个数越多环越大
	var dyson_cells: Array[Vector3i] = []
	var dyson_sizes: Array[float] = []
	for c in me.dysons:
		if me.dysons[c] > 0 and _detail_at(c):
			dyson_cells.append(c)
			dyson_sizes.append(0.85 + 0.15 * me.dysons[c])
	var dyson_ring := TorusMesh.new()
	dyson_ring.inner_radius = 0.42
	dyson_ring.outer_radius = 0.5
	_markers.add_child(_instances(dyson_ring, dyson_cells, _fill(dyson_cells.size(), COLOR_DYSON), dyson_sizes))

	# 采矿船：星系斜上方一个棕色小方块；存着的光粒：紫色小球；恒星广播器：粉色小方块
	for spec in [[me.miners.keys(), COLOR_MINER, Vector3(0.42, 0.42, 0.0)],
			[me.grains.keys(), SHIP_COLORS[Ship.GRAIN], Vector3(-0.42, 0.42, 0.0)],
			[me.broadcasters.keys(), COLOR_BROADCAST, Vector3(0.42, -0.42, 0.0)]]:
		var cells: Array[Vector3i] = []
		cells.assign(spec[0].filter(_detail_at))
		var mark := BoxMesh.new()
		mark.size = Vector3.ONE * 0.16
		var node := _instances(mark, cells, _fill(cells.size(), spec[1]), _fill_f(cells.size(), 1.0))
		node.position = spec[2]
		_markers.add_child(node)

	# 掩体：星系下方一块灰色方片
	var bunker_cells: Array[Vector3i] = []
	bunker_cells.assign(me.bunkers.keys().filter(_detail_at))
	var disc := BoxMesh.new()
	disc.size = Vector3(0.6, 0.6, 0.04)
	var bunker_node := _instances(disc, bunker_cells, _fill(bunker_cells.size(), COLOR_BUNKER), _fill_f(bunker_cells.size(), 1.0))
	bunker_node.position = Vector3(0, 0, -0.3)
	_markers.add_child(bunker_node)

	# 二向箔：白色小方片，连一条线到目标
	for foil in me.foils:
		var sheet := BoxMesh.new()
		sheet.size = Vector3(0.35, 0.06 if foil.to_line else 0.35, 0.02)
		var node := MeshInstance3D.new()
		node.mesh = sheet
		node.material_override = _flat_material(COLOR_FOIL)
		node.position = _warp_point(foil.position())
		_markers.add_child(node)
		if detailed or selected_cell() == foil.target:
			_markers.add_child(_segment(foil.position(), Vector3(foil.target), Color(COLOR_FOIL, 0.4)))

	for d in me.pending_domains:
		_markers.add_child(_domain_box(d["center"], Color(COLOR_DOMAIN_EDGE, 0.15)))

	# 最近几条波前只画单环。所有己方广播目标仍显示，并按坐标去重。
	var active := active_broadcasts(me)
	for b in active.slice(-BROADCAST_LIMIT):
		_wave_rings(b["from"], b["radius"], Color(COLOR_BROADCAST, 0.45))
	var targets := {}
	for b in state.broadcasts:
		if b["sender"] == me and not targets.has(b["target"]):
			targets[b["target"]] = true
			_markers.add_child(_broadcast_mark(b["target"], 0.55))


func active_broadcasts(me: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for b in state.broadcasts:
		if b["sender"] == me and b["radius"] < _farthest_corner(b["from"]):
			result.append(b)
	return result


func _detail_at(c: Vector3i) -> bool:
	return detailed or selected_cell() == c


## 知道的别人的事：星系（传回来的情报）、看到的舰船和航迹、预警、打击方向、听到的广播。
func _draw_intel(me: Civ) -> void:
	# 看到过的星系：小球，颜色表示几颗恒星
	var seen: Array[Vector3i] = []
	for c in me.intel:
		if me.intel[c]["stars"] != StarMap.Star.NONE and not me.owns(c) and state.cell_exists(c):
			seen.append(c)
	if not _reveal:
		_markers.add_child(_star_spheres(seen, 1.0, me.intel))

	# 敌情记录图：打中过的格子，确认为空的格子
	var rec: Array[Vector3i] = []
	var rec_colors: Array[Color] = []
	var rec_sizes: Array[float] = []
	for c in me.record_empty:
		rec.append(c)
		rec_colors.append(COLOR_RECORD_EMPTY)
		rec_sizes.append(0.6)
	for c in me.record_hits:
		rec.append(c)
		rec_colors.append(COLOR_RECORD_HIT)
		rec_sizes.append(1.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.25
	ring.outer_radius = 0.32
	_markers.add_child(_instances(ring, rec, rec_colors, rec_sizes))

	# 看到的别人的舰船：红色小菱形，越旧越淡；预警系统这一回合报告的东西：橙色，大一点
	var points: Array[Vector3] = []
	var colors: Array[Color] = []
	var sizes: Array[float] = []
	for sight in me.sightings:
		var age := state.turn - int(sight["turn"])
		points.append(sight["pos"])
		colors.append(Color(COLOR_SIGHTING, clampf(1.0 - float(age) / Balance.SIGHTING_KEEP, 0.15, 1.0)))
		sizes.append(1.0)
	for alert in me.alerts:
		points.append(alert["pos"])
		colors.append(COLOR_ALERT)
		sizes.append(1.6)
	var diamond := SphereMesh.new()
	diamond.radius = 0.18
	diamond.height = 0.36
	diamond.radial_segments = 4
	diamond.rings = 2
	_markers.add_child(_instances_at(diamond, points, colors, sizes))

	# 看到的航迹：红色线，越旧越淡
	for i in me.wakes_seen:
		if i >= state.wakes.size():
			continue
		var w: Dictionary = state.wakes[i]
		if w["gone"]:
			continue
		var age := state.turn - int(w["turn"])
		var alpha := clampf(0.9 - 0.7 * age / INTEL_FADE_TURNS, 0.2, 0.9)
		_tube(w["a"], w["b"], Color(COLOR_WAKE, alpha), PATH_WIDTH * 0.8)

	# 被打时知道的打击方向：从被打的星系朝打击来的方向画一条射线
	for h in me.hit_dirs:
		var age := state.turn - int(h["turn"])
		if age > Balance.SIGHTING_KEEP:
			continue
		var at := Vector3(h["at"])
		var alpha := clampf(1.0 - float(age) / Balance.SIGHTING_KEEP, 0.2, 1.0)
		_markers.add_child(_segment(at, at + (h["dir"] as Vector3) * 5.0, Color(COLOR_HIT_DIR, alpha)))

	# 听到的广播：被广播的坐标画粉色方框
	for c in me.heard:
		_markers.add_child(_broadcast_mark(c, 0.6))

	# 调试：画出所有星系和别人的舰船
	if _reveal:
		var all: Array[Vector3i] = []
		for c in state.system_cells:
			if state.cell_exists(c) and state.map.star_at(c) != StarMap.Star.NONE:
				all.append(c)
		_markers.add_child(_star_spheres(all, 1.0))
		for civ in state.civs:
			if civ != me and civ.alive:
				for s in civ.ships:
					if not s.dead and not s.docked:
						_draw_ship(s, COLOR_HIDDEN_AI)

	# 自己的星系、已知的敌人（越旧越淡）、（调试）其他文明
	var cells: Array[Vector3i] = []
	var box_colors: Array[Color] = []
	var box_sizes: Array[float] = []
	for c in me.colonies:
		cells.append(c)
		box_colors.append(COLOR_MINE)
		box_sizes.append(1.4 if c == me.home else 1.0)
	for c in me.known:
		var age := state.turn - me.known[c]
		cells.append(c)
		box_colors.append(Color(COLOR_KNOWN, clampf(1.0 - 0.7 * age / INTEL_FADE_TURNS, 0.3, 1.0)))
		box_sizes.append(1.0)
	if _reveal:
		for civ in state.civs:
			if civ != me and civ.alive:
				for c in civ.colonies:
					if not me.known.has(c):
						cells.append(c)
						box_colors.append(COLOR_HIDDEN_AI)
						box_sizes.append(1.0)
	var marker := BoxMesh.new()
	marker.size = Vector3.ONE * 0.5
	_markers.add_child(_instances(marker, cells, box_colors, box_sizes))
	# 文字标签：自己的母星系、已知的敌方星系
	if me.alive and not me.colonies.is_empty():
		var home_name := "你的母星" if me == state.human() and not state.spectator else me.name + " 的母星"
		_markers.add_child(_label3d(home_name, _warp_point(Vector3(me.home)) + Vector3(0, 0, 0.75), COLOR_MINE, 44))
	# 调试：标出别的文明的母星
	if _reveal:
		for civ in state.civs:
			if civ != me and civ.alive and not me.known.has(civ.home):
				_markers.add_child(_label3d(civ.name, _warp_point(Vector3(civ.home)) + Vector3(0, 0, 0.6),
						COLOR_HIDDEN_AI, 36))
	for c in me.known:
		if not _detail_at(c):
			continue
		var info: Dictionary = me.intel.get(c, {})
		var owner: int = info.get("owner", -1)
		var name := state.civs[owner].name if owner >= 0 else "敌人"
		_markers.add_child(_label3d(name, _warp_point(Vector3(c)) + Vector3(0, 0, 0.6), Color(COLOR_KNOWN, 0.9), 40))


## 派殖民船、星舰时画绿圈的星系：看到过的宜居星系（F4.4），只按情报，不泄露没看到过的。
func _colony_targets(me: Civ) -> Array[Vector3i]:
	return state.known_habitable(me)


## 宜居候选画成小球外加绿圈。
func _colony_candidates(me: Civ) -> Node3D:
	var cells := _colony_targets(me)
	var group := Node3D.new()
	group.add_child(_star_spheres(cells, 1.6))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.26
	group.add_child(_instances(ring, cells, _fill(cells.size(), COLOR_COLONY_SHIP), _fill_f(cells.size(), 1.0)))
	return group


## 图例：星图上每种标记的颜色和意思。
static func legend_text() -> String:
	return "[color=#4d99ff]■ / ▲[/color] 己方星系 / 飞行单位；停泊舰队按数量合并。\n" + 			"[color=#ff5959]■ / ◆[/color] 已知敌方星系 / 舰船；[color=#ff991a]◆[/color] 当前预警。旧情报越旧越淡。\n" + 			"[color=#b8c4d9]●[/color] 已探索星系；[color=#ff80cc]□ / ○[/color] 广播目标 / 最近三条传播波前。\n" + 			"[color=#fff259]○[/color] 当前选择；悬停看详情，选中看航线与设施；详细星图显示全部。\n" + 			"白片是降维箔，淡紫区域是降维或黑域；黑域中心有框。x / y / z 是坐标轴。"


# ---------- 绘图小工具 ----------

## 半透明的颜色在网页版里看起来和桌面版一样亮。
## 网页版用的画法（Compatibility）混合半透明颜色的方式不同，同样的透明度在黑底上暗很多，
## 视野、星星、坐标轴这些很淡的颜色几乎看不见。这时把不透明度按亮度曲线（sRGB）调高来补上。
static func _shown(color: Color) -> Color:
	if color.a >= 1.0 or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return color
	return Color(color, Color(color.a, 0, 0).linear_to_srgb().r)


func _label3d(text: String, pos: Vector3, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = _shown(color)
	l.font_size = size
	l.pixel_size = 0.0006
	l.fixed_size = true  # 远近都一样大，免得离相机近的字特别大
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true  # 不会被网格挡住
	l.outline_size = 8
	return l


## 给定的星系各画一个小球，颜色表示几颗恒星。
## 给了 intel 时按情报里记的恒星数画（星系后来可能被打掉或压扁，现在已经没有恒星了）。
func _star_spheres(cells: Array[Vector3i], size: float, intel := {}) -> MultiMeshInstance3D:
	var colors: Array[Color] = []
	for c in cells:
		var star: int = intel[c]["stars"] if intel.has(c) else state.map.star_at(c)
		colors.append(STAR_COLORS[star])
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	return _instances(sphere, cells, colors, _fill_f(cells.size(), size))


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _shown(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## 用一个 MultiMesh 一次画出很多同形状、不同颜色和大小的物体，放在格子上。
func _instances(mesh: Mesh, cells: Array[Vector3i], colors: Array[Color],
		sizes: Array[float]) -> MultiMeshInstance3D:
	var points: Array[Vector3] = []
	for c in cells:
		points.append(Vector3(c))
	return _instances_at(mesh, points, colors, sizes)


## 同上，放在任意位置（小数坐标）。
func _instances_at(mesh: Mesh, points: Array[Vector3], colors: Array[Color],
		sizes: Array[float]) -> MultiMeshInstance3D:
	var mat := _flat_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		var basis := Basis().scaled(Vector3.ONE * sizes[i])
		mm.set_instance_transform(i, Transform3D(basis, _warp_point(points[i])))
		mm.set_instance_color(i, _shown(colors[i]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	return node


## 半透明的球：视野、预警范围。二维里画成平面上的圆片，一维里画成直线上的一段，不伸出平面或直线。
func _bubble(center: Vector3, radius: float, color: Color) -> MeshInstance3D:
	radius = maxf(radius, 0.01)
	var mesh: Mesh
	if state.dimension == 3:
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		mesh = sphere
	elif state.dimension == 2:
		var disc := CylinderMesh.new()  # 圆柱默认沿 y 轴，下面转到沿 z
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = FLAT_THICKNESS
		disc.radial_segments = 32
		disc.rings = 1
		mesh = disc
	else:
		var bar := BoxMesh.new()
		bar.size = Vector3(radius * 2.0, FLAT_THICKNESS, FLAT_THICKNESS)
		mesh = bar
	var node := MeshInstance3D.new()
	node.mesh = mesh
	if state.dimension == 2:
		node.basis = Basis(Vector3.RIGHT, PI / 2)
	node.material_override = _flat_material(color)
	node.position = _warp_point(center)
	return node


## 从 p 到星图最远的角有多远。
func _farthest_corner(p: Vector3) -> float:
	var lo := Vector3(state.map.origin)
	var hi := lo + Vector3(state.map.extent - Vector3i.ONE)
	return (p - lo).abs().max((p - hi).abs()).length()



## 广播波前：三维用朝向相机的单环示意半径，二维画平面里的一个圆，
## 一维是直线上的一段（两头各一道短竖线）。圆圈围着中心画在画面上的位置，不再一小段一小段地跟着展开变形，
## 免得展开到一半时被拉得很长。
func _wave_rings(center: Vector3, radius: float, color: Color) -> void:
	const SEGMENTS := 48
	var at := _warp_point(center)
	if state.dimension == 1:
		var lo := Vector3(state.map.origin)
		var hi := lo + Vector3(state.map.extent - Vector3i.ONE)
		var left := maxf(center.x - radius, lo.x - Geometry.CELL_HALF)
		var right := minf(center.x + radius, hi.x + Geometry.CELL_HALF)
		var shift := at - center
		_tube(Vector3(left, center.y, center.z) + shift, Vector3(right, center.y, center.z) + shift, color, 0.04, false)
		for x in [left, right]:
			var end := Vector3(x, center.y, center.z) + shift
			_tube(end - Vector3(0, 0.6, 0), end + Vector3(0, 0.6, 0), color, 0.04, false)
		return
	if state.dimension == 3:
		var ring := TorusMesh.new()
		ring.inner_radius = maxf(0.001, radius - 0.01)
		ring.outer_radius = maxf(0.02, radius + 0.01)
		ring.rings = SEGMENTS
		ring.ring_segments = 4
		var wave := MeshInstance3D.new()
		wave.mesh = ring
		wave.material_override = _flat_material(color)
		wave.position = at
		_markers.add_child(wave)
		_orient(wave, _world.global_basis.inverse() * _camera.global_basis.z)
		_wave_nodes.append(wave)
		return
	for axis in [2]:
		var u := Vector3.ZERO
		var v := Vector3.ZERO
		u[(axis + 1) % 3] = radius
		v[(axis + 2) % 3] = radius
		for i in SEGMENTS:
			var a := TAU * i / SEGMENTS
			var b := TAU * (i + 1) / SEGMENTS
			_tube(at + u * cos(a) + v * sin(a), at + u * cos(b) + v * sin(b), color, 0.02, false)


## 让网格自带的 +y 轴朝向 facing。
func _orient(node: Node3D, facing: Vector3) -> void:
	if facing.is_zero_approx():
		return
	var up := Vector3.UP if absf(facing.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	node.basis = Basis.looking_at(facing, up) * Basis(Vector3.RIGHT, -PI / 2)


## 画一艘在飞的飞船：位置画一个小锥体，朝向飞行方向。
func _draw_ship(ship: Ship, color: Color) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.17 if ship.kind != Ship.GRAIN else 0.12
	cone.height = 0.42 if ship.kind != Ship.GRAIN else 0.3
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.material_override = _flat_material(color)
	node.position = _warp_point(ship.position())
	# 圆柱网格默认沿 y 轴，转到飞行方向
	_orient(node, Vector3.RIGHT if ship.direction.is_zero_approx() else ship.direction)
	_markers.add_child(node)


## 自己单位的航线（F4.3）：身后几个回合的轨迹（越早越淡），下一回合要飞的一段（实线），
## 再往后几个回合（淡一些），每回合的落点画一个小点；有目的地的，剩下的路画成虚线连到目的地。
func _draw_path(s: Ship, color: Color) -> void:
	var trail: Array = _trails.get(s.id, [])
	for i in trail.size() - 1:
		var fade := float(i + 1) / trail.size()
		_tube(trail[i], trail[i + 1], Color(color, 0.08 + 0.4 * fade), PATH_WIDTH * 0.6)
	var points := state.predict_path(state.ship_owner(s), s, PATH_TURNS)
	var ticks: Array[Vector3] = []
	var tick_colors: Array[Color] = []
	for i in points.size() - 1:
		var next := i == 0
		_tube(points[i], points[i + 1], Color(color, 0.95 if next else 0.4), PATH_WIDTH * (1.0 if next else 0.6))
		ticks.append(points[i + 1])
		tick_colors.append(Color(color, 0.9 if next else 0.4))
	if s.has_target and points[-1].distance_to(s.target) > 0.05:
		var from: Vector3 = points[-1]
		var gap := s.target - from
		var dashes := ceili(gap.length() / 0.5)
		for i in dashes:
			var a := from + gap * (float(i) / dashes)
			var b := from + gap * minf(1.0, (i + 0.5) / dashes)
			_tube(a, b, Color(color, 0.35), PATH_WIDTH * 0.5)
	var tick := SphereMesh.new()
	tick.radius = 0.06
	tick.height = 0.12
	tick.radial_segments = 8
	tick.rings = 4
	_markers.add_child(_instances_at(tick, ticks, tick_colors, _fill_f(ticks.size(), 1.0)))


## 记下自己单位的位置，画身后的轨迹用。位置变了（过了一回合）才多记一个，最多记 TRAIL_TURNS 个。
func _remember_trails(me: Civ) -> void:
	var alive := {}
	for s in me.ships:
		if s.dead or s.docked:
			continue
		alive[s.id] = true
		var trail: Array = _trails.get(s.id, [])
		if trail.is_empty() or not (trail[-1] as Vector3).is_equal_approx(s.pos):
			trail.append(s.pos)
		if trail.size() > TRAIL_TURNS + 1:
			trail = trail.slice(-(TRAIL_TURNS + 1))
		_trails[s.id] = trail
	for id in _trails.keys():
		if not alive.has(id):
			_trails.erase(id)


## 记一段粗线，refresh 最后由 _tubes() 一起画。
## warp 为假时 from、to 已经是画面上的位置，不再跟着展开变形。
func _tube(from: Vector3, to: Vector3, color: Color, width: float, warp := true) -> void:
	_tube_parts.append([from, to, color, width, warp])


## 把记下的粗线画成细圆柱（普通线只有 1 像素宽，看不清）。长线分成小段，跟着压平区域旁边的变形弯曲。
func _tubes() -> MultiMeshInstance3D:
	var pieces: Array[Array] = []
	for part in _tube_parts:
		var from: Vector3 = part[0]
		var to: Vector3 = part[1]
		if not part[4]:
			pieces.append([from, to, part[2], part[3]])
			continue
		var steps := maxi(1, ceili(from.distance_to(to) * 2.0))
		for i in steps:
			var a := _warp_point(from.lerp(to, float(i) / steps))
			var b := _warp_point(from.lerp(to, float(i + 1) / steps))
			if a.distance_to(b) > 1e-4:
				pieces.append([a, b, part[2], part[3]])
	var rod := CylinderMesh.new()
	rod.top_radius = 1.0
	rod.bottom_radius = 1.0
	rod.height = 1.0
	rod.radial_segments = 6
	rod.rings = 1
	rod.cap_top = false
	rod.cap_bottom = false
	var mat := _flat_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rod
	mm.instance_count = pieces.size()
	for i in pieces.size():
		var a: Vector3 = pieces[i][0]
		var b: Vector3 = pieces[i][1]
		var width: float = pieces[i][3]
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP if absf(along.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT).normalized()
		var up := side.cross(along)
		var basis := Basis(side * width, along * a.distance_to(b), up * width)
		mm.set_instance_transform(i, Transform3D(basis, (a + b) / 2.0))
		mm.set_instance_color(i, _shown(pieces[i][2]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	return node


## 广播坐标只画空心边框，避免遮住这里已有的星系。
func _broadcast_mark(c: Vector3i, alpha: float) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		for i in [-1, 1]:
			for j in [-1, 1]:
				var a := Vector3.ZERO
				a[axis] = -0.38
				a[(axis + 1) % 3] = 0.38 * i
				a[(axis + 2) % 3] = 0.38 * j
				var b := a
				b[axis] = 0.38
				mesh.surface_add_vertex(a)
				mesh.surface_add_vertex(b)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = _warp_point(Vector3(c))
	node.material_override = _flat_material(Color(COLOR_BROADCAST, alpha))
	return node


## 目标格子：一个半透明的方块。
func _target_mark(c: Vector3i, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.7
	node.mesh = mesh
	node.material_override = _flat_material(color)
	node.position = _warp_point(Vector3(c))
	return node


## 黑域中心那一格（G14）：半透明的方块加一圈边框。
func _domain_box(center: Vector3i, color: Color) -> Node3D:
	var size := Vector3.ONE
	var group := Node3D.new()
	group.position = _warp_point(Vector3(center))
	var fill := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	fill.mesh = mesh
	fill.material_override = _flat_material(color)
	group.add_child(fill)
	var lo := -size / 2.0
	var hi := size / 2.0
	for a in [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z)]:
		group.add_child(_segment(a, Vector3(a.x, hi.y, a.z), COLOR_DOMAIN_EDGE, false))
	for y in [lo.y, hi.y]:
		group.add_child(_segment(Vector3(lo.x, y, lo.z), Vector3(hi.x, y, lo.z), COLOR_DOMAIN_EDGE, false))
		group.add_child(_segment(Vector3(lo.x, y, hi.z), Vector3(hi.x, y, hi.z), COLOR_DOMAIN_EDGE, false))
		group.add_child(_segment(Vector3(lo.x, y, lo.z), Vector3(lo.x, y, hi.z), COLOR_DOMAIN_EDGE, false))
		group.add_child(_segment(Vector3(hi.x, y, lo.z), Vector3(hi.x, y, hi.z), COLOR_DOMAIN_EDGE, false))
	return group


## 从起点沿方向画一条线。
func _arrow(from: Vector3, direction: Vector3, length: float, color: Color) -> MeshInstance3D:
	if direction.length() < 1e-6:
		return MeshInstance3D.new()
	return _segment(from, from + direction.normalized() * length, color)


## 从 from 沿方向走多远会离开星图。
func _length_inside(from: Vector3, direction: Vector3) -> float:
	if direction.length() < 1e-6:
		return 0.0
	var step := direction.normalized() * 0.1
	var traveled := 0.0
	var p := from
	while not Ship.outside(p, state.map.bounds()) and traveled < SHIP_PREVIEW_LENGTH * 2.0:
		p += step
		traveled += 0.1
	return traveled


## 一条线段。默认跟着压平区域旁边的变形走（和星系、网格对得上）；
## 坐标轴、以及画在别的节点里面的局部线段要传 warp = false。
func _segment(from: Vector3, to: Vector3, color: Color, warp := true) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if warp:
		# 长线段分成小段，变形以后才是弯的，而不是直接连两头
		var steps := maxi(1, ceili(from.distance_to(to) * 2.0))
		for i in steps:
			mesh.surface_add_vertex(_warp_point(from.lerp(to, float(i) / steps)))
			mesh.surface_add_vertex(_warp_point(from.lerp(to, float(i + 1) / steps)))
	else:
		mesh.surface_add_vertex(from)
		mesh.surface_add_vertex(to)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flat_material(color)
	return node


func _fill(n: int, color: Color) -> Array[Color]:
	var a: Array[Color] = []
	a.resize(n)
	a.fill(color)
	return a


func _fill_f(n: int, value: float) -> Array[float]:
	var a: Array[float] = []
	a.resize(n)
	a.fill(value)
	return a
