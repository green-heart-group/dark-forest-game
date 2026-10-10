extends "res://tests/rules/rule_suite.gd"
## V0.1 的经济契约：固定精度、先付后做、资源不足原子失败、取消仅退未耗部分。


## 规则：每回合的收入，科技树
func test_v01_start_and_three_ap() -> void:
	var s := GameState.new_game(21, 1)
	var me := s.human()
	check_eq([me.energy, me.mineral], [5.0, 10.0], "V0.1 开局5E10M")
	check_eq(me.ships.size(), 0, "初始无舰船")
	check_eq(Tech.ALL.size(), 34, "完整34科技")
	check_eq(Tech.starting(), ["miner", "fission", "telescope", "probe", "warning"], "只有五项初始科技")
	var edges := 0
	for id in Tech.ALL:
		edges += Tech.ALL[id]["needs"].size()
	check_eq(edges, 21, "保留21条显式前置")
	check(StarMap.star_count(s.map.star_at(me.home)) >= 1 and s.map.rocky.get(me.home, 0) >= 1, "母星具备最小裂变条件")
	me.colonies.append(Vector3i(-10, 0, 0))
	s.start_turn(me)
	check_eq(me.actions_left, 3, "殖民数和恒星数不增加每回合3AP")
	me.reduced = true
	me.line_reduced = true
	s.start_turn(me)
	check_eq(me.actions_left, 3, "一维也为3AP")
	check_eq(me.output_factor(), 0.36, "一维产出Q为.36")
	me.line_reduced = false
	check_eq(me.output_factor(), 0.6, "二维产出Q为.6")


## 规则：每回合的收入
func test_v01_fixed_point_stock() -> void:
	var me := Civ.new("定点测试", false, Vector3i.ZERO)
	me.energy = 0.0
	me.mineral = 0.0
	for i in 10:
		me.energy += 0.1
		me.mineral += 0.001
	check_eq(me.energy, 1.0, "分数能量在.001精度累计，不被整数截断")
	check_eq(me.mineral, 0.01, "千分之一矿石不丢失")
	me.energy -= 0.999
	check_eq(me.energy, 0.001, "扣款保持相同固定精度")


## 规则：每回合的收入，建造，科技树
func test_v01_ledger_reconciles_paid_orders_commands_and_refunds() -> void:
	var s:=GameState.new_game(2,1)
	for civ in s.civs: s.set_autoplay(civ,false)
	var me:=s.human()
	var initial:=[me.energy_millis,me.mineral_millis]
	check_eq(s.build(me,"miner")["error"],"","正式下单矿船，托管支出入账")
	for i in 3: s.end_turn()
	check_eq(s.research(me,"warship")["error"],"","正式下单研究，支出入账")
	s.end_turn()
	check_eq(s.cancel_order(me,me.research_project["id"])["error"],"","正式取消未完工研究，回传退款入账")
	check_eq(s.build(me,"probe")["error"],"","正式下单探测器")
	for i in 3: s.end_turn()
	var probe:=AI._docked(s,me,Ship.PROBE)
	check(probe!=null,"探测器已完成并回传")
	if probe!=null: check_eq(s.dispatch(me,probe.id,Vector3.RIGHT)["error"],"","正式派出，命令支出入账")
	for i in 3: s.end_turn()
	var expected:=initial.duplicate()
	for entry in me.ledger:
		if entry.has("delta"):
			for a in 2: expected[a]+=entry["delta"][a]
	check_eq([me.energy_millis,me.mineral_millis],expected,"初始库存加逐笔收支，精确等于千分单位当前库存")
	var prior:=me.ledger.size()
	check(s.build(me,"dimension_weapon")["error"]!="","未解锁的采购失败")
	check_eq(me.ledger.size(),prior,"采购失败不新增支出")


