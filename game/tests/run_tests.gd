extends SceneTree
## 规则测试，不打开窗口：
##   godot --headless --path game --script res://tests/run_tests.gd
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


func test_habitable_only_with_star() -> void:
	var m := StarMap.generate(3)
	for c in m.habitable:
		check(m.star_at(c) != StarMap.Star.NONE, "宜居格子 %s 必须有星系" % c)


## 空星图上手动放星系，方便控制测试条件。
func _map_with(cells: Dictionary) -> StarMap:
	var m := StarMap.new()
	for c in cells:
		m.stars[c] = cells[c]
	return m


## 两个文明：「你」在 (0,0,0)，「AI」在给定位置。
func _two_civs(ai_home: Vector3i) -> GameState:
	var s := GameState.new()
	s.map = _map_with({Vector3i.ZERO: StarMap.Star.SINGLE, ai_home: StarMap.Star.SINGLE})
	s.civs.append(Civ.new("你", false, Vector3i.ZERO))
	s.civs.append(Civ.new("AI", true, ai_home))
	for civ in s.civs:
		# 大部分测试和光粒、广播有关，默认已经建好恒星广播器
		civ.has_broadcaster = true
		s.start_turn(civ)
	return s


func test_civ_strength_follows_star_total() -> void:
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(5, 5, 5)
	var m := _map_with({a: StarMap.Star.SINGLE, b: StarMap.Star.TRIPLE})
	var civ := Civ.new("测试", false, a)
	check(civ.star_total(m) == 1, "单星母星有 1 颗恒星")
	check(civ.energy_per_turn(m) == 3, "单星母星每回合 3 能量")
	check(civ.action_points(m) == 5, "单星母星 5 个行动点")
	civ.colonies.append(b)
	check(civ.star_total(m) == 4, "再加一个三星系统共 4 颗恒星")
	check(civ.energy_per_turn(m) == 8, "能量随恒星增加：3 + 5")
	check(civ.action_points(m) == 2, "行动点随恒星减少，最少 2")
	check(civ.dyson_limit(m) == 4, "戴森球上限等于恒星总数")
	check(civ.mineral_per_turn(m) == 4, "每个星系 2 矿石")


func test_new_game_places_civs() -> void:
	var s := GameState.new_game(5)
	check(s.civs.size() == 1 + Balance.AI_COUNT, "一个人类加 %d 个 AI" % Balance.AI_COUNT)
	var homes := {}
	for civ in s.civs:
		check(s.map.star_at(civ.home) != StarMap.Star.NONE, "%s 的母星必须有星系" % civ.name)
		check(civ.actions_left == civ.action_points(s.map), "%s 开局行动点已发放" % civ.name)
		homes[civ.home] = true
	check(homes.size() == s.civs.size(), "母星不能重叠")
	var again := GameState.new_game(5)
	check(again.human().home == s.human().home, "同一个种子，母星位置相同")


func test_cone_basic_shape() -> void:
	var o := Vector3i(0, 0, 0)
	var cells := Geometry.cone_cells(o, Vector3(1, 0, 0), 3.0, 15.0)
	check(cells.has(Vector3i(1, 0, 0)), "正前方 1 格在圆锥内")
	check(cells.has(Vector3i(3, 0, 0)), "正前方 3 格在圆锥内")
	check(not cells.has(Vector3i(4, 0, 0)), "超出长度的格子不在圆锥内")
	check(not cells.has(o), "起点自己不算")
	check(not cells.has(Vector3i(0, 3, 0)), "侧面 90 度的格子不在圆锥内")
	check(Geometry.cone_cells(o, Vector3.ZERO, 3.0, 15.0).is_empty(), "没有方向时什么都不覆盖")


func test_cone_wider_and_longer_covers_more() -> void:
	var o := Vector3i(5, 5, 5)
	var base := Geometry.cone_cells(o, Vector3(1, 1, 0), 3.0, 15.0).size()
	var wide := Geometry.cone_cells(o, Vector3(1, 1, 0), 3.0, 60.0).size()
	var long := Geometry.cone_cells(o, Vector3(1, 1, 0), 6.0, 15.0).size()
	check(wide > base, "望远镜升级（张角变大）覆盖更多格子")
	check(long > base, "探测器升级（长度变长）覆盖更多格子")


func test_cone_points_backwards() -> void:
	var cells := Geometry.cone_cells(Vector3i(5, 5, 5), Vector3(-1, 0, 0), 3.0, 15.0)
	check(cells.has(Vector3i(3, 5, 5)), "反方向也能探测")
	check(not cells.has(Vector3i(6, 5, 5)), "背后的格子不在圆锥内")


func test_scout_finds_enemy_and_costs() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	var energy := me.energy
	var actions := me.actions_left
	var r := s.scout(me, Vector3(1, 0, 0))
	check(r["error"] == "", "探测应成功")
	check(r["found"] == [Vector3i(3, 0, 0)], "应发现 (3,0,0) 的 AI")
	check(me.known.has(Vector3i(3, 0, 0)), "发现的坐标记入已知")
	check(me.energy == energy - Balance.COST_SCOUT, "消耗探测能量")
	check(me.actions_left == actions - 1, "消耗一个行动点")
	var again := s.scout(me, Vector3(1, 0, 0))
	check(again["found"].is_empty(), "已知的坐标不重复报告")


func test_scout_misses_wrong_direction() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var r := s.scout(s.human(), Vector3(0, 1, 0))
	check(r["error"] == "" and r["found"].is_empty(), "方向不对就发现不了")


func test_scout_refuses_bad_requests() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	check(s.scout(me, Vector3(1, 0, 0), Vector3i(3, 0, 0))["error"] != "", "不能从别人的星系发射")
	check(s.scout(me, Vector3.ZERO)["error"] != "", "必须有方向")
	me.energy = 0
	check(s.scout(me, Vector3(1, 0, 0))["error"] != "", "能量不足时不能探测")
	me.energy = 100
	me.actions_left = 0
	check(s.scout(me, Vector3(1, 0, 0))["error"] != "", "行动点不足时不能探测")


func test_end_turn_pays_income() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	me.actions_left = 0
	var energy := me.energy
	s.end_turn()
	check(s.turn == 2, "进入第 2 回合")
	check(me.energy == energy + me.energy_per_turn(s.map), "回合结束发放能量")
	check(me.actions_left == me.action_points(s.map), "新回合重置行动点")


func test_cylinder_shape_and_order() -> void:
	var o := Vector3i(0, 5, 5)
	var cells := Geometry.cylinder_cells(o, Vector3(1, 0, 0), 5.0, 0.0)
	check(cells == [Vector3i(1, 5, 5), Vector3i(2, 5, 5), Vector3i(3, 5, 5),
			Vector3i(4, 5, 5), Vector3i(5, 5, 5)], "半径 0 时只覆盖中轴线上的格子，由近到远")
	var wide := Geometry.cylinder_cells(o, Vector3(1, 0, 0), 5.0, 1.0)
	check(wide.has(Vector3i(3, 6, 5)), "半径 1 时覆盖旁边一格")
	check(wide.size() > cells.size(), "半径越大覆盖越多")
	check(not wide.has(Vector3i(6, 5, 5)), "超出长度的格子不在圆柱内")


## 在 _two_civs 的基础上，把 AI 的母星改成指定的星系类型。
func _set_star(s: GameState, c: Vector3i, star: int) -> void:
	s.map.stars[c] = star


func test_lightgrain_hit_removes_one_star() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_set_star(s, target, StarMap.Star.TRIPLE)
	var me := s.human()
	me.energy = 100
	var r := s.lightgrain(me, Vector3(1, 0, 0))
	check(r["error"] == "" and r["hit"], "光粒应打中")
	check(r["cell"] == target, "打中的是 (3,0,0)")
	check(s.map.star_at(target) == StarMap.Star.DOUBLE, "三星变双星")
	check(me.record_hits.has(target), "打中的格子记进敌情记录图")
	check(me.record_empty.has(Vector3i(1, 0, 0)), "途经的空格子记为空")
	check(me.energy == 100 - Balance.COST_LIGHTGRAIN, "消耗光粒能量")
	check(s.civs[1].alive, "还剩恒星，文明还活着")


