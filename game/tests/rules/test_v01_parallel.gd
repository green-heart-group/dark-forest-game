extends "res://tests/rules/rule_suite.gd"
## 并发提速：容量、独立托管与有限回执，不加速任何单项工程。


func match_with_mines() -> GameState:
	var s := _two_civs(Vector3i(8,8,8))
	s.rng.seed = 1024
	s.map.rocky[Vector3i.ZERO] = 1
	return s


## 规则：每回合的收入，建造，W6
func test_v01_parallel_three_ap_and_two_paid_mines() -> void:
	var s := match_with_mines()
	var me := s.human()
	check_eq(me.actions_left,3,"新局每文明每年3AP")
	check_eq(s.civs[1].actions_left,3,"自动文明与玩家相同AP")
	var before := me.mineral
	var a := s.build(me,"miner")
	var b := s.build(me,"miner")
	check_eq([a["error"],b["error"]],["",""],"母星同回合两单均受理")
	check_eq(me.mineral,before-6.0,"两单分别预付3M")
	check_eq(me.actions_left,1,"两次建造各消耗1AP")
	var paid := [me.energy,me.mineral,me.actions_left,s.rng.state,me.order_reports.size()]
	check(s.build(me,"probe")["error"]!="","有AP且有钱时第三单仍拒绝")
	check_eq([me.energy,me.mineral,me.actions_left,s.rng.state,me.order_reports.size()],paid,"第三单不扣费、AP或新增订单")
	check_eq(s.research(me,"fusion")["error"],"","两槽施工同时研究")
	check_eq(me.actions_left,0,"建造两单加研究正好3AP")
	check(s.research(me,"warship")["error"]!="","仍只有一个研究槽")
	s.end_turn()
	check_eq(me.pending.size(),2,"两项2W工程一年后均未完成")
	for order in me.pending:
		check_eq(order["done"],1000,"两槽各推进1W，而不是共享1W")
	for order in OrderControl.visible(s,me):
		check_eq(order["done"],1000,"控制据点的本地工程显示当前独立进度")
	check_eq(me.research_project["done"],1000,"研究独立推进1W")
	check_eq(me.actions_left,3,"下一回合恢复3AP")
	s.end_turn()
	check_eq(me.miner_count(),2,"同刻两项2W完成")
	check_eq(s.mineral_income(me),4.0,"真实两矿船产生4M/年")
	check(me.has_tech("fusion"),"研究也在2W后完成")
	check(me.pending.is_empty(),"两槽均收到本地完工并释放")


## 规则：建造
func test_v01_parallel_different_work_and_slot_reuse() -> void:
	var s := match_with_mines()
	var me := s.human()
	s.build(me,"miner")
	s.build(me,"probe")
	s.end_turn()
	check_eq(me.count(Ship.PROBE),1,"1W探测器先完成")
	check_eq(me.pending.size(),1,"2W矿船继续独立施工")
	check_eq(s.build(me,"probe")["error"],"","仅释放已完成的一槽")
	var before := [me.energy,me.mineral,me.actions_left]
	check(s.build(me,"probe")["error"]!="","补单后仍拒绝第三项")
	check_eq([me.energy,me.mineral,me.actions_left],before,"补满后失败原子")
	s.end_turn()
	check_eq([me.miner_count(),me.count(Ship.PROBE)],[1,2],"不同起始时间的订单各自完成")


## 规则：建造
func test_v01_parallel_cancel_only_selected_escrow() -> void:
	var s := match_with_mines()
	var me := s.human()
	var a := s.build(me,"miner")
	var b := s.build(me,"miner")
	s.end_turn()
	var before := me.mineral
	check_eq(s.cancel_order(me,a.get("order",-1))["error"],"","只取消选中的订单")
	check_eq(me.mineral,before+1.5,"只退该单剩余一半3M")
	check_eq(me.pending.size(),1,"另一项仍在施工")
	if not me.pending.is_empty():
		check_eq(me.pending[0]["id"],b.get("order",-1),"存续项目ID没有串单")
	before = me.mineral
	check(s.cancel_order(me,a.get("order",-1))["error"]!="","重复取消拒绝")
	check_eq(me.mineral,before,"重复取消不再次退款")
	s.end_turn()
	check_eq(me.miner_count(),1,"另一槽正常完工")


