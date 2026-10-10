class_name WorkOrder
extends RefCounted
## 预付项目的固定点成本账。货币单位为千分之一，工作量也记到千分之一。
## paid 是已付款施工资格；spent/refundable 是经迁维折损后的回收/退款基数。
## 项目只保存值，不保存对象引用，故存档快照不会与原局共用可变对象。

const SCALE := 1000


static func units(value: float) -> int:
	return roundi(value * SCALE)


static func amount(value: int) -> float:
	return float(value) / SCALE


static func create(id: int, kind: String, at: Vector3i, cost: Array, work: float, category := "build") -> Dictionary:
	var paid := [units(cost[0]), units(cost[1])]
	return {"id": id, "kind": kind, "at": at, "category": category,
			"work": units(work), "done": 0, "paid": paid.duplicate(),
			"spent": [0, 0], "refundable": paid.duplicate(), "receipts": {},
			"host_ship": -1, "modules": [], "work_remainder": 0.0,
			"basis_done": 0, "basis_spent": [0, 0], "basis_refund": paid.duplicate(), "command_ready": true}


## 完成比例只移动成本账，不再次从文明库存扣费。尾项吸收舍入余数，保持精确守恒。
static func advance(order: Dictionary, work: float) -> bool:
	var remaining: int = order["work"] - order["done"]
	if remaining <= 0:
		return true
	var exact: float = work * SCALE + order.get("work_remainder", 0.0)
	var delta := mini(remaining, maxi(0, floori(exact + 1e-6)))
	order["work_remainder"] = exact - delta if delta < remaining else 0.0
	order["done"] += delta
	for i in 2:
		@warning_ignore("integer_division")
		var consumed: int = order["basis_refund"][i] * (order["done"] - order["basis_done"]) / (order["work"] - order["basis_done"])
		order["refundable"][i] = order["basis_refund"][i] - consumed
		order["spent"][i] = order["basis_spent"][i] + consumed
	return order["done"] >= order["work"]


static func refund(order: Dictionary) -> Array:
	return [amount(order["refundable"][0]), amount(order["refundable"][1])]


static func salvage(order: Dictionary) -> Array:
	return [amount(order["spent"][0]), amount(order["spent"][1])]


## 同一实体的同一步迁维只结算一次，保留已付款资格及工作进度。
static func retain(order: Dictionary, receipt: String, fraction: float) -> bool:
	if order["receipts"].has(receipt):
		return false
	order["receipts"][receipt] = fraction
	for field in ["spent", "refundable"]:
		for i in 2:
			order[field][i] = floori(order[field][i] * fraction)
	order["basis_done"] = order["done"]
	order["basis_spent"] = order["spent"].duplicate()
	order["basis_refund"] = order["refundable"].duplicate()
	return true
