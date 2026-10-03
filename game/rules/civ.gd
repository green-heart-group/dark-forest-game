class_name Civ
extends RefCounted
## 一个文明。实力由拥有的恒星总数决定（设计说明 §1）。

var name: String
var is_ai: bool
var home: Vector3i
## 拥有的星系，第一个是母星
var colonies: Array[Vector3i] = []
var alive := true

var energy := Balance.START_ENERGY
var mineral := Balance.START_MINERAL
var actions_left := 0

var scout_range := Balance.INIT_SCOUT_RANGE
var cone_angle := Balance.INIT_CONE_ANGLE
## 在飞的战舰
var warships: Array[Ship] = []
## 在飞的殖民船
var colony_ships: Array[Ship] = []
## 准备中的黑域：每项是 {"center": 中心坐标, "left": 还要准备几个回合}
var pending_domains: Array[Dictionary] = []
## 准备中的广播：每项是 {"target": 要公开的坐标, "left": 还要准备几个回合}
var pending_broadcasts: Array[Dictionary] = []
## 广播过的坐标（AI 用来避免重复广播）
var broadcasted: Dictionary[Vector3i, bool] = {}
## 被打中过几次（包括被预警系统、反物质挡下的）。AI 用来判断要不要躲进黑域
var times_hit := 0
## 有没有星舰，星舰在哪里
var has_starship := false
var starship := Vector3i.ZERO
## 星舰建造中：下一回合在 starship_build_at 建好
var starship_building := false
var starship_build_at := Vector3i.ZERO
## 准备中或在飞的二向箔
var foils: Array[Foil] = []
## 自身降维还要几个回合完成，0 表示没在降维
var reduce_left := 0
## 已经降维（进入二维）：不怕光粒，被二向箔压平也能活，但产能减半
var reduced := false
## AI 用：派过殖民船的目标。目标可能已被别人悄悄占了，不再重复去。
var colony_tried: Dictionary[Vector3i, bool] = {}

## 预警系统：抵消下一次打击
var has_warning := false
## 恒星广播器：有了才能发光粒和广播
var has_broadcaster := false
## 引力波发射器：有了才能广播
var has_gravity := false
## 存着的反物质个数：每个拦下一艘打过来的战舰
var antimatter := 0

## 已下单、下一回合生效的升级和建造（"telescope" / "probe" / "warning" 等）
var pending_upgrades: Array[String] = []
## 每个星系上建好的戴森球个数
var dysons: Dictionary[Vector3i, int] = {}
## 已下单、下一回合建好的戴森球所在的星系（同一个星系可以出现多次）
var pending_dysons: Array[Vector3i] = []
## 有采矿船的星系（每个星系最多一艘）
var miners: Dictionary[Vector3i, bool] = {}
## 已下单、下一回合建好的采矿船所在的星系
var pending_miners: Array[Vector3i] = []
## 建了掩体的星系（下一回合建好）
var bunkers: Dictionary[Vector3i, bool] = {}
var pending_bunkers: Array[Vector3i] = []

var strike_range := Balance.INIT_STRIKE_RANGE
var strike_radius := Balance.INIT_STRIKE_RADIUS

## 已经探测到的其他文明坐标
var known: Dictionary[Vector3i, bool] = {}

## 敌情记录图（类似海战棋记录结果的竖板），只有自己能看到。
## 打中过的格子
var record_hits: Dictionary[Vector3i, bool] = {}
## 光粒经过、确认没有敌人的格子
var record_empty: Dictionary[Vector3i, bool] = {}


func _init(p_name: String, p_is_ai: bool, p_home: Vector3i) -> void:
	name = p_name
	is_ai = p_is_ai
	home = p_home
	colonies.append(p_home)


func owns(c: Vector3i) -> bool:
	return colonies.has(c)


## 可以作为发射源的位置：自己的星系，加上星舰。
func origins() -> Array[Vector3i]:
	var result: Array[Vector3i] = colonies.duplicate()
	if has_starship:
		result.append(starship)
	return result


## 星系全丢了，只剩星舰。
func starship_only() -> bool:
	return colonies.is_empty() and has_starship


## 所有星系里恒星的总数。
func star_total(map: StarMap) -> int:
	var total := 0
	for c in colonies:
		total += StarMap.star_count(map.star_at(c))
	return total


## 恒星越多，能量越多。降维后减半。
func energy_per_turn(map: StarMap) -> int:
	var total := 0
	for c in colonies:
		total += Balance.ENERGY_PER_SYSTEM + StarMap.star_count(map.star_at(c)) * Balance.ENERGY_PER_STAR
	total += dyson_count() * Balance.DYSON_ENERGY
	if starship_only():
		total = Balance.STARSHIP_ENERGY
	return int(total / 2.0) if reduced else total


func dyson_count() -> int:
	var total := 0
	for c in dysons:
		total += dysons[c]
	return total


## 每个星系产矿石，每艘采矿船再多产一些。降维后减半。
func mineral_per_turn(_map: StarMap) -> int:
	var total := colonies.size() * Balance.MINERAL_PER_COLONY + miners.size() * Balance.MINER_MINERAL
	if starship_only():
		total = Balance.STARSHIP_MINERAL
	return int(total / 2.0) if reduced else total


## 自身降维要带进二维的单位数：每个星系、每艘在飞的飞船、星舰各算一个。
func reduce_units() -> int:
	return colonies.size() + warships.size() + colony_ships.size() + (1 if has_starship else 0)


func reduce_cost() -> int:
	return Balance.COST_REDUCE_BASE + Balance.COST_REDUCE_PER_UNIT * reduce_units()


## 恒星越多，行动点越少（乱纪元）。只剩星舰时只有最少的行动点。
func action_points(map: StarMap) -> int:
	if starship_only():
		return Balance.ACTION_MIN
	return maxi(Balance.ACTION_MIN, Balance.ACTION_BASE - star_total(map))


## 能建的戴森球个数等于恒星总数。
func dyson_limit(map: StarMap) -> int:
	return star_total(map)
