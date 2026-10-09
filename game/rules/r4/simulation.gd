class_name R4Simulation
extends RefCounted
## 连续时间按事件/有限子步推进。相对线段扫掠求首次接触；加速弧的误差和收敛由测试记录。
const Intel := preload("res://rules/r4/intel.gd")
const Combat := preload("res://rules/r4/combat.gd")
const Commands := preload("res://rules/r4/commands.gd")

static func advance(s, duration: float) -> void:
	var end_time: float = s.now+duration
	var iterations := 0
	var phases: Array = [0,0,0,0,0]
	s.space.use_uniform_cache=not s.plain_checks
	s.space.refresh_uniform_cache()
	while s.now<end_time-1e-10 and s.terminal_reason=="":
		var clock := Time.get_ticks_usec()
		iterations+=1
		assert(iterations<100000,"event loop failed to make positive time progress")
		var dt: float = minf(s.config.physics.physics_max_dt,end_time-s.now)
		s.space.advance_domains(s.now)
		var info_owners := batchable_information_owners(s)
		dt=minf(dt,next_event_delta(s,dt,info_owners))
		if iterations==10000:
			print("R4_STEP_DIAGNOSTIC ",JSON.stringify({"round":s.round_index,"now":s.now,"dt":dt,"messages":s.messages.size(),"projects":s.civs.map(func(c):return c.ledger.projects.values())}))
		assert(iterations<30000,"excessive event subdivisions; preserve diagnostic and stop this probe")
		phases[0]+=Time.get_ticks_usec()-clock
		clock=Time.get_ticks_usec()
		refresh_tactical(s)
		Combat.fire_available(s)
		var paths := predict(s,dt)
		var contacts := find_contacts(s,paths,dt)
		var fraction := 1.0
		for hit in contacts: fraction=minf(fraction,hit.fraction)
		if fraction<1.0-1e-9:
			# Commit the computed earliest event. Re-testing a float32 endpoint
			# can miss the touching pair and create an endless epsilon approach.
			contacts=contacts.filter(func(hit):return hit.fraction<=fraction+1e-7)
			dt=maxf(s.config.physics.event_epsilon,dt*fraction)
			paths=predict(s,dt)
		phases[1]+=Time.get_ticks_usec()-clock
		clock=Time.get_ticks_usec()
		# 此段已存活时间的实际产出和维护原子记账，先于段末死亡。
		var interval_start: float = s.now
		var information := drain_information(s,s.now+dt,info_owners,paths)
		var settled: Dictionary = information.settled
		for ci in s.civs.size():
			if s.civs[ci].alive: settle_finance_interval(s,ci,settled.get(ci,interval_start),interval_start+dt)
		s.now=interval_start
		phases[2]+=Time.get_ticks_usec()-clock
		clock=Time.get_ticks_usec()
		var new_wakes := move_paths(s,paths,dt)
		move_messages(s,dt,information.advanced)
		move_broadcasts_and_scans(s,dt)
		phases[3]+=Time.get_ticks_usec()-clock
		clock=Time.get_ticks_usec()
		s.now+=dt
		if not new_wakes.is_empty():
			s.flush_scheduled_messages()
			s.space.wakes.append_array(new_wakes)
		resolve_contacts(s,contacts)
		apply_space_contacts(s)
		activate_payloads(s)
		apply_space_contacts(s)
		deliver_messages(s)
		s.progress_projects(dt,s.now-dt) # 与前沿同刻完成不算提前准备，送达前不施工。
		periodic_systems(s,dt)
		if s.space.transition_complete(): remap_world(s)
		s.check_terminal()
		cleanup(s)
		phases[4]+=Time.get_ticks_usec()-clock
	s.last_physics_substeps=iterations
	s.last_physics_profile=phases
	s.space.use_uniform_cache=false

static func batchable_information_owners(s) -> Dictionary:
	var result := {}
	if s.space.uniform_dimension!=s.space.world_dim or not s.space.domains.is_empty() or not s.space.wakes.is_empty(): return result
	for c in s.civs:
		var upkeep := Vector2.ZERO
		var stable: bool = c.alive
		for e in s.owned_entities(c.id):
			if not e.online or (e.kind in R4Config.ANCHORS and e.moving): stable=false; break
			var row: Dictionary = s.config.economy.units.get(e.kind,{})
			upkeep+=Vector2(row.get("upkeep_M",0),row.get("upkeep_E",0))
		if stable and c.ledger.stock.x>=upkeep.x*1000.0 and c.ledger.stock.y>=upkeep.y*1000.0: result[c.id]=true
	return result

static func information_only(s, msg: Dictionary, owners: Dictionary) -> bool:
	if not owners.has(msg.owner): return false
	var target: Dictionary = s.entities.get(msg.target_id,{})
	if not target.get("alive",false): return false
	if not s.passive_message(msg) and not (msg.kind=="sensor_photon" and target.kind=="battleship" and s.no_automatic_fire_left(target)): return false
	return not target.get("moving",false) or (target.kind in ["probe_basic","probe_nuclear","devourer","transport","battleship"] and not target.modules.has("205"))

