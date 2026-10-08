extends SceneTree
## 规则测试，不打开窗口：
##   godot_console --headless --path game --script res://tests/run_tests.gd
## 每个以 test_ 开头的函数是一个测试。有失败时退出码为 1。
## 一个测试一次 check 都没做到（例如规则代码编译失败，第一行就出错），也算失败。

var _failures := 0
var _checks := 0


func _init() -> void:
	var count := 0
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_"):
			count += 1
			var before := _checks
			call(name)
			if _checks == before:
				_failures += 1
				push_error("失败：%s 没有跑到任何检查（可能是代码出错）" % name)
	print("%d 个测试，%d 个失败" % [count, _failures])
	quit(1 if _failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("失败：" + what)


# ---------- 测试用的小工具 ----------

## 空星图上手动放星系，方便控制测试条件。
func _map_with(cells: Dictionary) -> StarMap:
	var m := StarMap.new()
	for c in cells:
		m.stars[c] = cells[c]
	return m


## 两个文明：「你」在 (0,0,0)，「AI」在给定位置。两边都不自动行动（AI 测试再打开）。
func _two_civs(ai_home: Vector3i) -> GameState:
	var s := GameState.new()
	s.map = _map_with({Vector3i.ZERO: StarMap.Star.SINGLE, ai_home: StarMap.Star.SINGLE})
	s.system_cells = [Vector3i.ZERO, ai_home]
	s.civs.append(Civ.new("你", false, Vector3i.ZERO))
	var ai := Civ.new("AI", false, ai_home)
	s.civs.append(ai)
	for civ in s.civs:
		civ.energy = 100
		civ.mineral = 100
		s.start_turn(civ)
	return s


func _set_star(s: GameState, c: Vector3i, star: int) -> void:
	s.map.stars[c] = star
	if not s.system_cells.has(c):
		s.system_cells.append(c)


## 在星图上放一个宜居星系。
func _set_habitable(s: GameState, c: Vector3i, star: int) -> void:
	_set_star(s, c, star)
	s.map.habitable[c] = true
	s.map.rocky[c] = 1


func _give(civ: Civ, ids: Array) -> void:
	for id in ids:
		civ.techs[id] = true


## 造好一个单位并直接放到 pos，朝 dir 飞（测试用，不花资源）。
func _ship(s: GameState, civ: Civ, kind: String, pos: Vector3, dir := Vector3.ZERO) -> Ship:
	var sh := Ship.make(kind, pos, s.next_id())
	sh.docked = dir == Vector3.ZERO
	sh.direction = dir.normalized()
	civ.ships.append(sh)
	return sh


## 直接开放 I 到 tier 级（测试用，不管条件）。
func _open_tiers(civ: Civ, tier: int) -> void:
	for t in range(1, tier + 1):
		civ.set_tier_turn(t, 0)


func _turns(s: GameState, n: int) -> void:
	for i in n:
		s.end_turn()


# ---------- 星图 ----------

func test_same_seed_same_map() -> void:
	var a := StarMap.generate(42)
	var b := StarMap.generate(42)
	check(a.stars == b.stars, "同一个种子应生成同样的星系")
	check(a.habitable == b.habitable, "同一个种子应生成同样的宜居格子")


func test_map_covers_every_cell() -> void:
	var m := StarMap.generate(1)
	check(m.stars.size() == StarMap.SIZE ** 3, "每个格子都应有记录")


func test_star_ratio_roughly_right() -> void:
	var m := StarMap.generate(7)
	var with_star := 0
	for c in m.stars:
		if m.stars[c] != StarMap.Star.NONE:
			with_star += 1
	var ratio := with_star / float(m.stars.size())
	check(ratio > 0.45 and ratio < 0.65, "有星系的比例应接近 0.55，实际 %.2f" % ratio)


func test_map_generation_follows_planet_rules() -> void:
	var m := StarMap.generate(11)
	for c in m.stars:
		var star: int = m.stars[c]
		if star == StarMap.Star.NONE:
			check(not m.rocky.has(c) and not m.habitable.has(c), "没有星系的格子没有行星")
			continue
		check(m.rocky[c] + m.gas[c] <= Balance.MAX_PLANETS[star - 1], "行星数不超过上限")
		if m.habitable.has(c):
			check(m.rocky[c] > 0, "宜居星系至少有一颗类地行星")


func test_bounds() -> void:
	check(StarMap.in_bounds(Vector3i(0, 0, 0)), "原点在图内")
	check(StarMap.in_bounds(Vector3i(8, 8, 8)), "(8,8,8) 在图内")
	check(not StarMap.in_bounds(Vector3i(10, 0, 0)), "(10,0,0) 在图外")


func test_new_game_places_civs() -> void:
	var s := GameState.new_game(5)
	check(s.civs.size() == 1 + Balance.AI_COUNT, "一个人类加 %d 个 AI" % Balance.AI_COUNT)
	var homes := {}
	for civ in s.civs:
		check(s.map.star_at(civ.home) != StarMap.Star.NONE, "%s 的母星必须有星系" % civ.name)
		check(civ.actions_left == civ.action_points(s.map), "%s 开局行动点已发放" % civ.name)
		check(civ.has_tech("probe") and civ.has_tech("colony") and not civ.has_tech("starship"), "开局只有 0 级科技（殖民船在 0 级）")
		homes[civ.home] = true
	check(homes.size() == s.civs.size(), "母星不能重叠")
	check(s.hidden.size() == Balance.HIDDEN_COUNT, "有 %d 个隐藏文明" % Balance.HIDDEN_COUNT)
	check(s.hidden.all(func(h): return not StarMap.in_bounds(h)), "隐藏文明都在星图外")
	var again := GameState.new_game(5)
	check(again.human().home == s.human().home, "同一个种子，母星位置相同")


func test_homes_far_apart() -> void:
	var close := 0
	for seed_value in 50:
		var s := GameState.new_game(seed_value)
		for a in s.civs:
			for b in s.civs:
				if a != b and Vector3(a.home).distance_to(Vector3(b.home)) < Balance.HOME_MIN_DISTANCE:
					close += 1
	check(close == 0, "50 局里母星系都彼此隔开 %.0f 格以上（太近的 %d 对）" % [Balance.HOME_MIN_DISTANCE, close])


# ---------- 实力和收入 ----------

func test_action_points_follow_home_stars_and_colonies() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	check(me.action_points(s.map) == 5, "单星母星系 6 − 1 = 5 个行动点")
	_set_star(s, Vector3i.ZERO, StarMap.Star.TRIPLE)
	check(me.action_points(s.map) == 3, "三星母星系 3 个行动点")
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.TRIPLE)
	me.colonies.append(Vector3i(1, 0, 0))
	check(me.action_points(s.map) == 4, "每多一个殖民地 +1，殖民地的恒星数不影响")


func test_income_from_fission_dysons_and_miners() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 3
	var base := Balance.ENERGY_PER_SYSTEM + Balance.ENERGY_PER_STAR
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY, "每颗类地行星给裂变能")
	me.dysons[Vector3i.ZERO] = 1
	check(s.energy_income(me) == base + 3 * Balance.FISSION_ENERGY + Balance.DYSON_ENERGY, "戴森球 +6E")
	s.map.stars[Vector3i.ZERO] = StarMap.Star.NONE
	check(s.energy_income(me) == Balance.ENERGY_PER_SYSTEM + 3 * Balance.FISSION_ENERGY, "没有恒星的星系没有戴森球和恒星的产能")
	check(s.mineral_income(me) == Balance.MINERAL_PER_COLONY, "每个星系的矿石")
	me.miners[Vector3i.ZERO] = 3
	check(s.mineral_income(me) == Balance.MINERAL_PER_COLONY + 3 * Balance.MINER_MINERAL, "每艘采矿船多产矿石")


func test_end_turn_pays_income() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = 2
	var e := me.energy
	var m := me.mineral
	me.actions_left = 0
	s.end_turn()
	check(me.energy == e + s.energy_income(me) and me.mineral == m + s.mineral_income(me), "回合结束发放收入")
	check(me.actions_left == me.action_points(s.map), "行动点恢复")
	check(s.turn == 2, "进入下一回合")


# ---------- 几何 ----------

func test_cone_basic_shape() -> void:
	var o := Vector3(0, 0, 0)
	var cells := Geometry.cone_cells(o, Vector3(1, 0, 0), 3.0, 15.0)
	check(cells.has(Vector3i(1, 0, 0)) and cells.has(Vector3i(3, 0, 0)), "正前方在圆锥内")
	check(not cells.has(Vector3i(4, 0, 0)), "超出长度的格子不在圆锥内")
	check(not cells.has(Vector3i.ZERO), "起点自己不算")
	check(not cells.has(Vector3i(0, 3, 0)), "侧面 90 度的格子不在圆锥内")
	check(Geometry.cone_cells(o, Vector3.ZERO, 3.0, 15.0).is_empty(), "没有方向时什么都不覆盖")


