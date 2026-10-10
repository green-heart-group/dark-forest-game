class_name AI
extends RefCounted
## 简单 AI。只用自己知道的信息（known、heard、hit_dirs、sightings），和玩家用同一套规则和价格。
## 先保障首个矿源，再按原优先顺序提交研究和行动；研究、建造与命令都消耗 AP。

## 升级科技时至少留下这么多能量
const RESERVE := 6
## 同时在飞的探测器个数
const PROBES_WANTED := 2
## 探测器出星图前至少要飞出母星系视野这么多格，才算朝有东西可看的方向派
const PROBE_MIN_REACH := 1.0
## 随机挑探测方向时最多试几次
const PROBE_TRIES := 8
## 发过光粒的目标，这么多回合内不再发
const GRAIN_WAIT := 14

## 各项科技的基础优先分（越大越先升）
const PRIORITY := {
	"colony": 7.0, "dyson": 6.0, "warship": 5.0, "interstellar_probe": 3.0, "bunker": 3.0,
	"grain": 7.0, "antimatter": 3.0, "warp": 2.0, "starship": 3.0, "gravity": 1.0, "devourer": 2.0,
	"dimension": 5.0, "dark_energy": 4.0, "domain": 2.0, "beam": 4.0, "torpedo": 3.0, "hbomb": 3.0, "sophon": 3.0,
}


static func take_turn(s: GameState, ai: Civ) -> void:
	_consume_command_results(s, ai)
	# V0.1 不再赠送基础矿收入，先保障真实矿源；旧优先表不能花光首艘矿船预算。
	_bootstrap_mining(s, ai)
	_research(s, ai)
	if _flat_near(s, ai) and not (ai.line_reduced if s.all_flat() else ai.reduced) and _conversion_plan(s, ai).is_empty():
		if s.reduce_error(ai) == "":
			s.start_reduce(ai)
			s.ai_note(ai, "压平的区域快到了，先降维")
		else:
			var cost: Array = Conversion.quote(Conversion.known_roster(s,ai,s.dimension), false)["cost"]
			if s._money_error(ai, cost[0], cost[1]) != "":
				s.ai_note(ai, "压平的区域快到了，先保留迁维所需资源")
				return
	if Knowledge.colonies(s,ai).is_empty() and s.reported_starship(ai)!=null:
		s.ai_note(ai, "只剩星舰，去找能殖民的星系")
		_starship_turn(s, ai)
		return
	var target := _nearest_known(s, ai)
	if target != GameState.NO_HIT:
		s.ai_note(ai, "知道 %d 个敌方星系，打最近的 %s" % [ai.known.size(), target])
	elif not ai.hit_dirs.is_empty():
		s.ai_note(ai, "不知道敌人在哪，但被打过，朝打来的方向反击")
	else:
		s.ai_note(ai, "还不知道敌人在哪，发展和探索")
	var done := {}
	var guard := 0
	while ai.actions_left > 0 and ai.alive and not s.is_over() and guard < 40:
		guard += 1
		if not _act(s, ai, done):
			break


## 只消费已经传回控制锚点的结果；远端实际失败不能提前改变目标或释放待命标记。
static func _consume_command_results(s: GameState, ai: Civ) -> void:
	while ai.ai_receipt_cursor < ai.command_results.size():
		var result: Dictionary = ai.command_results[ai.ai_receipt_cursor]
		ai.ai_receipt_cursor += 1
		if result["executed"]:
			continue
		var request: String = result.get("request_name", "")
		var target: Vector3i = result.get("request_target", GameState.NO_HIT)
		if target != GameState.NO_HIT:
			if request in ["send_colony", "move_starship"]:
				ai.colony_tried.erase(target)
			elif request == "send_sophon":
				ai.sophon_tried.erase(target)
		s.ai_note(ai, "收到命令失败回执：%s；%s" % [request, result.get("reason", "")])


