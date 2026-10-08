extends "res://tests/rules/rule_suite.gd"
## 智子（D5）。


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


## 规则：智子（D5）
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


## 规则：智子（D5）
func test_building_own_sophon_frees_civ() -> void:
	var s := _two_civs(Vector3i(3, 0, 0))
	var ai := s.civs[1]
	var sophon := _lock_ai_with_sophon(s)
	check(sophon.lock == 1, "先锁住")
	_give(ai, ["sophon"])
	check(s.build(ai, "sophon", Vector3i(3, 0, 0))["error"] == "", "被锁住的文明能造智子")
	check(s.sophons_on(ai).is_empty() and s.sophon_research_left(ai) == 0 and s.sophon_tier_left(ai) == 0,
			"造出自己的智子，锁住它的智子全部失效")


## 规则：智子（D5）
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