func test_segment_cells_in_order() -> void:
	var cells := Geometry.segment_cells(Vector3(0.2, 0, 0), Vector3(3.2, 0, 0), 0.0)
	check(cells == [Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)], "按由近到远排列，不含起点")
	var wide := Geometry.segment_cells(Vector3(0, 5, 5), Vector3(1, 5, 5), 0.5)
	check(wide.has(Vector3i(1, 6, 5)) and not wide.has(Vector3i(1, 6, 6)), "半径 0.5 的圆柱再加半个格子")


func test_sphere_sizes_match_design() -> void:
	var c := Vector3(5, 5, 5)
	check(Geometry.sphere_cells(c, 1.0).size() - 1 == 6, "半径 1.0 看到 6 个相邻格子")
	check(Geometry.sphere_cells(c, 1.5).size() - 1 == 18, "半径 1.5 看到 18 格")
	check(Geometry.sphere_cells(c, 2.0).size() - 1 == 32, "半径 2.0 看到 32 格")


# ---------- 移动 ----------

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


func test_ship_without_target_leaves_map() -> void:
	var s := _two_civs(Vector3i(0, 0, 8))
	var me := s.human()
	var w := _ship(s, me, Ship.WARSHIP, Vector3(8, 5, 5), Vector3(1, 0, 0))
	w.speed = 0.7
	s._move_ship(me, w)
	s._clean_dead()
	check(me.ships.is_empty(), "飞出星图就消失")


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


# ---------- 科技和建造 ----------

func test_tech_tiers_and_prerequisites() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ap := me.actions_left
	check(me.has_tech("colony"), "殖民船开局就有（0 级）")
	check(s.research(me, "starship")["error"] != "", "没发现别人不能升 I 级")
	_open_tiers(me, 1)
	check(s.research(me, "starship")["error"] == "", "发现别人以后可以升 I 级（星舰，前置：殖民船）")
	check(me.actions_left == ap, "升级科技不花行动点")
	check(me.energy == 100 - Tech.cost("starship")[0], "升级科技花资源")
	check(s.research(me, "grain")["error"] != "", "没接触不能升 II 级")
	_open_tiers(me, 2)
	check(s.research(me, "devourer")["error"] == "", "接触后可以升 II 级（吞噬者，前置：采矿船）")
	check(s.research(me, "domain")["error"] != "", "III 级要能量收入达到门槛")
	_open_tiers(me, 3)
	check(s.research(me, "domain")["error"].contains("曲率引擎"), "黑域投放要先有曲率引擎")
	check(s.research(me, "starship")["error"] != "", "已经有的不能再升")


## E8：III 级要 II 级开放以后、能量收入达到门槛，再比 II 级晚 TIER_GAP 回合。
func test_tier3_needs_tier2_and_income() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = Balance.TIER3_ENERGY
	s.end_turn()
	check(me.tier3_turn < 0, "II 级没开时收入再高也不算")
	_open_tiers(me, 2)
	me.tier2_turn = s.turn
	s.end_turn()
	check(me.tier3_turn == me.tier2_turn + Balance.TIER_GAP, "收入达标后，III 级比 II 级晚 TIER_GAP 回合开放")
	check(not s.tier_open(me, 3), "还没到那一回合")
	s.map.rocky[Vector3i.ZERO] = 0
	_turns(s, Balance.TIER_GAP)
	check(s.tier_open(me, 3), "达到过一次，到时候就开")
	check(s.research(me, "dimension")["error"] == "", "可以升 III 级")


func test_telescope_and_warning_upgrades() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ap := me.actions_left
	for i in Balance.TELESCOPE_MAX:
		s.upgrade(me, "telescope")
	check(me.telescope == Balance.TELESCOPE_MAX and me.actions_left == ap, "望远镜升到上限，不花行动点")
	check(s.upgrade(me, "telescope")["error"] != "", "不能再升")
	check(is_equal_approx(s.sphere_radius(me, Balance.VISION_HOME), Balance.VISION_HOME + Balance.TELESCOPE_MAX * Balance.TELESCOPE_STEP),
			"升满时母星系视野加 TELESCOPE_MAX × TELESCOPE_STEP")
	var p := _ship(s, me, Ship.PROBE, Vector3.ZERO, Vector3(1, 0, 0))
	check(s.cone_of(me, p)[1] == Balance.MAX_CONE_ANGLE, "圆锥张角最大 60°")
	check(s.upgrade(me, "warning")["error"] != "", "没建预警系统不能升级范围")
	me.has_warning = true
	s.upgrade(me, "warning")
	check(me.warning_range() == Balance.WARNING_RANGE + 1, "预警范围 +1")


func test_build_needs_tech_and_respects_limits() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
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


func test_units_built_docked_then_dispatched() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
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


func test_facilities_next_turn_and_dyson_cap() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
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


func test_grain_no_effect_on_reduced() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	s.civs[1].reduced = true
	var g := _ship(s, s.human(), Ship.GRAIN, Vector3.ZERO, Vector3(1, 0, 0))
	g.speed = 1.0
	_turns(s, 3)
	check(s.civs[1].alive and s.map.star_at(Vector3i(2, 0, 0)) == StarMap.Star.SINGLE, "降维的文明不怕光粒")


# ---------- 视野和情报 ----------

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


func test_warning_reports_enemy_warship() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.has_warning = true
	_ship(s, s.civs[1], Ship.WARSHIP, Vector3(1.8, 0, 0), Vector3(-1, 0, 0))
	_ship(s, s.civs[1], Ship.WARSHIP, Vector3(5, 0, 0), Vector3(-1, 0, 0))
	s._warn(me)
	check(me.alerts.size() == 1 and me.alerts[0]["kind"] == Ship.WARSHIP, "只报告预警范围里的敌方战舰")


# ---------- 战舰、反物质、殖民船 ----------

func test_warships_destroy_each_other() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(s, ai, Ship.WARSHIP, Vector3(3.8, 0, 0), Vector3(-1, 0, 0))
	s._combat()
	check(me.ships.is_empty() and ai.ships.is_empty(), "两艘战舰一起毁掉")


## E8：II 级的条件是自己的任何舰船和别人的舰船相距 CONTACT_RANGE 以内，I 级开放以后才算。
func test_contact_opens_tier2_after_tier1() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.PROBE, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(s, ai, Ship.COLONY, Vector3(3.8, 0, 0), Vector3(-1, 0, 0))
	s._combat()
	check(me.tier2_turn < 0, "I 级还没开时，接触不算")
	_open_tiers(me, 1)
	_open_tiers(ai, 1)
	s._combat()
	check(me.tier2_turn >= 0 and ai.tier2_turn >= 0, "探测器和殖民船相距 1 格以内，双方都算接触")
	check(me.tier2_turn == Balance.TIER_GAP, "II 级比 I 级晚 TIER_GAP 回合开放")
	var far := _two_civs(Vector3i(8, 8, 8))
	_open_tiers(far.human(), 1)
	_ship(far, far.human(), Ship.PROBE, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(far, far.civs[1], Ship.PROBE, Vector3(4.5, 0, 0), Vector3(1, 0, 0))
	far._combat()
	check(far.human().tier2_turn < 0, "隔得远不算")


func test_tiers_open_in_order_with_a_gap() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s._engage(me, s.civs[1])
	check(me.tier2_turn < 0, "先接触、还没发现别人时不算")
	s._discover(me, "测试")
	check(me.tier1_turn == s.turn + 1 and not s.tier_open(me, 1), "发现的那一回合还不开，下一回合开 I 级")
	s.end_turn()
	check(s.tier_open(me, 1), "下一回合开 I 级")
	s._engage(me, s.civs[1])
	check(me.tier2_turn == me.tier1_turn + Balance.TIER_GAP, "接触以后 II 级比 I 级晚 TIER_GAP 回合")
	_turns(s, Balance.TIER_GAP - 1)
	check(not s.tier_open(me, 2), "间隔没满不开")
	s.end_turn()
	check(s.tier_open(me, 2), "间隔满了开 II 级")


# ---------- 战舰的武器（T23） ----------

func test_warships_carry_researched_weapons() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["warship"])
	var plain := s.build_cost(me, "warship")
	_give(me, ["beam", "torpedo"])
	var armed := s.build_cost(me, "warship")
	check(armed[0] == plain[0] + Balance.COST_BEAM_EXTRA[0] + Balance.COST_TORPEDO_EXTRA[0]
			and armed[1] == plain[1] + Balance.COST_BEAM_EXTRA[1] + Balance.COST_TORPEDO_EXTRA[1], "每带一种武器多花一份钱")
	var ship: Ship = s.build(me, "warship")["ship"]
	check(ship.weapons == ["beam", "torpedo"] and ship.cost == armed, "之后造的战舰带上升级过的武器，记下花了多少")


