extends "res://tests/rules/rule_suite.gd"
## 原交战回归迁移：调用正式连续时钟，武器使用本地收到的观测。


## 规则：交战
func test_warships_destroy_each_other() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var a:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0),Vector3.RIGHT)
	var b:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.1,0,0),Vector3.LEFT)
	a.speed=0.15
	b.speed=0.15
	WorldTime.advance(s,0.29)
	check(not a.dead and not b.dead,".01ly接触前不发生旧范围自毁")
	WorldTime.advance(s,0.03)
	check(a.dead and b.dead,"连续轨迹首次接触时同批自毁")


## 规则：交战，建造
func test_warships_carry_only_selected_researched_weapons() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["warship"])
	var plain:=s.build_cost(me,"warship")
	_give(me,["beam","torpedo"])
	check_eq(s.build_cost(me,"warship"),plain,"研究不自动提高裸舰造价")
	var armed:=s.build_cost(me,"warship",["beam","torpedo"])
	check_eq(armed,[plain[0]+Balance.MODULE_COST.beam[0]+Balance.MODULE_COST.torpedo[0],plain[1]+Balance.MODULE_COST.beam[1]+Balance.MODULE_COST.torpedo[1]],"选装清单才增加造价")
	var result:=s.build(me,"warship",me.home,["beam","torpedo"])
	check_eq(result["error"],"","提交选装工程")
	check(me.ships.is_empty(),"提交时没有瞬间造好的舰体")
	_turns(s,6)
	var ships:=me.ships.filter(func(sh):return sh.kind==Ship.WARSHIP)
	check_eq(ships.size(),1,"正式工程完工生成一艘")
	if not ships.is_empty():
		check(ships[0].weapons==["beam","torpedo"] and ships[0].cost[0]==armed[0] and ships[0].cost[1]==armed[1],"武器和已付回收基数符合订单")


## 规则：交战
func test_beam_destroys_warship_after_local_observation_and_flight() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var mine:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0))
	mine.weapons=["beam"]
	var victim:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.4,0,0))
	WorldTime.advance(s,0.7)
	check(not victim.dead,".4ly观测加弹丸航行尚未完成")
	WorldTime.advance(s,0.2)
	check(victim.dead and not mine.dead,"2点能量伤害击毁2HP裸舰")
	check_eq(mine.fired_turn,s.turn,"本年只发射一个通道")


## 规则：交战
func test_torpedo_three_damage_hits_after_flight() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var mine:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0))
	mine.weapons=["torpedo"]
	var victim:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.8,0,0))
	WorldTime.advance(s,3.2)
	check(not victim.dead,".8ly观测与.3c鱼雷航程尚未结束")
	WorldTime.advance(s,0.4)
	check(victim.dead and victim.damage==3,"一次3点物理伤害足以摧毁裸舰，取消旧固定两发判定")


## 规则：交战
func test_hbomb_special_priority_salvages_once() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var mine:=_ship(s,me,Ship.WARSHIP,Vector3(3,0,0))
	mine.weapons=["hbomb","beam","torpedo"]
	mine.weapon_policy="special"
	var victim:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.1,0,0))
	victim.cost=[12.0,10.0]
	var before:=[me.energy,me.mineral]
	WorldTime.advance(s,0.25)
	check(victim.dead and victim.salvage_claimed and not mine.dead,"特殊近战优先且只回收一次")
	# 此舰.25年固定维护.25E/.125M；命中一次6E，收到实付12E10M。
	check_eq([me.energy,me.mineral],[before[0]+12.0-6.0-0.25,before[1]+10.0-0.125],"回收实付账并正常支付射击与维护")
	WorldTime.advance(s,0.1)
	check_eq(me.ledger.filter(func(item):return item["kind"]=="salvage").size(),1,"残骸不再重复回收")


## 规则：交战
func test_armed_warships_fire_at_the_same_time() -> void:
	for reverse in [false,true]:
		var s:=_two_civs(Vector3i(8,8,8))
		var a:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0))
		var b:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.4,0,0))
		a.weapons=["beam"]
		b.weapons=["beam"]
		if reverse: s.civs.reverse()
		WorldTime.advance(s,0.9)
		check(a.dead and b.dead,"对称局部观测和同刻束流造成双方死亡，和遍历顺序无关")


## 规则：交战
func test_weapon_needs_start_of_round_ammo_money() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.energy=0
	me.techs["fission"]=true
	var mine:=_ship(s,me,Ship.WARSHIP,Vector3(3,0,0))
	mine.weapons=["beam"]
	var victim:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(3.4,0,0))
	WorldTime.advance(s,1.0)
	check(not victim.dead and mine.fired_turn<0,"年中收入不能抵押成本补发年初未预留弹药")


## 规则：交战，反物质
func test_warship_suppression_is_interruptible_by_antimatter() -> void:
	var s:=_two_civs(Vector3i(1,0,0))
	var ai:=s.civs[1]
	ai.antimatter=1
	var mine:=_ship(s,s.human(),Ship.WARSHIP,Vector3(0.9,0,0))
	mine.weapons=["beam"]
	WorldTime.advance(s,0.2)
	check(mine.suppression.get("progress",0)>0 and ai.alive,"库存炸弹本身不免疫压制")
	check_eq(s.use_antimatter(ai)["error"],"","观测后下令发射炸弹")
	check(not mine.dead and ai.antimatter==0,"发射消耗库存但尚未命中")
	WorldTime.advance(s,0.2)
	check(mine.dead and ai.alive,"有限飞行后的4伤害中断压制")
	var replacement:=_ship(s,s.human(),Ship.WARSHIP,Vector3(0.9,0,0))
	replacement.weapons=["beam"]
	WorldTime.advance(s,2.9)
	check(ai.alive,"替代舰不能继承前舰的压制进度")
	WorldTime.advance(s,0.1)
	check(not ai.alive and s.winner=="你" and not replacement.dead,"新舰完整3年压制才清除星系")


## 规则：交战
func test_colony_ship_needs_a_legal_weapon_hit() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var naked:=_ship(s,s.human(),Ship.WARSHIP,Vector3(3,0,0))
	var transport:=_ship(s,s.civs[1],Ship.COLONY,Vector3(3.005,0,0))
	WorldTime.advance(s,0.1)
	check(not naked.dead and not transport.dead,"裸舰自毁目标集合不包括运输船")
	naked.weapons=["beam"]
	WorldTime.advance(s,0.1)
	check(transport.dead and not naked.dead,"有合法束流命中可击毁1HP运输船")
