class_name R4State
extends RefCounted
## r4对局入口：所有界面/AI行动共用校验、付费和队列。物理和情报另行推进。
const Config := preload("res://rules/r4/config.gd")
const Ledger := preload("res://rules/r4/ledger.gd")
const Space := preload("res://rules/r4/space.gd")
var config: R4Config
var space: R4Space
var seed_value := 0
var now := 0.0
var round_index := 0
var terminal_reason := ""
var winners: Array = []
var civs: Array[Dictionary] = []
var entities: Dictionary = {}
var messages: Array[Dictionary] = []
var scheduled_messages: Array[Dictionary] = []
var scheduled_deadlines: Dictionary = {}
var scheduled_groups: Dictionary = {}
var projectiles: Array[Dictionary] = []
var broadcasts: Array[Dictionary] = []
var scans: Array[Dictionary] = []
var events: Array[Dictionary] = []
var history: Array[Dictionary] = []
var state_hashes: Array[String] = []
var counters: Dictionary = {}
var last_remap := -INF
var capture_events := true
var initialized_sensors := false
var last_performance := {}
var last_physics_substeps := 0
var last_physics_profile: Array = []
var plain_checks := false
var finance_cache: Dictionary = {}

func invalidate_income(ci: int) -> void:
	finance_cache.erase(ci)

func _init(seed_id := 0, profile := "C", civilization_count := 5) -> void:
	seed_value = seed_id
	config = Config.new(profile)
	space = Space.new(config,seed_id)
	# 复用未改生成器/出生点挑选，使A/B/C的同一种子仍指相同的地图和母星位置。
	var original := GameState.new_game(seed_id,civilization_count-1,true)
	for ci in civilization_count:
		var old_home: Vector3i = original.civs[ci].home
		var cell := (old_home.x*9+old_home.y)*9+old_home.z
		space.cells[cell].stars = maxi(config.economy.start.home_stars_min,space.cells[cell].stars)
		space.cells[cell].rocky = maxi(config.economy.start.home_terrestrial_planets_min,space.cells[cell].rocky)
		space.cells[cell].habitable = true
		var ledger := Ledger.new()
		ledger.stock = Ledger.amount(config.economy.start.stock_M,config.economy.start.stock_E)
		var civ := {"id":ci,"alive":true,"ledger":ledger,"techs":{},"permissions":{0:true},"event_flags":{},
			"ap":int(config.economy.scale.action_points_per_turn),"home":-1,"radio":0,"warning_level":0,
			"seen":{},"known_cells":{},"coverage":{},"alerts":{},"emergency_round":-1,"built_starship":false,
			"scan_ready":0.0,"domain_ready":0.0,"first":{},"gross":Vector2.ZERO,"net":Vector2.ZERO,
			"reference_net":Vector2.ZERO,"strategy":"balanced","ai":true,"research_project":-1,
			"cleared":{},"paid_receipts":{},"last_effective":0.0,"quiet_rounds":0}
		civ["finance_residual"]={}
		civ["last_order_round"]={}
		for id in config.catalog:
			if config.catalog[id].initial: civ.techs[id]=true
		civs.append(civ)
		var home := create_entity(ci,"home",cell)
		civ.home = home.id
		home.original_home = true
		space.cells[cell].owner = ci
		remember(ci,home)
		remember_cell(ci,cell)

func next_id(owner := -1) -> int:
	var serial: int = counters.get(owner,0)+1
	counters[owner]=serial
	return (owner+2)*1000000+serial

func log_event(kind: String, owner: int, data: Dictionary = {}) -> void:
	if not capture_events: return
	var item := {"kind":kind,"civ":owner,"t":now,"round":round_index,"epoch":space.world_epoch}
	item.merge(data,true)
	events.append(item)

func first_use(owner: int, id: String, effect: String, entity := -1) -> void:
	var key := "use:"+id
	if not civs[owner].first.has(key):
		civs[owner].first[key]=now
		log_event("technology_first_use",owner,{"technology":id,"use":effect,"entity":entity})
	var effective := effect in ["hit","planet_consumed","colony_established","stellar_hit","front_unfolded","domain_activated","income_generated","scan_echo","broadcast_received","damage_prevented","shield_repair","warp_movement","survival_anchor_added","entity_adapted","dispatch_energy_discount"]
	if effective and not civs[owner].first.has("effect:"+id):
		civs[owner].first["effect:"+id]=now
		log_event("technology_first_effect",owner,{"technology":id,"effect":effect,"entity":entity})
	civs[owner].last_effective=now

func create_entity(owner: int, kind: String, cell: int, basis := Vector2i.ZERO, modules: Array = [], host := -1) -> Dictionary:
	invalidate_income(owner)
	var entity := {"id":next_id(owner),"owner":owner,"kind":kind,"cell":cell,"pos":space.position_for(cell),
		"dim":maxi(1,space.cells[cell].dim),"alive":true,"online":true,"priority":0,"host":host,"modules":modules.duplicate(),
		"paid_basis":basis,"receipts":{},"ready":{},"hp":float(config.physics.hp.get(kind,1)),"damage":0.0,
		"direction":Vector3.ZERO,"target":space.position_for(cell),"target_id":-1,"target_cell":cell,"speed":0.0,
		"accel_used":0.0,"moving":false,"born":now,"traveled":0.0,"fired_round":-1,"last_combat":-INF,
		"repair_time":0.0,"paused_until":0.0,"contacted":{},"original_home":false,"attached":kind in ["miner_basic","miner_advanced","warning"],
		"occupation":{},"payload_dim":space.world_dim,"spent":false,"forced_dormant":false}
	if kind=="dyson":
		var used: Array = []
		for existing in owned_entities(owner,"dyson"):
			if existing.cell==cell: used.append(existing.get("star_slot",0))
		var slot := 0
		while used.has(slot): slot+=1
		entity["star_slot"]=slot
	if kind=="battleship":
		entity.hp=max_hp(entity)
	entities[entity.id]=entity
	return entity

func max_hp(e: Dictionary) -> float:
	if e.kind!="battleship": return float(config.physics.hp.get(e.kind,1))
	if e.modules.has("106"): return config.physics.field_hp
	if e.modules.has("013"): return config.physics.armor_hp
	return config.physics.hp.battleship

