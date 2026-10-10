class_name Conversion
extends RefCounted
## 每一级独立冻结名册。准备是托管工程；ready 必须到达实体，库存税只在首次实际转换时发生。


static func step_key(from_dim: int) -> String:
	return "%d>%d" % [from_dim, from_dim - 1]


static func roster(civ: Civ, from_dim: int) -> Array[int]:
	var ids: Array[int] = []
	for asset in civ.assets:
		if asset["entity_dim"] == from_dim:
			ids.append(asset["id"])
	for ship in civ.ships:
		if not ship.dead and ship.kind != Ship.GRAIN and ship.entity_dim == from_dim:
			ids.append(ship.id)
	ids.sort()
	return ids


static func known_roster(s: GameState,civ: Civ,from_dim: int) -> Array[int]:
	var ids: Array[int]=[]
	for asset in Knowledge.assets(s,civ):
		if asset["entity_dim"]==from_dim:
			ids.append(asset["id"])
	for ship in Signals.reported_ships(s,civ):
		if ship.kind!=Ship.GRAIN and ship.entity_dim==from_dim:
			ids.append(ship.id)
	ids.sort()
	return ids


## 冻结名册逐项展示；真实entity.ready和plan.status不能证明控制端已经知情。
static func known_ready(s: GameState,civ: Civ,plan_id: int) -> Array:
	var plan: Dictionary=civ.conversions.get(plan_id,{})
	var result: Array=[]
	for id in plan.get("roster",[]):
		var entity:=Knowledge.entity(s,civ,id)
		var name: String="实体"
		if entity.has("ship"):
			name=Ship.NAMES[entity["ship"].kind]
		elif entity.has("asset"):
			name="星系" if entity["asset"]["kind"]=="anchor" else Construction.NAMES.get(entity["asset"]["kind"],"设施")
		var row: Dictionary={"id":id,"name":name}
		if plan.get("ready_at",{}).has(id):
			row["ready_at"]=plan["ready_at"][id]
			var report: Dictionary=plan.get("ready_reports",{}).get(id,{})
			if not report.is_empty():
				row["received_at"]=report["t_received"]
				row["epoch"]=report["epoch"]
		result.append(row)
	return result


static func quote(ids: Array, emergency: bool) -> Dictionary:
	if emergency:
		return {"cost": Balance.EMERGENCY_CONVERSION_COST.duplicate(), "work": Balance.EMERGENCY_CONVERSION_WORK,
				"fraction": Balance.EMERGENCY_CONVERSION_RETENTION}
	return {"cost": [Balance.CONVERSION_BASE_COST[0] + ids.size() * Balance.CONVERSION_ENTITY_COST[0],
			Balance.CONVERSION_BASE_COST[1] + ids.size() * Balance.CONVERSION_ENTITY_COST[1]],
			"work": Balance.CONVERSION_BASE_WORK + ceilf(float(ids.size()) / Balance.CONVERSION_BATCH_SIZE),
			"fraction": Balance.CONVERSION_RETENTION}


static func error(s: GameState, civ: Civ, ids: Array, host_id: int, emergency: bool) -> String:
	var err := s._common_error(civ)
	if err != "":
		return err
	if s.dimension <= 1:
		return "一维没有零维逃生；请驶离终止区"
	if not emergency and not civ.has_tech("dimension"):
		return "完整迁维需要302；可选择紧急迁维"
	var host := Knowledge.entity(s,civ,host_id)
	if host.is_empty() or not is_anchor(host):
		return "请选择现有生存锚点作为执行宿主"
	if s.construction_busy(civ, Vector3i(host["pos"].round()), host_id if host.has("ship") else -1):
		return "该宿主已有工程"
	var available := known_roster(s,civ,s.dimension)
	var seen := {}
	for id in ids:
		if seen.has(id) or not available.has(id):
			return "名册含重复、不存在或已转换的实体"
		seen[id] = true
	if ids.is_empty():
		return "当前维度没有待适配实体，需等待世界进入下一维"
	if emergency:
		if not ids.has(host_id) or ids.size() > 1 + Balance.EMERGENCY_CONVERSION_MINERS:
			return "紧急迁维只保护执行锚点和最多两艘当地矿船"
		for id in ids:
			if id == host_id:
				continue
			var asset: Dictionary=Knowledge.entity(s,civ,id).get("asset",{})
			if asset.is_empty() or asset["kind"] not in ["miner", "advanced_miner"] or Vector3(asset["at"]).distance_to(host["pos"]) > Balance.COLLISION_EPSILON:
				return "紧急名册只能加入执行锚点当地的矿船"
	var price: Array = quote(ids, emergency)["cost"]
	return s._pay_error(civ, price[0], price[1])


