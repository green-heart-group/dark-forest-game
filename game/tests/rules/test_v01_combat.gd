extends "res://tests/rules/rule_suite.gd"


func _armed(s: GameState, civ: Civ, pos: Vector3, weapons: Array) -> Ship:
	var ship := _ship(s, civ, Ship.WARSHIP, pos)
	ship.weapons.assign(weapons)
	ship.modules.assign(weapons)
	return ship


func _local_contacts(s: GameState) -> void:
	for civ in s.civs:
		for ship in civ.ships:
			for target in Combat.targets(s):
				if target["owner"] != s.civs.find(civ):
					ship.local_contacts[target["id"]] = {"id": target["id"], "owner": target["owner"],
							"kind": target["kind"], "hp": target["hp"], "pos": target["pos"], "velocity": target["velocity"]}


## 规则：交战
func test_v01_single_channel_and_start_stock_reservation() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var a := _armed(s, me, Vector3.ZERO, ["beam", "torpedo", "hbomb"])
	_armed(s, s.civs[1], Vector3(0.1, 0, 0), [])
	_local_contacts(s)
	me.energy = 2.0
	me.mineral = 0.0
	Combat.reserve_round(s)
	check_eq([me.energy, me.mineral, a.ammo_reserved], [0.0, 0.0, [2000, 0]], "年初仅预留负担得起的束流弹药")
	Combat.fire_ready(s)
	Combat.fire_ready(s)
	check_eq(s.projectiles.size(), 1, "三个模块不会同年齐射，也不能重复开火")
	check_eq(a.ammo_reserved, [0, 0], "发射消耗预留，不重复扣可用库存")
	var other := _armed(s, me, Vector3.ZERO, ["beam"])
	_local_contacts(s)
	me.energy = 100.0
	Combat.fire_ready(s)
	check(other.fired_turn < 0, "年中获得收入不能给未预留的舰船补开本年射击")


## 规则：交战
func test_v01_simultaneous_hits_and_unique_salvage() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var a := _armed(s, s.human(), Vector3.ZERO, ["beam"])
	var b := _armed(s, s.civs[1], Vector3(0.1, 0, 0), ["beam"])
	_local_contacts(s)
	Combat.reserve_round(s)
	Combat.fire_ready(s)
	var targets := Combat.targets(s)
	var hits: Array[Dictionary] = []
	for shot in s.projectiles:
		for target in targets:
			if target["owner"] != shot["owner"]:
				hits.append({"kind": "hit", "shot": shot, "target": target})
	Combat.resolve(s, hits)
	check(a.dead and b.dead, "同刻已发弹丸均生效，不由文明数组先后决定谁能还击")
	check_eq(s.applied_hits.size(), 2, "每个命中ID只提交一次")
	Combat.resolve(s, hits)
	check_eq([a.damage, b.damage], [2, 2], "重复投递同一命中不会重复损伤")
	var victim := _armed(s, s.civs[1], Vector3(0.1, 0, 0), [])
	victim.cost = [0.75, 6.75]
	var target: Dictionary = Combat.targets(s).filter(func(x): return x["id"] == victim.id)[0]
	var stock := [s.human().energy, s.human().mineral]
	var double: Array[Dictionary] = []
	for i in 2:
		double.append({"kind": "hit", "target": target, "shot": {"id": s.next_id(), "owner": 0, "weapon": "hbomb", "dead": false}})
	Combat.resolve(s, double)
	check_eq([s.human().energy, s.human().mineral], [stock[0]+0.75, stock[1]+6.75], "同刻两枚氢弹只回收一次、按已折损实付账")
	check(victim.salvage_claimed, "目标保留永久已回收标记")


## 规则：交战
func test_v01_hp_modules_and_defense_repeatability() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ship := _armed(s, s.human(), Vector3.ZERO, [])
	ship.damage = 1
	ship.modules.assign(["shield", "alloy"])
	check_eq([ship.max_hp(), ship.max_hp()-ship.damage], [5, 4], "装甲力场取最大HP并保留绝对损伤")
	var target: Dictionary = Combat.targets(s)[0]
	var first: Array[int] = []
	for shot in 100:
		first.append(Combat.damage(s, "beam", shot, target))
	for shot in range(99, -1, -1):
		check_eq(Combat.damage(s, "beam", shot, target), first[shot], "防御抽样不随遍历顺序变化")
	check_eq(Combat.damage(s, "hbomb", 3, target), 4, "力场装甲不能豁免人员致死")
	check(not Combat.legal("hbomb", Ship.DROPLET) and not Combat.legal("hbomb", Ship.PROBE), "氢弹不打无人实体")
	check(Combat.legal("torpedo", Ship.PROBE) and Combat.legal("beam", "miner"), "普通经济单位的受击范围明确")


## 规则：交战
func test_v01_repair_is_per_ship() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var quiet := _armed(s, s.human(), Vector3.ZERO, [])
	var fighting := _armed(s, s.human(), Vector3.ZERO, [])
	quiet.modules.append("shield")
	fighting.modules.append("shield")
	quiet.damage = 2
	fighting.damage = 2
	quiet.last_hit = 0.0
	fighting.last_hit = 4.0
	s.clock = 5.0
	Combat.repair(s)
	check_eq([quiet.damage, fighting.damage], [1, 2], "其他舰作战不重置未参战舰的脱战修复")
	Combat.repair(s)
	check_eq(quiet.damage, 1, "同一时刻不能重复修复")