## 规则：建造，灭亡和胜负
func test_v01_parallel_destroyed_host_burns_both_orders() -> void:
	var s := match_with_mines()
	var me := s.human()
	var backup := Vector3i(2,0,0)
	_set_habitable(s,backup,StarMap.Star.SINGLE)
	me.colonies.append(backup)
	Assets.ensure(s,me)
	s.build(me,"miner")
	s.build(me,"miner")
	var before := [me.energy,me.mineral]
	s._lose_system(me.home,me,"双槽宿主失效夹具")
	check_eq([me.energy,me.mineral],before,"宿主毁灭两笔托管均不退款")
	check(me.pending.is_empty(),"宿主失效中止两项工程")
	check(me.alive,"备份据点仍存续")


## 规则：建造
func test_v01_parallel_unique_facilities_reserve_once() -> void:
	for kind in ["warning","broadcaster","bunker"]:
		var s := match_with_mines()
		var me := s.human()
		s.map.gas[me.home] = 1
		_give(me,["broadcaster","bunker"])
		check_eq(s.build(me,kind)["error"],"",kind+"首单合法")
		var before := [me.energy,me.mineral,me.actions_left]
		check(s.build(me,kind)["error"]!="",kind+"另一槽不能重复预约唯一设施")
		check_eq([me.energy,me.mineral,me.actions_left],before,kind+"重复预约不扣费")
		check_eq(s.build(me,"probe")["error"],"","另一槽仍可造不同项目")


## 规则：建造
func test_v01_parallel_miner_refits_reserve_distinct_hulls() -> void:
	for count in [1,2]:
		var s := match_with_mines()
		var me := s.human()
		_give(me,["mining_advanced"])
		me.miners[me.home] = count
		Assets.ensure(s,me)
		check_eq(s.refit_miner(me)["error"],"","第一艘基础矿船改装")
		var before := [me.energy,me.mineral,me.actions_left]
		var second := s.refit_miner(me)
		check_eq(second["error"]=="",count==2,"两槽只能预约不同矿船")
		if count==1:
			check_eq([me.energy,me.mineral,me.actions_left],before,"不存在第二艘时不扣费")
		s.end_turn()
		check_eq(me.advanced_miners.get(me.home,0),count,"每艘真实矿船只改装一次")
		check_eq(me.miners.get(me.home,0),0,"不凭空复制基础矿船")


## 规则：建造
func test_v01_parallel_warning_upgrade_reserves_current_level() -> void:
	var s := match_with_mines()
	var me := s.human()
	me.warnings[me.home] = 0
	Assets.ensure(s,me)
	check_eq(s.upgrade(me,"warning")["error"],"","可升级现有预警")
	var before := [me.energy,me.mineral,me.actions_left]
	check(s.upgrade(me,"warning")["error"]!="","另一槽不重复购买同一当前等级")
	check_eq([me.energy,me.mineral,me.actions_left],before,"重复预警升级原子拒绝")


## 规则：建造
func test_v01_parallel_home_identity_and_docked_starship() -> void:
	var s := match_with_mines()
	var me := s.human()
	_give(me,["starship"])
	_ship(s,me,Ship.STARSHIP,Vector3(me.home))
	s.build(me,"probe")
	s.build(me,"probe")
	check(s.build(me,"probe")["error"]!="","同格星舰不能绕过母星两槽上限")
	var colony := Vector3i(2,0,0)
	_set_habitable(s,colony,StarMap.Star.SINGLE)
	me.colonies.append(colony)
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,colony)
	Signals.advance(s,2.0)
	s.clock = 2.0
	Signals.receive_due(s)
	me.actions_left = 3
	check_eq(s.build(me,"probe",colony)["error"],"","殖民星系可提交一项")
	check(s.build(me,"probe",colony)["error"]!="","殖民星系仍一槽")
	var mother := me.original_home
	var original := me.original_anchor_id
	s._lose_system(mother,me,"母星身份测试")
	me.colonies.append(mother)
	Assets.ensure(s,me)
	me.home = mother # 调试夹具把控制点放回新殖民地；永久原锚点ID仍不变。
	check(Assets.at(me,"anchor",mother)[0]["id"]!=original,"重新殖民得到新锚点身份")
	me.actions_left = 3
	check_eq(s.build(me,"probe",mother)["error"],"","原坐标的新殖民地仍可建造")
	check(s.build(me,"probe",mother)["error"]!="","重新占有原坐标不继承起始母星容量")


