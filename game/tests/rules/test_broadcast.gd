extends "res://tests/rules/rule_suite.gd"
## 广播和隐藏文明。


## 规则：广播和隐藏文明
func test_broadcast_spreads_at_light_speed() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	ai.broadcasters[ai.home] = true
	me.broadcasters[me.home] = true
	check(s.broadcast(ai, Vector3i(8, 8, 8))["error"] == "", "可以广播任何坐标")
	_turns(s, 4)
	check(not me.heard.has(Vector3i(8, 8, 8)), "4 回合后还没传到 5 格外")
	s.end_turn()
	check(me.heard.has(Vector3i(8, 8, 8)), "第 5 回合听到")
	check(me.discovered, "听到广播算发现别人")


## 规则：广播和隐藏文明
func test_hearing_needs_broadcaster() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	ai.broadcasters[ai.home] = true
	s.broadcast(ai, Vector3i(8, 8, 8))
	_turns(s, 3)
	check(not me.heard.has(Vector3i(8, 8, 8)), "没有恒星广播器听不到")


## 规则：广播和隐藏文明
func test_broadcast_reveals_owner_and_needs_source() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	check(s.broadcast(ai, Vector3i.ZERO)["error"] != "", "没有恒星广播器不能广播")
	_give(ai, ["gravity"])
	check(s.broadcast(ai, Vector3i(0, 0, 0))["error"] == "", "有引力波广播，所有星系都能广播")
	check(s.broadcast(ai, ai.home)["error"] != "", "不能广播自己的坐标")
	var third := Civ.new("第三方", false, Vector3i(0, 3, 0))
	third.broadcasters[third.home] = true
	s.civs.append(third)
	_set_star(s,third.home,StarMap.Star.SINGLE)
	third.energy=100
	third.mineral=100
	s.start_turn(third)
	_turns(s, 5)
	check(third.known.has(Vector3i.ZERO), "听到的人知道被广播的星系")


## 规则：广播和隐藏文明
func test_hidden_civ_strikes_after_hearing() -> void:
	Balance.HIDDEN_STRIKE_CHANCE = 1.0
	Balance.HIDDEN_FOIL_CHANCE = 0.0
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	s.hidden = [Vector3i(-1, 0, 0)]
	ai.broadcasters[ai.home] = true
	s.broadcast(ai, Vector3i.ZERO)
	_turns(s, 5)
	check(s.hidden_listen.is_empty() and s.hidden_ships.is_empty() and s.human().alive, "广播还没传到隐藏文明")
	_turns(s, 10)
	check(not s.human().alive, "隐藏文明听到后发光粒，从星图外飞过来")


## 没钱时广播失败：失败的操作不进对局记录，所以也不能动随机数，不然回放会走偏。
## 规则：广播和隐藏文明
func test_failed_broadcast_keeps_rng() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	me.broadcasters[me.home] = true
	me.energy = 0
	var before := s.rng.state
	check(s.broadcast(me, Vector3i(5, 0, 0))["error"] != "", "能量不够时不能广播")
	check(s.rng.state == before, "失败的广播不用随机数")


## 离星图好几格的隐藏文明：光粒第一回合还在星图外，不能当成「飞出星图」删掉。
## 规则：广播和隐藏文明
func test_hidden_grain_from_far_outside() -> void:
	Balance.HIDDEN_STRIKE_CHANCE = 1.0
	Balance.HIDDEN_FOIL_CHANCE = 0.0
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	s.hidden = [Vector3i(-3, 1, 0)]
	ai.broadcasters[ai.home] = true
	s.broadcast(ai, Vector3i.ZERO)
	_turns(s, 20)
	check(not s.human().alive, "离星图 3 格的隐藏文明发的光粒也能飞到")