## Static reports change knowledge and income, not trajectories or work rates
## while the owner can fund every operating package. Deliver at their exact
## times inside the kinematic segment instead of rebuilding every trajectory.
static func drain_information(s, until: float, owners: Dictionary, paths: Dictionary) -> Dictionary:
	var began: float = s.now
	var settled := {}
	var advanced := {}
	var arrivals: Array = []
	var duration := until-began
	for msg in s.messages:
		if not information_only(s,msg,owners) or not paths.has(msg.target_id): continue
		var path: Dictionary = paths[msg.target_id]
		var speed: float = s.config.c(s.space.world_dim)
		var elapsed := information_intercept(msg.pos,path,speed,duration)
		if elapsed>=0.0 and maxf(began+elapsed,msg.earliest)<=until:
			elapsed=maxf(elapsed,msg.earliest-began)
			arrivals.append({"at":began+elapsed,"message":msg,"position":R4Space.path_position(path,elapsed)})
		else:
			var delta: Vector3 = path.to-msg.pos
			var distance: float = minf(delta.length(),speed*duration)
			msg.pos=path.to if distance>=delta.length()-0.000002 else msg.pos+delta.normalized()*distance
			msg.traveled+=distance
		advanced[msg.id]=true
	arrivals.sort_custom(func(a,b):return a.message.id<b.message.id if a.at==b.at else a.at<b.at)
	var index := 0
	var delivered := {}
	while true:
		var scheduled_at := INF
		if not s.scheduled_messages.is_empty() and information_only(s,s.scheduled_messages[0],owners): scheduled_at=s.scheduled_messages[0].flight.arrival
		var moving_at: float = arrivals[index].at if index<arrivals.size() else INF
		if minf(scheduled_at,moving_at)>=until-1e-10: break
		var from_dynamic: bool = moving_at<scheduled_at
		if moving_at==scheduled_at and index<arrivals.size(): from_dynamic=arrivals[index].message.id<s.scheduled_messages[0].id
		var msg: Dictionary = arrivals[index].message if from_dynamic else s.scheduled_messages[0]
		var arrived: float = maxf(began,moving_at if from_dynamic else scheduled_at)
		var changes_income := message_changes_income(s,msg,arrived)
		if changes_income:
			settle_finance_interval(s,msg.owner,settled.get(msg.owner,began),arrived)
			settled[msg.owner]=arrived
		s.now=arrived
		var receiver: Dictionary = s.entities[msg.target_id]
		var previous_position: Vector3 = receiver.pos
		if from_dynamic:
			receiver.pos=arrivals[index].position
			msg.traveled+=msg.pos.distance_to(receiver.pos)
			msg.pos=receiver.pos
			delivered[msg.id]=true
			index+=1
		else:
			msg=s.pop_scheduled()
			msg.pos=receiver.pos
			msg.traveled=msg.flight.distance
			msg.erase("flight")
		Intel.deliver(s,msg)
		if changes_income: s.reference_and_income(msg.owner,0.0,true)
		receiver.pos=previous_position
	# An arrival at the exact segment boundary is committed by the ordinary
	# delivery phase, after same-time physical contacts have been resolved.
	for i in range(index,arrivals.size()):
		var item: Dictionary = arrivals[i]
		item.message.traveled+=item.message.pos.distance_to(item.position)
		item.message.pos=item.position
	s.messages=s.messages.filter(func(msg):return not delivered.has(msg.id))
	s.now=began
	return {"settled":settled,"advanced":advanced}

static func message_changes_income(s, msg: Dictionary, at: float) -> bool:
	var c: Dictionary = s.civs[msg.owner]
	if not c.techs.has("102"): return false
	if msg.kind=="sensor_photon" and msg.target_id!=s.command_anchor(msg.owner).get("id",-1): return false
	if msg.kind not in ["sensor_photon","sensor_report"]: return false
	for cell in msg.payload.get("cells",[]):
		var old: Dictionary = c.coverage.get(cell.id,{})
		if not cell.was_system and not old.get("was_system",false): continue
		if old.get("expires",-INF)<at or old.get("stars",-1)!=cell.stars or old.get("dim",-1)!=cell.dim or old.get("was_system",false)!=cell.was_system: return true
	return false

static func information_intercept(origin: Vector3, path: Dictionary, speed: float, duration: float) -> float:
	# Receiver speed is bounded by c, so distance(receiver(t), origin)-c*t
	# is monotone. Bisection includes acceleration without a future observation.
	if path.from.distance_to(origin)<=0.000002: return 0.0
	if R4Space.path_position(path,duration).distance_to(origin)>speed*duration+0.000002: return -1.0
	var lo := 0.0
	var hi := duration
	for _i in 36:
		var mid := (lo+hi)*0.5
		if R4Space.path_position(path,mid).distance_to(origin)>speed*mid: lo=mid
		else: hi=mid
	return hi

static func settle_finance_interval(s, ci: int, start: float, finish: float) -> void:
	var cursor := start
	while cursor<finish-1e-12:
		var boundary := finish
		if s.civs[ci].techs.has("102"):
			for coverage in s.civs[ci].coverage.values():
				if coverage.expires>cursor+1e-12: boundary=minf(boundary,coverage.expires)
		s.now=cursor
		s.reference_and_income(ci,boundary-cursor,true)
		cursor=boundary

