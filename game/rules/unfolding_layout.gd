extends RefCounted
## 共享的纯数据布局。规则坐标 z 向上；编号始终来自原三维格子。
## 不依赖 GameState，不把渲染位置写回正式规则。

const SIZE := 9
const COUNT := SIZE * SIZE * SIZE
# 从 +z 俯视、x 向右、y 向上：从上方开始顺时针。
const RING: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0),
		Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]
const WAVE_WIDTH := 2.0
const SPACE_LEAD := 0.8


static func cell_id(c: Vector3i) -> int:
	return (c.x * SIZE + c.y) * SIZE + c.z


# 固定映射：把 729 格想成一根线上串着的珠子，按皮亚诺曲线（一种一笔画完、每步只走一格的折线）
# 摆成体、面或直线。珠子在线上的位置就是它在一维里的坐标。
# 位置写成 6 位三进制数，每一位交给哪个坐标轴（0、1、2 是 x、y、z）由下面两个表决定；
# 这两个表是在所有排法里比出来的（比较见 docs/devlog/2026-10.md「固定三维、二维、一维映射」）。
const CURVE_3D: Array[int] = [0, 0, 1, 2, 1, 2]
const CURVE_2D: Array[int] = [0, 0, 1, 1, 0, 1]
static var _order_3d: Array[Vector3i] = []
static var _order_2d: Array[Vector2i] = []
static var _index_3d := {}
static var _index_2d := {}


## 第 index 颗珠子在曲线上的坐标（每轴 0～3^位数-1）。前面别的轴的位数之和是奇数时，这一位倒过来走，
## 这样相邻的两颗珠子总是只差一格。
static func curve_point(index: int, axes: Array[int]) -> Array[int]:
	var digits: Array[int] = []
	for i in axes.size():
		digits.push_front(index % 3)
		index /= 3
	var coord: Array[int] = [0, 0, 0]
	for j in axes.size():
		var flips := 0
		for i in j:
			if axes[i] != axes[j]:
				flips += digits[i]
		coord[axes[j]] = coord[axes[j]] * 3 + (2 - digits[j] if flips % 2 == 1 else digits[j])
	return coord


static func _build() -> void:
	if not _order_3d.is_empty():
		return
	for i in COUNT:
		var a := curve_point(i, CURVE_3D)
		var b := curve_point(i, CURVE_2D)
		_order_3d.append(Vector3i(a[0], a[1], a[2]))
		_order_2d.append(Vector2i(b[0], b[1]))
		_index_3d[_order_3d[i]] = i
		_index_2d[_order_2d[i]] = i


## 三维格子在一维直线上的位置（0～728）。和打击点无关。
static func line_index(c: Vector3i) -> int:
	_build()
	return _index_3d[c]


## 三维格子展开成 27×27 平面后的坐标。和打击点无关。
static func fixed_plane(c: Vector3i) -> Vector2i:
	_build()
	return _order_2d[_index_3d[c]]


## 平面上的格子压成直线后的位置。
static func plane_to_line(p: Vector2i) -> int:
	_build()
	return _index_2d[p]


## 平面上的格子原来是哪个三维格子。
static func plane_origin(p: Vector2i) -> Vector3i:
	_build()
	return _order_3d[_index_2d[p]]


## 直线上第 i 格原来是哪个三维格子。
static func line_origin(i: int) -> Vector3i:
	_build()
	return _order_3d[i]


static func slot(z: int, layer: int) -> Vector2i:
	if z == layer:
		return Vector2i.ZERO
	return RING[z if z < layer else z - 1]


static func to_plane(c: Vector3i, layer: int) -> Vector2i:
	return Vector2i(c.x * 3 + 1, c.y * 3 + 1) + slot(c.z, layer)


static func from_plane(p: Vector2i, layer: int) -> Vector3i:
	var offset := Vector2i(p.x % 3 - 1, p.y % 3 - 1)
	var z := layer
	if offset != Vector2i.ZERO:
		z = RING.find(offset)
		if z >= layer:
			z += 1
	return Vector3i(p.x / 3, p.y / 3, z)


