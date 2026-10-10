extends "res://tests/rules/rule_suite.gd"
## 维度载荷、展开及准备；保留原覆盖主题，使用当前正式时钟与实体名册。


func _protect(civ: Civ) -> void:
	civ.reduced=true
	for asset in civ.assets: asset["entity_dim"]=2


## 规则：二向箔
func test_half_light_speed_spread() -> void:
	check_eq(Balance.FOIL_SPREAD,0.5,"展开速度硬约束保持.5背景光速")
	var s:=_two_civs(Vector3i(8,8,8))
	for civ in s.civs: _protect(civ)
	s._unfold_foil(Vector3i.ZERO)
	check_eq(s.flattened.size(),1,"刚展开只覆盖落点")
	s._spread_flat()
	check_eq(s.foil_zones[0]["age"],0.5,"一年的半光年进度不取整")
	check(s.flattened.has(Vector3i(1,0,0)),"邻格边界恰为.5ly，接触即转换")
	check(not s.flattened.has(Vector3i(1,1,0)),"面对角最近.707ly仍在外")
	s._spread_flat()
	check(s.flattened.has(Vector3i(1,1,1)),"1ly球扫到最近.866ly的体对角格")
	check(not s.flattened.has(Vector3i(2,0,0)),"第二格边界1.5ly尚未到")
	s._unfold_foil(Vector3i(8,8,8))
	s._spread_flat()
	check_eq(s.foil_zones[1]["age"],0.5,"后来的原点有独立物理起始时刻")
	check(s.flattened.has(Vector3i(2,0,0)),"1.5ly触及第二格")


## 规则：二向箔，移动
func test_warp_ship_escapes_half_speed_wave() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	_protect(s.human())
	var ship:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(2,0,0),Vector3.RIGHT)
	ship.warp=true
	s._unfold_foil(Vector3i.ZERO)
	for i in 3:
		s.end_turn()
		check(not ship.dead and ship.pos.x>s.foil_zones[0]["age"]+0.5,"曲率舰经加速与自身航迹限速仍领先.5c前沿")


## 规则：灭亡和胜负
func test_elimination_reports_cause_once() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var causes:=[]
	s.connect("civilization_eliminated",func(_civ,cause):causes.append(cause))
	s._unfold_foil(Vector3i.ZERO)
	s._unfold_foil(Vector3i.ZERO)
	check_eq(causes,["空间前沿"],"同一锚点只记录一次真实淘汰原因")


## 规则：二向箔，建造
func test_foil_builds_then_flies_and_activates() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var target:=Vector3i(1,0,0)
	check(s.launch_foil(me,target)["error"]!="","没有科技不能发射")
	me.techs["dimension"]=true
	check(s.launch_foil(me,target)["error"]!="","研究不能代替预付弹药工程")
	me.energy=250
	me.mineral=100
	check_eq(s.build(me,"dimension_weapon")["error"],"","正式开工维度武器")
	check_eq([me.energy,me.mineral,me.dimension_ammo],[50.0,45.0,0],"预付200E55M尚无弹药")
	_turns(s,8)
	check_eq(me.dimension_ammo,1,"8W完成后才入库")
	check_eq(s.launch_foil(me,target)["error"],"","发射消耗现存弹药")
	check_eq(me.dimension_ammo,0,"库存不重复使用")
	WorldTime.advance(s,3.9)
	check(s.foil_zones.is_empty() and s.payloads[0]["pos"].x<1,".25c飞行还未到达1ly目标")
	WorldTime.advance(s,0.2)
	check(s.foil_zones.is_empty(),"抵达后仍需1年激活")
	WorldTime.advance(s,1.0)
	check(s.flattened.has(target),"真实激活后才展开")


## 规则：二向箔
func test_foil_flies_past_enemy_to_empty_target() -> void:
	var s:=_two_civs(Vector3i(1,0,0))
	var me:=s.human()
	me.techs["dimension"]=true
	me.dimension_ammo=1
	var target:=Vector3i(3,0,0)
	check_eq(s.launch_foil(me,target)["error"],"","可向未占有空格发射")
	WorldTime.advance(s,6.0)
	check(s.payloads[0]["pos"].x>1 and s.foil_zones.is_empty() and s.civs[1].alive,"路过敌星系不提前展开")
	WorldTime.advance(s,7.1)
	check(s.flattened.has(target),"3ly/.25c加1年激活后到目标展开")


## 规则：二向箔
func test_foil_between_two_civs_hits_nearer_first() -> void:
	var s:=_three_civs()
	_protect(s.human())
	# 前沿先后测试直接摆激活点，发射旅行另有独立正式入口回归。
	s._unfold_foil(Vector3i(8,3,4))
	var third_out:=-1
	var ai_out:=-1
	for i in 16:
		s.end_turn()
		if third_out<0 and not s.civs[2].alive: third_out=i
		if ai_out<0 and not s.civs[1].alive: ai_out=i
	check(third_out>=0 and ai_out>third_out,"较近第三方先被连续球前沿扫到")
	check(s.human().alive and s.winner=="你","已转换实体存续且最后合法终局")


## 规则：二向箔
func test_foil_bad_targets() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.techs["dimension"]=true
	me.dimension_ammo=1
	check(s.launch_foil(me,Vector3i(10,0,0))["error"]!="","拒绝图外")
	check(s.launch_foil(me,me.home)["error"]!="","拒绝己方星系")
	var at:=Vector3i(5,5,3)
	me.intel[at]={"cell_dim":2,"stars":0,"owner":-1}
	check(s.launch_foil(me,at)["error"]!="","已收到的转换格不能重复指定")
	me.dimension_ammo=0
	check(s.launch_foil(me,Vector3i(5,5,5))["error"]!="","没有库存不得发射")


