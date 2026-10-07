extends "res://tests/rules/rule_suite.gd"
## 自身降维和三维里的二向箔：飞行、展开、压平、搬到平面上。


## 规则：二向箔
func test_foil_prepares_flies_and_unfolds() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
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
	check(s.map.star_at(Vector3i(1, 0, 2)) == StarMap.Star.NONE, "中心那一列所有高度都压平")
	check(not s.flattened.has(Vector3i(2, 0, 1)) and s.flattened.has(Vector3i(2, 0, 2)), "旁边一列：平面附近还留着")
	s.end_turn()
	check(s.flattened.has(Vector3i(2, 0, 1)) and not s.flattened.has(Vector3i(3, 0, 1)), "每回合向外扩散 0.9 格")


## 规则：二向箔，B7
func test_foil_unfolds_on_enemy_in_path() -> void:
	var s := _two_civs(Vector3i(1, 0, 0))
	var me := s.human()
	_give(me, ["dimension"])
	s.launch_foil(me, Vector3i(3, 0, 0))
	_turns(s, Balance.FOIL_PREPARE_TURNS + 5)
	check(s.flattened.has(Vector3i(1, 0, 0)), "途中碰到别人的星系，提前展开")
	check(not s.civs[1].alive and s.winner == "你", "没降维的文明被压平，灭亡")


## 规则：二向箔
func test_foil_bad_targets() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	_give(me, ["dimension"])
	check(s.launch_foil(me, Vector3i(10, 0, 0))["error"] != "", "目标必须在星图内")
	check(s.launch_foil(me, Vector3i.ZERO)["error"] != "", "目标不能是发射源")
	s.flattened[Vector3i(5, 5, 3)] = 0
	check(s.launch_foil(me, Vector3i(5, 5, 3))["error"] != "", "已经压平的格子不能当目标")
	me.energy = 0
	check(s.launch_foil(me, Vector3i(5, 5, 5))["error"] != "", "能量不足不能发射")


## 规则：二向箔，自身降维
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


## 规则：二向箔
func test_reduced_civ_moves_onto_plane() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	me.reduced = true
	_set_star(s, Vector3i.ZERO, StarMap.Star.DOUBLE)
	me.dysons[Vector3i.ZERO] = 1
	me.miners[Vector3i.ZERO] = 2
	me.grains[Vector3i.ZERO] = true
	ai.known[Vector3i.ZERO] = 1
	var w := _ship(s, me, Ship.WARSHIP, Vector3.ZERO)
	var flat := Vector3i(0, 0, 4)
	_flatten_whole_column(s, Vector2i(0, 0), 4)
	check(me.alive and me.home == flat and me.colonies == [flat], "母星被压到平面的高度上")
	check(s.map.star_at(flat) == StarMap.Star.DOUBLE and s.map.star_at(Vector3i.ZERO) == StarMap.Star.NONE, "恒星跟着走")
	check(me.dysons.get(flat, 0) == 1 and me.miners.get(flat, 0) == 2 and me.grains.has(flat), "设施跟着走")
	check(w.pos == Vector3(flat) and not w.dead, "停着的单位也跟着走")
	check(ai.known.has(flat) and not ai.known.has(Vector3i.ZERO), "知道这个星系的文明改记新坐标")


## 规则：二向箔
func test_reduced_systems_in_same_column_collide() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.reduced = true
	var upper := Vector3i(0, 0, 7)
	_set_star(s, upper, StarMap.Star.SINGLE)
	me.colonies.append(upper)
	var ss := _ship(s, me, Ship.STARSHIP, Vector3(0, 0, 3))
	ss.docked = false
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(me.alive and me.colonies == [Vector3i.ZERO], "压到同一格的第二个星系毁掉")
	check(not ss.dead and ss.pos == Vector3.ZERO, "降维文明的星舰也被压到平面上")


## 星系搬到平面上：别人记的情报跟着改坐标，宜居与否跟着搬来的星系；
## 和平面上的星系重叠而毁掉时，别人也不再记着这个坐标。
## 规则：二向箔
func test_moved_system_keeps_intel_consistent() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	me.reduced = true
	var flat := Vector3i(0, 0, 4)
	_set_habitable(s, flat, StarMap.Star.SINGLE)
	ai.known[Vector3i.ZERO] = 1
	ai.intel[Vector3i.ZERO] = s.snapshot(Vector3i.ZERO)
	_flatten_whole_column(s, Vector2i(0, 0), 4)
	check(me.home == flat and ai.intel.has(flat) and not ai.intel.has(Vector3i.ZERO), "情报跟着星系改坐标")
	check(not s.map.is_habitable(flat), "不宜居的星系盖住平面上的宜居星系后，那一格不再宜居")

	var s2 := _two_civs(Vector3i(9, 9, 9))
	var me2 := s2.human()
	me2.reduced = true
	var upper := Vector3i(0, 0, 7)
	_set_star(s2, upper, StarMap.Star.SINGLE)
	me2.colonies.append(upper)
	s2.civs[1].known[upper] = 1
	_flatten_whole_column(s2, Vector2i(0, 0), 0)
	check(not s2.civs[1].known.has(upper), "重叠毁掉的星系，别人也不再记着")


