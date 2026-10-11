extends "res://tests/rules/rule_suite.gd"
## 黑域：光速变慢、扩散、挡住视野，以及为提速做的捷径。


## 把整张星图的光速都设成 c，不再扩散（测试用）。
func _fill_light(s: GameState, c: float) -> void:
	s._ensure_light()
	s.light.fill(c)
	s._light_moving = false


## 规则：黑域
func test_black_domain_payload_activation_radius_and_expiry() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var center:=Vector3i(2,0,0)
	check(s.launch_black_domain(me,center)["error"]!="","未解锁不可投放")
	me.techs["domain"]=true
	check(s.launch_black_domain(me,Vector3i(5,0,0))["error"]!="","没有已收情报与覆盖的目标拒绝")
	check_eq(s.launch_black_domain(me,center)["error"],"","公开入口投放")
	check_eq([me.energy,me.mineral,me.actions_left],[52.0,88.0,Balance.ACTION_BASE-1],"48E12M及1AP预付")
	check(s.launch_black_domain(me,center)["error"]!="","20年冷却生效")
	WorldTime.advance(s,4.2)
	check(s.black_domains.is_empty(),"2ly/.9c飞行后还需2年激活")
	WorldTime.advance(s,0.1)
	check(s.black_domains.size()==1 and s.relative_light(Vector3(center))==0,"真实激活后核心零光速")
	WorldTime.advance(s,2.0)
	check(absf(s.relative_light(Vector3(2.5,0,0))-1.0/3.0)<0.00001,"半径1ly内按权重衰减")
	check_eq(s.relative_light(Vector3(3.01,0,0)),1.0,"有界场不扩散到半径之外")
	WorldTime.advance(s,18.1)
	check(s.black_domains.is_empty() and s.relative_light(Vector3(center))==1.0,"激活20年到期后恢复，无全图残场")


## 规则：黑域
func test_light_caps_ships_and_disarms_grains() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	Hazards.activate(s,Vector3(3,0,0))
	s.clock=2.0
	Hazards.refresh(s)
	var war:=_ship(s,me,Ship.WARSHIP,Vector3(3.5,0,0),Vector3.RIGHT)
	war.warp=true
	war.speed=1.0
	var motion:=Kinematics.motion(s,me,war,0.05)
	check(absf(motion["speed"]-1.0/3.0)<0.00001,"已达光速的曲率舰被当地有效光速限速")
	var grain:=_ship(s,me,Ship.GRAIN,Vector3(3.5,0,0),Vector3.RIGHT)
	var probe:=_ship(s,me,Ship.PROBE,Vector3(3,0,0),Vector3.RIGHT)
	WorldTime.advance(s,0.1)
	check(grain.dead,"低于.95相对光速的光粒失效")
	check(probe.dead,"进入低于.01相对光速核心的舰船直接毁灭，不使用旧5年计时")
	check(not war.dead and war.pos.x>3.5 and war.pos.x<3.55,"非核心中的舰船继续有限移动")
	me.grains[me.home]=true
	Hazards.activate(s,Vector3(me.home))
	check(s.grain_error(me,Vector3.RIGHT)!="","核心内的发射源不能投送光粒")


## 规则：黑域
func test_black_domain_blocks_vision_and_slows_reports() -> void:
	var s:=_two_civs(Vector3i(4,0,0))
	var me:=s.human()
	me.telescope=3
	Hazards.activate(s,Vector3(2,0,0))
	s.clock=2.0
	Hazards.refresh(s)
	var message:=Signals.send(s,0,Vector3(4,0,0),Signals.controller(me),"report",{
		"type":"own","data":{"id":9001},"source_id":9001,"t_observed":s.clock,"epoch":0})
	WorldTime.advance(s,8.0)
	check(not me.telemetry.has(9001) and message["pos"].x>2.0,"实际消息沿途减速并停在核心外，不瞬间回报")
	var held:Vector3=message["pos"]
	WorldTime.advance(s,0.5)
	check(message["pos"].is_equal_approx(held),"源仍存在时消息停留，不从源头重发")
	check(not me.known.has(s.civs[1].home),"有效视距也不能让核心后的观测即时穿越")
	WorldTime.advance(s,14.0)
	check(me.telemetry.has(9001),"场到期后从原进度继续传播，最终报告到达")