## 按局面给能升的科技打分，挑最高的升，留一点能量。
static func _research(s: GameState, ai: Civ) -> void:
	for i in 3:
		var best := ""
		var best_score := -INF
		for id in Tech.ALL:
			if ai.has_tech(id):
				continue
			if s.research_block_error(ai, id) != "":
				continue  # 钱不够的先留着打分，攒够了再升
			var score: float = PRIORITY.get(id, 1.0) + ai.taste.get(id, 0.0)
			if id == "dyson":
				for at in Knowledge.colonies(s,ai):
					score += StarMap.star_count(ai.intel.get(at, {}).get("stars", StarMap.Star.NONE))
			if ai.times_hit > 0 and (id == "bunker" or id == "antimatter"):
				score += 4.0
			if score > best_score:
				best_score = score
				best = id
		if best == "":
			break
		var cost := Tech.cost(best)
		if not _keeps_reserves(s,ai, cost, RESERVE):
			break
		if s.research(ai, best)["error"] != "":
			break
	# 还没发现别人时升级射电望远镜，看得更远
	if not ai.discovered and _keeps_reserves(s,ai, s.upgrade_price(ai, "telescope"), 2 * RESERVE):
		s.upgrade(ai, "telescope")
	if ai.times_hit > 0 and not Knowledge.flag_cells(s,ai,"warning").is_empty() and _keeps_reserves(s,ai, s.upgrade_price(ai, "warning"), 3 * RESERVE):
		s.upgrade(ai, "warning")


static func _keeps_reserves(s: GameState, ai: Civ, cost: Array, energy_reserve: float) -> bool:
	if ai.energy_millis - WorkOrder.units(cost[0]) < WorkOrder.units(energy_reserve):
		return false
	var mineral_left := ai.mineral_millis - WorkOrder.units(cost[1])
	if mineral_left < 0:
		return false
	return Knowledge.miners(s,ai) > 0 or Knowledge.pending(ai,"miner") > 0 \
			or mineral_left >= WorkOrder.units(Construction.cost("miner")[1])


## 做一件事，做成了返回 true。done 记这一回合已经做过的几类事，免得行动点全花在同一件事上。
static func _act(s: GameState, ai: Civ, done: Dictionary) -> bool:
	if ai.antimatter > 0 and not s.antimatter_targets(ai).is_empty() and s.use_antimatter(ai)["error"] == "":
		return true
	if _try_foil(s, ai):
		return true
	var target := _nearest_known(s, ai)
	if target != GameState.NO_HIT:
		if _try_grain(s, ai, target):
			return true
		if not done.has("warship") and _try_warship(s, ai, target):
			done["warship"] = true
			return true
	elif not done.has("warship") and _try_warship_hit_dir(s, ai):
		done["warship"] = true
		return true
	if not done.has("turn") and _try_turn_warships(s, ai):
		done["turn"] = true
		return true
	if not done.has("broadcast") and _try_broadcast(s, ai):
		done["broadcast"] = true
		return true
	if not done.has("sophon") and _try_sophon(s, ai):
		done["sophon"] = true
		return true
	if ai.has_tech("warning") and Knowledge.flag_cells(s,ai,"warning").is_empty() and Knowledge.pending(ai,"warning") == 0 \
			and s.build(ai, "warning")["error"] == "":
		return true
	if _try_domain(s, ai):
		return true
	if ai.times_hit > 0 and _try_bunker(s, ai):
		return true
	if ai.times_hit > 0 and _reported_count(s, ai, Ship.STARSHIP) == 0 and s.build(ai, "starship")["error"] == "":
		return true
	if not done.has("colony") and _try_colonize(s, ai):
		done["colony"] = true
		return true
	if not done.has("miner") and _try_each(s, ai, "miner"):
		done["miner"] = true
		return true
	if not done.has("dyson") and _try_each(s, ai, "dyson"):
		done["dyson"] = true
		return true
	if ai.has_tech("antimatter") and ai.antimatter == 0 and s.build(ai, "antimatter")["error"] == "":
		return true
	if not done.has("probe") and _try_probe(s, ai):
		done["probe"] = true
		return true
	if not done.has("devourer") and _try_devourer(s, ai):
		done["devourer"] = true
		return true
	if Knowledge.flag_cells(s,ai,"broadcaster").is_empty() and Knowledge.pending(ai,"broadcaster") == 0 and ai.energy > 20 \
			and s.build(ai, "broadcaster")["error"] == "":
		return true
	return false


