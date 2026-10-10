extends "res://tests/rules/rule_suite.gd"
## 正式稿第24–25页：下一维航程预览和逐实体准备确认只读已收信息。


func _preview_script():
	if not FileAccess.file_exists("res://rules/navigation_preview.gd"):
		check(false,"正式稿要求的当前/下一维导航预览尚未实现")
		return null
	return load("res://rules/navigation_preview.gd")


func _preview_match() -> GameState:
	var s:=_two_civs(Vector3i(8,8,8))
	s.ensure_cells()
	s.light.resize(DimensionSpace.COUNT)
	s.light.fill(1.0)
	for civ in s.civs:
		Assets.ensure(s,civ)
	return s


## 规则：二维、单向著和奇异点
func test_v01_preview_scales_distances_and_capped_eta() -> void:
	var preview=_preview_script()
	if preview==null:
		return
	var s:=_preview_match()
	var me:=s.human()
	var ship:=_ship(s,me,Ship.STARSHIP,Vector3.ZERO)
	var goal:=Vector3i(8,8,8)
	var data: Dictionary=preview.compare(s,me,ship.pos,goal,ship.id)
	var current: Dictionary=data["current"]
	var next: Dictionary=data["next"]
	check_eq([current["dim"],next["dim"],current["cell_size"],next["cell_size"]],[3,2,1.0,0.5],"格距按正式稿并排显示")
	check(absf(current["distance"]-sqrt(192.0))<1e-6,"三维欧氏物理距离")
	check(absf(next["distance"]-sqrt(1352.0)*0.5)<1e-6,"固定Peano映射后的二维物理距离")
	check(absf(next["signal_eta"]-next["distance"]/0.6)<1e-6,"下一维光行时使用.6ly/年")
	var expected: float=15.0+(current["distance"]-1.125)/0.15
	check(absf(current["eta"]-expected)<1e-5,"舰船ETA包含加速到.15ly/年的完整过程")
	check_eq(data["weapons"]["railgun"]["range"],Balance.WEAPON_DATA["railgun"]["range"],"公开武器射程保持物理ly")
	check_eq(data["weapons"]["railgun"]["next_cells"],0.2,"格距减半时射程格数翻倍，不改武器数值")
	s.fold_anchor=Vector3i.ZERO
	DimensionSpace.commit(s,false)
	for id in s.cell_dims:
		s.cell_dims[id]=s.dimension
	for civ in s.civs:
		for asset in civ.assets:
			asset["entity_dim"]=s.dimension
		for owned in civ.ships:
			owned.entity_dim=s.dimension
	goal=DimensionSpace.plane_cell(goal,0)
	data=preview.compare(s,me,ship.pos,goal,ship.id)
	check_eq([data["current"]["cell_size"],data["next"]["cell_size"]],[0.5,0.03125],"二维到一维使用1/32ly格距")
	check(absf(data["next"]["distance"]-22.75)<1e-6,"一维729格首尾间距22.75ly")
	check(absf(data["next"]["signal_eta"]-22.75/0.36)<1e-6,"一维最大光行时63.1944年")


## 规则：情报传回
func test_v01_preview_hidden_truth_pair_and_received_threats() -> void:
	var preview=_preview_script()
	if preview==null:
		return
	var s:=_preview_match()
	var me:=s.human()
	var remote:=_ship(s,me,Ship.WARSHIP,Vector3(3,0,0))
	me.telemetry[remote.id]={"data":Signals.ship_status(remote),"t_observed":1.0,"t_received":4.0,"epoch":0}
	me.sightings.append({"id":9001,"kind":Ship.DROPLET,"owner":1,"pos":Vector3(4,0,0),"velocity":Vector3.ZERO,"t_observed":2.0,"t_received":6.0,"epoch":0})
	s.clock=6.0
	var before: Dictionary=preview.compare(s,me,Vector3(3,0,0),Vector3i(8,0,0),remote.id)
	remote.pos=Vector3(7,7,7)
	remote.dormant=true
	s.light[s.light_index(Vector3i(5,0,0))]=0.0
	s.cell_dims[s.cell_ids[Vector3i(4,0,0)]]=1
	s.foil_zones.append({"id":9002,"center":Vector3i(7,7,7),"age":4.0})
	_ship(s,s.civs[1],Ship.WARSHIP,Vector3(2,0,0))
	var after: Dictionary=preview.compare(s,me,Vector3(3,0,0),Vector3i(8,0,0),remote.id)
	check_eq(after,before,"隐藏位置、休眠、黑域、维度和敌舰变化不能改变预览")
	check_eq([before["threats"].size(),before["threats"][0]["t_observed"],before["threats"][0]["t_received"]],[1,2.0,6.0],"只列已收威胁并保留双时间戳")
	check_eq(before["unit_observed"],1.0,"远方航程以最后已收遥测时刻标注")
	check_eq(before["anchors"].size(),1,"未收到的敌方或远端己方据点不进入锚点清单")
	me.intel[Vector3i(5,0,0)]={"relative_light":0.0,"cell_dim":3,"t_observed":3.0,"t_received":6.0}
	var known: Dictionary=preview.compare(s,me,Vector3(3,0,0),Vector3i(8,0,0),remote.id)
	check(known["current"]["eta"]==INF and known["current"]["signal_eta"]==INF,"收到零光速报告后才显示航路受阻")


