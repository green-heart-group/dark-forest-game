extends VBoxContainer
## 面板的「行动」页：选一个行动，给方向或目标，执行。
## 能不能执行、要花多少，都问规则（GameState 的 xxx_error、action_cost），这里只管显示和收集输入。

const Widgets := preload("res://view/widgets.gd")
const MapView := preload("res://view/map_view.gd")
const AngleDial := preload("res://view/angle_dial.gd")

## 行动页里的行动。DISPATCH 是派出停着的单位，或让在飞的战舰、吞噬者转向。
enum Action { DISPATCH, COLONY, STARSHIP, SETTLE, GRAIN, ANTIMATTER, SOPHON, BROADCAST, FOIL, LINE_FOIL, DOMAIN, SINGULARITY, SCAN, LANDING }
## 行动要玩家给什么：不用给、一个方向、一个目标格子
enum Aim { NONE, DIRECTION, TARGET }
## 每个行动对应的规则函数名（GameState.action_cost 用这个名字查价格）
const RULE_NAMES := {
	Action.DISPATCH: "dispatch", Action.COLONY: "send_colony", Action.STARSHIP: "move_starship",
	Action.SETTLE: "settle_starship", Action.GRAIN: "launch_grain", Action.ANTIMATTER: "use_antimatter",
	Action.SOPHON: "send_sophon",
	Action.BROADCAST: "broadcast", Action.FOIL: "launch_foil", Action.LINE_FOIL: "launch_line_foil",
	Action.DOMAIN: "launch_black_domain", Action.SINGULARITY: "launch_singularity",
	Action.SCAN:"active_scan",Action.LANDING:"start_landing",
}

var main: Node
var state: GameState:
	get: return main.state

## 现在选中的行动（Action 里的一个）
var _action := Action.DISPATCH
var _action_tiles: Dictionary[int, Button] = {}
## 选哪个单位（派出、转向、殖民、智子用）
var _unit_box := HBoxContainer.new()
var _unit_pick := OptionButton.new()
## 刷新单位下拉菜单时要选中的单位（刚造好的），没有时为 -1
var _want_unit := -1
## 探测器先慢速飞出视野（不被自己附近的人看到航迹）
var _slow := CheckBox.new()
## 方向输入
var _dir_box := VBoxContainer.new()
## 方向和目标共用的提示（文字按行动不同）
var _aim_hint: Label
## 方向用两个角度表示，各用一个圆盘调：水平角（在等高平面里转，0° 朝 x 轴，90° 朝 y 轴）
## 和俯仰角（半圆，往上为正）
var _yaw := AngleDial.new()
var _pitch := AngleDial.new()
## 直接输入坐标：x、y、z 三个数字框，改了数字就指向那个格子；点星图时也填上点到的格子
var _coord_boxes: Array[SpinBox] = []
## 目标坐标输入
var _target_box := VBoxContainer.new()
## 距离那一行；悬停说明写这段距离指什么
var _dist_row: HBoxContainer
## 俯仰角那一格（星图进入二维以后藏起来）
var _pitch_box: Control
## 水平角那一格（一维时换成下面两个按钮）
var _yaw_box: Control
## 一维时选方向的两个按钮：朝 -x、朝 +x
var _line_dirs := HBoxContainer.new()
var _line_left := Button.new()
var _line_right := Button.new()
## 目标位置用极坐标表示：方向用上面的两个角度圆盘，再加离发射源的距离
var _dist := HSlider.new()
var _dist_label := Label.new()
## 算出来的目标格子（写在距离后面）
var _target_info := Button.new()
var _known_pick := OptionButton.new()
var _go := Button.new()
## 执行按钮下面的小字：为什么现在不能执行
var _go_hint := Label.new()


