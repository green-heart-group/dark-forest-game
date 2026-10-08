extends "res://tests/rules/rule_suite.gd"
## 殖民船、星舰、吞噬者、星际探测器。


## 规则：调度（派出和行动）
func test_colony_ship_settles_target() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["colony"])
	_set_habitable(s, Vector3i(1, 0, 0), StarMap.Star.DOUBLE)
	var c := s.build(me, "colony")["ship"] as Ship
	var e := me.energy
	check(s.send_colony(me, c.id, Vector3i(-1, 0, 0))["error"] != "", "目的地要在星图里")
	check(s.send_colony(me, c.id, Vector3i.ZERO)["error"] != "", "目的地不能是自己的星系")
	check(s.send_colony(me, c.id, Vector3i(1, 0, 0))["error"] == "", "选目的地派出")
	check(me.energy == e, "派殖民船不花能量")
	check(s.send_colony(me, c.id, Vector3i(2, 0, 0))["error"] != "", "在飞的殖民船不能改目的地")
	_turns(s, 6)
	check(me.colonies.size() == 1, "还没到（每回合 0.05 加速）")
	s.end_turn()
	check(me.colonies.has(Vector3i(1, 0, 0)) and me.count(Ship.COLONY) == 0, "到了建殖民地，殖民船用掉")


## F4.4：没看到过的格子也能当目的地；到了不能殖民就停在那里，可以再派。
## 规则：调度（派出和行动），F4.4
func test_colony_ship_blind_target() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["colony"])
	var c := s.build(me, "colony")["ship"] as Ship
	check(s.send_colony(me, c.id, Vector3i(1, 0, 0))["error"] == "", "空格子也能当目的地（盲飞）")
	_turns(s, 8)
	check(not c.dead and not c.docked and c.pos == Vector3(1, 0, 0) and c.direction == Vector3.ZERO,
			"到了不能殖民，停在原地")
	_set_habitable(s, Vector3i(2, 0, 0), StarMap.Star.SINGLE)
	check(s.send_colony(me, c.id, Vector3i(2, 0, 0))["error"] == "", "停着的殖民船可以再派")
	_turns(s, 8)
	check(me.colonies.has(Vector3i(2, 0, 0)), "到了新的目的地，建立殖民地")


## F4.4：宜居星系要看到过才知道；情报里记着宜居不宜居。
## 规则：星图和星系生成，F4.4
func test_known_habitable_needs_intel() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var far := Vector3i(6, 0, 0)
	_set_habitable(s, far, StarMap.Star.SINGLE)
	s.end_turn()
	check(not s.known_habitable(me).has(far), "没看到过的宜居星系不知道")
	me.intel[far] = s.snapshot(far)
	check(me.intel[far]["habitable"] and s.known_habitable(me).has(far), "看到过就知道它宜居")
	var near := Vector3i(1, 0, 0)
	_set_habitable(s, near, StarMap.Star.SINGLE)
	s.end_turn()
	check(s.known_habitable(me).has(near), "母星系视野里的宜居星系自动知道")


## 规则：调度（派出和行动）
func test_colony_ship_destroyed_by_enemy_system() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	_set_habitable(s, Vector3i(2, 0, 0), StarMap.Star.SINGLE)
	var c := _ship(s, me, Ship.COLONY, Vector3.ZERO)
	s.send_colony(me, c.id, Vector3i(2, 0, 0))
	_turns(s, 12)
	check(me.count(Ship.COLONY) == 0 and me.colonies.size() == 1, "路上经过别人的星系就被毁掉")


## 规则：星际探测器
func test_interstellar_probe_parks_and_jams_broadcaster() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	ai.broadcasters[ai.home] = true
	check(s.can_broadcast_from(ai, ai.home), "有恒星广播器可以广播")
	var p := _ship(s, me, Ship.PROBE, Vector3.ZERO, Vector3(1, 0, 0))
	p.interstellar = true
	p.accel = Balance.IPROBE_MOVE[1]
	_turns(s, 8)
	check(p.parked and p.pos == Vector3(2, 0, 0), "星际探测器飞到别人的星系时停下")
	check(not s.can_broadcast_from(ai, ai.home), "那个星系的恒星广播器不能用")


## 规则：调度（派出和行动）
func test_devourer_eats_rocky_planet() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.SINGLE)
	s.map.rocky[Vector3i(1, 0, 0)] = 2
	var d := _ship(s, me, Ship.DEVOURER, Vector3.ZERO, Vector3(1, 0, 0))
	var before := me.mineral
	for i in 9:
		s._move_ship(me, d)
	check(s.map.rocky[Vector3i(1, 0, 0)] == 1, "经过没人的星系，吃掉一颗类地行星")
	check(me.mineral == before + Balance.DEVOURER_MINERAL, "得到矿石")


## 规则：调度（派出和行动），灭亡和胜负
func test_starship_keeps_civ_alive_and_settles() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ss := _ship(s, me, Ship.STARSHIP, Vector3(2, 0, 0))
	ss.docked = false
	s._lose_system(Vector3i.ZERO, me)
	check(me.alive and me.starship_only() and me.home == Vector3i(2, 0, 0), "星系全丢了，靠星舰活着")
	check(s.build(me, "probe")["error"] != "", "只剩星舰不能建造")
	_set_habitable(s, Vector3i(3, 0, 0), StarMap.Star.SINGLE)
	check(s.settle_starship(me)["error"] != "", "不在宜居星系上不能建立星系")
	s.move_starship(me, Vector3i(3, 0, 0))
	_turns(s, 4)
	check(ss.pos == Vector3(3, 0, 0), "飞到宜居星系")
	check(s.settle_starship(me)["error"] == "", "建立星系")
	check(me.colonies == [Vector3i(3, 0, 0)] and not me.has_starship(), "星舰用掉，成为新的母星系")
