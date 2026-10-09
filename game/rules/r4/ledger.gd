class_name R4Ledger
extends RefCounted
## 中央抽象账本。整数为千分之一资源；库存、托管、消耗及残骸成本分别记账。
## 不读画面、时钟或随机数。已付资格不会因成本账降维折损而重新收费。

const PRECISION := 1000
var stock := Vector2i.ZERO
var projects: Dictionary = {}
var shots: Dictionary = {}
var receipts: Dictionary = {}
var salvaged: Dictionary = {}
var transactions: Array[Dictionary] = []

static func amount(m: float, e: float) -> Vector2i:
	return Vector2i(roundi(m * PRECISION), roundi(e * PRECISION))

static func scaled(value: Vector2i, ratio: float) -> Vector2i:
	return Vector2i(roundi(value.x * ratio), roundi(value.y * ratio))

static func nonnegative(value: Vector2i) -> bool:
	return value.x >= 0 and value.y >= 0

func can_pay(value: Vector2i) -> bool:
	return nonnegative(value) and nonnegative(stock - value)

func debit(value: Vector2i, reason: String) -> bool:
	if not can_pay(value):
		return false
	stock -= value
	transactions.append({"kind": "debit", "amount": value, "reason": reason})
	return true

func credit(value: Vector2i, reason: String) -> void:
	assert(nonnegative(value))
	stock += value
	transactions.append({"kind": "credit", "amount": value, "reason": reason})

func fund_project(id: int, cost: Vector2i, work: float, host: int, metadata: Dictionary = {}) -> bool:
	if projects.has(id) or work <= 0.0 or not can_pay(cost):
		return false
	debit(cost, "project:%d" % id)
	projects[id] = {"id": id, "host": host, "work": work, "done": 0.0,
		"original_payment": cost, "refundable": cost, "consumed": Vector2i.ZERO,
		"paid_eligibility": true, "metadata": metadata.duplicate(true), "receipts": []}
	return true

func advance(id: int, work: float) -> bool:
	if not projects.has(id) or work <= 0.0:
		return false
	var p: Dictionary = projects[id]
	var remaining: float = maxf(0.0, p.work - p.done)
	var delta: float = minf(work, remaining)
	if remaining > 0.0:
		var spent: Vector2i = p.refundable if delta >= remaining else scaled(p.refundable, delta / remaining)
		p.refundable -= spent
		p.consumed += spent
		p.done += delta
	return p.done >= p.work - 1e-9

func take_completed(id: int) -> Dictionary:
	if not projects.has(id):
		return {}
	var p: Dictionary = projects[id]
	if p.done < p.work - 1e-9:
		return {}
	projects.erase(id)
	transactions.append({"kind": "project_complete", "project": id, "basis": p.consumed})
	return p

func cancel(id: int) -> Vector2i:
	if not projects.has(id):
		return Vector2i.ZERO
	var refund: Vector2i = projects[id].refundable
	credit(refund, "cancel:%d" % id)
	projects.erase(id)
	return refund

func destroy_host(host: int) -> void:
	for id in projects.keys():
		if projects[id].host == host:
			transactions.append({"kind": "project_destroyed", "project": id,
				"lost_refundable": projects[id].refundable, "lost_consumed": projects[id].consumed})
			projects.erase(id)

func apply_receipt(id: String, retention: float, selected_projects: Array) -> bool:
	if receipts.has(id) or retention < 0.0 or retention > 1.0:
		return false
	receipts[id] = retention
	var before := stock
	stock = scaled(stock, retention)
	for pid in selected_projects:
		if not projects.has(pid):
			continue
		var p: Dictionary = projects[pid]
		if p.receipts.has(id):
			continue
		p.refundable = scaled(p.refundable, retention)
		p.consumed = scaled(p.consumed, retention)
		p.receipts.append(id)
	# 已锁定但未发射的弹药也属于当前资源账，不能绕过损失。
	for shot in shots:
		shots[shot] = scaled(shots[shot], retention)
	transactions.append({"kind": "migration", "receipt": id, "retention": retention, "loss": before - stock})
	return true

func reserve_shot(id: String, cost: Vector2i) -> bool:
	if shots.has(id) or not debit(cost, "reserve:" + id):
		return false
	shots[id] = cost
	return true

func fire_shot(id: String) -> Vector2i:
	if not shots.has(id):
		return Vector2i.ZERO
	var paid: Vector2i = shots[id]
	shots.erase(id)
	transactions.append({"kind": "shot", "shot": id, "amount": paid})
	return paid

func release_shot(id: String) -> Vector2i:
	if not shots.has(id):
		return Vector2i.ZERO
	var unused: Vector2i = shots[id]
	shots.erase(id)
	credit(unused, "release:" + id)
	return unused

func release_all_shots() -> void:
	for id in shots.keys():
		release_shot(id)

func salvage(target_id: int, paid_hull_modules: Vector2i, qualified_enemy: bool) -> Vector2i:
	if not qualified_enemy or salvaged.has(target_id) or not nonnegative(paid_hull_modules):
		return Vector2i.ZERO
	salvaged[target_id] = true
	credit(paid_hull_modules, "salvage:%d" % target_id)
	return paid_hull_modules

## 每个包由调用者按实际存活时间及实体Q计算gross，维护不乘Q。
## 先决定整批在线包，再一次结算，因而不使用同回合未来收入为武器或项目垫款。
func settle_packages(packages: Array) -> Array:
	var selected := packages.filter(func(p):return not p.get("force_off",false))
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("priority", 0) == b.get("priority", 0):
			return a.id < b.id
		return a.get("priority", 0) < b.get("priority", 0))
	while true:
		var net := Vector2i.ZERO
		for p in selected:
			net += p.gross - p.upkeep
		if nonnegative(stock + net):
			stock += net
			transactions.append({"kind": "production_upkeep", "net": net})
			break
		var removed := false
		for i in range(selected.size() - 1, -1, -1):
			if selected[i].upkeep != Vector2i.ZERO:
				transactions.append({"kind": "package_dormant", "id": selected[i].id})
				selected.remove_at(i)
				removed = true
				break
		assert(removed, "free packages cannot create negative cash")
	var online: Array = []
	for p in selected:
		online.append(p.id)
	return online

func invariant_errors() -> Array[String]:
	var errors: Array[String] = []
	if not nonnegative(stock): errors.append("negative stock")
	for p in projects.values():
		if not nonnegative(p.refundable) or not nonnegative(p.consumed): errors.append("negative project basis")
		if p.done < 0.0 or p.done > p.work + 1e-9: errors.append("project progress outside bounds")
		if not p.paid_eligibility: errors.append("unpaid project queued")
	for value in shots.values():
		if not nonnegative(value): errors.append("negative ammunition reservation")
	return errors

func snapshot() -> Dictionary:
	return {"stock": stock, "projects": projects.duplicate(true), "shots": shots.duplicate(true),
		"receipts": receipts.duplicate(true), "salvaged": salvaged.duplicate(true)}

func restore(data: Dictionary) -> void:
	stock = data.stock
	for field in ["projects", "shots", "receipts", "salvaged"]:
		set(field, data[field].duplicate(true))
