class_name Signals
extends RefCounted
## 有限光速的点对点信息。存当前位置、已走距离和永久收件者ID，换图后继续走。
## 被动传感先到本地接收器，再转发控制锚点；两段时间分别记录。


static func entity(s: GameState, owner: int, id: int) -> Dictionary:
	if owner < 0 or owner >= s.civs.size():
		return {}
	var civ: Civ = s.civs[owner]
	var ship := civ.ship_by_id(id)
	if ship != null and not ship.dead:
		return {"id": id, "pos": ship.pos, "ship": ship}
	var asset := Assets.get_id(civ, id)
	if not asset.is_empty():
		if asset["carrier"] >= 0:
			var carrier := civ.ship_by_id(asset["carrier"])
			return {"id":id,"pos":carrier.pos,"asset":asset} if carrier != null and not carrier.dead else {}
		return {"id": id, "pos": Vector3(asset["at"]), "asset": asset}
	return {}


static func controller(civ: Civ) -> int:
	var anchors := Assets.at(civ, "anchor", civ.home)
	if not anchors.is_empty():
		return anchors[0]["id"]
	var ship := civ.starship()
	return ship.id if ship != null else -1


static func send(s: GameState, owner: int, source: Vector3, recipient: int, kind: String, body: Dictionary, private_id:=0) -> Dictionary:
	var receiver := entity(s, owner, recipient)
	var fallback: Vector3 = body.get("recipient_pos", source)
	var message := {"id": s.next_id() if private_id==0 else private_id, "owner": owner, "pos": source, "source": source,
			"recipient": recipient, "kind": kind, "body": body.duplicate(true),
			"sent": s.clock, "distance": 0.0, "epoch": s.space_epoch, "dead": false,
			"target": receiver["pos"] if not receiver.is_empty() else fallback}
	s.messages.append(message)
	return message


static func motion(s: GameState, message: Dictionary) -> Dictionary:
	var receiver := entity(s, message["owner"], message["recipient"])
	return _motion(s,message,receiver)


static func _motion(s: GameState,message: Dictionary,receiver: Dictionary) -> Dictionary:
	var target: Vector3 = receiver["pos"] if not receiver.is_empty() else message["target"]
	var delta: Vector3 = target - message["pos"]
	var length := delta.length() * s.physical_cell_size()
	var speed := s.light_speed_at(message["pos"])
	return {"arrival": length / speed if speed > 0 else INF, "speed": speed,
			"velocity": delta.normalized() * speed / s.physical_cell_size()}


## 一个物理子步中位置尚未变化；同一收件者和同一消息轨迹只查算一次。
static func plan(s: GameState) -> Dictionary:
	var receivers: Dictionary={}
	var motions: Dictionary={}
	for message in s.messages:
		if message["dead"]:
			continue
		var key: Array=[message["owner"],message["recipient"]]
		if not receivers.has(key):
			receivers[key]=entity(s,key[0],key[1])
		motions[message["id"]]=_motion(s,message,receivers[key])
	return motions


static func next_arrival(s: GameState,prepared: Dictionary = {}) -> float:
	var next := INF
	for message in s.messages:
		if not message["dead"]:
			var m: Dictionary=prepared[message["id"]] if prepared.has(message["id"]) else motion(s,message)
			next = minf(next, m["arrival"])
	return next


static func advance(s: GameState, duration: float,prepared: Dictionary = {}) -> void:
	for message in s.messages:
		if message["dead"]:
			continue
		var m: Dictionary=prepared[message["id"]] if prepared.has(message["id"]) else motion(s,message)
		var dt := minf(duration, m["arrival"])
		message["pos"] += m["velocity"] * dt
		message["distance"] += m["speed"] * dt


