class_name AI
extends RefCounted
## 简单 AI。只用自己知道的信息（known、heard、hit_dirs、sightings），和玩家用同一套规则和价格。
## 每回合先升级科技（不花行动点），再按优先顺序花行动点，直到没事可做。

## 升级科技时至少留下这么多能量
const RESERVE := 6
## 同时在飞的探测器个数
const PROBES_WANTED := 2
## 发过光粒的目标，这么多回合内不再发
const GRAIN_WAIT := 14

## 各项科技的基础优先分（越大越先升）
const PRIORITY := {
	"colony": 7.0, "dyson": 6.0, "warship": 5.0, "interstellar_probe": 3.0, "bunker": 3.0,
	"grain": 7.0, "antimatter": 3.0, "warp": 2.0, "starship": 3.0, "gravity": 1.0, "devourer": 2.0,
	"dimension": 5.0, "dark_energy": 4.0, "domain": 2.0, "beam": 4.0, "torpedo": 3.0, "hbomb": 3.0, "sophon": 3.0,
}


static func take_turn(s: GameState, ai: Civ) -> void:
	_research(s, ai)
	if _flat_near(s, ai) and not (ai.line_reduced if s.all_flat() else ai.reduced) and ai.reduce_left == 0:
		if s.start_reduce(ai)["error"] != "":
			s.ai_note(ai, "压平的区域快到了，能量不够降维，这回合什么都不做，先攒着")
			return
		s.ai_note(ai, "压平的区域快到了，先降维")
	if ai.starship_only():
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


## 按局面给能升的科技打分，挑最高的升，留一点能量。
static func _research(s: GameState, ai: Civ) -> void:
	for i in 3:
		var best := ""
		var best_score := -INF
		for id in Tech.ALL:
			if ai.has_tech(id) or Tech.tier(id) == 0:
				continue
			var err := s.research_error(ai, id)
			if err != "" and err != "能量不足" and err != "矿石不足":
				continue
			var score: float = PRIORITY.get(id, 1.0) + ai.taste.get(id, 0.0)
			if id == "dyson":
				score += ai.star_total(s.map)
			if ai.times_hit > 0 and (id == "bunker" or id == "antimatter"):
				score += 4.0
			# 被智子锁住时，先升智子来解锁
			if id == "sophon" and not s.sophons_on(ai).is_empty():
				score += 10.0
			if score > best_score:
				best_score = score
				best = id
		if best == "":
			break
		var cost := Tech.cost(best)
		if ai.energy - cost[0] < RESERVE or ai.mineral < cost[1]:
			break
		s.research(ai, best)
	# 还没发现别人时升级射电望远镜，看得更远
	if not ai.discovered and ai.energy >= Balance.COST_TELESCOPE + 2 * RESERVE:
		s.upgrade(ai, "telescope")
	if ai.times_hit > 0 and ai.has_warning and ai.energy >= Balance.COST_WARNING_UPGRADE + 3 * RESERVE:
		s.upgrade(ai, "warning")


## 做一件事，做成了返回 true。done 记这一回合已经做过的几类事，免得行动点全花在同一件事上。
static func _act(s: GameState, ai: Civ, done: Dictionary) -> bool:
	if ai.antimatter > 0 and not s.antimatter_targets(ai).is_empty() and s.use_antimatter(ai)["error"] == "":
		return true
	# 被智子锁住：造一个自己的智子解锁
	if not s.sophons_on(ai).is_empty() and s.build(ai, "sophon")["error"] == "":
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
	if ai.has_tech("warning") and not ai.has_warning and ai.pending_count("warning") == 0 \
			and s.build(ai, "warning")["error"] == "":
		return true
	if _try_domain(s, ai):
		return true
	if ai.times_hit > 0 and _try_bunker(s, ai):
		return true
	if ai.times_hit > 0 and ai.count(Ship.STARSHIP) == 0 and s.build(ai, "starship")["error"] == "":
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
	if s.tier_open(ai, 2) and ai.antimatter == 0 and s.build(ai, "antimatter")["error"] == "":
		return true
	if not done.has("probe") and _try_probe(s, ai):
		done["probe"] = true
		return true
	if not done.has("devourer") and _try_devourer(s, ai):
		done["devourer"] = true
		return true
	if ai.broadcasters.is_empty() and ai.pending_count("broadcaster") == 0 and ai.energy > 20 \
			and s.build(ai, "broadcaster")["error"] == "":
		return true
	return false


