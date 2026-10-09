extends PanelContainer
## 独立的全屏科技树。列按等级与同级前置排列，连线只取 Tech.ALL.needs。
## 选节点看详情，再研究；锁定节点也能查看，条件和价格仍由规则提供。

const NODE_SIZE := Vector2(176, 58)
const COLUMN_STEP := 226.0
const ROW_STEP := 68.0
const TOP := 76.0

var main: Node
var tiles: Dictionary[String, Button] = {}
var edges: Array[Array] = []
var selected_id := "dyson"
var _canvas := Control.new()
var _scroll := ScrollContainer.new()
var _details := Label.new()
var _resources := Label.new()
var _research := Button.new()
var _headings: Array[Label] = []
var _heading_tiers: Array[int] = []
var _return_focus: Control


func setup(p_main: Node) -> void:
	main = p_main
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", _style(Color("111722"), Color("29364b")))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "科技树   →   从左向右研究"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "返回星图 · Esc"
	close.pressed.connect(close_tree)
	header.add_child(close)
	box.add_child(header)
	_resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resources.add_theme_font_size_override("font_size", 14)
	box.add_child(_resources)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_scroll.add_child(_canvas)
	_canvas.draw.connect(_draw_edges)
	_build_graph()
	var footer := HBoxContainer.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.custom_minimum_size.y = 106
	_details.add_theme_font_size_override("font_size", 14)
	footer.add_child(_details)
	_research.custom_minimum_size.x = 160
	_research.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_research.pressed.connect(_on_research)
	footer.add_child(_research)
	box.add_child(footer)
	hide()


func _build_graph() -> void:
	var columns := {}
	var next_column := 0
	var max_rows := 0
	for tier in Tech.TIER_NAMES.size():
		var pending: Array = Tech.ALL.keys().filter(func(id): return Tech.tier(id) == tier)
		var tier_end := next_column
		# 同级依赖仍然向右，不能把战舰和它的武器画在同一列。
		while not pending.is_empty():
			var progressed := false
			for id in pending.duplicate():
				var col := next_column
				var ready := true
				for need in Tech.ALL[id]["needs"]:
					if not columns.has(need):
						ready = false
						break
					col = maxi(col, columns[need] + 1)
				if not ready:
					continue
				columns[id] = col
				tier_end = maxi(tier_end, col)
				pending.erase(id)
				progressed = true
			assert(progressed, "科技依赖不能成环")
		for col in range(next_column, tier_end + 1):
			var heading := Label.new()
			heading.position = Vector2(12 + col * COLUMN_STEP, 0)
			heading.add_theme_font_size_override("font_size", 15)
			_canvas.add_child(heading)
			_headings.append(heading)
			_heading_tiers.append(tier)
		next_column = tier_end + 1
	var rows := {}
	# 把相邻的科技链尽量摆在同一行；这里只是排版，不定义依赖。
	var order: Array = ["fission", "probe", "telescope", "warning", "colony", "miner", "broadcaster"]
	for id in Tech.ALL:
		if not order.has(id):
			order.append(id)
	for id in order:
		var col: int = columns[id]
		var row: int = rows.get(col, 0)
		if id == "beam":
			row = 2
		elif id == "dimension":
			row = 2
		elif id == "domain":
			row = 4
		rows[col] = row + 1
		max_rows = maxi(max_rows, row + 1)
		var tile := Button.new()
		tile.position = Vector2(12 + col * COLUMN_STEP, TOP + row * ROW_STEP)
		tile.size = NODE_SIZE
		tile.add_theme_font_size_override("font_size", 14)
		tile.pressed.connect(select_tech.bind(id))
		_canvas.add_child(tile)
		tiles[id] = tile
		for need in Tech.ALL[id]["needs"]:
			edges.append([need, id])
	_canvas.custom_minimum_size = Vector2(next_column * COLUMN_STEP - 26, TOP + max_rows * ROW_STEP)


func open_tree() -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	if main.debug != null:
		main.debug.pause()
	main.map._drag_button = MOUSE_BUTTON_NONE
	main.map._set_hover({})
	show()
	refresh(main.viewed())
	tiles[selected_id].grab_focus()
	_scroll.ensure_control_visible.call_deferred(tiles[selected_id])


func close_tree() -> void:
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	else:
		get_viewport().gui_release_focus()


func select_tech(id: String) -> void:
	selected_id = id
	refresh(main.viewed())


