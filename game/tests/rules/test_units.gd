extends "res://tests/rules/rule_suite.gd"
## 运输船、星舰、吞食者与水滴；整段调度、返报和落地通过连续时钟。


func _transport(s: GameState) -> Ship:
	var me:=s.human()
	me.techs["interstellar_travel"]=true
	var result:=s.build(me,"colony")
	check_eq(result["error"],"","015运输船正式开工")
	_turns(s,3)
	var ships:=me.ships.filter(func(ship):return ship.kind==Ship.COLONY)
	check_eq(ships.size(),1,"3W后生成运输船")
	return ships[0] if not ships.is_empty() else null


## 规则：调度（派出和行动），建造
func test_colony_ship_requires_paid_landing_after_arrival() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	me.techs["colony"]=true
	_set_habitable(s,Vector3i(1,0,0),StarMap.Star.DOUBLE)
	var ship:=_transport(s)
	if ship==null: return
	check(s.send_colony(me,ship.id,Vector3i(-1,0,0))["error"]!="","拒绝图外")
	check(s.send_colony(me,ship.id,me.home)["error"]!="","拒绝己方已占有星系")
	var e:=me.energy
	check_eq(s.send_colony(me,ship.id,Vector3i(1,0,0))["error"],"","派出正式运输船")
	check_eq(me.energy,e,"派出不另花能量")
	check(s.send_colony(me,ship.id,Vector3i(2,0,0))["error"]!="","在途命令禁止重复派出")
	_turns(s,20)
	check(ship.pos.x<1 and me.colonies.size()==1,".005加速和.08限速使1ly航程超过20年")
	_turns(s,2)
	check(ship.pos.is_equal_approx(Vector3(1,0,0)) and not ship.moving(),"21年内抵达，随后等遥测返回")
	check(me.colonies.size()==1 and not ship.dead,"到达本身不免费殖民")
	var stock:=[me.energy,me.mineral]
	check_eq(s.start_landing(me,ship.id)["error"],"","109正式提交落地")
	check_eq([me.energy,me.mineral],[stock[0]-3.0,stock[1]-4.0],"落地全额预付3E4M")
	WorldTime.advance(s,4.8)
	check(not ship.dead and me.colonies.size()==1,"1年命令加4W尚未完成")
	WorldTime.advance(s,0.3)
	check(ship.dead and me.owns(Vector3i(1,0,0)),"完工时消耗运输船并建立锚点")


## 规则：调度（派出和行动）
func test_colony_ship_blind_target() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var ship:=_transport(s)
	if ship==null: return
	check_eq(s.send_colony(me,ship.id,Vector3i(1,0,0))["error"],"","未侦察空格也可盲飞")
	_turns(s,22)
	check(not ship.dead and not ship.moving() and ship.pos.is_equal_approx(Vector3(1,0,0)),"抵达空格停泊，不能建立殖民地")
	check(s.landing_error(me,ship.id)!="","缺109且无天体不能落地")
	_set_habitable(s,Vector3i(2,0,0),StarMap.Star.SINGLE)
	check_eq(s.send_colony(me,ship.id,Vector3i(2,0,0))["error"],"","收到待命遥测后可重新派出")
	WorldTime.advance(s,0.9)
	check(not ship.moving(),"远端命令仍在一光年航程中")
	WorldTime.advance(s,0.2)
	check(ship.moving(),"命令实际抵达才起航")
	_turns(s,23)
	check(ship.pos.is_equal_approx(Vector3(2,0,0)) and me.colonies.size()==1,"第二次到达仍要另行落地工程")


## 规则：星图和星系生成
func test_known_habitable_needs_intel() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var far:=Vector3i(6,0,0)
	_set_habitable(s,far,StarMap.Star.SINGLE)
	s.end_turn()
	check(not s.known_habitable(me).has(far),"未收到远端宜居观测不能获悉")
	me.intel[far]=s.snapshot(far) # 收到的历史观测夹具。
	check(s.known_habitable(me).has(far),"行动读取已知快照")
	var near:=Vector3i(1,0,0)
	_set_habitable(s,near,StarMap.Star.SINGLE)
	WorldTime.advance(s,1.3)
	check(s.known_habitable(me).has(near),"近处天体出现后也须等待下一采样与1ly传播")


