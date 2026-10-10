extends "res://tests/rules/rule_suite.gd"
## 建造原有交互契约迁移到付费工作队列；每次使用正式下单与连续回合。


func _finish_build(s: GameState,civ: Civ,kind: String) -> Dictionary:
	var result:=s.build(civ,kind)
	check_eq(result["error"],"","提交"+kind)
	if result["error"]!="":
		return result
	for year in int(ceilf(Construction.work(kind)))+2:
		if civ.order_reports[result["order"]].get("status","")=="completed":
			break
		s.end_turn()
	check_eq(civ.order_reports[result["order"]].get("status",""),"completed","完整工作与当地回报完成"+kind)
	return result


## 规则：建造
func test_build_needs_tech_and_respects_limits() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.energy=1000
	me.mineral=1000
	check(s.build(me,"warship")["error"]!="","没有科技不能造战舰")
	_give(me,["warship","interstellar_travel","devourer","sophon","starship"])
	for i in 2:
		_finish_build(s,me,"warship")
	check(s.build(me,"warship")["error"]!="","005基础上限2艘")
	me.techs["alloy"]=true
	check(s.build(me,"warship")["error"]!="","013仍为2艘")
	me.techs["shield"]=true
	_finish_build(s,me,"warship")
	check(s.build(me,"warship")["error"]!="","106上限3艘")
	for kind in ["colony","devourer","sophon","starship"]:
		_finish_build(s,me,kind)
	check(s.build(me,"starship")["error"]!="","110整局限建一艘")
	var starship:=me.starship()
	s._destroy(me,starship,"测试星舰损失")
	s._clean_dead()
	check(s.build(me,"starship")["error"]!="","星舰已毁也不重置整局限建")
	check(s.build(me,"probe",Vector3i(5,5,5))["error"]!="","只能建在已知己方存续锚点")


## 规则：建造，调度（派出和行动）
func test_units_built_docked_then_dispatched() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var before:=[me.energy,me.mineral,me.actions_left]
	var result:=s.build(me,"probe")
	check_eq(result["error"],"","可以下单探测器")
	check(result["ship"]==null and me.ships.is_empty(),"下单只创建工程，不能直接拿到远端成品")
	check_eq([me.energy,me.mineral,me.actions_left],[before[0]-1,before[1]-3,before[2]-1],"全额托管并扣1AP")
	s.end_turn()
	var p:=me.ship_by_id(me.order_reports[result["order"]]["result_ship"])
	check(p!=null and p.docked and p.pos==Vector3.ZERO,"工作完成后停在星系")
	check(s.dispatch(me,p.id,Vector3.ZERO)["error"]!="","派出需要方向")
	var ap:=me.actions_left
	check_eq(s.dispatch(me,p.id,Vector3(0,0,1))["error"],"","通过正式命令派出")
	check_eq(me.actions_left,ap-1,"派出扣1AP")
	check(s.dispatch(me,p.id,Vector3(0,0,1))["error"]!="","已经派出不能重复派出")
	s.end_turn()
	check(absf(p.pos.z-0.3)<1e-6,"化学探测器按W7的.3c在三维每年航行")


## 规则：建造
func test_facilities_next_turn_and_dyson_cap() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.energy=1000
	me.mineral=1000
	s.map.rocky[me.home]=1
	_give(me,["dyson"])
	_finish_build(s,me,"miner")
	_finish_build(s,me,"miner")
	check(s.build(me,"miner")["error"]!="","001每系只能两艘基础矿船")
	_give(me,["mining_advanced"])
	for i in 3:
		_finish_build(s,me,"advanced_miner")
	check_eq(me.miner_count(),5,"008后两种矿船合计5艘")
	check(s.build(me,"miner")["error"]!="" and s.build(me,"advanced_miner")["error"]!="","两种型号共享矿点容量")
	var r:=s.build(me,"dyson")
	check_eq(r["error"],"","当地恒星可建戴森")
	check(me.dysons.is_empty(),"下单不即时增加设施")
	check(s.build(me,"dyson")["error"]!="","在制也占本地队列和容量")
	_turns(s,6)
	check_eq(me.dysons.get(me.home,0),1,"完成六工作量后建成")
	var other:=Vector3i(1,0,0)
	_set_star(s,other,StarMap.Star.DOUBLE)
	me.colonies.append(other)
	check(s.build(me,"dyson")["error"]!="","别处两颗恒星不能增加母星的戴森容量")


## 规则：建造
func test_build_refuses_second_one() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["bunker","broadcaster","antimatter"])
	me.energy=1000
	me.mineral=1000
	var refused:=func(kind: String,what: String):
		var before:=[me.energy,me.mineral,me.actions_left,me.pending.size(),me.antimatter,s.rng.state]
		check(s.build(me,kind)["error"]!="",what)
		check_eq([me.energy,me.mineral,me.actions_left,me.pending.size(),me.antimatter,s.rng.state],before,what+"：失败原子且不消耗RNG")
	refused.call("bunker","无类木行星不能建掩体")
	s.map.gas[me.home]=1
	for kind in ["bunker","broadcaster","warning"]:
		var r:=s.build(me,kind)
		check_eq(r["error"],"","可以建"+kind)
		refused.call(kind,"在制时不允许重复工程")
		_turns(s,int(ceilf(Construction.work(kind))))
		refused.call(kind,"当地已有设施不重复建")
	for i in 3:
		_finish_build(s,me,"antimatter")
	check_eq(me.antimatter,3,"已收到的库存弹药最多三枚")
	refused.call("antimatter","库存满后拒绝并保留资源")
	var other:=Vector3i(0,3,0)
	_set_star(s,other,StarMap.Star.SINGLE)
	s.map.gas[other]=1
	me.colonies.append(other)
	Assets.ensure(s,me)
	# 此例夹具明确提供已收远端站点快照；传播耗时另由远端订单回归检查。
	me.site_reports[other]={"data":Knowledge.actual_site(s,me,other),"t_observed":s.clock,"epoch":s.space_epoch}
	for kind in ["bunker","broadcaster","warning"]:
		check_eq(s.build_error(me,kind,other),"","另一星系有独立容量："+kind)
	check_eq(s.build(me,"warning",other)["error"],"","预警容量属于每星系而非整个文明")


## 规则：预警系统，建造
func test_warning_built_after_its_system_falls() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var backup:=Vector3i(0,3,0)
	_set_star(s,backup,StarMap.Star.SINGLE)
	me.colonies.append(backup)
	check_eq(s.build(me,"warning")["error"],"","在母星提交预警工程")
	var stock:=[me.energy,me.mineral]
	s._lose_system(me.home,me,"测试宿主毁灭")
	check_eq([me.energy,me.mineral],stock,"宿主毁灭烧毁托管，不能转移工程或即时退款")
	_turns(s,3)
	check(me.alive and me.pending.is_empty() and not me.has_warning,"备份锚点存续，但已毁宿主的工程不会在别处复活")
