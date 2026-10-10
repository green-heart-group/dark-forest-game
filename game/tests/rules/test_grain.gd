extends "res://tests/rules/rule_suite.gd"
## 光粒和掩体。


## 规则：光粒，建造
func test_grain_build_then_launch_flies_and_wipes_system() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var third:=Civ.new("旁观文明",false,Vector3i(8,8,8))
	s.civs.append(third)
	_set_star(s,third.home,StarMap.Star.SINGLE)
	s.start_turn(third)
	var me := s.human()
	check(s.build(me, "grain")["error"] != "", "没有光粒投送科技不能造")
	_give(me, ["grain"])
	var m := me.mineral
	check(s.build(me, "grain")["error"] == "" and me.grains.is_empty(), "光粒提交6W工程，不立即获得弹药")
	check(me.mineral == m - Balance.COST_GRAIN[1], "造光粒花矿石")
	check(s.build(me, "grain")["error"] != "", "每个星系最多存 1 颗")
	_turns(s,6)
	check(me.grains.has(me.home),"完工后收到光粒库存")
	var e := me.energy
	check(s.launch_grain(me, Vector3(1, 0, 0))["error"] == "", "发射光粒")
	check(me.energy == e - Balance.COST_GRAIN_LAUNCH and me.grains.is_empty(), "发射花能量，光粒用掉")
	_turns(s, 2)
	check(s.civs[1].alive, "2年飞1.98ly，还没进入3ly目标的.25ly碰撞半径")
	s.end_turn()
	check(not s.civs[1].alive and not s.is_over(), "第3年打中；仍有两个文明故继续")
	check(s.map.star_at(Vector3i(3, 0, 0)) == StarMap.Star.NONE, "毁掉 1 颗恒星")
	check(not me.record_hits.has(Vector3i(3,0,0)),"真实命中不能瞬间写远端战报")
	_turns(s,3)
	check(me.record_hits.has(Vector3i(3,0,0)) and not me.battle_reports.is_empty(),"3ly战报回传后保留原敌情标记功能")


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


## 规则：光粒
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
func test_grain_still_hits_converted_entity() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	s.civs[1].reduced = true
	Assets.ensure(s,s.civs[1])
	for asset in s.civs[1].assets:
		asset["entity_dim"] = 2
	check_eq(s.civs[1].assets[0]["entity_dim"],2,"夹具明确采用已转换实体")
	var g := _ship(s, s.human(), Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 3)
	check(not s.civs[1].alive and s.map.star_at(Vector3i(2, 0, 0)) == StarMap.Star.NONE, "转换不产生额外光粒免疫")


## 只有一个星系、星舰停在那里：光粒打中后星系和星舰都没了，文明要灭亡，不能「只剩星舰」地活着。
## 规则：光粒，灭亡和胜负
func test_grain_kills_parked_starship_and_civ() -> void:
	var s := _three_civs()
	var ai := s.civs[1]
	_ship(s, ai, Ship.STARSHIP, Vector3(8, 8, 8))
	_ship(s, s.human(), Ship.GRAIN, Vector3(6, 8, 8), Vector3(1, 0, 0))
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
