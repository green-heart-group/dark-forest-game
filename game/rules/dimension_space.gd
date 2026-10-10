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
	var old_systems := s.system_cells.duplicate()
	var old_size := s.physical_cell_size()
	var next_dim := 1 if to_line else 2
	var new_size: float = Balance.DIMENSION_CELL_SIZE[str(next_dim)]
	var next := StarMap.new()
	next.extent = Vector3i(COUNT, 1, 1) if to_line else Vector3i(PLANE_SIZE, PLANE_SIZE, 1)
	next.origin = Vector3i(0, anchor.y if to_line else 0, anchor.z)
	var mapping := {}
	for cell in old.cells():
		mapping[cell] = map_cell(cell, anchor, to_line)
	LightFront.remap(s,anchor,to_line,old,mapping)
	for field in ["stars", "rocky", "gas", "habitable"]:
		var data: Dictionary = old.get(field).duplicate(true)
		_keys(data, mapping)
		next.set(field, data)
	var remapped_light := PackedFloat64Array()
	if not s.light.is_empty():
		remapped_light.resize(COUNT)
		for cell in mapping:
			var d: Vector3i = mapping[cell] - next.origin
			remapped_light[(d.x * next.extent.y + d.y) * next.extent.z + d.z] = s.light[s.light_index(cell)]
	for civ in s.civs:
		civ.home = mapping.get(civ.home, Vector3i(point(Vector3(civ.home), anchor, to_line, old)))
		civ.original_home = mapping.get(civ.original_home, civ.original_home)
		for i in civ.colonies.size():
			civ.colonies[i] = mapping[civ.colonies[i]]
		for field in ["dysons", "miners", "advanced_miners", "bunkers", "broadcasters", "grains", "warnings", "colonial",
				"dormant_colonies", "dormant_dysons", "known", "intel", "heard", "record_hits", "record_empty",
				"colony_tried", "aimed", "broadcasted", "sophon_tried", "site_reports"]:
			_keys(civ.get(field), mapping)
		for field in ["pending", "pending_domains", "assets", "reports", "sightings", "hit_dirs", "alerts"]:
			for value in civ.get(field):
				_migrate_value(value, anchor, to_line, old, old_size / new_size)
		for value in civ.intel.values():
			_migrate_value(value, anchor, to_line, old, old_size / new_size)
		for value in civ.telemetry.values():
			_migrate_value(value, anchor, to_line, old, old_size / new_size)
		for value in civ.site_reports.values():
			_migrate_value(value,anchor,to_line,old,old_size/new_size)
		for field in ["order_reports","payload_reports","command_results","local_contacts_by_source","front_reports","broadcast_reports","battle_reports","wake_reports"]:
			_migrate_value(civ.get(field),anchor,to_line,old,old_size/new_size)
		_migrate_value(civ.research_project, anchor, to_line, old, old_size / new_size)
		for field in ["maintenance_priority", "stopped_packages"]:
			var keys: Array = civ.get(field)
			for i in keys.size():
				var original: String=keys[i]
				for cell in mapping:
					for kind in ["anchor", "dyson"]:
						var prefix := "%s:%s:" % [kind, cell]
						if original.begins_with(prefix):
							keys[i] = "%s:%s:" % [kind, mapping[cell]] + original.substr(prefix.length())
							break
		for ship in civ.ships:
			_move_ship(ship, anchor, to_line, old)
			_migrate_value(ship.local_contacts, anchor, to_line, old, old_size / new_size)
			_migrate_value(ship.command, anchor, to_line, old, old_size / new_size)
		# 在途箔保留；视图镜像随真实载荷同步，已完成的旧阶段波才退休。
		for foil in civ.foils:
			foil.origin = point(foil.origin, anchor, to_line, old)
			foil.current_position = point(foil.current_position,anchor,to_line,old)
			foil.target = mapping.get(foil.target, Vector3i(point(Vector3(foil.target), anchor, to_line, old)))
	for ship in s.hidden_ships:
		_move_ship(ship, anchor, to_line, old)
	for i in s.hidden.size():
		s.hidden[i] = Vector3i(point(Vector3(s.hidden[i]), anchor, to_line, old))
	for field in ["black_domains", "deadlines", "projectiles", "payloads", "messages", "scans", "neutral_assets", "hidden_listen", "wakes", "pending_battle_surveys"]:
		for value in s.get(field):
			_migrate_value(value, anchor, to_line, old, old_size / new_size)
	for broadcast in s.broadcasts:
		_migrate_value(broadcast, anchor, to_line, old, old_size / new_size)
	for foil in s.hidden_foils:
		foil.origin = point(foil.origin, anchor, to_line, old)
		foil.target = mapping.get(foil.target, foil.target)
	_keys(s.cell_ids, mapping)
	s.map = next
	s.light = remapped_light
	s.system_cells.clear()
	for cell in old_systems:
		s.system_cells.append(mapping.get(cell, cell))
	s._view_cache.clear()
	s.last_mapping = mapping
	var zones := s.line_zones if to_line else s.foil_zones
	if not zones.is_empty():
		var base := Layout.base_plane(zone_origins(zones), to_line)
		s.visual_offset += base - (Vector3(map_cell(anchor, anchor, to_line)) - Layout.target(anchor, to_line))
	s.dimension = next_dim
	for payload in s.payloads:
		payload["leg_start"] = payload["pos"]
		payload["leg_distance"] = 0.0
		payload["remaining"] = payload["pos"].distance_to(payload["target"]) * new_size
		if payload["remaining"] > 1e-12:
			payload["direction"] = (payload["target"] - payload["pos"]).normalized()
	s.space_epoch += 1
	s.remap_until = s.clock + 2.0 * Balance.TIME_EPSILON
	for message in s.messages:
		message["not_before"] = s.remap_until
	for wave in Information.waves(s):
		for sample in wave["samples"]:
			sample["leg_start"] = sample["pos"]
			sample["leg_distance"] = 0.0
			sample["remaining"] = sample["pos"].distance_to(sample["target"]) * new_size
			sample["direction"] = (sample["target"]-sample["pos"]).normalized()
	s.events.append({"id": s.next_id(), "kind": "world_remapped", "t": s.clock, "epoch": s.space_epoch, "dim": next_dim})
	s.add_log("宇宙展开为%s，729个永久格子及在途对象保留；旧观测仍标注原时刻" % ("729格直线" if to_line else "27×27平面"))


