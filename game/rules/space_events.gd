class_name SpaceEvents
extends RefCounted
## 战略载荷、分格空间前沿及存续检查，与普通战斗共享连续时钟。


static func launch(s: GameState, owner: int, origin: Vector3, target: Vector3, kind: String, id := -1) -> Dictionary:
	var payload := {"id": s.next_id() if id<0 else id, "owner": owner, "kind": kind, "from_dim": s.dimension,
			"pos": origin, "origin": origin, "target": target, "direction": (target - origin).normalized(),
			"velocity": Vector3.ZERO, "distance": 0.0, "damage": 0, "dead": false,
			"launched": s.clock, "activate_at": INF, "epoch": s.space_epoch,
			"remaining": origin.distance_to(target) * s.physical_cell_size(), "leg_start": origin, "leg_distance": 0.0}
	s.payloads.append(payload)
	report(s,payload)
	return payload


static func report(s: GameState,payload: Dictionary) -> void:
	if payload["owner"]<0:
		return
	payload["report_at"] = s.clock
	var civ: Civ = s.civs[payload["owner"]]
	Signals.send(s,payload["owner"],payload["pos"],Signals.controller(civ),"report",{"type":"payload",
		"data":payload.duplicate(true),"t_observed":s.clock,"source_id":payload["id"],"epoch":s.space_epoch})


static func motion(s: GameState, payload: Dictionary) -> Dictionary:
	var speed := 0.0
	var arrival := INF
	if payload["activate_at"] == INF:
		var factor := Balance.DOMAIN_PAYLOAD_SPEED if payload["kind"] == "domain" else Balance.DIMENSION_PAYLOAD_SPEED
		speed = factor * s.light_speed_at(payload["pos"])
		if speed > 0.0:
			arrival = maxf(0.0, payload["remaining"]) / speed
	var velocity: Vector3 = payload["direction"] * speed / s.physical_cell_size()
	return {"pos": payload["pos"], "velocity": velocity, "acceleration": Vector3.ZERO, "speed": speed, "arrival": arrival}


static func zones(s: GameState) -> Array[Dictionary]:
	if s.dimension == 3:
		return s.foil_zones
	if s.dimension == 2:
		return s.line_zones
	return s.zero_zones


static func radius(s: GameState, zone: Dictionary, at: float) -> float:
	return (at - zone["created"]) * Balance.FOIL_SPREAD * s.background_light()


static func cell_distance(s: GameState, center: Vector3, cell: Vector3i) -> float:
	var point := center.clamp(Vector3(cell) - Vector3.ONE * Geometry.CELL_HALF, Vector3(cell) + Vector3.ONE * Geometry.CELL_HALF)
	return center.distance_to(point) * s.physical_cell_size()


static func next_change(s: GameState) -> float:
	var next := INF
	for payload in s.payloads:
		if payload["dead"]:
			continue
		if payload["activate_at"] != INF:
			next = minf(next, maxf(0.0, payload["activate_at"] - s.clock))
		else:
			next = minf(next, motion(s, payload)["arrival"])
	return next


## 降维前沿扫到每个还没降维的格子的时刻：{格子: 时刻}，几个前沿取最早的。
static func front_times(s: GameState) -> Dictionary:
	var times := {}
	for zone in zones(s):
		for cell in s.cell_ids:
			if s.cell_dims[s.cell_ids[cell]] < s.dimension:
				continue
			var time: float = zone["created"] + cell_distance(s, Vector3(zone["center"]), cell) / (Balance.FOIL_SPREAD * s.background_light())
			times[cell] = minf(times.get(cell, INF), time)
	return times


## 降维前沿下一次非停不可是什么时候，最多看 dt 年。motions 是这一步各个东西的运动。
## 前沿扫到的格子里没有东西、这一步也没有东西会进去、也没有光波正好经过时，不用为它停下：
## 等下一次因为别的事停下时再补上（resolve），记的仍是前沿扫到的准确时刻，消息也按那个时刻重算。
## 扫完最后一批格子以后要换图，那一批照旧准时停。
static func next_front(s: GameState, motions: Dictionary, dt: float) -> float:
	var times := front_times(s)
	var batches := _batches(times, s.clock + dt)
	if batches.is_empty():
		return INF
	var left := times.size()
	var boxes := _moving_boxes(s, motions, dt)
	for batch in batches:
		left -= batch["cells"].size()
		if left <= 0 or _front_matters(s, batch, boxes, s.clock + dt):
			return maxf(0.0, batch["at"] - s.clock)
	return INF


## 把不晚于 until 的格子按时刻分批（同一时刻扫到的一批），按时刻先后排好。
static func _batches(times: Dictionary, until: float) -> Array:
	var due := []
	var n := 0
	for cell in times:
		if times[cell] <= until:
			due.append([times[cell], n, cell])
		n += 1
	due.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var batches := []
	for item in due:
		if batches.is_empty() or item[0] - batches[-1]["at"] > 1e-9:
			batches.append({"at": item[0], "cells": []})
		batches[-1]["cells"].append(item[2])
	return batches