## 只为提速的捷径（回合末看之前先算好的数据、只扫线段附近的格子），和直接一格一格算的结果一样。
## 规则：黑域
func test_speedups_match_plain_checks() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := StarMap.SIZE
	s._ensure_light()
	for i in 6:
		s.light[rng.randi_range(0, s.light.size() - 1)] = 0.0
	s.light_version += 1
	s.system_cells.clear()
	for x in n:
		for y in n:
			for z in n:
				if (x + 2 * y + 3 * z) % 4 == 0:
					s.system_cells.append(Vector3i(x, y, z))
	var rand_pos := func() -> Vector3:
		return Vector3(rng.randf_range(-1.0, n), rng.randf_range(-1.0, n), rng.randf_range(-1.0, n))
	s._begin_view_cache()
	var blocked_same := true
	var near_same := true
	for i in 400:
		var a: Vector3 = rand_pos.call()
		var b: Vector3 = a + (rand_pos.call() - a) * rng.randf()
		blocked_same = blocked_same and s.blocked(a, b) == (s.light_time(a, b) == INF)
		var reach := rng.randf_range(0.5, 5.0)
		var round := rng.randf() < 0.5
		var plain: Array[Vector3i] = []
		for c in s.system_cells:
			var v := Vector3(c) - a
			if absf(v.x) <= reach and absf(v.y) <= reach and absf(v.z) <= reach and (not round or v.length() <= reach):
				plain.append(c)
		near_same = near_same and s._systems_near(a, reach, round) == plain
	s._view_cache = {}
	check(blocked_same, "有没有被光速为 0 的格子挡住：先排除离得远的，结果不变")
	check(near_same, "按 (x, y) 分好再找附近的星系：找到的格子和顺序都不变")
	var cells_same := true
	for i in 300:
		var a: Vector3 = rand_pos.call()
		var b: Vector3 = a + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var radius := 0.5 if rng.randf() < 0.5 else 0.0
		var d := b - a
		var dir := d.normalized()
		var plain: Array[Vector3i] = []
		for x in n:
			for y in n:
				for z in n:
					var v := Vector3(x, y, z) - a
					var t := v.dot(dir)
					if d.length() >= 1e-9 and t > 0.0 and t <= d.length() and (v - dir * t).length() <= radius + Geometry.CELL_HALF:
						plain.append(Vector3i(x, y, z))
		var fast := Geometry.segment_cells(a, b, radius, s.map.bounds())
		fast.sort()
		cells_same = cells_same and fast == plain
	check(cells_same, "飞一步扫过的格子：只扫线段附近，结果不变")


## 规则：黑域，每回合的收入
func test_domain_does_not_invent_anchor_elimination_or_output_multiplier() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.techs["fission"]=true
	s.map.rocky[me.home]=4
	var full:=s.energy_income(me)
	Hazards.activate(s,Vector3(me.home))
	WorldTime.advance(s,1.0)
	check_eq(s.energy_income(me),full,"产能依实体Q和维护，不再套旧黑域十分之一倍率")
	check(me.alive and not s.is_over(),"永久星系锚点仍存续，不因通信中断宣告灭亡")
	check_eq(s.emergency_work(me,"M")["error"],"","原地锚点保留应急作业")


## 规则：黑域
func test_message_through_domain_takes_exact_time() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var center:=Vector3(4,4,4)
	Hazards.activate(s,center)
	s.clock+=4.0
	Hazards.refresh(s)
	var from:=Vector3(1,4.3,4)
	var to:=Vector3(7,4.3,4)
	var size:=s.physical_cell_size()
	var steps:=60000
	var expected:=0.0
	for i in steps:
		var at:=from.lerp(to,(i+0.5)/steps)
		expected+=from.distance_to(to)*size/steps/s.light_speed_at(at)
	var eta:=Signals.travel_time(s,from,to)
	check(absf(eta-expected)<1e-4,"穿过黑域的用时按公式算准：%f 对 %f"%[eta,expected])
	check(eta>from.distance_to(to)*size/s.background_light()+0.5,"黑域确实让消息慢了")
	var half:=Hazards.light_travel(s,from,Vector3.RIGHT,from.distance_to(to)*size,eta*0.5)
	var rest:=Signals.travel_time(s,from+Vector3.RIGHT*half["distance"]/size,to)
	check(absf(half["time"]+rest-eta)<1e-6,"走一半时间停下，剩下的路再走正好补齐")


## 规则：黑域
func test_bounded_domain_uses_physical_radius_in_new_dimensions() -> void:
	var s:=_two_dimensional_match()
	var center:=Vector3(13,13,s.flat_plane)
	Hazards.activate(s,center)
	s.clock+=4.0
	Hazards.refresh(s)
	check_eq(s.light_speed_at(center),0.0,"二维黑域核心为零")
	check(absf(s.light_speed_at(center+Vector3.RIGHT)-0.2)<0.00001,"二维1逻辑格=.5ly，.6背景光速乘1/3场系数")
	check_eq(s.light_speed_at(center+Vector3(3,0,0)),0.6,"超过1ly后恢复二维背景光速")
	check_eq(s.cell_ids.size(),729,"物理场不丢失永久格身份")


