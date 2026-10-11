class_name Hazards
extends RefCounted
## 有界黑域与曲率死线。时间用世界时钟；同一格的硬到期不会被后来的源延长。

## 光走到格子边界上时，查光速前沿前进方向挪这么多格，免得按刚离开的那一格算。
const LIGHT_NUDGE := 1e-6


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


## 算光速时用的黑域半径。长大的时候，从释放那一刻起每 ROUGH_DT 年算一段，段内都用这一段结束时的大小：
## 半径越大光越慢，所以只会算慢、不会算快，消息不会早到。长到最大以后就是最大半径。
static func field_radius(s: GameState, source: Dictionary) -> float:
	var end := _growth_piece_end(s, source)
	return Balance.DOMAIN_RADIUS if end == INF else radius(s, source, end)


## 黑域还在长大时，现在所在那一段在什么时刻结束；已经长到最大时为 INF。
static func _growth_piece_end(s: GameState, source: Dictionary) -> float:
	var age: float = s.clock - source["created"]
	if age * Balance.DOMAIN_SPREAD * s.background_light() >= Balance.DOMAIN_RADIUS:
		return INF
	return source["created"] + (floorf(age / Balance.ROUGH_DT + Balance.TIME_EPSILON) + 1.0) * Balance.ROUGH_DT


## 这一点在不在某个黑域里面（光速随位置连续变化的地方）。在里面飞的东西每段最长 ROUGH_DT 年。
static func in_field(s: GameState, pos: Vector3) -> bool:
	for source in s.black_domains:
		if pos.distance_to(source["pos"]) * s.physical_cell_size() <= field_radius(s, source) + 1e-8:
			return true
	return false


static func refresh(s: GameState) -> void:
	s.ensure_cells()
	# 到期的黑域和死线马上要删掉、黑域里到期的格子马上不再受影响，那里光速会变快：
	# 先把经过那里的消息按还没变的光速挪到现在的位置（到期那一刻 suppression 仍算它们，标记 "lapsed" 以后才不算）。
	var ending := []
	for source in s.black_domains:
		if source["expires"] <= s.clock:
			ending.append(Signals.domain_shape(s, source))
	for line in s.deadlines:
		if line["expires"] <= s.clock:
			ending.append(Signals.deadline_shape(s, line))
	var lapsed := {}
	for id in s.domain_cells:
		if s.clock >= s.domain_cells[id]["expires"] and not s.domain_cells[id].get("lapsed", false):
			lapsed[id] = true
	var lapsed_cells: Array[Vector3i] = []
	if not lapsed.is_empty():
		for cell in s.cell_ids:
			if lapsed.has(s.cell_ids[cell]):
				lapsed_cells.append(cell)
	if not ending.is_empty() or not lapsed_cells.is_empty():
		Signals.before_light_change(s, lapsed_cells, ending)
	for id in lapsed:
		s.domain_cells[id]["lapsed"] = true
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
		if s.cell_dims.get(s.cell_ids[cell], s.dimension) != s.dimension or s.light_at(cell) != 1.0:
			return false
	return true


static func suppression(s: GameState, position: Vector3) -> float:
	if not any(s):
		return 1.0
	var relative := 1.0
	var cell := Vector3i(position.round())
	var life: Dictionary = s.domain_cells.get(s.cell_ids.get(cell, -1), {})
	# 到期那一刻还算受影响，refresh 先按还没变的光速挪好在途消息、标上 lapsed 以后才不算（和黑域本身一样）。
	var ignores: bool = not life.is_empty() and (s.clock > life["expires"] or life.get("lapsed", false)) and s.clock < life["immune_until"]
	if not ignores:
		var weight := 0.0
		for source in s.black_domains:
			if source["expires"] < s.clock:
				continue
			var reach := field_radius(s, source)
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
		if line["expires"] >= s.clock and segment_distance(position, line["a"], line["b"]) * s.physical_cell_size() <= Balance.DEADLINE_RADIUS:
			relative = minf(relative, Balance.DEADLINE_FACTOR)
	return relative