## 这一步里各个东西可能到的范围（格坐标的方框）：舰船、隐藏舰船、载荷、弹在这一步的轨迹，设施和殖民地的位置。
static func _moving_boxes(s: GameState, motions: Dictionary, dt: float) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for id in motions:
		var m: Dictionary = motions[id]
		boxes.append(_sweep(m["pos"], Kinematics.position(m, dt), m["acceleration"].length() * dt * dt / 8.0))
	for shot in s.projectiles:
		if not shot["dead"]:
			var m := Combat.projectile_motion(s, shot)
			boxes.append(_sweep(shot["pos"], shot["pos"] + m["velocity"] * dt, 0.0))
	for owner in s.civs.size():
		for asset in s.civs[owner].assets:
			var physical := Signals.entity(s, owner, asset["id"])
			if not physical.is_empty():
				boxes.append(_sweep(physical["pos"], physical["pos"], 0.0))
	return boxes


static func _sweep(a: Vector3, b: Vector3, bow: float) -> AABB:
	var margin := Vector3.ONE * (bow + 1e-3)
	var low := a.min(b) - margin
	return AABB(low, a.max(b) + margin - low)


## 这一批格子在 [batch.at, until] 里有没有用处：有东西可能在里面，或者有光波（广播、扫描）的波前可能正经过。
static func _front_matters(s: GameState, batch: Dictionary, boxes: Array[AABB], until: float) -> bool:
	var cells: Array[Vector3i] = []
	cells.assign(batch["cells"])
	for cell_box in Geometry.cell_boxes(cells):
		for box in boxes:
			if cell_box.intersects(box):
				return true
	var waves := Information.waves(s)
	if waves.is_empty():
		return false
	# 光在任何格子里都不比 fastest 快、不比 slowest 慢（黑域里可以慢到 0，这时只看波前到没到）。
	var fastest := maxf(s.background_light(), 1.0)
	var slowest := s.background_light()
	for value in Balance.DIMENSION_LIGHT.values():
		fastest = maxf(fastest, value)
		slowest = minf(slowest, value)
	var dim := 1.0
	var bright := 1.0
	for value in s.light:
		if value > 0.0:
			dim = minf(dim, value)
			bright = maxf(bright, value)
	fastest *= bright
	slowest *= dim
	if not s.deadlines.is_empty():
		slowest *= Balance.DEADLINE_FACTOR
	if not s.black_domains.is_empty():
		slowest = 0.0
	var size := s.physical_cell_size()
	for wave in waves:
		var p: Dictionary = wave["propagation"]
		for event in p["events"]:
			if not event.has("environment"):
				return true # 换过图的波，起点不在现在的坐标里，不细算
		for cell in cells:
			var near := cell_distance(s, p["origin"], cell)
			var far := 0.0
			for corner in 8:
				var at := Vector3(cell) - Vector3.ONE * Geometry.CELL_HALF
				for axis in 3:
					if corner & (1 << axis):
						at[axis] += 2.0 * Geometry.CELL_HALF
				far = maxf(far, p["origin"].distance_to(at) * size)
			var enters: float = p["sent"] + near / fastest
			var leaves: float = p["sent"] + far / slowest if slowest > 0.0 else INF
			if enters <= until and leaves >= batch["at"]:
				return true
	return false


static func advance(s: GameState, dt: float) -> void:
	for payload in s.payloads:
		if payload["dead"] or payload["activate_at"] != INF:
			continue
		var m := motion(s, payload)
		var elapsed: float = minf(dt, m["arrival"])
		payload["leg_distance"] += m["speed"] * elapsed
		payload["pos"] = payload["leg_start"] + payload["direction"] * payload["leg_distance"] / s.physical_cell_size()
		payload["velocity"] = m["velocity"]
		payload["distance"] += m["speed"] * elapsed
		payload["remaining"] = maxf(0.0, payload["remaining"] - m["speed"] * elapsed)
		if m["arrival"] <= dt + Balance.TIME_EPSILON:
			payload["pos"] = payload["target"]
			payload["velocity"] = Vector3.ZERO
			payload["activate_at"] = s.clock + elapsed + (Balance.DOMAIN_ACTIVATION if payload["kind"] == "domain" else Balance.DIMENSION_ACTIVATION)


