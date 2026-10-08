extends VBoxContainer
## 面板的「行动」页：选一个行动，给方向或目标，执行。
## 能不能执行、要花多少，都问规则（GameState 的 xxx_error、action_cost），这里只管显示和收集输入。

const Widgets := preload("res://view/widgets.gd")
const MapView := preload("res://view/map_view.gd")
const AngleDial := preload("res://view/angle_dial.gd")

## 行动页里的行动。DISPATCH 是派出停着的单位，或让在飞的战舰、吞噬者转向。
enum Action { DISPATCH, COLONY, STARSHIP, SETTLE, GRAIN, ANTIMATTER, SOPHON, BROADCAST, FOIL, LINE_FOIL, DOMAIN, SINGULARITY }
## 行动要玩家给什么：不用给、一个方向、一个目标格子
enum Aim { NONE, DIRECTION, TARGET }
## 每个行动对应的规则函数名（GameState.action_cost 用这个名字查价格）
const RULE_NAMES := {
	Action.DISPATCH: "dispatch", Action.COLONY: "send_colony", Action.STARSHIP: "move_starship",
	Action.SETTLE: "settle_starship", Action.GRAIN: "launch_grain", Action.ANTIMATTER: "use_antimatter",
	Action.SOPHON: "send_sophon",
	Action.BROADCAST: "broadcast", Action.FOIL: "launch_foil", Action.LINE_FOIL: "launch_line_foil",
	Action.DOMAIN: "launch_black_domain", Action.SINGULARITY: "launch_singularity",
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
## 目标位置用极坐标表示：方向用上面的两个角度圆盘，再加离发射源的距离
var _dist := HSlider.new()
var _dist_label := Label.new()
## 算出来的目标格子（写在距离后面）
var _target_info := Label.new()
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
	_slow.text = "先慢速飞出自己的视野（藏住航迹起点）"
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
	dials.add_child(_dial_box(_yaw, "↻ 水平角", "0° 朝 x 轴，90° 朝 y 轴。" + how))
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
	_target_info.add_theme_font_size_override("font_size", 13)
	_target_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_refresh_units(me)
	_refresh_aim_inputs()
	_refresh_known_pick(me)

	var specs := _action_specs()
	for a in _action_tiles:
		var tile := _action_tiles[a]
		var reason := _block(me, a)
		tile.button_pressed = a == _action
		tile.modulate.a = 1.0 if reason == "" else 0.5
		Widgets.set_tile_cost(tile, Widgets.cost_text(Vector2i(_cost(me, a), 0)))
		tile.tooltip_text = "%s %s（1 行动点）\n%s%s" % [specs[a][0], specs[a][1], specs[a][2],
				"\n\n现在不能用：" + reason if reason != "" else ""]
	var spec: Array = specs[_action]
	# 行动的名字写在选中的方块和执行按钮上，说明不占面板，放在它们的悬停说明里
	_go.tooltip_text = spec[2]
	var block := _block(me, _action)
	var verb: String = spec[1]
	var unit := _selected_unit()
	if _action == Action.DISPATCH and unit != null:
		verb = ("派出" if unit.docked else "转向") + unit.label()
	_go.text = "▶ %s　%s" % [verb, Widgets.cost_text(Vector2i(_cost(me, _action), 0))]
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
	_unit_box.visible = _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON]
	var s := _selected_unit()
	_slow.visible = _action == Action.DISPATCH and s != null and s.kind == Ship.PROBE and s.docked
	var from := "选中的单位" if _unit_box.visible else ("星舰" if _action == Action.STARSHIP else "发射源")
	# 只留一行，细节（角度加距离、圆钮怎么调）在提示和圆盘的悬停说明里
	if aim == Aim.TARGET:
		_aim_hint.text = "👆 点星图上的格子当目标（从%s算起）" % from
		_aim_hint.tooltip_text = "点星图上的格子选目标。也可以调角度和距离，或输入坐标。"
	else:
		_aim_hint.text = "👆 点星图上的格子定方向（从%s算起）" % from
		_aim_hint.tooltip_text = "点星图上的格子定方向。也可以调角度，或输入坐标。"
	if state.all_flat():
		_aim_hint.text += "\n一维空间：只能沿 x 轴移动。" if state.all_linear() else "\n二维空间：只有水平角。"
	match _action:
		Action.FOIL:
			_dist_row.tooltip_text = "离发射源多远（以目标格子为中心压平）"
		Action.LINE_FOIL:
			_dist_row.tooltip_text = "离发射源多远（沿 x 扩散，最终展开为 %d 格直线）" % DimensionSpace.COUNT
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
		Action.DISPATCH: ["🚀", "派出 / 转向",
				"派出停着的探测器（%dE）、战舰（%dE）、吞噬者（%dE），或让在飞的战舰、吞噬者转向（%dE，转过 90° 以上速度归零）。单位每回合先加速再飞。" % [
					Balance.COST_PROBE_LAUNCH, Balance.COST_WARSHIP_LAUNCH, Balance.COST_DEVOURER_LAUNCH, Balance.COST_TURN],
				Aim.DIRECTION],
		Action.COLONY: ["🌱", "殖民",
				"派殖民船去一个格子，不花能量。绿圈是看到过的宜居星系；没看到过的地方也能盲飞。到了能殖民就建星系，不能就原地待命。路过别人的星系会被毁。",
				Aim.TARGET],
		Action.STARSHIP: ["🛸", "星舰移动",
				"星舰飞到目标格子停下，不能停在已知的敌方星系。星舰是据点：星系全丢了也能活。",
				Aim.TARGET],
		Action.SETTLE: ["🏠", "星舰定居",
				"星舰停在无主的宜居星系上时，在那里建星系，星舰用掉。", Aim.NONE],
		Action.GRAIN: ["✨", "光粒",
				"从存着光粒的发射源朝一个方向发射，光速飞行。打中路上第一个别人的星系：毁 1 颗恒星，抹掉那里的文明（有掩体时人活下来）。",
				Aim.DIRECTION],
		Action.ANTIMATTER: ["⚛️", "反物质",
				"用 1 份反物质，消灭自己星系 %.0f 格内最近的敌方战舰。" % Balance.ANTIMATTER_RANGE, Aim.NONE],
		Action.SOPHON: ["👁️", "智子",
				"派智子去一个格子，以 %.2f 倍光速飞，别人看不到。到了别人的母星系就锁住它：%d 回合不能升科技，%d 回合达到的等级条件不算，它做的事你都看得到，直到它自己造出智子。不是母星系就原地待命。" % [
					Balance.SOPHON_MOVE[0], Balance.SOPHON_RESEARCH_TURNS, Balance.SOPHON_TIER_TURNS],
				Aim.TARGET],
		Action.BROADCAST: ["📢", "广播",
				"从有广播器的发射源把一个坐标以光速告诉所有人。那里的文明可能被听到的人（包括看不见的隐藏文明）打。离目标越近，越容易暴露自己。",
				Aim.TARGET],
		Action.FOIL: ["📄", "二向箔",
				"准备 %d 回合后飞向目标格子，路上不停，到了才展开（可以打空格子）：每列 9 格展开为 3×3，波前持续扩散。全图完成后得到 %d×%d 新坐标并重新探索。未自身降维的文明会被消灭。" % [Balance.FOIL_PREPARE_TURNS, DimensionSpace.PLANE_SIZE, DimensionSpace.PLANE_SIZE],
				Aim.TARGET],
		Action.LINE_FOIL: ["━", "单向著",
				"二维里用。准备 %d 回合后起飞，展开后沿 x 轴扩散，把平面压成直线。只有再次降维的文明能活。" % Balance.FOIL_PREPARE_TURNS,
				Aim.TARGET],
		Action.DOMAIN: ["🕳️", "黑域",
				"在现在看得到的一格投放黑域，准备 %d 回合后生效：那一格的光速变成 0，保持 %d 回合，同时每回合向周围扩散一格，之后慢慢恢复。光速变慢的地方舰船和情报都变慢；光速低于 %.2f 时光粒没有杀伤力，那里的星系产出只有 1/10，母星系在里面不能升科技；光速接近 0 时光和舰船过不去，舰船停 %d 回合后消失。所有星系都困在光速为 0 的地方算输。" % [
					Balance.BLACK_DOMAIN_PREPARE_TURNS, Balance.BLACK_DOMAIN_TURNS, Balance.GRAIN_MIN_LIGHT,
					Balance.SHIP_STUCK_TURNS],
				Aim.TARGET],
		Action.SINGULARITY: ["⚫", "奇异点",
				"全图压成直线、自己已进入一维后可用。%d 回合后降到零维，获胜。" % Balance.SINGULARITY_TURNS,
				Aim.NONE],
	}


