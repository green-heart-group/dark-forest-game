class_name EarthTransform
extends RefCounted
## 206把原母星锚点原ID变成移动载体。选择的类地行星与附着设备搬走；外部资产原地封存。


static func options(civ: Civ) -> Array[int]:
	var ids: Array[int] = []
	for asset in civ.assets:
		if asset["at"] == civ.original_home and asset["carrier"] < 0 and asset["kind"] in ["miner","advanced_miner","warning"]:
			ids.append(asset["id"])
	return ids


static func known_options(s: GameState,civ: Civ) -> Array[int]:
	var ids: Array[int]=[]
	for asset in Knowledge.assets(s,civ):
		if asset["at"]==civ.original_home and asset["carrier"]<0 and asset["kind"] in ["miner","advanced_miner","warning"]:
			ids.append(asset["id"])
	return ids


static func known_error(s: GameState,civ: Civ,ids: Array,rocky: int) -> String:
	var anchor:=Knowledge.entity(s,civ,civ.original_anchor_id)
	if not anchor.has("asset") or not Knowledge.owns(s,civ,civ.original_home) or s.reported_starship(civ)!=null:
		return "需要仍存续的原母星，且不能已有普通星舰或流浪地球"
	if rocky<1 or rocky>Knowledge.snapshot(s,civ,civ.original_home).get("rocky",0):
		return "携带类地行星数必须在1到原母星最近回报数量之间"
	var choices:=known_options(s,civ)
	var seen:={}
	for id in ids:
		if seen.has(id) or not choices.has(id):
			return "携行名册含重复或不在原母星的附着设备"
		seen[id]=true
	return ""


static func error(s: GameState, civ: Civ, ids: Array, rocky: int) -> String:
	var anchor := Assets.get_id(civ,civ.original_anchor_id)
	if anchor.is_empty() or not civ.owns(civ.original_home) or civ.has_starship():
		return "需要仍存续的原母星，且不能已有普通星舰或流浪地球"
	if rocky < 1 or rocky > s.map.rocky.get(civ.original_home,0):
		return "携带类地行星数必须在1到原母星实际数量之间"
	var choices := options(civ)
	var seen := {}
	for id in ids:
		if seen.has(id) or not choices.has(id):
			return "携行名册含重复或不在原母星的附着设备"
		seen[id] = true
	return ""


static func complete(s: GameState, civ: Civ, project: Dictionary) -> bool:
	var ids: Array = project.get("earth_roster",[])
	var rocky: int = project.get("earth_rocky",1)
	if error(s,civ,ids,rocky) != "":
		return false
	var anchor := Assets.get_id(civ,civ.original_anchor_id)
	var at := civ.original_home
	var ship := Ship.make(Ship.WANDERING_EARTH,Vector3(at),anchor["id"])
	ship.entity_dim = anchor["entity_dim"]
	ship.ready = anchor["ready"].duplicate(true)
	ship.conversion_receipts = anchor["receipts"].duplicate(true)
	ship.cost = WorkOrder.salvage(project)
	ship.carried_rocky = rocky
	civ.ships.append(ship)
	for asset in civ.assets:
		if ids.has(asset["id"]):
			asset["carrier"] = ship.id
			if asset["kind"] == "warning":
				asset["warning_level"] = civ.warnings.get(at,0)
		elif asset["at"] == at and asset["id"] != ship.id and asset["carrier"] < 0:
			var external: Dictionary = asset.duplicate(true)
			external["former_owner"] = s.civs.find(civ)
			s.neutral_assets.append(external)
	s.map.rocky[at] -= rocky
	if s.map.rocky[at] == 0:
		s.map.habitable.erase(at)
	if not civ.research_project.is_empty() and civ.research_project["at"] == at and civ.research_project["host_ship"] < 0:
		civ.research_project["host_ship"] = ship.id
	s._lose_system(at,civ,"母星改为流浪地球")
	if civ.colonies.is_empty():
		civ.home = ship.cell()
	Signals.report_ship(s,civ,ship)
	s.events.append({"id":s.next_id(),"kind":"earth_transformed","t":s.clock,"entity":ship.id,
		"roster":ids.duplicate(),"rocky":rocky,"original_cell":s.cell_ids[at]})
	return true


static func gross(civ: Civ, ship: Ship) -> Dictionary:
	var e: float = ship.carried_rocky*Balance.FISSION_ENERGY if civ.has_tech("fission") else 0.0
	var m := 0.0
	var actual_m := 0.0
	for asset in civ.assets:
		if asset["carrier"] != ship.id or asset["kind"] not in ["miner","advanced_miner"]:
			continue
		var rate: float = Balance.MINER_MINERAL if asset["kind"] == "miner" else Balance.ADVANCED_MINER_MINERAL
		m += rate
		actual_m += rate*Balance.DIMENSION_OUTPUT[str(asset["entity_dim"])]
	return {"nominal":[e,m],"actual":[e*Balance.DIMENSION_OUTPUT[str(ship.entity_dim)],actual_m]}
