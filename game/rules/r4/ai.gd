class_name R4AI
extends RefCounted
## AI只从本文明收到的历史、中央账本和公开几何选行动。所有合法性/价格共用state接口。
## 无赠科技、资源加成或敌方真值查询。B/C使用同一策略。
const RESEARCH := ["008","009","015","010","005","011","013","006","014","102","109","103","110","012","105","104","106","107","108","101","201","202","203","205","204","206","301","302","303"]

static func accepted(s, ci: int, request: Dictionary) -> bool:
	return s.submit(ci,request).error==""

static func open_slot(c: Dictionary, host: int) -> bool:
	for p in c.ledger.projects.values():
		if p.host==host and p.metadata.kind!="research": return false
	return true

static func take_turn(s, ci: int) -> void:
	var c: Dictionary = s.civs[ci]
	for action in int(s.config.economy.scale.action_points_per_turn):
		if c.ap<=0 or not choose(s,ci): break

static func choose(s, ci: int) -> bool:
	var c: Dictionary = s.civs[ci]
	var own: Array = []
	var enemies: Array = []
	for e in c.seen.values():
		if not e.alive: continue
		var current: Dictionary = e.duplicate(false)
		current.pos=s.observation_position(e)
		if e.owner==ci: own.append(current)
		elif e.kind in R4Config.ANCHORS or e.kind in R4Config.MOBILE or e.kind in R4Config.CELESTIAL: enemies.append(current)
	own.sort_custom(func(a,b): return a.id<b.id)
	enemies.sort_custom(func(a,b): return a.id<b.id)
	var anchors: Array = own.filter(func(e):return e.kind in R4Config.ANCHORS)
	if anchors.is_empty(): return false
	var primary: Dictionary = anchors[0]
	for e in anchors:
		if e.id==c.home: primary=e
	# 只使用已到达预警。302的主动进攻同样先给自己做准备。
	var crisis: bool = c.alerts.values().any(func(a):return a.kind=="dimensional_weapon")
	var strategic: bool = c.techs.has("302")
	if (crisis or strategic) and primary.dim>1 and not primary.ready.has(str(primary.dim)) and open_slot(c,primary.id):
		var manifest: Array = [primary.id]
		for e in own:
			if e.id==primary.id or e.dim!=primary.dim or e.kind in R4Config.AMMUNITION: continue
			if strategic or (e.cell==primary.cell and e.kind in ["miner_basic","miner_advanced"] and manifest.size()<3): manifest.append(e.id)
		if accepted(s,ci,{"kind":"prepare","host":primary.id,"manifest":manifest,"emergency":not strategic,"auto":true}): return true
	# 在已观测的停泊运输船上落地，不为失败者赠送殖民科技或天体。
	for e in own:
		if e.kind=="transport" and not e.moving and open_slot(c,e.id):
			if accepted(s,ci,{"kind":"build","item":"colony","host":e.id}): return true
	# 每系先建实际产能；已研究008也保留旧基础矿船。
	for host in anchors:
		if host.kind not in ["home","colony"] or not open_slot(c,host.id): continue
		var miners: int = own.filter(func(e):return e.cell==host.cell and e.kind in ["miner_basic","miner_advanced"]).size()
		var target: int = s.config.physics.advanced_miner_cap if c.techs.has("008") else s.config.physics.basic_miner_cap
		if miners<target:
			var kind := "miner_advanced" if c.techs.has("008") else "miner_basic"
			if accepted(s,ci,{"kind":"build","item":kind,"host":host.id}): return true
			if kind=="miner_advanced" and miners<2 and accepted(s,ci,{"kind":"build","item":"miner_basic","host":host.id}): return true
	# 研究选择是同一目录顺序；三个人工试玩策略可调整经济/军备优先顺序。
	var research := RESEARCH.duplicate()
	if c.strategy=="defensive":
		for id in ["014","106","110"]:
			research.erase(id)
			research.push_front(id)
	elif c.strategy=="aggressive":
		for id in ["104","105","012","005"]:
			research.erase(id)
			research.push_front(id)
	if c.research_project<0:
		for id in research:
			if accepted(s,ci,{"kind":"research","item":id,"host":primary.id}): return true
	# 预警、天体供能和唯一移动存续锚点。
	for host in anchors:
		if not open_slot(c,host.id): continue
		if host.kind in ["home","colony"]:
			if not own.any(func(e):return e.kind=="warning" and e.cell==host.cell):
				if accepted(s,ci,{"kind":"build","item":"warning","host":host.id}): return true
			if accepted(s,ci,{"kind":"build","item":"dyson","host":host.id}): return true
			if (c.strategy=="defensive" or crisis) and accepted(s,ci,{"kind":"build","item":"bunker","host":host.id}): return true
		if c.techs.has("110") and not c.built_starship and s.project_count(ci,"starship")==0:
			if accepted(s,ci,{"kind":"build","item":"starship","host":host.id}): return true
	# 调度只以已收到坐标为目标；未知格的选择使用公开格子ID，不读其中的行星或敌军。
	for e in own:
		if e.kind not in R4Config.MOBILE or e.moving or c.last_order_round.get(e.id,-100)==s.round_index: continue
		var target := -1
		var best := INF
		if e.kind=="transport":
			for cell in c.known_cells.values():
				if not cell.habitable or cell.rocky<=0 or cell.owner>=0: continue
				var distance: float = e.pos.distance_squared_to(s.observation_position(cell))
				if distance<best: best=distance; target=cell.id
		elif e.kind in ["battleship","sophon","droplet"] and not enemies.is_empty():
			for enemy in enemies:
				var distance: float = e.pos.distance_squared_to(enemy.pos)
				if distance<best and distance>0.0001: best=distance; target=enemy.cell
		elif e.kind in ["probe_basic","probe_nuclear","devourer"]:
			for id in 729:
				if e.kind=="devourer" and c.known_cells.has(id):
					var cell: Dictionary = c.known_cells[id]
					if cell.owner>=0 or cell.rocky<=0: continue
				elif c.known_cells.has(id): continue
				var distance: float = e.pos.distance_squared_to(s.space.position_for(id))
				if distance<best and distance>0.01: best=distance; target=id
		if target>=0 and target!=e.cell:
			if accepted(s,ci,{"kind":"move","host":e.id,"target_cell":target}):
				return true
	# 扩张和侦察数量是策略预算，不是额外建造限制。
	var transports: int = own.filter(func(e):return e.kind=="transport").size()+s.project_count(ci,"transport")
	var probes: int = own.filter(func(e):return e.kind in ["probe_basic","probe_nuclear","sophon","droplet"]).size()
	for host in anchors:
		if not open_slot(c,host.id): continue
		if anchors.size()<6 and transports<2:
			if accepted(s,ci,{"kind":"build","item":"transport","host":host.id}): return true
		if probes<3:
			for kind in ["sophon","probe_nuclear","probe_basic"]:
				if accepted(s,ci,{"kind":"build","item":kind,"host":host.id}): return true
		if not enemies.is_empty():
			var modules: Array = []
			for module in ["011","012","013","104","105","106"]:
				if c.techs.has(module): modules.append(module)
			if accepted(s,ci,{"kind":"build","item":"battleship","host":host.id,"modules":modules}): return true
		if c.techs.has("302") and primary.ready.has(str(primary.dim)):
			if not own.any(func(e):return e.kind=="dimensional_weapon") and accepted(s,ci,{"kind":"build","item":"dimensional_weapon","host":host.id}): return true
		if not enemies.is_empty() and c.techs.has("204") and not own.any(func(e):return e.kind=="photoid"):
			if accepted(s,ci,{"kind":"build","item":"photoid","host":host.id}): return true
		if c.techs.has("101") and not own.any(func(e):return e.kind=="devourer"):
			if accepted(s,ci,{"kind":"build","item":"devourer","host":host.id}): return true
	# 已有舰船单独改装；不把研究当装备，也不强制205抬高所有新船价格。
	for e in own:
		if e.kind!="battleship" or not open_slot(c,e.id): continue
		for module in ["104","105","012","011","013","106","108","205"]:
			if accepted(s,ci,{"kind":"refit","item":module,"host":e.id}): return true
	if not enemies.is_empty():
		var destination: Dictionary = enemies[0]
		for ammo in own:
			if ammo.kind in ["dimensional_weapon","photoid"] and accepted(s,ci,{"kind":"launch","host":primary.id,"ammunition":ammo.id,"target_cell":destination.cell}): return true
		if s.round_index%10==0 and accepted(s,ci,{"kind":"scan","host":primary.id,"target_cell":destination.cell}): return true
		if s.round_index%25==0 and accepted(s,ci,{"kind":"broadcast","host":primary.id,"target_cell":destination.cell}): return true
		if crisis and accepted(s,ci,{"kind":"domain","host":primary.id,"target":primary.pos+(destination.pos-primary.pos).normalized()}): return true
	if c.radio<s.config.economy.upgrades.max_radio_and_warning_upgrades and open_slot(c,primary.id):
		if accepted(s,ci,{"kind":"radio","host":primary.id}): return true
	# 决策耗尽后才用一次低效应急积资，不能把它计入发展权限产能。
	var resource := "M" if c.ledger.stock.x<c.ledger.stock.y else "E"
	return accepted(s,ci,{"kind":"emergency","host":primary.id,"resource":resource})
