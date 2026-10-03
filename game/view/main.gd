extends Node3D
## 画面：把规则状态画成 3D 星图，加上右侧控制面板。
## 只读取 GameState，所有行动都通过 GameState 的方法完成。
## 操作：左键拖动旋转，滚轮缩放。

const SEED := 1

const STAR_COLORS := {
	StarMap.Star.SINGLE: Color(1.0, 0.9, 0.5, 0.35),
	StarMap.Star.DOUBLE: Color(1.0, 0.6, 0.2, 0.35),
	StarMap.Star.TRIPLE: Color(1.0, 0.3, 0.3, 0.35),
}
const COLOR_MINE := Color(0.3, 0.6, 1.0)
const COLOR_KNOWN := Color(1.0, 0.15, 0.15)
const COLOR_HIDDEN_AI := Color(0.7, 0.7, 0.7)
const COLOR_CONE := Color(0.2, 1.0, 1.0, 0.18)
const COLOR_BEAM := Color(1.0, 0.3, 1.0, 0.18)
const COLOR_RECORD_HIT := Color(1.0, 0.9, 0.0)
const COLOR_SHIP := Color(1.0, 0.55, 0.1)
const COLOR_SHIP_PATH := Color(1.0, 0.55, 0.1, 0.12)
## 战舰预览画多远：足够穿过整张星图
const SHIP_PREVIEW_LENGTH := 16.0
const COLOR_RECORD_EMPTY := Color(0.5, 0.5, 0.6, 0.5)
const COLOR_COLONY_SHIP := Color(0.3, 1.0, 0.5)
const COLOR_COLONY_PATH := Color(0.3, 1.0, 0.5, 0.12)
const COLOR_FOIL := Color(1.0, 1.0, 1.0)
const COLOR_FOIL_COLUMN := Color(1.0, 1.0, 1.0, 0.1)
## 被压平的区域：画成一层薄片
const COLOR_FLAT := Color(0.8, 0.75, 1.0, 0.35)
const COLOR_DYSON := Color(1.0, 0.8, 0.2)
const COLOR_MINER := Color(0.75, 0.55, 0.35)
const COLOR_STARSHIP := Color(0.3, 0.9, 1.0)
const COLOR_DOMAIN := Color(0.25, 0.15, 0.45, 0.55)
const COLOR_DOMAIN_EDGE := Color(0.55, 0.45, 0.9)
const COLOR_BROADCAST := Color(1.0, 0.5, 0.8)
## 坐标轴颜色：x 红、y 绿、z 蓝。面板里的 x、y、z 输入框用同样的颜色。
const AXIS_COLORS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.4, 1.0, 0.4), Color(0.4, 0.6, 1.0)]

enum Action { SCOUT, LIGHTGRAIN, WARSHIP, COLONY, FOIL, DOMAIN, BROADCAST, STARSHIP }

var state: GameState

var _pivot := Node3D.new()
## 星图的所有内容（网格、坐标轴、标记）都放在这个节点下，直接用规则里的坐标。
## 规则用右手系、z 轴向上；Godot 是 y 轴向上，所以把这个节点绕 x 轴转一下：
## 规则的 x、y、z 分别对应 Godot 的 x、-z、y。
var _world := Node3D.new()
var _camera := Camera3D.new()
var _distance := 17.0
var _dragging := false

var _markers := Node3D.new()
## 右侧面板宽度
const PANEL_WIDTH := 380

var _status := Label.new()
## 各项数值的标签，键是左边显示的名字
var _stat_values: Dictionary[String, Label] = {}
## 面板最上面的资源数字：能量、矿石、行动点
var _res_values: Dictionary[String, Label] = {}
var _log := RichTextLabel.new()
var _end := Button.new()
var _origin_pick := OptionButton.new()
## 现在选中的行动（Action 里的一个）
var _action := Action.SCOUT
var _action_tiles: Dictionary[int, Button] = {}
## 建造和升级的按钮，键是 _build_specs() 里的种类
var _build_tiles: Dictionary[String, Button] = {}
var _action_name := Label.new()
var _action_desc := Label.new()
var _go := Button.new()
## 执行按钮下面的小字：为什么现在不能执行
var _go_hint := Label.new()
## 结束回合按钮上面的提示：上一次操作失败的原因
var _feedback := Label.new()
const AngleDial := preload("res://view/angle_dial.gd")
## 方向用两个角度表示，各用一个圆盘调：水平角（在等高平面里转，0° 朝 x 轴，90° 朝 y 轴）
## 和俯仰角（半圆，往上为正）
var _yaw := AngleDial.new()
var _pitch := AngleDial.new()
var _reveal := CheckBox.new()
var _legend := RichTextLabel.new()
## 方向输入（探测、光粒、战舰、殖民船用）
var _dir_box := VBoxContainer.new()
## 目标坐标输入（二向箔用）
var _target_box := VBoxContainer.new()
var _target_label := Label.new()
## 目标位置用极坐标表示：方向用上面的两个角度圆盘，再加离发射源的距离
var _dist := HSlider.new()
var _dist_label := Label.new()
## 算出来的目标格子
var _target_info := Label.new()
## 方向和目标共用的提示（文字按行动不同）
var _aim_hint: Label
var _known_pick := OptionButton.new()
## 空间网格。压平的格子只留下平面那一层，所以压平的范围变了要重画。
var _grid := MeshInstance3D.new()
## 网格画的是哪个压平状态（和 state.flattened 比较，找出新压平的格子）。
## 动画时从 _grid_flat_old 过渡到 _grid_flat。
var _grid_flat: Dictionary[Vector3i, int] = {}
var _grid_flat_old: Dictionary[Vector3i, int] = {}
## 还活着的空间的边界面（侧面看像躺倒的沙漏，二向箔中心最扁）
var _funnel := MeshInstance3D.new()
## 还活着的空间的上下边界，见 _envelope。动画时从 _env_old 过渡到 _env_new。
var _env_old := {}
var _env_new := {}
## 边界面每格分几段（分得越细，曲面越平滑）
const ENV_SUBDIV := 2
## 过渡进度，0 到 1
var _warp_t := 1.0
const FLAT_ANIM_SECONDS := 1.2
## 鼠标点选：按下的位置（松开时没怎么动就算点击，否则是拖动旋转）
var _press_pos := Vector2.ZERO
## 鼠标停在哪个格子上（没有时为 NO_CELL）
var _hover := NO_CELL
## 鼠标所指的格子：一个线框方块，旁边写着坐标
var _cursor := Node3D.new()
var _cursor_label := Label3D.new()

const NO_CELL := Vector3i(-1, -1, -1)
## 鼠标离标记多近（像素）就直接选中标记
const SNAP_PX := 16.0
const COLOR_BUNKER := Color(0.6, 0.65, 0.75)


func _ready() -> void:
	state = GameState.new_game(SEED)
	_world.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	add_child(_world)
	_setup_camera()
	_grid.material_override = _flat_material(Color(1, 1, 1, 0.05))
	_world.add_child(_grid)
	var funnel_mat := _flat_material(Color(COLOR_FLAT, 0.1))
	funnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_funnel.material_override = funnel_mat
	_world.add_child(_funnel)
	_draw_grid()
	_draw_axes()
	_world.add_child(_markers)
	_build_cursor()
	_build_panel()
	refresh()


# ---------- 相机 ----------

func _setup_camera() -> void:
	_pivot.position = _world.transform * (Vector3.ONE * (StarMap.SIZE - 1) / 2.0)
	# 课本上常见的画法：x 轴朝左前方（朝着看的人），y 轴朝右，z 轴朝上
	_pivot.rotation_degrees = Vector3(-25, 115, 0)
	add_child(_pivot)
	_pivot.add_child(_camera)
	_update_camera()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.05)
	add_child(env)


