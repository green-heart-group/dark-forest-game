class_name Assets
extends RefCounted
## 静态资产的永久身份；原有按星系列表继续供原界面使用。
## 新资产由完工事件登记；ensure 只在开局/调试编辑/测试夹具边界对齐旧集合。

const COUNTS := {"miner": "miners", "advanced_miner": "advanced_miners", "dyson": "dysons"}
const FLAGS := {"bunker": "bunkers", "broadcaster": "broadcasters", "warning": "warnings"}


static func make(s: GameState, civ: Civ, kind: String, at: Vector3i, paid: Array = [0.0, 0.0], dim := -1) -> Dictionary:
	var asset := {"id": s.next_id(), "kind": kind, "at": at,
			"entity_dim": civ.entity_dimension() if dim < 0 else dim,
			"paid": paid.duplicate(), "damage": 0, "receipts": {}, "ready": {}, "carrier": -1}
	civ.assets.append(asset)
	if kind == "anchor" and at == civ.original_home and civ.original_anchor_id < 0:
		civ.original_anchor_id = asset["id"]
	return asset


static func at(civ: Civ, kind: String, cell: Vector3i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for asset in civ.assets:
		if asset["kind"] == kind and asset["at"] == cell and asset["carrier"] < 0:
			found.append(asset)
	return found


static func get_id(civ: Civ, id: int) -> Dictionary:
	for asset in civ.assets:
		if asset["id"] == id:
			return asset
	return {}


static func dimension(civ: Civ, kind: String, cell: Vector3i) -> int:
	var items := at(civ, kind, cell)
	return items[0]["entity_dim"] if not items.is_empty() else civ.entity_dimension()


static func ensure(s: GameState, civ: Civ) -> void:
	var wanted := {}
	for cell in civ.colonies:
		wanted[["anchor", cell]] = 1
	for kind in COUNTS:
		for cell in civ.get(COUNTS[kind]):
			wanted[[kind, cell]] = civ.get(COUNTS[kind])[cell]
	for kind in FLAGS:
		for cell in civ.get(FLAGS[kind]):
			wanted[[kind, cell]] = 1
	var found := {}
	for asset in civ.assets.duplicate():
		if asset["carrier"] >= 0:
			continue
		var key := [asset["kind"], asset["at"]]
		var count: int = found.get(key, 0)
		if count >= wanted.get(key, 0):
			civ.assets.erase(asset)
		else:
			found[key] = count + 1
	for key in wanted:
		for i in range(found.get(key, 0), wanted[key]):
			make(s, civ, key[0], key[1])


static func remove_at(civ: Civ, cell: Vector3i) -> void:
	civ.assets = civ.assets.filter(func(asset): return asset["at"] != cell or asset["carrier"] >= 0)


## 普通攻击击毁单个静态实体，不复制或重新编号其他设施。
static func destroy(civ: Civ, asset: Dictionary) -> void:
	if asset["carrier"] >= 0:
		civ.assets.erase(asset)
		return
	var kind: String = asset["kind"]
	var cell: Vector3i = asset["at"]
	if COUNTS.has(kind):
		var counts: Dictionary = civ.get(COUNTS[kind])
		counts[cell] = maxi(0, counts.get(cell, 0) - 1)
		if counts[cell] == 0:
			counts.erase(cell)
	elif FLAGS.has(kind):
		civ.get(FLAGS[kind]).erase(cell)
	civ.assets.erase(asset)
	civ.has_warning = not civ.warnings.is_empty()


static func miner_gross(civ: Civ, cell: Vector3i) -> float:
	var total := 0.0
	for kind in ["miner", "advanced_miner"]:
		var rate := Balance.MINER_MINERAL if kind == "miner" else Balance.ADVANCED_MINER_MINERAL
		var items := at(civ, kind, cell)
		for asset in items:
			total += rate * Balance.DIMENSION_OUTPUT[str(asset["entity_dim"])]
		# 尚未经过调试同步的只读预览不能创建资产或消耗ID。
		var missing: int = civ.get(COUNTS[kind]).get(cell, 0) - items.size()
		total += maxi(0, missing) * rate * civ.output_factor()
	return total
