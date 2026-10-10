class_name Information
extends RefCounted
## 主动信息波保留各永久格子/收件者的前沿样本。每份样本从当前位置继续传播，换图不追溯送达。
## 星系采样点是原地图格心；往返报告和本地预警仍经过Signals的有限光速链路。


## 仅报告这处锚点已毁，不查询敌方的其他星系、星舰或全局存续。
static func system_destroyed(s: GameState,attacker: int,victim: int,cell: Vector3i,anchor_id: int,cause: String) -> void:
	if attacker<0 or attacker==victim or anchor_id<0:
		return
	var event_id:=s.survey_sequence
	s.survey_sequence-=1
	var body: Dictionary={"type":"site_destroyed","event_id":event_id,"attacker":attacker,
		"victim":victim,"cell_id":s.cell_ids[cell],"cell":cell,"anchor_id":anchor_id,
		"cause":cause,"t_observed":s.clock,"epoch":s.space_epoch}
	s.pending_battle_surveys.append(body)
	Signals.send(s,attacker,Vector3(cell),Signals.controller(s.civs[attacker]),"report",body,s.survey_sequence)
	s.survey_sequence-=1


## 选毁灭事件所在的同刻批次T作历史截面。只有被己方传感器实际覆盖的格子能发证据。
## 分散时间的旧情报不能拼成“全部清空”；未覆盖或光路被阻断时证明保持不完整。
static func observe_battles(s: GameState) -> void:
	for battle in s.pending_battle_surveys:
		var civ: Civ=s.civs[battle["attacker"]]
		var eyes:=Signals.observers(s,civ)
		for cell in s.cell_ids:
			for eye in eyes:
				if not Signals.in_view(s,eye,Vector3(cell)):
					continue
				var owner:=s.coord_owner(cell)
				# 持续传感录像按需保存T截面，不通知传感器发生了远方战斗。
				# 私有传感包使用单独编号，不能让隐藏核查改变公开命令/实体编号。
				Signals.send(s,battle["attacker"],Vector3(cell),eye["id"],"survey_record",{
					"type":"battle_survey","event_id":battle["event_id"],"cell_id":s.cell_ids[cell],
					"local_owner":s.civs.find(owner) if owner!=null else -1,
					"t_observed":battle["t_observed"],"epoch":battle["epoch"]},s.survey_sequence)
				s.survey_sequence-=1
	s.pending_battle_surveys.clear()


## 私有事件号只在物理消息中流转；公开编号按本文明实际收到的战报次序生成。
static func receive_battle(s: GameState,owner: int,body: Dictionary) -> void:
	var civ: Civ=s.civs[owner]
	if not s.battle_tokens.has(owner):
		s.battle_tokens[owner]={}
	var tokens: Dictionary=s.battle_tokens[owner]
	var private_id: int=body["event_id"]
	if not tokens.has(private_id):
		tokens[private_id]=civ.battle_reports.size()+1
	var report: Dictionary=body.duplicate(true)
	report["event_id"]=tokens[private_id]
	civ.battle_reports[report["event_id"]]=report
	civ.record_hits[report["cell"]]=s.turn
	query_battles(s,civ)
	confirm_battles(s,civ)


## 已知战报到达后才能查询；收件者只来自当时已收己方遥测，不枚举真实远端传感器。
static func query_battles(s: GameState,civ: Civ) -> void:
	var known:=Knowledge.assets(s,civ).filter(func(asset):return asset["kind"]=="anchor")
	var recipients: Dictionary={}
	for asset in known:
		recipients[asset["id"]]=Vector3(asset["at"])
	for ship in Signals.reported_ships(s,civ):
		if ship.kind!=Ship.GRAIN:
			recipients[ship.id]=ship.pos
	for event_id in civ.battle_reports:
		var private_id: Variant=s.battle_tokens.get(s.civs.find(civ),{}).find_key(event_id)
		if private_id==null:
			continue
		for id in recipients:
			var key: Array=[event_id,id]
			if civ.battle_queries.has(key):
				continue
			civ.battle_queries[key]=true
			Signals.send(s,s.civs.find(civ),Signals.entity(s,s.civs.find(civ),Signals.controller(civ)).get("pos",Vector3(civ.home)),id,"survey_query",{
				"event_id":private_id,"recipient_pos":recipients[id]},s.survey_sequence)
			s.survey_sequence-=1


