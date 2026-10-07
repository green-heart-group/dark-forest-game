extends PanelContainer
## 右侧控制面板：最上面是资源和发射源，中间是科技、建造、行动、情况四页，最下面是「结束回合」。
## 能不能做、要花多少都问规则（GameState），这里只管显示和把按钮接到规则的函数上。
## 「行动」页比较大，单独放在 action_page.gd。

const Widgets := preload("res://view/widgets.gd")
const ActionPage := preload("res://view/action_page.gd")

## 建造页的顺序
const BUILD_ORDER := ["probe", "warship", "colony", "starship", "devourer", "sophon", "grain", "antimatter",
		"miner", "dyson", "bunker", "broadcaster", "warning"]
const BUILD_ICONS := {"probe": "🛰️", "warship": "🚀", "colony": "🌱", "starship": "🛸", "devourer": "🐛",
		"sophon": "👁️", "grain": "✨", "antimatter": "⚛️", "miner": "⛏️", "dyson": "🌞", "bunker": "🛡️", "broadcaster": "🌟",
		"warning": "🚨"}

var main: Node
var state: GameState:
	get: return main.state

## 「行动」页
var actions := ActionPage.new()
## 面板最上面的资源数字：能量、矿石、行动点
var _res_values: Dictionary[String, Label] = {}
var _origin_pick := OptionButton.new()
## 科技、建造、行动、情况四页
var _tabs := TabContainer.new()
## 科技页：每项科技一个按钮，键是 Tech.ALL 里的名字
var _tech_tiles: Dictionary[String, Button] = {}
## 射电望远镜和预警范围的升级按钮
var _upgrade_tiles: Dictionary[String, Button] = {}
## 每一级科技现在开没开放
var _tier_labels: Array[Label] = []
## 建造的按钮，键是 BUILD_ORDER 里的种类，另有 "reduce"（自身降维）
var _build_tiles: Dictionary[String, Button] = {}
var _reduce_info := Label.new()
## 「情况」页各项数值的标签，键是左边显示的名字
var _stat_values: Dictionary[String, Label] = {}
## 结束回合按钮上面的提示：上一次操作失败的原因
var _feedback := Label.new()
## 结束回合；对局结束后变成「再来一局」
var _end := Button.new()


func setup(p_main: Node) -> void:
	main = p_main
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -Widgets.PANEL_WIDTH
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if side in ["left", "right"] else 8)
	add_child(margin)
	# 最上面是资源和发射源，最下面是「结束回合」，都固定不动；中间是可以切换的几页
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)
	outer.add_child(_resource_bar())

	# 发射源：行动从这里出发，建造也建在这里
	var origin_row := HBoxContainer.new()
	origin_row.add_child(Widgets.dim_label("📍 发射源"))
	origin_row.tooltip_text = "建造的位置；光粒、广播、二向箔、黑域的出发点。"
	_origin_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_origin_pick.item_selected.connect(func(_i): main.refresh())
	origin_row.add_child(_origin_pick)
	outer.add_child(origin_row)

	actions.setup(main)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	for page in [["🔬 科技", _build_tech_page()], ["🏗️ 建造", _build_build_page()],
			["🎯 行动", actions], ["📊 情况", _build_stats_page()]]:
		_tabs.add_child(Widgets.scroll_page(page[1]))
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, page[0])
	_tabs.current_tab = 2

	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_feedback.visible = false
	outer.add_child(_feedback)
	_end.text = "⏭️ 结束回合"
	_end.add_theme_font_size_override("font_size", 18)
	_end.custom_minimum_size.y = 40
	_end.pressed.connect(main.end_turn)
	outer.add_child(_end)


## 面板最上面的一排资源：能量、矿石、行动点。
func _resource_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for spec in [
		["energy", "⚡", "能量：现有  +每回合收入"],
		["mineral", "🪨", "矿石：现有  +每回合收入"],
		["actions", "🎯", "行动点：剩余 / 每回合。母星恒星越多越少（乱纪元），每多一个星系 +1。"],
	]:
		var chip := PanelContainer.new()
		var bg := Widgets.card_style(0.06, 8)
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


