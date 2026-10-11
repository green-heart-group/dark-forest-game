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
	var recipients:=_battle_recipients(s,civ)
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


## 战况查询的收件者 {编号: 位置}：已知的据点（Knowledge.assets 里的锚点），再加已知的舰船（Signals.reported_ships，光粒除外）。
## 和那两个函数得出的一样、顺序也一样，只是不为每艘船重建一份船的状态、不为每处据点拍快照：每收一条己方回报就要算一次。
static func _battle_recipients(s: GameState,civ: Civ) -> Dictionary:
	var owner:=s.civs.find(civ)
	var control:=Signals.entity(s,owner,Signals.controller(civ))
	var center: Vector3=control.get("pos",Vector3(civ.home))
	var size:=s.physical_cell_size()
	# 已知的舰船：[编号, 种类, 位置, 是否在控制地点]，和 reported_ships 同样的编号和顺序。
	var ids: Array=civ.telemetry.keys()
	if not control.is_empty():
		for ship in civ.ships:
			if ship.pos.distance_to(control["pos"])*size<=Balance.COLLISION_EPSILON and not ids.has(ship.id):
				ids.append(ship.id)
	ids.sort()
	var ships: Array=[]
	for id in ids:
		var actual:=civ.ship_by_id(id)
		var pos: Vector3
		var kind: String
		if actual!=null and not actual.dead and not control.is_empty() and actual.pos.distance_to(control["pos"])*size<=Balance.COLLISION_EPSILON:
			pos=actual.pos
			kind=actual.kind
		elif civ.telemetry.has(id) and not civ.telemetry[id]["data"]["dead"]:
			pos=civ.telemetry[id]["data"]["pos"]
			kind=civ.telemetry[id]["data"]["kind"]
		else:
			continue
		ships.append([id,kind,pos,center.distance_to(pos)*size<=Balance.COLLISION_EPSILON])
	var recipients: Dictionary={}
	var add_anchors:=func(assets: Array):
		for asset in assets:
			if asset["kind"]=="anchor":
				recipients[asset["id"]]=Vector3(asset["at"])
	# Knowledge.colonies：有回报说还占着的星系，加上在控制地点、自己知道还占着的；排好序。
	var cells: Array[Vector3i]=[]
	for cell in civ.site_reports:
		var here: bool=center.distance_to(Vector3(cell))*size<=Balance.COLLISION_EPSILON
		if civ.owns(cell) if here else civ.site_reports[cell].get("data",{}).get("owned",false):
			cells.append(cell)
	for cell in civ.colonies:
		if center.distance_to(Vector3(cell))*size<=Balance.COLLISION_EPSILON and not cells.has(cell):
			cells.append(cell)
	cells.sort()
	for cell in cells:
		if center.distance_to(Vector3(cell))*size<=Balance.COLLISION_EPSILON:
			add_anchors.call(civ.assets.filter(func(a):return a["at"]==cell and a["carrier"]<0))
		else:
			add_anchors.call(civ.site_reports.get(cell,{}).get("data",{}).get("assets",[]))
	for ship in ships:
		if ship[3]:
			add_anchors.call(civ.assets.filter(func(a):return a["carrier"]==ship[0]))
		else:
			add_anchors.call(civ.telemetry.get(ship[0],{}).get("data",{}).get("assets",[]))
	for ship in ships:
		if ship[1]!=Ship.GRAIN:
			recipients[ship[0]]=ship[2]
	return recipients


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
		# 只有有人住的格子听得见。殖民要求有恒星（can_settle），所以只给有恒星或现在有人住的格子发光线；
		# 空格子的光线到了也没人收，却会让整个世界多停一次。波传到哪里由下面的地图角光线负责。
		if s.map.star_at(cell) == StarMap.Star.NONE and s.coord_owner(cell) == null:
			continue
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