## 相机后退到 _distance，并向右平移，让星图中心落在面板左边那块画面的正中。
## 平移量按画面宽度换算：右侧面板占掉的宽度的一半。
func _update_camera() -> void:
	var view := get_viewport().get_visible_rect().size
	var half_height := _distance * tan(deg_to_rad(_camera.fov / 2.0))
	var world_per_px := 2.0 * half_height / view.y
	_camera.position = Vector3(0, 0, _distance)
	_camera.h_offset = PANEL_WIDTH / 2.0 * world_per_px


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_press_pos = mb.position
			elif mb.position.distance_to(_press_pos) < 5.0:
				_on_map_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(6.0, _distance - 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(60.0, _distance + 1.0)
		_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_pivot.rotation_degrees.y -= mm.relative.x * 0.3
		_pivot.rotation_degrees.x = clampf(_pivot.rotation_degrees.x - mm.relative.y * 0.3, -89, 89)
	elif event is InputEventMouseMotion:
		_set_hover(_pick_cell((event as InputEventMouseMotion).position))


# ---------- 在星图上点选格子 ----------

## 鼠标所指的格子。先看附近有没有标记（自己的星系、已知的敌人、星舰、可以殖民的星系等），
## 有就选最近的那个；没有就选鼠标射线和发射源所在高度那一层平面的交点。
func _pick_cell(pos: Vector2) -> Vector3i:
	if pos.x > get_viewport().get_visible_rect().size.x - PANEL_WIDTH:
		return NO_CELL
	var best := NO_CELL
	var best_d := SNAP_PX
	for c in _snap_cells():
		var p := _world.to_global(_warp_point(Vector3(c)))
		if _camera.is_position_behind(p):
			continue
		var d := _camera.unproject_position(p).distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	if best != NO_CELL:
		return best
	var from := _world.to_local(_camera.project_ray_origin(pos))
	var dir := _world.global_transform.basis.inverse() * _camera.project_ray_normal(pos)
	if absf(dir.z) < 1e-6:
		return NO_CELL
	var layer := _aim_origin().z
	var t := (layer - from.z) / dir.z
	if t < 0:
		return NO_CELL
	var hit := from + dir * t
	var c := Vector3i(roundi(hit.x), roundi(hit.y), layer)
	return c if StarMap.in_bounds(c) else NO_CELL


## 可以直接点中的标记所在的格子。
func _snap_cells() -> Array[Vector3i]:
	var me := state.human()
	var cells: Array[Vector3i] = []
	cells.append_array(me.colonies)
	for c in me.known:
		cells.append(c)
	if me.has_starship:
		cells.append(me.starship)
	if _action == Action.COLONY or _action == Action.STARSHIP:
		for c in state.map.habitable:
			if state.map.star_at(c) != StarMap.Star.NONE and not me.owns(c):
				cells.append(c)
	if _reveal.button_pressed:
		for c in state.map.stars:
			if state.map.stars[c] != StarMap.Star.NONE:
				cells.append(c)
	return cells


func _set_hover(c: Vector3i) -> void:
	if c == _hover:
		return
	_hover = c
	_cursor.visible = c != NO_CELL
	if c == NO_CELL:
		return
	_cursor.position = _warp_point(Vector3(c))
	var me := state.human()
	var what := ""
	if me.owns(c):
		what = "　你的星系"
	elif me.known.has(c):
		what = "　已知的敌人"
	elif me.has_starship and me.starship == c:
		what = "　你的星舰"
	elif state.map.is_habitable(c) and (_action == Action.COLONY or _action == Action.STARSHIP):
		what = "　宜居星系"
	_cursor_label.text = "(%d, %d, %d)%s" % [c.x, c.y, c.z, what]


## 点了星图上的格子：两个角度转到「从发射源指向这个格子」；要目标的行动，距离也填好。
func _on_map_click(pos: Vector2) -> void:
	var c := _pick_cell(pos)
	if c == NO_CELL or state.is_over():
		return
	_aim_at(c)


## 让两个角度（和距离）指向格子 c。
func _aim_at(c: Vector3i) -> void:
	var v := Vector3(c - _aim_origin())
	if v == Vector3.ZERO and not _target_box.visible:
		return
	if v != Vector3.ZERO:
		_yaw.value = roundf(rad_to_deg(atan2(v.y, v.x)))
		_pitch.value = roundf(rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length())))
	_dist.set_value_no_signal(v.length())
	refresh()


## 角度和距离从哪里算起：星舰移动从星舰算，其他从选中的发射源算。
func _aim_origin() -> Vector3i:
	if _action == Action.STARSHIP and state.human().has_starship:
		return state.human().starship
	return _selected_origin()


## 鼠标所指格子的标记：线框方块加坐标文字。
func _build_cursor() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.95
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = _flat_material(Color(1, 1, 1, 0.12))
	_cursor.add_child(node)
	_cursor_label.position = Vector3(0, 0, 0.7)
	_cursor_label.font_size = 40
	_cursor_label.pixel_size = 0.0006
	_cursor_label.fixed_size = true
	_cursor_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cursor_label.no_depth_test = true
	_cursor_label.outline_size = 8
	_cursor.add_child(_cursor_label)
	_cursor.visible = false
	_world.add_child(_cursor)


# ---------- 固定的背景：网格和坐标轴 ----------

## 每个整数坐标沿三个方向连线，组成空间网格。压没的格子不画，压平的只留下平面那一层。
## 还活着的空间用半透明的面围起来：二向箔中心最扁，越往外越厚（侧面看像躺倒的沙漏）。
## 画的就是规则里真正还活着的范围。
func _draw_grid() -> void:
	_grid_flat = state.flattened.duplicate()
	_grid_flat_old = _grid_flat
	_env_new = _envelope()
	_env_old = _env_new
	_warp_t = 1.0
	_rebuild_warped()


## 还活着的空间的上下边界：键是边界面上的点（每格分 ENV_SUBDIV 段），值是 Vector2(下沿, 上沿) 的高度。
## 没有展开的二向箔时，就是整张星图的上下边。
func _envelope() -> Dictionary:
	var env := {}
	var n := float(StarMap.SIZE - 1)
	var steps := (StarMap.SIZE - 1) * ENV_SUBDIV
	for i in steps + 1:
		for j in steps + 1:
			var p := Vector2(i, j) / ENV_SUBDIV
			var lo := 0.0
			var hi := n
			for zone in state.foil_zones:
				var center: Vector3i = zone["center"]
				var room := GameState.zone_room(zone["age"], p.distance_to(Vector2(center.x, center.y)))
				lo = maxf(lo, center.z - room)
				hi = minf(hi, center.z + room)
			env[Vector2i(i, j)] = Vector2(lo, maxf(lo, hi))
	return env


## 一点在压平动画中的位置：新压平的格子里的点，从原来的高度慢慢落到平面上；
## 已经压平的格子里的点在平面上；没压平的格子不动。
func _warp_point(p: Vector3, blend := 1.0) -> Vector3:
	var c := Vector3i(clampi(roundi(p.x), 0, StarMap.SIZE - 1), clampi(roundi(p.y), 0, StarMap.SIZE - 1),
			clampi(roundi(p.z), 0, StarMap.SIZE - 1))
	if not _grid_flat.has(c):
		return p
	var plane := float(_grid_flat[c])
	if _grid_flat_old.has(c):
		return Vector3(p.x, p.y, plane)
	return Vector3(p.x, p.y, lerpf(p.z, plane, blend))


## 按现在的过渡进度重画网格和压平区域边上的曲面。
func _rebuild_warped() -> void:
	# 动画中还用旧的网格（新压平的格子里的线还在，正落到平面上），动画结束后换成新的
	var segs := _grid_segments(_grid_flat if _warp_t >= 1.0 else _grid_flat_old)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for s in segs.values():
		mesh.surface_add_vertex(_warp_point(s[0], _warp_t))
		mesh.surface_add_vertex(_warp_point(s[1], _warp_t))
	mesh.surface_end()
	_grid.mesh = mesh
	_funnel.mesh = _funnel_mesh()