static func next_event_delta(s, maximum: float, info_owners: Dictionary = {}) -> float:
	var next := maximum
	for group in s.scheduled_deadlines:
		var heap: Array = s.scheduled_deadlines[group]
		if heap.is_empty(): continue
		var required: bool = group=="critical"
		if group.begins_with("info:"): required=not info_owners.has(int(group.trim_prefix("info:")))
		elif group.begins_with("combat:"):
			var receiver: Dictionary = s.entities.get(int(group.trim_prefix("combat:")),{})
			required=not info_owners.has(receiver.get("owner",-1)) or not s.no_automatic_fire_left(receiver)
		if required:
			next=minf(next,maxf(s.config.physics.event_epsilon,heap[0].arrival-s.now))
	var front_time: float = s.space.next_front_time(s.now)
	if is_finite(front_time): next=minf(next,maxf(s.config.physics.event_epsilon,front_time-s.now))
	for source in s.space.domains:
		if source.expires>s.now: next=minf(next,source.expires-s.now)
	for message in s.messages:
		if information_only(s,message,info_owners): continue
		var target: Dictionary = s.entities.get(message.target_id,{})
		if not target.get("alive",false): continue
		var speed: float = s.space.effective_c(message.pos,s.now)
		if speed>0.0 and message.pos.distance_to(target.pos)>0.000002:
			var velocity: Vector3 = target.direction*target.speed if target.get("moving",false) else Vector3.ZERO
			var eta := intercept_time(target.pos-message.pos,velocity,speed)
			if eta>1e-10: next=minf(next,maxf(eta,message.earliest-s.now))
		elif message.pos.distance_to(target.pos)<=0.000002 and message.earliest>s.now:
			next=minf(next,message.earliest-s.now)
	for p in s.projectiles:
		if p.get("arrived",false) and p.activate_at>s.now: next=minf(next,p.activate_at-s.now)
	for c in s.civs:
		var hosts := {}
		for p in c.ledger.projects.values():
			if not p.metadata.arrived or not s.entities.has(p.host) or not s.entities[p.host].alive: continue
			if p.metadata.kind!="research" and hosts.has(p.host): continue
			if p.metadata.kind!="research": hosts[p.host]=true
			var rate: float = s.project_rate(p)
			if rate<=0.0: continue
			var eta: float = (p.work-p.done)/rate
			if eta>1e-10: next=minf(next,eta)
	return maxf(s.config.physics.event_epsilon,next)

static func intercept_time(relative: Vector3, velocity: Vector3, speed: float) -> float:
	var a := velocity.length_squared()-speed*speed
	var b := 2.0*relative.dot(velocity)
	var c := relative.length_squared()
	if c<1e-16: return 0.0
	if absf(a)<1e-12: return -c/b if b<0.0 else INF
	var disc := b*b-4.0*a*c
	if disc<0.0: return INF
	var first := (-b-sqrt(disc))/(2.0*a)
	var second := (-b+sqrt(disc))/(2.0*a)
	if first>0.0 and second>0.0: return minf(first,second)
	return maxf(first,second) if maxf(first,second)>0.0 else INF

static func refresh_tactical(s) -> void:
	for observer in s.entities.values():
		if not observer.alive or not observer.online or observer.kind!="battleship": continue
		var known := {}
		for target in observer.get("local_seen",{}).values():
			if not target.get("alive",false) or target.owner==observer.owner: continue
			var record: Dictionary = target.duplicate(false)
			record.pos=s.observation_position(target)
			known[target.id]=record
		observer["tactical"]=known

static func warp_allowed(s, e: Dictionary) -> bool:
	if not e.modules.has("205") or e.kind not in R4Config.WARP_HULLS: return false
	for anchor in s.anchors(e.owner):
		if anchor.kind in ["home","colony"] and e.pos.distance_to(anchor.pos)<=Intel.radius(s,anchor): return false
	return true

static func motion(s, e: Dictionary, dt: float) -> Dictionary:
	var result := {"from":e.pos,"to":e.pos,"speed":e.speed,"accel":0.0,"warp":false,"velocity":Vector3.ZERO,"acceleration":Vector3.ZERO,"accelerating":0.0}
	if not e.moving or not e.online or s.now<e.paused_until or not s.config.physics.motion.has(e.kind): return result
	var params: Array = s.config.physics.motion[e.kind]
	var acceleration: float = params[0]
	var cap: float = params[1]
	var burn: float = dt if params[2]<0 else minf(dt,maxf(0.0,params[2]-e.accel_used))
	if e.kind=="sophon": cap*=s.space.effective_c(e.pos,s.now,e.dim)
	if warp_allowed(s,e):
		acceleration=s.config.physics.warp_acceleration
		cap=s.space.effective_c(e.pos,s.now,e.dim)
		burn=dt
		result.warp=true
	cap=minf(cap,s.space.effective_c(e.pos,s.now,e.dim))
	var v0: float = minf(e.speed,cap)
	var accelerating: float = minf(burn,maxf(0.0,(cap-v0)/acceleration)) if acceleration>0.0 else 0.0
	var v1: float = minf(cap,v0+acceleration*accelerating)
	var distance: float = v0*accelerating+0.5*acceleration*accelerating*accelerating+v1*(dt-accelerating)
	result.to=e.pos+e.direction*distance
	result.velocity=e.direction*v0
	result.acceleration=e.direction*acceleration
	result.accelerating=accelerating
	result.speed=v1
	result.accel=0.0 if result.warp else burn
	return result

