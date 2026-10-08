extends "res://tests/rules/rule_suite.gd"
## 移动：加速、目的地、转向、慢速出发、曲率引擎。


## 规则：移动
func test_ship_accelerates_then_moves() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var w := _ship(s, me, Ship.WARSHIP, Vector3.ZERO, Vector3(1, 0, 0))
	var expect := [0.1, 0.3, 0.6, 1.0, 1.5, 2.1, 2.8, 3.6, 4.4]
	var ok := true
	for x in expect:
		s._move_ship(me, w)
		ok = ok and absf(w.pos.x - x) < 1e-4
	check(ok, "战舰先加速再移动：0.1、0.3、0.6……最高每回合 0.8")


## 规则：移动
func test_ship_with_target_snaps_onto_it() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["colony", "starship"])
	var ss := s.build(me, "starship")["ship"] as Ship
	check(ss != null and ss.docked, "星舰造好后停在星系里")
	check(s.move_starship(me, Vector3i(2, 0, 0))["error"] == "", "选目的地移动")
	for i in 5:
		s._move_ship(me, ss)
	check(ss.pos.x < 2.0, "还没到")
	s._move_ship(me, ss)
	check(ss.pos == Vector3(2, 0, 0) and ss.direction == Vector3.ZERO and ss.speed == 0.0, "到了就停在目的地上，不飞过头")


## 星舰的目的地：下令时只拦已知的敌方星系，不泄露别人悄悄占着哪里；飞到才发现，就停在旁边。
## 规则：调度（派出和行动）
func test_starship_target_does_not_reveal_owner() -> void:
	var enemy := Vector3i(5, 0, 0)
	var s := _two_civs(enemy)
	var me := s.human()
	_give(me, ["colony", "starship"])
	var ss := s.build(me, "starship")["ship"] as Ship
	check(s.starship_target_ok(me, enemy), "不知道那里有人时，可以选它当目的地")
	check(s.move_starship(me, enemy)["error"] == "", "下令不会因为那里有人而被拒绝")
	for i in 30:
		if ss.direction == Vector3.ZERO:
			break
		s._move_ship(me, ss)
	check(ss.pos == Vector3(4, 0, 0) and ss.direction == Vector3.ZERO, "飞到才发现是别人的星系，停在离它 1 格的地方")
	check(me.known.has(enemy), "记下那里有敌方星系")
	var energy := me.energy
	check(s.move_starship(me, enemy)["error"] != "" and me.energy == energy, "已知的敌方星系不能当目的地，也不收费")


## 规则：移动
func test_ship_without_target_leaves_map() -> void:
	var s := _two_civs(Vector3i(0, 0, 8))
	var me := s.human()
	var w := _ship(s, me, Ship.WARSHIP, Vector3(8, 5, 5), Vector3(1, 0, 0))
	w.speed = 0.7
	s._move_ship(me, w)
	s._clean_dead()
	check(me.ships.is_empty(), "飞出星图就消失")


## 规则：移动，调度（派出和行动）
func test_turn_ship_costs_and_reverse_resets_speed() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var w := _ship(s, me, Ship.WARSHIP, Vector3(3, 3, 3), Vector3(1, 0, 0))
	w.speed = 0.5
	var e := me.energy
	var ap := me.actions_left
	check(s.turn_ship(me, w.id, Vector3(1, 1, 0))["error"] == "", "可以转向")
	check(me.energy == e - Balance.COST_TURN and me.actions_left == ap - 1, "转向花 1 AP + 2E")
	check(w.speed == 0.5, "转不到 90° 速度不变")
	s.turn_ship(me, w.id, Vector3(-1, 0, 0))
	check(w.speed == 0.0, "转过 90° 以上速度归零")


## 规则：调度（派出和行动）
func test_probe_slow_start_until_out_of_vision() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["interstellar_probe"])
	var p := s.build(me, "probe")["ship"] as Ship
	check(p.interstellar, "有星际探测器科技时造的是星际探测器")
	check(s.dispatch(me, p.id, Vector3(1, 0, 0), true)["error"] == "", "派出探测器，先慢速飞出视野")
	for i in 3:
		s._move_ship(me, p)
	check(p.speed <= Balance.SLOW_START_SPEED + 1e-6, "在自己星系的视野里不超过慢速")
	for i in 20:
		s._move_ship(me, p)
	check(not p.slow_start and p.speed > Balance.SLOW_START_SPEED, "飞出视野后开始加速")


## 画航线用的预测和真正的移动用同一套算法（F4.3）。
## 规则：移动
func test_predicted_path_matches_movement() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["interstellar_probe"])
	var p := s.build(me, "probe")["ship"] as Ship
	s.dispatch(me, p.id, Vector3(1, 0.3, 0), true)
	var path := s.predict_path(me, p, 20)
	var slow := p.slow_start
	check(path.size() > 1, "在飞的单位有预测的航线")
	for i in range(1, path.size()):
		s._move_ship(me, p)
		check(p.pos.distance_to(path[i]) < 1e-4, "第 %d 回合的位置和预测的一样（慢速出发、加速都算上）" % i)
	check(slow and not p.slow_start, "这一段里经过了慢速出发和飞出视野两种情况")
	check_eq(s.predict_path(me, _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3.ZERO), 6).size(), 1, "停着的单位只有现在的位置")


## 规则：移动
func test_warp_ship_flies_at_light_speed_outside_vision() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var w := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	w.warp = true
	w.speed = 0.2
	s._move_ship(me, w)
	check(w.speed == 1.0 and absf(w.pos.x - 4.0) < 1e-6, "曲率引擎在视野外以光速飞")
	check(s.wakes.size() == 1, "近光速飞行留下航迹")
	var near := _ship(s, me, Ship.WARSHIP, Vector3(0.5, 0, 0), Vector3(0, 1, 0))
	near.warp = true
	s._move_ship(me, near)
	check(near.speed == Balance.WARSHIP_MOVE[1], "在自己星系的视野里按原来的速度")