static func leave_deadline(s: GameState, a: Vector3, b: Vector3, ship: Ship, duration := 0.0) -> void:
	if a.distance_squared_to(b) < 1e-15:
		return
	var piece: Dictionary={"a":a,"b":b,"created":s.clock-duration,"ended":s.clock,"expires":s.clock+Balance.DEADLINE_LIFETIME}
	var slot:=floori(s.clock-duration+Balance.TIME_EPSILON)
	# 同一年里接着走的直线段共享身份。消息到达等切分不能再制造新航迹和新回报。
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


## 一点的光速。table 是 LightFront.environment 存下的光速表（只在没有黑域和死线时用）：
## 照那份表查，表里没有的格子是背景光速；不给 table 就查现在的局面。
static func light_speed(s: GameState, table: Dictionary, pos: Vector3) -> float:
	if table.is_empty():
		return s.light_speed_at(pos)
	return table["speeds"].get(Vector3i(pos.round()), table["speed"])


## 光和消息（匀速直线）下一次真的换光速是什么时候，最多看 dt 年。
## 没有黑域和死线时，每格光速固定；过边界后光速不变的，停下来什么都不变，就跳过去接着往前看。
## 有黑域或死线时光速在格子里也会变，照旧用 next_boundary。
## start 是起点，velocity 是每年走多少格。
static func next_light_edge(s: GameState, start: Vector3, velocity: Vector3, dt: float, table := {}) -> float:
	if table.is_empty() and any(s):
		return next_boundary(s, {"pos": start, "velocity": velocity, "acceleration": Vector3.ZERO}, dt)
	if velocity.length_squared() < 1e-20:
		return INF
	if not table.is_empty() and table["speeds"].is_empty():
		return INF
	# 边界上的点按前进方向归到下一格（Vector3i(round()) 在 .5 处往远离 0 的方向取整，往负方向走时会归回上一格）。
	var nudge := velocity.normalized() * LIGHT_NUDGE
	var here := light_speed(s, table, start + nudge)
	var pos := start
	var t := 0.0
	for i in 8:
		var edge := Kinematics.straight_cell_exit(pos, velocity)
		if t + edge > dt:
			return INF
		t += edge
		pos = start + velocity * t
		if light_speed(s, table, pos + nudge) != here:
			return t
	return t


## 光或消息从 pos 沿 direction 走 duration 年，最多走 remaining（物理距离）。
## 在一个子步里自己分段：每段用这一段起点的光速，到光速会变的地方（next_light_edge）换一段。
## 有黑域或死线时改用 _field_travel：黑域里光速随位置连续变化，按公式算准每段的用时。
## 返回走了多远（distance）、到达终点用了多久（arrival，没到为 INF）、实际走了多久（time）。光速为 0 的地方走不动。
## 每段至少走 TIME_EPSILON 年，所以不限段数也一定会停；一维的长直线上可能要分几百段。
static func light_travel(s: GameState, pos: Vector3, direction: Vector3, remaining: float, duration: float, table := {}) -> Dictionary:
	if table.is_empty() and any(s):
		return _field_travel(s, pos, direction, remaining, duration)
	var size := s.physical_cell_size()
	var t := 0.0
	var moved := 0.0
	while true:
		var need := remaining - moved
		if need <= 0.0:
			return {"distance": remaining, "arrival": t}
		if t >= duration:
			break
		var at := pos + direction * moved / size
		var speed := light_speed(s, table, at + direction * LIGHT_NUDGE)
		if speed <= 0.0:
			break
		var left := minf(duration - t, need / speed)
		var edge := next_light_edge(s, at, direction * speed / size, left, table)
		var step := minf(left, maxf(edge, Balance.TIME_EPSILON))
		if step >= need / speed:
			return {"distance": remaining, "arrival": t + need / speed}
		moved += speed * step
		t += step
	return {"distance": moved, "arrival": INF, "time": t}


