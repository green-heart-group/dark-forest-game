extends "res://tests/rules/rule_suite.gd"
## 智子保留建造、指定目的地、停留与改派入口；V0.1 取消科研封锁和全境透视。


func build_sophon(s: GameState,civ: Civ) -> Ship:
	_give(civ,["sophon"])
	var result:=s.build(civ,"sophon",civ.home)
	check_eq(result["error"],"","正式提交4W智子工程")
	if result["error"]!="": return null
	var id: int=civ.pending[-1]["id"]
	_turns(s,4)
	check_eq(civ.order_reports.get(id,{}).get("status",""),"completed","工程完工且回执已收到")
	return civ.ship_by_id(civ.order_reports.get(id,{}).get("result_ship",-1))


## 规则：智子，情报传回
func test_sophon_observes_enemy_home_without_lock() -> void:
	var s:=_two_civs(Vector3i(3,0,0))
	var me:=s.human()
	var ai:=s.civs[1]
	var sophon:=build_sophon(s,me)
	if sophon==null: return
	check_eq(s.send_sophon(me,sophon.id,ai.home)["error"],"","按旧目的地操作派出智子")
	_turns(s,5)
	check(sophon.pos.distance_to(Vector3(ai.home))<0.0001 and not sophon.moving(),"按 .5 加速/.95c 上限抵达并停留")
	check(sophon.lock<0 and s.watched_by(ai).is_empty(),"不赋予科研封锁")
	_give(ai,["warship"])
	check_eq(s.research(ai,"beam")["error"],"","智子在场不妨碍合法研究")
	var far:=_ship(s,ai,Ship.PROBE,Vector3(8,8,8),Vector3.LEFT)
	_turns(s,4)
	check(me.known.has(ai.home),"本地星系观察按物理传播回到控制锚点")
	check(not me.sightings.any(func(record):return record["id"]==far.id),"不提供敌文明远端单位的全境透视")
	check(ai.has_tech("beam"),"研究确实通过正式工作时钟完成")


## 规则：智子
func test_own_sophon_does_not_disable_enemy_sensor() -> void:
	var s:=_two_civs(Vector3i(3,0,0))
	var mine:=build_sophon(s,s.human())
	if mine==null: return
	s.send_sophon(s.human(),mine.id,s.civs[1].home)
	_turns(s,5)
	var theirs:=build_sophon(s,s.civs[1])
	check(theirs!=null,"对方仍能建造自己的智子")
	check(not mine.dead and not mine.moving(),"建造自己的智子不会无故移除已停留的敌方传感器")
	check_eq([s.sophon_research_left(s.civs[1]),s.sophon_tier_left(s.civs[1])],[0,0],"不存在旧科研/分级锁定倒计时")


## 规则：智子，调度（派出和行动）
func test_sophon_waits_when_not_a_home() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var sophon:=build_sophon(s,me)
	if sophon==null: return
	check_eq(s.send_sophon(me,sophon.id,Vector3i(2,0,0))["error"],"","空格也可作为目的地")
	_turns(s,7) # 等待周期性遥测的发出及2ly回传，不能只看真实到达。
	check(sophon.pos==Vector3(2,0,0) and not sophon.moving() and sophon.lock<0,"到空目的地原地待命")
	check_eq(s.send_sophon(me,sophon.id,Vector3i(3,0,0))["error"],"","遥测收到后可改派")
	check(not sophon.moving(),"远端改派命令不瞬间执行")
	WorldTime.advance(s,1.9)
	check(not sophon.moving(),"两光年命令尚未抵达")
	WorldTime.advance(s,0.2)
	check(sophon.moving(),"命令实际抵达后才再出发")
	check(s.civs[1].known.is_empty(),"远方文明不能凭真实位置知道此地活动")