func owned_entities(ci: int, kind := "") -> Array:
	var result: Array = []
	for e in entities.values():
		if e.alive and e.owner==ci and (kind=="" or kind==e.kind): result.append(e)
	result.sort_custom(func(a,b): return a.id<b.id)
	return result

func anchors(ci: int) -> Array:
	return owned_entities(ci).filter(func(e): return e.kind in Config.ANCHORS)

func command_anchor(ci: int) -> Dictionary:
	if entities.has(civs[ci].home) and entities[civs[ci].home].alive: return entities[civs[ci].home]
	var alive := anchors(ci)
	return {} if alive.is_empty() else alive[0]

func remember(ci: int, e: Dictionary) -> void:
	var observation := e.duplicate(true)
	observation["t_observed"]=now
	observation["epoch"]=space.world_epoch
	civs[ci].seen[e.id]=observation

func remember_cell(ci: int, cell: int) -> void:
	var observation: Dictionary = space.cells[cell].duplicate(true)
	observation["t_observed"]=now
	observation["epoch"]=space.world_epoch
	observation["pos"]=space.position_for(cell)
	civs[ci].known_cells[cell]=observation

func observed_owned(ci: int, id: int) -> Dictionary:
	var info: Dictionary = civs[ci].seen.get(id,{})
	return info if info.get("owner",-1)==ci and info.get("alive",false) else {}

func observation_position(record: Dictionary) -> Vector3:
	var from_dim: int = 3-int(record.get("epoch",space.world_epoch))
	if from_dim==space.world_dim: return record.pos
	return space.remap_point(record.pos,from_dim,space.world_dim)

func navigation_years(record: Dictionary, distance: float, dim: int) -> float:
	# A forecast from a received record and public background c; it does not
	# consult hidden fields or the current position of a remote entity.
	if not config.physics.motion.has(record.kind): return INF
	var p: Array = config.physics.motion[record.kind]
	var background: float = config.c(mini(dim,record.dim))
	var cap: float = minf(p[1],background)
	if record.kind=="sophon": cap=p[1]*background
	var speed: float = minf(cap,record.get("speed",0.0))
	if record.kind=="probe_basic": speed=minf(p[3],background)
	var burn: float = INF if p[2]<0.0 else maxf(0.0,p[2]-record.get("accel_used",0.0))
	var acceleration: float = p[0]
	var accelerating: float = minf(burn,(cap-speed)/acceleration) if acceleration>0.0 else 0.0
	var accelerating_distance := speed*accelerating+0.5*acceleration*accelerating*accelerating
	if distance<=accelerating_distance and acceleration>0.0:
		return (sqrt(speed*speed+2.0*acceleration*distance)-speed)/acceleration
	var coast_speed := minf(cap,speed+acceleration*accelerating)
	return accelerating+(distance-accelerating_distance)/coast_speed if coast_speed>0.0 else INF

func movement_cost(ci: int, kind: String) -> Vector2i:
	if kind in ["transport","probe_basic","probe_nuclear"]: return Vector2i.ZERO
	var tech: Dictionary = civs[ci].techs
	if tech.has("301"): return Vector2i.ZERO
	var cost: float = config.economy.actions.ordinary_fleet_launch_or_turn_E
	for id in ["009","102"]:
		if tech.has(id): cost-=config.economy.actions[id+"_discount_E"]
	return Ledger.amount(0,maxf(0,cost))

func project_count(ci: int, item: String, cell := -1) -> int:
	var count := 0
	for p in civs[ci].ledger.projects.values():
		if p.metadata.get("item","")==item and (cell<0 or entities.get(p.host,{}).get("cell",-1)==cell): count+=1
	return count

func observed_count(ci: int, kind: String, cell := -1) -> int:
	var count := 0
	for e in civs[ci].seen.values():
		if e.alive and e.owner==ci and e.kind==kind and (cell<0 or e.cell==cell): count+=1
	return count