static func predict(s, dt: float) -> Dictionary:
	var paths := {}
	for e in s.entities.values():
		if e.alive: paths[e.id]=motion(s,e,dt)
	for e in s.entities.values():
		if e.alive and e.attached and s.entities.has(e.host) and s.entities[e.host].kind=="wandering_earth" and paths.has(e.host):
			paths[e.id]=paths[e.host].duplicate()
			paths[e.id].from=e.pos
			paths[e.id].warp=false
	for p in s.projectiles:
		if not p.alive: continue
		var speed: float = s.space.effective_c(p.pos,s.now)*p.c_fraction
		var distance: float = minf(speed*dt,p.remaining)
		if p.get("arrived",false): distance=0.0
		if p.kind in ["dimensional_weapon","domain_payload"]: distance=minf(distance,p.pos.distance_to(p.target))
		paths[p.id]={"from":p.pos,"to":p.pos+p.direction*distance,"speed":speed,"accel":0.0,"warp":false,"velocity":p.direction*(distance/dt),"acceleration":Vector3.ZERO,"accelerating":0.0}
	return paths

static func path_index(paths: Dictionary) -> Dictionary:
	var index := {}
	for id in paths:
		var p: Dictionary = paths[id]
		var lo := Vector3i((p.from.min(p.to)*2.0).floor())
		var hi := Vector3i((p.from.max(p.to)*2.0).floor())
		for x in range(lo.x,hi.x+1):
			for y in range(lo.y,hi.y+1):
				for z in range(lo.z,hi.z+1):
					var key := Vector3i(x,y,z)
					if not index.has(key): index[key]=[]
					index[key].append(id)
	return index

static func nearby_ids(index: Dictionary, path: Dictionary, radius: float) -> Array:
	var lo := Vector3i(((path.from.min(path.to)-Vector3.ONE*radius)*2.0).floor())
	var hi := Vector3i(((path.from.max(path.to)+Vector3.ONE*radius)*2.0).floor())
	var result := {}
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1):
				for id in index.get(Vector3i(x,y,z),[]): result[id]=true
	var ids: Array = result.keys(); ids.sort()
	return ids

static func find_contacts(s, paths: Dictionary, dt: float) -> Array:
	var contacts: Array = []
	var radius: float = s.config.physics.collision_radius
	var index := {} if s.plain_checks else path_index(paths)
	var objects: Dictionary = s.entities.duplicate(false)
	for object in s.projectiles: objects[object.id]=object
	var all_ids: Array = objects.keys(); all_ids.sort()
	for e in s.entities.values():
		if not e.alive or not e.online or not e.moving or not paths.has(e.id): continue
		var path: Dictionary = paths[e.id]
		var waypoint: float = R4Space.accelerated_contact(path,{"from":e.target,"to":e.target},dt,0.0)
		if waypoint>=0.0: contacts.append({"type":"waypoint","fraction":waypoint,"source":e.id,"position":e.target})
		if e.kind=="transport":
			var cells: Array = s.space.cells if s.plain_checks else s.space.cell_candidates(path.from,path.to,radius+0.000002)
			for cell in cells:
				if not cell.habitable or cell.rocky<=0 or cell.owner==e.owner: continue
				var center: Vector3 = s.space.position_for(cell.id)
				var arrival: float = R4Space.accelerated_contact(path,{"from":center,"to":center},dt,radius)
				if arrival>=0.0: contacts.append({"type":"waypoint","fraction":arrival,"source":e.id,"position":center})
	for p in s.projectiles:
		if not p.alive or p.earliest>s.now+dt or not paths.has(p.id): continue
		var path: Dictionary = paths[p.id]
		var first := 2.0
		var selected := {}
		if p.kind=="weapon":
			var candidates: Array = all_ids if s.plain_checks else nearby_ids(index,path,radius+0.000002)
			for id in candidates:
				var target: Dictionary = objects[id]
				if not target.get("alive",false) or target.owner==p.owner or not paths.has(target.id) or not Combat.eligible(p.weapon,target): continue
				var t: float = R4Space.accelerated_contact(path,paths[target.id],dt,radius)
				if t>=0.0 and t<first:
					first=t
					selected={"type":"weapon","fraction":t,"projectile":p.id,"target":target.id}
		elif p.kind=="photoid":
			var cells: Array = s.space.cells if s.plain_checks else s.space.cell_candidates(path.from,path.to,s.config.physics.photoid_radius+0.000002)
			for cell in cells:
				if cell.owner<0 or cell.stars<=0: continue
				var center: Vector3 = s.space.position_for(cell.id)
				if not p.get("cleared_source",false) and s.entities.has(p.source) and cell.id==s.entities[p.source].cell: continue
				var t: float = R4Space.accelerated_contact(path,{"from":center,"to":center},dt,s.config.physics.photoid_radius)
				if t>=0.0 and t<first:
					first=t
					selected={"type":"photoid","fraction":t,"projectile":p.id,"cell":cell.id}
		if not selected.is_empty(): contacts.append(selected)
	for a in s.entities.values():
		if not a.alive or not a.online or a.kind not in ["battleship","droplet","transport"] or not paths.has(a.id): continue
		var candidates: Array = all_ids if s.plain_checks else nearby_ids(index,paths[a.id],radius+0.000002)
		for id in candidates:
			if not s.entities.has(id): continue
			var b: Dictionary = s.entities[id]
			if not b.alive or b.owner==a.owner or not paths.has(b.id): continue
			var kind := ""
			if a.kind=="droplet" and b.kind=="battleship" and not a.contacted.has(b.id): kind="droplet"
			elif a.kind=="battleship" and b.kind=="battleship" and not a.modules.any(func(m):return m in Combat.PRIORITY): kind="suicide"
			elif a.kind=="transport" and b.kind in ["battleship","home","colony"]: kind="transport_contact"
			if kind=="": continue
			var t: float = R4Space.accelerated_contact(paths[a.id],paths[b.id],dt,radius)
			if t>=0.0: contacts.append({"type":kind,"fraction":t,"source":a.id,"target":b.id})
	return contacts