func test_lightgrain_miss_records_and_clears_stale_known() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	me.energy = 100
	me.known[Vector3i(0, 2, 0)] = true  # 过时的情报
	var r := s.lightgrain(me, Vector3(0, 1, 0))
	check(r["error"] == "" and not r["hit"], "方向上没有敌人，应没打中")
	check(me.record_empty.has(Vector3i(0, 2, 0)), "途经的格子记为空")
	check(not me.known.has(Vector3i(0, 2, 0)), "过时的已知坐标被清掉")


func test_lightgrain_hits_only_nearest_and_skips_own() -> void:
	var s := _two_civs(Vector3i(4, 0, 0))
	var me := s.human()
	me.energy = 100
	var mine := Vector3i(2, 0, 0)
	_set_star(s, mine, StarMap.Star.SINGLE)
	me.colonies.append(mine)
	var far_civ := Civ.new("远处", true, Vector3i(5, 0, 0))
	_set_star(s, far_civ.home, StarMap.Star.SINGLE)
	s.civs.append(far_civ)
	s.lightgrain(me, Vector3(1, 0, 0))
	check(s.map.star_at(mine) == StarMap.Star.SINGLE, "自己的星系被穿过，不受影响")
	check(s.map.star_at(Vector3i(4, 0, 0)) == StarMap.Star.NONE, "最近的敌方星系被打中")
	check(s.map.star_at(far_civ.home) == StarMap.Star.SINGLE, "后面的敌方星系不受影响")


func test_last_star_kills_and_wins() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	me.energy = 100
	s.lightgrain(me, Vector3(1, 0, 0))
	var ai := s.civs[1]
	check(not ai.alive, "单星星系被打掉，唯一的星系没了，文明灭亡")
	check(ai.colonies.is_empty(), "星系从 AI 名下移除")
	check(not me.known.has(Vector3i(3, 0, 0)), "已灭的坐标从已知中移除")
	check(s.winner == "你", "所有 AI 灭亡，你胜利")
	check(s.lightgrain(me, Vector3(1, 0, 0))["error"] != "", "游戏结束后不能再行动")


func test_home_moves_when_lost() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	var other := Vector3i(9, 9, 9)
	_set_star(s, other, StarMap.Star.SINGLE)
	ai.colonies.append(other)
	s.human().energy = 100
	s.lightgrain(s.human(), Vector3(1, 0, 0))
	check(ai.alive, "还有别的星系，文明不灭亡")
	check(ai.home == other, "母星改为剩下的星系")


func test_ai_strikes_known_target() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	_set_star(s, Vector3i.ZERO, StarMap.Star.DOUBLE)
	var ai := s.civs[1]
	ai.energy = 100
	ai.known[Vector3i.ZERO] = true
	s.end_turn()
	check(s.map.star_at(Vector3i.ZERO) < StarMap.Star.DOUBLE, "AI 用光粒打已知的你")


func test_ai_scouts_without_targets() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	var energy := ai.energy
	var income := ai.energy_per_turn(s.map)
	s.end_turn()
	check(ai.energy < energy + income, "AI 没有目标时会花能量探测")


func test_upgrades_take_effect_next_turn() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	var angle := me.cone_angle
	var length := me.scout_range
	check(s.upgrade(me, "telescope")["error"] == "", "可以升级望远镜")
	check(s.upgrade(me, "probe")["error"] == "", "可以升级探测器")
	check(s.upgrade(me, "probe")["error"] != "", "同一项不能在一回合里重复升级")
	check(me.cone_angle == angle and me.scout_range == length, "当回合还没生效")
	check(me.energy == Balance.START_ENERGY - Balance.COST_TELESCOPE, "望远镜花能量")
	check(me.mineral == Balance.START_MINERAL - Balance.COST_PROBE, "探测器花矿石")
	s.end_turn()
	check(me.cone_angle == angle + Balance.TELESCOPE_STEP, "下一回合张角变大")
	check(me.scout_range == length + Balance.PROBE_STEP, "下一回合探测变远")
	check(me.pending_upgrades.is_empty(), "生效后清空待升级列表")


func test_upgrades_respect_limits() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	me.cone_angle = Balance.MAX_CONE_ANGLE
	check(s.upgrade(me, "telescope")["error"] != "", "张角到上限后不能再升级")
	me.mineral = 0
	check(s.upgrade(me, "probe")["error"] != "", "矿石不足不能升级探测器")
	check(s.upgrade(me, "warp")["error"] != "", "未知的升级会被拒绝")


func test_ai_ignores_targets_out_of_range() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.energy = 100
	ai.known[Vector3i.ZERO] = true  # 距离约 15.6，超过光粒射程
	s.end_turn()
	check(s.map.star_at(Vector3i.ZERO) == StarMap.Star.SINGLE, "射程外的目标不打")


func test_warship_flies_and_hits() -> void:
	var target := Vector3i(5, 0, 0)
	var s := _two_civs(target)
	_set_star(s, target, StarMap.Star.DOUBLE)
	var me := s.human()
	_idle_ai(s)
	var r := s.launch_warship(me, Vector3(1, 0, 0))
	check(r["error"] == "", "可以派出战舰")
	check(me.energy == Balance.START_ENERGY - Balance.COST_WARSHIP_ENERGY, "花能量")
	check(me.mineral == Balance.START_MINERAL - Balance.COST_WARSHIP_MINERAL, "花矿石")
	s.end_turn()
	check(me.warships.size() == 1, "第 1 回合还在飞")
	check(me.warships[0].position().is_equal_approx(Vector3(2, 0, 0)), "每回合前进 2 格")
	check(me.record_empty.has(Vector3i(1, 0, 0)), "经过的空格子记进敌情记录图")
	s.end_turn()
	s.end_turn()
	check(s.map.star_at(target) == StarMap.Star.SINGLE, "第 3 回合到达，双星变单星")
	check(me.warships.is_empty(), "攻击后战舰消耗掉")
	check(me.known.has(target), "打中的坐标记入已知")


func test_warship_checks_every_cell_on_diagonal() -> void:
	# 斜着飞时，每回合飞过的格子都要检查，不能跳过
	var target := Vector3i(1, 1, 1)
	var s := _two_civs(target)
	s.civs[1].energy = 0
	s.launch_warship(s.human(), Vector3(1, 1, 1))
	s.end_turn()
	check(not s.civs[1].alive, "斜线上第一个格子的敌人被打中")


func test_warship_leaves_map() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	s.civs[1].energy = 0
	var me := s.human()
	s.launch_warship(me, Vector3(0, 0, -1))
	s.end_turn()
	check(me.warships.is_empty(), "飞出星图的战舰消失")


func test_warship_needs_mineral() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	s.human().mineral = 0
	check(s.launch_warship(s.human(), Vector3(1, 0, 0))["error"] != "", "矿石不足不能派战舰")


func test_ai_sends_warship_to_far_target() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.known[Vector3i.ZERO] = true  # 超出光粒射程
	s.end_turn()
	check(ai.warships.size() == 1, "射程外的目标，AI 派战舰过去")


func test_warning_blocks_one_strike() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	var me := s.human()
	var ai := s.civs[1]
	ai.energy = Balance.COST_WARNING  # 只够造预警系统
	check(s.upgrade(ai, "warning")["error"] == "", "可以建造预警系统")
	check(not ai.has_warning, "当回合还没生效")
	check(s.upgrade(ai, "warning")["error"] != "", "不能同时造两个")
	me.actions_left = 0
	s.end_turn()
	check(ai.has_warning, "下一回合生效")
	me.energy = 100
	var r := s.lightgrain(me, Vector3(1, 0, 0))
	check(r["hit"] and s.map.star_at(target) == StarMap.Star.SINGLE, "第一次打击被抵消，恒星不变")
	check(not ai.has_warning, "预警系统用掉了")
	check(me.known.has(target), "攻击方仍然知道打中了这个坐标")
	s.lightgrain(me, Vector3(1, 0, 0))
	check(not ai.alive, "第二次打击正常生效")


func test_warning_blocks_warship() -> void:
	var target := Vector3i(2, 0, 0)
	var s := _two_civs(target)
	var ai := s.civs[1]
	ai.has_warning = true
	ai.energy = 0
	ai.mineral = 0
	s.launch_warship(s.human(), Vector3(1, 0, 0))
	s.end_turn()
	check(ai.alive and not ai.has_warning, "战舰的打击也会被抵消")
	check(s.human().warships.is_empty(), "被抵消的战舰也消耗掉")