## 规则：自身降维，情报传回
func test_v01_preview_ready_times_wait_for_round_trip_receipts() -> void:
	var conversion: Script=load("res://rules/conversion.gd")
	if not conversion.has_method("known_ready"):
		check(false,"逐实体ready时间尚未提供给界面")
		return
	var s:=_preview_match()
	var me:=s.human()
	me.techs["dimension"]=true
	var remote:=_ship(s,me,Ship.WARSHIP,Vector3(2,0,0))
	Signals.report_ship(s,me,remote)
	Signals.advance(s,2.0)
	s.clock=2.0
	Signals.receive_due(s)
	var result:=s.prepare_conversion(me,Conversion.known_roster(s,me,3),Signals.controller(me),false,true)
	check_eq(result["error"],"","实际提交迁维工程")
	var id: int=result["order"]
	WorkOrder.advance(me.pending[0],5.0)
	s.clock=7.0
	s._finish_pending(me,0)
	Signals.receive_due(s)
	var rows: Array=conversion.known_ready(s,me,id)
	check_eq([rows[0]["ready_at"],rows[0]["received_at"]],[7.0,7.0],"本地实体同刻确认准备到达")
	check(not rows[1].has("ready_at"),"完工并不等于远方实体ready")
	Signals.advance(s,2.0)
	s.clock=9.0
	Signals.receive_due(s)
	check_eq(remote.ready["3>2"]["at"],9.0,"后端逐实体ready已有真实两年传播")
	var pending: Array=conversion.known_ready(s,me,id)
	check(not pending[1].has("ready_at"),"实体已ready但回执尚未抵达时界面仍不知情")
	me.conversions[id]["status"]="destroyed"
	remote.dead=true
	check_eq(conversion.known_ready(s,me,id),pending,"未收到的失败或死亡不能改变准备展示")
	remote.dead=false
	Signals.advance(s,2.0)
	s.clock=11.0
	Signals.receive_due(s)
	rows=conversion.known_ready(s,me,id)
	check_eq([rows[1]["ready_at"],rows[1]["received_at"],rows[1]["epoch"]],[9.0,11.0,0],"收到回执后分别列真实ready时刻、回执时刻和坐标阶段")
	var copy:=StateCopy.copy(s)
	check_eq(conversion.known_ready(copy,copy.human(),id),rows,"逐实体确认及回执时间保存在快照内")