func refresh(me: Civ) -> void:
	_resources.text = "%d E   /   %d M     已有 · 可研究 · 未解锁     选节点查看；箭头只表示直接前置，等级另需开放。" % [me.energy, me.mineral]
	for i in _headings.size():
		var tier := _heading_tiers[i]
		_headings[i].text = "%s · %s" % [Tech.TIER_NAMES[tier], "已开放" if main.state.tier_open(me, tier) else "未开放"]
		_headings[i].tooltip_text = Tech.TIER_RULES[tier]
	for id in tiles:
		var has := me.has_tech(id)
		var reason: String = main.locked_reason()
		if reason == "":
			reason = main.state.research_error(me, id)
		var status := "已有" if has else ("可研究" if reason == "" else "未解锁")
		if not has and reason != "" and main.locked_reason() == "" and main.state.research_block_error(me, id) == "":
			status = "资源不足"
		var cost := Tech.cost(id)
		tiles[id].text = "%s\n%s%s" % [Tech.title(id), status, "" if has else " · %d E / %d M" % [cost[0], cost[1]]]
		tiles[id].tooltip_text = main.panel._tech_desc(id) + ("" if has or reason == "" else "\n" + reason)
		var border := Color("486580") if has else (Color("73bfe0") if reason == "" else Color("344053"))
		if id == selected_id:
			border = Color("edd08a")
		tiles[id].add_theme_stylebox_override("normal", _style(Color("202e40") if has else Color("19212e"), border))
		tiles[id].add_theme_stylebox_override("hover", _style(Color("2b3d53"), border.lightened(0.2)))
		tiles[id].add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("edd08a")))
		tiles[id].add_theme_color_override("font_color", Color("b6c5d7") if has or reason != "" else Color("e6f5ff"))
	var needs: Array = Tech.ALL[selected_id]["needs"].map(func(id): return Tech.ALL[id]["name"])
	var reason: String = main.locked_reason()
	if reason == "":
		reason = main.state.research_error(me, selected_id)
	_research.disabled = reason != "" or me.has_tech(selected_id)
	_research.text = "已有" if me.has_tech(selected_id) else "研究 · 不花行动点"
	var status := "已经拥有" if me.has_tech(selected_id) else ("可以研究，立即生效" if reason == "" else reason)
	_details.text = "%s　|　%s\n%s\n前置：%s。等级条件：%s。\n%s" % [Tech.title(selected_id), status,
			main.panel._tech_desc(selected_id), "无" if needs.is_empty() else "、".join(needs), Tech.TIER_RULES[Tech.tier(selected_id)],
			"II、III 级至少比上一级晚 %d 回合开放。" % Balance.TIER_GAP]
	_canvas.queue_redraw()


func _on_research() -> void:
	if not _research.disabled:
		main.panel._on_research(selected_id)


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


## 跨列的长连线从顶端通道绕行，避免穿过中间的科技按钮。
func _draw_edges() -> void:
	var lane := 0
	var paths: Array[Array] = []
	var source_lanes := {}
	var next_lanes := {}
	for edge in edges:
		var source: Button = tiles[edge[0]]
		var target: Button = tiles[edge[1]]
		var a := source.position + Vector2(source.size.x, source.size.y / 2)
		var b := target.position + Vector2(0, target.size.y / 2)
		var column := int(source.position.x / COLUMN_STEP)
		if not source_lanes.has(edge[0]):
			source_lanes[edge[0]] = next_lanes.get(column, 0)
			next_lanes[column] = next_lanes.get(column, 0) + 1
		var x := a.x + 8 + int(source_lanes[edge[0]]) * 6
		var points := PackedVector2Array([a])
		if b.x - a.x > COLUMN_STEP:
			var y := 32.0 + lane * 11.0
			lane += 1
			var end_x := b.x - 8 - lane * 5
			points.append_array(PackedVector2Array([Vector2(x, a.y), Vector2(x, y), Vector2(end_x, y), Vector2(end_x, b.y)]))
		else:
			points.append_array(PackedVector2Array([Vector2(x, a.y), Vector2(x, b.y)]))
		points.append(b)
		var active: bool = selected_id in edge
		paths.append([points, active])
	# 当前节点的线最后画，不被其他依赖压住。
	for active in [false, true]:
		for path in paths:
			if path[1] != active:
				continue
			var points: PackedVector2Array = path[0]
			var b := points[-1]
			var color := Color("edd08a") if active else Color("50617b")
			_canvas.draw_polyline(points, color, 2.5 if active else 1.2, true)
			_canvas.draw_colored_polygon(PackedVector2Array([b, b + Vector2(-8, -4), b + Vector2(-8, 4)]), color)