static func receive_due(s: GameState, depth := 0) -> void:
	assert(depth < 8, "本地零距离收据不能无限重发")
	var arrived: Array[Dictionary] = []
	var changed := false
	var receivers: Dictionary={}
	for message in s.messages:
		if message["dead"]:
			continue
		if s.clock < message.get("not_before", -INF):
			continue
		var key: Array=[message["owner"],message["recipient"]]
		if not receivers.has(key):
			receivers[key]=entity(s,key[0],key[1])
		var receiver: Dictionary=receivers[key]
		if receiver.is_empty():
			# 收件者死亡不能令远端命令在发送瞬间退款，从余额泄露真实战况。
			if message["pos"].distance_to(message["target"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON:
				message["dead"] = true
				changed = true
				if message["kind"] == "command":
					s._receive_command(message, false)
			continue
		if message["pos"].distance_to(receiver["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON:
			message["dead"] = true
			arrived.append(message)
	for message in arrived:
		_deliver(s, message)
	s.messages = s.messages.filter(func(m): return not m["dead"])
	if changed or not arrived.is_empty():
		receive_due(s, depth + 1)


static func _deliver(s: GameState, message: Dictionary) -> void:
	var owner: int = message["owner"]
	var civ: Civ = s.civs[owner]
	var receiver := entity(s, owner, message["recipient"])
	var body: Dictionary = message["body"]
	if message["kind"]=="survey_record":
		Information.receive_record(s,message)
		return
	if message["kind"]=="survey_query":
		Information.receive_query(s,message)
		return
	if message["kind"] == "command":
		s._receive_command(message, true)
		return
	if message["kind"] == "conversion_ready":
		if not receiver.is_empty():
			var ready: Dictionary = receiver["ship"].ready if receiver.has("ship") else receiver["asset"]["ready"]
			ready[body["step"]] = {"at": s.clock, "fraction": body["fraction"], "plan": body["plan"], "automatic": body.get("automatic", false)}
			send(s, owner, receiver["pos"], controller(civ), "report", {"type": "conversion_ready_receipt",
					"plan": body["plan"], "entity": message["recipient"], "t_observed": s.clock, "epoch": s.space_epoch})
		return
	if message["kind"] == "conversion_execute":
		if not receiver.is_empty():
			Conversion.apply(s, civ, receiver, body["step"], false)
		return
	if message["kind"] == "sensor":
		body["t_local_received"] = s.clock
		if receiver.has("ship") and body["type"] == "cell":
			var key: String="cell:%d"%body["cell_id"]
			if receiver["ship"].local_contacts.get(key,{}).get("t_observed",-INF)<=body["t_observed"]:
				receiver["ship"].local_contacts[key]={"id":-body["cell_id"]-1,"kind":"anchor",
					"owner":body["data"]["owner"],"pos":Vector3(body["cell"]),"velocity":Vector3.ZERO,"hp":0,
					"t_observed":body["t_observed"],"t_received":s.clock,"epoch":body["epoch"]}
		if receiver.has("ship") and body["type"] == "entity":
			var contact: Dictionary = body["data"].duplicate(true)
			contact["t_observed"] = body["t_observed"]
			contact["t_received"] = s.clock
			contact["epoch"] = body["epoch"]
			if receiver["ship"].local_contacts.get(contact["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
				receiver["ship"].local_contacts[contact["id"]] = contact
		elif receiver.has("asset") and body["type"] == "entity":
			var contact: Dictionary = body["data"].duplicate(true)
			contact.merge({"t_observed":body["t_observed"],"t_received":s.clock,"epoch":body["epoch"]},true)
			if not civ.local_contacts_by_source.has(message["recipient"]):
				civ.local_contacts_by_source[message["recipient"]] = {}
			if civ.local_contacts_by_source[message["recipient"]].get(contact["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
				civ.local_contacts_by_source[message["recipient"]][contact["id"]] = contact
		if message["recipient"] != controller(civ):
			if not receiver.is_empty():
				send(s, owner, receiver["pos"], controller(civ), "report", body)
			return
	body["t_received"] = s.clock
	if body["type"]=="permission":
		var tier: int=body["tier"]
		var proof: Dictionary=civ.pending_permissions.get(tier,{})
		if proof.get("id",-1)==body["ticket"]:
			proof["waiting"].erase(body["source"])
	elif body["type"]=="front":
		var id: int=body["data"]["id"]
		if civ.front_reports.get(id,{}).get("t_observed",-INF)<=body["t_observed"]:
			civ.front_reports[id]=body.duplicate(true)
	elif body["type"]=="broadcast_sent":
		civ.broadcast_reports[body["data"]["id"]]=body["data"].duplicate(true)
	elif body["type"]=="wake":
		var data: Dictionary=body["data"]
		if not civ.wake_reports.has(data["id"]):
			civ.wake_reports[data["id"]]={}
		var ends: Dictionary=civ.wake_reports[data["id"]]
		if ends.get(data["endpoint"],{}).get("t_observed",-INF)<=body["t_observed"]:
			ends[data["endpoint"]]=body.duplicate(true)
	elif body["type"] == "conversion_ready_receipt":
		if civ.conversions.has(body["plan"]):
			var plan: Dictionary=civ.conversions[body["plan"]]
			if not plan.has("ready_reports"):
				plan["ready_reports"]={}
			if plan["ready_at"].get(body["entity"],-INF)<=body["t_observed"]:
				plan["ready_at"][body["entity"]]=body["t_observed"]
				plan["ready_reports"][body["entity"]]={"t_observed":body["t_observed"],"t_received":s.clock,"epoch":body["epoch"]}
	elif body["type"] == "site_destroyed":
		Information.receive_battle(s,owner,body)
	elif body["type"] == "battle_survey":
		var id: int=s.battle_tokens.get(owner,{}).get(body["event_id"],-1)
		if id<0:
			return
		if not civ.battle_surveys.has(id):
			civ.battle_surveys[id]={"t_observed":body["t_observed"],"epoch":body["epoch"],"seen":{},"owners":{}}
		var survey: Dictionary=civ.battle_surveys[id]
		if survey["t_observed"]==body["t_observed"] and survey["epoch"]==body["epoch"]:
			survey["seen"][body["cell_id"]]=true
			survey["owners"][body["local_owner"]]=true
		Information.confirm_battles(s,civ)
	elif body["type"] == "hit":
		civ.times_hit+=1
		civ.hit_dirs.append({"at":body["cell"],"dir":body["direction"],"turn":s.turn,"t_observed":body["t_observed"],"t_received":s.clock})
	elif body["type"] == "broadcast":
		civ.heard[body["target"]] = s.turn
		civ.known[body["target"]] = s.turn
		if body.get("has_exposure",false):
			civ.known[body["exposed"]] = s.turn
		s._discover(civ,"收到广播坐标")
	elif body["type"] == "warning":
		var warning: Dictionary = body["data"].duplicate(true)
		warning.merge({"turn":s.turn,"t_observed":body["t_observed"],"t_received":s.clock,"source_id":body["source_id"],"epoch":body["epoch"]},true)
		civ.alerts = civ.alerts.filter(func(old):return old.get("id",-1)!=warning["id"])
		civ.alerts.append(warning)
	elif body["type"] == "payload":
		var data: Dictionary = body["data"]
		if civ.payload_reports.get(data["id"],{}).get("t_observed",-INF)>body["t_observed"]:
			return
		civ.payload_reports[data["id"]]=body.duplicate(true)
		if data["dead"]:
			civ.foils=civ.foils.filter(func(foil):return foil.id!=data["id"])
		else:
			for foil in civ.foils:
				if foil.id==data["id"]:
					foil.current_position=data["pos"]
					foil.traveled=data["distance"]/s.physical_cell_size()
	elif body["type"] == "order":
		var data: Dictionary = body["data"].duplicate(true)
		data["t_observed"] = body["t_observed"]
		data["t_received"] = s.clock
		if civ.order_reports.get(data["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
			var previous: String=civ.order_reports.get(data["id"],{}).get("status","")
			if previous in ["completed","failed","destroyed","cancelled"]:
				return
			if civ.order_reports.get(data["id"],{}).get("cancel_pending",false):
				data["cancel_pending"]=true
			civ.order_reports[data["id"]] = data
			if data["status"]=="failed":
				var refund: Array=data.get("failure_refund",[0,0])
				civ.energy_millis+=refund[0]
				civ.mineral_millis+=refund[1]
				civ.ledger.append({"t":s.clock,"kind":"failed_order_refund","order":data["id"],"delta":refund.duplicate()})
			if data["status"]=="completed" and previous!="completed":
				if data["category"]=="research":
					civ.techs[data["kind"]]=true
				elif data["category"]=="upgrade" and data["kind"]=="telescope":
					civ.telescope+=1
				elif data["kind"]=="antimatter":
					civ.antimatter+=1
				elif data["kind"]=="dimension_weapon":
					civ.dimension_ammo+=1
				if civ==s.human():
					s.add_log("收到工程完成回报：%s"%Tech.title(data["kind"]) if data["category"]=="research" else "收到建造完成回报：%s"%GameState.BUILD_NAMES.get(data["kind"],data["kind"]))
	elif body["type"] == "command_result":
		civ.energy_millis += body["refund"][0]
		civ.mineral_millis += body["refund"][1]
		civ.antimatter += body.get("ammo_refund",0)
		civ.dimension_ammo += body.get("dimension_refund",0)
		if not body["executed"] and body.get("payload_id",-1)>=0:
			civ.foils=civ.foils.filter(func(f):return f.id!=body["payload_id"])
		if body["request_name"]=="scan":
			civ.scan_ready_at = body["scan_ready_at"] if body["executed"] else s.clock
		civ.command_pending.erase(body["command"])
		civ.command_results.append(body.duplicate(true))
		civ.ledger.append({"t": s.clock, "kind": "command_receipt", "command": body["command"], "delta": body["refund"].duplicate()})
	elif body["type"] == "cell":
		var cell: Vector3i = body["cell"]
		var cell_id: int = body.get("cell_id", s.cell_ids.get(cell, -1))
		if body.get("passive", false):
			if not civ.coverage.has(cell_id):
				civ.coverage[cell_id] = {}
			civ.coverage[cell_id][body["source_id"]] = {"t_observed": body["t_observed"], "t_received": s.clock, "epoch": body["epoch"]}
		var first_discovery := not civ.intel.has(cell) and not Knowledge.owns(s,civ,cell)
		var info: Dictionary = body["data"].duplicate(true)
		info.merge({"t_observed": body["t_observed"], "t_received": s.clock,
				"source_id": body["source_id"], "epoch": body["epoch"]}, true)
		if civ.intel.has(cell) and civ.intel[cell].get("t_observed", -INF) > body["t_observed"]:
			return
		civ.intel[cell] = info
		if first_discovery:
			s._discover(civ, "首次收到未知星系观测")
		if body.get("contact", false):
			civ.contacted = true
		if info["owner"] >= 0 and info["owner"] != owner:
			civ.known[cell] = s.turn
			s._discover(civ, "收到异文明星系观测")
		else:
			civ.known.erase(cell)
	elif body["type"] == "entity":
		var contact: Dictionary = body["data"].duplicate(true)
		contact.merge({"t_observed": body["t_observed"], "t_received": s.clock,
				"source_id": body["source_id"], "epoch": body["epoch"], "turn": s.turn}, true)
		for old in civ.sightings:
			if old.get("id",-1)==contact["id"] and old.get("t_observed",-INF)>body["t_observed"]:
				return
		civ.sightings = civ.sightings.filter(func(old): return old.get("id", -1) != contact["id"])
		civ.sightings.append(contact)
		if body.get("contact",false):
			civ.contacted=true
		if contact["owner"] >= 0 and contact["owner"] != owner:
			s._discover(civ, "收到异文明单位观测")
	elif body["type"] == "own_site":
		var cell: Vector3i=body["data"]["cell"]
		if civ.site_reports.get(cell,{}).get("t_observed",-INF)<=body["t_observed"]:
			civ.site_reports[cell]=body.duplicate(true)
			if civ.intel.get(cell,{}).get("t_observed",-INF)<=body["t_observed"]:
				civ.intel[cell]=body["data"]["snapshot"].duplicate(true)
				civ.intel[cell].merge({"t_observed":body["t_observed"],"t_received":s.clock,"turn":s.turn,"source_id":body["source_id"],"epoch":body["epoch"]},true)
	elif body["type"] == "own":
		var id: int = body["data"]["id"]
		if not civ.telemetry.has(id) or civ.telemetry[id]["t_observed"] <= body["t_observed"]:
			civ.telemetry[id] = body.duplicate(true)
			civ.telemetry[id]["t_received"] = s.clock
	if not civ.battle_reports.is_empty() and body["type"] in ["own","own_site"]:
		Information.query_battles(s,civ)
	_receive_permissions(s,civ)


static func _receive_permissions(s: GameState,civ: Civ) -> void:
	for tier in civ.pending_permissions.keys():
		var proof: Dictionary=civ.pending_permissions[tier]
		for cell in civ.site_reports:
			if not civ.site_reports[cell]["data"].get("owned",true):
				proof["missing_sites"].erase(s.cell_ids.get(cell,-1))
		for id in proof["missing_ships"].duplicate():
			if civ.telemetry.get(id,{}).get("data",{}).get("dead",false):
				proof["missing_ships"].erase(id)
		if proof["waiting"].is_empty() and proof["missing_sites"].is_empty() and proof["missing_ships"].is_empty():
			civ.set_tier_turn(tier,s.turn+1)
			civ.pending_permissions.erase(tier)


static func observers(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for asset in civ.assets:
		if asset["kind"] != "anchor" or civ.dormant_colonies.has(asset["at"]):
			continue
		result.append({"id": asset["id"], "pos": Vector3(asset["at"]), "dir": Vector3.ZERO,
				"radius": (Balance.VISION_HOME if asset["at"] == civ.home else Balance.VISION_COLONY) + civ.vision_bonus(),
				"angle": 0.0, "backward": 0.0})
	for ship in civ.ships:
		if ship.dead or ship.dormant or ship.kind == Ship.GRAIN:
			continue
		var cone := ship.kind in [Ship.PROBE, Ship.NUCLEAR_PROBE, Ship.DROPLET] and ship.direction != Vector3.ZERO
		var base := Balance.VISION_SHIP
		if ship.kind == Ship.SOPHON:
			base = Balance.SOPHON_VISION
		elif ship.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH]:
			base = Balance.VISION_HOME if ship.kind == Ship.WANDERING_EARTH else Balance.VISION_COLONY
		result.append({"id": ship.id, "pos": ship.pos, "dir": ship.direction if cone else Vector3.ZERO,
				"radius": base + civ.vision_bonus(), "angle": Balance.PROBE_ANGLE + civ.telescope * Balance.TELESCOPE_ANGLE_STEP,
				"backward": civ.telescope * Balance.LINE_BACKWARD_PER_LEVEL if s.dimension == 1 else 0.0})
	return result


static func in_view(s: GameState, observer: Dictionary, pos: Vector3) -> bool:
	var d: Vector3 = (pos - observer["pos"]) * s.physical_cell_size()
	var radius: float = observer["radius"]
	if observer["dir"] == Vector3.ZERO:
		return d.length() <= radius + 1e-7
	var forward := d.dot(observer["dir"])
	if s.dimension == 1:
		return forward <= radius and forward >= -radius * observer["backward"]
	return forward >= 0.0 and forward <= radius and (d - observer["dir"] * forward).length() <= forward * tan(deg_to_rad(observer["angle"] * 0.5)) + Balance.COLLISION_EPSILON


static func _emit(s: GameState, owner: int, observer: Dictionary, origin: Vector3, key: String, body: Dictionary, heartbeat: bool) -> void:
	var signature := hash([body["data"],body.get("contact",false)])
	var stamp: Dictionary = s.sensor_stamps.get(key, {})
	if stamp.get("hash", -1) == signature and (not heartbeat or s.clock - stamp.get("time", -INF) < 1.0):
		return
	s.sensor_stamps[key] = {"hash": signature, "time": s.clock}
	body["t_observed"] = s.clock
	body["epoch"] = s.space_epoch
	body["source_id"] = observer["id"]
	send(s, owner, origin, observer["id"], "sensor", body)


static func sample(s: GameState, force := false) -> void:
	if not force and s.clock < s.next_sensor_time - Balance.TIME_EPSILON:
		return
	Information.retry_archives(s)
	# 在固定最大子步网格采样，不能因接收一个消息再无限加密采样而产生零时间事件洪泛。
	s.next_sensor_time = (floorf(s.clock / Balance.PHYSICS_MAX_DT + Balance.TIME_EPSILON) + 1.0) * Balance.PHYSICS_MAX_DT
	var entities := Combat.targets(s, true)
	for civ in s.civs:
		if not civ.alive:
			continue
		var owner := s.civs.find(civ)
		Knowledge.sample(s,civ)
		_sample_warning(s,civ,entities)
		for project in WorldTime.orders(civ):
			var period := 1.0
			if Balance.LOCAL_ORDER_REPORT_CURRENT == 1:
				var source: Dictionary = OrderControl.host(s,civ,project)
				var receiver := entity(s,owner,controller(civ))
				if not source.is_empty() and not receiver.is_empty() and source["pos"].distance_to(receiver["pos"])*s.physical_cell_size()<=Balance.COLLISION_EPSILON:
					# 本地也走报告链路；仅零距离缩短采样间隔，不能把远端施工真值给界面或AI。
					period = maxf(0.0,Balance.PHYSICS_MAX_DT-Balance.TIME_EPSILON)
			if s.clock-project.get("report_time",-INF)>=period:
				project["report_time"] = s.clock
				OrderControl.report(s,civ,project,project.get("status","working"))
		for observer in observers(s, civ):
			for wake in s.deadlines:
				if wake["expires"]<=s.clock:
					continue
				# 两个端点各自走完整的光路；较近的一端不能替远端或被阻断端提供情报。
				for endpoint in 2:
					var pos: Vector3=wake["a"] if endpoint==0 else wake["b"]
					if in_view(s,observer,pos):
						_emit(s,owner,observer,pos,"%d:wake:%d:%d"%[observer["id"],wake["id"],endpoint],
							{"type":"wake","data":{"id":wake["id"],"endpoint":endpoint,"pos":pos,"turn":s.turn}},true)
			for entry in [["foil",s.foil_zones],["line",s.line_zones]]:
				for zone in entry[1]:
					if in_view(s,observer,Vector3(zone["center"])):
						_emit(s,owner,observer,Vector3(zone["center"]),"%d:front:%d"%[observer["id"],zone.get("id",-1)],
							{"type":"front","front_type":entry[0],"data":zone.duplicate(true)},true)
			for cell in s.system_cells:
				if not in_view(s, observer, Vector3(cell)):
					continue
				var data := s.snapshot(cell)
				data["cell_dim"] = s.cell_dims.get(s.cell_ids.get(cell,-1),s.dimension)
				data["turn"] = 0 # 签名只反映事实变化，观测时间另存。
				_emit(s, owner, observer, Vector3(cell), "%d:cell:%d" % [observer["id"], s.cell_ids.get(cell, -1)],
						{"type": "cell", "cell": cell, "cell_id": s.cell_ids.get(cell, -1), "passive": true, "data": data, "contact": data["owner"] >= 0 and data["owner"] != owner and Vector3i(observer["pos"].round()) == cell}, true)
			for target in entities:
				if target["owner"] == owner or not in_view(s, observer, target["pos"]):
					continue
				var data := {"id": target["id"], "owner": target["owner"], "kind": target["kind"],
						"pos": target["pos"], "velocity": target["velocity"], "hp": target["hp"]}
				_emit(s, owner, observer, target["pos"], "%d:entity:%d" % [observer["id"], target["id"]],
					{"type":"entity","data":data,"contact":target["owner"]>=0 and Vector3i(observer["pos"].round())==Vector3i(target["pos"].round())},true)
		for ship in civ.ships:
			var key := "own:%d" % ship.id
			var data := ship_status(ship)
			data["assets"]=civ.assets.filter(func(a):return a["carrier"]==ship.id).duplicate(true)
			var stamp: Dictionary = s.sensor_stamps.get(key, {})
			# 每年一次常规定位回报；死亡等状态变化立即在当地发出，仍须等传回。
			var important := hash([ship.dead, ship.dormant, ship.damage, ship.weapons])
			if s.clock - stamp.get("time", -INF) < 1.0 and stamp.get("hash", -1) == important:
				continue
			s.sensor_stamps[key] = {"time": s.clock, "hash": important}
			send(s, owner, ship.pos, controller(civ), "report", {"type": "own", "data": data,
					"t_observed": s.clock, "source_id": ship.id, "epoch": s.space_epoch})


static func ship_status(ship: Ship) -> Dictionary:
	return {"id": ship.id, "kind": ship.kind, "pos": ship.pos, "direction": ship.direction,
			"speed": ship.speed, "target": ship.target, "has_target": ship.has_target,
			"docked": ship.docked, "dead": ship.dead, "dormant": ship.dormant,
			"lock": ship.lock, "parked": ship.parked, "warp": ship.warp, "gravity": ship.gravity,
			"damage": ship.damage, "modules": ship.modules.duplicate(), "weapons": ship.weapons.duplicate(),
			"entity_dim": ship.entity_dim, "work_locked": ship.work_locked,"weapon_policy":ship.weapon_policy,"carried_rocky":ship.carried_rocky,
			"slow_start":ship.slow_start,"pause_until":ship.pause_until}


static func reported_ships(s: GameState, civ: Civ) -> Array[Ship]:
	var ids: Array = civ.telemetry.keys()
	var control := entity(s, s.civs.find(civ), controller(civ))
	if not control.is_empty():
		for ship in civ.ships:
			if ship.pos.distance_to(control["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON and not ids.has(ship.id):
				ids.append(ship.id)
	ids.sort()
	var result: Array[Ship] = []
	for id in ids:
		var ship := reported_ship(s, civ, id)
		if ship != null:
			result.append(ship)
	return result


## 前端与命令校验使用最后收到的遥测；只在控制锚点原地时可直接读本地实体。
static func reported_ship(s: GameState, civ: Civ, id: int) -> Ship:
	var actual := civ.ship_by_id(id)
	var control := entity(s, s.civs.find(civ), controller(civ))
	if actual != null and not actual.dead and not control.is_empty() and actual.pos.distance_to(control["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON:
		return actual
	if not civ.telemetry.has(id):
		return null
	var status: Dictionary = civ.telemetry[id]["data"]
	if status["dead"]:
		return null
	var reported := Ship.make(status["kind"], status["pos"], id)
	for field in status:
		if field in reported:
			if reported.get(field) is Array:
				reported.get(field).assign(status[field])
			else:
				reported.set(field, status[field])
	return reported


static func report_ship(s: GameState, civ: Civ, ship: Ship) -> void:
	var data:=ship_status(ship)
	data["assets"]=civ.assets.filter(func(a):return a["carrier"]==ship.id).duplicate(true)
	send(s, s.civs.find(civ), ship.pos, controller(civ), "report", {"type": "own", "data": data,
			"t_observed": s.clock, "source_id": ship.id, "epoch": s.space_epoch})


## 收入只认仍在线、仍在视野内且具有可传播链路的接收器；历史报告本身不产能。
static func coverage_packages(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not civ.has_tech("antimatter_collection"):
		return result
	var owner := s.civs.find(civ)
	var control := entity(s, owner, controller(civ))
	if control.is_empty():
		return result
	# 按原星系顺序一次分桶。每个观察者仍按相同顺序处理自己的已收覆盖，
	# 不为每个观察者重新扫描全图并为未覆盖格分配空字典。
	var by_source:= {}
	for cell in s.system_cells:
		var id: int=s.cell_ids.get(cell,-1)
		if s.cell_dims.get(id,s.dimension)==0 or not civ.coverage.has(id): continue
		for source in civ.coverage[id]:
			if not by_source.has(source): by_source[source]=[]
			by_source[source].append([cell,id])
	for observer in observers(s, civ):
		var receiver := entity(s, owner, observer["id"])
		if not path_open(s, observer["pos"], control["pos"]):
			continue
		var dim: int = receiver["ship"].entity_dim if receiver.has("ship") else receiver["asset"]["entity_dim"]
		var parent: String = "ship:%d" % observer["id"] if receiver.has("ship") else Economy.package_key("anchor", receiver["asset"]["at"])
		for pair in by_source.get(observer["id"],[]):
			var cell: Vector3i=pair[0]
			var id: int=pair[1]
			if not in_view(s, observer, Vector3(cell)) or not path_open(s, Vector3(cell), observer["pos"]):
				continue
			var e: float = Balance.COVERED_ENERGY + (Balance.VACUUM_ENERGY if civ.has_tech("dark_energy") and s.map.star_at(cell) == StarMap.Star.NONE else 0)
			result.append({"key": "coverage:%d:%d" % [id,observer["id"]], "kind": "coverage", "at": cell,
					"coverage_cell": id, "nominal": [e,0.0], "q": Balance.DIMENSION_OUTPUT[str(dim)], "upkeep": [0.0,0.0], "parent": parent})
	return result


static func path_open(s: GameState, a: Vector3, b: Vector3) -> bool:
	# 没有任何修改光速的场或网格时，两端必为正光速，避免逐覆盖点重复构造场查询。
	if s.light.is_empty() and s.black_domains.is_empty() and s.deadlines.is_empty(): return true
	if s.relative_light(a) <= 0.0 or s.relative_light(b) <= 0.0:
		return false
	for source in s.black_domains:
		var closest := a
		var d := b-a
		if d.length_squared() > 1e-15:
			closest += d * clampf((source["pos"]-a).dot(d)/d.length_squared(),0.0,1.0)
		if s.relative_light(closest) <= 0.0:
			return false
	return true


static func _sample_warning(s: GameState, civ: Civ, targets: Array[Dictionary]) -> void:
	for asset in civ.assets:
		if asset["kind"] != "warning":
			continue
		if (asset["carrier"] < 0 and civ.dormant_colonies.has(asset["at"])) or (asset["carrier"] >= 0 and civ.ship_by_id(asset["carrier"]).dormant):
			continue
		var observer := {"id":asset["id"],"pos":entity(s,s.civs.find(civ),asset["id"])["pos"]}
		var radius: float = Balance.WARNING_RANGE+asset.get("warning_level",civ.warnings.get(asset["at"],0))
		for target in targets:
			if target["owner"] == s.civs.find(civ) or target["kind"] not in [Ship.WARSHIP,Ship.DROPLET,Ship.GRAIN,"payload"]:
				continue
			if observer["pos"].distance_to(target["pos"])*s.physical_cell_size()>radius:
				continue
			var data := {"id":target["id"],"kind":target["kind"],"pos":target["pos"],"velocity":target["velocity"]}
			if target.has("payload"):
				data["payload_kind"] = target["payload"]["kind"]
			_emit(s,s.civs.find(civ),observer,target["pos"],"warning:%d:%d"%[asset["id"],target["id"]],{"type":"warning","data":data},true)
