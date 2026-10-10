extends "res://tests/rules/rule_suite.gd"


func remote_match() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s, civ)
	return s


## 规则：调度（派出和行动），情报传回
func test_v01_command_travels_and_dead_remote_does_not_leak() -> void:
	var s := remote_match()
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3(2, 0, 0))
	Signals.report_ship(s, me, ship)
	Signals.advance(s, 2.0)
	s.clock = 2.0
	Signals.receive_due(s)
	check(Signals.reported_ship(s, me, ship.id) != null, "只有状态回传后远方单位进入已知操作集合")
	var money := me.energy
	check_eq(s.dispatch(me, ship.id, Vector3.RIGHT)["error"], "", "根据最近遥测发送合法命令")
	check_eq([me.energy, me.actions_left], [money - 4.0, Balance.ACTION_BASE-1], "发出时占用AP和资源")
	check(ship.docked, "两光年外不能当帧收到出航命令")
	ship.dead = true
	Signals.receive_due(s)
	check_eq(me.energy, money - 4.0, "真实死亡不能令发出时马上退款而泄露战况")
	Signals.advance(s, 2.0)
	s.clock = 4.0
	Signals.receive_due(s)
	check_eq(me.energy, money - 4.0, "失败收据还要从远方返回")
	Signals.advance(s, 2.0)
	s.clock = 6.0
	Signals.receive_due(s)
	check_eq([me.energy, me.actions_left], [money, Balance.ACTION_BASE-1], "往返四年后释放未用资源，AP不退款")


## 规则：调度（派出和行动）
func test_v01_dispatch_discounts_and_original_bare_models() -> void:
	var s := remote_match()
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3.ZERO)
	check_eq(s.command_cost(me, ship), 4, "普通舰体基础调度4E")
	me.techs["fusion"] = true
	check_eq(s.command_cost(me, ship), 3, "聚变减1E")
	me.techs["antimatter_collection"] = true
	check_eq(s.command_cost(me, ship), 1, "收集再减2E")
	me.techs["dark_energy"] = true
	check_eq(s.command_cost(me, ship), 0, "真空能替换为零")
	for kind in [Ship.PROBE, Ship.NUCLEAR_PROBE, Ship.COLONY]:
		var bare := Ship.make(kind, Vector3.ZERO, 100)
		check_eq(s.command_cost(me, bare), 0, "探测/运输型号保持免费命令")


## 规则：建造，情报传回
func test_v01_remote_build_checks_actual_site_and_refunds_after_receipt() -> void:
	var s:=remote_match()
	var me:=s.human()
	var at:=Vector3i(2,0,0)
	_set_habitable(s,at,StarMap.Star.SINGLE)
	me.colonies.append(at)
	Assets.ensure(s,me)
	Knowledge.report_site(s,me,at)
	Signals.advance(s,2.0)
	s.clock=2.0
	Signals.receive_due(s)
	check_eq(s.build(me,"miner",at)["error"],"","按已收到的真实矿点信息下单")
	var paid:=me.mineral
	s.map.rocky[at]=0 # 命令飞行期间矿点消失，锚点仍活着。
	Signals.advance(s,2.0)
	s.clock=4.0
	Signals.receive_due(s)
	check(me.pending.is_empty(),"开工抵达必须检查真实矿点，不能造幽灵矿船")
	check_eq(me.mineral,paid,"远端失败退款要等回执，不能立即暴露")
	Signals.advance(s,2.0)
	s.clock=6.0
	Signals.receive_due(s)
	check_eq(me.mineral,paid+3.0,"未开工的3M托管随失败回执全额返回")
	Signals.receive_due(s)
	check_eq(me.mineral,paid+3.0,"失败回执只退款一次")
	check_eq(me.actions_left,Balance.ACTION_BASE-1,"已发出的命令不返还AP")


## 规则：建造，情报传回
func test_v01_project_cannot_inherit_replacement_anchor() -> void:
	var s:=remote_match()
	var me:=s.human()
	var at:=Vector3i(2,0,0)
	_set_habitable(s,at,StarMap.Star.SINGLE)
	me.colonies.append(at)
	Assets.ensure(s,me)
	var old_id: int=Assets.at(me,"anchor",at)[0]["id"]
	var project:=WorkOrder.create(s.next_id(),"probe",at,[0,1],1)
	project["host_id"]=old_id
	Assets.remove_at(me,at)
	Assets.ensure(s,me)
	check(Assets.at(me,"anchor",at)[0]["id"]!=old_id,"同址替换锚点具有新实例ID")
	check(not s.project_host_alive(me,project),"旧工程不能仅因坐标仍属己方就寄生到新锚点")