## 离自己最近的已知敌方星系（已经压平的不算），没有时为 NO_HIT。
static func _nearest_known(s: GameState, ai: Civ) -> Vector3i:
	var best := GameState.NO_HIT
	var best_d := INF
	for t in ai.known:
		if Knowledge.owns(s,ai,t) or not s.cell_exists(t):
			continue
		var d := GameState.nearest_distance(Knowledge.colonies(s,ai), Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	return best


## 有存着光粒的星系就朝目标发射；没有就造一颗。
static func _try_grain(s: GameState, ai: Civ, target: Vector3i) -> bool:
	if not ai.has_tech("grain") or (ai.aimed.has(target) and s.turn - ai.aimed[target] < GRAIN_WAIT):
		return false
	for c in Knowledge.flag_cells(s,ai,"grain"):
		if ai.energy < GameState.action_cost("launch_grain"):
			return false
		if s.launch_grain(ai, Vector3(target - c), c)["error"] == "":
			ai.aimed[target] = s.turn
			return true
	if Knowledge.flag_cells(s,ai,"grain").is_empty():
		for c in Knowledge.colonies(s,ai):
			if s.build(ai, "grain", c)["error"] == "":
				return true
	return false


## 有停着的战舰就朝目标派出；没有就造一艘。
static func _try_warship(s: GameState, ai: Civ, target: Vector3i) -> bool:
	if not ai.has_tech("warship"):
		return false
	var ship := _docked(s, ai, Ship.WARSHIP)
	if ship == null:
		var flying := Knowledge.pending(ai,"warship")
		for sh in Signals.reported_ships(s, ai):
			if sh.kind == Ship.WARSHIP and (not sh.docked or s.ship_command_pending(ai, sh.id)):
				flying += 1
		if flying >= 2:
			return false
		var modules := warship_modules(ai)
		var result := s.build(ai, "warship", _nearest_colony(s,ai, Vector3(target)), modules)
		return result["error"] == ""
	return s.dispatch(ai, ship.id, Vector3(target) - ship.pos)["error"] == ""


## 没有已知目标、但被打过时，朝打击来的方向派战舰（反击）。
static func _try_warship_hit_dir(s: GameState, ai: Civ) -> bool:
	if ai.hit_dirs.is_empty() or not ai.has_tech("warship"):
		return false
	var h: Dictionary = ai.hit_dirs[-1]
	if s.turn - h["turn"] > 20:
		return false
	for sh in Signals.reported_ships(s, ai):
		if sh.kind == Ship.WARSHIP and (not sh.docked or s.ship_command_pending(ai, sh.id)):
			return false
	var ship := _docked(s, ai, Ship.WARSHIP)
	if ship == null:
		if Knowledge.pending(ai,"warship") > 0:
			return false
		return s.build(ai, "warship", ai.home, warship_modules(ai))["error"] == ""
	return s.dispatch(ai, ship.id, h["dir"])["error"] == ""


## 在飞的战舰偏离已知目标太多时转向。
static func _try_turn_warships(s: GameState, ai: Civ) -> bool:
	for sh in Signals.reported_ships(s, ai):
		if sh.kind != Ship.WARSHIP or sh.docked or sh.direction == Vector3.ZERO or sh.work_locked or sh.dormant \
				or s.ship_command_pending(ai, sh.id):
			continue
		var best := GameState.NO_HIT
		var best_d := INF
		for t in ai.known:
			var d := sh.pos.distance_to(Vector3(t))
			if d < best_d and s.cell_exists(t):
				best_d = d
				best = t
		if best == GameState.NO_HIT or best_d < 1.0:
			continue
		var want := (Vector3(best) - sh.pos).normalized()
		if want.angle_to(sh.direction) > deg_to_rad(25) and ai.energy >= s.command_cost(ai, sh) + RESERVE:
			return s.turn_ship(ai, sh.id, want)["error"] == ""
	return false


## 离自己远的已知目标，广播出去借刀杀人（每个坐标一次）。
static func _try_broadcast(s: GameState, ai: Civ) -> bool:
	if ai.energy < GameState.action_cost("broadcast") + RESERVE:
		return false
	for t in ai.known:
		if ai.broadcasted.has(t) or GameState.nearest_distance(Knowledge.colonies(s,ai), Vector3(t)) < 4.0:
			continue
		for c in Knowledge.colonies(s,ai):
			if s.can_broadcast_from(ai, c) and s.broadcast(ai, t, c)["error"] == "":
				ai.broadcasted[t] = true
				return true
	return false


## 派智子去还没去过的已知敌方星系持续侦察；V0.1 智子不锁定科技。
## 没有能派的智子、能量又宽裕时造一个。
static func _try_sophon(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("sophon"):
		return false
	var best := GameState.NO_HIT
	var best_d := INF
	for t in ai.known:
		if ai.sophon_tried.has(t) or Knowledge.owns(s,ai,t) or not s.cell_exists(t):
			continue
		var d := GameState.nearest_distance(Knowledge.colonies(s,ai), Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	if best == GameState.NO_HIT:
		return false
	var ship: Ship = null
	for sh in Signals.reported_ships(s, ai):
		if sh.kind == Ship.SOPHON and sh.waiting() and not sh.work_locked and not sh.dormant \
				and not s.ship_command_pending(ai, sh.id):
			ship = sh
	if ship == null:
		if Knowledge.pending(ai,"sophon") > 0:
			return false
		var command_price := s.command_cost(ai, Ship.make(Ship.SOPHON, Vector3(ai.home), -1))
		if ai.energy < s.build_cost(ai, "sophon")[0] + command_price + 4 * RESERVE:
			return false
		return s.build(ai, "sophon", _nearest_colony(s,ai, Vector3(best)))["error"] == ""
	if s.send_sophon(ai, ship.id, best)["error"] == "":
		ai.sophon_tried[best] = true
		return true
	return false


## 被打中过、有两个以上星系时，让母星系躲进黑域。
static func _try_domain(s: GameState, ai: Civ) -> bool:
	if ai.times_hit == 0 or Knowledge.colonies(s,ai).size() < 2 or not ai.has_tech("domain"):
		return false
	if Knowledge.site(s,ai,ai.home).get("relative_light",1.0)<Balance.GRAIN_MIN_LIGHT or not ai.pending_domains.is_empty():
		return false
	return s.launch_black_domain(ai, ai.home)["error"] == ""


static func _try_bunker(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("bunker"):
		return false
	for c in Knowledge.colonies(s,ai):
		if not Knowledge.site(s,ai,c).get("bunker",false) and ai.intel.get(c, {}).get("gas", 0) > 0 and s.build(ai, "bunker", c)["error"] == "":
			return true
	return false


static func _try_each(s: GameState, ai: Civ, kind: String) -> bool:
	if not ai.has_tech(kind):
		return false
	for c in Knowledge.colonies(s,ai):
		if kind == "miner" and ai.has_tech("mining_advanced") and s.refit_miner_error(ai, c) == "":
			return s.refit_miner(ai, c)["error"] == ""
		var model := "advanced_miner" if kind == "miner" and ai.has_tech("mining_advanced") else kind
		if s.build(ai, model, c)["error"] == "":
			return true
	return false


## 据点告急且没有常规武器时才考虑降维打击；全图一维后争取奇异点。
static func _try_foil(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("dimension") or not ai.foils.is_empty():
		return false
	var target := _nearest_known(s, ai)
	if target == GameState.NO_HIT:
		return false
	if s.all_linear():
		if ai.dimension_ammo == 0:
			return _try_dimension_ammo(s, ai)
		return s.launch_singularity(ai, target)["error"] == ""
	# 末日武器只在据点告急或敌方已经展开降维时考虑，优先常规反击。
	if not _flat_near(s, ai) and not (ai.times_hit >= Balance.AI_FOIL_HITS and Knowledge.colonies(s,ai).size() <= 1):
		return false
	if _reported_count(s, ai, Ship.WARSHIP) > 0 or not Knowledge.flag_cells(s,ai,"grain").is_empty():
		return false
	var to_line := s.all_flat()
	if s.foil_target_error(ai, to_line, target) != "":
		return false
	if not (ai.line_reduced if to_line else ai.reduced):
		var plan := _conversion_plan(s, ai)
		if not plan.is_empty():
			if not plan["ready_at"].has(Signals.controller(ai)):
				return false
			return s.execute_conversion(ai, plan["id"])["error"] == ""
		var cost: Array = Conversion.quote(Conversion.known_roster(s,ai,s.dimension), false)["cost"]
		if ai.energy < maxf(Balance.AI_FOIL_ENERGY, cost[0]) or ai.mineral < cost[1]:
			return false
		return s.start_reduce(ai)["error"] == ""
	if ai.dimension_ammo == 0:
		return _try_dimension_ammo(s, ai)
	var origin := _nearest_colony(s,ai, Vector3(target))
	return (s.launch_line_foil(ai, target, origin) if to_line else s.launch_foil(ai, target, origin))["error"] == ""


static func _conversion_plan(s: GameState, ai: Civ) -> Dictionary:
	for plan in ai.conversions.values():
		if plan["from_dim"] == s.dimension and ai.order_reports.get(plan["id"],{}).get("status","") not in ["cancelled","failed","destroyed"]:
			return plan
	return {}


static func _try_dimension_ammo(s: GameState, ai: Civ) -> bool:
	if Knowledge.pending(ai,"dimension_weapon") > 0:
		return false
	return s.build(ai, "dimension_weapon")["error"] == ""


## 派殖民船去最近的、看到过的宜居星系（F4.4：只知道情报里的）；没有停着的殖民船就造一艘。
static func _try_colonize(s: GameState, ai: Civ) -> bool:
	var habitable := s.known_habitable(ai)
	var origins:=Knowledge.colonies(s,ai).duplicate()
	if origins.is_empty():
		var mobile:=s.reported_starship(ai)
		if mobile!=null: origins.append(mobile.cell())
	for transport in Signals.reported_ships(s, ai):
		if transport.kind == Ship.COLONY and transport.waiting() and not transport.work_locked \
				and not transport.dormant and not s.ship_command_pending(ai, transport.id) \
				and habitable.has(transport.cell()) and s.landing_error(ai, transport.id) == "":
			return s.start_landing(ai, transport.id)["error"] == ""
	if not ai.has_tech("colony"):
		return false
	var best := GameState.NO_HIT
	var best_d := INF
	for t in habitable:
		if ai.colony_tried.has(t):
			continue
		var d := GameState.nearest_distance(origins, Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	if best == GameState.NO_HIT:
		return false
	var ship := _idle_colony_ship(s, ai)
	if ship == null:
		if Knowledge.pending(ai,"colony") > 0:
			return false
		var at: Vector3i=_nearest_colony(s,ai,Vector3(best)) if not Knowledge.colonies(s,ai).is_empty() else origins[0]
		return s.build(ai, "colony", at)["error"] == ""
	if s.send_colony(ai, ship.id, best)["error"] == "":
		ai.colony_tried[best] = true
		return true
	return false


## 能派的殖民船：停在星系里的，或者上次到了没能殖民、停在外面的（没有时为 null）。
static func _idle_colony_ship(s: GameState, ai: Civ) -> Ship:
	for sh in Signals.reported_ships(s, ai):
		if sh.kind == Ship.COLONY and not sh.work_locked and not sh.dormant and sh.waiting() \
				and not s.ship_command_pending(ai, sh.id):
			return sh
	return null


## 停在星系里、还没派出的某种单位（没有时为 null）。
static func _docked(s: GameState, ai: Civ, kind: String) -> Ship:
	for sh in Signals.reported_ships(s, ai):
		if sh.kind == kind and sh.docked and not sh.work_locked and not sh.dormant \
				and not s.ship_command_pending(ai, sh.id):
			return sh
	return null


static func _reported_count(s: GameState, ai: Civ, kind: String) -> int:
	var count := 0
	for ship in Signals.reported_ships(s, ai):
		if ship.kind == kind:
			count += 1
	return count


## 保持几个探测器在飞：朝最近被打来的方向、最近看到的东西，或者随机方向（先慢速飞出视野）。
## 只朝出星图前还能飞出视野一段的方向派（_worth_probing），比如从星图外打来的方向就不去。
static func _try_probe(s: GameState, ai: Civ) -> bool:
	var flying := Knowledge.pending(ai,"probe") + Knowledge.pending(ai,"nuclear_probe")
	var docked: Ship = null
	for sh in Signals.reported_ships(s, ai):
		if sh.kind in [Ship.PROBE, Ship.NUCLEAR_PROBE]:
			if s.ship_command_pending(ai, sh.id):
				flying += 1
			elif sh.docked and not sh.work_locked and not sh.dormant:
				docked = sh
			elif not sh.parked:
				flying += 1
	if flying >= PROBES_WANTED + Knowledge.colonies(s,ai).size() / 3:
		return false
	if docked == null:
		return s.build(ai, "nuclear_probe" if ai.has_tech("interstellar_probe") else "probe")["error"] == ""
	var dir := Vector3.ZERO
	var slow := false
	if not ai.hit_dirs.is_empty() and s.rng.randf() < 0.5:
		dir = ai.hit_dirs[-1]["dir"]
	elif not ai.sightings.is_empty() and s.rng.randf() < 0.5:
		dir = ai.sightings[-1]["pos"] - docked.pos
	if not _worth_probing(s, ai, docked.pos, dir):
		dir = _random_probe_direction(s, ai, docked.pos)
		slow = true
	return s.dispatch(ai, docked.id, dir, slow)["error"] == ""


## 从 from 朝 dir 派探测器值不值得：出星图前要飞出母星系视野至少 PROBE_MIN_REACH 格。
## 只看星图边界和自己的视野，不看别人在哪。
static func _worth_probing(s: GameState, ai: Civ, from: Vector3, dir: Vector3) -> bool:
	dir = s.space_direction(dir)
	if dir == Vector3.ZERO:
		return false
	return Geometry.distance_to_edge(from, dir, s.map.bounds()) \
			>= s.sphere_radius(ai, Balance.VISION_HOME) + PROBE_MIN_REACH


## 随机挑一个值得派的方向：不值得时，把朝离得近的那一边的分量反过来（朝星图中间）再看一次。
## 试 PROBE_TRIES 次都不值得时，用其中出星图前飞得最远的。
static func _random_probe_direction(s: GameState, ai: Civ, from: Vector3) -> Vector3:
	var center := s.map.bounds().get_center() - Vector3.ONE * Geometry.CELL_HALF
	var best := Vector3.ZERO
	var best_reach := -1.0
	for i in PROBE_TRIES:
		var d := s.random_direction()
		if _worth_probing(s, ai, from, d):
			return d
		for axis in 3:
			if d[axis] * (from[axis] - center[axis]) > 0.0:
				d[axis] = -d[axis]
		if _worth_probing(s, ai, from, d):
			return d
		var reach := Geometry.distance_to_edge(from, s.space_direction(d), s.map.bounds())
		if s.space_direction(d) != Vector3.ZERO and reach > best_reach:
			best_reach = reach
			best = d
	return best


static func _try_devourer(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("devourer"):
		return false
	for sh in Signals.reported_ships(s, ai):
		if sh.kind == Ship.DEVOURER:
			if sh.docked and not sh.work_locked and not sh.dormant and not s.ship_command_pending(ai, sh.id):
				return s.dispatch(ai, sh.id, s.random_direction())["error"] == ""
			return false
	return s.build(ai, "devourer")["error"] == ""


static func _nearest_colony(s: GameState, ai: Civ, p: Vector3) -> Vector3i:
	var best := ai.home
	var best_d := INF
	for c in Knowledge.colonies(s,ai):
		var d := Vector3(c).distance_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## 只剩星舰的 AI：先沿现有109运输/落地流程恢复星系；否则飞向最近的、看到过的、没去过的宜居星系；
## 一个也不知道时随便挑一个格子飞过去，路上看看（F4.4）。
static func _starship_turn(s: GameState, ai: Civ) -> void:
	if _try_colonize(s,ai): return
	var ship: Ship = null
	for known in Signals.reported_ships(s, ai):
		if known.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH]:
			ship = known
			break
	if ship == null or s.ship_command_pending(ai, ship.id):
		return
	if ship.direction != Vector3.ZERO and not ship.docked:
		return  # 还在飞
	if Knowledge.pending(ai,"colony")>0 or Signals.reported_ships(s,ai).any(func(unit):return unit.kind==Ship.COLONY):
		return # 运输/落地进行中，不能靠旧免费定居入口消耗生存锚点。
	var best := GameState.NO_HIT
	var best_d := INF
	for t in s.known_habitable(ai):
		if ai.colony_tried.has(t):
			continue
		var d := Vector3(t).distance_to(ship.pos)
		if d < best_d:
			best_d = d
			best = t
	if best == GameState.NO_HIT:
		var n := s.map.extent - Vector3i.ONE
		best = s.map.origin + Vector3i(s.rng.randi_range(0, n.x), s.rng.randi_range(0, n.y), s.rng.randi_range(0, n.z))
		if not s.starship_target_ok(ai, best):
			return
	if s.move_starship(ai, best)["error"] == "":
		ai.colony_tried[best] = true


## 根据已收到的观测估计：压平区域在 AI_REDUCE_ALERT 回合内可能威胁某个据点。
static func _flat_near(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("dimension"):
		return false
	var origins := Knowledge.colonies(s,ai).duplicate()
	for ship in Signals.reported_ships(s, ai):
		if ship.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH]:
			origins.append(ship.cell())
	for c in origins:
		if s.known_front_eta(ai, c) <= Balance.AI_REDUCE_ALERT:
			return true
	return false


## 旧策略选择武器，现在显式下单模块，不能因研究而免费给全舰队加装。
static func warship_modules(civ: Civ) -> Array:
	for weapon in ["hbomb", "torpedo", "beam", "railgun"]:
		if civ.has_tech(weapon):
			return [weapon]
	return []


static func _bootstrap_mining(s: GameState, civ: Civ) -> void:
	if Knowledge.colonies(s,civ).is_empty() or Knowledge.miners(s,civ) > 0 or Knowledge.pending(civ,"miner") > 0:
		return
	for at in Knowledge.colonies(s,civ):
		if s.build_error(civ, "miner", at) == "":
			s.build(civ, "miner", at)
			return
	if civ.mineral < Construction.cost("miner")[1] and s.emergency_work_error(civ, "M") == "":
		s.emergency_work(civ, "M")
