extends "res://tests/rules/rule_suite.gd"
## W7：四类船的普通航速分档；连续主流程、已知导航与旧记录兼容。

const KINDS := [Ship.PROBE, Ship.NUCLEAR_PROBE, Ship.COLONY, Ship.DEVOURER]
const TOPS := [0.3, 0.5, 0.4, 0.3]
const ACCELS := [0.0, 0.25, 0.08, 0.06]
const RAMP := [0.0, 2.0, 5.0, 5.0]
const ETA_3D := [[10.0/3.0, 10.0, 50.0/3.0], [3.0, 7.0, 11.0],
		[5.0, 10.0, 15.0], [35.0/6.0, 12.5, 115.0/6.0]]


func _space(dim: int = 3) -> GameState:
	var s := _two_civs(Vector3i(8,8,8))
	s._ensure_light()
	if dim < 3:
		s.fold_anchor = Vector3i.ZERO
		DimensionSpace.commit(s,false)
	if dim < 2:
		s.line_anchor = s.map.origin
		DimensionSpace.commit(s,true)
	for id in s.cell_dims:
		s.cell_dims[id] = dim
	for civ in s.civs:
		for asset in civ.assets:
			asset["entity_dim"] = dim
	return s


func _eta(length: float, top: float, accel: float) -> float:
	if accel == 0.0:
		return length / top
	var ramp_distance := top * top / (2.0 * accel)
	return sqrt(2.0 * length / accel) if length <= ramp_distance else top/accel+(length-ramp_distance)/top


## 规则：移动，W7
func test_v01_speed_parameters_and_other_units_unchanged() -> void:
	check_eq(Balance.values().get("SHIP_SPEED_RELATIVE"),1,"新局启用当地光速分档")
	for i in KINDS.size():
		var ship := Ship.make(KINDS[i],Vector3.ZERO,i)
		check_eq([ship.max_speed,ship.accel],[TOPS[i],ACCELS[i]],"四类船按授权的速度和加速度建造")
	check_eq(Balance.WARSHIP_MOVE,[0.15,0.01],"战舰速度不变")
	check_eq(Balance.STARSHIP_MOVE,[0.15,0.01],"星舰速度不变")
	check_eq(Balance.GRAIN_MOVE,[0.99,0.0],"光粒速度不变")
	check_eq(Balance.WARP_MOVE,[1.0,1.0],"曲率引擎既有速度和加速不变")
	check_eq([Balance.ACTION_BASE,Balance.HOME_BUILD_SLOTS,Balance.BUILD_SLOTS],[3,2,1],"保留AP3、母星双槽和其他单槽")
	check_eq(Balance.TECH_BURST_CHANCE,0.0,"技术爆炸继续关闭")


## 规则：移动，二维、单向著和奇异点，W7
func test_v01_speed_dimensional_caps_and_ramp_years() -> void:
	for dim in [3,2,1]:
		var s := _space(dim)
		var me := s.human()
		var c: float = {3:1.0,2:0.6,1:0.36}[dim]
		for i in KINDS.size():
			var ship := _ship(s,me,KINDS[i],Vector3(me.home),Vector3.RIGHT)
			ship.entity_dim = dim
			var limits := Kinematics.limits(s,me,ship,ship.pos,false)
			check(absf(limits[0]-TOPS[i]*c)<1e-10,"最高速度随所在维度光速缩放")
			check(absf(limits[1]-ACCELS[i]*c)<1e-10,"加速度同步缩放")
			var motion := Kinematics.motion(s,me,ship,20.0)
			if i == 0:
				check_eq(motion["speed"],limits[0],"化学探测器派出即为匀速")
				check_eq(motion["acceleration"],Vector3.ZERO,"化学探测器不增加虚构加速")
			else:
				check(absf(motion["cap_time"]-RAMP[i])<1e-10,"各维度从静止达到普通上限的年数相同")