## 科技页：按等级排的科技按钮，下面是射电望远镜和预警范围的升级。
func _build_tech_page() -> VBoxContainer:
	var box := Widgets.page_box()
	box.add_child(Widgets.hint_label("只花资源，不花行动点，马上生效。悬停看说明。"))
	for tier in Tech.TIER_NAMES.size():
		var label := Widgets.title("")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 开放条件写得长，不折行会把右侧面板撑宽
		_tier_labels.append(label)
		box.add_child(label)
		var grid := Widgets.tile_grid(3)
		box.add_child(grid)
		for id in Tech.ALL:
			if Tech.tier(id) != tier:
				continue
			var tile := Widgets.tile(Tech.ALL[id]["code"], Tech.ALL[id]["name"], "")
			tile.pressed.connect(_on_research.bind(id))
			grid.add_child(tile)
			_tech_tiles[id] = tile
	box.add_child(Widgets.title("升级　不花行动点"))
	var grid := Widgets.tile_grid(3)
	box.add_child(grid)
	for spec in [["telescope", "📡", "射电望远镜"], ["warning", "🚨", "预警范围"]]:
		var tile := Widgets.tile(spec[1], spec[2], "")
		tile.pressed.connect(_on_upgrade.bind(spec[0]))
		grid.add_child(tile)
		_upgrade_tiles[spec[0]] = tile
	return box


## 建造页：建在发射源上的单位和设施，加上自身降维。
func _build_build_page() -> VBoxContainer:
	var box := Widgets.page_box()
	box.add_child(Widgets.hint_label("建在发射源上，每次 1 行动点。单位造好停在星系里，到「行动」页派出；设施下回合建好。"))
	var grid := Widgets.tile_grid(4)
	box.add_child(grid)
	for kind in BUILD_ORDER:
		var tile := Widgets.tile(BUILD_ICONS[kind], GameState.BUILD_NAMES[kind], "")
		tile.pressed.connect(_on_build.bind(kind))
		grid.add_child(tile)
		_build_tiles[kind] = tile
	box.add_child(Widgets.title("自身降维"))
	var row := Widgets.tile_grid(4)
	box.add_child(row)
	var reduce := Widgets.tile("🔻", "自身降维", "")
	reduce.pressed.connect(_on_build.bind("reduce"))
	row.add_child(reduce)
	_build_tiles["reduce"] = reduce
	_reduce_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reduce_info.add_theme_font_size_override("font_size", 13)
	box.add_child(_reduce_info)
	return box


func _build_stats_page() -> VBoxContainer:
	var box := Widgets.page_box()
	var made := Widgets.stat_grid(_stats(main.viewed()).keys())
	box.add_child(made[0])
	_stat_values = made[1]
	return box


# ---------- 刷新 ----------

## 结束回合按钮上面的提示（上一次操作失败的原因、为什么现在不能操作）。
func set_feedback(text: String) -> void:
	_feedback.text = text
	_feedback.visible = text != ""  # 没有提示时不占地方


## 按现在的局面刷新整个面板。
func refresh(me: Civ) -> void:
	_refresh_origins(me)
	actions.refresh(me)
	var finished := state.is_over() and not state.collapse_pending()
	_end.text = "🔄 再来一局（新的星图）" if finished else "⏭️ 结束回合"
	_end.disabled = (state.is_over() and not finished) or (main.debug != null and main.debug.replaying())

	_res_values["energy"].text = "%d  +%d" % [me.energy, state.energy_income(me)]
	_res_values["mineral"].text = "%d  +%d" % [me.mineral, state.mineral_income(me)]
	_res_values["actions"].text = "%d / %d" % [me.actions_left, me.action_points(state.map)]
	_res_values["actions"].add_theme_color_override("font_color",
			Color(1.0, 0.5, 0.4) if me.actions_left <= 0 else Color.WHITE)

	_refresh_tech_tiles(me)
	_refresh_build_tiles(me)
	var stats := _stats(me)
	for key in stats:
		_stat_values[key].text = stats[key]