func setup(p_main: Node) -> void:
	main = p_main
	add_theme_constant_override("separation", 4)
	var grid := Widgets.tile_grid(4)
	add_child(grid)
	var group := ButtonGroup.new()
	var specs := _action_specs()
	for a in specs:
		var spec: Array = specs[a]
		var tile := Widgets.tile(spec[0], spec[1], "")
		tile.toggle_mode = true
		tile.button_group = group
		tile.pressed.connect(func(): _action = a; main.panel.set_feedback(""); main.refresh())
		grid.add_child(tile)
		_action_tiles[a] = tile

	# 选中行动的详情卡片：单位、方向或目标、执行
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Widgets.card_style(0.04, 8))
	add_child(card)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 4)
	card.add_child(detail)
	_unit_box.add_child(Widgets.dim_label("单位"))
	_unit_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_pick.clip_text = true
	_unit_pick.item_selected.connect(func(_i): main.refresh())
	_unit_box.add_child(_unit_pick)
	detail.add_child(_unit_box)
	_slow.text = "先慢速飞出自己的视野"
	_slow.add_theme_font_size_override("font_size", 13)
	detail.add_child(_slow)
	detail.add_child(_dir_box)
	_aim_hint = Widgets.hint_label("")
	_aim_hint.mouse_filter = Control.MOUSE_FILTER_PASS
	_dir_box.add_child(_aim_hint)
	# 两个角度圆盘，右边一列输入坐标（放一行省高度，面板不用滚动）
	var dials := HBoxContainer.new()
	dials.add_theme_constant_override("separation", 12)
	_yaw.marks = {0: "x", 90: "y", 180: "-x", 270: "-y"}
	_pitch.half = true
	_pitch.marks = {90: "上", 0: "平", -90: "下"}
	var how := "\n拖圆钮调，滚轮每格 1°。"
	_yaw_box = _dial_box(_yaw, "↻ 水平角", "0° 朝 x 轴，90° 朝 y 轴。" + how)
	dials.add_child(_yaw_box)
	_line_dirs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line_dirs.add_theme_constant_override("separation", 6)
	var line_group := ButtonGroup.new()
	for pair in [[_line_left, "◀ -x", 180.0], [_line_right, "+x ▶", 0.0]]:
		var b: Button = pair[0]
		b.text = pair[1]
		b.toggle_mode = true
		b.button_group = line_group
		b.custom_minimum_size = Vector2(64, 36)
		b.tooltip_text = "一维里只能沿直线走：朝 x 变小的一边，或 x 变大的一边。"
		var yaw: float = pair[2]
		b.pressed.connect(func(): _yaw.value = yaw; main.refresh())
		_line_dirs.add_child(b)
	dials.add_child(_line_dirs)
	_pitch_box = _dial_box(_pitch, "⇅ 俯仰角", "0° 水平，90° 朝上，-90° 朝下。" + how)
	dials.add_child(_pitch_box)
	dials.add_child(_coord_column())
	_dir_box.add_child(dials)
	detail.add_child(_target_box)
	# 距离一行：滑块、距离、算出来的目标格子；这一段距离指什么写在悬停说明里
	var dist_row := HBoxContainer.new()
	dist_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_dist_row = dist_row
	dist_row.add_child(Widgets.dim_label("↔ 距离"))
	_dist.min_value = 0
	_dist.step = 0.1
	_dist.value = 5
	_dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dist.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dist.value_changed.connect(func(_v): main.refresh())
	dist_row.add_child(_dist)
	_dist_label.custom_minimum_size.x = 56
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dist_row.add_child(_dist_label)
	_target_info.custom_minimum_size.x = 92
	_target_info.flat=true
	_target_info.pressed.connect(func():main.migration_preview.open_preview())
	_target_info.tooltip_text="查看当前/下一维的物理距离、预计航时、射程与已知威胁。"
	_target_info.add_theme_font_size_override("font_size", 13)
	_target_info.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dist_row.add_child(_target_info)
	_target_box.add_child(dist_row)
	_go.custom_minimum_size.y = 36
	_go.pressed.connect(_on_go)
	detail.add_child(_go)
	_go_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_go_hint.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	_go_hint.add_theme_font_size_override("font_size", 13)
	detail.add_child(_go_hint)