static func _move_ship(ship: Ship, anchor: Vector3i, to_line: bool, old: StarMap) -> void:
	var original := ship.pos
	var waypoint := ship.target if ship.has_target else _heading_point(original, ship.direction, old)
	ship.pos = point(original, anchor, to_line, old)
	ship.leg_origin = ship.pos
	ship.leg_distance = 0.0
	ship.target = point(ship.target, anchor, to_line, old)
	var ahead := point(waypoint, anchor, to_line, old) - ship.pos
	if ship.direction != Vector3.ZERO and ahead.length_squared() > 1e-15:
		ship.direction = ahead.normalized()
	# 投影重合时保留既有方向；速度大小、目标ID、已花距离和本地历史不重置。


static func _migrate_value(value: Variant, anchor: Vector3i, to_line: bool, old: StarMap, speed_scale: float) -> void:
	if value is Array:
		for item in value:
			_migrate_value(item, anchor, to_line, old, speed_scale)
		return
	if not value is Dictionary:
		return
	var positions := ["pos", "at", "cell", "target", "request_target", "recipient_pos", "center", "origin", "source", "from", "exposed", "a", "b"]
	var origin: Vector3 = value.get("pos", value.get("recipient_pos",value.get("from", Vector3.ZERO))) if (value.get("pos", value.get("recipient_pos",value.get("from", Vector3.ZERO))) is Vector3 or value.get("pos", value.get("recipient_pos",value.get("from", Vector3.ZERO))) is Vector3i) else Vector3.ZERO
	for key in ["velocity", "direction", "dir"]:
		if value.get(key) is Vector3:
			var direction: Vector3 = value[key]
			var ahead := point(origin + direction.normalized(), anchor, to_line, old) - point(origin, anchor, to_line, old)
			if ahead.length_squared() > 1e-15:
				value[key] = ahead.normalized() * direction.length() * (speed_scale if key == "velocity" else 1.0)
	for key in value.keys():
		if key in positions and (value[key] is Vector3 or value[key] is Vector3i):
			if key == "pos" and value.has("t_observed") and not value.has("observed_pos"):
				value["observed_pos"] = value[key]
			var mapped := point(Vector3(value[key]), anchor, to_line, old)
			value[key] = Vector3i(mapped.round()) if value[key] is Vector3i else mapped
		elif (not key is String or key != "propagation") and (value[key] is Array or value[key] is Dictionary):
			_migrate_value(value[key], anchor, to_line, old, speed_scale)


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