func test_cannot_build_warning_when_already_have_one() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var me := s.human()
	me.has_warning = true
	check(s.upgrade(me, "warning")["error"] != "", "已有预警系统时不能再造")


func test_long_ai_game_terminates() -> void:
	var s := GameState.new_game(11)
	for i in 300:
		s.end_turn()
		if s.is_over():
			break
	check(s.turn > 1, "AI 回合能正常推进")


func test_bounds() -> void:
	check(StarMap.in_bounds(Vector3i(0, 0, 0)), "原点在图内")
	check(StarMap.in_bounds(Vector3i(9, 9, 9)), "(9,9,9) 在图内")
	check(not StarMap.in_bounds(Vector3i(10, 0, 0)), "(10,0,0) 在图外")
	check(not StarMap.in_bounds(Vector3i(0, -1, 0)), "(0,-1,0) 在图外")


## 在星图上放一个宜居星系。
func _set_habitable(s: GameState, c: Vector3i, star: int) -> void:
	s.map.stars[c] = star
	s.map.habitable[c] = true


func test_colony_ship_settles_first_free_habitable() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	s.civs[1].energy = 0
	_set_star(s, Vector3i(1, 0, 0), StarMap.Star.SINGLE)  # 有星系但不宜居，飞过
	_set_habitable(s, Vector3i(3, 0, 0), StarMap.Star.DOUBLE)
	_set_habitable(s, Vector3i(4, 0, 0), StarMap.Star.SINGLE)
	var r := s.launch_colony_ship(me, Vector3(1, 0, 0))
	check(r["error"] == "", "可以派出殖民船")
	check(me.energy == Balance.START_ENERGY - Balance.COST_COLONY_ENERGY, "花能量")
	check(me.mineral == Balance.START_MINERAL - Balance.COST_COLONY_MINERAL, "花矿石")
	s.end_turn()
	check(me.colony_ships.size() == 1 and me.colonies.size() == 1, "第 1 回合飞到 2，还没到")
	s.end_turn()
	check(me.colonies.has(Vector3i(3, 0, 0)), "第 2 回合停在第一个宜居星系")
	check(not me.colonies.has(Vector3i(4, 0, 0)), "只殖民一个")
	check(me.colony_ships.is_empty(), "殖民后殖民船用掉")
	check(me.star_total(s.map) == 3, "恒星总数加上新殖民地的 2 颗")
	check(me.home == Vector3i.ZERO, "母星不变")


func test_colony_ship_passes_owned_system() -> void:
	var enemy_home := Vector3i(2, 0, 0)
	var s := _two_civs(enemy_home)
	s.map.habitable[enemy_home] = true
	s.civs[1].energy = 0
	_set_habitable(s, Vector3i(3, 0, 0), StarMap.Star.SINGLE)
	var me := s.human()
	s.launch_colony_ship(me, Vector3(1, 0, 0))
	s.end_turn()
	s.end_turn()
	check(s.civs[1].owns(enemy_home), "别人的星系不会被占")
	check(me.colonies.has(Vector3i(3, 0, 0)), "飞过去，停在后面的无主星系")
	check(not me.known.has(enemy_home), "飞过别人的星系不会暴露它")


func test_colony_ship_lost_outside_map() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	s.civs[1].energy = 0
	var me := s.human()
	s.launch_colony_ship(me, Vector3(0, 0, -1))
	s.end_turn()
	check(me.colony_ships.is_empty() and me.colonies.size() == 1, "飞出星图的殖民船消失")


func test_new_colony_is_launch_source() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	s.civs[1].energy = 0
	var col := Vector3i(2, 0, 0)
	_set_habitable(s, col, StarMap.Star.SINGLE)
	var me := s.human()
	s.launch_colony_ship(me, Vector3(1, 0, 0))
	s.end_turn()
	check(s.scout(me, Vector3(0, 1, 0), col)["error"] == "", "新殖民地可以作为发射源")


func test_colony_ships_vanish_when_civ_dies() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.colony_ships.append(Ship.new(ai.home, Vector3(0, 1, 0)))
	s.human().energy = 100
	s.lightgrain(s.human(), Vector3(1, 0, 0))
	check(not ai.alive and ai.colony_ships.is_empty(), "文明灭亡，殖民船也消失")


func test_ai_colonizes_and_does_not_retry() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.has_warning = true  # 跳过建造预警系统这一步
	var target := Vector3i(9, 9, 6)
	_set_habitable(s, target, StarMap.Star.SINGLE)
	s.human().actions_left = 0
	s.end_turn()
	check(ai.colony_ships.size() == 1, "AI 朝宜居星系派殖民船")
	s.end_turn()
	s.end_turn()
	check(ai.owns(target), "AI 殖民成功")
	check(ai.colony_tried.has(target), "记下派过的目标")

## 让 AI 什么都做不了，不干扰测试。
func _idle_ai(s: GameState) -> void:
	s.civs[1].energy = 0
	s.civs[1].mineral = 0


func test_foil_prepares_then_flies_and_unfolds() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	var target := Vector3i(3, 0, 0)
	_set_star(s, Vector3i(3, 0, 2), StarMap.Star.DOUBLE)  # 同一列、别的高度
	check(s.launch_foil(me, target)["error"] == "", "可以发射二向箔")
	check(me.energy == 100 - Balance.COST_FOIL, "花能量")
	s.end_turn()
	s.end_turn()
	check(me.foils[0].prepare_left == 0 and me.foils[0].traveled == 0.0, "准备 2 回合后才起飞")
	s.end_turn()
	s.end_turn()
	check(s.flattened.is_empty(), "飞了 2 格，还没到")
	s.end_turn()
	check(me.foils.is_empty(), "到达目标后用掉")
	check(s.flattened.get(target) == 0, "目标被压平，平面高度是目标的 z")
	check(s.map.star_at(Vector3i(3, 0, 2)) == StarMap.Star.NONE, "中心那一列所有高度都压平")
	check(not s.flattened.has(Vector3i(4, 0, 0)) and not s.flattened.has(Vector3i(4, 0, 1)), "旁边一列：平面附近还留着")
	check(s.flattened.has(Vector3i(4, 0, 2)), "旁边一列：离平面远的被压没")
	check(not s.flattened.has(Vector3i(5, 0, 4)) and s.flattened.has(Vector3i(5, 0, 5)), "越往外留下的空间越厚")
	s.end_turn()
	check(s.flattened.has(Vector3i(4, 0, 1)) and s.flattened.has(Vector3i(2, 0, 0)), "下一回合，完全压平的圆半径加 1")
	check(not s.flattened.has(Vector3i(5, 0, 1)) and s.flattened.has(Vector3i(5, 0, 2)), "外面一列变得和原来旁边那列一样扁")


func test_foil_unfolds_on_enemy_in_path() -> void:
	var s := _two_civs(Vector3i(2, 0, 0))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	s.launch_foil(me, Vector3i(6, 0, 0))
	for i in 4:
		s.end_turn()
	check(s.flattened.has(Vector3i(2, 0, 0)), "途中碰到别人的星系，提前展开")
	check(not s.civs[1].alive and s.winner == "你", "没降维的文明被压平，灭亡")


func test_foil_bad_targets() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.energy = 100
	check(s.launch_foil(me, Vector3i(10, 0, 0))["error"] != "", "目标必须在星图内")
	check(s.launch_foil(me, Vector3i.ZERO)["error"] != "", "目标不能是发射源")
	me.colonies.append(Vector3i(1, 1, 1))
	check(s.launch_foil(me, Vector3i(1, 1, 1))["error"] != "", "目标不能是自己的星系")
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
	check(not s.civs[1].alive, "扩散两回合，没降维的 AI 灭亡")
	check(s.winner == "你", "你胜利")


func test_reduced_civ_moves_onto_plane() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	me.reduced = true
	_set_star(s, Vector3i.ZERO, StarMap.Star.DOUBLE)
	me.dysons[Vector3i.ZERO] = 1
	me.miners[Vector3i.ZERO] = true
	ai.known[Vector3i.ZERO] = true
	var flat := Vector3i(0, 0, 4)
	_flatten_whole_column(s, Vector2i(0, 0), 4)
	check(me.alive and me.home == flat and me.colonies == [flat], "母星被压到平面的高度上")
	check(s.map.star_at(flat) == StarMap.Star.DOUBLE and s.map.star_at(Vector3i.ZERO) == StarMap.Star.NONE, "恒星跟着走")
	check(me.dysons.get(flat, 0) == 1 and me.miners.has(flat), "戴森球和采矿船跟着走")
	check(ai.known.has(flat) and not ai.known.has(Vector3i.ZERO), "知道这个星系的文明改记新坐标")


