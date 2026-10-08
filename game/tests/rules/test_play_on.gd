extends "res://tests/rules/rule_suite.gd"
## 玩家灭亡后接着打，以及灭亡文明的善后。


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


## 规则：灭亡和胜负
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
## 规则：灭亡和胜负
func test_spectator_winner_is_named() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.spectator = true
	s._die(s.civs[1])
	check(s.winner == "你" and s.winner_by_name(), "观战局的胜负写赢家的名字")
	check(not s.log_lines.any(func(l): return l.contains("你胜利了")), "日志不说「你胜利了」")
