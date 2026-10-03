class_name GameState
extends RefCounted
## 一局游戏的全部规则状态。画面只读取它，通过它的方法来行动。
## 日志只写玩家应该知道的事：自己的行动、自己被打、有文明灭亡。

## 发射源参数的默认值，表示「用母星」。
const AT_HOME := Vector3i(-1, -1, -1)
## 「没打中」的返回值
const NO_HIT := Vector3i(-1, -1, -1)
## 「被黑域挡住」的返回值
const TRAPPED := Vector3i(-2, -2, -2)

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
## 被二向箔压平的格子：键是格子坐标，值是它被压到的平面所在的高度 z。所有文明都看得到。
## 平面那一层的格子（z 等于平面高度）还在，降维的文明可以待在上面；其他压平的格子已经没有了。
var flattened: Dictionary[Vector3i, int] = {}
## 生效的黑域的中心坐标。所有文明都看得到。
var black_domains: Array[Vector3i] = []
## 隐藏文明的位置。它们看不见、打不到，只对广播做出反应。
var hidden: Array[Vector3i] = []
## 隐藏文明已经出手、还在路上的打击：每项是 {"target": 坐标, "left": 还要几个回合, "foil": 是不是二向箔}
var hidden_strikes: Array[Dictionary] = []
## 展开的二向箔：每项是 {"center": 展开的格子, "age": 展开了几个回合}。所有文明都看得到。
var foil_zones: Array[Dictionary] = []


## 第一个文明是人类玩家，其余是 AI。母星优先放在宜居星系上。
static func new_game(seed_value: int, ai_count: int = Balance.AI_COUNT) -> GameState:
	var s := GameState.new()
	s.map = StarMap.generate(seed_value)
	s.rng.seed = seed_value + 1

	var candidates: Array[Vector3i] = []
	for c in s.map.habitable:
		candidates.append(c)
	if candidates.size() < ai_count + 1:
		for c in s.map.stars:
			if s.map.stars[c] != StarMap.Star.NONE and not candidates.has(c):
				candidates.append(c)
	# 自己洗牌，不用全局随机数，保证同一个种子结果相同
	for i in range(candidates.size() - 1, 0, -1):
		var j := s.rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	s.civs.append(Civ.new("你", false, candidates[0]))
	for i in ai_count:
		s.civs.append(Civ.new("AI-%d" % (i + 1), true, candidates[i + 1]))
	# 隐藏文明放在没有恒星、也没有文明的格子上
	while s.hidden.size() < Balance.HIDDEN_COUNT:
		var c := Vector3i(s.rng.randi_range(0, StarMap.SIZE - 1), s.rng.randi_range(0, StarMap.SIZE - 1),
				s.rng.randi_range(0, StarMap.SIZE - 1))
		if s.map.star_at(c) == StarMap.Star.NONE and not s.hidden.has(c):
			s.hidden.append(c)
	for civ in s.civs:
		s.start_turn(civ)
	return s


func human() -> Civ:
	return civs[0]


func is_over() -> bool:
	return winner != ""


## 哪个活着的文明的星舰停在这个格子，没有则返回 null。
func starship_owner(c: Vector3i) -> Civ:
	for civ in civs:
		if civ.alive and civ.has_starship and civ.starship == c:
			return civ
	return null


## 哪个活着的文明拥有这个格子，没有则返回 null。
func coord_owner(c: Vector3i) -> Civ:
	for civ in civs:
		if civ.alive and civ.owns(c):
			return civ
	return null


func start_turn(civ: Civ) -> void:
	civ.actions_left = civ.action_points(map)


## 玩家结束回合：AI 依次行动，然后所有文明结算产出，进入下一回合。
func end_turn() -> void:
	if is_over():
		return
	for civ in civs:
		if civ.is_ai and civ.alive and not is_over():
			_ai_turn(civ)
	if is_over():
		return
	for civ in civs:
		if civ.alive and not is_over():
			_move_warships(civ)
	for civ in civs:
		if civ.alive and not is_over():
			_move_colony_ships(civ)
	# 先扩散已有的压平区域，再让二向箔前进；这一回合新展开的，下一回合才扩散
	_spread_flat()
	for civ in civs:
		if civ.alive and not is_over():
			_advance_foils(civ)
	for civ in civs:
		if civ.alive:
			_advance_domains(civ)
	_advance_hidden_strikes()
	for civ in civs:
		if civ.alive and not is_over():
			_advance_broadcasts(civ)
	if is_over():
		return
	for civ in civs:
		if not civ.alive:
			continue
		_apply_upgrades(civ)
		_advance_reduce(civ)
		civ.energy += civ.energy_per_turn(map)
		civ.mineral += civ.mineral_per_turn(map)
		start_turn(civ)
	turn += 1
	add_log("第 %d 回合开始" % turn)


# ---------- 行动 ----------

## 从 origin（默认母星）朝 direction 发出圆锥探测。
## 返回 {"error": 出错原因，成功时为空, "found": 新发现的坐标}。
func scout(civ: Civ, direction: Vector3, origin: Vector3i = AT_HOME) -> Dictionary:
	var found: Array[Vector3i] = []
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_action(civ, direction, origin, Balance.COST_SCOUT)
	if error != "":
		return {"error": error, "found": found}

	civ.energy -= Balance.COST_SCOUT
	civ.actions_left -= 1
	for c in Geometry.cone_cells(origin, direction, civ.scout_range, civ.cone_angle):
		var owner := coord_owner(c)
		if owner != null and owner != civ and not civ.known.has(c) and not blocked(origin, c):
			civ.known[c] = true
			found.append(c)
	if not civ.is_ai:
		if found.is_empty():
			add_log("探测：没有发现")
		else:
			add_log("探测：发现 %d 个文明坐标" % found.size())
	return {"error": "", "found": found}


## 从 origin（默认母星）朝 direction 发射光粒。
## 圆柱范围内最近的敌方星系被打中，少一颗恒星；自己的星系会被穿过。
## 返回 {"error": 出错原因, "hit": 是否打中, "cell": 打中的格子}。
func lightgrain(civ: Civ, direction: Vector3, origin: Vector3i = AT_HOME) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_action(civ, direction, origin, Balance.COST_LIGHTGRAIN)
	if error == "" and not civ.has_broadcaster:
		error = "要先建恒星广播器"
	if error != "":
		return {"error": error, "hit": false, "cell": Vector3i.ZERO}

	civ.energy -= Balance.COST_LIGHTGRAIN
	civ.actions_left -= 1
	var cells := Geometry.cylinder_cells(origin, direction, civ.strike_range, civ.strike_radius)
	var hit := _sweep(civ, origin, cells, "光粒")
	if hit == TRAPPED:
		if not civ.is_ai:
			add_log("光粒：被黑域挡住")
		return {"error": "", "hit": false, "cell": Vector3i.ZERO}
	if hit != NO_HIT:
		return {"error": "", "hit": true, "cell": hit}
	if not civ.is_ai:
		add_log("光粒：没打中")
	return {"error": "", "hit": false, "cell": Vector3i.ZERO}


