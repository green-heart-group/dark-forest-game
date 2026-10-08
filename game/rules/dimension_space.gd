class_name DimensionSpace
extends RefCounted
## 整数坐标的一一映射、阶段换图和只读的展开布局。每个阶段仍有 729 格。

const SIZE := 9
const PLANE_SIZE := 27
const COUNT := 729
const Layout := preload("res://rules/unfolding_layout.gd")
const WAVE_WIDTH := 2.0


static func plane_cell(c: Vector3i, layer: int) -> Vector3i:
	var p := Layout.to_plane(c, layer)
	return Vector3i(p.x, p.y, layer)


static func line_cell(c: Vector3i, row: int) -> Vector3i:
	# 蛇形遍历：相邻列的端点相接，保留平面上连续路径。
	return Vector3i(c.x * PLANE_SIZE + (c.y if c.x % 2 == 0 else PLANE_SIZE - 1 - c.y), row, c.z)


static func map_cell(c: Vector3i, anchor: Vector3i, to_line: bool) -> Vector3i:
	return line_cell(c, anchor.y) if to_line else plane_cell(c, anchor.z)


static func point(p: Vector3, anchor: Vector3i, to_line: bool, old_map: StarMap) -> Vector3:
	var c := Vector3i(p.round())
	if not old_map.contains(c):
		# 图外的隐藏来袭仍从新图边缘进入，不能凭映射落到图内。
		var width := COUNT if to_line else PLANE_SIZE
		return Vector3(-3 if p.x < old_map.origin.x else width + 2,
				anchor.y if to_line else clampf(p.y * 3.0, 0.0, PLANE_SIZE - 1), anchor.z)
	var local := p - Vector3(c)
	local.z = 0.0
	if to_line:
		local.y = 0.0
	return Vector3(map_cell(c, anchor, to_line)) + local


static func _keys(data: Dictionary, mapping: Dictionary) -> void:
	var copy := data.duplicate(true)
	data.clear()
	for c in copy:
		data[mapping.get(c, c)] = copy[c]


## 全阶段完成后调用一次。先做新容器再替换，绝不边搬边覆盖目标格子。
static func commit(s: GameState, to_line: bool) -> void:
	var anchor := s.line_anchor if to_line else s.fold_anchor
	var old := s.map
	var next := StarMap.new()
	next.extent = Vector3i(COUNT, 1, 1) if to_line else Vector3i(PLANE_SIZE, PLANE_SIZE, 1)
	next.origin = Vector3i(0, anchor.y if to_line else 0, anchor.z)
	var mapping := {}
	for c in old.cells():
		mapping[c] = map_cell(c, anchor, to_line)
	for field in ["stars", "rocky", "gas", "habitable"]:
		var data: Dictionary = old.get(field).duplicate(true)
		_keys(data, mapping)
		next.set(field, data)
	var remapped_light := PackedFloat64Array()
	if not s.light.is_empty():
		remapped_light.resize(COUNT)
		for c in mapping:
			var d: Vector3i = mapping[c] - next.origin
			remapped_light[(d.x * next.extent.y + d.y) * next.extent.z + d.z] = s.light[s._li(c)]
	for civ in s.civs:
		civ.home = mapping.get(civ.home, Vector3i(point(Vector3(civ.home), anchor, to_line, old)))
		for i in civ.colonies.size():
			civ.colonies[i] = mapping[civ.colonies[i]]
		for field in ["dysons", "miners", "bunkers", "broadcasters", "grains"]:
			_keys(civ.get(field), mapping)
		for pending in civ.pending:
			pending["at"] = mapping.get(pending["at"], civ.home)
		for pending in civ.pending_domains:
			pending["center"] = mapping[pending["center"]]
		for ship in civ.ships:
			_move_ship(ship, anchor, to_line, old)
		civ.times_hit = 0
		civ.foils.clear()  # 旧阶段的箔已没有可压缩的维度。
		# 清掉旧坐标的情报和行动记忆；科技解锁、资源和发展进度保留。
		for field in ["known", "intel", "reports", "sightings", "wakes_seen", "heard", "hit_dirs", "alerts",
				"record_hits", "record_empty", "colony_tried", "aimed", "broadcasted", "sophon_tried"]:
			civ.get(field).clear()
	for ship in s.hidden_ships:
		_move_ship(ship, anchor, to_line, old)
	for i in s.hidden.size():
		s.hidden[i] = Vector3i(point(Vector3(s.hidden[i]), anchor, to_line, old))
	for domain in s.black_domains:
		domain["center"] = mapping[domain["center"]]
	s.hidden_foils.clear()
	s.hidden_listen.clear()
	s.broadcasts.clear()
	s.wakes.clear()
	s.map = next
	s.light = remapped_light
	s.system_cells.clear()
	for c in next.stars:
		if next.star_at(c) != StarMap.Star.NONE:
			s.system_cells.append(c)
	s._view_cache.clear()
	s.last_mapping = mapping
	# 只改变坐标标签；渲染位置仍固定在第一打击点，不在换图时跳动。
	s.visual_offset += Vector3(anchor - map_cell(anchor, anchor, to_line))
	s.dimension = 1 if to_line else 2
	s.space_epoch += 1
	s.add_log("宇宙展开为 %s，729 格完整保留；旧情报失效，需要重新探索" % ("729 格直线" if to_line else "27×27 平面"))