## 规则：移动，W7
func test_v01_speed_rest_eta_matches_continuous_arrival() -> void:
	var preview = load("res://rules/navigation_preview.gd")
	for i in KINDS.size():
		for j in 3:
			var length: float = [1.0,3.0,5.0][j]
			var s := _space()
			var me := s.human()
			var ship := _ship(s,me,KINDS[i],Vector3(me.home))
			var target := me.home+Vector3i(int(length),0,0)
			var data: Dictionary = preview.compare(s,me,ship.pos,target,ship.id)
			check(absf(data["current"]["eta"]-ETA_3D[i][j])<1e-6,"1/3/5ly导航ETA包含完整加速段")
			check_eq(data["current"]["signal_eta"],length,"光行时未随舰速改变")
			s._set_target(ship,target)
			WorldTime.advance(s,ETA_3D[i][j]-0.001)
			check(ship.has_target,"预计到达前仍在航行，不提前瞬移")
			WorldTime.advance(s,0.00101)
			check(ship.pos.distance_to(Vector3(target))<1e-6,"连续主流程在预计时刻抵达")
			check(not ship.has_target and ship.direction==Vector3.ZERO and ship.speed==0.0,"抵达保留原停车行为")
			check(not ship.dead and not ship.dormant,"正常维护下航行不意外停机或销毁")
			# Godot Vector3为单精度，连续累积5ly的实测误差小于1e-5ly；不修改引擎的既有坐标精度。
			check(absf(ship.distance_flown-length)<1e-5,"实际物理路程不因逻辑格而变化：%s %sly，累计%.12f" % [KINDS[i],length,ship.distance_flown])


## 规则：移动，二维、单向著和奇异点，W7
func test_v01_speed_lower_dimension_eta_is_physical() -> void:
	var preview = load("res://rules/navigation_preview.gd")
	for dim in [2,1]:
		for i in KINDS.size():
			var s := _space(dim)
			var me := s.human()
			var ship := _ship(s,me,KINDS[i],Vector3(me.home))
			ship.entity_dim = dim
			var c: float = {2:0.6,1:0.36}[dim]
			for length in [1.0,3.0,5.0]:
				var goal := me.home+Vector3i(int(length/s.physical_cell_size()),0,0)
				var data: Dictionary = preview.compare(s,me,ship.pos,goal,ship.id)
				check_eq(data["current"]["distance"],length,"低维导航按物理ly计距")
				check(absf(data["current"]["eta"]-_eta(length,TOPS[i]*c,ACCELS[i]*c))<1e-6,"低维ETA同时缩放最高速和加速度")
				check(absf(data["current"]["signal_eta"]-length/c)<1e-6,"低维消息仍按当地光速传播")


## 规则：移动，二维、单向著和奇异点，W7
func test_v01_speed_cross_cell_and_entity_dimension_caps() -> void:
	var s := _space()
	var me := s.human()
	var ship := _ship(s,me,Ship.COLONY,Vector3.ZERO,Vector3.RIGHT)
	ship.speed = 0.4
	s.cell_dims[s.cell_ids[Vector3i(1,0,0)]] = 1
	var lower := Kinematics.limits(s,me,ship,Vector3(1,0,0),false)
	check(absf(lower[0]-0.144)<1e-10 and absf(lower[1]-0.0288)<1e-10,"三维实体进入一维格也服从当地普通航速")
	ship.pos = Vector3(1,0,0)
	var motion := Kinematics.motion(s,me,ship,1.0)
	check(absf(motion["speed"]-0.144)<1e-10,"跨低光速格立即限制现有速度")
	ship.entity_dim = 1
	ship.pos = Vector3.ZERO
	var own := Kinematics.limits(s,me,ship,ship.pos,false)
	check(absf(own[0]-0.144)<1e-10 and absf(own[1]-0.0288)<1e-10,"一维实体进入三维格不突破自身光速档")
	# 未准备的三维实体会在低维格被原迁维规则销毁；使用已经迁至一维的合法实体验证跨格。
	ship.entity_dim = 1
	var start := Vector3(0.49,0,0)
	ship.pos = start
	WorldTime.advance(s,0.2)
	check(not ship.dead and ship.pos.x>0.5 and ship.pos.x<0.54,"合法一维实体跨格保持当地普通航速限制")
	check(ship.speed<=0.144+1e-8,"边界后一维普通航速上限有效")