## 输入坐标的一列（放在角度圆盘右边）：在星图上点不准时用。
func _coord_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	for i in 3:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = StarMap.SIZE - 1
		spin.prefix = ["x", "y", "z"][i]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.get_line_edit().add_theme_color_override("font_color", MapView.AXIS_COLORS[i])
		col.add_child(spin)
		spin.tooltip_text = "输入格子的坐标，方向（和距离）就指向那一格"
		spin.value_changed.connect(func(_v): aim_at(Vector3i(int(_coord_boxes[0].value), int(_coord_boxes[1].value),
				int(_coord_boxes[2].value))))
		_coord_boxes.append(spin)
	# 目标行动才显示：从已知的敌方星系里挑一个当目标
	_known_pick.clip_text = true
	_known_pick.tooltip_text = "从已知的敌方星系里选一个当目标"
	_known_pick.item_selected.connect(_on_known_picked)
	col.add_child(_known_pick)
	return col


## 角度圆盘加上面的名字，鼠标停在上面时显示说明。
func _dial_box(dial: Control, title: String, tip: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.tooltip_text = tip
	var name_label := Widgets.dim_label(title)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	dial.tooltip_text = tip
	dial.value_changed.connect(func(_v: float) -> void: main.refresh())
	box.add_child(dial)
	return box


# ---------- 刷新 ----------

## 换了局面：不再等着选中刚造好的单位。
func reset() -> void:
	_want_unit = -1


## 刚造好一个单位：切到能用它的行动，下次刷新时在单位菜单里选中它，方便马上派出。
func select_unit(ship: Ship) -> void:
	_action = {Ship.COLONY: Action.COLONY, Ship.STARSHIP: Action.STARSHIP, Ship.SOPHON: Action.SOPHON}.get(
			ship.kind, Action.DISPATCH)
	_want_unit = ship.id


## 按现在的局面刷新整页：哪些行动能用、单位菜单、方向和目标输入、执行按钮。
func refresh(me: Civ) -> void:
	_dist.max_value = ceilf(Vector3(state.map.extent - Vector3i.ONE).length())
	for i in _coord_boxes.size():
		var spin := _coord_boxes[i]
		spin.set_block_signals(true)
		spin.min_value = state.map.origin[i]
		spin.max_value = state.map.origin[i] + state.map.extent[i] - 1
		spin.editable = state.map.extent[i] > 1
		spin.set_block_signals(false)
	if state.all_flat() and _action == Action.FOIL:
		_action = Action.LINE_FOIL
	elif not state.all_flat() and _action == Action.LINE_FOIL:
		_action = Action.FOIL
	_action_tiles[Action.FOIL].visible = not state.all_flat()
	_action_tiles[Action.LINE_FOIL].visible = state.all_flat()
	_pitch_box.visible = not state.all_flat()
	_yaw_box.visible = not state.all_linear()
	_line_dirs.visible = state.all_linear()
	# 一维里 y、z 不会变，不用输入
	_coord_boxes[1].visible = not state.all_linear()
	_coord_boxes[2].visible = not state.all_linear()
	if state.all_linear():
		var right := _direction().x >= 0.0
		_line_right.set_pressed_no_signal(right)
		_line_left.set_pressed_no_signal(not right)
	_refresh_units(me)
	_refresh_aim_inputs()
	_refresh_known_pick(me)

	var specs := _action_specs()
	for a in _action_tiles:
		var tile := _action_tiles[a]
		var reason := _block(me, a)
		tile.button_pressed = a == _action
		tile.modulate.a = 1.0 if reason == "" else 0.5
		Widgets.set_tile_cost(tile, _price_text(me,a))
		tile.tooltip_text = "%s %s（1 行动点）\n%s%s" % [specs[a][0], specs[a][1], specs[a][2],
				"\n\n现在不能用：" + reason if reason != "" else ""]
	var spec: Array = specs[_action]
	# 行动的名字写在选中的方块和执行按钮上，说明不占面板，放在它们的悬停说明里
	_go.tooltip_text = spec[2]
	var block := _block(me, _action)
	var verb: String = spec[1]
	var unit := _selected_unit()
	if unit != null:
		var speed := Widgets.ship_speed_tip(unit.kind)
		if speed != "":
			_go.tooltip_text += "\n"+speed
	if _action == Action.DISPATCH and unit != null:
		verb = ("派出" if unit.docked else "转向") + unit.label()
	_go.text = "▶ %s　%s" % [verb, _price_text(me,_action)]
	var locked: String = main.locked_reason()
	if locked != "":
		block = locked
	_go.disabled = block != ""
	_go_hint.text = block
	_go_hint.visible = block != ""


## 方向和目标输入：按选中的行动显示需要的部分，更新提示文字。
func _refresh_aim_inputs() -> void:
	var aim: int = _action_specs()[_action][3]
	_dir_box.visible = aim != Aim.NONE
	_target_box.visible = aim == Aim.TARGET
	_known_pick.visible = aim == Aim.TARGET
	_unit_box.visible = _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON, Action.LANDING]
	var s := _selected_unit()
	_slow.visible = _action == Action.DISPATCH and s != null and s.kind in [Ship.PROBE,Ship.NUCLEAR_PROBE] and s.docked
	var from := "选中的单位" if _unit_box.visible else ("星舰" if _action == Action.STARSHIP else "发射源")
	# 只留一行，细节（角度加距离、圆钮怎么调）在提示和圆盘的悬停说明里
	if aim == Aim.TARGET:
		_aim_hint.text = "👆 点星图上的格子当目标（从%s算起）" % from
		_aim_hint.tooltip_text = "点星图上的格子选目标。也可以调角度和距离，或输入坐标。"
	else:
		_aim_hint.text = "👆 点星图上的格子定方向（从%s算起）" % from
		_aim_hint.tooltip_text = "点星图上的格子定方向。也可以调角度，或输入坐标。"
	if state.all_flat():
		_aim_hint.text += "\n一维空间：只能沿直线往左（-x）或往右（+x）。" if state.all_linear() else "\n二维空间：只有水平角。"
	match _action:
		Action.FOIL:
			_dist_row.tooltip_text = "离发射源多远（以目标格子为中心压平）"
		Action.LINE_FOIL:
			_dist_row.tooltip_text = "离发射源多远（在平面上向四周扩散，最终展开为 %d 格直线）" % DimensionSpace.COUNT
		Action.DOMAIN:
			_dist_row.tooltip_text = "离发射源多远（黑域的中心）"
		Action.BROADCAST:
			_dist_row.tooltip_text = "离发射源多远（要公开的坐标，星图内任意格子）"
		Action.COLONY:
			_dist_row.tooltip_text = "离殖民船多远（绿圈：看到过的宜居星系）"
		Action.SOPHON:
			_dist_row.tooltip_text = "离智子多远（目的地：别人的母星系）"
		_:
			_dist_row.tooltip_text = "离星舰多远（目的地）"
	_dist_label.text = "%.1f 格" % _dist.value
	var goal := _target_cell()
	if state.map.contains(goal):
		for i in _coord_boxes.size():
			_coord_boxes[i].set_value_no_signal(goal[i])
		_target_info.text = "→ (%d, %d, %d)" % [goal.x, goal.y, goal.z]
		_target_info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	else:
		_target_info.text = "→ 星图外"
		_target_info.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_dist_row.tooltip_text += "\n目标格子：(%d, %d, %d)%s" % [goal.x, goal.y, goal.z,
			"" if state.map.contains(goal) else "，在星图外面"]


