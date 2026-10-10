extends "res://tests/rules/rule_suite.gd"


## 规则：AI 怎么行动，每回合的收入
func test_v01_ai_recovers_startup_mineral_without_gifts() -> void:
	var s := GameState.new_game(0, 1)
	var me := s.human()
	me.energy = 63.0
	me.mineral = 1.0
	for n in 6:
		AI._bootstrap_mining(s, me)
		s.end_turn()
	check(me.miner_count() >= 1, "1M零产矿残局由合法应急恢复首矿船")
	check_eq(s.mineral_income(me), 2.0, "唯一新增经常收入来自真实完工矿船")
	var emergency := me.ledger.filter(func(item): return item.get("kind", "") == "grant")
	check(emergency.is_empty(), "恢复不使用赠款")
	var works := s.history.filter(func(item): return item["name"] == "emergency_work" and item["civ"] == 0)
	check_eq(works.size(), 2, "仅用两次1M应急筹齐3M首矿船")
	check_eq(works[0]["args"], ["M",Signals.controller(me)], "应急资源ID与执行锚点符合后端契约")


## 规则：AI 怎么行动，建造
func test_v01_ai_accepted_orders_are_not_failed_completed_units() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.techs["warship"] = true
	me.techs["beam"] = true
	me.hit_dirs.append({"turn": s.turn, "dir": Vector3.RIGHT, "at": me.home})
	check(AI._try_warship_hit_dir(s, me), "反击分支将已受理工程视为一次成功行动")
	check_eq(me.count(Ship.WARSHIP), 0, "受理没有凭空创建即时舰船")
	check_eq(me.pending.size(), 1, "仅提交一个工程")
	check_eq(me.pending[0]["modules"], ["beam"], "反击分支显式支付武器模块")
	check(not AI._try_warship_hit_dir(s, me), "队列冲突返回失败且不重复受理")
	var money := [me.energy, me.mineral, me.actions_left]
	AI._try_warship_hit_dir(s, me)
	check_eq([me.energy, me.mineral, me.actions_left], money, "拒绝重复工程不扣款/AP")


func _interface_match() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s, civ)
	return s


## 规则：AI 怎么行动，建造，调度（派出和行动）
func test_v01_starship_only_ai_uses_paid_transport_and_landing() -> void:
	var s:=_interface_match()
	var me:=s.human()
	_give(me,["interstellar_travel","colony"])
	var carrier:=_ship(s,me,Ship.STARSHIP,Vector3(2,0,0))
	s._lose_system(me.home,me)
	var target:=Vector3i(3,0,0)
	_set_habitable(s,target,StarMap.Star.SINGLE)
	me.intel[target]=s.snapshot(target)
	var before: float=me.mineral
	AI._starship_turn(s,me)
	check_eq(Knowledge.pending(me,"colony"),1,"只剩移动锚点仍可选择最近已知目标并受理运输工程")
	check_eq(me.mineral,before-Construction.cost("colony")[1],"工程预付真实材料")
	_turns(s,3)
	AI._starship_turn(s,me)
	var ships:=me.ships.filter(func(ship):return ship.kind==Ship.COLONY)
	check_eq(ships.size(),1,"不靠免费定居复制生存锚点")
	if ships.is_empty(): return
	check(s.ship_command_pending(me,ships[0].id) or ships[0].moving(),"向已知宜居目标派出完工运输船")
	_turns(s,22)
	AI._starship_turn(s,me)
	check_eq(Knowledge.pending(me,"landing"),1,"收到到达遥测后提交付费落地")
	_turns(s,6)
	check(me.owns(target) and not carrier.dead and me.count(Ship.COLONY)==0,"工程完成消耗运输船，保留原星舰与新殖民锚点")


func _receive_telemetry(s: GameState, civ: Civ, ship: Ship) -> void:
	Signals.report_ship(s, civ, ship)
	var duration := ship.pos.distance_to(Vector3(civ.home)) * s.physical_cell_size() / s.background_light()
	Signals.advance(s, duration)
	s.clock += duration
	Signals.receive_due(s)


