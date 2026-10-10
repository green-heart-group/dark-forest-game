extends "res://tests/rules/rule_suite.gd"
## AI 原优先表的回归；钱、工程、命令和已收情报使用与玩家相同入口。


func _ai_game() -> GameState:
	var s:=_two_civs(Vector3i(8,8,8))
	var ai:=s.civs[1]
	ai.taste={}
	ai.discovered=true
	ai.energy=1000
	ai.mineral=1000
	for id in Tech.ALL:
		if Tech.ALL[id]["initial"]: ai.techs[id]=true
	s.map.rocky[ai.home]=1
	Knowledge.report_site(s,ai,ai.home)
	Signals.receive_due(s)
	return s


func _builds(s: GameState,civ: Civ) -> Array:
	return s.history.filter(func(h):return h["civ"]==s.civs.find(civ) and h["name"]=="build").map(func(h):return h["args"][0])


func _research_choices(ai: Civ, choices: Array) -> void:
	_open_tiers(ai,3)
	for id in Tech.ALL:
		if choices.has(id): ai.techs.erase(id)
		else: ai.techs[id]=true


## 规则：AI 怎么行动
func test_ai_research_picks_highest_score_and_keeps_reserve() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	_research_choices(ai,["dyson","warship"])
	ai.energy=Tech.cost("dyson")[0]+AI.RESERVE-1
	AI._research(s,ai)
	check(ai.research_project.is_empty(),"最高分戴森研究不能留够6E时先储蓄")
	ai.energy=Tech.cost("dyson")[0]+AI.RESERVE
	AI._research(s,ai)
	check_eq(ai.research_project.get("kind",""),"dyson","选择最高分合法科技并预付")
	check(not ai.has_tech("dyson") and ai.energy==AI.RESERVE,"研究尚未完成，恰保留6E")
	var history:=s.history.size()
	AI._research(s,ai)
	check_eq(s.history.size(),history,"同一研究队列不能一年连升3项")
	_turns(s,5)
	check(ai.has_tech("dyson"),"5W正式完工后才取得科技")
	ai.energy=1000
	AI._research(s,ai)
	check_eq(ai.research_project.get("kind",""),"warship","之后才能提交下一优先项")


## 规则：AI 怎么行动
func test_ai_research_favours_bunker_after_hit() -> void:
	for hit in [0,1]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		_research_choices(ai,["warship","bunker"])
		ai.times_hit=hit
		AI._research(s,ai)
		check_eq(ai.research_project.get("kind",""),"warship" if hit==0 else "bunker","遇袭反馈增加掩体优先分，仍为付费研究工程")


## 规则：AI 怎么行动
func test_ai_builds_in_order_when_nobody_known() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	AI.take_turn(s,ai)
	check_eq(_builds(s,ai),["miner","warning"],"先保障真实首矿，第二槽沿原优先顺序建预警")
	check(ai.ships.is_empty(),"下单不瞬间生成并派出探测器")
	_turns(s,2)
	AI.take_turn(s,ai)
	check_eq(_builds(s,ai),["miner","warning","miner","probe"],"两槽释放后沿原顺序补矿并探索")
	var count:=ai.pending.size()
	AI.take_turn(s,ai)
	check_eq(ai.pending.size(),count,"未完工程不能重复下单")


func _probe_direction(s: GameState,ai: Civ) -> Vector3:
	# 已注销的旧探测器与旧遥测一同移除；每次是独立待命舰夹具。
	ai.ships.clear()
	ai.telemetry.clear()
	ai.command_pending.clear()
	ai.actions_left=2
	var probe:=_ship(s,ai,Ship.PROBE,Vector3(ai.home))
	if not AI._try_probe(s,ai): return Vector3.ZERO
	return probe.direction


func _probe_reach(s: GameState,ai: Civ,dir: Vector3) -> float:
	return Geometry.distance_to_edge(Vector3(ai.home),dir,s.map.bounds())-s.sphere_radius(ai,Balance.VISION_HOME)


## 规则：AI 怎么行动
func test_probe_from_corner_heads_into_map() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	s.rng.seed=8129
	for i in 20:
		var dir:=_probe_direction(s,ai)
		check(dir!=Vector3.ZERO,"正式派出待命探测器")
		check(_probe_reach(s,ai,dir)>=AI.PROBE_MIN_REACH,"原随机方向算法保持向图内探索")


