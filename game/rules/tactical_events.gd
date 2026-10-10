class_name TacticalEvents
extends RefCounted
## 光粒使用直径0.5ly的连续扫掠；压制使用物理半径和连续三年维护，不瞬间占领。


static func suppression_target(s: GameState, civ: Civ, ship: Ship) -> Vector3i:
	if not ship.armed() or ship.work_locked:
		return GameState.NO_HIT
	for other in s.civs:
		if other == civ or not other.alive:
			continue
		for cell in other.colonies:
			if ship.pos.distance_to(Vector3(cell)) * s.physical_cell_size() > Balance.SUPPRESSION_RANGE + 1e-7:
				continue
			var defended := false
			for defender in other.ships:
				if defender.armed() and defender.pos.distance_to(Vector3(cell)) * s.physical_cell_size() <= Balance.SUPPRESSION_DEFENDER_RANGE:
					defended = true
					break
			if not defended:
				return cell
	return GameState.NO_HIT


static func packages(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ship in civ.ships:
		var cell := suppression_target(s, civ, ship)
		if cell != GameState.NO_HIT:
			result.append({"key": "suppression:%d" % ship.id, "kind": "suppression", "id": ship.id, "at": cell,
					"nominal": [0, 0], "q": 1.0, "upkeep": Balance.SUPPRESSION_UPKEEP, "parent": "ship:%d" % ship.id})
	return result


static func next_change(s: GameState, motions: Dictionary, duration: float) -> float:
	var next := INF
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead or not motions.has(ship.id):
				continue
			if not ship.suppression.is_empty():
				next = minf(next, maxf(0.0, Balance.SUPPRESSION_DURATION - ship.suppression["progress"]))
			if ship.kind != Ship.WARSHIP:
				continue
			for other in s.civs:
				for cell in other.colonies:
					for radius in [Balance.SUPPRESSION_RANGE, Balance.SUPPRESSION_DEFENDER_RANGE]:
						next = minf(next, Hazards._surface(motions[ship.id], {"a": Vector3(cell), "b": Vector3(cell), "r": radius / s.physical_cell_size(), "growth": 0.0}, duration))
	return next


static func integrate(s: GameState, civ: Civ, plan: Dictionary, dt: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	var active := {}
	for item in plan["items"]:
		if item["kind"] != "suppression" or not plan["active"][item["key"]]:
			continue
		active[item["id"]] = true
		var ship := civ.ship_by_id(item["id"])
		if ship.suppression.get("cell", GameState.NO_HIT) != item["at"]:
			ship.suppression = {"cell": item["at"], "progress": 0.0}
		ship.suppression["progress"] += dt
		if ship.suppression["progress"] >= Balance.SUPPRESSION_DURATION - Balance.TIME_EPSILON:
			due.append({"kind": "suppression", "at": item["at"], "owner": s.civs.find(civ), "source": ship.id})
	for ship in civ.ships:
		if not active.has(ship.id):
			ship.suppression = {}
	return due


static func box_entry(motion: Dictionary, cell: Vector3i, duration: float) -> float:
	var near := 0.0
	var far := duration
	for axis in 3:
		var lo := float(cell[axis]) - Geometry.CELL_HALF
		var hi := float(cell[axis]) + Geometry.CELL_HALF
		var v: float = motion["velocity"][axis]
		var x: float = motion["pos"][axis]
		if absf(v) < 1e-12:
			if x < lo or x > hi:
				return INF
			continue
		var a := (lo - x) / v
		var b := (hi - x) / v
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
	return near if near <= far and far >= 0.0 else INF


static func events_in(s: GameState, motions: Dictionary, duration: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if s.clock < s.remap_until:
		return due
	var all: Array = s.hidden_ships.map(func(ship): return [ship, -1])
	for civ in s.civs:
		for ship in civ.ships:
			all.append([ship, s.civs.find(civ)])
	for pair in all:
		var ship: Ship = pair[0]
		if ship.dead or not motions.has(ship.id):
			continue
		var motion: Dictionary=motions[ship.id]
		# 任一二次轨迹的位移不超过 |v|dt+|a|dt²/2；远于此球的格子不可能相交。
		# 只做保守剔除，近处仍使用原来的连续轨迹精确判定。
		var travel_bound: float=motion["velocity"].length()*duration+0.5*motion["acceleration"].length()*duration*duration
		if ship.kind in [Ship.COLONY,Ship.DEVOURER,Ship.DROPLET,Ship.SOPHON] and ship.moving():
			var bound: float=travel_bound+Balance.COLLISION_EPSILON/s.physical_cell_size()+1e-7
			for cell in s.system_cells:
				if motion["pos"].distance_squared_to(Vector3(cell))>bound*bound:
					continue
				var owner:=s.coord_owner(cell)
				var qualifies: bool = s.can_settle(cell) if ship.kind==Ship.COLONY else (owner==null and s.map.rocky.get(cell,0)>0 if ship.kind==Ship.DEVOURER else owner!=null and s.civs.find(owner)!=pair[1])
				if not qualifies:
					continue
				var at:=Kinematics.first_contact(motion["pos"]-Vector3(cell),motion["velocity"],motion["acceleration"],Balance.COLLISION_EPSILON/s.physical_cell_size(),duration)
				if at!=INF:
					due.append({"after":at,"kind":"arrival_stop","ship":ship,"owner":pair[1],"at":cell})
		if ship.kind!=Ship.GRAIN:
			continue
		if s.relative_light(ship.pos) < Balance.GRAIN_MIN_LIGHT:
			ship.dead = true
			continue
		var grain_bound: float=travel_bound+Balance.GRAIN_RADIUS/s.physical_cell_size()+1e-7
		for cell in s.system_cells:
			if motion["pos"].distance_squared_to(Vector3(cell))>grain_bound*grain_bound:
				continue
			if s.coord_owner(cell) == null or s.map.star_at(cell) == StarMap.Star.NONE or s.cell_ids.get(cell, -1) == ship.origin_cell_id:
				continue
			var t := Kinematics.first_contact(motion["pos"]-Vector3(cell),motion["velocity"],motion["acceleration"],Balance.GRAIN_RADIUS/s.physical_cell_size(),duration)
			if t != INF:
				due.append({"after": t, "kind": "grain", "ship": ship, "owner": pair[1], "at": cell, "victim": s.civs.find(s.coord_owner(cell))})
	return due


static func resolve(s: GameState, due: Array[Dictionary]) -> void:
	due.sort_custom(func(a, b): return a.get("source", a.get("ship", null).id if a.has("ship") else -1) < b.get("source", b.get("ship", null).id if b.has("ship") else -1))
	var used := {}
	for event in due:
		var at: Vector3i = event["at"]
		var owner := s.coord_owner(at)
		if event["kind"]=="arrival_stop":
			var ship: Ship=event["ship"]
			if not ship.dead and ship.moving():
				ship.direction=Vector3.ZERO
				ship.speed=0.0
				ship.has_target=false
				ship.parked=ship.kind in [Ship.DROPLET,Ship.SOPHON,Ship.DEVOURER]
				Signals.report_ship(s,s.civs[event["owner"]],ship)
			continue
		if event["kind"] == "suppression":
			if owner != null and s.civs.find(owner) != event["owner"]:
				var anchors:=Assets.at(owner,"anchor",at)
				var anchor_id: int=anchors[0]["id"] if not anchors.is_empty() else -1
				s._lose_system(at, owner, "连续压制")
				Information.system_destroyed(s,event["owner"],s.civs.find(owner),at,anchor_id,"连续压制")
				s.events.append({"id": s.next_id(), "kind": "suppression_complete", "t": s.clock, "cell_id": s.cell_ids[at], "source": event["source"]})
			continue
		var grain: Ship = event["ship"]
		owner = s.civs[event["victim"]] if event.get("victim", -1) >= 0 else owner
		if used.has(grain.id) or grain.dead:
			continue
		used[grain.id] = true
		grain.dead = true
		if s.relative_light(grain.pos) < Balance.GRAIN_MIN_LIGHT or s.map.star_at(at) == StarMap.Star.NONE:
			continue
		s.map.stars[at] = s.map.star_at(at) - 1
		if owner != null:
			var dysons := Assets.at(owner, "dyson", at)
			if not dysons.is_empty():
				Assets.destroy(owner, dysons[0])
			if not owner.bunkers.has(at):
				var anchors:=Assets.at(owner,"anchor",at)
				var anchor_id: int=anchors[0]["id"] if not anchors.is_empty() else -1
				s._lose_system(at, owner, "光粒")
				Information.system_destroyed(s,event["owner"],s.civs.find(owner),at,anchor_id,"光粒")
				for civ in s.civs:
					for ship in civ.ships:
						if not ship.dead and ship.cell() == at and not ship.moving():
							s._destroy(civ, ship, "光粒")
			Signals.send(s,s.civs.find(owner),Vector3(at),Signals.controller(owner),"report",{
				"type":"hit","cell":at,"direction":-grain.direction,"t_observed":s.clock,"epoch":s.space_epoch})
		s.events.append({"id": s.next_id(), "kind": "star_destroyed", "t": s.clock, "cell_id": s.cell_ids[at], "source": grain.id, "owner": event["owner"]})


static func devour(s: GameState) -> void:
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead or ship.dormant or ship.kind != Ship.DEVOURER or ship.moving() or ship.last_devour_turn == s.turn or s.clock < ship.pause_until:
				continue
			var cell := ship.cell()
			if s.coord_owner(cell) != null or s.map.rocky.get(cell, 0) <= 0:
				continue
			s.map.rocky[cell] -= 1
			if s.map.rocky[cell] == 0:
				s.map.habitable.erase(cell)
			var gained: float = Balance.DEVOURER_ENERGY * Balance.DIMENSION_OUTPUT[str(ship.entity_dim)]
			civ.energy += gained
			ship.last_devour_turn = s.turn
			ship.pause_until = s.clock + 1.0
			civ.ledger.append({"t": s.clock, "kind": "devour", "delta": [WorkOrder.units(gained), 0], "cell_id": s.cell_ids[cell]})
			s.events.append({"id": s.next_id(), "kind": "planet_consumed", "t": s.clock, "cell_id": s.cell_ids[cell], "ship": ship.id})
