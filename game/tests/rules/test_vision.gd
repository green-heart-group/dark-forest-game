extends "res://tests/rules/rule_suite.gd"
## 视野、情报传回、航迹和预警。


## 规则：视野，情报传回
func test_home_vision_discovers_neighbour() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var me := s.human()
	s._observe(me)
	check(me.known.has(Vector3i(2, 0, 0)) and me.discovered, "母星系 2.0 格内的星系当回合看到，算发现别人")
	check(me.intel[Vector3i(2, 0, 0)]["owner"] == 1, "情报里记下是谁的星系")
	var far := _two_civs(Vector3i(3, 0, 0))
	far._observe(far.human())
	check(far.human().known.is_empty(), "3 格外看不到")
	for i in ceili((3.0 - Balance.VISION_HOME) / Balance.TELESCOPE_STEP):
		far.upgrade(far.human(), "telescope")
	far._observe(far.human())
	check(far.human().known.has(Vector3i(3, 0, 0)), "升级望远镜后看到")


## 规则：情报传回
func test_probe_report_travels_back_at_light_speed() -> void:
	var s := _two_civs(Vector3i(6, 0, 0))
	var me := s.human()
	_ship(s, me, Ship.PROBE, Vector3(5, 0, 0), Vector3(1, 0, 0))
	s._observe(me)
	check(me.known.is_empty() and not me.discovered, "探测器看到了，但情报还在路上")
	s.turn += 4
	s._deliver_reports(me)
	check(me.known.is_empty(), "4 回合后还没传回（5 格远）")
	s.turn += 1
	s._deliver_reports(me)
	check(me.known.has(Vector3i(6, 0, 0)) and me.discovered, "5 回合后传回母星系")
	check(me.known[Vector3i(6, 0, 0)] == s.turn - 5, "记的是看到的那一回合")


## 规则：移动，视野
func test_wakes_are_left_and_seen() -> void:
	var s := _two_civs(Vector3i(3, 2, 0))
	var me := s.human()
	var ai := s.civs[1]
	var p := _ship(s, me, Ship.PROBE, Vector3(3, 0, 0), Vector3(0, 1, 0))
	p.speed = 0.95
	s._move_ship(me, p)
	check(s.wakes.size() == 1, "近光速的探测器留下航迹")
	s._observe(ai)
	check(ai.wakes_seen.has(0), "航迹落进视野就看到")
	check(ai.sightings.size() == 1 and ai.sightings[0]["kind"] == Ship.PROBE, "也看到了探测器")


## 规则：预警系统
func test_warning_reports_enemy_warship() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.has_warning = true
	_ship(s, s.civs[1], Ship.WARSHIP, Vector3(1.8, 0, 0), Vector3(-1, 0, 0))
	_ship(s, s.civs[1], Ship.WARSHIP, Vector3(5, 0, 0), Vector3(-1, 0, 0))
	s._warn(me)
	check(me.alerts.size() == 1 and me.alerts[0]["kind"] == Ship.WARSHIP, "只报告预警范围里的敌方战舰")


## 规则：情报传回
func test_seeing_enemy_ship_counts_as_discovery() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_ship(s, s.civs[1], Ship.PROBE, Vector3(1, 0, 0), Vector3(1, 0, 0))
	s._observe(me)
	check(me.discovered and me.known.is_empty(), "母星系看到别人的探测器就算发现别人")
