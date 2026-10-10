extends "res://tests/rules/rule_suite.gd"


func _wave_match() -> GameState:
	var s:=_two_civs(Vector3i(8,8,8))
	for civ in s.civs: Assets.ensure(s,civ)
	return s


## 规则：广播和隐藏文明
func test_v01_broadcast_intercepts_moving_receiver() -> void:
	var s:=_wave_match()
	var other:=s.civs[1]
	var receiver:=_ship(s,other,Ship.STARSHIP,Vector3(2,0,0),Vector3.RIGHT)
	receiver.gravity=true
	receiver.speed=0.12
	Information.broadcast(s,s.human(),Vector3.ZERO,Vector3i(4,4,4),GameState.NO_HIT)
	WorldTime.advance(s,2.2)
	check(s.broadcasts[0]["heard"].is_empty(),"移动接收器在2.2年时仍在半径2.2之外")
	WorldTime.advance(s,0.2)
	check(s.broadcasts[0]["heard"].has(other),"连续波面追上移动接收器，不要求回到发射时位置")
	check(not other.heard.has(Vector3i(4,4,4)),"本地收到后还须转发到远方控制锚点")
	check(s.messages.any(func(m):return m["body"].get("type")=="broadcast" and m["body"]["t_observed"]>2.2),"保留实际相交时刻")


## 规则：广播和隐藏文明
func test_v01_broadcast_reaches_new_receiver_but_not_wave_tail() -> void:
	var s:=_wave_match()
	var other:=s.civs[1]
	Information.broadcast(s,s.human(),Vector3.ZERO,Vector3i(4,4,4),GameState.NO_HIT)
	WorldTime.advance(s,1.0)
	var behind:=_ship(s,other,Ship.STARSHIP,Vector3(0.2,0,0))
	behind.gravity=true
	WorldTime.advance(s,0.2)
	check(s.broadcasts[0]["heard"].is_empty(),"在波后新建接收器不追溯收到过去的广播")
	var ahead:=_ship(s,other,Ship.STARSHIP,Vector3(1.8,0,0))
	ahead.gravity=true
	WorldTime.advance(s,0.7)
	check(s.broadcasts[0]["heard"].has(other),"发射后才出现、但仍在前沿之前的接收器会收到")


## 规则：广播和隐藏文明
func test_v01_uniform_light_does_not_stop_waves_at_cell_edges() -> void:
	var s:=_wave_match()
	# 发射点不在格心：朝 (0,0,1) 的光线先过 z=0.5 的格子边界，晚于它才到最近的格心。
	Information.broadcast(s,s.human(),Vector3(0.1,0.2,0.3),Vector3i(4,4,4),GameState.NO_HIT)
	check(Hazards.uniform_light(s),"没有黑域和死线，各格光速相同")
	var arrival:=INF
	for sample in s.broadcasts[0]["samples"]:
		arrival=minf(arrival,sample["remaining"]/s.light_speed_at(sample["pos"]))
	check_eq(Information.next_change(s,true),arrival,"光速处处相同时，下一次变化是最早的到达，不在格子边界停")
	Hazards.activate(s,Vector3(6,6,6))
	check(not Hazards.uniform_light(s),"有黑域时光速会变")
	check(Information.next_change(s,false)<arrival,"有黑域时照旧在格子边界停，换成新格子的光速")


## 规则：广播和隐藏文明
func test_v01_uniform_light_keeps_broadcast_years_short() -> void:
	var s:=_wave_match()
	Information.broadcast(s,s.human(),Vector3(0.1,0.2,0.3),Vector3i(4,4,4),GameState.NO_HIT)
	s.profiling=true
	WorldTime.advance(s,1.0)
	var steps: int=s.profile["连续/子步数"]
	# 每条光线过一次格子边界就切一刀时，一年要切几百段。
	check(steps<=2*roundi(1.0/Balance.PHYSICS_MAX_DT),"一年只切 %d 段，不随光线过格子边界的次数增加" % steps)