## 星系会增减（殖民、被打掉），每次刷新时重建发射源列表，尽量保持原来的选择。
func _refresh_origins(me: Civ) -> void:
	var previous := _origin_pick.get_item_text(_origin_pick.selected) if _origin_pick.selected >= 0 else ""
	_origin_pick.clear()
	for c in me.colonies:
		_origin_pick.add_item("%s %s" % ["母星" if c == me.home else "殖民地", c])
	var ss := me.starship()
	if ss != null:
		_origin_pick.add_item("星舰 %s" % ss.cell())
	for i in _origin_pick.item_count:
		if _origin_pick.get_item_text(i) == previous:
			_origin_pick.select(i)


## 选中的发射源（建造建在这里，光粒、广播、二向箔从这里出发）。
func selected_origin() -> Vector3i:
	var me: Civ = main.viewed()
	var origins := me.origins()
	if origins.is_empty():
		return me.home
	return origins[clampi(_origin_pick.selected, 0, origins.size() - 1)]


## 科技页：每一级开没开放，每项科技有没有、能不能升。
func _refresh_tech_tiles(me: Civ) -> void:
	for tier in _tier_labels.size():
		var open := state.tier_open(me, tier)
		var status := "未开放：%s" % Tech.TIER_RULES[tier]
		if open:
			status = "已开放"
		elif me.tier_turn(tier) >= 0:
			status = "第 %d 回合开放" % me.tier_turn(tier)
		_tier_labels[tier].text = "%s　%s" % [Tech.TIER_NAMES[tier], status]
		_tier_labels[tier].tooltip_text = "条件要按顺序达到；II、III 级至少比上一级晚 %d 回合开放。" % Balance.TIER_GAP
		_tier_labels[tier].add_theme_color_override("font_color",
				Color(0.6, 0.8, 1.0) if open else Color(0.6, 0.6, 0.65))
	for id in _tech_tiles:
		var tile := _tech_tiles[id]
		var has := me.has_tech(id)
		var reason := "" if has else state.research_error(me, id)
		tile.disabled = has or reason != ""
		tile.modulate = Color(0.55, 1.0, 0.65) if has else Color(1, 1, 1, 1.0 if reason == "" else 0.5)
		var cost := Tech.cost(id)
		Widgets.set_tile_cost(tile, "已有" if has else Widgets.cost_text(Vector2i(cost[0], cost[1])))
		var status := "已经有了" if has else ("现在不能升级：" + reason if reason != "" else "点一下升级")
		tile.tooltip_text = "%s\n%s\n\n%s" % [Tech.title(id), _tech_desc(id), status]
	for kind in _upgrade_tiles:
		var tile := _upgrade_tiles[kind]
		var reason := state.upgrade_error(me, kind)
		tile.disabled = reason != ""
		tile.modulate.a = 1.0 if reason == "" else 0.5
		var level := "%d/%d" % ([me.telescope, Balance.TELESCOPE_MAX] if kind == "telescope"
				else [me.warning_level, Balance.WARNING_MAX])
		Widgets.set_tile_cost(tile, "%s　%s" % [level, Widgets.cost_text(Vector2i(GameState.upgrade_cost(kind), 0))])
		var what := "视野半径和探测器圆锥长度 +%.1f 格，圆锥张角 +%.0f°。" % [Balance.TELESCOPE_STEP,
				Balance.TELESCOPE_ANGLE_STEP] if kind == "telescope" else "预警范围 +1 格。"
		tile.tooltip_text = "%s\n不花行动点，马上生效。%s" % [what, "\n\n现在不能升级：" + reason if reason != "" else ""]


