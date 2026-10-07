extends "res://tests/rules/rule_suite.gd"
## 交战：战舰相撞、战舰的武器、战舰打星系和殖民船、反物质。


## 规则：交战
func test_warships_destroy_each_other() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(s, ai, Ship.WARSHIP, Vector3(3.8, 0, 0), Vector3(-1, 0, 0))
	s._combat()
	check(me.ships.is_empty() and ai.ships.is_empty(), "两艘战舰一起毁掉")


## 规则：交战，T23
func test_warships_carry_researched_weapons() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	_give(me, ["warship"])
	var plain := s.build_cost(me, "warship")
	_give(me, ["beam", "torpedo"])
	var armed := s.build_cost(me, "warship")
	check(armed[0] == plain[0] + Balance.COST_BEAM_EXTRA[0] + Balance.COST_TORPEDO_EXTRA[0]
			and armed[1] == plain[1] + Balance.COST_BEAM_EXTRA[1] + Balance.COST_TORPEDO_EXTRA[1], "每带一种武器多花一份钱")
	var ship: Ship = s.build(me, "warship")["ship"]
	check(ship.weapons == ["beam", "torpedo"] and ship.cost == armed, "之后造的战舰带上升级过的武器，记下花了多少")


## 规则：交战，T23
func test_beam_destroys_warship_out_of_collision_range() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam", "torpedo"]
	var theirs := _ship(s, ai, Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	var energy := me.energy
	s._combat()
	check(theirs.dead and not mine.dead, "高能粒子束（射程 1.5）先打掉对方，自己留下")
	check(me.energy == energy - Balance.BEAM_SHOT[0], "开火花能量")


## 规则：交战，T23
func test_torpedo_needs_two_hits() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam", "torpedo"]
	var theirs := _ship(s, ai, Ship.WARSHIP, Vector3(4.9, 0, 0), Vector3(1, 0, 0))
	var mineral := me.mineral
	s._combat()
	check(not theirs.dead and theirs.damage == 1, "1.9 格只有鱼雷够得着，打中一次不毁")
	check(me.mineral == mineral - Balance.TORPEDO_SHOT[1], "鱼雷花矿石")
	s._combat()
	check(theirs.dead, "打中 %d 次毁掉" % Balance.TORPEDO_HITS)


## 规则：交战，T23
func test_hbomb_first_and_salvages_cost() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["hbomb", "beam", "torpedo"]
	var theirs := _ship(s, ai, Ship.WARSHIP, Vector3(3.8, 0, 0), Vector3(-1, 0, 0))
	theirs.cost = [12, 10]
	var energy := me.energy
	var mineral := me.mineral
	s._combat()
	check(theirs.dead and not mine.dead, "次声波氢弹优先，打掉对方以后不再相撞")
	check(me.energy == energy - Balance.HBOMB_SHOT[0] + 12 and me.mineral == mineral - Balance.HBOMB_SHOT[1] + 10,
			"收回对方造船花的资源")


## 规则：交战，T23
func test_armed_warships_fire_at_the_same_time() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var a := _ship(s, s.human(), Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	var b := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	a.weapons = ["beam"]
	b.weapons = ["beam"]
	s._combat()
	check(a.dead and b.dead, "两边同时开火，一起毁掉")


## 规则：交战，T23
func test_weapon_needs_ammo_money() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam"]
	var theirs := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	me.energy = 0
	s._combat()
	check(not theirs.dead, "能量不够就不开火")


## 规则：交战，反物质
func test_warship_wipes_system_without_antimatter() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	var w := _ship(s, me, Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	ai.antimatter = 1
	s._combat()
	check(ai.alive, "有反物质的星系，战舰打不了")
	ai.actions_left = 1
	check(s.use_antimatter(ai)["error"] == "", "下令用反物质")
	check(w.dead and ai.antimatter == 0, "战舰消失，反物质用掉")
	s._clean_dead()
	var w2 := _ship(s, me, Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	s._combat()
	check(not ai.alive and s.winner == "你", "没有反物质，战舰抹掉那里的文明")
	check(not w2.dead, "战舰打完星系还在")


## 规则：交战
func test_warship_hits_colony_ship_first() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	var c := _ship(s, ai, Ship.COLONY, Vector3(4.5, 0.5, 0), Vector3(0, 1, 0))
	s._combat()
	check(c.dead and ai.alive, "每回合只打一个目标，先打殖民船")