## 规则：AI 怎么行动
func test_probe_ignores_hit_direction_leading_off_map() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	s.rng.seed=8129
	var outward:=Vector3.ONE.normalized()
	ai.hit_dirs.append({"at":ai.home,"dir":outward,"turn":0})
	for i in 20:
		check(_probe_direction(s,ai).dot(outward)<0.99,"图外来袭方向不能令探测器立刻出界")
	var inward:=-outward
	ai.hit_dirs.append({"at":ai.home,"dir":inward,"turn":0})
	var used:=false
	for i in 20: used=_probe_direction(s,ai).dot(inward)>0.99 or used
	check(used,"指向图内的已收到来袭方向仍被采用")


## 规则：AI 怎么行动
func test_ai_protects_itself_after_hit() -> void:
	for hit in [0,1]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		_give(ai,["domain","bunker","starship"])
		var colony:=Vector3i(8,8,6)
		_set_star(s,colony,StarMap.Star.SINGLE)
		s.map.gas[colony]=1
		ai.colonies.append(colony)
		Assets.ensure(s,ai)
		Knowledge.report_site(s,ai,colony)
		Signals.advance(s,2.0)
		s.clock=2.0
		Signals.receive_due(s)
		ai.times_hit=hit
		# take_turn中的防御分支单独调用，避免无关研究/首矿抢占固定2AP。
		var domain:=AI._try_domain(s,ai)
		var bunker:=AI._try_bunker(s,ai) if hit>0 else false
		check(domain==(hit>0) and bunker==(hit>0),"有遇袭与已收殖民地遥测才走防御分支")
		if hit>0:
			check(s.payloads.size()==1 and s.payloads[0]["kind"]=="domain","黑域成为有限投送载荷")
			check(ai.pending.any(func(p):return p["kind"]=="bunker" and p["at"]==colony),"远端掩体合法下单并等待命令")
			s.start_turn(ai)
			ai.pending.clear() # 本测试另摆空闲母星队列；不改变远端生产事实。
			var done:={"miner":true,"probe":true,"colony":true,"dyson":true}
			ai.warnings[ai.home]=0
			Assets.ensure(s,ai)
			AI._act(s,ai,done)
			check(_builds(s,ai).has("starship"),"受袭后原星舰避险建造分支仍可受理")


## 规则：AI 怎么行动
func test_ai_sends_warships_at_known_target() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	_give(ai,["warship","beam"])
	ai.known[Vector3i.ZERO]=1
	check(AI._try_warship(s,ai,Vector3i.ZERO),"已知目标触发选装战舰工程")
	check(ai.ships.is_empty() and ai.pending.size()==1,"造船等待工时")
	_turns(s,4)
	check(AI._try_warship(s,ai,Vector3i.ZERO),"完工并收到舰船信息后派出")
	var ship:Ship=ai.ships[0]
	check(not ship.docked and ship.direction.is_equal_approx(-Vector3.ONE.normalized()),"派向已知敌人")
	check(AI._try_warship(s,ai,Vector3i.ZERO),"允许第二艘订单")
	_turns(s,4)
	check(AI._try_warship(s,ai,Vector3i.ZERO),"第二艘完工派出")
	s.start_turn(ai)
	check(not AI._try_warship(s,ai,Vector3i.ZERO),"原AI偏好最多两艘在飞，待命令也计数")


## 规则：AI 怎么行动
func test_ai_counterattacks_along_hit_direction() -> void:
	for age in [0,21]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		ai.techs["warship"]=true
		s.turn=30
		ai.hit_dirs.append({"at":ai.home,"dir":Vector3.LEFT,"turn":s.turn-age})
		var ship:=_ship(s,ai,Ship.WARSHIP,Vector3(ai.home))
		var acted:=AI._try_warship_hit_dir(s,ai)
		check(acted==(age==0),"只使用20回合内的来袭历史")
		check(ship.direction==(Vector3.LEFT if age==0 else Vector3.ZERO),"正式本地命令沿收到的来袭方向")


## 规则：AI 怎么行动
func test_ai_turns_warship_toward_received_target() -> void:
	for degrees in [90.0,10.0]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		ai.known[Vector3i.ZERO]=1
		var pos:=Vector3(6,6,4)
		var want:=-pos.normalized()
		var dir:=want.rotated(want.cross(Vector3.FORWARD).normalized(),deg_to_rad(degrees))
		var ship:=_ship(s,ai,Ship.WARSHIP,pos,dir)
		Signals.report_ship(s,ai,ship)
		Signals.advance(s,5.0)
		s.clock=5.0
		Signals.receive_due(s)
		var result:=AI._try_turn_warships(s,ai)
		check(result==(degrees>25),"只针对已收遥测中偏离超过25度的方向下令")
		check(ship.direction.is_equal_approx(dir),"远程转向不能在决策时改真实航向")
		if result:
			WorldTime.advance(s,5.5)
			check(ship.direction.is_equal_approx(want),"命令传播后执行所发方向，不偷取新敌情")


