class_name Knowledge
extends RefCounted
## 决策/界面可用的己方状态。远端据点只读回报；真实状态只供发报和命令抵达结算。

static func local(s: GameState, civ: Civ, pos: Vector3) -> bool:
	var control := Signals.entity(s,s.civs.find(civ),Signals.controller(civ))
	# 初始化夹具尚未分配永久ID时，母星仍是本地控制地点。
	var center: Vector3 = control.get("pos",Vector3(civ.home))
	return center.distance_to(pos)*s.physical_cell_size()<=Balance.COLLISION_EPSILON

static func actual_site(s: GameState,civ: Civ,cell: Vector3i) -> Dictionary:
	var owned:=civ.owns(cell)
	return {"cell":cell,"owned":owned,"assets":civ.assets.filter(func(a):return a["at"]==cell and a["carrier"]<0).duplicate(true),
		"snapshot":s.snapshot(cell),"dormant":civ.dormant_colonies.has(cell),"jammed":s.jammed(civ,cell),
		"relative_light":s.relative_light(Vector3(cell)),"miners":civ.miners.get(cell,0),"advanced_miners":civ.advanced_miners.get(cell,0),
		"dysons":civ.dysons.get(cell,0),"bunker":civ.bunkers.has(cell),"broadcaster":civ.broadcasters.has(cell),
		"warning":civ.warnings.get(cell,-1),"grain":civ.grains.has(cell),"colonial":civ.colonial.get(cell,false)}

static func site(s: GameState,civ: Civ,cell: Vector3i) -> Dictionary:
	if local(s,civ,Vector3(cell)):
		return actual_site(s,civ,cell)
	return civ.site_reports.get(cell,{}).get("data",{})

static func colonies(s: GameState,civ: Civ) -> Array[Vector3i]:
	var result: Array[Vector3i]=[]
	for cell in civ.site_reports:
		if site(s,civ,cell).get("owned",false):
			result.append(cell)
	for cell in civ.colonies:
		if local(s,civ,Vector3(cell)) and not result.has(cell):
			result.append(cell)
	result.sort()
	return result

static func owns(s: GameState,civ: Civ,cell: Vector3i) -> bool:
	return site(s,civ,cell).get("owned",false)

static func snapshot(s: GameState,civ: Civ,cell: Vector3i) -> Dictionary:
	return site(s,civ,cell).get("snapshot",civ.intel.get(cell,{}))

