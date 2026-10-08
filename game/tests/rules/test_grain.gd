extends "res://tests/rules/rule_suite.gd"
## 光粒和掩体。


## 规则：光粒，建造
func test_grain_build_then_launch_flies_and_wipes_system() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	check(s.build(me, "grain")["error"] != "", "没有光粒投送科技不能造")
	_give(me, ["grain"])
	var m := me.mineral
	check(s.build(me, "grain")["error"] == "" and me.grains.has(Vector3i.ZERO), "造光粒，存在星系里")
	check(me.mineral == m - Balance.COST_GRAIN[1], "造光粒花矿石")
	check(s.build(me, "grain")["error"] != "", "每个星系最多存 1 颗")
	var e := me.energy
	check(s.launch_grain(me, Vector3(1, 0, 0))["error"] == "", "发射光粒")
	check(me.energy == e - Balance.COST_GRAIN_LAUNCH and me.grains.is_empty(), "发射花能量，光粒用掉")
	_turns(s, 3)
	check(s.civs[1].alive, "飞了 3 回合（0.5、1.5、2.5 格），还没到")
	s.end_turn()
	check(not s.civs[1].alive and s.winner == "你", "第 4 回合打中，抹掉那里的文明")
	check(s.map.star_at(Vector3i(3, 0, 0)) == StarMap.Star.NONE, "毁掉 1 颗恒星")
	check(me.record_hits.has(Vector3i(3, 0, 0)), "打中记在敌情记录图上")


## 规则：掩体，光粒
func test_grain_bunker_keeps_civ_and_costs_star_and_dyson() -> void:
	var target := Vector3i(2, 0, 0)
	var s := _two_civs(target)
	var ai := s.civs[1]
	_set_star(s, target, StarMap.Star.DOUBLE)
	ai.bunkers[target] = true
	ai.dysons[target] = 2
	var g := _ship(s, s.human(), Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 2)
	check(ai.alive and ai.owns(target), "有掩体，文明留下")
	check(s.map.star_at(target) == StarMap.Star.SINGLE and ai.dysons[target] == 1, "恒星和它的戴森球少一个")
	check(ai.hit_dirs.size() == 1 and ai.hit_dirs[0]["dir"].x < -0.9, "被打的一方知道打击从哪个方向来")


## 规则：光粒，T20
func test_grain_passes_starless_system() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var ai := s.civs[1]
	s.map.stars[Vector3i(2, 0, 0)] = StarMap.Star.NONE
	ai.colonies.append(Vector3i(3, 0, 0))
	_set_star(s, Vector3i(3, 0, 0), StarMap.Star.SINGLE)
	var g := _ship(s, s.human(), Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 3)
	check(ai.owns(Vector3i(2, 0, 0)), "没有恒星的星系打不中，光粒穿过去")
	check(not ai.owns(Vector3i(3, 0, 0)), "打中后面有恒星的星系")


## 规则：光粒，自身降维
func test_grain_no_effect_on_reduced() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	s.civs[1].reduced = true
	var g := _ship(s, s.human(), Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 3)
	check(s.civs[1].alive and s.map.star_at(Vector3i(2, 0, 0)) == StarMap.Star.SINGLE, "降维的文明不怕光粒")


## 只有一个星系、星舰停在那里：光粒打中后星系和星舰都没了，文明要灭亡，不能「只剩星舰」地活着。
## 规则：光粒，灭亡和胜负
func test_grain_kills_parked_starship_and_civ() -> void:
	var s := _three_civs()
	var ai := s.civs[1]
	_ship(s, ai, Ship.STARSHIP, Vector3(9, 9, 9))
	_ship(s, s.human(), Ship.GRAIN, Vector3(6, 9, 9), Vector3(1, 0, 0))
	_turns(s, 6)
	check(ai.colonies.is_empty() and not ai.has_starship(), "星系和停着的星舰都被毁掉")
	check(not ai.alive, "什么都不剩的文明灭亡")


## 文明灭亡前发出的光粒接着飞，照样能打中。
## 规则：灭亡和胜负
func test_grain_flies_on_after_owner_dies() -> void:
	var s := _three_civs()
	var ai := s.civs[1]
	_ship(s, ai, Ship.GRAIN, Vector3(3, 0, 0), Vector3(-1, 0, 0))
	s._die(ai)
	check(not s.is_over(), "还剩两个文明，对局继续")
	_turns(s, 6)
	check(not s.human().alive, "灭亡文明发出的光粒照样打中")