## 有黑域或死线时的 light_travel。在格子边界、黑域表面和中心、死线边界处分段；
## 段内格子、死线和覆盖的黑域都不变，光速只随到各黑域中心的距离变，用时按公式算（_field_time）。
static func _field_travel(s: GameState, pos: Vector3, direction: Vector3, remaining: float, duration: float) -> Dictionary:
	var size := s.physical_cell_size()
	var t := 0.0
	var moved := 0.0
	while true:
		var need := remaining - moved
		if need <= 0.0:
			return {"distance": remaining, "arrival": t}
		if t >= duration:
			break
		var at := pos + direction * moved / size
		var piece := minf(need, maxf(_field_edge(s, at, direction, need), Balance.TIME_EPSILON))
		var field := _field(s, at, direction, piece)
		if field.is_empty():
			break
		var cost := _field_time(field, piece)
		if t + cost > duration:
			moved += _field_reach(field, piece, duration - t)
			t = duration
			break
		t += cost
		if piece >= need:
			return {"distance": remaining, "arrival": t}
		moved += piece
	return {"distance": moved, "arrival": INF, "time": t}


## 从 at 沿 direction 走多远（物理距离）光速的算法会变：出格子、碰到黑域表面或中心、进出死线。最多看 limit。
## 黑域半径取现在的大小，和 suppression 一样。
static func _field_edge(s: GameState, at: Vector3, direction: Vector3, limit: float) -> float:
	var size := s.physical_cell_size()
	var motion := {"pos": at, "velocity": direction, "acceleration": Vector3.ZERO}
	var best := minf(Kinematics.straight_cell_exit(at, direction), limit / size)
	for source in s.black_domains:
		for r in [Balance.DOMAIN_CORE, field_radius(s, source)]:
			best = minf(best, _surface(motion, {"a": source["pos"], "b": source["pos"], "r": r / size, "growth": 0.0}, best))
	for line in s.deadlines:
		best = minf(best, _surface(motion, {"a": line["a"], "b": line["b"], "r": Balance.DEADLINE_RADIUS / size, "growth": 0.0}, best))
	return best * size


## 从 at 沿 direction 走 piece（物理距离）这一段的光速：{"c": 这一格的背景光速, "floor": 1 / 上限比例,
## "domains": 覆盖这一段的黑域 [{"u": 起点沿方向离中心多远, "b2": 直线离中心最近距离的平方, "k": 权重 / 半径}],
## "lo"、"hi": 黑域减速比上限更慢的那一截}。光速为 0（在黑域中心或零维格子里）时为空。
## 这一点的相对光速是 min(上限, 1 / (1 + 各黑域权重之和))，上限是格子自己的光速和死线的 0.8 中较小的。
static func _field(s: GameState, at: Vector3, direction: Vector3, piece: float) -> Dictionary:
	var size := s.physical_cell_size()
	var mid := at + direction * (0.5 * piece / size)
	var cell := Vector3i(mid.round())
	var id: int = s.cell_ids.get(cell, -1)
	var dim: int = s.cell_dims.get(id, s.dimension)
	if dim == 0:
		return {}
	var c: float = s.background_light() if dim == s.dimension else Balance.DIMENSION_LIGHT[str(dim)]
	var cap := minf(s.light_at(cell), 1.0)
	for line in s.deadlines:
		if line["expires"] >= s.clock and segment_distance(mid, line["a"], line["b"]) * size <= Balance.DEADLINE_RADIUS:
			cap = minf(cap, Balance.DEADLINE_FACTOR)
	if c <= 0.0 or cap <= 0.0:
		return {}
	var domains := []
	var life: Dictionary = s.domain_cells.get(id, {})
	if life.is_empty() or (s.clock <= life["expires"] and not life.get("lapsed", false)) or s.clock >= life["immune_until"]:
		for source in s.black_domains:
			if source["expires"] < s.clock:
				continue
			var reach := field_radius(s, source)
			var distance: float = mid.distance_to(source["pos"]) * size
			if reach <= 0.0 or distance > reach + 1e-8:
				continue
			if distance <= Balance.DOMAIN_CORE:
				return {}
			var offset: Vector3 = (at - source["pos"]) * size
			var u := offset.dot(direction)
			domains.append({"u": u, "b2": maxf(0.0, offset.length_squared() - u * u), "k": Balance.DOMAIN_WEIGHT / reach})
	var field := {"c": c, "floor": 1.0 / cap, "domains": domains, "lo": 0.0, "hi": 0.0}
	if domains.is_empty():
		return field
	# 1 + 权重之和沿直线是凸起的一条（各项是负的到中心距离），比上限更慢的部分是一整截 [lo, hi]。
	var top := _field_peak(field, piece)
	if _field_slowness(field, top) <= field["floor"]:
		return field
	field["lo"] = 0.0 if _field_slowness(field, 0.0) > field["floor"] else _field_cross(field, 0.0, top)
	field["hi"] = piece if _field_slowness(field, piece) > field["floor"] else _field_cross(field, piece, top)
	return field


