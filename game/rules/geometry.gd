class_name Geometry
extends RefCounted
## 沿方向行动用到的几何计算。格子看作边长 1 的小方块，中心在整数坐标上。

## 格子中心到格子边的距离。圆锥只要擦到格子，就算覆盖了这个格子。
const CELL_HALF := 0.5


## 从 origin 朝 direction 发出的圆锥覆盖哪些格子（不含 origin 所在的格子）。
## full_angle_deg 是圆锥张开的总角度，length 是沿方向能伸多远。
static func cone_cells(origin: Vector3, direction: Vector3, length: float,
		full_angle_deg: float, bounds: AABB) -> Array[Vector3i]:
	var spread := tan(deg_to_rad(full_angle_deg / 2.0))
	return _along(origin, direction, 0.0, length, func(t: float) -> float: return t * spread, bounds)


## 从 origin 朝 direction 发出的圆柱覆盖哪些格子（不含 origin 所在的格子），
## 按离 origin 由近到远排列。radius 是圆柱半径。
static func cylinder_cells(origin: Vector3, direction: Vector3, length: float,
		radius: float, bounds: AABB) -> Array[Vector3i]:
	return cylinder_cells_between(origin, direction, 0.0, length, radius, bounds)


## 圆柱中沿方向距离在 (from_t, to_t] 之间的一段。
static func cylinder_cells_between(origin: Vector3, direction: Vector3, from_t: float,
		to_t: float, radius: float, bounds: AABB) -> Array[Vector3i]:
	return _along(origin, direction, from_t, to_t, func(_t: float) -> float: return radius, bounds)


## 一回合里从 a 飞到 b 扫过的格子：离线段不超过 radius + 半个格子、沿线段的位置在 (a, b] 之间。
## 按离 a 由近到远排列。
static func segment_cells(a: Vector3, b: Vector3, radius: float, bounds: AABB) -> Array[Vector3i]:
	var d := b - a
	if d.length() < 1e-9:
		return []
	return cylinder_cells_between(a, d, 0.0, d.length(), radius, bounds)


## 以 center 为中心、半径 r 的球里的格子（格子中心离球心不超过 r）。
static func sphere_cells(center: Vector3, r: float, bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var lo := Vector3i((center - Vector3.ONE * r).floor())
	var hi := Vector3i((center + Vector3.ONE * r).ceil())
	for x in range(maxi(lo.x, int(bounds.position.x)), mini(hi.x, int(bounds.end.x) - 1) + 1):
		for y in range(maxi(lo.y, int(bounds.position.y)), mini(hi.y, int(bounds.end.y) - 1) + 1):
			for z in range(maxi(lo.z, int(bounds.position.z)), mini(hi.z, int(bounds.end.z) - 1) + 1):
				var c := Vector3i(x, y, z)
				if Vector3(c).distance_to(center) <= r + 1e-6:
					result.append(c)
	return result


## 沿方向扫描：走到 t 处时，离中轴线不超过 width(t) + 半个格子的格子都算覆盖。
## 只要 t 在 (from_t, to_t] 之间的格子，结果按 t 由近到远排列。
static func _along(origin: Vector3, direction: Vector3, from_t: float, to_t: float,
		width: Callable, bounds: AABB) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if direction.length() < 1e-6 or to_t <= from_t:
		return result
	var dir := direction.normalized()
	var hits: Array = []  # [t, 格子]
	# 覆盖的格子离这一段中轴线不超过 width + 半格，只要扫这一段外面包一层的方盒（宽度随 t 只增不减，取最远处的）
	var pad: float = width.call(to_t) + CELL_HALF + 1e-3
	var a := origin + dir * maxf(from_t, 0.0)
	var b := origin + dir * to_t
	var lo := Vector3i((a.min(b) - Vector3.ONE * pad).ceil().max(bounds.position))
	var hi := Vector3i((a.max(b) + Vector3.ONE * pad).floor().min(bounds.end - Vector3.ONE))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var c := Vector3i(x, y, z)
				# 起点所在的格子 t 为 0，下面的 t > 0 会把它排除
				if not bounds.has_point(Vector3(c) + Vector3.ONE * 0.5):
					continue
				var v := Vector3(c) - origin
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
