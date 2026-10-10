extends "res://tests/rules/rule_suite.gd"


func remote_match() -> GameState:
	var s:=_two_civs(Vector3i(8,8,8))
	s.rng.seed=1919
	var me:=s.human()
	var remote:=Vector3i(4,0,0)
	_set_habitable(s,remote,StarMap.Star.SINGLE)
	me.colonies.append(remote)
	me.broadcasters[remote]=true
	me.warnings[remote]=0
	me.miners[remote]=1
	me.known[s.civs[1].home]=s.turn
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	Knowledge.report_site(s,me,remote)
	Signals.advance(s,4.0)
	s.clock=4.0
	Signals.receive_due(s)
	return s


func observed(s: GameState,include_rng:=true) -> int:
	var me:=s.human()
	return hash([me.intel,me.known,me.sightings,me.alerts,me.site_reports,me.telemetry,
		me.order_reports,me.command_pending,me.command_results,me.techs,me.energy,me.mineral,me.actions_left,str(s.rng.state) if include_rng else ""])


func screen_state(s: GameState) -> int:
	var view:=Knowledge.presentation(s,s.human())
	var me:=view.human()
	return hash([view.map.stars,view.map.rocky,view.light,view.black_domains,DimensionSpace.frame(view),
		me.colonies,me.assets,me.miners,me.warnings,me.ships.map(func(ship):return Signals.ship_status(ship))])


## 规则：情报传回，科技树
func test_v01_remote_income_permission_waits_for_all_source_reports() -> void:
	var a:=remote_match()
	var me:=a.human()
	me.discovered=true
	a.map.rocky[me.home]=4
	var b:=StateCopy.copy(a)
	b.human().miners[Vector3i(4,0,0)]=5
	Assets.ensure(b,b.human())
	check_eq(observed(a),observed(b),"隐藏远端新增矿船，玩家收到的情报和可用余额相同")
	a._refresh_permissions(a.human())
	b._refresh_permissions(b.human())
	check_eq(a.human().tier1_turn,b.human().tier1_turn,"名义产能变化未回报，权限不能先解锁")
	check_eq(a.research_block_error(a.human(),"devourer"),b.research_block_error(b.human(),"devourer"),"玩家与AI调用的研究理由相同")
	Signals.advance(b,3.9)
	b.clock+=3.9
	Signals.receive_due(b)
	check_eq(b.human().tier1_turn,-1,"四光年来源的证明在3.9年后仍未收齐")
	Signals.advance(b,0.1)
	b.clock+=0.1
	Signals.receive_due(b)
	check(b.human().tier1_turn>=0,"收到全部本地产能证明后公开永久权限")
	check_eq(a.human().tier1_turn,-1,"未实际达标的对照局不获权限")


## 规则：情报传回，预警系统
func test_v01_remote_telescope_completion_is_not_instant_upgrade() -> void:
	var s:=remote_match()
	var me:=s.human()
	var project:=WorkOrder.create(s.next_id(),"telescope",Vector3i(4,0,0),[3,3],1,"upgrade")
	me.pending.append(project)
	OrderControl.submit(s,me,project)
	Signals.advance(s,4.0)
	s.clock+=4.0
	Signals.receive_due(s)
	s._finish_pending(me,1.0)
	check_eq(me.telescope,0,"远端升级完工不直接增加全局视距")
	Signals.advance(s,4.0)
	s.clock+=4.0
	Signals.receive_due(s)
	check_eq(me.telescope,1,"完成回报送达后升级生效")


## 规则：情报传回，光粒
func test_v01_remote_hit_does_not_change_ai_defense_before_receipt() -> void:
	var s:=remote_match()
	var me:=s.human()
	var remote:=Vector3i(4,0,0)
	var grain:=_ship(s,s.civs[1],Ship.GRAIN,Vector3(remote),Vector3.LEFT)
	TacticalEvents.resolve(s,[{"kind":"grain","at":remote,"ship":grain,"owner":1,"victim":0}])
	check_eq(me.times_hit,0,"远端遇袭次数未回报前不改变AI防御分数")
	check(me.hit_dirs.is_empty(),"远端受袭方向不能提前回传")
	Signals.advance(s,4.0)
	s.clock+=4.0
	Signals.receive_due(s)
	check_eq(me.times_hit,1,"四年后收到一次遇袭报告")
	check_eq(me.hit_dirs[0]["dir"],Vector3.RIGHT,"回报保留实际来袭方向")