func test_reduced_systems_in_same_column_collide() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.reduced = true
	var upper := Vector3i(0, 0, 7)
	_set_star(s, upper, StarMap.Star.SINGLE)
	me.colonies.append(upper)
	me.has_starship = true
	me.starship = Vector3i(0, 0, 3)
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(me.alive and me.colonies == [Vector3i.ZERO], "压到同一格的第二个星系毁掉")
	check(me.has_starship and me.starship == Vector3i.ZERO, "降维文明的星舰也被压到平面上")


func test_everyone_flattened_means_no_winner() -> void:
	var s := _two_civs(Vector3i(0, 0, 5))  # 和你在同一列
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(not s.human().alive and not s.civs[1].alive, "同一列的文明都被压平")
	check(s.winner == "无", "都灭亡了，没有赢家")


## 把一整列压平到高度 plane（先压平面那一格，再压其他高度），测试用。
func _flatten_whole_column(s: GameState, col: Vector2i, plane: int) -> void:
	s._flatten_cell(Vector3i(col.x, col.y, plane), plane)
	for z in StarMap.SIZE:
		s._flatten_cell(Vector3i(col.x, col.y, z), plane)


func test_foil_vanishes_when_launcher_dies() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.foils.append(Foil.new(ai.home, Vector3i(9, 9, 9), 2))
	s.human().energy = 100
	s.lightgrain(s.human(), Vector3(1, 0, 0))
	check(ai.foils.is_empty(), "发射者灭亡，二向箔也消失")


func test_reduce_takes_turns_and_blocks_building() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.has_broadcaster = false
	var income := me.energy_per_turn(s.map)
	check(me.reduce_cost() == Balance.COST_REDUCE_BASE + Balance.COST_REDUCE_PER_UNIT, "一个星系，按一个单位收费")
	check(s.start_reduce(me)["error"] == "", "可以开始降维")
	check(s.launch_warship(me, Vector3(1, 0, 0))["error"] != "", "降维期间不能派战舰")
	check(s.upgrade(me, "probe")["error"] != "", "降维期间不能升级")
	check(s.launch_foil(me, Vector3i(5, 5, 5))["error"] != "", "降维期间不能发射二向箔")
	check(s.scout(me, Vector3(1, 0, 0))["error"] == "", "降维期间可以探测")
	for i in Balance.REDUCE_TURNS - 1:
		s.end_turn()
	check(not me.reduced, "还没完成")
	s.end_turn()
	check(me.reduced and me.reduce_left == 0, "%d 回合后完成" % Balance.REDUCE_TURNS)
	check(me.energy_per_turn(s.map) == income / 2, "降维后能量减半")
	check(s.start_reduce(me)["error"] != "", "不能再降维")


func test_reduce_counts_completed_equipment_and_facilities() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.has_broadcaster = false
	me.energy = 1000
	me.mineral = 1000
	me.actions_left = 30
	_set_star(s, me.home, StarMap.Star.TRIPLE)
	s.map.gas[me.home] = 1
	for kind in ["telescope", "probe", "warning", "antimatter", "broadcaster", "gravity"]:
		check(s.upgrade(me, kind)["error"] == "", "可下单：" + kind)
	check(s.build_dyson(me)["error"] == "", "可下单戴森球")
	check(s.build_miner(me)["error"] == "", "可下单采矿船")
	check(s.build_bunker(me)["error"] == "", "可下单掩体")
	check(s.build_starship(me)["error"] == "", "可下单星舰")
	check(me.reduce_units() == 1, "未完成订单不算已建造单位")
	s.end_turn()
	check(me.reduce_units() == 11, "星系和十个建成单位全部计费")
	check(me.reduce_cost() == Balance.COST_REDUCE_BASE + 11 * Balance.COST_REDUCE_PER_UNIT, "建成后费用正确上涨")
	me.warships.append(Ship.new(me.home, Vector3.RIGHT))
	me.colony_ships.append(Ship.new(me.home, Vector3.UP))
	check(me.reduce_units() == 13, "两种在飞飞船各计一次")
	me.actions_left = 10
	check(s.upgrade(me, "telescope")["error"] == "", "可再次升级望远镜")
	check(s.upgrade(me, "probe")["error"] == "", "可再次升级探测器")
	check(s.upgrade(me, "antimatter")["error"] == "", "可追加反物质")
	s.end_turn()
	check(me.reduce_units() == 16, "重复升级设备和库存反物质按数量累计")
	me.has_warning = false
	me.antimatter -= 1
	me.dysons[me.home] = 0
	check(me.reduce_units() == 13, "消耗预警和反物质、损失戴森球后不再计费")
	var energy := me.energy
	check(s.start_reduce(me)["error"] == "", "完整设施文明可以降维")
	check(me.energy == energy - Balance.COST_REDUCE_BASE - 13 * Balance.COST_REDUCE_PER_UNIT, "实际扣费包含建成设施")


func test_reduce_waits_for_every_construction_queue() -> void:
	for kind in ["telescope", "probe", "warning", "antimatter", "broadcaster", "gravity", "dyson", "miner", "bunker", "starship"]:
		var s := _two_civs(Vector3i(9, 9, 9))
		_idle_ai(s)
		var me := s.human()
		me.has_broadcaster = false
		me.energy = 1000
		me.mineral = 1000
		s.map.gas[me.home] = 1
		var result: Dictionary
		match kind:
			"dyson": result = s.build_dyson(me)
			"miner": result = s.build_miner(me)
			"bunker": result = s.build_bunker(me)
			"starship": result = s.build_starship(me)
			_: result = s.upgrade(me, kind)
		check(result["error"] == "", kind + " 下单成功")
		var energy := me.energy
		var ap := me.actions_left
		check(s.start_reduce(me)["error"] == "请先完成建造和升级，再开始降维", kind + " 完成前不能降维")
		check(me.energy == energy and me.actions_left == ap and me.reduce_left == 0, "拒绝启动没有副作用")
		s.end_turn()
		check(not me.has_pending_construction() and me.reduce_units() == 2, "订单完成后纳入携带计数")
		check(s.start_reduce(me)["error"] == "", kind + " 完成后可以降维")


func test_reduce_rejections_do_not_charge_and_only_charge_once() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.dysons[me.home] = 1
	var cost := me.reduce_cost()
	me.energy = cost - 1
	var ap := me.actions_left
	check(s.start_reduce(me)["error"] == "能量不足", "设施加入费用后不足一能量也不能启动")
	check(me.energy == cost - 1 and me.actions_left == ap and me.reduce_left == 0, "不足资源不扣费")
	me.energy = cost
	me.actions_left = 0
	check(s.start_reduce(me)["error"] == "行动点不足" and me.energy == cost, "不足行动点不扣费")
	me.actions_left = ap
	check(s.start_reduce(me)["error"] == "" and me.energy == 0, "恰好够费用可以启动")
	check(me.actions_left == ap - 1, "启动只扣一个行动点")
	check(s.start_reduce(me)["error"] == "正在降维" and me.actions_left == ap - 1, "重复启动不重复收费")
	for i in Balance.REDUCE_TURNS:
		s.end_turn()
	check(me.reduced and me.energy >= 0, "后续回合不再扣降维费用")


