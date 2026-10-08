extends "res://tests/rules/rule_suite.gd"
## 黑域：光速变慢、扩散、挡住视野，以及为提速做的捷径。


## 把整张星图的光速都设成 c，不再扩散（测试用）。
func _fill_light(s: GameState, c: float) -> void:
	s._ensure_light()
	s.light.fill(c)
	s._light_moving = false


## G14：只能投放在看得到的地方；生效后那一格光速为 0，保持一段时间，同时向周围扩散，之后慢慢恢复。
## 规则：黑域，G14
func test_black_domain_holds_then_spreads() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var center := Vector3i(2, 0, 0)
	check(s.launch_black_domain(me, center)["error"] != "", "要先有黑域投放科技")
	_give(me, ["domain"])
	check(s.launch_black_domain(me, Vector3i(5, 0, 0))["error"].contains("看得到"), "只能投放在自己现在看得到的地方")
	check(s.launch_black_domain(me, center)["error"] == "", "投放黑域")
	s.end_turn()
	check(s.black_domains.is_empty() and s.light_at(center) == 1.0, "还在准备")
	s.end_turn()
	check(s.light_at(center) == 0.0 and s.black_domains.size() == 1, "生效后那一格的光速变成 0")
	s.end_turn()
	var next := s.light_at(Vector3i(3, 0, 0))
	check(s.light_at(center) == 0.0 and next > 0.0 and next < 1.0, "每回合向周围扩散一格，中心保持 0")
	check(s.light_at(Vector3i(5, 0, 0)) == 1.0, "一回合只扩散一格")
	_turns(s, Balance.BLACK_DOMAIN_TURNS)
	check(s.black_domains.is_empty() and s.light_at(center) > 0.0, "保持 %d 回合后，中心慢慢恢复" % Balance.BLACK_DOMAIN_TURNS)
	check(s.light_at(Vector3i(5, 0, 0)) < 1.0, "扩散到更远的地方")
	_turns(s, 60)
	check(s.light_at(center) > Balance.GRAIN_MIN_LIGHT, "很久以后中心也恢复得差不多")
	check(s.light_at(Vector3i(8, 8, 8)) < 1.0, "宇宙背景的光速降低了一点")


## G14：舰船的速度乘以光速；光速低于 0.95 的地方光粒没有杀伤力；舰船慢到几乎不动就停下，停 5 回合消失。
## 规则：黑域，G14
func test_light_slows_ships_and_disarms_grains() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_fill_light(s, 0.5)
	var w := _ship(s, me, Ship.WARSHIP, Vector3(0, 1, 0), Vector3(1, 0, 0))
	w.speed = Balance.WARSHIP_MOVE[0]
	s.end_turn()
	check(is_equal_approx(w.pos.x, Balance.WARSHIP_MOVE[0] * 0.5), "光速一半的地方，战舰只飞一半远")
	_fill_light(s, 0.9)
	var g := _ship(s, me, Ship.GRAIN, Vector3(0, 2, 0), Vector3(1, 0, 0))
	s.end_turn()
	check(g.dead or not me.ships.has(g), "光速低于 0.95 的地方光粒失去杀伤力，消失")
	me.grains[Vector3i.ZERO] = true
	check(s.grain_error(me, Vector3(1, 0, 0)).contains("黑域"), "在黑域里不能发射光粒")
	_fill_light(s, 0.005)
	s.light[s._li(Vector3i.ZERO)] = 1.0  # 两边的母星系都不在里面，不然直接算输
	s.light[s._li(Vector3i(8, 8, 8))] = 1.0
	var p := _ship(s, me, Ship.PROBE, Vector3(0, 3, 0), Vector3(1, 0, 0))
	_turns(s, Balance.SHIP_STUCK_TURNS - 1)
	check(me.ships.has(p) and p.pos == Vector3(0, 3, 0) and p.stuck == Balance.SHIP_STUCK_TURNS - 1, "慢到几乎不动就停在原地")
	s.end_turn()
	check(not me.ships.has(p), "停 %d 回合后消失" % Balance.SHIP_STUCK_TURNS)
	_give(me, ["warship"])
	var docked := _ship(s, me, Ship.WARSHIP, Vector3(0, 4, 0))
	check(s.dispatch_error(me, docked.id, Vector3(1, 0, 0)) == GameState.STUCK_ERROR, "光速几乎为 0 的地方派不出去")


## G14：光速几乎为 0 的格子挡住光和视野；光速低的地方，情报传回得慢。
## 规则：黑域，G14
func test_black_domain_blocks_vision_and_slows_reports() -> void:
	var s := _two_civs(Vector3i(4, 0, 0))
	var me := s.human()
	me.telescope = 3
	s._ensure_light()
	s.light[s._li(Vector3i(2, 0, 3))] = 0.0
	check(not s.blocked(Vector3.ZERO, Vector3(4, 0, 0)), "光速为 0 的格子不在路线上，不挡")
	s.light[s._li(Vector3i(2, 0, 3))] = 1.0
	s.light[s._li(Vector3i(2, 0, 0))] = 0.0
	check(s.blocked(Vector3.ZERO, Vector3(4, 0, 0)), "路线穿过光速为 0 的格子，挡住")
	s._observe(me)
	check(me.known.is_empty(), "看不到后面")
	var g := _ship(s, me, Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 4)
	check(s.civs[1].alive, "光粒穿不过黑域")
	_fill_light(s, 0.5)
	var probe := _ship(s, me, Ship.PROBE, Vector3(0, 6, 0), Vector3(0, 0, 1))
	probe.speed = 0.0
	me.reports.clear()
	s._observe(me)
	var report: Dictionary = me.reports[-1]
	check(report["home_at"] == s.turn + 12, "光速一半，情报传回要两倍的时间")


