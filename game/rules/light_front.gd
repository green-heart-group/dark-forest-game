class_name LightFront
extends RefCounted
## 移动接收者与连续波面的相交。射线按发射时刻和经过的实际介质推进；
## 仅延迟计算未曾查询的方向，不追踪接收者转弯，也不向已越过的波后补送消息。
## 历史介质与换图事件是只读数据，和存档一同保留，不暴露给文明决策。


static func begin(s: GameState, origin: Vector3) -> Dictionary:
	return {"origin":origin,"sent":s.clock,"events":[],"uniform":true,"received":{},
		"size":s.physical_cell_size(),"speed":s.background_light()}


static func environment(s: GameState) -> Dictionary:
	var speeds := {}
	var immunity := {}
	for cell in s.cell_ids:
		var id: int=s.cell_ids[cell]
		var dim: int=s.cell_dims.get(id,s.dimension)
		var c: float=0.0 if dim==0 else Balance.DIMENSION_LIGHT[str(dim)]*s.light_at(cell)
		if c!=s.background_light(): speeds[cell]=c
		if s.domain_cells.has(id): immunity[cell]=s.domain_cells[id].duplicate(true)
	var domains: Array=[]
	for field in s.black_domains:
		domains.append({"pos":field["pos"],"created":field["created"],"expires":field["expires"]})
	var lines: Array=[]
	for line in s.deadlines:
		lines.append({"a":line["a"],"b":line["b"],"expires":line["expires"]})
	return {"size":s.physical_cell_size(),"speed":s.background_light(),"speeds":speeds,
		"immunity":immunity,"domains":domains,"lines":lines,"epoch":s.space_epoch}


static func remember(wave: Dictionary, env: Dictionary, start: float, end: float) -> void:
	if not wave.has("propagation"): return
	var p: Dictionary=wave["propagation"]
	var events: Array=p["events"]
	if not env["speeds"].is_empty() or not env["domains"].is_empty() or not env["lines"].is_empty():
		p["uniform"]=false
	if not events.is_empty() and events[-1].has("environment") and events[-1]["environment"]==env:
		events[-1]["end"]=end
	else:
		events.append({"start":start,"end":end,"environment":env})


static func remap(s: GameState, anchor: Vector3i, to_line: bool, old: StarMap, mapping: Dictionary) -> void:
	for wave in Information.waves(s):
		if not wave.has("propagation"): continue
		wave["propagation"]["uniform"]=false
		var inverse := {}
		for cell in mapping: inverse[mapping[cell]]=cell
		wave["propagation"]["events"].append({"at":s.clock,"anchor":anchor,"to_line":to_line,
			"old_origin":old.origin,"old_extent":old.extent,"inverse":inverse})


static func _speed(env: Dictionary, at: Vector3, time: float) -> float:
	var cell:=Vector3i(at.round())
	var speed: float=env["speeds"].get(cell,env["speed"])
	var factor:=1.0
	var life: Dictionary=env["immunity"].get(cell,{})
	if life.is_empty() or time<life["expires"] or time>=life["immune_until"]:
		var weight:=0.0
		for field in env["domains"]:
			if time<field["created"] or time>=field["expires"]: continue
			var radius:=minf(Balance.DOMAIN_RADIUS,(time-field["created"])*Balance.DOMAIN_SPREAD*env["speed"])
			var distance: float=at.distance_to(field["pos"])*env["size"]
			if distance>radius+1e-8: continue
			if distance<=Balance.DOMAIN_CORE: return 0.0
			if radius>0: weight+=Balance.DOMAIN_WEIGHT*maxf(0.0,1.0-distance/radius)
		factor=1.0/(1.0+weight)
	for line in env["lines"]:
		if time<line["expires"] and Hazards.segment_distance(at,line["a"],line["b"])*env["size"]<=Balance.DEADLINE_RADIUS:
			factor=minf(factor,Balance.DEADLINE_FACTOR)
	return speed*factor


static func _boundary(env: Dictionary, motion: Dictionary, at: float, dt: float) -> float:
	var next:=Kinematics.next_cell_boundary(motion)
	for field in env["domains"]:
		if at>=field["expires"]: continue
		var reach:=minf(Balance.DOMAIN_RADIUS,maxf(0.0,at-field["created"])*Balance.DOMAIN_SPREAD*env["speed"])
		for radius in [Balance.DOMAIN_CORE,reach]:
			var growth: float=Balance.DOMAIN_SPREAD*env["speed"]/env["size"] if radius!=Balance.DOMAIN_CORE and reach<Balance.DOMAIN_RADIUS else 0.0
			next=minf(next,Hazards._surface(motion,{"a":field["pos"],"b":field["pos"],"r":radius/env["size"],"growth":growth},dt))
	for line in env["lines"]:
		if at<line["expires"]:
			next=minf(next,Hazards._surface(motion,{"a":line["a"],"b":line["b"],"r":Balance.DEADLINE_RADIUS/env["size"],"growth":0.0},dt))
	return next