static func is_anchor(entity: Dictionary) -> bool:
	return (entity.has("asset") and entity["asset"]["kind"] == "anchor") or (entity.has("ship") and entity["ship"].kind in [Ship.STARSHIP, Ship.WANDERING_EARTH])


static func prepare(s: GameState, civ: Civ, ids: Array, host_id: int, emergency: bool, automatic: bool) -> Dictionary:
	var err := error(s, civ, ids, host_id, emergency)
	if err != "":
		return {"error": err}
	var host := Knowledge.entity(s,civ,host_id)
	var spec := quote(ids, emergency)
	var project := WorkOrder.create(s.next_id(), "conversion", Vector3i(host["pos"].round()), spec["cost"], spec["work"], "conversion")
	project["host_ship"] = host_id if host.has("ship") else -1
	project["host_id"] = host_id
	project["from_dim"] = s.dimension
	project["roster"] = ids.duplicate()
	project["fraction"] = spec["fraction"]
	project["automatic"] = automatic
	Economy.charge(s,civ,spec["cost"],"conversion")
	civ.actions_left -= 1
	civ.pending.append(project)
	civ.conversions[project["id"]] = {"id": project["id"], "roster": ids.duplicate(), "host": host_id,
			"from_dim": s.dimension, "fraction": spec["fraction"], "automatic": automatic,
			"emergency": emergency, "status": "preparing", "created": s.clock, "ready_at": {}}
	OrderControl.submit(s,civ,project)
	s.events.append({"id": s.next_id(), "kind": "conversion_prepared", "t": s.clock, "plan": project["id"], "roster": ids.duplicate()})
	return {"error": "", "order": project["id"]}


static func complete(s: GameState, civ: Civ, project: Dictionary) -> void:
	var owner := s.civs.find(civ)
	var host := Signals.entity(s, owner, project["host_id"])
	if host.is_empty():
		return
	civ.conversions[project["id"]]["status"] = "distributing"
	for id in project["roster"]:
		if Signals.entity(s, owner, id).is_empty():
			continue
		Signals.send(s, owner, host["pos"], id, "conversion_ready", {"step": step_key(project["from_dim"]),
				"fraction": project["fraction"], "plan": project["id"], "automatic": project["automatic"]})


static func execute_error(s: GameState, civ: Civ, plan_id: int) -> String:
	var err := s._pay_error(civ, 0)
	if err != "":
		return err
	if not civ.conversions.has(plan_id):
		return "没有这份迁维计划"
	var plan: Dictionary = civ.conversions[plan_id]
	if civ.order_reports.get(plan_id,{}).get("status","") in ["cancelled", "destroyed", "failed"]:
		return "准备尚未完成或已取消"
	if plan["ready_at"].is_empty():
		return "尚未收到任何实体的迁维准备回执"
	if plan["from_dim"] != s.dimension or s.dimension == 1:
		return "这份计划不属于当前维度步骤"
	return ""