func battle_match(full_view: bool,remote_base: bool,bunker:=false) -> GameState:
	var s:=_two_civs(Vector3i(1,0,0))
	s.rng.seed=251
	var me:=s.human()
	var other:=s.civs[1]
	if full_view:
		me.telescope=100 # 测试夹具让传感覆盖全图；不改正式上限和价格。
	# 配对局先分配相同实体ID，再只改变不可见的远端所有权。
	var remote:=Vector3i(8,8,8)
	_set_habitable(s,remote,StarMap.Star.SINGLE)
	other.colonies.append(remote)
	if bunker:
		other.bunkers[other.home]=true
		other.dormant_colonies[other.home]=true
	_ship(s,other,Ship.STARSHIP,Vector3(7,7,7))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	if not remote_base:
		Assets.remove_at(other,remote)
		other.colonies.erase(remote)
	var grain:=_ship(s,me,Ship.GRAIN,Vector3(1,0,0),Vector3.RIGHT)
	TacticalEvents.resolve(s,[{"kind":"grain","at":Vector3i(1,0,0),"ship":grain,"owner":0,"victim":1}])
	Information.observe_battles(s)
	Signals.advance(s,15.0)
	s.clock=15.0
	Signals.receive_due(s)
	return s


## 规则：情报传回，科技树，灭亡和胜负
func test_v01_local_battle_cannot_report_unseen_empire_completion() -> void:
	var a:=battle_match(false,false)
	var b:=battle_match(false,true)
	check(not a.human().conquered and not b.human().conquered,"一次近处战报不能判断未侦察远方是否还有星系")
	check_eq(a.human().battle_reports,b.human().battle_reports,"当地锚点毁灭报告不含全境资格推断")
	check_eq(a.human().battle_surveys,b.human().battle_surveys,"有限视野中同一截面证据不受隐藏远端殖民地影响")
	check(a.civs[1].alive and a.civs[1].colonies.is_empty(),"所有固定星系已毁但星舰仍能维持文明")


## 规则：情报传回，科技树，灭亡和胜负
func test_v01_complete_same_time_recon_confirms_history_not_extinction() -> void:
	var clear:=battle_match(true,false)
	check(clear.human().conquered,"完整同刻全图侦察和本方战报返回后确认过去星系清空")
	check(clear.civs[1].alive,"获得星系清空资格不擅自判定星舰文明灭亡")
	check_eq(clear.human().conquest_confirmation["qualified_at"],0.0,"记录实际历史截面时刻")
	check_eq(clear.human().conquest_confirmation["confirmed_at"],15.0,"另记收到全部证据的时刻")
	var remains:=battle_match(true,true)
	check(not remains.human().conquered,"全图证据中仍有远方星系，不能获得资格")
	var dormant:=battle_match(true,false,true)
	check(not dormant.human().conquered,"恒星被毁但掩体内休眠锚点保留，不能称星系已毁")
	check(dormant.human().battle_reports.is_empty(),"没有真实锚点毁灭就不生成毁灭战报")


## 规则：情报传回，科技树
func test_v01_hidden_battle_does_not_emit_local_survey_before_report() -> void:
	var a:=_two_civs(Vector3i(8,0,0))
	a.ensure_cells()
	for civ in a.civs:
		Assets.ensure(a,civ)
	_ship(a,a.civs[1],Ship.STARSHIP,Vector3(7,7,7))
	var b:=StateCopy.copy(a)
	b.civs[1].bunkers[b.civs[1].home]=true
	for s in [a,b]:
		var grain:=_ship(s,s.human(),Ship.GRAIN,Vector3(8,0,0),Vector3.RIGHT)
		TacticalEvents.resolve(s,[{"kind":"grain","at":Vector3i(8,0,0),"ship":grain,"owner":0,"victim":1}])
		Information.observe_battles(s)
		Signals.receive_due(s)
	check(not a.battle_archive.is_empty(),"当地持续传感录像可以先留在私有缓冲")
	check(a.human().battle_reports.is_empty(),"八光年远战报尚未传回")
	check_eq(a.human().battle_surveys,b.human().battle_surveys,"隐藏战斗不触发本地可见核查事件")
	check_eq(a.human().battle_queries,b.human().battle_queries,"未收到战报不得自动查询")
	check_eq(observed(a),observed(b),"同一已收到的信息仍完全相同")
	var snapshot:=StateCopy.copy(a)
	check_eq(snapshot.battle_archive,a.battle_archive,"私有传感缓冲可无损存档")
	check_eq(snapshot.checksum(),a.checksum(),"缓冲和私有序列纳入回放校验")


