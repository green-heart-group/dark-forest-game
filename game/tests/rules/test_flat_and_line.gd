extends "res://tests/rules/rule_suite.gd"
## 全图压平以后：共同平面、二维、单向著、一维、奇异点和平局。


## 规则：二维、单向著和奇异点
func test_line_wave_preserves_fractional_physical_radius() -> void:
	var s := _two_dimensional_match()
	_protect(s,1)
	var at := Vector3i(13,13,s.flat_plane)
	s._unfold_line_foil(at)
	s._spread_flat()
	check(absf(s.line_zones[0]["age"]-0.6)<0.00001,"二维一年的.3ly对应.6逻辑格，不取整")
	check(s.linearized.has(at+Vector3i.RIGHT),"前沿触及邻格边界即转换")
	check(not s.linearized.has(at+Vector3i(2,0,0)),"尚未到第二格")
	s._spread_flat()
	check(not s.linearized.has(at+Vector3i(2,0,0)),"两年.6ly仍未到.75ly的第二格边界")
	s._spread_flat()
	check(s.linearized.has(at+Vector3i(2,0,0)),"三年.9ly已越过第二格边界")


## 规则：二向箔
func test_foils_share_one_plane() -> void:
	var s := _collapse_match()
	for civ in s.civs:
		civ.dimension_ammo=1
	check_eq(s.launch_foil(s.human(),Vector3i(1,1,1))["error"],"","第一片正式发射")
	check_eq(s.launch_foil(s.civs[1],Vector3i(8,8,7))["error"],"","另一高度正式发射")
	for i in 40:
		if s.all_flat(): break
		s.end_turn()
	check(s.all_flat(),"有限速度载荷和展开前沿最终压平全图")
	check(s.flattened.values().all(func(z):return z==s.flat_plane),"所有格子同一平面")
	check(s.civs.all(func(c):return c.alive and c.home.z==s.flat_plane),"准备好的资产存续")


## 规则：二向箔
func test_different_planes_are_not_fully_flat() -> void:
	var s := _collapse_match()
	for x in StarMap.SIZE:
		for y in StarMap.SIZE:
			for z in StarMap.SIZE:
				s.flattened[Vector3i(x, y, z)] = 2 if x < 5 else 7
	check(not s.all_flat(), "只数格子不够：不同高度不能算压成同一平面")


## 规则：灭亡和胜负
func test_collapse_finishes_after_combat_ends() -> void:
	var s := _collapse_match()
	for asset in s.civs[1].assets: asset["entity_dim"]=3
	s._unfold_foil(Vector3i(8,8,8))
	check(s.is_over() and s.collapse_pending(),"胜负已出，空间还在坍缩")
	var turn:=s.turn
	var energy:=s.human().energy
	for i in 30: s.advance_collapse()
	check(s.all_flat() and not s.collapse_pending(),"专用环境续播可完成整图展开")
	check_eq([s.turn,s.human().energy],[turn,energy],"续播没有行动、收入或游戏回合")


## 规则：二维、单向著和奇异点
func test_line_foil_requires_two_dimensional_world() -> void:
	var s := _collapse_match()
	var energy := s.human().energy
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 3))["error"] != "", "三维地图不能发射单向著")
	check(s.human().energy == energy and s.human().foils.is_empty(), "拒绝的发射不花资源")
	s = _two_dimensional_match()
	check(s.all_flat(), "测试准备：全图压平")
	check(s.launch_line_foil(s.human(), Vector3i(3, 3, 8))["error"] != "", "单向著目标必须在现有平面")
	check(s.launch_foil(s.human(), Vector3i(3, 3, 4))["error"] != "", "二维后不能再发二向箔")


## 维度载荷共用有限飞行和目标激活，经过其他星系不会提前展开。
## 规则：二维、单向著和奇异点
func test_line_foil_unfolds_only_at_designated_target() -> void:
	var s := _two_dimensional_match()
	var enemy:=Vector3i(13,13,s.flat_plane)
	s.civs[1].colonies.append(enemy)
	Assets.ensure(s,s.civs[1])
	var origin:=enemy-Vector3i.RIGHT
	var target:=enemy+Vector3i.RIGHT
	SpaceEvents.launch(s,0,Vector3(origin),Vector3(target),"dimension")
	WorldTime.advance(s,7.5)
	check(s.line_zones.is_empty(),"路过敌星系不提前展开，仍需到达和1年激活")
	WorldTime.advance(s,0.2)
	check_eq(s.line_anchor,target,"在1ly/.15ly每年+1年后只于指定目标展开")


