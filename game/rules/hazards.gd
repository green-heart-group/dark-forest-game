class_name Hazards
extends RefCounted
## 有界黑域与曲率死线。时间用世界时钟；同一格的硬到期不会被后来的源延长。


static func activate(s: GameState, center: Vector3, id := -1) -> Dictionary:
	var source := {"id": s.next_id() if id < 0 else id, "center": Vector3i(center.round()), "pos": center,
			"created": s.clock, "expires": s.clock + Balance.DOMAIN_LIFETIME,
			"left": Balance.DOMAIN_LIFETIME, "radius": 0.0}
	s.black_domains.append(source)
	s._ensure_light()
	refresh(s)
	return source


static func radius(s: GameState, source: Dictionary, at: float) -> float:
	return minf(Balance.DOMAIN_RADIUS, maxf(0.0, at - source["created"]) * Balance.DOMAIN_SPREAD * s.background_light())


static func refresh(s: GameState) -> void:
	s.ensure_cells()
	s.black_domains = s.black_domains.filter(func(source): return source["expires"] > s.clock)
	for source in s.black_domains:
		source["left"] = source["expires"] - s.clock
		source["radius"] = radius(s, source, s.clock)
		for cell in s.cell_ids:
			var id: int = s.cell_ids[cell]
			var center := Vector3(cell)
			var closest: Vector3 = source["pos"].clamp(center - Vector3.ONE * Geometry.CELL_HALF, center + Vector3.ONE * Geometry.CELL_HALF)
			var distance: float = source["pos"].distance_to(closest) * s.physical_cell_size()
			if distance > source["radius"] + 1e-8:
				continue
			var life: Dictionary = s.domain_cells.get(id, {})
			if not life.is_empty() and s.clock < life["immune_until"]:
				continue
			var first: float = source["created"] + distance / (Balance.DOMAIN_SPREAD * s.background_light())
			if not life.is_empty():
				first = maxf(first, life["immune_until"])
			var expiry := first + Balance.DOMAIN_LIFETIME
			s.domain_cells[id] = {"first": first, "expires": expiry, "immune_until": expiry + Balance.DOMAIN_IMMUNITY}
	s.deadlines = s.deadlines.filter(func(line): return line["expires"] > s.clock)
	for line in s.deadlines:
		if line.has("pieces"):
			line["pieces"]=line["pieces"].filter(func(piece):return piece["expires"]>s.clock)
		for piece in pieces(line):
			var cutoff := s.clock - Balance.DEADLINE_LIFETIME
			var ended: float = piece.get("ended", piece["created"])
			if cutoff > piece["created"] and ended > piece["created"]:
				piece["a"] = piece["a"].lerp(piece["b"], clampf((cutoff - piece["created"]) / (ended - piece["created"]), 0, 1))
				piece["created"] = cutoff
		if line.has("pieces"):
			line["a"]=line["pieces"][0]["a"]
			line["created"]=line["pieces"][0]["created"]


static func pieces(line: Dictionary) -> Array:
	return line.get("pieces",[line])


static func segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var d := b - a
	var part := clampf((point - a).dot(d) / d.length_squared(), 0.0, 1.0) if d.length_squared() > 1e-15 else 0.0
	return point.distance_to(a + part * d)


## 场上有没有黑域或死线。都没有时，压制恒为 1，一点的光速只由所在格子决定。
static func any(s: GameState) -> bool:
	return not s.black_domains.is_empty() or not s.deadlines.is_empty()


## 全图光速处处相同：没有黑域和死线，每格的维度和光速也都和背景一样。
## 这时光走过格子边界什么都不变，不用在边界停下来。
static func uniform_light(s: GameState) -> bool:
	if any(s):
		return false
	for cell in s.cell_ids:
		if s.cell_dims.get(s.cell_ids[cell], s.dimension) != s.dimension or s.light_at(cell) < 1.0:
			return false
	return true


static func suppression(s: GameState, position: Vector3) -> float:
	if not any(s):
		return 1.0
	var relative := 1.0
	var cell := Vector3i(position.round())
	var life: Dictionary = s.domain_cells.get(s.cell_ids.get(cell, -1), {})
	var ignores: bool = not life.is_empty() and s.clock >= life["expires"] and s.clock < life["immune_until"]
	if not ignores:
		var weight := 0.0
		for source in s.black_domains:
			if source["expires"] <= s.clock:
				continue
			var reach := radius(s, source, s.clock)
			var distance: float = position.distance_to(source["pos"]) * s.physical_cell_size()
			if distance > reach + 1e-8:
				continue
			if distance <= Balance.DOMAIN_CORE:
				relative = 0.0
				break
			if reach > 0.0:
				weight += Balance.DOMAIN_WEIGHT * maxf(0.0, 1.0 - distance / reach)
		if relative > 0.0:
			relative = 1.0 / (1.0 + weight)
	for line in s.deadlines:
		# 连续共线子段的胶囊并集正好等于首尾胶囊；内部接缝不是场强边界。
		if line["expires"] > s.clock and segment_distance(position, line["a"], line["b"]) * s.physical_cell_size() <= Balance.DEADLINE_RADIUS:
			relative = minf(relative, Balance.DEADLINE_FACTOR)
	return relative