## 建造页：每个按钮的价格、能不能建，以及自身降维的说明。
func _refresh_build_tiles(me: Civ) -> void:
	var at := selected_origin()
	for kind in BUILD_ORDER:
		var tile := _build_tiles[kind]
		var reason := state.build_error(me, kind, at)
		tile.disabled = reason != ""
		tile.modulate.a = 1.0 if reason == "" else 0.5
		var cost := state.build_cost(me, kind)
		Widgets.set_tile_cost(tile, Widgets.cost_text(Vector2i(cost[0], cost[1])))
		tile.tooltip_text = "%s %s\n%s%s" % [BUILD_ICONS[kind], GameState.BUILD_NAMES[kind], _build_desc(kind),
				"\n\n现在不能建：" + reason if reason != "" else ""]
	var reduce := _build_tiles["reduce"]
	var reason := state.reduce_error(me)
	reduce.disabled = reason != ""
	reduce.modulate.a = 1.0 if reason == "" else 0.5
	Widgets.set_tile_cost(reduce, ("剩 %d 回合" % me.reduce_left) if me.reduce_left > 0
			else Widgets.cost_text(Vector2i(me.reduce_cost(), 0)))
	reduce.tooltip_text = _reduce_description(me) + ("\n\n现在不能用：" + reason if reason != "" else "")
	_reduce_info.text = "携带 %d 个单位：%dE + %dE × %d = %dE\n准备 %d 回合，期间不能建造。" % [
			me.reduce_units(), Balance.COST_REDUCE_BASE, Balance.COST_REDUCE_PER_UNIT, me.reduce_units(),
			me.reduce_cost(), Balance.REDUCE_TURNS]
	if me.reduce_left > 0:
		_reduce_info.text = "正在准备%s生存，还剩 %d 回合。\n费用已支付；期间不能建造或投放。" % [
				"一维" if me.reduced else "二维", me.reduce_left]
	elif me.line_reduced:
		_reduce_info.text = "一维生存准备已完成。"
	elif me.reduced and not state.all_flat():
		_reduce_info.text = "二维生存准备已完成；全图进入二维后可再次降维。"
	elif not me.pending.is_empty():
		_reduce_info.text += "\n请先等建造完成（下一回合），完成后按新单位数计费。"


## 「情况」页的数值。
func _stats(me: Civ) -> Dictionary:
	var at := selected_origin()
	var units: Array[String] = []
	for kind in [Ship.PROBE, Ship.WARSHIP, Ship.COLONY, Ship.STARSHIP, Ship.DEVOURER, Ship.SOPHON, Ship.GRAIN]:
		var n := me.count(kind)
		if n > 0:
			units.append("%s %d" % [Ship.NAMES[kind], n])
	var building: Array[String] = []
	for p in me.pending:
		building.append(GameState.BUILD_NAMES[p["kind"]])
	var reports := 0
	for r in me.reports:
		reports += r["cells"].size()
	var weapons: Array[String] = []
	for w in GameState.warship_weapons(me):
		weapons.append(Tech.ALL[w]["name"])
	var watching: Array[String] = []
	for s in me.ships:
		if s.kind == Ship.SOPHON and s.lock >= 0:
			watching.append(state.civs[s.lock].name)
	var sophon := "锁住 " + "、".join(watching) if not watching.is_empty() else "无"
	if not state.sophons_on(me).is_empty():
		sophon += "　被锁住：科技还要 %d 回合，等级条件还要 %d 回合" % [state.sophon_research_left(me), state.sophon_tier_left(me)]
	return {
		"星系": "%d 个　采矿船 %d　掩体 %d" % [me.colonies.size(), me.miner_count(), me.bunkers.size()],
		"发射源": "%s　类地 %d　类木 %d" % [at, state.map.rocky.get(at, 0), state.map.gas.get(at, 0)],
		"恒星": "%d 颗　戴森球 %d" % [me.star_total(state.map), me.dyson_count()],
		"视野": "母星 %.1f 格　望远镜 %d 级" % [state.sphere_radius(me, Balance.VISION_HOME), me.telescope],
		"单位": "、".join(units) if not units.is_empty() else "无",
		"建造中": "、".join(building) if not building.is_empty() else "无",
		"存货": "光粒 %d　反物质 %d/%d" % [me.grains.size(), me.antimatter, Balance.MAX_ANTIMATTER],
		"预警系统": ("范围 %.0f 格" % me.warning_range()) if me.has_warning else "无",
		"广播器": "%d 个%s" % [me.broadcasters.size(), "　引力波广播" if me.has_tech("gravity") else ""],
		"情报": "已知敌方星系 %d　看过 %d 格　路上 %d 条" % [me.known.size(), me.intel.size(), reports],
		"战舰武器": "、".join(weapons) if not weapons.is_empty() else "无",
		"智子": sophon,
		"被打": "%d 次" % me.times_hit,
		"降维": ("进行中，还剩 %d 回合" % me.reduce_left) if me.reduce_left > 0 else (
				"一维（产能 1/4）" if me.line_reduced else ("二维（产能 1/2）" if me.reduced else "无")),
		"黑域": "光速为 0 的中心 %d 个%s" % [state.black_domains.size(),
				"　你的准备中 %d 个" % me.pending_domains.size() if not me.pending_domains.is_empty() else ""],
	}