## 光线在一个子步里自己分段走（Hazards.light_travel），过光速不同的边界不让整个世界停下。
## 广播光线的到达也不停：advance 记下准确的到达时刻，resolve 在子步末按那个时刻补做。
## 扫描要在到达那一刻给格子拍快照，仍然在到达时停。uniform：全图光速处处相同（Hazards.uniform_light）。
static func next_change(s: GameState, uniform := false) -> float:
	var time := INF
	var memo: Variant = _memo(s)
	for wave in s.scans:
		for sample in wave["samples"]:
			if sample["done"]:
				continue
			if uniform:
				var speed := _speed(s, sample["pos"], memo)
				if speed > 0.0:
					time = minf(time,sample["remaining"]/speed)
			else:
				time = minf(time,Hazards.light_travel(s,sample["pos"],sample["direction"],sample["remaining"],INF)["arrival"])
	return time


## 没有黑域和死线时，光速只随格子变，而且只有在出事的那一刻才变；广播光线走到哪只取决于时间。
## 这时不必每个子步逐条挪动光线：开始时按当时的光速表（LightFront.environment）算好每条光线的到达时刻 eta，
## 按时间排好（order）；到了最早的到达时刻 due，只把到了的几条放到终点，其余光线停在 lazy_from 那一刻不动。
## 光速表变了（有星系熄灭、换图等），先用旧表把所有光线推进到现在，再按新表重新排。
static func advance(s: GameState, dt: float, uniform := false) -> void:
	var env:=LightFront.environment(s,uniform) if not waves(s).is_empty() else {}
	var memo: Variant = _memo(s)
	var fixed := not Hazards.any(s)
	for wave in waves(s):
		LightFront.remember(wave,env,s.clock,s.clock+dt)
		if fixed and wave.has("sender"):
			if wave.has("medium") and wave["medium"] != env and not _swap_medium(s, wave, env):
				settle_wave(s, wave)
			if not wave.has("medium"):
				_lazy_begin(s, wave, env)
			_lazy_arrive(s, wave, s.clock + dt)
			var reach: float = wave["live_max"] + env["speed"]*(s.clock + dt - wave["lazy_from"])
			wave["radius"] = maxf(wave.get("radius",0.0), reach/s.physical_cell_size())
			continue
		settle_wave(s, wave)
		for sample in wave["samples"]:
			if sample["done"]:
				continue
			if uniform:
				_step(s, wave, sample, _speed(s, sample["pos"], memo), dt, s.clock)
			else:
				var trip := Hazards.light_travel(s, sample["pos"], sample["direction"], sample["remaining"], dt)
				_move(s, wave, sample, trip["distance"], trip["arrival"], s.clock)


static func _step(s: GameState, wave: Dictionary, sample: Dictionary, speed: float, dt: float, start: float) -> void:
	var arrival: float = sample["remaining"]/speed if speed > 0.0 and sample["remaining"] <= speed*dt else INF
	_move(s, wave, sample, minf(sample["remaining"], speed*dt), arrival, start)


## 光线这一段走了 distance；arrival 是从 start 起到达终点用的时间，没到为 INF。
static func _move(s: GameState, wave: Dictionary, sample: Dictionary, distance: float, arrival: float, start: float) -> void:
	if arrival < INF:
		sample["arrived_at"] = start + arrival
	sample["leg_distance"] += distance
	sample["pos"] = sample["leg_start"] + sample["direction"]*sample["leg_distance"]/s.physical_cell_size()
	sample["remaining"] = maxf(0.0,sample["remaining"]-distance)
	sample["distance"] += distance
	wave["radius"] = maxf(wave.get("radius",0.0),sample["distance"]/s.physical_cell_size())


## 光线从现在起照 table 走，多久到终点。
static func _eta(s: GameState, sample: Dictionary, table: Dictionary) -> float:
	if table["speeds"].is_empty():
		return sample["remaining"]/table["speed"] if table["speed"] > 0.0 else INF
	return Hazards.light_travel(s, sample["pos"], sample["direction"], sample["remaining"], INF, table)["arrival"]