static func move_paths(s, paths: Dictionary, dt: float) -> Array:
	var new_wakes: Array = []
	for e in s.entities.values():
		if not e.alive or not paths.has(e.id): continue
		var p: Dictionary = paths[e.id]
		var displacement: float = p.from.distance_to(p.to)
		e.pos=p.to
		e.speed=p.speed
		e.accel_used+=p.accel
		e.traveled+=displacement
		if p.warp and displacement>0.0:
			new_wakes.append({"id":s.next_id(e.owner),"a":p.from,"b":p.to,"expires":s.now+dt+s.config.physics.wake.life})
			s.first_use(e.owner,"205","warp_movement",e.id)
		var cell: int = s.space.cell_at(e.pos)
		if cell<0:
			s.destroy_entity(e.id,"outside_map")
			continue
		if e.cell!=cell and e.kind in R4Config.ANCHORS: s.invalidate_income(e.owner)
		e.cell=cell
		if e.kind=="transport" and e.moving:
			var closest := 2.0
			var destination := -1
			var cells: Array = s.space.cells if s.plain_checks else s.space.cell_candidates(p.from,p.to,s.config.physics.collision_radius+0.000002)
			for item in cells:
				if not item.habitable or item.rocky<=0 or item.owner==e.owner: continue
				var center: Vector3 = s.space.position_for(item.id)
				var t: float = R4Space.sweep_contact(p.from,p.to,center,center,s.config.physics.collision_radius)
				if t>=0.0 and t<closest:
					closest=t
					destination=item.id
			if destination>=0:
				e.pos=s.space.position_for(destination)
				e.cell=destination
				e.moving=false
				e.speed=0.0
		elif e.kind in ["sophon","droplet"] and s.space.cells[cell].owner>=0 and s.space.cells[cell].owner!=e.owner:
			e.moving=false
			e.speed=0.0
		elif e.moving and R4Space.point_segment_distance(e.target,p.from,p.to)<1e-7:
			e.pos=e.target
			e.moving=false
			e.speed=0.0
		if e.kind=="droplet":
			for other in e.contacted.keys():
				if not s.entities.has(other) or e.pos.distance_to(s.entities[other].pos)>s.config.physics.collision_radius*1.1:
					e.contacted.erase(other)
	for p in s.projectiles:
		if not p.alive or not paths.has(p.id): continue
		var row: Dictionary = paths[p.id]
		var traveled: float = row.from.distance_to(row.to)
		p.pos=row.to
		p.traveled+=traveled
		p.remaining-=traveled
		p.speed=row.speed
		if p.traveled>s.config.physics.photoid_radius: p["cleared_source"]=true
		if p.kind in ["dimensional_weapon","domain_payload"] and not p.arrived and p.pos.distance_to(p.target)<=0.000002:
			p.pos=p.target
			p.arrived=true
			p.activate_at=s.now+dt+p.delay
			s.log_event("payload_arrived",p.owner,{"projectile":p.id,"activate_at":p.activate_at})
	return new_wakes

static func move_messages(s, dt: float, advanced: Dictionary = {}) -> void:
	for msg in s.messages:
		if advanced.has(msg.id): continue
		var target: Dictionary = s.entities.get(msg.target_id,{})
		if target.is_empty(): continue
		var delta: Vector3 = target.pos-msg.pos
		var distance: float = minf(delta.length(),s.space.effective_c(msg.pos,s.now)*dt)
		# Vector3 uses single precision. Snap the last two microlightyears to
		# the calculated endpoint; smaller increments can round to no movement.
		if distance>=delta.length()-0.000002: msg.pos=target.pos
		else: msg.pos+=delta.normalized()*distance
		msg.traveled+=distance

static func deliver_messages(s) -> void:
	var pending: Array[Dictionary] = []
	var delivered: Array = []
	while not s.scheduled_messages.is_empty() and s.scheduled_messages[0].flight.arrival<=s.now+1e-10:
		var msg: Dictionary = s.pop_scheduled()
		var target: Dictionary = s.entities.get(msg.target_id,{})
		if not target.get("alive",false):
			if msg.reservation!="": s.civs[msg.owner].ledger.release_shot(msg.reservation)
			continue
		msg.pos=target.pos
		msg.traveled=msg.flight.distance
		msg.erase("flight")
		delivered.append(msg)
	for msg in s.messages:
		var target: Dictionary = s.entities.get(msg.target_id,{})
		if target.is_empty() or not target.alive:
			if msg.reservation!="": s.civs[msg.owner].ledger.release_shot(msg.reservation)
			continue
		if s.now>=msg.earliest and s.now>s.last_remap+s.config.physics.event_epsilon*0.5 and msg.pos.distance_to(target.pos)<=0.000002:
			delivered.append(msg)
		else: pending.append(msg)
	s.messages=pending
	delivered.sort_custom(func(a,b): return a.id<b.id)
	for msg in delivered:
		if msg.kind=="command": Commands.execute(s,msg)
		else: Intel.deliver(s,msg)