## 规则：二向箔，自身降维
func test_reduced_civ_survives_flattening() -> void:
	var s:=_two_civs(Vector3i(2,0,0))
	_protect(s.human())
	s._unfold_foil(Vector3i.ZERO)
	check(s.human().alive and s.map.star_at(Vector3i.ZERO)==StarMap.Star.SINGLE,"实体已转换则保留星系")
	WorldTime.advance(s,2.9)
	check(s.civs[1].alive,"前沿尚未触及2ly目标的1.5ly边界")
	WorldTime.advance(s,0.2)
	check(not s.civs[1].alive and s.winner=="你","触及未转换锚点后依法淘汰")


## 规则：二向箔，灭亡和胜负
func test_everyone_flattened_same_time_means_draw() -> void:
	var s:=_two_civs(Vector3i(0,0,4))
	s._unfold_foil(Vector3i(0,0,2))
	WorldTime.advance(s,3.1)
	check(not s.human().alive and not s.civs[1].alive,"对称前沿同刻扫到双方")
	check_eq(s.winner,"平局","最后存续集合同时为空，不按遍历先后定赢家")


## 规则：二向箔
func test_flattening_destroys_unprepared_ships_but_not_physical_wakes() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var ship:=_ship(s,me,Ship.STARSHIP,Vector3(3,3,3))
	Hazards.leave_deadline(s,Vector3(3,3,3),Vector3(3,3,4),ship)
	s._unfold_foil(Vector3i(3,3,3))
	check(ship.dead and not me.has_starship(),"未适配星舰被前沿摧毁")
	check(s.deadlines.size()==1 and s.deadlines[0]["expires"]==20.0,"场不是文明资产，原形成与到期时间保留")


## 规则：灭亡和胜负
func test_foil_keeps_flying_after_launcher_dies() -> void:
	var s:=_three_civs()
	var me:=s.human()
	me.techs["dimension"]=true
	me.dimension_ammo=1
	check_eq(s.launch_foil(me,Vector3i(1,0,0))["error"],"","正式发射")
	var id:int=s.payloads[0]["id"]
	s._lose_system(me.home,me)
	s._check_winner()
	check(not me.alive and not s.is_over(),"发射者灭亡但其他双方仍存续")
	check(s.payloads.any(func(p):return p["id"]==id and not p["dead"]),"在途载荷不随发射者删除")
	WorldTime.advance(s,5.1)
	check(s.flattened.has(Vector3i(1,0,0)),"失去发射者后载荷仍抵达激活")


## 规则：自身降维
func test_reduce_takes_work_freezes_roster_and_executes_separately() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	check(s.start_reduce(me)["error"]!="","完整迁维需要302")
	me.techs["dimension"]=true
	me.techs["probe"]=true
	var probe:=_ship(s,me,Ship.PROBE,Vector3.ZERO)
	me.grains[me.home]=true
	var roster:=Conversion.known_roster(s,me,3)
	check_eq(roster.size(),2,"锚点和探测器计入名册，库存光粒不计入")
	var stock:=[me.energy,me.mineral]
	var result:=s.start_reduce(me)
	check_eq(result["error"],"","准备冻结两实体名册")
	check_eq([me.energy,me.mineral],[stock[0]-18,stock[1]-12],"12E8M基础加每实体3E2M")
	check(s.build(me,"probe")["error"]!="","同一宿主在制迁维占用建造队列")
	_turns(s,4)
	check(not me.reduced and not me.pending.is_empty(),"5W在4年时尚未完成")
	s.end_turn()
	check(not me.reduced and probe.entity_dim==3,"准备完成只发ready，不立即降维")
	check_eq(s.execute_conversion(me,result["order"])["error"],"","收到回执后执行")
	check(me.reduced and probe.entity_dim==2,"名册内的原地实体已转换")
	check_eq(me.energy,61.5,"准备后剩82E，在首次执行时保留75%")


## 规则：自身降维
func test_reduce_waits_for_host_construction() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["dimension","miner"])
	s.map.rocky[me.home]=1
	check_eq(s.build(me,"miner")["error"],"","合法矿点开工")
	var e:=me.energy
	check(s.start_reduce(me)["error"]!="" and me.energy==e,"同一宿主在制工程阻止迁维，不额外扣费")
	_turns(s,2)
	check_eq(s.start_reduce(me)["error"],"","已有工程完成后可准备")


## 规则：二向箔
func test_visual_anticipation_preserves_rules() -> void:
	var s:=_collapse_match()
	s._unfold_foil(Vector3i(4,4,4))
	var far:=Vector3i(8,8,8)
	var before:=s.checksum()
	var first:=DimensionSpace.frame(s)
	check(first["amounts"][far]>0.0 and first["amounts"][far]<1.0,"远处体素可提前显示展开动画")
	check_eq(s.checksum(),before,"布局采样不改变规则状态")
	check_eq(s.flattened.size(),1,"动画不提前施加伤害")
	check_eq(s.civs[1].home,far,"画面位置不能回写物理位置")
	s._spread_flat()
	var next:=DimensionSpace.frame(s)
	check(next["amounts"][far]>first["amounts"][far] and not s.flattened.has(far),"视觉继续展开而远方前沿尚未到达")
