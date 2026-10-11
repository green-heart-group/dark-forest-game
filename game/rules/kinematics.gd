class_name Kinematics
extends RefCounted
## 时间用年，速度/距离用物理ly；只有与原视图交界时才转换成逻辑格。
## 在分段恒定加速度内求距离及首次相对接触，移动交叉不会被步末检查漏掉。


static func distance(speed: float, acceleration: float, duration: float) -> float:
	return speed * duration + 0.5 * acceleration * duration * duration


static func time_to_distance(length: float, speed: float, acceleration: float) -> float:
	if length <= 0.0:
		return 0.0
	if acceleration <= 0.0:
		return length / speed if speed > 0.0 else INF
	# 等价于(-v+sqrt(v²+2ax))/a，但在小距离时避免相减损失。
	return 2.0 * length / (speed + sqrt(speed * speed + 2.0 * acceleration * length))


static func uses_relative_speed(ship: Ship) -> bool:
	return Balance.SHIP_SPEED_RELATIVE == 1 and ship.kind in [Ship.PROBE,Ship.NUCLEAR_PROBE,Ship.COLONY,Ship.DEVOURER]


## 四类普通船以当地及实体维度的较低光速缩放速度和加速度；旧记录保留绝对数值。
static func normal_limits(s: GameState, ship: Ship, pos: Vector3) -> Array[float]:
	var local_c := s.light_speed_at(pos)
	var entity_c: float = Balance.DIMENSION_LIGHT[str(ship.entity_dim)] * s.relative_light(pos)
	var top := minf(ship.max_speed, minf(local_c, entity_c))
	var acceleration := ship.accel
	if uses_relative_speed(ship):
		top = ship.max_speed * minf(local_c,entity_c)
		acceleration = ship.accel * minf(local_c,entity_c)
	elif ship.kind == Ship.GRAIN:
		top = Balance.GRAIN_MOVE[0] * local_c
	elif ship.kind == Ship.SOPHON:
		top = Balance.SOPHON_MOVE[0] * minf(local_c, entity_c)
	return [top,acceleration]


static func limits(s: GameState, civ: Civ, ship: Ship, pos: Vector3, slow: bool) -> Array[float]:
	var bounds := normal_limits(s,ship,pos)
	var top := bounds[0]
	var acceleration := bounds[1]
	if ship.warp and ship.kind in [Ship.WARSHIP, Ship.COLONY, Ship.STARSHIP, Ship.DEVOURER] \
			and civ != null and not in_owned_system_vision(s, civ, pos):
		top = minf(s.light_speed_at(pos),Balance.DIMENSION_LIGHT[str(ship.entity_dim)] * s.relative_light(pos))
		acceleration = Balance.WARP_MOVE[1]
	if slow and civ != null and in_owned_system_vision(s,civ,pos):
		top = minf(top, Balance.SLOW_START_SPEED)
	return [top, acceleration]


static func in_owned_system_vision(s: GameState, civ: Civ, pos: Vector3) -> bool:
	for at in civ.colonies:
		var radius := (Balance.VISION_HOME if at == civ.home else Balance.VISION_COLONY) + civ.vision_bonus()
		if pos.distance_to(Vector3(at)) * s.physical_cell_size() <= radius:
			return true
	return false


## 按 motion 走，最多看 dt 年，下一次进出己方星系视野（in_owned_system_vision 的那些球）是什么时候。
static func next_vision_edge(s: GameState, civ: Civ, motion: Dictionary, dt: float) -> float:
	var best := INF
	if civ == null or motion["velocity"].length_squared() + motion["acceleration"].length_squared() < 1e-20:
		return best
	for at in civ.colonies:
		var radius := (Balance.VISION_HOME if at == civ.home else Balance.VISION_COLONY) + civ.vision_bonus()
		best = minf(best, Hazards._surface(motion, {"a": Vector3(at), "b": Vector3(at), "r": radius / s.physical_cell_size(), "growth": 0.0}, minf(dt, best)))
	return best


## 返回逻辑格上的二次轨迹；在cap_time处必须分段，再读取当地光速。
static func motion(s: GameState, civ: Civ, ship: Ship, duration: float) -> Dictionary:
	var velocity := Vector3.ZERO
	var acceleration := Vector3.ZERO
	var speed := 0.0
	var cap_time := INF
	var arrival := INF
	var goal:=ship.target
	if ship.kind==Ship.STARSHIP and civ!=null and ship.has_target:
		# 自主避开已经在舰上确认的敌方星系；不读尚未送达的全局归属。
		for contact in ship.local_contacts.values():
			if contact["kind"]=="anchor" and contact["owner"]>=0 and contact["owner"]!=s.civs.find(civ) and contact["pos"].is_equal_approx(ship.target):
				goal=ship.target-ship.direction/s.physical_cell_size() if ship.pos.distance_to(ship.target)*s.physical_cell_size()>1.0 else ship.pos
				break
	if ship.moving() and not ship.dormant and not ship.work_locked and s.clock >= ship.pause_until:
		var bounds := limits(s, civ, ship, ship.pos, ship.slow_start)
		speed = minf(ship.speed, bounds[0])
		if ship.kind in [Ship.PROBE, Ship.GRAIN]:
			speed = bounds[0]
		var acc := bounds[1] if speed < bounds[0] - 1e-10 else 0.0
		if acc > 0:
			cap_time = (bounds[0] - speed) / acc
		velocity = ship.direction * speed / s.physical_cell_size()
		acceleration = ship.direction * acc / s.physical_cell_size()
		if ship.has_target:
			arrival = time_to_distance(ship.pos.distance_to(goal) * s.physical_cell_size(), speed, acc)
	return {"pos": ship.pos, "velocity": velocity, "acceleration": acceleration,
			"speed": speed, "cap_time": cap_time, "arrival": arrival, "duration": duration,"target":goal}


