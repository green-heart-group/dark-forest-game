extends RefCounted
## 正式稿24–25页的只读导航比较。光路、舰速、前沿均只用Knowledge投影和已收报告。
## 下一维采用公开固定映射；平面/直线的共同平移不影响距离，不查询隐藏打击点。


static func compare(s: GameState,civ: Civ,from: Vector3,target: Vector3i,unit_id: int=-1,options: Dictionary={}) -> Dictionary:
	var known:=Knowledge.presentation(s,civ)
	var me: Civ=known.civs[s.civs.find(civ)]
	var unit:=me.ship_by_id(unit_id)
	if unit!=null:
		from=unit.pos
	var outside:=not known.map.contains(target)
	var current:=_journey(known,me,from,Vector3(target),unit)
	var next: Dictionary={}
	var anchor:=known.map.origin
	if outside:
		current["outside"]=true
		current["eta"]=INF
		current["signal_eta"]=INF
		if s.dimension>1:
			next={"dim":s.dimension-1,"cell_size":Balance.DIMENSION_CELL_SIZE[str(s.dimension-1)],"light_speed":Balance.DIMENSION_LIGHT[str(s.dimension-1)],"outside":true}
	if known.dimension>1 and not outside:
		var next_from:=DimensionSpace.point(from,anchor,known.dimension==2,known.map)
		var next_target:=DimensionSpace.map_cell(target,anchor,known.dimension==2)
		known.fold_anchor=anchor
		known.line_anchor=anchor
		DimensionSpace.commit(known,known.dimension==2)
		for ship in me.ships:
			ship.entity_dim=mini(ship.entity_dim,known.dimension)
		for id in known.cell_dims:
			known.cell_dims[id]=mini(known.cell_dims[id],known.dimension)
		next=_journey(known,me,next_from,Vector3(next_target),unit)
	var size: float=Balance.DIMENSION_CELL_SIZE[str(s.dimension)]
	var next_size: float=Balance.DIMENSION_CELL_SIZE[str(maxi(1,s.dimension-1))]
	var weapons: Dictionary={}
	for id in Balance.WEAPON_DATA:
		var range_ly: float=Balance.WEAPON_DATA[id]["range"]
		weapons[id]={"name":Tech.title(id),"range":range_ly,"current_cells":range_ly/size,"next_cells":range_ly/next_size}
	var anchors: Array=[]
	for asset in Knowledge.assets(s,civ):
		if asset["kind"]=="anchor":
			anchors.append(_place(s,civ,asset["id"],"星系锚点",Vector3(asset["at"]),anchor))
	for ship in Signals.reported_ships(s,civ):
		if ship.kind in [Ship.STARSHIP,Ship.WANDERING_EARTH]:
			anchors.append(_place(s,civ,ship.id,Ship.NAMES[ship.kind],ship.pos,anchor))
	var threats: Array=[]
	for contact in civ.sightings:
		if contact.get("owner",-1)!=s.civs.find(civ):
			threats.append(_threat(s,contact,Ship.NAMES.get(contact["kind"],"来袭载荷"),anchor))
	for alert in civ.alerts:
		threats.append(_threat(s,alert,"预警："+Ship.NAMES.get(alert.get("kind",""),"来袭载荷"),anchor))
	for cell in civ.intel:
		var info: Dictionary=civ.intel[cell]
		if info.get("owner",-1)>=0 and info["owner"]!=s.civs.find(civ):
			var data:=info.duplicate(true)
			data["pos"]=Vector3(cell)
			threats.append(_threat(s,data,"已知异文明星系",anchor))
	for report in civ.front_reports.values():
		var data: Dictionary=report.duplicate(true)
		data["pos"]=Vector3(report["data"]["center"])
		threats.append(_threat(s,data,"已观测降维前沿",anchor))
	var observed: float=s.clock if unit==null or Knowledge.local(s,civ,from) else civ.telemetry.get(unit_id,{}).get("t_observed",s.clock)
	var ids: Array=options.get("roster",Conversion.known_roster(s,civ,s.dimension))
	var preparation_error:=Conversion.error(s,civ,ids,options.get("host",Signals.controller(civ)),options.get("emergency",false))
	return {"current":current,"next":next,"outside":outside,"weapons":weapons,"anchors":anchors,"threats":threats,
		"unit_label":unit.label() if unit!=null else "光信号","unit_observed":observed,
		"warnings":_warnings(s,civ,options),"preparation_error":preparation_error}


static func _journey(s: GameState,civ: Civ,from: Vector3,target: Vector3,unit: Ship) -> Dictionary:
	return {"dim":s.dimension,"cell_size":s.physical_cell_size(),"light_speed":s.background_light(),"from":from,"target":target,
		"distance":from.distance_to(target)*s.physical_cell_size(),"signal_eta":_travel(s,civ,from,target,null),
		"eta":_travel(s,civ,from,target,unit)}