static func resolve(s: GameState) -> void:
	# 所有同刻攻击先决定伤亡，再展开仍存活的载荷；工程完工在此阶段之后。
	for payload in s.payloads:
		if payload["dead"] or payload["activate_at"] > s.clock + Balance.TIME_EPSILON:
			continue
		payload["dead"] = true
		if payload["kind"] == "domain":
			Hazards.activate(s, payload["pos"], payload["id"])
		elif payload["from_dim"] == s.dimension:
			unfold(s, Vector3i(payload["pos"].round()), payload["id"])
	for zone in zones(s):
		zone["age"] = radius(s, zone, s.clock) / s.physical_cell_size()
	# 前沿已经扫到的格子按扫到的时刻先后降维。早于现在的是 next_front 没为它停下的：把时钟拨回那一刻再降维，事件记那一刻。
	# 路过那里的消息先按旧光速挪到那一刻，降维后再按新光速重算（Signals.before_cells_change、after_cells_change），
	# 不会把那一刻之前走的路也算慢。
	var now := s.clock
	for batch in _batches(front_times(s), now + Balance.TIME_EPSILON):
		var cells: Array[Vector3i] = []
		cells.assign(batch["cells"])
		s.clock = batch["at"] if batch["at"] < now - Balance.TIME_EPSILON else now
		Signals.before_cells_change(s, cells)
		for cell in cells:
			convert_cell(s, cell)
		Signals.after_cells_change(s, cells)
		s.clock = now
	# 只有全部格子检查完后换图，避免同刻实体在新旧坐标中混合求交。
	var completed := s.cell_dims.values().all(func(dim): return dim < s.dimension)
	if completed and s.dimension > 1:
		DimensionSpace.commit(s, s.dimension == 2)
		return
	check_entities(s)
	for payload in s.payloads:
		if payload["dead"] or s.clock-payload.get("report_at",-INF)>=1.0:
			report(s,payload)
	s.payloads = s.payloads.filter(func(p): return not p["dead"])


static func unfold(s: GameState, cell: Vector3i, id := -1) -> void:
	if not s.map.contains(cell):
		return
	if s.dimension == 3 and s.foil_zones.is_empty():
		s.fold_anchor = cell
		s.flat_plane = cell.z
	elif s.dimension == 2 and s.line_zones.is_empty():
		s.line_anchor = cell
		s.line_y = cell.y
	zones(s).append({"id": s.next_id() if id < 0 else id, "center": cell, "created": s.clock, "age": 0.0})
	if s.dimension == 3 and s.foil_zones.all(func(zone):return absf(zone["created"]-s.clock)<=Balance.TIME_EPSILON):
		# 首次展开的同刻批次共用平均展示平面，不能由载荷数组顺序决定。
		s.flat_plane=int(DimensionSpace.Layout.base_plane(DimensionSpace.zone_origins(s.foil_zones)).z)
		s.fold_anchor.z=s.flat_plane
		for converted in s.flattened:
			s.flattened[converted]=s.flat_plane
	s.events.append({"id": s.next_id(), "kind": "dimension_front", "t": s.clock, "cell_id": s.cell_ids[cell], "from_dim": s.dimension})


static func convert_cell(s: GameState, cell: Vector3i) -> void:
	var id: int = s.cell_ids[cell]
	if s.cell_dims[id] < s.dimension:
		return
	s.set_cell_dim(id, s.dimension - 1)
	s.converted_cells.append(cell)
	if s.dimension == 3:
		s.flattened[cell] = s.flat_plane
	elif s.dimension == 2:
		s.linearized[cell] = s.line_y
	else:
		s.map.stars.erase(cell)
		s.map.rocky.erase(cell)
		s.map.gas.erase(cell)
		s.map.habitable.erase(cell)
	s.events.append({"id": s.next_id(), "kind": "cell_converted", "t": s.clock, "cell_id": id, "dim": s.dimension - 1})
	check_cell(s, cell)


static func check_cell(s: GameState, cell: Vector3i) -> void:
	var target_dim: int = s.cell_dims.get(s.cell_ids.get(cell, -1), s.dimension)
	var step := Conversion.step_key(s.dimension)
	for civ in s.civs:
		var owner := s.civs.find(civ)
		var lose_anchor := false
		for asset in civ.assets.duplicate():
			var physical := Signals.entity(s,owner,asset["id"])
			if physical.is_empty() or Vector3i(physical["pos"].round()) != cell or asset["entity_dim"] <= target_dim:
				continue
			var survives := target_dim > 0 and Conversion.apply(s, civ, physical, step, true)
			if not survives:
				if asset["kind"] == "anchor":
					lose_anchor = true
				else:
					Assets.destroy(civ, asset)
		for ship in civ.ships:
			if ship.dead or ship.cell() != cell or ship.entity_dim <= target_dim:
				continue
			if ship.kind == Ship.GRAIN:
				if target_dim == 0:
					ship.dead = true
				continue
			if target_dim == 0 or not Conversion.apply(s, civ, Signals.entity(s, owner, ship.id), step, true):
				s._destroy(civ, ship, "空间前沿")
		if lose_anchor:
			s._lose_system(cell, civ, "空间前沿")


static func check_entities(s: GameState) -> void:
	var occupied := {}
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead:
				continue
			if ship.is_outside(s.map.bounds()):
				s._destroy(civ, ship, "飞出星图")
				continue
			occupied[ship.cell()] = true
			var slow := s.relative_light(ship.pos)
			if ship.kind == Ship.GRAIN and slow < Balance.GRAIN_MIN_LIGHT:
				ship.dead = true
			elif slow < Balance.SHIP_MIN_SPEED:
				s._destroy(civ, ship, "进入黑域核心")
	for cell in occupied:
		if s.cell_dims.get(s.cell_ids.get(cell, -1), s.dimension) < s.dimension:
			check_cell(s, cell)
