class_name DimensionSpace
extends RefCounted
## 整数坐标的一一映射、阶段换图和只读的展开布局。每个阶段仍有 729 格。

const Layout := preload("res://rules/unfolding_layout.gd")
const SIZE := Layout.SIZE
const PLANE_SIZE := Layout.SIZE * 3
const COUNT := Layout.COUNT


## 三维格子在平面上的坐标：固定映射（U3），和打击点无关，平面高度是 layer。
static func plane_cell(c: Vector3i, layer: int) -> Vector3i:
	var p := Layout.fixed_plane(c)
	return Vector3i(p.x, p.y, layer)


## 平面上的格子在直线上的坐标：沿同一条曲线（U3），直线所在的行是 row。
static func line_cell(c: Vector3i, row: int) -> Vector3i:
	return Vector3i(Layout.plane_to_line(Vector2i(c.x, c.y)), row, c.z)


## 展开中的箔换成 Layout 用的原点：每片箔已经扩散了 age 格，相当于在 -age 时开始扩张。
static func zone_origins(zones: Array[Dictionary]) -> Array:
	return zones.map(func(z): return {"at": z["center"], "start": -z["age"]})


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
			remapped_light[(d.x * next.extent.y + d.y) * next.extent.z + d.z] = s.light[s.light_index(c)]
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
	# 画面上整张图落在展开动画的终点（固定映射再整体平移 base_plane），换坐标时不跳动。
	var zones := s.line_zones if to_line else s.foil_zones
	if not zones.is_empty():
		var base := Layout.base_plane(zone_origins(zones), to_line)
		s.visual_offset += base - (Vector3(map_cell(anchor, anchor, to_line)) - Layout.target(anchor, to_line))
	s.dimension = 1 if to_line else 2
	s.space_epoch += 1
	s.add_log("宇宙展开为 %s，729 格完整保留；旧情报失效，需要重新探索" % ("729 格直线" if to_line else "27×27 平面"))


## 有目的地的重新对准搬过去的目的地。没有目的地的保留原来的方向，只去掉压掉的轴（U3）：
## 固定映射里相邻的两格搬过去不一定还在同一个方向上相邻，按「前方一格」搬过去再对准会突然拐弯。
## 图外飞来的仍朝搬过去以后的入口飞。
static func _move_ship(ship: Ship, anchor: Vector3i, to_line: bool, old: StarMap) -> void:
	var inside := old.contains(Vector3i(ship.pos.round()))
	var ahead := point(_heading_point(ship.pos, ship.direction, old), anchor, to_line, old)
	ship.pos = point(ship.pos, anchor, to_line, old)
	ship.target = point(ship.target, anchor, to_line, old)
	if ship.direction != Vector3.ZERO:
		if ship.has_target:
			ship.direction = (ship.target - ship.pos).normalized()
		elif inside:
			ship.direction = flatten_direction(ship.direction, to_line)
		else:
			ship.direction = (ahead - ship.pos).normalized()
	ship.lock = -1
	if ship.direction == Vector3.ZERO:
		ship.speed = 0.0


## 换坐标后的方向：进二维去掉 z，进一维只留 x。正好沿压掉的轴飞的变成零（停下）。
static func flatten_direction(direction: Vector3, to_line: bool) -> Vector3:
	direction.z = 0.0
	if to_line:
		direction.y = 0.0
	return direction.normalized() if direction.length() > 1e-6 else Vector3.ZERO


## 所有键均为本阶段的逻辑坐标；渲染的位置绝不写回规则。
## 展开中用和演示一样的球形扩张（Layout.sample_spread）；规则压平的格子画面上也已铺平。
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
	# 时间取 WAVE_WIDTH：波前扫到的格子（离落点不超过 age）正好铺平
	var sample := Layout.sample_spread(Layout.WAVE_WIDTH, zone_origins(zones), to_line)
	for i in sample["cells"].size():
		var c: Vector3i = sample["cells"][i]
		positions[c] = sample["positions"][i] + s.visual_offset
		amounts[c] = sample["amounts"][i]
	return {"positions": positions, "amounts": amounts}

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