static func _lazy_begin(s: GameState, wave: Dictionary, table: Dictionary) -> void:
	var keyed := []
	var live_max := 0.0
	var samples: Array = wave["samples"]
	for i in samples.size():
		var sample: Dictionary = samples[i]
		if sample["done"]:
			continue
		sample["eta"] = s.clock + _eta(s, sample, table)
		keyed.append([sample["eta"], i])
		live_max = maxf(live_max, sample["distance"])
	# 按到达时刻排，同时到的按光线顺序。[时刻, 序号] 直接用内置排序比较，比逐对调用脚本函数快得多。
	keyed.sort()
	var order := keyed.map(func(pair): return pair[1])
	wave["medium"] = table
	wave["order"] = order
	wave["cursor"] = 0
	wave["lazy_from"] = s.clock
	wave["live_max"] = live_max
	wave["due"] = samples[order[0]]["eta"] if not order.is_empty() else INF


## 把到 time 为止该到的光线放到终点，记下准确的到达时刻；resolve 看到 check 才去处理。
static func _lazy_arrive(s: GameState, wave: Dictionary, time: float) -> void:
	var samples: Array = wave["samples"]
	var order: Array = wave["order"]
	var cursor: int = wave["cursor"]
	while cursor < order.size() and samples[order[cursor]]["eta"] <= time + Balance.TIME_EPSILON:
		var sample: Dictionary = samples[order[cursor]]
		_move(s, wave, sample, sample["remaining"], sample["eta"] - wave["lazy_from"], wave["lazy_from"])
		sample.erase("lazy_from")
		wave["check"] = true
		cursor += 1
	wave["cursor"] = cursor
	wave["due"] = samples[order[cursor]]["eta"] if cursor < order.size() else INF


## 离开「到点才推进」之前（光速表变了、出现黑域或死线、换图），用旧表把还在路上的光线推进到现在。
static func settle_wave(s: GameState, wave: Dictionary) -> void:
	if not wave.has("medium"):
		return
	_lazy_arrive(s, wave, s.clock)
	var table: Dictionary = wave["medium"]
	var start: float = wave["lazy_from"]
	var samples: Array = wave["samples"]
	var order: Array = wave["order"]
	for k in range(wave["cursor"], order.size()):
		var sample: Dictionary = samples[order[k]]
		# 被 _swap_medium 单独推进过的光线从它自己那一刻接着推进。
		var from: float = sample.get("lazy_from", start)
		if s.clock > from:
			var trip := Hazards.light_travel(s, sample["pos"], sample["direction"], sample["remaining"], s.clock - from, table)
			_move(s, wave, sample, trip["distance"], trip["arrival"], from)
		sample.erase("eta")
		sample.erase("lazy_from")
	for key in ["medium", "order", "cursor", "lazy_from", "live_max", "due"]:
		wave.erase(key)


## 光速表只是几个格子的光速变了（比如有格子降了维）时，不用整条波重排：
## 只把剩下的路线穿过这些格子的光线按旧表推进到现在，再按新表算到达时刻；其余光线一路光速没变，到达时刻照旧。
## 别的东西也变了（格子大小、背景光速、换图、黑域、死线），或者变的格子太多，返回 false，由调用方整条重排。
static func _swap_medium(s: GameState, wave: Dictionary, env: Dictionary) -> bool:
	var old: Dictionary = wave["medium"]
	for key in ["size", "speed", "epoch"]:
		if old[key] != env[key]:
			return false
	for key in ["immunity", "domains", "lines"]:
		if not old[key].is_empty() or not env[key].is_empty():
			return false
	var changed: Array[Vector3i] = []
	for cell in old["speeds"]:
		if env["speeds"].get(cell, env["speed"]) != old["speeds"][cell]:
			changed.append(cell)
	for cell in env["speeds"]:
		if not old["speeds"].has(cell):
			changed.append(cell)
	if changed.size() > 64:
		return false
	_lazy_arrive(s, wave, s.clock)
	var boxes := Geometry.cell_boxes(changed)
	var start: float = wave["lazy_from"]
	var samples: Array = wave["samples"]
	var order: Array = wave["order"]
	var keyed := []
	for k in range(wave["cursor"], order.size()):
		var i: int = order[k]
		var sample: Dictionary = samples[i]
		if Geometry.crosses_cells(boxes, sample["pos"], sample["target"]):
			var from: float = sample.get("lazy_from", start)
			if s.clock > from:
				var trip := Hazards.light_travel(s, sample["pos"], sample["direction"], sample["remaining"], s.clock - from, old)
				_move(s, wave, sample, trip["distance"], trip["arrival"], from)
			sample["lazy_from"] = s.clock
			sample["eta"] = s.clock + _eta(s, sample, env)
		keyed.append([sample["eta"], i])
	keyed.sort()
	wave["order"] = order.slice(0, wave["cursor"]) + keyed.map(func(pair): return pair[1])
	wave["medium"] = env
	wave["due"] = samples[wave["order"][wave["cursor"]]]["eta"] if wave["cursor"] < wave["order"].size() else INF
	return true