static func smooth_amount(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 二次曲线：先向外展开，再落到平面。横向偏移不超出预留的方框。
static func spread(t: float) -> float:
	return 2.0 * t - t * t


## 每列（或每行）的宽度是 widths，锚点那列不动，算出每列中心的位置。
static func centers(widths: PackedFloat32Array, anchor: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(widths.size())
	result[anchor] = anchor
	for i in range(anchor, widths.size() - 1):
		result[i + 1] = result[i] + (widths[i] + widths[i + 1]) / 2.0
	for i in range(anchor - 1, -1, -1):
		result[i] = result[i + 1] - (widths[i] + widths[i + 1]) / 2.0
	return result


## 球形扩张时，每个原点铺好自己的局部平面后，再过多久开始向基准平面靠拢、靠拢要多久（单位和扩张半径相同）。
const MERGE_DELAY := 4.0
const MERGE_TIME := 6.0
## 周围还没展开的空间最多被推开多远，给平面腾地方。
const MAX_PUSH := 6.0


## 每个格子被哪个原点先波及、什么时候波及。origins 里每项是 {"at": Vector3i, "start": float}，
## 扩张速度是每单位时间 1 格。同时到达时按原点坐标比大小，所以原点的先后顺序不影响结果。
static func arrivals(origins: Array) -> Dictionary:
	var owner := {}
	var time := {}
	for x in SIZE:
		for y in SIZE:
			for z in SIZE:
				var c := Vector3i(x, y, z)
				var best := -1
				for i in origins.size():
					var t: float = origins[i]["start"] + Vector3(c - origins[i]["at"]).length()
					if best < 0 or t < time[c] - 1e-6 or (absf(t - time[c]) <= 1e-6 and _before(origins[i]["at"], origins[best]["at"])):
						best = i
						time[c] = t
				owner[c] = best
	return {"owner": owner, "time": time}


static func _before(a: Vector3i, b: Vector3i) -> bool:
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))


## 最早一批原点决定基准平面：高度取它们 z 的平均（四舍五入，.5 往上），
## 水平位置让这批原点的格子平均起来不动。之后的原点铺好局部平面后向它靠拢。
static func base_plane(origins: Array) -> Vector3:
	var first := INF
	for o in origins:
		first = minf(first, o["start"])
	var shift := Vector3.ZERO
	var n := 0
	for o in origins:
		if absf(o["start"] - first) <= 1e-6:
			shift += _local_shift(o["at"])
			n += 1
	shift /= n
	return Vector3(roundf(shift.x), roundf(shift.y), floorf(shift.z + 0.5))


## 让原点所在格子留在原地的局部平面：平面坐标加上这个偏移就是画的位置，高度是原点的 z。
static func _local_shift(at: Vector3i) -> Vector3:
	var p := fixed_plane(at)
	return Vector3(at.x - p.x, at.y - p.y, at.z)


## 扩张半径 r 的球铺成平面后大约多宽，比 r 多出来的部分就是周围空间要推开的距离。
static func _push(r: float) -> float:
	if r <= 0.0:
		return 0.0
	return minf(sqrt(4.0 / 3.0 * r * r * r) - r, MAX_PUSH) if r > 1.0 else 0.0


