class_name GameState
extends RefCounted
## 等同刻伤亡、工程和空间变换结算完毕后采集战场侦察截面。
var pending_battle_surveys: Array[Dictionary] = []
## 私有的传感器原始录像缓冲；仅实际收件者收到查询后才可转发。AI/UI不能读取。
var battle_archive: Dictionary = {}
## 私有事件号与各收件方本地战报号之间的映射，不进入玩家/AI历史。
var battle_tokens: Dictionary = {}
var survey_sequence := -1

## 仅供模拟统计；不参与规则状态或回放校验。
signal civilization_eliminated(civ: Civ, cause: String)
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
const FACILITIES := Construction.FACILITIES
## 调试时 dev_set 不能直接改的文明属性：直接改会让别处对不上（比如灭亡了却还占着星系）
const DEV_SET_LOCKED := ["is_ai", "alive", "name", "home"]
## 造好后停在星系里、要另外派出的单位
const UNITS := Construction.UNITS
const BUILD_NAMES := Construction.NAMES
## 每种建造要哪项科技
const BUILD_TECH := Construction.TECH
## 智子看到被锁的文明做了什么时，日志里怎么写（只写给玩家看）
const SOPHON_REPORTS := {"dispatch": "派出了一个单位", "turn_ship": "让舰船转向", "send_colony": "派殖民船去 %s",
		"move_starship": "让星舰飞向 %s", "settle_starship": "用星舰建立了星系", "launch_grain": "发射了光粒",
		"use_antimatter": "用了反物质", "broadcast": "广播了 %s", "launch_foil": "准备发射二向箔，目标 %s",
		"launch_line_foil": "准备发射单向著，目标 %s", "launch_black_domain": "投放黑域，位置 %s",
		"start_reduce": "开始自身降维", "launch_singularity": "发射了奇异点", "send_sophon": "派智子去 %s",
		"upgrade": "升级了射电望远镜或预警范围"}

var dimension := 3
var space_epoch := 0
var fold_anchor := Vector3i.ZERO
var line_anchor := Vector3i.ZERO
var visual_offset := Vector3.ZERO
var last_mapping := {}
var map: StarMap
var civs: Array[Civ] = []
var turn := 1
var clock := 0.0
## 格子ID不随729格的展开映射改变；局部空间维度与全图维度独立。
var cell_ids: Dictionary[Vector3i, int] = {}
var cell_dims: Dictionary[int, int] = {}
var projectiles: Array[Dictionary] = []
var payloads: Array[Dictionary] = []
var events: Array[Dictionary] = []
var applied_hits: Dictionary[int, bool] = {}
var messages: Array[Dictionary] = []
var scans: Array[Dictionary] = []
var neutral_assets: Array[Dictionary] = []
var sensor_stamps: Dictionary = {}
var next_sensor_time := 0.0
var domain_cells: Dictionary[int, Dictionary] = {}
var zero_zones: Array[Dictionary] = []
var remap_until := -1.0
var deadlines: Array[Dictionary] = []
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
## 它和下面的 foil_zones、fold_anchor 用的是三维时的坐标，展开成二维（DimensionSpace.commit）以后不再换，只在三维阶段读；
## linearized、line_zones、line_anchor 同样只在二维阶段读。
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
## 展开的二向箔：每项是 {"center": 展开的格子, "age": 压平的球的半径（每回合加 FOIL_SPREAD）}
var foil_zones: Array[Dictionary] = []
## 全图共同平面的高度：第一回合展开的二向箔 z 的平均（U3），后续展开不会再产生不同高度的平面。
var flat_plane := -1
## 二维格子压到共同直线的 y（第一回合展开的单向著 y 的平均）；z 始终为 flat_plane，直线沿 x 轴。
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
## 开局时 balance.cfg 的数值（回放从这些数值开始，中途改的数值在 history 里）
var start_balance := {}
## 用调试功能改过数值。以后做成绩、成就时，这样的对局不算。
var dev_used := false


## 第一个文明是人类玩家，其余是 AI。母星优先放在宜居星系上。
## 开一局新的。spectator 为真时是观战局：玩家的文明也交给 AI。
static func new_game(seed_value: int, ai_count: int = Balance.AI_COUNT, spectator := false) -> GameState:
	var s := GameState.new()
	s.seed_value = seed_value
	s.ai_count = ai_count
	s.spectator = spectator
	s.start_balance = Balance.values()
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
	for home in homes:
		s.map.rocky[home] = maxi(1, s.map.rocky.get(home, 0))

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
		if not s.map.contains(c) and not s.hidden.has(c):
			s.hidden.append(c)
	for civ in s.civs:
		Assets.ensure(s, civ)
		civ.intel[civ.home] = s.snapshot(civ.home)
		s.start_turn(civ)
	s.human().is_ai = spectator  # 开局这一眼照玩家算，和以前的对局记录一样
	s.ensure_cells()
	Signals.sample(s, true)
	Signals.receive_due(s)
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

## 改一个数值（全局有效，直到再改回来或者重新开局）。
func dev_balance(name: String, value: Variant) -> Dictionary:
	var err := Balance.set_value(name, value)
	if err != "":
		return {"error": err}
	_dev_record(-1, "dev_balance", [name, value])
	return {"error": ""}


## 改一个文明的属性（能量、矿石、行动点、望远镜等级等，DEV_SET_LOCKED 里的除外）。
func dev_set(civ: Civ, field: String, value: Variant) -> Dictionary:
	if not field in civ:
		return {"error": "文明没有 %s 这一项" % field}
	if DEV_SET_LOCKED.has(field):
		return {"error": "%s 不能直接改（由谁控制用 set_autoplay，灭亡和母星系由规则管）" % field}
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
	var parts: Array = [turn, clock, winner, steps, _next_id, flattened.size(), linearized.size(), dimension, space_epoch, map.extent, light, rng.state, cell_ids, cell_dims]
	parts.append([map.stars, map.rocky, map.gas, map.habitable, messages, projectiles, payloads,
			domain_cells, black_domains, deadlines, sensor_stamps, next_sensor_time, zero_zones, remap_until, applied_hits])
	parts.append([scans,neutral_assets,hidden_listen,foil_zones,line_zones,pending_battle_surveys,battle_archive,battle_tokens,survey_sequence])
	for wave in broadcasts:
		parts.append([wave["id"],wave["from"],wave["target"],civs.find(wave["sender"]),wave["samples"],wave["visited"],wave.get("propagation",{})])
	for civ in civs:
		parts.append([civ.alive, civ.energy, civ.mineral, civ.actions_left, civ.colonies, civ.techs.keys(),
				civ.known.keys(), civ.antimatter, civ.foils.size(), civ.tier1_turn, civ.tier2_turn, civ.tier3_turn])
		parts.append([civ.research_project, civ.pending, civ.miners, civ.advanced_miners, civ.dysons,
				civ.warnings, civ.colonial, civ.dormant_colonies, civ.dormant_dysons, civ.maintenance_priority,
				civ.stopped_packages, civ.emergency_turn, civ.starship_ever_built, civ.dimension_ammo,
				civ.discovered, civ.contacted, civ.conquered,civ.pending_permissions,
				civ.battle_reports,civ.battle_surveys,civ.battle_queries,civ.conquest_confirmation])
		parts.append([civ.assets, civ.flow_remainder, civ.ledger, civ.conversion_receipts, civ.conversions,
				civ.telemetry, civ.intel, civ.sightings, civ.wake_reports, civ.domain_ready_at, civ.scan_ready_at])
		parts.append([civ.command_pending,civ.command_results,civ.ai_receipt_cursor,civ.coverage,civ.local_contacts_by_source,civ.order_reports,civ.payload_reports,civ.site_reports,civ.front_reports,civ.broadcast_reports,civ.original_home,civ.original_anchor_id])
		for sh in civ.ships:
			parts.append([sh.id, sh.kind, sh.pos, sh.docked, sh.direction, sh.damage, sh.lock])
			parts.append([sh.modules, sh.cost, sh.dormant, sh.entity_dim, sh.conversion_receipts,
					sh.salvage_claimed, sh.work_locked,sh.carried_rocky])
			parts.append([sh.speed, sh.target, sh.has_target, sh.pause_until, sh.last_hit, sh.next_repair,
					sh.fired_turn, sh.contact_ids, sh.ready, sh.command, sh.local_contacts, sh.weapon_policy,
					sh.target_id, sh.channel, sh.ammo_reserved, sh.suppression, sh.origin_cell_id,
					sh.last_devour_turn, sh.leg_origin, sh.leg_distance, sh.distance_flown])
	return hash(parts)


## 玩家结束回合：AI 依次行动，然后所有东西移动、交战、扩散，情报传回，结算产出，进入下一回合。
## 每结束一回合记一个校验值，回放时用来检查重算的结果和原来一样。
func end_turn() -> void:
	if is_over():
		return
	var t := Time.get_ticks_usec()
	_end_turn()
	t = Time.get_ticks_usec()
	steps += 1
	checksums.append(checksum())
	_lap("校验值", t)


func _end_turn() -> void:
	ensure_cells()
	for civ in civs:
		Assets.ensure(self, civ)
	# 决策只读取边界前已经到达的信息。各方提交后统一推进，不在AI之间移动或采样。
	Signals.receive_due(self)
	var started := Time.get_ticks_usec()
	for civ in civs:
		if civ.is_ai and civ.alive:
			AI.take_turn(self, civ)
	started = _lap("AI 行动", started)
	WorldTime.advance(self, 1.0)
	_lap("统一连续事件", started)
	for civ in civs:
		_expire_intel(civ)
		if civ.alive:
			_refresh_permissions(civ)
			if not is_over() and civ.is_ai and Balance.TECH_BURST_CHANCE>0.0 and rng.randf()<Balance.TECH_BURST_CHANCE:
				_tech_burst(civ)
			start_turn(civ)
	if not is_over():
		turn += 1
		add_log("第 %d 回合开始" % turn)


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
func _reach_tier(civ: Civ, tier: int, _what: String) -> void:
	if tier == 1:
		civ.discovered = true
	elif tier == 2:
		civ.contacted = true
	_refresh_permissions(civ)


## 发现别人（看到别人的星系或舰船、听到广播）：I 级的条件。
func _discover(civ: Civ, what: String) -> void:
	civ.discovered = true
	_reach_tier(civ, 1, what)


## 为什么不能升级这项科技（能升级时为空）。
func research_error(civ: Civ, id: String) -> String:
	var error := research_block_error(civ, id)
	if error != "":
		return error
	var cost := Tech.cost(id)
	return _pay_error(civ, cost[0], cost[1])


## 前置科技都有了没有。
static func _needs_met(civ: Civ, id: String) -> bool:
	for need in Tech.ALL[id]["needs"]:
		if not civ.has_tech(need):
			return false
	return true


## 除了能量、矿石不够以外，为什么不能升级这项科技（AI 用它挑攒钱的目标）。
func research_block_error(civ: Civ, id: String) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not Tech.ALL.has(id):
		return "没有这项科技"
	if civ.has_tech(id):
		return "已经有了"
	if not Knowledge.research(civ).is_empty():
		return "已有研究进行中"
	if not tier_open(civ, Tech.tier(id)):
		return "%s尚未开放：%s" % [Tech.TIER_NAMES[Tech.tier(id)], Tech.TIER_RULES[Tech.tier(id)]]
	for need in Tech.ALL[id]["needs"]:
		if not civ.has_tech(need):
			return "要先有「%s」" % Tech.ALL[need]["name"]
	if Knowledge.origins(self,civ).is_empty():
		return "没有可进行研究的星系或星舰"
	if Knowledge.site(self,civ,civ.home).get("dormant",false) or (Knowledge.colonies(self,civ).is_empty() and reported_starship(civ)!=null and reported_starship(civ).dormant):
		if id not in ["miner", "fission", "probe", "interstellar_travel", "colony"]:
			return "休眠救援槽只支持基础生产、探测、运输与殖民研究"
	return ""


