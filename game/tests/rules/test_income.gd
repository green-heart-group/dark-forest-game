extends "res://tests/rules/rule_suite.gd"
## 收入、行动点和回合结束。


## 规则：每回合的收入
func test_action_points_follow_home_stars_and_colonies() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	check(me.action_points(s.map) == 5, "单星母星系 6 − 1 = 5 个行动点")
	_set_star(s, Vector3i.ZERO, StarMap.Star.TRIPLE)
	check(me.action_points(s.map) == 3, "三星母星系 3 个行动点")
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.TRIPLE)
	me.colonies.append(Vector3i(1, 0, 0))
	check(me.action_points(s.map) == 4, "每多一个殖民地 +1，殖民地的恒星数不影响")


## 规则：每回合的收入
func test_income_from_fission_dysons_and_miners() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 3
	var base := Balance.ENERGY_PER_SYSTEM + Balance.ENERGY_PER_STAR
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY, "每颗类地行星给裂变能")
	me.dysons[Vector3i.ZERO] = 1
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY + Balance.DYSON_ENERGY, "戴森球 +6E")
	s.map.stars[Vector3i.ZERO] = StarMap.Star.NONE
	check(s.energy_income(me) == Balance.ENERGY_PER_SYSTEM + 3 * Balance.FISSION_ENERGY, "没有恒星的星系没有戴森球和恒星的产能")
	check(s.mineral_income(me) == Balance.MINERAL_PER_COLONY, "每个星系的矿石")
	me.miners[Vector3i.ZERO] = 3
	check(s.mineral_income(me) == Balance.MINERAL_PER_COLONY + 3 * Balance.MINER_MINERAL, "每艘采矿船多产矿石")


## 规则：每回合的收入，一个回合里发生什么
func test_end_turn_pays_income() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 2
	var e := me.energy
	var m := me.mineral
	me.actions_left = 0
	s.end_turn()
	check(me.energy == e + s.energy_income(me) and me.mineral == m + s.mineral_income(me), "回合结束发放收入")
	check(me.actions_left == me.action_points(s.map), "行动点恢复")
	check(s.turn == 2, "进入下一回合")