## 多个原点各自按球形扩张，被波及的格子先铺到自己原点的局部平面，再一起靠拢到基准平面，
## 最后每个格子都落在固定映射的位置上（再整体平移 base_plane）。time 是从最早的原点开始算的时间。
static func sample_spread(time: float, origins: Array) -> Dictionary:
	var hit := arrivals(origins)
	var base := base_plane(origins)
	var cells: Array[Vector3i] = []
	var positions := PackedVector3Array()
	var amounts := PackedFloat32Array()
	var owners := PackedInt32Array()
	var finished := 0
	for x in SIZE:
		for y in SIZE:
			for z in SIZE:
				var c := Vector3i(x, y, z)
				var o: Dictionary = origins[hit["owner"][c]]
				var q := smooth_amount((time - hit["time"][c]) / WAVE_WIDTH)
				var standing := Vector3(c)
				for other in origins:
					var away := Vector3(c - other["at"])
					var r: float = time - other["start"]
					if away.length() > r and away.length() > 0.0:
						standing += away.normalized() * _push(r) * clampf(r / maxf(away.length(), 1.0), 0.0, 1.0)
				var merge := smooth_amount((time - o["start"] - MERGE_DELAY) / MERGE_TIME)
				var shift := _local_shift(o["at"]).lerp(base, merge)
				var p := fixed_plane(c)
				var flat := Vector3(p.x + shift.x, p.y + shift.y, shift.z)
				var at := standing.lerp(flat, q)
				at.z = lerpf(standing.z, flat.z, q * q)
				if q >= 1.0 and merge >= 1.0:
					finished += 1
				cells.append(c)
				positions.append(at)
				amounts.append(q)
				owners.append(hit["owner"][c])
	return {"cells": cells, "positions": positions, "amounts": amounts, "owners": owners,
			"finished": finished, "base": base}


## sample_spread 要播多久才全部落定。
static func spread_duration(origins: Array) -> float:
	var hit := arrivals(origins)
	var last := 0.0
	for c in hit["time"]:
		last = maxf(last, hit["time"][c] + WAVE_WIDTH)
	for o in origins:
		last = maxf(last, o["start"] + MERGE_DELAY + MERGE_TIME)
	return last


## 同一进度总是得到同一布局，允许任意回放、倒放、拖动。
## 只固定首个打击点；其他列的中心随扩张移动。锚点层在每个局部 3×3 的中心。
static func sample(progress: float, anchor: Vector3i, single := false) -> Dictionary:
	var far := Vector2(maxi(anchor.x, 8 - anchor.x), maxi(anchor.y, 8 - anchor.y)).length()
	var radius := lerpf(-SPACE_LEAD, far + WAVE_WIDTH, clampf(progress, 0.0, 1.0))
	var q := PackedFloat32Array()
	q.resize(SIZE * SIZE)
	var wx := PackedFloat32Array()
	var wy := PackedFloat32Array()
	wx.resize(SIZE)
	wy.resize(SIZE)
	wx.fill(1.0)
	wy.fill(1.0)
	for x in SIZE:
		for y in SIZE:
			var distance := Vector2(x - anchor.x, y - anchor.y).length()
			q[x * SIZE + y] = smooth_amount(progress) if single else smooth_amount((radius - distance) / WAVE_WIDTH)
			var reserved := spread(smooth_amount((radius + SPACE_LEAD - distance) / WAVE_WIDTH))
			wx[x] = maxf(wx[x], 1.0 + 2.0 * reserved)
			wy[y] = maxf(wy[y], 1.0 + 2.0 * reserved)
	var cx := centers(wx, anchor.x)
	var cy := centers(wy, anchor.y)
	var cells: Array[Vector3i] = []
	var positions := PackedVector3Array()
	var amounts := PackedFloat32Array()
	var finished := 0
	for x in SIZE:
		for y in SIZE:
			if single and (x != anchor.x or y != anchor.y):
				continue
			var t := q[x * SIZE + y]
			if t >= 1.0:
				finished += 1
			for z in SIZE:
				var offset := Vector2(slot(z, anchor.z)) * spread(t)
				cells.append(Vector3i(x, y, z))
				positions.append(Vector3(cx[x] + offset.x, cy[y] + offset.y,
						lerpf(z, anchor.z, t * t)))
				amounts.append(t)
	return {"cells": cells, "positions": positions, "amounts": amounts, "q": q,
			"cx": cx, "cy": cy, "wx": wx, "wy": wy, "finished": finished}