# ---------- 说明文字 ----------

## 每种建造的说明。
func _build_desc(kind: String) -> String:
	match kind:
		"probe":
			return "到「行动」页派出。飞行时用圆锥看前方，看到的按光速传回。"
		"warship":
			return "停着也能防守。派出后每回合打 %.0f 格内一个目标：先殖民船，再没有反物质的星系。遇到敌方战舰、星舰同归于尽。带上升级过的武器（每种多花钱），敌方战舰进了射程自动开火。最多 %d 艘。" % [
					Balance.WARSHIP_RANGE, Balance.MAX_WARSHIPS]
		"sophon":
			return "到「行动」页派去别人的母星系：锁住对方 %d 回合不能升科技、%d 回合达到的等级条件不算，它做的事你都看得到，直到它造出智子。最多 %d 个。" % [
					Balance.SOPHON_RESEARCH_TURNS, Balance.SOPHON_TIER_TURNS, Balance.MAX_SOPHONS]
		"colony":
			return "到「行动」页选目的地。到了无主的宜居星系就建新星系。最多 %d 艘。" % Balance.MAX_COLONY_SHIPS
		"starship":
			return "会移动的据点：星系全丢了也能活。能在无主的宜居星系定居。"
		"devourer":
			return "吃掉路上无主星系的类地行星，每颗 +%dM。吃到宜居行星，那里就不能殖民。" % Balance.DEVOURER_MINERAL
		"grain":
			return "存 1 颗（每个星系最多 1 颗），到「行动」页发射，发射 %dE。" % Balance.COST_GRAIN_LAUNCH
		"antimatter":
			return "存 1 份，最多 %d 份。有反物质时敌方战舰打不了你的星系；也可在「行动」页消灭附近的敌方战舰。" % Balance.MAX_ANTIMATTER
		"miner":
			return "每艘矿石 +%d/回合。每个星系最多 %d 艘，下回合建好。" % [Balance.MINER_MINERAL, Balance.MAX_MINERS]
		"dyson":
			return "能量 +%d/回合（星系还有恒星时）。总数不超过恒星数，下回合建好。" % Balance.DYSON_ENERGY
		"bunker":
			return "要有类木行星。光粒打掉恒星时人能活下来；挡不住战舰。下回合建好。"
		"broadcaster":
			return "能从这里广播坐标，也能听到别人的广播。别人的星际探测器停在这里时失效。下回合建好。"
		"warning":
			return "敌方战舰、光粒、二向箔进入 %.0f 格内时报告位置。全文明一个，可在科技页升级范围。下回合建好。" % Balance.WARNING_RANGE
	return ""