func test_beam_destroys_warship_out_of_collision_range() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ai := s.civs[1]
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam", "torpedo"]
	var theirs := _ship(s, ai, Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	var energy := me.energy
	s._combat()
	check(theirs.dead and not mine.dead, "高能粒子束（射程 1.5）先打掉对方，自己留下")
	check(me.energy == energy - Balance.BEAM_SHOT[0], "开火花能量")


func test_torpedo_needs_two_hits() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ai := s.civs[1]
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam", "torpedo"]
	var theirs := _ship(s, ai, Ship.WARSHIP, Vector3(4.8, 0, 0), Vector3(1, 0, 0))
	var mineral := me.mineral
	s._combat()
	check(not theirs.dead and theirs.damage == 1, "1.9 格只有鱼雷够得着，打中一次不毁")
	check(me.mineral == mineral - Balance.TORPEDO_SHOT[1], "鱼雷花矿石")
	s._combat()
	check(theirs.dead, "打中 %d 次毁掉" % Balance.TORPEDO_HITS)


func test_hbomb_first_and_salvages_cost() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
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


func test_armed_warships_fire_at_the_same_time() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var a := _ship(s, s.human(), Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	var b := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	a.weapons = ["beam"]
	b.weapons = ["beam"]
	s._combat()
	check(a.dead and b.dead, "两边同时开火，一起毁掉")


func test_weapon_needs_ammo_money() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var mine := _ship(s, me, Ship.WARSHIP, Vector3(3, 0, 0), Vector3(1, 0, 0))
	mine.weapons = ["beam"]
	var theirs := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(4.4, 0, 0), Vector3(-1, 0, 0))
	me.energy = 0
	s._combat()
	check(not theirs.dead, "能量不够就不开火")


# ---------- 智子（D5） ----------

## 你在 (0,0,0)，AI 在 (3,0,0)。你派智子过去，等到锁住为止。
func _lock_ai_with_sophon(s: GameState) -> Ship:
	var me := s.human()
	_give(me, ["sophon"])
	var sophon: Ship = s.build(me, "sophon")["ship"]
	check(s.send_sophon(me, sophon.id, Vector3i(3, 0, 0))["error"] == "", "能派智子去任意格子")
	for i in 6:
		if sophon.lock >= 0:
			break
		s.end_turn()
	return sophon


func test_sophon_locks_enemy_home() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	_open_tiers(ai, 1)
	var sophon := _lock_ai_with_sophon(s)
	check(sophon.lock == 1 and s.watched_by(ai) == [me], "智子到了 AI 的母星系，锁住它")
	check(s.research(ai, "dyson")["error"].contains("智子"), "被锁住时不能升级科技")
	var probe := _ship(s, ai, Ship.PROBE, Vector3(8, 8, 8), Vector3(1, 0, 0))
	s._engage(ai, me)
	check(ai.tier2_turn < 0, "被锁住时达到的科技等级条件不算")
	s._observe(me)
	check(me.known.has(Vector3i(3, 0, 0)), "锁住的文明的星系都知道")
	check(me.sightings.any(func(x): return x["pos"] == probe.pos), "它在飞的单位当回合就看到，多远都一样")
	_turns(s, Balance.SOPHON_RESEARCH_TURNS)
	check(s.research(ai, "dyson")["error"] == "", "%d 回合后又能升级科技" % Balance.SOPHON_RESEARCH_TURNS)
	check(s.sophon_tier_left(ai) > 0, "科技等级条件还要更久才算")


func test_building_own_sophon_frees_civ() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	var sophon := _lock_ai_with_sophon(s)
	check(sophon.lock == 1, "先锁住")
	_give(ai, ["sophon"])
	check(s.build(ai, "sophon", Vector3i(3, 0, 0))["error"] == "", "被锁住的文明能造智子")
	check(s.sophons_on(ai).is_empty() and s.sophon_research_left(ai) == 0 and s.sophon_tier_left(ai) == 0,
			"造出自己的智子，锁住它的智子全部失效")


func test_sophon_waits_when_not_a_home() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["sophon"])
	var sophon: Ship = s.build(me, "sophon")["ship"]
	s.send_sophon(me, sophon.id, Vector3i(2, 0, 0))
	_turns(s, 4)
	check(sophon.lock < 0 and sophon.direction == Vector3.ZERO and sophon.pos == Vector3(2, 0, 0), "不是别人的母星系，原地待命")
	check(s.sophon_error(me, sophon.id, Vector3i(8, 8, 8)) == "", "可以再派")
	check(s.civs[1].known.is_empty() and s.civs[1].sightings.is_empty(), "别人看不到智子")

func test_seeing_enemy_ship_counts_as_discovery() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_ship(s, s.civs[1], Ship.PROBE, Vector3(1, 0, 0), Vector3(1, 0, 0))
	s._observe(me)
	check(me.discovered and me.known.is_empty(), "母星系看到别人的探测器就算发现别人")


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


func test_warship_hits_colony_ship_first() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	var c := _ship(s, ai, Ship.COLONY, Vector3(4.5, 0.5, 0), Vector3(0, 1, 0))
	s._combat()
	check(c.dead and ai.alive, "每回合只打一个目标，先打殖民船")


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


func test_colony_ship_destroyed_by_enemy_system() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	_set_habitable(s, Vector3i(2, 0, 0), StarMap.Star.SINGLE)
	var c := _ship(s, me, Ship.COLONY, Vector3.ZERO)
	s.send_colony(me, c.id, Vector3i(2, 0, 0))
	_turns(s, 12)
	check(me.count(Ship.COLONY) == 0 and me.colonies.size() == 1, "路上经过别人的星系就被毁掉")


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


# ---------- 广播和隐藏文明 ----------

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


func test_hearing_needs_broadcaster() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var me := s.human()
	var ai := s.civs[1]
	ai.broadcasters[ai.home] = true
	s.broadcast(ai, Vector3i(8, 8, 8))
	_turns(s, 3)
	check(not me.heard.has(Vector3i(8, 8, 8)), "没有恒星广播器听不到")


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
	_turns(s, 5)
	check(third.known.has(Vector3i.ZERO), "听到的人知道被广播的星系")


func test_hidden_civ_strikes_after_hearing() -> void:
	var old_chance := Balance.HIDDEN_STRIKE_CHANCE
	var old_foil := Balance.HIDDEN_FOIL_CHANCE
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
	Balance.HIDDEN_STRIKE_CHANCE = old_chance
	Balance.HIDDEN_FOIL_CHANCE = old_foil


## 没钱时广播失败：失败的操作不进对局记录，所以也不能动随机数，不然回放会走偏。
func test_failed_broadcast_keeps_rng() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var me := s.human()
	me.broadcasters[me.home] = true
	me.energy = 0
	var before := s.rng.state
	check(s.broadcast(me, Vector3i(5, 0, 0))["error"] != "", "能量不够时不能广播")
	check(s.rng.state == before, "失败的广播不用随机数")


## 离星图好几格的隐藏文明：光粒第一回合还在星图外，不能当成「飞出星图」删掉。
func test_hidden_grain_from_far_outside() -> void:
	var old_chance := Balance.HIDDEN_STRIKE_CHANCE
	var old_foil := Balance.HIDDEN_FOIL_CHANCE
	Balance.HIDDEN_STRIKE_CHANCE = 1.0
	Balance.HIDDEN_FOIL_CHANCE = 0.0
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	s.hidden = [Vector3i(-3, 1, 0)]
	ai.broadcasters[ai.home] = true
	s.broadcast(ai, Vector3i.ZERO)
	_turns(s, 20)
	check(not s.human().alive, "离星图 3 格的隐藏文明发的光粒也能飞到")
	Balance.HIDDEN_STRIKE_CHANCE = old_chance
	Balance.HIDDEN_FOIL_CHANCE = old_foil


# ---------- 黑域 ----------

## 把整张星图的光速都设成 c，不再扩散（测试用）。
func _fill_light(s: GameState, c: float) -> void:
	s._ensure_light()
	s.light.fill(c)
	s._light_moving = false


## G14：只能投放在看得到的地方；生效后那一格光速为 0，保持一段时间，同时向周围扩散，之后慢慢恢复。
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


# ---------- 降维 ----------

func test_foil_prepares_flies_and_unfolds() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var target := Vector3i(1, 0, 0)
	_set_star(s, Vector3i(1, 0, 2), StarMap.Star.DOUBLE)  # 同一列、别的高度
	check(s.launch_foil(me, target)["error"] != "", "要先有维度打击科技")
	_give(me, ["dimension"])
	check(s.launch_foil(me, target)["error"] == "", "可以发射二向箔")
	check(me.energy == 100 - Balance.COST_FOIL, "花能量")
	_turns(s, Balance.FOIL_PREPARE_TURNS)
	check(me.foils[0].prepare_left == 0 and me.foils[0].traveled == 0.0, "准备 2 回合后才起飞")
	_turns(s, 4)
	check(s.flattened.is_empty() and absf(me.foils[0].traveled - 0.8) < 1e-6, "每回合飞 0.2 格")
	s.end_turn()
	check(me.foils.is_empty(), "到达目标后用掉")
	check(s.flattened.get(target) == 0, "目标被压平，平面高度是目标的 z")
	check(s.map.star_at(Vector3i(1, 0, 2)) == StarMap.Star.DOUBLE, "展开保留原星系")
	check(not s.flattened.has(Vector3i(2, 0, 1)) and not s.flattened.has(Vector3i(2, 0, 2)), "波前按整列传播")
	s.end_turn()
	check(not s.flattened.has(Vector3i(2, 0, 1)), "0.9 格尚未覆盖相邻列")