## 规则：自身降维
func test_second_self_reduction() -> void:
	var s := _two_dimensional_match()
	var me:=s.human()
	var result:=s.start_reduce(me)
	check_eq(result["error"],"","二维可准备第二步转换")
	WorldTime.advance(s,4.9)
	check(not me.pending.is_empty(),"二维工作效率仍为1，5W尚未完工")
	WorldTime.advance(s,0.2)
	check(not me.line_reduced,"准备就绪本身不执行转换")
	check_eq(s.execute_conversion(me,result["order"])["error"],"","就绪后正式执行")
	WorldTime.advance(s,0.01)
	check(me.line_reduced,"实体转换至一维")
	s.dimension=1
	check(s.start_reduce(me)["error"]!="","不提供零维避难")


## 规则：二维、单向著和奇异点，灭亡和胜负
func test_line_foils_converge_without_timer_draw() -> void:
	var s := _two_dimensional_match()
	_protect(s,1)
	s._unfold_line_foil(Vector3i(2,2,4))
	s._unfold_line_foil(Vector3i(7,7,4))
	for i in 70:
		if s.all_linear(): break
		s._spread_flat()
	check(s.all_linear() and s.linearized.values().all(func(y):return y==s.line_y),"多前沿共用一条直线")
	check(s.civs.all(func(c):return c.alive and c.home.y==s.line_y),"幸存锚点保留不同格子")
	_turns(s,Balance.LINE_GRACE_TURNS+1)
	check(not s.is_over(),"存续中的文明不会因一维等待计时平局")


## 规则：二维、单向著和奇异点
func test_singularity_has_physical_front_and_no_automatic_win() -> void:
	var s := _two_dimensional_match()
	_finish_line(s)
	var me:=s.human()
	me.dimension_ammo=1
	check_eq(s.launch_singularity(me)["error"],"","一维正式发射零维载荷")
	WorldTime.advance(s,0.9)
	check(not s.is_over(),"激活完成前不判获胜")
	WorldTime.advance(s,0.2)
	check(not me.alive and s.winner=="AI","在自身唯一锚点激活摧毁自己，胜负仍按存续")


## F5.3：预警按箔的种类报名字；已经没用的箔（二维里的二向箔）不报。
## 规则：预警系统
func test_warning_reports_real_dimension_payload() -> void:
	var s:=_two_dimensional_match()
	var me:=s.human()
	me.warnings[me.home]=0
	Assets.ensure(s,me)
	var payload:=SpaceEvents.launch(s,1,Vector3(me.home)+Vector3.RIGHT,Vector3(me.home)+Vector3(3,0,0),"dimension")
	WorldTime.advance(s,0.7)
	check(me.alerts.is_empty(),"半光年预警尚未按.6c回传")
	WorldTime.advance(s,0.2)
	check(me.alerts.any(func(a):return a.get("id",-1)==payload["id"] and a.get("payload_kind","")=="dimension"),"到达后预警携带真实维度载荷类型")


## F5.3：隐藏文明按现在的维度出手：二维发单向著（目标挪到平面上），压成直线后只发光粒。
## 规则：广播和隐藏文明
func test_hidden_weapon_matches_dimension() -> void:
	Balance.HIDDEN_STRIKE_CHANCE=1.0
	Balance.HIDDEN_FOIL_CHANCE=1.0
	Balance.HIDDEN_HEAR_RANGE=1e6
	var s:=_two_dimensional_match()
	s.hidden_listen.append({"id":s.next_id(),"from":Vector3i(-1,4,4),"target":Vector3i(3,3,4),"left":5,"received":s.clock-1,"next_check":s.clock})
	Information.resolve(s)
	check(s.payloads.size()==1 and s.payloads[0]["from_dim"]==2 and s.payloads[0]["target"].z==4,"二维隐藏文明用单向维度载荷")
	s.payloads.clear()
	_finish_line(s)
	s.clock=s.remap_until
	s.hidden_listen.clear()
	s.hidden_listen.append({"id":s.next_id(),"from":Vector3i(-1,s.line_y,4),"target":s.human().home,"left":5,"received":s.clock-1,"next_check":s.clock})
	Information.resolve(s)
	check(s.payloads.is_empty() and s.hidden_ships.size()==1,"一维隐藏攻击保留光粒分支")


