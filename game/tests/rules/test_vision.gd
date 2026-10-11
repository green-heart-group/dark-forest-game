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


## 规则：预警系统，情报传回
func test_steady_course_is_not_resent_every_sample() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.warnings[me.home]=0
	var start:=Vector3(1.5,0,0)
	var ship:=_ship(s,s.civs[1],Ship.WARSHIP,start,Vector3.UP)
	ship.gravity=true
	ship.speed=0.05
	var v0:=ship.direction*ship.speed/s.physical_cell_size()
	var a: Vector3=Kinematics.motion(s,s.civs[1],ship,0.0)["acceleration"]
	check(a.length()>0.0,"夹具里的战舰在加速")
	# 预警要飞 1.5 年才到，期间发出的每一条都还在路上，逐段数一遍就是发了多少条。
	var sent:={}
	var advance:=func(years: float):
		for i in roundi(years/Balance.PHYSICS_MAX_DT):
			WorldTime.advance(s,Balance.PHYSICS_MAX_DT)
			for m in s.messages:
				if m["body"].get("type")=="warning" and m["body"]["data"]["id"]==ship.id:
					sent[m["id"]]=true
	advance.call(2.9)
	# 每 0.05 年采样一次；照旧每次都发的话，2.9 年要发 58 条。
	check(sent.size()<=3,"加速度和航向不变时只有首发和每年的心跳，实际 %d 条" % sent.size())
	var alert: Dictionary=me.alerts.filter(func(x):return x["id"]==ship.id)[0]
	var known:=Combat.observed(s,alert)
	var t: float=known["t"]
	check(known["pos"].distance_to(start+v0*t+0.5*a*t*t)<1e-4,"收件方按速度和加速度推出那一刻的真实位置")
	check(known["velocity"].distance_to(v0+a*t)<1e-6,"也推出那一刻的真实速度")
	check(t<s.clock-1.4,"只推到「现在减去传播时间」，不提前知道")
	var before:=sent.size()
	ship.direction=Vector3.DOWN
	advance.call(0.05)
	check_eq(sent.size(),before+1,"航向一变就立即重发")


## 规则：情报传回
func test_relayed_reports_keep_exact_arrival_time() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	for x in 4:
		for y in 4:
			_set_star(s,Vector3i(x,y,1),StarMap.Star.SINGLE)
	s.ensure_cells()
	# 几个探测器散在不同位置，看到的星系离它们远近各不相同，观测到达的时刻也各不相同。
	for pos in [Vector3(0.3,0.7,0.2),Vector3(2.6,1.1,0.4),Vector3(1.2,3.3,0.9),Vector3(3.4,2.2,1.7)]:
		_ship(s,me,Ship.PROBE,pos)
	s.profiling=true
	WorldTime.advance(s,2.0)
	var steps: int=s.profile["连续/子步数"]
	var ticks:=roundi(1.0/Balance.PHYSICS_MAX_DT)
	# 这里没有别的事件，只该停在两年的采样刻度上；每到一条观测或转发就停一次的话要切 59 段以上。
	check(steps<=2*ticks+2,"两年切了 %d 段，不随到达的观测条数增加" % steps)
	check(me.intel.size()>4,"观测照样送到")
	# 观测先按光速走到探测器，探测器在到达那一刻转发回母星：收到时刻正好是两段光路之和，不等刻度。
	var home:=Vector3(me.home)
	var relayed:=0
	for cell in me.intel:
		var info: Dictionary=me.intel[cell]
		var eye:=me.ship_by_id(info["source_id"])
		if eye==null:
			continue
		relayed+=1
		var expected: float=info["t_observed"]+Signals.travel_time(s,Vector3(cell),eye.pos)+Signals.travel_time(s,eye.pos,home)
		check(absf(info["t_received"]-expected)<1e-6,"转发一手的观测按两段光路准时收到：%f 对 %f"%[info["t_received"],expected])
	check(relayed>0,"有经探测器转发的观测")


## 规则：视野
func test_unit_passing_through_view_between_samples_is_seen() -> void:
	# 子步放宽到一整年：敌方探测器在两次采样之间整个穿过战舰的视野，照样看到，观测时刻是进入视野那一刻。
	var keep:=Balance.PHYSICS_MAX_DT
	Balance.PHYSICS_MAX_DT=1.0
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var eye:=_ship(s,me,Ship.WARSHIP,Vector3(4,4,4))
	var passer:=_ship(s,s.civs[1],Ship.PROBE,Vector3(3.87,4.995,4),Vector3.RIGHT)
	WorldTime.advance(s,1.0)
	var outside:=not Signals.in_view(s,Signals.observers(s,me).filter(func(o):return o["id"]==eye.id)[0],passer.pos)
	WorldTime.advance(s,1.0)
	Balance.PHYSICS_MAX_DT=keep
	check(outside,"一年后探测器已经飞出视野")
	var entry:=(4.0-sqrt(1.0-0.995*0.995)-3.87)/0.3
	var contact: Dictionary=eye.local_contacts.get(passer.id,{})
	check(absf(contact.get("t_observed",-1.0)-entry)<1e-4,"按进入视野的时刻记观测：%f 对 %f"%[contact.get("t_observed",-1.0),entry])
	check(contact.get("pos",Vector3.ZERO).distance_to(Vector3(3.87+0.3*entry,4.995,4))<1e-4,"位置是进入视野那一刻的位置")


## 规则：视野
func test_cone_view_records_exact_entry_time() -> void:
	# 探测器的视野是朝前的圆锥。敌方光粒从侧面横穿圆锥，在两次采样之间进去又出来，照样看到，观测时刻按进入那一刻算。
	var keep:=Balance.PHYSICS_MAX_DT
	Balance.PHYSICS_MAX_DT=1.0
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var probe:=_ship(s,me,Ship.PROBE,Vector3(1,4,4),Vector3.RIGHT)
	var target:=_ship(s,s.civs[1],Ship.GRAIN,Vector3(2.1,4.3,4),Vector3.DOWN)
	WorldTime.advance(s,1.0)
	var eye: Dictionary=Signals.observers(s,me).filter(func(o):return o["id"]==probe.id)[0]
	check(not Signals.in_view(s,eye,target.pos),"一年后光粒已经离开圆锥")
	WorldTime.advance(s,2.0)
	Balance.PHYSICS_MAX_DT=keep
	# 圆锥长 1 光年：探测器以 0.3c 追近，0.1 光年后光粒进入圆锥远端，这时它已在圆锥里面（离轴不到张角）。
	var entry:=(1.1-1.0)/0.3
	var contact: Dictionary=probe.local_contacts.get(target.id,{})
	check(absf(contact.get("t_observed",-1.0)-entry)<1e-4,"圆锥视野按进入时刻记观测：%f 对 %f"%[contact.get("t_observed",-1.0),entry])


## 规则：情报传回
func test_seeing_enemy_ship_counts_as_discovery() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_ship(s,s.civs[1],Ship.PROBE,Vector3(1,0,0),Vector3.RIGHT)
	WorldTime.advance(s,0.9)
	check(not me.discovered,"敌方单位的真实存在不能瞬间触发发现")
	WorldTime.advance(s,0.2)
	check(me.discovered and me.known.is_empty(),"收到单位观测可触发发现，不透露它的母星")