## 直线路径在格界、限速和己方星系视野边界分段；没有把最高速度当起步速度。
static func _travel(s: GameState,civ: Civ,from: Vector3,target: Vector3,unit: Ship) -> float:
	if from.distance_to(target)*s.physical_cell_size()<=Balance.COLLISION_EPSILON:
		return 0.0
	if unit!=null and (unit.dormant or unit.work_locked):
		return INF
	var ship:=Ship.make(unit.kind if unit!=null else Ship.PROBE,from,unit.id if unit!=null else -1)
	if unit!=null:
		for key in Signals.ship_status(unit):
			if key in ship:
				if ship.get(key) is Array:
					ship.get(key).assign(unit.get(key))
				else:
					ship.set(key,unit.get(key))
	ship.pos=from
	ship.target=target
	ship.has_target=true
	ship.direction=(target-from).normalized()
	ship.docked=false
	ship.parked=false
	var elapsed:=maxf(0.0,ship.pause_until-s.clock) if unit!=null else 0.0
	ship.pause_until=s.clock
	if _uniform(s) and (unit==null or (not ship.warp and not ship.slow_start)):
		var length:=from.distance_to(target)*s.physical_cell_size()
		if unit==null:
			return length/s.background_light()
		var bounds:=Kinematics.limits(s,civ,ship,from,false)
		var speed: float=bounds[0] if ship.kind in [Ship.PROBE,Ship.GRAIN] else minf(ship.speed,bounds[0])
		var acceleration: float=bounds[1] if speed<bounds[0] else 0.0
		var cap_time: float=(bounds[0]-speed)/acceleration if acceleration>0.0 else INF
		var arrival:=Kinematics.time_to_distance(length,speed,acceleration)
		if arrival<=cap_time:
			return elapsed+arrival
		return elapsed+cap_time+(length-Kinematics.distance(speed,acceleration,cap_time))/bounds[0] if bounds[0]>0.0 else INF
	# 有限段数是计算保护，不改游戏时间或玩法参数。
	for segment in DimensionSpace.COUNT*4:
		if ship.slow_start and not Kinematics.in_owned_system_vision(s,civ,ship.pos):
			ship.slow_start=false
		var motion: Dictionary
		if unit==null:
			var speed:=s.light_speed_at(ship.pos)
			if speed<=0.0:
				return INF
			motion={"pos":ship.pos,"velocity":ship.direction*speed/s.physical_cell_size(),"acceleration":Vector3.ZERO,
				"speed":speed,"cap_time":INF,"arrival":ship.pos.distance_to(target)*s.physical_cell_size()/speed}
		else:
			motion=Kinematics.motion(s,civ,ship,INF)
		if motion["velocity"]==Vector3.ZERO and motion["acceleration"]==Vector3.ZERO:
			return INF
		var dt: float=minf(motion["arrival"],minf(motion["cap_time"],Kinematics.next_cell_boundary(motion)))
		if unit!=null and (ship.warp or ship.slow_start):
			dt=minf(dt,_vision_boundary(s,civ,ship,motion))
		dt=maxf(Balance.TIME_EPSILON,dt)
		if is_inf(dt):
			return INF
		elapsed+=dt
		if motion["arrival"]<=dt+Balance.TIME_EPSILON:
			return elapsed
		ship.pos=Kinematics.position(motion,dt)
		ship.speed=motion["speed"]+motion["acceleration"].length()*s.physical_cell_size()*dt
	return INF


static func _uniform(s: GameState) -> bool:
	for value in s.light:
		if value!=1.0:
			return false
	for dim in s.cell_dims.values():
		if dim!=s.dimension:
			return false
	return true


static func _vision_boundary(s: GameState,civ: Civ,ship: Ship,motion: Dictionary) -> float:
	var best:=INF
	for cell in civ.colonies:
		var radius: float=((Balance.VISION_HOME if cell==civ.home else Balance.VISION_COLONY)+civ.vision_bonus())/s.physical_cell_size()
		var relative:=ship.pos-Vector3(cell)
		var b:=relative.dot(ship.direction)
		var discriminant:=b*b-relative.length_squared()+radius*radius
		if discriminant<0.0:
			continue
		for length in [-b-sqrt(discriminant),-b+sqrt(discriminant)]:
			if length>Balance.COLLISION_EPSILON/s.physical_cell_size():
				best=minf(best,Kinematics.time_to_distance(length*s.physical_cell_size(),motion["speed"],motion["acceleration"].length()*s.physical_cell_size()))
	return best


