class_name GameState
extends RefCounted
## 一局游戏的全部规则状态。画面只读取它，通过它的方法来行动。
## 日志只写玩家应该知道的事：自己的行动、自己被打、有文明灭亡。
## AI 怎么行动在 ai.gd。

## 发射源参数的默认值，表示「用母星系」。
const AT_HOME := Vector3i(-1, -1, -1)
const NO_HIT := Vector3i(-1, -1, -1)
## 「为什么不能做」检查（xxx_error）的目标参数用它时，只检查和目标无关的条件。
## 画面在玩家还没选目标时用，比如给没选中的行动按钮标上能不能用。
const ANY_TARGET := Vector3i(-2, -2, -2)
## 情报传不回母星系时（路上光速几乎为 0）的「到达回合」
const NEVER := 1 << 30
## 会造在星系里、下一回合建好的设施
const FACILITIES := ["miner", "dyson", "bunker", "broadcaster", "warning"]
## 造好后马上存在星系里的东西
const STORED := ["antimatter", "grain"]
## 造好后停在星系里、要另外派出的单位
const UNITS := ["probe", "warship", "colony", "starship", "devourer", "sophon"]
const BUILD_NAMES := {"miner": "采矿船", "dyson": "戴森球", "bunker": "掩体", "broadcaster": "恒星广播器",
		"warning": "预警系统", "antimatter": "反物质", "grain": "光粒", "probe": "探测器", "warship": "恒星级战舰",
		"colony": "殖民船", "starship": "星舰", "devourer": "吞噬者", "sophon": "智子"}
## 每种建造要哪项科技
const BUILD_TECH := {"miner": "miner", "dyson": "dyson", "bunker": "bunker", "broadcaster": "broadcaster",
		"warning": "warning", "antimatter": "antimatter", "grain": "grain", "probe": "probe", "warship": "warship",
		"colony": "colony", "starship": "starship", "devourer": "devourer", "sophon": "sophon"}
## 智子看到被锁的文明做了什么时，日志里怎么写（只写给玩家看）
const SOPHON_REPORTS := {"dispatch": "派出了一个单位", "turn_ship": "让舰船转向", "send_colony": "派殖民船去 %s",
		"move_starship": "让星舰飞向 %s", "settle_starship": "用星舰建立了星系", "launch_grain": "发射了光粒",
		"use_antimatter": "用了反物质", "broadcast": "广播了 %s", "launch_foil": "准备发射二向箔，目标 %s",
		"launch_line_foil": "准备发射单向著，目标 %s", "launch_black_domain": "投放黑域，位置 %s",
		"start_reduce": "开始自身降维", "launch_singularity": "发射了奇异点", "send_sophon": "派智子去 %s",
		"upgrade": "升级了射电望远镜或预警范围"}

var map: StarMap
var civs: Array[Civ] = []
var turn := 1
var log_lines: Array[String] = []
## 结束时为「你」「AI」「无」（都灭亡了）或「平局」；观战模式下是赢家的名字。进行中为空。
var winner := ""
var rng := RandomNumberGenerator.new()
## 观战模式（平衡模拟用）：所有文明都由 AI 控制，打到只剩一个文明才结束。
## 开启后要把 human().is_ai 也设为 true。
var spectator := false
## 玩家灭亡后对局不结束，其余文明接着打到分出胜负（调试时用来看后面的发展）。
var play_on_after_death := false
## 有星系的格子（生成时有恒星的；星系被压到平面上时跟着改）
var system_cells: Array[Vector3i] = []
## 被二向箔压平的格子：键是格子坐标，值是它被压到的平面所在的高度 z。所有文明都看得到。
var flattened: Dictionary[Vector3i, int] = {}
## 生效的黑域中心：每项是 {"center": 中心坐标, "left": 光速还保持 0 几个回合}。所有文明都看得到。
var black_domains: Array[Dictionary] = []
## 每格的光速（G14），下标见 _li。还没出现过黑域时为空，表示处处都是 1.0。
var light := PackedFloat64Array()
## 光速还在变（有黑域中心，或者还没扩散均匀）。不变时不用每回合重算。
var _light_moving := false
## 隐藏文明的位置，在星图外面。它们看不见、打不到，只对广播做出反应。
var hidden: Array[Vector3i] = []
## 听到了广播、还在考虑要不要出手的隐藏文明：每项是 {"from": 隐藏文明的位置, "target": 被广播的坐标, "left": 还会等几回合}
var hidden_listen: Array[Dictionary] = []
## 隐藏文明发出的光粒和二向箔
var hidden_ships: Array[Ship] = []
var hidden_foils: Array[Foil] = []
## 正在扩散的广播：每项是 {"from": 广播者的位置, "target": 被广播的坐标, "sender": 广播的文明,
## "exposed": 暴露的广播者星系（没暴露时为 NO_HIT）, "radius": 传到多远了, "heard": 听到过的文明, "hidden_heard": 听到过的隐藏文明}
var broadcasts: Array[Dictionary] = []
## 航迹：每项是 {"a": 起点, "b": 终点, "turn": 第几回合留下, "gone": 被降维抹掉了}
var wakes: Array[Dictionary] = []
## 展开的二向箔：每项是 {"center": 展开的格子, "age": 压平的圆的半径（每回合加 FOIL_SPREAD）}
var foil_zones: Array[Dictionary] = []
## 第一片二向箔确定全图共同平面，后续展开不会再产生不同高度的平面。
var flat_plane := -1
## 二维格子压到共同直线的 y；z 始终为 flat_plane，直线沿 x 轴。
var linearized: Dictionary[Vector3i, int] = {}
var line_zones: Array[Dictionary] = []
var line_y := -1
## 全图压成直线以后过了几回合
var line_turns := 0
## 先完成奇异点、降到零维的文明
var zero_winner: Civ = null
## 测速用（平衡模拟的 PROFILE=1）：打开后把回合里每一步花的微秒数累加到 profile 里
var profiling := false
var profile: Dictionary[String, int] = {}
## 回合末所有文明看一遍时用的临时数据，看完就清空（见 _begin_view_cache）
var _view_cache: Dictionary = {}

## 一轮空间坍缩完整结算后再判断胜负。
var _collapse_depth := 0
var _next_id := 1

## 开局用的种子和 AI 个数（回放时用同样的值重新开局）
var seed_value := 0
var ai_count := 0
## 结束过几次回合（游戏结束后不再增加）
var steps := 0
## 每次结束回合后的校验值，checksums[i] 是第 i + 1 次结束回合后的
var checksums: Array[int] = []
## 所有文明做成的每一次操作，按发生顺序：
## {"step": 第几次结束回合之前, "civ": 文明序号, "ai": 是不是 AI 做的, "name": 操作函数名, "args": 参数}
## 调试面板用它显示 AI 做了什么；回放时把不是 AI 做的操作按顺序重做一遍。
var history: Array[Dictionary] = []
## 开局时 balance.gd 的数值（回放从这些数值开始，中途改的数值在 history 里）
var start_balance := {}
## 用调试功能改过数值。以后做成绩、成就时，这样的对局不算。
var dev_used := false


## 第一个文明是人类玩家，其余是 AI。母星优先放在宜居星系上。
static func new_game(seed_value: int, ai_count: int = Balance.AI_COUNT) -> GameState:
	var s := GameState.new()
	s.seed_value = seed_value
	s.ai_count = ai_count
	s.start_balance = Replay.balance_values()
	s.map = StarMap.generate(seed_value)
	s.rng.seed = seed_value + 1
	for c in s.map.stars:
		if s.map.stars[c] != StarMap.Star.NONE:
			s.system_cells.append(c)

	var candidates: Array[Vector3i] = []
	for c in s.map.habitable:
		candidates.append(c)
	if candidates.size() < ai_count + 1:
		for c in s.system_cells:
			if not candidates.has(c):
				candidates.append(c)
	var homes := s._pick_homes(candidates, ai_count + 1)

	s.civs.append(Civ.new("你", false, homes[0]))
	for i in ai_count:
		var ai := Civ.new("AI-%d" % (i + 1), true, homes[i + 1])
		for id in Tech.ALL:
			ai.taste[id] = s.rng.randf_range(0.0, 3.0)
		s.civs.append(ai)
	# 隐藏文明放在星图外面 1～3 格的地方
	var lo := -3
	var hi := StarMap.SIZE + 2
	while s.hidden.size() < Balance.HIDDEN_COUNT:
		var c := Vector3i(s.rng.randi_range(lo, hi), s.rng.randi_range(lo, hi), s.rng.randi_range(lo, hi))
		if not StarMap.in_bounds(c) and not s.hidden.has(c):
			s.hidden.append(c)
	for civ in s.civs:
		s._observe(civ)
		s.start_turn(civ)
	return s


