class_name Geometry
extends RefCounted
## 沿方向行动用到的几何计算。格子看作边长 1 的小方块，中心在整数坐标上。

## 格子中心到格子边的距离。圆锥只要擦到格子，就算覆盖了这个格子。
const CELL_HALF := 0.5


## 从 origin 朝 direction 发出的圆锥覆盖哪些格子（不含 origin 自己）。
## full_angle_deg 是圆锥张开的总角度，length 是沿方向能伸多远。
static func cone_cells(origin: Vector3i, direction: Vector3, length: float,
		full_angle_deg: float) -> Array[Vector3i]:
	var spread := tan(deg_to_rad(full_angle_deg / 2.0))
	return _along(origin, direction, 0.0, length, func(t: float) -> float: return t * spread)


## 从 origin 朝 direction 发出的圆柱覆盖哪些格子（不含 origin 自己），
## 按离 origin 由近到远排列。radius 是圆柱半径。
static func cylinder_cells(origin: Vector3i, direction: Vector3, length: float,
		radius: float) -> Array[Vector3i]:
	return cylinder_cells_between(origin, direction, 0.0, length, radius)


## 圆柱中沿方向距离在 (from_t, to_t] 之间的一段。战舰每回合只检查新飞过的这一段。
static func cylinder_cells_between(origin: Vector3i, direction: Vector3, from_t: float,
		to_t: float, radius: float) -> Array[Vector3i]:
	return _along(origin, direction, from_t, to_t, func(_t: float) -> float: return radius)


## 沿方向扫描：走到 t 处时，离中轴线不超过 width(t) + 半个格子的格子都算覆盖。
## 只要 t 在 (from_t, to_t] 之间的格子，结果按 t 由近到远排列。
static func _along(origin: Vector3i, direction: Vector3, from_t: float, to_t: float,
		width: Callable) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if direction.length() < 1e-6 or to_t <= from_t:
		return result
	var dir := direction.normalized()
	var hits: Array = []  # [t, 格子]
	var r := ceili(to_t) + 3
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var c := origin + Vector3i(dx, dy, dz)
				if c == origin or not StarMap.in_bounds(c):
					continue
				var v := Vector3(c - origin)
				# t：沿方向走了多远；off：离中轴线多远
				var t := v.dot(dir)
				if t <= maxf(from_t, 0.0) or t > to_t:
					continue
				var off := (v - dir * t).length()
				if off <= width.call(t) + CELL_HALF:
					hits.append([t, c])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	for h in hits:
		result.append(h[1])
	return result