## 从 origin（默认母星）朝 direction 派出战舰。之后每回合结束时前进一段。
## 返回 {"error": 出错原因，成功时为空}。
func launch_warship(civ: Civ, direction: Vector3, origin: Vector3i = AT_HOME) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_build(civ)
	if error == "":
		error = _check_action(civ, direction, origin, Balance.COST_WARSHIP_ENERGY,
				Balance.COST_WARSHIP_MINERAL)
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_WARSHIP_ENERGY
	civ.mineral -= Balance.COST_WARSHIP_MINERAL
	civ.actions_left -= 1
	civ.warships.append(Ship.new(origin, direction))
	if not civ.is_ai:
		add_log("战舰出发，方向 (%.0f, %.0f, %.0f)" % [direction.x, direction.y, direction.z])
	return {"error": ""}


## 从 origin（默认母星）朝 direction 派出殖民船。之后每回合结束时前进一段，
## 停在经过的第一个无主宜居星系。返回 {"error": 出错原因，成功时为空}。
func launch_colony_ship(civ: Civ, direction: Vector3, origin: Vector3i = AT_HOME) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_build(civ)
	if error == "":
		error = _check_action(civ, direction, origin, Balance.COST_COLONY_ENERGY,
				Balance.COST_COLONY_MINERAL)
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_COLONY_ENERGY
	civ.mineral -= Balance.COST_COLONY_MINERAL
	civ.actions_left -= 1
	civ.colony_ships.append(Ship.new(origin, direction))
	if not civ.is_ai:
		add_log("殖民船出发，方向 (%.0f, %.0f, %.0f)" % [direction.x, direction.y, direction.z])
	return {"error": ""}


## 每艘殖民船前进一段，检查新飞过的格子：遇到无主的宜居星系就停下，成为殖民地；
## 有主的星系直接飞过（不会暴露任何信息）；飞出星图就消失。
func _move_colony_ships(civ: Civ) -> void:
	var still_flying: Array[Ship] = []
	for ship in civ.colony_ships:
		var from_t := ship.traveled
		ship.traveled += Balance.COLONY_SHIP_SPEED
		var cells := Geometry.cylinder_cells_between(ship.origin, ship.direction, from_t,
				ship.traveled, Balance.COLONY_SHIP_RADIUS)
		var settled := false
		var trapped := false
		for c in cells:
			if blocked(ship.origin, c):
				trapped = true
				break
			if can_settle(c):
				civ.colonies.append(c)
				if not civ.is_ai:
					add_log("殖民船在 %s 建立殖民地（%d 颗恒星）" % [c, map.star_at(c)])
				settled = true
				break
		if settled:
			continue
		if trapped:
			if not civ.is_ai:
				add_log("殖民船被黑域困住")
			continue
		if ship.is_outside():
			if not civ.is_ai:
				add_log("殖民船飞出星图，没有找到可殖民的星系")
			continue
		still_flying.append(ship)
	civ.colony_ships = still_flying


## 这个格子能不能建立殖民地：宜居、还有恒星、没有活着的文明占着。
func can_settle(c: Vector3i) -> bool:
	return map.is_habitable(c) and map.star_at(c) != StarMap.Star.NONE and coord_owner(c) == null


## 每艘战舰前进一段，检查新飞过的格子：碰到敌方星系就攻击并消耗掉，飞出星图就消失。
func _move_warships(civ: Civ) -> void:
	var still_flying: Array[Ship] = []
	for ship in civ.warships:
		var from_t := ship.traveled
		ship.traveled += Balance.WARSHIP_SPEED
		var cells := Geometry.cylinder_cells_between(ship.origin, ship.direction, from_t,
				ship.traveled, civ.strike_radius)
		var hit := _sweep(civ, ship.origin, cells, "战舰")
		if is_over():
			return
		if hit == TRAPPED:
			if not civ.is_ai:
				add_log("战舰被黑域困住")
			continue
		if hit != NO_HIT:
			continue
		if ship.is_outside():
			if not civ.is_ai:
				add_log("战舰飞出星图")
			continue
		still_flying.append(ship)
	civ.warships = still_flying


## 打击沿途的格子（已按由近到远排好）：空格子记进敌情记录图，
## 碰到第一个敌方星系就让它少一颗恒星并停下。返回打中的格子，没打中返回 NO_HIT，
## 碰到黑域边界（和发射源 origin 不在同一边）返回 TRAPPED。
func _sweep(civ: Civ, origin: Vector3i, cells: Array[Vector3i], weapon: String) -> Vector3i:
	for c in cells:
		if blocked(origin, c):
			return TRAPPED
		var owner := coord_owner(c)
		if owner == null and weapon == "战舰":
			var ship_owner := starship_owner(c)
			if ship_owner != null and ship_owner != civ:
				if not civ.is_ai:
					add_log("战舰：在 %s 撞毁一艘星舰" % c)
				_lose_starship(ship_owner, "战舰")
				return c
		if owner == civ:
			continue
		if owner == null:
			# 以前以为这里有敌人的，说明情报已经过时
			civ.record_empty[c] = true
			civ.known.erase(c)
			continue
		civ.record_hits[c] = true
		civ.record_empty.erase(c)
		civ.known[c] = true
		owner.times_hit += 1
		if owner.reduced and weapon == "光粒":
			if not civ.is_ai:
				add_log("光粒：打中 %s，但对方已降维，光粒无效" % c)
			return c

		if weapon == "战舰" and owner.antimatter > 0:
			owner.antimatter -= 1
			if not civ.is_ai:
				add_log("战舰：到达 %s，被对方的反物质拦下" % c)
			if owner == human():
				add_log("反物质拦下了一艘打向 %s 的战舰，还剩 %d 个" % [c, owner.antimatter])
			return c
		if owner.has_warning:
			owner.has_warning = false
			if not civ.is_ai:
				add_log("%s：打中 %s，但被对方的预警系统抵消" % [weapon, c])
			if owner == human():
				add_log("预警系统抵消了一次%s打击（%s），需要重新建造" % [weapon, c])
			return c
		if not civ.is_ai:
			add_log("%s：打中 %s" % [weapon, c])
		_lose_star(c, owner, civ, weapon)
		return c
	return NO_HIT


