class_name WorldTime
extends RefCounted
## 同一连续时钟：收入/维护和工作积分到事件时刻，再提交同刻伤害，最后完工与终局。
## 加速度限速点、到达点、完工点和相对轨迹碰撞会缩短子步。


static func orders(civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = civ.pending.duplicate()
	if not civ.research_project.is_empty():
		result.append(civ.research_project)
	return result


static func next_completion(s: GameState) -> float:
	var remaining := INF
	for civ in s.civs:
		if not civ.alive:
			continue
		for project in orders(civ):
			var rate := s.project_work_rate(civ, project)
			if rate <= 0.0 or not s.project_host_alive(civ, project):
				continue
			var work: float = (project["work"] - project["done"] - project.get("work_remainder", 0.0)) / WorkOrder.SCALE
			remaining = minf(remaining, work / rate)
	return remaining


static func integrate(s: GameState, plans: Dictionary, duration: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	for civ in s.civs:
		if not civ.alive:
			continue
		Economy.integrate(s, civ, plans[s.civs.find(civ)], duration)
		due.append_array(TacticalEvents.integrate(s, civ, plans[s.civs.find(civ)], duration))
		for project in orders(civ):
			if s.project_host_alive(civ, project):
				WorkOrder.advance(project, s.project_work_rate(civ, project) * duration)
	return due


static func advance(s: GameState, duration: float) -> void:
	var end := s.clock + duration
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s, civ)
	Signals.sample(s)
	Signals.receive_due(s)
	Combat.reserve_round(s)
	var guard := 0
	while s.clock < end - 1e-12 and not s.is_over():
		guard += 1
		if s.profiling:
			s.profile["连续/子步数"] = s.profile.get("连续/子步数",0)+1
		var phase:=Time.get_ticks_usec() if s.profiling else 0
		assert(guard < 100000, "连续事件不能在零时间重复触发")
		Hazards.refresh(s)
		var plans := {}
		for civ in s.civs:
			if civ.alive:
				var plan := Economy.plan(s, civ, end - s.clock)
				Economy.set_operating(civ, plan)
				plans[s.civs.find(civ)] = plan
		Signals.receive_due(s)
		TacticalEvents.devour(s)
		Combat.fire_ready(s)
		if s.profiling:
			phase=s._lap("连续/维护与就绪",phase)
		var dt := minf(Balance.PHYSICS_MAX_DT, end - s.clock)
		dt = minf(dt, SpaceEvents.next_change(s))
		dt = minf(dt, Hazards.next_change(s))
		if s.clock < s.remap_until:
			dt = minf(dt, s.remap_until - s.clock)
		dt = minf(dt, s.next_sensor_time - s.clock)
		dt = minf(dt, next_completion(s))
		var message_motions:=Signals.plan(s)
		dt = minf(dt, Signals.next_arrival(s,message_motions))
		dt = minf(dt, Information.next_change(s))
		var detail:=Time.get_ticks_usec() if s.profiling else 0
		var motions := {}
		for civ in s.civs:
			for ship in civ.ships:
				if ship.dead:
					continue
				if ship.slow_start and not Kinematics.in_owned_system_vision(s,civ,ship.pos):
					ship.slow_start=false
				var motion := Kinematics.motion(s, civ, ship, dt)
				motions[ship.id] = motion
				dt = minf(dt, minf(motion["cap_time"], motion["arrival"]))
				dt = minf(dt, Hazards.next_boundary(s, motion, dt))
				if ship.pause_until > s.clock:
					dt = minf(dt, ship.pause_until - s.clock)
		for ship in s.hidden_ships:
			if not ship.dead:
				motions[ship.id] = Kinematics.motion(s, null, ship, dt)
		for payload in s.payloads:
			if not payload["dead"]:
				motions[payload["id"]] = SpaceEvents.motion(s, payload)
				dt = minf(dt, Hazards.next_boundary(s, motions[payload["id"]], dt))
		for shot in s.projectiles:
			if not shot["dead"]:
				var speed: float = Combat.projectile_motion(s, shot)["speed"]
				if speed > 0.0:
					dt = minf(dt, shot["remaining"] / speed)
				dt = minf(dt, Hazards.next_boundary(s, Combat.projectile_motion(s, shot), dt))
		for message in s.messages:
			var m: Dictionary = message_motions[message["id"]]
			dt = minf(dt, Hazards.next_boundary(s, {"pos": message["pos"], "velocity": m["velocity"], "acceleration": Vector3.ZERO}, dt))
		if s.profiling:
			detail=s._lap("细分/移动与环境边界",detail)
		dt = minf(dt, TacticalEvents.next_change(s, motions, dt))
		var collisions := Combat.events_in(s, motions, maxf(dt, 0.0))
		if s.profiling:
			detail=s._lap("细分/压制与武器相交",detail)
		var strategic := TacticalEvents.events_in(s, motions, maxf(dt, 0.0))
		var light_events:=LightFront.events_in(s,motions,maxf(dt,0.0))
		if s.profiling:
			s._lap("细分/战略相交",detail)
		for event in strategic:
			dt = minf(dt, event["after"])
		for event in collisions:
			dt = minf(dt, event["after"])
		for event in light_events:
			dt = minf(dt,event["after"])
		dt = minf(end - s.clock, maxf(dt, Balance.TIME_EPSILON))
		if s.profiling:
			phase=s._lap("连续/边界与相交",phase)
		var tactical_due := integrate(s, plans, dt)
		Signals.advance(s, dt,message_motions)
		Information.advance(s, dt)
		SpaceEvents.advance(s, dt)
		s._collapse_depth += 1
		_move(s, motions, dt)
		s.clock += dt
		var due: Array[Dictionary] = []
		for event in collisions:
			if event["after"] <= dt + Balance.TIME_EPSILON:
				due.append(event)
		Combat.resolve(s, due)
		for event in strategic:
			if event["after"] <= dt + Balance.TIME_EPSILON:
				tactical_due.append(event)
		TacticalEvents.resolve(s, tactical_due)
		SpaceEvents.resolve(s)
		LightFront.resolve(s,light_events,dt)
		Information.resolve(s)
		if s.profiling:
			phase=s._lap("连续/积分与伤害",phase)
		var messages_due:=true
		for civ in s.civs:
			if civ.alive:
				s._finish_pending(civ, 0.0, messages_due)
				messages_due=false
		detail=Time.get_ticks_usec() if s.profiling else 0
		Signals.receive_due(s)
		if s.profiling:
			detail=s._lap("细分/接收消息",detail)
		Signals.sample(s)
		if s.profiling:
			s._lap("细分/采样传感",detail)
		if s.profiling:
			phase=s._lap("连续/完工与传感",phase)
		Combat.repair(s)
		for civ in s.civs:
			for ship in civ.ships:
				if ship.dead:
					Combat.release(s, civ, ship)
		s._clean_dead()
		Information.observe_battles(s)
		s.projectiles = s.projectiles.filter(func(shot): return not shot["dead"] and shot["remaining"] > Balance.COLLISION_EPSILON)
		s._collapse_depth -= 1
		s._check_winner()
		if s.profiling:
			s._lap("连续/清理与终局",phase)
	for civ in s.civs:
		for ship in civ.ships:
			Combat.release(s, civ, ship)
	if not s.is_over():
		s.clock = end


static func _move(s: GameState, motions: Dictionary, dt: float) -> void:
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead or not motions.has(ship.id):
				continue
			var motion: Dictionary = motions[ship.id]
			var from := ship.pos
			ship.pos = Kinematics.position(motion, dt)
			var traveled: float = Kinematics.distance(motion["speed"], motion["acceleration"].length() * s.physical_cell_size(), dt)
			ship.distance_flown += traveled
			if ship.kind == Ship.GRAIN:
				ship.leg_distance += traveled
				ship.pos = ship.leg_origin + ship.direction * ship.leg_distance / s.physical_cell_size()
			ship.speed = motion["speed"] + motion["acceleration"].length() * s.physical_cell_size() * dt
			if motion["arrival"] <= dt + Balance.TIME_EPSILON:
				ship.pos = motion.get("target",ship.target)
				ship.speed = 0.0
				ship.has_target = false
				ship.direction = Vector3.ZERO
				if ship.kind == Ship.COLONY:
					s._settle(civ, ship)
			for asset in civ.assets:
				if asset["carrier"] == ship.id:
					asset["at"] = ship.cell()
			# 新分档的设计值是光速比例；曲率航迹须比较当地普通上限，不能与三维比例数直接比较。
			if ship.warp:
				var normal_top := Kinematics.normal_limits(s,ship,from)[0] if Kinematics.uses_relative_speed(ship) else ship.max_speed
				if motion["speed"] > normal_top + Balance.TIME_EPSILON:
					# 此时clock仍是段首，传入段尾时钟创建路径寿命。
					s.clock += dt
					Hazards.leave_deadline(s, from, ship.pos, ship, dt)
					s.clock -= dt
	for ship in s.hidden_ships:
		if not ship.dead and motions.has(ship.id):
			var traveled: float = motions[ship.id]["speed"] * dt
			ship.distance_flown += traveled
			ship.leg_distance += traveled
			ship.pos = ship.leg_origin + ship.direction * ship.leg_distance / s.physical_cell_size()
	for shot in s.projectiles:
		if shot["dead"]:
			continue
		var motion := Combat.projectile_motion(s, shot)
		var distance: float = motion["speed"] * dt
		shot["pos"] += motion["velocity"] * dt
		shot["remaining"] -= distance
		shot["distance"] += distance
