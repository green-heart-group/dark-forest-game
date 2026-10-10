class_name Combat
extends RefCounted
## 单通道武器、在途弹丸和同刻命中批次。只在发射时消耗年初预留弹药。
## 本地自动战斗使用舰上已收到的传感历史，不更新玩家的远方地图。


static func targets(s: GameState, include_grain := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for civ in s.civs:
		var owner := s.civs.find(civ)
		for ship in civ.ships:
			if ship.dead or (ship.kind == Ship.GRAIN and not include_grain):
				continue
			result.append({"id": ship.id, "kind": ship.kind, "owner": owner, "pos": ship.pos,
					"velocity": ship.direction * ship.speed / s.physical_cell_size(),
					"hp": ship.max_hp() - ship.damage, "ship": ship})
		for asset in civ.assets:
			if asset["kind"] not in ["miner", "advanced_miner"]:
				continue
			result.append({"id": asset["id"], "kind": asset["kind"], "owner": owner,
					"pos": Signals.entity(s,owner,asset["id"])["pos"], "velocity": Vector3.ZERO if asset["carrier"] < 0 else civ.ship_by_id(asset["carrier"]).direction*civ.ship_by_id(asset["carrier"]).speed/s.physical_cell_size(), "hp": 1, "asset": asset})
	for payload in s.payloads:
		if not payload.get("dead", false):
			result.append({"id": payload["id"], "kind": "payload", "owner": payload["owner"],
					"pos": payload["pos"], "velocity": payload.get("velocity", Vector3.ZERO),
					"hp": Balance.HULL_HP["payload"] - payload.get("damage", 0), "payload": payload})
	if include_grain:
		for ship in s.hidden_ships:
			if not ship.dead:
				result.append({"id": ship.id, "kind": ship.kind, "owner": -1, "pos": ship.pos,
						"velocity": ship.direction * ship.speed / s.physical_cell_size(), "hp": 0, "ship": ship})
	return result


static func legal(weapon: String, kind: String) -> bool:
	if weapon == "hbomb":
		return kind in [Ship.WARSHIP, Ship.STARSHIP, Ship.WANDERING_EARTH]
	if weapon == "railgun":
		return kind in [Ship.WARSHIP, Ship.STARSHIP, Ship.WANDERING_EARTH, "payload"]
	return kind != Ship.GRAIN and kind != "anchor"


static func channel(civ: Civ, ship: Ship) -> String:
	var choices: Array[String] = []
	for weapon in ship.weapons:
		if not Balance.WEAPON_DATA.has(weapon):
			continue
		var price: Array = Balance.WEAPON_DATA[weapon]["cost"]
		if civ.energy_millis >= WorkOrder.units(price[0]) and civ.mineral_millis >= WorkOrder.units(price[1]):
			choices.append(weapon)
	if choices.is_empty():
		return ""
	choices.sort_custom(func(a, b):
		var aa: Dictionary = Balance.WEAPON_DATA[a]
		var bb: Dictionary = Balance.WEAPON_DATA[b]
		if ship.weapon_policy == "economy":
			return aa["cost"][0] + aa["cost"][1] < bb["cost"][0] + bb["cost"][1]
		if ship.weapon_policy == "special" and (a == "hbomb" or b == "hbomb"):
			return a == "hbomb"
		return aa["range"] > bb["range"])
	if ship.weapon_policy == "lethal":
		var best := ""
		var cost := INF
		for weapon in choices:
			var data: Dictionary = Balance.WEAPON_DATA[weapon]
			for contact in ship.local_contacts.values():
				if legal(weapon, contact["kind"]) and (weapon == "hbomb" or data["damage"] >= contact["hp"]):
					var price: float = data["cost"][0] + data["cost"][1]
					if price < cost:
						best = weapon
						cost = price
		if best != "":
			return best
	return choices[0]


static func reserve_round(s: GameState) -> void:
	for civ in s.civs:
		var ordered: Array[Ship] = civ.ships.duplicate()
		ordered.sort_custom(func(a, b): return a.id < b.id)
		for ship in ordered:
			ship.channel = ""
			ship.ammo_reserved = [0, 0]
			if not civ.alive or not ship.armed() or ship.work_locked:
				continue
			ship.channel = channel(civ, ship)
			if ship.channel == "":
				continue
			var cost: Array = Balance.WEAPON_DATA[ship.channel]["cost"]
			ship.ammo_reserved = [WorkOrder.units(cost[0]), WorkOrder.units(cost[1])]
			civ.energy_millis -= ship.ammo_reserved[0]
			civ.mineral_millis -= ship.ammo_reserved[1]
			civ.ledger.append({"t": s.clock, "kind": "ammo_reserve", "ship": ship.id, "delta": [-ship.ammo_reserved[0], -ship.ammo_reserved[1]]})


static func release(s: GameState, civ: Civ, ship: Ship) -> void:
	if ship.ammo_reserved == [0, 0]:
		return
	civ.energy_millis += ship.ammo_reserved[0]
	civ.mineral_millis += ship.ammo_reserved[1]
	civ.ledger.append({"t": s.clock, "kind": "ammo_release", "ship": ship.id, "delta": ship.ammo_reserved.duplicate()})
	ship.ammo_reserved = [0, 0]
	ship.channel = ""


## 用已观测位置及速度作线性提前瞄准；敌人后来的加速/转向不会自动修正弹道。
static func aim(origin: Vector3, target: Vector3, velocity: Vector3, speed: float) -> Vector3:
	var delta := target - origin
	var aa := velocity.length_squared() - speed * speed
	var bb := 2.0 * delta.dot(velocity)
	var cc := delta.length_squared()
	var t := 0.0
	if absf(aa) < 1e-12:
		if bb < -1e-12:
			t = -cc / bb
	else:
		var discriminant := bb * bb - 4.0 * aa * cc
		if discriminant >= 0.0:
			var a := (-bb - sqrt(discriminant)) / (2.0 * aa)
			var b := (-bb + sqrt(discriminant)) / (2.0 * aa)
			t = minf(a if a >= 0 else INF, b if b >= 0 else INF)
			if t == INF:
				t = 0.0
	return (delta + velocity * t).normalized()


static func fire_ready(s: GameState) -> void:
	for civ in s.civs:
		var ships: Array[Ship] = civ.ships.duplicate()
		ships.sort_custom(func(a, b): return a.id < b.id)
		for ship in ships:
			if not civ.alive or not ship.armed() or ship.channel == "" or ship.fired_turn == s.turn or ship.work_locked:
				continue
			var data: Dictionary = Balance.WEAPON_DATA[ship.channel]
			if ship.ammo_reserved[0] < WorkOrder.units(data["cost"][0]) or ship.ammo_reserved[1] < WorkOrder.units(data["cost"][1]):
				release(s, civ, ship)
				continue
			var options: Array = ship.local_contacts.values().filter(func(contact):
				return contact["owner"] != s.civs.find(civ) and legal(ship.channel, contact["kind"]) \
						and (ship.target_id < 0 or ship.target_id == contact["id"]) \
						and ship.pos.distance_to(predicted(s,contact)) * s.physical_cell_size() <= data["range"] + 1e-7)
			if options.is_empty():
				continue
			options.sort_custom(func(a, b):
				var da := ship.pos.distance_squared_to(predicted(s,a))
				var db := ship.pos.distance_squared_to(predicted(s,b))
				return a["id"] < b["id"] if is_equal_approx(da, db) else da < db)
			var target: Dictionary = options[0]
			var speed: float = data["speed"] * s.light_speed_at(ship.pos)
			if speed <= 0.0:
				continue
			var direction := aim(ship.pos, predicted(s,target), target["velocity"], speed / s.physical_cell_size())
			var shot := {"id": s.next_id(), "owner": s.civs.find(civ), "source": ship.id,
					"weapon": ship.channel, "pos": ship.pos, "direction": direction,
					"remaining": float(data["range"]), "distance": 0.0, "created": s.clock,
					"epoch": s.space_epoch, "dead": false}
			s.projectiles.append(shot)
			civ.ledger.append({"t": s.clock, "kind": "ammo_consumed", "ship": ship.id, "shot": shot["id"], "reserved": ship.ammo_reserved.duplicate()})
			ship.ammo_reserved = [0, 0]
			ship.fired_turn = s.turn
			ship.last_hit = s.clock
			s.events.append({"id": shot["id"], "t": s.clock, "kind": "fire", "source": ship.id, "target": target["id"], "weapon": ship.channel})


static func predicted(s: GameState,contact: Dictionary) -> Vector3:
	return contact["pos"]+contact["velocity"]*maxf(0.0,s.clock-contact.get("t_observed",s.clock))


static func projectile_motion(s: GameState, shot: Dictionary) -> Dictionary:
	var data: Dictionary = Balance.WEAPON_DATA.get(shot["weapon"], {"speed": 1.0})
	var speed: float = data["speed"] * s.light_speed_at(shot["pos"])
	return {"pos": shot["pos"], "velocity": shot["direction"] * speed / s.physical_cell_size(), "acceleration": Vector3.ZERO, "speed": speed}


static func target_motion(target: Dictionary, motions: Dictionary) -> Dictionary:
	return motions.get(target["id"], {"pos": target["pos"], "velocity": Vector3.ZERO, "acceleration": Vector3.ZERO})


static func events_in(s: GameState, motions: Dictionary, duration: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if s.clock < s.remap_until:
		return found
	var all := targets(s)
	for shot in s.projectiles:
		if shot["dead"]:
			continue
		var motion := projectile_motion(s, shot)
		var span := minf(duration, shot["remaining"] / motion["speed"]) if motion["speed"] > 0 else duration
		for target in all:
			if target["owner"] == shot["owner"] or not legal(shot["weapon"], target["kind"]):
				continue
			var t := Kinematics.relative_contact(motion, target_motion(target, motions), Balance.COLLISION_EPSILON / s.physical_cell_size(), span)
			if t != INF:
				found.append({"after": t, "kind": "hit", "shot": shot, "target": target})
	for civ in s.civs:
		for ship in civ.ships:
			if ship.dead or ship.dormant or ship.work_locked or (ship.kind != Ship.DROPLET and (ship.kind != Ship.WARSHIP or not ship.weapons.is_empty())):
				continue
			if s.clock < ship.pause_until or not motions.has(ship.id):
				continue
			for target in all:
				if target["owner"] == s.civs.find(civ):
					continue
				if ship.kind == Ship.WARSHIP and target["kind"] != Ship.WARSHIP:
					continue
				var radius := Balance.DROPLET_RANGE if ship.kind == Ship.DROPLET else Balance.SUICIDE_RANGE
				var apart := ship.pos.distance_to(target["pos"]) * s.physical_cell_size() > radius + 1e-7
				if apart:
					ship.contact_ids.erase(target["id"])
				if ship.contact_ids.has(target["id"]):
					continue
				var t := Kinematics.relative_contact(motions[ship.id], target_motion(target, motions), radius / s.physical_cell_size(), duration)
				if t != INF:
					found.append({"after": t, "kind": "contact", "ship": ship, "owner": civ, "target": target})
	return found


static func defense_roll(seed: int, shot: int, target: int, defense: String) -> float:
	return float(posmod(hash([seed, shot, target, defense]), 1000000)) / 1000000.0


static func damage(s: GameState, weapon: String, shot: int, target: Dictionary) -> int:
	var data: Dictionary = Balance.WEAPON_DATA.get(weapon, {"damage": Balance.ANTIMATTER_DAMAGE, "type": "physical"})
	if weapon == "droplet":
		data = {"damage": Balance.DROPLET_DAMAGE, "type": "physical"}
	if data["type"] == "personnel":
		return target["hp"]
	var amount: int = data["damage"]
	if target.has("ship"):
		var ship: Ship = target["ship"]
		if data["type"] == "physical" and ship.modules.has("alloy") and defense_roll(s.seed_value, shot, ship.id, "alloy") < Balance.ALLOY_CHANCE:
			amount = maxi(0, amount - Balance.ALLOY_REDUCTION)
		if data["type"] == "energy" and ship.modules.has("shield") and defense_roll(s.seed_value, shot, ship.id, "shield") < Balance.SHIELD_CHANCE:
			amount = 0
	return amount


## 先收集所有伤害和资源归属，再统一提交；本批次回收不能反过来支付已提交的攻击。
static func resolve(s: GameState, hits: Array[Dictionary]) -> void:
	hits.sort_custom(func(a, b): return a["target"]["id"] < b["target"]["id"])
	var injuries := {}
	var salvage := {}
	var chosen := {}
	for event in hits:
		var target: Dictionary = event["target"]
		var id: int = target["id"]
		var hit := -1
		var weapon := ""
		var shooter := -1
		if event["kind"] == "hit":
			var shot: Dictionary = event["shot"]
			if shot["dead"] or chosen.has(shot["id"]):
				continue
			chosen[shot["id"]] = true
			shot["dead"] = true
			hit = shot["id"]
			weapon = shot["weapon"]
			shooter = shot["owner"]
		else:
			var ship: Ship = event["ship"]
			if chosen.has(ship.id):
				continue
			chosen[ship.id] = true
			hit = s.next_id()
			weapon = "droplet" if ship.kind == Ship.DROPLET else "suicide"
			ship.contact_ids.append(id)
			ship.pause_until = s.clock + Balance.DROPLET_PAUSE
			ship.last_hit = s.clock
			if weapon == "suicide":
				injuries[ship.id] = {"target": {"ship": ship, "owner": s.civs.find(event["owner"])}, "damage": ship.max_hp()}
		if s.applied_hits.has(hit):
			continue
		s.applied_hits[hit] = true
		if not injuries.has(id):
			injuries[id] = {"target": target, "damage": 0}
		injuries[id]["damage"] += target["hp"] if weapon == "suicide" else damage(s, weapon, hit, target)
		if weapon == "hbomb" and target.has("ship") and not target["ship"].salvage_claimed:
			if not salvage.has(id) or hit < salvage[id]["hit"]:
				salvage[id] = {"hit": hit, "owner": shooter, "ship": target["ship"]}
		s.events.append({"id": hit, "t": s.clock, "kind": "hit", "target": id, "weapon": weapon})
	s._collapse_depth += 1
	for item in injuries.values():
		var target: Dictionary = item["target"]
		var owner: Civ = s.civs[target["owner"]] if target["owner"] >= 0 else null
		if target.has("ship"):
			var ship: Ship = target["ship"]
			ship.damage += item["damage"]
			ship.last_hit = s.clock
			ship.next_repair = s.clock + repair_interval(ship)
			if ship.damage >= ship.max_hp():
				s._destroy(owner, ship, "常规攻击")
		elif target.has("asset"):
			if item["damage"] > 0 and owner != null:
				Assets.destroy(owner, target["asset"])
		elif target.has("payload"):
			target["payload"]["damage"] += item["damage"]
			if target["payload"]["damage"] >= Balance.HULL_HP["payload"]:
				target["payload"]["dead"] = true
	for award in salvage.values():
		var ship: Ship = award["ship"]
		ship.salvage_claimed = true
		var receiver: Civ = s.civs[award["owner"]]
		var delta := [WorkOrder.units(ship.cost[0] * Balance.SALVAGE_RATE), WorkOrder.units(ship.cost[1] * Balance.SALVAGE_RATE)]
		receiver.energy_millis += delta[0]
		receiver.mineral_millis += delta[1]
		receiver.ledger.append({"t": s.clock, "kind": "salvage", "target": ship.id, "delta": delta})
	s._collapse_depth -= 1


static func repair_interval(ship: Ship) -> float:
	if ship.kind == Ship.STARSHIP:
		return Balance.STARSHIP_REPAIR_INTERVAL
	if ship.kind == Ship.WARSHIP and ship.modules.has("shield"):
		return Balance.SHIELD_REPAIR_INTERVAL
	return INF


static func repair(s: GameState) -> void:
	for civ in s.civs:
		for ship in civ.ships:
			var interval := repair_interval(ship)
			if not ship.dead and not ship.dormant and ship.damage > 0 and s.clock >= maxf(ship.next_repair, ship.last_hit + interval):
				ship.damage -= 1
				ship.next_repair = s.clock + interval