## 升级一项科技：花资源，不花行动点，马上生效（T15）。返回 {"error": 出错原因，成功时为空}。
func research(civ: Civ, id: String) -> Dictionary:
	var error := research_error(civ, id)
	if error != "":
		return {"error": error}
	var cost := Tech.cost(id)
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.research_project = WorkOrder.create(next_id(), id, civ.home, cost, Tech.work(id), "research")
	if Knowledge.colonies(self,civ).is_empty() and reported_starship(civ)!=null:
		civ.research_project["host_ship"] = reported_starship(civ).id
	OrderControl.submit(self,civ,civ.research_project)
	if not civ.is_ai:
		add_log("开始研究：%s，工作量 %.1f" % [Tech.title(id), Tech.work(id)])
	_record(civ, "research", [id])
	return {"error": "", "order": civ.research_project["id"]}


## AI 的技术爆炸：不花资源直接得到一项能升的科技（D6）。
func _tech_burst(civ: Civ) -> void:
	if Balance.TECH_BURST_CHANCE<=0.0:
		return
	var options: Array[String] = []
	for id in Tech.ALL:
		if not civ.has_tech(id) and id!=Knowledge.research(civ).get("kind","") and tier_open(civ, Tech.tier(id)) and _needs_met(civ, id):
			options.append(id)
	var obtained:=""
	if not options.is_empty():
		obtained=options[rng.randi_range(0, options.size() - 1)]
		civ.techs[obtained] = true
	events.append({"id":next_id(),"kind":"tech_burst","t":clock,"owner":civs.find(civ),"tech":obtained,"granted":obtained!=""})
	if civ==human() and obtained!="":
		add_log("技术爆炸：免费获得%s"%Tech.title(obtained))


## 射电望远镜（"telescope"）或预警范围（"warning"）升一级要多少能量。
static func upgrade_cost(kind: String) -> int:
	return Balance.TELESCOPE_UPGRADE_COST[0][0] if kind == "telescope" else Balance.WARNING_UPGRADE_COST[0]


func upgrade_price(civ: Civ, kind: String, at: Vector3i = AT_HOME) -> Array:
	if at == AT_HOME:
		at = civ.home
	if kind == "telescope":
		return Balance.TELESCOPE_UPGRADE_COST[mini(civ.telescope, Balance.TELESCOPE_MAX - 1)].duplicate()
	return Balance.WARNING_UPGRADE_COST.duplicate()


## 为什么不能升级射电望远镜或预警范围（能升级时为空）。
func upgrade_error(civ: Civ, kind: String, at: Vector3i = AT_HOME) -> String:
	if at == AT_HOME:
		at = civ.home
	var error := _common_error(civ)
	if error != "":
		return error
	if kind == "telescope":
		if civ.telescope >= Balance.TELESCOPE_MAX:
			return "射电望远镜已经升满"
		if OrderControl.visible(self,civ).any(func(project):return project["kind"]=="telescope"):
			return "已有射电望远镜升级待完成或待回报"
	elif kind == "warning":
		if Knowledge.site(self,civ,at).get("warning",-1)<0:
			return "要先在这个星系建预警系统"
		if Knowledge.site(self,civ,at).get("warning",-1) >= Balance.WARNING_MAX:
			return "预警范围已经升满"
		if OrderControl.visible(self,civ).any(func(project):return project["category"]=="upgrade" and project["kind"]=="warning" and project["at"]==at):
			return "这个星系已有预警升级施工或正在等待回报"
	else:
		return "未知的升级"
	var host := construction_host(civ, at)
	if host == -2 or construction_busy(civ, at, host):
		return "升级需要空闲的己方建造队列"
	if Knowledge.site(self,civ,at).get("dormant",false) or (host >= 0 and Signals.reported_ship(self,civ,host).dormant):
		return "休眠锚点不能进行普通升级"
	var cost := upgrade_price(civ, kind, at)
	return _pay_error(civ, cost[0], cost[1])