func test_reduce_blocks_all_construction_without_spending() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.energy = 1000
	me.mineral = 1000
	me.has_starship = true
	me.starship = Vector3i(2, 0, 0)
	_set_star(s, me.starship, StarMap.Star.SINGLE)
	s.map.habitable[me.starship] = true
	check(s.start_reduce(me)["error"] == "", "开始降维")
	var energy := me.energy
	var mineral := me.mineral
	var ap := me.actions_left
	for kind in ["telescope", "probe", "warning", "antimatter", "broadcaster", "gravity"]:
		check(s.upgrade(me, kind)["error"] == "降维期间不能建造", "禁止升级和建造：" + kind)
	for result in [s.build_dyson(me), s.build_miner(me), s.build_bunker(me), s.build_starship(me),
			s.launch_warship(me, Vector3.RIGHT), s.launch_colony_ship(me, Vector3.RIGHT),
			s.launch_foil(me, Vector3i(3, 3, 3)), s.launch_black_domain(me, Vector3i(1, 1, 1))]:
		check(result["error"] != "", "禁止新增设施、飞船和空间武器")
	check(s.settle_starship(me)["error"] == "降维期间不能建立星系", "准备中禁止星舰定居")
	check(me.energy == energy and me.mineral == mineral and me.actions_left == ap, "所有被禁止操作都不扣资源")
	check(not me.has_pending_construction(), "没有产生建造订单")
	for i in Balance.REDUCE_TURNS - 1:
		s.end_turn()
		check(not me.reduced and me.reduce_left == Balance.REDUCE_TURNS - i - 1, "每回合仅推进一步")
	s.end_turn()
	check(me.reduced and s.build_miner(me)["error"] == "", "完成后恢复建造")


func test_lightgrain_no_effect_on_reduced() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	s.civs[1].reduced = true
	s.human().energy = 100
	var r := s.lightgrain(s.human(), Vector3(1, 0, 0))
	check(r["hit"] and s.civs[1].alive, "光粒打中已降维的文明，但没有效果")
	check(s.map.star_at(Vector3i(3, 0, 0)) == StarMap.Star.SINGLE, "恒星不变")


func test_ai_reduces_when_flattening_near() -> void:
	var s := _two_civs(Vector3i(9, 9, 0))
	var ai := s.civs[1]
	ai.energy = 100
	s.human().actions_left = 0
	s.foil_zones.append({"center": Vector3i(7, 7, 0), "age": 0})
	check(s.turns_until_flat(Vector3i(9, 9, 0)) <= Balance.AI_REDUCE_ALERT, "再过几回合就压到 AI 的母星")
	s.end_turn()
	check(ai.reduce_left > 0 or ai.reduced, "压平的区域靠近时，AI 开始降维")

func test_dyson_built_next_turn_and_adds_energy() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	_set_star(s, Vector3i.ZERO, StarMap.Star.DOUBLE)
	var income := me.energy_per_turn(s.map)
	check(s.build_dyson(me)["error"] == "", "可以在母星建戴森球")
	check(me.mineral == Balance.START_MINERAL - Balance.COST_DYSON, "花矿石")
	check(me.dyson_count() == 0, "当回合还没建好")
	s.end_turn()
	check(me.dyson_count() == 1, "下一回合建好")
	check(me.energy_per_turn(s.map) == income + Balance.DYSON_ENERGY, "每个戴森球多产能量")


func test_dyson_limited_by_stars_in_system() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.mineral = 100
	check(s.build_dyson(me)["error"] == "", "单星母星可以建 1 个")
	check(s.build_dyson(me)["error"] != "", "已下单的也算，不能超过恒星数")
	check(s.build_dyson(me, Vector3i(9, 9, 9))["error"] != "", "不能建在别人的星系")


func test_dyson_lost_with_star() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_set_star(s, target, StarMap.Star.DOUBLE)
	var ai := s.civs[1]
	ai.dysons[target] = 2
	s.human().energy = 100
	s.lightgrain(s.human(), Vector3(1, 0, 0))
	check(ai.dysons[target] == 1, "少一颗恒星，少一个戴森球")


func test_no_dyson_while_reducing() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.reduce_left = 2
	check(s.build_dyson(me)["error"] != "", "降维期间不能建戴森球")

func test_antimatter_stops_warship_not_lightgrain() -> void:
	var target := Vector3i(2, 0, 0)
	var s := _two_civs(target)
	_set_star(s, target, StarMap.Star.DOUBLE)
	var ai := s.civs[1]
	_idle_ai(s)
	ai.antimatter = 1
	ai.has_warning = true
	var me := s.human()
	me.energy = 100
	s.launch_warship(me, Vector3(1, 0, 0))
	s.end_turn()
	check(ai.antimatter == 0 and ai.has_warning, "战舰先被反物质拦下，预警系统还在")
	check(s.map.star_at(target) == StarMap.Star.DOUBLE and me.warships.is_empty(), "没有损失，战舰没了")
	check(me.known.has(target), "攻击方知道这里有人")
	s.lightgrain(me, Vector3(1, 0, 0))
	check(not ai.has_warning, "光粒不受反物质影响，由预警系统抵消")


func test_antimatter_stock_limit() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	me.mineral = 100
	check(s.upgrade(me, "antimatter")["error"] == "", "可以造反物质")
	check(me.energy == 100 - Balance.COST_ANTIMATTER_ENERGY and me.mineral == 100 - Balance.COST_ANTIMATTER_MINERAL, "花能量和矿石")
	s.end_turn()
	check(me.antimatter == 1, "下一回合生效")
	me.antimatter = Balance.MAX_ANTIMATTER
	check(s.upgrade(me, "antimatter")["error"] != "", "存满后不能再造")

func test_black_domain_prepares_then_blocks_lightgrain() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	check(s.launch_black_domain(me, target)["error"] == "", "可以投放黑域")
	check(me.energy == 100 - Balance.COST_BLACK_DOMAIN, "花能量")
	check(not s.in_black_domain(target), "准备期间还没生效")
	for i in Balance.BLACK_DOMAIN_PREPARE_TURNS:
		s.end_turn()
	check(s.in_black_domain(target) and s.in_black_domain(Vector3i(2, 1, 1)), "生效后中心周围一圈都在黑域里")
	check(not s.in_black_domain(Vector3i(1, 0, 0)), "外面不在")
	me.energy = 100
	var r := s.lightgrain(me, Vector3(1, 0, 0))
	check(not r["hit"] and s.map.star_at(target) == StarMap.Star.SINGLE, "光粒进不去黑域")


func test_black_domain_traps_ships_and_hides_scouting() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	s.black_domains.append(target)
	var me := s.human()
	me.energy = 100
	s.scout(me, Vector3(1, 0, 0))
	check(not me.known.has(target), "探测看不到黑域里面")
	s.launch_warship(me, Vector3(1, 0, 0))
	for i in 4:
		s.end_turn()
	check(me.warships.is_empty() and s.map.star_at(target) == StarMap.Star.SINGLE, "战舰被困住，打不到里面")
	var ai := s.civs[1]
	ai.energy = 100
	var r := s.lightgrain(ai, Vector3(-1, 0, 0))
	check(not r["hit"] and s.map.star_at(Vector3i.ZERO) == StarMap.Star.SINGLE, "里面的光粒也出不来")


func test_black_domain_out_of_range_and_flattened() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	check(s.launch_black_domain(me, Vector3i(9, 0, 0))["error"] != "", "超出探测长度不能投放")
	s.black_domains.append(Vector3i(4, 0, 0))
	s._flatten_cell(Vector3i(6, 0, 2), 0)
	check(s.black_domains.size() == 1, "压平的格子碰不到黑域时，黑域还在")
	s._flatten_cell(Vector3i(5, 1, 1), 0)
	check(s.black_domains.is_empty(), "压平经过的地方黑域消失")


func test_ai_hides_in_black_domain_after_hit() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.has_warning = true
	ai.times_hit = 1
	ai.energy = Balance.COST_BLACK_DOMAIN
	ai.mineral = 0
	s._ai_turn(ai)
	check(ai.pending_domains.size() == 1 and ai.pending_domains[0]["center"] == ai.home, "被打过的 AI 在母星投放黑域")

