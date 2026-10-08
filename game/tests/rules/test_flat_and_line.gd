extends "res://tests/rules/rule_suite.gd"
## 全图压平以后：共同平面、二维、单向著、一维、奇异点和平局。


## 规则：二向箔，U1
func test_foils_share_one_plane() -> void:
	var s := _collapse_match()
	check(s.launch_foil(s.human(), Vector3i(1, 1, 1))["error"] == "", "第一片箔发射")
	check(s.launch_foil(s.civs[1], Vector3i(8, 8, 7))["error"] == "", "另一高度的箔发射")
	for i in 180:
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
	s._unfold_foil(Vector3i(8, 8, 8))
	check(s.is_over() and s.collapse_pending(), "胜负已出，空间还在坍缩")
	var turn := s.turn
	var energy := s.human().energy
	for i in 30:
		s.end_turn()
	check(s.all_flat() and not s.collapse_pending(), "战斗结束后整张星图仍压成平面")
	check(s.turn == turn and s.human().energy == energy, "结束后不执行 AI、不产出、不增加回合")


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


## 二向箔改成只在目标展开（U2），单向著仍然在路上碰到别人的星系就展开。
## 规则：二维、单向著和奇异点，U2
func test_line_foil_still_unfolds_on_enemy_in_path() -> void:
	var s := _two_dimensional_match()
	var me := s.human()
	var enemy := s.civs[1].home
	# 从停在 AI 母星系左边一格的星舰发射，目标在 AI 母星系右边一格，正好穿过它
	var from := enemy - Vector3i(1, 0, 0)
	var target := enemy + Vector3i(1, 0, 0)
	check(s.map.contains(from) and s.map.contains(target), "测试准备：两格都在平面上")
	_ship(s, me, Ship.STARSHIP, Vector3(from))
	check(s.launch_line_foil(me, target, from)["error"] == "", "从星舰发射单向著")
	for i in Balance.FOIL_PREPARE_TURNS + 20:
		if s.line_y >= 0:
			break
		s.end_turn()
	check_eq(s.line_anchor, enemy, "单向著在路上碰到的别人的母星系展开")


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
	for i in 180:
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
	Balance.HIDDEN_STRIKE_CHANCE = 1.0
	Balance.HIDDEN_FOIL_CHANCE = 1.0
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


## 规则：二维、单向著和奇异点
func test_line_attack_destroys_unprepared_civ() -> void:
	var s := _two_dimensional_match()
	s.human().line_reduced = true
	s._unfold_line_foil(s.civs[1].home)
	check(not s.civs[1].alive and s.winner == "你", "只降到二维的对手不能抵挡单向著")


## 规则：二向箔，二维、单向著和奇异点
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


## 规则：二向箔，二维、单向著和奇异点
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


## 规则：二向箔，二维、单向著和奇异点
func test_same_column_enemy_assets_do_not_collide() -> void:
	var s := _two_civs(Vector3i(0, 0, 7))
	for civ in s.civs:
		civ.reduced = true
		_ship(s, civ, Ship.STARSHIP, Vector3(civ.home))
	_finish_flat(s)
	check(s.civs.all(func(c): return c.alive and c.has_starship()), "同列敌对星系和停靠星舰不会覆盖")
	check(s.civs[0].home != s.civs[1].home, "两个文明获得不同二维坐标")


## 规则：二向箔，二维、单向著和奇异点
func test_same_dimension_grain_still_works() -> void:
	var s := _two_dimensional_match()
	var enemy := s.civs[1]
	var shot := Ship.make(Ship.GRAIN, Vector3(enemy.home), 99)
	s._grain_hit(enemy.home, enemy, shot, s.human())
	check(not enemy.alive, "二维文明仍可用同维度常规武器交战，不会永久免疫光粒")


## 规则：二向箔，二维、单向著和奇异点
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
	s.set_light_at(upper, 0.25)
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


## 规则：二向箔，二维、单向著和奇异点
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


## 规则：二向箔，二维、单向著和奇异点
func test_unprepared_ship_entering_folded_column_dies() -> void:
	var s := _collapse_match()
	s.human().reduced = false
	s._unfold_foil(Vector3i(3, 0, 0))
	var ship := _ship(s, s.human(), Ship.PROBE, Vector3(2.9, 0, 4), Vector3.RIGHT)
	ship.speed = 0.5
	s._move_ship(s.human(), ship)
	check(ship.dead, "新进入已展开空间的未降维单位同样毁灭")


func _finish_flat(s: GameState, anchor := Vector3i(4, 4, 4)) -> void:
	s._unfold_foil(anchor)
	for i in 40:
		if s.all_flat():
			break
		s._spread_flat()
