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
	Signals.advance(s, 1.0)
	s.clock = 1.0
	Signals.receive_due(s)
	check(not me.intel.has(cell), "目标光先到远程探测器，不能同刻进入母星地图")
	check_eq(s.messages.size(), 1, "接收后从探测器发送独立回传")
	Signals.advance(s, 2.0)
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
	Signals.advance(s, 0.5)
	var pos: Vector3 = message["pos"]
	s.set_light_at(Vector3i(pos.round()), 0.0)
	Signals.advance(s, 20.0)
	check_eq([message["pos"], message["distance"]], [pos, 0.5], "零光速暂停，不清空或从源头重发")
	s.set_light_at(Vector3i(pos.round()), 1.0)
	Signals.advance(s, 1.5)
	s.clock = 22.0
	Signals.receive_due(s)
	check(me.telemetry.has(999) and s.messages.is_empty(), "恢复后继续剩余路径并只送达一次")


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
	Signals.advance(s,2.0) # 端点位于曲率死线内，初始有效光速也会减慢。
	s.clock=2.0
	Signals.receive_due(s)
	check(Knowledge.presentation(s,me).wakes.is_empty(),"侦察器已收到，但控制端还需等第二程")
	Signals.advance(s,2.0)
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
	Signals.advance(s,2.0)
	s.clock=2.0
	Signals.receive_due(s)
	Signals.advance(s,2.0)
	s.clock=4.0
	Signals.receive_due(s)
	check(me.wake_reports.has(9999) and me.wake_reports[9999].has(0),"近端已完整传回")
	check(not me.wake_reports.get(9999,{}).has(1),"视野以外端点不随近端消息送出")
	check(Knowledge.presentation(s,me).wakes.is_empty(),"只收到近端仍不能拼出整条线段")