## 射电望远镜（"telescope"）或预警范围（"warning"）升一级：花能量，不花行动点，马上生效。
func upgrade(civ: Civ, kind: String, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := upgrade_error(civ, kind, at)
	if error != "":
		return {"error": error}
	var cost := upgrade_price(civ, kind, at)
	var work: float = Balance.TELESCOPE_UPGRADE_WORK[civ.telescope] if kind == "telescope" else Balance.WARNING_UPGRADE_WORK
	var project := WorkOrder.create(next_id(), kind, at, cost, work, "upgrade")
	project["host_ship"] = construction_host(civ, at)
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.pending.append(project)
	OrderControl.submit(self,civ,project)
	if not civ.is_ai:
		add_log("开始升级%s，工作量 %.1f" % ["射电望远镜" if kind == "telescope" else "预警范围", work])
	_record(civ, "upgrade", [kind, at])
	return {"error": "", "order": project["id"]}


# ---------- 建造 ----------

## 建造的价格 [能量, 矿石]（含曲率引擎、引力波广播器多花的）。
func build_cost(_civ: Civ, kind: String, modules: Array = []) -> Array:
	var cost := Construction.cost(kind)
	for module in modules:
		var extra: Array = Balance.MODULE_COST.get(module, [0, 0])
		cost[0] += extra[0]
		cost[1] += extra[1]
	return cost


## 现在造的战舰会带哪些武器：升级过的都带上（T23）。
static func warship_weapons(_civ: Civ) -> Array[String]:
	# 裸舰是始终保留的型号；武器由建造/改装订单的选装清单决定。
	return []


## 带一种武器，造战舰多花的 [能量, 矿石]。
static func weapon_extra(w: String) -> Array:
	return Balance.MODULE_COST[w]


## 一种武器开一次火花的 [能量, 矿石]。
static func weapon_shot(w: String) -> Array:
	return Balance.WEAPON_DATA[w]["cost"]


## 一种武器的射程（格）。
static func weapon_range(w: String) -> float:
	return Balance.WEAPON_DATA[w]["range"]


## 为什么不能在 at 建这个（能建时为空）。
func build_error(civ: Civ, kind: String, at: Vector3i, modules: Array = []) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not BUILD_TECH.has(kind):
		return "不能建这个"
	if not civ.has_tech(BUILD_TECH[kind]):
		return "要先升级科技「%s」" % Tech.ALL[BUILD_TECH[kind]]["name"]
	if kind == "landing":
		return "运输船抵达后从行动页建立殖民地"
	var host := construction_host(civ, at)
	var known:=Knowledge.site(self,civ,at)
	var info:=Knowledge.snapshot(self,civ,at)
	if host == -2:
		return "先选择自己的星系或星舰作为建造地点"
	if construction_busy(civ, at, host):
		return "这里的 %d 个建造槽已占满，已有施工或正在等待回报；收到完工或取消回报后释放对应槽位" % construction_capacity(civ,at,host)
	if host >= 0 and FACILITIES.has(kind):
		return "普通星舰上不能建造天体设施"
	if known.get("dormant",false) or (host >= 0 and Signals.reported_ship(self,civ,host).dormant):
		if kind not in ["probe", "colony"]:
			return "休眠救援队列只支持基础探测器或运输船"
	if kind in ["miner", "advanced_miner"]:
		if info.get("rocky",0) <= 0:
			return "根据已收到的观测，这个星系没有可开采的类地行星"
		var count: int = known.get("miners",0) + known.get("advanced_miners",0) + Knowledge.pending(civ,"miner", at) + Knowledge.pending(civ,"advanced_miner", at)
		var limit: int = Balance.MAX_MINERS if civ.has_tech("mining_advanced") else Balance.BASE_MINER_LIMIT
		if count >= limit:
			return "这个星系的矿船已达到 %d 艘" % limit
	if kind == "dyson" and known.get("dysons",0) + Knowledge.pending(civ,kind, at) >= StarMap.star_count(info.get("stars",StarMap.Star.NONE)):
		return "每颗本地恒星最多一座戴森球"
	if kind == "bunker" and (info.get("gas",0) == 0 or known.get("bunker",false) or Knowledge.pending(civ,kind,at)>0):
		return "需要有类木行星，且尚无掩体或掩体工程的星系"
	if kind == "broadcaster" and (known.get("broadcaster",false) or info.get("stars",StarMap.Star.NONE) == StarMap.Star.NONE or Knowledge.pending(civ,kind,at)>0):
		return "需要有恒星，且尚无广播器或广播器工程的星系"
	if kind == "warning" and (known.get("warning",-1)>=0 or Knowledge.pending(civ,kind,at)>0):
		return "这个星系已有预警系统或预警建造工程"
	if kind == "antimatter" and civ.antimatter + Knowledge.pending(civ,kind) >= Balance.MAX_ANTIMATTER:
		return "反物质炸弹已经存满"
	if kind == "grain" and (known.get("grain",false) or Knowledge.pending(civ,kind, at) > 0):
		return "这个星系已经有光粒或在制光粒"
	if kind == "warship" and Knowledge.count(self,civ,Ship.WARSHIP) + Knowledge.pending(civ,kind) >= (3 if civ.has_tech("shield") else 2):
		return "战舰数量已达当前科技上限"
	if kind == "starship" and (civ.starship_ever_built or reported_starship(civ)!=null or Knowledge.pending(civ,kind) > 0):
		return "整局最多建造一艘星舰"
	if kind == "wandering_earth" and (at != civ.home or reported_starship(civ)!=null):
		return "需在母星改造，且不能已有存活星舰"
	if kind == "wandering_earth":
		var earth_error := EarthTransform.known_error(self,civ,EarthTransform.known_options(self,civ),1)
		if earth_error != "":
			return earth_error
	var module_error := _module_error(civ, kind, modules)
	if module_error != "":
		return module_error
	var cost := build_cost(civ, kind, modules)
	return _pay_error(civ, cost[0], cost[1])


## 在自己的星系 at（默认母星系）建造，花 1 行动点。
## 全额托管资源，命令抵达后按工作量建造；完成信息经有限光速回传。
## 成功返回订单ID；单位ID由完成回报提供，前端不能读取未回传的实际成品。
func build(civ: Civ, kind: String, at: Vector3i = AT_HOME, modules: Array = []) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var result := _submit_build(civ,kind,at,modules)
	if result["error"] == "":
		_record(civ, "build", [kind, at, modules.duplicate()])
	return result


func _submit_build(civ: Civ, kind: String, at: Vector3i, modules: Array) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := build_error(civ, kind, at, modules)
	if error != "":
		return {"error": error, "ship": null}
	var cost := build_cost(civ, kind, modules)
	var work := Construction.work(kind)
	for module in modules:
		work += Balance.MODULE_WORK[module]
	var project := WorkOrder.create(next_id(), kind, at, cost, work)
	project["host_ship"] = construction_host(civ, at)
	project["modules"] = modules.duplicate()
	if kind == "wandering_earth":
		project["earth_roster"] = EarthTransform.known_options(self,civ)
		project["earth_rocky"] = 1
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.pending.append(project)
	OrderControl.submit(self,civ,project)
	if not civ.is_ai:
		add_log("开始在 %s 建造%s，工作量 %.1f" % [at, BUILD_NAMES[kind], work])
	return {"error": "", "ship": null, "order": project["id"]}


func _finish_pending(civ: Civ, duration := 1.0, messages_due := true) -> void:
	var changed:=false
	if not civ.research_project.is_empty():
		var research := civ.research_project
		if not research.get("command_ready",true):
			pass
		elif not project_host_alive(civ, research):
			OrderControl.discard(self,civ,research,"destroyed")
			changed=true
		elif WorkOrder.advance(research, project_work_rate(civ, research) * duration):
			OrderControl.report(self,civ,research,"completed")
			civ.research_project = {}
			changed=true
	var remaining: Array[Dictionary] = []
	for project in civ.pending.duplicate():
		if not project.get("command_ready",true):
			remaining.append(project)
			continue
		if not project_host_alive(civ, project):
			OrderControl.discard(self,civ,project,"destroyed")
			changed=true
			continue
		var error:=OrderControl.physical_error(self,civ,project)
		if error!="":
			project["failure_reason"]=error
			OrderControl.discard(self,civ,project,"failed")
			changed=true
			continue
		if WorkOrder.advance(project, project_work_rate(civ, project) * duration):
			_complete_project(civ, project)
			OrderControl.report(self,civ,project,"completed")
			changed=true
		else:
			remaining.append(project)
	civ.pending = remaining
	# 同刻第一批接收后，无完工/失败就没有新增消息或接收实体变化。
	if messages_due or changed:
		Signals.receive_due(self)


# ---------- 调度 ----------

## 每个行动要花的能量（行动名就是 GameState 里的函数名）。派出、转向看单位，见 dispatch_cost。
## 殖民、星舰定居、反物质不花能量。画面显示价格也用这里的数。
static func action_cost(name: String) -> int:
	match name:
		"move_starship": return Balance.COST_STARSHIP_MOVE
		"launch_grain": return Balance.COST_GRAIN_LAUNCH
		"broadcast": return Balance.COST_BROADCAST
		"launch_foil": return 0
		"launch_line_foil": return 0
		"launch_black_domain": return Balance.COST_BLACK_DOMAIN
		"launch_singularity": return 0
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
	var s := Signals.reported_ship(self, civ, id)
	if s == null:
		return "没有这个单位"
	if s.work_locked:
		return "单位正在施工或改装，完成或取消工程后才能派出"
	if not s.docked:
		return "已经派出了"
	if not Ship.AIMED.has(s.kind):
		return "这个单位要选目的地"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	return _pay_error(civ, command_cost(civ, s))


## 派出停在星系里的探测器、战舰或吞噬者，朝 direction 飞。探测器可以选「先慢速飞出视野」（G13.4）。
## 花 1 行动点和一些能量。返回 {"error": 出错原因，成功时为空}。
func dispatch(civ: Civ, id: int, direction: Vector3, slow := false) -> Dictionary:
	var error := dispatch_error(civ, id, direction)
	if error != "":
		return {"error": error}
	var ship := Signals.reported_ship(self, civ, id)
	queue_ship_command(civ, ship, {"name": "dispatch", "direction": direction, "slow": slow}, command_cost(civ, ship))
	_record(civ, "dispatch", [id, direction, slow])
	return {"error": ""}


func turn_error(civ: Civ, id: int, direction: Vector3) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := Signals.reported_ship(self, civ, id)
	if s == null:
		return "没有这个单位"
	if not Ship.TURNABLE.has(s.kind):
		return "只有战舰和吞噬者能转向"
	if s.docked:
		return "还没派出"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	return _pay_error(civ, command_cost(civ, s))


## 在飞的战舰、吞噬者转向（G8）：花 1 行动点和 COST_TURN 能量；转过 90° 以上时速度归零。
func turn_ship(civ: Civ, id: int, direction: Vector3) -> Dictionary:
	var error := turn_error(civ, id, direction)
	if error != "":
		return {"error": error}
	var ship := Signals.reported_ship(self, civ, id)
	queue_ship_command(civ, ship, {"name": "turn_ship", "direction": direction}, command_cost(civ, ship))
	_record(civ, "turn_ship", [id, direction])
	return {"error": ""}


func colony_error(civ: Civ, id: int, target := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := Signals.reported_ship(self, civ, id)
	if s == null or s.kind != Ship.COLONY:
		return "没有这艘殖民船"
	if s.work_locked:
		return "运输船正在落地施工"
	if not s.waiting():
		return "还在飞"
	if target != ANY_TARGET:
		if Knowledge.owns(self,civ,target):
			return "这已经是自己的星系"
		if not colony_target_ok(civ, target):
			return "目的地在星图外"
	return _pay_error(civ, action_cost("send_colony"))


## 派殖民船去 target，不花能量（T13）。停着的（星系里的，或上次到了没能殖民的）都能派。
## 目的地可以是任意格子（F4.4）：到了能殖民就建殖民地，不能就停在那里等下一个目的地。
func send_colony(civ: Civ, id: int, target: Vector3i) -> Dictionary:
	var error := colony_error(civ, id, target)
	if error != "":
		return {"error": error}
	queue_ship_command(civ, Signals.reported_ship(self, civ, id), {"name": "send_colony", "target": target}, 0)
	_record(civ, "send_colony", [id, target])
	return {"error": ""}


func colony_target_ok(civ: Civ, c: Vector3i) -> bool:
	return not Knowledge.owns(self,civ,c) and cell_exists(c)


## 文明知道的、可以去殖民的星系：情报里看到过是宜居、还有恒星，不是自己的，也不是已知的敌方星系（F4.4）。
## 只按情报判断，情报旧了可能已经不能殖民。
func known_habitable(civ: Civ) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for c in civ.intel:
		var info: Dictionary = civ.intel[c]
		if info.get("habitable", false) and info["stars"] != StarMap.Star.NONE and not Knowledge.owns(self,civ,c) \
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
	var s := reported_starship(civ)
	if s == null:
		return "没有收到可用星舰的状态"
	if target != ANY_TARGET:
		if not cell_exists(target):
			return "目的地不在星图里"
		if Vector3(target).distance_to(s.pos) < 1e-6:
			return "已经在那里"
		if not starship_target_ok(civ, target):
			return "那里是已知的敌方星系，不能停"
	if s.work_locked or ship_command_pending(civ,s.id):
		return "星舰正在施工或等待命令回执"
	return _pay_error(civ, command_cost(civ,s))


## 星舰飞向目的地 target，到了就停下（G9）。
func move_starship(civ: Civ, target: Vector3i) -> Dictionary:
	var error := starship_move_error(civ,target)
	if error != "":
		return {"error":error}
	var ship := reported_starship(civ)
	queue_ship_command(civ,ship,{"name":"move_starship","target":target},command_cost(civ,ship))
	_record(civ,"move_starship",[target])
	return {"error":""}


func _set_target(s: Ship, target: Vector3i) -> void:
	s.docked = false
	s.parked = false
	s.has_target = true
	s.target = Vector3(target)
	s.direction = (s.target - s.pos).normalized()


## 为什么星舰现在不能定居（能定居时为空）。
func settle_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	return "星舰本身就是移动家园；建立星系殖民地请用运输船，并先研究「星际殖民」"


## 星舰停在无主的宜居星系上时，在那里建立星系，星舰用掉。花 1 个行动点。
func settle_starship(civ: Civ) -> Dictionary:
	return {"error":settle_error(civ)}


## 加一个星系；只剩星舰的文明落脚时，这里就是新的母星系。
func _add_colony(civ: Civ, c: Vector3i,entity_dim: int = -1) -> void:
	civ.colonies.append(c)
	civ.colonial[c] = true
	Assets.make(self, civ, "anchor", c,[0.0,0.0],entity_dim)
	if civ.colonies.size() == 1:
		civ.home = c


## 为什么不能从 at（默认母星系）朝 direction 发射光粒（能发射时为空）。
func grain_error(civ: Civ, direction: Vector3, at: Vector3i = AT_HOME) -> String:
	if at == AT_HOME:
		at = civ.home
	var error := _common_error(civ)
	if error != "":
		return error
	var known:=Knowledge.site(self,civ,at)
	if not known.get("owned",false) or not known.get("grain",false):
		return "这个星系没有存着光粒"
	if space_direction(direction).length() < 1e-6:
		return "需要指定方向"
	if known.get("relative_light",1.0)<Balance.GRAIN_MIN_LIGHT:
		return "这里在黑域里，光速太低，光粒发出去没有杀伤力"
	return _pay_error(civ, action_cost("launch_grain"))


## 从存着光粒的星系 at（默认母星系）朝 direction 发射光粒。
func launch_grain(civ: Civ, direction: Vector3, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := grain_error(civ, direction, at)
	if error != "":
		return {"error": error}
	Assets.ensure(self,civ)
	var anchor:=Knowledge.anchor(self,civ,at)
	if anchor.is_empty() or ship_command_pending(civ,anchor["id"]):
		return {"error":"等待发射源回报或上一命令回执"}
	queue_entity_command(civ,anchor["id"],anchor["pos"],{"name":"grain","direction":direction},[action_cost("launch_grain"),0],true)
	if not civ.is_ai:
		add_log("从 %s 发射光粒，方向 (%.2f, %.2f, %.2f)" % [at, direction.x, direction.y, direction.z])
	_record(civ, "launch_grain", [direction, at])
	return {"error": ""}


## 离自己星系 ANTIMATTER_RANGE 以内的敌方战舰（最近的在前）。
func antimatter_origins(civ: Civ) -> Array[Dictionary]:
	var origins: Array[Dictionary] = []
	for asset in Knowledge.assets(self,civ):
		if asset["kind"] == "anchor" and not Knowledge.site(self,civ,asset["at"]).get("dormant",false):
			origins.append({"id":asset["id"],"pos":Vector3(asset["at"])})
	for ship in Signals.reported_ships(self,civ):
		if ship.kind == Ship.WARSHIP and not ship.dormant:
			origins.append({"id":ship.id,"pos":ship.pos})
	return origins


func antimatter_targets(civ: Civ) -> Array[Ship]:
	var found: Array = []
	for contact in civ.sightings:
		if contact.get("owner",-1)==civs.find(civ) or not Ship.NAMES.has(contact["kind"]) or contact["kind"]==Ship.GRAIN:
			continue
		var distance := INF
		for origin in antimatter_origins(civ):
			distance = minf(distance,origin["pos"].distance_to(contact["pos"])*physical_cell_size())
		if distance <= Balance.ANTIMATTER_RANGE+Balance.COLLISION_EPSILON:
			var seen := Ship.make(contact["kind"],contact["pos"],contact["id"])
			found.append([distance,seen])
	found.sort_custom(func(a,b):return a[0]<b[0])
	var result: Array[Ship] = []
	for entry in found:
		result.append(entry[1])
	return result


func antimatter_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if civ.antimatter <= 0:
		return "没有反物质炸弹"
	if antimatter_targets(civ).is_empty():
		return "作用范围 %.1fly 内没有已收到的敌舰观测" % Balance.ANTIMATTER_RANGE
	return _pay_error(civ,0)


## 指令送达后由执行节点按本地观测发射；弹药真正发射后不退款。
func use_antimatter(civ: Civ) -> Dictionary:
	var error := antimatter_error(civ)
	if error != "":
		return {"error":error}
	var target := antimatter_targets(civ)[0]
	var origins := antimatter_origins(civ)
	origins.sort_custom(func(a,b):return a["pos"].distance_squared_to(target.pos)<b["pos"].distance_squared_to(target.pos))
	var origin: Dictionary = origins[0]
	var control := Signals.entity(self,civs.find(civ),Signals.controller(civ))
	civ.actions_left -= 1
	civ.antimatter -= 1
	var message := Signals.send(self,civs.find(civ),control["pos"],origin["id"],"command",
		{"name":"antimatter","target_id":target.id,"recipient_pos":origin["pos"],"ammo_reserved":1,"reserved":[0,0]})
	civ.command_pending[message["id"]] = {"recipient":origin["id"],"name":"antimatter","sent":clock}
	Signals.receive_due(self)
	_record(civ,"use_antimatter",[])
	return {"error":""}


func _fire_antimatter(civ: Civ, source: int, target: int) -> bool:
	var receiver := Signals.entity(self,civs.find(civ),source)
	if receiver.is_empty():
		return false
	var contacts: Dictionary
	if receiver.has("ship"):
		var ship: Ship = receiver["ship"]
		if ship.dead or ship.dormant or ship.work_locked or ship.fired_turn == turn:
			return false
		contacts = ship.local_contacts
	else:
		if civ.dormant_colonies.has(receiver["asset"]["at"]):
			return false
		contacts = civ.local_contacts_by_source.get(source,{})
	if not contacts.has(target):
		return false
	var contact: Dictionary = contacts[target]
	if receiver["pos"].distance_to(contact["pos"])*physical_cell_size()>Balance.ANTIMATTER_RANGE+Balance.COLLISION_EPSILON:
		return false
	var speed := light_speed_at(receiver["pos"])
	if speed <= 0.0:
		return false
	var shot := {"id":next_id(),"owner":civs.find(civ),"source":source,"weapon":"antimatter","pos":receiver["pos"],
		"direction":Combat.aim(receiver["pos"],contact["pos"],contact["velocity"],speed/physical_cell_size()),
		"remaining":Balance.ANTIMATTER_RANGE,"distance":0.0,"created":clock,"epoch":space_epoch,"dead":false}
	projectiles.append(shot)
	if receiver.has("ship"):
		receiver["ship"].fired_turn = turn
		receiver["ship"].last_hit = clock
	events.append({"id":shot["id"],"t":clock,"kind":"fire","source":source,"target":target,"weapon":"antimatter"})
	return true


# ---------- 智子（D5） ----------

## 为什么不能派这个智子去 target（能派时为空）。target 为 ANY_TARGET 时不检查目的地。
func sophon_error(civ: Civ, id: int, target := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var s := Signals.reported_ship(self, civ, id)
	if s == null or s.kind != Ship.SOPHON:
		return "没有这个智子"
	if s.lock >= 0:
		return "这个智子已经锁住了别的文明"
	if not s.waiting():
		return "还在飞"
	if target != ANY_TARGET:
		if Knowledge.owns(self,civ,target):
			return "这是自己的星系"
		if not cell_exists(target):
			return "目的地在星图外"
	return _pay_error(civ, command_cost(civ, s))


## 派智子去 target（一出发就以 0.99 倍光速飞）。到了别人的母星系就锁住那个文明，不是就原地待命，可以再派。
func send_sophon(civ: Civ, id: int, target: Vector3i) -> Dictionary:
	var error := sophon_error(civ, id, target)
	if error != "":
		return {"error": error}
	var ship := Signals.reported_ship(self, civ, id)
	queue_ship_command(civ, ship, {"name": "send_sophon", "target": target}, command_cost(civ, ship))
	_record(civ, "send_sophon", [id, target])
	return {"error": ""}


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
	var status:=Knowledge.site(self,civ,c)
	return status.get("owned",false) and not status.get("dormant",false) and not status.get("jammed",false) and (civ.has_tech("gravity") or status.get("broadcaster",false))


func can_broadcast_now(civ: Civ, c: Vector3i) -> bool:
	if not civ.owns(c) or civ.dormant_colonies.has(c) or jammed(civ, c):
		return false
	if civ.has_tech("gravity"):
		return true
	return civ.broadcasters.has(c) and not jammed(civ, c)


## 能听到广播：有引力波广播（203），或者至少有一个能用的恒星广播器（E7F6 2026-10-06）。
func can_hear(civ: Civ) -> bool:
	for c in civ.broadcasters:
		if civ.owns(c) and not civ.dormant_colonies.has(c):
			return true
	return civ.has_tech("gravity") and not civ.colonies.is_empty()


## 有别人的星际探测器停在这个星系上，恒星广播器不能用。
func jammed(civ: Civ, c: Vector3i) -> bool:
	for other in civs:
		if other == civ or not other.alive:
			continue
		for s in other.ships:
			if s.kind == Ship.DROPLET and s.parked and not s.dead and not s.dormant and s.cell() == c:
				return true
	return false


## 为什么不能广播（能广播时为空），参数和 broadcast 一样。target 为 ANY_TARGET 时不检查坐标。
func broadcast_error(civ: Civ, target := ANY_TARGET, source: Vector3i = AT_HOME, ship_id := -1) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if target != ANY_TARGET:
		if not map.contains(target):
			return "坐标不在星图内"
		if Knowledge.owns(self,civ,target):
			return "不能广播自己的坐标"
	if ship_id >= 0:
		var s := Signals.reported_ship(self, civ, ship_id)
		if s == null or not s.gravity or s.dormant:
			return "这艘战舰没有引力波广播器"
	elif not can_broadcast_from(civ, civ.home if source == AT_HOME else source):
		return "这个星系不能广播（要有恒星广播器，而且最近回报未被水滴封锁）"
	return _pay_error(civ, action_cost("broadcast"))


## 广播坐标 target（星图里任何格子）。从星系 source（默认母星系）广播；ship_id 不为 -1 时，
## 从带引力波广播器的战舰广播。广播当回合开始以光速扩散（游戏设计 §8）。
func broadcast(civ: Civ, target: Vector3i, source: Vector3i = AT_HOME, ship_id := -1) -> Dictionary:
	if source == AT_HOME and ship_id < 0:
		source = civ.home
	var error := broadcast_error(civ, target, source, ship_id)
	if error != "":
		return {"error": error}
	var from := Signals.reported_ship(self,civ,ship_id).pos if ship_id>=0 else Vector3(source)
	Assets.ensure(self,civ)
	var recipient:=ship_id
	if recipient<0:
		var anchor:=Knowledge.anchor(self,civ,source)
		if anchor.is_empty():
			return {"error":"没有已知广播宿主"}
		recipient=anchor["id"]
	queue_entity_command(civ,recipient,from,{"name":"broadcast","target":target},[action_cost("broadcast"),0],true)
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
		if b["radius"] < map.extent.length() * 6:
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


## 单位在 at 时的 [最高速度, 每回合加速]：曲率引擎在自己视野外换成更快的，慢速出发时在自己视野内限速。
func _speed_limits(civ: Civ, s: Ship, at: Vector3, slow_start: bool) -> Array[float]:
	var top := s.max_speed
	var acc := s.accel
	if s.warp and civ != null and not in_own_vision(civ, at):
		top = Balance.WARP_MOVE[0]
		acc = Balance.WARP_MOVE[1]
	if slow_start and civ != null and in_own_vision(civ, at):
		top = minf(top, Balance.SLOW_START_SPEED)
	return [top, acc]


## 照现在的速度，civ 的单位 s 接下来 turns 个回合大概在哪（第一项是现在的位置），画航线用。
## 加速、曲率引擎、慢速出发和光速都和 _move_ship 一样算；不管吞噬者停下来吃行星、星舰停在别人星系旁边、被困住。
func predict_path(civ: Civ, ship: Ship, turns: int) -> Array[Vector3]:
	return Knowledge.predict_path(self,civ,ship,turns)



## 单位先加速、再沿直线移动（G1），检查这一步扫过的格子。有目的地的，最后一步直接落在目的地上。
func _move_ship(civ: Civ, s: Ship) -> void:
	if s.docked or s.parked or s.direction == Vector3.ZERO:
		return
	if s.eat_wait > 0:
		s.eat_wait -= 1
		return
	if s.slow_start and (civ == null or not in_own_vision(civ, s.pos)):
		s.slow_start = false
	var limits := _speed_limits(civ, s, s.pos, s.slow_start)
	s.speed = minf(s.speed + limits[1], limits[0])
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
		# 星舰的视野（VISION_COLONY）比 1 格大，到这里本来就看得到那个星系
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
	var cells := Geometry.segment_cells(from, to, radius, map.bounds())
	# 光粒在光速低于 GRAIN_MIN_LIGHT 的地方失去杀伤力（G14）：出发的格子也要看
	if s.kind == Ship.GRAIN and light_at(s.cell()) < Balance.GRAIN_MIN_LIGHT:
		_disarm_grain(civ, s)
		return
	for c in cells:
		if s.kind == Ship.GRAIN and light_at(c) < Balance.GRAIN_MIN_LIGHT:
			_disarm_grain(civ, s)
			return
		if not cell_exists(c) or (civ != null and not cell_survives(civ, c)):
			if s.kind == Ship.GRAIN:
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
	var center := Vector3(map.origin) + Vector3(map.extent - Vector3i.ONE) / 2.0
	if s.is_outside(map.bounds()) and (not Ship.outside(from, map.bounds()) or to.distance_to(center) >= from.distance_to(center)):
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
	s.direction = Vector3.ZERO
	s.has_target = false
	Signals.report_ship(self,civ,s)


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
	if (dimension == 3 and owner.reduced) or (dimension == 2 and owner.line_reduced):
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
	_lose_system(c, owner, "光粒")


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
		_destroy(a[0], a[1], "舰船交战")
		_destroy(b[0], b[1], "舰船交战")
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
				_destroy(other, t, "战舰")
			"torpedo":
				t.damage += 1
				if t.damage >= Balance.TORPEDO_HITS:
					if told:
						add_log("%s用星际鱼雷打中%s，%s毁掉了" % [who, whom, t.label()])
					_destroy(other, t, "战舰")
				elif told:
					add_log("%s用星际鱼雷打中%s（%d/%d）" % [who, whom, t.damage, Balance.TORPEDO_HITS])
			"hbomb":
				civ.energy += t.cost[0]
				civ.mineral += t.cost[1]
				if told:
					add_log("%s用次声波氢弹杀死了%s的船员，收回 %dE、%dM" % [who, whom, t.cost[0], t.cost[1]])
				_destroy(other, t, "战舰")


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
				_destroy(other, t, "战舰")
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
				_lose_system(c, other, "战舰")
				return


## 单位毁掉：做个记号，回合里统一拿掉。
func _destroy(civ: Civ, s: Ship, cause: String) -> void:
	if s.dead:
		return
	s.dead = true
	if civ != null:
		if s.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH]:
			civ.last_anchor_loss_cause = cause
		civ.assets = civ.assets.filter(func(asset): return asset["carrier"] != s.id)
		Signals.report_ship(self, civ, s)
	if civ != null:
		if civ.research_project.get("host_ship", -1) == s.id and civ.research_project.get("command_ready",true):
			OrderControl.discard(self,civ,civ.research_project,"destroyed")
		var surviving: Array[Dictionary] = []
		for project in civ.pending:
			if (project.get("host_ship", -1) == s.id or project.get("target_ship", -1) == s.id) and project.get("command_ready",true):
				OrderControl.report(self,civ,project,"destroyed")
				if civ.conversions.has(project["id"]):
					civ.conversions[project["id"]]["status"] = "destroyed"
				var target := civ.ship_by_id(project.get("target_ship", -1))
				if target != null:
					target.work_locked = false
			else:
				surviving.append(project)
		civ.pending = surviving



func _remove_ship(civ: Civ, s: Ship) -> void:
	s.dead=true
	Signals.report_ship(self,civ,s)
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
	for observer in Signals.observers(self, civ):
		if Signals.in_view(self, observer, p):
			return true
	return false


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
			"bunker": false,"cell_dim":cell_dims.get(cell_ids.get(c,-1),dimension),"relative_light":relative_light(Vector3(c))}
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
		var n := map.extent
		for i in light.size():
			if light[i] < Balance.SHIP_MIN_SPEED:
				dark.append(Vector3(map.origin + Vector3i(i / (n.y * n.z), (i / n.z) % n.y, i % n.z)))
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
			if (not sphere and not in_view(o, p)) or (may_block and blocked(pos, p)):
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
		if nearest_distance(civ.colonies, t[0]) <= r + 1e-6:
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
	return mini(int(total), DimensionSpace.COUNT)


# ---------- 收入 ----------

## 每回合的能量：每个星系的基础能量（按恒星数）、裂变能（每颗类地行星）、戴森球（星系还有恒星时）和暗能量；
## 被困在黑域里的星系产出只有 1/10（向上取整，G14）；每次自身降维后减半。只剩星舰时只有一点点。
func energy_income(civ: Civ) -> float:
	return WorkOrder.amount(WorkOrder.units(Economy.plan(self, civ)["net"][0]))


## 每回合的矿石：每个星系一些，每艘采矿船再多一些；被困在黑域里的星系只有 1/10（向上取整）。
func mineral_income(civ: Civ) -> float:
	return WorkOrder.amount(WorkOrder.units(Economy.plan(self, civ)["net"][1]))


# ---------- 降维 ----------

## 从 origin（默认母星系）向目标坐标 target 发射二向箔：先准备几个回合，再飞过去。
func launch_foil(civ: Civ, target: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	return _launch_foil(civ, target, origin, false)


func launch_line_foil(civ: Civ, target: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	return _launch_foil(civ, target, origin, true)


## 为什么不能发射二向箔（to_line 时是单向著），能发射时为空。target 为 ANY_TARGET 时不检查目标。
func foil_error(civ: Civ, to_line: bool, target := ANY_TARGET, origin: Vector3i = AT_HOME) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("dimension"):
		return "需要302维度打击"
	if dimension != (2 if to_line else 3):
		return "等待世界进入二维" if to_line else "当前世界已不支持二向箔"
	if civ.dimension_ammo <= 0:
		return "需要先完成一枚维度武器弹药的建造"
	if origin == AT_HOME:
		origin = civ.home
	if not Knowledge.origins(self,civ).has(origin):
		return "发射源必须是自己的星系或星舰"
	if target != ANY_TARGET:
		error = foil_target_error(civ, to_line, target)
		if error != "":
			return error
	return _pay_error(civ, 0)


func foil_target_error(civ: Civ, to_line: bool, target: Vector3i) -> String:
	if not map.contains(target):
		return "目标坐标不在星图内"
	if to_line and target.z != flat_plane:
		return "目标必须在二维平面上"
	if Knowledge.owns(self,civ,target):
		return "目标不能是自己的星系"
	if Knowledge.snapshot(self,civ,target).get("cell_dim",dimension) < dimension:
		return "这一格已经压成直线了，换一个目标" if to_line else "这一格已经压平了，换一个目标"
	return ""


func _launch_foil(civ: Civ, target: Vector3i, origin: Vector3i, to_line: bool) -> Dictionary:
	var error := foil_error(civ, to_line, target, origin)
	if error != "":
		return {"error": error}
	if origin == AT_HOME:
		origin = civ.home
	Assets.ensure(self,civ)
	var recipient: int=Signals.controller(civ)
	var anchor:=Knowledge.anchor(self,civ,origin)
	if not anchor.is_empty():
		recipient=anchor["id"]
	else:
		var ship:=reported_starship(civ)
		if ship!=null:
			recipient=ship.id
	var payload_id:=next_id()
	civ.dimension_ammo-=1
	var foil := Foil.new(Vector3(origin), target, 0, to_line)
	foil.id = payload_id
	foil.position_override = true
	foil.current_position = Vector3(origin)
	civ.foils.append(foil)
	queue_entity_command(civ,recipient,Vector3(origin),{"name":"payload","kind":"dimension","target":target,"payload_id":payload_id,"dimension_reserved":1},[0,0],true)
	_record(civ, "launch_line_foil" if to_line else "launch_foil", [target, origin])
	return {"error": "", "payload": payload_id}


func _advance_foil_list(list: Array[Foil], owner: Civ) -> Array[Foil]:
	var still_flying: Array[Foil] = []
	for foil: Foil in list.duplicate():
		if not foil_works(foil):
			continue
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
		if foil.to_line and not foil.precise:
			# 多算一点点，免得浮点误差把目标格子漏掉
			for c in Geometry.cylinder_cells_between(foil.origin, foil.direction(), from_t,
					foil.traveled + 1e-4, 0.0, map.bounds()):
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
	return still_flying.filter(func(f): return foil_works(f))


## 箔还有没有用：星图已经全部压平，二向箔就没东西可压；压成直线以后，单向著也一样。
func foil_works(f: Foil) -> bool:
	return not all_linear() if f.to_line else not all_flat()


## 预警和看到的舰船里，箔的种类："foil"（二向箔）或 "line_foil"（单向著）。
static func foil_kind(f: Foil) -> String:
	return "line_foil" if f.to_line else "foil"


## 波前标记使用当前阶段的坐标；全图完成时才原子换坐标。
func _flatten_cell(c: Vector3i, plane: int) -> void:
	if dimension != 3 or flattened.has(c) or not map.contains(c):
		return
	flattened[c] = plane
	_compress_cell(c, false)
	if flattened.size() == DimensionSpace.COUNT:
		DimensionSpace.commit(self, false)


func _linearize_cell(c: Vector3i) -> void:
	if dimension != 2 or linearized.has(c) or not map.contains(c):
		return
	linearized[c] = line_y
	_compress_cell(c, true)
	if linearized.size() == DimensionSpace.COUNT:
		DimensionSpace.commit(self, true)


## 宇宙物质保留；未自行降维的文明失去资产，存活资产暂留原坐标。
func _compress_cell(c: Vector3i, to_line: bool) -> void:
	var weapon := "单向著" if to_line else "二向箔"
	var owner := coord_owner(c)
	if owner != null and not (owner.line_reduced if to_line else owner.reduced):
		if owner == human():
			add_log("你的星系 %s 被%s扫过，文明失去该据点" % [c, weapon])
		_lose_system(c, owner, weapon)
	for civ in civs:
		if civ.line_reduced if to_line else civ.reduced:
			continue
		for ship in civ.ships:
			if not ship.dead and ship.cell() == c and ship.lock < 0:
				_destroy(civ, ship, weapon)
	for ship in hidden_ships:
		if ship.cell() == c:
			ship.dead = true
	for wake in wakes:
		if Vector3i(wake["a"].round()) == c or Vector3i(wake["b"].round()) == c:
			wake["gone"] = true


func all_flat() -> bool:
	return dimension <= 2


func all_linear() -> bool:
	return dimension == 1


## 降维只重排坐标，不删除宇宙格子。
func cell_exists(c: Vector3i) -> bool:
	return map.contains(c)


func cell_survives(civ: Civ, c: Vector3i) -> bool:
	if dimension == 3:
		return not flattened.has(c) or civ.reduced
	if dimension == 2:
		return not linearized.has(c) or civ.line_reduced
	return civ.line_reduced


## 完成降维的地图里，方向只能沿剩下的轴。
func space_direction(direction: Vector3) -> Vector3:
	if all_flat():
		direction.z = 0.0
	if all_linear():
		direction.y = 0.0
	return direction.normalized() if direction.length() > 1e-6 else Vector3.ZERO


## 二向箔打到 target 时压成哪一层平面（z）：第一片箔定下，后来的都压到同一层。
func foil_plane_for(target: Vector3i) -> int:
	return flat_plane if flat_plane >= 0 else target.z


## 单向著打到 target 时压成哪一行（y）：第一片定下，后来的都压到同一行。
func line_y_for(target: Vector3i) -> int:
	return line_y if line_y >= 0 else target.y


## 二向箔在格子 at 展开，从这里按球形向外扩散（U3），马上压平它能压到的格子。
## 平面的高度由第一回合展开的箔定下：同一回合有几片时取它们 z 的平均，之后的箔不再改。
func _unfold_foil(at: Vector3i) -> void:
	if dimension!=3 or not map.contains(at):
		return
	ensure_cells()
	for civ in civs:
		Assets.ensure(self,civ)
	SpaceEvents.unfold(self,at)
	SpaceEvents.resolve(self)
	_check_winner()


## 胜负结束后也允许环境继续演化，不恢复行动、不结算收入或 AI。
func collapse_pending() -> bool:
	return (not foil_zones.is_empty() and not all_flat()) or (not line_zones.is_empty() and not all_linear())


func advance_collapse() -> void:
	if collapse_pending():
		_spread_flat()
		_clean_dead()


## 每回合每片展开的箔再向外扩散 FOIL_SPREAD 格（T17）。
func _spread_flat() -> void:
	# 仅供展开演示/终局后的环境动画；对局内由WorldTime统一推进。
	ensure_cells()
	clock+=1.0
	SpaceEvents.resolve(self)
	_check_winner()


func _unfold_line_foil(at: Vector3i) -> void:
	if dimension!=2 or not map.contains(at):
		return
	ensure_cells()
	for civ in civs:
		Assets.ensure(self,civ)
	SpaceEvents.unfold(self,at)
	SpaceEvents.resolve(self)
	_check_winner()


## 二维里在平面上按圆形扩散，扫过的格子压到一维（U3）。
static func line_covers(center: Vector3i, age: float, c: Vector3i) -> bool:
	return zone_distance(center, c) <= age


## 箔的波前离格子 c 多远：从落点算的直线距离（三维里是球形，二维里是圆形，U3）。
## 规则（压没哪些格子）和展开画面（DimensionSpace.frame 用的 Layout.arrivals）算法一样，两边不会对不上。
static func zone_distance(center: Vector3i, c: Vector3i) -> float:
	return Vector3(c - center).length()


func _apply_line_zone(zone: Dictionary) -> void:
	if dimension != 2:
		return
	_collapse_depth += 1
	for c in map.cells():
		if line_covers(zone["center"], zone["age"], c):
			_linearize_cell(c)
	_collapse_depth -= 1
	_check_winner()


## 波前从落点按球形推进，扫过的格子展开到二维（U3）。
static func zone_covers(center: Vector3i, age: float, c: Vector3i) -> bool:
	return zone_distance(center, c) <= age


## 按波前处理整列；同时展开多片箔时只处理尚未展开的格子。
func _apply_zone(zone: Dictionary) -> void:
	if dimension != 3:
		return
	_collapse_depth += 1
	for c in map.cells():
		if zone_covers(zone["center"], zone["age"], c):
			_flatten_cell(c, flat_plane)
	_collapse_depth -= 1
	_check_winner()


## 格子 c 再过几个回合会被压没（已经压没时为 0，没有展开的二向箔时为 INF）。
func turns_until_flat(c: Vector3i) -> float:
	var best := INF
	for zone in SpaceEvents.zones(self):
		var distance := SpaceEvents.cell_distance(self, Vector3(zone["center"]), c)
		best = minf(best, maxf(0.0, (distance - SpaceEvents.radius(self, zone, clock)) / (Balance.FOIL_SPREAD * background_light())))
	return best


## 仅用已收到的转换格和战略载荷轨迹估计危险；不读取尚未送达的真实波中心/目标。
func known_front_eta(civ: Civ, at: Vector3i) -> float:
	var best := INF
	for cell in civ.intel:
		var info: Dictionary = civ.intel[cell]
		if info.get("cell_dim",dimension) < dimension:
			var observed: float = info.get("t_observed",clock)
			var travel := Vector3(at).distance_to(Vector3(cell))*physical_cell_size()/(Balance.FOIL_SPREAD*background_light())
			best = minf(best,maxf(0.0,travel-(clock-observed)))
	for alert in civ.alerts:
		if alert.get("payload_kind","") != "dimension":
			continue
		var velocity: Vector3 = alert.get("velocity",Vector3.ZERO)
		var relative: Vector3 = Vector3(at)-alert["pos"]
		if velocity.length_squared()<=1e-15 or relative.dot(velocity)<0:
			continue
		var lead := relative.dot(velocity)/velocity.length_squared()
		if (relative-velocity*lead).length()*physical_cell_size()<=Balance.WARNING_RANGE:
			best=minf(best,maxf(0.0,lead-(clock-alert["t_observed"]))+Balance.DIMENSION_ACTIVATION)
	return best


## 为什么现在不能开始自身降维（能开始时为空）。
func reduce_error(civ: Civ) -> String:
	return Conversion.error(self, civ, Conversion.known_roster(self,civ,dimension), Signals.controller(civ), false)


func start_reduce(civ: Civ) -> Dictionary:
	return prepare_conversion(civ, Conversion.known_roster(self,civ,dimension), Signals.controller(civ), false, true)


func _advance_reduce(_civ: Civ) -> void:
	pass # 迁维由工程完成、有限传播和逐实体转换事件推进。


func singularity_error(civ: Civ) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("dimension") or dimension != 1:
		return "需要302且等待世界进入一维"
	if civ.dimension_ammo <= 0:
		return "需要先完成维度武器弹药"
	return _pay_error(civ, 0)


func launch_singularity(civ: Civ, target: Vector3i = AT_HOME) -> Dictionary:
	var error := singularity_error(civ)
	if error != "":
		return {"error": error}
	if target == AT_HOME:
		target = civ.home
	if not map.contains(target):
		return {"error": "目标不在星图内"}
	civ.dimension_ammo -= 1
	civ.actions_left -= 1
	SpaceEvents.launch(self, civs.find(civ), Signals.entity(self,civs.find(civ),Signals.controller(civ))["pos"], Vector3(target), "dimension")
	_record(civ, "launch_singularity", [target])
	return {"error": ""}


func _advance_singularity(_civ: Civ) -> void:
	pass # 奇异点是物理前沿，不产生倒计时胜利。


# ---------- 黑域 ----------

## 为什么不能在 center 投放黑域（能投放时为空）。center 为 ANY_TARGET 时不检查位置。
## 只能投放在自己现在看得到的地方（星系和星舰的视野，G14）。
func domain_error(civ: Civ, center := ANY_TARGET) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("domain"):
		return "需要303黑域投放"
	if clock < civ.domain_ready_at:
		return "黑域投放还需冷却%.2f年" % (civ.domain_ready_at - clock)
	if center != ANY_TARGET:
		if not map.contains(center):
			return "坐标不在星图内"
		if not civ.intel.has(center) and not Knowledge.in_vision(self,civ,Vector3(center)):
			return "请选择已知或有效覆盖的位置"
	return _pay_error(civ, Balance.DOMAIN_COST[0], Balance.DOMAIN_COST[1])


func launch_black_domain(civ: Civ, center: Vector3i) -> Dictionary:
	var error := domain_error(civ, center)
	if error != "":
		return {"error": error}
	Economy.charge(self,civ,Balance.DOMAIN_COST,"black_domain")
	civ.actions_left -= 1
	civ.domain_ready_at = clock + Balance.DOMAIN_COOLDOWN
	SpaceEvents.launch(self, civs.find(civ), Signals.entity(self,civs.find(civ),Signals.controller(civ))["pos"], Vector3(center), "domain")
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
		light[light_index(center)] = 0.0
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
	var n := map.extent
	var before := light
	var a := light
	for axis in 3:
		var stride: int = [n.y * n.z, n.z, 1][axis]
		var b := PackedFloat64Array()
		b.resize(a.size())
		for i in a.size():
			var k := (i / stride) % n[axis]
			var sum := a[i]
			var count := 1
			if k > 0:
				sum += a[i - stride]
				count += 1
			if k < n[axis] - 1:
				sum += a[i + stride]
				count += 1
			b[i] = sum / count
		a = b
	for d in black_domains:
		a[light_index(d["center"])] = 0.0
	light = a
	# 扩散均匀了（没有黑域中心，各格几乎不再变化）就停下，省得每回合重算
	var change := 0.0
	for i in light.size():
		change = maxf(change, absf(light[i] - before[i]))
	_light_moving = not black_domains.is_empty() or change > 1e-6


func _ensure_light() -> void:
	if light.is_empty():
		light.resize(DimensionSpace.COUNT)
		light.fill(1.0)


## 格子 c 的光速存在 light 的第几项。
func light_index(c: Vector3i) -> int:
	c -= map.origin
	return (c.x * map.extent.y + c.y) * map.extent.z + c.z


## 直接设格子 c 的光速（测试用来摆出想要的局面；规则里光速只由黑域改）。
func set_light_at(c: Vector3i, value: float) -> void:
	_ensure_light()
	light[light_index(c)] = value


## 格子 c 的光速（G14），开始是 1.0，被黑域拉低。星图外的都是 1.0。
func light_at(c: Vector3i) -> float:
	if light.is_empty() or not map.contains(c):
		return 1.0
	return light[light_index(c)]


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
			_die(civ, "黑域")


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
func _lose_system(c: Vector3i, owner: Civ, cause := "其他") -> void:
	if owner.colonies.has(c):
		owner.last_anchor_loss_cause = cause
	for project in WorldTime.orders(owner):
		if project["at"]==c and project.get("host_ship",-1)<0 and project.get("command_ready",true):
			OrderControl.report(self,owner,project,"destroyed")
			if owner.conversions.has(project["id"]):
				owner.conversions[project["id"]]["status"] = "destroyed"
	Assets.remove_at(owner, c)
	owner.colonies.erase(c)
	owner.dysons.erase(c)
	owner.miners.erase(c)
	owner.bunkers.erase(c)
	owner.broadcasters.erase(c)
	owner.grains.erase(c)
	owner.pending = owner.pending.filter(func(p): return p["at"] != c or p.get("host_ship", -1) >= 0 or not p.get("command_ready",true))
	owner.advanced_miners.erase(c)
	owner.warnings.erase(c)
	owner.colonial.erase(c)
	owner.dormant_colonies.erase(c)
	if not owner.research_project.is_empty() and owner.research_project["at"] == c and owner.research_project["host_ship"] < 0 and owner.research_project.get("command_ready",true):
		owner.research_project = {}
	owner.has_warning = not owner.warnings.is_empty()
	if owner.colonies.is_empty():
		if owner.has_starship():
			owner.home = owner.starship().cell()
	elif owner.home == c:
		owner.home = owner.colonies[0]
	Knowledge.report_site(self,owner,c)


## 文明灭亡，准备中和在飞的东西也随之消失（已经发出的光粒除外）。
func _die(owner: Civ, cause := "其他") -> void:
	if not owner.alive:
		return
	owner.alive = false
	civilization_eliminated.emit(owner, cause if cause != "" else "其他")
	owner.pending.clear()
	owner.research_project = {}
	for ship in owner.ships:
		if ship.kind != Ship.GRAIN:
			ship.dead = true
	# 已发射弹丸、载荷和光粒继续进入同刻批次；终局只在批次结束判断。
	events.append({"id":next_id(),"kind":"eliminated","t":clock,"owner":civs.find(owner),"cause":cause})


func winner_by_name() -> bool:
	return spectator or (play_on_after_death and not human().alive)


## 每有文明灭亡就重新判断一次。二向箔可能让好几个文明同时灭亡，
## 所以已经分出胜负后还会再改（例如你灭亡后，剩下的 AI 也被压平，就变成「无」）。
func _check_winner() -> void:
	if _collapse_depth > 0 or winner != "":
		return
	for civ in civs:
		if civ.alive and civ.colonies.is_empty() and not civ.has_starship():
			_die(civ, civ.last_anchor_loss_cause if civ.last_anchor_loss_cause != "" else "失去最后生存锚点")
	var alive := civs.filter(func(c): return c.alive)
	if alive.size() > 1:
		return
	if alive.is_empty():
		winner = "平局"
	elif winner_by_name():
		winner = alive[0].name
	else:
		winner = "你" if alive[0] == human() else "AI"
	events.append({"id": next_id(), "kind": "terminal", "t": clock, "winner": winner})
	add_log("同刻结算后：" + ("没有存续文明，平局" if alive.is_empty() else "%s 获胜" % alive[0].name))


# ---------- 小工具 ----------

func _common_error(civ: Civ) -> String:
	if is_over():
		return "对局已结束"
	if not civ.alive:
		return "文明已灭亡"
	return ""


## 行动点、能量、矿石够不够（够时为空）。
func _pay_error(civ: Civ, energy: float, mineral: float = 0.0) -> String:
	if civ.actions_left <= 0:
		return "行动点用完了，结束回合后恢复"
	return _money_error(civ, energy, mineral)


## 能量、矿石够不够（够时为空），不看行动点。
func _money_error(civ: Civ, energy: float, mineral: float = 0.0) -> String:
	if civ.energy_millis < WorkOrder.units(energy):
		return "能量不足（还差 %.3f）" % (energy - civ.energy)
	if civ.mineral_millis < WorkOrder.units(mineral):
		return "矿石不足（还差 %.3f）" % (mineral - civ.mineral)
	return ""


## p 离这些格子里最近的一个多远（没有格子时为 INF）。
static func nearest_distance(cells: Array[Vector3i], p: Vector3) -> float:
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


# ---------- V0.1 工程账本 ----------

func construction_host(civ: Civ, at: Vector3i) -> int:
	if Knowledge.owns(self,civ,at):
		return -1
	var ship := reported_starship(civ)
	return ship.id if ship != null and ship.cell() == at else -2


## 只依照已收到的原母星永久身份判断容量；重殖原坐标与同格星舰都不另开槽。
func construction_capacity(civ: Civ, at: Vector3i, host: int) -> int:
	if host == -2:
		return 0
	if host < 0 or Balance.HOME_BUILD_SLOTS>Balance.BUILD_SLOTS:
		var anchor := Knowledge.anchor(self,civ,at)
		if civ.original_anchor_id>=0 and anchor.get("id",-1)==civ.original_anchor_id:
			return Balance.HOME_BUILD_SLOTS
	return Balance.BUILD_SLOTS


## 队列归属在受理时冻结；实际工程宿主仍单独保留，不能用同格星舰多开母星槽。
func construction_queue_id(civ: Civ, at: Vector3i, host: int) -> int:
	if host<0 or (Balance.HOME_BUILD_SLOTS>Balance.BUILD_SLOTS and Knowledge.owns(self,civ,at)):
		return Knowledge.anchor(self,civ,at).get("id",-1)
	return host


## 送出的订单也占位；真实完工或失败不能在回执抵达前释放容量。
func construction_orders(civ: Civ, at: Vector3i, host: int) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var anchor_id: int = Knowledge.anchor(self,civ,at).get("id",-1) if host<0 else -1
	var queue_id := construction_queue_id(civ,at,host)
	for p in OrderControl.visible(self,civ):
		if p["category"]!="research" and p.has("queue_id") and queue_id>=0:
			if p["queue_id"]==queue_id:
				orders.append(p)
			continue
		if p["category"]!="research" and p.get("host_ship", -1) == host and (host >= 0 or p["at"] == at):
			if host>=0 or anchor_id<0 or p.get("host_id",-1) in [-1,anchor_id]:
				orders.append(p)
	return orders


func construction_busy(civ: Civ, at: Vector3i, host: int) -> bool:
	if host>=0 and OrderControl.visible(self,civ).filter(func(project):return project["category"]!="research" and project.get("host_ship",-1)==host).size()>=Balance.BUILD_SLOTS:
		return true
	return construction_orders(civ,at,host).size()>=construction_capacity(civ,at,host)


func project_host_alive(civ: Civ, project: Dictionary) -> bool:
	if project.get("host_id",-1)>=0 and Signals.entity(self,civs.find(civ),project["host_id"]).is_empty():
		return false
	if project["host_ship"] >= 0:
		var ship := civ.ship_by_id(project["host_ship"])
		return ship != null and not ship.dead
	return civ.owns(project["at"])


func project_work_rate(civ: Civ, project: Dictionary) -> float:
	if not project.get("command_ready", true):
		return 0.0
	var dim := Assets.dimension(civ, "anchor", project["at"])
	var rescue := false
	if project["host_ship"] >= 0:
		var host := civ.ship_by_id(project["host_ship"])
		if host == null or host.dead:
			return 0.0
		dim = host.entity_dim
		rescue = host.dormant
	else:
		rescue = civ.dormant_colonies.has(project["at"])
	if rescue:
		if project["kind"] not in ["miner", "fission", "probe", "interstellar_travel", "colony"] or not project["modules"].is_empty():
			return 0.0
		if project["category"] != "research" and project["kind"] not in ["probe", "colony"]:
			return 0.0
		for other in WorldTime.orders(civ):
			if other["id"] >= project["id"] or not other.get("command_ready", true) or not project_host_alive(civ, other):
				continue
			var dormant := civ.dormant_colonies.has(other["at"])
			if other["host_ship"] >= 0:
				dormant = civ.ship_by_id(other["host_ship"]).dormant
			var eligible: bool = other["kind"] in ["miner", "fission", "probe", "interstellar_travel", "colony"] if other["category"] == "research" else other["kind"] in ["probe", "colony"] and other["modules"].is_empty()
			if dormant and eligible:
				return 0.0
	return Balance.DIMENSION_WORK[str(dim)] * (Balance.RESCUE_WORK_FACTOR if rescue else 1.0)


func _module_error(civ: Civ, kind: String, modules: Array) -> String:
	var seen := {}
	for module in modules:
		if seen.has(module) or not Balance.MODULE_COST.has(module):
			return "模块重复或未知"
		seen[module] = true
		if not civ.has_tech(module):
			return "尚未研究模块：%s" % Tech.title(module)
		if module == "warp":
			if kind not in ["warship", "colony", "starship", "devourer"]:
				return "这种舰体不能安装曲率引擎"
		elif kind != "warship":
			return "这种模块只用于恒星级战舰"
	return ""


func _complete_project(civ: Civ, project: Dictionary) -> void:
	var at: Vector3i = project["at"]
	var kind: String = project["kind"]
	if kind == "wandering_earth":
		EarthTransform.complete(self,civ,project)
		return
	if project["category"] == "conversion":
		Conversion.complete(self, civ, project)
		return
	if project["category"] == "upgrade":
		if kind == "telescope":
			pass # 全局视距升级在完成回报送达控制端后生效。
		else:
			civ.warnings[at] += 1
			civ.warning_level = civ.warnings.get(civ.home, 0)
		return
	if project["category"] == "refit":
		var ship := civ.ship_by_id(project["target_ship"])
		if ship == null or ship.dead:
			return
		ship.work_locked = false
		for module in project["modules"]:
			ship.modules.append(module)
			if module in ["railgun", "beam", "hbomb", "torpedo"]:
				ship.weapons.append(module)
		ship.warp = ship.modules.has("warp")
		ship.gravity = ship.modules.has("gravity")
		var paid := WorkOrder.salvage(project)
		ship.cost[0] += paid[0]
		ship.cost[1] += paid[1]
		return
	if project["category"] == "miner_refit":
		var original := Assets.at(civ, "miner", at)
		if not original.is_empty():
			original[0]["kind"] = "advanced_miner"
			var extra := WorkOrder.salvage(project)
			for i in 2:
				original[0]["paid"][i] += extra[i]
		civ.miners[at] -= 1
		civ.advanced_miners[at] = civ.advanced_miners.get(at, 0) + 1
		return
	if kind == "landing":
		var ship := civ.ship_by_id(project["host_ship"])
		if ship != null:
			ship.work_locked = false
			if can_settle(at) and landing_site_survives(ship,at):
				_remove_ship(civ, ship)
				_add_colony(civ, at,ship.entity_dim)
		return
	match kind:
		"miner": civ.miners[at] = civ.miners.get(at, 0) + 1
		"advanced_miner": civ.advanced_miners[at] = civ.advanced_miners.get(at, 0) + 1
		"dyson": civ.dysons[at] = civ.dysons.get(at, 0) + 1
		"bunker": civ.bunkers[at] = true
		"broadcaster": civ.broadcasters[at] = true
		"warning":
			civ.warnings[at] = 0
			civ.has_warning = true
		"antimatter": pass # 完成回报到达后才进入可下令弹药库存。
		"grain": civ.grains[at] = true
		"dimension_weapon": pass
		_:
			if not UNITS.has(kind):
				return
			var pos := Vector3(at)
			if project["host_ship"] >= 0:
				pos = civ.ship_by_id(project["host_ship"]).pos
			var ship := Ship.make(kind, pos, next_id())
			project["result_ship"]=ship.id
			ship.entity_dim = Assets.dimension(civ, "anchor", at) if project["host_ship"] < 0 else civ.ship_by_id(project["host_ship"]).entity_dim
			ship.cost = WorkOrder.salvage(project)
			ship.modules.assign(project["modules"])
			for module in ship.modules:
				if module in ["railgun", "beam", "hbomb", "torpedo"]:
					ship.weapons.append(module)
			ship.warp = ship.modules.has("warp")
			ship.gravity = ship.modules.has("gravity")
			ship.interstellar = kind == Ship.NUCLEAR_PROBE
			civ.ships.append(ship)
			Signals.report_ship(self, civ, ship)
			Signals.receive_due(self)
			if kind == Ship.STARSHIP:
				civ.starship_ever_built = true
	if kind in FACILITIES:
		Assets.make(self, civ, kind, at, WorkOrder.salvage(project), Assets.dimension(civ, "anchor", at))


func cancel_order_error(civ: Civ, id: int) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	for order in OrderControl.visible(self,civ):
		if order["id"]==id:
			return "取消命令已发出" if order.get("cancel_pending",false) else ""
	return "没有这项已知未完成工程"


func cancel_order(civ: Civ, id: int) -> Dictionary:
	var error := cancel_order_error(civ,id)
	if error != "":
		return {"error":error}
	var order: Dictionary = civ.order_reports[id]
	var recipient: int = order.get("host_id",order["host_ship"])
	if recipient<0:
		var anchor:=Knowledge.anchor(self,civ,order["at"])
		if not anchor.is_empty():
			recipient=anchor["id"]
	order["cancel_pending"]=true
	queue_entity_command(civ,recipient,Vector3(order["at"]),{"name":"cancel_order","project":id},[0,0],false)
	_record(civ,"cancel_order",[id])
	return {"error":"","refund":[0.0,0.0]}


func _refresh_permissions(civ: Civ) -> void:
	Assets.ensure(self,civ)
	var plan:=Economy.plan(self,civ)
	var reference: Array = plan["reference"]
	var events := [false, civ.discovered, civ.contacted, civ.conquered]
	for tier in [1, 2, 3]:
		var gate: Array = Balance.TIER_NET_INCOME[str(tier)]
		if not events[tier] or civ.tier_turn(tier)>=0 or civ.pending_permissions.has(tier) or reference[0]<gate[0] or reference[1]<gate[1]:
			continue
		# 账本可即时结算余额，但远端增产、停机和损失不能经权限按钮提前暴露。
		# 同一时点冻结达标证明；来源分别走实际光路，不能用一个全局直线延时替代。
		var receiver:=Signals.controller(civ)
		var origins: Array[Dictionary]=[{"pos":Vector3(civ.home),"recipient":receiver}]
		for item in plan["items"]:
			var pos:=Vector3(item["at"])
			var via:=receiver
			if item.has("id"):
				pos=Signals.entity(self,civs.find(civ),item["id"]).get("pos",pos)
			if item["kind"]=="coverage":
				via=int(item["key"].get_slice(":",2))
			var source: Dictionary={"pos":pos,"recipient":via}
			if not origins.has(source):
				origins.append(source)
		# 已毁来源只能等待毁坏时已发出的回报，不能事后在空址造一份报告。
		var missing_sites: Array[int]=[]
		var missing_ships: Array[int]=[]
		for cell in Knowledge.colonies(self,civ):
			if not civ.owns(cell):
				missing_sites.append(cell_ids.get(cell,-1))
		for ship in Signals.reported_ships(self,civ):
			if Signals.entity(self,civs.find(civ),ship.id).is_empty():
				missing_ships.append(ship.id)
		var ticket:=next_id()
		var waiting:=range(origins.size())
		civ.pending_permissions[tier]={"id":ticket,"waiting":waiting,"missing_sites":missing_sites,"missing_ships":missing_ships}
		for i in origins.size():
			Signals.send(self,civs.find(civ),origins[i]["pos"],origins[i]["recipient"],"sensor",{
				"type":"permission","tier":tier,"ticket":ticket,"source":i,"t_observed":clock,"epoch":space_epoch})
	Signals.receive_due(self)


func emergency_work_error(civ: Civ, resource: String, anchor_id := -1) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if resource not in ["E", "M"]:
		return "一次只能选择一种资源"
	if civ.emergency_turn == turn:
		return "本回合已经进行过应急作业"
	if Knowledge.origins(self,civ).is_empty():
		return "没有存续锚点"
	if anchor_id>=0 and not Conversion.is_anchor(Knowledge.entity(self,civ,anchor_id)):
		return "请选择现有生存锚点"
	return _pay_error(civ, 0.0)


func emergency_work(civ: Civ, resource: String, anchor_id := -1) -> Dictionary:
	var error := emergency_work_error(civ, resource,anchor_id)
	if error != "":
		return {"error": error}
	Assets.ensure(self,civ)
	if anchor_id<0:
		anchor_id=Signals.controller(civ)
	var host:=Knowledge.entity(self,civ,anchor_id)
	var dim: int=host["ship"].entity_dim if host.has("ship") else host["asset"]["entity_dim"]
	var amount: float=Balance.EMERGENCY_YIELD*Balance.DIMENSION_OUTPUT[str(dim)]
	civ.emergency_turn = turn
	queue_entity_command(civ,anchor_id,host["pos"],{"name":"emergency","resource":resource},[0,0],true)
	_record(civ, "emergency_work", [resource,anchor_id])
	return {"error": "", "yield": amount}


func refit_error(civ: Civ, ship_id: int, modules: Array) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	var ship := Signals.reported_ship(self,civ,ship_id)
	if ship == null or ship.dead or ship.work_locked or not ship.waiting():
		return "需要一艘空闲待命的己方舰船"
	if OrderControl.visible(self,civ).any(func(project):return project["category"]=="refit" and project.get("target_ship",-1)==ship_id):
		return "这艘舰船已有改装施工或正在等待回报"
	if modules.is_empty():
		return "需要选择新增模块"
	var module_error := _module_error(civ, ship.kind, modules)
	if module_error != "":
		return module_error
	for module in modules:
		if ship.modules.has(module):
			return "已经安装这个模块"
	var host := construction_host(civ, ship.cell())
	if host == -2 or construction_busy(civ, ship.cell(), host):
		return "改装需要所在锚点的空闲工程队列"
	if Knowledge.site(self,civ,ship.cell()).get("dormant",false) or (host >= 0 and Signals.reported_ship(self,civ,host).dormant):
		return "休眠锚点不能进行普通改装"
	var cost := refit_cost(modules)
	return _pay_error(civ, cost[0], cost[1])


static func refit_cost(modules: Array) -> Array:
	var cost := [0.0, 0.0]
	for module in modules:
		var price: Array = Balance.MODULE_COST.get(module, [0, 0])
		cost[0] += price[0]
		cost[1] += price[1]
	return cost


func refit_ship(civ: Civ, ship_id: int, modules: Array) -> Dictionary:
	var error := refit_error(civ, ship_id, modules)
	if error != "":
		return {"error": error}
	var ship := Signals.reported_ship(self,civ,ship_id)
	var cost := refit_cost(modules)
	var work := 0.0
	for module in modules:
		work += Balance.MODULE_WORK[module]
	var project := WorkOrder.create(next_id(), ship.kind, ship.cell(), cost, work, "refit")
	project["host_ship"] = construction_host(civ, ship.cell())
	project["target_ship"] = ship_id
	project["modules"] = modules.duplicate()
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.pending.append(project)
	OrderControl.submit(self,civ,project)
	_record(civ, "refit_ship", [ship_id, modules.duplicate()])
	return {"error": "", "order": project["id"]}


## 只供命令到达和实际施工检查，不能在下令按钮读取尚未回报的格子维度。
func landing_site_survives(ship: Ship,at: Vector3i) -> bool:
	var cell_dim: int=cell_dims.get(cell_ids.get(at,-1),dimension)
	return ship!=null and not ship.dead and cell_dim>0 and ship.entity_dim<=cell_dim


func landing_error(civ: Civ, ship_id: int) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("colony"):
		return "需要研究109星际殖民"
	var ship := Signals.reported_ship(self,civ,ship_id)
	if ship == null or ship.dead or ship.kind != Ship.COLONY or ship.work_locked or not ship.waiting():
		return "需要抵达目的地、空闲待命的运输船"
	if not known_habitable(civ).has(ship.cell()):
		return "尚未收到当前位置可殖民的观测"
	if construction_busy(civ, ship.cell(), ship.id):
		return "运输船已经在施工"
	var cost := Construction.cost("landing")
	return _pay_error(civ, cost[0], cost[1])


func start_landing(civ: Civ, ship_id: int) -> Dictionary:
	var error := landing_error(civ, ship_id)
	if error != "":
		return {"error": error}
	var ship := Signals.reported_ship(self,civ,ship_id)
	var cost := Construction.cost("landing")
	var project := WorkOrder.create(next_id(), "landing", ship.cell(), cost, Construction.work("landing"))
	project["host_ship"] = ship_id
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.pending.append(project)
	OrderControl.submit(self,civ,project)
	_record(civ, "start_landing", [ship_id])
	return {"error": "", "order": project["id"]}


func refit_miner_error(civ: Civ, at: Vector3i = AT_HOME) -> String:
	if at == AT_HOME:
		at = civ.home
	var error := _common_error(civ)
	if error != "":
		return error
	var known:=Knowledge.site(self,civ,at)
	if not civ.has_tech("mining_advanced") or not known.get("owned",false) or known.get("miners",0)<1:
		return "需要008科技及本地一艘基础矿船"
	var reserved := OrderControl.visible(self,civ).filter(func(project):return project["category"]=="miner_refit" and project["at"]==at).size()
	if known.get("miners",0)<=reserved:
		return "当地基础矿船均已安排改装，需等待改装或取消回报"
	if known.get("dormant",false):
		return "休眠锚点不能进行普通改装"
	if construction_busy(civ, at, -1):
		return "这个锚点已有工程进行中"
	return _pay_error(civ, Balance.MINER_REFIT_COST[0], Balance.MINER_REFIT_COST[1])


func refit_miner(civ: Civ, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := refit_miner_error(civ, at)
	if error != "":
		return {"error": error}
	var cost := Balance.MINER_REFIT_COST
	var project := WorkOrder.create(next_id(), "advanced_miner", at, cost, Balance.MINER_REFIT_WORK, "miner_refit")
	Economy.charge(self,civ,cost,"project")
	civ.actions_left -= 1
	civ.pending.append(project)
	OrderControl.submit(self,civ,project)
	_record(civ, "refit_miner", [at])
	return {"error": "", "order": project["id"]}


func ensure_cells() -> void:
	if not cell_ids.is_empty():
		return
	for cell in map.cells():
		var id := cell_ids.size() + 1
		cell_ids[cell] = id
		cell_dims[id] = dimension


func physical_cell_size() -> float:
	return Balance.DIMENSION_CELL_SIZE[str(dimension)]


func background_light() -> float:
	return Balance.DIMENSION_LIGHT[str(dimension)]


func relative_light(pos: Vector3) -> float:
	return minf(light_at(Vector3i(pos.round())), Hazards.suppression(self, pos))


func light_speed_at(pos: Vector3) -> float:
	var dim: int = cell_dims.get(cell_ids.get(Vector3i(pos.round()), -1), dimension)
	return 0.0 if dim == 0 else Balance.DIMENSION_LIGHT[str(dim)] * relative_light(pos)


func _receive_command(message: Dictionary, exists: bool) -> void:
	var civ: Civ = civs[message["owner"]]
	var body: Dictionary = message["body"]
	var ship := civ.ship_by_id(message["recipient"])
	var valid := exists and civ.alive
	if body["name"] in ["scan","broadcast","payload","emergency","grain"]:
		valid = valid and _execute_source_command(civ,message["recipient"],body)
	elif body["name"]=="weapon_policy":
		valid = valid and ship!=null and not ship.dead
		if valid:
			ship.weapon_policy=body["policy"]
	elif body["name"] == "antimatter":
		valid = valid and _fire_antimatter(civ,message["recipient"],body["target_id"])
	elif body["name"] == "activate_project":
		valid = valid and OrderControl.activate(self,civ,body["project"])
		if not valid:
			var project:=OrderControl.find(civ,body["project"])
			if not project.is_empty():
				OrderControl.discard(self,civ,project,"destroyed")
	elif body["name"] == "cancel_order":
		body["returned"] = OrderControl.cancel(self,civ,body["project"]) if valid else [0,0]
	elif ship == null or ship.dead or ship.dormant or ship.work_locked:
		valid = false
	elif valid:
		match body["name"]:
			"dispatch", "turn_ship":
				var direction := space_direction(body["direction"])
				if ship.direction.dot(direction) < 0.0:
					ship.speed = 0.0
				ship.direction = direction
				ship.docked = false
				ship.parked = false
				ship.slow_start = body.get("slow", false) and ship.kind in [Ship.PROBE,Ship.NUCLEAR_PROBE]
			"send_colony", "move_starship", "send_sophon":
				_set_target(ship, body["target"])
			_: valid = false
	var reserved: Array = body.get("reserved", [0, 0])
	Signals.send(self, civs.find(civ), message["pos"], Signals.controller(civ), "report",
			{"type": "command_result", "executed": valid, "refund": body.get("returned",[0,0]) if valid else reserved,
			"ammo_refund": 0 if valid else body.get("ammo_reserved",0),
			"dimension_refund": 0 if valid else body.get("dimension_reserved",0),
			"payload_id":body.get("payload_id",-1),
			"scan_ready_at": body.get("scan_ready_at",-1.0),
			"command": message["id"], "t_observed": clock, "source_id": message["recipient"], "epoch": space_epoch,
			"request_name": body["name"], "request_target": body.get("target", NO_HIT),
			"reason": "" if valid else "命令抵达时宿主已失效、停机或被工程占用"})
	if ship != null:
		Signals.report_ship(self, civ, ship)
	events.append({"id": message["id"], "t": clock, "kind": "command_arrived", "recipient": message["recipient"], "executed": valid})


func prepare_conversion(civ: Civ, ids: Array, host_id: int, emergency: bool, automatic: bool) -> Dictionary:
	var result := Conversion.prepare(self, civ, ids, host_id, emergency, automatic)
	if result["error"] == "":
		_record(civ, "prepare_conversion", [ids, host_id, emergency, automatic])
	return result


func execute_conversion(civ: Civ, plan_id: int) -> Dictionary:
	var result := Conversion.execute(self, civ, plan_id)
	if result["error"] == "":
		_record(civ, "execute_conversion", [plan_id])
	return result


func command_cost(civ: Civ, ship: Ship) -> int:
	if ship.kind in [Ship.PROBE, Ship.NUCLEAR_PROBE, Ship.COLONY] or civ.has_tech("dark_energy"):
		return 0
	return maxi(0, Balance.COST_TURN - (Balance.FUSION_DISCOUNT if civ.has_tech("fusion") else 0) - (Balance.COLLECTION_DISCOUNT if civ.has_tech("antimatter_collection") else 0))


func queue_ship_command(civ: Civ, ship: Ship, body: Dictionary, energy_cost: float) -> void:
	queue_entity_command(civ,ship.id,ship.pos,body,[energy_cost,0.0],true)


func ship_command_pending(civ: Civ, id: int) -> bool:
	for pending in civ.command_pending.values():
		if pending["recipient"] == id:
			return true
	return false


func scan_error(civ: Civ, direction: Vector3) -> String:
	var error := _common_error(civ)
	if error != "":
		return error
	if not civ.has_tech("gravity_scan"):
		return "需要103引力波探测"
	if Knowledge.scan_source(self,civ).is_empty():
		return "原母星已失去；只有仍存续母星或流浪地球能扫描"
	if clock < civ.scan_ready_at:
		return "扫描冷却还需 %.2f 年" % (civ.scan_ready_at-clock)
	if space_direction(direction) == Vector3.ZERO:
		return "需要指定扫描方向"
	return _pay_error(civ,Balance.SCAN_COST[0],Balance.SCAN_COST[1])


func active_scan(civ: Civ, direction: Vector3) -> Dictionary:
	var error := scan_error(civ,direction)
	if error != "":
		return {"error":error}
	var source:=Knowledge.scan_source(self,civ)
	civ.scan_ready_at=INF
	queue_entity_command(civ,source["id"],source["pos"],{"name":"scan","direction":direction},Balance.SCAN_COST,true)
	_record(civ,"active_scan",[direction])
	return {"error":""}


func start_earth(civ: Civ, ids: Array, rocky: int) -> Dictionary:
	var error := EarthTransform.known_error(self,civ,ids,rocky)
	if error != "":
		return {"error":error}
	var result := _submit_build(civ,"wandering_earth",civ.original_home,[])
	if result["error"] != "":
		return result
	for project in civ.pending:
		if project["id"] == result["order"]:
			project["earth_roster"] = ids.duplicate()
			project["earth_rocky"] = rocky
	_record(civ,"start_earth",[ids.duplicate(),rocky])
	return result


func queue_entity_command(civ: Civ, id: int, pos: Vector3, body: Dictionary, cost: Array, spend_ap: bool) -> void:
	var control := Signals.entity(self,civs.find(civ),Signals.controller(civ))
	if spend_ap:
		civ.actions_left-=1
	Economy.charge(self,civ,cost,body["name"])
	body["reserved"]=[WorkOrder.units(cost[0]),WorkOrder.units(cost[1])]
	body["recipient_pos"]=pos
	var message := Signals.send(self,civs.find(civ),control["pos"],id,"command",body)
	civ.command_pending[message["id"]]={"recipient":id,"name":body["name"],"sent":clock}
	Signals.receive_due(self)


func reported_starship(civ: Civ) -> Ship:
	for ship in Signals.reported_ships(self,civ):
		if ship.kind in [Ship.STARSHIP,Ship.WANDERING_EARTH]:
			return ship
	return null


func _execute_source_command(civ: Civ,id: int,body: Dictionary) -> bool:
	var source := Signals.entity(self,civs.find(civ),id)
	if source.is_empty():
		return false
	var pos: Vector3=source["pos"]
	var cell:=Vector3i(pos.round())
	if body["name"]=="emergency":
		if not Conversion.is_anchor(source):
			return false
		var dim: int=source["ship"].entity_dim if source.has("ship") else source["asset"]["entity_dim"]
		var gained:=WorkOrder.units(Balance.EMERGENCY_YIELD*Balance.DIMENSION_OUTPUT[str(dim)])
		body["returned"]=[gained,0] if body["resource"]=="E" else [0,gained]
		return true
	if (source.has("ship") and source["ship"].dormant) or (source.has("asset") and civ.dormant_colonies.has(cell)):
		return false
	match body["name"]:
		"grain":
			if not civ.grains.has(cell) or relative_light(pos)<Balance.GRAIN_MIN_LIGHT:
				return false
			civ.grains.erase(cell)
			var grain:=Ship.make(Ship.GRAIN,pos,next_id())
			grain.docked=false
			grain.direction=space_direction(body["direction"])
			grain.origin_cell_id=cell_ids.get(cell,-1)
			civ.ships.append(grain)
			Signals.report_ship(self,civ,grain)
			Knowledge.report_site(self,civ,cell)
		"scan":
			Information.scan(self,civ,source,space_direction(body["direction"]))
			body["scan_ready_at"]=clock+Balance.SCAN_COOLDOWN
		"broadcast":
			if source.has("ship"):
				if not source["ship"].gravity:
					return false
			elif not can_broadcast_now(civ,cell):
				return false
			var exposed:=NO_HIT
			if source.has("asset") and rng.randf()<pow(0.5,pos.distance_to(Vector3(body["target"]))*physical_cell_size()/Balance.BROADCAST_EXPOSE_HALF):
				exposed=cell
			Information.broadcast(self,civ,pos,body["target"],exposed)
		"payload":
			SpaceEvents.launch(self,civs.find(civ),pos,Vector3(body["target"]),body["kind"],body["payload_id"])
	return true


func set_weapon_policy(civ: Civ,ship_id: int,policy: String) -> Dictionary:
	if policy not in ["lethal","economy","special"]:
		return {"error":"未知武器优先级"}
	var ship:=Signals.reported_ship(self,civ,ship_id)
	if ship==null or ship.kind!=Ship.WARSHIP or _common_error(civ)!="":
		return {"error":"需要已知己方战舰"}
	queue_entity_command(civ,ship_id,ship.pos,{"name":"weapon_policy","policy":policy},[0,0],false)
	_record(civ,"set_weapon_policy",[ship_id,policy])
	return {"error":""}


func set_maintenance(civ: Civ,priority: Array,stopped: Array) -> Dictionary:
	if _common_error(civ)!="":
		return {"error":_common_error(civ)}
	var keys: Array=Knowledge.maintenance(self,civ).map(func(p):return p["key"])
	var seen: Dictionary={}
	for key in priority:
		if not keys.has(key) or seen.has(key):
			return {"error":"维护顺序含未知或重复对象"}
		seen[key]=true
	for key in stopped:
		if not keys.has(key):
			return {"error":"停止列表含未知对象"}
	civ.maintenance_priority.assign(priority)
	civ.stopped_packages.assign(stopped)
	_record(civ,"set_maintenance",[priority.duplicate(),stopped.duplicate()])
	return {"error":""}