## 挑 n 个母星系，彼此至少隔开 HOME_MIN_DISTANCE 格（F3.1）。
## 打乱候选、依次挑离已挑的都够远的；挑不够就重新打乱再试，试多次还不够就把距离减 1 格。
func _pick_homes(candidates: Array[Vector3i], n: int) -> Array[Vector3i]:
	var gap := Balance.HOME_MIN_DISTANCE
	while true:
		for attempt in 30:
			# 自己洗牌，不用全局随机数，保证同一个种子结果相同
			for i in range(candidates.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp := candidates[i]
				candidates[i] = candidates[j]
				candidates[j] = tmp
			var picked: Array[Vector3i] = []
			for c in candidates:
				var far := true
				for h in picked:
					if Vector3(c).distance_to(Vector3(h)) < gap:
						far = false
						break
				if far:
					picked.append(c)
					if picked.size() == n:
						return picked
		gap -= 1.0
	return []


func human() -> Civ:
	return civs[0]


func is_over() -> bool:
	return winner != ""


## 哪个活着的文明拥有这个格子，没有则返回 null。
func coord_owner(c: Vector3i) -> Civ:
	for civ in civs:
		if civ.alive and civ.owns(c):
			return civ
	return null


## 单位的主人（隐藏文明的光粒返回 null）。
func ship_owner(s: Ship) -> Civ:
	for civ in civs:
		if civ.ships.has(s):
			return civ
	return null


func start_turn(civ: Civ) -> void:
	civ.actions_left = civ.action_points(map)


func next_id() -> int:
	_next_id += 1
	return _next_id - 1


## 让 AI 接管（或交还）一个文明。玩家的这个选择也记进 history，回放时同样重做。
func set_autoplay(civ: Civ, on: bool) -> Dictionary:
	if civ.is_ai == on:
		return {"error": ""}
	civ.is_ai = on
	history.append({"step": steps, "civ": civs.find(civ), "ai": false, "name": "set_autoplay", "args": [on]})
	return {"error": ""}


## 打开或关掉「玩家灭亡后接着打」。也记进 history，回放时同样重做。
func set_play_on_after_death(on: bool) -> Dictionary:
	if play_on_after_death == on:
		return {"error": ""}
	play_on_after_death = on
	history.append({"step": steps, "civ": -1, "ai": false, "name": "set_play_on_after_death", "args": [on]})
	return {"error": ""}


func _record(civ: Civ, name: String, args: Array) -> void:
	history.append({"step": steps, "civ": civs.find(civ), "ai": civ.is_ai, "name": name, "args": args})
	_sophon_report(civ, name, args)


## 玩家的智子锁着这个文明：它做的每件事都写进玩家的日志（D5）。
func _sophon_report(civ: Civ, name: String, args: Array) -> void:
	if civ == human() or not watched_by(civ).has(human()):
		return
	var what := ""
	match name:
		"research": what = "升级了科技 %s" % Tech.title(args[0])
		"build": what = "在 %s 造%s" % [args[1], BUILD_NAMES[args[0]]]
		_:
			what = SOPHON_REPORTS.get(name, name)
			if what.contains("%s"):
				what = what % [args[0]]
	add_log("智子报告：%s %s" % [civ.name, what])


## AI 写下为什么这样做（只给调试面板看，回放时不用）。同一回合里一样的话只记一次。
func ai_note(civ: Civ, text: String) -> void:
	var idx := civs.find(civ)
	for i in range(history.size() - 1, -1, -1):
		var h := history[i]
		if h["step"] != steps:
			break
		if h["civ"] == idx and h["name"] == "note" and h["args"][0] == text:
			return
	history.append({"step": steps, "civ": civs.find(civ), "ai": true, "name": "note", "args": [text]})


# ---------- 调试：随时改数值 ----------
# 都记进 history（算玩家的操作），回放时同样重做，改过数值的对局也能原样重现。

## 改 balance.gd 里的一个数值（全局有效，直到再改回来或者重新开局）。
func dev_balance(name: String, value: Variant) -> Dictionary:
	var script: Script = load("res://rules/balance.gd")
	var old = script.get(name)
	if old == null:
		return {"error": "balance.gd 里没有 %s" % name}
	if typeof(old) != typeof(value) and not (old is float and value is int):
		return {"error": "%s 的类型不对" % name}
	if old is Array:
		old.assign(value)
	else:
		script.set(name, float(value) if old is float else value)
	_dev_record(-1, "dev_balance", [name, value])
	return {"error": ""}


## 改一个文明的属性（能量、矿石、行动点、望远镜等级、是否由 AI 控制以外的任何数值或开关）。
func dev_set(civ: Civ, field: String, value: Variant) -> Dictionary:
	if not field in civ or field == "is_ai":
		return {"error": "文明没有 %s 这一项" % field}
	var old = civ.get(field)
	if typeof(old) != typeof(value) and not (old is float and value is int):
		return {"error": "%s 的类型不对" % field}
	civ.set(field, float(value) if old is float else value)
	_dev_record(civs.find(civ), "dev_set", [field, value])
	return {"error": ""}


## 直接给一个文明加上（或拿掉）一项科技，不花资源。
func dev_tech(civ: Civ, id: String, on: bool) -> Dictionary:
	if not Tech.ALL.has(id):
		return {"error": "没有这项科技"}
	if on:
		civ.techs[id] = true
	else:
		civ.techs.erase(id)
	_dev_record(civs.find(civ), "dev_tech", [id, on])
	return {"error": ""}


func _dev_record(civ_index: int, name: String, args: Array) -> void:
	dev_used = true
	history.append({"step": steps, "civ": civ_index, "ai": false, "name": name, "args": args})


## 当前局面的校验值：两次计算出的局面一样，校验值就一样。只取主要的数据，够发现回放走偏就行。
func checksum() -> int:
	var parts: Array = [turn, winner, steps, _next_id, flattened.size(), linearized.size(), rng.state]
	for civ in civs:
		parts.append([civ.alive, civ.energy, civ.mineral, civ.actions_left, civ.colonies, civ.techs.keys(),
				civ.known.keys(), civ.antimatter, civ.foils.size(), civ.tier1_turn, civ.tier2_turn, civ.tier3_turn])
		for sh in civ.ships:
			parts.append([sh.id, sh.kind, sh.pos, sh.docked, sh.direction, sh.damage, sh.lock])
	return hash(parts)


## 玩家结束回合：AI 依次行动，然后所有东西移动、交战、扩散，情报传回，结算产出，进入下一回合。
## 每结束一回合记一个校验值，回放时用来检查重算的结果和原来一样。
func end_turn() -> void:
	if is_over():
		advance_collapse()
		return
	var t := Time.get_ticks_usec()
	_end_turn()
	t = Time.get_ticks_usec()
	steps += 1
	checksums.append(checksum())
	_lap("校验值", t)


func _end_turn() -> void:
	var t := Time.get_ticks_usec()
	for civ in civs:
		if civ.is_ai and civ.alive and not is_over():
			AI.take_turn(self, civ)
	t = _lap("AI 行动", t)
	if is_over():
		_clean_dead()
		return
	_move_all_ships()
	t = _lap("移动", t)
	_combat()
	t = _lap("交战", t)
	# 先扩散已有的压平区域，再让二向箔前进；这一回合新展开的，下一回合才扩散
	_spread_flat()
	for civ in civs:
		if civ.alive and not is_over():
			civ.foils = _advance_foil_list(civ.foils, civ)
	hidden_foils = _advance_foil_list(hidden_foils, null)
	t = _lap("二向箔和压平", t)
	_tick_domains()
	for civ in civs:
		if civ.alive:
			_advance_domains(civ)
	_check_hiding()
	t = _lap("黑域和光速", t)
	_spread_broadcasts()
	_hidden_strikes()
	t = _lap("广播和隐藏文明", t)
	_clean_dead()
	if is_over():
		return
	_begin_view_cache()
	for civ in civs:
		if civ.alive:
			_observe(civ)
			t = _lap("视野", t)
			_deliver_reports(civ)
			t = _lap("情报传回", t)
			_warn(civ)
			t = _lap("预警", t)
		else:
			_expire_intel(civ)
	_view_cache = {}
	for civ in civs:
		if not civ.alive:
			continue
		_finish_pending(civ)
		_advance_reduce(civ)
		_advance_singularity(civ)
		var income := energy_income(civ)
		civ.energy += income
		civ.mineral += mineral_income(civ)
		if income >= Balance.TIER3_ENERGY:
			_reach_tier(civ, 3, "能量收入达到 %dE" % Balance.TIER3_ENERGY)
		if civ.is_ai and rng.randf() < Balance.TECH_BURST_CHANCE:
			_tech_burst(civ)
		start_turn(civ)
	if all_linear():
		line_turns += 1
		_check_winner()
	_lap("收入和其他", t)
	turn += 1
	add_log("第 %d 回合开始" % turn)
	var me := human()
	for tier in [1, 2, 3]:
		if me != null and me.alive and me.tier_turn(tier) == turn:
			add_log("可以升级 %s科技" % Tech.TIER_NAMES[tier])


## 测速：把从 since 到现在的时间记到 what 上，返回现在的时间。
func _lap(what: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if profiling:
		profile[what] = profile.get(what, 0) + now - since
	return now


# ---------- 科技 ----------

## 这一级现在能不能升级。
func tier_open(civ: Civ, tier: int) -> bool:
	var at := civ.tier_turn(tier)
	return at >= 0 and turn >= at


## 达到第 tier 级的条件（E8）。三级按顺序来：上一级已经开放时才算，被智子锁着时不算（D5）。
## 条件是回合结束时算的，最早下一回合开放；II、III 级还要比上一级晚 TIER_GAP 回合，中间先发展一段时间。
func _reach_tier(civ: Civ, tier: int, what: String) -> void:
	if civ.tier_turn(tier) >= 0 or not tier_open(civ, tier - 1) or sophon_tier_left(civ) > 0:
		return
	var at := turn + 1
	if tier >= 2:
		at = maxi(at, civ.tier_turn(tier - 1) + Balance.TIER_GAP)
	civ.set_tier_turn(tier, at)
	if not civ.is_ai:
		add_log("%s：%s第 %d 回合开放" % [what, Tech.TIER_NAMES[tier], at])


## 发现别人（看到别人的星系或舰船、听到广播）：I 级的条件。
func _discover(civ: Civ, what: String) -> void:
	civ.discovered = true
	_reach_tier(civ, 1, what)


## 为什么不能升级这项科技（能升级时为空）。
func research_error(civ: Civ, id: String) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not Tech.ALL.has(id):
		return "没有这项科技"
	if civ.has_tech(id):
		return "已经有了"
	var tier := Tech.tier(id)
	if not tier_open(civ, tier):
		if civ.tier_turn(tier) >= 0:
			return "%s第 %d 回合开放" % [Tech.TIER_NAMES[tier], civ.tier_turn(tier)]
		return "%s要%s才能升级" % [Tech.TIER_NAMES[tier], Tech.TIER_RULES[tier]]
	for need in Tech.ALL[id]["needs"]:
		if not civ.has_tech(need):
			return "要先有「%s」" % Tech.ALL[need]["name"]
	if not civ.colonies.is_empty() and in_black_domain(civ.home):
		return "母星系躲在黑域里，不能升级科技"
	if sophon_research_left(civ) > 0:
		return "被智子锁住，还要 %d 回合才能升级科技" % sophon_research_left(civ)
	var cost := Tech.cost(id)
	if civ.energy < cost[0]:
		return "能量不足"
	if civ.mineral < cost[1]:
		return "矿石不足"
	return ""


## 升级一项科技：花资源，不花行动点，马上生效（T15）。返回 {"error": 出错原因，成功时为空}。
func research(civ: Civ, id: String) -> Dictionary:
	var error := research_error(civ, id)
	if error != "":
		return {"error": error}
	var cost := Tech.cost(id)
	civ.energy -= cost[0]
	civ.mineral -= cost[1]
	civ.techs[id] = true
	if not civ.is_ai:
		add_log("升级科技：%s" % Tech.title(id))
	_record(civ, "research", [id])
	return {"error": ""}


## AI 的技术爆炸：不花资源直接得到一项能升的科技（D6）。
func _tech_burst(civ: Civ) -> void:
	if sophon_research_left(civ) > 0:
		return
	var options: Array[String] = []
	for id in Tech.ALL:
		if civ.has_tech(id) or not tier_open(civ, Tech.tier(id)):
			continue
		var ok := true
		for need in Tech.ALL[id]["needs"]:
			ok = ok and civ.has_tech(need)
		if ok:
			options.append(id)
	if not options.is_empty():
		civ.techs[options[rng.randi_range(0, options.size() - 1)]] = true


## 射电望远镜（"telescope"）或预警范围（"warning"）升一级要多少能量。
static func upgrade_cost(kind: String) -> int:
	return Balance.COST_TELESCOPE if kind == "telescope" else Balance.COST_WARNING_UPGRADE


## 为什么不能升级射电望远镜或预警范围（能升级时为空）。
func upgrade_error(civ: Civ, kind: String) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if kind == "telescope":
		if civ.telescope >= Balance.TELESCOPE_MAX:
			return "射电望远镜已经升满"
	elif kind == "warning":
		if not civ.has_warning:
			return "要先建预警系统"
		if civ.warning_level >= Balance.WARNING_MAX:
			return "预警范围已经升满"
	else:
		return "未知的升级"
	var cost := upgrade_cost(kind)
	return "能量不足（还差 %d）" % (cost - civ.energy) if civ.energy < cost else ""


## 射电望远镜（"telescope"）或预警范围（"warning"）升一级：花能量，不花行动点，马上生效。
func upgrade(civ: Civ, kind: String) -> Dictionary:
	var error := upgrade_error(civ, kind)
	if error != "":
		return {"error": error}
	civ.energy -= upgrade_cost(kind)
	if kind == "telescope":
		civ.telescope += 1
	else:
		civ.warning_level += 1
	if not civ.is_ai:
		add_log("升级%s，现在第 %d 级" % ["射电望远镜" if kind == "telescope" else "预警范围",
				civ.telescope if kind == "telescope" else civ.warning_level])
	_record(civ, "upgrade", [kind])
	return {"error": ""}


# ---------- 建造 ----------

## 建造的价格 [能量, 矿石]（含曲率引擎、引力波广播器多花的）。
func build_cost(civ: Civ, kind: String) -> Array:
	var cost: Array = {"miner": Balance.COST_MINER, "dyson": Balance.COST_DYSON, "bunker": Balance.COST_BUNKER,
			"broadcaster": Balance.COST_BROADCASTER, "warning": Balance.COST_WARNING,
			"antimatter": Balance.COST_ANTIMATTER, "grain": Balance.COST_GRAIN, "probe": Balance.COST_PROBE,
			"warship": Balance.COST_WARSHIP, "colony": Balance.COST_COLONY, "starship": Balance.COST_STARSHIP,
			"devourer": Balance.COST_DEVOURER, "sophon": Balance.COST_SOPHON}[kind].duplicate()
	if kind == "warship" and civ.has_tech("gravity"):
		cost[0] += Balance.COST_WARSHIP_GRAVITY
	if kind == "warship":
		for w in warship_weapons(civ):
			var extra := weapon_extra(w)
			cost[0] += extra[0]
			cost[1] += extra[1]
	if UNITS.has(kind) and civ.has_tech("warp"):
		cost[0] += Balance.COST_WARP_EXTRA
	return cost


## 现在造的战舰会带哪些武器：升级过的都带上（T23）。
static func warship_weapons(civ: Civ) -> Array[String]:
	var result: Array[String] = []
	for w in Tech.WEAPONS:
		if civ.has_tech(w):
			result.append(w)
	return result


## 带一种武器，造战舰多花的 [能量, 矿石]。
static func weapon_extra(w: String) -> Array:
	return {"beam": Balance.COST_BEAM_EXTRA, "torpedo": Balance.COST_TORPEDO_EXTRA,
			"hbomb": Balance.COST_HBOMB_EXTRA}[w]


## 一种武器开一次火花的 [能量, 矿石]。
static func weapon_shot(w: String) -> Array:
	return {"beam": Balance.BEAM_SHOT, "torpedo": Balance.TORPEDO_SHOT, "hbomb": Balance.HBOMB_SHOT}[w]


## 一种武器的射程（格）。
static func weapon_range(w: String) -> float:
	return {"beam": Balance.BEAM_RANGE, "torpedo": Balance.TORPEDO_RANGE, "hbomb": Balance.HBOMB_RANGE}[w]


## 为什么不能在 at 建这个（能建时为空）。
func build_error(civ: Civ, kind: String, at: Vector3i) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not BUILD_TECH.has(kind):
		return "不能建这个"
	if not civ.has_tech(BUILD_TECH[kind]):
		return "要先升级科技「%s」" % Tech.ALL[BUILD_TECH[kind]]["name"]
	if civ.reduce_left > 0:
		return "降维期间不能建造"
	if not civ.owns(at):
		return "只能建在自己的星系"
	match kind:
		"miner":
			if civ.miners.get(at, 0) + civ.pending_count("miner", at) >= Balance.MAX_MINERS:
				return "这个星系的采矿船已经有 %d 艘" % Balance.MAX_MINERS
		"dyson":
			if map.star_at(at) == StarMap.Star.NONE:
				return "这个星系没有恒星"
			if civ.dyson_count() + civ.pending_count("dyson") >= civ.star_total(map):
				return "戴森球已经和恒星一样多"
		"bunker":
			if map.gas.get(at, 0) == 0:
				return "这个星系没有类木行星"
			if civ.bunkers.has(at) or civ.pending_count("bunker", at) > 0:
				return "这个星系已经有掩体"
		"broadcaster":
			if civ.broadcasters.has(at) or civ.pending_count("broadcaster", at) > 0:
				return "这个星系已经有恒星广播器"
		"warning":
			if civ.has_warning or civ.pending_count("warning") > 0:
				return "已经有预警系统"
		"antimatter":
			if civ.antimatter >= Balance.MAX_ANTIMATTER:
				return "反物质已经存满"
		"grain":
			if civ.grains.has(at):
				return "这个星系已经存着一颗光粒"
		"warship":
			if civ.count(Ship.WARSHIP) >= Balance.MAX_WARSHIPS:
				return "战舰最多 %d 艘" % Balance.MAX_WARSHIPS
		"colony":
			if civ.count(Ship.COLONY) >= Balance.MAX_COLONY_SHIPS:
				return "殖民船最多 %d 艘" % Balance.MAX_COLONY_SHIPS
		"starship":
			if civ.count(Ship.STARSHIP) >= Balance.MAX_STARSHIPS:
				return "星舰最多 %d 艘" % Balance.MAX_STARSHIPS
		"devourer":
			if civ.count(Ship.DEVOURER) >= Balance.MAX_DEVOURERS:
				return "吞噬者最多 %d 个" % Balance.MAX_DEVOURERS
		"sophon":
			if civ.count(Ship.SOPHON) >= Balance.MAX_SOPHONS:
				return "智子最多 %d 个" % Balance.MAX_SOPHONS
	var cost := build_cost(civ, kind)
	return _pay_error(civ, cost[0], cost[1])


## 在自己的星系 at（默认母星系）建造，花 1 行动点。
## 设施（采矿船、戴森球、掩体、恒星广播器、预警系统）下一回合建好；
## 反物质、光粒马上存好；单位马上造好，停在星系里，等「派出」。
## 返回 {"error": 出错原因，成功时为空, "ship": 造好的单位（只有单位才有）}。
func build(civ: Civ, kind: String, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := build_error(civ, kind, at)
	if error != "":
		return {"error": error, "ship": null}
	var cost := build_cost(civ, kind)
	civ.energy -= cost[0]
	civ.mineral -= cost[1]
	civ.actions_left -= 1
	var ship: Ship = null
	if FACILITIES.has(kind):
		civ.pending.append({"kind": kind, "at": at})
		if not civ.is_ai:
			add_log("开始在 %s 建%s，下一回合建好" % [at, BUILD_NAMES[kind]])
	elif kind == "antimatter":
		civ.antimatter += 1
		if not civ.is_ai:
			add_log("造好 1 份反物质")
	elif kind == "grain":
		civ.grains[at] = true
		if not civ.is_ai:
			add_log("在 %s 造好 1 颗光粒" % at)
	else:
		ship = Ship.make(kind, Vector3(at), next_id())
		if kind == Ship.PROBE and civ.has_tech("interstellar_probe"):
			ship.interstellar = true
			ship.max_speed = Balance.IPROBE_MOVE[0]
			ship.accel = Balance.IPROBE_MOVE[1]
		ship.gravity = kind == Ship.WARSHIP and civ.has_tech("gravity")
		if kind == Ship.WARSHIP:
			ship.weapons = warship_weapons(civ)
		ship.warp = civ.has_tech("warp")
		ship.cost = cost
		civ.ships.append(ship)
		if not civ.is_ai:
			add_log("在 %s 造好%s，等待派出" % [at, ship.label()])
		if kind == Ship.SOPHON:
			_free_from_sophons(civ)
	_record(civ, "build", [kind, at])
	return {"error": "", "ship": ship}


func _finish_pending(civ: Civ) -> void:
	for p in civ.pending:
		var at: Vector3i = p["at"]
		# 预警系统是整个文明的，下单的星系丢了也照样建好（_lose_system 特意留下了它）
		if p["kind"] == "warning":
			civ.has_warning = true
			continue
		if not civ.owns(at):
			continue
		match p["kind"]:
			"miner": civ.miners[at] = civ.miners.get(at, 0) + 1
			"bunker": civ.bunkers[at] = true
			"broadcaster": civ.broadcasters[at] = true
			"dyson":
				if civ.dyson_count() < civ.star_total(map) and map.star_at(at) != StarMap.Star.NONE:
					civ.dysons[at] = civ.dysons.get(at, 0) + 1
	civ.pending.clear()


# ---------- 调度 ----------

## 每个行动要花的能量（行动名就是 GameState 里的函数名）。派出、转向看单位，见 dispatch_cost。
## 殖民、星舰定居、反物质不花能量。画面显示价格也用这里的数。
static func action_cost(name: String) -> int:
	match name:
		"move_starship": return Balance.COST_STARSHIP_MOVE
		"launch_grain": return Balance.COST_GRAIN_LAUNCH
		"broadcast": return Balance.COST_BROADCAST
		"launch_foil": return Balance.COST_FOIL
		"launch_line_foil": return Balance.COST_LINE_FOIL
		"launch_black_domain": return Balance.COST_BLACK_DOMAIN
		"launch_singularity": return Balance.COST_SINGULARITY
		"send_sophon": return Balance.COST_SOPHON_LAUNCH
	return 0


## 派出停着的单位（按种类定价），或让在飞的单位转向（COST_TURN）要花的能量。
static func dispatch_cost(s: Ship) -> int:
	if not s.docked:
		return Balance.COST_TURN
	return {Ship.PROBE: Balance.COST_PROBE_LAUNCH, Ship.WARSHIP: Balance.COST_WARSHIP_LAUNCH,
			Ship.DEVOURER: Balance.COST_DEVOURER_LAUNCH}.get(s.kind, 0)


## 舰船所在的格子光速几乎为 0，派出去也飞不动（G14）。
const STUCK_ERROR := "这里的光速几乎为 0，派出去也飞不动"


func _stuck_at(s: Ship) -> bool:
	return s.max_speed * light_at(s.cell()) < Balance.SHIP_MIN_SPEED


## 为什么不能派出这个单位（能派出时为空）。
func dispatch_error(civ: Civ, id: int, direction: Vector3) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.ship_by_id(id)
	if s == null:
		return "没有这个单位"
	if not s.docked:
		return "已经派出了"
	if not [Ship.PROBE, Ship.WARSHIP, Ship.DEVOURER].has(s.kind):
		return "这个单位要选目的地"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	if _stuck_at(s):
		return STUCK_ERROR
	return _pay_error(civ, dispatch_cost(s))


## 派出停在星系里的探测器、战舰或吞噬者，朝 direction 飞。探测器可以选「先慢速飞出视野」（G13.4）。
## 花 1 行动点和一些能量。返回 {"error": 出错原因，成功时为空}。
func dispatch(civ: Civ, id: int, direction: Vector3, slow := false) -> Dictionary:
	var error := dispatch_error(civ, id, direction)
	if error != "":
		return {"error": error}
	var s := civ.ship_by_id(id)
	var raw_direction := direction
	direction = space_direction(direction)
	civ.energy -= dispatch_cost(s)
	civ.actions_left -= 1
	s.docked = false
	s.direction = direction
	s.speed = 0.0
	s.slow_start = slow and s.kind == Ship.PROBE
	if not civ.is_ai:
		add_log("%s出发，方向 (%.2f, %.2f, %.2f)" % [s.label(), direction.x, direction.y, direction.z])
	_record(civ, "dispatch", [id, raw_direction, slow])
	return {"error": ""}


## 为什么不能让这个单位转向（能转向时为空）。
func turn_error(civ: Civ, id: int, direction: Vector3) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.ship_by_id(id)
	if s == null:
		return "没有这个单位"
	if not [Ship.WARSHIP, Ship.DEVOURER].has(s.kind):
		return "只有战舰和吞噬者能转向"
	if s.docked:
		return "还没派出"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	return _pay_error(civ, dispatch_cost(s))


## 在飞的战舰、吞噬者转向（G8）：花 1 行动点和 COST_TURN 能量；转过 90° 以上时速度归零。
func turn_ship(civ: Civ, id: int, direction: Vector3) -> Dictionary:
	var error := turn_error(civ, id, direction)
	if error != "":
		return {"error": error}
	var s := civ.ship_by_id(id)
	var raw_direction := direction
	direction = space_direction(direction)
	civ.energy -= dispatch_cost(s)
	civ.actions_left -= 1
	if s.direction.dot(direction) < 0.0:
		s.speed = 0.0
	s.direction = direction
	if not civ.is_ai:
		add_log("%s转向" % s.label())
	_record(civ, "turn_ship", [id, raw_direction])
	return {"error": ""}


## 为什么不能派这艘殖民船去 target（能派时为空）。target 为 ANY_TARGET 时不检查目的地。
func colony_error(civ: Civ, id: int, target := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.ship_by_id(id)
	if s == null or s.kind != Ship.COLONY:
		return "没有这艘殖民船"
	if not s.docked and s.direction != Vector3.ZERO:
		return "还在飞"
	if target != ANY_TARGET:
		if civ.owns(target):
			return "这已经是自己的星系"
		if not colony_target_ok(civ, target):
			return "目的地在星图外或已被压没"
	if _stuck_at(s):
		return STUCK_ERROR
	return _pay_error(civ, action_cost("send_colony"))


## 派殖民船去 target，不花能量（T13）。停着的（星系里的，或上次到了没能殖民的）都能派。
## 目的地可以是任意格子（F4.4）：到了能殖民就建殖民地，不能就停在那里等下一个目的地。
func send_colony(civ: Civ, id: int, target: Vector3i) -> Dictionary:
	var error := colony_error(civ, id, target)
	if error != "":
		return {"error": error}
	var s := civ.ship_by_id(id)
	civ.actions_left -= 1
	_set_target(s, target)
	if not civ.is_ai:
		add_log("%s出发，目的地 %s" % [s.label(), target])
	_record(civ, "send_colony", [id, target])
	return {"error": ""}


## 殖民船能不能以 c 为目的地：星图里、不是自己星系的任意格子（F4.4，可以盲飞）。
## 能不能殖民、有没有人占，飞到才知道。画面也用这个判断，免得提示泄露没看到过的东西。
func colony_target_ok(civ: Civ, c: Vector3i) -> bool:
	return not civ.owns(c) and cell_exists(c)


## 文明知道的、可以去殖民的星系：情报里看到过是宜居、还有恒星，不是自己的，也不是已知的敌方星系（F4.4）。
## 只按情报判断，情报旧了可能已经不能殖民。
func known_habitable(civ: Civ) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for c in civ.intel:
		var info: Dictionary = civ.intel[c]
		if info.get("habitable", false) and info["stars"] != StarMap.Star.NONE and not civ.owns(c) \
				and not civ.known.has(c) and cell_exists(c):
			cells.append(c)
	return cells


## 星舰能不能以 c 为目的地：只拦自己已经知道的敌方星系。别人悄悄占着的也能选，
## 飞到才发现，停在旁边（见 _move_ship）。画面也用这个判断，免得提示泄露谁占了哪里。
func starship_target_ok(civ: Civ, c: Vector3i) -> bool:
	return cell_exists(c) and not civ.known.has(c)


## 为什么星舰不能飞向 target（能飞时为空）。target 为 ANY_TARGET 时不检查目的地。
func starship_move_error(civ: Civ, target := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.starship()
	if s == null:
		return "没有星舰"
	if target != ANY_TARGET:
		if not cell_exists(target):
			return "目的地不在星图里"
		if Vector3(target).distance_to(s.pos) < 1e-6:
			return "已经在那里"
		if not starship_target_ok(civ, target):
			return "那里是已知的敌方星系，不能停"
	if _stuck_at(s):
		return STUCK_ERROR
	return _pay_error(civ, action_cost("move_starship"))


## 星舰飞向目的地 target，到了就停下（G9）。
func move_starship(civ: Civ, target: Vector3i) -> Dictionary:
	var error := starship_move_error(civ, target)
	if error != "":
		return {"error": error}
	var s := civ.starship()
	civ.energy -= action_cost("move_starship")
	civ.actions_left -= 1
	if s.direction == Vector3.ZERO:
		s.speed = 0.0
	_set_target(s, target)
	if not civ.is_ai:
		add_log("星舰飞向 %s" % target)
	_record(civ, "move_starship", [target])
	return {"error": ""}


func _set_target(s: Ship, target: Vector3i) -> void:
	s.docked = false
	s.has_target = true
	s.target = Vector3(target)
	s.direction = (s.target - s.pos).normalized()


## 为什么星舰现在不能定居（能定居时为空）。
func settle_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.starship()
	if civ.reduce_left > 0:
		return "降维期间不能建立星系"
	if s == null:
		return "没有星舰"
	if s.direction != Vector3.ZERO and not s.docked:
		return "星舰还在飞"
	if not can_settle(s.cell()):
		return "星舰不在无主的宜居星系上"
	return _pay_error(civ, action_cost("settle_starship"))


## 星舰停在无主的宜居星系上时，在那里建立星系，星舰用掉。花 1 个行动点。
func settle_starship(civ: Civ) -> Dictionary:
	var error := settle_error(civ)
	if error != "":
		return {"error": error}
	var s := civ.starship()
	civ.actions_left -= 1
	var c := s.cell()
	_remove_ship(civ, s)
	civ.colonies.append(c)
	if civ.colonies.size() == 1:
		civ.home = c
	if not civ.is_ai:
		add_log("星舰在 %s 建立星系（%d 颗恒星）" % [c, map.star_at(c)])
	_record(civ, "settle_starship", [])
	return {"error": ""}


## 为什么不能从 at（默认母星系）朝 direction 发射光粒（能发射时为空）。
func grain_error(civ: Civ, direction: Vector3, at: Vector3i = AT_HOME) -> String:
	if at == AT_HOME:
		at = civ.home
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.owns(at) or not civ.grains.has(at):
		return "这个星系没有存着光粒"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	if in_black_domain(at):
		return "这里在黑域里，光速太低，光粒发出去没有杀伤力"
	return _pay_error(civ, action_cost("launch_grain"))


## 从存着光粒的星系 at（默认母星系）朝 direction 发射光粒。
func launch_grain(civ: Civ, direction: Vector3, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := grain_error(civ, direction, at)
	if error != "":
		return {"error": error}
	var raw_direction := direction
	direction = space_direction(direction)
	civ.energy -= action_cost("launch_grain")
	civ.actions_left -= 1
	civ.grains.erase(at)
	var g := Ship.make(Ship.GRAIN, Vector3(at), next_id())
	g.docked = false
	g.direction = direction
	civ.ships.append(g)
	if not civ.is_ai:
		add_log("从 %s 发射光粒，方向 (%.2f, %.2f, %.2f)" % [at, direction.x, direction.y, direction.z])
	_record(civ, "launch_grain", [raw_direction, at])
	return {"error": ""}


## 离自己星系 ANTIMATTER_RANGE 以内的敌方战舰（最近的在前）。
func antimatter_targets(civ: Civ) -> Array[Ship]:
	var found: Array = []
	for other in civs:
		if other == civ or not other.alive:
			continue
		for s in other.ships:
			if s.kind != Ship.WARSHIP or s.dead or s.docked:
				continue
			var d := _nearest(civ.colonies, s.pos)
			if d <= Balance.ANTIMATTER_RANGE + 1e-6:
				found.append([d, s])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var result: Array[Ship] = []
	for f in found:
		result.append(f[1])
	return result


## 为什么现在不能用反物质（能用时为空）。
func antimatter_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if civ.antimatter <= 0:
		return "没有反物质"
	if antimatter_targets(civ).is_empty():
		return "自己星系 %.1f 格以内没有敌方战舰" % Balance.ANTIMATTER_RANGE
	return _pay_error(civ, action_cost("use_antimatter"))


## 用掉 1 份反物质，让离自己星系最近的敌方战舰消失（G6）。花 1 行动点。
func use_antimatter(civ: Civ) -> Dictionary:
	var error := antimatter_error(civ)
	if error != "":
		return {"error": error}
	civ.actions_left -= 1
	civ.antimatter -= 1
	var target := antimatter_targets(civ)[0]
	var owner := ship_owner(target)
	_destroy(owner, target, "")
	if not civ.is_ai:
		add_log("反物质消灭了 %s 的一艘战舰" % owner.name)
	elif owner == human():
		add_log("你的%s被反物质消灭" % target.label())
	_record(civ, "use_antimatter", [])
	return {"error": ""}


# ---------- 智子（D5） ----------

## 为什么不能派这个智子去 target（能派时为空）。target 为 ANY_TARGET 时不检查目的地。
func sophon_error(civ: Civ, id: int, target := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := civ.ship_by_id(id)
	if s == null or s.kind != Ship.SOPHON:
		return "没有这个智子"
	if s.lock >= 0:
		return "这个智子已经锁住了别的文明"
	if not s.docked and s.direction != Vector3.ZERO:
		return "还在飞"
	if target != ANY_TARGET:
		if civ.owns(target):
			return "这是自己的星系"
		if not cell_exists(target):
			return "目的地在星图外或已被压没"
	if _stuck_at(s):
		return STUCK_ERROR
	return _pay_error(civ, action_cost("send_sophon"))


## 派智子去 target（一出发就以 0.99 倍光速飞）。到了别人的母星系就锁住那个文明，不是就原地待命，可以再派。
func send_sophon(civ: Civ, id: int, target: Vector3i) -> Dictionary:
	var error := sophon_error(civ, id, target)
	if error != "":
		return {"error": error}
	var s := civ.ship_by_id(id)
	civ.energy -= action_cost("send_sophon")
	civ.actions_left -= 1
	s.speed = 0.0
	_set_target(s, target)
	if not civ.is_ai:
		add_log("%s出发，目的地 %s" % [s.label(), target])
	_record(civ, "send_sophon", [id, target])
	return {"error": ""}


## 智子到了目的地：是别人的母星系就锁住那个文明（D5）。
func _sophon_arrive(civ: Civ, s: Ship) -> void:
	var c := s.cell()
	var victim := coord_owner(c)
	if victim == null or victim == civ or victim.home != c:
		if not civ.is_ai:
			add_log("%s到达 %s，这里不是别的文明的母星系，原地待命" % [s.label(), c])
		return
	s.lock = civs.find(victim)
	s.lock_turn = turn
	civ.known[c] = turn
	if not civ.is_ai:
		add_log("%s锁住了 %s：%d 回合不能升级科技，%d 回合内达到的科技等级条件不算，它做的事你都看得到" % [
				s.label(), victim.name, Balance.SOPHON_RESEARCH_TURNS, Balance.SOPHON_TIER_TURNS])
	if not victim.is_ai:
		add_log("别人的智子到了你的母星系：%d 回合不能升级科技，%d 回合内达到的科技等级条件不算，你做的事对方都看得到。自己造出智子就能解除" % [
				Balance.SOPHON_RESEARCH_TURNS, Balance.SOPHON_TIER_TURNS])


## 锁住这个文明的别人的智子。
func sophons_on(victim: Civ) -> Array[Ship]:
	var idx := civs.find(victim)
	var result: Array[Ship] = []
	for other in civs:
		if other == victim or not other.alive:
			continue
		for s in other.ships:
			if s.kind == Ship.SOPHON and not s.dead and s.lock == idx:
				result.append(s)
	return result


## 用智子看着这个文明的别的文明。
func watched_by(victim: Civ) -> Array[Civ]:
	var result: Array[Civ] = []
	for s in sophons_on(victim):
		var owner := ship_owner(s)
		if not result.has(owner):
			result.append(owner)
	return result


## 被智子锁住，还要几个回合才能升级科技（没被锁时为 0）。
func sophon_research_left(civ: Civ) -> int:
	return _sophon_left(civ, Balance.SOPHON_RESEARCH_TURNS)


## 被智子锁住，还要几个回合达到的科技等级条件才算（没被锁时为 0）。
func sophon_tier_left(civ: Civ) -> int:
	return _sophon_left(civ, Balance.SOPHON_TIER_TURNS)


func _sophon_left(civ: Civ, turns: int) -> int:
	var left := 0
	for s in sophons_on(civ):
		left = maxi(left, s.lock_turn + turns - turn + 1)
	return left


## 被锁的文明自己造出智子：锁住它的智子都没用了，全部效果消失。
func _free_from_sophons(civ: Civ) -> void:
	for s in sophons_on(civ):
		var owner := ship_owner(s)
		_destroy(owner, s, "")
		if owner == human():
			add_log("%s 造出了自己的智子，你的%s失效了" % [civ.name, s.label()])
		elif civ == human():
			add_log("你造出了智子，%s 的智子失效了" % owner.name)


## 能广播的地方：有恒星广播器、没被星际探测器封锁的星系；有引力波广播（203）时所有自己的星系。
func can_broadcast_from(civ: Civ, c: Vector3i) -> bool:
	if not civ.owns(c):
		return false
	if civ.has_tech("gravity"):
		return true
	return civ.broadcasters.has(c) and not jammed(civ, c)


## 能听到广播：有引力波广播（203），或者至少有一个能用的恒星广播器（E7F6 2026-10-06）。
func can_hear(civ: Civ) -> bool:
	for c in civ.broadcasters:
		if can_broadcast_from(civ, c):
			return true
	return civ.has_tech("gravity") and not civ.colonies.is_empty()


## 有别人的星际探测器停在这个星系上，恒星广播器不能用。
func jammed(civ: Civ, c: Vector3i) -> bool:
	for other in civs:
		if other == civ or not other.alive:
			continue
		for s in other.ships:
			if s.parked and s.cell() == c:
				return true
	return false


## 为什么不能广播（能广播时为空），参数和 broadcast 一样。target 为 ANY_TARGET 时不检查坐标。
func broadcast_error(civ: Civ, target := ANY_TARGET, source: Vector3i = AT_HOME, ship_id := -1) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if target != ANY_TARGET:
		if not StarMap.in_bounds(target):
			return "坐标不在星图内"
		if civ.owns(target):
			return "不能广播自己的坐标"
	if ship_id >= 0:
		var s := civ.ship_by_id(ship_id)
		if s == null or not s.gravity:
			return "这艘战舰没有引力波广播器"
	elif not can_broadcast_from(civ, civ.home if source == AT_HOME else source):
		return "这个星系不能广播（要有恒星广播器，而且没被别人的星际探测器封锁）"
	return _pay_error(civ, action_cost("broadcast"))


## 广播坐标 target（星图里任何格子）。从星系 source（默认母星系）广播；ship_id 不为 -1 时，
## 从带引力波广播器的战舰广播。广播当回合开始以光速扩散（游戏设计 §8）。
func broadcast(civ: Civ, target: Vector3i, source: Vector3i = AT_HOME, ship_id := -1) -> Dictionary:
	if source == AT_HOME and ship_id < 0:
		source = civ.home
	var error := broadcast_error(civ, target, source, ship_id)
	if error != "":
		return {"error": error}
	var from := civ.ship_by_id(ship_id).pos if ship_id >= 0 else Vector3(source)
	var exposed := NO_HIT
	# 检查都通过了才掷暴露的骰子：失败的操作不进对局记录，不能动随机数
	if ship_id < 0 and rng.randf() < pow(0.5, from.distance_to(Vector3(target)) / Balance.BROADCAST_EXPOSE_HALF):
		exposed = source
	civ.energy -= action_cost("broadcast")
	civ.actions_left -= 1
	broadcasts.append({"from": from, "target": target, "sender": civ, "exposed": exposed, "radius": 0.0,
			"heard": {}, "hidden_heard": {}})
	if not civ.is_ai:
		add_log("开始广播 %s，以光速向四周传播" % target)
	_record(civ, "broadcast", [target, source, ship_id])
	return {"error": ""}


func _spread_broadcasts() -> void:
	var still: Array[Dictionary] = []
	for b in broadcasts:
		b["radius"] += 1.0
		var from: Vector3 = b["from"]
		var target: Vector3i = b["target"]
		for civ in civs:
			if not civ.alive or civ == b["sender"] or b["heard"].has(civ) or not can_hear(civ):
				continue
			if not _light_reaches_bases(civ, from, b["radius"]):
				continue
			b["heard"][civ] = true
			civ.heard[target] = turn
			_discover(civ, "听到了广播")
			var owner := coord_owner(target)
			if owner != null and owner != civ:
				civ.known[target] = turn
			var ex: Vector3i = b["exposed"]
			if ex != NO_HIT and coord_owner(ex) == b["sender"]:
				civ.known[ex] = turn
			if civ == human():
				add_log("听到广播：坐标 %s%s" % [target, "（广播者暴露在 %s）" % ex if ex != NO_HIT else ""])
				if owner == civ:
					add_log("你的星系 %s 被别人广播了" % target)
		for h in hidden:
			if b["hidden_heard"].has(h) or not _light_within(from, Vector3(h), b["radius"]):
				continue
			b["hidden_heard"][h] = true
			hidden_listen.append({"from": h, "target": target, "left": Balance.HIDDEN_PATIENCE})
		if b["radius"] < StarMap.SIZE * 6:
			still.append(b)
	broadcasts = still


## 听到广播的隐藏文明每回合按机会出手：大多数时候发一颗光粒，少数时候往被广播的坐标投送降维箔（G5）：
## 三维时是二向箔，二维时是单向著（目标挪到平面上）；压成直线以后没有箔可发，只发光粒（F5.3）。
## 离被广播的坐标越近，越可能出手。
func _hidden_strikes() -> void:
	var still: Array[Dictionary] = []
	for l in hidden_listen:
		var h: Vector3i = l["from"]
		var target: Vector3i = l["target"]
		var d := Vector3(h).distance_to(Vector3(target))
		var chance := Balance.HIDDEN_STRIKE_CHANCE * maxf(0.0, 1.0 - d / Balance.HIDDEN_HEAR_RANGE)
		if chance > 0.0 and rng.randf() < chance:
			if rng.randf() < Balance.HIDDEN_FOIL_CHANCE and not all_linear():
				if all_flat():
					target.z = flat_plane
				var f := Foil.new(Vector3(h), target, 0, all_flat())
				f.precise = true
				f.speed = Balance.HIDDEN_FOIL_SPEED
				hidden_foils.append(f)
			else:
				var g := Ship.make(Ship.GRAIN, Vector3(h), next_id())
				g.docked = false
				g.direction = (Vector3(target) - Vector3(h)).normalized()
				hidden_ships.append(g)
			continue
		l["left"] -= 1
		if l["left"] > 0:
			still.append(l)
	hidden_listen = still


# ---------- 移动和交战 ----------

func _move_all_ships() -> void:
	for civ in civs:
		for s in civ.ships.duplicate():
			# 文明灭亡后，它已经发出的光粒接着飞（_die 只留下光粒）
			if not s.dead and (civ.alive or s.kind == Ship.GRAIN):
				_move_ship(civ, s)
	for s in hidden_ships:
		if not s.dead:
			_move_ship(null, s)
	_clean_dead()


## 单位先加速、再沿直线移动（G1），检查这一步扫过的格子。有目的地的，最后一步直接落在目的地上。
func _move_ship(civ: Civ, s: Ship) -> void:
	if s.docked or s.parked or s.direction == Vector3.ZERO:
		return
	if s.eat_wait > 0:
		s.eat_wait -= 1
		return
	var top := s.max_speed
	var acc := s.accel
	if s.warp and civ != null and not in_own_vision(civ, s.pos):
		top = Balance.WARP_MOVE[0]
		acc = Balance.WARP_MOVE[1]
	if s.slow_start:
		if civ != null and in_own_vision(civ, s.pos):
			top = minf(top, Balance.SLOW_START_SPEED)
		else:
			s.slow_start = false
	s.speed = minf(s.speed + acc, top)
	var from := s.pos
	var mine := civ != null and not civ.is_ai
	# 实际速度还要乘以所在格的光速（G14）。慢到几乎不动就停在原地，停久了就消失
	if s.kind != Ship.GRAIN and s.speed * light_at(s.cell()) < Balance.SHIP_MIN_SPEED:
		s.stuck += 1
		if s.stuck >= Balance.SHIP_STUCK_TURNS:
			if mine:
				add_log("%s困在光速几乎为 0 的地方，%d 回合后消失了" % [s.label(), s.stuck])
			_destroy(civ, s, "")
		return
	s.stuck = 0
	var step := _travel(from, s.direction, s.speed)
	var to := from + s.direction * step
	var arrived := false
	if s.has_target:
		# 星舰的目的地是别人的星系（下令时不知道）：停在离它 1 格的地方（已经在 1 格以内就原地停下）。
		# 星舰视野 1.5 格，到这里本来就看得到那个星系
		var goal := s.target
		var dest := Vector3i(s.target.round())
		var dest_owner := coord_owner(dest)
		var blocked := s.kind == Ship.STARSHIP and civ != null and dest_owner != null and dest_owner != civ
		if blocked:
			goal = s.target - s.direction * 1.0 if from.distance_to(s.target) > 1.0 else from
		if from.distance_to(goal) <= step + 1e-6:
			to = goal
			arrived = true
			if blocked:
				civ.known[dest] = turn
				if not civ.is_ai:
					add_log("星舰飞到 %s 旁边，发现那里是别人的星系，停了下来" % dest)
	# 光粒、智子不是舰船，不留航迹
	if step > Balance.WAKE_SPEED and s.kind != Ship.GRAIN and s.kind != Ship.SOPHON:
		wakes.append({"a": from, "b": to, "turn": turn, "gone": false})
	var radius := Balance.GRAIN_RADIUS if s.kind == Ship.GRAIN else 0.0
	var cells := Geometry.segment_cells(from, to, radius)
	# 光粒在光速低于 GRAIN_MIN_LIGHT 的地方失去杀伤力（G14）：出发的格子也要看
	if s.kind == Ship.GRAIN and light_at(s.cell()) < Balance.GRAIN_MIN_LIGHT:
		_disarm_grain(civ, s)
		return
	for c in cells:
		if s.kind == Ship.GRAIN and light_at(c) < Balance.GRAIN_MIN_LIGHT:
			_disarm_grain(civ, s)
			return
		if not cell_exists(c):
			if s.kind == Ship.GRAIN or (civ != null and civ.reduced):
				continue
			if mine:
				add_log("%s飞进被压平的空间，消失了" % s.label())
			_destroy(civ, s, "")
			return
		var owner := coord_owner(c)
		match s.kind:
			Ship.GRAIN:
				if owner != null and owner != civ and map.star_at(c) != StarMap.Star.NONE:
					_grain_hit(c, owner, s, civ)
					_destroy(civ, s, "")
					return
			Ship.COLONY:
				if owner != null and owner != civ:
					if mine:
						add_log("%s经过别人的星系，被毁掉了" % s.label())
					_destroy(civ, s, "")
					return
			Ship.PROBE:
				if s.interstellar and owner != null and owner != civ:
					s.pos = Vector3(c)
					s.parked = true
					s.speed = 0.0
					if mine:
						add_log("%s停在了 %s 的一个星系上" % [s.label(), owner.name])
					return
			Ship.DEVOURER:
				if owner == null and map.rocky.get(c, 0) > 0:
					s.pos = Vector3(c)
					s.speed = 0.0
					s.eat_wait = 1
					_eat(civ, c)
					return
	s.pos = to
	if arrived:
		s.speed = 0.0
		s.direction = Vector3.ZERO
		s.has_target = false
		if s.kind == Ship.COLONY:
			_settle(civ, s)
			return
		if s.kind == Ship.SOPHON:
			_sophon_arrive(civ, s)
			return
		if mine:
			add_log("%s到达 %s" % [s.label(), s.cell()])
	# 飞出星图才消失；隐藏文明的光粒从星图外出发，往星图里飞的时候不算
	var center := Vector3.ONE * (StarMap.SIZE - 1) / 2.0
	if s.is_outside() and (not Ship.outside(from) or to.distance_to(center) >= from.distance_to(center)):
		if mine or (s.kind == Ship.GRAIN and civ == human()):
			add_log("%s飞出星图%s" % [s.label(), "，没打中" if s.kind == Ship.GRAIN else ""])
		_destroy(civ, s, "")


func _disarm_grain(civ: Civ, g: Ship) -> void:
	if civ == human():
		add_log("光粒飞进光速变慢的地方（黑域），失去了杀伤力")
	_destroy(civ, g, "")


## 吞噬者吃掉 c 的一颗类地行星。吃掉的可能是宜居行星，那样这个星系就不能再殖民（T14）。
func _eat(civ: Civ, c: Vector3i) -> void:
	var before: int = map.rocky[c]
	map.rocky[c] = before - 1
	if map.habitable.has(c) and rng.randf() < 1.0 / before:
		map.habitable.erase(c)
	civ.mineral += Balance.DEVOURER_MINERAL
	if not civ.is_ai:
		add_log("吞噬者在 %s 吃掉一颗类地行星，得到 %dM" % [c, Balance.DEVOURER_MINERAL])


## 殖民船到了目的地：能殖民就建殖民地（船用掉）；不能就停在那里，可以再派去别处（F4.4）。
func _settle(civ: Civ, s: Ship) -> void:
	var c := s.cell()
	if not can_settle(c):
		if not civ.is_ai:
			add_log("%s到达 %s，这里不能殖民，原地待命" % [s.label(), c])
		return
	_destroy(civ, s, "")
	civ.colonies.append(c)
	if civ.colonies.size() == 1:
		civ.home = c
	if not civ.is_ai:
		add_log("殖民船在 %s 建立殖民地（%d 颗恒星）" % [c, map.star_at(c)])


## 这个格子能不能建立殖民地：宜居、还有恒星、没有活着的文明占着。
func can_settle(c: Vector3i) -> bool:
	return cell_exists(c) and map.is_habitable(c) and map.star_at(c) != StarMap.Star.NONE and coord_owner(c) == null


## 光粒打中 c：毁掉 1 颗恒星（连同它的戴森球），抹掉那里的文明；有掩体时文明留下（B1、T10、D1）。
func _grain_hit(c: Vector3i, owner: Civ, g: Ship, shooter: Civ) -> void:
	owner.times_hit += 1
	owner.hit_dirs.append({"at": c, "dir": -g.direction, "turn": turn})
	if shooter != null:
		shooter.record_hits[c] = true
		shooter.record_empty.erase(c)
	var weapon := "光粒" if shooter != null else "来历不明的光粒"
	if owner.reduced:
		if owner == human() or shooter == human():
			add_log("%s打中 %s，但对方已降维，光粒无效" % [weapon, c])
		return
	var left := map.star_at(c) - 1
	map.stars[c] = left
	if owner.dysons.get(c, 0) > 0:
		owner.dysons[c] -= 1
		if owner.dysons[c] == 0:
			owner.dysons.erase(c)
	_cap_dysons(owner)
	if owner.bunkers.has(c):
		if owner == human():
			add_log("%s打中你的星系 %s，毁掉 1 颗恒星（剩 %d 颗），躲在掩体里的人活了下来" % [weapon, c, left])
		elif shooter == human():
			add_log("光粒打中 %s，毁掉 1 颗恒星，但对方躲在掩体里活了下来" % c)
		return
	if owner == human():
		add_log("%s打中你的星系 %s，那里的文明被抹掉了" % [weapon, c])
	elif shooter == human():
		add_log("光粒打中 %s，毁掉了那里的文明" % c)
	if shooter != null:
		shooter.known.erase(c)
	# 停在这里的星舰也一起毁掉
	for civ in civs:
		var ss := civ.starship()
		if civ.alive and ss != null and ss.cell() == c and ss.direction == Vector3.ZERO:
			_destroy(civ, ss, "光粒")
	_lose_system(c, owner)


## 戴森球不能比恒星多。
func _cap_dysons(civ: Civ) -> void:
	var extra := civ.dyson_count() - civ.star_total(map)
	for c in civ.dysons.keys():
		if extra <= 0:
			break
		var n: int = civ.dysons[c]
		var take := mini(n, extra)
		civ.dysons[c] = n - take
		extra -= take
		if civ.dysons[c] == 0:
			civ.dysons.erase(c)


## 交战（游戏设计 §6、§12）：
## 1. 一方的舰船和另一方的舰船（光粒、智子除外）相距 CONTACT_RANGE 以内，双方都算接触过（II 级的条件，E8）。
## 2. 带武器的战舰朝射程里的敌方战舰开火（T23），所有战舰同时开火。
## 3. 还活着的战舰和敌方战舰、星舰相遇，一起毁掉。
## 4. 其余在飞的战舰每回合打一个目标：先打附近的敌方殖民船，再打附近没有反物质的敌方星系。
func _combat() -> void:
	var units: Array = []  # [文明, 单位]
	for civ in civs:
		if not civ.alive:
			continue
		for s in civ.ships:
			if not s.dead and s.kind != Ship.GRAIN and s.kind != Ship.SOPHON:
				units.append([civ, s])
	for i in units.size():
		for j in range(i + 1, units.size()):
			var a: Array = units[i]
			var b: Array = units[j]
			if a[0] != b[0] and not (a[1].docked and b[1].docked) \
					and a[1].pos.distance_to(b[1].pos) <= Balance.CONTACT_RANGE + 1e-6:
				_engage(a[0], b[0])
	_fire_weapons(units)
	var r := Balance.WARSHIP_RANGE + 1e-6
	var pairs: Array = []
	for i in units.size():
		for j in range(i + 1, units.size()):
			var a: Array = units[i]
			var b: Array = units[j]
			if a[0] == b[0] or (a[1].docked and b[1].docked) or a[1].dead or b[1].dead:
				continue
			var kinds := [a[1].kind, b[1].kind]
			var d: float = a[1].pos.distance_to(b[1].pos)
			if d > r:
				continue
			if kinds.has(Ship.WARSHIP) and (kinds.count(Ship.WARSHIP) == 2 or kinds.has(Ship.STARSHIP)):
				pairs.append([d, a, b])
	pairs.sort_custom(func(x, y): return x[0] < y[0])
	for p in pairs:
		var a: Array = p[1]
		var b: Array = p[2]
		if a[1].dead or b[1].dead:
			continue
		if a[0] == human() or b[0] == human():
			add_log("%s的%s和%s的%s相遇，一起毁掉了" % [a[0].name, a[1].label(), b[0].name, b[1].label()])
		_destroy(a[0], a[1], "")
		_destroy(b[0], b[1], "")
	for u in units:
		var civ: Civ = u[0]
		var s: Ship = u[1]
		if s.dead or s.kind != Ship.WARSHIP:
			continue
		if s.docked or not civ.alive:
			continue
		_warship_strike(civ, s)
	_clean_dead()


## 一方的舰船和另一方的舰船接触：双方都算达到 II 级的条件（E8）。
func _engage(a: Civ, b: Civ) -> void:
	for civ in [a, b]:
		_reach_tier(civ, 2, "和别的文明的舰船接触")


## 带武器的战舰开火（T23）：射程里有敌方战舰时，按次声波氢弹、高能粒子束、星际鱼雷的顺序，
## 用第一种够得着、付得起的武器打最近的一艘。先定好所有战舰打谁，再一起结算，所以两艘可以同时打掉对方。
## 两边都停在星系里的不打（和相遇一样）。
func _fire_weapons(units: Array) -> void:
	var shots: Array = []  # [开火的文明, 战舰, 武器, 目标的文明, 目标]
	for u in units:
		var civ: Civ = u[0]
		var s: Ship = u[1]
		if s.kind != Ship.WARSHIP or s.weapons.is_empty():
			continue
		for w in Tech.WEAPONS:
			if not s.weapons.has(w) or _cant_afford_shot(civ, w):
				continue
			var best: Array = []
			var best_d := weapon_range(w) + 1e-6
			for v in units:
				var t: Ship = v[1]
				if v[0] == civ or t.kind != Ship.WARSHIP or (s.docked and t.docked):
					continue
				var d := s.pos.distance_to(t.pos)
				if d <= best_d and not blocked(s.pos, t.pos):
					best_d = d
					best = v
			if not best.is_empty():
				shots.append([civ, s, w, best[0], best[1]])
				break
	for shot in shots:
		var civ: Civ = shot[0]
		var w: String = shot[2]
		var other: Civ = shot[3]
		var t: Ship = shot[4]
		if t.dead or _cant_afford_shot(civ, w):
			continue
		var pay := weapon_shot(w)
		civ.energy -= pay[0]
		civ.mineral -= pay[1]
		var who := "%s的%s" % [civ.name, shot[1].label()]
		var whom := "%s的%s" % [other.name, t.label()]
		var told := civ == human() or other == human()
		match w:
			"beam":
				if told:
					add_log("%s用高能粒子束毁掉了%s" % [who, whom])
				_destroy(other, t, "")
			"torpedo":
				t.damage += 1
				if t.damage >= Balance.TORPEDO_HITS:
					if told:
						add_log("%s用星际鱼雷打中%s，%s毁掉了" % [who, whom, t.label()])
					_destroy(other, t, "")
				elif told:
					add_log("%s用星际鱼雷打中%s（%d/%d）" % [who, whom, t.damage, Balance.TORPEDO_HITS])
			"hbomb":
				civ.energy += t.cost[0]
				civ.mineral += t.cost[1]
				if told:
					add_log("%s用次声波氢弹杀死了%s的船员，收回 %dE、%dM" % [who, whom, t.cost[0], t.cost[1]])
				_destroy(other, t, "")


## 开一次火的钱够不够（够时为 false）。
func _cant_afford_shot(civ: Civ, w: String) -> bool:
	var pay := weapon_shot(w)
	return civ.energy < pay[0] or civ.mineral < pay[1]


## 战舰每回合打一个目标：附近的敌方殖民船，再是附近没有反物质的敌方星系。
func _warship_strike(civ: Civ, s: Ship) -> void:
	var r := Balance.WARSHIP_RANGE + 1e-6
	for other in civs:
		if other == civ or not other.alive:
			continue
		for t in other.ships:
			if not t.dead and t.kind == Ship.COLONY and t.pos.distance_to(s.pos) <= r:
				if other == human() or civ == human():
					add_log("%s的%s打掉了%s的%s" % [civ.name, s.label(), other.name, t.label()])
				_destroy(other, t, "")
				return
	for other in civs:
		if other == civ or not other.alive or other.antimatter > 0:
			continue
		for c in other.colonies:
			if Vector3(c).distance_to(s.pos) <= r and not blocked(s.pos, Vector3(c)):
				other.times_hit += 1
				other.hit_dirs.append({"at": c, "dir": (s.pos - Vector3(c)).normalized(), "turn": turn})
				civ.record_hits[c] = true
				civ.known.erase(c)
				if other == human():
					add_log("敌方战舰打到你的星系 %s，那里的文明被抹掉了" % c)
				elif civ == human():
					add_log("%s抹掉了 %s 在 %s 的星系" % [s.label(), other.name, c])
				_lose_system(c, other)
				return


## 单位毁掉：做个记号，回合里统一拿掉。
func _destroy(civ: Civ, s: Ship, cause: String) -> void:
	if s.dead:
		return
	s.dead = true
	if civ != null and s.kind == Ship.STARSHIP:
		if civ == human() and cause != "":
			add_log("你的星舰被%s毁掉" % cause)
		if civ.colonies.is_empty():
			_die(civ)


func _remove_ship(civ: Civ, s: Ship) -> void:
	civ.ships.erase(s)


func _clean_dead() -> void:
	for civ in civs:
		civ.ships = civ.ships.filter(func(s): return not s.dead)
	hidden_ships = hidden_ships.filter(func(s): return not s.dead)


# ---------- 视野和情报 ----------

## 视野半径：母星系 2.0、殖民星系和星舰 1.5、其他舰船 1.0，射电望远镜每升一级 +TELESCOPE_STEP 格。
func sphere_radius(civ: Civ, base: float) -> float:
	return base + civ.vision_bonus()


## 探测器的圆锥 [长度, 张角]。
func cone_of(civ: Civ, s: Ship) -> Array:
	var length := (Balance.IPROBE_LENGTH if s.interstellar else Balance.PROBE_LENGTH) + civ.vision_bonus()
	var angle := (Balance.IPROBE_ANGLE if s.interstellar else Balance.PROBE_ANGLE) \
			+ civ.telescope * Balance.TELESCOPE_ANGLE_STEP
	return [length, minf(angle, Balance.MAX_CONE_ANGLE)]


## 文明所有的「眼睛」：每项是 {"pos", "r": 球的半径（圆锥时为长度）, "dir": 圆锥方向（球时为零）,
## "angle": 圆锥张角, "base": 是不是据点（据点的视野不用传）}。
func observers(civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in civ.colonies:
		result.append({"pos": Vector3(c), "r": sphere_radius(civ, Balance.VISION_HOME if c == civ.home else Balance.VISION_COLONY),
				"dir": Vector3.ZERO, "angle": 0.0, "base": true})
	for s in civ.ships:
		if s.dead or s.kind == Ship.GRAIN or s.kind == Ship.SOPHON or s.docked:
			continue
		if s.kind == Ship.STARSHIP:
			result.append({"pos": s.pos, "r": sphere_radius(civ, Balance.VISION_COLONY), "dir": Vector3.ZERO,
					"angle": 0.0, "base": true})
		elif s.kind == Ship.PROBE and not s.parked:
			var cone := cone_of(civ, s)
			result.append({"pos": s.pos, "r": cone[0], "dir": s.direction, "angle": cone[1], "base": false})
		else:
			result.append({"pos": s.pos, "r": sphere_radius(civ, Balance.VISION_SHIP), "dir": Vector3.ZERO,
					"angle": 0.0, "base": false})
	return result


## 点 p 在不在这只眼睛的视野里（不管黑域）。
static func in_view(o: Dictionary, p: Vector3) -> bool:
	var v: Vector3 = p - o["pos"]
	var r: float = o["r"]
	var dir: Vector3 = o["dir"]
	if dir == Vector3.ZERO:
		return v.length() <= r + 1e-6
	var t := v.dot(dir)
	if t <= 0.0 or t > r + 1e-6:
		return false
	var off := (v - dir * t).length()
	return off <= t * tan(deg_to_rad(o["angle"] / 2.0)) + Geometry.CELL_HALF


## 点 p 在不在自己星系的视野里（曲率引擎、慢速飞出视野用）。
func in_own_vision(civ: Civ, p: Vector3) -> bool:
	for c in civ.colonies:
		var r := sphere_radius(civ, Balance.VISION_HOME if c == civ.home else Balance.VISION_COLONY)
		if Vector3(c).distance_to(p) <= r + 1e-6:
			return true
	return false


## 现在能直接看到这个格子（自己的星系、星舰的视野，不用等传回）。
func sees_now(civ: Civ, c: Vector3i) -> bool:
	for o in observers(civ):
		if o["base"] and in_view(o, Vector3(c)) and not blocked(o["pos"], Vector3(c)):
			return true
	return false


## 星系 c 现在的样子（情报里记下的）。
func snapshot(c: Vector3i) -> Dictionary:
	var owner := coord_owner(c)
	var info := {"turn": turn, "stars": map.star_at(c), "rocky": map.rocky.get(c, 0), "gas": map.gas.get(c, 0),
			"habitable": map.is_habitable(c), "owner": civs.find(owner) if owner != null else -1, "dysons": 0, "warships": 0, "broadcaster": false, "grain": false, "foil": false,
			"bunker": false}
	if owner != null:
		info["dysons"] = owner.dysons.get(c, 0)
		info["broadcaster"] = owner.broadcasters.has(c)
		info["grain"] = owner.grains.has(c)
		info["bunker"] = owner.bunkers.has(c)
		for s in owner.ships:
			if s.kind == Ship.WARSHIP and s.docked and s.cell() == c:
				info["warships"] += 1
		for f in owner.foils:
			if f.prepare_left > 0 and Vector3i(f.origin.round()) == c:
				info["foil"] = true
	return info


## 回合末所有文明看一遍之前，先把这段时间里不会变的东西算好，省得每只眼睛都重算（只为提速，结果不变）：
## - "grid"：按 (x, y) 分好的星系格子，存的是在 system_cells 里的下标，找附近的星系时不用扫全图；
## - "dark"：光速几乎为 0 的格子，路线离它们都远时就不用一段段查有没有被挡住；
## - "snaps"：这一回合拍过的星系快照。看的过程中星系不会变，同一个星系只拍一次，大家共用。
func _begin_view_cache() -> void:
	var grid := {}
	for i in system_cells.size():
		var c := system_cells[i]
		var key := Vector2i(c.x, c.y)
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var dark: Array[Vector3] = []
	if not light.is_empty():
		var n := StarMap.SIZE
		for i in light.size():
			if light[i] < Balance.SHIP_MIN_SPEED:
				dark.append(Vector3(i / (n * n), (i / n) % n, i % n))
	_view_cache = {"grid": grid, "dark": dark, "snaps": {}}



## 离 pos 每个方向都不超过 reach 的星系格子（round 时还要直线距离不超过 reach），顺序和 system_cells 一样。
func _systems_near(pos: Vector3, reach: float, round := false) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if _view_cache.is_empty():
		for c in system_cells:
			if absf(c.x - pos.x) <= reach and absf(c.y - pos.y) <= reach and absf(c.z - pos.z) <= reach \
					and (not round or (Vector3(c) - pos).length() <= reach):
				result.append(c)
		return result
	var grid: Dictionary = _view_cache["grid"]
	var found := PackedInt32Array()
	for x in range(ceili(pos.x - reach), floori(pos.x + reach) + 1):
		for y in range(ceili(pos.y - reach), floori(pos.y + reach) + 1):
			var key := Vector2i(x, y)
			if not grid.has(key):
				continue
			for i in grid[key]:
				var c := system_cells[i]
				if absf(c.z - pos.z) <= reach and (not round or (Vector3(c) - pos).length() <= reach):
					found.append(i)
	found.sort()
	for i in found:
		result.append(system_cells[i])
	return result


## 星系快照，回合末看的时候同一个星系只拍一次。
func _snapshot_once(c: Vector3i) -> Dictionary:
	if _view_cache.is_empty():
		return snapshot(c)
	var snaps: Dictionary = _view_cache.get("snaps", {})
	if not snaps.has(c):
		snaps[c] = snapshot(c)
	return snaps[c]


## 每只眼睛看一遍：据点看到的当回合就知道；舰船、探测器看到的按光速传回（G7.6）。
func _observe(civ: Civ) -> void:
	var home_pos := Vector3(civ.home)
	if civ.colonies.is_empty() and civ.has_starship():
		home_pos = civ.starship().pos
	var bases := civ.bases()
	# 还没压缩过时，星系格子都还在
	var may_vanish := not flattened.is_empty() or not linearized.is_empty()
	var snaps: Dictionary = _view_cache.get("snaps", {})
	for o in observers(civ):
		var pos: Vector3 = o["pos"]
		var report := {"cells": {}, "ships": [], "wakes": [], "turn": turn}
		# 球形视野：和 in_view 一样只看 r 以内，找的时候就按距离挑好。圆锥边上还加了半格，多找 1 格，再用 in_view 挑
		var sphere: bool = o["dir"] == Vector3.ZERO
		var reach: float = o["r"] + (1e-6 if sphere else 1.0)
		var cells: Dictionary = report["cells"]
		var may_block := _may_block(pos - Vector3.ONE * reach, pos + Vector3.ONE * reach)
		var near := _systems_near(pos, reach, sphere)
		for c in near:
			var p := Vector3(c)
			if (may_vanish and not cell_exists(c)) or (not sphere and not in_view(o, p)) or (may_block and blocked(pos, p)):
				continue
			if not snaps.has(c):
				snaps[c] = snapshot(c)
			cells[c] = snaps[c]
		for other in civs:
			if other == civ or not other.alive:
				continue
			for s in other.ships:
				# 智子太小，看不到
				if not s.dead and not s.docked and s.kind != Ship.SOPHON and in_view(o, s.pos) and not blocked(pos, s.pos):
					# 看到别的文明的舰船（光粒除外）也算发现别人（I 级）
					report["ships"].append({"pos": s.pos, "kind": s.kind, "turn": turn,
							"civ_ship": s.kind != Ship.GRAIN})
			for f in other.foils:
				if f.prepare_left == 0 and in_view(o, f.position()):
					report["ships"].append({"pos": f.position(), "kind": foil_kind(f), "turn": turn})
		for s in hidden_ships:
			if in_view(o, s.pos):
				report["ships"].append({"pos": s.pos, "kind": s.kind, "turn": turn})
		for i in wakes.size():
			var w: Dictionary = wakes[i]
			if w["gone"] or civ.wakes_seen.has(i):
				continue
			var a: Vector3 = w["a"]
			var b: Vector3 = w["b"]
			if in_view(o, a) or in_view(o, b) or in_view(o, (a + b) / 2.0):
				report["wakes"].append(i)
		if o["base"]:
			_apply_detail(civ, report)
			_apply_home(civ, report)
		else:
			# 按光速传回：经过光速低的地方会慢一些，经过光速几乎为 0 的地方传不回来（G14）
			var to_base := INF
			for b in bases:
				# 光走的时间不会比直线距离短，比已经找到的还远的据点不用细算
				if pos.distance_to(b) <= to_base + 1e-6:
					to_base = minf(to_base, light_time(pos, b))
			if to_base == INF:
				continue
			var to_home := light_time(pos, home_pos)
			report["detail_at"] = turn + ceili(to_base - 1e-6)
			report["home_at"] = turn + ceili(to_home - 1e-6) if to_home != INF else NEVER
			report["detail_done"] = false
			civ.reports.append(report)
	_sophon_watch(civ)


## 智子锁住的文明：它的星系和在飞的单位当回合就知道，不用等光传回（D5）。
func _sophon_watch(civ: Civ) -> void:
	for s in civ.ships:
		if s.kind != Ship.SOPHON or s.dead or s.lock < 0:
			continue
		var victim := civs[s.lock]
		if not victim.alive:
			continue
		for c in victim.colonies:
			civ.intel[c] = _snapshot_once(c)
			civ.known[c] = turn
		for t in victim.ships:
			if not t.dead and not t.docked and t.kind != Ship.SOPHON:
				civ.sightings.append({"pos": t.pos, "kind": t.kind, "turn": turn})


## 情报传回最近的据点：记下细节（鼠标停在格子上能看到）。
func _apply_detail(civ: Civ, report: Dictionary) -> void:
	for c in report["cells"]:
		var info: Dictionary = report["cells"][c]
		if not civ.intel.has(c) or civ.intel[c]["turn"] <= info["turn"]:
			civ.intel[c] = info


## 情报传回母星系：敌人的星系、舰船、航迹显示在星图上；看到别人的星系或舰船就算发现别人（B8、T3）。
func _apply_home(civ: Civ, report: Dictionary) -> void:
	for c in report["cells"]:
		var info: Dictionary = report["cells"][c]
		var owner: Civ = civs[info["owner"]] if info["owner"] >= 0 else null
		if owner != null and owner != civ:
			if not civ.known.has(c) or civ.known[c] <= info["turn"]:
				civ.known[c] = info["turn"]
			civ.record_empty.erase(c)
			_discover(civ, "发现了别的文明的星系（%s）" % c)
		elif civ.known.has(c) and civ.known[c] <= info["turn"]:
			civ.known.erase(c)
	for sight in report["ships"]:
		civ.sightings.append(sight)
		if sight.get("civ_ship", false):
			_discover(civ, "发现了别的文明的舰船")
	for i in report["wakes"]:
		civ.wakes_seen[i] = true


func _deliver_reports(civ: Civ) -> void:
	var still: Array[Dictionary] = []
	for r in civ.reports:
		if not r["detail_done"] and turn >= r["detail_at"]:
			_apply_detail(civ, r)
			r["detail_done"] = true
		if turn >= r["home_at"]:
			_apply_home(civ, r)
		elif r["home_at"] != NEVER or not r["detail_done"]:
			still.append(r)
	civ.reports = still
	_expire_intel(civ)


## 太旧的目击记录删掉；预警只报这一回合的，清空。灭亡的文明不再收到新情报，旧的也照样过期。
func _expire_intel(civ: Civ) -> void:
	civ.sightings = civ.sightings.filter(func(x): return x["turn"] >= turn - Balance.SIGHTING_KEEP)
	if not civ.alive:
		civ.alerts.clear()


## 预警系统：敌方的战舰、光粒、二向箔或单向著进入预警范围，报告它的位置（T12）。
func _warn(civ: Civ) -> void:
	civ.alerts.clear()
	if not civ.has_warning or civ.colonies.is_empty():
		return
	var r := civ.warning_range()
	var things: Array = []  # [位置, 种类]
	for other in civs:
		if other == civ or not other.alive:
			continue
		for s in other.ships:
			if not s.dead and not s.docked and (s.kind == Ship.WARSHIP or s.kind == Ship.GRAIN):
				things.append([s.pos, s.kind])
		for f in other.foils:
			if f.prepare_left == 0 and foil_works(f):
				things.append([f.position(), foil_kind(f)])
	for s in hidden_ships:
		things.append([s.pos, s.kind])
	for f in hidden_foils:
		if foil_works(f):
			things.append([f.position(), foil_kind(f)])
	for t in things:
		if _nearest(civ.colonies, t[0]) <= r + 1e-6:
			var alert := {"pos": t[0], "kind": t[1], "turn": turn}
			civ.alerts.append(alert)
			civ.sightings.append(alert)
			if civ == human():
				var names := {Ship.WARSHIP: "敌方战舰", Ship.GRAIN: "光粒", "foil": "二向箔", "line_foil": "单向著"}
				var p: Vector3 = t[0]
				add_log("预警：%s在 (%.1f, %.1f, %.1f)" % [names[t[1]], p.x, p.y, p.z])


## 星系和星舰视野里的格子数（暗能量采集用，按球的体积估算）。
func vision_cells(civ: Civ) -> int:
	var total := 0.0
	for o in observers(civ):
		if o["base"]:
			total += 4.0 / 3.0 * PI * pow(o["r"], 3)
	return mini(int(total), StarMap.SIZE * StarMap.SIZE * StarMap.SIZE)


# ---------- 收入 ----------

## 每回合的能量：每个星系的基础能量（按恒星数）、裂变能（每颗类地行星）、戴森球（星系还有恒星时）和暗能量；
## 被困在黑域里的星系产出只有 1/10（向上取整，G14）；每次自身降维后减半。只剩星舰时只有一点点。
func energy_income(civ: Civ) -> int:
	if civ.colonies.is_empty():
		return Balance.STARSHIP_ENERGY if civ.has_starship() else 0
	var total := 0.0
	for c in civ.colonies:
		var e := float(Balance.ENERGY_PER_SYSTEM + Balance.ENERGY_PER_STAR * StarMap.star_count(map.star_at(c)))
		if civ.has_tech("fission"):
			e += map.rocky.get(c, 0) * Balance.FISSION_ENERGY
		if map.star_at(c) != StarMap.Star.NONE:
			e += civ.dysons.get(c, 0) * Balance.DYSON_ENERGY
		if in_black_domain(c):
			e = ceilf(e * Balance.DOMAIN_INCOME)
		total += e
	if civ.has_tech("dark_energy"):
		total += vision_cells(civ) / Balance.DARK_ENERGY_CELLS
	return int(total * civ.output_factor())


## 每回合的矿石：每个星系一些，每艘采矿船再多一些；被困在黑域里的星系只有 1/10（向上取整）。
func mineral_income(civ: Civ) -> int:
	if civ.colonies.is_empty():
		return Balance.STARSHIP_MINERAL if civ.has_starship() else 0
	var total := 0.0
	for c in civ.colonies:
		var m := float(Balance.MINERAL_PER_COLONY + civ.miners.get(c, 0) * Balance.MINER_MINERAL)
		if in_black_domain(c):
			m = ceilf(m * Balance.DOMAIN_INCOME)
		total += m
	return int(total * civ.output_factor())


# ---------- 降维 ----------

## 从 origin（默认母星系）向目标坐标 target 发射二向箔：先准备几个回合，再飞过去。
func launch_foil(civ: Civ, target: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	return _launch_foil(civ, target, origin, false)


func launch_line_foil(civ: Civ, target: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	return _launch_foil(civ, target, origin, true)


## 为什么不能发射二向箔（to_line 时是单向著），能发射时为空。target 为 ANY_TARGET 时不检查目标。
func foil_error(civ: Civ, to_line: bool, target := ANY_TARGET, origin: Vector3i = AT_HOME) -> String:
	if origin == AT_HOME:
		origin = civ.home
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("dimension"):
		return "要先升级科技「维度打击」"
	if civ.reduce_left > 0 or civ.colonies.is_empty():
		return "降维期间、没有星系时不能发射"
	if to_line and not all_flat():
		return "整张星图进入二维后才能发射单向著"
	if not to_line and all_flat():
		return "星图已是二维，请使用单向著"
	if target != ANY_TARGET:
		if not StarMap.in_bounds(target):
			return "目标坐标不在星图内"
		if to_line and target.z != flat_plane:
			return "目标必须在二维平面上"
	if not civ.origins().has(origin):
		return "发射源必须是自己的星系或星舰"
	if target != ANY_TARGET:
		if target == origin:
			return "目标不能是发射源"
		if civ.owns(target):
			return "目标不能是自己的星系"
		if (linearized.has(target) if to_line else flattened.has(target)):
			return "这一格已经压成直线了，换一个目标" if to_line else "这一格已经压平了，换一个目标"
	return _pay_error(civ, action_cost("launch_line_foil" if to_line else "launch_foil"))


func _launch_foil(civ: Civ, target: Vector3i, origin: Vector3i, to_line: bool) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := foil_error(civ, to_line, target, origin)
	if error != "":
		return {"error": error}
	civ.energy -= action_cost("launch_line_foil" if to_line else "launch_foil")
	civ.actions_left -= 1
	civ.foils.append(Foil.new(Vector3(origin), target, Balance.FOIL_PREPARE_TURNS, to_line))
	if not civ.is_ai:
		add_log("%s开始准备，目标 %s，%d 回合后起飞" % ["单向著" if to_line else "二向箔", target, Balance.FOIL_PREPARE_TURNS])
	_record(civ, "launch_line_foil" if to_line else "launch_foil", [target, origin])
	return {"error": ""}


## 每片箔：还在准备的，准备回合减一；已经起飞的，前进一段。
## 碰到别人的星系（隐藏文明的不会），或到达目标（最后一步直接落在目标上），就在那里展开。
func _advance_foil_list(list: Array[Foil], owner: Civ) -> Array[Foil]:
	var still_flying: Array[Foil] = []
	for foil in list:
		if is_over() and owner != null:
			break
		if foil.prepare_left > 0:
			foil.prepare_left -= 1
			if foil.prepare_left == 0 and owner != null and not owner.is_ai:
				add_log("%s准备完成，起飞" % ("单向著" if foil.to_line else "二向箔"))
			still_flying.append(foil)
			continue
		var from_t := foil.traveled
		foil.traveled = minf(foil.traveled + foil.speed, foil.total_distance())
		var arrived := foil.traveled >= foil.total_distance() - 1e-6
		var at := NO_HIT
		if not foil.precise:
			# 多算一点点，免得浮点误差把目标格子漏掉
			for c in Geometry.cylinder_cells_between(foil.origin, foil.direction(), from_t,
					foil.traveled + 1e-4, 0.0):
				var o := coord_owner(c)
				if o != null and o != owner:
					at = c
					break
		if at == NO_HIT and arrived:
			at = foil.target
		if at == NO_HIT:
			still_flying.append(foil)
			continue
		var name := "单向著" if foil.to_line else "二向箔"
		add_log(("%s在 %s 展开" if owner != null else "一片来历不明的%s在 %s 展开") % [name, at])
		if foil.to_line:
			_unfold_line_foil(at)
		elif not all_flat():
			_unfold_foil(at)
	if owner != null and not owner.alive:
		return []
	return still_flying


## 箔还有没有用：星图已经全部压平，二向箔就没东西可压；压成直线以后，单向著也一样。
func foil_works(f: Foil) -> bool:
	return not all_linear() if f.to_line else not all_flat()


## 预警和看到的舰船里，箔的种类："foil"（二向箔）或 "line_foil"（单向著）。
static func foil_kind(f: Foil) -> String:
	return "line_foil" if f.to_line else "foil"


## 把格子 c 压到高度 plane 的平面上。
func _flatten_cell(c: Vector3i, plane: int) -> void:
	if flattened.has(c) or not StarMap.in_bounds(c):
		return
	flattened[c] = plane
	_compress_cell(c, Vector3i(c.x, c.y, plane), false)
	if all_flat():
		add_log("整张星图已进入二维：可以再次自身降维，并发射单向著")
		_check_winner()


func _linearize_cell(c: Vector3i) -> void:
	if linearized.has(c):
		return
	linearized[c] = line_y
	_compress_cell(c, Vector3i(c.x, line_y, flat_plane), true)
	if all_linear():
		add_log("整张星图已压成一条直线：完成第二次自身降维的文明可以发射奇异点")


## 格子 c 被压缩：里面没降维的文明失去星系、恒星消失、舰船毁掉；降维的文明连同星系、舰船搬到 flat。
## 那里的航迹也消失（G13.2）。
func _compress_cell(c: Vector3i, flat: Vector3i, to_line: bool) -> void:
	var weapon := "单向著" if to_line else "二向箔"
	# 被压到的黑域消失：这一格的光速回到 1.0
	black_domains = black_domains.filter(func(d): return d["center"] != c)
	if not light.is_empty() and StarMap.in_bounds(c) and light[_li(c)] != 1.0:
		light[_li(c)] = 1.0
		_light_moving = true
	var owner := coord_owner(c)
	if owner != null and (owner.line_reduced if to_line else owner.reduced):
		_move_system(owner, c, flat)
	else:
		if c != flat:
			map.stars[c] = StarMap.Star.NONE
		for civ in civs:
			civ.known.erase(c)
		if owner != null:
			if owner == human():
				add_log("你的星系 %s 被%s压缩" % [c, weapon])
			_lose_system(c, owner)
	var axis := 1 if to_line else 2
	for civ in civs:
		var survives := civ.line_reduced if to_line else civ.reduced
		for s in civ.ships:
			# 锁住别人的智子跟着那个文明，不在这一格
			if s.dead or s.cell() != c or s.lock >= 0:
				continue
			if survives:
				s.pos[axis] = flat[axis]
				s.target[axis] = flat[axis]
				s.direction[axis] = 0.0
				s.direction = s.direction.normalized()
			else:
				_destroy(civ, s, weapon)
	for s in hidden_ships:
		if s.cell() == c:
			s.dead = true
	for w in wakes:
		if not w["gone"] and (Vector3i(w["a"].round()) == c or Vector3i(w["b"].round()) == c):
			w["gone"] = true
	_crush_starships_on(flat)


## 压缩以后，停着的星舰和别人的星系落在同一格：和星系重叠一样，星舰毁掉。
## 先压过来的可能是星舰，也可能是星系，所以每压一格都看一次压到的那一格。
## 在飞的星舰不算，它本来就能飞过别人的星系。
func _crush_starships_on(c: Vector3i) -> void:
	var owner := coord_owner(c)
	if owner == null:
		return
	for civ in civs:
		var ss := civ.starship()
		if civ == owner or not civ.alive or ss == null or ss.direction != Vector3.ZERO or ss.cell() != c:
			continue
		if civ == human():
			add_log("你的星舰被压到 %s 和 %s 的星系重叠，毁掉了" % [c, owner.name])
		_destroy(civ, ss, "")



## 整张星图是不是都压平了。
func all_flat() -> bool:
	if flattened.size() != StarMap.SIZE * StarMap.SIZE * StarMap.SIZE:
		return false
	var plane: int = flattened.values()[0]
	return flattened.values().all(func(z): return z == plane)


## 二维地图只剩一条共同直线。
func all_linear() -> bool:
	return linearized.size() == StarMap.SIZE * StarMap.SIZE and linearized.values().all(func(y): return y == line_y)


## 还存在的格子：压平后只保留平面，压线后只保留直线。
func cell_exists(c: Vector3i) -> bool:
	return StarMap.in_bounds(c) and (not flattened.has(c) or flattened[c] == c.z) \
			and (not linearized.has(c) or linearized[c] == c.y)


## 完成降维的地图里，方向只能沿剩下的轴。
func space_direction(direction: Vector3) -> Vector3:
	if all_flat():
		direction.z = 0.0
	if all_linear():
		direction.y = 0.0
	return direction.normalized() if direction.length() > 1e-6 else Vector3.ZERO


## 降维文明的星系被压到平面上：从 from 搬到 to，恒星、行星和设施跟着走，
## 知道这个坐标的文明也改记新坐标。平面上那一格已经有星系时，就当作被压毁了。
func _move_system(owner: Civ, from: Vector3i, to: Vector3i) -> void:
	if from == to:
		return
	if coord_owner(to) != null:
		if owner == human():
			add_log("你的星系 %s 被压缩后和 %s 的星系重叠，毁掉了" % [from, to])
		map.stars[from] = StarMap.Star.NONE
		for civ in civs:
			civ.known.erase(from)
		_lose_system(from, owner)
		return
	map.stars[to] = map.stars[from]
	map.stars[from] = StarMap.Star.NONE
	for planets in [map.rocky, map.gas]:
		planets[to] = planets.get(from, 0)
		planets.erase(from)
	# 平面上原来那一格的星系被盖掉，宜居与否也跟着搬来的星系
	map.habitable.erase(to)
	if map.habitable.has(from):
		map.habitable.erase(from)
		map.habitable[to] = true
	system_cells.erase(from)
	if not system_cells.has(to):
		system_cells.append(to)
	owner.colonies[owner.colonies.find(from)] = to
	if owner.home == from:
		owner.home = to
	for counts in [owner.dysons, owner.miners]:
		if counts.has(from):
			counts[to] = counts[from]
			counts.erase(from)
	for marks in [owner.bunkers, owner.broadcasters, owner.grains]:
		if marks.has(from):
			marks.erase(from)
			marks[to] = true
	for p in owner.pending:
		if p["at"] == from:
			p["at"] = to
	for s in owner.ships:
		if s.docked and s.cell() == from:
			s.pos = Vector3(to)
	for f in owner.foils:
		if f.prepare_left > 0 and Vector3i(f.origin.round()) == from:
			f.origin = Vector3(to)
	for civ in civs:
		if civ.known.has(from):
			civ.known[to] = civ.known[from]
			civ.known.erase(from)
		if civ.intel.has(from):
			civ.intel[to] = civ.intel[from]
			civ.intel.erase(from)
	if owner == human():
		add_log("你的星系 %s 被压缩，现在在 %s" % [from, to])


## 二向箔在格子 at 展开：平面的高度是第一片箔定下的，马上压平它能压到的格子。
func _unfold_foil(at: Vector3i) -> void:
	if flat_plane < 0:
		flat_plane = at.z
	var zone := {"center": Vector3i(at.x, at.y, flat_plane), "age": 0.0}
	foil_zones.append(zone)
	_apply_zone(zone)


## 胜负结束后也允许环境继续演化，不恢复行动、不结算收入或 AI。
func collapse_pending() -> bool:
	return (not foil_zones.is_empty() and not all_flat()) or (not line_zones.is_empty() and not all_linear())


func advance_collapse() -> void:
	if collapse_pending():
		_spread_flat()
		_clean_dead()


## 每回合每片展开的箔再向外扩散 FOIL_SPREAD 格（T17）。
func _spread_flat() -> void:
	if not all_flat():
		for zone in foil_zones:
			zone["age"] += Balance.FOIL_SPREAD
			_apply_zone(zone)
	if not all_linear():
		for zone in line_zones:
			zone["age"] += Balance.FOIL_SPREAD
			_apply_line_zone(zone)


func _unfold_line_foil(at: Vector3i) -> void:
	if not all_flat() or at.z != flat_plane:
		return
	if line_y < 0:
		line_y = at.y
	var zone := {"center": Vector3i(at.x, line_y, flat_plane), "age": 0.0}
	line_zones.append(zone)
	_apply_line_zone(zone)


## 和二向箔相同的收拢形状，在二维里沿 x 扩散、压缩 y。
static func line_covers(center: Vector3i, age: float, c: Vector3i) -> bool:
	var room := zone_room(age, absf(c.x - center.x))
	return absf(c.x - center.x) <= age or absi(c.y - center.y) > room


func _apply_line_zone(zone: Dictionary) -> void:
	_collapse_depth += 1
	var center: Vector3i = zone["center"]
	for h in StarMap.SIZE:
		for y in ([line_y - h, line_y + h] if h > 0 else [line_y]):
			if y < 0 or y >= StarMap.SIZE:
				continue
			for x in StarMap.SIZE:
				var c := Vector3i(x, y, flat_plane)
				if line_covers(center, zone["age"], c):
					_linearize_cell(c)
	_collapse_depth -= 1
	_check_winner()


## 压平的圆半径为 age、中心在 center 的二向箔，有没有把格子 c 压没。
## 圆里整列都压到平面上；圆外面离圆边 x 格的地方，平面上下各只剩 FOIL_SQUISH × x² 格，超出的被压没。
static func zone_covers(center: Vector3i, age: float, c: Vector3i) -> bool:
	var x := Vector2(c.x - center.x, c.y - center.y).length() - age
	return x <= 0.0 or absi(c.z - center.z) > Balance.FOIL_SQUISH * x * x


## 压平的圆半径为 age 时，离中心水平距离 d 的地方，平面上下各还剩多高（没有剩下时为 0）。
static func zone_room(age: float, d: float) -> float:
	var x := d - age
	return 0.0 if x <= 0.0 else Balance.FOIL_SQUISH * x * x


## 压平这片二向箔压到的格子。离平面近的先压，免得降维文明的星系移到平面上时，
## 撞上待会儿才会被压掉的别人的星系。
func _apply_zone(zone: Dictionary) -> void:
	_collapse_depth += 1
	var center: Vector3i = zone["center"]
	var age: float = zone["age"]
	for h in StarMap.SIZE:
		for z in ([center.z - h, center.z + h] if h > 0 else [center.z]):
			if z < 0 or z >= StarMap.SIZE:
				continue
			for x in StarMap.SIZE:
				for y in StarMap.SIZE:
					var c := Vector3i(x, y, z)
					if not flattened.has(c) and zone_covers(center, age, c):
						_flatten_cell(c, center.z)
	_collapse_depth -= 1
	_check_winner()


## 格子 c 再过几个回合会被压没（已经压没时为 0，没有展开的二向箔时为 INF）。
func turns_until_flat(c: Vector3i) -> float:
	var best := INF
	for zone in foil_zones:
		var center: Vector3i = zone["center"]
		var d := Vector2(c.x - center.x, c.y - center.y).length()
		var h := absi(c.z - center.z)
		var left: float = d - sqrt(h / Balance.FOIL_SQUISH) - zone["age"]
		best = minf(best, maxf(0.0, left / Balance.FOIL_SPREAD))
	return best


## 为什么现在不能开始自身降维（能开始时为空）。
func reduce_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("dimension"):
		return "要先升级科技「维度打击」"
	if civ.line_reduced:
		return "已经进入一维"
	if civ.reduce_left > 0:
		return "正在降维，还剩 %d 回合" % civ.reduce_left
	if civ.reduced and not all_flat():
		return "整张星图进入二维后才能再次降维"
	if not civ.pending.is_empty():
		return "请先完成建造，再开始降维"
	return _pay_error(civ, civ.reduce_cost())


## 开始自身降维：花能量和 1 个行动点，几个回合后完成，期间不能建造。
func start_reduce(civ: Civ) -> Dictionary:
	var error := reduce_error(civ)
	if error != "":
		return {"error": error}
	var cost := civ.reduce_cost()
	civ.energy -= cost
	civ.actions_left -= 1
	civ.reduce_left = Balance.REDUCE_TURNS
	if not civ.is_ai:
		add_log("携带 %d 个单位，消耗 %dE；开始自身降维到%s，%d 回合后完成，期间不能建造" % [
				civ.reduce_units(), cost, "一维" if civ.reduced else "二维", Balance.REDUCE_TURNS])
	_record(civ, "start_reduce", [])
	return {"error": ""}


func _advance_reduce(civ: Civ) -> void:
	if civ.reduce_left <= 0:
		return
	civ.reduce_left -= 1
	if civ.reduce_left == 0:
		if civ.reduced:
			civ.line_reduced = true
		else:
			civ.reduced = true
		if not civ.is_ai:
			add_log("自身降维完成：进入%s，产能为原来的 %s" % ["一维" if civ.line_reduced else "二维", "1/4" if civ.line_reduced else "1/2"])


## 为什么现在不能发射奇异点（能发射时为空）。
func singularity_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("dimension"):
		return "要先升级科技「维度打击」"
	if not all_linear():
		return "整张星图压成直线后才能发射奇异点"
	if not civ.line_reduced:
		return "要先降到一维"
	if civ.singularity_left > 0:
		return "奇异点正在准备，还剩 %d 回合" % civ.singularity_left
	return _pay_error(civ, action_cost("launch_singularity"))


## 全图压成直线后，已经进入一维的文明发射奇异点，准备几个回合后降到零维，赢得对局（T14）。
func launch_singularity(civ: Civ) -> Dictionary:
	var error := singularity_error(civ)
	if error != "":
		return {"error": error}
	civ.energy -= action_cost("launch_singularity")
	civ.actions_left -= 1
	civ.singularity_left = Balance.SINGULARITY_TURNS
	add_log("%s发射了奇异点，%d 回合后降到零维" % [civ.name if civ != human() else "你", Balance.SINGULARITY_TURNS])
	_record(civ, "launch_singularity", [])
	return {"error": ""}


func _advance_singularity(civ: Civ) -> void:
	if civ.singularity_left <= 0 or zero_winner != null:
		return
	civ.singularity_left -= 1
	if civ.singularity_left == 0:
		zero_winner = civ
		add_log("%s降到了零维，整个宇宙只剩一个点" % civ.name)
		_check_winner()


# ---------- 黑域 ----------

## 为什么不能在 center 投放黑域（能投放时为空）。center 为 ANY_TARGET 时不检查位置。
## 只能投放在自己现在看得到的地方（星系和星舰的视野，G14）。
func domain_error(civ: Civ, center := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("domain"):
		return "要先升级科技「黑域投放」"
	if civ.reduce_left > 0 or civ.colonies.is_empty():
		return "降维期间、没有星系时不能投放"
	if center != ANY_TARGET:
		if not StarMap.in_bounds(center):
			return "坐标不在星图内"
		if not cell_exists(center):
			return "压平的空间不能生成黑域"
		if not sees_now(civ, center):
			return "只能投放在自己现在看得到的地方"
	return _pay_error(civ, action_cost("launch_black_domain"))


## 在 center 投放黑域（科技 303）：准备几个回合后，那一格的光速变成 0（G14）。
func launch_black_domain(civ: Civ, center: Vector3i) -> Dictionary:
	var error := domain_error(civ, center)
	if error != "":
		return {"error": error}
	civ.energy -= action_cost("launch_black_domain")
	civ.actions_left -= 1
	civ.pending_domains.append({"center": center, "left": Balance.BLACK_DOMAIN_PREPARE_TURNS})
	if not civ.is_ai:
		add_log("开始投放黑域，位置 %s，%d 回合后生效" % [center, Balance.BLACK_DOMAIN_PREPARE_TURNS])
	_record(civ, "launch_black_domain", [center])
	return {"error": ""}


func _advance_domains(civ: Civ) -> void:
	var still: Array[Dictionary] = []
	for d in civ.pending_domains:
		d["left"] -= 1
		if d["left"] > 0:
			still.append(d)
			continue
		var center: Vector3i = d["center"]
		if not cell_exists(center):
			continue
		_ensure_light()
		light[_li(center)] = 0.0
		_light_moving = true
		black_domains = black_domains.filter(func(x): return x["center"] != center)
		black_domains.append({"center": center, "left": Balance.BLACK_DOMAIN_TURNS})
		add_log("%s 出现黑域：那一格的光速变成 0，保持 %d 回合，再慢慢向周围扩散" % [center, Balance.BLACK_DOMAIN_TURNS])
	civ.pending_domains = still


## 黑域中心倒数，然后光速向周围扩散一格。
func _tick_domains() -> void:
	var still: Array[Dictionary] = []
	for d in black_domains:
		d["left"] -= 1
		if d["left"] > 0:
			still.append(d)
		else:
			add_log("%s 的黑域中心不再保持光速为 0，开始慢慢恢复" % d["center"])
	black_domains = still
	_spread_light()


## 光速扩散（G14）：每一格变成它自己和周围 26 格（星图里的）的平均，所以比周围慢的格子每回合向外扩散一格，
## 慢的格子也被周围拉快一点。黑域中心在保持期内一直是 0。几个黑域自然叠在一起算。
## 依次沿 x、y、z 三个方向各取一次相邻三格的平均，结果和直接取 3×3×3 的平均一样，但快得多。
func _spread_light() -> void:
	if not _light_moving:
		return
	var n := StarMap.SIZE
	var before := light
	var a := light
	for axis in 3:
		var stride: int = [n * n, n, 1][axis]
		var b := PackedFloat64Array()
		b.resize(a.size())
		for i in a.size():
			var k := (i / stride) % n
			var sum := a[i]
			var count := 1
			if k > 0:
				sum += a[i - stride]
				count += 1
			if k < n - 1:
				sum += a[i + stride]
				count += 1
			b[i] = sum / count
		a = b
	for d in black_domains:
		a[_li(d["center"])] = 0.0
	light = a
	# 扩散均匀了（没有黑域中心，各格几乎不再变化）就停下，省得每回合重算
	var change := 0.0
	for i in light.size():
		change = maxf(change, absf(light[i] - before[i]))
	_light_moving = not black_domains.is_empty() or change > 1e-6


func _ensure_light() -> void:
	if light.is_empty():
		light.resize(StarMap.SIZE * StarMap.SIZE * StarMap.SIZE)
		light.fill(1.0)


static func _li(c: Vector3i) -> int:
	return (c.x * StarMap.SIZE + c.y) * StarMap.SIZE + c.z


## 格子 c 的光速（G14），开始是 1.0，被黑域拉低。星图外的都是 1.0。
func light_at(c: Vector3i) -> float:
	if light.is_empty() or not StarMap.in_bounds(c):
		return 1.0
	return light[_li(c)]


## 光从 a 走到 b 要几个回合：每一小段按那里的光速算（G14）。路上有光速几乎为 0 的格子（包括两头），过不去，返回 INF。
func light_time(a: Vector3, b: Vector3) -> float:
	var length := a.distance_to(b)
	if light.is_empty() or length < 1e-6:
		return length
	var n := maxi(1, ceili(length / 0.25))
	var t := 0.0
	for i in n:
		var c := light_at(Vector3i((a + (b - a) * ((i + 0.5) / n)).round()))
		if c < Balance.SHIP_MIN_SPEED:
			return INF
		t += length / n / c
	return t


## 光从 a 走到 b 要不要超过 limit 个回合。光速最多是 1，光走的时间不会比直线距离短，
## 直线距离已经超过 limit 的不用一段段算。
func _light_within(a: Vector3, b: Vector3, limit: float) -> bool:
	return a.distance_to(b) <= limit + 1e-6 and light_time(a, b) <= limit


## 光从 p 能不能在 limit 个回合内传到文明的某个据点（星系、星舰）。
func _light_reaches_bases(civ: Civ, p: Vector3, limit: float) -> bool:
	for b in civ.bases():
		if _light_within(p, b, limit):
			return true
	return false

## 舰船以 speed 从 from 沿 direction 飞一回合，实际飞多远：每一小段的速度都乘以那里的光速（G14）。
func _travel(from: Vector3, direction: Vector3, speed: float) -> float:
	if light.is_empty():
		return speed
	var dist := 0.0
	var time := 1.0
	while time > 1e-9:
		var v := speed * light_at(Vector3i((from + direction * dist).round()))
		if v < 1e-9:
			break
		var step := 0.25
		var dt := step / v
		if dt > time:
			step = v * time
			dt = time
		dist += step
		time -= dt
	return dist


## 自己所有星系和星舰都被困在光速为 0 的黑域里，就算输（B4、G14）。
func _check_hiding() -> void:
	if light.is_empty():
		return
	for civ in civs:
		if not civ.alive:
			continue
		var all_in := true
		for c in civ.origins():
			all_in = all_in and light_at(c) < Balance.SHIP_MIN_SPEED
		if all_in:
			add_log("%s 把自己全部困在了光速为 0 的黑域里，再也出不来，算输" % civ.name)
			_die(civ)


## 这个格子在不在黑域里：光速低到光粒没有杀伤力（G14）。在里面的星系产出只有 1/10。
func in_black_domain(c: Vector3i) -> bool:
	return light_at(c) < Balance.GRAIN_MIN_LIGHT


## 从 a 能不能看到 b：路上（包括两头）有光速几乎为 0 的格子，光过不去，挡住（G14）。
func blocked(a: Vector3, b: Vector3) -> bool:
	if light.is_empty():
		return false
	if _view_cache.is_empty():
		return light_time(a, b) == INF
	# 路上取的点四舍五入到格子；格子中心离路线超过半个对角线（约 0.87）时，取的点不会落在这一格里
	var ab := b - a
	var len2 := ab.length_squared()
	for d: Vector3 in _view_cache["dark"]:
		var t := clampf((d - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		if (a + ab * t).distance_to(d) <= 0.9:
			return light_time(a, b) == INF
	return false


## 两头都在 lo～hi 这个方盒里的路线，有没有可能被光速几乎为 0 的格子挡住。
## 只在回合末看的时候（_view_cache）知道这些格子在哪，别的时候一律当作可能。
## 路上取的点四舍五入到格子，不会超出方盒各半格；这些格子都在方盒外 1 格以上时，一定挡不住。
func _may_block(lo: Vector3, hi: Vector3) -> bool:
	if light.is_empty():
		return false
	if _view_cache.is_empty():
		return true
	for d: Vector3 in _view_cache["dark"]:
		if d.x >= lo.x - 1.0 and d.y >= lo.y - 1.0 and d.z >= lo.z - 1.0 and d.x <= hi.x + 1.0 and d.y <= hi.y + 1.0 and d.z <= hi.z + 1.0:
			return true
	return false


# ---------- 失去星系和灭亡 ----------

## 文明失去一个星系，那里的设施和停着的单位（星舰除外）也没了。星系全丢了、又没有星舰，文明灭亡。
func _lose_system(c: Vector3i, owner: Civ) -> void:
	owner.colonies.erase(c)
	owner.dysons.erase(c)
	owner.miners.erase(c)
	owner.bunkers.erase(c)
	owner.broadcasters.erase(c)
	owner.grains.erase(c)
	owner.pending = owner.pending.filter(func(p): return p["at"] != c or p["kind"] == "warning")
	for s in owner.ships:
		if s.docked and s.kind != Ship.STARSHIP and s.cell() == c:
			s.dead = true
	if owner.colonies.is_empty():
		owner.pending.clear()
		if owner.has_starship():
			owner.home = owner.starship().cell()
			add_log("%s 失去了所有星系，只剩星舰" % owner.name)
		else:
			_die(owner)
	elif owner.home == c:
		owner.home = owner.colonies[0]


## 文明灭亡，准备中和在飞的东西也随之消失（已经发出的光粒除外）。
func _die(owner: Civ) -> void:
	if not owner.alive:
		return
	for s in sophons_on(owner):
		s.dead = true
	owner.alive = false
	for s in owner.ships:
		if s.kind != Ship.GRAIN:
			s.dead = true
	owner.foils.clear()
	owner.pending_domains.clear()
	add_log("%s 灭亡" % owner.name)
	_check_winner()


## 观战或者玩家死后接着打的，胜负（winner）写赢家的名字，不写「你」「AI」。
func winner_by_name() -> bool:
	return spectator or (play_on_after_death and not human().alive)


## 每有文明灭亡就重新判断一次。二向箔可能让好几个文明同时灭亡，
## 所以已经分出胜负后还会再改（例如你灭亡后，剩下的 AI 也被压平，就变成「无」）。
func _check_winner() -> void:
	if _collapse_depth > 0:
		return
	var alive := civs.filter(func(c): return c.alive)
	var result := ""
	var by_name := winner_by_name()
	if zero_winner != null:
		result = zero_winner.name if by_name else ("你" if zero_winner == human() else "AI")
	elif alive.is_empty():
		result = "无"
	elif not spectator and not play_on_after_death and not human().alive:
		result = "AI"
	elif alive.size() == 1:
		result = alive[0].name if by_name else "你"
	elif all_linear() and line_turns >= Balance.LINE_GRACE_TURNS:
		result = "平局"
	if result == "" or result == winner:
		return
	winner = result
	if by_name and result not in ["无", "平局"]:
		add_log("%s 胜利" % result)  # 观战局里 0 号文明也叫「你」，不能当成玩家赢了
		return
	match result:
		"你": add_log("你胜利了")
		"AI": add_log("你失败了")
		"无": add_log("所有文明都灭亡了")
		"平局": add_log("整张星图压成直线 %d 回合后还剩 %d 个文明，平局" % [line_turns, alive.size()])
		_: add_log("%s 胜利" % result)


# ---------- 小工具 ----------

func _common_error(civ: Civ) -> String:
	if is_over():
		return "对局已结束"
	if not civ.alive:
		return "文明已灭亡"
	return ""


## 行动点、能量、矿石够不够（够时为空）。
func _pay_error(civ: Civ, energy: int, mineral := 0) -> String:
	if civ.actions_left <= 0:
		return "行动点用完了，结束回合后恢复"
	if civ.energy < energy:
		return "能量不足（还差 %d）" % (energy - civ.energy)
	if civ.mineral < mineral:
		return "矿石不足（还差 %d）" % (mineral - civ.mineral)
	return ""


## p 离这些格子里最近的一个多远（没有格子时为 INF）。
static func _nearest(cells: Array[Vector3i], p: Vector3) -> float:
	var best := INF
	for c in cells:
		best = minf(best, Vector3(c).distance_to(p))
	return best


func random_direction() -> Vector3:
	var d := Vector3.ZERO
	while d.length() < 0.1:
		d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return d.normalized()


func add_log(line: String) -> void:
	log_lines.append(line)