## 给星图画预览用的瞄准：{"kind": 预览画成什么, "from": 起点, "direction": 方向, "target": 目标格子,
## "unit": 选中的单位}。kind 是 "dispatch"、"grain"、"colony"（殖民船和星舰的目的地）、"sophon"、"broadcast"、
## "domain"、"foil"、"line_foil"，或者空（不用画预览）。
func preview() -> Dictionary:
	var kinds := {Action.DISPATCH: "dispatch", Action.GRAIN: "grain", Action.COLONY: "colony",
			Action.STARSHIP: "colony", Action.SOPHON: "sophon", Action.BROADCAST: "broadcast", Action.DOMAIN: "domain",
			Action.FOIL: "foil", Action.LINE_FOIL: "line_foil"}
	return {"kind": kinds.get(_action, ""), "from": _aim_point(), "direction": _direction(),
			"target": _target_cell(), "unit": _selected_unit()}


# ---------- 能不能执行、花多少 ----------

## 每种行动：[图标, 名字, 说明, 要什么输入]。都要花 1 个行动点。
func _action_specs() -> Dictionary:
	return {
		Action.DISPATCH:["🚀","派出 / 转向","命令按光速传到舰船。基础费用4E；聚变能、反物质收集科技可减费，真空能提取后免费；探测器与运输船免费。",Aim.DIRECTION],
		Action.COLONY:["🌱","运输船航行","选择目的地，运输船抵达后停下；建立殖民地还需研究「星际殖民」并支付建设费。",Aim.TARGET],
		Action.STARSHIP:["🛸","星舰移动","让星舰前往指定坐标；命令按光速传到星舰，到达目的地后停下。",Aim.TARGET],
		Action.SETTLE:["🏠","星舰定居","星舰本身就是移动家园。要建立星系殖民地，请使用运输船并研究「星际殖民」。",Aim.NONE],
		Action.GRAIN:["✨","光粒","以背景光速的99%飞行，打中航线上第一个有人居住的恒星星系。",Aim.DIRECTION],
		Action.ANTIMATTER:["⚛️","反物质","消耗一枚炸弹和1行动点；以光速飞向目标，命中造成4点物理伤害。",Aim.NONE],
		Action.SOPHON:["👁️","智子","前往目标侦察；情报须按光速传回。",Aim.TARGET],
		Action.BROADCAST:["📢","广播","5E广播坐标；命令先到发射器，广播再以当地光速传播。",Aim.TARGET],
		Action.FOIL:["📄","二向箔","消耗一枚降维武器，以背景光速的25%飞行；抵达1年后启动，降维波以背景光速的一半扩散。",Aim.TARGET],
		Action.LINE_FOIL:["━","单向著","在二维空间发射，将空间降为一维。星系、设施和舰船需要分别准备进入一维。",Aim.TARGET],
		Action.DOMAIN:["🕳️","黑域","以背景光速的90%飞向目标，抵达2年后启动。中心区域光速降至零，黑域到期后恢复；刚恢复的区域暂时不受新黑域影响。",Aim.TARGET],
		Action.SINGULARITY:["⚫","奇异点","在一维空间发射，抵达后摧毁影响范围内的空间和其中的星系、设施与舰船。",Aim.TARGET],
		Action.SCAN:["📡","主动扫描","原母星或流浪地球；8E，8光年长、1光年半径，10年冷却，等待往返回波。",Aim.DIRECTION],
		Action.LANDING:["🏠","建立殖民地","先研究「星际殖民」。运输船抵达无主宜居星系后，花3E和4M施工，正常需4年；完工后消耗运输船并建立殖民地。",Aim.NONE],
	}



