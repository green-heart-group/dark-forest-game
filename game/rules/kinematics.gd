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
		var vv := v.length_squared()
		if vv < 1e-18:
			return INF
		var rv := r.dot(v)
		var discriminant := rv * rv - vv * (r.length_squared() - radius * radius)
		if discriminant < 0.0:
			return INF
		var hit := (-rv - sqrt(discriminant)) / vv
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


## 对直线推进在每个格界硬分段，进入已转换格、硬到期格和图外边界不会等到年末。
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