static func settle(s: GameState) -> void:
	for wave in s.broadcasts:
		settle_wave(s, wave)

static func resolve(s: GameState) -> void:
	if s.clock < s.remap_until:
		return
	for wave in s.broadcasts:
		# 到点才推进的波，只有刚推进过才可能有光线到达。
		if wave.has("lazy_from") and not wave.get("check", false):
			continue
		wave.erase("check")
		for sample in wave["samples"]:
			if sample["done"] or sample["remaining"] > Balance.COLLISION_EPSILON:
				continue
			sample["done"] = true
			# 光速处处相同时到达不切子步，这里可能比到达晚一点；一律按准确的到达时刻记。
			# 不和现在取小：到达时刻可能比现在晚不到 TIME_EPSILON，取小就记早了。
			var at: float = sample.get("arrived_at", s.clock)
			if sample.has("cell_id"):
				wave["visited"][sample["cell_id"]] = at
				var civ := s.coord_owner(sample["cell"])
				if civ != null and not civ.dormant_colonies.has(sample["cell"]) and (civ.has_tech("gravity") or civ.broadcasters.has(sample["cell"])):
					_hear(s,wave,civ,sample["pos"],at)
			elif sample.has("hidden"):
				var index: int = sample["hidden"]
				wave["hidden_heard"][index] = true
				s.hidden_listen.append({"id":s.next_id(),"from":s.hidden[index],"target":wave["target"],
					"left":Balance.HIDDEN_PATIENCE,"next_check":at+1.0,"received":at})
			elif sample.has("ship_id"):
				var civ: Civ = s.civs[sample["owner"]]
				var ship := civ.ship_by_id(sample["ship_id"])
				if ship != null and not ship.dead and not ship.dormant and ship.gravity and ship.pos.distance_to(sample["pos"])*s.physical_cell_size() <= Balance.COLLISION_EPSILON:
					_hear(s,wave,civ,ship.pos,at)
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
	s.broadcasts = s.broadcasts.filter(_live)
	s.scans = s.scans.filter(_live)


static func _live(wave: Dictionary) -> bool:
	if wave.get("due", INF) < INF:
		return true
	for sample in wave["samples"]:
		if not sample["done"]:
			return true
	return false


## at：广播到达的准确时刻，可能略早于现在。回报照样从那一刻出发，先补走晚掉的那段路。
static func _hear(s: GameState, wave: Dictionary, civ: Civ, pos: Vector3, at: float) -> void:
	if civ == wave["sender"] or wave["heard"].has(civ) or not civ.alive:
		return
	wave["heard"][civ] = true
	var message := Signals.send(s,s.civs.find(civ),pos,Signals.controller(civ),"report",{"type":"broadcast","target":wave["target"],
		"exposed":wave["exposed"],"has_exposure":wave["has_exposure"],"t_observed":at,"epoch":s.space_epoch,"source_id":wave["id"]},0,false)
	Signals.catch_up(s,message,s.clock-at)


## 隐藏文明听到广播以后每年决定一次要不要出手，在回合开始时决定（WorldTime.advance 开头），不为它切开一年。
## 到了 next_check 的才决定，所以只会比「听到后满一年」晚，不会早。
static func hidden_strikes(s: GameState) -> void:
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