## 不算上限时，走 x 处每走 1 光年要多少年（乘以背景光速）：1 + 各黑域权重之和。
static func _field_slowness(field: Dictionary, x: float) -> float:
	var value := 1.0
	for d in field["domains"]:
		value += Balance.DOMAIN_WEIGHT - d["k"] * sqrt(d["b2"] + (d["u"] + x) * (d["u"] + x))
	return value


## _field_slowness 在 [0, piece] 上最大的位置（它的斜率一路变小，二分找斜率为 0 处）。
static func _field_peak(field: Dictionary, piece: float) -> float:
	if _field_slope(field, 0.0) <= 0.0:
		return 0.0
	if _field_slope(field, piece) >= 0.0:
		return piece
	var lo := 0.0
	var hi := piece
	for i in 60:
		var mid := (lo + hi) * 0.5
		if _field_slope(field, mid) > 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func _field_slope(field: Dictionary, x: float) -> float:
	var value := 0.0
	for d in field["domains"]:
		var along: float = d["u"] + x
		var distance := sqrt(d["b2"] + along * along)
		if distance > 0.0:
			value -= d["k"] * along / distance
	return value


## 在 outside（比上限快）和 top（比上限慢）之间，找 _field_slowness 正好等于上限的位置。
static func _field_cross(field: Dictionary, outside: float, top: float) -> float:
	var a := outside
	var b := top
	for i in 60:
		var mid := (a + b) * 0.5
		if _field_slowness(field, mid) > field["floor"]:
			b = mid
		else:
			a = mid
	return (a + b) * 0.5


## 从这一段起点走 x（物理距离）要多少年。比上限慢的那一截用积分公式，其余按上限的光速。
static func _field_time(field: Dictionary, x: float) -> float:
	var lo := minf(x, field["lo"])
	var hi := minf(x, field["hi"])
	var slow := 0.0
	if hi > lo:
		slow = (1.0 + Balance.DOMAIN_WEIGHT * field["domains"].size()) * (hi - lo)
		for d in field["domains"]:
			slow -= d["k"] * (_distance_integral(d["u"] + hi, d["b2"]) - _distance_integral(d["u"] + lo, d["b2"]))
	return (field["floor"] * (x - (hi - lo)) + slow) / field["c"]


## 走 time 年能走多远，最多 piece。用时随距离只增不减，二分找。
static func _field_reach(field: Dictionary, piece: float, time: float) -> float:
	var lo := 0.0
	var hi := piece
	for i in 60:
		var mid := (lo + hi) * 0.5
		if _field_time(field, mid) > time:
			hi = mid
		else:
			lo = mid
	return lo


## 到一点距离 sqrt(b2 + u²) 对 u 的积分（从 0 积到 u）：(u·sqrt(b2 + u²) + b2·arsinh(u / sqrt(b2))) / 2。
static func _distance_integral(u: float, b2: float) -> float:
	var root := sqrt(b2 + u * u)
	var value := u * root
	if b2 > 1e-24:
		var ratio := absf(u) / sqrt(b2)
		value += b2 * signf(u) * log(ratio + sqrt(ratio * ratio + 1.0))
	return 0.5 * value