## 规则：科技树，建造
func test_v01_research_is_paid_work_and_cancellable() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_open_tiers(me, 3)
	var ap := me.actions_left
	var before := [me.energy, me.mineral]
	check_eq(s.research(me, "warship")["error"], "", "可研究非初始0级科技")
	check(not me.has_tech("warship"), "支付研究款不会立即完成")
	check_eq(me.actions_left, ap - 1, "研究消耗1AP")
	check_eq([me.energy, me.mineral], [before[0]-1.0,before[1]-5.0], "全额预付且M/E顺序正确")
	check("research_project" in me and s.has_method("cancel_order"), "研究托管与主动取消接口存在")
	if not "research_project" in me or not s.has_method("cancel_order"):
		return
	var project: Dictionary = me.get("research_project")
	check(not project.is_empty(), "研究占用唯一研究队列")
	if project.is_empty():
		return
	var id: int = project["id"]
	check(s.research(me, "fusion")["error"] != "", "在制研究阻止第二项研究")
	s.end_turn()
	check(not me.has_tech("warship"), "两工作量研究在一年后还未完成")
	before = [me.energy, me.mineral]
	check_eq(s.call("cancel_order", me, id)["error"], "", "取消剩余研究")
	check_eq([me.energy, me.mineral], [before[0]+0.5,before[1]+2.5], "只退未耗的一半托管")
	check(me.get("research_project").is_empty(), "取消释放研究队列")
	check(s.call("cancel_order", me, id)["error"] != "", "重复取消不重复退款")


## 规则：建造，每回合的收入
func test_v01_construction_queue_and_completion() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[me.home] = 1
	var m: float = me.mineral
	check_eq(s.build(me, "miner")["error"], "", "可下单基础采矿船")
	check_eq(me.mineral, m-3.0, "下单支付3M")
	check_eq(s.build(me,"probe")["error"],"","母星第二槽可并行建造探测器")
	var paid := [me.energy, me.mineral, me.actions_left]
	check(s.build(me, "probe")["error"] != "", "母星两槽占满后拒绝第三项")
	check_eq([me.energy, me.mineral, me.actions_left], paid, "队列冲突不扣资源或AP")
	s.end_turn()
	check_eq(me.miner_count(), 0, "两工作量矿船一年后未完成")
	s.end_turn()
	check_eq(me.miner_count(), 1, "两年后完成一艘矿船")
	check_eq(s.mineral_income(me), 2.0, "只计算真实矿船，不凭空给星系基础产矿")
	check_eq(me.pending.size(), 0, "完成释放锚点队列")


## 规则：建造，科技树，灭亡和胜负
func test_v01_host_destruction_burns_escrow() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var backup := Vector3i(2, 0, 0)
	_set_habitable(s, backup, StarMap.Star.SINGLE)
	me.colonies.append(backup)
	_open_tiers(me, 3)
	s.research(me, "warship")
	s.build(me, "warning")
	var stock := [me.energy, me.mineral]
	s._lose_system(Vector3i.ZERO, me, "测试")
	check_eq([me.energy, me.mineral], stock, "宿主被毁没有退款")
	check_eq(me.pending.size(), 0, "预警项目也随宿主被毁")
	check("research_project" in me, "研究保存明确宿主")
	if "research_project" in me:
		check(me.get("research_project").is_empty(), "研究宿主被毁立即中止")


## 规则：科技树
func test_v01_research_failure_is_atomic() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_open_tiers(me, 3)
	me.energy = 0
	me.mineral = 5
	var before := [me.energy, me.mineral, me.actions_left, me.techs.duplicate()]
	check(s.research(me, "warship")["error"] != "", "不能用未来产出来预付研究")
	check_eq([me.energy, me.mineral, me.actions_left, me.techs], before, "失败不产生局部扣费或科技")


## 规则：建造，自身降维
func test_v01_escrow_conversion_conservation() -> void:
	var project := WorkOrder.create(31, "warship", Vector3i.ZERO, [1, 5], 2.0)
	check(not WorkOrder.advance(project, 1.0), "一半工作量尚未完成")
	check(WorkOrder.retain(project, "3>2", 0.75), "首次完整迁维收据生效")
	check(not WorkOrder.retain(project, "3>2", 0.4), "同一次迁维不能重复结算或改换留存率")
	check_eq(WorkOrder.refund(project), [0.375, 1.875], "未消耗托管按75%保留")
	check_eq(WorkOrder.salvage(project), [0.375, 1.875], "已消耗回收账按同一收据保留")
	check_eq(project["done"], 1000, "迁维不倒扣工作进度")
	check(WorkOrder.advance(project, 1.0), "不需二次付款即可完成")
	check_eq(WorkOrder.refund(project), [0.0, 0.0], "完工后没有未耗托管")
	check_eq(WorkOrder.salvage(project), [0.75, 3.75], "完工回收基数恰为折损后的实付成本")