static func _place(s: GameState,civ: Civ,id: int,name: String,pos: Vector3,anchor: Vector3i) -> Dictionary:
	var local:=Knowledge.local(s,civ,pos)
	var report: Dictionary=civ.telemetry.get(id,civ.site_reports.get(Vector3i(pos.round()),{}))
	return {"id":id,"name":name,"current":pos,"next":DimensionSpace.point(pos,anchor,s.dimension==2,s.map) if s.dimension>1 else pos,
		"t_observed":s.clock if local else report.get("t_observed",s.clock),"t_received":s.clock if local else report.get("t_received",s.clock)}


static func _threat(s: GameState,data: Dictionary,name: String,anchor: Vector3i) -> Dictionary:
	var pos: Vector3=data["pos"]
	return {"id":data.get("id",-1),"name":name,"current":pos,"next":DimensionSpace.point(pos,anchor,s.dimension==2,s.map) if s.dimension>1 else pos,
		"t_observed":data.get("t_observed",0.0),"t_received":data.get("t_received",0.0),"epoch":data.get("epoch",0)}


static func _danger(s: GameState,civ: Civ,pos: Vector3) -> Dictionary:
	var best: Dictionary={"eta":INF,"age":0.0,"delay":0.0}
	var speed: float=Balance.FOIL_SPREAD*s.background_light()
	for cell in civ.intel:
		var info: Dictionary=civ.intel[cell]
		if info.get("cell_dim",s.dimension)<s.dimension:
			_warning_min(s,best,info,pos.distance_to(Vector3(cell))*s.physical_cell_size()/speed)
	for report in civ.front_reports.values():
		if report.get("epoch",-1)!=s.space_epoch:
			continue
		var zone: Dictionary=report["data"]
		_warning_min(s,best,report,maxf(0.0,(pos.distance_to(Vector3(zone["center"]))-zone["age"])*s.physical_cell_size()/speed))
	for alert in civ.alerts:
		if alert.get("payload_kind","")!="dimension" or alert.get("epoch",s.space_epoch)!=s.space_epoch:
			continue
		var velocity: Vector3=alert.get("velocity",Vector3.ZERO)
		var relative: Vector3=pos-alert["pos"]
		if velocity.length_squared()<=1e-15 or relative.dot(velocity)<0.0:
			continue
		var lead:=relative.dot(velocity)/velocity.length_squared()
		if (relative-velocity*lead).length()*s.physical_cell_size()<=Balance.COLLISION_EPSILON:
			_warning_min(s,best,alert,lead+Balance.DIMENSION_ACTIVATION)
	return best


static func _warning_min(s: GameState,best: Dictionary,report: Dictionary,eta_at_observation: float) -> void:
	var age:=maxf(0.0,s.clock-float(report.get("t_observed",s.clock)))
	var eta:=maxf(0.0,eta_at_observation-age)
	if eta<best["eta"]:
		best.merge({"eta":eta,"age":age,"delay":maxf(0.0,float(report.get("t_received",s.clock))-float(report.get("t_observed",s.clock)))},true)


static func _warnings(s: GameState,civ: Civ,options: Dictionary) -> Array:
	var ids: Array=options.get("roster",Conversion.known_roster(s,civ,s.dimension))
	var host_id: int=options.get("host",Signals.controller(civ))
	var host:=Knowledge.entity(s,civ,host_id)
	var control:=Knowledge.entity(s,civ,Signals.controller(civ))
	if host.is_empty() or control.is_empty():
		return []
	var known:=Knowledge.presentation(s,civ)
	var me: Civ=known.civs[s.civs.find(civ)]
	var command:=_travel(known,me,control["pos"],host["pos"],null)
	var work_amount: float=Conversion.quote(ids,options.get("emergency",false))["work"]
	var project:=WorkOrder.create(-1,"conversion",Vector3i(host["pos"].round()),[0,0],work_amount,"conversion")
	project["host_id"]=host_id
	project["host_ship"]=host_id if host.has("ship") else -1
	var rate:=known.project_work_rate(me,project)
	var work: float=work_amount/rate if rate>0.0 else INF
	var result: Array=[]
	for id in ids:
		var entity:=Knowledge.entity(s,civ,id)
		if entity.is_empty():
			continue
		var danger:=_danger(s,civ,entity["pos"])
		var distribution:=_travel(known,me,host["pos"],entity["pos"],null)
		var confirmation:=0.0
		if not options.get("automatic",true):
			confirmation=_travel(known,me,entity["pos"],control["pos"],null)+_travel(known,me,control["pos"],entity["pos"],null)
		var needed:=command+work+distribution+confirmation
		result.append({"id":id,"danger_eta":danger["eta"],"information_age":danger["age"],"information_delay":danger["delay"],
			"command_eta":command,"work_time":work,"distribution_eta":distribution,"confirmation_eta":confirmation,
			"needed":needed,"margin":danger["eta"]-needed if not is_inf(danger["eta"]) and not is_inf(needed) else -INF})
	return result