## 动的东西下一次碰到光速算法会变的地方：进入规则不同的格子（next_cell_change）、黑域表面和中心、死线边界。
## 黑域半径在一段里不变（field_radius），长大时每段结束另外切开（next_change）。
## grain 为真时再加上光粒失效的那一层：单个黑域里光速正好等于 GRAIN_MIN_LIGHT 的球面（几个黑域重叠时只是近似）。
static func next_boundary(s: GameState, motion: Dictionary, dt: float, grain := false) -> float:
	var best := next_cell_change(s, motion, dt)
	if motion["velocity"].length_squared() + motion["acceleration"].length_squared() < 1e-20:
		return best
	var scale := s.physical_cell_size()
	for source in s.black_domains:
		var reach := field_radius(s, source)
		var radii := [Balance.DOMAIN_CORE, reach]
		if grain:
			radii.append(reach * (1.0 - (1.0 / Balance.GRAIN_MIN_LIGHT - 1.0) / Balance.DOMAIN_WEIGHT))
		for r in radii:
			best = minf(best, _surface(motion, {"a": source["pos"], "b": source["pos"], "r": r / scale, "growth": 0.0}, dt))
	for line in s.deadlines:
		best = minf(best, _surface(motion, {"a": line["a"], "b": line["b"], "r": Balance.DEADLINE_RADIUS / scale, "growth": 0.0}, dt))
	return best


## 按 motion 走，最多看 dt 年，下一次进入「格子规则」（_cell_rule）和现在这一格不同的格子是什么时候。
## 前后两格的维度、光速、黑域留下的寿命都一样时，过边界什么都不变，不用停下，接着往前看。
static func next_cell_change(s: GameState, motion: Dictionary, dt: float) -> float:
	var velocity: Vector3 = motion["velocity"]
	var acceleration: Vector3 = motion["acceleration"]
	if velocity.length_squared() + acceleration.length_squared() < 1e-20:
		return Kinematics.next_cell_boundary(motion)
	var here := _cell_rule(s, _cell_ahead(motion, 0.0))
	var t := 0.0
	# 一步最多看 32 个边界，再多就在那里停一下，下一步接着看。
	for i in 32:
		var at := {"pos": Kinematics.position(motion, t), "velocity": velocity + acceleration * t, "acceleration": acceleration}
		var edge := Kinematics.next_cell_boundary(at)
		if t + edge > dt:
			return INF
		t += edge
		if _cell_rule(s, _cell_ahead(motion, t)) != here:
			return t
	return t


## 时刻 t 所在的格子；正好在边界上时，归到前进方向的那一格。
static func _cell_ahead(motion: Dictionary, t: float) -> Vector3i:
	var heading: Vector3 = motion["velocity"] + motion["acceleration"] * t
	if heading.length_squared() < 1e-20:
		heading = motion["acceleration"]
	return Vector3i((Kinematics.position(motion, t) + heading.normalized() * LIGHT_NUDGE).round())


## 一格里决定光速和存续的东西：在不在图上、维度、格子光速、黑域留下的寿命。两格的这几样都一样，过边界就什么都不变。
static func _cell_rule(s: GameState, cell: Vector3i) -> Array:
	var id: int = s.cell_ids.get(cell, -1)
	return [s.map.contains(cell), s.cell_dims.get(id, s.dimension), s.light_at(cell), s.domain_cells.get(id, {})]


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
		# 还在长大时，每段结束换一次半径（field_radius）。
		next = minf(next, _growth_piece_end(s, source) - s.clock)
	for life in s.domain_cells.values():
		for value in [life["expires"], life["immune_until"]]:
			if value > s.clock:
				next = minf(next, value - s.clock)
	for line in s.deadlines:
		for piece in pieces(line):
			next = minf(next, maxf(0.0, piece["expires"] - s.clock))
	return next
