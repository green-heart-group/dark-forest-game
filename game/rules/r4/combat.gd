class_name R4Combat
extends RefCounted
## 本地自动战斗、预留弹药和同一时刻命中批次。不可使用远方未收到的文明情报开火。
const PRIORITY := ["104","105","012","011"]

static func eligible(weapon: String, target: Dictionary) -> bool:
	if weapon=="104": return target.kind in R4Config.PERSONNEL_TARGETS
	if target.kind in ["dimensional_weapon","domain_payload"]: return true
	if target.kind in R4Config.PERSONNEL_TARGETS: return true
	if weapon=="012": return target.kind in ["miner_basic","miner_advanced"]
	if weapon=="105": return target.kind in ["miner_basic","miner_advanced","probe_basic","probe_nuclear"]
	if weapon=="107": return target.kind in R4Config.MOBILE
	return false

static func reserve(s) -> void:
	var ships: Array = s.entities.values()
	ships.sort_custom(func(a,b): return a.id<b.id)
	for ship in ships:
		if not ship.alive or not ship.online or not s.civs[ship.owner].alive or ship.kind!="battleship": continue
		ship["armed_weapon"]=""
		ship["shot_reservation"]=""
		for key in ship.occupation.keys():
			if key is String: ship.occupation.erase(key)
		if ship.modules.any(func(m):return m in PRIORITY):
			for target in ship.get("tactical",{}).values():
				if target.kind not in ["home","colony"]: continue
				var p: Dictionary = s.config.physics.occupation
				if ship.pos.distance_to(target.pos)>p.range+ship.speed: continue
				s.civs[ship.owner].ledger.reserve_shot("occupation:%d:%d:%d"%[ship.id,target.id,s.round_index],R4Ledger.amount(p.M,p.E))
		var choice := ""
		var best := -INF
		for weapon in PRIORITY:
			if not ship.modules.has(weapon): continue
			var params: Dictionary = s.config.physics.weapons[weapon]
			var score: float = params.range*0.01
			for target in ship.get("tactical",{}).values():
				if not eligible(weapon,target) or ship.pos.distance_to(target.pos)>params.range: continue
				score=maxf(score,100.0 if weapon=="104" else (50.0 if params.damage>=target.get("hp",1)-target.get("damage",0) else 10.0))
			var cost: Dictionary = s.config.economy.actions.weapon_round_costs[weapon]
			if score>best and s.civs[ship.owner].ledger.can_pay(R4Ledger.amount(cost.M,cost.E)):
				choice=weapon
				best=score
		if choice=="": continue
		var cost: Dictionary = s.config.economy.actions.weapon_round_costs[choice]
		var reservation := "ammo:%d:%d"%[ship.id,s.round_index]
		if s.civs[ship.owner].ledger.reserve_shot(reservation,R4Ledger.amount(cost.M,cost.E)):
			ship.armed_weapon=choice
			ship.shot_reservation=reservation

static func fire_available(s) -> void:
	var shooters: Array = s.entities.values()
	shooters.sort_custom(func(a,b): return a.id<b.id)
	for ship in shooters:
		if not ship.alive or not ship.online or not s.civs[ship.owner].alive or ship.kind!="battleship" or ship.fired_round==s.round_index: continue
		var weapon: String = ship.get("armed_weapon","")
		if weapon=="": continue
		var params: Dictionary = s.config.physics.weapons[weapon]
		var targets: Array = ship.get("tactical",{}).values()
		targets.sort_custom(func(a,b):
			var da: float = ship.pos.distance_squared_to(a.pos)
			var db: float = ship.pos.distance_squared_to(b.pos)
			return a.id<b.id if is_equal_approx(da,db) else da<db)
		for target in targets:
			if not target.alive or not eligible(weapon,target): continue
			if ship.pos.distance_to(target.pos)>params.range: continue
			var cost: Dictionary = s.config.economy.actions.weapon_round_costs[weapon]
			var required := R4Ledger.amount(cost.M,cost.E)
			var ledger = s.civs[ship.owner].ledger
			var held: Vector2i = ledger.shots.get(ship.shot_reservation,Vector2i.ZERO)
			var missing := required-held
			if not ledger.can_pay(missing): continue
			if missing!=Vector2i.ZERO: ledger.debit(missing,"migration_ammunition_topup")
			ledger.fire_shot(ship.shot_reservation)
			ship.fired_round=s.round_index
			ship.last_combat=s.now
			ship.repair_time=0.0
			var velocity: Vector3 = target.get("direction",Vector3.ZERO)*target.get("speed",0.0)
			var local_speed: float = s.space.effective_c(ship.pos,s.now)*params.c_fraction
			var intercept_time: float = ship.pos.distance_to(target.pos)/maxf(local_speed,1e-9)
			var aim: Vector3 = target.pos+velocity*(s.now-target.t_observed+intercept_time)
			spawn_shot(s,ship,weapon,aim,target.id)
			break