func action_error(ci: int, request: Dictionary) -> String:
	if not terminal_reason.is_empty(): return "对局已结束"
	if ci<0 or ci>=civs.size() or not civs[ci].alive: return "文明已失去所有存续锚点"
	var c: Dictionary = civs[ci]
	if c.ap<=0: return "本回合行动点已用完"
	var kind: String = request.get("kind","")
	if kind=="cancel":
		return "" if c.ledger.projects.has(request.get("project",-1)) else "没有该在建项目"
	var host: Dictionary = observed_owned(ci,request.get("host",c.home))
	if host.is_empty(): return "没有已知存续的己方发令源"
	var item: String = request.get("item","")
	var cost := Vector2i.ZERO
	if kind=="operation":
		if host.kind not in Config.ANCHORS: return "运营优先级需要锚点"
	elif kind=="emergency":
		if host.kind not in Config.ANCHORS: return "应急作业需要存续锚点"
		if c.emergency_round==round_index: return "每文明每回合只能一次应急作业"
		if request.get("resource","") not in ["M","E"]: return "选择矿石或能量之一"
	elif kind=="research":
		if not config.catalog.has(item): return "不存在该科技"
		if c.techs.has(item): return "该科技已完成"
		if host.kind not in Config.ANCHORS: return "研究需要存续锚点"
		if c.research_project>=0: return "全局研究槽已占用"
		var node: Dictionary = config.catalog[item]
		if not c.permissions.has(int(node.tier)): return "发展权限未开放"
		for dep in node.dependencies:
			if not c.techs.has(dep): return "前置科技尚未完成："+dep
		if not host.online and item not in config.physics.rescue_research_ids: return "休眠救援槽仅进行基础/殖民研究"
		cost=config.price("technologies",item)
	elif kind=="build":
		if not Config.BUILD_TECH.has(item): return "不存在该建造项目"
		if not c.techs.has(Config.BUILD_TECH[item]): return "所需科技尚未研究"
		if item=="colony":
			if host.kind!="transport": return "需要已抵达宜居星系的运输船"
			var info: Dictionary = c.known_cells.get(host.cell,{})
			if not info.get("habitable",false) or info.get("rocky",0)<=0 or info.get("owner",-1)>=0: return "需要已观测的无主宜居星系"
			if host.moving: return "运输船尚未停泊"
		elif host.kind not in Config.ANCHORS: return "需要已完成的存续锚点/船坞"
		if host.kind in ["starship","wandering_earth"] and item in Config.CELESTIAL: return "移动船坞不能凭空建造天体设施"
		if not host.online and item not in ["transport","probe_basic"]: return "休眠救援槽只造裸运输船或廉价探测器"
		if not host.online and not request.get("modules",[]).is_empty(): return "救援船必须使用裸型"
		var cell_info: Dictionary = c.known_cells.get(host.cell,{})
		if item in ["miner_basic","miner_advanced"]:
			if cell_info.get("owner",-1)!=ci or cell_info.get("rocky",0)<=0: return "矿船需要己方可采矿星系"
			var capacity: int = config.physics.advanced_miner_cap if c.techs.has("008") else config.physics.basic_miner_cap
			var count := observed_count(ci,"miner_basic",host.cell)+observed_count(ci,"miner_advanced",host.cell)
			for p in c.ledger.projects.values():
				if p.host==host.id and p.metadata.get("item","") in ["miner_basic","miner_advanced"]: count+=1
			if count>=capacity: return "该星系矿船容量已满"
		if item=="stellar_broadcaster" and cell_info.get("stars",0)<=0: return "恒星广播器需要恒星"
		if item=="bunker" and cell_info.get("gas",0)<=0: return "掩体需要类木行星"
		if item in ["stellar_broadcaster","bunker","warning"] and observed_count(ci,item,host.cell)+project_count(ci,item,host.cell)>0: return "该星系已有或正在建造该设施"
		if item=="dyson" and observed_count(ci,item,host.cell)+project_count(ci,item,host.cell)>=cell_info.get("stars",0): return "没有空闲的己方恒星槽"
		if item=="battleship":
			var cap: int = config.physics.field_battleship_cap if c.techs.has("106") else config.physics.battleship_cap
			if observed_count(ci,item)+project_count(ci,item)>=cap: return "战舰容量已满"
		if item=="antimatter_bomb" and observed_count(ci,item)+project_count(ci,item)>=config.physics.bomb_cap: return "反物质库存/在建已达上限"
		if item=="starship" and (c.built_starship or project_count(ci,item)>0): return "整局只能完成一艘110星舰"
		if item=="starship" and (observed_count(ci,"wandering_earth")>0 or project_count(ci,"wandering_earth")>0): return "206存续或改造中时不能另造110星舰"
		if item=="wandering_earth":
			if not host.original_home or host.kind!="home": return "只能改造存续原母星"
			if observed_count(ci,"starship")>0 or project_count(ci,"starship")>0: return "星舰存续或在建时不能改造母星"
		cost=config.price("units",item)
		var selected_modules: Array = []
		for module in request.get("modules",[]):
			var err := module_error(ci,item,module,selected_modules)
			if err!="": return err
			selected_modules.append(module)
			cost+=config.price("ship_modules",module)
	elif kind=="refit":
		var module_error_text := module_error(ci,host.kind,item,host.modules)
		if module_error_text!="": return module_error_text
		cost=config.price("ship_modules",item)
	elif kind=="miner_refit":
		if not c.techs.has("008") or host.kind!="miner_basic": return "需要008和未升级矿船"
		cost=Ledger.amount(config.economy.upgrades.miner_refit.M,config.economy.upgrades.miner_refit.E)
	elif kind in ["radio","warning_upgrade"]:
		if host.kind not in Config.ANCHORS: return "升级需要存续锚点"
		var level: int = c.radio if kind=="radio" else c.warning_level
		if level>=config.economy.upgrades.max_radio_and_warning_upgrades: return "升级已达上限"
		var row: Dictionary = config.economy.upgrades.radio_telescope_upgrade_costs[level] if kind=="radio" else config.economy.upgrades.warning_upgrade_each
		cost=Ledger.amount(row.M,row.E)
	elif kind=="prepare":
		if host.kind not in Config.ANCHORS or host.dim<=1: return "没有可执行的下一维生存适配"
		var emergency: bool = request.get("emergency",false)
		if not emergency and not c.techs.has("302"): return "完整迁维需要302"
		var manifest: Array = request.get("manifest",[host.id])
		if manifest.is_empty() or not manifest.has(host.id): return "名册需包含执行锚点"
		var unique := {}
		for id in manifest:
			var e := observed_owned(ci,id)
			if e.is_empty() or e.dim!=host.dim or unique.has(id) or e.kind in Config.AMMUNITION: return "名册实体无效或重复"
			if emergency and id!=host.id and (e.kind not in ["miner_basic","miner_advanced"] or e.cell!=host.cell): return "紧急迁维仅保护锚点和同系矿船"
			unique[id]=true
		if emergency and manifest.size()>1+config.economy.dimension_conversion.emergency.get("max_same_system_miners",2): return "紧急迁维最多带两艘矿船"
		cost=migration_price(manifest.size(),emergency)
	elif kind=="convert":
		if host.dim<=1: return "奇异点不提供0D逃生"
		if not host.ready.has(str(host.dim)): return "该实体尚未收到适配完成通知"
	elif kind=="move":
		if host.kind not in Config.MOBILE: return "该实体不能移动"
		if not host.online: return "休眠实体不能进行普通机动"
		cost=movement_cost(ci,host.kind)
	elif kind=="broadcast":
		if not broadcast_capable(ci,host,true): return "此源没有可用广播设施"
		cost=Ledger.amount(0,config.economy.actions.broadcast_E)
	elif kind=="scan":
		if not c.techs.has("103") or not host.original_home: return "103只能由存续母星或206发射"
		if now<c.scan_ready: return "主动扫描仍在冷却"
		if (messages+scheduled_messages).any(func(m):return m.owner==ci and m.kind=="command" and m.payload.command.kind=="scan"): return "扫描命令仍在传输"
		cost=Ledger.amount(0,config.economy.actions.gravity_scan_E)
	elif kind=="domain":
		if not c.techs.has("303"): return "需要303"
		if now<c.domain_ready: return "黑域投放仍在冷却"
		cost=Ledger.amount(config.economy.actions.black_domain_deploy.M,config.economy.actions.black_domain_deploy.E)
	elif kind in ["launch","bomb"]:
		var ammunition := observed_owned(ci,request.get("ammunition",-1))
		if ammunition.is_empty() or ammunition.kind not in Config.AMMUNITION: return "没有已建成弹药"
		if kind=="bomb" and ammunition.kind!="antimatter_bomb": return "需要反物质炸弹"
		if ammunition.kind=="dimensional_weapon" and ammunition.payload_dim!=space.world_dim: return "等待世界完成当前一轮转换或改用本维载荷"
		if kind=="bomb" and host.kind not in Config.ANCHORS and host.kind!="battleship": return "反物质脉冲需要锚点或战舰"
	else: return "未知行动"
	if not c.ledger.can_pay(cost): return "当前可用库存不足"
	return ""