## 规则：二维、单向著和奇异点
func test_line_attack_destroys_unprepared_civ() -> void:
	var s:=_two_dimensional_match()
	for asset in s.human().assets: asset["entity_dim"]=1
	s._unfold_line_foil(s.civs[1].home)
	check(not s.civs[1].alive and s.winner=="你","二维实体抵挡不了一维前沿")


## 规则：二向箔，二维、单向著和奇异点
func test_epoch_preserves_historical_intelligence() -> void:
	var s:=_collapse_match()
	var me:=s.human()
	var enemy:=s.civs[1].home
	me.known[enemy]=1
	me.intel[enemy]=s.snapshot(enemy)
	me.intel[enemy]["t_observed"]=-3.0
	me.intel[enemy]["epoch"]=0
	me.heard[enemy]=1
	me.colony_tried[enemy]=true
	me.discovered=true
	me.tier1_turn=1
	var energy:=me.energy
	_finish_flat(s)
	var mapped:=DimensionSpace.plane_cell(enemy,4)
	check(me.known.has(mapped) and me.intel.has(mapped) and me.heard.has(mapped),"历史情报按永久格子搬迁，不抹掉")
	check_eq([me.intel[mapped]["t_observed"],me.intel[mapped]["epoch"]],[-3.0,0],"空间换图不把旧观测冒充为新观测")
	check(me.colony_tried.has(mapped) and me.energy==energy and me.tier1_turn==1 and me.discovered,"已知发展成果和探索记录保留")


## 规则：二向箔，二维、单向著和奇异点
func test_unfold_keeps_incoming_projectiles_moving() -> void:
	var s := _collapse_match()
	var grain := Ship.make(Ship.GRAIN, Vector3(-2, 4, 4), 123)
	grain.docked = false
	grain.direction = Vector3.RIGHT
	s.hidden_ships.append(grain)
	_finish_flat(s)
	check(grain.direction != Vector3.ZERO and not grain.dead, "图外来袭换图后仍在飞行")
	var before := grain.pos
	WorldTime.advance(s,0.1)
	check(grain.pos != before and not grain.dead, "新航向仍进入星图，不会卡死在边缘")


## 规则：二向箔，二维、单向著和奇异点
func test_same_column_enemy_assets_do_not_collide() -> void:
	var s := _two_civs(Vector3i(0, 0, 7))
	for civ in s.civs:
		_ship(s, civ, Ship.STARSHIP, Vector3(civ.home))
	_protect(s,2)
	_finish_flat(s)
	check(s.civs.all(func(c): return c.alive and c.has_starship()), "同列敌对星系和停靠星舰不会覆盖")
	check(s.civs[0].home != s.civs[1].home, "两个文明获得不同二维坐标")


## 规则：二向箔，二维、单向著和奇异点
func test_same_dimension_grain_still_works() -> void:
	var s:=_two_dimensional_match()
	var enemy:=s.civs[1]
	_ship(s,s.human(),Ship.GRAIN,Vector3(enemy.home)-Vector3.RIGHT,Vector3.RIGHT)
	WorldTime.advance(s,0.5)
	check(not enemy.alive,"二维光粒按物理半径碰撞，并非转换后永久免疫")


## 规则：二向箔，二维、单向著和奇异点
func test_unfold_preserves_systems_assets_and_environment() -> void:
	var s:=_collapse_match()
	var me:=s.human()
	var upper:=Vector3i(0,0,7)
	_set_habitable(s,upper,StarMap.Star.DOUBLE)
	me.colonies.append(upper)
	me.dysons[upper]=2
	me.miners[upper]=3
	me.grains[upper]=true
	me.bunkers[upper]=true
	me.broadcasters[upper]=true
	var order:=WorkOrder.create(s.next_id(),"miner",upper,[0,3],2)
	WorkOrder.advance(order,0.5)
	me.pending.append(order)
	var ship:=_ship(s,me,Ship.STARSHIP,Vector3(0,0,3))
	var scout:=_ship(s,me,Ship.PROBE,Vector3(1.2,2,3),Vector3(0,0,1))
	_protect(s,2)
	Hazards.activate(s,Vector3(upper),s.next_id())
	var stars:=s.map.stars.duplicate()
	var expires:float=s.black_domains[0]["expires"]
	_flatten_whole_column(s,Vector2i.ZERO,4)
	check(me.colonies==[Vector3i.ZERO,upper] and not ship.dead,"阶段内同列资产不覆盖")
	_finish_flat(s)
	var dest:=DimensionSpace.plane_cell(upper,4)
	check(s.all_flat() and s.map.extent==Vector3i(27,27,1),"真实星图切换27²")
	check(me.colonies.size()==2 and me.owns(dest) and not ship.dead,"同列星系星舰保留身份")
	for cell in stars:
		check_eq(s.map.star_at(DimensionSpace.plane_cell(cell,4)),stars[cell],"每个星系一一保留")
	check(me.dysons[dest]==2 and me.miners[dest]==3 and me.grains.has(dest),"设施与弹药数量保留")
	check(me.bunkers.has(dest) and me.broadcasters.has(dest) and order["at"]==dest,"防御和工程宿主搬迁")
	check_eq([order["done"],WorkOrder.refund(order)],[500,[0.0,2.25]],"只换坐标不重置施工和退款账")
	check_eq([s.black_domains[0]["center"],s.black_domains[0]["expires"]],[dest,expires],"黑域空间位置迁移而到期时刻不刷新")
	check(s.map.is_habitable(dest) and s.map.rocky[dest]==1,"行星宜居信息保留")
	check(scout.pos.z==4 and scout.direction.z==0 and not scout.dead,"浮点舰船映射为有效平面轨迹")
	check(s.cell_exists(Vector3i(26,26,4)) and not s.cell_exists(Vector3i(27,0,4)) and not s.cell_exists(Vector3i(26,26,5)),"新平面边界生效")


