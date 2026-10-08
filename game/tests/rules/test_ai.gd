extends "res://tests/rules/rule_suite.gd"
## AI 的行动。


## AI 在 (8,8,8)，你在 (0,0,0)。AI 没有随机偏好、资源充足、有 6 个行动点；
## 算作已经发现过别人，免得它先花能量升射电望远镜。
func _ai_game() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ai := s.civs[1]
	ai.is_ai = true
	ai.taste = {}
	ai.discovered = true
	ai.energy = 1000
	ai.mineral = 1000
	ai.actions_left = 6
	return s


## 这个文明造过的东西，按造的顺序。
func _builds(s: GameState, civ: Civ) -> Array:
	var civ_index := s.civs.find(civ)
	return s.history.filter(func(h): return h["civ"] == civ_index and h["name"] == "build").map(func(h): return h["args"][0])


## 这个文明停着和在飞的某种单位。
func _ships_of(civ: Civ, kind: String) -> Array:
	return civ.ships.filter(func(sh): return sh.kind == kind)


## 规则：AI 怎么行动
func test_ai_research_picks_highest_score_and_keeps_reserve() -> void:
	var s := _ai_game()
	var ai := s.civs[1]
	_open_tiers(ai, 1)
	var before := ai.techs.size()
	# 分最高的是戴森球（6 分 + 1 颗恒星），升了以后剩不到 6E 就不升，也不退而求其次
	ai.energy = Tech.cost("dyson")[0] + AI.RESERVE - 1
	AI.take_turn(s, ai)
	check_eq(ai.techs.size(), before, "最想升的升了会剩不到 6E 时，这回合不升科技")
	ai.energy = Tech.cost("dyson")[0] + AI.RESERVE
	AI._research(s, ai)
	check(ai.has_tech("dyson") and ai.energy >= AI.RESERVE, "先升分最高的戴森球，至少留 6E")
	ai.energy = 1000
	before = ai.techs.size()
	AI._research(s, ai)
	check_eq(ai.techs.size() - before, 3, "一回合最多升 3 项")
	check(ai.has_tech("warship"), "接着升分第二高的战舰（5 分）")


## 规则：AI 怎么行动
func test_ai_research_favours_bunker_after_hit() -> void:
	for hit in [0, 1]:
		var s := _ai_game()
		var ai := s.civs[1]
		_open_tiers(ai, 1)
		ai.techs["dyson"] = true
		ai.times_hit = hit
		# 只够升一项：战舰 5 分，掩体 3 分，被打过时掩体加 4 分
		ai.energy = Tech.cost("warship")[0] + AI.RESERVE
		AI._research(s, ai)
		if hit == 0:
			check(ai.has_tech("warship") and not ai.has_tech("bunker"), "没被打过时先升战舰")
		else:
			check(ai.has_tech("bunker") and not ai.has_tech("warship"), "被打过时掩体加分，先升掩体")


## 规则：AI 怎么行动
func test_ai_builds_in_order_when_nobody_known() -> void:
	var s := _ai_game()
	var ai := s.civs[1]
	AI.take_turn(s, ai)
	check_eq(_builds(s, ai), ["warning", "miner", "probe", "broadcaster"],
			"不知道敌人时按顺序：预警系统、采矿船（每回合一艘）、探测器、恒星广播器")
	var probe: Ship = _ships_of(ai, Ship.PROBE)[0]
	check(not probe.docked, "造好的探测器马上派出去")
	# 已经有两个探测器在飞、能量不多于 20E 时：只造采矿船
	s = _ai_game()
	ai = s.civs[1]
	ai.has_warning = true
	ai.energy = 20
	for i in AI.PROBES_WANTED:
		_ship(s, ai, Ship.PROBE, Vector3(ai.home), Vector3(0, 0, -1))
	AI.take_turn(s, ai)
	check_eq(_builds(s, ai), ["miner"], "探测器够了不再造；能量不多于 20E 不建恒星广播器")


