extends "res://tests/rules/rule_suite.gd"
## 建造：要什么科技、数量上限、什么时候建好、派出。


## 规则：建造
func test_build_needs_tech_and_respects_limits() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.energy = 1000
	me.mineral = 1000
	me.actions_left = 20
	check(s.build(me, "warship")["error"] != "", "没有科技不能造战舰")
	_give(me, ["warship", "colony"])
	for i in Balance.MAX_WARSHIPS:
		check(s.build(me, "warship")["error"] == "", "造第 %d 艘战舰" % (i + 1))
	check(s.build(me, "warship")["error"] != "", "战舰最多 %d 艘" % Balance.MAX_WARSHIPS)
	for i in Balance.MAX_COLONY_SHIPS:
		s.build(me, "colony")
	check(s.build(me, "colony")["error"] != "", "殖民船最多 %d 艘" % Balance.MAX_COLONY_SHIPS)
	check(s.build(me, "probe", Vector3i(5, 5, 5))["error"] != "", "只能建在自己的星系")


## 规则：建造，调度（派出和行动）
func test_units_built_docked_then_dispatched() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ap := me.actions_left
	var m := me.mineral
	var p := s.build(me, "probe")["ship"] as Ship
	check(p != null and p.docked and me.actions_left == ap - 1, "造探测器花 1 行动点，造好停在星系里")
	check(me.mineral == m - Balance.COST_PROBE[1], "探测器花矿石")
	s.end_turn()
	check(p.pos == Vector3.ZERO, "没派出就不动")
	check(s.dispatch(me, p.id, Vector3.ZERO)["error"] != "", "派出要方向")
	ap = me.actions_left
	check(s.dispatch(me, p.id, Vector3(0, 0, 1))["error"] == "", "派出")
	check(me.actions_left == ap - 1, "派出花 1 行动点")
	check(s.dispatch(me, p.id, Vector3(0, 0, 1))["error"] != "", "已经派出的不能再派")
	s.end_turn()
	check(absf(p.pos.z - Balance.PROBE_MOVE[1]) < 1e-6, "第一回合飞的距离等于加速度")


## 规则：建造，F3.5
func test_facilities_next_turn_and_dyson_cap() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	_give(me, ["dyson"])
	me.actions_left = 99
	me.mineral = 1000
	for i in Balance.MAX_MINERS:
		check(s.build(me, "miner")["error"] == "", "可以建采矿船")
	check(s.build(me, "miner")["error"] != "", "每个星系的采矿船有上限")
	check(s.build(me, "dyson")["error"] == "", "可以建戴森球")
	check(s.build(me, "dyson")["error"] != "", "戴森球不能比恒星多")
	check(me.miners.is_empty() and me.dysons.is_empty(), "下一回合才建好")
	s.end_turn()
	check(me.miners.get(Vector3i.ZERO, 0) == Balance.MAX_MINERS and me.dysons.get(Vector3i.ZERO, 0) == 1, "建好了")
	check(s.build(me, "miner")["error"] != "", "建好以后也不能超过上限")
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.DOUBLE)
	me.colonies.append(Vector3i(1, 0, 0))
	check(s.build(me, "dyson", Vector3i.ZERO)["error"] == "", "上限按所有星系的恒星总数，可以都建在母星系")


## 预警系统是整个文明的：下单的星系在建好前丢了，换个星系照样建好。
## 规则：预警系统，建造
func test_warning_built_after_its_system_falls() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var other := Vector3i(0, 3, 0)
	_set_star(s, other, StarMap.Star.SINGLE)
	me.colonies.append(other)
	me.pending.append({"kind": "warning", "at": other})
	s._lose_system(other, me)
	s._finish_pending(me)
	check(me.has_warning, "预警系统照样建好")