## 固定空间点的光到达时差；正数表示波前尚未到，负数表示已越过。
## 换图时映射的是当时的光位置及其下一目标，绝不用新原点重画旧半径。
static func difference(s: GameState, wave: Dictionary, position: Vector3, time: float, current: Dictionary) -> float:
	var p: Dictionary=wave["propagation"]
	if p["uniform"] and current["speeds"].is_empty() and current["domains"].is_empty() and current["lines"].is_empty():
		return p["origin"].distance_to(position)*p["size"]/p["speed"]-(time-p["sent"])
	var goal:=position
	var events: Array=p["events"]
	# 单元身份可逆；连续坐标采用和实体迁移相同的丢弃轴中心投影。
	for i in range(events.size()-1,-1,-1):
		var event: Dictionary=events[i]
		if not event.has("inverse"): continue
		var cell:=Vector3i(goal.round())
		if not event["inverse"].has(cell): return INF
		goal=Vector3(event["inverse"][cell])+(goal-Vector3(cell))
	var ray: Dictionary={"pos":p["origin"],"goal":goal,"arrival":INF}
	for event in events:
		if event.has("environment"):
			_trace(ray,event["environment"],event["start"],minf(event["end"],time))
			if ray["arrival"]!=INF: return ray["arrival"]-time
		else:
			var old:=StarMap.new()
			old.origin=event["old_origin"]
			old.extent=event["old_extent"]
			ray["pos"]=DimensionSpace.point(ray["pos"],event["anchor"],event["to_line"],old)
			ray["goal"]=DimensionSpace.point(ray["goal"],event["anchor"],event["to_line"],old)
			# 新邻接只可在下一物理子步相交。
			if ray["pos"].distance_squared_to(ray["goal"])<1e-20:
				return event["at"]+2.0*Balance.TIME_EPSILON-time
	_trace(ray,current,s.clock,time)
	if ray["arrival"]!=INF: return ray["arrival"]-time
	return ray["pos"].distance_to(ray["goal"])*current["size"]/maxf(current["speed"],1e-9)


static func _trace(ray: Dictionary, env: Dictionary, start: float, end: float) -> void:
	var t:=start
	var direction: Vector3=(ray["goal"]-ray["pos"]).normalized()
	if env["speeds"].is_empty() and env["domains"].is_empty() and env["lines"].is_empty():
		var flight: float=ray["pos"].distance_to(ray["goal"])*env["size"]/env["speed"]
		if flight<=end-start:
			ray["arrival"]=start+flight
			ray["pos"]=ray["goal"]
		else:
			ray["pos"]+=direction*env["speed"]*(end-start)/env["size"]
		return
	while t<end-1e-12:
		var speed:=_speed(env,ray["pos"],t)
		var dt:=minf(Balance.PHYSICS_MAX_DT,end-t)
		if speed>0.0:
			var remaining: float=ray["pos"].distance_to(ray["goal"])*env["size"]
			var motion: Dictionary={"pos":ray["pos"],"velocity":direction*speed/env["size"],"acceleration":Vector3.ZERO}
			dt=minf(dt,maxf(_boundary(env,motion,t,dt),Balance.TIME_EPSILON))
			if remaining/speed<=dt:
				ray["arrival"]=t+remaining/speed
				ray["pos"]=ray["goal"]
				return
			ray["pos"]+=motion["velocity"]*dt
		t+=dt


static func events_in(s: GameState, motions: Dictionary, dt: float) -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	if (s.broadcasts.is_empty() and s.scans.is_empty()) or s.clock<s.remap_until: return out
	var env:=environment(s)
	for wave in Information.waves(s):
		if not wave.has("propagation"): continue
		for owner in s.civs.size():
			var civ: Civ=s.civs[owner]
			if not civ.alive or (wave.has("owner") and wave["owner"]==owner): continue
			for ship in civ.ships:
				if ship.dead or ship.dormant or ship.kind==Ship.GRAIN or not motions.has(ship.id): continue
				if wave["propagation"]["received"].has(ship.id): continue
				if wave.has("sender") and (not ship.gravity or wave["heard"].has(civ) or wave["sender"]==civ): continue
				var motion: Dictionary=motions[ship.id]
				var last:=0.0
				var f:=difference(s,wave,ship.pos,s.clock,env)
				for part in [0.5,1.0]:
					var at: float=dt*part
					var g:=difference(s,wave,Kinematics.position(motion,at),s.clock+at,env)
					if (f>0.0 and g<=0.0) or (f<0.0 and g>=0.0) or absf(f)<Balance.TIME_EPSILON:
						var lo:=last
						var hi:=at
						for i in 24:
							if hi-lo<=Balance.TIME_EPSILON: break
							var mid: float=(lo+hi)*0.5
							var m:=difference(s,wave,Kinematics.position(motion,mid),s.clock+mid,env)
							if signf(m)==signf(f): lo=mid
							else: hi=mid
						var hit:=Kinematics.position(motion,hi)
						if not wave.has("owner") or Information.inside_scan(s,wave["from"],wave["direction"],hit):
							out.append({"after":maxf(hi,Balance.TIME_EPSILON),"wave":wave["id"],"ship":ship.id,"owner":owner})
						break
					last=at
					f=g
	return out


static func resolve(s: GameState, events: Array[Dictionary], dt: float) -> void:
	for event in events:
		if event["after"]>dt+Balance.TIME_EPSILON: continue
		var civ: Civ=s.civs[event["owner"]]
		var ship:=civ.ship_by_id(event["ship"])
		if ship==null or ship.dead: continue
		for wave in Information.waves(s):
			if wave["id"]!=event["wave"]: continue
			wave["propagation"]["received"][ship.id]=s.clock
			if wave.has("sender"):
				Information._hear(s,wave,civ,ship.pos)
			else:
				Signals.send(s,wave["owner"],ship.pos,wave["source_id"],"sensor",{
					"type":"entity","scan":wave["id"],"source_id":wave["source_id"],"t_observed":s.clock,"epoch":s.space_epoch,
					"data":{"id":ship.id,"owner":event["owner"],"kind":ship.kind,"pos":ship.pos,
						"velocity":ship.direction*ship.speed/s.physical_cell_size(),"hp":ship.max_hp()-ship.damage}})
