extends "res://tests/rules/rule_suite.gd"
## 通过当前连续时钟检查移动、有限指令、慢速出发与路径预览。


func movement_match(at: Vector3i) -> GameState:
	var s:=_two_civs(at)
	s.ensure_cells()
	for civ in s.civs: Assets.ensure(s,civ)
	return s


func built(s: GameState,kind: String) -> Ship:
	var me:=s.human()
	var result:=s.build(me,kind)
	check_eq(result["error"],"","创建真实建造工程："+kind)
	if result["error"]!="": return null
	var id: int=me.pending[-1]["id"]
	for year in 12:
		s.end_turn()
		if me.order_reports.get(id,{}).get("status","")=="completed":
			return Signals.reported_ship(s,me,me.order_reports[id].get("result_ship",-1))
	return null


## 规则：移动
func test_ship_accelerates_then_moves() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var w:=_ship(s,s.human(),Ship.WARSHIP,Vector3.ZERO,Vector3.RIGHT)
	for year in range(1,18):
		WorldTime.advance(s,1.0)
		var expected:=0.005*year*year if year<=15 else 1.125+(year-15)*0.15
		check(absf(w.pos.x-expected)<0.0001,"连续加速 .01，15年达到 .15 后匀速：第%d年"%year)
	check(absf(w.speed-0.15)<0.00001,"速度上限 .15 ly/年")


## 规则：移动，建造
func test_ship_with_target_snaps_onto_it() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["starship"])
	var ss:=built(s,"starship")
	check(ss!=null and ss.docked,"完成6W并收到回报后有停泊星舰")
	if ss==null: return
	check_eq(s.move_starship(me,Vector3i(2,0,0))["error"],"","选目的地移动")
	WorldTime.advance(s,20.0)
	var actual:=me.starship()
	check(actual!=null and actual.pos.x<2.0,"20年内还未到2ly")
	WorldTime.advance(s,1.0)
	check(actual.pos==Vector3(2,0,0) and actual.direction==Vector3.ZERO and actual.speed==0.0,"连续时钟到达后准确停下")


## 规则：调度（派出和行动），移动
func test_starship_target_does_not_reveal_owner() -> void:
	var enemy:=Vector3i(3,0,0)
	var s:=movement_match(enemy)
	var me:=s.human()
	var ss:=_ship(s,me,Ship.STARSHIP,Vector3.ZERO)
	check(s.starship_target_ok(me,enemy),"未回报敌星系可选为目的地")
	check_eq(s.move_starship(me,enemy)["error"],"","下令不查全局所有权")
	WorldTime.advance(s,1.0)
	check(not me.known.has(enemy),"下令不会暴露远方归属")
	WorldTime.advance(s,24.0)
	check(ss.pos.distance_to(Vector3(2,0,0))<0.0001 and not ss.moving(),"船上收到敌星系信号后在1ly外停车")
	check(me.known.has(enemy),"船上观察回传后才更新指挥星图")
	var stock:=[me.energy,me.mineral,me.actions_left,s.rng.state]
	check(s.move_starship(me,enemy)["error"]!="","已知敌方星系不能停")
	check_eq([me.energy,me.mineral,me.actions_left,s.rng.state],stock,"拒绝不收费或消耗RNG")


## 规则：移动
func test_ship_without_target_leaves_map() -> void:
	var s:=movement_match(Vector3i(0,0,8))
	var w:=_ship(s,s.human(),Ship.WARSHIP,Vector3(8.49,5,5),Vector3.RIGHT)
	w.speed=0.15
	WorldTime.advance(s,0.2)
	check(w.dead,"越过实际8.5边界即销毁，不能在图外存续")


## 规则：移动，调度（派出和行动）
func test_turn_ship_costs_and_reverse_resets_speed() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var me:=s.human()
	var w:=_ship(s,me,Ship.WARSHIP,Vector3.ZERO,Vector3.RIGHT)
	w.speed=0.1
	var stock:=[me.energy,me.actions_left]
	check_eq(s.turn_ship(me,w.id,Vector3(1,1,0))["error"],"","原点转向命令合法")
	check_eq([me.energy,me.actions_left],[stock[0]-Balance.COST_TURN,stock[1]-1],"统一转向价格与AP")
	Signals.receive_due(s)
	check(absf(w.speed-0.1)<0.000001,"小角度转向不重置速度")
	check_eq(s.turn_ship(me,w.id,Vector3.LEFT)["error"],"","回执后可反向")
	Signals.receive_due(s)
	check_eq(w.speed,0.0,"反向命令实际抵达时清零速度")


## 规则：调度（派出和行动），移动
func test_probe_slow_start_until_out_of_vision() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["interstellar_probe"])
	var p:=built(s,"nuclear_probe")
	check(p!=null and p.kind==Ship.NUCLEAR_PROBE,"核脉冲探测器为独立型号")
	if p==null: return
	check_eq(s.dispatch(me,p.id,Vector3.RIGHT,true)["error"],"","新型号仍可选择慢速出发")
	Signals.receive_due(s)
	var actual:=me.ship_by_id(p.id)
	check(actual.slow_start,"指令抵达后保存慢速选择")
	WorldTime.advance(s,2.0)
	check(actual.speed<=Balance.SLOW_START_SPEED+1e-6,"自家视野内 .01 上限")
	# 边界夹具跳过约200年慢航；速度、型号和命令均来自以上真实流程。
	actual.pos=Vector3(2.01,0,0)
	WorldTime.advance(s,1.0)
	check(not actual.slow_start and actual.speed>Balance.SLOW_START_SPEED,"离开视野解除单次慢速阶段")
	actual.pos=Vector3(0.5,0,0)
	WorldTime.advance(s,1.0)
	check(actual.speed>Balance.SLOW_START_SPEED,"返回视野不会重新慢速出发")


## 规则：移动
func test_predicted_path_matches_movement() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var me:=s.human()
	var p:=_ship(s,me,Ship.NUCLEAR_PROBE,Vector3.ZERO,Vector3(1,0.3,0))
	Signals.report_ship(s,me,p)
	Signals.receive_due(s)
	var path:=s.predict_path(me,Signals.reported_ship(s,me,p.id),16)
	check_eq(path.size(),17,"路径提供当前点和16年预测")
	for year in range(1,path.size()):
		WorldTime.advance(s,1.0)
		check(p.pos.distance_to(path[year])<0.0001,"无未知环境时预览与实际连续积分相同：%d 实际%s 预测%s"%[year,p.pos,path[year]])
	check_eq(s.predict_path(me,_ship(s,me,Ship.WARSHIP,Vector3.ZERO),6).size(),1,"静止只有当前位置")


## 规则：移动
func test_warp_ship_flies_at_light_speed_outside_vision() -> void:
	var s:=movement_match(Vector3i(8,8,8))
	var me:=s.human()
	var w:=_ship(s,me,Ship.WARSHIP,Vector3(3,0,0),Vector3.RIGHT)
	w.warp=true
	var near:=_ship(s,me,Ship.WARSHIP,Vector3(0.5,0,0),Vector3.UP)
	near.warp=true
	WorldTime.advance(s,0.5)
	check(w.speed>0.4 and w.speed<=0.5+1e-5,"曲率以1ly/年²加速，不瞬移到光速")
	check(absf(near.speed-0.005)<1e-5,"实际所属星系视野内按原推进器")
	WorldTime.advance(s,1.0)
	check(w.speed<=1.0 and not s.deadlines.is_empty(),"视野外受当地光速限制并留下真实航迹")