## 规则：AI 怎么行动
func test_ai_broadcasts_far_targets_once() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	ai.broadcasters[ai.home]=true
	Assets.ensure(s,ai)
	var near:=Vector3i(8,8,5)
	ai.known[Vector3i.ZERO]=1
	ai.known[near]=1
	check(AI._try_broadcast(s,ai),"广播远方已知目标")
	check(ai.broadcasted.has(Vector3i.ZERO) and not ai.broadcasted.has(near),"近于4ly的已知目标不广播")
	check(not AI._try_broadcast(s,ai) and s.broadcasts.size()==1,"同坐标只发送一次")


## 规则：AI 怎么行动
func test_ai_saves_up_then_reduces_then_launches_foil() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	ai.techs["dimension"]=true
	ai.times_hit=2
	ai.known[Vector3i.ZERO]=1
	ai.energy=Balance.AI_FOIL_ENERGY-1
	check(not AI._try_foil(s,ai) and ai.conversions.is_empty(),"危急但低于储备阈值时不先浪费迁维资源")
	ai.energy=1000
	check(AI._try_foil(s,ai) and not ai.pending.is_empty(),"资源充足先准备迁维")
	check(ai.dimension_ammo==0 and s.payloads.is_empty(),"准备不凭空获得武器")
	_turns(s,5)
	check(AI._try_foil(s,ai) and ai.reduced,"收到ready回执后才执行")
	s.start_turn(ai)
	check(AI._try_foil(s,ai) and Knowledge.pending(ai,"dimension_weapon")==1,"下一步付费建维度弹药")
	_turns(s,8)
	check(AI._try_foil(s,ai) and s.payloads.size()==1,"弹药实际完工后发射")
	check_eq(s.payloads[0]["target"],Vector3.ZERO,"目标是已收到的敌方坐标")
	s.start_turn(ai)
	check(not AI._try_foil(s,ai),"在途载荷不重复发射")


## 规则：AI 怎么行动
func test_ai_sends_sophon_when_energy_allows() -> void:
	var need:int=Balance.COST_SOPHON[0]+4+4*AI.RESERVE
	for energy in [need-1,need]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		ai.techs["sophon"]=true
		ai.known[Vector3i.ZERO]=1
		ai.energy=energy
		var acted:=AI._try_sophon(s,ai)
		check(acted==(energy==need),"按舰体及4E派出费用和4份储备判断")
		if acted:
			check(ai.ships.is_empty(),"智子也需要建造工时")
			_turns(s,4)
			check(AI._try_sophon(s,ai) and ai.sophon_tried.has(Vector3i.ZERO),"完工后派出并记录目标")
			s.start_turn(ai)
			check(not AI._try_sophon(s,ai),"同一敌星系不重复派智子")


## 规则：AI 怎么行动
func test_ai_researches_after_discovery() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	_research_choices(ai,["colony"])
	ai.tier1_turn=-1
	AI._research(s,ai)
	check(ai.research_project.is_empty(),"未开放I级权限不能直接研究109")
	_open_tiers(ai,1)
	AI._research(s,ai)
	check_eq(ai.research_project.get("kind",""),"colony","正式权限开放后选择扩张科技")
	_turns(s,3)
	check(ai.has_tech("colony"),"完成后才成为实际科技")


## 规则：AI 怎么行动
func test_ai_launches_grain_at_known_target() -> void:
	var s:=_two_civs(Vector3i(5,0,0))
	var ai:=s.civs[1]
	ai.techs["grain"]=true
	ai.grains[ai.home]=true
	ai.known[Vector3i.ZERO]=1
	check(AI._try_grain(s,ai,Vector3i.ZERO),"通过同一正式入口使用已有弹药")
	check(ai.count(Ship.GRAIN)==1 and ai.aimed.has(Vector3i.ZERO),"记录光粒与避免短期重复的时间戳")
	_turns(s,5)
	check(not s.human().alive,".99c光粒经过真实航程和.25ly碰撞后命中")