## 规则：二向箔，二维、单向著和奇异点
func test_dimension_mapping_bijection_and_movement() -> void:
	for z in 9:
		var seen:={}
		for cell in StarMap.new().cells(): seen[DimensionSpace.plane_cell(cell,z)]=true
		check_eq(seen.size(),729,"每个锚点层都有729唯一目标")
	var s:=_two_dimensional_match()
	_finish_line(s)
	check(s.all_linear() and s.map.extent==Vector3i(729,1,1),"二维展开为729格直线")
	check(s.map.cells().size()==729 and s.civs[0].home!=s.civs[1].home,"一维没有坐标覆盖")
	var sh:=_ship(s,s.human(),Ship.PROBE,Vector3(700,13,4),Vector3.RIGHT)
	sh.entity_dim=1
	WorldTime.advance(s,0.1)
	check(not sh.dead and sh.pos.x>700,"连续物理使用新边界")
	check_eq(Geometry.segment_cells(Vector3(700,13,4),Vector3(702,13,4),0,s.map.bounds()).size(),2,"几何扫描使用新边界")


## 规则：二向箔，二维、单向著和奇异点
func test_unprepared_ship_entering_flattened_cell_dies() -> void:
	var s:=_collapse_match()
	s._unfold_foil(Vector3i(3,0,4))
	var ship:=_ship(s,s.human(),Ship.NUCLEAR_PROBE,Vector3(2.49,0,4),Vector3.RIGHT)
	ship.speed=0.1
	check(not ship.dead and ship.entity_dim==3,"初始未进入降维格子")
	WorldTime.advance(s,0.2)
	check(ship.dead,"连续移动越过已转换格子边界即毁灭")


func _finish_flat(s: GameState, anchor := Vector3i(4, 4, 4)) -> void:
	s._unfold_foil(anchor)
	for i in ceili(37.0 / Balance.FOIL_SPREAD) + 1:
		if s.all_flat():
			break
		s._spread_flat()


## 规则：二向箔
func test_foil_spreads_as_sphere_from_landing_cell() -> void:
	var s:=_collapse_match()
	s._unfold_foil(Vector3i(4,4,2))
	s.clock+=4.0
	SpaceEvents.resolve(s)
	check(s.flattened.has(Vector3i(4,4,4)) and s.flattened.has(Vector3i(6,4,2)),"2ly球前沿接触竖直及水平邻格")
	check(not s.flattened.has(Vector3i(4,4,5)),"最短距离2.5ly的格子尚未到达")
	check(not s.flattened.has(Vector3i(6,4,4)),"角落最近2.12ly也未到达")


## 规则：二向箔
func test_flat_position_does_not_depend_on_strike() -> void:
	var homes := []
	for at in [Vector3i(4, 4, 4), Vector3i(0, 8, 1)]:
		var s := _collapse_match()
		var before: Array = s.civs.map(func(c): return c.home)
		_finish_flat(s, at)
		check(s.all_flat(), "测试准备：压平")
		for i in s.civs.size():
			var p := DimensionSpace.Layout.fixed_plane(before[i])
			check_eq(Vector2i(s.civs[i].home.x, s.civs[i].home.y), p, "母星系落在固定映射的位置")
		homes.append(s.civs.map(func(c): return Vector2i(c.home.x, c.home.y)))
	check_eq(homes[0], homes[1], "打在不同地方，压平后的坐标一样")


