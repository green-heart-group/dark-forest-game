extends "res://tests/rules/rule_suite.gd"


## 规则：交战，灭亡和胜负
func test_v01_suppression_requires_three_maintained_years() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	var warship := _ship(s, me, Ship.WARSHIP, Vector3(0.9, 0, 0))
	warship.weapons = ["beam"]
	WorldTime.advance(s, 2.9)
	check(s.civs[1].owns(Vector3i(1, 0, 0)), "近旁有武装舰不立即删除殖民地")
	WorldTime.advance(s, 0.1)
	check(not s.civs[1].owns(Vector3i(1, 0, 0)), "连续三年后清除归属")
	check(not me.owns(Vector3i(1, 0, 0)), "压制不是免费殖民")
	check_eq(s.winner, "你", "最后生存锚点被压制后合法结束")
	var hit := s.events.filter(func(event): return event["kind"] == "suppression_complete")
	check(hit.size() == 1 and absf(hit[0]["t"] - 3.0) < 0.00001, "事件发生在连续三年边界")


## 规则：交战
func test_v01_suppression_break_resets_and_defender_blocks() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var ship := _ship(s, s.human(), Ship.WARSHIP, Vector3(0.9, 0, 0))
	ship.weapons = ["beam"]
	WorldTime.advance(s, 1.0)
	check(absf(ship.suppression.get("progress", 0) - 1.0) < 0.00001, "第一年进度可追踪")
	var defender := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(1.4, 0, 0))
	defender.weapons = ["railgun"]
	WorldTime.advance(s, 0.1)
	check(ship.suppression.is_empty(), ".5ly内敌方武装舰令连续进度清零")
	defender.dead = true
	WorldTime.advance(s, 2.9)
	check(not s.is_over(), "重新压制需完整三年，不能累计中断前时间")


## 规则：交战，每回合的收入
func test_v01_unaffordable_suppression_dormant_not_debt() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3(0.9, 0, 0))
	ship.weapons = ["railgun"]
	me.energy = 0
	me.mineral = 0
	WorldTime.advance(s, 1.0)
	check(ship.suppression.is_empty(), "库存无法维持时不免费推进压制")
	check(me.energy >= 0 and me.mineral >= 0, "维护与压制的原子闭包不借贷")
	check(s.civs[1].alive, "没有支付真实维护就不能清除锚点")


## 规则：光粒，灭亡和胜负
func test_v01_simultaneous_grains_have_no_dimension_immunity() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s, civ)
		civ.grains[civ.home] = true
		civ.reduced = true
		Assets.at(civ, "anchor", civ.home)[0]["entity_dim"] = 2
	s.launch_grain(s.human(), Vector3.RIGHT)
	s.launch_grain(s.civs[1], Vector3.LEFT)
	WorldTime.advance(s, 1.0)
	check_eq(s.winner, "平局", "同刻双向光粒摧毁双方最后锚点，不能按先遍历者胜负")
	check_eq(s.map.star_at(Vector3i.ZERO) + s.map.star_at(Vector3i(1, 0, 0)), 0, "提前实体降维不免疫普通光粒")


## 规则：吞噬者
func test_v01_devour_is_unique_energy_not_recurring_minerals() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	var me := s.human()
	var at := Vector3i(2, 0, 0)
	s.map.rocky[at] = 2
	var ship := _ship(s, me, Ship.DEVOURER, Vector3(at))
	ship.entity_dim = 2
	var before := [me.energy, me.mineral]
	var recurring := s.energy_income(me)
	TacticalEvents.devour(s)
	check_eq([me.energy, me.mineral], [before[0] + 15, before[1]], "一次吞食25E×.6，不赠送旧版矿石")
	TacticalEvents.devour(s)
	check_eq(s.map.rocky[at], 1, "同年不会反复吞食")
	s.clock = 1
	s.turn = 2
	TacticalEvents.devour(s)
	check_eq(s.map.rocky[at], 0, "真实天体永久消耗")
	check_eq(s.energy_income(me), recurring, "吞食不伪装成经常收入抬高权限门槛；固定维护仍计入")