static func _move_ship(ship: Ship, anchor: Vector3i, to_line: bool, old: StarMap) -> void:
	var ahead := point(_heading_point(ship.pos, ship.direction, old), anchor, to_line, old)
	ship.pos = point(ship.pos, anchor, to_line, old)
	ship.target = point(ship.target, anchor, to_line, old)
	if ship.direction != Vector3.ZERO:
		ship.direction = (ship.target - ship.pos if ship.has_target else ahead - ship.pos).normalized()
	ship.lock = -1
	if ship.direction == Vector3.ZERO:
		ship.speed = 0.0


## 所有键均为本阶段的逻辑坐标；渲染的位置绝不写回规则。
static func frame(s: GameState) -> Dictionary:
	var positions := {}
	var amounts := {}
	var to_line := s.dimension == 2
	var zones := s.line_zones if to_line else s.foil_zones
	if s.dimension == 1 or zones.is_empty():
		for c in s.map.cells():
			positions[c] = Vector3(c) + s.visual_offset
			amounts[c] = 0.0
		return {"positions": positions, "amounts": amounts}
	var anchor := s.line_anchor if to_line else s.fold_anchor
	var n := PLANE_SIZE if to_line else SIZE
	var widths := PackedFloat32Array()
	var heights := PackedFloat32Array()
	widths.resize(n)
	heights.resize(n)
	widths.fill(1.0)
	heights.fill(1.0)
	var q := {}
	for x in n:
		for y in (1 if to_line else n):
			var value := 0.0
			var reserved := 0.0
			for zone in zones:
				var center: Vector3i = zone["center"]
				var distance := absf(x - center.x) if to_line else Vector2(x - center.x, y - center.y).length()
				value = maxf(value, Layout.smooth_amount((zone["age"] - distance + WAVE_WIDTH) / WAVE_WIDTH))
				reserved = maxf(reserved, Layout.spread(Layout.smooth_amount((zone["age"] - distance + WAVE_WIDTH + 0.8) / WAVE_WIDTH)))
			q[Vector2i(x, y)] = value
			widths[x] = maxf(widths[x], 1.0 + (26.0 if to_line else 2.0) * reserved)
			if not to_line:
				heights[y] = maxf(heights[y], 1.0 + 2.0 * reserved)
	var cx := _centers(widths, anchor.x)
	var cy := _centers(heights, anchor.y if not to_line else 0)
	for c in s.map.cells():
		var t: float = q[Vector2i(c.x, 0 if to_line else c.y)]
		var p: Vector3
		if to_line:
			# 奇偶列的中心不同；统一以 13 为中心，保证最终映射和连续动画一致。
			var anchor_slot := anchor.y if anchor.x % 2 == 0 else 26 - anchor.y
			var slot := c.y if c.x % 2 == 0 else 26 - c.y
			p = Vector3(cx[c.x] + (slot - anchor_slot) * Layout.spread(t), lerpf(c.y, anchor.y, t * t), c.z)
		else:
			var offset := Vector2(Layout.slot(c.z, anchor.z)) * Layout.spread(t)
			p = Vector3(cx[c.x] + offset.x, cy[c.y] + offset.y, lerpf(c.z, anchor.z, t * t))
		positions[c] = p + s.visual_offset
		amounts[c] = t
	return {"positions": positions, "amounts": amounts}


static func _centers(widths: PackedFloat32Array, anchor: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(widths.size())
	result[anchor] = anchor
	for i in range(anchor, widths.size() - 1):
		result[i + 1] = result[i] + (widths[i] + widths[i + 1]) / 2.0
	for i in range(anchor - 1, -1, -1):
		result[i] = result[i + 1] - (widths[i] + widths[i + 1]) / 2.0
	return result


## 图外来袭使用射线进入旧星图的位置作新航向，不能把位置和方向都夹到同一边缘后停住。
static func _heading_point(p: Vector3, direction: Vector3, map: StarMap) -> Vector3:
	if map.contains(Vector3i(p.round())) or direction == Vector3.ZERO:
		return p + direction
	var near := 0.0
	var far := INF
	for axis in 3:
		var lo := float(map.origin[axis])
		var hi := lo + map.extent[axis] - 1
		if absf(direction[axis]) < 1e-9:
			if p[axis] < lo or p[axis] > hi:
				return p + direction
			continue
		var a := (lo - p[axis]) / direction[axis]
		var b := (hi - p[axis]) / direction[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
	return p + direction * near if near <= far else p + direction