func test_foil_unfolds_on_enemy_in_path() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	_give(me, ["dimension"])
	s.launch_foil(me, Vector3i(3, 0, 0))
	_turns(s, Balance.FOIL_PREPARE_TURNS + 5)
	check(s.flattened.has(Vector3i(1, 0, 0)), "途中碰到别人的星系，提前展开")
	check(not s.civs[1].alive and s.winner == "你", "没降维的文明被压平，灭亡")


func test_foil_bad_targets() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["dimension"])
	check(s.launch_foil(me, Vector3i(10, 0, 0))["error"] != "", "目标必须在星图内")
	check(s.launch_foil(me, Vector3i.ZERO)["error"] != "", "目标不能是发射源")
	s.flattened[Vector3i(5, 5, 3)] = 0
	check(s.launch_foil(me, Vector3i(5, 5, 3))["error"] != "", "已经压平的格子不能当目标")
	me.energy = 0
	check(s.launch_foil(me, Vector3i(5, 5, 5))["error"] != "", "能量不足不能发射")


func test_reduced_civ_survives_flattening() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	var me := s.human()
	me.reduced = true
	s._unfold_foil(Vector3i.ZERO)
	check(me.alive and s.map.star_at(Vector3i.ZERO) == StarMap.Star.SINGLE, "降维的文明不受压平影响")
	s._spread_flat()
	check(s.civs[1].alive, "扩散一回合，还没压到 2 格外的 AI")
	s._spread_flat()
	s._spread_flat()
	check(not s.civs[1].alive and s.winner == "你", "压到以后，没降维的 AI 灭亡")


## 把一整列压平到高度 plane（先压平面那一格，再压其他高度），测试用。
func _flatten_whole_column(s: GameState, col: Vector2i, plane: int) -> void:
	s._flatten_cell(Vector3i(col.x, col.y, plane), plane)
	for z in StarMap.SIZE:
		s._flatten_cell(Vector3i(col.x, col.y, z), plane)


func _finish_flat(s: GameState, anchor := Vector3i(4, 4, 4)) -> void:
	s._unfold_foil(anchor)
	for i in 40:
		if s.all_flat():
			break
		s._spread_flat()


func test_unfold_preserves_systems_assets_and_environment() -> void:
	var s := _collapse_match()
	var me := s.human()
	var upper := Vector3i(0, 0, 7)
	_set_habitable(s, upper, StarMap.Star.DOUBLE)
	me.colonies.append(upper)
	me.dysons[upper] = 2
	me.miners[upper] = 3
	me.grains[upper] = true
	me.bunkers[upper] = true
	me.broadcasters[upper] = true
	me.pending.append({"kind": "miner", "at": upper})
	me.pending_domains.append({"center": upper, "left": 2})
	var ship := _ship(s, me, Ship.STARSHIP, Vector3(0, 0, 3))
	ship.docked = false
	var scout := _ship(s, me, Ship.PROBE, Vector3(1.2, 2, 3), Vector3(0, 0, 1))
	s._ensure_light()
	s.light[s._li(upper)] = 0.25
	s.black_domains.append({"center": upper, "left": 3})
	var stars := s.map.stars.duplicate()
	_flatten_whole_column(s, Vector2i.ZERO, 4)
	check(me.colonies == [Vector3i.ZERO, upper] and not ship.dead, "阶段内保留身份，不把同列资产相互覆盖")
	_finish_flat(s)
	var dest := DimensionSpace.plane_cell(upper, 4)
	check(s.all_flat() and s.map.extent == Vector3i(27, 27, 1), "真实星图切换为 27²")
	check(me.colonies.size() == 2 and me.owns(dest) and not ship.dead, "同列多个星系、星舰全部存活")
	for c in stars:
		check(s.map.star_at(DimensionSpace.plane_cell(c, 4)) == stars[c], "每个原星系一一保留")
	check(me.dysons[dest] == 2 and me.miners[dest] == 3 and me.grains.has(dest), "设施、库存正确迁移")
	check(me.bunkers.has(dest) and me.broadcasters.has(dest) and me.pending[0]["at"] == dest, "防御和待建队列迁移")
	check(me.pending_domains[0]["center"] == dest and s.black_domains[0]["center"] == dest, "黑域准备和中心迁移")
	check(s.light_at(dest) == 0.25 and s.map.is_habitable(dest) and s.map.rocky[dest] == 1, "光速、行星及宜居信息保留")
	check(scout.pos.z == 4 and scout.direction.z == 0 and scout.direction.length() > 0, "浮点舰船和竖直航向转入二维")
	check(s.cell_exists(Vector3i(26, 26, 4)) and not s.cell_exists(Vector3i(27, 0, 4)), "新边界生效")
	check(not s.cell_exists(Vector3i(26, 26, 5)), "二维平面外不是有效格子")


func test_epoch_clears_old_intelligence_and_reexplores() -> void:
	var s := _collapse_match()
	var me := s.human()
	var enemy := s.civs[1].home
	me.known[enemy] = 1
	me.intel[enemy] = s.snapshot(enemy)
	me.reports.append({"cells": {enemy: s.snapshot(enemy)}})
	me.heard[enemy] = 1
	me.colony_tried[enemy] = true
	me.discovered = true
	me.tier1_turn = 1
	var energy := me.energy
	_finish_flat(s)
	check(me.known.is_empty() and me.intel.is_empty() and me.reports.is_empty() and me.heard.is_empty(), "新阶段清除旧情报及在途报告")
	check(me.colony_tried.is_empty() and me.energy == energy and me.tier1_turn == 1 and me.discovered, "探索记忆重置，发展成果保留")
	s._observe(me)
	check(me.intel.has(me.home) and not me.known.has(s.civs[1].home), "新坐标可重新观测，远处敌人仍隐藏")


func test_same_column_enemy_assets_do_not_collide() -> void:
	var s := _two_civs(Vector3i(0, 0, 7))
	for civ in s.civs:
		civ.reduced = true
		_ship(s, civ, Ship.STARSHIP, Vector3(civ.home))
	_finish_flat(s)
	check(s.civs.all(func(c): return c.alive and c.has_starship()), "同列敌对星系和停靠星舰不会覆盖")
	check(s.civs[0].home != s.civs[1].home, "两个文明获得不同二维坐标")


func test_dimension_mapping_bijection_and_movement() -> void:
	for z in 9:
		var seen := {}
		for c in StarMap.new().cells():
			seen[DimensionSpace.plane_cell(c, z)] = true
		check(seen.size() == 729, "每个锚点层都有 729 个唯一目标")
	var s := _two_dimensional_match()
	for civ in s.civs:
		civ.line_reduced = true
	s._unfold_line_foil(Vector3i(13, 13, s.flat_plane))
	for i in 40:
		s._spread_flat()
	check(s.all_linear() and s.map.extent == Vector3i(729, 1, 1), "二维再次展开为 729 格直线")
	check(s.map.cells().size() == 729 and s.civs[0].home != s.civs[1].home, "一维仍没有坐标覆盖")
	check(s.cell_exists(Vector3i(728, 13, s.flat_plane)), "一维末端可用")
	var sh := _ship(s, s.human(), Ship.PROBE, Vector3(700, 13, s.flat_plane), Vector3.RIGHT)
	s._move_ship(s.human(), sh)
	check(not sh.dead and sh.pos.x > 700, "原 3D 边界不会错误删除一维舰船")
	check(Geometry.segment_cells(Vector3(700, 13, s.flat_plane), Vector3(702, 13, s.flat_plane), 0, s.map.bounds()).size() == 2, "一维战斗扫描使用当前边界")


func test_ai_foil_is_last_resort() -> void:
	var s := _collapse_match()
	var ai := s.civs[1]
	ai.known[s.human().home] = 1
	check(not AI._try_foil(s, ai), "有资源和已知敌人不等于可以常规使用末日武器")
	ai.times_hit = 2
	check(AI._try_foil(s, ai) and ai.foils.size() == 1, "最后据点反复被打且没有常规武器时可发射")
	check(not AI._try_foil(s, ai), "在途箔未结束时不重复发射")


func test_everyone_flattened_means_no_winner() -> void:
	var s := _two_civs(Vector3i(0, 0, 5))  # 和你在同一列
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(not s.human().alive and not s.civs[1].alive, "同一列的文明都被压平")
	check(s.winner == "无", "都灭亡了，没有赢家")


func test_flattening_destroys_ships_and_wakes() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ss := _ship(s, me, Ship.STARSHIP, Vector3(3, 3, 3))
	ss.docked = false
	s.wakes.append({"a": Vector3(3, 3, 3), "b": Vector3(3, 3, 4), "turn": 1, "gone": false})
	_flatten_whole_column(s, Vector2i(3, 3), 0)
	s._clean_dead()
	check(not me.has_starship(), "没降维的星舰被压平")
	check(s.wakes[0]["gone"], "航迹在降维时消失")


func test_foil_vanishes_when_launcher_dies() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.foils.append(Foil.new(Vector3(ai.home), Vector3i(8, 8, 8), 2))
	s._lose_system(ai.home, ai)
	check(ai.foils.is_empty(), "发射者灭亡，二向箔也消失")