static func find_projectile(s, id: int) -> Dictionary:
	for p in s.projectiles:
		if p.id==id: return p
	return {}

static func resolve_contacts(s, contacts: Array) -> void:
	var hits: Array = []
	var used := {}
	for contact in contacts:
		if contact.fraction>1.0+1e-7: continue
		var type: String = contact.type
		if type=="waypoint":
			var entity: Dictionary = s.entities[contact.source]
			if not entity.alive: continue
			entity.pos=contact.position
			entity.cell=s.space.cell_at(entity.pos)
			entity.moving=false
			entity.speed=0.0
		elif type in ["weapon","photoid"]:
			var p := find_projectile(s,contact.projectile)
			if p.is_empty() or not p.alive or used.has(p.id): continue
			used[p.id]=true
			p.alive=false
			if type=="photoid":
				photoid_hit(s,p,contact.cell)
			else:
				if not s.entities.has(contact.target):
					var intercept := find_projectile(s,contact.target)
					if not intercept.is_empty():
						intercept.damage+=p.damage
						if intercept.damage>=intercept.hp: intercept.alive=false
						s.log_event("payload_intercepted",p.owner,{"shot":p.id,"target":contact.target,"damage":p.damage})
				else:
					hits.append({"shot":p.id,"owner":p.owner,"target":contact.target,"damage":p.damage,"kind":p.damage_kind,"weapon":p.weapon})
		elif type=="transport_contact": s.destroy_entity(contact.source,"hostile_contact",s.entities[contact.target].owner)
		elif type in ["droplet","suicide"]:
			var source: Dictionary = s.entities[contact.source]
			if not source.alive: continue
			var hit := {"shot":s.next_id(source.owner),"owner":source.owner,"target":contact.target,"kind":"physical","damage":s.config.physics.droplet_damage,"weapon":"203"}
			if type=="suicide":
				hit.damage=INF
				hit.weapon="005"
				hit["self_destroy"]=source.id
			else:
				source.contacted[contact.target]=true
				source.paused_until=s.now+s.config.physics.droplet_pause
			hits.append(hit)
	Combat.apply_hits(s,hits)

static func photoid_hit(s, p: Dictionary, cell_id: int) -> void:
	var cell: Dictionary = s.space.cells[cell_id]
	if cell.owner<0 or cell.stars<=0: return
	var owner: int = cell.owner
	s.invalidate_income(owner)
	var bunker := false
	for e in s.owned_entities(owner,"bunker"):
		if e.cell==cell_id: bunker=true
	cell.stars=maxi(0,cell.stars-1)
	for e in s.entities.values():
		if not e.alive or e.cell!=cell_id: continue
		var ground_protected: bool = bunker and e.owner==owner and e.kind in ["home","colony","miner_basic","miner_advanced","warning","bunker"]
		var surviving_star: bool = bunker and e.owner==owner and e.kind=="dyson" and e.get("star_slot",0)<cell.stars
		if not ground_protected and not surviving_star: s.destroy_entity(e.id,"photoid",p.owner)
	if not bunker: cell.owner=-1
	s.log_event("photoid_hit",p.owner,{"cell":cell_id,"bunker":bunker,"stars_remaining":cell.stars,"old_owner":owner})
	s.first_use(p.owner,"204","stellar_hit",p.id)
	if bunker: s.first_use(owner,"014","damage_prevented")
	mark_cleared(s,p.owner,owner)

static func mark_cleared(s, attacker: int, victim: int) -> void:
	if attacker<0 or victim<0 or attacker==victim: return
	for cell in s.space.cells:
		if cell.owner==victim: return
	s.civs[attacker].event_flags["destroyed_all_systems_of_one_other_civilization"]=true
	s.civs[attacker].cleared[victim]=s.now
	s.unlock_permissions(attacker)

static func apply_space_contacts(s) -> void:
	var converted: Array = s.space.convert_due(s.now)
	for item in converted:
		var cell: Dictionary = s.space.cells[item.cell]
		s.log_event("cell_converted",item.owner,{"cell":item.cell,"dim":cell.dim,"front":item.front})
		if cell.dim==0:
			cell.stars=0
			cell.rocky=0
			cell.gas=0
			cell.habitable=false
			cell.owner=-1
	for e in s.entities.values():
		if not e.alive: continue
		var dim: int = s.space.cell_dimension(e.pos)
		if dim==0: s.destroy_entity(e.id,"singularity_terminal_zone")
		elif e.dim>dim:
			var automatic: bool = e.ready.get(str(e.dim),{}).get("auto",true)
			if not automatic or not s.convert_entity(e.id,s.now): s.destroy_entity(e.id,"unadapted_front")
		elif e.kind in R4Config.MOBILE and s.space.local_factor(e.pos,s.now)<s.config.physics.domain.ship_cutoff:
			s.destroy_entity(e.id,"black_domain")
	for p in s.projectiles:
		if not p.alive: continue
		if s.space.cell_dimension(p.pos)==0: p.alive=false
		elif p.kind=="photoid" and s.space.local_factor(p.pos,s.now)<s.config.physics.domain.grain_cutoff:
			p.alive=false
			s.log_event("photoid_disrupted",p.owner,{"projectile":p.id})

