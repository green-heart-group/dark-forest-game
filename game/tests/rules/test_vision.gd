extends "res://tests/rules/rule_suite.gd"
## 当前时钟中的目标→传感器→指挥锚点两段信息；保留原视野功能。


## 规则：视野，情报传回
func test_home_vision_discovers_neighbour() -> void:
	var s:=_two_civs(Vector3i(2,0,0))
	var me:=s.human()
	WorldTime.advance(s,1.9)
	check(me.known.is_empty(),"母星视野也需要2ly信号传播")
	WorldTime.advance(s,0.2)
	check(me.known.has(Vector3i(2,0,0)) and me.discovered,"传到后发现邻居")
	check_eq(me.intel[Vector3i(2,0,0)]["owner"],1,"收到的所有权正确")
	var far:=_two_civs(Vector3i(3,0,0))
	WorldTime.advance(far,3.0)
	check(far.human().known.is_empty(),"3ly超出初始视野，等时间也不能透视")
	for i in 2:
		check_eq(far.upgrade(far.human(),"telescope")["error"],"","望远镜升级付费下单")
		_turns(far,i+2)
	_turns(far,4)
	check(far.human().known.has(Vector3i(3,0,0)),"升级完工且目标信号到达后才看见")


## 规则：情报传回
func test_probe_report_travels_back_at_light_speed() -> void:
	var s:=_two_civs(Vector3i(6,0,0))
	var me:=s.human()
	_ship(s,me,Ship.PROBE,Vector3(5,0,0))
	WorldTime.advance(s,5.9)
	check(me.known.is_empty() and not me.discovered,"目标→5ly处接收器1年，加返回5年，未满6年不送达")
	WorldTime.advance(s,0.2)
	check(me.known.has(Vector3i(6,0,0)) and me.discovered,"两段传播完成才确认发现")
	var report: Dictionary=me.intel[Vector3i(6,0,0)]
	check(report["t_observed"]<report["t_received"] and report["t_received"]>=6.0-0.0001,"观察与到达时间分别保存")


## 规则：移动，视野
func test_wakes_are_left_and_seen() -> void:
	var s:=_two_civs(Vector3i(3,2,0))
	var ai:=s.civs[1]
	var ship:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0),Vector3.UP)
	ship.warp=true
	WorldTime.advance(s,0.3)
	check(not s.deadlines.is_empty(),"真实曲率运动留下有限寿命航迹")
	check(ai.wake_reports.is_empty(),"在视野中并不等于波已传到")
	ship.direction=Vector3.ZERO # 限定短轨迹夹具，之后只观察已形成的航迹。
	ship.speed=0.0
	WorldTime.advance(s,2.1)
	check(not Knowledge.presentation(s,ai).wakes.is_empty(),"两端观测实际传回后保留地图航迹")
	check(ai.sightings.any(func(record):return record["id"]==ship.id),"舰船观测也按有限传播接收")


## 规则：预警系统
func test_warning_reports_enemy_warship() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.warnings[me.home]=0
	var near:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(1.8,0,0),Vector3.LEFT)
	_ship(s,s.civs[1],Ship.WARSHIP,Vector3(5,0,0),Vector3.LEFT)
	WorldTime.advance(s,1.7)
	check(me.alerts.is_empty(),"预警不能早于轨迹信号到达")
	WorldTime.advance(s,0.3)
	check(me.alerts.size()==1 and me.alerts[0]["id"]==near.id,"只报告预警范围内且已收到的实际敌舰")


## 规则：情报传回
func test_seeing_enemy_ship_counts_as_discovery() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_ship(s,s.civs[1],Ship.PROBE,Vector3(1,0,0),Vector3.RIGHT)
	WorldTime.advance(s,0.9)
	check(not me.discovered,"敌方单位的真实存在不能瞬间触发发现")
	WorldTime.advance(s,0.2)
	check(me.discovered and me.known.is_empty(),"收到单位观测可触发发现，不透露它的母星")