## 规则：黑域
func test_domain_released_mid_year_grows_from_release_time() -> void:
	# 子步放宽到一整年：载荷在年中到达，黑域在准确时刻释放，回合之间看到的大小按释放时刻算。
	var keep:=Balance.PHYSICS_MAX_DT
	Balance.PHYSICS_MAX_DT=1.0
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.techs["domain"]=true
	check_eq(s.launch_black_domain(me,Vector3i(2,0,0))["error"],"","投放")
	for i in 5:
		WorldTime.advance(s,1.0)
	Balance.PHYSICS_MAX_DT=keep
	var release:=2.0*s.physical_cell_size()/(Balance.DOMAIN_PAYLOAD_SPEED*s.background_light())+Balance.DOMAIN_ACTIVATION
	check_eq(s.black_domains.size(),1,"黑域已释放")
	var source: Dictionary=s.black_domains[0] if not s.black_domains.is_empty() else {"created":-1.0}
	check(absf(source["created"]-release)<1e-6,"释放时刻是载荷到达后再等激活时间：%f 对 %f"%[source["created"],release])
	check(absf(Hazards.radius(s,source,s.clock)-(5.0-release)*Balance.DOMAIN_SPREAD*s.background_light())<1e-6,"第 5 年看到的半径按释放时刻算")


## 规则：黑域
func test_message_through_growing_domain_is_not_early() -> void:
	# 黑域还在长大时，消息从旁边穿过。和每 0.0001 年按当时的半径一步步走的结果比：不早到，也晚不了多少。
	var keep:=Balance.PHYSICS_MAX_DT
	Balance.PHYSICS_MAX_DT=1.0
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var center:=Vector3(2,0.3,0)
	var source:=Hazards.activate(s,center)
	WorldTime.advance(s,0.5)
	var from:=Vector3(4,0,0)
	Signals.send(s,0,from,Signals.controller(me),"report",{"type":"own","data":{"id":9001},"source_id":9001,"t_observed":s.clock,"epoch":0})
	for i in 10:
		WorldTime.advance(s,1.0)
	Balance.PHYSICS_MAX_DT=keep
	var size:=s.physical_cell_size()
	var pos:=from
	var t:=0.5
	var step:=0.0001
	while pos.x>0.0:
		var reach:=Hazards.radius(s,source,t)
		var d:=pos.distance_to(center)*size
		var c:=s.background_light()
		if d<=reach:
			c/=1.0+Balance.DOMAIN_WEIGHT*(1.0-d/reach)
		pos.x-=c*step/size
		t+=step
	check(me.telemetry.has(9001),"消息送到了")
	var got: float=me.telemetry.get(9001,{}).get("t_received",-1.0)
	check(got>=t-1e-3,"不早到：%f 对 %f"%[got,t])
	check(got<t+0.2,"也不会晚太多：%f 对 %f"%[got,t])


## 规则：黑域，移动
func test_probe_entering_domain_mid_year_slows_down() -> void:
	# 探测器在年中飞进长到最大的黑域：子步一整年和子步 0.001 年算出的位置差不多，而且确实慢了下来。
	var ends := []
	for dt in [1.0,0.001]:
		var keep:=Balance.PHYSICS_MAX_DT
		Balance.PHYSICS_MAX_DT=dt
		var s:=_two_civs(Vector3i(8,8,8))
		Hazards.activate(s,Vector3(4,4,4))
		s.clock=3.0
		Hazards.refresh(s)
		var probe:=_ship(s,s.human(),Ship.PROBE,Vector3(2.9,4.3,4),Vector3.RIGHT)
		WorldTime.advance(s,1.0)
		Balance.PHYSICS_MAX_DT=keep
		ends.append(probe.pos.x)
	check(absf(ends[0]-ends[1])<0.02,"一年一步和细分的位置相差不到 0.02 光年：%f 对 %f"%ends)
	check(ends[0]<2.9+0.3-0.02,"进了黑域就减速")


## 规则：黑域
func test_grain_disarmed_where_light_drops_below_limit() -> void:
	# 子步一整年：光粒冲进黑域，在光速正好降到 GRAIN_MIN_LIGHT 的那一层失效，不等下一次切分。
	var keep:=Balance.PHYSICS_MAX_DT
	Balance.PHYSICS_MAX_DT=1.0
	var s:=_two_civs(Vector3i(8,8,8))
	var center:=Vector3(4,4,4)
	Hazards.activate(s,center)
	s.clock=3.0
	Hazards.refresh(s)
	var grain:=_ship(s,s.civs[1],Ship.GRAIN,Vector3(2.5,4,4),Vector3.RIGHT)
	WorldTime.advance(s,1.0)
	Balance.PHYSICS_MAX_DT=keep
	var layer:=Balance.DOMAIN_RADIUS*(1.0-(1.0/Balance.GRAIN_MIN_LIGHT-1.0)/Balance.DOMAIN_WEIGHT)
	check(grain.dead,"光粒失效")
	check(absf(grain.pos.distance_to(center)*s.physical_cell_size()-layer)<1e-3,"在那一层失效：离中心 %f，那一层 %f"%[grain.pos.distance_to(center)*s.physical_cell_size(),layer])