## 还活着的空间的边界面：上下各一张，在二向箔中心贴着平面，往外慢慢张开，
## 合起来侧面看像躺倒的沙漏。贴着星图上下边的地方（还没被压到）不画。
func _funnel_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var n := float(StarMap.SIZE - 1)
	var steps := (StarMap.SIZE - 1) * ENV_SUBDIV
	var tris: Array[Vector3] = []
	for i in steps:
		for j in steps:
			var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			var top: Array[Vector3] = []
			var bottom: Array[Vector3] = []
			var top_edge := true
			var bottom_edge := true
			for c in corners:
				var e: Vector2 = _env_old[c].lerp(_env_new[c], _warp_t)
				var p := Vector2(c) / ENV_SUBDIV
				bottom.append(Vector3(p.x, p.y, e.x))
				top.append(Vector3(p.x, p.y, e.y))
				top_edge = top_edge and e.y >= n - 0.01
				bottom_edge = bottom_edge and e.x <= 0.01
			if not top_edge:
				tris.append_array([top[0], top[1], top[2], top[0], top[2], top[3]])
			if not bottom_edge:
				tris.append_array([bottom[0], bottom[1], bottom[2], bottom[0], bottom[2], bottom[3]])
	if tris.is_empty():
		return mesh
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		mesh.surface_add_vertex(v)
	mesh.surface_end()
	return mesh



## 网格的每一小段（相邻两个格子之间的连线），键是线段中点，值是 [起点, 终点]。
## 一段线只有两头的格子都还在（没压平，或者就是平面那一层），才画出来。
func _grid_segments(flat: Dictionary[Vector3i, int]) -> Dictionary:
	var keep := func(x: int, y: int, z: int) -> bool:
		var c := Vector3i(x, y, z)
		return not flat.has(c) or flat[c] == z
	var segs := {}
	for a in StarMap.SIZE:
		for b in StarMap.SIZE:
			for i in StarMap.SIZE - 1:
				if keep.call(i, a, b) and keep.call(i + 1, a, b):
					segs[Vector3(i + 0.5, a, b)] = [Vector3(i, a, b), Vector3(i + 1, a, b)]
				if keep.call(a, i, b) and keep.call(a, i + 1, b):
					segs[Vector3(a, i + 0.5, b)] = [Vector3(a, i, b), Vector3(a, i + 1, b)]
				if keep.call(a, b, i) and keep.call(a, b, i + 1):
					segs[Vector3(a, b, i + 0.5)] = [Vector3(a, b, i), Vector3(a, b, i + 1)]
	return segs


## 压平的范围变了：从旧的形状慢慢过渡到新的（新压没的格子落到平面上，边界面跟着收紧）。
func _animate_flattening() -> void:
	if state.flattened.size() == _grid_flat.size():
		return
	_grid_flat_old = _grid_flat
	_grid_flat = state.flattened.duplicate()
	_env_old = _env_new
	_env_new = _envelope()
	_warp_t = 0.0


func _process(delta: float) -> void:
	if _warp_t >= 1.0:
		return
	_warp_t = minf(1.0, _warp_t + delta / FLAT_ANIM_SECONDS)
	_rebuild_warped()


## 从 (0,0,0) 那个角沿三条边画出坐标轴，标上轴名和 0～9 的刻度，
## 让玩家看得出每个格子的坐标。文字总是朝向相机。
func _draw_axes() -> void:
	var n := StarMap.SIZE - 1
	# 轴线放在网格外侧一点，免得和网格线重叠
	var start := Vector3.ONE * -0.6
	for i in 3:
		var axis := Vector3.ZERO
		axis[i] = 1.0
		var color := AXIS_COLORS[i]
		_world.add_child(_segment(start, start + axis * (n + 1.8), color, false))
		_world.add_child(_label3d(["x", "y", "z"][i], start + axis * (n + 2.3), color, 64))
		for k in StarMap.SIZE:
			var p := start + axis * (k + 0.6)
			_world.add_child(_label3d(str(k), p, Color(color, 0.85), 48))
	_world.add_child(_label3d("(0,0,0)", start - Vector3.ONE * 0.4, Color(1, 1, 1, 0.6), 32))


