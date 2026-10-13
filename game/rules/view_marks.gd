class_name ViewMarks
extends RefCounted
## 看视野时「什么变了」的记录（见 docs/proposals/event-queue.md 的「视野的细节」）。
## 每回合开头全看一遍，记下每样东西的样子，并预测这一回合里谁会进入谁的视野。
## 之后每一刀只看样子变了的东西，加上预测在这一小步里进入视野的那几对；其余的按航位推算本来就不用重发。
## 「变了」不靠各处手动标记，而是每一刀比较样子：这样新加的规则改了什么，这里也能看出来。
## 记录只在一回合的结算里用，不存档、不进校验值：每回合开头重新记，所以读档和复制出来的局面算出来一样。
##
## s.view_marks 里有：
## - "env"：地图编号、维度、星系个数。变了就整个重看。
## - "subjects"：{单位编号: [记下的时刻, 位置, 速度, 加速度, 签名]}。之后照这组运动推算，对不上或签名变了就是变了。
## - "shapes"：{观察者编号: 视野签名}，位置所在的格子、朝向、半径、张角。
## - "ver"：{编号: 版本}。单位或观察者每变一次加 1；预测记着两边的版本，对不上就作废。
## - "cells"：{格子: 快照签名}，只记有观察者看着的星系。
## - "watch"：{格子: {观察者编号: true}}，"watching"：{观察者编号: [格子]}。观察者这一回合可能看到哪些星系。
## - "entries"：{观察者编号: [[时刻, 种类, 格子或单位编号, 观察者版本, 单位版本]]}，预测的进入视野。种类 CELL 或 ENTITY。
##   预测把视野边缘放宽 SLACK，宁可早一点；到时以后每一刀都看这一对，直到真的在视野里（finish 里删掉），或者哪边变了作废。
## - "boxes"、"grid"、"placed"：每个单位到这回合结束可能扫过的方框，和它放进了哪些网格桶（见 _place）。
##   变了的观察者只和方框碰得到自己视野的单位比，不用和所有单位逐个比。
## - "reach"：{观察者编号: 它的视野这回合可能扫过的方框}。没变的观察者只和方框碰得到的、变了的单位比。
## - "facts"：上次比较时星系的事实（GameState.cell_facts）。没变就不用逐个拍快照。

const CELL := 0
const ENTITY := 1
## 预测进入视野时视野边缘放宽多少光年。只要比坐标的浮点误差大得多就行。
const SLACK := 1e-3