## 原始信息先沿真实cell→sensor光路抵达；查询前只保存在这一个传感器的私有缓冲。
static func receive_record(s: GameState,message: Dictionary) -> void:
	var key: Array=[message["owner"],message["recipient"],message["body"]["event_id"]]
	if not s.battle_archive.has(key):
		s.battle_archive[key]={"records":{},"requested":false,"sent":{}}
	var archive: Dictionary=s.battle_archive[key]
	var record: Dictionary=message["body"].duplicate(true)
	record["t_local_received"]=s.clock
	record["source_id"]=message["recipient"]
	archive["records"][record["cell_id"]]=record
	_relay_archive(s,key)


static func receive_query(s: GameState,message: Dictionary) -> void:
	var key: Array=[message["owner"],message["recipient"],message["body"]["event_id"]]
	if not s.battle_archive.has(key):
		s.battle_archive[key]={"records":{},"requested":false,"sent":{}}
	s.battle_archive[key]["requested"]=true
	_relay_archive(s,key)


static func _relay_archive(s: GameState,key: Array) -> void:
	var archive: Dictionary=s.battle_archive[key]
	var sensor:=Signals.entity(s,key[0],key[1])
	if not archive["requested"] or sensor.is_empty():
		return
	var civ: Civ=s.civs[key[0]]
	if (sensor.has("ship") and sensor["ship"].dormant) or (sensor.has("asset") and civ.dormant_colonies.has(sensor["asset"]["at"])):
		return
	for cell_id in archive["records"]:
		if archive["sent"].has(cell_id):
			continue
		archive["sent"][cell_id]=true
		Signals.send(s,key[0],sensor["pos"],Signals.controller(civ),"report",archive["records"][cell_id],s.survey_sequence)
		s.survey_sequence-=1


static func retry_archives(s: GameState) -> void:
	for key in s.battle_archive:
		_relay_archive(s,key)


## 资格只从已收到的局部证据得出；晚到的确认可证明过去T时刻，不声称此刻仍无新殖民。
static func confirm_battles(s: GameState,civ: Civ) -> void:
	if civ.conquered:
		return
	for id in civ.battle_reports:
		var battle: Dictionary=civ.battle_reports[id]
		var survey: Dictionary=civ.battle_surveys.get(id,{})
		if survey.is_empty() or survey["seen"].size()!=s.cell_ids.size():
			continue
		if survey["t_observed"]!=battle["t_observed"] or survey["epoch"]!=battle["epoch"] or survey["owners"].has(battle["victim"]):
			continue
		civ.conquered=true
		civ.conquest_confirmation={"victim":battle["victim"],"qualified_at":battle["t_observed"],"confirmed_at":s.clock,"event_id":id}
		return


static func ray(s: GameState, origin: Vector3, target: Vector3, fields: Dictionary) -> Dictionary:
	var result := {"id":s.next_id(),"pos":origin,"origin":origin,"target":target,
		"direction":(target-origin).normalized(),"distance":0.0,"leg_distance":0.0,"leg_start":origin,
		"remaining":origin.distance_to(target)*s.physical_cell_size(),"done":false,"epoch":s.space_epoch}
	result.merge(fields,true)
	return result


static func broadcast(s: GameState, civ: Civ, origin: Vector3, target: Vector3i, exposed: Vector3i) -> void:
	var samples: Array[Dictionary] = []
	for cell in s.cell_ids:
		samples.append(ray(s,origin,Vector3(cell),{"cell_id":s.cell_ids[cell],"cell":cell}))
	for i in s.hidden.size():
		samples.append(ray(s,origin,Vector3(s.hidden[i]),{"hidden":i}))
	# 最远的格子中心已越过时，地图外沿仍可能有新出现的舰载接收器。
	for corner in 8:
		var at:=Vector3(s.map.origin)-Vector3.ONE*0.5
		for axis in 3:
			if corner&(1<<axis): at[axis]+=s.map.extent[axis]
		samples.append(ray(s,origin,at,{"boundary":true}))
	for owner in s.civs.size():
		for ship in s.civs[owner].ships:
			if not ship.dead and ship.kind != Ship.GRAIN:
				samples.append(ray(s,origin,ship.pos,{"ship_id":ship.id,"owner":owner}))
	s.broadcasts.append({"id":s.next_id(),"from":origin,"target":target,"sender":civ,"exposed":exposed,
		"has_exposure":exposed!=GameState.NO_HIT,"radius":0.0,"heard":{},"hidden_heard":{},
		"samples":samples,"sent":s.clock,"epoch":s.space_epoch,"visited":{},"propagation":LightFront.begin(s,origin)})
	Signals.send(s,s.civs.find(civ),origin,Signals.controller(civ),"report",{"type":"broadcast_sent",
		"data":{"id":s.broadcasts[-1]["id"],"from":origin,"target":target,"exposed":exposed,"sent":s.clock},"t_observed":s.clock,"epoch":s.space_epoch})