## 规则：每回合的收入
func test_v01_maintenance_is_atomic_and_unscaled() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.energy = 0
	me.mineral = 0
	me.reduced = true
	me.miners[me.home] = 1
	me.dysons[me.home] = 1
	check_eq(s.energy_income(me), 6.0, "二维戴森毛产出10E乘Q=.6")
	check_eq(s.mineral_income(me), 0.7, "二维矿产1.2M减固定.5M维护")
	s.end_turn()
	check_eq([me.energy, me.mineral], [6.0, 0.7], "同回合产出可支付维护，原子结算无借贷")
	me.miners.clear()
	me.mineral = 0
	s.end_turn()
	check_eq(me.energy, 6.0, "付不起矿石维护时戴森关闭，不白拿能量")
	check_eq(me.mineral, 0.0, "维护不会透支")


## 规则：每回合的收入，建造
func test_v01_dormant_colony_and_emergency_work() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var colony := Vector3i(1, 0, 0)
	_set_habitable(s, colony, StarMap.Star.SINGLE)
	s._add_colony(me, colony)
	me.energy = 0
	me.mineral = 0
	s.end_turn()
	check(me.dormant_colonies.has(colony), "无法维持整座生产包时殖民地休眠")
	check(me.owns(colony) and me.alive, "休眠仍是存续锚点")
	var stock := [me.energy, me.mineral]
	check_eq(s.emergency_work(me, "M")["error"], "", "休眠文明仍可主动应急作业")
	check_eq([me.energy, me.mineral], [stock[0], stock[1]+1.0], "一次只获得选定的一种资源")
	check(s.emergency_work(me, "E")["error"] != "", "每文明每回合最多一次应急作业")
	check_eq(s.mineral_income(me), 0.0, "应急作业不计经常产能")


## 规则：科技树，每回合的收入
func test_v01_tier_event_and_reference_income() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.reduced = true
	s.map.rocky[me.home] = 4
	me.advanced_miners[me.home] = 3
	s._refresh_permissions(me)
	check_eq(me.tier1_turn, -1, "仅有产能没有发现事件不开放I级")
	me.discovered = true
	s._refresh_permissions(me)
	check(me.tier1_turn >= 0, "名义净产能达12M4E，即使二维实际收入较低仍可获得权限")
	me.advanced_miners.clear()
	s._refresh_permissions(me)
	check(me.tier1_turn >= 0, "得到的权限不会因产能下降撤销")


## 规则：建造，科技树
func test_v01_bare_hull_and_explicit_modules() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["warship", "beam"])
	check_eq(s.build_cost(me, "warship"), [1, 5], "解锁武器后仍保留裸舰价格")
	check_eq(s.build_cost(me, "warship", ["beam"]), [2, 7], "只加入实际选装模块")
	check_eq(s.build(me, "warship")["error"], "", "可造裸舰")
	_turns(s, 3)
	check_eq(me.ships.size(), 1, "裸舰按3工作量完工")
	check(me.ships[0].weapons.is_empty(), "研究不自动安装武器")
	check_eq(s.build(me, "warship", me.home, ["beam"])["error"], "", "可选择束流模块")
	_turns(s, 3)
	check_eq(me.ships.size(), 1, "模块工时加入舰体工时")
	s.end_turn()
	check_eq(me.ships.size(), 2, "选装舰第4工作量完工")
	check_eq(me.ships[1].weapons, ["beam"], "仅装入所选武器")


## 规则：建造，预警系统
func test_v01_upgrades_have_costs_and_work() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	check(s.has_method("upgrade_price"), "升级有按当前等级计算的双资源价格接口")
	if not s.has_method("upgrade_price"):
		return
	check_eq(s.call("upgrade_price", me, "telescope", me.home), [3, 3], "第一级望远镜3E3M")
	check_eq(s.upgrade(me, "telescope")["error"], "", "升级订单成功")
	check_eq(me.telescope, 0, "升级不立即生效")
	s.end_turn()
	check_eq(me.telescope, 1, "一级望远镜工作量1")
	check_eq(s.call("upgrade_price", me, "telescope", me.home), [6, 6], "第二级望远镜6E6M")