## 每次看视野开始时调用：判断这次要不要全看，算出哪些单位和星系变了。
## look 是 Signals.sample 这一次的上下文，这里往里放 "full"、"dirty"（{单位编号: true}）、"changed"（{格子: true}）。
static func begin(s: GameState, look: Dictionary) -> void:
	var env := [s.space_epoch, s.dimension, s.system_cells.size(), s.map.extent]
	var marks: Dictionary = s.view_marks
	# 回合开头（还没有上一个子步）、不在 WorldTime.advance 里（测试直接调用）、要求全看、地图变了：全看。
	var full: bool = look["force"] or s.step_motions.is_empty() or s.clock > s.view_until + Balance.TIME_EPSILON \
			or marks.is_empty() or marks["env"] != env
	look["full"] = full
	look["dirty"] = {}
	look["changed"] = {}
	look["dirty_observers"] = {}
	if full:
		marks = {"env": env, "subjects": {}, "shapes": {}, "ver": {}, "cells": {}, "watch": {}, "watching": {}, "entries": {},
				"boxes": {}, "grid": {}, "placed": {}, "reach": {}}
		s.view_marks = marks
	var subjects := {}
	var tolerance := Balance.COLLISION_EPSILON / s.physical_cell_size()
	var until: float = maxf(s.view_until, s.clock)
	for target in look["entities"]:
		var id: int = target["id"]
		var sig := hash([target["kind"], target["owner"], target["hp"], target["acceleration"], Vector3i(target["pos"].round())])
		var old: Array = marks["subjects"].get(id, [])
		var same: bool = not full and not old.is_empty() and old[4] == sig
		if same:
			var t: float = s.clock - old[0]
			var pos: Vector3 = old[1] + old[2] * t + 0.5 * old[3] * t * t
			var velocity: Vector3 = old[2] + old[3] * t
			same = pos.distance_to(target["pos"]) <= tolerance and velocity.distance_to(target["velocity"]) <= tolerance
		if same:
			subjects[id] = old
		else:
			subjects[id] = [s.clock, target["pos"], target["velocity"], target["acceleration"], sig]
			look["dirty"][id] = true
			marks["ver"][id] = marks["ver"].get(id, 0) + 1
			_place(marks, id, _box(s, target, target["pos"], until, 0.0))
	# 这次不在的单位（毁了、休眠的观察者等）不留记录：再出现时当作新的。
	for id in marks["subjects"]:
		if not subjects.has(id):
			_place(marks, id, [])
	marks["subjects"] = subjects
	if full:
		return
	# 星系的事实整体没变，就不用逐个拍快照比较（见 GameState.cell_facts）。
	var facts := 0
	if not Hazards.any(s):
		look["counts"] = s.snapshot_counts()
		facts = s.cell_facts(look["counts"])
		look["facts"] = facts
		if facts == marks.get("facts", 0):
			return
	marks["facts"] = facts
	for cell in marks["watch"]:
		var snap := snapshot(s, look, cell)
		if marks["cells"].get(cell, 0) != snap[false]:
			marks["cells"][cell] = snap[false]
			look["changed"][cell] = true


## 这个星系这一次的样子和签名（同一次看视野里只拍一次）：{"data": 快照, false: 签名, true: 带接触标记的签名}。
static func snapshot(s: GameState, look: Dictionary, cell: Vector3i) -> Dictionary:
	var snapshots: Dictionary = look["snapshots"]
	if not snapshots.has(cell):
		if not look.has("counts"):
			look["counts"] = s.snapshot_counts()
		var fresh := s.snapshot(cell, look["counts"])
		fresh["cell_dim"] = s.cell_dims.get(s.cell_ids.get(cell,-1),s.dimension)
		fresh["turn"] = 0 # 签名只反映事实变化，观测时间另存。
		snapshots[cell] = {"data": fresh, false: hash([fresh, false]), true: hash([fresh, true])}
	return snapshots[cell]


## 这个观察者这次要不要全看：全看的时候、它自己变了（运动、所在格子、视野）、或者上次不在（新造的、刚醒的）。
static func observer_changed(s: GameState, look: Dictionary, observer: Dictionary) -> bool:
	var marks: Dictionary = s.view_marks
	var id: int = observer["id"]
	var sig := hash([Vector3i(observer["pos"].round()), observer["dir"], observer["radius"], observer["angle"], observer["backward"]])
	var changed: bool = look["full"] or look["dirty"].has(id) or marks["shapes"].get(id, 0) != sig
	if changed and not look["dirty"].has(id):
		marks["ver"][id] = marks["ver"].get(id, 0) + 1
	look["shapes"][id] = sig
	if changed:
		look["dirty_observers"][id] = true
	return changed


## 不用全看的观察者这次要看的星系：预测在上一小步里进入视野的，加上它可能看到、样子变了的。按星系编号排好。
static func cells_to_check(s: GameState, look: Dictionary, observer: Dictionary) -> Array[Vector3i]:
	var marks: Dictionary = s.view_marks
	var id: int = observer["id"]
	var found := {}
	for cell in look["changed"]:
		if marks["watch"][cell].has(id):
			found[cell] = true
	for entry in _due(s, look, id, CELL):
		found[entry[2]] = true
	var cells: Array[Vector3i] = []
	cells.assign(found.keys())
	cells.sort_custom(func(a, b): return s.cell_ids.get(a, -1) < s.cell_ids.get(b, -1))
	return cells