## 规则：黑域，移动，W7
func test_v01_speed_domain_scales_acceleration_and_stops_core() -> void:
	var s := _space()
	var me := s.human()
	var domain := Hazards.activate(s,Vector3.ZERO)
	domain["created"] = -20.0
	domain["expires"] = 30.0
	Hazards.refresh(s)
	var at := Vector3(0.5,0,0)
	var c := s.light_speed_at(at)
	check(c>0.0 and c<1.0,"测试位置位于黑域衰减区")
	for i in KINDS.size():
		var ship := _ship(s,me,KINDS[i],at,Vector3.RIGHT)
		ship.speed = TOPS[i]
		var limits := Kinematics.limits(s,me,ship,at,false)
		check(absf(limits[0]-TOPS[i]*c)<1e-10,"黑域按实际当地光速限制普通速度")
		check(absf(limits[1]-ACCELS[i]*c)<1e-10,"黑域同步限制加速度")
		ship.pos = Vector3.ZERO
		var motion := Kinematics.motion(s,me,ship,1.0)
		check_eq([motion["velocity"],motion["acceleration"]],[Vector3.ZERO,Vector3.ZERO],"黑域核心中不能靠加速逃逸")
		ship.dead = true


## 规则：黑域，移动，W7
func test_v01_speed_warp_override_and_one_dimensional_trail() -> void:
	for dim in [3,2,1]:
		var s := _space(dim)
		var me := s.human()
		for kind in [Ship.COLONY,Ship.DEVOURER]:
			var ship := _ship(s,me,kind,Vector3(me.home)+Vector3.RIGHT*4.0/s.physical_cell_size(),Vector3.RIGHT)
			ship.entity_dim = dim
			ship.warp = true
			var limits := Kinematics.limits(s,me,ship,ship.pos,false)
			var c: float = {3:1.0,2:0.6,1:0.36}[dim]
			check_eq(limits,[c,1.0],"曲率引擎在己方视野外仍覆盖普通速度档和原加速")
			ship.pos = Vector3(me.home)
			limits = Kinematics.limits(s,me,ship,ship.pos,false)
			check(absf(limits[0]-(0.4 if kind==Ship.COLONY else 0.3)*c)<1e-10,"己方视野内仍使用普通速度档")
			ship.dead = true
	var s := _space(1)
	var me := s.human()
	var ship := _ship(s,me,Ship.COLONY,Vector3(me.home)+Vector3.RIGHT*4.0/s.physical_cell_size(),Vector3.RIGHT)
	ship.entity_dim = 1
	ship.warp = true
	ship.speed = 0.36
	WorldTime.advance(s,0.05)
	check(not s.deadlines.is_empty(),"一维曲率速度虽低于三维设计值，仍应留下原机制航迹")


## 规则：移动，情报传回，W7
func test_v01_speed_reverse_turn_restarts_existing_acceleration() -> void:
	var s := _space()
	var me := s.human()
	var ship := _ship(s,me,Ship.DEVOURER,Vector3.ZERO,Vector3.RIGHT)
	ship.speed = 0.3
	check_eq(s.turn_ship(me,ship.id,Vector3.UP)["error"],"","吞食者仍能用原入口转向")
	Signals.receive_due(s)
	check_eq(ship.speed,0.3,"原垂直转向行为保留速度")
	me.actions_left = 3
	check_eq(s.turn_ship(me,ship.id,Vector3.DOWN)["error"],"","反向命令仍走共同合法性入口")
	Signals.receive_due(s)
	check_eq(ship.speed,0.0,"原反向转弯重置速度")
	WorldTime.advance(s,1.0)
	check(absf(ship.speed-0.06)<1e-6 and absf(ship.pos.y+0.03)<1e-6,"反向后从静止重新连续加速")
	for kind in [Ship.PROBE,Ship.NUCLEAR_PROBE]:
		var probe := _ship(s,me,kind,Vector3.ZERO,Vector3.RIGHT)
		check(s.turn_error(me,probe.id,Vector3.LEFT)!="","两种探测器不新增飞行中转向能力")