## 规则：调度（派出和行动），交战
func test_colony_transport_requires_real_enemy_fire_to_be_destroyed() -> void:
	var s:=_two_civs(Vector3i(1,0,0))
	var me:=s.human()
	_set_habitable(s,Vector3i(2,0,0),StarMap.Star.SINGLE)
	var ship:=_ship(s,me,Ship.COLONY,Vector3(0.9,0,0),Vector3.RIGHT)
	ship.speed=0.08
	ship.has_target=true
	ship.target=Vector3(2,0,0)
	WorldTime.advance(s,2.0)
	check(not ship.dead and ship.pos.x>1,"仅经过敌方坐标不产生无来源伤害")
	var guard:=_ship(s,s.civs[1],Ship.WARSHIP,Vector3(1.2,0,0))
	guard.weapons=["beam"]
	WorldTime.advance(s,0.5)
	check(ship.dead and me.colonies.size()==1,"真实束流观测与命中摧毁1HP运输船")


## 规则：星际探测器
func test_droplet_parks_and_jams_broadcaster() -> void:
	var s:=_two_civs(Vector3i(2,0,0))
	var me:=s.human()
	var other:=s.civs[1]
	other.broadcasters[other.home]=true
	Assets.ensure(s,other)
	check(s.can_broadcast_from(other,other.home),"广播器初始可用")
	me.techs["droplet"]=true
	check_eq(s.build(me,"droplet")["error"],"","水滴是独立型号")
	_turns(s,5)
	var fleet:=me.ships.filter(func(sh):return sh.kind==Ship.DROPLET)
	check_eq(fleet.size(),1,"5W后生成水滴")
	if fleet.is_empty(): return
	var ship:Ship=fleet[0]
	check_eq(s.dispatch(me,ship.id,Vector3.RIGHT)["error"],"","水滴正式派出")
	_turns(s,15)
	check(ship.parked and ship.pos.is_equal_approx(Vector3(2,0,0)),".02加速到达敌星系后停泊")
	check(not s.can_broadcast_from(other,other.home),"实体停泊后封锁新广播")


## 规则：调度（派出和行动），吞噬者
func test_devourer_eats_rocky_planet_for_energy() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	var at:=Vector3i(1,0,0)
	_set_star(s,at,StarMap.Star.SINGLE)
	s.map.rocky[at]=2
	var ship:=_ship(s,me,Ship.DEVOURER,Vector3(0.92,0,0),Vector3.RIGHT)
	ship.speed=0.08
	WorldTime.advance(s,1.1)
	check(ship.parked and not ship.moving() and s.map.rocky[at]==1,"到达无主天体后停泊，消耗首颗行星")
	var rewards:=me.ledger.filter(func(item):return item["kind"]=="devour")
	check_eq(rewards.size(),1,"同年只吞食一颗")
	if not rewards.is_empty(): check_eq(rewards[0]["delta"],[25000,0],"记入25E一次性收益，不给矿石或经常产能")
	s.turn+=1
	WorldTime.advance(s,1.1)
	check_eq(s.map.rocky[at],0,"下一年且停留满一年才能吃第二颗")


## 规则：调度（派出和行动），灭亡和胜负
func test_starship_keeps_civ_alive_and_builds_rescue_transport() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_give(me,["interstellar_travel","colony"])
	var starship:=_ship(s,me,Ship.STARSHIP,Vector3(2,0,0))
	s._lose_system(me.home,me)
	check(me.alive and me.starship_only() and me.home==Vector3i(2,0,0),"星舰继续作为控制与存续锚点")
	check(s.settle_starship(me)["error"]!="","不能把星舰免费消耗成殖民地")
	check_eq(s.build(me,"colony")["error"],"","可在星舰上预付建造运输船")
	_turns(s,3)
	check(me.count(Ship.COLONY)==1 and me.has_starship(),"运输船完工，原锚点不被复制或消耗")
	var transport:Ship=me.ships.filter(func(ship):return ship.kind==Ship.COLONY)[0]
	check(transport.pos.is_equal_approx(starship.pos),"新船在施工宿主处出现")
	s._destroy(me,starship,"测试最后锚点被击毁")
	s._check_winner()
	check(not me.alive and s.winner=="AI","运输船不是存续锚点，不能延缓灭亡")