## 行动 a 要花的能量。派出和转向看单位：选中的行动用选中的单位，其他用第一个能选的单位。
func _cost(me: Civ, a: int) -> int:
	if a == Action.DISPATCH:
		var s := _unit_for(me, a)
		return state.command_cost(me,s) if s != null else 0
	if a==Action.STARSHIP:
		var ship:=state.reported_starship(me)
		return state.command_cost(me,ship) if ship!=null else 0
	if a==Action.SCAN:
		return Balance.SCAN_COST[0]
	if a==Action.LANDING:
		return Construction.cost("landing")[0]
	if a==Action.DOMAIN:
		return Balance.DOMAIN_COST[0]
	return GameState.action_cost(RULE_NAMES[a])


## 行动 a 现在为什么不能执行（能执行时为空）。原因都来自规则；选中的行动连目标一起检查，
## 没选中的只检查和目标无关的条件。
func _block(me: Civ, a: int) -> String:
	var target := _target_cell() if a == _action else GameState.ANY_TARGET
	var origin: Vector3i = main.panel.selected_origin()
	match a:
		Action.DISPATCH:
			var s := _unit_for(me, a)
			if s == null:
				return "没有能派出或转向的单位（先去「建造」页造）"
			return state.dispatch_error(me, s.id, _direction()) if s.docked else state.turn_error(me, s.id, _direction())
		Action.COLONY:
			var s := _unit_for(me, a)
			if s == null:
				return "没有停着的殖民船（在「建造」页造）"
			return state.colony_error(me, s.id, target)
		Action.STARSHIP:
			return state.starship_move_error(me, target)
		Action.SCAN:
			return state.scan_error(me,_direction())
		Action.LANDING:
			var ship:=_unit_for(me,a)
			return state.landing_error(me,ship.id) if ship!=null else "需要收到待命运输船的状态"
		Action.SETTLE:
			return state.settle_error(me)
		Action.GRAIN:
			return state.grain_error(me, _direction(), origin)
		Action.ANTIMATTER:
			return state.antimatter_error(me)
		Action.SOPHON:
			var s := _unit_for(me, a)
			if s == null:
				return "没有能派的智子（在「建造」页造）"
			return state.sophon_error(me, s.id, target)
		Action.BROADCAST:
			return state.broadcast_error(me, target, origin)
		Action.FOIL:
			return state.foil_error(me, false, target, origin)
		Action.LINE_FOIL:
			return state.foil_error(me, true, target, origin)
		Action.DOMAIN:
			return state.domain_error(me, target)
		Action.SINGULARITY:
			return state.singularity_error(me)
	return ""