## 离自己最近的已知敌方星系（已经压平的不算），没有时为 NO_HIT。
static func _nearest_known(s: GameState, ai: Civ) -> Vector3i:
	var best := GameState.NO_HIT
	var best_d := INF
	for t in ai.known:
		if not s.cell_exists(t):
			continue
		var d := GameState._nearest(ai.colonies, Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	return best


## 有存着光粒的星系就朝目标发射；没有就造一颗。
static func _try_grain(s: GameState, ai: Civ, target: Vector3i) -> bool:
	if not ai.has_tech("grain") or (ai.aimed.has(target) and s.turn - ai.aimed[target] < GRAIN_WAIT):
		return false
	for c in ai.grains:
		if ai.energy < Balance.COST_GRAIN_LAUNCH:
			return false
		if s.launch_grain(ai, Vector3(target - c), c)["error"] == "":
			ai.aimed[target] = s.turn
			return true
	if ai.grains.is_empty():
		for c in ai.colonies:
			if s.build(ai, "grain", c)["error"] == "":
				return true
	return false


## 有停着的战舰就朝目标派出；没有就造一艘。
static func _try_warship(s: GameState, ai: Civ, target: Vector3i) -> bool:
	if not ai.has_tech("warship"):
		return false
	var built := false
	var ship := _docked(ai, Ship.WARSHIP)
	if ship == null:
		var flying := 0
		for sh in ai.ships:
			if sh.kind == Ship.WARSHIP and not sh.docked:
				flying += 1
		if flying >= 2:
			return false
		ship = s.build(ai, "warship", _nearest_colony(ai, Vector3(target)))["ship"]
		if ship == null:
			return false
		built = true
	return s.dispatch(ai, ship.id, Vector3(target) - ship.pos)["error"] == "" or built


## 没有已知目标、但被打过时，朝打击来的方向派战舰（反击）。
static func _try_warship_hit_dir(s: GameState, ai: Civ) -> bool:
	if ai.hit_dirs.is_empty() or not ai.has_tech("warship"):
		return false
	var h: Dictionary = ai.hit_dirs[-1]
	if s.turn - h["turn"] > 20:
		return false
	for sh in ai.ships:
		if sh.kind == Ship.WARSHIP and not sh.docked:
			return false
	var built := false
	var ship := _docked(ai, Ship.WARSHIP)
	if ship == null:
		ship = s.build(ai, "warship")["ship"]
		if ship == null:
			return false
		built = true
	return s.dispatch(ai, ship.id, h["dir"])["error"] == "" or built


## 在飞的战舰偏离已知目标太多时转向。
static func _try_turn_warships(s: GameState, ai: Civ) -> bool:
	for sh in ai.ships:
		if sh.kind != Ship.WARSHIP or sh.docked or sh.direction == Vector3.ZERO:
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
		if want.angle_to(sh.direction) > deg_to_rad(25) and ai.energy >= Balance.COST_TURN + RESERVE:
			return s.turn_ship(ai, sh.id, want)["error"] == ""
	return false


## 离自己远的已知目标，广播出去借刀杀人（每个坐标一次）。
static func _try_broadcast(s: GameState, ai: Civ) -> bool:
	if ai.energy < Balance.COST_BROADCAST + RESERVE:
		return false
	for t in ai.known:
		if ai.broadcasted.has(t) or GameState._nearest(ai.colonies, Vector3(t)) < 4.0:
			continue
		for c in ai.colonies:
			if s.can_broadcast_from(ai, c) and s.broadcast(ai, t, c)["error"] == "":
				ai.broadcasted[t] = true
				return true
	return false


## 派智子去还没去过的已知敌方星系（猜它是母星系），已经被自己的智子锁住的文明不再派。
## 没有能派的智子、能量又宽裕时造一个。
static func _try_sophon(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("sophon"):
		return false
	var locked := {}
	for sh in ai.ships:
		if sh.kind == Ship.SOPHON and sh.lock >= 0:
			locked[sh.lock] = true
	var best := GameState.NO_HIT
	var best_d := INF
	for t in ai.known:
		var info: Dictionary = ai.intel.get(t, {})
		if ai.sophon_tried.has(t) or locked.has(info.get("owner", -1)) or not s.cell_exists(t):
			continue
		var d := GameState._nearest(ai.colonies, Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	if best == GameState.NO_HIT:
		return false
	var ship: Ship = null
	for sh in ai.ships:
		if sh.kind == Ship.SOPHON and sh.lock < 0 and (sh.docked or sh.direction == Vector3.ZERO):
			ship = sh
	var built := false
	if ship == null:
		if ai.energy < Balance.COST_SOPHON[0] + Balance.COST_SOPHON_LAUNCH + 4 * RESERVE:
			return false
		ship = s.build(ai, "sophon", _nearest_colony(ai, Vector3(best)))["ship"]
		if ship == null:
			return false
		built = true
	if s.send_sophon(ai, ship.id, best)["error"] == "":
		ai.sophon_tried[best] = true
		return true
	return built


## 被打中过、有两个以上星系时，让母星系躲进黑域。
static func _try_domain(s: GameState, ai: Civ) -> bool:
	if ai.times_hit == 0 or ai.colonies.size() < 2 or not ai.has_tech("domain"):
		return false
	if s.in_black_domain(ai.home) or not ai.pending_domains.is_empty():
		return false
	return s.launch_black_domain(ai, ai.home)["error"] == ""


static func _try_bunker(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("bunker"):
		return false
	for c in ai.colonies:
		if not ai.bunkers.has(c) and s.map.gas.get(c, 0) > 0 and s.build(ai, "bunker", c)["error"] == "":
			return true
	return false


static func _try_each(s: GameState, ai: Civ, kind: String) -> bool:
	if not ai.has_tech(kind):
		return false
	for c in ai.colonies:
		if s.build(ai, kind, c)["error"] == "":
			return true
	return false


## 据点告急且没有常规武器时才考虑降维打击；全图一维后争取奇异点。
static func _try_foil(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("dimension") or not ai.foils.is_empty() or ai.reduce_left > 0:
		return false
	if s.all_linear():
		return ai.line_reduced and s.launch_singularity(ai)["error"] == ""
	# 末日武器只在据点告急或敌方已经展开降维时考虑，优先常规反击。
	if not _flat_near(s, ai) and not (ai.times_hit >= Balance.AI_FOIL_HITS and ai.colonies.size() <= 1):
		return false
	if ai.count(Ship.WARSHIP) > 0 or not ai.grains.is_empty():
		return false
	var target := _nearest_known(s, ai)
	if target == GameState.NO_HIT:
		return false
	var to_line := s.all_flat()
	if to_line and (s.linearized.has(target) or target.z != s.flat_plane):
		return false
	if not to_line and s.flattened.has(target):
		return false
	if not (ai.line_reduced if to_line else ai.reduced):
		var cost := Balance.COST_LINE_FOIL if to_line else Balance.COST_FOIL
		var need := maxi(Balance.AI_FOIL_ENERGY, ai.reduce_cost() + cost)
		if ai.energy < need:
			s.ai_note(ai, "想发%s，要攒到 %dE（降维加发射）" % ["单向著" if to_line else "二向箔", need])
			return false
		return s.start_reduce(ai)["error"] == ""
	var origin := _nearest_colony(ai, Vector3(target))
	return (s.launch_line_foil(ai, target, origin) if to_line else s.launch_foil(ai, target, origin))["error"] == ""


## 派殖民船去最近的、看到过的宜居星系（F4.4：只知道情报里的）；没有停着的殖民船就造一艘。
static func _try_colonize(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("colony"):
		return false
	var best := GameState.NO_HIT
	var best_d := INF
	for t in s.known_habitable(ai):
		if ai.colony_tried.has(t):
			continue
		var d := GameState._nearest(ai.colonies, Vector3(t))
		if d < best_d:
			best_d = d
			best = t
	if best == GameState.NO_HIT:
		return false
	var built := false
	var ship := _idle_colony_ship(ai)
	if ship == null:
		ship = s.build(ai, "colony", _nearest_colony(ai, Vector3(best)))["ship"]
		if ship == null:
			return false
		built = true
	if s.send_colony(ai, ship.id, best)["error"] == "":
		ai.colony_tried[best] = true
		return true
	return built


## 能派的殖民船：停在星系里的，或者上次到了没能殖民、停在外面的（没有时为 null）。
static func _idle_colony_ship(ai: Civ) -> Ship:
	for sh in ai.ships:
		if sh.kind == Ship.COLONY and not sh.dead and (sh.docked or sh.direction == Vector3.ZERO):
			return sh
	return null


## 停在星系里、还没派出的某种单位（没有时为 null）。
static func _docked(ai: Civ, kind: String) -> Ship:
	for sh in ai.ships:
		if sh.kind == kind and sh.docked:
			return sh
	return null


## 保持几个探测器在飞：朝最近被打来的方向、最近看到的东西，或者随机方向（先慢速飞出视野）。
static func _try_probe(s: GameState, ai: Civ) -> bool:
	var flying := 0
	var built := false
	var docked: Ship = null
	for sh in ai.ships:
		if sh.kind == Ship.PROBE:
			if sh.docked:
				docked = sh
			elif not sh.parked:
				flying += 1
	if flying >= PROBES_WANTED + ai.colonies.size() / 3:
		return false
	if docked == null:
		docked = s.build(ai, "probe")["ship"]
		if docked == null:
			return false
		built = true
	var dir := s.random_direction()
	var slow := true
	if not ai.hit_dirs.is_empty() and s.rng.randf() < 0.5:
		dir = ai.hit_dirs[-1]["dir"]
		slow = false
	elif not ai.sightings.is_empty() and s.rng.randf() < 0.5:
		dir = ai.sightings[-1]["pos"] - docked.pos
		slow = false
	return s.dispatch(ai, docked.id, dir, slow)["error"] == "" or built


static func _try_devourer(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("devourer"):
		return false
	for sh in ai.ships:
		if sh.kind == Ship.DEVOURER:
			if sh.docked:
				return s.dispatch(ai, sh.id, s.random_direction())["error"] == ""
			return false
	return s.build(ai, "devourer")["error"] == ""


static func _nearest_colony(ai: Civ, p: Vector3) -> Vector3i:
	var best := ai.home
	var best_d := INF
	for c in ai.colonies:
		var d := Vector3(c).distance_to(p)
		if d < best_d:
			best_d = d
			best = c
	return best


## 只剩星舰的 AI：停在能殖民的星系上就建立星系；否则飞向最近的、看到过的、没去过的宜居星系；
## 一个也不知道时随便挑一个格子飞过去，路上看看（F4.4）。
static func _starship_turn(s: GameState, ai: Civ) -> void:
	var ship := ai.starship()
	if ship == null:
		return
	if ship.direction != Vector3.ZERO and not ship.docked:
		return  # 还在飞
	if s.can_settle(ship.cell()):
		s.settle_starship(ai)
		return
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
	ai.colony_tried[best] = true
	s.move_starship(ai, best)


## 压平的区域再过不超过 AI_REDUCE_ALERT 回合就会压到这个文明的某个据点。
static func _flat_near(s: GameState, ai: Civ) -> bool:
	if not ai.has_tech("dimension"):
		return false
	for c in ai.origins():
		if s.all_flat():
			for zone in s.line_zones:
				if GameState.line_covers(zone["center"], zone["age"] + Balance.AI_REDUCE_ALERT * Balance.FOIL_SPREAD, c):
					return true
		elif s.turns_until_flat(c) <= Balance.AI_REDUCE_ALERT:
			return true
	return false