## 规则：建造，交战
func test_v01_refit_preserves_damage_and_paid_cost() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["warship", "alloy"])
	s.build(me, "warship")
	_turns(s, 3)
	var ship := me.ships[0]
	ship.damage = 1
	check(s.has_method("refit_ship"), "有显式逐舰改装入口")
	if not s.has_method("refit_ship"):
		return
	var before := [me.energy, me.mineral]
	check_eq(s.call("refit_ship", me, ship.id, ["alloy"])["error"], "", "合金改装可下单")
	check_eq([me.energy, me.mineral], [before[0], before[1]-4.0], "只付新模块成本")
	check(not ship.modules.has("alloy"), "未完成的模块不生效")
	check(s.dispatch_error(me, ship.id, Vector3.RIGHT) != "", "在制改装舰不能带着工程出发")
	s.end_turn()
	check(ship.modules.has("alloy"), "一工作量后安装模块")
	check_eq(ship.damage, 1, "改装保留绝对损伤，不免费修理")
	check_eq(ship.cost, [1.0, 9.0], "可回收基数只增加已付模块成本")
	check(s.call("refit_ship", me, ship.id, ["alloy"])["error"] != "", "已装模块不能重复收费/重复增益")


## 规则：建造，调度（派出和行动）
func test_v01_transport_landing_separate_escrow() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["colony", "interstellar_travel"])
	var target := Vector3i(1, 0, 0)
	_set_habitable(s, target, StarMap.Star.SINGLE)
	var transport := _ship(s, me, Ship.COLONY, Vector3(target))
	s._settle(me, transport)
	_received_landing_site(s,me,transport)
	check(not me.owns(target), "到达不能绕过落地工程免费殖民")
	check(s.has_method("start_landing"), "有明确的付费落地入口")
	if not s.has_method("start_landing") or me.owns(target):
		return
	var stock := [me.energy, me.mineral]
	check_eq(s.call("start_landing", me, transport.id)["error"], "", "无主星系由运输船作为在制宿主")
	check_eq([me.energy, me.mineral], [stock[0]-3.0, stock[1]-4.0], "单独支付3E4M")
	check(not me.pending[0]["command_ready"],"远端开工指令仍在途中")
	Signals.advance(s,1.0)
	s.clock += 1.0
	Signals.receive_due(s)
	_turns(s, 3)
	check(not me.owns(target) and not transport.dead, "工程完成前不是锚点，运输船也未凭空消失")
	s.end_turn()
	check(me.owns(target), "四工作量后落地完成")
	check(transport.dead or not me.ships.has(transport), "完成时消耗运输船")
	check(me.colonial.has(target), "新锚点纳入殖民维护")


## 规则：建造，灭亡和胜负
func test_v01_mobile_host_burns_all_projects() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["colony", "interstellar_travel"])
	var at := Vector3i(1, 0, 0)
	_set_habitable(s, at, StarMap.Star.SINGLE)
	var ship := _ship(s, me, Ship.COLONY, Vector3(at))
	_received_landing_site(s,me,ship)
	var order := s.start_landing(me, ship.id)
	check_eq(order["error"], "", "落地在制订单建立")
	Signals.advance(s,1.0)
	s.clock+=1.0
	Signals.receive_due(s)
	check(me.pending[0]["command_ready"],"先让落地开工命令实际抵达，再检验在制工程损毁")
	var stock := [me.energy, me.mineral]
	s._destroy(me, ship, "测试")
	check(me.pending.is_empty(), "运输船毁灭立即烧毁工程，不能等回合末才中止")
	check_eq(s.cancel_order(me, order["order"])["error"],"", "远端死亡尚未回传时仍可发出取消请求")
	check_eq([me.energy, me.mineral], stock, "无幽灵宿主退款")
	Signals.advance(s,1.0)
	s.clock+=1.0
	Signals.receive_due(s)
	check(s.cancel_order(me,order["order"])["error"]!="","损毁收据到达后禁止重发取消")
	check_eq([me.energy,me.mineral],stock,"宿主被毁没有可退托管成本")