## 只为提速的捷径（回合末看之前先算好的数据、只扫线段附近的格子），和直接一格一格算的结果一样。
## 规则：黑域
func test_speedups_match_plain_checks() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := StarMap.SIZE
	s._ensure_light()
	for i in 6:
		s.light[rng.randi_range(0, s.light.size() - 1)] = 0.0
	s.system_cells.clear()
	for x in n:
		for y in n:
			for z in n:
				if (x + 2 * y + 3 * z) % 4 == 0:
					s.system_cells.append(Vector3i(x, y, z))
	var rand_pos := func() -> Vector3:
		return Vector3(rng.randf_range(-1.0, n), rng.randf_range(-1.0, n), rng.randf_range(-1.0, n))
	s._begin_view_cache()
	var blocked_same := true
	var near_same := true
	for i in 400:
		var a: Vector3 = rand_pos.call()
		var b: Vector3 = a + (rand_pos.call() - a) * rng.randf()
		blocked_same = blocked_same and s.blocked(a, b) == (s.light_time(a, b) == INF)
		var reach := rng.randf_range(0.5, 5.0)
		var round := rng.randf() < 0.5
		var plain: Array[Vector3i] = []
		for c in s.system_cells:
			var v := Vector3(c) - a
			if absf(v.x) <= reach and absf(v.y) <= reach and absf(v.z) <= reach and (not round or v.length() <= reach):
				plain.append(c)
		near_same = near_same and s._systems_near(a, reach, round) == plain
	s._view_cache = {}
	check(blocked_same, "有没有被光速为 0 的格子挡住：先排除离得远的，结果不变")
	check(near_same, "按 (x, y) 分好再找附近的星系：找到的格子和顺序都不变")
	var cells_same := true
	for i in 300:
		var a: Vector3 = rand_pos.call()
		var b: Vector3 = a + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var radius := 0.5 if rng.randf() < 0.5 else 0.0
		var d := b - a
		var dir := d.normalized()
		var plain: Array[Vector3i] = []
		for x in n:
			for y in n:
				for z in n:
					var v := Vector3(x, y, z) - a
					var t := v.dot(dir)
					if d.length() >= 1e-9 and t > 0.0 and t <= d.length() and (v - dir * t).length() <= radius + Geometry.CELL_HALF:
						plain.append(Vector3i(x, y, z))
		var fast := Geometry.segment_cells(a, b, radius)
		fast.sort()
		cells_same = cells_same and fast == plain
	check(cells_same, "飞一步扫过的格子：只扫线段附近，结果不变")


## G14、B4：被困在黑域里的星系产出只有 1/10（向上取整），母星系在里面不能升级；全部困在光速为 0 的地方就算输。
## 规则：黑域，每回合的收入，G14
func test_hiding_in_domain_cuts_income_and_all_in_loses() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 4
	_set_star(s, Vector3i(5, 5, 5), StarMap.Star.SINGLE)
	me.colonies.append(Vector3i(5, 5, 5))
	_open_tiers(me, 1)
	var full := s.energy_income(me)
	me.colonies.erase(Vector3i(5, 5, 5))
	var home := s.energy_income(me)
	me.colonies.append(Vector3i(5, 5, 5))
	s._ensure_light()
	s.light[s._li(Vector3i.ZERO)] = 0.5
	check(s.energy_income(me) == ceili(home * Balance.DOMAIN_INCOME) + full - home, "被困在黑域里的星系产出只有 1/10，向上取整")
	check(s.research(me, "dyson")["error"] != "", "母星系在黑域里不能升级科技")
	me.colonies.erase(Vector3i(5, 5, 5))
	s._check_hiding()
	check(me.alive, "光速没降到 0，还算没困住")
	s.light[s._li(Vector3i.ZERO)] = 0.0
	s._check_hiding()
	check(not me.alive, "所有星系都困在光速为 0 的黑域里，算输")


## 规则：黑域
func test_light_diffusion_in_new_dimensions() -> void:
	var s := _two_dimensional_match()
	s._ensure_light()
	var center := Vector3i(13, 13, s.flat_plane)
	s.light[s._li(center)] = 0.0
	s._light_moving = true
	s._spread_light()
	check(is_equal_approx(s.light_at(center), 8.0 / 9.0), "二维光速按邻近 3×3 格扩散")
	check(s.light.size() == 729 and s.light_at(Vector3i(13, 13, s.flat_plane + 1)) == 1.0, "光速数组保留 729 格且图外读取安全")
