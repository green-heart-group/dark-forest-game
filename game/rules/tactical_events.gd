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
	var shapes := []
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead or not motions.has(ship.id):
				continue
			if not ship.suppression.is_empty():
				next = minf(next, maxf(0.0, Balance.SUPPRESSION_DURATION - ship.suppression["progress"]))
			if ship.kind != Ship.WARSHIP:
				continue
			var motion: Dictionary = motions[ship.id]
			# 不动的战舰不会越过压制范围的边界（对不动的点 _surface 总是 INF），不用逐个星系算。
			if motion["velocity"] == Vector3.ZERO and motion["acceleration"] == Vector3.ZERO:
				continue
			if shapes.is_empty():
				for other in s.civs:
					for cell in other.colonies:
						for radius in [Balance.SUPPRESSION_RANGE, Balance.SUPPRESSION_DEFENDER_RANGE]:
							shapes.append({"a": Vector3(cell), "b": Vector3(cell), "r": radius / s.physical_cell_size(), "growth": 0.0})
			# 这一步走过的路的方框（弦的方框，四周放宽弯曲的余量 |a|t²/8，再多留一点浮点误差）。
			# 离方框都比半径远的星系，整段路都在它的球外面，不会越过表面（_surface 也是 INF），不用算。
			var low := Vector3.ONE * -INF
			var high := Vector3.ONE * INF
			if is_finite(duration):
				var end := Kinematics.position(motion, duration)
				var bend: float = motion["acceleration"].length() * duration * duration / 8.0 + 1e-4
				low = motion["pos"].min(end) - Vector3.ONE * bend
				high = motion["pos"].max(end) + Vector3.ONE * bend
			for shape in shapes:
				var point: Vector3 = shape["a"]
				if point.distance_to(point.clamp(low, high)) > shape["r"]:
					continue
				next = minf(next, Hazards._surface(motion, shape, duration))
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


## 到了目标星系会自己停下的几种船（events_in 的 arrival_stop）。
const STOP_KINDS := [Ship.COLONY, Ship.DEVOURER, Ship.DROPLET, Ship.SOPHON]
## events_in 只看这几种船：会停下的，加上光粒。别的船跳过，不用逐艘查。
const EVENT_KINDS := [Ship.COLONY, Ship.DEVOURER, Ship.DROPLET, Ship.SOPHON, Ship.GRAIN]


static func events_in(s: GameState, motions: Dictionary, duration: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if s.clock < s.remap_until:
		return due
	var all: Array = []
	for ship in s.hidden_ships:
		if ship.kind in EVENT_KINDS:
			all.append([ship, -1])
	for civ in s.civs:
		var owner := s.civs.find(civ)
		for ship in civ.ships:
			if ship.kind in EVENT_KINDS:
				all.append([ship, owner])
	var index := Geometry.cell_index(s.system_cells) if not all.is_empty() else {}
	for pair in all:
		var ship: Ship = pair[0]
		if ship.dead or not motions.has(ship.id):
			continue
		var stops: bool = ship.kind in STOP_KINDS and ship.moving()
		if not stops and ship.kind != Ship.GRAIN:
			continue
		var motion: Dictionary=motions[ship.id]
		# 任一二次轨迹的位移不超过 |v|dt+|a|dt²/2；远于此球的格子不可能相交。
		# 只做保守剔除，近处仍使用原来的连续轨迹精确判定。
		var travel_bound: float=motion["velocity"].length()*duration+0.5*motion["acceleration"].length()*duration*duration
		if stops:
			var bound: float=travel_bound+Balance.COLLISION_EPSILON/s.physical_cell_size()+1e-7
			for cell in Geometry.cells_near(s.system_cells, index, motion["pos"], bound):
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
		for cell in Geometry.cells_near(s.system_cells, index, motion["pos"], grain_bound):
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