static func activate_payloads(s) -> void:
	for p in s.projectiles:
		if not p.alive or not p.get("arrived",false) or p.activate_at>s.now+1e-9: continue
		p.alive=false
		s.flush_scheduled_messages()
		if p.kind=="domain_payload":
			s.space.domains.append({"id":p.id,"owner":p.owner,"pos":p.pos,"born":s.now,"expires":s.now+s.config.physics.domain.life,"dim":maxi(1,s.space.cell_dimension(p.pos))})
			s.first_use(p.owner,"303","domain_activated",p.id)
		elif p.kind=="dimensional_weapon" and p.payload_dim==s.space.world_dim:
			s.space.add_front(p.id,p.owner,p.pos,s.now)
			s.first_use(p.owner,"302","front_unfolded",p.id)
			s.log_event("front_unfolded",p.owner,{"projectile":p.id,"pos":p.pos,"dim":s.space.world_dim,"speed":s.space.front_speed()})

static func move_broadcasts_and_scans(s, dt: float) -> void:
	for broadcast in s.broadcasts:
		for id in broadcast.rays:
			var ray: Dictionary = broadcast.rays[id]
			if ray.arrived: continue
			var target: Vector3 = s.space.position_for(id)
			var delta: Vector3 = target-ray.pos
			var traveled: float = minf(delta.length(),s.space.effective_c(ray.pos,s.now)*dt)
			ray.pos+=delta.normalized()*traveled
			ray.traveled+=traveled
			if ray.pos.distance_to(target)>1e-7 or s.now+dt<broadcast.earliest: continue
			ray.arrived=true
			broadcast.visited[id]=s.now+dt
			for e in s.entities.values():
				if not e.alive or e.cell!=id or e.kind not in R4Config.ANCHORS: continue
				if broadcast.received.has(e.owner): continue
				broadcast.received[e.owner]=s.now+dt
				s.first_use(broadcast.owner,"108" if s.civs[broadcast.owner].techs.has("108") else "006","broadcast_received",broadcast.source)
				var c: Dictionary = s.civs[e.owner]
				if not c.has("broadcast_intel"): c["broadcast_intel"]={}
				c.broadcast_intel[broadcast.id]={"target_cell":broadcast.target_cell,"position_at_emission":broadcast.target,
					"t_received":s.now+dt,"t_emitted":broadcast.born,"epoch":broadcast.epoch,"sender":broadcast.owner}
				s.log_event("broadcast_received",e.owner,{"broadcast":broadcast.id,"target_cell":broadcast.target_cell,"emitted":broadcast.born,"received":s.now+dt})
	for scan in s.scans:
		if scan.remaining<=0.0: continue
		var traveled: float = minf(scan.remaining,s.space.effective_c(scan.pos,s.now)*dt)
		var old: Vector3 = scan.pos
		scan.pos+=scan.direction*traveled
		scan.traveled+=traveled
		scan.remaining-=traveled
		for cell in s.space.cells:
			if cell.owner<0 or cell.owner==scan.owner or scan.seen.has(cell.id): continue
			var point: Vector3 = s.space.position_for(cell.id)
			var longitudinal: float = (point-scan.origin).dot(scan.direction)
			if longitudinal<0.0 or longitudinal>scan.traveled: continue
			if R4Space.point_segment_distance(point,scan.origin,scan.pos)>s.config.physics.scan.radius: continue
			scan.seen[cell.id]=true
			var record: Dictionary = cell.duplicate(true)
			record["t_observed"]=s.now+dt
			record["epoch"]=s.space.world_epoch
			record["pos"]=point
			s.send_message(scan.owner,"scan_echo",point,scan.source,{"cell":record,"source":scan.source,"t_observed":s.now+dt},s.now+dt)

