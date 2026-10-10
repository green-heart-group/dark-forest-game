extends "res://tests/rules/rule_suite.gd"
## 科技树、队列和权限；通过现行工作与回传入口验证原有操作。


## 规则：科技树
func test_tech_tiers_and_prerequisites() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	check_eq(Tech.starting(),["miner","fission","telescope","probe","warning"],"只有五项初始科技")
	var expected:={"mining_advanced":"miner","fusion":"fission","interstellar_probe":"probe",
		"railgun":"warship","beam":"warship","alloy":"warship","bunker":"warning",
		"devourer":"mining_advanced","gravity_scan":"telescope","hbomb":"beam","torpedo":"railgun",
		"shield":"beam","antimatter":"antimatter_collection","gravity":"broadcaster","colony":"interstellar_travel",
		"starship":"interstellar_travel","dyson":"devourer","droplet":"interstellar_probe",
		"wandering_earth":"starship","dark_energy":"antimatter_collection","domain":"warp"}
	for id in Tech.ALL:
		check_eq(Tech.ALL[id]["needs"],[expected[id]] if expected.has(id) else [],"逐项核对前置："+id)
	check(s.research(me,"starship")["error"]!="","权限未开放不能研究星舰")
	_open_tiers(me,1)
	check(s.research(me,"starship")["error"].contains("恒星际航行"),"权限开放也不能跳过前置")
	_give(me,["interstellar_travel"])
	var before:=[me.energy,me.mineral,me.actions_left]
	check_eq(s.research(me,"starship")["error"],"","前置和权限都满足后进入研究队列")
	check_eq([me.energy,me.mineral,me.actions_left],[before[0]-Tech.cost("starship")[0],before[1]-Tech.cost("starship")[1],before[2]-1],"研究全额托管并花1AP")
	check(not me.has_tech("starship"),"不能在下单瞬间获得科技")
	_turns(s,3)
	check(me.has_tech("starship"),"工作完成且当地回报送达才获得科技")
	check(s.research(me,"starship")["error"]!="","已有科技不能重复研究")
	_open_tiers(me,3)
	check(s.research(me,"domain")["error"].contains("曲率引擎"),"黑域仍需要曲率前置")


## 规则：科技树
func test_research_money_errors() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_open_tiers(me,1)
	_give(me,["interstellar_travel"])
	me.energy=Tech.cost("starship")[0]-3
	check_eq(s.research_error(me,"starship"),"能量不足（还差 3.000）","固定点金额说明差额")
	check_eq(s.research_block_error(me,"starship"),"","只有资源不足时没有其他阻塞")
	me.actions_left=0
	me.energy=1000
	check(s.research_error(me,"starship")!="","研究同样需要行动点")
	var before:=[me.energy,me.mineral,me.techs.duplicate(),s.rng.state]
	check(s.research(me,"starship")["error"]!="","不能用零AP下研究单")
	check_eq([me.energy,me.mineral,me.techs,s.rng.state],before,"拒绝不改变资源、科技或随机流")
	check(s.research_block_error(me,"grain")!="","等级未开放仍给出阻塞")


## 规则：科技树
func test_tier3_needs_tier2_and_income() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	s.map.rocky[me.home]=40
	me.advanced_miners[me.home]=15
	s._refresh_permissions(me)
	check(me.tier3_turn<0,"仅有60M40E产能不能替代毁灭资格")
	me.conquered=true # 此例只测试权限结合；侦察与战报的形成另有配对测试。
	s._refresh_permissions(me)
	check(me.tier3_turn>=0,"已收到资格和名义产能都达标后记录永久权限")
	me.advanced_miners.clear()
	s.end_turn()
	check(s.tier_open(me,3),"随后产能下降不撤销已经取得的权限")
	me.energy=1000
	me.mineral=1000
	check_eq(s.research(me,"dimension")["error"],"","权限生效后可正式研究302")


## 规则：视野，预警系统
func test_telescope_and_warning_upgrades() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	for level in Balance.TELESCOPE_MAX:
		var ap:=me.actions_left
		check_eq(s.upgrade(me,"telescope")["error"],"","望远镜可逐级升级")
		check_eq(me.actions_left,ap-1,"升级花1AP")
		check_eq(me.telescope,level,"下单不提前改变视野")
		_turns(s,int(ceilf(Balance.TELESCOPE_UPGRADE_WORK[level])))
	check_eq(me.telescope,Balance.TELESCOPE_MAX,"三级升级工作完成")
	check(s.upgrade(me,"telescope")["error"]!="","不能超过最高等级")
	check(is_equal_approx(s.sphere_radius(me,Balance.VISION_HOME),Balance.VISION_HOME+Balance.TELESCOPE_MAX*Balance.TELESCOPE_STEP),"满级母星视野保留对应加成")
	var p:=_ship(s,me,Ship.PROBE,Vector3.ZERO,Vector3.RIGHT)
	var eye: Dictionary=Signals.observers(s,me).filter(func(o):return o["id"]==p.id)[0]
	check_eq(eye["angle"],Balance.MAX_CONE_ANGLE,"探测器满级圆锥角")
	check(s.upgrade(me,"warning")["error"]!="","预警必须先建造")
	check_eq(s.build(me,"warning")["error"],"","可以建造当地预警")
	_turns(s,int(ceilf(Construction.work("warning"))))
	check_eq(s.upgrade(me,"warning")["error"],"","已完成设施可以升级")
	_turns(s,int(ceilf(Balance.WARNING_UPGRADE_WORK)))
	check_eq(me.warnings[me.home],1,"当地预警升级一级")


## 规则：科技树
func test_contact_opens_tier2_after_tier1() -> void:
	var s:=_two_civs(Vector3i(8,8,8))
	var me:=s.human()
	_set_star(s,Vector3i(3,0,0),StarMap.Star.SINGLE)
	_ship(s,me,Ship.PROBE,Vector3(3,0,0))
	_ship(s,s.civs[1],Ship.COLONY,Vector3(3.1,0,0))
	_turns(s,2)
	check(not me.contacted,"传感器本地接触不能提前到控制端")
	_turns(s,3)
	check(me.contacted,"同星系接触经过目标至传感器及回传被保存")
	check(me.tier2_turn<0,"事件本身不代替30M10E产能")
	s.map.rocky[me.home]=10
	me.advanced_miners[me.home]=8
	s._refresh_permissions(me)
	_turns(s,4) # 远端单位的资格状态也须回传，不能从权限按钮提前泄露。
	check(s.tier_open(me,2),"先收到的接触资格在后来产能达标时仍有效")


## 规则：科技树
func test_tiers_open_in_order_with_a_gap() -> void:
	for event_first in [true,false]:
		var s:=_two_civs(Vector3i(8,8,8))
		var me:=s.human()
		if event_first:
			s._discover(me,"已收未知实体观测")
			s._refresh_permissions(me)
			check(me.tier1_turn<0,"先发现还需产能")
		s.map.rocky[me.home]=4
		me.advanced_miners[me.home]=3
		if not event_first:
			s._refresh_permissions(me)
			check(me.tier1_turn<0,"先有产能还需发现")
			s._discover(me,"已收未知实体观测")
		s._refresh_permissions(me)
		s.end_turn()
		check(s.tier_open(me,1),"事件与产能顺序不影响权限，无旧强制等级间隔")