func module_error(ci: int, hull: String, module: String, installed: Array) -> String:
	if not config.economy.ship_modules.has(module) or not civs[ci].techs.has(module): return "模块科技未研究"
	if installed.has(module): return "模块已安装"
	if module=="205": return "" if hull in Config.WARP_HULLS else "该舰型不能选装曲率引擎"
	return "" if hull=="battleship" else "该模块只适用于恒星级战舰"

func broadcast_capable(ci: int, source: Dictionary, observed: bool) -> bool:
	if not source.get("online",false): return false
	if source.kind=="battleship": return source.modules.has("108")
	if source.kind not in ["home","colony"] and not source.original_home: return false
	if civs[ci].techs.has("108"): return true
	if source.kind not in ["home","colony"]: return false
	var available: Array = civs[ci].seen.values() if observed else entities.values()
	return available.any(func(e):return e.alive and e.owner==ci and e.cell==source.cell and e.kind=="stellar_broadcaster" and e.online)

func migration_price(n: int, emergency: bool) -> Vector2i:
	var p: Dictionary = config.physics.migration
	return Ledger.amount(p.emergency_M,p.emergency_E) if emergency else Ledger.amount(p.base_M+p.per_entity_M*n,p.base_E+p.per_entity_E*n)

func submit(ci: int, request: Dictionary) -> Dictionary:
	var error := action_error(ci,request)
	if error!="": return {"error":error}
	var c: Dictionary = civs[ci]
	var kind: String = request.kind
	var host_id: int = request.get("host",c.home)
	var item: String = request.get("item","")
	c.ap-=1
	history.append({"round":round_index,"t":now,"civ":ci,"request":request.duplicate(true)})
	if kind=="move": c.last_order_round[host_id]=round_index
	log_event("action_submitted",ci,{"action":kind,"item":item,"host":host_id})
	if kind=="cancel":
		var pid: int = request.project
		c.ledger.cancel(pid)
		if c.research_project==pid: c.research_project=-1
		return {"error":""}
	var host: Dictionary = entities.get(host_id,{})
	if kind=="emergency":
		c.emergency_round=round_index
		send_message(ci,"command",command_anchor(ci).get("pos",Vector3.ZERO),host_id,{"command":request.duplicate(true)})
		return {"error":""}
	if kind in ["research","build","refit","miner_refit","radio","warning_upgrade","prepare"]:
		var price := Vector2i.ZERO
		var work := 0.0
		if kind in ["research","build","refit"]:
			var section := "technologies" if kind=="research" else ("units" if kind=="build" else "ship_modules")
			price=config.price(section,item)
			work=config.work(section,item)
			if kind=="build":
				for module in request.get("modules",[]):
					price+=config.price("ship_modules",module)
					work+=config.work("ship_modules",module)
		elif kind=="prepare":
			var n: int = request.get("manifest",[host_id]).size()
			var emergency: bool = request.get("emergency",false)
			price=migration_price(n,emergency)
			work=config.physics.migration.emergency_work if emergency else config.physics.migration.base_work+ceilf(float(n)/config.physics.migration.entities_per_work)
		else:
			var row: Dictionary = config.economy.upgrades.miner_refit
			if kind=="radio": row=config.economy.upgrades.radio_telescope_upgrade_costs[c.radio]
			if kind=="warning_upgrade": row=config.economy.upgrades.warning_upgrade_each
			price=Ledger.amount(row.M,row.E)
			work=row.work
		var pid := next_id(ci)
		var metadata := request.duplicate(true)
		metadata["kind"]=kind
		metadata["arrived"]=host_id==command_anchor(ci).get("id",-1)
		metadata["arrived_at"]=now if metadata.arrived else INF
		metadata["from_dim"]=host.get("dim",3)
		assert(c.ledger.fund_project(pid,price,work,host_id,metadata))
		if kind=="research": c.research_project=pid
		if not metadata.arrived: send_message(ci,"project_order",command_anchor(ci).get("pos",Vector3.ZERO),host_id,{"project":pid})
		log_event("project_paid",ci,{"project":pid,"project_kind":kind,"item":item,"cost":price,"work":work,"host":host_id})
		return {"error":"","project":pid}
	var cost := Vector2i.ZERO
	if kind=="move": cost=movement_cost(ci,host.get("kind",""))
	if kind=="broadcast": cost=Ledger.amount(0,config.economy.actions.broadcast_E)
	if kind=="scan":
		cost=Ledger.amount(0,config.economy.actions.gravity_scan_E)
	if kind=="domain":
		cost=Ledger.amount(config.economy.actions.black_domain_deploy.M,config.economy.actions.black_domain_deploy.E)
		c.domain_ready=now+config.economy.actions.black_domain_deploy.cooldown_turns
	var command := request.duplicate(true)
	var message := send_message(ci,"command",command_anchor(ci).get("pos",Vector3.ZERO),host_id,{"command":command,"required_cost":cost})
	message["reservation"]="command:%d"%message.id
	assert(c.ledger.reserve_shot(message.reservation,cost))
	return {"error":""}

func send_message(owner: int, kind: String, origin: Vector3, target: int, payload: Dictionary, emission_time := -1.0) -> Dictionary:
	var moment: float = now if emission_time<0.0 else emission_time
	var msg := {"id":next_id(owner),"owner":owner,"kind":kind,"pos":origin,"target_id":target,"payload":payload.duplicate(true),
		"born":moment,"epoch":space.world_epoch,"traveled":0.0,"earliest":moment+config.physics.event_epsilon,"reservation":""}
	var receiver: Dictionary = entities.get(target,{})
	var fixed: bool = receiver.get("alive",false) and not receiver.get("moving",false)
	if receiver.get("attached",false) and entities.get(receiver.get("host",-1),{}).get("moving",false): fixed=false
	if fixed and space.uniform_dimension==space.world_dim and space.domains.is_empty() and space.wakes.is_empty():
		var delta: Vector3 = receiver.pos-origin
		var speed: float = config.c(space.world_dim)
		msg["flight"]={"start":moment,"origin":origin,"direction":delta.normalized(),"distance":delta.length(),"speed":speed,"arrival":maxf(msg.earliest,moment+delta.length()/speed)}
		push_scheduled(msg)
	else: messages.append(msg)
	return msg