## 行动 a 要花的能量。派出和转向看单位：选中的行动用选中的单位，其他用第一个能选的单位。
func _cost(me: Civ, a: int) -> int:
	if a == Action.DISPATCH:
		var s := _unit_for(me, a)
		return GameState.dispatch_cost(s) if s != null else 0
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
	for s in me.ships:
		if s.dead:
			continue
		if a == Action.DISPATCH and (Ship.AIMED.has(s.kind) if s.docked else Ship.TURNABLE.has(s.kind)):
			result.append(s)
		elif a == Action.COLONY and s.kind == Ship.COLONY and s.waiting():
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
	if not _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON]:
		return null
	if _unit_pick.selected < 0 or _unit_pick.item_count == 0:
		return null
	return main.viewed().ship_by_id(_unit_pick.get_item_metadata(_unit_pick.selected))


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
	if _action in [Action.DISPATCH, Action.COLONY, Action.SOPHON]:
		var s := _selected_unit()
		if s != null:
			return s.pos
	if _action == Action.STARSHIP and me.has_starship():
		return me.starship().pos
	return Vector3(main.panel.selected_origin())


## 两个角度换算成方向（长度为 1）。
func _direction() -> Vector3:
	var yaw := deg_to_rad(_yaw.value)
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
			r = state.launch_singularity(me)
	main.panel.set_feedback("无法执行：" + r["error"] if r["error"] != "" else "")
	main.refresh()
