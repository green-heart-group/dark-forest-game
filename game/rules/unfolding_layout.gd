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


static func centers(widths: PackedFloat32Array, anchor: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(SIZE)
	result[anchor] = anchor
	for i in range(anchor, SIZE - 1):
		result[i + 1] = result[i] + (widths[i] + widths[i + 1]) / 2.0
	for i in range(anchor - 1, -1, -1):
		result[i] = result[i + 1] - (widths[i] + widths[i + 1]) / 2.0
	return result


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