static func position(motion: Dictionary, t: float) -> Vector3:
	return motion["pos"] + motion["velocity"] * t + 0.5 * motion["acceleration"] * t * t


## 相对二次轨迹首次进入闭球。静止/匀速用解析根；加速时用弦段包围界剪枝。
## 弦与抛物线偏离至多|a|dt²/8；递归到时间精度后保留该空间误差上界。
static func first_contact(r: Vector3, v: Vector3, a: Vector3, radius: float, duration: float) -> float:
	if r.length_squared() <= radius * radius:
		return 0.0
	if a.length_squared() < 1e-18:
		# 先找最近点，再按最近距离算进球的时刻。不用「rv² − vv·(r² − 半径²)」：坐标是单精度，
		# 离得远时两个大数相减的误差比碰撞半径的平方还大，会把正对着的碰撞算漏。各分量取出来按双精度算。
		var rx := r.x
		var ry := r.y
		var rz := r.z
		var vx := v.x
		var vy := v.y
		var vz := v.z
		var vv := vx * vx + vy * vy + vz * vz
		if vv < 1e-18:
			return INF
		var closest := -(rx * vx + ry * vy + rz * vz) / vv
		var cx := rx + vx * closest
		var cy := ry + vy * closest
		var cz := rz + vz * closest
		var miss := cx * cx + cy * cy + cz * cz
		if miss > radius * radius:
			return INF
		var hit := closest - sqrt((radius * radius - miss) / vv)
		return hit if hit >= 0.0 and hit <= duration else INF
	return _curved_contact(r, v, a, radius, 0.0, duration)


static func _curved_contact(r: Vector3, v: Vector3, a: Vector3, radius: float, lo: float, hi: float) -> float:
	var start := r + v * lo + 0.5 * a * lo * lo
	if start.length_squared() <= radius * radius:
		return lo
	var end := r + v * hi + 0.5 * a * hi * hi
	var chord := end - start
	var fraction := clampf(-start.dot(chord) / chord.length_squared(), 0.0, 1.0) if chord.length_squared() > 1e-18 else 0.0
	var bound := a.length() * (hi - lo) * (hi - lo) / 8.0
	if (start + chord * fraction).length() > radius + bound:
		return INF
	if hi - lo <= Balance.TIME_EPSILON:
		return lo
	var mid := (lo + hi) * 0.5
	var left := _curved_contact(r, v, a, radius, lo, mid)
	return left if left != INF else _curved_contact(r, v, a, radius, mid, hi)


static func relative_contact(first: Dictionary, second: Dictionary, radius: float, duration: float) -> float:
	return first_contact(first["pos"] - second["pos"], first["velocity"] - second["velocity"],
			first["acceleration"] - second["acceleration"], radius, duration)


## 下一次走到格子边界是什么时候。结算时只在规则不同的格子边界停下（Hazards.next_cell_change），这里只管找边界。
static func next_cell_boundary(motion: Dictionary) -> float:
	var best := INF
	for axis in 3:
		var v: float = motion["velocity"][axis]
		var a: float = motion["acceleration"][axis]
		var sign_value := signf(v if absf(v) > 1e-15 else a)
		if sign_value == 0.0:
			continue
		var x: float = motion["pos"][axis]
		var cell := floorf(x + 0.5 + sign_value * 1e-7)
		var boundary := cell + (0.5 if sign_value > 0 else -0.5)
		var distance_to_edge := absf(boundary - x)
		best = minf(best, time_to_distance(distance_to_edge, absf(v), absf(a)))
	return best


## 匀速直线（没有加速度）时的 next_cell_boundary，结果相同。光和消息分段时每个子步要算几十万次，所以单独写一份不建字典的。
static func straight_cell_exit(pos: Vector3, velocity: Vector3) -> float:
	var best := INF
	for axis in 3:
		var v: float = velocity[axis]
		if absf(v) <= 1e-15:
			continue
		var x: float = pos[axis]
		var boundary := floorf(x + 0.5 + signf(v) * 1e-7) + (0.5 if v > 0.0 else -0.5)
		var edge := absf(boundary - x)
		if edge > 0.0:
			best = minf(best, edge / absf(v))
		else:
			best = 0.0
	return best
