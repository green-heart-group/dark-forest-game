extends "res://tests/rules/rule_suite.gd"


## 规则：黑域
func test_v01_bounded_domains_overlap_and_expire() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	Hazards.activate(s, Vector3.ZERO)
	s.clock = 2.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3.ZERO), 0.0, "核心为零光速")
	check(absf(Hazards.suppression(s, Vector3(0.5, 0, 0)) - 1.0/3.0) < 1e-7, "半径中点单源权重2，s=1/3")
	check_eq(Hazards.suppression(s, Vector3(1.0, 0, 0)), 1.0, "外边界源权重为0")
	Hazards.activate(s, Vector3.ZERO)
	s.clock = 4.0
	Hazards.refresh(s)
	check(absf(Hazards.suppression(s, Vector3(0.5, 0, 0)) - 0.2) < 1e-7, "两个源权重相加而非概率相乘")
	s.clock = 19.0
	Hazards.activate(s, Vector3.ZERO)
	s.clock = 20.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3.ZERO), 1.0, "后投放不能延长首次覆盖格的20年硬到期")
	s.clock = 29.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3.ZERO), 1.0, "10年免疫期内忽略重复黑域")
	s.clock = 30.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3.ZERO), 0.0, "免疫结束后仍活跃源才可以重新封锁")
	s.clock = 40.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3.ZERO), 1.0, "所有源真实到期后不留无限扩散残场")


## 规则：黑域，移动
func test_v01_deadlines_take_minimum_and_keep_lifetime() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var ship := _ship(s, s.human(), Ship.WARSHIP, Vector3.ZERO)
	Hazards.leave_deadline(s, Vector3.ZERO, Vector3.RIGHT, ship)
	s.clock = 1.0
	s.turn = 2
	Hazards.leave_deadline(s, Vector3.ZERO, Vector3.RIGHT, ship)
	check_eq(Hazards.suppression(s, Vector3(0.5, 0, 0)), 0.8, "死线重叠不反复相乘成永久堵图")
	check_eq(Hazards.suppression(s, Vector3(0.5, 0.1, 0)), 1.0, "半径.05ly以外不受影响")
	s.clock = 20.5
	Hazards.refresh(s)
	check_eq(s.deadlines.size(), 1, "第一条寿命不被第二条刷新")
	s.clock = 21.0
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s, Vector3(0.5, 0, 0)), 1.0, "20年后每条死线独立到期")


## 规则：黑域，移动
func test_v01_deadline_identity_does_not_multiply_with_message_substeps() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var ship:=_ship(s,s.human(),Ship.WARSHIP,Vector3.ZERO)
	# 仅几何寿命夹具：两段足够长，避免半径覆盖相邻段干扰到期断言。
	s.clock=0.01
	Hazards.leave_deadline(s,Vector3.ZERO,Vector3.RIGHT,ship,0.01)
	var first_id: int=s.deadlines[0]["id"]
	s.clock=0.02
	Hazards.leave_deadline(s,Vector3.RIGHT,Vector3(2,0,0),ship,0.01)
	check_eq(s.deadlines.size(),1,"同一固定采样区间的直线航迹不因消息细分产生新ID")
	check_eq(s.deadlines[0]["id"],first_id,"延伸保留航迹身份")
	s.clock=20.011
	Hazards.refresh(s)
	check_eq(Hazards.suppression(s,Vector3(0.5,0,0)),1.0,"聚合身份不延长第一小段寿命")
	check_eq(Hazards.suppression(s,Vector3(1.5,0,0)),0.8,"后一段仍按自己的真实形成时刻保留")
	s.clock=20.021
	Hazards.refresh(s)
	check(s.deadlines.is_empty(),"末段到期后整条删除")