## 每项科技的说明。
func _tech_desc(id: String) -> String:
	match id:
		"miner": return "解锁采矿船（矿石 +%d/回合）。" % Balance.MINER_MINERAL
		"fission": return "每颗类地行星能量 +%d/回合。" % Balance.FISSION_ENERGY
		"telescope": return "可升级射电望远镜：视野和探测器圆锥更大。"
		"probe": return "解锁探测器：飞出去看远处。"
		"broadcaster": return "解锁恒星广播器：公开别人的坐标，也能听到别人的广播。"
		"warning": return "解锁预警系统：敌方打击靠近时报告位置。"
		"dyson": return "解锁戴森球（能量 +%d/回合）。" % Balance.DYSON_ENERGY
		"interstellar_probe": return "之后造的探测器圆锥更长更宽，会停在别人的星系上，让那里的广播器失效。"
		"warship": return "解锁恒星级战舰。"
		"bunker": return "解锁掩体（要有类木行星）。"
		"colony": return "解锁殖民船：去别的宜居星系建星系。"
		"devourer": return "解锁吞噬者：吃无主星系的行星换矿石。"
		"grain": return "解锁光粒：从远处打掉别人的星系。"
		"gravity": return "所有星系都能广播，不怕封锁；之后造的战舰也能广播（多 %dE）。" % Balance.COST_WARSHIP_GRAVITY
		"antimatter": return "解锁反物质：挡住和消灭敌方战舰。"
		"warp": return "之后造的单位在自己星系视野外以光速飞（每个多 %dE）。" % Balance.COST_WARP_EXTRA
		"starship": return "解锁星舰。"
		"beam": return "之后造的战舰带上：射程 %.1f 格，打一次 %dE，直接毁掉敌方战舰（每艘多 %dE）。" % [
				Balance.BEAM_RANGE, Balance.BEAM_SHOT[0], Balance.COST_BEAM_EXTRA[0]]
		"torpedo": return "之后造的战舰带上：射程 %.1f 格，打一次 %dM，打中 %d 次毁掉敌方战舰（每艘多 %dM）。" % [
				Balance.TORPEDO_RANGE, Balance.TORPEDO_SHOT[1], Balance.TORPEDO_HITS, Balance.COST_TORPEDO_EXTRA[1]]
		"hbomb": return "之后造的战舰带上：射程 %.1f 格，打一次 %dE + %dM，杀死敌方战舰的船员，收回它造船花的资源（每艘多 %dE + %dM）。最先用。" % [
				Balance.HBOMB_RANGE, Balance.HBOMB_SHOT[0], Balance.HBOMB_SHOT[1], Balance.COST_HBOMB_EXTRA[0],
				Balance.COST_HBOMB_EXTRA[1]]
		"sophon": return "解锁智子：锁住别人的科技，看着它的一举一动。被锁住时造一个就能解除。"
		"dark_energy": return "视野里每 %d 格，能量 +1/回合。" % Balance.DARK_ENERGY_CELLS
		"dimension": return "解锁二向箔、单向著和自身降维。"
		"domain": return "解锁黑域。"
	return ""


func _reduce_description(me: Civ) -> String:
	var names := {"systems": "星系", "ships": "单位", "dysons": "戴森球", "miners": "采矿船", "bunkers": "掩体",
			"broadcasters": "恒星广播器", "warning": "预警系统", "antimatter": "反物质", "grains": "光粒"}
	var parts: Array[String] = []
	var counts := me.reduce_unit_counts()
	for kind in counts:
		if counts[kind] > 0:
			parts.append("%s %d" % [names[kind], counts[kind]])
	return "全部携带：%s。\n共 %d 个单位，%dE + %dE × %d = %dE，启动时一次支付。\n花 %d 回合准备%s生存，期间不能建造；建造中的要先完成。\n%s" % [
			"、".join(parts), me.reduce_units(), Balance.COST_REDUCE_BASE, Balance.COST_REDUCE_PER_UNIT,
			me.reduce_units(), me.reduce_cost(), Balance.REDUCE_TURNS, "一维" if me.reduced else "二维",
			"完成后抵挡单向著，产能再减半。" if me.reduced else "完成后不怕光粒和二向箔，产能减半。"]


# ---------- 按钮 ----------

func _on_build(kind: String) -> void:
	if main.blocked():
		main.refresh()
		return
	var me: Civ = main.viewed()
	var r: Dictionary
	if kind == "reduce":
		r = state.start_reduce(me)
	else:
		r = state.build(me, kind, selected_origin())
	var name: String = "自身降维" if kind == "reduce" else GameState.BUILD_NAMES[kind]
	set_feedback("无法执行「%s」：%s" % [name, r["error"]] if r["error"] != "" else "")
	# 造好的单位：在「行动」页里预先选中它，方便马上派出
	var ship = r.get("ship")
	if ship != null:
		actions.select_unit(ship)
	main.refresh()


func _on_research(id: String) -> void:
	if main.blocked():
		main.refresh()
		return
	var r := state.research(main.viewed(), id)
	set_feedback("无法升级「%s」：%s" % [Tech.ALL[id]["name"], r["error"]] if r["error"] != "" else "")
	main.refresh()


func _on_upgrade(kind: String) -> void:
	if main.blocked():
		main.refresh()
		return
	var r := state.upgrade(main.viewed(), kind)
	set_feedback("无法升级：%s" % r["error"] if r["error"] != "" else "")
	main.refresh()