## 不用全看的观察者这次要看的单位（在 look["entities"] 里的下标，排好序）：变了的单位，加上预测在上一小步里进入视野的。
static func targets_to_check(s: GameState, look: Dictionary, observer: Dictionary) -> Array:
	var found := {}
	var where: Dictionary = look["where"]
	for id in look["dirty"]:
		found[where[id]] = true
	for entry in _due(s, look, observer["id"], ENTITY):
		if where.has(entry[2]):
			found[where[entry[2]]] = true
	var result := found.keys()
	result.sort()
	return result


## 这个观察者已经到时的某一种预测。作废的丢掉；到时的留在表里，等 finish 看到这一对真的在视野里才删。
## 观察者这次要全看时不取（全看已经包括了）。
static func _due(s: GameState, look: Dictionary, id: int, kind: int) -> Array:
	var marks: Dictionary = s.view_marks
	var entries: Array = marks["entries"].get(id, [])
	var due := []
	var keep := []
	var ver: Dictionary = marks["ver"]
	for entry in entries:
		if entry[3] != ver.get(id, -1) or (entry[1] == ENTITY and entry[4] != ver.get(entry[2], -1)):
			continue
		keep.append(entry)
		if entry[1] == kind and entry[0] <= s.clock + Balance.TIME_EPSILON:
			due.append(entry)
	marks["entries"][id] = keep
	return due


## 这次看完以后：给变了的观察者和单位预测这一回合里接下来谁会进入谁的视野，记下观察者的样子。
## 先用方框粗筛（begin 记下的单位方框、这里记下的观察者方框），方框碰得上的才逐对预测（_predict），所以结果和逐对全算一样。
static func finish(s: GameState, look: Dictionary) -> void:
	var marks: Dictionary = s.view_marks
	marks["shapes"] = look["shapes"]
	var until: float = maxf(s.view_until, s.clock)
	var entities: Array = look["entities"]
	var trails := {}
	for target in entities:
		trails[target["id"]] = target
	for pair in look["observers"]:
		var owner: int = pair[0]
		var observer: Dictionary = pair[1]
		var id: int = observer["id"]
		if not look["dirty_observers"].has(id):
			_settle(s, observer, trails)
			continue
		var mine: Dictionary = trails.get(id, {})
		var entries := []
		_watch_cells(s, look, observer, mine, until, entries)
		var box := _box(s, mine, observer["pos"], until, sqrt(Signals.view_reach2(s, observer)))
		marks["reach"][id] = box
		for i in _near(marks, look, box):
			var target: Dictionary = entities[i]
			if target["owner"] != owner:
				_predict(s, observer, mine, target, until, entries)
		marks["entries"][id] = entries
	if look["dirty"].is_empty():
		return
	# 变了的单位对没变的观察者：没变的观察者自己不会重新预测，这里替它补上和这些单位的。
	for pair in look["observers"]:
		var owner: int = pair[0]
		var observer: Dictionary = pair[1]
		var id: int = observer["id"]
		if look["dirty_observers"].has(id):
			continue
		var reach: Array = marks["reach"].get(id, [])
		var mine: Dictionary = trails.get(id, {})
		var entries: Array = marks["entries"].get(id, [])
		for target_id in look["dirty"]:
			var target: Dictionary = trails[target_id]
			if target["owner"] != owner and (reach.is_empty() or _overlap(reach, marks["boxes"][target_id])):
				_predict(s, observer, mine, target, until, entries)
		marks["entries"][id] = entries


## 粗筛用：每个单位从记下运动起、到能推算的最远处扫过的方框（"boxes"），按 GRID 格见方分桶（"grid"，太大的放进 "wide"）。
## 单位的运动没变时，它以后走的路还在当初的方框里，所以只在变了的时候重新放（begin 里）。只为算得快，不影响结果。
const GRID := 4.0
## 一个方框最多碰几个桶，再多就当它到处都在（放进 "wide"，谁都查它）。
const GRID_LIMIT := 64