func _label3d(text: String, pos: Vector3, color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.modulate = color
	l.font_size = size
	l.pixel_size = 0.0006
	l.fixed_size = true  # 远近都一样大，免得离相机近的字特别大
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true  # 不会被网格挡住
	l.outline_size = 8
	return l


## 给定的星系各画一个小球，颜色表示几颗恒星。
## 星系位置不公开，平时不画；只在派殖民船时画宜居星系（设计说明 §1）。
func _star_spheres(cells: Array[Vector3i], size: float) -> MultiMeshInstance3D:
	var colors: Array[Color] = []
	for c in cells:
		colors.append(STAR_COLORS[state.map.star_at(c)])
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	return _instances(sphere, cells, colors, _fill_f(cells.size(), size))


# ---------- 会变化的部分：标记和面板 ----------

## 规则状态变了以后调用，重画标记、刷新面板。
func refresh() -> void:
	for child in _markers.get_children():
		child.queue_free()
	var me := state.human()
	_refresh_origins()
	_animate_flattening()
	_set_hover(NO_CELL)

	var foil_mode := _action == Action.FOIL
	var domain_mode := _action == Action.DOMAIN
	var broadcast_mode := _action == Action.BROADCAST
	var target_mode := foil_mode or domain_mode or broadcast_mode
	_target_box.visible = target_mode
	if target_mode:
		_aim_hint.text = "👆 在星图上点一个格子，就选它当目标。也可以用两个角度加距离来定位置（从发射源算起）。"
	else:
		_aim_hint.text = "👆 在星图上点一个格子，方向就指向它。也可以沿圆边拖动圆钮微调，滚轮每格 1°。"
	if foil_mode:
		_target_label.text = "离发射源多远（以目标格子为中心压平）"
	elif domain_mode:
		_target_label.text = "离发射源多远（黑域中心不能超出探测长度）"
	else:
		_target_label.text = "离发射源多远（要公开的坐标，星图内任意格子）"
	_dist_label.text = "%.1f 格" % _dist.value
	var goal := _target_cell()
	if StarMap.in_bounds(goal):
		_target_info.text = "目标格子：(%d, %d, %d)" % [goal.x, goal.y, goal.z]
		_target_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	else:
		_target_info.text = "目标格子 (%d, %d, %d) 在星图外面" % [goal.x, goal.y, goal.z]
		_target_info.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))

	# 广播预览和准备中的广播：在坐标上画一个粉色方框
	if me.alive and not state.is_over() and broadcast_mode:
		_markers.add_child(_broadcast_mark(_target_cell(), 1.0))
	for b in me.pending_broadcasts:
		_markers.add_child(_broadcast_mark(b["target"], 0.5))
	_target_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))

	# 黑域预览：将来生效的立方体范围
	if me.alive and not state.is_over() and domain_mode:
		var origin := _selected_origin()
		var center := _target_cell()
		_markers.add_child(_domain_box(center, Color(COLOR_DOMAIN_EDGE, 0.25)))
		_markers.add_child(_segment(Vector3(origin), Vector3(center), COLOR_DOMAIN_EDGE))

	# 二向箔预览：从发射源到目标的直线，目标那一层（展开后最先压平、扩散最远的平面）
	if me.alive and not state.is_over() and foil_mode:
		var origin := _selected_origin()
		var target := _target_cell()
		var layer: Array[Vector3i] = []
		for x in StarMap.SIZE:
			for y in StarMap.SIZE:
				layer.append(Vector3i(x, y, target.z))
		var tile := BoxMesh.new()
		tile.size = Vector3(1.0, 1.0, 0.03)
		_markers.add_child(_instances(tile, layer, _fill(layer.size(), COLOR_FOIL_COLUMN), _fill_f(layer.size(), 1.0)))
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.9
		var aim: Array[Vector3i] = [target]
		_markers.add_child(_instances(box, aim, _fill(1, Color(COLOR_FOIL, 0.3)), _fill_f(1, 1.0)))
		_markers.add_child(_segment(Vector3(origin), Vector3(target), COLOR_FOIL))

	# 行动范围预览：探测是圆锥，光粒是圆柱
	if me.alive and not state.is_over() and not target_mode:
		var origin := _selected_origin()
		var direction := _direction()
		var area: Array[Vector3i]
		var color := COLOR_CONE
		var length := me.scout_range
		if _action == Action.LIGHTGRAIN:
			area = Geometry.cylinder_cells(origin, direction, me.strike_range, me.strike_radius)
			color = COLOR_BEAM
			length = me.strike_range
		elif _action == Action.WARSHIP:
			area = Geometry.cylinder_cells(origin, direction, SHIP_PREVIEW_LENGTH, me.strike_radius)
			color = COLOR_SHIP_PATH
			length = _length_inside(origin, direction)
		elif _action == Action.STARSHIP:
			if me.has_starship:
				origin = me.starship
			area = Geometry.cylinder_cells(origin, direction, Balance.STARSHIP_JUMP, 0.0)
			color = Color(COLOR_STARSHIP, 0.15)
			length = Balance.STARSHIP_JUMP
		elif _action == Action.COLONY:
			area = Geometry.cylinder_cells(origin, direction, SHIP_PREVIEW_LENGTH, Balance.COLONY_SHIP_RADIUS)
			color = COLOR_COLONY_PATH
			length = _length_inside(origin, direction)
			_markers.add_child(_settle_candidates(me))
		else:
			area = Geometry.cone_cells(origin, direction, me.scout_range, me.cone_angle)
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.9
		_markers.add_child(_instances(box, area, _fill(area.size(), color), _fill_f(area.size(), 1.0)))
		_markers.add_child(_arrow(origin, direction, length, Color(color, 1.0)))

	# 在飞的战舰和殖民船：位置画一个小锥体，朝向飞行方向；再画出下一回合要飞的一段
	for ship in me.warships:
		_draw_ship(ship, COLOR_SHIP, Balance.WARSHIP_SPEED)
	for ship in me.colony_ships:
		_draw_ship(ship, COLOR_COLONY_SHIP, Balance.COLONY_SHIP_SPEED)

	# 自己的戴森球：星系外面套金色圆环，个数越多环越大
	var dyson_cells: Array[Vector3i] = []
	var dyson_sizes: Array[float] = []
	for c in me.dysons:
		if me.dysons[c] > 0:
			dyson_cells.append(c)
			dyson_sizes.append(0.85 + 0.15 * me.dysons[c])
	var dyson_ring := TorusMesh.new()
	dyson_ring.inner_radius = 0.42
	dyson_ring.outer_radius = 0.5
	_markers.add_child(_instances(dyson_ring, dyson_cells, _fill(dyson_cells.size(), COLOR_DYSON), dyson_sizes))

	# 自己的星舰：青色的八面体（像一颗钻石）
	if me.has_starship:
		var gem := SphereMesh.new()
		gem.radius = 0.28
		gem.height = 0.56
		gem.radial_segments = 4
		gem.rings = 2
		var ship_node := MeshInstance3D.new()
		ship_node.mesh = gem
		ship_node.material_override = _flat_material(COLOR_STARSHIP)
		ship_node.position = _warp_point(Vector3(me.starship))
		_markers.add_child(ship_node)

	# 自己的采矿船：星系旁边一个棕色小方块
	var miner_cells: Array[Vector3i] = []
	for c in me.miners:
		miner_cells.append(c)
	var miner_box := BoxMesh.new()
	miner_box.size = Vector3.ONE * 0.16
	var miner_node := _instances(miner_box, miner_cells, _fill(miner_cells.size(), COLOR_MINER), _fill_f(miner_cells.size(), 1.0))
	miner_node.position = Vector3(0.42, 0.42, 0.0)  # 放在星系的斜上方一点，不和星系的方块重叠
	_markers.add_child(miner_node)

	# 自己的掩体：星系下方一块灰色方片
	var bunker_cells: Array[Vector3i] = []
	for c in me.bunkers:
		bunker_cells.append(c)
	var disc := BoxMesh.new()
	disc.size = Vector3(0.6, 0.6, 0.04)
	var bunker_node := _instances(disc, bunker_cells, _fill(bunker_cells.size(), COLOR_BUNKER), _fill_f(bunker_cells.size(), 1.0))
	bunker_node.position = Vector3(0, 0, -0.3)
	_markers.add_child(bunker_node)

	# 自己的二向箔：白色小方片，连一条线到目标
	for foil in me.foils:
		var sheet := BoxMesh.new()
		sheet.size = Vector3(0.35, 0.35, 0.02)
		var node := MeshInstance3D.new()
		node.mesh = sheet
		node.material_override = _flat_material(COLOR_FOIL)
		node.position = _warp_point(foil.position())
		_markers.add_child(node)
		_markers.add_child(_segment(foil.position(), Vector3(foil.target), Color(COLOR_FOIL, 0.4)))

	# 被压平的区域：在压成的平面上画薄片（每列一片），所有文明都看得到
	if not state.flattened.is_empty():
		var flat_cells: Array[Vector3i] = []
		for c in state.flattened:
			if c.z == state.flattened[c]:
				flat_cells.append(c)
		var tile := BoxMesh.new()
		tile.size = Vector3(1.0, 1.0, 0.03)
		_markers.add_child(_instances(tile, flat_cells, _fill(flat_cells.size(), COLOR_FLAT), _fill_f(flat_cells.size(), 1.0)))

	# 黑域：生效的画成深色立方体，所有文明都看得到；自己准备中的只画边框
	for center in state.black_domains:
		_markers.add_child(_domain_box(center, COLOR_DOMAIN))
	for d in me.pending_domains:
		_markers.add_child(_domain_box(d["center"], Color(COLOR_DOMAIN_EDGE, 0.15)))

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

	# 调试：画出所有星系
	if _reveal.button_pressed:
		var all: Array[Vector3i] = []
		for c in state.map.stars:
			if state.map.stars[c] != StarMap.Star.NONE:
				all.append(c)
		_markers.add_child(_star_spheres(all, 1.0))
	_legend.text = _legend_text(_action == Action.COLONY)

	# 自己的星系、已发现的敌人、（调试）其他文明
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var sizes: Array[float] = []
	for c in me.colonies:
		cells.append(c)
		colors.append(COLOR_MINE)
		sizes.append(1.4 if c == me.home else 1.0)
	for c in me.known:
		cells.append(c)
		colors.append(COLOR_KNOWN)
		sizes.append(1.0)
	if _reveal.button_pressed:
		for civ in state.civs:
			if civ != me and civ.alive:
				for c in civ.colonies:
					if not me.known.has(c):
						cells.append(c)
						colors.append(COLOR_HIDDEN_AI)
						sizes.append(1.0)
	var marker := BoxMesh.new()
	marker.size = Vector3.ONE * 0.4
	_markers.add_child(_instances(marker, cells, colors, sizes))

	_refresh_texts(me)