static func spawn_shot(s, source: Dictionary, weapon: String, aim: Vector3, target_id := -1) -> Dictionary:
	var params: Dictionary = s.config.physics.weapons[weapon]
	var direction: Vector3 = (aim-source.pos).normalized()
	if direction==Vector3.ZERO: direction=Vector3.RIGHT
	var shot := {"id":s.next_id(source.owner),"owner":source.owner,"source":source.id,"kind":"weapon","weapon":weapon,
		"pos":source.pos,"direction":direction,"target":aim,"target_id":target_id,"remaining":params.range,"traveled":0.0,
		"damage":params.damage,"damage_kind":params.kind,"c_fraction":params.c_fraction,"speed":0.0,
		"born":s.now,"earliest":s.now+s.config.physics.event_epsilon,"alive":true,"consumed":false}
	s.projectiles.append(shot)
	s.first_use(source.owner,weapon,"weapon_fired",source.id)
	s.log_event("weapon_fired",source.owner,{"weapon":weapon,"shot":shot.id,"source":source.id,"target_observed":target_id})
	return shot

static func defense_roll(seed_value: int, shot_id: int, target_id: int, channel: String) -> float:
	var key := "%d:%d:%d:%s"%[seed_value,shot_id,target_id,channel]
	return float(key.sha256_text().substr(0,8).hex_to_int())/4294967296.0

static func apply_hits(s, hits: Array) -> void:
	# 先采样整个批次的生存状态并计算全部命中，再提交死亡；不在循环中宣布赢家。
	var damage := {}
	var crew_kills := {}
	var self_kills := {}
	hits.sort_custom(func(a,b): return a.shot<b.shot)
	for hit in hits:
		var target: Dictionary = s.entities.get(hit.target,{})
		if target.is_empty() or not target.alive: continue
		if hit.get("self_destroy",-1)>=0: self_kills[hit.self_destroy]=true
		var dealt: float = hit.damage
		if hit.kind=="personnel":
			if target.kind not in R4Config.PERSONNEL_TARGETS: continue
			if not crew_kills.has(target.id): crew_kills[target.id]=hit
			dealt=target.hp
		elif hit.kind=="physical" and target.modules.has("013"):
			if defense_roll(s.seed_value,hit.shot,target.id,"armor")<s.config.physics.defense_chance:
				dealt=maxf(0.0,dealt-s.config.physics.armor_reduction)
				s.first_use(target.owner,"013","damage_prevented",target.id)
		elif hit.kind=="energy" and target.modules.has("106"):
			if defense_roll(s.seed_value,hit.shot,target.id,"field")<s.config.physics.defense_chance:
				dealt=0.0
				s.first_use(target.owner,"106","damage_prevented",target.id)
		damage[target.id]=damage.get(target.id,0.0)+dealt
		target.last_combat=s.now
		target.repair_time=0.0
		s.log_event("weapon_hit",hit.owner,{"shot":hit.shot,"target":target.id,"weapon":hit.get("weapon",""),"damage":dealt,"damage_kind":hit.kind})
		if hit.owner>=0 and hit.get("weapon","")!="": s.first_use(hit.owner,hit.weapon,"hit",target.id)
	for id in damage:
		s.entities[id].damage+=damage[id]
	var dead: Array = []
	for id in damage:
		if s.entities[id].damage>=s.entities[id].hp or crew_kills.has(id): dead.append(id)
	for id in self_kills:
		if not dead.has(id): dead.append(id)
	dead.sort()
	for id in dead:
		var cause := "personnel_104" if crew_kills.has(id) else "weapon_damage"
		s.destroy_entity(id,cause,crew_kills[id].owner if crew_kills.has(id) else -1)
	# 同批战利品只能在所有攻击已确定后入账，不能资助这批的另一发。
	for id in crew_kills:
		var hit: Dictionary = crew_kills[id]
		var target: Dictionary = s.entities[id]
		if hit.owner!=target.owner:
			var recovered: Vector2i = s.civs[hit.owner].ledger.salvage(id,target.paid_basis,true)
			s.log_event("salvage_104",hit.owner,{"target":id,"actual_paid_basis":recovered})