## 规则：情报传回，移动，W7
func test_v01_speed_remote_command_does_not_skip_light_delay() -> void:
	var s := _space()
	var me := s.human()
	var ship := _ship(s,me,Ship.DEVOURER,Vector3(4,0,0),Vector3.RIGHT)
	ship.speed = 0.3
	Signals.report_ship(s,me,ship)
	Signals.advance(s,4.0)
	s.clock = 4.0
	Signals.receive_due(s)
	check_eq(s.turn_ship(me,ship.id,Vector3.LEFT)["error"],"","根据已收遥测发送远程转向")
	WorldTime.advance(s,1.0)
	check_eq(ship.direction,Vector3.RIGHT,"舰速增加不让一光年内提前收到四光年外命令")
	check(not s.messages.is_empty(),"命令仍在有限光路上传播")
	check_eq(me.telemetry[ship.id]["t_observed"],0.0,"观测仍标注原观测时刻，不显示最新远端真值")


## 规则：情报传回，移动，二维、单向著和奇异点，W7
func test_v01_speed_navigation_hidden_medium_pair() -> void:
	var preview = load("res://rules/navigation_preview.gd")
	var a := _space()
	var me := a.human()
	var ship := _ship(a,me,Ship.COLONY,Vector3.ZERO)
	var b := StateCopy.copy(a)
	b.cell_dims[b.cell_ids[Vector3i(5,0,0)]] = 1
	Hazards.activate(b,Vector3(6,0,0))
	var x: Dictionary = preview.compare(a,me,Vector3.ZERO,Vector3i(7,0,0),ship.id)
	var y: Dictionary = preview.compare(b,b.human(),Vector3.ZERO,Vector3i(7,0,0),ship.id)
	check_eq(x,y,"未回传的维度和黑域变化不能通过速度、ETA或目标选项透视")


## 规则：存档和回放，移动，W7
func test_v01_speed_new_replay_and_state_copy() -> void:
	var s := GameState.new_game(42,1)
	var me := s.human()
	check_eq(s.build(me,"probe")["error"],"","正常新局建造化学探测器")
	s.end_turn()
	var ship: Ship = me.ships.filter(func(x):return x.kind==Ship.PROBE)[0]
	check_eq(s.dispatch(me,ship.id,Vector3.RIGHT)["error"],"","使用原派出入口")
	s.end_turn()
	check(absf(ship.distance_flown-0.3)<1e-6,"新局一年化学侦察移动0.3物理ly")
	var copy := StateCopy.copy(s)
	check_eq(copy.checksum(),s.checksum(),"新速度状态可完整复制")
	var replay := Replay.from_state(s)
	check_eq(replay.balance.get("SHIP_SPEED_RELATIVE"),1,"记录保存新速度规则开关")
	var path := "user://_test_tiered_speeds.forest"
	check_eq(replay.save(path),OK,"新规则存档成功")
	var loaded := Replay.load_file(path)
	check(loaded!=null,"新规则存档可读")
	if loaded!=null:
		var restored := loaded.play_to(s.steps)
		check_eq(loaded.desync_step,-1,"新规则连续回放无失步")
		check_eq(restored.checksum(),s.checksum(),"新速度和并行参数一同回放一致")
	DirAccess.remove_absolute(path)


## 规则：存档和回放，移动，W7
func test_v01_speed_old_replay_preserves_absolute_rules() -> void:
	var old := Replay.new()
	old.balance = Balance.values().duplicate(true)
	old.balance.erase("SHIP_SPEED_RELATIVE")
	old.balance["PROBE_MOVE"] = [0.01,0.0]
	old.balance["IPROBE_MOVE"] = [0.1,0.01]
	old.balance["COLONY_MOVE"] = [0.08,0.005]
	old.balance["DEVOURER_MOVE"] = [0.08,0.005]
	old.apply_balance()
	check_eq(Balance.values().get("SHIP_SPEED_RELATIVE"),0,"缺少新开关的旧记录按原规则重放")
	var s := _space(2)
	var me := s.human()
	var ship := _ship(s,me,Ship.COLONY,Vector3(me.home),Vector3.RIGHT)
	ship.entity_dim = 2
	check_eq(Kinematics.limits(s,me,ship,ship.pos,false),[0.08,0.005],"旧记录低维仍保留原绝对航速和加速度")
	check_eq([Balance.ACTION_BASE,Balance.HOME_BUILD_SLOTS],[3,2],"AP/双槽冻结记录的既有参数不受船速兼容回退影响")
