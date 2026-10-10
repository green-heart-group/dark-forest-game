class_name Civ
extends RefCounted

## 最后一次锚点损失的物理原因，供同刻批次结束后的淘汰记录使用。
var last_anchor_loss_cause := ""
## 一个文明：拥有的星系、单位、科技，以及它知道的别人的事。
## 据点是母星系、殖民星系和星舰，三样都没有了就灭亡（游戏设计 §1）。

var name: String
var is_ai: bool
var home: Vector3i
## 拥有的星系，第一个是母星系
var colonies: Array[Vector3i] = []
var alive := true

var energy_millis := WorkOrder.units(Balance.START_ENERGY)
var mineral_millis := WorkOrder.units(Balance.START_MINERAL)
## 画面/既有操作继续使用E/M金额；内部一律以.001固定点保存。
var energy: float:
	get: return WorkOrder.amount(energy_millis)
	set(value): energy_millis = WorkOrder.units(value)
var mineral: float:
	get: return WorkOrder.amount(mineral_millis)
	set(value): mineral_millis = WorkOrder.units(value)
var actions_left := 0
## 事件权限永久保存，与达到产能门槛的先后顺序无关。
var contacted := false
var conquered := false
## 当地毁灭战报及同一历史时点的侦察证据；不把文明灭亡等同于星系清空。
var battle_reports: Dictionary = {}
var battle_surveys: Dictionary = {}
var battle_queries: Dictionary = {}
var conquest_confirmation: Dictionary = {}
## 唯一研究队列；工程成本和宿主使用WorkOrder的值记录。
var research_project: Dictionary = {}
var advanced_miners: Dictionary[Vector3i, int] = {}
var warnings: Dictionary[Vector3i, int] = {}
var colonial: Dictionary[Vector3i, bool] = {}
var dormant_colonies: Dictionary[Vector3i, bool] = {}
var dormant_dysons: Dictionary[Vector3i, int] = {}
var maintenance_priority: Array[String] = []
var stopped_packages: Array[String] = []
var starship_ever_built := false
var dimension_ammo := 0
var emergency_turn := -1
var assets: Array[Dictionary] = []
## 连续积分不足.001的尾数，不可用于支付，跨步累计后才入账。
var flow_remainder: Array[float] = [0.0, 0.0]
var ledger: Array[Dictionary] = []
var conversion_receipts: Dictionary = {}
var conversions: Dictionary = {}
var domain_ready_at := 0.0
var scan_ready_at := 0.0
var telemetry: Dictionary = {}
## 只由发送和返回收据修改，不能通过真正在途队列的消失泄露远端状态。
var command_pending: Dictionary = {}
var command_results: Array[Dictionary] = []
var ai_receipt_cursor := 0
var coverage: Dictionary = {}
var local_contacts_by_source: Dictionary = {}
var order_reports: Dictionary = {}
var payload_reports: Dictionary = {}
var site_reports: Dictionary[Vector3i, Dictionary] = {}
var front_reports: Dictionary = {}
var broadcast_reports: Dictionary = {}
var original_home := Vector3i.ZERO
var original_anchor_id := -1

# ---------- 科技 ----------
## 已经有的科技（键是 Tech.ALL 里的名字）
var techs: Dictionary[String, bool] = {}
## 发现过别人的星系或舰船、听到过广播
var discovered := false
## I～III 级从哪个回合起开放（-1：还没达到条件）。条件要按顺序达到，见 GameState._reach_tier（E8）
var tier1_turn := -1
var tier2_turn := -1
var tier3_turn := -1
## 物理端冻结的产能证明；各来源回报全部抵达后才公开阶段权限。
var pending_permissions: Dictionary = {}
## 射电望远镜升级了几次
var telescope := 0

# ---------- 单位和设施 ----------
## 所有单位：停在星系里的、在飞的、停在别人星系上的星际探测器、飞行中的光粒
var ships: Array[Ship] = []
## 存着光粒的星系（每个星系最多 1 颗）
var grains: Dictionary[Vector3i, bool] = {}
## 有恒星广播器的星系
var broadcasters: Dictionary[Vector3i, bool] = {}
## 预警系统：整个文明一个，升级几次
var has_warning := false
var warning_level := 0
## 存着的反物质
var antimatter := 0
## 每个星系上的戴森球个数
var dysons: Dictionary[Vector3i, int] = {}
## 每个星系上的采矿船艘数
var miners: Dictionary[Vector3i, int] = {}
## 有掩体的星系
var bunkers: Dictionary[Vector3i, bool] = {}
## 下一回合建好的设施：每项是 {"kind": 种类, "at": 星系}
var pending: Array[Dictionary] = []
## 准备中或在飞的降维箔
var foils: Array[Foil] = []
## 准备中的黑域：每项是 {"center": 中心坐标, "left": 还要准备几个回合}
var pending_domains: Array[Dictionary] = []

# ---------- 降维 ----------
var reduce_left := 0
var reduced := false
var line_reduced := false
## 奇异点还要几个回合完成，0 表示没有在准备
var singularity_left := 0