## 刷新面板和左侧叠加层里的文字。
func _refresh_texts(me: Civ) -> void:
	var alive_ai := state.civs.filter(func(c): return c.is_ai and c.alive).size()
	_status.text = "第 %d 回合　剩 %d 个 AI 文明" % [state.turn, alive_ai]
	if state.winner == "你":
		_status.text = "🏆 你胜利了！（第 %d 回合）" % state.turn
	elif state.winner == "无":
		_status.text = "所有文明都灭亡了（第 %d 回合）" % state.turn
	elif state.winner == "平局":
		_status.text = "🤝 平局：整张星图都被压平了（第 %d 回合）" % state.turn
	elif state.winner != "":
		_status.text = "💀 你失败了（第 %d 回合）" % state.turn
	_refresh_known_pick(me)
	_end.disabled = state.is_over()

	_res_values["energy"].text = "%d  +%d" % [me.energy, me.energy_per_turn(state.map)]
	_res_values["mineral"].text = "%d  +%d" % [me.mineral, me.mineral_per_turn(state.map)]
	_res_values["actions"].text = "%d / %d" % [me.actions_left, me.action_points(state.map)]
	_res_values["actions"].add_theme_color_override("font_color",
			Color(1.0, 0.5, 0.4) if me.actions_left <= 0 else Color.WHITE)

	# 行动：选中的那一项的说明和执行按钮
	var spec: Array = _action_specs()[_action]
	var specs_a := _action_specs()
	for a in _action_tiles:
		var tile := _action_tiles[a]
		var reason := _action_block(me, a)
		tile.button_pressed = a == _action
		tile.modulate.a = 1.0 if reason == "" else 0.5
		tile.tooltip_text = "%s %s\n%s%s" % [specs_a[a][0], specs_a[a][1], specs_a[a][4],
				"\n\n现在不能用：" + reason if reason != "" else ""]
	_action_name.text = "%s %s" % [spec[0], spec[1]]
	_action_desc.text = spec[4]
	var block := _action_block(me, _action)
	_go.text = "▶ 执行%s　%s" % [spec[1], _cost_text(spec[2], spec[3])]
	_go.disabled = block != ""
	_go_hint.text = block
	_go_hint.visible = block != ""

	# 建造和升级：数值不够的按钮变灰，鼠标停上去能看到原因
	var specs := _build_specs(me)
	for kind in _build_tiles:
		var tile := _build_tiles[kind]
		var b: Array = specs[kind]
		var reason := _build_block(kind, b, me)
		tile.disabled = reason != ""
		tile.modulate.a = 1.0 if reason == "" else 0.5
		(tile.get_meta("cost") as Label).text = _cost_text(b[2], b[3]) if b[2] + b[3] > 0 else "免费"
		tile.tooltip_text = "%s %s\n%s%s" % [b[0], b[1], b[4], "\n\n现在不能用：" + reason if reason != "" else ""]

	var upgrading := me.pending_upgrades.has("telescope") or me.pending_upgrades.has("probe")
	var stats := {
		"星系": "%d 个　采矿船 %d　掩体 %d" % [me.colonies.size(), me.miners.size(), me.bunkers.size()],
		"发射源的行星": "类地 %d　类木 %d%s" % [state.map.rocky.get(_selected_origin(), 0),
				state.map.gas.get(_selected_origin(), 0),
				"　有掩体" if me.bunkers.has(_selected_origin()) else ""],
		"恒星": "%d 颗　戴森球 %d / %d" % [me.star_total(state.map), me.dyson_count(), me.dyson_limit(state.map)],
		"探测": "长 %.0f 格　张角 %.0f°%s" % [me.scout_range, me.cone_angle, "　升级中" if upgrading else ""],
		"光粒": "长 %.0f 格　半径 %.1f" % [me.strike_range, me.strike_radius],
		"预警系统": "建造中" if me.pending_upgrades.has("warning") else ("已就绪" if me.has_warning else "无"),
		"已知坐标": "%d 个" % me.known.size(),
		"反物质": "%d / %d%s" % [me.antimatter, Balance.MAX_ANTIMATTER,
				"　制造中" if me.pending_upgrades.has("antimatter") else ""],
		"降维": "已降维（产能减半）" if me.reduced else (
				"进行中，还剩 %d 回合" % me.reduce_left if me.reduce_left > 0 else "无"),
		"在飞飞船": "战舰 %d　殖民船 %d　二向箔 %d" % [me.warships.size(), me.colony_ships.size(),
				me.foils.size()],
		"星舰": ("在 %s" % me.starship) if me.has_starship else ("建造中" if me.starship_building else "无"),
		"广播": "准备中 %d 个" % me.pending_broadcasts.size(),
		"广播设施": "广播器 %s　引力波 %s" % [
				_facility(me.has_broadcaster, me.pending_upgrades.has("broadcaster")),
				_facility(me.has_gravity, me.pending_upgrades.has("gravity"))],
		"黑域": "星图上 %d 个%s" % [state.black_domains.size(),
				"　你的准备中 %d 个" % me.pending_domains.size() if not me.pending_domains.is_empty() else ""],
	}
	for key in stats:
		_stat_values[key].text = stats[key]

	_log.clear()
	_log.get_parent().visible = not state.log_lines.is_empty()
	for line in state.log_lines.slice(-8):
		_log.append_text(line + "\n")


## 每种行动：[图标, 名字, 能量, 矿石, 说明]。都要花 1 个行动点。
func _action_specs() -> Dictionary:
	return {
		Action.SCOUT: ["🔭", "探测", Balance.COST_SCOUT, 0,
				"朝一个方向看，圆锥范围里的敌方星系会被发现。"],
		Action.LIGHTGRAIN: ["✨", "光粒", Balance.COST_LIGHTGRAIN, 0,
				"朝一个方向发射，打中圆柱范围里最近的敌方星系，让它少一颗恒星。\n要先建恒星广播器。"],
		Action.WARSHIP: ["🚀", "战舰", Balance.COST_WARSHIP_ENERGY, Balance.COST_WARSHIP_MINERAL,
				"沿方向每回合飞 %.0f 格，撞上敌方星系让它少一颗恒星。比光粒便宜，没有射程限制，但飞得慢。" % Balance.WARSHIP_SPEED],
		Action.COLONY: ["🌱", "殖民船", Balance.COST_COLONY_ENERGY, Balance.COST_COLONY_MINERAL,
				"沿方向飞，停在路上第一个无主的宜居星系，变成你的新星系。"],
		Action.FOIL: ["📄", "二向箔", Balance.COST_FOIL, 0,
				"指定目标坐标，准备 %d 回合后飞过去展开：那一列压成平面，周围的空间离平面远的部分被压没，中心最扁、越往外留得越多。之后每回合向外扩散一圈，不会停。" % Balance.FOIL_PREPARE_TURNS],
		Action.DOMAIN: ["🕳️", "黑域", Balance.COST_BLACK_DOMAIN, 0,
				"在探测范围内指定中心，准备 %d 回合后生成 3×3×3 的黑域。光和飞船都穿不过它的边界，二向箔不受影响。" % Balance.BLACK_DOMAIN_PREPARE_TURNS],
		Action.BROADCAST: ["📢", "广播", Balance.COST_BROADCAST, 0,
				"准备 %d 回合后把一个坐标公开给所有文明。如果那里有别人的星系，附近看不见的隐藏文明可能替你出手。\n要先建恒星广播器或引力波发射器。" % Balance.BROADCAST_PREPARE_TURNS],
		Action.STARSHIP: ["🛸", "星舰移动", Balance.COST_STARSHIP_MOVE, 0,
				"从星舰现在的位置出发，最远 %.0f 格，停在路上最远的、没有别人星系的格子。" % Balance.STARSHIP_JUMP],
	}


func _spec_cost(a: int) -> Vector2i:
	var spec: Array = _action_specs()[a]
	return Vector2i(spec[2], spec[3])


