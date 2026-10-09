class_name R4Intel
extends RefCounted
## 真值仅供传感器采样和物理碰撞。文明/AI收到的历史保留观测时刻及epoch。
## 远方报告、预警和扫描回波必须经过消息推进器才能进入文明视图。

static func radius(s, e: Dictionary) -> float:
	var p: Dictionary = s.config.physics.vision
	var base: float = p.ship
	if e.kind=="home" or e.original_home: base=p.home
	elif e.kind=="colony": base=p.colony
	elif e.kind=="sophon": base=p.sophon
	return base+s.civs[e.owner].radio*p.radio_step

static func in_sensor(s, observer: Dictionary, point: Vector3) -> bool:
	var delta: Vector3 = point-observer.pos
	var r := radius(s,observer)
	if delta.length()>r: return false
	if observer.kind not in ["probe_basic","probe_nuclear","droplet"]: return true
	if delta.length_squared()<1e-12: return true
	var direction: Vector3 = observer.direction
	if direction==Vector3.ZERO: direction=Vector3.RIGHT
	if s.space.world_dim==1:
		return delta.dot(direction)>=0.0 or delta.length()<=r*0.25*s.civs[observer.owner].radio
	var full_angle: float = s.config.physics.vision.probe_cone_deg+s.civs[observer.owner].radio*s.config.physics.vision.cone_step_deg
	return direction.dot(delta.normalized())>=cos(deg_to_rad(full_angle*0.5))

static func observe(s) -> void:
	var ordered_entities: Array = s.entities.values()
	ordered_entities.sort_custom(func(a,b):return a.id<b.id)
	for observer in ordered_entities:
		if not observer.alive or not observer.online: continue
		if observer.kind not in R4Config.ANCHORS and observer.kind not in R4Config.MOBILE: continue
		var ci: int = observer.owner
		if not s.civs[ci].alive: continue
		var receiver: Dictionary = s.command_anchor(ci)
		if receiver.is_empty(): continue
		# 光先从被观测点到传感器，再由传感器向指挥锚点回报。
		# 不能把“在几何视野内”当作该时刻的瞬时真值。
		for cell in s.space.cells:
			if not in_sensor(s,observer,s.space.position_for(cell.id)): continue
			var record: Dictionary = cell.duplicate(true)
			record["pos"]=s.space.position_for(cell.id)
			record["t_observed"]=s.now
			record["epoch"]=s.space.world_epoch
			s.send_message(ci,"sensor_photon",record.pos,observer.id,{"cells":[record],"entities":[],"t_observed":s.now,"source":observer.id,
				"contacted_enemy":cell.owner>=0 and cell.owner!=ci and observer.cell==cell.id})
		for e in ordered_entities+s.projectiles:
			if not in_sensor(s,observer,e.pos): continue
			var record: Dictionary = e.duplicate(false)
			record.erase("tactical")
			record.erase("local_seen")
			record["cell"]=s.space.cell_at(e.pos)
			record["dim"]=s.space.cell_dimension(e.pos)
			if e.has("dim"): record.dim=e.dim
			record["t_observed"]=s.now
			record["epoch"]=s.space.world_epoch
			# 未经侦察不能读取敌方库存、选装、预备名册或命令目标。
			if e.owner!=ci:
				for private_field in ["paid_basis","ready","receipts","occupation","target_id","target_cell","target","modules"]:
					record.erase(private_field)
			s.send_message(ci,"sensor_photon",e.pos,observer.id,{"cells":[],"entities":[record],"t_observed":s.now,"source":observer.id,
				"contacted_enemy":e.alive and e.owner!=ci and observer.cell==record.cell})
		warn(s,observer,receiver.id)

static func apply_report(s, ci: int, payload: Dictionary) -> void:
	var c: Dictionary = s.civs[ci]
	if payload.get("contacted_enemy",false): c.event_flags["own_unit_contacted_other_entity_in_same_system"]=true
	for cell in payload.get("cells",[]):
		var old: Dictionary = c.known_cells.get(cell.id,{})
		if old.get("t_observed",-INF)>cell.t_observed: continue
		if old.is_empty() and cell.was_system and cell.owner!=ci:
			c.event_flags["discovered_unknown_entity"]=true
			if not c.first.has("discovery"):
				c.first.discovery=s.now
				s.log_event("first_discovery",ci,{"cell":cell.id,"t_observed":cell.t_observed})
		c.known_cells[cell.id]=cell.duplicate(true)
		var old_coverage: Dictionary = c.coverage.get(cell.id,{})
		if old_coverage.get("expires",-1)<=s.now or old_coverage.get("stars",-1)!=cell.stars or old_coverage.get("dim",-1)!=cell.dim or old_coverage.get("was_system",false)!=cell.was_system:
			s.invalidate_income(ci)
		# 每次真正收到一次新覆盖报告，授予一个观察周期；不复用永久记忆持续供能。
		c.coverage[cell.id]={"stars":cell.stars,"dim":cell.dim,"was_system":cell.was_system,"expires":s.now+1.0,"t_observed":cell.t_observed,"source":payload.source}
	for e in payload.get("entities",[]):
		if c.seen.get(e.id,{}).get("t_observed",-INF)<=e.t_observed: c.seen[e.id]=e.duplicate(true)
	s.unlock_permissions(ci)
	s.log_event("report_received",ci,{"source":payload.get("source",-1),"t_observed":payload.t_observed,"cells":payload.get("cells",[]).size(),"entities":payload.get("entities",[]).size()})