static func assets(s: GameState,civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for cell in colonies(s,civ):
		result.append_array(site(s,civ,cell).get("assets",[]))
	for ship in Signals.reported_ships(s,civ):
		if local(s,civ,ship.pos):
			result.append_array(civ.assets.filter(func(a):return a["carrier"]==ship.id))
		else:
			result.append_array(civ.telemetry.get(ship.id,{}).get("data",{}).get("assets",[]))
	return result

static func entity(s: GameState,civ: Civ,id: int) -> Dictionary:
	var ship:=Signals.reported_ship(s,civ,id)
	if ship!=null:
		return {"id":id,"pos":ship.pos,"ship":ship}
	for asset in assets(s,civ):
		if asset["id"]==id:
			var pos:=Vector3(asset["at"])
			if asset["carrier"]>=0:
				var carrier:=Signals.reported_ship(s,civ,asset["carrier"])
				if carrier!=null:
					pos=carrier.pos
			return {"id":id,"pos":pos,"asset":asset}
	return {}

static func anchor(s: GameState,civ: Civ,cell: Vector3i) -> Dictionary:
	for asset in site(s,civ,cell).get("assets",[]):
		if asset["kind"]=="anchor":
			return {"id":asset["id"],"pos":Vector3(cell),"asset":asset}
	return {}

static func count(s: GameState,civ: Civ,kind: String) -> int:
	if kind in Ship.NAMES:
		return Signals.reported_ships(s,civ).filter(func(ship):return ship.kind==kind).size()
	return assets(s,civ).filter(func(asset):return asset["kind"]==kind).size()

static func miners(s: GameState,civ: Civ) -> int:
	var total:=0
	for cell in colonies(s,civ):
		var data:=site(s,civ,cell)
		total+=data.get("miners",0)+data.get("advanced_miners",0)
	for asset in assets(s,civ):
		if asset["carrier"]>=0 and asset["kind"] in ["miner","advanced_miner"]:
			total+=1
	return total

static func pending(civ: Civ,kind: String,cell:=GameState.ANY_TARGET) -> int:
	var total:=0
	for report in civ.order_reports.values():
		if report["category"]!="research" and report["kind"]==kind and report.get("status","") not in ["completed","failed","destroyed","cancelled"] and (cell==GameState.ANY_TARGET or report["at"]==cell):
			total+=1
	return total

static func flag_cells(s: GameState,civ: Civ,flag: String) -> Array[Vector3i]:
	var result: Array[Vector3i]=[]
	for cell in colonies(s,civ):
		var value=site(s,civ,cell).get(flag,false)
		if (value is bool and value) or (value is int and value>=0):
			result.append(cell)
	return result

static func report_site(s: GameState,civ: Civ,cell: Vector3i) -> void:
	var data:=actual_site(s,civ,cell)
	data["snapshot"]["turn"]=0
	var stamp:="site:%d:%d"%[s.civs.find(civ),s.cell_ids.get(cell,-1)]
	s.sensor_stamps[stamp]={"hash":hash(data),"time":s.clock,"cell":cell}
	Signals.send(s,s.civs.find(civ),Vector3(cell),Signals.controller(civ),"report",{"type":"own_site","data":data,
		"t_observed":s.clock,"source_id":data["assets"][0]["id"] if not data["assets"].is_empty() else -1,"epoch":s.space_epoch})

static func sample(s: GameState,civ: Civ) -> void:
	for cell in civ.colonies:
		var data:=actual_site(s,civ,cell)
		data["snapshot"]["turn"]=0
		var stamp: Dictionary=s.sensor_stamps.get("site:%d:%d"%[s.civs.find(civ),s.cell_ids.get(cell,-1)],{})
		if stamp.get("hash",-1)!=hash(data) or s.clock-stamp.get("time",-INF)>=1.0:
			report_site(s,civ,cell)

static func maintenance(s: GameState,civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for cell in colonies(s,civ):
		result.append({"key":Economy.package_key("anchor",cell),"kind":"anchor","at":cell})
		for i in site(s,civ,cell).get("dysons",0):
			result.append({"key":Economy.package_key("dyson",cell,i),"kind":"dyson","at":cell})
	for ship in Signals.reported_ships(s,civ):
		if Balance.BUILD_UPKEEP.has(ship.kind):
			result.append({"key":"ship:%d"%ship.id,"kind":"ship","at":ship.cell()})
	return result


static func origins(s: GameState,civ: Civ) -> Array[Vector3i]:
	var result:=colonies(s,civ)
	for ship in Signals.reported_ships(s,civ):
		if ship.kind in [Ship.STARSHIP,Ship.WANDERING_EARTH] and not result.has(ship.cell()):
			result.append(ship.cell())
	return result


static func in_vision(s: GameState,civ: Civ,pos: Vector3) -> bool:
	var known:=presentation(s,civ)
	return known.in_own_vision(known.civs[s.civs.find(civ)],pos)


static func research(civ: Civ) -> Dictionary:
	for report in civ.order_reports.values():
		if report["category"]=="research" and report.get("status","") not in ["completed","failed","destroyed","cancelled"]:
			return report
	return {}


## 玩家已知状态维持不变时的一年收支估算，不查询远端实际产出或在途回报。
static func economy_preview(s: GameState,civ: Civ) -> Dictionary:
	var view := presentation(s,civ)
	var me: Civ = view.civs[s.civs.find(civ)]
	me.maintenance_priority.assign(civ.maintenance_priority)
	me.stopped_packages.assign(civ.stopped_packages)
	me.flow_remainder.assign(civ.flow_remainder)
	for cell in me.colonies:
		if site(s,civ,cell).get("colonial",false):
			me.colonial[cell] = true
	var plan := Economy.plan(view,me)
	var upkeep := [0.0,0.0]
	for item in plan["items"]:
		if not plan["active"].get(item["key"],false) or (item["parent"]!="" and not plan["active"].get(item["parent"],false)):
			continue
		for i in 2:
			upkeep[i] += item["upkeep"][i]
	var prepaid := [0.0,0.0]
	for order in OrderControl.visible(s,civ):
		for i in 2:
			prepaid[i] += WorkOrder.amount(order["paid"][i])
	var ammo := [0.0,0.0]
	var remote_ammo := false
	for ship in Signals.reported_ships(s,civ):
		if local(s,civ,ship.pos):
			for i in 2:
				ammo[i] += WorkOrder.amount(ship.ammo_reserved[i])
		elif ship.armed():
			remote_ammo = true
	return {"net":plan["net"],"gross":[plan["net"][0]+upkeep[0],plan["net"][1]+upkeep[1]],
		"upkeep":upkeep,"prepaid":prepaid,"ammo":ammo,"remote_ammo":remote_ammo}


static func scan_source(s: GameState,civ: Civ) -> Dictionary:
	var original:=entity(s,civ,civ.original_anchor_id)
	if not original.is_empty():
		return original
	for ship in Signals.reported_ships(s,civ):
		if ship.kind==Ship.WANDERING_EARTH:
			return {"id":ship.id,"pos":ship.pos,"ship":ship}
	return {}


## 原画面的只读投影。交互仍调用真实GameState的公共命令接口；投影中没有未知远端真值。
static func presentation(s: GameState,civ: Civ) -> GameState:
	var view:=GameState.new()
	for field in ["dimension","space_epoch","visual_offset","turn","clock","winner","spectator","play_on_after_death","seed_value","dev_used"]:
		view.set(field,s.get(field))
	# 完成全世界换图后的坐标系是共同规则；局部前沿中心只能由观测报告提供。
	view.flat_plane=s.map.origin.z if s.dimension<=2 else -1
	view.line_y=s.map.origin.y if s.dimension==1 else -1
	view.map=StarMap.new()
	view.map.origin=s.map.origin
	view.map.extent=s.map.extent
	view.cell_ids=s.cell_ids.duplicate()
	view.light.resize(s.map.extent.x*s.map.extent.y*s.map.extent.z)
	view.light.fill(1.0)
	for other in s.civs:
		var copy:=Civ.new(other.name,other.is_ai,Vector3i.ZERO)
		copy.colonies.clear()
		copy.alive=true
		view.civs.append(copy)
	var me: Civ=view.civs[s.civs.find(civ)]
	for field in ["home","alive","telescope","actions_left","energy_millis","mineral_millis","antimatter","dimension_ammo","reduced","line_reduced","reduce_left","times_hit"]:
		me.set(field,civ.get(field))
	for field in ["techs","intel","known","heard","record_hits","record_empty","sightings","alerts","hit_dirs","telemetry","site_reports","payload_reports","order_reports","command_pending"]:
		me.set(field,civ.get(field).duplicate(true))
	me.foils=civ.foils.duplicate()
	me.colonies=colonies(s,civ)
	me.assets=assets(s,civ).duplicate(true)
	for ship in Signals.reported_ships(s,civ):
		var copy:=Ship.make(ship.kind,ship.pos,ship.id)
		for field in Signals.ship_status(ship):
			if field in copy:
				if copy.get(field) is Array:
					copy.get(field).assign(ship.get(field))
				else:
					copy.set(field,ship.get(field))
		me.ships.append(copy)
	for cell in me.colonies:
		var known:=site(s,civ,cell)
		me.intel[cell]=known.get("snapshot",{}).duplicate(true)
		for field in ["miners","advanced_miners","dysons"]:
			if known.get(field,0)>0:
				me.get(field)[cell]=known[field]
		for pair in [["bunker","bunkers"],["broadcaster","broadcasters"],["grain","grains"],["dormant","dormant_colonies"]]:
			if known.get(pair[0],false):
				me.get(pair[1])[cell]=true
		if known.get("warning",-1)>=0:
			me.warnings[cell]=known["warning"]
	me.has_warning=not me.warnings.is_empty()
	me.warning_level=me.warnings.get(me.home,0)
	for cell in me.intel:
		if not view.map.contains(cell):
			continue
		var info: Dictionary=me.intel[cell]
		view.map.stars[cell]=info.get("stars",StarMap.Star.NONE)
		view.map.rocky[cell]=info.get("rocky",0)
		view.map.gas[cell]=info.get("gas",0)
		if info.get("habitable",false):
			view.map.habitable[cell]=true
		view.system_cells.append(cell)
		view.light[view.light_index(cell)]=info.get("relative_light",1.0)
		view.cell_dims[view.cell_ids.get(cell,-1)]=info.get("cell_dim",s.dimension)
		if info.get("cell_dim",s.dimension)<s.dimension:
			if s.dimension==3:
				view.flattened[cell]=0
			elif s.dimension==2:
				view.linearized[cell]=0
	for report in civ.front_reports.values():
		if report["epoch"]!=s.space_epoch:
			continue
		var zone: Dictionary=report["data"].duplicate(true)
		zone["age"]+=maxf(0.0,s.clock-report["t_observed"])*Balance.FOIL_SPREAD*s.background_light()/s.physical_cell_size()
		if report["front_type"]=="foil":
			view.foil_zones.append(zone)
		elif report["front_type"]=="line":
			view.line_zones.append(zone)
	if not view.foil_zones.is_empty():
		view.flat_plane=int(DimensionSpace.Layout.base_plane(DimensionSpace.zone_origins(view.foil_zones)).z)
	if not view.line_zones.is_empty():
		view.line_y=int(DimensionSpace.Layout.base_plane(DimensionSpace.zone_origins(view.line_zones),true).y)
	for report in civ.broadcast_reports.values():
		var wave: Dictionary=report.duplicate(true)
		wave["sender"]=me
		wave["radius"]=maxf(0.0,s.clock-wave["sent"])*s.background_light()/s.physical_cell_size()
		view.broadcasts.append(wave)
	for ends in civ.wake_reports.values():
		if not ends.has(0) or not ends.has(1):
			continue
		me.wakes_seen[view.wakes.size()]=true
		view.wakes.append({"a":ends[0]["data"]["pos"],"b":ends[1]["data"]["pos"],
			"turn":mini(ends[0]["data"]["turn"],ends[1]["data"]["turn"]),"gone":false})
	return view


## 使用已收到的位置和环境预测，未知区域按背景空间外推，不能查询未来航段的真值。
static func predict_path(s: GameState,civ: Civ,ship: Ship,years: int) -> Array[Vector3]:
	var points: Array[Vector3]=[ship.pos]
	if not ship.moving():
		return points
	var view:=presentation(s,civ)
	var me: Civ=view.civs[s.civs.find(civ)]
	var moving:=Ship.make(ship.kind,ship.pos,ship.id)
	for key in Signals.ship_status(ship):
		if key in moving:
			if moving.get(key) is Array:
				moving.get(key).assign(ship.get(key))
			else:
				moving.set(key,ship.get(key))
	for year in years:
		var remaining:=1.0
		while remaining>Balance.TIME_EPSILON:
			if moving.slow_start and not Kinematics.in_owned_system_vision(view,me,moving.pos):
				moving.slow_start=false
			var motion:=Kinematics.motion(view,me,moving,remaining)
			# 和正式时钟一样跨过有限精度的限速边界；不能在 cap_time≈0 时永久停住预览。
			var dt:=minf(remaining,maxf(Balance.TIME_EPSILON,minf(Balance.PHYSICS_MAX_DT,minf(motion["cap_time"],motion["arrival"]))))
			moving.pos=Kinematics.position(motion,dt)
			moving.speed=motion["speed"]+motion["acceleration"].length()*view.physical_cell_size()*dt
			view.clock+=dt
			remaining-=dt
			if motion["arrival"]<=dt+Balance.TIME_EPSILON:
				points.append(moving.pos)
				return points
		points.append(moving.pos)
		if Ship.outside(moving.pos,view.map.bounds()):
			break
	return points