## 被打过以后：有两个以上星系时母星系躲进黑域，有类木行星的星系建掩体，造一艘星舰。没被打过时都不做。
## 规则：AI 怎么行动
func test_ai_protects_itself_after_hit() -> void:
	for hit in [0, 1]:
		var s := _ai_game()
		var ai := s.civs[1]
		_give(ai, ["domain", "bunker", "starship"])
		var colony := Vector3i(8, 8, 6)
		_set_star(s, colony, StarMap.Star.SINGLE)
		ai.colonies.append(colony)
		s.map.gas[colony] = 1
		ai.times_hit = hit
		ai.actions_left = 10
		AI.take_turn(s, ai)
		var builds := _builds(s, ai)
		if hit == 0:
			check(ai.pending_domains.is_empty() and not builds.has("bunker") and not builds.has("starship"),
					"没被打过时不投黑域、不建掩体、不造星舰")
		else:
			check(not ai.pending_domains.is_empty(), "被打过、有两个星系时，在母星系投放黑域")
			check(builds.has("bunker") and ai.pending.any(func(p): return p["kind"] == "bunker" and p["at"] == colony),
					"被打过时在有类木行星的星系建掩体")
			check(builds.has("starship"), "被打过时造一艘星舰")


## 规则：AI 怎么行动
func test_ai_sends_warships_at_known_target() -> void:
	var s := _ai_game()
	var ai := s.civs[1]
	_give(ai, ["warship"])
	ai.known[Vector3i.ZERO] = 1
	AI.take_turn(s, ai)
	var warships := _ships_of(ai, Ship.WARSHIP)
	check_eq(warships.size(), 1, "知道敌人时造一艘战舰（一回合一艘）")
	var toward := (Vector3.ZERO - Vector3(ai.home)).normalized()
	check(not warships[0].docked and warships[0].direction.is_equal_approx(toward), "战舰朝已知的敌方星系派出")
	for i in 3:
		ai.actions_left = 6
		AI.take_turn(s, ai)
	check_eq(_ships_of(ai, Ship.WARSHIP).size(), 2, "在飞的战舰最多 2 艘")


## 规则：AI 怎么行动
func test_ai_counterattacks_along_hit_direction() -> void:
	for age in [0, 21]:
		var s := _ai_game()
		var ai := s.civs[1]
		_give(ai, ["warship"])
		s.turn = 30
		ai.hit_dirs.append({"at": ai.home, "dir": Vector3(-1, 0, 0), "turn": s.turn - age})
		AI.take_turn(s, ai)
		var warships := _ships_of(ai, Ship.WARSHIP)
		if age == 0:
			check(warships.size() == 1 and warships[0].direction.is_equal_approx(Vector3(-1, 0, 0)),
					"不知道敌人但刚被打过：朝打来的方向派战舰")
		else:
			check(warships.is_empty(), "被打是 20 回合以前的事，不再反击")


## 规则：AI 怎么行动
func test_ai_turns_warship_toward_target() -> void:
	var want := (Vector3.ZERO - Vector3(8, 8, 4)).normalized()
	var side := want.cross(Vector3(0, 0, 1)).normalized()
	for degrees in [90.0, 10.0]:
		var s := _ai_game()
		var ai := s.civs[1]
		ai.known[Vector3i.ZERO] = 1
		var dir := want.rotated(side, deg_to_rad(degrees))
		var w := _ship(s, ai, Ship.WARSHIP, Vector3(8, 8, 4), dir)
		AI.take_turn(s, ai)
		if degrees > 25.0:
			check(w.direction.is_equal_approx(want), "偏离已知敌人超过 25° 的战舰转向它")
		else:
			check(w.direction.is_equal_approx(dir), "只偏一点（10°）的不转")


## 规则：AI 怎么行动
func test_ai_broadcasts_far_targets_once() -> void:
	var s := _ai_game()
	var ai := s.civs[1]
	ai.broadcasters[ai.home] = true
	var near := Vector3i(8, 8, 5)
	_set_star(s, near, StarMap.Star.SINGLE)
	ai.known[Vector3i.ZERO] = 1
	ai.known[near] = 1
	AI.take_turn(s, ai)
	check(ai.broadcasted.has(Vector3i.ZERO) and not ai.broadcasted.has(near), "只广播离自己 4 格以外的已知敌人")
	check_eq(s.broadcasts.size(), 1, "广播了一次")
	ai.actions_left = 6
	AI.take_turn(s, ai)
	check_eq(s.broadcasts.size(), 1, "同一个坐标只广播一次")