static func warn(s, observer: Dictionary, receiver: int) -> void:
	if observer.kind not in R4Config.ANCHORS: return
	var has_warning := false
	for e in s.owned_entities(observer.owner,"warning"):
		if e.cell==observer.cell and e.online: has_warning=true
	if not has_warning: return
	var r: float = s.config.physics.warning.radius+s.civs[observer.owner].warning_level*s.config.physics.warning.radius_step
	var threats: Array = s.projectiles.duplicate()
	for e in s.entities.values():
		if e.alive and e.kind=="battleship": threats.append(e)
	for threat in threats:
		if threat.owner==observer.owner: continue
		var position: Vector3 = threat.pos
		if observer.pos.distance_to(position)>r: continue
		var direction: Vector3 = threat.get("direction",Vector3.ZERO)
		if direction==Vector3.ZERO: continue
		if (observer.pos-position).dot(direction)<0.0: continue
		if R4Space.point_segment_distance(observer.pos,position,position+direction*r*2.0)>maxf(0.25,s.config.spacing(s.space.world_dim)): continue
		var alert := {"threat_id":threat.id,"kind":threat.kind,"pos":position,"direction":direction,
			"speed_observed":threat.get("speed",0.0),"t_observed":s.now,"epoch":s.space.world_epoch,"anchor":observer.id}
		s.send_message(observer.owner,"warning_photon",position,observer.id,alert)

static func deliver(s, msg: Dictionary) -> void:
	var ci: int = msg.owner
	if ci<0 or ci>=s.civs.size(): return
	var c: Dictionary = s.civs[ci]
	if msg.kind=="sensor_photon":
		var observer: Dictionary = s.entities.get(msg.target_id,{})
		if not observer.get("alive",false): return
		if not observer.has("local_seen"): observer["local_seen"]={}
		for e in msg.payload.get("entities",[]):
			if observer.local_seen.get(e.id,{}).get("t_observed",-INF)<=e.t_observed: observer.local_seen[e.id]=e
		var receiver: Dictionary = s.command_anchor(ci)
		if receiver.is_empty(): return
		if observer.id==receiver.id: apply_report(s,ci,msg.payload)
		else: s.send_message(ci,"sensor_report",observer.pos,receiver.id,msg.payload)
	elif msg.kind=="warning_photon":
		var observer: Dictionary = s.entities.get(msg.target_id,{})
		var receiver: Dictionary = s.command_anchor(ci)
		if not observer.get("alive",false) or receiver.is_empty(): return
		if observer.id==receiver.id:
			var local := msg.duplicate(false); local.kind="warning"
			deliver(s,local)
		else: s.send_message(ci,"warning",observer.pos,receiver.id,msg.payload)
	elif msg.kind=="sensor_report": apply_report(s,ci,msg.payload)
	elif msg.kind=="own_entity":
		var e: Dictionary = msg.payload.entity.duplicate(true)
		e["t_observed"]=msg.payload.t_observed
		e["epoch"]=msg.epoch
		if c.seen.get(e.id,{}).get("t_observed",-INF)<=e.t_observed: c.seen[e.id]=e
	elif msg.kind=="warning":
		var alert: Dictionary = msg.payload
		var first: bool = not c.alerts.has(alert.threat_id)
		c.alerts[alert.threat_id]=alert.duplicate(true)
		if first:
			s.log_event("warning_received",ci,{"threat":alert.threat_id,"anchor":alert.anchor,"t_observed":alert.t_observed,
				"pos_observed":alert.pos,"speed_observed":alert.speed_observed,"stock":c.ledger.stock})
	elif msg.kind=="adapt_ready":
		var e: Dictionary = s.entities.get(msg.target_id,{})
		if e.get("alive",false):
			var p: Dictionary = msg.payload.prepared.duplicate(true)
			p["received_at"]=s.now
			e.ready[str(p.from_dim)]=p
			s.log_event("entity_adaptation_ready",ci,{"entity":e.id,"from_dim":p.from_dim,"prepared_at":p.prepared_at})
	elif msg.kind=="project_order":
		var id: int = msg.payload.project
		if c.ledger.projects.has(id):
			c.ledger.projects[id].metadata.arrived=true
			c.ledger.projects[id].metadata["arrived_at"]=s.now
	elif msg.kind=="scan_echo":
		apply_report(s,ci,{"cells":[msg.payload.cell],"entities":[],"t_observed":msg.payload.t_observed,"source":msg.payload.source})
		s.first_use(ci,"103","scan_echo",msg.payload.source)