## 规则：情报传回，科技树
func test_v01_visible_battle_token_does_not_disclose_hidden_event_count() -> void:
	var a:=_two_civs(Vector3i(8,8,8))
	a.ensure_cells()
	for civ in a.civs:
		Assets.ensure(a,civ)
	var b:=StateCopy.copy(a)
	# 只改变引擎内部曾发生的隐藏传感记录数；公开战报事实完全相同。
	b.survey_sequence-=10000
	for s in [a,b]:
		Information.system_destroyed(s,0,1,Vector3i.ZERO,99,"测试")
		Signals.receive_due(s)
	check_eq(a.human().battle_reports,b.human().battle_reports,"公开战报使用收件方本地编号，不暴露隐藏事件计数")
	check_eq(a.human().battle_queries,b.human().battle_queries,"公开查询索引同样只使用本地编号")


## 规则：情报传回，科技树
func test_v01_overlapping_sensors_each_retain_their_recording() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	var me:=s.human()
	var first:=_ship(s,me,Ship.PROBE,Vector3(3,0,0))
	var second:=_ship(s,me,Ship.PROBE,Vector3(3,0,0))
	Information.system_destroyed(s,0,1,Vector3i(3,0,0),99,"测试")
	var event_id: int=s.pending_battle_surveys[0]["event_id"]
	Information.observe_battles(s)
	Signals.receive_due(s)
	check(s.battle_archive.has([0,first.id,event_id]),"第一个覆盖传感器保存本地录像")
	check(s.battle_archive.has([0,second.id,event_id]),"重叠覆盖的第二个传感器也独立保存录像")
	first.dead=true
	Information.receive_query(s,{"owner":0,"recipient":second.id,"body":{"event_id":event_id}})
	check(s.messages.any(func(message):return message["kind"]=="report" and message["body"].get("type","")=="battle_survey" and message["body"]["source_id"]==second.id),"首个传感器死亡后，存活的覆盖者仍能回应查询")


## 规则：情报传回，科技树
func test_v01_survey_query_needs_finite_route_and_surviving_sensor() -> void:
	var s:=remote_match()
	var me:=s.human()
	var probe:=_ship(s,me,Ship.PROBE,Vector3(2,0,0))
	Signals.report_ship(s,me,probe)
	Signals.advance(s,2.0)
	s.clock+=2.0
	Signals.receive_due(s)
	var secret:=_ship(s,me,Ship.PROBE,Vector3(7,0,0))
	var event_id:=20001
	Information.receive_record(s,{"owner":0,"recipient":probe.id,"body":{"type":"battle_survey","event_id":event_id,"cell_id":1,"local_owner":-1,"t_observed":0.0,"epoch":0}})
	Information.receive_battle(s,0,{"event_id":event_id,"victim":1,"cell":s.civs[1].home,"t_observed":0.0,"epoch":0})
	check(not me.battle_queries.has([1,secret.id]),"不能向从未回报的隐藏传感器自动查询")
	Signals.receive_due(s)
	check(me.battle_surveys.is_empty(),"远方缓存不能由控制端直接读取")
	probe.dead=true
	Signals.advance(s,2.0)
	s.clock+=2.0
	Signals.receive_due(s)
	Signals.advance(s,2.0)
	s.clock+=2.0
	Signals.receive_due(s)
	check(me.battle_surveys.is_empty(),"查询抵达前传感器被毁，文明全局不能代答录像")


## 规则：广播和隐藏文明，情报传回
func test_v01_hidden_jammer_cannot_change_broadcast_choice_or_refund_early() -> void:
	var a:=remote_match()
	var droplet:=_ship(a,a.civs[1],Ship.DROPLET,Vector3(7,7,7))
	droplet.parked=true
	var b:=StateCopy.copy(a)
	b.civs[1].ships[0].pos=Vector3(4,0,0)
	check_eq(observed(a),observed(b),"同已收情报、资源、RNG，只有隐藏水滴位置不同")
	check_eq(screen_state(a),screen_state(b),"正常画面投影不因隐藏封锁变化")
	check(AI._try_broadcast(a,a.human()) and AI._try_broadcast(b,b.human()),"两个AI均可按已知远端广播器下令")
	check_eq(a.history,b.history,"下达完全相同命令")
	for s in [a,b]:
		Signals.advance(s,4.0)
		s.clock=8.0
		Signals.receive_due(s)
	# 真正执行广播的分支会抽暴露率；物理RNG不是玩家信息，下一次决策配对另固定RNG。
	check_eq(observed(a,false),observed(b,false),"命令已到达但回执未返回：隐藏阻塞不提前退款或改可用状态")
	for s in [a,b]:
		Signals.advance(s,4.0)
		s.clock=12.0
		Signals.receive_due(s)
	check(a.human().command_results[-1]["executed"],"无封锁时真实执行")
	check(not b.human().command_results[-1]["executed"],"真实封锁时失败经四年回执返回")
	check_eq(b.human().energy-a.human().energy,float(GameState.action_cost("broadcast")),"只有合法回执到达后退还失败预算")