## 规则：AI 怎么行动
func test_ai_saves_up_then_reduces_then_launches_foil() -> void:
	var s := _ai_game()
	var ai := s.civs[1]
	ai.times_hit = 2  # 最后据点反复被打，才满足降维武器的最后手段条件
	ai.has_warning = true
	ai.warning_level = Balance.WARNING_MAX  # 不把测试的临界能量花在预警升级上
	_give(ai, ["dimension"])
	ai.known[Vector3i.ZERO] = 1
	var need := maxi(Balance.AI_FOIL_ENERGY, ai.reduce_cost() + Balance.COST_FOIL)
	ai.energy = need - 1
	AI.take_turn(s, ai)
	check(ai.reduce_left == 0 and ai.foils.is_empty(), "能量不到 %dE 时先攒着，不降维" % need)
	# 这回合下单的设施建好（建造中不能降维）；造了别的单位，降维要带的单位多了，再算一次
	s._finish_pending(ai)
	need = maxi(Balance.AI_FOIL_ENERGY, ai.reduce_cost() + Balance.COST_FOIL)
	ai.energy = need
	ai.actions_left = 6
	AI.take_turn(s, ai)
	check(ai.reduce_left > 0 and ai.foils.is_empty(), "能量够了先降维，还不发射")
	ai.reduce_left = 0
	ai.reduced = true
	ai.energy = 1000
	ai.actions_left = 6
	AI.take_turn(s, ai)
	check(ai.foils.size() == 1 and ai.foils[0].target == Vector3i.ZERO, "降维完成后朝最近的已知敌人发射二向箔")
	ai.actions_left = 6
	AI.take_turn(s, ai)
	check_eq(ai.foils.size(), 1, "同时最多一片")


## 规则：AI 怎么行动
func test_ai_sends_sophon_when_energy_allows() -> void:
	var need: int = Balance.COST_SOPHON[0] + Balance.COST_SOPHON_LAUNCH + 4 * AI.RESERVE
	for energy in [need - 1, need]:
		var s := _ai_game()
		var ai := s.civs[1]
		_give(ai, ["sophon"])
		ai.known[Vector3i.ZERO] = 1
		ai.energy = energy
		AI.take_turn(s, ai)
		var sophons := _ships_of(ai, Ship.SOPHON)
		if energy < need:
			check(sophons.is_empty(), "能量不到 %dE 时不造智子" % need)
		else:
			check(sophons.size() == 1 and sophons[0].has_target and ai.sophon_tried.has(Vector3i.ZERO),
					"能量够了造智子，派去已知的敌方星系")
			ai.actions_left = 6
			ai.energy = 1000
			AI.take_turn(s, ai)
			check_eq(_ships_of(ai, Ship.SOPHON).size(), 1, "派过的星系不再派")


## 规则：AI 怎么行动
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


## 规则：AI 怎么行动
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


## 规则：AI 怎么行动
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


## 规则：AI 怎么行动
func test_ai_uses_antimatter() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	ai.is_ai = true
	ai.antimatter = 1
	var w := _ship(s, s.human(), Ship.WARSHIP, Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	AI.take_turn(s, ai)
	check(w.dead, "敌方战舰靠近时用反物质")


## 规则：AI 怎么行动
func test_ai_reduces_when_flattening_near() -> void:
	var s := _two_civs(Vector3i(5, 0, 0))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["dimension"])
	s.foil_zones.append({"center": Vector3i(3, 0, 0), "age": 0.0})
	AI.take_turn(s, ai)
	check(ai.reduce_left > 0, "压平快到时开始降维")
	# 不是因为钱不够而降不了维（比如还有没建好的东西）时，这回合照常行动
	s = _two_civs(Vector3i(5, 0, 0))
	ai = s.civs[1]
	ai.is_ai = true
	_give(ai, ["dimension"])
	s.foil_zones.append({"center": Vector3i(3, 0, 0), "age": 0.0})
	ai.energy = 1000
	ai.pending.append({"kind": "miner", "at": ai.home})
	var ap := ai.actions_left
	AI.take_turn(s, ai)
	check(ai.reduce_left == 0 and ai.actions_left < ap, "降不了维也不白白空过一回合")


## 规则：AI 怎么行动
func test_long_ai_game_runs() -> void:
	var s := GameState.new_game(3, Balance.AI_COUNT, true)
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
## 规则：AI 怎么行动
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


## 规则：AI 怎么行动
func test_ai_foil_is_last_resort() -> void:
	var s := _collapse_match()
	var ai := s.civs[1]
	ai.known[s.human().home] = 1
	check(not AI._try_foil(s, ai), "有资源和已知敌人不等于可以常规使用末日武器")
	ai.times_hit = 2
	check(AI._try_foil(s, ai) and ai.foils.size() == 1, "最后据点反复被打且没有常规武器时可发射")
	check(not AI._try_foil(s, ai), "在途箔未结束时不重复发射")