## 规则：AI 怎么行动，情报传回
func test_v01_ai_steers_from_received_telemetry_not_remote_truth() -> void:
	for hidden_change in ["move", "destroy"]:
		var s := _interface_match()
		var me := s.human()
		var target := Vector3i(6, 0, 0)
		me.known[target] = s.turn
		var ship := _ship(s, me, Ship.WARSHIP, Vector3(2, 0, 0), Vector3.UP)
		_receive_telemetry(s, me, ship)
		if hidden_change == "move":
			ship.pos = Vector3(2, 2, 0)
			ship.direction = Vector3.RIGHT
		else:
			ship.dead = true
			me.ships.erase(ship)
		check(AI._try_turn_warships(s, me), "远端变化尚未回传时，仍可按旧遥测提交转向")
		var commands := s.history.filter(func(item): return item["name"] == "turn_ship")
		check_eq(commands.size(), 1, "只提交一次转向")
		if not commands.is_empty():
			check_eq(commands[0]["args"][1], Vector3.RIGHT, "方向从收到的位置计算，不读取真实新位置")


## 规则：AI 怎么行动，调度（派出和行动）
func test_v01_ai_waits_for_command_receipt_and_uses_discounted_cost() -> void:
	var s := _interface_match()
	var me := s.human()
	me.known[Vector3i(6, 0, 0)] = s.turn
	me.techs["dark_energy"] = true
	me.energy = AI.RESERVE
	var ship := _ship(s, me, Ship.WARSHIP, Vector3(2, 0, 0), Vector3.UP)
	_receive_telemetry(s, me, ship)
	check(AI._try_turn_warships(s, me), "调度折扣归零后，保留6E也可转向")
	check(s.ship_command_pending(me, ship.id), "发送后命令尚未确认")
	var before := [me.energy_millis, me.mineral_millis, me.actions_left, s.history.size()]
	check(not AI._try_turn_warships(s, me), "不对等待确认的舰船重复下同类命令")
	check_eq([me.energy_millis, me.mineral_millis, me.actions_left, s.history.size()], before, "等待不重复扣资源或AP")


## 规则：AI 怎么行动
func test_v01_ai_waits_for_received_transport_arrival() -> void:
	var s := _interface_match()
	var me := s.human()
	_give(me, ["interstellar_travel", "colony"])
	var target := Vector3i(3, 0, 0)
	_set_habitable(s, target, StarMap.Star.SINGLE)
	me.intel[target] = s.snapshot(target)
	me.colony_tried[target] = true
	var ship := _ship(s, me, Ship.COLONY, Vector3(2, 0, 0), Vector3.RIGHT)
	_receive_telemetry(s, me, ship)
	ship.pos = Vector3(target)
	ship.direction = Vector3.ZERO
	ship.docked = false
	check(not AI._try_colonize(s, me), "实际到达但未回传时，不提前发起落地")
	check(me.pending.is_empty(), "遥测到达前没有落地工程")
	_receive_telemetry(s, me, ship)
	check(AI._try_colonize(s, me), "收到到达遥测后可以提交落地")
	check_eq(me.pending.size(), 1, "仅提交一个落地项目")


## 规则：AI 怎么行动，建造
func test_v01_ai_sophon_uses_accepted_order_contract() -> void:
	var s := _interface_match()
	var me := s.human()
	me.techs["sophon"] = true
	me.known[s.civs[1].home] = s.turn
	check(AI._try_sophon(s, me), "智子预付订单受理后返回成功")
	check_eq(me.count(Ship.SOPHON), 0, "受理时没有即时完成智子")
	check_eq(me.pending_count("sophon"), 1, "只有一个待完成智子订单")
	check(me.sophon_tried.is_empty(), "尚未发出航行命令，不记录为已派遣")


## 规则：AI 怎么行动
func test_v01_ai_singularity_builds_ammo_and_targets_known_enemy() -> void:
	var s := _interface_match()
	var me := s.human()
	s.dimension = 1
	me.line_reduced = true
	me.techs["dimension"] = true
	me.energy = 1000
	me.mineral = 1000
	var target := Vector3i(6, 0, 0)
	me.known[target] = s.turn
	check(AI._try_foil(s, me), "一维零弹药时先下单维度武器")
	check_eq(me.pending_count("dimension_weapon"), 1, "维度武器只预付一单")
	check(s.payloads.is_empty(), "弹药未完成不发射")
	var before := [me.energy_millis, me.mineral_millis, me.actions_left]
	check(not AI._try_foil(s, me), "已有弹药订单时等待完成")
	check_eq([me.energy_millis, me.mineral_millis, me.actions_left], before, "等待工程不重复扣费")
	s._finish_pending(me, Construction.work("dimension_weapon"))
	check(AI._try_foil(s, me), "弹药完成后可朝已知敌方坐标发射")
	check_eq(me.dimension_ammo, 0, "发射只消耗一枚已完成弹药")
	check_eq(s.payloads.size(), 1, "只有一个奇异点载荷")
	if not s.payloads.is_empty():
		check_eq(s.payloads[0]["target"], Vector3(target), "不再用默认母星坐标作为奇异点目标")


