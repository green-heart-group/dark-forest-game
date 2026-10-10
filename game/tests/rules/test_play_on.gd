extends "res://tests/rules/rule_suite.gd"
## 确定性终局夹具；长自然局由冻结后的400年实验单列，不在回归里搜索种子。


## 规则：灭亡和胜负
func test_play_on_after_player_death() -> void:
	for flag in [false,true]:
		var s:=_three_civs()
		s.set_play_on_after_death(flag)
		s._lose_system(s.human().home,s.human())
		s._check_winner()
		check(not s.human().alive and not s.is_over(),"玩家灭亡但两个AI锚点尚存，任何观战选项均不提前终局")
		var prior:=s.steps
		s.end_turn()
		check_eq(s.steps,prior+1,"其余文明的时钟仍推进")
		s._lose_system(s.civs[1].home,s.civs[1])
		s._check_winner()
		check(s.is_over(),"仅剩一个存续文明才终局")
		check_eq(s.winner,"第三方" if flag else "AI","原普通/按名字观战显示约定保留")


## 规则：灭亡和胜负
func test_continue_after_death_recomputes_last_turn() -> void:
	var s:=_three_civs()
	s._lose_system(s.human().home,s.human())
	s._check_winner()
	var packed:=StateCopy.pack(s)
	var copied:=StateCopy.unpack(packed)
	s.set_play_on_after_death(true)
	copied.set_play_on_after_death(true)
	for year in 3:
		s.end_turn()
		copied.end_turn()
	check_eq(copied.checksum(),s.checksum(),"死亡时刻缓存重建后继续的结果一致")
	# 回放历史另用正式开局和记录入口，不能把手工灭亡夹具伪称可重放自然局。
	var recorded:=GameState.new_game(8129,2,false)
	for civ in recorded.civs: recorded.set_autoplay(civ,false)
	recorded.set_play_on_after_death(true)
	recorded.end_turn()
	recorded.set_play_on_after_death(false)
	recorded.end_turn()
	var replay:=Replay.from_state(recorded)
	var again:=replay.play_to(recorded.steps)
	check_eq(again.checksum(),recorded.checksum(),"观战设置变更仍完整记录并可回放")


## 规则：情报传回
func test_dead_civ_intel_expires() -> void:
	var s:=_three_civs()
	var me:=s.human()
	me.alerts.append({"pos":Vector3(3,3,3),"t_received":0.0,"turn":s.turn})
	me.sightings.append({"pos":Vector3(4,4,4),"kind":Ship.WARSHIP,"t_received":0.0,"turn":s.turn})
	s._lose_system(me.home,me)
	s._check_winner()
	_turns(s,Balance.SIGHTING_KEEP+2)
	check(me.alerts.is_empty() and me.sightings.is_empty(),"灭亡不阻止历史预警/目击按原期限过期")


## 规则：灭亡和胜负
func test_spectator_winner_is_named() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	s.spectator=true
	s._lose_system(s.civs[1].home,s.civs[1])
	s._check_winner()
	check(s.winner=="你" and s.winner_by_name(),"观战局使用文明名而非玩家身份")
	check(not s.log_lines.any(func(line):return line.contains("你胜利了")),"日志不把同名文明当操作者")
