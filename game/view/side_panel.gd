extends PanelContainer
## 右侧控制面板：最上面是资源和发射源，中间是科技、建造、行动、情况四页，最下面是「结束回合」。
## 能不能做、要花多少都问规则（GameState），这里只管显示和把按钮接到规则的函数上。
## 「行动」页比较大，单独放在 action_page.gd。

const Widgets := preload("res://view/widgets.gd")
const ActionPage := preload("res://view/action_page.gd")
const V01Controls := preload("res://view/v01_controls.gd")

## 建造页的顺序
const BUILD_ORDER := ["probe", "warship", "colony", "starship", "devourer", "sophon", "grain", "antimatter",
		"miner", "dyson", "bunker", "broadcaster", "warning", "advanced_miner", "nuclear_probe", "droplet", "dimension_weapon", "wandering_earth"]
const BUILD_ICONS := {"probe": "🛰️", "warship": "🚀", "colony": "🌱", "starship": "🛸", "devourer": "🐛",
		"sophon": "👁️", "grain": "✨", "antimatter": "⚛️", "miner": "⛏️", "dyson": "🌞", "bunker": "🛡️", "broadcaster": "🌟",
		"warning": "🚨", "advanced_miner":"⛏️", "nuclear_probe":"🛰️", "droplet":"💧", "dimension_weapon":"📄", "wandering_earth":"🌍"}

var main: Node
var state: GameState:
	get: return main.state

## 「行动」页
var actions := ActionPage.new()
var advanced := V01Controls.new()
## 面板最上面的资源数字：能量、矿石、行动点
var _res_values: Dictionary[String, Label] = {}
var _origin_pick := OptionButton.new()
## 科技、建造、行动、情况四页
var _tabs := TabContainer.new()
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
var _build_state: GameState
var _build_orders: Dictionary = {}
var _build_progress := Label.new()
var _build_hint := Widgets.hint_label("")


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
	_origin_pick.clip_text=true
	_origin_pick.fit_to_longest_item=false
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
	_tabs.tab_changed.connect(func(_tab): main.refresh())

	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_feedback.visible = false
	outer.add_child(_feedback)
	_end.text = "⏭️ 结束回合"
	_end.add_theme_font_size_override("font_size", 18)
	_end.custom_minimum_size.y = 40
	_end.pressed.connect(main.end_turn)
	_end.tooltip_text = "结束回合（Shift+Enter）"
	outer.add_child(_end)