## 规则：情报传回，建造
func test_v01_hidden_remote_loss_preserves_actions_roster_map_and_path() -> void:
	var a:=remote_match()
	var ship:=_ship(a,a.human(),Ship.WARSHIP,Vector3.ZERO,Vector3.RIGHT)
	ship.warp=true
	ship.speed=0.1
	var b:=StateCopy.copy(a)
	var remote:=Vector3i(4,0,0)
	var id: int=Knowledge.anchor(a,a.human(),remote)["id"]
	b._lose_system(remote,b.human(),"未传回的损失")
	check_eq(observed(a),observed(b),"真实失守未改变已收历史")
	check_eq(a.emergency_work_error(a.human(),"M",id),b.emergency_work_error(b.human(),"M",id),"同历史应急按钮理由相同")
	check_eq(a.upgrade_error(a.human(),"warning",remote),b.upgrade_error(b.human(),"warning",remote),"同历史预警升级理由相同")
	check_eq(a.refit_miner_error(a.human(),remote),b.refit_miner_error(b.human(),remote),"同历史矿船改装理由相同")
	check_eq(Conversion.known_roster(a,a.human(),3),Conversion.known_roster(b,b.human(),3),"迁维名册不提前删除失联实体")
	check_eq(screen_state(a),screen_state(b),"原地图与资产显示保持最后回报")
	check_eq(a.predict_path(a.human(),ship,10),b.predict_path(b.human(),b.human().ships[0],10),"航迹预测不读取未报告远端锚点状态")


## 规则：二向箔，情报传回
func test_v01_hidden_front_does_not_change_target_or_map() -> void:
	var a:=remote_match()
	var b:=StateCopy.copy(a)
	var target:=Vector3i(7,7,7)
	b.flattened[target]=7
	b.foil_zones.append({"id":999,"center":target,"age":0.25,"created":b.clock})
	b.cell_dims[b.cell_ids[target]]=2
	check_eq(observed(a),observed(b),"未收新前沿信息")
	check_eq(a.foil_target_error(a.human(),false,target),b.foil_target_error(b.human(),false,target),"目标错误理由不能探测隐藏维度")
	check_eq(screen_state(a),screen_state(b),"原版展开布局输入也只来自已收前沿")
	for s in [a,b]:
		s.human().techs["dimension"]=true
		s.human().dimension_ammo=1
	check_eq(a.launch_foil(a.human(),target)["error"],b.launch_foil(b.human(),target)["error"],"人类与AI共用的命令入口同样接受历史目标")


## 规则：反物质，情报传回
func test_v01_antimatter_cannot_target_unobserved_enemy() -> void:
	var a:=remote_match()
	var enemy:=_ship(a,a.civs[1],Ship.WARSHIP,Vector3(7,7,7))
	a.human().antimatter=1
	a.human().techs["antimatter"]=true
	var b:=StateCopy.copy(a)
	b.civs[1].ships[0].pos=Vector3(0.5,0,0)
	check_eq(observed(a),observed(b),"隐藏敌舰移入射程，不生成观测")
	check_eq(a.antimatter_targets(a.human()).size(),0,"远端未知舰不列目标")
	check_eq(b.antimatter_targets(b.human()).size(),0,"近处但消息未到也不列目标")
	check_eq(a.antimatter_error(a.human()),b.antimatter_error(b.human()),"共享玩家/AI入口不能窥探未知舰")
	check(enemy.id>=0,"目标具有稳定ID")


## 规则：建造，情报传回
func test_v01_remote_ammo_completion_is_disclosed_by_receipt() -> void:
	var s:=remote_match()
	var me:=s.human()
	me.techs["dimension"]=true
	me.energy=1000
	me.mineral=1000
	var before_log:=s.log_lines.duplicate()
	var result:=s.build(me,"dimension_weapon",Vector3i(4,0,0))
	check_eq(result["error"],"","已知宿主接受弹药订单")
	Signals.advance(s,4.0)
	s.clock=8.0
	Signals.receive_due(s)
	var project: Dictionary=me.pending[0]
	WorkOrder.advance(project,100.0)
	s._finish_pending(me,0.0)
	check_eq(me.dimension_ammo,0,"远端真实完工不提前增加下令弹药列表")
	check(not s.log_lines.any(func(line):return line.contains("完成回报")),"完工日志不能抢跑回执")
	Signals.advance(s,4.0)
	s.clock=12.0
	Signals.receive_due(s)
	check_eq(me.dimension_ammo,1,"完成回执到达后仅发放一次弹药")
	check(s.log_lines.size()>before_log.size(),"用户可见工程回报")
	Signals.receive_due(s)
	check_eq(me.dimension_ammo,1,"重复检查收件箱不重复发放")