static func flight_less(a: Dictionary, b: Dictionary) -> bool:
	return a.id<b.id if a.flight.arrival==b.flight.arrival else a.flight.arrival<b.flight.arrival

func push_scheduled(msg: Dictionary) -> void:
	var group := "critical"
	if passive_message(msg): group="info:"+str(msg.owner)
	elif msg.kind=="sensor_photon": group="combat:"+str(msg.target_id)
	scheduled_groups[msg.id]=group
	if not scheduled_deadlines.has(group): scheduled_deadlines[group]=[]
	var heap: Array = scheduled_deadlines[group]
	heap.append({"id":msg.id,"arrival":msg.flight.arrival})
	var position := heap.size()-1
	while position>0:
		var parent := (position-1)/2
		if not deadline_less(heap[position],heap[parent]): break
		var swap: Dictionary = heap[parent]; heap[parent]=heap[position]; heap[position]=swap
		position=parent
	scheduled_messages.append(msg)
	var index := scheduled_messages.size()-1
	while index>0:
		var parent := (index-1)/2
		if not flight_less(scheduled_messages[index],scheduled_messages[parent]): break
		var swap: Dictionary = scheduled_messages[parent]
		scheduled_messages[parent]=scheduled_messages[index]
		scheduled_messages[index]=swap
		index=parent

func passive_message(msg: Dictionary) -> bool:
	if msg.kind not in ["sensor_photon","sensor_report","warning_photon","warning","own_entity"]: return false
	var target: Dictionary = entities.get(msg.target_id,{})
	if target.get("kind","")!="battleship": return true
	# A warship may shoot upon receipt of an enemy observation. Its cell
	# geography and friendly records cannot introduce an enemy firing target.
	return msg.kind=="sensor_photon" and msg.payload.get("entities",[]).all(func(e):return e.owner==msg.owner)

func no_automatic_fire_left(entity: Dictionary) -> bool:
	return entity.get("fired_round",-1)==round_index or entity.get("armed_weapon","")==""

func pop_scheduled() -> Dictionary:
	var first: Dictionary = scheduled_messages[0]
	var group: String = scheduled_groups[first.id]
	var heap: Array = scheduled_deadlines[group]
	assert(heap[0].id==first.id,"secondary deadline heap is inconsistent")
	pop_deadline(heap)
	scheduled_groups.erase(first.id)
	var last: Dictionary = scheduled_messages.pop_back()
	if not scheduled_messages.is_empty():
		scheduled_messages[0]=last
		var index := 0
		while index*2+1<scheduled_messages.size():
			var child := index*2+1
			if child+1<scheduled_messages.size() and flight_less(scheduled_messages[child+1],scheduled_messages[child]): child+=1
			if not flight_less(scheduled_messages[child],scheduled_messages[index]): break
			var swap: Dictionary = scheduled_messages[index]
			scheduled_messages[index]=scheduled_messages[child]
			scheduled_messages[child]=swap
			index=child
	return first

static func deadline_less(a: Dictionary, b: Dictionary) -> bool:
	return a.id<b.id if a.arrival==b.arrival else a.arrival<b.arrival

static func pop_deadline(heap: Array) -> void:
	var last: Dictionary = heap.pop_back()
	if heap.is_empty(): return
	heap[0]=last
	var index := 0
	while index*2+1<heap.size():
		var child := index*2+1
		if child+1<heap.size() and deadline_less(heap[child+1],heap[child]): child+=1
		if not deadline_less(heap[child],heap[index]): break
		var swap: Dictionary = heap[index]; heap[index]=heap[child]; heap[child]=swap
		index=child

func materialize_message(msg: Dictionary, time: float) -> Dictionary:
	var result: Dictionary = msg.duplicate(true)
	if not result.has("flight"): return result
	var flight: Dictionary = result.flight
	var traveled: float = minf(flight.distance,maxf(0.0,time-flight.start)*flight.speed)
	result.pos=flight.origin+flight.direction*traveled
	result.traveled=traveled
	return result

func flush_scheduled_messages(time := -1.0, target_ids: Array = []) -> void:
	if time<0.0: time=now
	var previous := scheduled_messages.duplicate()
	scheduled_messages.clear()
	scheduled_deadlines.clear()
	scheduled_groups.clear()
	for msg in previous:
		if not target_ids.is_empty() and not target_ids.has(msg.target_id):
			push_scheduled(msg)
			continue
		var updated := materialize_message(msg,time)
		updated.erase("flight")
		messages.append(updated)

func message_count() -> int:
	return messages.size()+scheduled_messages.size()

func progress_projects(dt: float, interval_start := -INF) -> void:
	for c in civs:
		if not c.alive: continue
		var used_hosts := {}
		var project_ids: Array = c.ledger.projects.keys()
		project_ids.sort()
		for pid in project_ids:
			if not c.ledger.projects.has(pid): continue
			var p: Dictionary = c.ledger.projects[pid]
			var host: Dictionary = entities.get(p.host,{})
			if not host.get("alive",false):
				c.ledger.destroy_host(p.host)
				if c.research_project==pid: c.research_project=-1
				continue
			if not p.metadata.arrived: continue
			var research: bool = p.metadata.kind=="research"
			if not research and used_hosts.has(p.host): continue
			if not research: used_hosts[p.host]=true
			var efficiency := project_rate(p)
			if efficiency<=0.0: continue
			var active_dt: float = dt if not is_finite(interval_start) else clampf(now-maxf(interval_start,p.metadata.get("arrived_at",interval_start)),0.0,dt)
			if c.ledger.advance(pid,active_dt*efficiency): complete_project(c.id,pid)