## 每种建造和升级：[图标, 名字, 能量, 矿石, 说明]。都要花 1 个行动点。
func _build_specs(me: Civ) -> Dictionary:
	return {
		"telescope": ["📡", "射电望远镜", Balance.COST_TELESCOPE, 0,
				"探测的张角 +%.0f°，下回合生效。" % Balance.TELESCOPE_STEP],
		"probe": ["🛰️", "探测器", 0, Balance.COST_PROBE,
				"探测长度 +%.0f 格，下回合生效。" % Balance.PROBE_STEP],
		"warning": ["🚨", "预警系统", Balance.COST_WARNING, 0,
				"抵消一次打击，用掉后可以再造。同一时间最多一个，下回合生效。"],
		"antimatter": ["⚛️", "反物质", Balance.COST_ANTIMATTER_ENERGY, Balance.COST_ANTIMATTER_MINERAL,
				"拦下一艘打到你的战舰，挡不住光粒。最多存 %d 个，下回合生效。" % Balance.MAX_ANTIMATTER],
		"broadcaster": ["🌟", "恒星广播器", Balance.COST_BROADCASTER, 0,
				"有了才能发光粒和广播。整个文明一个，下回合建好。"],
		"gravity": ["🌊", "引力波", Balance.COST_GRAVITY_ENERGY, Balance.COST_GRAVITY_MINERAL,
				"引力波发射器：有了才能广播（不能发光粒）。整个文明一个，下回合建好。"],
		"miner": ["⛏️", "采矿船", 0, Balance.COST_MINER,
				"建在选中的发射源上，矿石 +%d/回合。每个星系最多一艘，下回合建好。" % Balance.MINER_MINERAL],
		"dyson": ["🌞", "戴森球", 0, Balance.COST_DYSON,
				"建在选中的发射源上，能量 +%d/回合。每个星系最多建到和它的恒星数一样多。" % Balance.DYSON_ENERGY],
		"bunker": ["🛡️", "掩体", Balance.COST_BUNKER_ENERGY, Balance.COST_BUNKER_MINERAL,
				"建在选中的发射源上，那个星系要有类木行星。光粒照样打爆恒星，但人躲在类木行星背后活下来：最后一颗恒星没了，星系也不会丢。战舰照样能摧毁它。每个星系一个，下回合建好。"],
		"starship": ["🛸", "星舰", Balance.COST_STARSHIP_ENERGY, Balance.COST_STARSHIP_MINERAL,
				"建在选中的发射源上，最多一艘。星系全丢了，有星舰文明就还活着。探测发现不了、光粒打不到；战舰撞上或二向箔压平会毁掉它。"],
		"settle": ["🏠", "星舰定居", 0, 0,
				"星舰停在无主的宜居星系上时，在那里建立新的星系。"],
		"reduce": ["🔻", "自身降维", me.reduce_cost(), 0,
				"花 %d 回合进入二维，期间不能建造。之后不怕光粒，被二向箔压平也能活，但产能减半。\n每个星系、每艘在飞的飞船都要多花能量。" % Balance.REDUCE_TURNS],
	}


func _cost_text(energy: int, mineral: int) -> String:
	var parts: Array[String] = []
	if energy > 0:
		parts.append("⚡%d" % energy)
	if mineral > 0:
		parts.append("🪨%d" % mineral)
	return " ".join(parts)


## 行动点、能量、矿石够不够。够就返回空字符串。
func _cost_block(cost: Vector2i, me: Civ) -> String:
	if state.is_over():
		return "对局已结束"
	if me.actions_left <= 0:
		return "行动点用完了，结束回合后恢复"
	if me.energy < cost.x:
		return "能量不够（还差 %d）" % (cost.x - me.energy)
	if me.mineral < cost.y:
		return "矿石不够（还差 %d）" % (cost.y - me.mineral)
	return ""


## 行动 a 现在为什么不能执行。只做简单的检查，其余的由规则在执行时报错。
func _action_block(me: Civ, a: int) -> String:
	var r := _cost_block(_spec_cost(a), me)
	if r != "":
		return r
	match a:
		Action.LIGHTGRAIN:
			if not me.has_broadcaster:
				return "要先建恒星广播器（在下面「建造和升级」里）"
		Action.BROADCAST:
			if not me.has_broadcaster and not me.has_gravity:
				return "要先建恒星广播器或引力波发射器"
		Action.STARSHIP:
			if not me.has_starship:
				return "还没有星舰（在下面「建造和升级」里建）"
		Action.FOIL:
			if a == _action and state.flattened.has(_target_cell()):
				return "目标所在的这一列已经压平了，换一个目标"
	return ""


func _build_block(kind: String, b: Array, me: Civ) -> String:
	var r := _cost_block(Vector2i(b[2], b[3]), me)
	if r != "":
		return r
	if me.reduce_left > 0:
		return "降维期间不能建造"
	if me.pending_upgrades.has(kind):
		return "已在建造中"
	match kind:
		"warning":
			if me.has_warning:
				return "已经有了"
		"antimatter":
			if me.antimatter >= Balance.MAX_ANTIMATTER:
				return "已经存满"
		"broadcaster":
			if me.has_broadcaster:
				return "已经有了"
		"gravity":
			if me.has_gravity:
				return "已经有了"
		"starship":
			if me.has_starship or me.starship_building:
				return "已经有了" if me.has_starship else "已在建造中"
		"settle":
			if not me.has_starship:
				return "还没有星舰"
		"bunker":
			if state.map.gas.get(_selected_origin(), 0) == 0:
				return "发射源所在的星系没有类木行星"
			if me.bunkers.has(_selected_origin()) or me.pending_bunkers.has(_selected_origin()):
				return "发射源已经有掩体"
		"reduce":
			if me.reduced:
				return "已经降维"
	return ""


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_build_overlay(layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	# 最上面是资源，最下面是「结束回合」，都固定不动；中间的内容可以上下滚动
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	outer.add_child(_resource_bar())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# 右边留出滚动条的位置，免得盖住内容
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 12)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)

	# 发射源：行动从这里出发，建造也建在这里
	var origin_row := HBoxContainer.new()
	origin_row.add_child(_dim_label("📍 发射源"))
	origin_row.tooltip_text = "行动从这里出发；采矿船、戴森球、星舰也建在这里。"
	_origin_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_pick.item_selected.connect(func(_i): refresh())
	origin_row.add_child(_origin_pick)
	box.add_child(origin_row)

	box.add_child(_title("行动　每次 1 行动点"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	var group := ButtonGroup.new()
	var specs := _action_specs()
	for a in specs:
		var spec: Array = specs[a]
		var tile := _tile(spec[0], spec[1], _cost_text(spec[2], spec[3]))
		tile.toggle_mode = true
		tile.button_group = group
		tile.pressed.connect(func(): _action = a; _feedback.text = ""; refresh())
		grid.add_child(tile)
		_action_tiles[a] = tile

	# 选中行动的详情卡片：说明、方向或目标、执行
	var card := PanelContainer.new()
	var card_bg := StyleBoxFlat.new()
	card_bg.bg_color = Color(1, 1, 1, 0.04)
	card_bg.set_corner_radius_all(6)
	card_bg.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", card_bg)
	box.add_child(card)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	card.add_child(detail)
	_action_name.add_theme_font_size_override("font_size", 18)
	detail.add_child(_action_name)
	_action_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	_action_desc.add_theme_font_size_override("font_size", 13)
	detail.add_child(_action_desc)
	detail.add_child(_dir_box)
	_aim_hint = _hint_label("")
	_dir_box.add_child(_aim_hint)
	var dials := HBoxContainer.new()
	dials.alignment = BoxContainer.ALIGNMENT_CENTER
	dials.add_theme_constant_override("separation", 24)
	_yaw.marks = {0: "x", 90: "y", 180: "-x", 270: "-y"}
	_pitch.half = true
	_pitch.marks = {90: "上", 0: "平", -90: "下"}
	dials.add_child(_dial_box(_yaw, "↻ 水平角", "在同一高度的平面里转：0° 朝 x 轴，90° 朝 y 轴"))
	dials.add_child(_dial_box(_pitch, "⇅ 俯仰角", "往上或往下抬：0° 是水平，90° 朝正上方，-90° 朝正下方"))
	_dir_box.add_child(dials)
	detail.add_child(_target_box)
	_target_label.add_theme_font_size_override("font_size", 13)
	_target_box.add_child(_target_label)
	var dist_row := HBoxContainer.new()
	dist_row.add_child(_dim_label("↔ 距离"))
	_dist.min_value = 0
	_dist.max_value = ceilf(sqrt(3.0) * (StarMap.SIZE - 1))
	_dist.step = 0.1
	_dist.value = 5
	_dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dist.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dist.value_changed.connect(func(_v): refresh())
	dist_row.add_child(_dist)
	_dist_label.custom_minimum_size.x = 56
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dist_row.add_child(_dist_label)
	_target_box.add_child(dist_row)
	_target_box.add_child(_target_info)
	_known_pick.item_selected.connect(_on_known_picked)
	_target_box.add_child(_known_pick)
	_go.custom_minimum_size.y = 36
	_go.pressed.connect(_on_go)
	detail.add_child(_go)
	_go_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_go_hint.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	_go_hint.add_theme_font_size_override("font_size", 13)
	detail.add_child(_go_hint)

	box.add_child(_title("建造和升级　每次 1 行动点，下回合生效"))
	var builds := GridContainer.new()
	builds.columns = 4
	builds.add_theme_constant_override("h_separation", 4)
	builds.add_theme_constant_override("v_separation", 4)
	box.add_child(builds)
	var b_specs := _build_specs(state.human())
	for kind in b_specs:
		var b: Array = b_specs[kind]
		var tile := _tile(b[0], b[1], _cost_text(b[2], b[3]))
		tile.pressed.connect(_on_build.bind(kind))
		builds.add_child(tile)
		_build_tiles[kind] = tile

	# 详细数值，可以收起来
	var stats := _stat_grid(["星系", "发射源的行星", "恒星", "探测", "光粒", "预警系统", "反物质", "降维", "星舰", "黑域",
			"广播", "广播设施", "已知坐标", "在飞飞船"])
	box.add_child(_fold_title("📊 详细情况", stats))
	box.add_child(stats)

	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	outer.add_child(_feedback)
	_end.text = "⏭️ 结束回合"
	_end.add_theme_font_size_override("font_size", 18)
	_end.custom_minimum_size.y = 46
	_end.pressed.connect(func(): _feedback.text = ""; state.end_turn(); refresh())
	outer.add_child(_end)


## 面板最上面的一排资源：能量、矿石、行动点。
func _resource_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for spec in [
		["energy", "⚡", "能量：现有  +每回合收入"],
		["mineral", "🪨", "矿石：现有  +每回合收入"],
		["actions", "🎯", "行动点：本回合还剩 / 每回合共有。恒星越多，行动点越少（乱纪元）。"],
	]:
		var chip := PanelContainer.new()
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.06)
		bg.set_corner_radius_all(6)
		bg.content_margin_left = 8
		bg.content_margin_right = 8
		bg.content_margin_top = 4
		bg.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", bg)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.tooltip_text = spec[2]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)
		var icon := Label.new()
		icon.text = spec[1]
		icon.add_theme_font_size_override("font_size", 18)
		row.add_child(icon)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", 18)
		row.add_child(value)
		_res_values[spec[0]] = value
		bar.add_child(chip)
	return bar


## 一个方块按钮：上面一个大图标，下面是名字和花费。
func _tile(icon: String, name: String, cost: String) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0, 78)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	for spec in [[icon, 24, Color.WHITE], [name, 13, Color.WHITE], [cost, 12, Color(0.75, 0.75, 0.8)]]:
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[1] == 24:
			# 彩色图标比文字高，往下放，上面留出空间，免得被切掉
			l.custom_minimum_size.y = 36
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		col.add_child(l)
		if spec[1] == 12:
			tile.set_meta("cost", l)
	# 选中的行动：蓝色边框
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.2, 0.35, 0.6, 0.6)
	pressed.border_color = Color(0.5, 0.75, 1.0)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)
	tile.add_theme_stylebox_override("pressed", pressed)
	tile.add_theme_stylebox_override("hover_pressed", pressed)
	return tile


