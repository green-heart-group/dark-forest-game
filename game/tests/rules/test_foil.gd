extends "res://tests/rules/rule_suite.gd"
## 自身降维和三维里的二向箔：飞行、展开、压平、搬到平面上。


## 规则：二向箔
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
	var s := _two_civs(Vector3i(8, 8, 8))
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


## 规则：二向箔，灭亡和胜负
func test_everyone_flattened_means_no_winner() -> void:
	var s := _two_civs(Vector3i(0, 0, 5))  # 和你在同一列
	_flatten_whole_column(s, Vector2i(0, 0), 0)
	check(not s.human().alive and not s.civs[1].alive, "同一列的文明都被压平")
	check(s.winner == "无", "都灭亡了，没有赢家")


## 规则：二向箔
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


## 规则：灭亡和胜负
func test_foil_vanishes_when_launcher_dies() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	ai.foils.append(Foil.new(Vector3(ai.home), Vector3i(8, 8, 8), 2))
	s._lose_system(ai.home, ai)
	check(ai.foils.is_empty(), "发射者灭亡，二向箔也消失")


## 规则：自身降维
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


## 规则：自身降维
func test_reduce_waits_for_pending_buildings() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["dimension"])
	s.build(me, "miner")
	var e := me.energy
	check(s.start_reduce(me)["error"] != "" and me.energy == e, "有没建好的设施时不能降维，也不花钱")