## 规则：AI 怎么行动
func test_ai_colonizes() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	_give(ai,["interstellar_travel","colony"])
	var at:=Vector3i(8,8,7)
	_set_habitable(s,at,StarMap.Star.SINGLE)
	_set_habitable(s,Vector3i(8,0,8),StarMap.Star.SINGLE)
	ai.intel[at]=s.snapshot(at)
	check(AI._try_colonize(s,ai),"只有已收到的宜居目标可触发订单")
	_turns(s,3)
	check(AI._try_colonize(s,ai),"正式完工后派出")
	check(not ai.colony_tried.has(Vector3i(8,0,8)),"未知适宜星系不进入目标")
	_turns(s,22)
	check(AI._try_colonize(s,ai),"等待抵达遥测后提交109落地")
	_turns(s,6)
	check(ai.owns(at),"有限命令传播和4W后建立新锚点")


## 规则：AI 怎么行动
func test_ai_uses_antimatter_after_observation() -> void:
	var s:=_two_civs(Vector3i(5,0,0))
	var ai:=s.civs[1]
	ai.antimatter=1
	var war:=_ship(s,s.human(),Ship.WARSHIP,Vector3(4.2,0,0))
	AI._act(s,ai,{})
	check(not war.dead and ai.antimatter==1,"未收到接近观测不因引擎看到敌舰而发射")
	WorldTime.advance(s,0.9)
	AI._act(s,ai,{})
	check(ai.antimatter==0 and not war.dead,"观测到达才发射，仍有弹丸航程")
	WorldTime.advance(s,0.9)
	check(war.dead,"有限传播后真实命中")


## 规则：AI 怎么行动
func test_ai_reduces_when_received_front_near() -> void:
	for busy in [false,true]:
		var s:=_ai_game()
		var ai:=s.civs[1]
		ai.techs["dimension"]=true
		# 此用例检查已发展文明的迁维优先级；真实完成首艘矿船，避免开局保障矿源抢占宿主。
		check_eq(s.build(ai,"miner")["error"],"","先建立真实矿源")
		WorldTime.advance(s,2.0)
		s.start_turn(ai)
		var near:=ai.home-Vector3i.RIGHT
		ai.intel[near]={"cell_dim":2,"t_observed":s.clock}
		if busy:
			check_eq(s.build(ai,"miner")["error"],"","先占用同一宿主队列")
			check_eq(s.build(ai,"probe")["error"],"","再占满母星第二槽")
			ai.actions_left=2
		var ap:=ai.actions_left
		AI.take_turn(s,ai)
		check(not ai.conversions.is_empty() if not busy else ai.conversions.is_empty(),"收到近处转换观测后按宿主可用性准备")
		if busy: check(ai.actions_left<ap,"迁维宿主忙也可做其他合法操作")


## 规则：AI 怎么行动
func test_long_ai_game_runs() -> void:
	var s:=GameState.new_game(3,Balance.AI_COUNT,true)
	for i in 200:
		if s.is_over(): break
		s.end_turn()
		trace_long(s,"ai200")
	check(s.turn>20,"保留200回合AI集成回归，不替代六局400验收")
	var techs:=0
	for civ in s.civs: techs+=civ.techs.size()
	check(techs>s.civs.size()*6,"AI在自然开局中确实完成付费科技")


## 规则：AI 怎么行动
func test_ai_only_knows_what_it_saw() -> void:
	var s:=_ai_game()
	var ai:=s.civs[1]
	_give(ai,["warship","grain","dimension"])
	for i in 5:
		ai.actions_left=2
		AI.take_turn(s,ai)
		WorldTime.advance(s,0.1)
	check(not ai.known.has(Vector3i.ZERO) and not ai.intel.has(Vector3i.ZERO),"未观测的远方敌星系仍未知")
	check(s.payloads.is_empty() and ai.ships.all(func(ship):return ship.kind!=Ship.GRAIN),"没有已知敌人坐标不发战略攻击")
	ai.broadcasters[ai.home]=true
	Assets.ensure(s,ai)
	Information.broadcast(s,s.human(),Vector3(8,8,7),Vector3i.ZERO,GameState.NO_HIT)
	WorldTime.advance(s,0.9)
	check(not ai.known.has(Vector3i.ZERO),"广播前沿还未到AI的接收器")
	WorldTime.advance(s,0.2)
	check(ai.known.has(Vector3i.ZERO),"实际收到广播后才知道所广播的历史坐标")


## 规则：AI 怎么行动
func test_ai_foil_is_last_resort() -> void:
	var s:=_collapse_match()
	var ai:=s.civs[1]
	ai.dimension_ammo=1
	ai.known[s.human().home]=1
	check(not AI._try_foil(s,ai),"有资源与目标不等于常规使用末日武器")
	ai.times_hit=2
	check(AI._try_foil(s,ai) and s.payloads.size()==1,"仅在原策略的最后手段条件满足后发射")
	s.start_turn(ai)
	check(not AI._try_foil(s,ai),"在途武器阻止重复发射")
