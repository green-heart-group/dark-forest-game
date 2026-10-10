class_name Economy
extends RefCounted
## 原子收入/维护结算。预测函数不改变规则状态，不消耗随机数。
## 名义净经常收入用于科技权限；实际产出乘实体Q，固定维护不乘Q。


static func package_key(kind: String, at: Vector3i, index := 0) -> String:
	return "%s:%s:%d" % [kind, at, index]


## 和原扣款保持相同固定点舍入，同时登记实际库存差，供对局资源守恒核对。
static func charge(s: GameState,civ: Civ,cost: Array,reason: String) -> void:
	var before:=[civ.energy_millis,civ.mineral_millis]
	civ.energy-=cost[0]
	civ.mineral-=cost[1]
	var delta:=[civ.energy_millis-before[0],civ.mineral_millis-before[1]]
	if delta!=[0,0]:
		civ.ledger.append({"t":s.clock,"kind":"expense","reason":reason,"delta":delta})


static func packages(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for at in civ.colonies:
		var e := 0.0
		if civ.has_tech("fission"):
			e += s.map.rocky.get(at, 0) * Balance.FISSION_ENERGY
		if civ.has_tech("fusion"):
			e += StarMap.star_count(s.map.star_at(at)) * Balance.FUSION_ENERGY
		var m: float = civ.miners.get(at, 0) * Balance.MINER_MINERAL + civ.advanced_miners.get(at, 0) * Balance.ADVANCED_MINER_MINERAL
		var key := package_key("anchor", at)
		var upkeep: Array = Construction.upkeep("landing") if civ.colonial.get(at, false) else [0, 0]
		var q: float = Balance.DIMENSION_OUTPUT[str(Assets.dimension(civ, "anchor", at))]
		result.append({"key": key, "kind": "anchor", "at": at, "nominal": [e, m],
				"actual": [e * q, Assets.miner_gross(civ, at)], "q": q, "upkeep": upkeep, "parent": ""})
		var dysons := Assets.at(civ, "dyson", at)
		for i in civ.dysons.get(at, 0):
			var dim: int = dysons[i]["entity_dim"] if i < dysons.size() else civ.entity_dimension()
			result.append({"key": package_key("dyson", at, i), "kind": "dyson", "at": at,
					"nominal": [Balance.DYSON_ENERGY if s.map.star_at(at) != StarMap.Star.NONE else 0, 0],
					"q": Balance.DIMENSION_OUTPUT[str(dim)], "upkeep": Construction.upkeep("dyson"), "parent": key})
	for ship in civ.ships:
		if ship.dead or not Balance.BUILD_UPKEEP.has(ship.kind):
			continue
		result.append({"key": "ship:%d" % ship.id, "kind": "ship", "id": ship.id,
				"at": ship.cell(), "nominal": [0, 0], "q": Balance.DIMENSION_OUTPUT[str(ship.entity_dim)],
				"upkeep": Construction.upkeep(ship.kind), "parent": ""})
		if ship.kind == Ship.WANDERING_EARTH:
			result[-1].merge(EarthTransform.gross(civ,ship),true)
	result.append_array(TacticalEvents.packages(s, civ))
	result.append_array(Signals.coverage_packages(s, civ))
	return result


static func _totals(items: Array[Dictionary], active: Dictionary) -> Dictionary:
	var net := [0.0, 0.0]
	var reference := [0.0, 0.0]
	var covered := {}
	for p in items:
		if not active.get(p["key"], false):
			continue
		if p["parent"] != "" and not active.get(p["parent"], false):
			continue
		if p.has("coverage_cell"):
			if covered.has(p["coverage_cell"]):
				continue
			covered[p["coverage_cell"]] = true
		for i in 2:
			var gross: float = p["actual"][i] if p.has("actual") else p["nominal"][i] * p["q"]
			net[i] += gross - p["upkeep"][i]
			reference[i] += p["nominal"][i] - p["upkeep"][i]
	return {"net": net, "reference": reference}


## 优先级数组前面的包先保留；未排序的按稳定生成顺序处理。
static func plan(s: GameState, civ: Civ, duration := 1.0) -> Dictionary:
	var phase:=Time.get_ticks_usec() if s.profiling else 0
	var items := packages(s, civ)
	if s.profiling: phase=s._lap("经济/运营包",phase)
	var active := {}
	for p in items:
		active[p["key"]] = not civ.stopped_packages.has(p["key"])
	for p in items:
		if p["parent"] != "" and not active.get(p["parent"], false):
			active[p["key"]] = false
	var ordered: Array[String] = []
	var ordered_keys: Dictionary={}
	for key in civ.maintenance_priority:
		if active.has(key):
			ordered.append(key)
			ordered_keys[key]=true
	for p in items:
		if not ordered_keys.has(p["key"]):
			ordered.append(p["key"])
			ordered_keys[p["key"]]=true
	var totals := _totals(items, active)
	if s.profiling: phase=s._lap("经济/优先级和合计",phase)
	while civ.energy_millis + floori(totals["net"][0] * duration * WorkOrder.SCALE + civ.flow_remainder[0] + 1e-8) < 0 or civ.mineral_millis + floori(totals["net"][1] * duration * WorkOrder.SCALE + civ.flow_remainder[1] + 1e-8) < 0:
		var removed := false
		for k in range(ordered.size() - 1, -1, -1):
			var key := ordered[k]
			if not active.get(key, false):
				continue
			var index := items.find_custom(func(p): return p["key"] == key)
			var p: Dictionary = items[index]
			if p["upkeep"][0] == 0 and p["upkeep"][1] == 0:
				continue
			active[key] = false
			for child in items:
				if child["parent"] == key:
					active[child["key"]] = false
			removed = true
			break
		if not removed:
			break
		totals = _totals(items, active)
	totals["items"] = items
	totals["active"] = active
	if s.profiling: s._lap("经济/支付方案",phase)
	return totals


static func set_operating(civ: Civ, p: Dictionary) -> void:
	civ.dormant_colonies.clear()
	civ.dormant_dysons.clear()
	for ship in civ.ships:
		ship.dormant = false
	for item in p["items"]:
		if p["active"][item["key"]]:
			continue
		match item["kind"]:
			"anchor": civ.dormant_colonies[item["at"]] = true
			"dyson": civ.dormant_dysons[item["at"]] = civ.dormant_dysons.get(item["at"], 0) + 1
			"ship":
				var ship := civ.ship_by_id(item["id"])
				if ship != null:
					ship.dormant = true


static func integrate(s: GameState, civ: Civ, p: Dictionary, duration: float) -> void:
	var delta: Array[int] = []
	for i in 2:
		var exact: float = p["net"][i] * duration * WorkOrder.SCALE + civ.flow_remainder[i]
		var whole := floori(exact + 1e-8)
		civ.flow_remainder[i] = exact - whole
		delta.append(whole)
	civ.energy_millis += delta[0]
	civ.mineral_millis += delta[1]
	if delta != [0, 0]:
		if not civ.ledger.is_empty() and civ.ledger[-1]["kind"] == "production_and_upkeep" and civ.ledger[-1].get("turn", -1) == s.turn and civ.ledger[-1].get("rate", []) == p["net"]:
			civ.ledger[-1]["duration"] += duration
			for i in 2:
				civ.ledger[-1]["delta"][i] += delta[i]
		else:
			civ.ledger.append({"t": s.clock, "duration": duration, "turn": s.turn, "rate": p["net"].duplicate(), "kind": "production_and_upkeep", "delta": delta})
	assert(civ.energy_millis >= 0 and civ.mineral_millis >= 0, "维护不得产生借贷")


static func settle(s: GameState, civ: Civ) -> void:
	var p := plan(s, civ)
	set_operating(civ, p)
	integrate(s, civ, p, 1.0)