static func remap_world(s) -> void:
	s.flush_scheduled_messages()
	var from: int = s.space.world_dim
	var to: int = from-1
	var collections: Array = [s.entities.values(),s.projectiles,s.messages,s.scans,s.space.domains]
	for collection in collections:
		for object in collection:
			var old_direction: Vector3 = object.get("direction",Vector3.RIGHT)
			var old_position: Vector3 = object.pos
			var waypoint: Vector3 = object.get("target",old_position+old_direction*s.config.spacing(from))
			object.pos=s.space.remap_point(old_position,from,to)
			var mapped_waypoint: Vector3 = s.space.remap_point(waypoint,from,to)
			if object.has("target"): object.target=mapped_waypoint
			if object.has("origin"): object.origin=s.space.remap_point(object.origin,from,to)
			if object.has("direction"):
				var direction: Vector3 = mapped_waypoint-object.pos
				if direction.length_squared()<=1e-16:
					direction=old_direction
					direction.z=0.0
					if to==1: direction.y=0.0
					if direction.length_squared()<=1e-16: direction=Vector3.RIGHT if old_direction.dot(Vector3.ONE)>=0.0 else Vector3.LEFT
				object.direction=direction.normalized()
			if object.has("speed"): object.speed=minf(object.speed,s.config.c(to))
			if object.has("earliest"): object.earliest=maxf(object.earliest,s.now+s.config.physics.event_epsilon)
			if object.has("payload") and object.kind=="command" and object.payload.command.has("target"):
				object.payload.command.target=s.space.remap_point(object.payload.command.target,from,to)
	for wake in s.space.wakes:
		wake.a=s.space.remap_point(wake.a,from,to)
		wake.b=s.space.remap_point(wake.b,from,to)
	for broadcast in s.broadcasts:
		for ray in broadcast.rays.values(): ray.pos=s.space.remap_point(ray.pos,from,to)
		broadcast.earliest=maxf(broadcast.earliest,s.now+s.config.physics.event_epsilon)
		# 广播中的历史目标坐标和发射epoch保留，永久target_cell可供显示映射。
	s.space.commit_remap()
	s.last_remap=s.now
	s.log_event("world_dimension_entered",-1,{"dimension":to,"epoch":s.space.world_epoch})

static func cleanup(s) -> void:
	for p in s.projectiles:
		if p.remaining<=1e-9 or not s.space.inside(p.pos): p.alive=false
	s.projectiles=s.projectiles.filter(func(p):return p.alive)
	s.scans=s.scans.filter(func(scan):return scan.remaining>0.0)
	s.broadcasts=s.broadcasts.filter(func(b):return b.visited.size()<729)
	if s.plain_checks: sort_collections(s)

static func sort_collections(s) -> void:
	s.messages.sort_custom(func(a,b):return a.id<b.id)
	s.projectiles.sort_custom(func(a,b):return a.id<b.id)
	s.broadcasts.sort_custom(func(a,b):return a.id<b.id)

static func periodic_systems(s, dt: float) -> void:
	for e in s.entities.values():
		if not e.alive or not e.online: continue
		if e.kind=="devourer" and not e.moving and e.get("devoured_round",-1)!=s.round_index:
			var cell: Dictionary = s.space.cells[e.cell]
			if cell.owner<0 and cell.rocky>0:
				cell.rocky-=1
				if cell.rocky==0: cell.habitable=false
				e["devoured_round"]=s.round_index
				s.civs[e.owner].ledger.credit(R4Ledger.amount(0,s.config.physics.devourer_energy*s.config.q(e.dim)),"devourer_oneoff")
				s.first_use(e.owner,"101","planet_consumed",e.id)
		var heal_period := INF
		if e.kind=="starship": heal_period=s.config.physics.starship_heal_period
		elif e.kind=="battleship" and e.modules.has("106"): heal_period=s.config.physics.field_heal_period
		if e.damage>0.0 and s.now>e.last_combat:
			e.repair_time+=dt
			if e.repair_time>=heal_period and s.now-e.last_combat>=heal_period:
				e.damage=maxf(0.0,e.damage-1.0)
				e.repair_time-=heal_period
				if e.kind=="battleship": s.first_use(e.owner,"106","shield_repair",e.id)
		if e.kind!="battleship" or not e.modules.any(func(m):return m in Combat.PRIORITY): continue
		occupation(s,e,dt)

static func occupation(s, ship: Dictionary, dt: float) -> void:
	var p: Dictionary = s.config.physics.occupation
	var touched := {}
	for target in s.entities.values():
		if not target.alive or target.owner==ship.owner or target.kind not in ["home","colony"]: continue
		if ship.pos.distance_to(target.pos)>p.range: continue
		var defender := false
		for e in s.entities.values():
			if e.alive and e.online and e.kind=="battleship" and e.owner==target.owner and e.pos.distance_to(target.pos)<=p.defender_range and e.modules.any(func(m):return m in Combat.PRIORITY): defender=true
		if defender: continue
		var reservation := "occupation:%d:%d:%d"%[ship.id,target.id,s.round_index]
		var paid_key := "paid:"+reservation
		if not ship.occupation.has(paid_key):
			# 用本回合开始时已预留的现金，禁止同批次战利品资助占领。
			if not s.civs[ship.owner].ledger.shots.has(reservation): continue
			var ledger = s.civs[ship.owner].ledger
			var shortfall: Vector2i = R4Ledger.amount(p.M,p.E)-ledger.shots[reservation]
			if not ledger.can_pay(shortfall): continue
			if shortfall!=Vector2i.ZERO: ledger.debit(shortfall,"migration_occupation_topup")
			ledger.fire_shot(reservation)
			ship.occupation[paid_key]=true
		touched[target.id]=true
		ship.occupation[target.id]=ship.occupation.get(target.id,0.0)+dt
		if ship.occupation[target.id]>=p.work:
			var victim: int = target.owner
			s.destroy_entity(target.id,"occupation",ship.owner)
			mark_cleared(s,ship.owner,victim)
			s.log_event("system_suppressed",ship.owner,{"target":target.id,"cell":target.cell,"work":p.work})
	for key in ship.occupation.keys():
		if key is int and not touched.has(key): ship.occupation.erase(key)
