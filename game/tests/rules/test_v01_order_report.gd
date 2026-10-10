extends "res://tests/rules/rule_suite.gd"
## 独立Gate反例：本地并行工程满一年后仍显示0.05W；修复不能提前刷新远端真值。


func _local() -> GameState:
	var s := _two_civs(Vector3i(8,8,8))
	s.map.rocky[Vector3i.ZERO] = 3
	Assets.ensure(s,s.human())
	# 正常new_game已在玩家操作前采样，下一传感时刻是0.05；不能用未采样的简化局面掩盖Gate反例。
	Signals.sample(s)
	return s


## 规则：建造，每回合的收入，情报传回，界面和操作
func test_v01_progress_gate_seed_zero_natural_start() -> void:
	var s := GameState.new_game(0,1)
	var me := s.human()
	var a := s.build(me,"miner")
	var b := s.build(me,"miner")
	var research := s.research(me,"fusion")
	check_eq([a["error"],b["error"],research["error"]],["","",""],"Gate种子0正常新局双矿船及009同年开工")
	check_eq([me.energy,me.mineral,me.actions_left],[3.0,2.0,0],"原预付费用和AP不变")
	s.end_turn()
	check_eq([me.energy,me.mineral,me.actions_left],[6.0,2.0,3],"第一年原收入与AP恢复不变")
	for id in [a["order"],b["order"]]:
		check_eq(OrderControl.find(me,id)["done"],1000,"自然开局每单真实完成1W")
		check_eq(me.order_reports[id]["done"],1000,"自然开局每单已收进度为1W")
		check(absf(me.order_reports[id]["t_observed"]-1.0)<1e-8,"自然开局报告观测为年末1.0")


## 规则：建造，情报传回，界面和操作
func test_v01_local_parallel_progress_observed_at_round_end() -> void:
	var s := _local()
	var me := s.human()
	var a := s.build(me,"miner")
	var b := s.build(me,"miner")
	check_eq([a["error"],b["error"]],["",""],"母星双槽均合法开工")
	s.end_turn()
	check_eq(s.clock,1.0,"连续主流程完成一年")
	for id in [a["order"],b["order"]]:
		var physical := OrderControl.find(me,id)
		var report: Dictionary = me.order_reports[id]
		check_eq(physical["done"],1000,"每个槽实际完成1W")
		check_eq(report["done"],1000,"本地工程已收报告也显示1W，不能滞留0.05W")
		check(absf(report["t_observed"]-s.clock)<1e-8,"本地观测时间为当前年末")
		check(absf(report["t_received"]-s.clock)<1e-8,"零距离回报在同一时刻抵达")


## 规则：建造，情报传回，界面和操作
func test_v01_local_research_progress_uses_same_observation() -> void:
	var s := _local()
	var me := s.human()
	check_eq(s.research(me,"fusion")["error"],"","独立研究队列正常开工")
	s.end_turn()
	check_eq(me.research_project["done"],1000,"研究实际完成1W")
	check_eq(me.order_reports[me.research_project["id"]]["done"],1000,"本地研究回报同步刷新")


## 规则：建造，情报传回
func test_v01_progress_remote_hidden_state_pair() -> void:
	var s := _local()
	var me := s.human()
	var remote := Vector3i(4,0,0)
	_set_habitable(s,remote,StarMap.Star.SINGLE)
	s.map.rocky[remote] = 3
	me.colonies.append(remote)
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,remote)
	Signals.advance(s,4.0)
	s.clock = 4.0
	Signals.receive_due(s)
	var result := s.build(me,"miner",remote)
	check_eq(result["error"],"","按已收远端星系报告提交工程")
	var hidden := StateCopy.copy(s)
	var project := OrderControl.find(hidden.human(),result["order"])
	project["done"] = 1700
	project["command_ready"] = true
	project["status"] = "working"
	check_eq(OrderControl.visible(hidden,hidden.human()),OrderControl.visible(s,me),"隐藏施工状态不改变玩家或AI订单列表")
	WorldTime.advance(s,1.0)
	WorldTime.advance(hidden,1.0)
	check_eq(OrderControl.visible(hidden,hidden.human()),OrderControl.visible(s,me),"远端新施工报告未到达前仍完全相同")
	check_eq(me.order_reports[result["order"]]["done"],0,"远端不能因本地刷新机制提前显示真实进度")
	check_eq(me.order_reports[result["order"]]["status"],"sent","四光年开工命令尚未抵达")


## 规则：建造，存档和回放
func test_v01_old_replay_retains_order_report_cadence() -> void:
	var old := Replay.new()
	old.balance = Balance.values().duplicate(true)
	old.balance.erase("LOCAL_ORDER_REPORT_CURRENT")
	old.apply_balance()
	var s := _local()
	var me := s.human()
	var result := s.build(me,"miner")
	s.end_turn()
	check_eq(me.order_reports[result["order"]]["done"],50,"旧记录保留原周期，不能改变已冻结历史校验")
	check(absf(me.order_reports[result["order"]]["t_observed"]-0.05)<1e-8,"旧记录保留原报告时刻")