func _received_landing_site(s: GameState,me: Civ,ship: Ship) -> void:
	s.ensure_cells()
	Assets.ensure(s,me)
	Signals.report_ship(s,me,ship)
	Signals.send(s,0,ship.pos,Signals.controller(me),"report",{"type":"cell","cell":ship.cell(),"data":s.snapshot(ship.cell()),"t_observed":s.clock,"source_id":ship.id,"epoch":s.space_epoch})
	Signals.advance(s,1.0)
	s.clock += 1.0
	Signals.receive_due(s)


func _landing_refund_match() -> GameState:
	var s := _two_civs(Vector3i(8,8,8))
	var me := s.human()
	var at := Vector3i(2,0,0)
	_set_habitable(s,at,StarMap.Star.SINGLE)
	_give(me,["colony"])
	var ship := _ship(s,me,Ship.COLONY,Vector3(at))
	Signals.report_ship(s,me,ship)
	Signals.send(s,0,ship.pos,Signals.controller(me),"report",{"type":"cell","cell":at,
		"data":s.snapshot(at),"t_observed":s.clock,"source_id":ship.id,"epoch":s.space_epoch})
	_landing_messages(s,2.0)
	return s


func _landing_messages(s: GameState, duration: float) -> void:
	Signals.advance(s,duration)
	s.clock += duration
	Signals.receive_due(s)


## 规则：建造，情报传回
func test_v01_landing_invalid_after_start_burns_escrow() -> void:
	# 正式Word第9页；独立Gate反例：3E/4M、1/4进度后错误退款2.25E/3M。
	for cause in ["habitable","occupied","dimension"]:
		for work in [0.0,1.0]:
			var s := _landing_refund_match()
			var me := s.human()
			var ship: Ship = me.ships[0]
			var at := ship.cell()
			var accepted := s.start_landing(me,ship.id)
			check_eq(accepted["error"],"","落地命令按已收观测受理")
			check_eq([me.energy,me.mineral],[97.0,96.0],"完整预付3E/4M")
			_landing_messages(s,2.0)
			var project: Dictionary = me.pending[0]
			check(project["command_ready"] and ship.work_locked,"宿主已接受开工，不以是否已有进度区分")
			WorkOrder.advance(project,work)
			var paid := [me.energy_millis,me.mineral_millis]
			var known: Dictionary = me.order_reports[project["id"]].duplicate(true)
			match cause:
				"habitable": s.map.habitable.erase(at)
				"occupied": s.civs[1].colonies.append(at)
				"dimension": s.cell_dims[s.cell_ids[at]] = 2
			s._finish_pending(me,0.0)
			check(me.pending.is_empty(),"失效落地工程立即销毁")
			check_eq(me.order_reports[project["id"]],known,"远端失效要等回执，不能提前改变已知工程")
			check_eq([me.energy_millis,me.mineral_millis],paid,"销毁时不退预付")
			check(not me.owns(at) and not ship.dead and not ship.work_locked,"不生成殖民锚点，不复制或消耗存活运输船，释放作业锁")
			# 降维格子的光速也变慢，仍需等待实际回传，不能假定两年已收到。
			var return_time := 4.0 if cause=="dimension" else 2.0
			_landing_messages(s,return_time)
			var receipt: Dictionary = me.order_reports[project["id"]]
			check_eq(receipt["status"],"destroyed","已开工失效回执是项目销毁")
			check(not receipt.has("failure_refund"),"项目销毁不携带退款")
			check_eq([me.energy_millis,me.mineral_millis],paid,"收到失效回执也不退2.25E/3M或零进度费用")
			check_eq([receipt.get("t_observed",-1),receipt.get("t_received",-1)],
				[4.0,4.0+return_time],"失效观测与接收时间遵守实际光路，不提前回传")
			Signals.receive_due(s)
			check_eq([me.energy_millis,me.mineral_millis],paid,"重复接收不产生退款")