func test_broadcast_publishes_coordinate() -> void:
	var target := Vector3i(5, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	var third := Civ.new("AI-2", true, Vector3i(9, 9, 9))
	_set_star(s, third.home, StarMap.Star.SINGLE)
	s.civs.append(third)
	var me := s.human()
	me.energy = 100
	check(s.broadcast(me, me.home)["error"] != "", "不能广播自己的坐标")
	check(s.broadcast(me, target)["error"] == "", "可以广播任意坐标")
	check(me.energy == 100 - Balance.COST_BROADCAST, "花能量")
	s.end_turn()
	check(not third.known.has(target), "准备期间还没公开")
	s.end_turn()
	check(third.known.has(target) and me.known.has(target), "公开后所有其他文明都知道这个坐标")
	check(not s.civs[1].known.has(target), "主人自己不算")


func test_hidden_civ_strikes_broadcast_target() -> void:
	var target := Vector3i(5, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	_set_star(s, target, StarMap.Star.DOUBLE)
	s.hidden.append(target + Vector3i(0, 1, 0))  # 紧挨着，出手概率接近上限
	var old := Balance.HIDDEN_STRIKE_CHANCE
	var old_foil := Balance.HIDDEN_FOIL_CHANCE
	Balance.HIDDEN_STRIKE_CHANCE = 2.0  # 保证出手
	Balance.HIDDEN_FOIL_CHANCE = 0.0
	var me := s.human()
	me.energy = 100
	s.broadcast(me, target)
	for i in Balance.BROADCAST_PREPARE_TURNS:
		s.end_turn()
	check(s.hidden_strikes.size() == 1, "附近的隐藏文明出手")
	for i in Balance.HIDDEN_STRIKE_DELAY:
		s.end_turn()
	check(s.map.star_at(target) == StarMap.Star.SINGLE, "隐藏文明的光粒打掉一颗恒星")
	check(s.hidden_strikes.is_empty(), "打完就没了")
	Balance.HIDDEN_STRIKE_CHANCE = old
	Balance.HIDDEN_FOIL_CHANCE = old_foil


func test_hidden_civ_far_away_does_nothing() -> void:
	var target := Vector3i(0, 0, 9)
	var s := _two_civs(target)
	_idle_ai(s)
	s.hidden.append(Vector3i(9, 9, 0))
	var me := s.human()
	me.energy = 100
	s.broadcast(me, target)
	for i in Balance.BROADCAST_PREPARE_TURNS:
		s.end_turn()
	check(s.hidden_strikes.is_empty(), "太远的隐藏文明听不到")

func test_ai_reduces_then_launches_foil() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.has_warning = true
	ai.mineral = 0
	ai.known[Vector3i.ZERO] = true
	ai.energy = Balance.AI_FOIL_ENERGY - 1
	check(not s._try_foil(ai), "能量不够时不动")
	ai.energy = maxi(Balance.AI_FOIL_ENERGY, ai.reduce_cost() + Balance.COST_FOIL)
	check(s._try_foil(ai) and ai.reduce_left > 0, "先开始降维")
	ai.reduce_left = 0
	ai.reduced = true
	ai.energy = 100
	check(s._try_foil(ai) and ai.foils.size() == 1, "降维后发射二向箔")
	check(ai.foils[0].target == Vector3i.ZERO, "目标是已知的敌人")
	check(not s._try_foil(ai), "同时最多一片")

func test_miner_built_next_turn_and_adds_minerals() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	var before := me.mineral_per_turn(s.map)
	check(s.build_miner(me)["error"] == "", "可以在母星建采矿船")
	check(me.mineral == Balance.START_MINERAL - Balance.COST_MINER, "花矿石")
	check(s.build_miner(me)["error"] != "", "每个星系最多一艘")
	check(me.mineral_per_turn(s.map) == before, "下一回合才建好")
	s.end_turn()
	check(me.miners.has(me.home), "建好了")
	check(me.mineral_per_turn(s.map) == before + Balance.MINER_MINERAL, "每回合多产矿石")
	check(s.build_miner(me, Vector3i(9, 9, 9))["error"] != "", "只能建在自己的星系")


func test_miner_lost_with_system() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var colony := Vector3i(1, 0, 0)
	_set_star(s, colony, StarMap.Star.SINGLE)
	me.colonies.append(colony)
	me.miners[colony] = true
	s._lose_system(colony, me)
	check(not me.miners.has(colony), "星系丢了，采矿船也没了")

func test_lightgrain_needs_broadcaster() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	var me := s.human()
	me.has_broadcaster = false
	me.energy = 100
	check(s.lightgrain(me, Vector3(1, 0, 0))["error"] != "", "没有恒星广播器不能发光粒")
	check(me.energy == 100, "不花能量")
	check(s.upgrade(me, "broadcaster")["error"] == "", "可以建恒星广播器")
	check(me.energy == 100 - Balance.COST_BROADCASTER, "花能量")
	check(s.lightgrain(me, Vector3(1, 0, 0))["error"] != "", "当回合还没建好")
	s.end_turn()
	me.energy = 100
	check(s.lightgrain(me, Vector3(1, 0, 0))["hit"], "建好后可以发光粒")
	check(s.upgrade(me, "broadcaster")["error"] != "", "已经有了不能再建")


func test_broadcast_needs_broadcaster_or_gravity() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	_idle_ai(s)
	var me := s.human()
	me.has_broadcaster = false
	me.energy = 100
	me.mineral = 100
	check(s.broadcast(me, Vector3i(5, 0, 0))["error"] != "", "两样都没有不能广播")
	check(s.upgrade(me, "gravity")["error"] == "", "可以建引力波发射器")
	check(me.energy == 100 - Balance.COST_GRAVITY_ENERGY and me.mineral == 100 - Balance.COST_GRAVITY_MINERAL, "花能量和矿石")
	s.end_turn()
	me.energy = 100
	check(s.broadcast(me, Vector3i(5, 0, 0))["error"] == "", "有引力波发射器就能广播")
	check(s.lightgrain(me, Vector3(1, 0, 0))["error"] != "", "引力波发射器不能用来发光粒")


func test_ai_builds_broadcaster_before_lightgrain() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.has_broadcaster = false
	ai.has_warning = true
	ai.known[Vector3i.ZERO] = true
	ai.energy = Balance.COST_BROADCASTER
	ai.mineral = 0
	s._ai_turn(ai)
	check(ai.pending_upgrades.has("broadcaster"), "射程内有目标时先建恒星广播器")
	check(s.map.star_at(Vector3i.ZERO) == StarMap.Star.SINGLE, "还没打")


func test_starship_built_next_turn_and_moves() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	me.mineral = 100
	check(s.build_starship(me)["error"] == "", "可以在母星建星舰")
	check(me.energy == 100 - Balance.COST_STARSHIP_ENERGY and me.mineral == 100 - Balance.COST_STARSHIP_MINERAL, "花能量和矿石")
	check(s.build_starship(me)["error"] != "", "最多一艘")
	check(not me.has_starship, "当回合还没建好")
	s.end_turn()
	check(me.has_starship and me.starship == me.home, "下一回合在母星建好")
	me.energy = 100
	var r := s.move_starship(me, Vector3(1, 0, 0))
	check(r["error"] == "" and me.starship == Vector3i(4, 0, 0), "沿方向最远移动 4 格")
	check(me.energy == 100 - Balance.COST_STARSHIP_MOVE, "移动花能量")
	check(me.home == Vector3i.ZERO, "还有星系时母星不变")


func test_starship_keeps_civ_alive() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.has_starship = true
	me.starship = Vector3i(0, 3, 0)
	s._lose_system(me.home, me)
	check(me.alive, "星系丢光了，还有星舰就活着")
	check(me.home == me.starship, "星舰成为发射源")
	check(me.energy_per_turn(s.map) == Balance.STARSHIP_ENERGY and me.mineral_per_turn(s.map) == Balance.STARSHIP_MINERAL, "只剩星舰时收入很少")
	check(me.action_points(s.map) == Balance.ACTION_MIN, "行动点最少")
	me.energy = 100
	me.mineral = 100
	check(s.upgrade(me, "warning")["error"] != "", "只剩星舰时不能建造")
	check(s.scout(me, Vector3(1, 0, 0))["error"] == "", "可以从星舰探测")


func test_starship_settles_habitable_system() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	var spot := Vector3i(0, 2, 0)
	_set_habitable(s, spot, StarMap.Star.DOUBLE)
	me.has_starship = true
	me.starship = Vector3i(0, 4, 0)
	s._lose_system(me.home, me)
	check(s.settle_starship(me)["error"] != "", "不在宜居星系上不能定居")
	me.energy = 100
	s.move_starship(me, Vector3(0, -1, 0), 2.0)
	check(me.starship == spot, "可以只移动到指定距离")
	check(s.settle_starship(me)["error"] == "", "在无主的宜居星系上可以定居")
	check(me.colonies == [spot] and me.home == spot and not me.has_starship, "成为新的母星，星舰用掉")


func test_starship_hidden_from_lightgrain_but_not_warship() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	var ai := s.civs[1]
	ai.has_starship = true
	ai.starship = Vector3i(2, 0, 0)
	me.energy = 100
	me.mineral = 100
	check(s.scout(me, Vector3(1, 0, 0))["found"].is_empty(), "探测发现不了星舰")
	s.lightgrain(me, Vector3(1, 0, 0))
	check(ai.has_starship, "光粒打不到星舰")
	s._lose_system(ai.home, ai)
	check(ai.alive, "AI 只剩星舰")
	ai.actions_left = 0
	s.launch_warship(me, Vector3(1, 0, 0))
	s.end_turn()
	check(not ai.has_starship and not ai.alive, "战舰撞毁星舰，只剩星舰的文明灭亡")


func test_flattening_destroys_starship() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.has_starship = true
	ai.starship = Vector3i(5, 5, 2)
	s._flatten_cell(Vector3i(5, 5, 2), 0)
	check(not ai.has_starship and ai.alive, "压平那一格的星舰被毁，还有星系就还活着")


func test_starship_cannot_leave_black_domain() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	_idle_ai(s)
	var me := s.human()
	me.has_starship = true
	me.starship = Vector3i(0, 0, 0)
	s.black_domains.append(Vector3i(0, 0, 0))
	me.energy = 100
	s.move_starship(me, Vector3(1, 0, 0))
	check(me.starship == Vector3i(1, 0, 0), "只能在黑域里移动，出不去")


func test_map_generation_follows_planet_rules() -> void:
	var m := StarMap.generate(7)
	var counts := [0, 0, 0, 0]
	for c in m.stars:
		counts[m.stars[c]] += 1
		if m.stars[c] == StarMap.Star.NONE:
			check(not m.rocky.has(c) and not m.habitable.has(c), "空格子没有行星")
			continue
		var planets: int = m.rocky[c] + m.gas[c]
		check(planets <= Balance.MAX_PLANETS[m.stars[c] - 1], "行星数不超过上限")
		if m.habitable.has(c):
			check(m.rocky[c] > 0, "宜居的星系至少有一颗类地行星")
	check(counts[1] > counts[2] and counts[2] > counts[3], "单星最多，双星其次，三星最少")
	check(not m.habitable.is_empty(), "有宜居星系")
	var again := StarMap.generate(7)
	check(again.stars == m.stars and again.gas == m.gas, "同一个种子生成的星图一样")


func test_bunker_keeps_system_after_last_star() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_idle_ai(s)
	var ai := s.civs[1]
	var me := s.human()
	s.map.gas[Vector3i.ZERO] = 0
	check(s.build_bunker(me)["error"] != "", "没有类木行星不能建掩体")
	s.map.gas[target] = 1
	ai.energy = 100
	ai.mineral = 100
	check(s.build_bunker(ai, target)["error"] == "", "有类木行星可以建掩体")
	check(s.build_bunker(ai, target)["error"] != "", "每个星系一个")
	ai.actions_left = 0
	s.end_turn()
	check(ai.bunkers.has(target), "下一回合建好")
	_idle_ai(s)
	ai.has_warning = false
	ai.antimatter = 0
	me.energy = 100
	s.lightgrain(me, Vector3(1, 0, 0))
	check(s.map.star_at(target) == StarMap.Star.NONE, "光粒照样打爆恒星")
	check(ai.alive and ai.owns(target), "人躲在掩体里，星系没丢")
	s.lightgrain(me, Vector3(1, 0, 0))
	check(ai.alive and ai.owns(target), "没有恒星了，再打光粒也没东西可毁")
	s.launch_warship(me, Vector3(1, 0, 0))
	for i in 3:
		s.end_turn()
	check(not ai.alive, "战舰照样能打")


func test_foil_cannot_target_flattened_cell() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.energy = 100
	s.flattened[Vector3i(5, 5, 3)] = 0
	check(s.launch_foil(me, Vector3i(5, 5, 3))["error"] != "", "已经压平的格子不能当目标")
	check(s.launch_foil(me, Vector3i(5, 5, 6))["error"] == "", "同一列还没压平的格子可以")
	var ai := s.civs[1]
	ai.reduced = true
	ai.energy = 100
	ai.known[Vector3i(5, 5, 3)] = true
	check(not s._try_foil(ai), "AI 不朝已经压平的格子发射二向箔")


func test_whole_map_flat_continues_in_two_dimensions() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	for civ in s.civs:
		civ.reduced = true
	for x in StarMap.SIZE:
		for y in StarMap.SIZE:
			for z in StarMap.SIZE:
				if Vector2i(x, y) != Vector2i(9, 9):
					s.flattened[Vector3i(x, y, z)] = 0
	check(not s.is_over(), "还有一列没压平，对局继续")
	_flatten_whole_column(s, Vector2i(9, 9), 0)
	check(not s.is_over() and s.human().alive and s.civs[1].alive, "二维地图继续游戏，不自动判平局")

func test_bunker_costs_a_star_in_multi_star_system() -> void:
	var target := Vector3i(3, 0, 0)
	var s := _two_civs(target)
	_set_star(s, target, StarMap.Star.DOUBLE)
	var ai := s.civs[1]
	ai.bunkers[target] = true
	var me := s.human()
	me.energy = 100
	s.lightgrain(me, Vector3(1, 0, 0))
	check(s.map.star_at(target) == StarMap.Star.SINGLE, "双星系统丢一颗恒星")


func test_black_domain_wall_between_civs() -> void:
	var s := _two_civs(Vector3i(4, 0, 0))
	_idle_ai(s)
	var me := s.human()
	me.energy = 100
	me.scout_range = 6.0
	s.black_domains.append(Vector3i(2, 0, 3))  # 挡在中间：x 1～3、z 2～4，不挡 z=0 那条线
	check(not s.blocked(Vector3i.ZERO, Vector3i(4, 0, 0)), "黑域不在路线上，不挡")
	s.black_domains[0] = Vector3i(2, 0, 1)  # 挡在 (0,0,0) 和 (4,0,0) 正中间
	check(s.blocked(Vector3i.ZERO, Vector3i(4, 0, 0)), "两边都在黑域外，但路线穿过黑域，挡住")
	var r := s.scout(me, Vector3(1, 0, 0))
	check(r["found"].is_empty(), "探测看不到墙后面")
	var hit := s.lightgrain(me, Vector3(1, 0, 0))
	check(not hit["hit"] and s.civs[1].alive, "光粒穿不过墙")
	_set_habitable(s, Vector3i(4, 4, 0), StarMap.Star.SINGLE)
	me.colonies.append(Vector3i(4, 4, 0))
	check(not s.blocked(Vector3i(4, 4, 0), Vector3i(4, 0, 0)), "从别的殖民地出发可以绕开")

func _collapse_match() -> GameState:
	var s := _two_civs(Vector3i(9, 9, 9))
	for civ in s.civs:
		civ.is_ai = false
		civ.reduced = true
		civ.energy = 1000
	return s


func test_foils_share_one_plane() -> void:
	var s := _collapse_match()
	check(s.launch_foil(s.human(), Vector3i(2, 2, 2))["error"] == "", "第一片箔发射")
	check(s.launch_foil(s.civs[1], Vector3i(7, 7, 7))["error"] == "", "另一高度的箔发射")
	for i in 30:
		s.end_turn()
	check(s.all_flat(), "两片箔最终压平全图")
	check(s.flattened.values().all(func(z): return z == s.flat_plane), "每个格子都在同一个平面")
	check(s.civs.all(func(c): return c.home.z == s.flat_plane), "幸存文明也在共同平面")
	check(s.civs.all(func(c): return c.foils.is_empty()), "展开的箔被消耗")


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
	check(s.launch_foil(s.human(), s.civs[1].home)["error"] == "", "向最后一个对手发射")
	for i in 30:
		if s.is_over():
			break
		s.end_turn()
	check(s.is_over() and s.collapse_pending(), "胜负已出，空间还在坍缩")
	check(s.flattened.size() > 1, "致命打击当次扩散完整结算，不能只处理一个格子")
	var turn := s.turn
	var energy := s.human().energy
	for i in 20:
		s.end_turn()
	check(s.all_flat() and not s.collapse_pending(), "战斗结束后整张星图仍压成平面")
	check(s.turn == turn and s.human().energy == energy, "结束后不执行 AI、不产出、不增加回合")


func _two_dimensional_match() -> GameState:
	var s := _collapse_match()
	s._unfold_foil(Vector3i(4, 4, 4))
	for i in 15:
		if s.all_flat():
			break
		s.end_turn()
	return s


func test_line_foil_requires_two_dimensional_world() -> void:
	var s := _collapse_match()
	var energy := s.human().energy
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 3))["error"] != "", "三维地图不能发射单向箔")
	check(s.human().energy == energy and s.human().foils.is_empty(), "拒绝的发射不花资源")
	s = _two_dimensional_match()
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 8))["error"] != "", "单向箔目标必须在现有平面")
	check(s.launch_foil(s.human(), Vector3i(3, 3, 4))["error"] != "", "二维后不能再发二向箔")