static func scan_source(s: GameState, civ: Civ) -> Dictionary:
	var original := Signals.entity(s,s.civs.find(civ),civ.original_anchor_id)
	if not original.is_empty():
		return original
	for ship in civ.ships:
		if ship.kind == Ship.WANDERING_EARTH and not ship.dead:
			return Signals.entity(s,s.civs.find(civ),ship.id)
	return {}


static func inside_scan(s: GameState, origin: Vector3, direction: Vector3, target: Vector3) -> bool:
	var delta := (target-origin)*s.physical_cell_size()
	var forward := delta.dot(direction)
	return forward >= 0.0 and forward <= Balance.SCAN_LENGTH and (delta-direction*forward).length() <= Balance.SCAN_RADIUS


static func scan(s: GameState, civ: Civ, source: Dictionary, direction: Vector3) -> void:
	var samples: Array[Dictionary] = []
	for cell in s.system_cells:
		if inside_scan(s,source["pos"],direction,Vector3(cell)):
			samples.append(ray(s,source["pos"],Vector3(cell),{"cell_id":s.cell_ids[cell],"cell":cell}))
	for target in Combat.targets(s):
		if target["owner"] != s.civs.find(civ) and inside_scan(s,source["pos"],direction,target["pos"]):
			samples.append(ray(s,source["pos"],target["pos"],{"entity_id":target["id"]}))
	s.scans.append({"id":s.next_id(),"owner":s.civs.find(civ),"source_id":source["id"],"from":source["pos"],
		"direction":direction,"samples":samples,"sent":s.clock,"epoch":s.space_epoch,"propagation":LightFront.begin(s,source["pos"])})
	# 保留没有静态目标的扫描；发射后才进入柱体的单位同样可能与波前相交。
	s.scans[-1]["samples"].append(ray(s,source["pos"],source["pos"]+direction*sqrt(Balance.SCAN_LENGTH*Balance.SCAN_LENGTH+Balance.SCAN_RADIUS*Balance.SCAN_RADIUS)/s.physical_cell_size(),{"boundary":true}))


static func waves(s: GameState) -> Array:
	var result: Array = s.broadcasts.duplicate()
	result.append_array(s.scans)
	return result


## 没有黑域和死线时，同一格里的光速相同：一次调用内按格子记下，和逐点现查是同一个数。
static func _speed(s: GameState, pos: Vector3, memo: Variant) -> float:
	if memo == null:
		return s.light_speed_at(pos)
	var cell := Vector3i(pos.round())
	if not memo.has(cell):
		memo[cell] = s.light_speed_at(pos)
	return memo[cell]


static func _memo(s: GameState) -> Variant:
	return null if Hazards.any(s) else {}


## uniform：全图光速处处相同（Hazards.uniform_light），这时光线只在到达时有变化。
static func next_change(s: GameState, uniform := false) -> float:
	var time := INF
	var memo: Variant = _memo(s)
	for wave in waves(s):
		for sample in wave["samples"]:
			if sample["done"]:
				continue
			var speed := _speed(s, sample["pos"], memo)
			if speed > 0.0:
				time = minf(time,sample["remaining"]/speed)
				if uniform:
					continue
				var motion := {"pos":sample["pos"],"velocity":sample["direction"]*speed/s.physical_cell_size(),"acceleration":Vector3.ZERO}
				time = minf(time,Hazards.next_boundary(s,motion,Balance.PHYSICS_MAX_DT))
	for listener in s.hidden_listen:
		time = minf(time,maxf(0.0,listener["next_check"]-s.clock))
	return time


static func advance(s: GameState, dt: float) -> void:
	var env:=LightFront.environment(s) if not waves(s).is_empty() else {}
	var memo: Variant = _memo(s)
	for wave in waves(s):
		LightFront.remember(wave,env,s.clock,s.clock+dt)
		for sample in wave["samples"]:
			if sample["done"]:
				continue
			var speed := _speed(s, sample["pos"], memo)
			var distance: float = minf(sample["remaining"], speed*dt)
			sample["leg_distance"] += distance
			sample["pos"] = sample["leg_start"] + sample["direction"]*sample["leg_distance"]/s.physical_cell_size()
			sample["remaining"] = maxf(0.0,sample["remaining"]-distance)
			sample["distance"] += distance
			wave["radius"] = maxf(wave.get("radius",0.0),sample["distance"]/s.physical_cell_size())


