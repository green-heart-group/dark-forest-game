class_name OrderControl
extends RefCounted
## 工程先托管预算，宿主收到开工命令后才工作。取消和状态沿同一条信息链路返回。


static func find(civ: Civ, id: int) -> Dictionary:
	for project in WorldTime.orders(civ):
		if project["id"] == id:
			return project
	return {}


static func host(s: GameState, civ: Civ, project: Dictionary) -> Dictionary:
	var id: int = project.get("host_id",project["host_ship"])
	if id < 0:
		var anchors := Assets.at(civ,"anchor",project["at"])
		if anchors.is_empty():
			return {}
		id = anchors[0]["id"]
	return Signals.entity(s,s.civs.find(civ),id)


static func submit(s: GameState, civ: Civ, project: Dictionary) -> void:
	Assets.ensure(s,civ)
	var id: int=project.get("host_id",project["host_ship"])
	var known:=Knowledge.entity(s,civ,id) if id>=0 else Knowledge.anchor(s,civ,project["at"])
	project["command_ready"] = false
	project["status"] = "sent"
	if not known.is_empty():
		project["host_id"]=known["id"]
	if Balance.HOME_BUILD_SLOTS>Balance.BUILD_SLOTS:
		project["queue_id"]=s.construction_queue_id(civ,project["at"],project["host_ship"])
	civ.order_reports[project["id"]] = project.duplicate(true)
	if not known.is_empty():
		s.queue_entity_command(civ,known["id"],known["pos"],{"name":"activate_project","project":project["id"]},[0,0],false)


static func activate(s: GameState, civ: Civ, id: int) -> bool:
	var project := find(civ,id)
	if project.is_empty():
		return false
	if not s.project_host_alive(civ,project):
		discard(s,civ,project,"destroyed")
		return false
	var error:=physical_error(s,civ,project)
	if error!="":
		project["failure_reason"]=error
		discard(s,civ,project,"failed")
		return false
	var target := civ.ship_by_id(project.get("target_ship",project["host_ship"] if project["kind"]=="landing" else -1))
	if project["kind"]=="landing":
		if target==null or target.dead or target.work_locked or not target.waiting() or target.cell()!=project["at"] or not s.can_settle(project["at"]):
			discard(s,civ,project,"failed")
			return false
	if project["category"]=="refit":
		var physical := host(s,civ,project)
		if target==null or target.dead or target.work_locked or not target.waiting() or physical.is_empty() or target.pos.distance_to(physical["pos"])*s.physical_cell_size()>Balance.COLLISION_EPSILON:
			discard(s,civ,project,"failed")
			return false
	if target!=null:
		target.work_locked = true
	project["command_ready"] = true
	project["status"] = "working"
	report(s,civ,project,"working")
	return true


## 宿主实际接到命令或继续施工时的物理检查。不得用于玩家/AI的下令可用性判断。
static func physical_error(s: GameState,civ: Civ,project: Dictionary) -> String:
	var at: Vector3i=project["at"]
	var kind: String=project["kind"]
	match project["category"]:
		"upgrade":
			if kind=="warning" and (not civ.warnings.has(at) or civ.warnings[at]>=Balance.WARNING_MAX):
				return "预警设施已不存在或已达上限"
		"miner_refit":
			if civ.miners.get(at,0)<1 or s.map.rocky.get(at,0)<=0:
				return "待改装矿船或矿点已不存在"
		"refit":
			var target:=civ.ship_by_id(project["target_ship"])
			if target==null or target.dead:
				return "待改装舰已毁"
			for module in project["modules"]:
				if target.modules.has(module):
					return "模块已经安装"
		"build":
			match kind:
				"miner","advanced_miner":
					if not civ.owns(at) or s.map.rocky.get(at,0)<=0:
						return "本地真实矿点已不存在"
					var count: int=civ.miners.get(at,0)+civ.advanced_miners.get(at,0)
					if count>=(Balance.MAX_MINERS if civ.has_tech("mining_advanced") else Balance.BASE_MINER_LIMIT):
						return "本地矿船已达上限"
				"dyson":
					if civ.dysons.get(at,0)>=StarMap.star_count(s.map.star_at(at)):
						return "本地恒星或空闲戴森位置已不存在"
				"bunker":
					if s.map.gas.get(at,0)<=0 or civ.bunkers.has(at):
						return "本地类木行星不存在或已有掩体"
				"broadcaster":
					if s.map.star_at(at)==StarMap.Star.NONE or civ.broadcasters.has(at):
						return "本地恒星不存在或已有广播器"
				"warning":
					if civ.warnings.has(at):
						return "本地已有预警系统"
				"grain":
					if civ.grains.has(at):
						return "本地已有光粒"
				"warship":
					if civ.count(Ship.WARSHIP)>=(3 if civ.has_tech("shield") else 2):
						return "战舰已达当前上限"
				"starship":
					if civ.starship_ever_built or civ.has_starship():
						return "整局星舰额度已使用或已有移动锚点"
				"wandering_earth":
					return EarthTransform.error(s,civ,project.get("earth_roster",[]),project.get("earth_rocky",1))
				"landing":
					if not s.can_settle(at) or not s.landing_site_survives(civ.ship_by_id(project["host_ship"]),at):
						return "落地点已不再可殖民"
	return ""


static func report(s: GameState, civ: Civ, project: Dictionary, status: String) -> void:
	var physical := host(s,civ,project)
	var origin: Vector3 = physical.get("pos",Vector3(project["at"]))
	var data: Dictionary = project.duplicate(true)
	data["status"] = status
	Signals.send(s,s.civs.find(civ),origin,Signals.controller(civ),"report",{"type":"order","data":data,
		"t_observed":s.clock,"source_id":project.get("host_id",-1),"epoch":s.space_epoch})


static func discard(s: GameState, civ: Civ, project: Dictionary, status: String) -> void:
	# 正式Word第9页：宿主接受开工后的落地失效烧毁托管；未开工拒绝仍可退款。
	if status=="failed" and project["kind"]=="landing" and project.get("command_ready",true):
		status = "destroyed"
	if status=="failed":
		project["failure_refund"]=project["refundable"].duplicate()
	report(s,civ,project,status)
	if civ.conversions.has(project["id"]):
		civ.conversions[project["id"]]["status"] = status
	var target := civ.ship_by_id(project.get("target_ship",project["host_ship"] if project["kind"]=="landing" else -1))
	if target!=null:
		target.work_locked = false
	civ.pending.erase(project)
	if civ.research_project.get("id",-1)==project["id"]:
		civ.research_project = {}


static func cancel(s: GameState, civ: Civ, id: int) -> Array:
	var project := find(civ,id)
	if project.is_empty() or not s.project_host_alive(civ,project):
		return [0,0]
	# 只在远端实际执行时核对；已失效的落地项目不能抢在施工检查前取回托管。
	if project["kind"]=="landing" and project.get("command_ready",true):
		var error := physical_error(s,civ,project)
		if error!="":
			project["failure_reason"] = error
			discard(s,civ,project,"failed")
			return [0,0]
	var refund := WorkOrder.refund(project)
	discard(s,civ,project,"cancelled")
	return [WorkOrder.units(refund[0]),WorkOrder.units(refund[1])]


static func visible(s: GameState,civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in civ.order_reports:
		var report: Dictionary = civ.order_reports[id]
		if report.get("status","") not in ["completed","cancelled","failed","destroyed"]:
			result.append(report)
	result.sort_custom(func(a,b):return a["id"]<b["id"])
	return result