func test_second_self_reduction_takes_time_and_reduces_income() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	var energy := me.energy
	var income := me.energy_per_turn(s.map)
	check(s.start_reduce(me)["error"] == "", "二维地图可以准备一维生存")
	check(me.energy == energy - me.reduce_cost(), "第二次降维按单位数收费")
	check(s.launch_line_foil(me, Vector3i(3, 3, 4))["error"] != "", "准备降维期间不能发射单向箔")
	for i in Balance.REDUCE_TURNS - 1:
		s.end_turn()
	check(not me.line_reduced, "不能提前完成一维生存准备")
	s.end_turn()
	check(me.reduced and me.line_reduced, "三回合后进入一维生存状态")
	check(me.energy_per_turn(s.map) == int(income / 2.0), "再次降维产出再减半")
	check(s.start_reduce(me)["error"] != "", "不支持一维以下的自身降维")


func test_line_foil_prepares_flies_and_consumes() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	me.line_reduced = true
	var energy := me.energy
	check(s.launch_line_foil(me, Vector3i(3, 0, 4))["error"] == "", "单向箔可以发射")
	check(me.energy == energy - Balance.COST_LINE_FOIL, "单向箔扣除正确成本")
	for i in Balance.FOIL_PREPARE_TURNS:
		s.end_turn()
	check(me.foils.size() == 1 and me.foils[0].traveled == 0, "准备期间不飞行")
	for i in 2:
		s.end_turn()
	check(s.linearized.is_empty(), "飞行未到目标时不展开")
	s.end_turn()
	check(me.foils.is_empty() and not s.linearized.is_empty(), "到达后消耗单向箔并开始压缩")