## 规则：AI 怎么行动
func test_v01_ai_singularity_has_no_target_without_received_intel() -> void:
	var s := _interface_match()
	var me := s.human()
	s.dimension = 1
	me.line_reduced = true
	me.techs["dimension"] = true
	me.dimension_ammo = 1
	check(not AI._try_foil(s, me), "没有已知敌方坐标就不发射奇异点")
	check_eq(me.dimension_ammo, 1, "未发射时保留弹药")
	check(s.payloads.is_empty(), "不会读取敌方真实位置或对母星发射")


## 规则：AI 怎么行动
func test_v01_ai_conversion_waits_for_ready_receipt() -> void:
	var s := _interface_match()
	var me := s.human()
	me.techs["dimension"] = true
	me.known[s.civs[1].home] = s.turn
	me.times_hit = Balance.AI_FOIL_HITS
	me.energy = 1000
	me.mineral = 1000
	var host := _ship(s, me, Ship.STARSHIP, Vector3(2, 0, 0))
	Signals.report_ship(s,me,host)
	Signals.advance(s,2.0)
	s.clock+=2.0
	Signals.receive_due(s)
	check_eq(s.prepare_conversion(me, Conversion.roster(me, s.dimension), host.id, false, true)["error"], "", "远端锚点预付本级迁维准备工程")
	var plan_id: int = me.pending[0]["id"]
	check(not me.pending[0]["command_ready"],"远端宿主尚未收到开工命令")
	Signals.advance(s,2.0)
	s.clock += 2.0
	Signals.receive_due(s)
	s._finish_pending(me, WorkOrder.amount(me.pending[0]["work"]))
	Signals.receive_due(s)
	check(me.conversions[plan_id]["ready_at"].is_empty(), "准备完成消息尚未处理")
	var before := [me.energy_millis, me.mineral_millis, me.actions_left]
	check(not AI._try_foil(s, me), "收到ready收据以前等待，不空发执行指令")
	check_eq([me.energy_millis, me.mineral_millis, me.actions_left], before, "等待收据不重复付费或扣AP")
	check(me.pending.is_empty(), "已有迁维计划时不新开同级准备工程")
	Signals.advance(s, 2.0)
	s.clock += 2.0
	Signals.receive_due(s)
	check(AI._try_foil(s, me), "收到本地控制锚点ready收据后执行迁维")
	check(me.reduced, "执行沿合法接口转换本地锚点")


## 规则：AI 怎么行动
func test_v01_ai_failed_starship_move_does_not_blacklist_target() -> void:
	var s := _interface_match()
	var me := s.human()
	var target := Vector3i(3, 0, 0)
	_set_habitable(s, target, StarMap.Star.SINGLE)
	me.intel[target] = s.snapshot(target)
	_ship(s, me, Ship.STARSHIP, Vector3.ZERO)
	me.colonies.clear()
	me.energy = 0
	AI._starship_turn(s, me)
	check(not me.colony_tried.has(target), "调度被余额拒绝时不把目的地标为已尝试")
	check(s.history.is_empty(), "失败移动不留下成功行动记录")