## 规则：自身降维，情报传回
func test_v01_preview_warning_deducts_information_and_commands() -> void:
	var preview=_preview_script()
	if preview==null:
		return
	var s:=_preview_match()
	var me:=s.human()
	var anchor:=Signals.controller(me)
	var remote:=_ship(s,me,Ship.WARSHIP,Vector3(2,0,0))
	me.telemetry[remote.id]={"data":Signals.ship_status(remote),"t_observed":0.0,"t_received":2.0,"epoch":0}
	me.alerts.append({"id":7001,"kind":"payload","payload_kind":"dimension","pos":Vector3(3,0,0),"velocity":Vector3(-0.25,0,0),"t_observed":0.0,"t_received":3.0,"epoch":0})
	s.clock=3.0
	var options: Dictionary={"host":anchor,"roster":[anchor,remote.id],"automatic":true}
	var data: Dictionary=preview.compare(s,me,Vector3.ZERO,Vector3i(8,0,0),-1,options)
	var local: Dictionary=data["warnings"][0]
	var distant: Dictionary=data["warnings"][1]
	check_eq([local["danger_eta"],local["information_age"],local["information_delay"]],[10.0,3.0,3.0],"预警先扣三年情报传播，而不是显示观察时的13年上界")
	check_eq([distant["danger_eta"],distant["distribution_eta"],distant["needed"],distant["margin"]],[2.0,2.0,7.0,-5.0],"远方实体扣5年施工和2年准备命令传播，余量为负")
	options["automatic"]=false
	data=preview.compare(s,me,Vector3.ZERO,Vector3i(8,0,0),-1,options)
	check_eq(data["warnings"][1]["confirmation_eta"],4.0,"主动执行还需准备回执和执行命令往返")
	me.alerts[0]["epoch"]=-1
	var old: Dictionary=preview.compare(s,me,Vector3.ZERO,Vector3i(8,0,0),-1,options)
	check(is_inf(old["warnings"][0]["danger_eta"]) and not old["threats"].is_empty(),"跨阶段旧轨迹保留历史展示，当前危险余量未知")
	me.alerts[0]["epoch"]=0
	var before:=data.duplicate(true)
	s.payloads.append({"id":7002,"pos":Vector3.ONE,"kind":"dimension","owner":1})
	s.hidden_foils.append(Foil.new(Vector3(6,6,6),Vector3i.ZERO,0))
	check_eq(preview.compare(s,me,Vector3.ZERO,Vector3i(8,0,0),-1,options),before,"未报告的载荷和前沿不改变危险余量")
	me.alerts.clear()
	data=preview.compare(s,me,Vector3.ZERO,Vector3i(8,0,0),-1,options)
	check(is_inf(data["warnings"][0]["danger_eta"]),"无已收轨迹时保持未知，不显示安全保证")


## 规则：调度（派出和行动）
func test_v01_preview_parked_pause_and_outside_destination() -> void:
	var preview=_preview_script()
	if preview==null:
		return
	var s:=_preview_match()
	var me:=s.human()
	var ship:=_ship(s,me,Ship.COLONY,Vector3.ZERO)
	ship.pause_until=2.0
	var data: Dictionary=preview.compare(s,me,ship.pos,Vector3i(1,0,0),ship.id)
	check(absf(data["current"]["eta"]-7.0)<1e-5,"已知暂停加上5年起步加速，不用匀速2.5年冒充ETA")
	ship.dormant=true
	data=preview.compare(s,me,ship.pos,Vector3i(1,0,0),ship.id)
	check(is_inf(data["current"]["eta"]),"已知休眠不显示可到达航时")
	data=preview.compare(s,me,ship.pos,Vector3i(10,0,0),ship.id)
	check(data["outside"] and data["next"]["outside"] and is_inf(data["current"]["eta"]),"图外目的地明确危险，不把边缘映射当作合法目的地")
	check_eq(data["next"]["cell_size"],0.5,"图外目标仍可比较公开格距，不编造下一维坐标")
	s=_preview_match()
	me=s.human()
	s.fold_anchor=Vector3i.ZERO
	DimensionSpace.commit(s,false)
	for id in s.cell_dims:
		s.cell_dims[id]=s.dimension
	Assets.get_id(me,Signals.controller(me))["entity_dim"]=2
	me.techs["dimension"]=true
	var host:=_ship(s,me,Ship.STARSHIP,Vector3.ZERO)
	host.entity_dim=1
	var options: Dictionary={"host":host.id,"roster":[Signals.controller(me)],"automatic":true}
	data=preview.compare(s,me,host.pos,Vector3i(1,0,0),host.id,options)
	check_eq(data["preparation_error"],"","低维星舰宿主为合法已知锚点")
	check(absf(data["warnings"][0]["work_time"]-5.0/0.9)<1e-6,"工期使用已知宿主本体维度的k_work，不误用世界维度")
	host.dormant=true
	data=preview.compare(s,me,host.pos,Vector3i(1,0,0),host.id,options)
	check(is_inf(data["warnings"][0]["work_time"]),"已知休眠宿主不能执行迁维工程，准备时间未知")