func test_reduce_takes_turns_and_blocks_building() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	check(s.start_reduce(me)["error"] != "", "要先有维度打击科技")
	_give(me, ["dimension"])
	check(me.reduce_cost() == Balance.COST_REDUCE_BASE + Balance.COST_REDUCE_PER_UNIT, "一个星系，按一个单位收费")
	_ship(s, me, Ship.PROBE, Vector3.ZERO)
	me.grains[Vector3i.ZERO] = true
	check(me.reduce_units() == 3, "单位、光粒也算")
	var e := me.energy
	check(s.start_reduce(me)["error"] == "", "可以开始降维")
	check(me.energy == e - (Balance.COST_REDUCE_BASE + 3 * Balance.COST_REDUCE_PER_UNIT), "按单位数收费")
	check(s.build(me, "probe")["error"] != "", "降维期间不能建造")
	_turns(s, Balance.REDUCE_TURNS - 1)
	check(not me.reduced, "还没完成")
	s.end_turn()
	check(me.reduced, "%d 回合后完成" % Balance.REDUCE_TURNS)
	s.map.rocky[Vector3i.ZERO] = 4
	var full := Balance.ENERGY_PER_SYSTEM + Balance.ENERGY_PER_STAR + 4 * Balance.FISSION_ENERGY
	check(s.energy_income(me) == int(full / 2.0), "降维后收入减半")


func test_reduce_waits_for_pending_buildings() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["dimension"])
	s.build(me, "miner")
	var e := me.energy
	check(s.start_reduce(me)["error"] != "" and me.energy == e, "有没建好的设施时不能降维，也不花钱")


func _collapse_match() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	for civ in s.civs:
		civ.reduced = true
		civ.energy = 1000
		_give(civ, ["dimension"])
	return s


func test_foils_share_one_plane() -> void:
	var s := _collapse_match()
	check(s.launch_foil(s.human(), Vector3i(1, 1, 1))["error"] == "", "第一片箔发射")
	check(s.launch_foil(s.civs[1], Vector3i(8, 8, 7))["error"] == "", "另一高度的箔发射")
	for i in 180:
		s.end_turn()
	check(s.all_flat(), "两片箔最终压平全图")
	check(s.flattened.values().all(func(z): return z == s.flat_plane), "每个格子都在同一个平面")
	check(s.civs.all(func(c): return c.home.z == s.flat_plane), "幸存文明也在共同平面")


func test_different_planes_are_not_fully_flat() -> void:
	var s := _collapse_match()
	for x in StarMap.SIZE:
		for y in StarMap.SIZE:
			for z in StarMap.SIZE:
				s.flattened[Vector3i(x, y, z)] = 2 if x < 5 else 7
	check(not s.all_flat(), "只数格子不够：不同高度不能算压成同一平面")


func test_collapse_finishes_after_combat_ends() -> void:
	var s := _collapse_match()
	s.civs[1].reduced = false
	s._unfold_foil(Vector3i(8, 8, 8))
	check(s.is_over() and s.collapse_pending(), "胜负已出，空间还在坍缩")
	var turn := s.turn
	var energy := s.human().energy
	for i in 30:
		s.end_turn()
	check(s.all_flat() and not s.collapse_pending(), "战斗结束后整张星图仍压成平面")
	check(s.turn == turn and s.human().energy == energy, "结束后不执行 AI、不产出、不增加回合")


func _two_dimensional_match() -> GameState:
	var s := _collapse_match()
	s._unfold_foil(Vector3i(4, 4, 4))
	for i in 20:
		if s.all_flat():
			break
		s.end_turn()
	return s


func test_line_foil_requires_two_dimensional_world() -> void:
	var s := _collapse_match()
	var energy := s.human().energy
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 3))["error"] != "", "三维地图不能发射单向著")
	check(s.human().energy == energy and s.human().foils.is_empty(), "拒绝的发射不花资源")
	s = _two_dimensional_match()
	check(s.all_flat(), "测试准备：全图压平")
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 8))["error"] != "", "单向著目标必须在现有平面")
	check(s.launch_foil(s.human(), Vector3i(3, 3, 4))["error"] != "", "二维后不能再发二向箔")


func test_second_self_reduction() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	check(s.start_reduce(me)["error"] == "", "二维地图可以再降一次")
	_turns(s, Balance.REDUCE_TURNS)
	check(me.line_reduced, "进入一维")
	check(s.start_reduce(me)["error"] != "", "不支持一维以下的自身降维")


func test_line_foils_converge_then_draw_after_grace() -> void:
	var s := _two_dimensional_match()
	for civ in s.civs:
		civ.line_reduced = true
	check(s.launch_line_foil(s.human(), Vector3i(2, 2, 4))["error"] == "", "第一片单向著")
	check(s.launch_line_foil(s.civs[1], Vector3i(7, 7, 4))["error"] == "", "另一 y 位置的单向著")
	for i in 180:
		if s.all_linear():
			break
		s.end_turn()
	check(s.all_linear() and s.linearized.values().all(func(y): return y == s.line_y), "全部格子归于同一条直线")
	check(s.civs.all(func(c): return c.alive and c.home.y == s.line_y), "幸存文明位于共同直线")
	check(not s.is_over(), "压成直线后不马上判平局")
	_turns(s, Balance.LINE_GRACE_TURNS + 1)
	check(s.winner == "平局", "过了 %d 回合没人完成奇异点，平局" % Balance.LINE_GRACE_TURNS)


func test_singularity_wins() -> void:
	var s := _two_dimensional_match()
	for civ in s.civs:
		civ.line_reduced = true
	s._unfold_line_foil(Vector3i(4, 4, s.flat_plane))
	for i in 30:
		if s.all_linear():
			break
		s.end_turn()
	var me := s.human()
	me.actions_left = 3
	check(s.launch_singularity(me)["error"] == "", "一维里可以发射奇异点")
	_turns(s, Balance.SINGULARITY_TURNS)
	check(s.winner == "你", "先降到零维的赢")


## F5.3：预警按箔的种类报名字；已经没用的箔（二维里的二向箔）不报。
func test_warning_names_line_foil() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	me.has_warning = true
	var other := s.civs[1]
	other.foils.append(Foil.new(Vector3(me.home) + Vector3(1, 0, 0), me.home, 0, true))
	other.foils.append(Foil.new(Vector3(me.home) + Vector3(0, 1, 0), me.home, 0, false))
	s._warn(me)
	check(me.alerts.size() == 1 and me.alerts[0]["kind"] == "line_foil", "二维里只报单向著，叫单向著")


## F5.3：隐藏文明按现在的维度出手：二维发单向著（目标挪到平面上），压成直线后只发光粒。
func test_hidden_weapon_matches_dimension() -> void:
	var old_chance := Balance.HIDDEN_STRIKE_CHANCE
	var old_foil := Balance.HIDDEN_FOIL_CHANCE
	Balance.HIDDEN_STRIKE_CHANCE = 1.0
	Balance.HIDDEN_FOIL_CHANCE = 1.0
	var old_range := Balance.HIDDEN_HEAR_RANGE
	Balance.HIDDEN_HEAR_RANGE = 1e6  # 出手的机会随距离变小，放大范围让它一定出手
	var s := _two_dimensional_match()
	var listen := {"from": Vector3i(-1, 4, s.flat_plane), "target": Vector3i(3, 3, 7), "left": 5}
	s.hidden_listen.append(listen.duplicate())
	s._hidden_strikes()
	check(s.hidden_foils.size() == 1 and s.hidden_foils[0].to_line and s.hidden_foils[0].target.z == s.flat_plane,
			"二维时投送单向著，目标在平面上")
	s.hidden_foils.clear()
	for civ in s.civs:
		civ.line_reduced = true
	s._unfold_line_foil(Vector3i(4, 4, s.flat_plane))
	for i in 30:
		if s.all_linear():
			break
		s.end_turn()
	check(s.all_linear(), "测试准备：压成直线")
	s.hidden_listen.clear()
	s.hidden_foils.clear()
	s.hidden_ships.clear()
	s.hidden_listen.append(listen.duplicate())
	s._hidden_strikes()
	check(s.hidden_foils.is_empty() and s.hidden_ships.size() == 1, "一维里没有箔可发，只发光粒")
	Balance.HIDDEN_HEAR_RANGE = old_range
	Balance.HIDDEN_STRIKE_CHANCE = old_chance
	Balance.HIDDEN_FOIL_CHANCE = old_foil


func test_line_attack_destroys_unprepared_civ() -> void:
	var s := _two_dimensional_match()
	s.human().line_reduced = true
	s._unfold_line_foil(s.civs[1].home)
	check(not s.civs[1].alive and s.winner == "你", "只降到二维的对手不能抵挡单向著")


# ---------- AI ----------

func test_ai_researches_after_discovery() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ai := s.civs[1]
	ai.is_ai = true
	_open_tiers(ai, 1)
	AI.take_turn(s, ai)
	var tier1 := 0
	for id in ai.techs:
		if Tech.tier(id) == 1:
			tier1 += 1
	check(tier1 > 0, "发现别人以后会升 I 级科技")