# ---------- 知道的事 ----------
## 母星系知道的别的文明的星系：坐标 -> 第几回合看到（情报传回母星系以后才有）
var known: Dictionary[Vector3i, int] = {}
## 看到过的坐标的细节：坐标 -> {"turn", "stars", "rocky", "gas", "habitable", "owner"（文明在 GameState.civs 里的下标，没有时为 -1）, "dysons", "warships",
## "broadcaster", "grain", "foil", "bunker"}（和 GameState.snapshot() 的一样）。传回最近的据点以后才有
var intel: Dictionary[Vector3i, Dictionary] = {}
## 还在路上的情报
var reports: Array[Dictionary] = []
## 看到的别人的舰船：每项是 {"pos", "kind", "turn"}
var sightings: Array[Dictionary] = []
## 看到过的航迹（GameState.wakes 的下标）
var wakes_seen: Dictionary[int, bool] = {}
## 航迹端点分别经传感器回传；只有两端都已收到才画出历史线段。
var wake_reports: Dictionary = {}
## 听到的广播：被广播的坐标 -> 第几回合听到
var heard: Dictionary[Vector3i, int] = {}
## 被打时知道的打击方向：每项是 {"at": 被打的星系, "dir": 打击从哪个方向来, "turn"}
var hit_dirs: Array[Dictionary] = []
## 这一回合预警系统报告的东西：每项是 {"pos", "kind", "turn"}
var alerts: Array[Dictionary] = []
## 敌情记录图：打中过的格子、确认没有敌人的格子
var record_hits: Dictionary[Vector3i, bool] = {}
var record_empty: Dictionary[Vector3i, bool] = {}
## 被打中过几次（包括被挡下的）
var times_hit := 0

# ---------- AI 用 ----------
## 派过殖民船的目标，不再重复去
var colony_tried: Dictionary[Vector3i, bool] = {}
## 发过光粒的目标 -> 第几回合发的，免得光粒还在路上又发一颗
var aimed: Dictionary[Vector3i, int] = {}
## 广播过的坐标
var broadcasted: Dictionary[Vector3i, bool] = {}
## 派智子去过的坐标
var sophon_tried: Dictionary[Vector3i, bool] = {}
## 每个 AI 偏好不同：科技名 -> 额外的优先分
var taste: Dictionary[String, float] = {}


func _init(p_name: String, p_is_ai: bool, p_home: Vector3i) -> void:
	name = p_name
	is_ai = p_is_ai
	home = p_home
	original_home = p_home
	colonies.append(p_home)
	for id in Tech.starting():
		techs[id] = true


func owns(c: Vector3i) -> bool:
	return colonies.has(c)


func has_tech(id: String) -> bool:
	return techs.has(id)


## 第 tier 级从哪个回合起开放（0 级是 0，还没达到条件时为 -1）。
func tier_turn(tier: int) -> int:
	return [0, tier1_turn, tier2_turn, tier3_turn][tier]


func set_tier_turn(tier: int, at: int) -> void:
	set("tier%d_turn" % tier, at)


## 星舰（没有时为 null）。
func starship() -> Ship:
	for s in ships:
		if s.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH] and not s.dead:
			return s
	return null


func has_starship() -> bool:
	return starship() != null


func ship_by_id(id: int) -> Ship:
	for s in ships:
		if s.id == id:
			return s
	return null


## 某种单位（不算光粒）有几个，含停着的。
func count(kind: String) -> int:
	var n := 0
	for s in ships:
		if s.kind == kind and not s.dead:
			n += 1
	return n


## 据点的位置：自己的星系，加上星舰。
func bases() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for c in colonies:
		result.append(Vector3(c))
	var ss := starship()
	if ss != null:
		result.append(ss.pos)
	return result


## 可以作为发射源的格子：自己的星系，加上星舰所在的格子。
func origins() -> Array[Vector3i]:
	var result: Array[Vector3i] = colonies.duplicate()
	var ss := starship()
	if ss != null:
		result.append(ss.cell())
	return result


## 星系全丢了，只剩星舰。
func starship_only() -> bool:
	return colonies.is_empty() and has_starship()


## 所有星系里恒星的总数。
func star_total(map: StarMap) -> int:
	var total := 0
	for c in colonies:
		total += StarMap.star_count(map.star_at(c))
	return total


func dyson_count() -> int:
	var total := 0
	for c in dysons:
		total += dysons[c]
	return total


func miner_count() -> int:
	var total := 0
	for c in miners:
		total += miners[c]
	for c in advanced_miners:
		total += advanced_miners[c]
	return total


func pending_count(kind: String, at = null) -> int:
	var n := 0
	for p in pending:
		if p["kind"] == kind and (at == null or p["at"] == at):
			n += 1
	return n


## 视野加成：射电望远镜每升一次 +TELESCOPE_STEP 格。
func vision_bonus() -> float:
	return telescope * Balance.TELESCOPE_STEP


func warning_range() -> float:
	return Balance.WARNING_RANGE + warning_level


## 每文明每年的固定额度，所有维度一致；殖民地、恒星与锚点数不增加AP。
func action_points(_map: StarMap) -> int:
	return Balance.ACTION_BASE


## 自身降维带上的单位个数，用来算费用。
func reduce_unit_counts() -> Dictionary[String, int]:
	var units := 0
	for s in ships:
		if s.kind != Ship.GRAIN:
			units += 1
	return {
		"systems": colonies.size(), "ships": units, "dysons": dyson_count(), "miners": miner_count(),
		"bunkers": bunkers.size(), "broadcasters": broadcasters.size(), "warning": int(has_warning),
		"antimatter": antimatter, "grains": grains.size(),
	}


func reduce_units() -> int:
	var total := 0
	for n in reduce_unit_counts().values():
		total += n
	return total


func reduce_cost() -> int:
	return Balance.COST_REDUCE_BASE + Balance.COST_REDUCE_PER_UNIT * reduce_units()


## 实体当前维度。全球几何阶段不改变尚未迁维实体的产出。
func entity_dimension() -> int:
	return 1 if line_reduced else (2 if reduced else 3)


func work_factor() -> float:
	return Balance.DIMENSION_WORK[str(entity_dimension())]


## 产能Q、光速c和工作倍率分别读取，不能互相代用。
func output_factor() -> float:
	return Balance.DIMENSION_OUTPUT[str(entity_dimension())]