func project_rate(project: Dictionary) -> float:
	var host: Dictionary = entities.get(project.host,{})
	if not host.get("alive",false) or not project.metadata.arrived: return 0.0
	var rate: float = config.work_factor(host.dim)
	if host.online: return rate
	var data: Dictionary = project.metadata
	var rescue: bool = (data.kind=="research" and data.item in config.physics.rescue_research_ids) or (data.kind=="build" and data.item in ["transport","probe_basic"] and data.get("modules",[]).is_empty())
	return rate*config.physics.dormant_work_factor if rescue else 0.0

func complete_project(ci: int, pid: int) -> void:
	invalidate_income(ci)
	var c: Dictionary = civs[ci]
	var p: Dictionary = c.ledger.take_completed(pid)
	if p.is_empty(): return
	var data: Dictionary = p.metadata
	var host: Dictionary = entities[p.host]
	var kind: String = data.kind
	var item: String = data.get("item","")
	log_event("project_complete",ci,{"project":pid,"project_kind":kind,"item":item,"host":host.id})
	if kind=="research":
		c.techs[item]=true
		c.research_project=-1
		log_event("technology_acquired",ci,{"technology":item,"mode":"paid"})
	elif kind=="build":
		if item=="colony":
			var cell: Dictionary = space.cells[host.cell]
			if cell.owner>=0 or not cell.habitable or cell.rocky<=0 or host.moving:
				log_event("landing_invalidated",ci,{"host":host.id,"project":pid})
				return
			host.alive=false
			cell.owner=ci
			var colony := create_entity(ci,item,cell.id,p.consumed)
			colony.dim=host.dim
			remember(ci,colony)
			remember_cell(ci,cell.id)
			first_use(ci,"109","colony_established",colony.id)
		elif item=="wandering_earth":
			host.kind=item
			host.hp=config.physics.hp.wandering_earth
			host.paid_basis+=p.consumed
			host["carried_rocky"]=1
			host.original_home=true
			# The carried home planet is removed from the stationary system.
			# Its miners travel with it; external stellar installations do not.
			var old_cell: Dictionary = space.cells[host.cell]
			old_cell.rocky=maxi(0,old_cell.rocky-1)
			old_cell.habitable=old_cell.rocky>0
			old_cell.owner=-1
			for child in owned_entities(ci):
				if child.host!=host.id or child.kind not in Config.CELESTIAL: continue
				child.attached=child.kind in ["miner_basic","miner_advanced"]
				if not child.attached:
					child.host=-1
					child.online=false
			remember_cell(ci,old_cell.id)
			remember(ci,host)
			first_use(ci,"206","home_converted",host.id)
		else:
			var e := create_entity(ci,item,host.cell,p.consumed,data.get("modules",[]),host.id)
			e.pos=host.pos
			e.dim=host.dim
			if item=="starship": c.built_starship=true
			if item=="starship": first_use(ci,"110","survival_anchor_added",e.id)
			if p.host==command_anchor(ci).get("id",-1): remember(ci,e)
			else: send_message(ci,"own_entity",host.pos,command_anchor(ci).get("id",-1),{"entity":e.duplicate(true),"t_observed":now})
			log_event("entity_constructed",ci,{"item":item,"entity":e.id,"modules":e.modules})
	elif kind in ["refit","miner_refit"]:
		if kind=="miner_refit": host.kind="miner_advanced"
		else: host.modules.append(item)
		host.paid_basis+=p.consumed
		host.hp=max_hp(host) # damage字段独立；提高HP上限不免费抹掉已受伤害。
		remember(ci,host)
		log_event("module_installed",ci,{"entity":host.id,"module":item})
	elif kind=="radio": c.radio+=1
	elif kind=="warning_upgrade": c.warning_level+=1
	elif kind=="prepare":
		var manifest: Array = data.get("manifest",[host.id])
		var prepared := {"from_dim":data.from_dim,"emergency":data.get("emergency",false),"auto":data.get("auto",true),"prepared_at":now,"project":pid}
		for id in manifest:
			if not entities.has(id) or not entities[id].alive: continue
			if id==host.id:
				entities[id].ready[str(data.from_dim)]=prepared.duplicate(true)
			else: send_message(ci,"adapt_ready",host.pos,id,{"prepared":prepared})
		log_event("adaptation_prepared",ci,{"manifest":manifest,"project":pid,"from_dim":data.from_dim})

func convert_entity(id: int, at_time: float) -> bool:
	var e: Dictionary = entities.get(id,{})
	if e.is_empty() or not e.alive or e.dim<=1 or not e.ready.has(str(e.dim)): return false
	var prep: Dictionary = e.ready[str(e.dim)]
	if prep.get("received_at",prep.prepared_at)>=at_time-config.physics.event_epsilon: return false
	var ci: int = e.owner
	invalidate_income(ci)
	var from: int = e.dim
	var receipt := "%d:%d>%d"%[ci,from,from-1]
	var retention: float = config.physics.migration.emergency_retention if prep.emergency else config.physics.migration.complete_retention
	if civs[ci].ledger.receipts.has(receipt): retention=civs[ci].ledger.receipts[receipt]
	if civs[ci].ledger.apply_receipt(receipt,retention,civs[ci].ledger.projects.keys()):
		for asset in owned_entities(ci):
			if not asset.receipts.has(receipt):
				asset.paid_basis=Ledger.scaled(asset.paid_basis,retention)
				asset.receipts[receipt]=true
		log_event("stock_conversion_receipt",ci,{"receipt":receipt,"retention":retention,"trigger_entity":id})
	# A newly built higher-dimensional asset may be prepared after the first
	# receipt. Its own basis still loses value once; past stocks never pay again.
	if not e.receipts.has(receipt):
		e.paid_basis=Ledger.scaled(e.paid_basis,retention)
		e.receipts[receipt]=true
	e.dim-=1
	e.ready.erase(str(from))
	if not prep.emergency: first_use(ci,"302","entity_adapted",id)
	log_event("entity_dimension_entered",ci,{"entity":id,"dim":e.dim,"receipt":receipt})
	return true