## 规则：二向箔
func test_same_turn_foils_average_plane_height() -> void:
	for order in [[Vector3i(1, 1, 2), Vector3i(7, 6, 5)], [Vector3i(7, 6, 5), Vector3i(1, 1, 2)]]:
		var s := _collapse_match()
		for at in order:
			s._unfold_foil(at)
		check_eq(s.flat_plane, 4, "同一回合两片箔 z 是 2 和 5，平均 3.5 往上取 4，和先后无关")
		check(s.flattened.values().all(func(z): return z == 4), "已经压平的格子也记到这个高度")
		s._spread_flat()
		s._unfold_foil(Vector3i(8, 0, 8))
		check_eq(s.flat_plane, 4, "之后的箔不再改平面高度")


## 规则：二维、单向著和奇异点
func test_line_spreads_as_circle_and_keeps_curve_order() -> void:
	var s:=_two_dimensional_match()
	_protect(s,1)
	var before:Array=s.civs.map(func(c):return c.home)
	var at:=Vector3i(13,13,4)
	s._unfold_line_foil(at)
	s.clock+=5.0
	SpaceEvents.resolve(s)
	check(s.linearized.has(at+Vector3i(0,3,0)) and s.linearized.has(at+Vector3i(2,2,0)),"1.5ly圆前沿扫到近格")
	check(not s.linearized.has(at+Vector3i(4,0,0)) and not s.linearized.has(at+Vector3i(3,3,0)),"圆外角落不会当成正方形覆盖")
	for i in 40:
		if s.all_linear(): break
		s._spread_flat()
	check(s.all_linear(),"圆形前沿最终全部转换")
	for i in s.civs.size():
		check_eq(s.civs[i].home.x,DimensionSpace.Layout.plane_to_line(Vector2i(before[i].x,before[i].y)),"保持皮亚诺曲线的永久格顺序")


## 规则：二向箔
func test_ship_without_destination_keeps_heading_when_flattened() -> void:
	var s:=_collapse_match()
	var ship:=_ship(s,s.human(),Ship.PROBE,Vector3(2,3,4),Vector3(0,1,1).normalized())
	ship.entity_dim=2
	ship.speed=0.01
	ship.distance_flown=2.25
	var anchor:=Vector3i(4,4,4)
	var expected:=(DimensionSpace.point(ship.pos+ship.direction,anchor,false,s.map)-DimensionSpace.point(ship.pos,anchor,false,s.map)).normalized()
	_finish_flat(s)
	check(ship.direction.is_equal_approx(expected),"方向映射到相邻航迹点，不沿旧坐标飞行")
	check_eq([ship.speed,ship.distance_flown],[0.01,2.25],"物理速度和已走路程保留")
	var line_expected:=(DimensionSpace.point(ship.pos+ship.direction,Vector3i(13,13,4),true,s.map)-DimensionSpace.point(ship.pos,Vector3i(13,13,4),true,s.map)).normalized()
	_finish_line(s)
	check(ship.direction.is_equal_approx(line_expected),"同一航迹点再次映射到一维")


## 规则：二向箔
func test_straight_up_ship_retains_mapped_trajectory() -> void:
	var s:=_collapse_match()
	var ship:=_ship(s,s.human(),Ship.PROBE,Vector3(2,3,4),Vector3(0,0,1))
	ship.entity_dim=2
	ship.speed=0.01
	_finish_flat(s)
	check(ship.direction.z==0 and ship.direction.length()>0.99 and ship.speed==0.01,"相邻z格展开到不同平面格，航迹保持而非静止")


## 几何夹具直接指定已转换实体；完整准备、传播和扣费另由conversion及画面回放回归验证。
func _protect(s: GameState, dim: int) -> void:
	for civ in s.civs:
		Assets.ensure(s,civ)
		civ.reduced=dim<=2
		civ.line_reduced=dim<=1
		for asset in civ.assets: asset["entity_dim"]=dim
		for ship in civ.ships: ship.entity_dim=dim


func _finish_line(s: GameState) -> void:
	_protect(s,1)
	s._unfold_line_foil(Vector3i(13,13,s.flat_plane))
	for i in 40:
		if s.all_linear(): break
		s._spread_flat()
