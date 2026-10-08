extends "res://tests/rules/rule_suite.gd"
## 全图压平以后：共同平面、二维、单向著、一维、奇异点和平局。


func _collapse_match() -> GameState:
	var s := _two_civs(Vector3i(9, 9, 9))
	for civ in s.civs:
		civ.reduced = true
		civ.energy = 1000
		_give(civ, ["dimension"])
	return s


## 规则：二向箔
func test_foils_share_one_plane() -> void:
	var s := _collapse_match()
	check(s.launch_foil(s.human(), Vector3i(1, 1, 1))["error"] == "", "第一片箔发射")
	check(s.launch_foil(s.civs[1], Vector3i(8, 8, 7))["error"] == "", "另一高度的箔发射")
	for i in 60:
		s.end_turn()
	check(s.all_flat(), "两片箔最终压平全图")
	check(s.flattened.values().all(func(z): return z == s.flat_plane), "每个格子都在同一个平面")
	check(s.civs.all(func(c): return c.home.z == s.flat_plane), "幸存文明也在共同平面")


## 规则：二向箔
func test_different_planes_are_not_fully_flat() -> void:
	var s := _collapse_match()
	for x in StarMap.SIZE:
		for y in StarMap.SIZE:
			for z in StarMap.SIZE:
				s.flattened[Vector3i(x, y, z)] = 2 if x < 5 else 7
	check(not s.all_flat(), "只数格子不够：不同高度不能算压成同一平面")


## 规则：灭亡和胜负
func test_collapse_finishes_after_combat_ends() -> void:
	var s := _collapse_match()
	s.civs[1].reduced = false
	s._unfold_foil(Vector3i(9, 9, 9))
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


## 规则：二维、单向著和奇异点
func test_line_foil_requires_two_dimensional_world() -> void:
	var s := _collapse_match()
	var energy := s.human().energy
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 3))["error"] != "", "三维地图不能发射单向著")
	check(s.human().energy == energy and s.human().foils.is_empty(), "拒绝的发射不花资源")
	s = _two_dimensional_match()
	check(s.all_flat(), "测试准备：全图压平")
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 8))["error"] != "", "单向著目标必须在现有平面")
	check(s.launch_foil(s.human(), Vector3i(3, 3, 4))["error"] != "", "二维后不能再发二向箔")


## 规则：自身降维
func test_second_self_reduction() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	check(s.start_reduce(me)["error"] == "", "二维地图可以再降一次")
	_turns(s, Balance.REDUCE_TURNS)
	check(me.line_reduced, "进入一维")
	check(s.start_reduce(me)["error"] != "", "不支持一维以下的自身降维")


## 规则：二维、单向著和奇异点，灭亡和胜负
func test_line_foils_converge_then_draw_after_grace() -> void:
	var s := _two_dimensional_match()
	for civ in s.civs:
		civ.line_reduced = true
	check(s.launch_line_foil(s.human(), Vector3i(2, 2, 4))["error"] == "", "第一片单向著")
	check(s.launch_line_foil(s.civs[1], Vector3i(7, 7, 4))["error"] == "", "另一 y 位置的单向著")
	for i in 60:
		if s.all_linear():
			break
		s.end_turn()
	check(s.all_linear() and s.linearized.values().all(func(y): return y == s.line_y), "全部格子归于同一条直线")
	check(s.civs.all(func(c): return c.alive and c.home.y == s.line_y), "幸存文明位于共同直线")
	check(not s.is_over(), "压成直线后不马上判平局")
	_turns(s, Balance.LINE_GRACE_TURNS + 1)
	check(s.winner == "平局", "过了 %d 回合没人完成奇异点，平局" % Balance.LINE_GRACE_TURNS)


## 规则：二维、单向著和奇异点
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
## 规则：预警系统，F5.3
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
## 规则：广播和隐藏文明，F5.3
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


## 规则：二维、单向著和奇异点
func test_line_attack_destroys_unprepared_civ() -> void:
	var s := _two_dimensional_match()
	s.human().line_reduced = true
	s._unfold_line_foil(Vector3i(9, 3, 4))
	check(not s.civs[1].alive and s.winner == "你", "只降到二维的对手不能抵挡单向著")