## 面板最上面的一排资源：能量、矿石、行动点。
func _resource_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for spec in [
		["energy", "⚡", "已结算、可支用的能量余额。远端生产和损失详情以收到的回报为准。"],
		["mineral", "🪨", "已结算、可支用的矿石余额。远端生产和损失详情以收到的回报为准。"],
		["actions", "🎯", "行动点：剩余 / 每回合，未用完不结转。"],
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


## 科技页：打开完整依赖图、等级状态，以及射电望远镜和预警范围的升级。
func _build_tech_page() -> VBoxContainer:
	var box := Widgets.page_box()
	var open := Button.new()
	open.text = "打开全屏科技树 · Alt+1"
	open.custom_minimum_size.y = 48
	open.pressed.connect(func(): main.tech_tree.open_tree())
	box.add_child(open)
	for tier in Tech.TIER_NAMES.size():
		var label := Widgets.title("")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 开放条件写得长，不折行会把右侧面板撑宽
		_tier_labels.append(label)
		box.add_child(label)
	box.add_child(Widgets.title("升级　1 行动点 + 工程"))
	var grid := Widgets.tile_grid(3)
	box.add_child(grid)
	for spec in [["telescope", "📡", "射电望远镜"], ["warning", "🚨", "预警范围"]]:
		var tile := Widgets.tile(spec[1], spec[2], "")
		tile.pressed.connect(_on_upgrade.bind(spec[0]))
		Widgets.explain_disabled(tile,set_feedback)
		grid.add_child(tile)
		_upgrade_tiles[spec[0]] = tile
	return box


## 建造页：建在发射源上的单位和设施，加上自身降维。
func _build_build_page() -> VBoxContainer:
	var box := Widgets.page_box()
	box.add_child(_build_hint)
	_build_progress.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_build_progress.add_theme_font_size_override("font_size",13)
	box.add_child(_build_progress)
	var grid := Widgets.tile_grid(4)
	box.add_child(grid)
	for kind in BUILD_ORDER:
		var tile := Widgets.tile(BUILD_ICONS[kind], GameState.BUILD_NAMES[kind], "")
		tile.pressed.connect(_on_build.bind(kind))
		Widgets.explain_disabled(tile,set_feedback)
		grid.add_child(tile)
		_build_tiles[kind] = tile
	box.add_child(Widgets.title("自身降维"))
	var row := Widgets.tile_grid(4)
	box.add_child(row)
	var reduce := Widgets.tile("🔻", "自身降维", "")
	reduce.pressed.connect(_on_build.bind("reduce"))
	Widgets.explain_disabled(reduce,set_feedback)
	row.add_child(reduce)
	_build_tiles["reduce"] = reduce
	_reduce_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reduce_info.add_theme_font_size_override("font_size", 13)
	box.add_child(_reduce_info)
	advanced.setup(main)
	box.add_child(advanced)
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
	_refresh_completed_units(me)
	actions.refresh(me)
	var finished := state.is_over() and not state.collapse_pending()
	_end.text = "🔄 再来一局（新的星图）" if finished else "⏭️ 结束回合"
	_end.disabled = main.saves.busy or (state.is_over() and not finished) or (main.debug != null and (main.debug.replaying() or main.debug.seeking))

	_refresh_resources(me)
	_res_values["actions"].text = "%d / %d" % [me.actions_left, me.action_points(state.map)]
	_res_values["actions"].get_parent().get_parent().tooltip_text = "行动点：剩余 / 每回合。所有维度每文明每回合固定 %d 点，未用完不结转。" % me.action_points(state.map)
	_res_values["actions"].add_theme_color_override("font_color",
			Color(1.0, 0.5, 0.4) if me.actions_left <= 0 else Color.WHITE)

	_refresh_tech_tiles(me)
	advanced.refresh(me)
	_refresh_build_tiles(me)
	var stats := _stats(me)
	for key in stats:
		_stat_values[key].text = stats[key]


func _refresh_resources(me: Civ) -> void:
	var forecast := Knowledge.economy_preview(state,me)
	for i in 2:
		var key: String = ["energy","mineral"][i]
		var unit: String = ["E","M"][i]
		var stock: float = [me.energy,me.mineral][i]
		var value := _res_values[key]
		value.text = "%s  %s" % [Widgets.number(stock),Widgets.signed_number(forecast["net"][i])]
		var tip := "可用%s：%s%s\n下回合总收入约 %s%s，维护约 %s%s，预计净变化 %s%s。\n进行中工程已预付 %s%s，已从余额扣除，不会再次收费。\n本地弹药预留 %s%s，已从余额扣除。" % [
			"能量" if i==0 else "矿石",Widgets.number(stock),unit,Widgets.number(forecast["gross"][i]),unit,Widgets.number(forecast["upkeep"][i]),unit,Widgets.signed_number(forecast["net"][i]),unit,Widgets.number(forecast["prepaid"][i]),unit,Widgets.number(forecast["ammo"][i]),unit]
		if forecast["remote_ammo"]:
			tip += "\n远方舰船的弹药情况等待回报。"
		tip += "\n按当前已知情况估算；远端变动、途中事件与新工程完工可能改变实际收支。"
		value.get_parent().get_parent().tooltip_text = tip


## 延续原版建造后自动选中单位的操作；只消费实际收到的完工报告和遥测。
func _refresh_completed_units(me: Civ) -> void:
	if _build_state!=state:
		_build_state=state
		_build_orders.clear()
	for id in _build_orders.keys():
		if _build_orders[id]!=state.civs.find(me):
			continue
		var report: Dictionary=me.order_reports.get(id,{})
		if report.get("status","") in ["failed","cancelled","destroyed"]:
			_build_orders.erase(id)
		elif report.get("status","")=="completed":
			var ship:=Signals.reported_ship(state,me,report.get("result_ship",-1))
			if ship!=null:
				actions.select_unit(ship)
				_build_orders.erase(id)


## 星系会增减（殖民、被打掉），每次刷新时重建发射源列表，尽量保持原来的选择。
func _refresh_origins(me: Civ) -> void:
	var previous := _origin_pick.get_item_text(_origin_pick.selected) if _origin_pick.selected >= 0 else ""
	_origin_pick.clear()
	for c in Knowledge.colonies(state,me):
		_origin_pick.add_item("%s %s" % ["母星" if c == me.home else "殖民地", c])
	var ss := state.reported_starship(me)
	if ss != null:
		_origin_pick.add_item("星舰 %s" % ss.cell())
	for i in _origin_pick.item_count:
		if _origin_pick.get_item_text(i) == previous:
			_origin_pick.select(i)


## 选中的发射源（建造建在这里，光粒、广播、二向箔从这里出发）。
func selected_origin() -> Vector3i:
	var me: Civ = main.viewed()
	var origins := Knowledge.origins(state,me)
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
		_tier_labels[tier].tooltip_text = "先完成相应探索或战斗条件，再让每年收入扣除维护后达到要求。产能门槛按三维产量计算；达标后永久开放。"
		_tier_labels[tier].add_theme_color_override("font_color",
				Color(0.6, 0.8, 1.0) if open else Color(0.6, 0.6, 0.65))
	for kind in _upgrade_tiles:
		var tile := _upgrade_tiles[kind]
		var reason := state.upgrade_error(me, kind, selected_origin())
		tile.disabled = reason != ""
		tile.set_meta("disabled_reason",reason)
		tile.modulate.a = 1.0 if reason == "" else 0.5
		var level := "%d/%d" % ([me.telescope, Balance.TELESCOPE_MAX] if kind == "telescope"
				else [maxi(0,Knowledge.site(state,me,selected_origin()).get("warning",-1)), Balance.WARNING_MAX])
		if kind=="warning" and Knowledge.site(state,me,selected_origin()).get("warning",-1)<0:
			level="未建造"
		var price := state.upgrade_price(me, kind, selected_origin())
		Widgets.set_tile_cost(tile, "%s　%s" % [level, Widgets.cost_text(Vector2i(price[0], price[1]))])
		var what := "视野半径和探测器圆锥长度 +%.1f 格，圆锥张角 +%.0f°。" % [Balance.TELESCOPE_STEP,
				Balance.TELESCOPE_ANGLE_STEP] if kind == "telescope" else "预警范围 +1 格。"
		tile.tooltip_text = "%s\n全额支付并完成工作量后生效。%s" % [what, "\n\n现在不能升级：" + reason if reason != "" else ""]


## 建造页：每个按钮的价格、能不能建，以及自身降维的说明。
func _refresh_build_tiles(me: Civ) -> void:
	var at := selected_origin()
	var host := state.construction_host(me,at)
	var orders := state.construction_orders(me,at,host)
	var capacity := state.construction_capacity(me,at,host)
	_build_hint.text = "建造槽 %d / %d 已占用；研究另占独立队列。每单花 1 行动点并预付资源，各项同时按原速度施工；造好单位后到「行动」页派出。" % [orders.size(),capacity]
	_build_hint.tooltip_text = "起始母星 %d 槽，殖民星系和独立星舰各 %d 槽。同格星舰使用星系槽，不能额外增加容量。送出的订单及待回报工程仍占槽；收到该订单的完工或取消回报后释放。" % [Balance.HOME_BUILD_SLOTS,Balance.BUILD_SLOTS]
	var progress: Array[String] = []
	for order in orders:
		var observed := "观测 %s 年 · 收到 %s 年" % [Widgets.number(order["t_observed"]),Widgets.number(order["t_received"])] if order.has("t_observed") and order.has("t_received") else "等待进度回报"
		progress.append("#%d %s：%s，进度 %s / %s；%s；收到完工回报后释放本单槽位。" % [order["id"],Widgets.order_name(order["kind"]),Widgets.order_status(order.get("status","")),Widgets.number(WorkOrder.amount(order["done"])),Widgets.number(WorkOrder.amount(order["work"])),observed])
	_build_progress.text="\n".join(progress)
	_build_progress.visible=not progress.is_empty()
	for kind in BUILD_ORDER:
		var tile := _build_tiles[kind]
		var reason := state.build_error(me, kind, at,advanced.selected_modules(kind))
		tile.disabled = reason != ""
		tile.set_meta("disabled_reason",reason)
		tile.modulate.a = 1.0 if reason == "" else 0.5
		var cost := state.build_cost(me, kind,advanced.selected_modules(kind))
		Widgets.set_tile_cost(tile, Widgets.cost_text(Vector2i(cost[0], cost[1])))
		tile.tooltip_text = "%s %s\n%s%s" % [BUILD_ICONS[kind], GameState.BUILD_NAMES[kind], _build_desc(kind),
				"\n\n现在不能建：" + reason if reason != "" else ""]
	var reduce := _build_tiles["reduce"]
	var reason:=advanced.prepare_error(me)
	reduce.disabled=reason!=""
	reduce.set_meta("disabled_reason",reason)
	reduce.modulate.a=1.0 if reason=="" else 0.5
	var quote:=advanced.quote()
	Widgets.set_tile_cost(reduce,V01Controls.price(quote["cost"]))
	reduce.tooltip_text="让下方选中的星系、设施和舰船准备进入更低维空间。下单后名单不能更改。"+("\n"+reason if reason!="" else "")
	_reduce_info.text="携带 %d 项 · %s · 正常准备需 %.1f 年\n转换时保留 %.0f%% 库存；远端准备情况须等消息传回。"%[advanced.roster().size(),V01Controls.price(quote["cost"]),quote["work"],quote["fraction"]*100.0]



## 「情况」页的数值。
func _stats(me: Civ) -> Dictionary:
	var visible:=Knowledge.presentation(state,me)
	me=visible.civs[state.civs.find(me)]
	var at := selected_origin()
	var units: Array[String] = []
	for kind in Ship.NAMES:
		var n := me.count(kind)
		if n > 0:
			units.append("%s %d" % [Ship.NAMES[kind], n])
	var building: Array[String] = []
	for p in OrderControl.visible(visible,me):
		var label: String=GameState.BUILD_NAMES.get(p["kind"],Tech.title(p["kind"]) if Tech.ALL.has(p["kind"]) else p["kind"])
		building.append("%s %s/%s"%[label,Widgets.number(WorkOrder.amount(p["done"])),Widgets.number(WorkOrder.amount(p["work"]))])
	var latest:=0.0
	for intel in me.intel.values():
		latest=maxf(latest,intel.get("t_observed",0.0))
	var weapons: Array[String] = []
	for ship in me.ships:
		for weapon in ship.weapons:
			var label:=Tech.title(weapon)
			if not weapons.has(label):
				weapons.append(label)
	var dims:={1:0,2:0,3:0}
	for asset in me.assets:
		dims[asset["entity_dim"]]=dims.get(asset["entity_dim"],0)+1
	for ship in me.ships:
		dims[ship.entity_dim]=dims.get(ship.entity_dim,0)+1
	return {
		"星系": "%d 个　采矿船 %d　掩体 %d" % [me.colonies.size(), me.miner_count(), me.bunkers.size()],
		"发射源": "%s　类地 %d　类木 %d" % [at, visible.map.rocky.get(at, 0), visible.map.gas.get(at, 0)],
		"恒星": "%d 颗　戴森球 %d" % [me.star_total(visible.map), me.dyson_count()],
		"视野": "母星 %.1f 格　望远镜 %d 级" % [visible.sphere_radius(me, Balance.VISION_HOME), me.telescope],
		"单位": "、".join(units) if not units.is_empty() else "无",
		"建造中": "、".join(building) if not building.is_empty() else "无",
		"存货": "光粒 %d　反物质 %d/%d" % [me.grains.size(), me.antimatter, Balance.MAX_ANTIMATTER],
		"预警系统": ("范围 %.0f 格" % me.warning_range()) if me.has_warning else "无",
		"广播器": "%d 个%s" % [me.broadcasters.size(), "　引力波广播" if me.has_tech("gravity") else ""],
		"情报": "已知敌方星系 %d　看过 %d 格\n最近观测 %.2f 年；远端均为回报值" % [me.known.size(), me.intel.size(), latest],
		"战舰武器": "、".join(weapons) if not weapons.is_empty() else "无",
		"智子": "已知 %d 艘；侦察回报需传回" % me.count(Ship.SOPHON),
		"被打": "%d 次" % me.times_hit,
		"降维": "已知星系、设施和舰船：三维 %d　二维 %d　一维 %d" % [dims[3],dims[2],dims[1]],
		"黑域": "光速为 0 的中心 %d 个%s" % [visible.black_domains.size(),
				"　你的准备中 %d 个" % me.pending_domains.size() if not me.pending_domains.is_empty() else ""],
	}


# ---------- 说明文字 ----------

## 每种建造的说明。
func _build_desc(kind: String) -> String:
	var descriptions := {
		"probe":"化学探测器；从行动页派出，按光速传回前方观测。",
		"nuclear_probe":"核脉冲探测器；单独制造，不自动替换化学探测器。",
		"warship":"基础舰体不带武器。可在下方选装；每年最多开火一次，年初预留弹药资源，未发射则返还。",
		"sophon":"快速侦察单位；传感消息仍需返回，不会直接冻结对方研究。",
		"colony":"从行动页选择目的地。抵达可殖民星系后停船，再选择「建立殖民地」并支付建设费。",
		"starship":"可以移动的家园和船坞；整局最多建成一艘。只要星舰还在，文明就能存续；维护不足时只能进行救援建设。",
		"wandering_earth":"把原母星改造成可移动家园；带走下方选定的类地行星与设施。恒星和戴森球留在原地。",
		"devourer":"停在无主类地行星时，每年最多吞食一颗并获得能量；降维后收入减少。",
		"droplet":"接触攻击后暂停一年；停驻恒星可阻止当地发出新广播。",
		"grain":"每星系存放一颗。发射后沿方向飞行，命中航线上的恒星。",
		"antimatter":"制造一枚反物质炸弹；使用另耗行动点。命中伤害按物理防御结算。",
		"dimension_weapon":"制造一枚降维武器：三维发射二向箔，二维发射单向著，一维发射奇异点。途中可被拦截，抵达并激活后开始影响空间。",
		"miner":"本星系需要类地行星；造好后每年产矿。高级型号解锁后仍可选择基础型号。",
		"advanced_miner":"先研究「小行星带开采」，本星系还需类地行星；已有基础采矿船也可以逐艘改装升级。",
		"dyson":"每颗本地恒星最多一座；降维后发电量减少，但维护费不变。",
		"bunker":"需要类木行星；恒星被光粒击毁后保留当地人员，不能免疫常规压制。",
		"broadcaster":"发送与接收坐标广播。水滴的当地封锁仅阻止新广播，已发出的波继续传播。",
		"warning":"每星系单独建造与升级；预警报告包含观测时刻，不能即时掌握远方战况。",
		"landing":"运输船抵达后建立殖民地；完工后运输船成为殖民地的一部分，不再作为舰船存在。"
	}
	var cost: Array=Construction.cost(kind)
	var upkeep: Array=Construction.upkeep(kind)
	var speed := Widgets.ship_speed_tip(kind)
	return descriptions.get(kind,"")+("\n"+speed if speed!="" else "")+"\n基础价格 %sE + %sM；正常工期 %s 年；每年维护 %sE + %sM。\n选装会增加费用和工期；一维施工及维护不足时会变慢，远程通信时间另计。" % [Widgets.number(cost[0]),Widgets.number(cost[1]),Widgets.number(Construction.work(kind)),Widgets.number(upkeep[0]),Widgets.number(upkeep[1])]


## 每项科技的说明。
func _tech_desc(id: String) -> String:
	match id:
		"miner": return "建造基础采矿船，每艘在三维空间每年产出 2M，降维后产量减少。"
		"fission": return "用类地行星发电，每颗在三维空间每年产出 1E，降维后产量减少。"
		"telescope": return "升级太空望远镜，扩大视野和探测器圆锥；最多 3 级。"
		"probe": return "建造化学探测器。\n"+Widgets.ship_speed_tip(Ship.PROBE)
		"warship": return "建造恒星级战舰的基础舰体；武器与防御装备可在建造页另行选装并付费。"
		"broadcaster": return "建造恒星广播台，发送与接收坐标广播。"
		"warning": return "建造本星系预警系统，初始半径 2 光年，可升 3 级。"
		"mining_advanced": return "建造高级采矿船，在三维空间每艘每年产出 4M；已有基础采矿船可逐艘改装。"
		"fusion": return "每颗自有恒星在三维空间每年产出 3E，降维后产量减少；派遣舰船的能耗降低 1E。"
		"interstellar_probe": return "建造核脉冲探测器，仍需单独制造。\n"+Widgets.ship_speed_tip(Ship.NUCLEAR_PROBE)
		"railgun": return "可选电磁炮模块：射程 0.1 光年，1 物理伤害，每发 1M。"
		"beam": return "可选粒子束模块：射程 0.5 光年，2 能量伤害，每发 2E。"
		"alloy": return "可选合金装甲：战舰最大生命 3；物理伤害有 50% 概率减少 1。"
		"bunker": return "建造掩体，需要气态巨行星；掩体不阻止常规压制。"
		"interstellar_travel": return "可以建造运输船，带它前往其他星系；建立殖民地还需研究「星际殖民」。也是研究星舰的前置。\n"+Widgets.ship_speed_tip(Ship.COLONY)
		"devourer": return "建造吞噬者，每年最多吞食一颗无主类地行星；三维获得 25E，二维 15E，一维 9E。\n"+Widgets.ship_speed_tip(Ship.DEVOURER)
		"antimatter_collection": return "当前侦察范围覆盖的每个星系，在三维空间每年产出 1E；重叠不重复计算。派遣舰船的能耗再降低 2E。"
		"gravity_scan": return "方向性扫描，8 光年长、1 光年半径；8E，冷却 10 年，回波按光速传播。"
		"hbomb": return "可选氢弹模块：射程 0.2 光年，每发 6E；清除人员并回收目标实际已付的船体与模块资源。"
		"torpedo": return "可选鱼雷模块：射程 1 光年，3 物理伤害，每发 1E + 2M。"
		"shield": return "可选护盾：战舰最大生命 5；50% 概率免疫能量伤害，连续 5 年未受击后修复 1。"
		"antimatter": return "生产反物质炸弹，最多 3 枚；使用消耗 1 行动点，造成 4 物理伤害。"
		"gravity": return "可选引力波广播装备；每次广播花 5E，消息按当地光速传播。"
		"colony": return "运输船抵达无主宜居星系后，花 3E + 4M 建立殖民地，正常施工需 4 年；完工后消耗这艘运输船。"
		"starship": return "建造能移动、能制造舰船的家园。整局最多建成 1 艘，每年维护 1E + 1M。"
		"dyson": return "每颗恒星可建一座；三维空间每年发电 10E，降维后减少；每年维护 0.5M。"
		"sophon": return "建造智子；用于侦察，不再直接锁死对手研究。"
		"droplet": return "建造水滴，接触造成 5 物理伤害；持续接触只命中一次，命中后暂停 1 年。"
		"grain": return "生产光粒；以 0.99 倍背景光速飞行，摧毁目标恒星。"
		"warp": return "可选曲率模块；战舰、运输船、星舰、吞噬者在自有视野外可达背景光速。"
		"wandering_earth": return "把原母星改造成可移动的家园，生命值 30；选定携带的行星与设施，需要没有存活星舰。"
		"dark_energy": return "当前侦察范围内没有恒星的星系，在三维空间额外每年产出 3E；派遣舰船不再消耗能量。"
		"dimension": return "制造降维武器，并让选中的星系、设施和舰船准备进入低维空间；准备完成后仍需等消息传回再执行。"
		"domain": return "释放有限寿命的局部黑域，消耗 48E + 12M、冷却 20 年。"
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
		r = advanced.prepare()
	elif kind=="wandering_earth":
		r=state.start_earth(me,advanced.earth_ids(),advanced.earth_rocky())
	else:
		r = state.build(me, kind, selected_origin(),advanced.selected_modules(kind))
	var name: String = "自身降维" if kind == "reduce" else GameState.BUILD_NAMES[kind]
	set_feedback("无法执行「%s」：%s" % [name, r["error"]] if r["error"] != "" else "已发送「%s」建造命令；资源已预付，进度见建造页。" % name)
	if r["error"]=="" and r.has("order") and kind in GameState.UNITS:
		_build_orders[r["order"]]=state.civs.find(me)
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
	var r := state.upgrade(main.viewed(), kind, selected_origin())
	set_feedback("无法升级：%s" % r["error"] if r["error"] != "" else "")
	main.refresh()