## 规则：AI 怎么行动，情报传回
func test_v01_ai_retries_only_after_failed_command_receipt() -> void:
	for kind in [Ship.COLONY, Ship.SOPHON]:
		var s := _interface_match()
		var me := s.human()
		var target := Vector3i(6, 0, 0)
		_give(me, ["interstellar_travel", "colony", "sophon"])
		if kind == Ship.COLONY:
			_set_habitable(s, target, StarMap.Star.SINGLE)
			me.intel[target] = s.snapshot(target)
		else:
			me.known[target] = s.turn
		var ship := _ship(s, me, kind, Vector3(2, 0, 0))
		_receive_telemetry(s, me, ship)
		check(AI._try_colonize(s, me) if kind == Ship.COLONY else AI._try_sophon(s, me), "依据已到达情报发送目的地命令")
		var tried: Dictionary = me.colony_tried if kind == Ship.COLONY else me.sophon_tried
		check(tried.has(target), "受理命令后防止重复派往该目标")
		ship.dead = true
		me.ships.erase(ship)
		me.actions_left = 0
		AI.take_turn(s, me)
		check(tried.has(target), "远端真实死亡不能提前恢复目标")
		Signals.advance(s, 2.0)
		s.clock += 2.0
		Signals.receive_due(s)
		AI.take_turn(s, me)
		check(tried.has(target), "命令已失败但回执仍在途中时继续等待")
		Signals.advance(s, 2.0)
		s.clock += 2.0
		Signals.receive_due(s)
		AI.take_turn(s, me)
		check(not tried.has(target), "收到失败回执后允许重新选择同一目标")
		check_eq(me.ai_receipt_cursor, me.command_results.size(), "每份到达回执只处理一次")
		tried[target] = true
		AI.take_turn(s, me)
		check(tried.has(target), "旧失败回执不清除后续的新尝试")


## 规则：AI 怎么行动，每回合的收入
func test_v01_ai_upgrade_cannot_spend_first_miner_reserve() -> void:
	var s := _interface_match()
	var me := s.human()
	me.energy = 100
	me.mineral = Construction.cost("miner")[1]
	AI._research(s, me)
	check_eq(me.mineral, 3.0, "未有矿源时保留首艘矿船的全部3M预算")
	check(me.research_project.is_empty() and me.pending.is_empty(), "研究和望远镜升级均不能抢走首矿船预算")
	check_eq(me.actions_left, 3, "未受理项目不消耗AP")


## 规则：AI 怎么行动，每回合的收入
func test_v01_ai_research_is_one_paid_order_not_instant_tech() -> void:
	var s := _interface_match()
	var me := s.human()
	me.discovered = true
	me.miners[me.home] = 1
	var cost := Tech.cost("warship")
	me.energy = cost[0] + AI.RESERVE
	me.mineral = cost[1]
	AI._research(s, me)
	check_eq(me.research_project.get("kind", ""), "warship", "0级非初始科技也通过合法研究下单")
	check(not me.has_tech("warship"), "研究受理时尚未获得科技")
	check_eq([me.energy, me.mineral, me.actions_left], [float(AI.RESERVE), 0.0, Balance.ACTION_BASE-1], "按[E,M]精确预付并扣1AP")
	var before := [me.energy_millis, me.mineral_millis, me.actions_left]
	AI._research(s, me)
	check_eq([me.energy_millis, me.mineral_millis, me.actions_left], before, "研究队列忙时不能重复下单或扣款")


## 规则：AI 怎么行动，情报传回
func test_v01_ai_front_estimate_uses_only_received_observations() -> void:
	var s := _interface_match()
	var me := s.human()
	me.techs["dimension"] = true
	var nearby := me.home + Vector3i.RIGHT
	s.foil_zones.append({"id": s.next_id(), "center": nearby, "created": s.clock, "age": 0.0})
	check(s.turns_until_flat(me.home) <= Balance.AI_REDUCE_ALERT, "测试准备：真实隐藏前沿已经在避险阈值内")
	check(not AI._flat_near(s, me), "尚无已收到观测时，AI不能读取真实前沿提前避险")
	s.foil_zones.clear()
	me.intel[nearby] = {"cell_dim": 2, "t_observed": s.clock}
	check(AI._flat_near(s, me), "收到近处转换格观测后，按历史信息估计并触发避险")
	me.intel.erase(nearby)
	me.alerts.append({"payload_kind": "domain", "pos": Vector3(me.home) + Vector3(2, 0, 0),
			"velocity": Vector3.LEFT, "t_observed": s.clock})
	check(not AI._flat_near(s, me), "黑域载荷预警不误判为降维前沿")
	me.alerts[0]["payload_kind"] = "dimension"
	check(AI._flat_near(s, me), "收到临近的维度载荷轨迹才按原阈值触发避险")