## 规则：建造，情报传回
func test_v01_parallel_mobile_host_stays_one_slot() -> void:
	var s := match_with_mines()
	var me := s.human()
	var ship := _ship(s,me,Ship.STARSHIP,Vector3(1,0,0))
	me.telemetry[ship.id] = {"data":Signals.ship_status(ship),"t_observed":s.clock,"t_received":s.clock,"epoch":0}
	check_eq(s.build(me,"probe",ship.cell())["error"],"","独立星舰格可造一项")
	check(s.build(me,"probe",ship.cell())["error"]!="","星舰自身仍一槽")
	var before := [me.energy,me.mineral,me.actions_left]
	ship.pos = Vector3(2,0,0)
	me.telemetry[ship.id]["data"] = Signals.ship_status(ship)
	check(s.build(me,"probe",ship.cell())["error"]!="","移动后同一ID不能获得第二槽")
	check_eq([me.energy,me.mineral,me.actions_left],before,"移动宿主不重复扣费")


## 规则：建造，情报传回
func test_v01_parallel_remote_receipt_does_not_release_other_slot() -> void:
	var s := match_with_mines()
	var me := s.human()
	var at := Vector3i(4,0,0)
	_set_habitable(s,at,StarMap.Star.SINGLE)
	me.colonies.append(at)
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,at)
	Signals.advance(s,4.0)
	s.clock = 4.0
	Signals.receive_due(s)
	s.build(me,"miner")
	s.build(me,"miner")
	var remote := s.build(me,"probe",at)
	check_eq(remote["error"],"","母星两槽和殖民槽独立受理")
	Signals.advance(s,4.0)
	s.clock += 4.0
	Signals.receive_due(s)
	s._finish_pending(me,1.0)
	check_eq(me.count(Ship.PROBE),1,"远端已实际完成探测器")
	check(s.construction_busy(me,at,-1),"未收完工报告不能释放远端槽")
	check(s.construction_busy(me,me.home,-1),"远端完工不释放母星的两项工程")
	Signals.advance(s,4.0)
	s.clock += 4.0
	Signals.receive_due(s)
	check(not s.construction_busy(me,at,-1),"收到该ID完工报告才释放远端槽")
	check(s.construction_busy(me,me.home,-1),"回执不能串到母星其他ID")


## 规则：AI 怎么行动，建造，情报传回
func test_v01_parallel_ai_uses_three_ap_without_hidden_state() -> void:
	var a := match_with_mines()
	var b := StateCopy.copy(a)
	b.map.rocky[b.civs[1].home] = 0
	b.civs[1].ships.append(Ship.make(Ship.DROPLET,Vector3(8,8,7),98765))
	for s in [a,b]:
		var me: Civ = s.human()
		me.is_ai = true
		AI.take_turn(s,me)
		check_eq(me.actions_left,0,"AI合法使用新增第三AP")
		check_eq(me.pending.size(),2,"AI能同时占用母星两槽")
		check(not me.research_project.is_empty(),"AI同时保留一条研究")
	check_eq(a.human().pending,b.human().pending,"未见敌方差异不改变AI工程决策")
	check_eq(a.human().research_project,b.human().research_project,"未见真值不改变研究")
	check_eq(a.rng.state,b.rng.state,"隐藏差异不改变决策随机数")


## 规则：每回合的收入，建造
func test_v01_parallel_snapshot_and_saved_replay() -> void:
	var s := GameState.new_game(7,1)
	for civ in s.civs: s.set_autoplay(civ,false)
	var me := s.human()
	s.build(me,"miner")
	s.build(me,"miner")
	s.research(me,"fusion")
	var copy := StateCopy.unpack(StateCopy.pack(s))
	check_eq(copy.human().pending.size(),2,"快照恢复两份在制订单")
	check_eq(copy.checksum(),s.checksum(),"独立快照完整状态一致")
	var path := "user://_test_parallel.forest"
	var replay := Replay.from_state(s)
	check_eq(replay.save(path),OK,"存档保存并发操作")
	var loaded := Replay.load_file(path)
	check(loaded!=null,"读取并发存档")
	if loaded!=null:
		var restored := loaded.play_to(0)
		check_eq(restored.human().pending.size(),2,"回合中途读档恢复两项目")
		check_eq(restored.checksum(),s.checksum(),"存档完整校验一致")
	s.end_turn()
	replay = Replay.from_state(s)
	var again := replay.play_to(1)
	check_eq(replay.desync_step,-1,"并发工程连续回放无失步")
	check_eq(again.checksum(),s.checksum(),"下一回合完整校验一致")
	DirAccess.remove_absolute(path)