## 从 origin（默认母星）向目标坐标 target 发射二向箔：先准备几个回合，再飞过去。
## 返回 {"error": 出错原因，成功时为空}。
func launch_foil(civ: Civ, target: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_build(civ)
	if error == "" and not StarMap.in_bounds(target):
		error = "目标坐标不在星图内"
	if error == "" and target == origin:
		error = "目标不能是发射源"
	if error == "" and civ.owns(target):
		error = "目标不能是自己的星系"
	if error == "" and flattened.has(target):
		error = "这一格已经压平了"
	if error == "":
		error = _check_action(civ, Vector3(target - origin), origin, Balance.COST_FOIL)
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_FOIL
	civ.actions_left -= 1
	civ.foils.append(Foil.new(origin, target, Balance.FOIL_PREPARE_TURNS))
	if not civ.is_ai:
		add_log("二向箔开始准备，目标 %s，%d 回合后起飞" % [target, Balance.FOIL_PREPARE_TURNS])
	return {"error": ""}


## 每片二向箔：还在准备的，准备回合减一；已经起飞的，前进一段。
## 碰到别人的星系，或到达目标（最后一步直接落在目标上），就在那里展开。
func _advance_foils(civ: Civ) -> void:
	var still_flying: Array[Foil] = []
	for foil in civ.foils:
		if foil.prepare_left > 0:
			foil.prepare_left -= 1
			if foil.prepare_left == 0 and not civ.is_ai:
				add_log("二向箔准备完成，起飞")
			still_flying.append(foil)
			continue
		var from_t := foil.traveled
		foil.traveled = minf(foil.traveled + Balance.FOIL_SPEED, foil.total_distance())
		var arrived := foil.traveled >= foil.total_distance() - 1e-6
		var at := NO_HIT
		# 多算一点点，免得浮点误差把目标格子漏掉
		for c in Geometry.cylinder_cells_between(foil.origin, foil.direction(), from_t,
				foil.traveled + 1e-4, 0.0):
			var owner := coord_owner(c)
			if owner != null and owner != civ:
				at = c
				break
		if at == NO_HIT and arrived:
			at = foil.target
		if at == NO_HIT:
			still_flying.append(foil)
			continue
		add_log("二向箔在 %s 展开" % at)
		_unfold_foil(at)
		if is_over():
			return
	civ.foils = still_flying


## 把格子 c 压到高度 plane 的平面上（同一个 x、y，z 变成 plane）。这一格里没降维的文明失去星系，
## 恒星也随之消失；在这一格里的飞船（主人没降维的）也被毁掉。
## 降维的文明活下来，但星系和星舰都被移到平面上。
func _flatten_cell(c: Vector3i, plane: int) -> void:
	if flattened.has(c) or not StarMap.in_bounds(c):
		return
	flattened[c] = plane
	var r := Balance.BLACK_DOMAIN_RADIUS
	black_domains = black_domains.filter(func(d): return maxi(maxi(absi(d.x - c.x), absi(d.y - c.y)), absi(d.z - c.z)) > r)
	var flat := Vector3i(c.x, c.y, plane)
	var owner := coord_owner(c)
	if owner != null and owner.reduced:
		_move_system(owner, c, flat)
	else:
		map.stars[c] = StarMap.Star.NONE
		for civ in civs:
			civ.known.erase(c)
		if owner != null:
			if owner == human():
				add_log("你的星系 %s 被二向箔压平" % c)
			_lose_system(c, owner)
	for civ in civs:
		if civ.alive and civ.has_starship and civ.starship == c:
			if civ.reduced:
				civ.starship = flat
			else:
				_lose_starship(civ, "二向箔")
		if civ.reduced:
			continue
		civ.warships = _outside_cell(civ.warships, c)
		civ.colony_ships = _outside_cell(civ.colony_ships, c)
	if all_flat():
		_check_winner()


## 整张星图是不是都压平了。
func all_flat() -> bool:
	return flattened.size() == StarMap.SIZE * StarMap.SIZE * StarMap.SIZE


## 降维文明的星系被压到平面上：从 from 搬到 to，恒星、戴森球、采矿船跟着走，
## 知道这个坐标的文明也改记新坐标。平面上那一格已经有星系时（同一列里后压下来的），
## 就当作被压毁了。
func _move_system(owner: Civ, from: Vector3i, to: Vector3i) -> void:
	if from == to:
		return
	if coord_owner(to) != null:
		if owner == human():
			add_log("你的星系 %s 被压到平面上，和 %s 的星系重叠，毁掉了" % [from, to])
		map.stars[from] = StarMap.Star.NONE
		_lose_system(from, owner)
		return
	map.stars[to] = map.stars[from]
	map.stars[from] = StarMap.Star.NONE
	for planets in [map.rocky, map.gas]:
		planets[to] = planets.get(from, 0)
		planets.erase(from)
	if map.habitable.has(from):
		map.habitable.erase(from)
		map.habitable[to] = true
	owner.colonies[owner.colonies.find(from)] = to
	if owner.home == from:
		owner.home = to
	if owner.dysons.has(from):
		owner.dysons[to] = owner.dysons[from]
		owner.dysons.erase(from)
	for marks in [owner.miners, owner.bunkers]:
		if marks.has(from):
			marks.erase(from)
			marks[to] = true
	for list in [owner.pending_dysons, owner.pending_miners, owner.pending_bunkers]:
		for i in list.size():
			if list[i] == from:
				list[i] = to
	if owner.starship_build_at == from:
		owner.starship_build_at = to
	for civ in civs:
		if civ.known.has(from):
			civ.known.erase(from)
			civ.known[to] = true
	if owner == human():
		add_log("你的星系 %s 被压到平面上，现在在 %s" % [from, to])


## 不在格子 c 里的飞船。
func _outside_cell(ships: Array[Ship], c: Vector3i) -> Array[Ship]:
	var kept: Array[Ship] = []
	for s in ships:
		if Vector3i(s.position().round()) != c:
			kept.append(s)
	return kept


## 二向箔在格子 at 展开：平面的高度是 at 的 z，马上压平它能压到的格子。
func _unfold_foil(at: Vector3i) -> void:
	var zone := {"center": at, "age": 0}
	foil_zones.append(zone)
	_apply_zone(zone)


## 每回合每片展开的二向箔再扩散一圈。
func _spread_flat() -> void:
	for zone in foil_zones:
		zone["age"] += 1
		_apply_zone(zone)


## 展开了 age 回合、中心在 center 的二向箔，有没有把格子 c 压没。
## 中心周围半径 age 的圆里，整列都压到平面上；圆外面离圆边 x 格的地方，
## 平面上下各只剩 FOIL_SQUISH × x² 格，超出的被压没。侧面看像躺倒的沙漏，中心最扁。
static func zone_covers(center: Vector3i, age: int, c: Vector3i) -> bool:
	var x := Vector2(c.x - center.x, c.y - center.y).length() - age
	return x <= 0.0 or absi(c.z - center.z) > Balance.FOIL_SQUISH * x * x


## 展开了 age 回合时，离中心水平距离 d 的地方，平面上下各还剩多高（没有剩下时为 0）。
static func zone_room(age: int, d: float) -> float:
	var x := d - age
	return 0.0 if x <= 0.0 else Balance.FOIL_SQUISH * x * x


## 压平这片二向箔压到的格子。离平面近的先压，免得降维文明的星系移到平面上时，
## 撞上待会儿才会被压掉的别人的星系。
func _apply_zone(zone: Dictionary) -> void:
	var center: Vector3i = zone["center"]
	var age: int = zone["age"]
	for h in StarMap.SIZE:
		for z in ([center.z - h, center.z + h] if h > 0 else [center.z]):
			if z < 0 or z >= StarMap.SIZE:
				continue
			for x in StarMap.SIZE:
				for y in StarMap.SIZE:
					var c := Vector3i(x, y, z)
					if not flattened.has(c) and zone_covers(center, age, c):
						_flatten_cell(c, center.z)
						if is_over():
							return


## 格子 c 再过几个回合会被压没（已经压没时为 0，没有展开的二向箔时为 INF）。
func turns_until_flat(c: Vector3i) -> float:
	var best := INF
	for zone in foil_zones:
		var center: Vector3i = zone["center"]
		var d := Vector2(c.x - center.x, c.y - center.y).length()
		var h := absi(c.z - center.z)
		best = minf(best, maxf(0.0, d - sqrt(h / Balance.FOIL_SQUISH) - zone["age"]))
	return best


## 以 center 为中心投放黑域：center 离发射源 origin（默认母星）不能超过探测长度。
## 准备几个回合后生效。返回 {"error": 出错原因，成功时为空}。
func launch_black_domain(civ: Civ, center: Vector3i, origin: Vector3i = AT_HOME) -> Dictionary:
	if origin == AT_HOME:
		origin = civ.home
	var error := _check_build(civ)
	if error == "" and not StarMap.in_bounds(center):
		error = "中心坐标不在星图内"
	if error == "" and Vector3(center - origin).length() > civ.scout_range:
		error = "中心离发射源太远，超出探测长度"
	if error == "":
		# 方向随便给一个，投放黑域不需要方向
		error = _check_action(civ, Vector3.ONE, origin, Balance.COST_BLACK_DOMAIN)
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_BLACK_DOMAIN
	civ.actions_left -= 1
	civ.pending_domains.append({"center": center, "left": Balance.BLACK_DOMAIN_PREPARE_TURNS})
	if not civ.is_ai:
		add_log("开始投放黑域，中心 %s，%d 回合后生效" % [center, Balance.BLACK_DOMAIN_PREPARE_TURNS])
	return {"error": ""}


func _advance_domains(civ: Civ) -> void:
	var still: Array[Dictionary] = []
	for d in civ.pending_domains:
		d["left"] -= 1
		if d["left"] > 0:
			still.append(d)
			continue
		var center: Vector3i = d["center"]
		# 已经被压平的地方生不成黑域
		if flattened.has(center):
			continue
		black_domains.append(center)
		add_log("%s 出现黑域" % center)
	civ.pending_domains = still


## 广播坐标 target（星图内任意格子）：准备几个回合后公开，所有文明都知道这个坐标。
## 返回 {"error": 出错原因，成功时为空}。
func broadcast(civ: Civ, target: Vector3i) -> Dictionary:
	var error := ""
	if not StarMap.in_bounds(target):
		error = "坐标不在星图内"
	elif civ.owns(target):
		error = "不能广播自己的坐标"
	elif not civ.has_broadcaster and not civ.has_gravity:
		error = "要先建恒星广播器或引力波发射器"
	else:
		# 方向随便给一个，广播不需要方向
		error = _check_action(civ, Vector3.ONE, civ.home, Balance.COST_BROADCAST)
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_BROADCAST
	civ.actions_left -= 1
	civ.broadcasted[target] = true
	civ.pending_broadcasts.append({"target": target, "left": Balance.BROADCAST_PREPARE_TURNS})
	if not civ.is_ai:
		add_log("开始广播 %s，%d 回合后公开" % [target, Balance.BROADCAST_PREPARE_TURNS])
	return {"error": ""}


func _advance_broadcasts(civ: Civ) -> void:
	var still: Array[Dictionary] = []
	for b in civ.pending_broadcasts:
		b["left"] -= 1
		if b["left"] > 0:
			still.append(b)
		else:
			_publish(civ, b["target"])
	civ.pending_broadcasts = still


## 广播生效：坐标公开。那里有别人的星系时，所有其他文明都知道它，附近的隐藏文明可能出手。
func _publish(sender: Civ, target: Vector3i) -> void:
	add_log("广播：坐标 %s 被公开" % target)
	var owner := coord_owner(target)
	if owner == null or owner == sender:
		return
	for civ in civs:
		if civ.alive and civ != owner:
			civ.known[target] = true
	if owner == human():
		add_log("你的星系 %s 暴露了" % target)
	for h in hidden:
		var d := Vector3(h - target).length()
		var chance := Balance.HIDDEN_STRIKE_CHANCE * (1.0 - d / Balance.HIDDEN_HEAR_RANGE)
		if chance > 0.0 and rng.randf() < chance:
			hidden_strikes.append({"target": target, "left": Balance.HIDDEN_STRIKE_DELAY,
					"foil": rng.randf() < Balance.HIDDEN_FOIL_CHANCE})
			return  # 一次广播最多引来一次打击


func _advance_hidden_strikes() -> void:
	var still: Array[Dictionary] = []
	for s in hidden_strikes:
		s["left"] -= 1
		if s["left"] > 0:
			still.append(s)
		elif not is_over():
			_hidden_strike(s["target"], s["foil"])
	hidden_strikes = still


## 隐藏文明打到 target：二向箔直接在那里展开；光粒和普通光粒一样会被降维、预警系统挡下。
## 隐藏文明在黑域外，打不进黑域。
func _hidden_strike(target: Vector3i, foil: bool) -> void:
	var owner := coord_owner(target)
	if foil:
		add_log("一片来历不明的二向箔在 %s 展开" % target)
		_unfold_foil(target)
		return
	if owner == null or in_black_domain(target):
		return
	owner.times_hit += 1
	var weapon := "来历不明的光粒"
	if owner.reduced:
		if owner == human():
			add_log("%s打中你的星系 %s，但你已降维，光粒无效" % [weapon, target])
		return

	if owner.has_warning:
		owner.has_warning = false
		if owner == human():
			add_log("预警系统抵消了一次%s打击（%s），需要重新建造" % [weapon, target])
		return
	_lose_star(target, owner, null, weapon)


## 这个格子在不在任何一个黑域里。
func in_black_domain(c: Vector3i) -> bool:
	var r := Balance.BLACK_DOMAIN_RADIUS
	for d in black_domains:
		if absi(c.x - d.x) <= r and absi(c.y - d.y) <= r and absi(c.z - d.z) <= r:
			return true
	return false


## 从 a 到 b 会不会被黑域挡住。光和飞船都不能穿过黑域的边界，所以：
## 一边在黑域里、另一边不在，挡住；两边都在外面，但直线穿过了黑域（黑域像一堵墙挡在中间），也挡住。
func blocked(a: Vector3i, b: Vector3i) -> bool:
	if in_black_domain(a) != in_black_domain(b):
		return true
	if in_black_domain(a):
		return false
	var half := Balance.BLACK_DOMAIN_RADIUS + 0.5
	for d in black_domains:
		if _segment_hits_box(Vector3(a), Vector3(b), Vector3(d) - Vector3.ONE * half, Vector3(d) + Vector3.ONE * half):
			return true
	return false


## 线段 a→b 有没有碰到以 lo、hi 为对角的方块（分别看 x、y、z 三个方向的进出范围）。
static func _segment_hits_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var t_in := 0.0
	var t_out := 1.0
	var d := b - a
	for i in 3:
		if absf(d[i]) < 1e-9:
			if a[i] < lo[i] or a[i] > hi[i]:
				return false
			continue
		var t1 := (lo[i] - a[i]) / d[i]
		var t2 := (hi[i] - a[i]) / d[i]
		t_in = maxf(t_in, minf(t1, t2))
		t_out = minf(t_out, maxf(t1, t2))
		if t_in > t_out:
			return false
	return true


## 开始自身降维：花能量和 1 个行动点，几个回合后完成，期间不能建造。
## 返回 {"error": 出错原因，成功时为空}。
func start_reduce(civ: Civ) -> Dictionary:
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif civ.reduced:
		error = "已经降维"
	elif civ.reduce_left > 0:
		error = "正在降维"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif civ.energy < civ.reduce_cost():
		error = "能量不足"
	if error != "":
		return {"error": error}
	civ.energy -= civ.reduce_cost()
	civ.actions_left -= 1
	civ.reduce_left = Balance.REDUCE_TURNS
	if not civ.is_ai:
		add_log("开始自身降维，%d 回合后完成，期间不能建造" % Balance.REDUCE_TURNS)
	return {"error": ""}


func _advance_reduce(civ: Civ) -> void:
	if civ.reduce_left <= 0:
		return
	civ.reduce_left -= 1
	if civ.reduce_left == 0:
		civ.reduced = true
		if not civ.is_ai:
			add_log("自身降维完成：不怕光粒和二向箔，产能减半")


## 在自己的星系 at（默认母星）上建一个戴森球，花矿石，下一回合建好。
## 每个星系最多建到和它的恒星数一样多。返回 {"error": 出错原因，成功时为空}。
func build_dyson(civ: Civ, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif _check_build(civ) != "":
		error = _check_build(civ)
	elif not civ.owns(at):
		error = "只能建在自己的星系"
	elif civ.dysons.get(at, 0) + civ.pending_dysons.count(at) >= StarMap.star_count(map.star_at(at)):
		error = "这个星系的每颗恒星都已经有戴森球"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif civ.mineral < Balance.COST_DYSON:
		error = "矿石不足"
	if error != "":
		return {"error": error}
	civ.mineral -= Balance.COST_DYSON
	civ.actions_left -= 1
	civ.pending_dysons.append(at)
	if not civ.is_ai:
		add_log("开始在 %s 建戴森球，下一回合建好" % at)
	return {"error": ""}


## 在自己的星系 at（默认母星）上建星舰，每个文明最多一艘，下一回合建好。
## 返回 {"error": 出错原因，成功时为空}。
func build_starship(civ: Civ, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif _check_build(civ) != "":
		error = _check_build(civ)
	elif not civ.owns(at):
		error = "只能建在自己的星系"
	elif civ.has_starship or civ.starship_building:
		error = "已经有星舰"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif civ.energy < Balance.COST_STARSHIP_ENERGY:
		error = "能量不足"
	elif civ.mineral < Balance.COST_STARSHIP_MINERAL:
		error = "矿石不足"
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_STARSHIP_ENERGY
	civ.mineral -= Balance.COST_STARSHIP_MINERAL
	civ.actions_left -= 1
	civ.starship_building = true
	civ.starship_build_at = at
	if not civ.is_ai:
		add_log("开始在 %s 建星舰，下一回合建好" % at)
	return {"error": ""}


## 星舰朝 direction 移动，最远 max_distance 格（不超过 STARSHIP_JUMP），停在路上最远的一个能停的格子：
## 在星图内、没有别人的星系、没被压平。不能穿过黑域的边界。
## 返回 {"error": 出错原因，成功时为空, "to": 到达的格子}。
func move_starship(civ: Civ, direction: Vector3, max_distance: float = Balance.STARSHIP_JUMP) -> Dictionary:
	var error := ""
	if not civ.has_starship:
		error = "没有星舰"
	else:
		error = _check_action(civ, direction, civ.starship, Balance.COST_STARSHIP_MOVE)
	var dest := civ.starship
	if error == "":
		for c in Geometry.cylinder_cells(civ.starship, direction, minf(max_distance, Balance.STARSHIP_JUMP), 0.0):
			if blocked(civ.starship, c):
				break
			var owner := coord_owner(c)
			if (owner != null and owner != civ) or flattened.has(c):
				continue
			dest = c
		if dest == civ.starship:
			error = "这个方向上没有能停的格子"
	if error != "":
		return {"error": error, "to": civ.starship}
	civ.energy -= Balance.COST_STARSHIP_MOVE
	civ.actions_left -= 1
	civ.starship = dest
	if civ.colonies.is_empty():
		civ.home = dest
	if not civ.is_ai:
		add_log("星舰移动到 %s" % dest)
	return {"error": "", "to": dest}


## 星舰停在无主的宜居星系上时，在那里建立星系，星舰用掉。花 1 个行动点。
## 返回 {"error": 出错原因，成功时为空}。
func settle_starship(civ: Civ) -> Dictionary:
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif not civ.has_starship:
		error = "没有星舰"
	elif not can_settle(civ.starship):
		error = "星舰不在无主的宜居星系上"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	if error != "":
		return {"error": error}
	civ.actions_left -= 1
	civ.has_starship = false
	civ.colonies.append(civ.starship)
	if civ.colonies.size() == 1:
		civ.home = civ.starship
	if not civ.is_ai:
		add_log("星舰在 %s 建立星系（%d 颗恒星）" % [civ.starship, map.star_at(civ.starship)])
	return {"error": ""}


## 在自己的星系 at（默认母星）上建采矿船，每个星系最多一艘，下一回合建好。
## 返回 {"error": 出错原因，成功时为空}。
func build_miner(civ: Civ, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif _check_build(civ) != "":
		error = _check_build(civ)
	elif not civ.owns(at):
		error = "只能建在自己的星系"
	elif civ.miners.has(at) or civ.pending_miners.has(at):
		error = "这个星系已经有采矿船"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif civ.mineral < Balance.COST_MINER:
		error = "矿石不足"
	if error != "":
		return {"error": error}
	civ.mineral -= Balance.COST_MINER
	civ.actions_left -= 1
	civ.pending_miners.append(at)
	if not civ.is_ai:
		add_log("开始在 %s 建采矿船，下一回合建好" % at)
	return {"error": ""}


## 在自己有类木行星的星系 at（默认母星）上建掩体，每个星系一个，下一回合建好。
## 建好后光粒打掉这个星系的最后一颗恒星时，星系不会丢。返回 {"error": 出错原因，成功时为空}。
func build_bunker(civ: Civ, at: Vector3i = AT_HOME) -> Dictionary:
	if at == AT_HOME:
		at = civ.home
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif _check_build(civ) != "":
		error = _check_build(civ)
	elif not civ.owns(at):
		error = "只能建在自己的星系"
	elif map.gas.get(at, 0) == 0:
		error = "这个星系没有类木行星"
	elif civ.bunkers.has(at) or civ.pending_bunkers.has(at):
		error = "这个星系已经有掩体"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif civ.energy < Balance.COST_BUNKER_ENERGY:
		error = "能量不足"
	elif civ.mineral < Balance.COST_BUNKER_MINERAL:
		error = "矿石不足"
	if error != "":
		return {"error": error}
	civ.energy -= Balance.COST_BUNKER_ENERGY
	civ.mineral -= Balance.COST_BUNKER_MINERAL
	civ.actions_left -= 1
	civ.pending_bunkers.append(at)
	if not civ.is_ai:
		add_log("开始在 %s 建掩体，下一回合建好" % at)
	return {"error": ""}


## 升级或建造，下一回合生效。kind 为：
##   "telescope"：射电望远镜，张角变大
##   "probe"：探测器，探测更远
##   "warning"：预警系统，抵消一次打击
##   "antimatter"：反物质，拦下一艘打过来的战舰（可以存几个）
##   "broadcaster"：恒星广播器，有了才能发光粒和广播
##   "gravity"：引力波发射器，有了才能广播
## 返回 {"error": 出错原因，成功时为空}。
func upgrade(civ: Civ, kind: String) -> Dictionary:
	var error := ""
	if is_over():
		error = "游戏已结束"
	elif not civ.alive:
		error = "文明已灭亡"
	elif _check_build(civ) != "":
		error = _check_build(civ)
	elif civ.pending_upgrades.has(kind):
		error = "这一项已在升级中"
	elif civ.actions_left <= 0:
		error = "行动点不足"
	elif kind == "telescope":
		if civ.cone_angle >= Balance.MAX_CONE_ANGLE:
			error = "张角已到上限"
		elif civ.energy < Balance.COST_TELESCOPE:
			error = "能量不足"
	elif kind == "probe":
		if civ.scout_range >= Balance.MAX_SCOUT_RANGE:
			error = "探测长度已到上限"
		elif civ.mineral < Balance.COST_PROBE:
			error = "矿石不足"
	elif kind == "warning":
		if civ.has_warning:
			error = "已经有预警系统"
		elif civ.energy < Balance.COST_WARNING:
			error = "能量不足"
	elif kind == "antimatter":
		if civ.antimatter >= Balance.MAX_ANTIMATTER:
			error = "反物质已经存满"
		elif civ.energy < Balance.COST_ANTIMATTER_ENERGY:
			error = "能量不足"
		elif civ.mineral < Balance.COST_ANTIMATTER_MINERAL:
			error = "矿石不足"
	elif kind == "broadcaster":
		if civ.has_broadcaster:
			error = "已经有恒星广播器"
		elif civ.energy < Balance.COST_BROADCASTER:
			error = "能量不足"
	elif kind == "gravity":
		if civ.has_gravity:
			error = "已经有引力波发射器"
		elif civ.energy < Balance.COST_GRAVITY_ENERGY:
			error = "能量不足"
		elif civ.mineral < Balance.COST_GRAVITY_MINERAL:
			error = "矿石不足"
	else:
		error = "未知的升级"
	if error != "":
		return {"error": error}

	match kind:
		"telescope": civ.energy -= Balance.COST_TELESCOPE
		"probe": civ.mineral -= Balance.COST_PROBE
		"warning": civ.energy -= Balance.COST_WARNING
		"antimatter":
			civ.energy -= Balance.COST_ANTIMATTER_ENERGY
			civ.mineral -= Balance.COST_ANTIMATTER_MINERAL
		"broadcaster": civ.energy -= Balance.COST_BROADCASTER
		"gravity":
			civ.energy -= Balance.COST_GRAVITY_ENERGY
			civ.mineral -= Balance.COST_GRAVITY_MINERAL
	civ.actions_left -= 1
	civ.pending_upgrades.append(kind)
	if not civ.is_ai:
		var names := {"telescope": "升级射电望远镜", "probe": "升级探测器", "warning": "建造预警系统",
				"antimatter": "制造反物质", "broadcaster": "建造恒星广播器", "gravity": "建造引力波发射器"}
		add_log("开始%s，下一回合生效" % names[kind])
	return {"error": ""}


func _apply_upgrades(civ: Civ) -> void:
	for kind in civ.pending_upgrades:
		match kind:
			"telescope":
				civ.cone_angle = minf(civ.cone_angle + Balance.TELESCOPE_STEP, Balance.MAX_CONE_ANGLE)
			"probe":
				civ.scout_range = minf(civ.scout_range + Balance.PROBE_STEP, Balance.MAX_SCOUT_RANGE)
			"warning":
				civ.has_warning = true
			"antimatter":
				civ.antimatter = mini(civ.antimatter + 1, Balance.MAX_ANTIMATTER)
			"broadcaster":
				civ.has_broadcaster = true
			"gravity":
				civ.has_gravity = true
	civ.pending_upgrades.clear()
	for c in civ.pending_dysons:
		# 建造期间星系可能丢了，或者恒星被打掉了
		if civ.owns(c) and civ.dysons.get(c, 0) < StarMap.star_count(map.star_at(c)):
			civ.dysons[c] = civ.dysons.get(c, 0) + 1
	civ.pending_dysons.clear()
	if civ.starship_building:
		civ.starship_building = false
		if civ.owns(civ.starship_build_at):
			civ.has_starship = true
			civ.starship = civ.starship_build_at
			if not civ.is_ai:
				add_log("星舰在 %s 建好" % civ.starship)
	for c in civ.pending_miners:
		if civ.owns(c):
			civ.miners[c] = true
	civ.pending_miners.clear()
	for c in civ.pending_bunkers:
		if civ.owns(c):
			civ.bunkers[c] = true
	civ.pending_bunkers.clear()


## 降维期间、只剩星舰时不能建造（派战舰、殖民船、二向箔，升级）。
func _check_build(civ: Civ) -> String:
	if civ.reduce_left > 0:
		return "降维期间不能建造"
	if civ.colonies.is_empty():
		return "没有星系，不能建造"
	return ""


func _check_action(civ: Civ, direction: Vector3, origin: Vector3i, energy_cost: int,
		mineral_cost: int = 0) -> String:
	if is_over():
		return "游戏已结束"
	if not civ.alive:
		return "文明已灭亡"
	if not civ.owns(origin) and not (civ.has_starship and origin == civ.starship):
		return "发射源必须是自己的星系或星舰"
	if direction.length() < 1e-6:
		return "需要指定方向"
	if civ.actions_left <= 0:
		return "行动点不足"
	if civ.energy < energy_cost:
		return "能量不足"
	if civ.mineral < mineral_cost:
		return "矿石不足"
	return ""


## 星系少一颗恒星。恒星没了，星系就丢了；星系全丢了，文明灭亡。
## 掩体（按原著的掩体计划）：光粒照样打爆恒星，但躲在类木行星背后的人活下来，
## 最后一颗恒星没了，这个星系也不会丢（变成没有恒星的星系）。没有恒星的星系再被光粒打中，
## 没有东西可毁；被战舰打中，星系就丢了。
func _lose_star(c: Vector3i, owner: Civ, attacker: Civ, weapon: String) -> void:
	var lightgrain := weapon.ends_with("光粒")
	if map.star_at(c) == StarMap.Star.NONE:
		if lightgrain:
			if owner == human():
				add_log("%s打中 %s，这里的恒星已经没了，躲在掩体里的人没事" % [weapon, c])
			return
		if owner == human() or attacker == human():
			add_log("没有恒星的星系 %s 被%s摧毁" % [c, weapon])
		_lose_system(c, owner)
		return
	var left := map.star_at(c) - 1
	map.stars[c] = left
	if owner == human():
		add_log("你的星系 %s 被%s击中，剩 %d 颗恒星" % [c, weapon, left])
	# 恒星少了，多出来的戴森球也没了
	if owner.dysons.get(c, 0) > left:
		owner.dysons[c] = left
		if owner == human():
			add_log("你在 %s 失去一个戴森球" % c)
	if left > StarMap.Star.NONE:
		return
	if lightgrain and owner.bunkers.has(c):
		if owner == human() or attacker == human():
			add_log("星系 %s 的恒星全部熄灭，但有人躲在类木行星背后的掩体里活了下来" % c)
		return
	if attacker != null:
		attacker.known.erase(c)
	if owner == human() or attacker == human():
		add_log("星系 %s 的恒星全部熄灭" % c)
	_lose_system(c, owner)


## 文明失去一个星系。星系全丢了，文明灭亡。
func _lose_system(c: Vector3i, owner: Civ) -> void:
	owner.colonies.erase(c)
	owner.dysons.erase(c)
	owner.miners.erase(c)
	owner.bunkers.erase(c)
	if owner.colonies.is_empty():
		owner.starship_building = false
		if owner.has_starship:
			owner.home = owner.starship
			add_log("%s 失去了所有星系，只剩星舰" % owner.name)
		else:
			_die(owner)
	elif owner.home == c:
		owner.home = owner.colonies[0]


## 文明灭亡，准备中和在飞的东西也随之消失。
func _die(owner: Civ) -> void:
	owner.alive = false
	owner.has_starship = false
	owner.starship_building = false
	owner.warships.clear()
	owner.colony_ships.clear()
	owner.foils.clear()
	owner.pending_domains.clear()
	owner.pending_broadcasts.clear()
	add_log("%s 灭亡" % owner.name)
	_check_winner()


## 文明失去星舰。只剩星舰的文明随之灭亡。
func _lose_starship(owner: Civ, cause: String) -> void:
	owner.has_starship = false
	if owner == human():
		add_log("你的星舰被%s毁掉" % cause)
	if owner.colonies.is_empty():
		_die(owner)


## 每有文明灭亡就重新判断一次。二向箔可能让好几个文明同时灭亡，
## 所以已经分出胜负后还会再改（例如你灭亡后，剩下的 AI 也被压平，就变成「无」）。
func _check_winner() -> void:
	var alive := civs.filter(func(c): return c.alive)
	var result := ""
	# 暂定：整张星图都压平后，还活着的文明（都已降维）之间没法再分出胜负，算平局
	if all_flat() and alive.size() >= 2:
		result = "平局"
	elif spectator:
		if alive.size() <= 1:
			result = alive[0].name if alive.size() == 1 else "无"
	elif alive.is_empty():
		result = "无"
	elif not human().alive:
		result = "AI"
	elif alive.size() == 1:
		result = "你"
	if result == "" or result == winner:
		return
	winner = result
	match result:
		"你": add_log("你胜利了")
		"AI": add_log("你失败了")
		"无": add_log("所有文明都灭亡了")
		"平局": add_log("整张星图都被压平，还剩 %d 个文明，平局" % alive.size())


# ---------- 简单 AI ----------

## 二向箔压平的区域靠近自己时，先降维（能量不够就攒着）。
## 能量攒到 AI_FOIL_ENERGY 以上、又有已知目标时，先降维，再发射二向箔。
## 射程内有已知目标：没有恒星广播器就先建（建造中先做别的），有了以后能量够就发光粒，不够就攒着。
## 已知目标都在射程外：派一艘战舰过去（同时最多一艘）；已经有战舰在路上，就广播它的坐标（每个坐标一次）。
## 没有能打的目标：先造预警系统，被打中过就在母星投放黑域（躲起来）、再建一艘星舰（留条后路），再派殖民船（同时最多一艘），再建采矿船（每回合最多一艘），再建戴森球（每回合最多一个），再造一个反物质（没有时），再升级探测器、望远镜，
## 然后随机方向探测。
func _ai_turn(ai: Civ) -> void:
	if _flat_near(ai) and not ai.reduced and ai.reduce_left == 0:
		if start_reduce(ai)["error"] != "":
			return  # 能量不够降维，先攒着，什么都不做
	if ai.starship_only():
		_ai_starship_turn(ai)
		return
	var built_miner := false  # 采矿船也是每回合最多一艘
	var built_dyson := false  # 每回合最多建一个戴森球，免得把行动点全花在上面、不去探测
	while ai.actions_left > 0 and ai.alive and not is_over():
		if _try_foil(ai):
			continue
		var r: Dictionary
		var pair := _nearest_pair(ai, ai.strike_range)
		var far := _nearest_pair(ai, INF)
		if not pair.is_empty() and ai.has_broadcaster:
			if ai.energy < Balance.COST_LIGHTGRAIN:
				return
			r = lightgrain(ai, Vector3(pair[1] - pair[0]), pair[0])
		elif not pair.is_empty() and not ai.pending_upgrades.has("broadcaster"):
			r = upgrade(ai, "broadcaster")
		elif not far.is_empty() and ai.warships.is_empty() \
				and launch_warship(ai, Vector3(far[1] - far[0]), far[0])["error"] == "":
			continue
		elif not far.is_empty() and not ai.broadcasted.has(far[1]) \
				and broadcast(ai, far[1])["error"] == "":
			continue
		elif upgrade(ai, "warning")["error"] == "":
			continue
		elif _try_domain(ai):
			continue
		elif ai.times_hit > 0 and _try_bunker(ai):
			continue
		elif ai.times_hit > 0 and build_starship(ai, ai.home)["error"] == "":
			continue
		elif ai.colony_ships.is_empty() and _try_colonize(ai):
			continue
		elif not built_miner and _try_miner(ai):
			built_miner = true
			continue
		elif not built_dyson and _try_dyson(ai):
			built_dyson = true
			continue
		elif ai.antimatter == 0 and upgrade(ai, "antimatter")["error"] == "":
			continue
		elif upgrade(ai, "probe")["error"] == "":
			continue
		elif upgrade(ai, "telescope")["error"] == "":
			continue
		elif ai.energy >= Balance.COST_SCOUT:
			r = scout(ai, _random_direction(), ai.home)
		else:
			return
		if r["error"] != "":
			return  # 出错时不会消耗行动点，必须停下，否则会一直重试


## 距离不超过 max_d 时，自己的星系和已知目标中距离最近的一对：[发射源, 目标]。
## skip_flat 为 true 时跳过已经压平的目标。没有符合的目标时返回空数组。
func _nearest_pair(ai: Civ, max_d: float, skip_flat := false) -> Array[Vector3i]:
	var best: Array[Vector3i] = []
	var best_d := max_d
	for t in ai.known:
		if skip_flat and flattened.has(t):
			continue
		for o in ai.colonies:
			var d := Vector3(t - o).length()
			if d <= best_d and not blocked(o, t):
				best_d = d
				best = [o, t]
	return best


## 能量攒到 AI_FOIL_ENERGY 以上、又有已知目标时，先降维，降维完成后朝最近的已知目标发射二向箔
## （同时最多一片）。降维或发射成功返回 true。
func _try_foil(ai: Civ) -> bool:
	if not ai.foils.is_empty() or ai.reduce_left > 0:
		return false
	var far := _nearest_pair(ai, INF, true)
	if far.is_empty():
		return false
	if not ai.reduced:
		if ai.energy < maxi(Balance.AI_FOIL_ENERGY, ai.reduce_cost() + Balance.COST_FOIL):
			return false
		return start_reduce(ai)["error"] == ""
	return launch_foil(ai, far[1], far[0])["error"] == ""


## 只剩星舰的 AI：停在能殖民的星系上就建立星系；否则朝最近的、没去过的宜居星系移动。
func _ai_starship_turn(ai: Civ) -> void:
	while ai.actions_left > 0 and ai.alive and not is_over():
		if can_settle(ai.starship):
			settle_starship(ai)
			return
		var best := NO_HIT
		var best_d := INF
		for t in map.habitable:
			if ai.known.has(t) or ai.colony_tried.has(t) or map.star_at(t) == StarMap.Star.NONE:
				continue
			var d := Vector3(t - ai.starship).length()
			if d < best_d:
				best_d = d
				best = t
		if best == NO_HIT or ai.energy < Balance.COST_STARSHIP_MOVE:
			return
		# 不要飞过头：最多飞到目标那里
		if move_starship(ai, Vector3(best - ai.starship), best_d)["error"] != "":
			# 走不过去（被别人占了、或被黑域挡住），下次换一个
			ai.colony_tried[best] = true
			return


## 被打中过、母星还没有黑域（也没在准备）时，以母星为中心投放黑域。投放成功返回 true。
func _try_domain(ai: Civ) -> bool:
	if ai.times_hit == 0 or in_black_domain(ai.home) or not ai.pending_domains.is_empty():
		return false
	return launch_black_domain(ai, ai.home)["error"] == ""


## 在第一个能建掩体的星系上建掩体。建成返回 true。
func _try_bunker(ai: Civ) -> bool:
	for c in ai.colonies:
		if map.gas.get(c, 0) > 0 and build_bunker(ai, c)["error"] == "":
			return true
	return false


## 在第一个还没有采矿船的星系上建采矿船。建成返回 true。
func _try_miner(ai: Civ) -> bool:
	for c in ai.colonies:
		if build_miner(ai, c)["error"] == "":
			return true
	return false


## 在第一个还有空位的星系上建戴森球。建成返回 true。
func _try_dyson(ai: Civ) -> bool:
	for c in ai.colonies:
		if build_dyson(ai, c)["error"] == "":
			return true
	return false


## 压平的区域再过不超过 AI_REDUCE_ALERT 回合就会压到这个文明的某个星系。
func _flat_near(ai: Civ) -> bool:
	for c in ai.colonies:
		if turns_until_flat(c) <= Balance.AI_REDUCE_ALERT:
			return true
	return false


## 朝最近的宜居星系派殖民船。AI 只用自己知道的信息：
## 排除自己的星系和已知的敌人坐标，不知道别人占了哪里。派出成功返回 true。
func _try_colonize(ai: Civ) -> bool:
	var best: Array[Vector3i] = []
	var best_d := INF
	for t in map.habitable:
		if ai.owns(t) or ai.known.has(t) or ai.colony_tried.has(t) or map.star_at(t) == StarMap.Star.NONE:
			continue
		for o in ai.colonies:
			var d := Vector3(t - o).length()
			if d < best_d and not blocked(o, t):
				best_d = d
				best = [o, t]
	if best.is_empty():
		return false
	if launch_colony_ship(ai, Vector3(best[1] - best[0]), best[0])["error"] != "":
		return false
	ai.colony_tried[best[1]] = true
	return true


func _random_direction() -> Vector3:
	var d := Vector3.ZERO
	while d.length() < 0.1:
		d = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return d


func add_log(line: String) -> void:
	log_lines.append(line)