func test_ai_launches_grain_at_known_target() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["grain"])
	ai.grains[ai.home] = true
	ai.known[Vector3i.ZERO] = 1
	AI.take_turn(s, ai)
	check(ai.count(Ship.GRAIN) == 1 and ai.aimed.has(Vector3i.ZERO), "朝已知目标发射光粒")
	_turns(s, 8)
	check(not s.human().alive, "光粒飞到，打中")


func test_ai_colonizes() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["colony"])
	_set_habitable(s, Vector3i(8, 8, 7), StarMap.Star.SINGLE)
	_set_habitable(s, Vector3i(8, 0, 8), StarMap.Star.SINGLE)
	ai.intel[Vector3i(8, 8, 7)] = s.snapshot(Vector3i(8, 8, 7))
	AI.take_turn(s, ai)
	check(not ai.colony_tried.has(Vector3i(8, 0, 8)), "AI 不去没看到过的宜居星系")
	var sent := false
	for sh in ai.ships:
		sent = sent or (sh.kind == Ship.COLONY and sh.has_target)
	check(sent, "造殖民船并派向宜居星系")


func test_ai_uses_antimatter() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	ai.is_ai = true
	ai.antimatter = 1
	var w := _ship(s, s.human(), Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	AI.take_turn(s, ai)
	check(w.dead, "敌方战舰靠近时用反物质")


func test_ai_reduces_when_flattening_near() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["dimension"])
	s.foil_zones.append({"center": Vector3i(3, 0, 0), "age": 0.0})
	AI.take_turn(s, ai)
	check(ai.reduce_left > 0, "压平快到时开始降维")


func test_long_ai_game_runs() -> void:
	var s := GameState.new_game(3)
	s.spectator = true
	s.human().is_ai = true
	for i in 200:
		if s.is_over():
			break
		s.end_turn()
	check(s.turn > 20, "整局 AI 对局能跑下去")
	var techs := 0
	for c in s.civs:
		techs += c.techs.size()
	check(techs > s.civs.size() * 6, "AI 升过科技")

## AI 只用自己看到或听到的情报：看不到你时，不知道你在哪里，也不会朝你打。
func test_ai_only_knows_what_it_saw() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["warship", "grain", "dimension"])
	_open_tiers(ai, 2)
	ai.energy = 500
	for i in 5:
		ai.actions_left = 5
		AI.take_turn(s, ai)
		s._observe(ai)
	check(not ai.known.has(Vector3i.ZERO), "AI 看不到你，就不知道你的星系")
	check(not ai.intel.has(Vector3i.ZERO), "AI 没有你星系的情报")
	check(ai.foils.is_empty(), "AI 不知道目标时不发二向箔")
	check(ai.ships.all(func(sh): return sh.kind != Ship.GRAIN), "AI 不知道目标时不发光粒")
	# 听到广播以后才知道
	s.civs[0].broadcasters[Vector3i.ZERO] = true
	ai.broadcasters[Vector3i(8, 8, 8)] = true  # 有广播器才听得到
	ai.heard.clear()
	s.broadcasts.append({"from": Vector3(8, 8, 0), "target": Vector3i.ZERO, "sender": null, "exposed": GameState.NO_HIT,
			"radius": 0.0, "heard": {}, "hidden_heard": {}})
	for i in 12:
		s._spread_broadcasts()
	check(ai.known.has(Vector3i.ZERO), "听到广播以后，AI 才知道你的坐标")


# ---------- 对局记录和回放 ----------

## 「你」照固定的做法行动（不用随机数）：能升的科技升一项，造探测器朝固定方向派出，有已知目标就派战舰。
func _scripted_player_turn(s: GameState) -> void:
	var me := s.human()
	if not me.alive or s.is_over():
		return
	for id in Tech.ALL:
		if s.research_error(me, id) == "":
			s.research(me, id)
			break
	var probe = s.build(me, "probe")["ship"]
	if probe != null:
		s.dispatch(me, probe.id, Vector3(1, (s.turn % 5) - 2, 0.5), s.turn % 2 == 0)
	if not me.known.is_empty():
		var ship = s.build(me, "warship")["ship"]
		if ship != null:
			s.dispatch(me, ship.id, Vector3(me.known.keys()[0]) - ship.pos)


## 玩家照固定做法打 n 回合（中途让 AI 接管几回合再交还）。
func _player_game(seed_value: int, n: int) -> GameState:
	var s := GameState.new_game(seed_value)
	for i in n:
		if s.is_over():
			break
		if i == 8:
			s.set_autoplay(s.human(), true)
		elif i == 12:
			s.set_autoplay(s.human(), false)
		if not s.human().is_ai:
			_scripted_player_turn(s)
		s.end_turn()
	return s


func test_same_seed_same_game() -> void:
	var a := GameState.new_game(11)
	var b := GameState.new_game(11)
	for s in [a, b]:
		s.spectator = true
		s.human().is_ai = true
		for i in 180:
			s.end_turn()
	check(a.checksums.size() == b.checksums.size() and a.checksums == b.checksums, "同一个种子的两局 AI 对局每回合都一样")
	check(a.checksum() == b.checksum(), "最后的局面一样")


func test_history_records_every_civ() -> void:
	var s := _player_game(5, 20)
	var by_civ := {}
	var wrong := 0
	for h in s.history:
		by_civ[h["civ"]] = true
		# 第 8～11 次结束回合时玩家由 AI 接管
		var by_ai: bool = h["name"] != "set_autoplay" and (h["civ"] != 0 or (h["step"] >= 8 and h["step"] < 12))
		if h["ai"] != by_ai:
			wrong += 1
	check(wrong == 0, "AI 做的操作标成 AI，玩家做的不是")
	check(by_civ.size() >= 3, "记录里有玩家和几个 AI 的操作")
	check(s.history.any(func(h): return h["civ"] == 0 and h["name"] == "dispatch"), "记录了玩家派出单位")
	check(s.history.filter(func(h): return h["name"] == "set_autoplay").size() == 2, "记录了让 AI 接管和交还")


func test_replay_rebuilds_player_game() -> void:
	var s := _player_game(7, 40)
	var r := Replay.from_state(s)
	check(r.commands.all(func(c): return not c["ai"]), "记录里只有玩家的操作")
	check(r.last_step() == s.steps, "记录的回合数和对局一样")
	var again := r.play_to(r.last_step())
	check(r.desync_step == -1, "重算没有走偏")
	check(again.checksum() == s.checksum() and again.turn == s.turn, "重算出的最后局面和原来一样")
	var mid := r.play_to(10)
	check(mid.steps == 10 and mid.checksums[9] == s.checksums[9], "可以只重算到中间某一回合")
	check(mid.human().is_ai, "第 10 回合时玩家还由 AI 接管着（接管也重做了）")
	# 从中间一步一步往后走，和原来一样
	while mid.steps < r.last_step():
		check(r.step(mid), "第 %d 回合往后走一步和原来一样" % mid.turn)
	check(mid.checksum() == s.checksum(), "一步一步走到最后，局面一样")


func test_replay_save_and_load() -> void:
	var s := _player_game(9, 25)
	var path := Replay.DIR.path_join("_test.replay")
	var r := Replay.from_state(s)
	check(r.save(path) == OK, "记录能存文件")
	var loaded := Replay.load_file(path)
	check(loaded != null and loaded.commands.size() == r.commands.size(), "能读回来")
	check(loaded.balance_diff().is_empty(), "数值没改过时没有差异")
	var again := loaded.play_to(loaded.last_step())
	check(loaded.desync_step == -1 and again.checksum() == s.checksum(), "读回来的记录重算结果一样")
	DirAccess.remove_absolute(path)
	check(Replay.load_file(Replay.DIR.path_join("_none.replay")) == null, "文件不存在时返回 null")


func test_replay_detects_changes() -> void:
	var s := _player_game(4, 20)
	var r := Replay.from_state(s)
	# 改记录中间一回合的校验值（对局可能提前结束，所以按记录长度取中间）
	var mid := r.last_step() / 2
	check(mid >= 2, "对局至少打了几回合")
	r.checksums[mid] += 1
	r.play_to(r.last_step())
	check(r.desync_step == mid + 1, "结果和记录不一样时记下是第几回合")
	r.balance["START_ENERGY"] = Balance.START_ENERGY + 1
	check(r.balance_diff().has("START_ENERGY"), "能列出记录时和现在不一样的数值")


func test_replay_truncate_branches() -> void:
	var s := _player_game(6, 30)
	var r := Replay.from_state(s)
	r.truncate(10)
	check(r.last_step() == 10 and r.commands.all(func(c): return c["step"] < 10), "第 10 回合以后的记录丢掉")
	var branch := r.play_to(10)
	check(branch.checksums[9] == s.checksums[9], "分叉点之前一样")


## 测试里改过的数值，测完换回来。
func _restore_balance(values: Dictionary) -> void:
	var r := Replay.new()
	r.balance = values
	r.apply_balance()


