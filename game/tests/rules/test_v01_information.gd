extends "res://tests/rules/rule_suite.gd"


func information_match(target := Vector3i(8,8,8)) -> GameState:
	var s := _two_civs(target)
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	return s


## 规则：每回合的收入
func test_v01_coverage_deduplicates_and_requires_live_chain() -> void:
	var s := information_match(Vector3i(1,0,0))
	var me := s.human()
	_give(me,["antimatter_collection","dark_energy"])
	var empty := Vector3i(2,0,0)
	_set_star(s,empty,StarMap.Star.NONE)
	check_eq(s.energy_income(me),0.0,"只有历史/未知星图时收集不提前生效")
	WorldTime.advance(s,2.1)
	check_eq(s.energy_income(me),6.0,"两个有星星系各1E，当前无星系统1+3E")
	var probe := _ship(s,me,Ship.PROBE,Vector3.ZERO)
	WorldTime.advance(s,1.1)
	check_eq(s.energy_income(me),6.0,"多观察者重复覆盖不叠加星系收入")
	probe.dead = true
	me.stopped_packages.append(Economy.package_key("anchor",me.home))
	check_eq(s.energy_income(me),0.0,"源停机后旧报告不继续供能")
	me.stopped_packages.clear()
	var core := Hazards.activate(s,Vector3(0.5,0,0))
	s.clock += 1.0
	Hazards.refresh(s)
	check_eq(s.energy_income(me),1.0,"黑域核心截断远方链路，保留原地有效覆盖")
	check(core["id"]>=0,"场源具有永久ID")


## 规则：建造
func test_v01_miner_needs_real_owned_deposit() -> void:
	var s := information_match()
	var me := s.human()
	check(s.build(me,"miner")["error"]!="","无类地矿点不能凭空造矿船")
	check_eq([me.energy,me.mineral,me.actions_left],[100.0,100.0,Balance.ACTION_BASE],"拒绝保持资源/AP")
	s.map.rocky[me.home] = 1
	check_eq(s.build(me,"miner")["error"],"","补齐真实矿点夹具后可合法下单")


## 规则：情报传回
func test_v01_scan_is_round_trip_and_original_mother_only() -> void:
	var target := Vector3i(4,0,0)
	var s := information_match(target)
	var me := s.human()
	me.techs["gravity_scan"] = true
	check_eq(s.active_scan(me,Vector3.RIGHT)["error"],"","母星发出8E扫描")
	check_eq([me.energy,me.actions_left],[92.0,Balance.ACTION_BASE-1],"扫描费用/AP来自统一规则")
	check(s.active_scan(me,Vector3.RIGHT)["error"]!="","十年冷却阻止重复")
	WorldTime.advance(s,7.9)
	check(not me.known.has(target),"四光年目标不足八年不能往返送达")
	WorldTime.advance(s,0.2)
	check(me.known.has(target),"扫描结果完成往返后到达")
	check(me.intel[target]["t_observed"]>=4.0-1e-5,"观测时刻是波前到达时")
	check(me.intel[target]["t_received"]>=8.0-1e-5,"回传时刻独立于观测时刻")
	var backup := Vector3i(0,2,0)
	_set_habitable(s,backup,StarMap.Star.SINGLE)
	me.colonies.append(backup)
	Assets.ensure(s,me)
	s._lose_system(me.original_home,me)
	Signals.advance(s,2.0)
	s.clock = 12.0
	Signals.receive_due(s)
	check(s.scan_error(me,Vector3.RIGHT)!="","后继殖民地不能冒充原母星扫描器")


## 规则：广播和隐藏文明
func test_v01_broadcast_keeps_travelling_after_emitter_jammed() -> void:
	var s := information_match(Vector3i(2,0,0))
	var me := s.human()
	var other := s.civs[1]
	me.broadcasters[me.home] = true
	other.broadcasters[other.home] = true
	Assets.ensure(s,me)
	Assets.ensure(s,other)
	var target := Vector3i(3,0,0)
	check_eq(s.broadcast(me,target)["error"],"","广播被接受")
	var droplet := _ship(s,other,Ship.DROPLET,Vector3(me.home))
	droplet.parked = true
	check(s.broadcast_error(me,target)!="","水滴只阻止新广播")
	WorldTime.advance(s,1.9)
	check(not other.heard.has(target),"不足传播时间不能听到")
	WorldTime.advance(s,0.2)
	check(other.heard.has(target),"已离开发射器的波仍然到达")


## 规则：预警系统
func test_v01_warning_is_observed_trajectory_with_delay() -> void:
	var s := information_match()
	var me := s.human()
	me.warnings[me.home] = 0
	Assets.ensure(s,me)
	var grain := _ship(s,s.civs[1],Ship.GRAIN,Vector3(1.5,0,0),Vector3.RIGHT)
	WorldTime.advance(s,1.4)
	check(me.alerts.is_empty(),"预警尚未收到轨迹光信号")
	WorldTime.advance(s,0.2)
	check(not me.alerts.is_empty(),"实际观察到的来袭轨迹回传后出现")
	if not me.alerts.is_empty():
		check_eq(me.alerts[0]["id"],grain.id,"预警针对实际单位ID")
		check(me.alerts[0]["t_received"]>me.alerts[0]["t_observed"],"保留观测/到达两个时刻")
		check(not me.alerts[0].has("target"),"不从引擎真实目标字段提前泄密")


## 规则：反物质
func test_v01_antimatter_is_four_damage_after_flight() -> void:
	var s := information_match()
	var me := s.human()
	var target := _ship(s,s.civs[1],Ship.STARSHIP,Vector3(0.5,0,0))
	me.antimatter = 1
	check(s.antimatter_targets(me).is_empty(),"真实敌舰尚未观测不能进入行动目标")
	WorldTime.advance(s,0.55)
	check_eq(s.use_antimatter(me)["error"],"","按收到的目标观测发出炸弹")
	check_eq([me.antimatter,me.actions_left,target.damage],[0,Balance.ACTION_BASE-1,0],"发射消耗弹药与AP但不瞬杀")
	WorldTime.advance(s,0.3)
	check_eq(target.damage,0,"光速弹丸仍未到达")
	WorldTime.advance(s,0.3)
	check_eq(target.damage,4,"命中只造成4物理伤害")
	check(not target.dead,"六HP星舰没有被旧即时移除逻辑误杀")