## 可以点击展开或收起的小标题，控制 target 显示不显示。
func _fold_title(text: String, target: Control) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	var update := func(): b.text = ("▾ " if target.visible else "▸ ") + text
	update.call()
	b.pressed.connect(func(): target.visible = not target.visible; update.call())
	return b


## 星图左侧的叠加层：回合状态、图例、调试开关（左上），日志（左下）。
func _build_overlay(layer: CanvasLayer) -> void:
	var top := VBoxContainer.new()
	top.position = Vector2(16, 12)
	layer.add_child(top)
	_status.add_theme_font_size_override("font_size", 22)
	top.add_child(_status)
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	_legend.add_theme_font_size_override("normal_font_size", 13)
	var fold := _fold_title("🗺️ 图例", _legend)
	fold.add_theme_font_size_override("font_size", 13)
	top.add_child(fold)
	top.add_child(_legend)
	if OS.is_debug_build():
		_reveal.text = "调试：显示所有文明和星系"
		_reveal.add_theme_font_size_override("font_size", 13)
		_reveal.toggled.connect(func(_on): refresh())
		top.add_child(_reveal)

	var log_panel := PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 16
	log_panel.offset_right = 16 + 420
	log_panel.offset_top = -150
	log_panel.offset_bottom = -16
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_content_margin_all(10)
	bg.set_corner_radius_all(6)
	log_panel.add_theme_stylebox_override("panel", bg)
	layer.add_child(log_panel)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	log_panel.add_child(_log)


func _on_go() -> void:
	var me := state.human()
	var r: Dictionary
	if _action == Action.LIGHTGRAIN:
		r = state.lightgrain(me, _direction(), _selected_origin())
	elif _action == Action.WARSHIP:
		r = state.launch_warship(me, _direction(), _selected_origin())
	elif _action == Action.COLONY:
		r = state.launch_colony_ship(me, _direction(), _selected_origin())
	elif _action == Action.FOIL:
		r = state.launch_foil(me, _target_cell(), _selected_origin())
	elif _action == Action.DOMAIN:
		r = state.launch_black_domain(me, _target_cell(), _selected_origin())
	elif _action == Action.BROADCAST:
		r = state.broadcast(me, _target_cell())
	elif _action == Action.STARSHIP:
		r = state.move_starship(me, _direction())
	else:
		r = state.scout(me, _direction(), _selected_origin())
	_feedback.text = "无法执行：" + r["error"] if r["error"] != "" else ""
	refresh()


## 设施状态：有、建造中、无。
func _facility(has: bool, building: bool) -> String:
	if has:
		return "有"
	return "建造中" if building else "无"


func _on_build(kind: String) -> void:
	var me := state.human()
	var r: Dictionary
	match kind:
		"starship": r = state.build_starship(me, _selected_origin())
		"settle": r = state.settle_starship(me)
		"miner": r = state.build_miner(me, _selected_origin())
		"dyson": r = state.build_dyson(me, _selected_origin())
		"bunker": r = state.build_bunker(me, _selected_origin())
		"reduce": r = state.start_reduce(me)
		_: r = state.upgrade(me, kind)
	var name: String = _build_specs(me)[kind][1]
	_feedback.text = "无法执行「%s」：%s" % [name, r["error"]] if r["error"] != "" else ""
	refresh()

## 已知坐标列表：选一个就把它填进目标坐标。
func _refresh_known_pick(me: Civ) -> void:
	_known_pick.clear()
	_known_pick.add_item("从已知坐标里选…")
	for c in me.known:
		_known_pick.add_item(str(c))
		_known_pick.set_item_metadata(_known_pick.item_count - 1, c)
	_known_pick.select(0)


func _on_known_picked(i: int) -> void:
	var c = _known_pick.get_item_metadata(i)
	if c is Vector3i:
		_aim_at(c)
	else:
		refresh()


## 两个角度加距离算出来的目标格子（从发射源算起，四舍五入到最近的格子；可能在星图外面）。
func _target_cell() -> Vector3i:
	return Vector3i((Vector3(_aim_origin()) + _direction() * _dist.value).round())