func test_dev_changes_are_replayed() -> void:
	var before := Replay.balance_values()
	var s := GameState.new_game(8)
	for i in 5:
		_scripted_player_turn(s)
		s.end_turn()
	var me := s.human()
	check(s.dev_set(me, "energy", 500)["error"] == "" and me.energy == 500, "可以直接改文明的能量")
	check(s.dev_balance("ENERGY_PER_STAR", Balance.ENERGY_PER_STAR + 3)["error"] == "", "可以改 balance.gd 的数值")
	check(s.dev_balance("COST_PROBE", [0, 1])["error"] == "" and Balance.COST_PROBE == [0, 1], "数组数值也能改")
	check(s.dev_tech(s.civs[1], "warship", true)["error"] == "" and s.civs[1].has_tech("warship"), "可以直接给科技")
	check(s.dev_used, "改过数值的对局有标记")
	for i in 15:
		_scripted_player_turn(s)
		s.end_turn()
	var r := Replay.from_state(s)
	check(r.balance["ENERGY_PER_STAR"] == before["ENERGY_PER_STAR"], "记录里存的是开局时的数值")
	check(r.commands.filter(func(c): return String(c["name"]).begins_with("dev_")).size() == 4, "改数值记进了记录")
	var again := r.play_to(r.last_step())
	check(r.desync_step == -1 and again.checksum() == s.checksum(), "改过数值的对局也能原样重算")
	r.play_to(3)
	check(Balance.ENERGY_PER_STAR == before["ENERGY_PER_STAR"], "退回到改数值以前，数值也回到当时的")
	_restore_balance(before)


func test_dev_set_rejects_bad_input() -> void:
	var s := _two_civs(Vector3i(5, 5, 5))
	var me := s.human()
	check(s.dev_set(me, "is_ai", true)["error"] != "" and not me.is_ai, "不能用它改由谁控制")
	check(s.dev_set(me, "no_such", 1)["error"] != "", "没有的属性改不了")
	check(s.dev_set(me, "energy", "lots")["error"] != "", "类型不对改不了")
	check(s.dev_balance("NO_SUCH", 1)["error"] != "", "没有的数值改不了")
	check(s.history.is_empty() and not s.dev_used, "改不成的不记")


func test_ai_writes_notes() -> void:
	var s := GameState.new_game(2)
	s.spectator = true
	s.human().is_ai = true
	for i in 15:
		s.end_turn()
	var notes := s.history.filter(func(h): return h["name"] == "note")
	check(notes.size() >= 15, "AI 每回合写下想法")
	check(Replay.from_state(s).commands.is_empty(), "AI 的想法和操作都不进回放记录")
	var seen := {}
	var dup := 0
	for h in notes:
		var key := [h["step"], h["civ"], h["args"][0]]
		if seen.has(key):
			dup += 1
		seen[key] = true
	check(dup == 0, "同一回合一样的想法只记一次")


# ---------- 玩家灭亡后接着打 ----------

## 玩家什么都不做、一直结束回合，直到对局结束。play_on 为 true 时开局就打开「灭亡后接着打」。
func _passive_game(seed_value: int, play_on: bool) -> GameState:
	var s := GameState.new_game(seed_value)
	if play_on:
		s.set_play_on_after_death(true)
	for i in 300:
		if s.is_over():
			break
		s.end_turn()
	return s


## 找一个玩家灭亡时还剩不止一个 AI 的种子（找不到时返回 -1）。
func _seed_where_player_dies() -> int:
	for seed_value in 30:
		var s := _passive_game(seed_value, false)
		if s.winner == "AI" and s.civs.filter(func(c): return c.alive).size() >= 2:
			return seed_value
	return -1


func test_play_on_after_player_death() -> void:
	var seed_value := _seed_where_player_dies()
	check(seed_value >= 0, "找得到玩家先灭亡的对局")
	if seed_value < 0:
		return
	var ended := _passive_game(seed_value, false)
	check(ended.is_over() and not ended.human().alive, "平时玩家灭亡对局就结束")
	var s := _passive_game(seed_value, true)
	check(not s.human().alive, "开着「灭亡后接着打」，玩家同样会灭亡")
	check(s.steps > ended.steps, "但对局没有在那一回合结束，其余文明接着打")
	check(s.winner != "AI" and s.winner != "你", "最后的胜负写赢家的名字（或无、平局）")
	var again := Replay.from_state(s).play_to(s.steps)
	check(again.checksum() == s.checksum(), "这样的对局也能原样重算")


## 调试面板里「继续往下看」的做法：重算灭亡的那一回合，先打开开关再结束回合。
func test_continue_after_death_recomputes_last_turn() -> void:
	var seed_value := _seed_where_player_dies()
	if seed_value < 0:
		check(false, "找得到玩家先灭亡的对局")
		return
	var ended := _passive_game(seed_value, false)
	var r := Replay.from_state(ended)
	var s := r.play_to(ended.steps - 1)
	r.apply_pending(s)
	s.set_play_on_after_death(true)
	s.end_turn()
	check(s.steps == ended.steps and not s.human().alive, "重算的那一回合玩家同样灭亡")
	check(not s.is_over(), "这次对局没有结束")
	for i in 300:
		if s.is_over():
			break
		s.end_turn()
	check(s.steps > ended.steps and s.winner != "AI", "接着推进对局，胜负不再由玩家死亡决定")
	var again := Replay.from_state(s).play_to(s.steps)
	check(again.checksum() == s.checksum(), "接着打的部分也能原样重算")


## 三个文明：你在 (0,0,0)，AI 在 (9,9,9)，第三方在 (9,0,0)。
func _three_civs() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	var third := Civ.new("第三方", false, Vector3i(8, 0, 0))
	_set_star(s, third.home, StarMap.Star.SINGLE)
	s.civs.append(third)
	s.start_turn(third)
	return s


## 只有一个星系、星舰停在那里：光粒打中后星系和星舰都没了，文明要灭亡，不能「只剩星舰」地活着。
func test_grain_kills_parked_starship_and_civ() -> void:
	var s := _three_civs()
	var ai := s.civs[1]
	_ship(s, ai, Ship.STARSHIP, Vector3(8, 8, 8))
	_ship(s, s.human(), Ship.GRAIN, Vector3(6, 8, 8), Vector3(1, 0, 0))
	_turns(s, 6)
	check(ai.colonies.is_empty() and not ai.has_starship(), "星系和停着的星舰都被毁掉")
	check(not ai.alive, "什么都不剩的文明灭亡")


## 文明灭亡前发出的光粒接着飞，照样能打中。
func test_grain_flies_on_after_owner_dies() -> void:
	var s := _three_civs()
	var ai := s.civs[1]
	_ship(s, ai, Ship.GRAIN, Vector3(3, 0, 0), Vector3(-1, 0, 0))
	s._die(ai)
	check(not s.is_over(), "还剩两个文明，对局继续")
	_turns(s, 6)
	check(not s.human().alive, "灭亡文明发出的光粒照样打中")


## 预警系统是整个文明的：下单的星系在建好前丢了，换个星系照样建好。
func test_warning_built_after_its_system_falls() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var other := Vector3i(0, 3, 0)
	_set_star(s, other, StarMap.Star.SINGLE)
	me.colonies.append(other)
	me.pending.append({"kind": "warning", "at": other})
	s._lose_system(other, me)
	s._finish_pending(me)
	check(me.has_warning, "预警系统照样建好")


## 灭亡的文明不再收到新情报，但这一回合的预警和太旧的目击记录照样清掉。
func test_dead_civ_intel_expires() -> void:
	var s := _three_civs()
	var me := s.human()
	s.set_play_on_after_death(true)
	me.alerts.append({"pos": Vector3(3, 3, 3)})
	me.sightings.append({"pos": Vector3(4, 4, 4), "kind": Ship.WARSHIP, "turn": s.turn})
	s._die(me)
	_turns(s, Balance.SIGHTING_KEEP + 2)
	check(me.alerts.is_empty() and me.sightings.is_empty(), "预警和旧的目击记录都清掉")


## 观战局里 0 号文明也叫「你」：它赢了也不能写成玩家胜利。
func test_spectator_winner_is_named() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.spectator = true
	s._die(s.civs[1])
	check(s.winner == "你" and s.winner_by_name(), "观战局的胜负写赢家的名字")
	check(not s.log_lines.any(func(l): return l.contains("你胜利了")), "日志不说「你胜利了」")


# ---------- 数值方案 ----------

func test_preset_save_and_read() -> void:
	var values := BalancePresets.file_values()
	values["START_ENERGY"] = values["START_ENERGY"] + 7
	values["STAR_WEIGHTS"] = [7, 2, 1]
	var path := BalancePresets.USER_DIR.path_join("_test.cfg")
	check(BalancePresets.save(path, values, "测试") == OK, "方案能存文件")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("STAR_WEIGHTS=[7, 2, 1]") and not text.contains("P_HAS_STAR"), "只存改过的数值，数组写成人看得懂的样子")
	var p := BalancePresets.read(path)
	check(p["values"].size() == 2 and p["values"]["START_ENERGY"] == values["START_ENERGY"], "读回来的数值一样")
	check(p["values"]["STAR_WEIGHTS"] == [7, 2, 1] and p["note"] == "测试" and p["warnings"].is_empty(), "数组和说明也读得回来")
	check(BalancePresets.list().any(func(x): return x["name"] == "_test" and not x["shared"]), "列表里有这个自己的方案")
	DirAccess.remove_absolute(path)
	check(BalancePresets.read(path).is_empty(), "文件不存在时返回空的")