## 规则：建造，情报传回
func test_v01_landing_invalid_before_start_refunds_after_receipt() -> void:
	var s := _landing_refund_match()
	var me := s.human()
	var ship: Ship = me.ships[0]
	s.map.habitable.erase(ship.cell()) # 真实变化尚未回传，下令仍按旧观测。
	var accepted := s.start_landing(me,ship.id)
	check_eq(accepted["error"],"","不能用隐藏落地点失效来提前拒绝命令")
	var paid := [me.energy_millis,me.mineral_millis]
	var project: Dictionary = me.pending[0]
	check(not project["command_ready"],"命令尚未抵达宿主")
	s._finish_pending(me,1.0)
	check(not me.pending.is_empty() and project["done"]==0,"途中命令不提前施工或检查隐藏现场")
	_landing_messages(s,2.0)
	check(me.pending.is_empty(),"命令抵达时发现不合法，未开工就拒绝")
	check_eq([me.energy_millis,me.mineral_millis],paid,"开工前失败也要等待退款回执")
	_landing_messages(s,2.0)
	var receipt: Dictionary = me.order_reports[project["id"]]
	check_eq(receipt["status"],"failed","未开工拒绝仍使用合法失败退款语义")
	check_eq(receipt["failure_refund"],[3000,4000],"未消耗预付完整返回")
	check_eq([me.energy,me.mineral,me.actions_left],[100.0,100.0,Balance.ACTION_BASE-1],"回执退款3E/4M，AP不退")
	Signals.receive_due(s)
	check_eq([me.energy,me.mineral],[100.0,100.0],"失败回执退款一次")


## 规则：建造，情报传回
func test_v01_landing_valid_cancel_refunds_unspent_after_receipt() -> void:
	var s := _landing_refund_match()
	var me := s.human()
	var ship: Ship = me.ships[0]
	var accepted := s.start_landing(me,ship.id)
	check_eq(accepted["error"],"","正常落地受理")
	_landing_messages(s,2.0)
	var project: Dictionary = me.pending[0]
	WorkOrder.advance(project,1.0)
	check_eq(s.cancel_order(me,project["id"])["error"],"","仍合法的已开工落地可主动取消")
	_landing_messages(s,2.0)
	check(me.pending.is_empty(),"取消命令抵达才停止项目")
	check_eq([me.energy,me.mineral],[97.0,96.0],"取消退款仍待返回")
	_landing_messages(s,2.0)
	check_eq(me.order_reports[project["id"]]["status"],"cancelled","合法主动取消不按项目失效销毁")
	check_eq([me.energy,me.mineral],[99.25,99.0],"1/4进度的正常取消仍退2.25E/3M")
	check(not ship.dead and not ship.work_locked and not me.owns(ship.cell()),"运输船保留待命，不制造殖民地")
	Signals.receive_due(s)
	check_eq([me.energy,me.mineral],[99.25,99.0],"正常取消不重复退款")


## 规则：建造，情报传回
func test_v01_landing_invalid_cancel_cannot_bypass_destruction() -> void:
	var s := _landing_refund_match()
	var me := s.human()
	var ship: Ship = me.ships[0]
	var accepted := s.start_landing(me,ship.id)
	check_eq(accepted["error"],"","落地先实际开工")
	_landing_messages(s,2.0)
	var project: Dictionary = me.pending[0]
	WorkOrder.advance(project,1.0)
	check_eq(s.cancel_order(me,project["id"])["error"],"","取消依共同已知信息受理")
	var known: Dictionary = me.order_reports[project["id"]].duplicate(true)
	s.map.habitable.erase(ship.cell())
	check_eq(me.order_reports[project["id"]],known,"取消途中隐藏失效不改变已知状态")
	# 取消命令先于下一次施工检查到达，也不能把已失效项目的托管取回。
	_landing_messages(s,2.0)
	check(me.pending.is_empty(),"取消抵达前已失效的落地工程销毁")
	check_eq([me.energy,me.mineral],[97.0,96.0],"远端执行没有本地即时退款")
	_landing_messages(s,2.0)
	check_eq(me.order_reports[project["id"]]["status"],"destroyed","非法项目不通过取消逃过销毁")
	check_eq([me.energy,me.mineral],[97.0,96.0],"失效项目取消回执也不退2.25E/3M")
	check(not ship.dead and not ship.work_locked,"存活运输船作业锁释放")