static func leave_deadline(s: GameState, a: Vector3, b: Vector3, ship: Ship, duration := 0.0) -> void:
	if a.distance_squared_to(b) < 1e-15:
		return
	var piece: Dictionary={"a":a,"b":b,"created":s.clock-duration,"ended":s.clock,"expires":s.clock+Balance.DEADLINE_LIFETIME}
	var slot:=floori((s.clock-duration+Balance.TIME_EPSILON)/Balance.PHYSICS_MAX_DT)
	# 同一固定采样区间的直线段共享身份。消息到达细分不能再制造新航迹和新回报。
	# 子段的形成时段、几何和到期仍各自保留，不能靠延伸刷新旧段寿命。
	for i in range(s.deadlines.size()-1,-1,-1):
		var line: Dictionary=s.deadlines[i]
		if line["source"]!=ship.id: continue
		if line.get("slot",-1)==slot and line.get("epoch",-1)==s.space_epoch and line["b"].distance_squared_to(a)<1e-14 and (b-a).normalized().dot((line["b"]-line["a"]).normalized())>1.0-1e-7:
			line["pieces"].append(piece)
			line["b"]=b
			line["ended"]=s.clock
			line["expires"]=piece["expires"]
			return
		break
	s.deadlines.append({"id":s.next_id(),"source":ship.id,"a":a,"b":b,
		"created":s.clock-duration,"ended":s.clock,"expires":piece["expires"],"turn":s.turn,"slot":slot,"epoch":s.space_epoch,"pieces":[piece]})


## 局部光速的不连续边界必须分段；场内连续权重使用最大步长积分并做减半收敛测试。
static func next_boundary(s: GameState, motion: Dictionary, dt: float) -> float:
	var best := Kinematics.next_cell_boundary(motion)
	if motion["velocity"].length_squared() + motion["acceleration"].length_squared() < 1e-20:
		return best
	var scale := s.physical_cell_size()
	for source in s.black_domains:
		for r in [Balance.DOMAIN_CORE, radius(s, source, s.clock)]:
			var growth: float = Balance.DOMAIN_SPREAD * s.background_light() / scale if r != Balance.DOMAIN_CORE and r < Balance.DOMAIN_RADIUS else 0.0
			var shape := {"a": source["pos"], "b": source["pos"], "r": r / scale, "growth": growth}
			best = minf(best, _surface(motion, shape, dt))
	for line in s.deadlines:
		best = minf(best, _surface(motion, {"a": line["a"], "b": line["b"], "r": Balance.DEADLINE_RADIUS / scale, "growth": 0.0}, dt))
	return best


static func _surface(motion: Dictionary, shape: Dictionary, dt: float) -> float:
	var lo := 4.0 * Balance.TIME_EPSILON
	if dt <= lo:
		return INF
	if absf(_surface_value(motion, shape, lo)) < 1e-10 and absf(_surface_value(motion, shape, dt)) < 1e-10 and absf(_surface_value(motion, shape, (dt + lo) * 0.5)) < 1e-10:
		return INF
	var sign_at_start := signf(_surface_value(motion, shape, lo))
	return _surface_root(motion, shape, sign_at_start, lo, dt)


static func _surface_value(motion: Dictionary, shape: Dictionary, t: float) -> float:
	return segment_distance(Kinematics.position(motion, t), shape["a"], shape["b"]) - shape["r"] - shape["growth"] * t


static func _surface_root(motion: Dictionary, shape: Dictionary, initial: float, lo: float, hi: float) -> float:
	var f := _surface_value(motion, shape, lo)
	if signf(f) != initial:
		return lo
	var speed: float = motion["velocity"].length() + motion["acceleration"].length() * hi + absf(shape["growth"])
	if absf(f) > speed * (hi - lo) + 1e-10:
		return INF
	if hi - lo <= Balance.TIME_EPSILON:
		return hi if signf(_surface_value(motion, shape, hi)) != initial else INF
	var mid := (lo + hi) * 0.5
	var left := _surface_root(motion, shape, initial, lo, mid)
	return left if left != INF else _surface_root(motion, shape, initial, mid, hi)


static func next_change(s: GameState) -> float:
	var next := INF
	for source in s.black_domains:
		next = minf(next, maxf(0.0, source["expires"] - s.clock))
	for life in s.domain_cells.values():
		for value in [life["expires"], life["immune_until"]]:
			if value > s.clock:
				next = minf(next, value - s.clock)
	for line in s.deadlines:
		for piece in pieces(line):
			next = minf(next, maxf(0.0, piece["expires"] - s.clock))
	return next