## 把单位 id 的方框换成 box（空的就是拿掉）。
static func _place(marks: Dictionary, id: int, box: Array) -> void:
	var grid: Dictionary = marks["grid"]
	for key in marks["placed"].get(id, []):
		grid[key].erase(id)
		if grid[key].is_empty():
			grid.erase(key)
	marks["placed"].erase(id)
	marks["boxes"].erase(id)
	if box.is_empty():
		return
	marks["boxes"][id] = box
	var keys := []
	keys.assign(_keys(box))
	if keys.is_empty():
		keys = ["wide"]
	for key in keys:
		if not grid.has(key):
			grid[key] = {}
		grid[key][id] = true
	marks["placed"][id] = keys


static func _overlap(a: Array, b: Array) -> bool:
	return a[0].x <= b[1].x and b[0].x <= a[1].x and a[0].y <= b[1].y and b[0].y <= a[1].y and a[0].z <= b[1].z and b[0].z <= a[1].z

## 按 trail 走到能推算的最远处扫过的方框 [最低角, 最高角]，四周再放宽 margin 格。trail 是空的就是不动，在 pos。
static func _box(s: GameState, trail: Dictionary, pos: Vector3, until: float, margin: float) -> Array[Vector3]:
	var low := pos
	var high := pos
	if _moves(trail):
		var span := maxf(0.0, _span(s, trail, until))
		var a: Vector3 = trail["acceleration"]
		var end: Vector3 = pos + trail["velocity"] * span + 0.5 * a * span * span
		low = low.min(end)
		high = high.max(end)
		margin += a.length() * span * span / 8.0
	return [low - Vector3.ONE * (margin + 1e-5), high + Vector3.ONE * (margin + 1e-5)]


static func _keys(box: Array[Vector3]) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	if not (box[0].is_finite() and box[1].is_finite()):
		return keys
	var a := Vector3i((box[0] / GRID).floor())
	var b := Vector3i((box[1] / GRID).floor())
	if (b.x - a.x + 1) * (b.y - a.y + 1) * (b.z - a.z + 1) > GRID_LIMIT:
		return keys
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				keys.append(Vector3i(x, y, z))
	return keys


## 方框碰到的单位（在 look["entities"] 里的下标，排好序）。方框太大时返回全部。
static func _near(marks: Dictionary, look: Dictionary, box: Array) -> Array:
	var grid: Dictionary = marks["grid"]
	var where: Dictionary = look["where"]
	var keys := []
	keys.assign(_keys(box))
	if keys.is_empty():
		keys = grid.keys()
	else:
		keys.append("wide")
	var found := {}
	for key in keys:
		for id in grid.get(key, {}):
			if _overlap(box, marks["boxes"][id]):
				found[where[id]] = true
	var result := found.keys()
	result.sort()
	return result

## 到时的预测里，这一刀已经真的在视野里的删掉：这一刀已经按现在看过它，之后照航位推算不用再看。
static func _settle(s: GameState, observer: Dictionary, trails: Dictionary) -> void:
	var marks: Dictionary = s.view_marks
	var entries: Array = marks["entries"].get(observer["id"], [])
	var keep := []
	for entry in entries:
		if entry[0] <= s.clock + Balance.TIME_EPSILON:
			var pos: Vector3 = Vector3(entry[2]) if entry[1] == CELL else trails.get(entry[2], {}).get("pos", Vector3.INF)
			if pos == Vector3.INF or Signals.in_view(s, observer, pos):
				continue
		keep.append(entry)
	marks["entries"][observer["id"]] = keep