## 规则：每回合的收入，建造
func test_v01_parallel_old_replay_restores_legacy_capacity() -> void:
	var old := Replay.new()
	old.balance = Balance.values().duplicate(true)
	old.balance["ACTION_BASE"] = 2
	old.balance.erase("HOME_BUILD_SLOTS")
	old.apply_balance()
	var s := match_with_mines()
	var me := s.human()
	check_eq(me.actions_left,2,"旧存档保留原AP数值")
	check_eq(s.build(me,"miner")["error"],"","旧存档首项可建")
	check(s.build(me,"probe")["error"]!="","旧存档缺少容量参数时保留原单槽")


## 规则：建造，情报传回，W6
func test_v01_parallel_remote_mother_cancel_and_hidden_state() -> void:
	var s := match_with_mines()
	var me := s.human()
	var mother := me.original_home
	var control := Vector3i(4,0,0)
	_set_habitable(s,control,StarMap.Star.SINGLE)
	me.colonies.append(control)
	Assets.ensure(s,me)
	me.home = control # 控制点搬迁，原母星资格仍按永久锚点ID保留。
	Knowledge.report_site(s,me,mother)
	Signals.advance(s,4.0)
	s.clock = 4.0
	Signals.receive_due(s)
	var a := s.build(me,"miner",mother)
	var b := s.build(me,"miner",mother)
	check_eq([a["error"],b["error"]],["",""],"远端起始母星仍有两槽")
	var hidden := StateCopy.copy(s)
	hidden.map.rocky[mother] = 0
	check_eq(hidden.build_error(hidden.human(),"probe",mother),s.build_error(me,"probe",mother),"第三单限制不读取隐藏的矿点失效")
	var before := [me.energy,me.mineral]
	check_eq(s.cancel_order(me,a.get("order",-1))["error"],"","指定取消远端第一项")
	check_eq([me.energy,me.mineral],before,"取消发送不立即退款")
	check(s.construction_busy(me,mother,-1),"取消发送不提前释放槽位")
	Signals.advance(s,4.0)
	s.clock += 4.0
	Signals.receive_due(s)
	check_eq(me.pending.size(),1,"取消到达只中止该订单")
	if not me.pending.is_empty():
		check_eq(me.pending[0]["id"],b.get("order",-1),"第二项仍独立存续")
	check_eq([me.energy,me.mineral],before,"远端执行后仍等待退款回执")
	check(s.construction_busy(me,mother,-1),"未收取消回执仍占满两槽")
	Signals.advance(s,4.0)
	s.clock += 4.0
	Signals.receive_due(s)
	check_eq(me.mineral,before[1]+3.0,"零施工进度只退第一项3M")
	check(not s.construction_busy(me,mother,-1),"已收取消回执只释放一槽")
	var stock := me.mineral
	check(s.cancel_order(me,a.get("order",-1))["error"]!="","重复远端取消拒绝")
	check_eq(me.mineral,stock,"重复回执或取消不重复退款")
	var known := OrderControl.visible(s,me).duplicate(true)
	if not me.pending.is_empty(): WorkOrder.advance(me.pending[0],0.5)
	check_eq(OrderControl.visible(s,me),known,"远端真实工程进度变化不能绕过已收回报")


## 规则：建造，自身降维，W6
func test_v01_parallel_same_cell_starship_cannot_bypass_capacity() -> void:
	var s := match_with_mines()
	var me := s.human()
	var ship := _ship(s,me,Ship.STARSHIP,Vector3(me.home))
	s.build(me,"probe")
	s.build(me,"probe")
	var before := [me.energy,me.mineral,me.actions_left]
	check(s.prepare_conversion(me,[ship.id],ship.id,true,false)["error"]!="","同格星舰迁维施工不能绕过母星两槽")
	check_eq([me.energy,me.mineral,me.actions_left],before,"额外队列申请原子拒绝")
	s = match_with_mines()
	me = s.human()
	ship = _ship(s,me,Ship.STARSHIP,Vector3(me.home))
	s.build(me,"miner")
	check_eq(s.prepare_conversion(me,[ship.id],ship.id,true,false)["error"],"","一项母星工程和一项同格星舰准备可共享两槽")
	check(s.build(me,"probe")["error"]!="","共享两槽后拒绝第三项")
	check(s.prepare_conversion(me,[ship.id],ship.id,true,false)["error"]!="","星舰本体仍不接受第二项工程")
