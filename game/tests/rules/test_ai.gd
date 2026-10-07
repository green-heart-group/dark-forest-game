extends "res://tests/rules/rule_suite.gd"
## AI 的行动。


## 规则：AI 怎么行动
func test_ai_researches_after_discovery() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
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
	var s := _two_civs(Vector3i(9, 9, 9))
	var ai := s.civs[1]
	ai.is_ai = true
	_give(ai, ["colony"])
	_set_habitable(s, Vector3i(9, 9, 8), StarMap.Star.SINGLE)
	_set_habitable(s, Vector3i(9, 0, 9), StarMap.Star.SINGLE)
	ai.intel[Vector3i(9, 9, 8)] = s.snapshot(Vector3i(9, 9, 8))
	AI.take_turn(s, ai)
	check(not ai.colony_tried.has(Vector3i(9, 0, 9)), "AI 不去没看到过的宜居星系")
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


## 规则：AI 怎么行动
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
## 规则：AI 怎么行动
func test_ai_only_knows_what_it_saw() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
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
	ai.broadcasters[Vector3i(9, 9, 9)] = true  # 有广播器才听得到
	ai.heard.clear()
	s.broadcasts.append({"from": Vector3(9, 9, 0), "target": Vector3i.ZERO, "sender": null, "exposed": GameState.NO_HIT,
			"radius": 0.0, "heard": {}, "hidden_heard": {}})
	for i in 12:
		s._spread_broadcasts()
	check(ai.known.has(Vector3i.ZERO), "听到广播以后，AI 才知道你的坐标")