static func execute(s: GameState, civ: Civ, plan_id: int) -> Dictionary:
	var err := execute_error(s, civ, plan_id)
	if err != "":
		return {"error": err}
	var owner := s.civs.find(civ)
	var controller := Signals.entity(s, owner, Signals.controller(civ))
	if controller.is_empty():
		return {"error": "没有指令锚点"}
	civ.actions_left -= 1
	for id in civ.conversions[plan_id]["roster"]:
		Signals.send(s, owner, controller["pos"], id, "conversion_execute", {"plan": plan_id, "step": step_key(s.dimension)})
	Signals.receive_due(s)
	return {"error": ""}


static func apply(s: GameState, civ: Civ, entity: Dictionary, step: String, at_front: bool) -> bool:
	var ready: Dictionary = entity["ship"].ready if entity.has("ship") else entity["asset"]["ready"]
	var from_dim := int(step.substr(0, 1))
	var current: int = entity["ship"].entity_dim if entity.has("ship") else entity["asset"]["entity_dim"]
	if current < from_dim:
		return true
	if current != from_dim or not ready.has(step):
		return false
	var qualification: Dictionary = ready[step]
	if at_front and (not qualification.get("automatic", false) or qualification["at"] >= s.clock - Balance.TIME_EPSILON):
		return false
	var fraction: float = qualification["fraction"]
	if not civ.conversion_receipts.has(step):
		civ.conversion_receipts[step] = {"fraction": fraction, "t": s.clock, "id": s.next_id()}
		var before := [civ.energy_millis, civ.mineral_millis]
		civ.energy_millis = floori(civ.energy_millis * fraction)
		civ.mineral_millis = floori(civ.mineral_millis * fraction)
		for ship in civ.ships:
			for i in 2:
				ship.ammo_reserved[i] = floori(ship.ammo_reserved[i] * fraction)
		for project in WorldTime.orders(civ):
			WorkOrder.retain(project, step, fraction)
		for message in s.messages:
			if message["owner"] == s.civs.find(civ) and message["kind"] == "command" and message["body"].has("reserved"):
				for i in 2:
					message["body"]["reserved"][i] = floori(message["body"]["reserved"][i]*fraction)
			if message["owner"]==s.civs.find(civ) and message["kind"]=="report" and message["body"].get("type","")=="command_result":
				for i in 2:
					message["body"]["refund"][i]=floori(message["body"]["refund"][i]*fraction)
			if message["owner"]==s.civs.find(civ) and message["kind"]=="report" and message["body"].get("type","")=="order" and message["body"]["data"].has("failure_refund"):
				for i in 2:
					message["body"]["data"]["failure_refund"][i]=floori(message["body"]["data"]["failure_refund"][i]*fraction)
		civ.ledger.append({"t": s.clock, "kind": "conversion_loss", "step": step,
				"delta": [civ.energy_millis - before[0], civ.mineral_millis - before[1]]})
	fraction = civ.conversion_receipts[step]["fraction"]
	if entity.has("ship"):
		var ship: Ship = entity["ship"]
		ship.entity_dim = from_dim - 1
		if not ship.conversion_receipts.has(step):
			ship.conversion_receipts[step] = fraction
			for i in 2:
				ship.cost[i] = WorkOrder.amount(floori(WorkOrder.units(ship.cost[i]) * fraction))
	else:
		var asset: Dictionary = entity["asset"]
		asset["entity_dim"] = from_dim - 1
		if not asset["receipts"].has(step):
			asset["receipts"][step] = fraction
			for i in 2:
				asset["paid"][i] = WorkOrder.amount(floori(WorkOrder.units(asset["paid"][i]) * fraction))
	# 兼容旧面板的标记只描述控制锚点，规则仍逐实体读取维度。
	if entity["id"] == Signals.controller(civ):
		civ.reduced = from_dim <= 3
		civ.line_reduced = from_dim <= 2
	s.events.append({"id": s.next_id(), "kind": "entity_converted", "entity": entity["id"], "t": s.clock, "step": step})
	return true