func test_multiple_line_foils_converge_on_one_line() -> void:
	var s := _two_dimensional_match()
	for civ in s.civs:
		civ.line_reduced = true
	check(s.launch_line_foil(s.human(), Vector3i(2, 2, 4))["error"] == "", "第一片单向箔")
	check(s.launch_line_foil(s.civs[1], Vector3i(7, 7, 4))["error"] == "", "另一 y 位置的单向箔")
	for i in 30:
		s.end_turn()
	check(s.all_linear() and s.linearized.size() == 100, "整个二维地图压缩完成")
	check(s.linearized.values().all(func(y): return y == s.line_y), "全部格子归于同一条直线")
	check(s.civs.all(func(c): return c.alive and c.home.y == s.line_y and c.home.z == s.flat_plane), "幸存文明位于共同直线")
	check(s.winner == "平局", "一维完成后多个幸存文明才判平局")
	var remaining := 0
	for x in StarMap.SIZE:
		for y in StarMap.SIZE:
			for z in StarMap.SIZE:
				if s.cell_exists(Vector3i(x, y, z)):
					remaining += 1
	check(remaining == StarMap.SIZE, "空间只剩沿 x 轴的十个格子")


func test_line_attack_destroys_unprepared_civ_and_keeps_spreading() -> void:
	var s := _two_dimensional_match()
	s.human().line_reduced = true
	s._unfold_line_foil(Vector3i(9, 3, 4))
	check(not s.civs[1].alive and s.winner == "你", "只降到二维的对手不能抵挡单向箔")
	check(s.collapse_pending(), "对手灭亡后直线坍缩还未完成")
	for i in 15:
		s.end_turn()
	check(s.all_linear() and s.human().alive, "胜负结束后完成直线坍缩，已准备的文明活着")


func test_line_relocation_preserves_system_facilities_and_knowledge() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	me.line_reduced = true
	me.dysons[me.home] = 1
	me.miners[me.home] = true
	s.civs[1].known[me.home] = true
	me.has_starship = true
	me.starship = Vector3i(1, 0, 4)
	s._unfold_line_foil(Vector3i(0, 3, 4))
	check(me.home == Vector3i(0, 3, 4), "星系从平面搬到直线")
	check(me.dysons.get(me.home, 0) == 1 and me.miners.has(me.home), "设施跟随星系")
	check(s.civs[1].known.has(me.home) and not s.civs[1].known.has(Vector3i(0, 0, 4)), "情报跟随新位置")
	check(me.starship == Vector3i(1, 3, 4), "已准备的星舰也压到直线上")


func test_two_dimensional_starship_movement_and_directions() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	me.has_starship = true
	me.starship = me.home
	check(s.move_starship(me, Vector3(1, 0, 5))["error"] == "", "二维中星舰仍可以移动")
	check(me.starship.z == s.flat_plane, "星舰不能离开二维平面")
	check(s.launch_warship(me, Vector3(1, 1, 5))["error"] == "", "二维中仍可以派战舰")
	check(me.warships[0].direction.z == 0.0, "飞行方向限于现有维度")
	check(s.launch_warship(me, Vector3(0, 0, 1))["error"] != "", "纯粹指向消失维度的方向无效")


func test_ai_prepares_for_one_dimension_and_uses_line_foil() -> void:
	var s := _two_dimensional_match()
	var ai := s.civs[1]
	ai.known[s.human().home] = true
	check(s._try_foil(ai) and ai.reduce_left > 0, "二维 AI 先准备一维生存")
	for i in Balance.REDUCE_TURNS:
		s.end_turn()
	check(ai.line_reduced and s._try_foil(ai), "准备完成后 AI 发射单向箔")
	check(ai.foils.size() == 1 and ai.foils[0].to_line, "AI 选择正确级别的箔")


func test_line_collision_and_ships_share_collapse_rules() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	me.line_reduced = true
	var other := Vector3i(0, 6, 4)
	_set_star(s, other, StarMap.Star.SINGLE)
	me.colonies.append(other)
	me.warships.append(Ship.new(Vector3i(1, 0, 4), Vector3(1, 1, 0)))
	s._unfold_line_foil(Vector3i(0, 3, 4))
	check(me.colonies.size() == 1, "同一 x 的两个星系压到同一位置时不能重叠")
	check(me.warships.size() == 1 and me.warships[0].position().y == 3, "降维飞船的实际坐标跟随压缩")
	check(me.warships[0].direction.y == 0, "压成直线后飞船只能沿线飞行")


func test_two_dimensional_black_domain_rejected_without_charge() -> void:
	var s := _two_dimensional_match()
	var energy := s.human().energy
	check(s.launch_black_domain(s.human(), s.human().home)["error"] != "", "二维里不能投放注定无法形成的黑域")
	check(s.human().energy == energy and s.human().pending_domains.is_empty(), "无效黑域不消耗资源")


func test_prepared_ship_survives_when_its_direction_disappears() -> void:
	var s := _collapse_match()
	var me := s.human()
	me.warships.append(Ship.new(Vector3i(0, 0, 5), Vector3(0, 0, 1)))
	s._unfold_foil(Vector3i.ZERO)
	check(me.warships.size() == 1, "已降维的飞船不会因为失去航向而被摧毁")
	check(me.warships[0].position().z == 0 and me.warships[0].direction.is_zero_approx(), "失去的方向归零，飞船留在平面上")


func test_post_game_line_collapse_preserves_player_defeat() -> void:
	var s := _two_dimensional_match()
	var third := Civ.new("Other-2", false, Vector3i(5, 5, s.flat_plane))
	third.reduced = true
	third.line_reduced = true
	s.map.stars[third.home] = StarMap.Star.SINGLE
	s.civs.append(third)
	s.civs[1].line_reduced = true
	s._unfold_line_foil(Vector3i(0, 3, s.flat_plane))
	check(s.winner == "AI" and not s.human().alive, "玩家未准备一维生存则失败")
	for i in 15:
		s.end_turn()
	check(s.all_linear() and s.winner == "AI", "剩余两个对手进入一维也不能把玩家失败改成平局")