## 规则：情报传回
func test_v01_scan_intercepts_new_moving_target_and_returns_later() -> void:
	var s:=_wave_match()
	var me:=s.human()
	me.techs["gravity_scan"]=true
	check_eq(s.active_scan(me,Vector3.RIGHT)["error"],"","正式发出扫描")
	WorldTime.advance(s,1.0)
	var ship:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3,0.9,0),Vector3.DOWN)
	ship.speed=0.15
	WorldTime.advance(s,2.2)
	check(s.scans[0]["propagation"]["received"].has(ship.id),"扫描击中发射后出现并持续移动的目标")
	check(not me.sightings.any(func(x):return x["id"]==ship.id),"3光年之外的观测还未回到母星")
	WorldTime.advance(s,3.2)
	check(me.sightings.any(func(x):return x["id"]==ship.id and x["t_received"]>x["t_observed"]+2.5),"回传之后才成为玩家与AI共同的历史信息")


## 规则：广播和隐藏文明，黑域
func test_v01_front_uses_historical_medium_not_current_radius() -> void:
	var s:=_wave_match()
	Information.broadcast(s,s.human(),Vector3.ZERO,Vector3i(4,4,4),GameState.NO_HIT)
	var wave: Dictionary=s.broadcasts[0]
	Hazards.activate(s,Vector3.ZERO)
	Information.advance(s,2.0)
	s.clock=2.0
	var env:=LightFront.environment(s)
	check(LightFront.difference(s,wave,Vector3(1,0,0),s.clock,env)>0.0,"源在黑域核心的两年不能当作已走两光年")
	s.clock=21.0
	Hazards.refresh(s)
	# 保留真实阻塞历史；字段恢复并不把停住的光瞬移补发。
	LightFront.remember(wave,env,2.0,20.0)
	var restored:=LightFront.environment(s)
	LightFront.remember(wave,restored,20.0,20.5)
	s.clock=20.5
	check(LightFront.difference(s,wave,Vector3(1,0,0),s.clock,restored)>0.0,"恢复后只走恢复期间的有限距离")
	LightFront.remember(wave,restored,20.5,21.1)
	s.clock=21.1
	check(LightFront.difference(s,wave,Vector3(1,0,0),s.clock,restored)<0.0,"实际走满后才越过一光年点")


## 规则：二向箔，广播和隐藏文明
func test_v01_front_remaps_current_light_position_and_replays() -> void:
	var s:=_wave_match()
	Information.broadcast(s,s.human(),Vector3.ZERO,Vector3i(4,4,4),GameState.NO_HIT)
	Information.advance(s,0.25)
	s.clock=0.25
	var original:=s.map
	s.human().assets[0]["ready"][2]={"plan":7,"fraction":0.75,"at":0.1}
	var destination:=Vector3(0,0,2)
	var mapped:=DimensionSpace.point(destination,Vector3i.ZERO,false,original)
	s.fold_anchor=Vector3i.ZERO
	DimensionSpace.commit(s,false)
	var wave: Dictionary=s.broadcasts[0]
	check_eq(wave["propagation"]["origin"],Vector3.ZERO,"历史发射坐标不被递归重写")
	check_eq(wave["propagation"]["events"][-1]["at"],0.25,"波保存实际换图时刻")
	check_eq(s.human().assets[0]["ready"][2]["plan"],7,"整数步骤键的准备收据随实体迁移，不与字符串字段名比较报错")
	var env:=LightFront.environment(s)
	var old_ray:=DimensionSpace.point(Vector3(0,0,0.25),Vector3i.ZERO,false,original)
	var expected:=old_ray.distance_to(mapped)*s.physical_cell_size()/s.background_light()
	check(absf(LightFront.difference(s,wave,mapped,s.clock+0.01,env)-(expected-0.01))<0.01,"从映射后的当前波前继续，不能按新距离套旧半径补发")
	var copy:=StateCopy.copy(s)
	check_eq(copy.checksum(),s.checksum(),"波前传播历史与换图事件可独立保存恢复")