## 做行动 a 用哪个单位：选中的行动用菜单里选中的，其他行动用第一个能选的（没有时为 null）。
func _unit_for(me: Civ, a: int) -> Ship:
	if a == _action:
		var s := _selected_unit()
		if s != null:
			return s
	var choices := _unit_choices(me, a)
	return choices[0] if not choices.is_empty() else null


## 可以选来做行动 a 的单位：派出或转向用探测器、战舰、吞噬者，殖民用停着的殖民船（含在外面待命的），
## 智子用停着的、没锁住别人的智子。
func _unit_choices(me: Civ, a: int) -> Array[Ship]:
	var result: Array[Ship] = []
	for s in Signals.reported_ships(state,me):
		if s.dead or state.ship_command_pending(me,s.id):
			continue
		if a == Action.DISPATCH and (Ship.AIMED.has(s.kind) if s.docked else Ship.TURNABLE.has(s.kind)):
			result.append(s)
		elif a in [Action.COLONY,Action.LANDING] and s.kind == Ship.COLONY and s.waiting():
			result.append(s)
		elif a == Action.SOPHON and s.kind == Ship.SOPHON and s.lock < 0 and s.waiting():
			result.append(s)
	return result


## 重建单位下拉菜单，尽量保持原来选中的单位。
func _refresh_units(me: Civ) -> void:
	var keep := _want_unit
	if keep < 0 and _unit_pick.selected >= 0:
		keep = _unit_pick.get_item_metadata(_unit_pick.selected)
	_want_unit = -1
	_unit_pick.clear()
	for s in _unit_choices(me, _action):
		var where := "停在 %s" % s.cell() if s.docked else "%s (%.1f, %.1f, %.1f)" % [
				"在飞" if s.moving() else "待命", s.pos.x, s.pos.y, s.pos.z]
		_unit_pick.add_item("%s　%s" % [s.label(), where])
		_unit_pick.set_item_metadata(_unit_pick.item_count - 1, s.id)
		if s.id == keep:
			_unit_pick.select(_unit_pick.item_count - 1)
	if _unit_pick.item_count > 0 and _unit_pick.selected < 0:
		_unit_pick.select(0)


func _selected_unit() -> Ship:
	if not _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON, Action.LANDING]:
		return null
	if _unit_pick.selected < 0 or _unit_pick.item_count == 0:
		return null
	return Signals.reported_ship(state,main.viewed(),_unit_pick.get_item_metadata(_unit_pick.selected))


# ---------- 瞄准 ----------

## 让两个角度（和距离）指向格子 c。
func aim_at(c: Vector3i) -> void:
	for i in _coord_boxes.size():
		_coord_boxes[i].set_value_no_signal(c[i])
	var v := Vector3(c) - _aim_point()
	if v.length() < 1e-6 and not _target_box.visible:
		return
	if v.length() >= 1e-6:
		_yaw.value = rad_to_deg(atan2(v.y, v.x))
		_pitch.value = rad_to_deg(atan2(v.z, Vector2(v.x, v.y).length()))
	_dist.set_value_no_signal(v.length())
	main.refresh()