## 规则：科技树
func test_v01_tech_burst_disabled_in_delivery_configuration() -> void:
	check_eq(Balance.TECH_BURST_CHANCE,0.0,"本轮交付配置明确关闭技术爆炸")
	var s:=remote_match()
	var me:=s.human()
	var techs:=me.techs.duplicate()
	var rng_before:=s.rng.state
	s._tech_burst(me)
	check_eq(me.techs,techs,"关闭时即使误调接口也不授予科技")
	check_eq(s.rng.state,rng_before,"关闭接口不消耗随机抽取")
	me.is_ai=true
	me.energy=0
	me.mineral=0
	s.end_turn()
	check(s.events.filter(func(event):return event["kind"]=="tech_burst").is_empty(),"正常AI回合也没有隐藏爆炸事件")


## 规则：科技树
func test_v01_optional_burst_preserves_active_research_and_payment() -> void:
	Balance.TECH_BURST_CHANCE=1.0
	var s:=remote_match()
	var me:=s.human()
	_open_tiers(me,3)
	for id in Tech.ALL:
		me.techs[id]=true
	me.techs.erase("warship")
	me.techs.erase("broadcaster")
	check_eq(s.research(me,"warship")["error"],"","先通过正常接口建立在研工程")
	var paid:=[me.energy,me.mineral,me.actions_left]
	var project:=me.research_project.duplicate(true)
	s._tech_burst(me)
	check(me.has_tech("broadcaster") and not me.has_tech("warship"),"候选排除已有和在研项目")
	check_eq(me.research_project,project,"免费获得另一科技不取消或改变原工程")
	check_eq([me.energy,me.mineral,me.actions_left],paid,"不重复扣资源或AP")
	s._tech_burst(me)
	check(not s.events[-1]["granted"],"没有可选科技时事件记录未授予")
	WorkOrder.advance(me.research_project,100.0)
	s._finish_pending(me,0.0)
	check(me.has_tech("warship"),"原工程仍按合法完工回报获得科技")


## 规则：建造，情报传回
func test_v01_late_order_status_cannot_duplicate_ammo_or_reopen_queue() -> void:
	var s:=remote_match()
	var me:=s.human()
	var order:=WorkOrder.create(s.next_id(),"antimatter",me.home,[1,1],1)
	order["status"]="completed"
	for status in ["completed","working","completed"]:
		order["status"]=status
		Signals.send(s,0,Vector3(me.home),Signals.controller(me),"report",{"type":"order","data":order,
			"t_observed":s.clock,"source_id":Signals.controller(me),"epoch":s.space_epoch})
		Signals.receive_due(s)
	check_eq(me.antimatter,1,"同刻乱序和重复完工只发放一次弹药")
	check(OrderControl.visible(s,me).is_empty(),"晚到工作中回报不能重新打开完工队列")


## 规则：情报传回
func test_v01_tactical_contact_ordering_and_prediction_use_received_history() -> void:
	var s:=remote_match()
	var me:=s.human()
	var observer:=_ship(s,me,Ship.WARSHIP,Vector3.ZERO)
	var id:=s.next_id()
	var body:={"type":"entity","data":{"id":id,"owner":1,"kind":Ship.WARSHIP,"pos":Vector3(0.2,0,0),"velocity":Vector3(0.1,0,0),"hp":2},
		"t_observed":3.0,"epoch":s.space_epoch,"source_id":observer.id}
	for observed_at in [3.0,2.0]:
		body["t_observed"]=observed_at
		Signals.send(s,0,observer.pos,observer.id,"sensor",body)
		Signals.receive_due(s)
	check_eq(observer.local_contacts[id]["t_observed"],3.0,"较旧传感包不覆盖舰上新观测")
	check_eq(me.sightings[-1]["t_observed"],3.0,"较旧传感包不覆盖控制端新观测")
	check(Combat.predicted(s,observer.local_contacts[id]).is_equal_approx(Vector3(0.3,0,0)),"瞄准先计入观测年龄，再作有限弹速提前量")