func test_preset_read_skips_bad_values() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("values", "NO_SUCH_VALUE", 1)
	cfg.set_value("values", "START_ENERGY", "很多")
	cfg.set_value("values", "P_HAS_STAR", 1)
	var path := BalancePresets.USER_DIR.path_join("_bad.cfg")
	DirAccess.make_dir_recursive_absolute(BalancePresets.USER_DIR)
	cfg.save(path)
	var p := BalancePresets.read(path)
	check(p["warnings"].size() == 2, "没有的名字、类型不对的值都跳过并说明")
	check(p["values"].get("P_HAS_STAR") is float, "整数可以当小数用")
	DirAccess.remove_absolute(path)


func test_file_values_ignore_runtime_changes() -> void:
	var before := Replay.balance_values()
	Balance.START_ENERGY = before["START_ENERGY"] + 50
	check(BalancePresets.file_values()["START_ENERGY"] == before["START_ENERGY"], "读到的是 balance.gd 文件里写的值")
	check(BalancePresets.file_values().size() == before.size(), "每个数值都读到了")
	check(BalancePresets.file_values()["STAR_WEIGHTS"].is_typed(), "数组的类型和 Balance 里的一样")
	_restore_balance(before)


## 运行时不读 balance.gd 的原文（导出的游戏里可能没有原文），数值的名字、说明、文件里的值都取自 balance_index.gd。
func test_balance_index_up_to_date() -> void:
	var source := FileAccess.get_file_as_string(BalancePresets.BALANCE_PATH)
	check(BalancePresets.index_source(source) == FileAccess.get_file_as_string(BalancePresets.INDEX_PATH),
			"balance_index.gd 和 balance.gd 对不上，运行 godot_console --headless --path game --script res://tools/make_balance_index.gd 重新生成")
	var count := RegEx.create_from_string("(?m)^static var ").search_all(source).size()
	check(Replay.balance_values().size() == count and BalanceIndex.DOCS.size() == count, "每个数值都在目录里")
	check(BalanceIndex.DOCS["P_HAS_STAR"].begins_with("α") and BalanceIndex.DOCS["ACTION_BASE"].contains("行动点"),
			"说明取自同一行后面的注释，没有时取上一行的")


func test_rewrite_balance_source() -> void:
	var source := FileAccess.get_file_as_string(BalancePresets.BALANCE_PATH)
	var file := BalancePresets.file_values()
	var cost: Dictionary = file["TECH_COST"].duplicate(true)
	cost["grain"] = [21, 1]
	var values := {"P_HAS_STAR": 0.6, "STAR_WEIGHTS": [7, 2, 1], "TECH_COST": cost,
			"START_ENERGY": file["START_ENERGY"], "VISION_HOME": 3.0}
	var r := BalancePresets.rewrite_source(source, values)
	check(r["missing"].is_empty(), "每个名字都找得到")
	check(r["changed"].size() == 4 and not r["changed"].has("START_ENERGY"), "只改值不一样的（没变的不动）")
	var new_source: String = r["source"]
	check(new_source.contains("static var P_HAS_STAR := 0.6") and new_source.contains("# α"), "改了值，行尾注释还在")
	check(new_source.contains("static var STAR_WEIGHTS: Array[int] = [7, 2, 1]"), "类型标注留着")
	check(new_source.contains("static var VISION_HOME := 3.0"), "小数写成带小数点的")
	# 多行的字典重新排版后行数会变，所以只数数值行和注释行
	var count := func(text: String, prefix: String) -> int:
		return Array(text.split("\n")).filter(func(l): return l.begins_with(prefix)).size()
	check(count.call(new_source, "static var") == count.call(source, "static var")
			and count.call(new_source, "#") == count.call(source, "#"), "别的数值行和注释行一行没少")
	# 改过的源码能编译，读出来就是新值
	var fresh := GDScript.new()
	fresh.source_code = RegEx.create_from_string("(?m)^class_name .*$").sub(new_source, "")
	check(fresh.reload() == OK, "改过的 balance.gd 能编译")
	check(fresh.get("P_HAS_STAR") == 0.6 and fresh.get("TECH_COST")["grain"] == [21, 1], "编译后读到新的值")
	check(fresh.get("START_ENERGY") == file["START_ENERGY"], "没改的数值不变")
	check(BalancePresets.rewrite_source(source, {"NO_SUCH": 1})["missing"] == ["NO_SUCH"], "找不到的名字会报出来")
	check(BalancePresets.rewrite_source(source, {})["source"] == source, "什么都不改时源码原样不动")

# ---------- 仓库文件 ----------

## 拉取时放回本地改动冲突了，冲突标记没处理就提交进来（export_presets.cfg 出过两次）。
func test_no_conflict_markers() -> void:
	var bad: Array[String] = []
	_find_conflict_markers("res://", bad)
	check(bad.is_empty(), "这些文件里有没处理的合并冲突标记：%s" % ", ".join(bad))


func _find_conflict_markers(dir: String, bad: Array[String]) -> void:
	# 标记拼出来写，免得这个文件自己被查出来
	var markers := ["<".repeat(7) + " ", ">".repeat(7) + " ", "|".repeat(7) + " "]
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_find_conflict_markers(dir.path_join(sub), bad)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() not in ["gd", "cfg", "tscn", "tres", "godot"]:
			continue
		var path := dir.path_join(f)
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if markers.any(func(m): return line.begins_with(m)):
				bad.append(path)
				break


func test_replay_across_dimension_epochs() -> void:
	var s := GameState.new_game(71, 1)
	for civ in s.civs:
		s.set_autoplay(civ, false)
		s.dev_set(civ, "energy", 2000)
		s.dev_set(civ, "reduced", true)
		s.dev_set(civ, "line_reduced", true)
		s.dev_tech(civ, "dimension", true)
	var target := Vector3i(4, 4, 4)
	if s.human().owns(target):
		target.x += 1
	check(s.launch_foil(s.human(), target)["error"] == "", "通过正式行动触发可重放的展开")
	for i in 100:
		if s.all_flat():
			break
		s.end_turn()
	check(s.all_flat() and not s.is_over(), "首次换坐标后仍是可玩的对局")
	target = Vector3i(13, 13, s.flat_plane)
	check(s.launch_line_foil(s.human(), target)["error"] == "", "二维通过正式行动再次展开")
	for i in 200:
		if s.all_linear():
			break
		s.end_turn()
	check(s.all_linear(), "两次维度展开均完成")
	var replay := Replay.from_state(s)
	var again := replay.play_to(s.steps)
	check(replay.desync_step == -1 and again.checksum() == s.checksum(), "两次原子换图及新地图行动确定性重放")
	check(again.map.stars == s.map.stars and again.map.extent == s.map.extent, "重放恢复所有星系及地图边界")


func test_same_dimension_grain_still_works() -> void:
	var s := _two_dimensional_match()
	var enemy := s.civs[1]
	var shot := Ship.make(Ship.GRAIN, Vector3(enemy.home), 99)
	s._grain_hit(enemy.home, enemy, shot, s.human())
	check(not enemy.alive, "二维文明仍可用同维度常规武器交战，不会永久免疫光粒")


func test_unprepared_ship_entering_folded_column_dies() -> void:
	var s := _collapse_match()
	s.human().reduced = false
	s._unfold_foil(Vector3i(3, 0, 0))
	var ship := _ship(s, s.human(), Ship.PROBE, Vector3(2.9, 0, 4), Vector3.RIGHT)
	ship.speed = 0.5
	s._move_ship(s.human(), ship)
	check(ship.dead, "新进入已展开空间的未降维单位同样毁灭")


func test_unfold_keeps_incoming_projectiles_moving() -> void:
	var s := _collapse_match()
	var grain := Ship.make(Ship.GRAIN, Vector3(-2, 4, 4), 123)
	grain.docked = false
	grain.direction = Vector3.RIGHT
	s.hidden_ships.append(grain)
	_finish_flat(s)
	check(grain.direction != Vector3.ZERO and not grain.dead, "图外来袭换图后仍在飞行")
	var before := grain.pos
	s._move_ship(null, grain)
	check(grain.pos != before and not grain.dead, "新航向仍进入星图，不会卡死在边缘")


func test_light_diffusion_in_new_dimensions() -> void:
	var s := _two_dimensional_match()
	s._ensure_light()
	var center := Vector3i(13, 13, s.flat_plane)
	s.light[s._li(center)] = 0.0
	s._light_moving = true
	s._spread_light()
	check(is_equal_approx(s.light_at(center), 8.0 / 9.0), "二维光速按邻近 3×3 格扩散")
	check(s.light.size() == 729 and s.light_at(Vector3i(13, 13, s.flat_plane + 1)) == 1.0, "光速数组保留 729 格且图外读取安全")


func test_old_replay_is_rejected_explicitly() -> void:
	var path := Replay.DIR.path_join("_old-version.replay")
	DirAccess.make_dir_recursive_absolute(Replay.DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"version": 1, "seed": 71})
	file.close()
	check(Replay.load_file(path) == null, "旧 10³ 规则记录不能被新规则静默重算")
	DirAccess.remove_absolute(path)