static func resolve(s: GameState) -> void:
	if s.clock < s.remap_until:
		return
	for wave in s.broadcasts:
		for sample in wave["samples"]:
			if sample["done"] or sample["remaining"] > Balance.COLLISION_EPSILON:
				continue
			sample["done"] = true
			if sample.has("cell_id"):
				wave["visited"][sample["cell_id"]] = s.clock
				var civ := s.coord_owner(sample["cell"])
				if civ != null and not civ.dormant_colonies.has(sample["cell"]) and (civ.has_tech("gravity") or civ.broadcasters.has(sample["cell"])):
					_hear(s,wave,civ,sample["pos"])
			elif sample.has("hidden"):
				var index: int = sample["hidden"]
				wave["hidden_heard"][index] = true
				s.hidden_listen.append({"id":s.next_id(),"from":s.hidden[index],"target":wave["target"],
					"left":Balance.HIDDEN_PATIENCE,"next_check":s.clock+1.0,"received":s.clock})
			elif sample.has("ship_id"):
				var civ: Civ = s.civs[sample["owner"]]
				var ship := civ.ship_by_id(sample["ship_id"])
				if ship != null and not ship.dead and not ship.dormant and ship.gravity and ship.pos.distance_to(sample["pos"])*s.physical_cell_size() <= Balance.COLLISION_EPSILON:
					_hear(s,wave,civ,ship.pos)
	for wave in s.scans:
		var civ: Civ = s.civs[wave["owner"]]
		for sample in wave["samples"]:
			if sample["done"] or sample["remaining"] > Balance.COLLISION_EPSILON:
				continue
			sample["done"] = true
			if sample.has("boundary"): continue
			var body := {"t_observed":s.clock,"source_id":wave["source_id"],"epoch":s.space_epoch,"scan":wave["id"]}
			if sample.has("cell"):
				body.merge({"type":"cell","cell":sample["cell"],"cell_id":sample["cell_id"],"data":s.snapshot(sample["cell"])})
			else:
				if wave.get("propagation",{}).get("received",{}).has(sample["entity_id"]): continue
				var targets := Combat.targets(s).filter(func(target):return target["id"]==sample["entity_id"] and target["pos"].distance_to(sample["pos"])*s.physical_cell_size()<=Balance.COLLISION_EPSILON)
				if targets.is_empty():
					continue
				var target: Dictionary = targets[0]
				body.merge({"type":"entity","data":{"id":target["id"],"owner":target["owner"],"kind":target["kind"],"pos":target["pos"],"velocity":target["velocity"],"hp":target["hp"]}})
			Signals.send(s,wave["owner"],sample["pos"],wave["source_id"],"sensor",body)
	s.broadcasts = s.broadcasts.filter(func(wave):return wave["samples"].any(func(sample):return not sample["done"]))
	s.scans = s.scans.filter(func(wave):return wave["samples"].any(func(sample):return not sample["done"]))
	_hidden_strikes(s)


static func _hear(s: GameState, wave: Dictionary, civ: Civ, pos: Vector3) -> void:
	if civ == wave["sender"] or wave["heard"].has(civ) or not civ.alive:
		return
	wave["heard"][civ] = true
	Signals.send(s,s.civs.find(civ),pos,Signals.controller(civ),"report",{"type":"broadcast","target":wave["target"],
		"exposed":wave["exposed"],"has_exposure":wave["has_exposure"],"t_observed":s.clock,"epoch":s.space_epoch,"source_id":wave["id"]})


static func _hidden_strikes(s: GameState) -> void:
	for listener in s.hidden_listen:
		if listener["left"] <= 0 or s.clock < listener["next_check"]-Balance.TIME_EPSILON:
			continue
		listener["next_check"] += 1.0
		listener["left"] -= 1
		var origin := Vector3(listener["from"])
		var target := Vector3(listener["target"])
		var chance := Balance.HIDDEN_STRIKE_CHANCE * maxf(0.0,1.0-origin.distance_to(target)*s.physical_cell_size()/Balance.HIDDEN_HEAR_RANGE)
		if chance <= 0 or s.rng.randf() >= chance:
			continue
		listener["left"] = 0
		if s.dimension > 1 and s.rng.randf() < Balance.HIDDEN_FOIL_CHANCE:
			SpaceEvents.launch(s,-1,origin,target,"dimension")
		else:
			var grain := Ship.make(Ship.GRAIN,origin,s.next_id())
			grain.docked = false
			grain.direction = (target-origin).normalized()
			s.hidden_ships.append(grain)
	s.hidden_listen = s.hidden_listen.filter(func(listener):return listener["left"]>0)