## 规则：建造，自身降维
func test_v01_landing_inherits_transport_dimension_not_controller_flag() -> void:
	for transport_dim in [2,3]:
		var s:=_two_civs(Vector3i(8,8,8))
		var me:=s.human()
		_give(me,["colony","interstellar_travel"])
		var at:=Vector3i(1,0,0)
		_set_habitable(s,at,StarMap.Star.SINGLE)
		var transport:=_ship(s,me,Ship.COLONY,Vector3(at))
		transport.entity_dim=transport_dim
		_received_landing_site(s,me,transport)
		s.cell_dims[s.cell_ids[at]]=2
		s.flattened[at]=0
		me.reduced=transport_dim==3 # 控制锚点恰与运输船不同维度。
		Assets.at(me,"anchor",me.home)[0]["entity_dim"]=2 if me.reduced else 3
		check_eq(s.start_landing(me,transport.id)["error"],"","下令依据已收历史，隐藏前沿不提前改变按钮")
		Signals.advance(s,1.0)
		s.clock+=1.0
		Signals.receive_due(s)
		if transport_dim==2:
			check(not me.pending.is_empty(),"运输船已适配二维，母星仍三维不应禁止合法施工")
			if not me.pending.is_empty():
				WorkOrder.advance(me.pending[0],100.0)
				s._finish_pending(me,0.0)
			check(me.owns(at),"已适配运输船可以在二维格子落地")
			check_eq(Assets.dimension(me,"anchor",at),2,"新锚点继承运输船的实体维度")
		else:
			check(me.pending.is_empty() and not me.owns(at),"未适配运输船不能借用母星的二维标记在前沿后施工")


## 规则：建造，每回合的收入
func test_v01_miner_refit_is_one_slot_and_paid() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[me.home]=1
	_give(me, ["mining_advanced"])
	me.miners[me.home] = 2
	check(s.has_method("refit_miner"), "基础矿船有显式逐艘改装入口")
	if not s.has_method("refit_miner"):
		return
	var stock := [me.energy, me.mineral]
	check_eq(s.call("refit_miner", me, me.home)["error"], "", "矿船改装可提交")
	check_eq([me.energy, me.mineral], [stock[0]-2.0, stock[1]-2.0], "只收2E2M改装费")
	check_eq(me.miner_count(), 2, "施工期间不凭空添船")
	s.end_turn()
	check_eq([me.miners[me.home], me.advanced_miners[me.home], me.miner_count()], [1, 1, 2], "原船替换、总容量不变")
	check_eq(s.mineral_income(me), 6.0, "完工后一个基础与一个高级矿船共6M")


## 规则：建造，每回合的收入
func test_v01_dormant_host_cannot_refit() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	_give(me, ["warship", "alloy"])
	var ship := _ship(s, me, Ship.WARSHIP, Vector3.ZERO)
	me.dormant_colonies[me.home] = true
	check(s.refit_error(me, ship.id, ["alloy"]) != "", "休眠救援不能夹带普通舰船改装")


## 规则：存档和回放
func test_v01_new_actions_and_escrow_replay() -> void:
	var s := GameState.new_game(43, 1)
	var me := s.human()
	s.set_autoplay(s.civs[1], false)
	s.dev_set(me, "energy", 100.0)
	s.dev_set(me, "mineral", 100.0)
	s.research(me, "warship")
	s.build(me, "miner")
	s.end_turn()
	s.cancel_order(me, me.research_project["id"])
	s.emergency_work(me, "M")
	s.end_turn()
	var replay := Replay.from_state(s)
	check(Replay.valid_data(replay.to_dict()), "新增取消和应急操作可登记回放")
	if not Replay.valid_data(replay.to_dict()):
		return
	var copy := replay.play_to(replay.last_step())
	check_eq(replay.desync_step, -1, "原始种子和已录操作可精确重算")
	check_eq(copy.checksum(), s.checksum(), "包括托管、工作量和余额校验")
	check_eq(copy.human().pending, me.pending, "未完成订单也完全一致")
	var old := replay.to_dict()
	old["version"] = 2
	check(not Replay.valid_data(old), "旧规则回放不能静默使用新规则重算")
