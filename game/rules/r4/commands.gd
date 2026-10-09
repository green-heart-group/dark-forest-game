class_name R4Commands
extends RefCounted
## 命令送达后的真实合法性与效果；发令已花AP，远方失败不会倒退回发令时刻。

static func execute(s, msg: Dictionary) -> void:
	var ci: int = msg.owner
	var request: Dictionary = msg.payload.command
	var e: Dictionary = s.entities.get(msg.target_id,{})
	var ledger = s.civs[ci].ledger
	if not s.civs[ci].alive or not e.get("alive",false) or e.owner!=ci:
		ledger.release_shot(msg.reservation)
		s.log_event("command_failed",ci,{"message":msg.id,"reason":"source_unavailable_on_arrival"})
		return
	var target: Vector3 = request.get("target",e.pos+request.get("direction",Vector3.RIGHT)*s.config.physics.scan.length)
	if request.has("target_cell"): target=s.space.position_for(request.target_cell)
	var kind: String = request.kind
	if kind=="broadcast" and not s.broadcast_capable(ci,e,false):
		ledger.release_shot(msg.reservation)
		s.log_event("command_failed",ci,{"message":msg.id,"reason":"broadcast_source_unavailable_on_arrival"})
		return
	if kind=="broadcast" and blocked(s,e):
		ledger.release_shot(msg.reservation)
		s.log_event("broadcast_blocked",ci,{"source":e.id})
		return
	var required: Vector2i = msg.payload.get("required_cost",Vector2i.ZERO)
	var held: Vector2i = ledger.shots.get(msg.reservation,Vector2i.ZERO)
	var missing: Vector2i = required-held
	if not ledger.can_pay(missing):
		ledger.release_shot(msg.reservation)
		s.log_event("command_failed",ci,{"message":msg.id,"reason":"conversion_depleted_command_reservation"})
		return
	if missing!=Vector2i.ZERO: ledger.debit(missing,"command_reservation_topup")
	if msg.reservation!="": ledger.fire_shot(msg.reservation)
	if kind=="operation":
		s.invalidate_income(ci)
		e.forced_dormant=request.get("dormant",false)
		e.priority=int(request.get("priority",e.priority))
		if e.forced_dormant: e.online=false
	elif kind=="emergency":
		var gain := R4Ledger.amount(s.config.q(e.dim) if request.resource=="M" else 0.0,s.config.q(e.dim) if request.resource=="E" else 0.0)
		ledger.credit(gain,"emergency")
		s.log_event("emergency_yield",ci,{"amount":gain,"host":e.id})
	if kind=="move":
		if not e.online: return
		var moving_ids: Array = [e.id]
		for child in s.owned_entities(ci):
			if child.host==e.id and child.attached: moving_ids.append(child.id)
		s.flush_scheduled_messages(s.now,moving_ids)
		e.target=target
		e.target_cell=request.get("target_cell",s.space.cell_at(target))
		e.target_id=request.get("target_id",-1)
		e.direction=(target-e.pos).normalized()
		if request.has("direction"): e.direction=request.direction.normalized()
		e.moving=e.direction!=Vector3.ZERO
		# 转向不补回已耗尽的加速时间，也不归零已有速度。
		if e.kind=="probe_basic": e.speed=s.config.physics.motion.probe_basic[3]
		s.log_event("unit_dispatched",ci,{"entity":e.id,"item":e.kind,"source_pos":e.pos,"direction":e.direction})
		s.first_use(ci,R4Config.BUILD_TECH.get(e.kind,"015"),"deployment",e.id)
	elif kind=="convert":
		var preparation: Dictionary = e.ready.get(str(e.dim),{})
		s.convert_entity(e.id,s.now)
		if request.get("group",true) and preparation.has("project"):
			for other in s.owned_entities(ci):
				if other.id==e.id or other.ready.get(str(other.dim),{}).get("project",-1)!=preparation.project: continue
				s.send_message(ci,"command",e.pos,other.id,{"command":{"kind":"convert","host":other.id,"group":false}})
	elif kind=="broadcast":
		var rays := {}
		for cell in s.space.cells:
			rays[cell.id]={"pos":e.pos,"traveled":0.0,"arrived":false}
		s.broadcasts.append({"id":s.next_id(ci),"owner":ci,"source":e.id,"born":s.now,"epoch":s.space.world_epoch,"target":target,
			"target_cell":request.get("target_cell",s.space.cell_at(target)),"rays":rays,"received":{},"visited":{},"earliest":s.now+s.config.physics.event_epsilon})
		s.first_use(ci,"108" if s.civs[ci].techs.has("108") else "006","broadcast_emitted",e.id)
	elif kind=="scan":
		s.civs[ci].scan_ready=s.now+s.config.physics.scan.cooldown
		s.scans.append({"id":s.next_id(ci),"owner":ci,"source":e.id,"pos":e.pos,"origin":e.pos,"direction":(target-e.pos).normalized(),
			"traveled":0.0,"born":s.now,"seen":{},"remaining":s.config.physics.scan.length})
	elif kind=="domain":
		spawn_payload(s,e,"domain_payload",target,s.config.physics.domain.payload_c_fraction,s.config.physics.domain.activation_delay)
	elif kind in ["launch","bomb"]:
		var ammo: Dictionary = s.entities.get(request.get("ammunition",-1),{})
		if not ammo.get("alive",false) or ammo.owner!=ci or ammo.spent: return
		ammo.spent=true
		ammo.alive=false
		if ammo.kind=="antimatter_bomb":
			R4Combat.spawn_shot(s,e,"107",target,request.get("target_id",-1))
		elif ammo.kind=="photoid":
			spawn_payload(s,e,"photoid",target,s.config.physics.photoid_c_fraction,-1.0)
		else:
			if ammo.payload_dim!=s.space.world_dim: return
			spawn_payload(s,e,"dimensional_weapon",target,s.config.physics.dimension_payload_c_fraction,s.config.physics.dimension_payload_delay)

static func spawn_payload(s, source: Dictionary, kind: String, target: Vector3, fraction: float, delay: float) -> Dictionary:
	var direction: Vector3 = (target-source.pos).normalized()
	if direction==Vector3.ZERO: direction=Vector3.RIGHT
	var p := {"id":s.next_id(source.owner),"owner":source.owner,"source":source.id,"kind":kind,"pos":source.pos,"target":target,
		"direction":direction,"c_fraction":fraction,"speed":0.0,"born":s.now,"traveled":0.0,"delay":delay,
		"arrived":false,"activate_at":INF,"alive":true,"hp":s.config.physics.hp.get(kind,INF),"damage":0.0,
		"payload_dim":s.space.world_dim,"earliest":s.now+s.config.physics.event_epsilon,"remaining":INF}
	s.projectiles.append(p)
	s.log_event("payload_launched",source.owner,{"projectile":p.id,"kind":kind,"world_dim":s.space.world_dim,"source":source.id})
	return p

static func blocked(s, source: Dictionary) -> bool:
	for e in s.entities.values():
		if e.alive and e.online and e.kind=="droplet" and e.owner!=source.owner and e.cell==source.cell and not e.moving:
			return true
	return false
