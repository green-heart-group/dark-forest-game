extends "res://tests/rules/rule_suite.gd"
## 收入、行动点和回合结束。


## 规则：每回合的收入
func test_action_points_are_fixed_across_stars_and_colonies() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	check_eq(me.action_points(s.map),3,"单星母星每年3行动点")
	_set_star(s, Vector3i.ZERO, StarMap.Star.TRIPLE)
	check_eq(me.action_points(s.map),3,"三星母星仍为3行动点")
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.TRIPLE)
	me.colonies.append(Vector3i(1, 0, 0))
	check_eq(me.action_points(s.map),3,"殖民数不增加行动点")
	me.actions_left=1
	s.start_turn(me)
	check_eq(me.actions_left,3,"剩余行动点不跨年累积")


## 规则：每回合的收入
func test_income_from_fission_dysons_and_miners() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 3
	var base := Balance.ENERGY_PER_SYSTEM + Balance.ENERGY_PER_STAR
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY, "每颗类地行星给裂变能")
	me.dysons[Vector3i.ZERO] = 1
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY + Balance.DYSON_ENERGY, "戴森产出来自恒星")
	s.map.stars[Vector3i.ZERO] = StarMap.Star.NONE
	check(s.energy_income(me) == Balance.ENERGY_PER_SYSTEM + 3 * Balance.FISSION_ENERGY, "没有恒星的星系没有戴森球和恒星的产能")
	check_eq(s.mineral_income(me),-Construction.upkeep("dyson")[1],"未关闭的戴森维护仍扣固定矿石，不凭空给星系产矿")
	me.miners[Vector3i.ZERO] = 3
	check_eq(s.mineral_income(me),3*Balance.MINER_MINERAL-Construction.upkeep("dyson")[1],"矿船毛产出扣固定维护")


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