func destroy_entity(id: int, cause: String, killer := -1) -> void:
	if not entities.has(id) or not entities[id].alive: return
	var e: Dictionary = entities[id]
	invalidate_income(e.owner)
	e.alive=false
	var c: Dictionary = civs[e.owner]
	c.ledger.destroy_host(id)
	if c.research_project>=0 and not c.ledger.projects.has(c.research_project): c.research_project=-1
	if e.kind in ["home","colony"]:
		space.cells[e.cell].owner=-1
		for dependent in owned_entities(e.owner):
			if dependent.host==id and dependent.kind in Config.CELESTIAL: destroy_entity(dependent.id,cause,killer)
	elif e.kind=="wandering_earth":
		for dependent in owned_entities(e.owner):
			if dependent.host==id and dependent.attached: destroy_entity(dependent.id,cause,killer)
	log_event("entity_destroyed",e.owner,{"entity":id,"item":e.kind,"cause":cause,"killer":killer})
	# 公共中央账本不附带远方死亡原因；战场报告由情报系统沿物理路径发送。

func check_terminal() -> void:
	for c in civs:
		if c.alive and anchors(c.id).is_empty():
			c.alive=false
			log_event("civilization_eliminated",c.id,{"cause":"no_survival_anchor"})
			messages=messages.filter(func(m): return m.owner!=c.id or m.kind not in ["command","project_order"])
	var survivors: Array = []
	for c in civs:
		if c.alive: survivors.append(c.id)
	if survivors.size()<=1:
		winners=survivors
		terminal_reason="last_survival_anchor" if survivors.size()==1 else "simultaneous_extinction_draw"

func reference_and_income(ci: int, dt := 1.0, settle := true) -> Dictionary:
	if not plain_checks and finance_cache.has(ci) and now<finance_cache[ci].expires:
		return settle_income(ci,dt,settle,finance_cache[ci].packages,finance_cache[ci].mine)
	var c: Dictionary = civs[ci]
	var packages: Array = []
	var mine := owned_entities(ci)
	for anchor in mine:
		if anchor.kind not in Config.ANCHORS: continue
		var nominal := Vector2.ZERO
		var actual := Vector2.ZERO
		var upkeep := Vector2.ZERO
		var child_ids: Array = []
		var cell: Dictionary = space.cells[anchor.cell]
		var stationary: bool = anchor.kind in ["home","colony"] and cell.owner==ci
		if stationary:
			nominal.y+=cell.rocky*config.economy.production["002_E_per_owned_terrestrial"]
			if c.techs.has("009"): nominal.y+=cell.stars*config.economy.production["009_E_per_owned_star"]
		if anchor.kind=="wandering_earth": nominal.y+=anchor.get("carried_rocky",1)*config.economy.production["002_E_per_owned_terrestrial"]
		actual+=nominal*config.q(anchor.dim)
		if config.economy.units.has(anchor.kind):
			var row: Dictionary = config.economy.units[anchor.kind]
			upkeep+=Vector2(row.upkeep_M,row.upkeep_E)
		for e in mine:
			if e.host!=anchor.id or e.kind not in Config.CELESTIAL: continue
			child_ids.append(e.id)
			if not stationary and not (anchor.kind=="wandering_earth" and e.attached): continue
			var row: Dictionary = config.economy.units[e.kind]
			var output := Vector2(row.gross_M,row.gross_E)
			nominal+=output
			actual+=output*config.q(e.dim)
			upkeep+=Vector2(row.upkeep_M,row.upkeep_E)
		packages.append({"id":anchor.id,"gross_rate":actual,"upkeep_rate":upkeep,"priority":anchor.priority,"nominal":nominal-upkeep,"gross_nominal":nominal,"force_off":anchor.forced_dormant,"children":child_ids})
	for e in mine:
		if e.kind in Config.ANCHORS or e.kind in Config.CELESTIAL or e.kind in Config.AMMUNITION: continue
		if not config.economy.units.has(e.kind): continue
		var row: Dictionary = config.economy.units[e.kind]
		var upkeep := Vector2(row.upkeep_M,row.upkeep_E)
		packages.append({"id":e.id,"gross_rate":Vector2.ZERO,"upkeep_rate":upkeep,"priority":e.priority+1,"nominal":-upkeep,"gross_nominal":Vector2.ZERO})
	# 102/301从已返回且尚有效的覆盖获取收入，不直接查询远方当前地图。
	var info_gross := 0.0
	var info_nominal := 0.0
	if c.techs.has("102"):
		for coverage in c.coverage.values():
			if coverage.expires<=now or not coverage.get("was_system",false): continue
			var energy: float = config.economy.production["102_E_per_currently_covered_unique_system"]
			if c.techs.has("301") and coverage.stars==0: energy+=config.economy.production["301_extra_E_per_currently_covered_starless_system"]
			info_nominal+=energy
			info_gross+=energy*config.q(maxi(1,coverage.dim))
	if info_gross>0:
		packages.append({"id":-ci-1,"gross_rate":Vector2(0,info_gross),"upkeep_rate":Vector2.ZERO,"priority":-1,"nominal":Vector2(0,info_nominal),"gross_nominal":Vector2(0,info_nominal)})
	var expires := INF
	if c.techs.has("102"):
		for coverage in c.coverage.values():
			if coverage.expires>now: expires=minf(expires,coverage.expires)
	finance_cache[ci]={"packages":packages,"mine":mine,"expires":expires}
	return settle_income(ci,dt,settle,packages,mine)

