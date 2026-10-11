extends "res://tests/rules/rule_suite.gd"


## 规则：情报传回
func test_v01_remote_sensor_two_leg_latency() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	Assets.ensure(s, me)
	var observer := _ship(s, me, Ship.PROBE, Vector3(2, 0, 0))
	var cell := Vector3i(3, 0, 0)
	s.ensure_cells()
	var body := {"type": "cell", "cell": cell,"cell_id":s.cell_ids[cell], "data": {"owner": 1, "stars": 1, "turn": 0},
			"t_observed": 0.0, "source_id": observer.id, "epoch": 0}
	Signals.send(s, 0, Vector3(cell), observer.id, "sensor", body)
	s.clock = 1.0
	Signals.receive_due(s)
	check(not me.intel.has(cell), "目标光先到远程探测器，不能同刻进入母星地图")
	check_eq(s.messages.size(), 1, "接收后从探测器发送独立回传")
	s.clock = 3.0
	Signals.receive_due(s)
	check(me.intel.has(cell), "再传播2年后母星收到")
	check_eq([me.intel[cell]["t_observed"], me.intel[cell]["t_received"], me.intel[cell]["epoch"]], [0.0, 3.0, 0], "观测、收到和几何世代分别保留")


## 规则：黑域，情报传回
func test_v01_signal_pauses_and_resumes_without_restarting() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	Assets.ensure(s, me)
	var message := Signals.send(s, 0, Vector3(2, 0, 0), Signals.controller(me), "report",
			{"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0})
	var pos: Vector3 = message["pos"]
	s.set_light_at(Vector3i(pos.round()), 0.0)
	Signals.retime(s)
	check_eq([s.messages.size(), message["eta"]], [1, INF], "零光速暂停，不清空，也算不出到达时间")
	s.set_light_at(Vector3i(pos.round()), 1.0)
	Signals.retime(s)
	check(message["eta"] < 22.0, "光速恢复后从原处接着走")
	s.clock = 22.0
	Signals.receive_due(s)
	check(me.telemetry.has(999) and s.messages.is_empty(), "恢复后继续剩余路径并只送达一次")


## 规则：情报传回
func test_v01_cell_conversion_retimes_only_crossing_messages() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var crossing := Signals.send(s, 0, Vector3(0, 0, 0), -5, "report", body.merged({"recipient_pos": Vector3(6, 0, 0)}), 0, false)
	var away := Signals.send(s, 0, Vector3(0, 4, 0), -5, "report", body.merged({"recipient_pos": Vector3(6, 4, 0)}), 0, false)
	s.message_medium = Signals.medium(s)
	var kept: float = away["eta"]
	var old: float = crossing["eta"]
	s.clock = 1.0
	SpaceEvents.convert_cell(s, Vector3i(3, 0, 0))
	Signals.retime(s, s.message_medium)
	check_eq([away["eta"], away["sent"]], [kept, 0.0], "路线不经过降维格的消息不重算")
	check(crossing["sent"] == 1.0 and crossing["eta"] > old, "穿过降维格的消息从现在的位置按新光速重算，只会更晚")
	check(s.converted_cells.is_empty(), "用过就清空")


## 规则：情报传回
func test_v01_one_dimensional_backward_telescope() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.dimension = 1
	var me := s.human()
	var probe := _ship(s, me, Ship.PROBE, Vector3(100, 0, 0), Vector3.RIGHT)
	for level in 4:
		me.telescope = level
		var observer: Dictionary = Signals.observers(s, me).filter(func(o): return o["id"] == probe.id)[0]
		var expected: float = observer["radius"] * level * 0.25
		check(Signals.in_view(s, observer, probe.pos + Vector3.LEFT * expected / s.physical_cell_size()), "后向倍率按望远镜等级扩展")
		check(not Signals.in_view(s, observer, probe.pos + Vector3.LEFT * (expected+0.01) / s.physical_cell_size()), "后向视野不超过相应倍率")


## 规则：情报传回，移动
func test_v01_known_wake_waits_for_sensor_and_return_and_keeps_history() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	s.ensure_cells()
	Assets.ensure(s,me)
	_ship(s,me,Ship.PROBE,Vector3(2,0,0))
	s.deadlines.append({"id":9999,"source":777,"a":Vector3(2.9,0,0),"b":Vector3(3,0,0),"created":0.0,"ended":0.0,"expires":20.0,"turn":1})
	Signals.sample(s,true)
	var view:=Knowledge.presentation(s,me)
	check(view.wakes.is_empty(),"曲率航迹尚未传感和回传，普通画面不读取物理死线")
	s.clock=2.0
	Signals.receive_due(s)
	check(Knowledge.presentation(s,me).wakes.is_empty(),"侦察器已收到，但控制端还需等第二程")
	s.clock=4.0
	Signals.receive_due(s)
	view=Knowledge.presentation(s,me)
	check_eq(view.wakes.size(),1,"两段传播后显示已观测航迹")
	var before:=view.wakes.duplicate(true)
	s.deadlines.clear()
	check_eq(Knowledge.presentation(s,me).wakes,before,"未收到新情报时，真实航迹消失不修改历史显示")


## 规则：情报传回，移动
func test_v01_known_wake_requires_both_received_endpoints() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	s.ensure_cells()
	Assets.ensure(s,me)
	_ship(s,me,Ship.PROBE,Vector3(2,0,0))
	s.deadlines.append({"id":9999,"a":Vector3(2.9,0,0),"b":Vector3(3.1,0,0),"expires":20.0})
	Signals.sample(s,true)
	s.clock=2.0
	Signals.receive_due(s)
	s.clock=4.0
	Signals.receive_due(s)
	check(me.wake_reports.has(9999) and me.wake_reports[9999].has(0),"近端已完整传回")
	check(not me.wake_reports.get(9999,{}).has(1),"视野以外端点不随近端消息送出")
	check(Knowledge.presentation(s,me).wakes.is_empty(),"只收到近端仍不能拼出整条线段")

## 规则：情报传回
func test_v01_retime_never_moves_arrival_earlier() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	# 路上先慢后快：按时间比例在直线上取点会比真实位置靠前，重算后就提前到了。
	s.set_light_at(Vector3i(1, 0, 0), 0.25)
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var message := Signals.send(s, 0, Vector3(0, 0, 0), -5, "report", body.merged({"recipient_pos": Vector3(6, 0, 0)}), 0, false)
	var eta: float = message["eta"]
	for i in 8:
		s.clock += 0.4
		Signals.retime(s)
		check(absf(message["eta"] - eta) < 1e-6, "光速没变时反复重算，到达时刻不变（第 %d 次：%s，原来 %s）" % [i, message["eta"], eta])


## 规则：情报传回，黑域
func test_v01_growing_domain_retimes_only_nearby_messages_each_piece() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var near := Signals.send(s, 0, Vector3(-3, 0, 0), -5, "report", body.merged({"recipient_pos": Vector3(3, 0, 0)}), 0, false)
	var far := Signals.send(s, 0, Vector3(-3, 3, 0), -5, "report", body.merged({"recipient_pos": Vector3(3, 3, 0)}), 0, false)
	# 黑域刚出现时很小，在消息前方路线旁边慢慢扩大。
	Hazards.activate(s, Vector3(0, 0.03, 0))
	Signals.retime(s, s.message_medium)
	s.message_medium = Signals.medium(s)
	var started: float = far["sent"]
	var before: float = near["eta"]
	s.clock += Balance.ROUGH_DT
	check(Signals.medium(s) != s.message_medium, "黑域长大时每 0.2 年换一次半径，要再看一次")
	Signals.retime(s, s.message_medium)
	check_eq(far["sent"], started, "离黑域远的消息不重算")
	check(near["sent"] == s.clock and near["eta"] >= before - 1e-6, "黑域旁边的消息按扩大后的黑域重算，不会提前")

## 规则：情报传回
func test_v01_light_reads_the_next_cell_after_an_edge() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	# 光从格子边界出发时按前进方向那一格的光速走；往负方向走也一样，不按刚离开的那一格算。
	var table := {"speed": 1.0, "speeds": {Vector3i(1, 0, 0): 0.6}}
	var expected := 0.5 + 1.0 / 0.6 + 1.0 + 0.5
	for start in [Vector3(2, 0, 0), Vector3(-1, 0, 0)]:
		var direction: Vector3 = (Vector3(1, 0, 0) - start).normalized()
		var trip := Hazards.light_travel(s, start, direction, 3.0, INF, table)
		check(absf(trip["arrival"] - expected) < 1e-6, "从 %s 出发应走 %s 年，实际 %s" % [start, expected, trip["arrival"]])


## 规则：情报传回
func test_v01_long_light_path_with_many_speed_changes_arrives() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	# 一维时一条直线上可能有几百段光速不同的格子，光照样能走到。
	var table := {"speed": 1.0, "speeds": {}}
	for i in 401:
		table["speeds"][Vector3i(i, 0, 0)] = 0.5 if i % 2 == 1 else 0.8
	var trip := Hazards.light_travel(s, Vector3.ZERO, Vector3.RIGHT, 400.0, INF, table)
	check(trip["arrival"] > 400.0 / 0.8 and trip["arrival"] < 400.0 / 0.5, "走了 %s 年" % trip["arrival"])


## 规则：情报传回
func test_v01_faster_light_does_not_make_messages_early() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	s.set_light_at(Vector3i(1, 0, 0), 0.2)
	s.set_light_at(Vector3i(2, 0, 0), 0.2)
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var message := Signals.send(s, 0, Vector3(0, 0, 0), -5, "report", body.merged({"recipient_pos": Vector3(6, 0, 0)}), 0, false)
	s.message_medium = Signals.medium(s)
	var eta: float = message["eta"]
	# 消息早已慢慢穿过这两格，现在两格恢复原来的光速：已经走过的那段不能按新光速重走。
	s.clock = 12.6
	s.set_light_at(Vector3i(1, 0, 0), 1.0)
	s.set_light_at(Vector3i(2, 0, 0), 1.0)
	Signals.retime(s, s.message_medium)
	check(absf(message["eta"] - eta) < 1e-6, "到达时刻不变：原来 %s，现在 %s" % [eta, message["eta"]])


## 规则：情报传回
func test_v01_dropped_messages_are_counted_like_a_copy_would() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	for i in 30:
		Signals.send(s, 0, Vector3.ZERO, -5, "report", body.merged({"recipient_pos": Vector3(6, 0, 0)}), 0, false)
	# 收件者不存在：到了就作废。三条一起作废，待清理的条数也要加三，和复制后从头数的一样。
	for i in 3:
		Signals.send(s, 0, Vector3.ZERO, 987654, "report", body.merged({"recipient_pos": Vector3(0.5, 0, 0)}), 0, false)
	s.clock = 1.0
	Signals.receive_due(s)
	var dead := s.messages.filter(func(m): return m["dead"]).size()
	check_eq(Signals._indexed(s)["dead"], dead, "待清理的条数等于实际作废的条数")
	check_eq(StateCopy.copy(s).checksum(), s.checksum(), "复制出来的局面校验值一样")

## 规则：情报传回，移动
func test_v01_message_meets_a_receiver_flying_toward_it() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var probe := _ship(s, me, Ship.PROBE, Vector3(6, 0, 0), Vector3(-1, 0, 0))
	var light := 6.0 / Signals.travel_time(s, Vector3.ZERO, Vector3(6, 0, 0))
	var speed: float = Kinematics.motion(s, me, probe, 0.0)["velocity"].length()
	var meet := 6.0 / (light + speed)
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var message := Signals.send(s, 0, Vector3.ZERO, probe.id, "report", body, 0, false)
	check(absf(message["eta"] - meet) < 0.05, "瞄准光和探测器相遇的时刻 %s，算出 %s" % [meet, message["eta"]])
	# 照原来的航向飞：到了就收下，不会因为先飞到发出时的位置再折回来而晚很多。
	var got := INF
	# 每 0.05 年看一次收没收到。
	for tick in 200:
		s.clock = tick * 0.05
		probe.pos = Vector3(6.0 - speed * s.clock, 0, 0)
		Signals.receive_due(s)
		if me.telemetry.has(999):
			got = s.clock
			break
	check(got >= meet - 1e-6 and got < meet + 0.15, "相遇 %s 年，收到 %s 年" % [meet, got])


## 规则：情报传回，移动
func test_v01_message_aimed_ahead_is_not_early_when_receiver_turns() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var probe := _ship(s, me, Ship.PROBE, Vector3(6, 0, 0), Vector3(-1, 0, 0))
	var body := {"type": "own", "data": {"id": 999}, "t_observed": 0.0, "source_id": 999, "epoch": 0}
	var message := Signals.send(s, 0, Vector3.ZERO, probe.id, "report", body, 0, false)
	var eta: float = message["eta"]
	# 探测器半路掉头，到时不在瞄准点：不能按瞄准点交付，要接着追。
	probe.direction = Vector3(1, 0, 0)
	probe.pos = Vector3(7, 0, 0)
	s.clock = ceilf(eta / 0.05) * 0.05
	Signals.receive_due(s)
	check(not me.telemetry.has(999), "光还没到探测器现在的位置，不能收到")
	check(message["eta"] >= Signals.travel_time(s, Vector3.ZERO, Vector3(7, 0, 0)) - 1e-6, "改到不早于光真正走到它那里")


## 规则：情报传回，移动
func test_v01_dead_reckoning_stops_speeding_up_at_top_speed() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	# 观测时每年加速 0.1 格，0.5 年后到最高速度；之后只能按最高速度匀速推算。
	var contact := {"pos": Vector3.ZERO, "velocity": Vector3(0.1, 0, 0), "acceleration": Vector3(0.1, 0, 0),
			"accel_until": 0.5, "t_observed": 0.0, "t_received": 0.0}
	s.clock = 1.5
	var known := Combat.observed(s, contact)
	check(known["velocity"].is_equal_approx(Vector3(0.15, 0, 0)), "速度停在最高速度：%s" % known["velocity"])
	check(known["pos"].is_equal_approx(Vector3(0.2125, 0, 0)), "先加速 0.5 年再匀速 1 年：%s" % known["pos"])


## 规则：情报传回，移动
func test_v01_dead_reckoning_stops_when_reports_stop() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	# 观测在路上走了 1 年。目标还在视野里时，最晚 Combat.stale_after() 年后会再看到它一次，
	# 再过 1 年传到；过了这个时间还没收到新的，说明它已离开视野、停下或没了，推算停在那里。
	var contact := {"pos": Vector3(1, 4, 4), "velocity": Vector3(0.5, 0, 0), "acceleration": Vector3.ZERO,
			"t_observed": 0.0, "t_received": 1.0}
	var stale := Combat.stale_after()
	s.clock = 1.5
	check(Combat.predicted(s, contact).is_equal_approx(Vector3(1.75, 4, 4)), "还在等下一次报告时照常推算：%s" % Combat.predicted(s, contact))
	check(not Combat.stale(s, contact), "还在等下一次报告时不算过时")
	s.clock = 10.0
	var frozen := Vector3(1, 4, 4) + Vector3(0.5, 0, 0) * (stale + 1.0)
	check(Combat.predicted(s, contact).is_equal_approx(frozen), "报告断了就停在最后能推到的地方：%s" % Combat.predicted(s, contact))
	check(Combat.stale(s, contact), "报告断了算过时")


## 规则：情报传回，移动
func test_v01_dead_reckoning_stays_inside_map() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var contact := {"pos": Vector3(8, 4, 4), "velocity": Vector3(1, 0, 0), "acceleration": Vector3.ZERO,
			"t_observed": 0.0, "t_received": 0.0}
	s.clock = 1.0
	var pos := Combat.predicted(s, contact)
	check(not Ship.outside(pos, s.map.bounds()), "推算的位置不出地图：%s" % pos)
	check(pos.x > 8.0, "朝地图边上推，停在边上：%s" % pos)


## 规则：视野
func test_v01_views_that_only_check_changes_miss_nothing() -> void:
	# 每回合中间只看变了的东西（ViewMarks）。核对模式每一刀再全看一遍，有内容变了却没发的观测就记下来。
	var s := GameState.new_game(5, Balance.AI_COUNT, true)
	s.view_check = true
	var checked := 0
	for i in 100:
		if s.is_over():
			break
		s.end_turn()
		trace_long(s, "view_check100")
		checked += 1
	check(checked >= 60, "打了 %d 回合" % checked)
	check(s.view_missed_total == 0, "没有漏发的观测：漏了 %d 条" % s.view_missed_total)