## 角度和距离从哪里算起：派出、转向、殖民、智子从选中的单位算，星舰移动从星舰算，其他从发射源算。
func _aim_point() -> Vector3:
	var me: Civ = main.viewed()
	if _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON, Action.LANDING]:
		var s := _selected_unit()
		if s != null:
			return s.pos
	if _action == Action.STARSHIP and state.reported_starship(me)!=null:
		return state.reported_starship(me).pos
	return Vector3(main.panel.selected_origin())


## 两个角度换算成方向（长度为 1）。
func _direction() -> Vector3:
	var yaw := deg_to_rad(_yaw.value)
	if state.all_linear():
		return Vector3(1.0 if cos(yaw) >= 0.0 else -1.0, 0.0, 0.0)
	var pitch := 0.0 if state.all_flat() else deg_to_rad(_pitch.value)
	return state.space_direction(Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch)))


## 两个角度加距离算出来的目标格子（从起点算起，四舍五入到最近的格子；可能在星图外面）。
func _target_cell() -> Vector3i:
	return Vector3i((_aim_point() + _direction() * _dist.value).round())


## 已知坐标列表：选一个就把它填进目标坐标。
func _refresh_known_pick(me: Civ) -> void:
	_known_pick.clear()
	_known_pick.add_item("📋 已知星系")
	for c in me.known:
		_known_pick.add_item("%s　第 %d 回合看到" % [c, me.known[c]])
		_known_pick.set_item_metadata(_known_pick.item_count - 1, c)
	_known_pick.select(0)


func _on_known_picked(i: int) -> void:
	var c = _known_pick.get_item_metadata(i)
	if c is Vector3i:
		aim_at(c)
	else:
		main.refresh()


# ---------- 执行 ----------

func _on_go() -> void:
	if main.blocked():
		main.refresh()
		return
	var me: Civ = main.viewed()
	var origin: Vector3i = main.panel.selected_origin()
	var r := {"error": ""}
	var s := _selected_unit()
	match _action:
		Action.DISPATCH:
			if s == null:
				r = {"error": "没有选单位"}
			elif s.docked:
				r = state.dispatch(me, s.id, _direction(), _slow.button_pressed)
			else:
				r = state.turn_ship(me, s.id, _direction())
		Action.COLONY:
			r = state.send_colony(me, s.id, _target_cell()) if s != null else {"error": "没有选殖民船"}
		Action.STARSHIP:
			r = state.move_starship(me, _target_cell())
		Action.SCAN:
			r=state.active_scan(me,_direction())
		Action.LANDING:
			r=state.start_landing(me,s.id) if s!=null else {"error":"没有选运输船"}
		Action.SETTLE:
			r = state.settle_starship(me)
		Action.GRAIN:
			r = state.launch_grain(me, _direction(), origin)
		Action.ANTIMATTER:
			r = state.use_antimatter(me)
		Action.SOPHON:
			r = state.send_sophon(me, s.id, _target_cell()) if s != null else {"error": "没有选智子"}
		Action.BROADCAST:
			r = state.broadcast(me, _target_cell(), origin)
		Action.FOIL:
			r = state.launch_foil(me, _target_cell(), origin)
		Action.LINE_FOIL:
			r = state.launch_line_foil(me, _target_cell(), origin)
		Action.DOMAIN:
			r = state.launch_black_domain(me, _target_cell())
		Action.SINGULARITY:
			r = state.launch_singularity(me,_target_cell())
	main.panel.set_feedback("无法执行：" + r["error"] if r["error"] != "" else "")
	main.refresh()


## 快捷键按屏幕上的顺序循环选择行动，隐藏的维度武器跳过；执行仍走同一个按钮。
func cycle_action(direction: int) -> void:
	var choices := []
	for a in _action_tiles:
		if _action_tiles[a].visible:
			choices.append(a)
	_action = choices[posmod(choices.find(_action) + direction, choices.size())]
	main.panel.set_feedback("")
	main.refresh()


func _price_text(me: Civ,a: int) -> String:
	var m:=0.0
	if a==Action.LANDING:
		m=Construction.cost("landing")[1]
	elif a==Action.DOMAIN:
		m=Balance.DOMAIN_COST[1]
	return "%sE / %sM"%[Widgets.number(_cost(me,a)),Widgets.number(m)]