func settle_income(ci: int, dt: float, settle: bool, packages: Array, mine: Array) -> Dictionary:
	var c: Dictionary = civs[ci]
	var gross_total := Vector2.ZERO
	var reference := Vector2.ZERO
	# 保留不足0.001的累积余数，不能因为分更多子步而逐项舍入创造/损失资源。
	for p in packages:
		for field in ["gross","upkeep"]:
			var key: String = str(p.id)+":"+field
			var exact: Vector2 = p[field+"_rate"]*dt*1000.0+c.finance_residual.get(key,Vector2.ZERO)
			p[field]=Vector2i(floori(exact.x+1e-7),floori(exact.y+1e-7))
			p[field+"_residual"]=exact-Vector2(p[field])
	var online: Array = []
	if settle: online=c.ledger.settle_packages(packages)
	else:
		var shadow := Ledger.new()
		shadow.stock=c.ledger.stock
		online=shadow.settle_packages(packages)
	var net_total := Vector2.ZERO
	for p in packages:
		if settle and p.id>=0:
			entities[p.id].online=online.has(p.id)
			for child_id in p.get("children",[]): entities[child_id].online=online.has(p.id)
		if not online.has(p.id): continue
		if settle:
			c.finance_residual[str(p.id)+":gross"]=p.gross_residual
			c.finance_residual[str(p.id)+":upkeep"]=p.upkeep_residual
		reference+=p.nominal
		gross_total+=p.gross_rate
		net_total+=p.gross_rate-p.upkeep_rate
		if settle and p.gross!=Vector2i.ZERO:
			if p.id<0:
				if not c.first.has("effect:102"): first_use(ci,"102","income_generated")
				if not c.first.has("effect:301") and c.techs.has("301") and c.coverage.values().any(func(v):return v.stars==0 and v.expires>now): first_use(ci,"301","income_generated")
			elif entities[p.id].kind in Config.ANCHORS:
				if not c.first.has("effect:002"): first_use(ci,"002","income_generated",p.id)
				if not c.first.has("effect:009") and c.techs.has("009") and space.cells[entities[p.id].cell].owner==ci and space.cells[entities[p.id].cell].stars>0: first_use(ci,"009","income_generated",p.id)
				for child_id in p.get("children",[]):
					var child: Dictionary = entities[child_id]
					if child.online and child.kind in ["miner_basic","miner_advanced","dyson"] and not c.first.has("effect:"+Config.BUILD_TECH[child.kind]): first_use(ci,Config.BUILD_TECH[child.kind],"income_generated",child.id)
	if settle:
		c.gross=gross_total
		c.net=net_total
		c.reference_net=reference
		unlock_permissions(ci)
	return {"gross":gross_total,"net":net_total,"reference_net":reference,"online":online}

func unlock_permissions(ci: int) -> void:
	var c: Dictionary = civs[ci]
	for tier in [1,2,3]:
		if c.permissions.has(tier): continue
		var gate: Dictionary = config.economy.gates[["I","II","III"][tier-1]]
		if c.event_flags.has(gate.event) and c.reference_net.x>=gate.M and c.reference_net.y>=gate.E:
			c.permissions[tier]=now
			log_event("tier_opened",ci,{"tier":tier,"reference_net":c.reference_net})

func snapshot() -> Dictionary:
	var civilizations: Array = []
	for c in civs:
		var copy := c.duplicate(true)
		copy.ledger=c.ledger.snapshot()
		civilizations.append(copy)
	var all_messages: Array = messages.duplicate(true)
	for msg in scheduled_messages: all_messages.append(materialize_message(msg,now))
	all_messages.sort_custom(func(a,b):return a.id<b.id)
	return {"seed":seed_value,"profile":config.profile,"config_hash":config.digest(),"t":now,"round":round_index,
		"format":"dark_forest_r4_state","version":2,"initialized_sensors":initialized_sensors,
		"space":space.snapshot(),"civs":civilizations,"entities":entities.duplicate(true),"messages":all_messages,
		"projectiles":projectiles.duplicate(true),"broadcasts":broadcasts.duplicate(true),"scans":scans.duplicate(true),
		"counters":counters.duplicate(),"last_remap":last_remap,"terminal_reason":terminal_reason,"winners":winners}

static func from_snapshot(data: Dictionary):
	if data.get("format","")!="dark_forest_r4_state" or data.get("version",0)!=2: return null
	var restored=load("res://rules/r4/state.gd").new(data.seed,data.profile,data.civs.size())
	if restored.config.digest()!=data.config_hash: return null
	restored.now=data.t
	restored.round_index=data.round
	restored.space.restore(data.space)
	restored.civs.clear()
	for source in data.civs:
		var c: Dictionary = source.duplicate(true)
		c.ledger=Ledger.new()
		c.ledger.restore(source.ledger)
		restored.civs.append(c)
	restored.entities=data.entities.duplicate(true)
	for msg in data.messages:
		if msg.has("flight"): restored.push_scheduled(msg.duplicate(true))
		else: restored.messages.append(msg.duplicate(true))
	for field in ["projectiles","broadcasts","scans"]: restored.get(field).assign(data[field])
	restored.counters=data.counters.duplicate()
	restored.last_remap=data.last_remap
	restored.terminal_reason=data.terminal_reason
	restored.winners=data.winners.duplicate()
	restored.initialized_sensors=data.initialized_sensors
	return restored

func initialize_sensors() -> void:
	if initialized_sensors: return
	initialized_sensors=true
	load("res://rules/r4/intel.gd").observe(self)

func end_round(run_ai := true, ai_order: Array = []) -> void:
	if terminal_reason!="": return
	initialize_sensors()
	var started := Time.get_ticks_usec()
	if run_ai:
		var order := ai_order.duplicate()
		if order.is_empty():
			for ci in civs.size(): order.append(ci)
		for ci in order:
			if civs[ci].alive and civs[ci].ai: load("res://rules/r4/ai.gd").take_turn(self,ci)
	var sim = load("res://rules/r4/simulation.gd")
	var ai_finished := Time.get_ticks_usec()
	sim.refresh_tactical(self)
	load("res://rules/r4/combat.gd").reserve(self)
	sim.advance(self,1.0)
	sim.sort_collections(self)
	var physics_finished := Time.get_ticks_usec()
	for c in civs:
		c.ledger.release_all_shots()
		c.ledger.transactions.clear()
		c.ap=int(config.economy.scale.action_points_per_turn)
	round_index+=1
	load("res://rules/r4/intel.gd").observe(self)
	for c in civs:
		if c.alive: unlock_permissions(c.id)
	last_performance={"ai_ms":(ai_finished-started)/1000.0,"physics_ms":(physics_finished-ai_finished)/1000.0,"observe_ms":(Time.get_ticks_usec()-physics_finished)/1000.0,"substeps":last_physics_substeps,"physics_phases_us":last_physics_profile}

static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a,b):return str(typeof(a))+":"+str(a)<str(typeof(b))+":"+str(b))
		var sorted: Dictionary = {}
		for key in keys: sorted[key]=canonical(value[key])
		return sorted
	if value is Array:
		var array: Array = []
		for element in value: array.append(canonical(element))
		return array
	return value

func state_hash() -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(canonical(snapshot())))
	return hashing.finish().hex_encode()