## 星系会增减（殖民、被打掉），每次刷新时重建发射源列表，尽量保持原来的选择。
func _refresh_origins() -> void:
	var me := state.human()
	var previous := _origin_pick.get_item_text(_origin_pick.selected) if _origin_pick.selected >= 0 else ""
	_origin_pick.clear()
	for c in me.colonies:
		_origin_pick.add_item("%s %s" % ["母星" if c == me.home else "殖民地", c])
	if me.has_starship:
		_origin_pick.add_item("星舰 %s" % me.starship)
	for i in _origin_pick.item_count:
		if _origin_pick.get_item_text(i) == previous:
			_origin_pick.select(i)


func _selected_origin() -> Vector3i:
	var me := state.human()
	var origins := me.origins()
	if origins.is_empty():
		return me.home
	return origins[clampi(_origin_pick.selected, 0, origins.size() - 1)]


## 两个角度换算成方向（长度为 1）。
func _direction() -> Vector3:
	var yaw := deg_to_rad(_yaw.value)
	var pitch := deg_to_rad(_pitch.value)
	return Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch))


## 角度圆盘加上面的名字，鼠标停在上面时显示说明。
func _dial_box(dial: Control, title: String, tip: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.tooltip_text = tip
	var name_label := _dim_label(title)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	dial.tooltip_text = tip
	dial.value_changed.connect(func(_v: float) -> void: refresh())
	box.add_child(dial)
	return box


# ---------- 绘图小工具 ----------

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	return l



## 会自动换行的浅色小字提示。
func _hint_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	l.add_theme_font_size_override("font_size", 13)
	return l


## 灰色的小字，用作表单左边的说明。
func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	return l


## 两列表格：左边名字，右边数值（右对齐）。数值标签记进 _stat_values，刷新时改文字。
func _stat_grid(keys: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for key in keys:
		grid.add_child(_dim_label(key))
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		_stat_values[key] = value
	return grid


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## 用一个 MultiMesh 一次画出很多同形状、不同颜色和大小的物体。
func _instances(mesh: Mesh, cells: Array[Vector3i], colors: Array[Color],
		sizes: Array[float]) -> MultiMeshInstance3D:
	var mat := _flat_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var basis := Basis().scaled(Vector3.ONE * sizes[i])
		mm.set_instance_transform(i, Transform3D(basis, _warp_point(Vector3(cells[i]))))
		mm.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	return node


## 画一艘在飞的飞船：位置画一个小锥体，朝向飞行方向；再画出下一回合要飞的一段。
func _draw_ship(ship: Ship, color: Color, speed: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.18
	cone.height = 0.45
	var node := MeshInstance3D.new()
	node.mesh = cone
	node.material_override = _flat_material(color)
	node.position = _warp_point(ship.position())
	# 圆柱网格默认沿 y 轴，转到飞行方向
	var up := Vector3.UP if absf(ship.direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	node.basis = Basis.looking_at(ship.direction, up) * Basis(Vector3.RIGHT, -PI / 2)
	_markers.add_child(node)
	_markers.add_child(_segment(ship.position(), ship.position() + ship.direction * speed, color))


## 广播的坐标：一个粉色线框方块。
func _broadcast_mark(c: Vector3i, alpha: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.7
	node.mesh = mesh
	node.material_override = _flat_material(Color(COLOR_BROADCAST, 0.35 * alpha))
	node.position = _warp_point(Vector3(c))
	return node


## 以 center 为中心的黑域立方体：半透明的方块加一圈边框。
func _domain_box(center: Vector3i, color: Color) -> Node3D:
	var size := Vector3.ONE * (Balance.BLACK_DOMAIN_RADIUS * 2 + 1)
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


## 图例。派殖民船时多显示宜居星系的说明。
func _legend_text(colony_view: bool) -> String:
	var hex := func(c: Color) -> String: return c.to_html(false)
	var lines: Array[String] = []
	if colony_view:
		lines.append("视图：殖民（显示宜居星系）")
		lines.append("[color=#%s]●[/color] 单星　[color=#%s]●[/color] 双星　[color=#%s]●[/color] 三星　[color=#%s]○[/color] 可以去殖民" % [
			hex.call(STAR_COLORS[StarMap.Star.SINGLE]), hex.call(STAR_COLORS[StarMap.Star.DOUBLE]),
			hex.call(STAR_COLORS[StarMap.Star.TRIPLE]), hex.call(COLOR_COLONY_SHIP)])
	else:
		lines.append("视图：探测和打击（只显示网格）")
	lines.append("[color=#%s]■[/color] 你的星系（大的是母星）　[color=#%s]■[/color] 已发现的敌人" % [
		hex.call(COLOR_MINE), hex.call(COLOR_KNOWN)])
	lines.append("[color=#%s]▲[/color] 你的战舰　[color=#%s]▲[/color] 你的殖民船　[color=#%s]◆[/color] 你的星舰" % [
		hex.call(COLOR_SHIP), hex.call(COLOR_COLONY_SHIP), hex.call(COLOR_STARSHIP)])
	lines.append("[color=#%s]○[/color] 打中过　[color=#%s]○[/color] 打击经过的空格子" % [
		hex.call(COLOR_RECORD_HIT), hex.call(COLOR_RECORD_EMPTY)])
	lines.append("[color=#%s]▬[/color] 你的二向箔　[color=#%s]▬[/color] 被压平的区域　[color=#%s]○[/color] 戴森球　[color=#%s]■[/color] 采矿船" % [
		hex.call(COLOR_FOIL), hex.call(COLOR_FLAT), hex.call(COLOR_DYSON), hex.call(COLOR_MINER)])
	lines.append("[color=#%s]■[/color] 黑域（光和飞船过不去）　[color=#%s]■[/color] 你准备中的广播" % [
		hex.call(COLOR_DOMAIN_EDGE), hex.call(COLOR_BROADCAST)])
	lines.append("坐标轴：[color=#%s]x[/color]　[color=#%s]y[/color]　[color=#%s]z（向上）[/color]，右手系，每格一个整数" % [
		hex.call(AXIS_COLORS[0]), hex.call(AXIS_COLORS[1]), hex.call(AXIS_COLORS[2])])
	lines.append("[color=#%s]■[/color] 掩体（恒星没了星系也不丢）　半透明的曲面：还活着的空间的边界，外面的格子已被压没" % hex.call(COLOR_BUNKER))
	lines.append("左键拖动旋转，滚轮缩放，单击格子选方向或目标")
	return "\n".join(lines)


## 玩家眼里可以去殖民的星系：宜居、还有恒星、不是自己的、也不是已知的敌人。
## 只用玩家知道的信息，别人悄悄占了的星系也会画出来。
## 画成小球（颜色表示几颗恒星）外加绿圈。
func _settle_candidates(me: Civ) -> Node3D:
	var cells: Array[Vector3i] = []
	for c in state.map.habitable:
		if state.map.star_at(c) != StarMap.Star.NONE and not me.owns(c) and not me.known.has(c):
			cells.append(c)
	var group := Node3D.new()
	group.add_child(_star_spheres(cells, 1.6))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.2
	ring.outer_radius = 0.26
	group.add_child(_instances(ring, cells, _fill(cells.size(), COLOR_COLONY_SHIP), _fill_f(cells.size(), 1.0)))
	return group


## 从发射源沿方向画一条线，长度等于行动能到达的距离。
func _arrow(origin: Vector3i, direction: Vector3, length: float, color: Color) -> MeshInstance3D:
	if direction.length() < 1e-6:
		return MeshInstance3D.new()
	return _segment(Vector3(origin), Vector3(origin) + direction.normalized() * length, color)


## 从 origin 沿方向走多远会离开星图。
func _length_inside(origin: Vector3i, direction: Vector3) -> float:
	if direction.length() < 1e-6:
		return 0.0
	var ship := Ship.new(origin, direction)
	while not ship.is_outside():
		ship.traveled += 0.1
	return ship.traveled


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