## 观察者 observer（运动是 mine，不动的设施和据点是空的）这一回合可能看到的星系，记进 watch；
## 动的观察者还预测它什么时候扫进每个星系，放进 entries。
static func _watch_cells(s: GameState, look: Dictionary, observer: Dictionary, mine: Dictionary, until: float, entries: Array) -> void:
	var marks: Dictionary = s.view_marks
	var id: int = observer["id"]
	for cell in marks["watching"].get(id, []):
		if marks["watch"].has(cell):
			marks["watch"][cell].erase(id)
			if marks["watch"][cell].is_empty():
				marks["watch"].erase(cell)
	var reach2 := Signals.view_reach2(s, observer)
	var cells: Array[Vector3i] = []
	if not _moves(mine):
		for seen in Signals._cells_in_view(s, look["index"], observer, reach2):
			cells.append(seen[0])
	else:
		var span := _span(s, mine, until)
		var a: Vector3 = mine["acceleration"]
		var end: Vector3 = mine["pos"] + mine["velocity"] * span + 0.5 * a * span * span
		var around: Vector3 = (mine["pos"] + end) * 0.5
		var widen: float = mine["pos"].distance_to(end) * 0.5 + a.length() * span * span / 8.0
		var ver: int = marks["ver"].get(id, 0)
		for cell in Geometry.cells_near(s.system_cells, look["index"], around, sqrt(reach2) + widen):
			var seen := Signals._first_seen(s, observer, Vector3(cell) - mine["pos"], -mine["velocity"], -a, span, SLACK)
			if seen == INF:
				continue
			cells.append(cell)
			# 现在已经在视野里的，这一刀刚看过；在放宽的边缘里、还没真进来的，从现在起每一刀都看。
			if seen > 0.0 or not Signals.in_view(s, observer, Vector3(cell)):
				entries.append([s.clock + seen, CELL, cell, ver, 0])
	marks["watching"][id] = cells
	for cell in cells:
		if not marks["watch"].has(cell):
			marks["watch"][cell] = {}
			marks["cells"][cell] = snapshot(s, look, cell)[false]
		marks["watch"][cell][id] = true


## 预测单位 target 什么时候进入观察者的视野（现在已经在视野里的不算），有就放进 entries。两边都不动就不会进入。
static func _predict(s: GameState, observer: Dictionary, mine: Dictionary, target: Dictionary, until: float, entries: Array) -> void:
	if not _moves(mine) and not _moves(target):
		return
	var span := minf(_span(s, mine, until), _span(s, target, until))
	if span <= 0.0:
		return
	var p0: Vector3 = mine.get("pos", observer["pos"])
	var v0: Vector3 = mine.get("velocity", Vector3.ZERO)
	var a0: Vector3 = mine.get("acceleration", Vector3.ZERO)
	var p1: Vector3 = target["pos"]
	var v1: Vector3 = target["velocity"]
	var a1: Vector3 = target["acceleration"]
	var reach := sqrt(Signals.view_reach2(s, observer))
	if not Signals._may_meet(p0, p0 + v0 * span + 0.5 * a0 * span * span, a0, p1, p1 + v1 * span + 0.5 * a1 * span * span, a1, span, reach):
		return
	var seen := Signals._first_seen(s, observer, p1 - p0, v1 - v0, a1 - a0, span, SLACK)
	if seen < INF and (seen > 0.0 or not Signals.in_view(s, observer, p1)):
		var marks: Dictionary = s.view_marks
		entries.append([s.clock + seen, ENTITY, target["id"], marks["ver"].get(observer["id"], 0), marks["ver"].get(target["id"], 0)])


static func _moves(trail: Dictionary) -> bool:
	return not trail.is_empty() and (trail["velocity"] != Vector3.ZERO or trail["acceleration"] != Vector3.ZERO)


## 按这组运动最多能推算多久：到这一回合结束，或者到加速停下（那时运动会变，到时重新预测）。
static func _span(s: GameState, trail: Dictionary, until: float) -> float:
	var span := until - s.clock
	if not trail.is_empty() and trail["acceleration"] != Vector3.ZERO:
		span = minf(span, trail.get("accel_until", INF) - s.clock)
	return span
