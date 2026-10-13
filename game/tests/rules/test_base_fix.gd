extends "res://tests/rules/rule_suite.gd"


## 规则：黑域，光粒，广播和隐藏文明
func test_base_fix_hidden_grain_grazes_domain_like_owned_grain() -> void:
	var stops: Array[Vector3] = []
	for hidden in [false, true]:
		var s := _two_civs(Vector3i(8, 8, 8))
		Hazards.activate(s, Vector3(4, 4, 4))
		s.clock = 3.0
		Hazards.refresh(s)
		var start := Vector3(3.5, 4.97, 4)
		var grain := _ship(s, s.civs[1], Ship.GRAIN, start, Vector3.RIGHT)
		if hidden:
			s.civs[1].ships.erase(grain)
			s.hidden_ships.append(grain)
		check_eq(s.relative_light(start), 1.0, "掠过路径起点在黑域外")
		check_eq(s.relative_light(start + Vector3.RIGHT * 0.99), 1.0, "一年路径终点也在黑域外")
		check(s.relative_light(Vector3(4, 4.97, 4)) < Balance.GRAIN_MIN_LIGHT, "中途真实光速低于失效门槛")
		WorldTime.advance(s, 1.0)
		check(grain.dead, "隐藏与普通光粒都在中途低光速层失效：hidden=%s" % hidden)
		stops.append(grain.pos)
	check(stops[0].distance_to(stops[1]) < 1e-4, "隐藏光粒与普通光粒在同一环境边界停止")


## 规则：黑域，光粒，广播和隐藏文明
func test_base_fix_hidden_grain_crosses_deadline_like_owned_grain() -> void:
	for hidden in [false, true]:
		var s := _two_civs(Vector3i(8, 8, 8))
		var source := _ship(s, s.human(), Ship.WARSHIP, Vector3.ZERO)
		Hazards.leave_deadline(s, Vector3(4, 3, 4), Vector3(4, 5, 4), source)
		var grain := _ship(s, s.civs[1], Ship.GRAIN, Vector3(3.5, 4, 4), Vector3.RIGHT)
		if hidden:
			s.civs[1].ships.erase(grain)
			s.hidden_ships.append(grain)
		WorldTime.advance(s, 1.0)
		check(grain.dead, "隐藏与普通光粒穿过窄死线都失效：hidden=%s" % hidden)
		check(grain.pos.x < 4.0, "不能穿过死线后在外面继续飞行")


## 规则：视野，情报传回，交战
func test_base_fix_damage_after_entry_is_not_backdated() -> void:
	var received: Array = []
	for ai in [false, true]:
		var s := _two_civs(Vector3i(8, 8, 8))
		s.human().is_ai = ai # 连续结算不调用 AI 行动；两种控制方式用完全相同的物理夹具。
		var target := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(2.025, 0, 0), Vector3.LEFT)
		target.speed = target.max_speed
		target.modules = ["shield"]
		target.weapons = ["railgun"] # 避免无武器战舰的自毁接触，与本测试无关。
		var old_hp := target.max_hp()
		s.projectiles.append({"id": s.next_id(), "owner": 0, "source": -1, "weapon": "torpedo",
			"pos": Vector3(2.145, 0, 0), "direction": Vector3.LEFT, "remaining": 1.0,
			"distance": 0.0, "dead": false})
		WorldTime.advance(s, 1.0)
		check(target.damage > 0 and not target.dead, "先进入视野，再受一次非致命命中")
		var hit_time := target.last_hit
		check(hit_time > 0.2 and hit_time < 1.0, "实际命中时刻晚于约0.167年的入视野时刻")
		var early := 0
		var damaged := 0
		for message in s.messages:
			var bodies: Array = [message["body"]]
			bodies.append_array(message.get("more", []))
			for body in bodies:
				if body.get("type") != "entity" or body["data"]["id"] != target.id:
					continue
				if body["t_observed"] < hit_time - Balance.TIME_EPSILON:
					early += 1
					check_eq(body["data"]["hp"], old_hp, "命中前的历史观测保留当时完整血量")
				if body["data"]["hp"] < old_hp:
					damaged += 1
					check(body["t_observed"] >= hit_time - Balance.TIME_EPSILON, "损伤观测时间不得早于实际命中")
					check(message["sent"] >= hit_time - Balance.TIME_EPSILON, "损伤光信号不得在命中前发出")
					check(message["eta"] >= hit_time + 1.90, "损伤还需沿实际光程传播到母星")
		check(early > 0 and damaged > 0, "同时保留入视野历史与命中后的新报告")
		WorldTime.advance(s, 1.3) # 总时刻2.3年，首次进入视野的完整血量已能到，命中后损伤还到不了。
		var sightings := s.human().sightings.filter(func(x): return x["id"] == target.id)
		check_eq(sightings.size(), 1, "早期观测已到控制点")
		if not sightings.is_empty():
			check_eq(sightings[0]["hp"], old_hp, "光程足够以前，玩家与AI均不能获知损伤")
		WorldTime.advance(s, 0.6)
		sightings = s.human().sightings.filter(func(x): return x["id"] == target.id)
		check(not sightings.is_empty() and sightings[0]["hp"] < old_hp, "损伤光信号到达后正常更新")
		received.append(sightings)
	check_eq(received[0], received[1], "玩家和AI获得相同的历史、血量和送达时刻")