## 降维文明的星系压到平面上和别人的星系重叠而毁掉：停在那里的星舰也一起毁掉，不会留在别人的星系上。
## 规则：二向箔
func test_parked_starship_crushed_with_its_system() -> void:
	var s := _two_civs(Vector3i(0, 0, 7))
	var ai := s.civs[1]
	s.human().reduced = true  # 没降维的文明在平面上也会被抹掉，这里要它的星系留在平面上
	ai.reduced = true
	_ship(s, ai, Ship.STARSHIP, Vector3(0, 0, 7))
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(ai.colonies.is_empty() and not ai.has_starship(), "星系和停着的星舰一起毁掉")
	check(not ai.alive and s.human().alive, "什么都不剩的文明灭亡，平面上原来的星系留下")


## 停在空格子上的星舰被压到别人的星系上，或者别人的星系后来被压到星舰所在的格子：星舰都毁掉。
## 规则：二向箔
func test_parked_starship_crushed_onto_other_system() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	s.human().reduced = true
	ai.reduced = true
	var ss := _ship(s, ai, Ship.STARSHIP, Vector3(0, 0, 5))
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(ss.dead and ai.alive, "星舰压到别人的星系上就毁掉，文明还有星系，活着")

	var s2 := _two_civs(Vector3i(9, 9, 9))
	var me := s2.human()
	var ai2 := s2.civs[1]
	me.reduced = true
	ai2.reduced = true
	s2.map.stars.erase(Vector3i.ZERO)
	var home := Vector3i(0, 0, 6)
	_set_star(s2, home, StarMap.Star.SINGLE)
	me.colonies = [home]
	me.home = home
	var ss2 := _ship(s2, ai2, Ship.STARSHIP, Vector3(0, 0, 2))
	_flatten_whole_column(s2, Vector2i(0, 0), 0)
	check(me.owns(Vector3i.ZERO) and ss2.dead, "星舰先压过去、别人的星系后压过来，星舰也毁掉")


## 一片准备中的二向箔，发射的星系被搬到平面上：箔从新位置起飞。
## 规则：二向箔
func test_moved_system_moves_preparing_foil() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	me.reduced = true
	var f := Foil.new(Vector3.ZERO, Vector3i(5, 5, 5), 2)
	me.foils.append(f)
	_flatten_whole_column(s, Vector2i(0, 0), 4)
	check(f.origin == Vector3(0, 0, 4), "准备中的箔跟着星系搬走")


## 规则：二向箔，灭亡和胜负
func test_everyone_flattened_means_no_winner() -> void:
	var s := _two_civs(Vector3i(0, 0, 5))  # 和你在同一列
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(not s.human().alive and not s.civs[1].alive, "同一列的文明都被压平")
	check(s.winner == "无", "都灭亡了，没有赢家")


## 规则：二向箔
func test_flattening_destroys_ships_and_wakes() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ss := _ship(s, me, Ship.STARSHIP, Vector3(3, 3, 3))
	ss.docked = false
	s.wakes.append({"a": Vector3(3, 3, 3), "b": Vector3(3, 3, 4), "turn": 1, "gone": false})
	_flatten_whole_column(s, Vector2i(3, 3), 0)
	s._clean_dead()
	check(not me.has_starship(), "没降维的星舰被压平")
	check(s.wakes[0]["gone"], "航迹在降维时消失")


## 规则：灭亡和胜负
func test_foil_vanishes_when_launcher_dies() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.foils.append(Foil.new(Vector3(ai.home), Vector3i(9, 9, 9), 2))
	s._lose_system(ai.home, ai)
	check(ai.foils.is_empty(), "发射者灭亡，二向箔也消失")


## 规则：自身降维
func test_reduce_takes_turns_and_blocks_building() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
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


## 规则：自身降维
func test_reduce_waits_for_pending_buildings() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	_give(me, ["dimension"])
	s.build(me, "miner")
	var e := me.energy
	check(s.start_reduce(me)["error"] != "" and me.energy == e, "有没建好的设施时不能降维，也不花钱")
