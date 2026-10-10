extends "res://tests/rules/rule_suite.gd"


func ready_match() -> GameState:
	var s := _two_civs(Vector3i(8, 8, 8))
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s, civ)
		civ.techs["dimension"] = true
	return s


## 规则：自身降维
func test_v01_conversion_frozen_roster_and_remote_ready() -> void:
	var s := ready_match()
	var me := s.human()
	var remote := _ship(s, me, Ship.WARSHIP, Vector3(2, 0, 0))
	Signals.report_ship(s,me,remote)
	Signals.advance(s,2.0)
	s.clock=2.0
	Signals.receive_due(s)
	var ids := Conversion.roster(me, 3)
	check_eq(Conversion.quote(ids, false)["cost"], [18, 12], "两实体费用18E12M，顺序不混淆")
	check_eq(Conversion.quote(ids, false)["work"], 5.0, "4+ceil(N/4)工作量")
	var result := s.prepare_conversion(me, ids, Signals.controller(me), false, true)
	check_eq(result["error"], "", "准备完整名册")
	var added := _ship(s, me, Ship.PROBE, Vector3.ZERO)
	var order: Dictionary = me.pending[0]
	WorkOrder.advance(order, 5.0)
	s.clock = 7.0
	s._finish_pending(me, 0)
	Signals.receive_due(s)
	check(not me.conversions[result["order"]]["roster"].has(added.id), "后来建造的资产不混入冻结名册")
	check(not remote.ready.has("3>2"), "远方舰船不能瞬间ready")
	Signals.advance(s, 2.0)
	s.clock = 9.0
	Signals.receive_due(s)
	check_eq(remote.ready["3>2"]["at"], 9.0, "准备完成后的两光年指令真实传播两年")


## 规则：自身降维
func test_v01_conversion_receipt_is_once_and_keeps_paid_work() -> void:
	var s := ready_match()
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3.ZERO)
	ship.cost = [2.0, 12.0]
	var anchor := Signals.controller(me)
	var project := WorkOrder.create(s.next_id(), "miner", me.home, [0, 10], 10)
	WorkOrder.advance(project, 4)
	me.pending.append(project)
	me.energy = 100
	me.mineral = 100
	for id in [anchor, ship.id]:
		var entity := Signals.entity(s, 0, id)
		var ready: Dictionary = entity["ship"].ready if entity.has("ship") else entity["asset"]["ready"]
		ready["3>2"] = {"at": -1.0, "fraction": 0.75, "plan": 1, "automatic": true}
		check(Conversion.apply(s, me, entity, "3>2", true), "每个ready实体单独转换")
	check_eq([me.energy, me.mineral], [75.0, 75.0], "第二个实体不重复扣全局库存")
	check_eq(WorkOrder.refund(project), [0.0, 4.5], "仅剩可退款账按.75折损")
	check_eq([project["paid"], project["done"]], [[0, 10000], 4000], "全额已付资格和已完工作不变")
	check_eq(ship.cost, [1.5, 9.0], "军舰实际回收成本基数折损")
	WorkOrder.advance(project, 6.0)
	check_eq(WorkOrder.salvage(project), [0.0, 7.5], "无需补缴折损额仍能完成")
	ship.ready["2>1"] = {"at": -1.0, "fraction": 0.75, "plan": 2, "automatic": true}
	s.dimension = 2
	Conversion.apply(s, me, Signals.entity(s, 0, ship.id), "2>1", true)
	check_eq([me.energy, me.mineral, ship.cost], [56.25, 56.25, [1.125, 6.75]], "第二级独立receipt：100→75→56.25")


## 规则：自身降维，二向箔
func test_v01_same_time_ready_does_not_escape_front() -> void:
	var s := ready_match()
	var me := s.human()
	var anchor := Signals.entity(s, 0, Signals.controller(me))
	anchor["asset"]["ready"]["3>2"] = {"at": 2.0, "fraction": 0.4, "plan": 1, "automatic": true}
	s.clock = 2.0
	s._collapse_depth += 1
	SpaceEvents.convert_cell(s, me.home)
	s._collapse_depth -= 1
	s._check_winner()
	check(not me.alive, "波前同刻才ready仍失败")
	check_eq(s.winner, "AI", "该批次仅另一文明存续")
	check(me.conversion_receipts.is_empty(), "失败的准备不征库存转换税")


## 规则：自身降维
func test_v01_emergency_limits_and_no_zero_dim_escape() -> void:
	var s := ready_match()
	var me := s.human()
	me.techs.erase("dimension")
	me.miners[me.home] = 3
	Assets.ensure(s, me)
	var anchor := Signals.controller(me)
	var miners := Assets.at(me, "miner", me.home)
	check_eq(Conversion.error(s, me, [anchor, miners[0]["id"], miners[1]["id"]], anchor, true), "", "无302也可保护1锚点2矿")
	check(Conversion.error(s, me, [anchor, miners[0]["id"], miners[1]["id"], miners[2]["id"]], anchor, true) != "", "不能多带第三艘矿")
	s.dimension = 1
	check(Conversion.error(s, me, [anchor], anchor, true) != "", "一维无零维迁维按钮规则")


## 规则：灭亡和胜负
func test_v01_terminal_batch_and_human_elimination() -> void:
	var s := _three_civs()
	s._lose_system(s.human().home, s.human(), "测试")
	s._check_winner()
	check(not s.human().alive and not s.is_over(), "玩家失去最后锚点但还有两个AI，对局继续")
	s._collapse_depth += 1
	for civ in s.civs.slice(1):
		s._lose_system(civ.home, civ, "同刻")
	s._collapse_depth -= 1
	s._check_winner()
	check_eq(s.winner, "平局", "最后双方同一批次失去锚点是同归于尽")
	var terminal := s.events.filter(func(event): return event["kind"] == "terminal")
	s._check_winner()
	check_eq(s.events.filter(func(event): return event["kind"] == "terminal").size(), terminal.size(), "终局仅写一次")
	var one := _two_civs(Vector3i(8, 8, 8))
	one.dimension = 1
	one.line_turns = 9999
	one._check_winner()
	check(not one.is_over(), "进入一维与等待不制造宽限平局")


## 规则：二维、单向著和奇异点，情报传回
func test_v01_atomic_remap_preserves_inflight_identity_and_history() -> void:
	var s := ready_match()
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3(1, 2, 3), Vector3.RIGHT)
	ship.speed = 0.1
	var asset := Assets.get_id(me, Signals.controller(me))
	var message := Signals.send(s, 0, Vector3(4, 2, 1), asset["id"], "report", {"type": "own", "data": {"id": ship.id, "pos": ship.pos}, "t_observed": 0.0, "epoch": 0})
	message["distance"] = 2.5
	var payload := SpaceEvents.launch(s, 0, Vector3(4, 2, 1), Vector3(7, 3, 1), "dimension")
	payload["distance"] = 0.75
	var ids := s.cell_ids.values().duplicate()
	var asset_id: int = asset["id"]
	var ship_id := ship.id
	var message_id: int = message["id"]
	s.fold_anchor = Vector3i(4, 4, 4)
	DimensionSpace.commit(s, false)
	check_eq([s.dimension, s.space_epoch, s.cell_ids.size()], [2, 1, 729], "原子映射保留729个格子并递增epoch")
	check_eq(s.cell_ids.values(), ids, "永久cell ID完全保留")
	check_eq([me.assets[0]["id"], me.ships[0].id, s.messages[0]["id"]], [asset_id, ship_id, message_id], "实体与在途消息不重建ID")
	check_eq([ship.speed, message["distance"], payload["distance"]], [0.1, 2.5, 0.75], "速度大小和已花物理航程不重置")
	check_eq([message["sent"], message["body"]["t_observed"], message["body"]["epoch"]], [0.0, 0.0, 0], "历史发送与观测epoch保留")
	check(message["not_before"] > s.clock, "新几何最早下一正时间子步才送达")
	check_eq(StateCopy.copy(s).messages, s.messages, "保存快照保留全部消息状态")


## 规则：二向箔，二维、单向著和奇异点
func test_v01_payload_flight_activation_and_survival_end() -> void:
	var s := ready_match()
	var me := s.human()
	me.dimension_ammo = 1
	var price := [me.energy, me.mineral]
	check_eq(s.launch_foil(me, Vector3i(1, 0, 0))["error"], "", "发射使用已造好的维度弹药")
	check_eq([me.dimension_ammo, me.energy, me.mineral], [0, price[0], price[1]], "发射不能再追扣一次建造价")
	WorldTime.advance(s, 4.0)
	check_eq(s.payloads[0]["pos"], Vector3(1, 0, 0), "1ly在.25c下四年抵达")
	check(s.foil_zones.is_empty(), "抵达并不马上展开")
	WorldTime.advance(s, 1.0)
	check_eq(s.foil_zones.size(), 1, "抵达后真实等待一年展开")
	check_eq(s.cell_dims[s.cell_ids[Vector3i(1, 0, 0)]], 2, "展开触及目标格")
	check(not s.is_over(), "发射与展开本身都不是胜利")


## 规则：二向箔，黑域
func test_v01_front_not_slowed_by_zero_light_and_full_remap() -> void:
	var s := ready_match()
	for civ in s.civs:
		Assets.get_id(civ, Signals.controller(civ))["ready"]["3>2"] = {"at": -1.0, "fraction": 0.75, "plan": 0, "automatic": true}
	SpaceEvents.unfold(s, Vector3i(4, 4, 4))
	Hazards.activate(s, Vector3(4, 4, 4))
	s.clock = 2.0
	s._collapse_depth += 1
	SpaceEvents.resolve(s)
	s._collapse_depth -= 1
	check_eq(s.foil_zones[0]["age"], 1.0, "三维前沿每年.5ly，不乘黑域零光速")
	check_eq(s.cell_dims[s.cell_ids[Vector3i(5, 4, 4)]], 2, "前沿已进入核心以外下一格")
	s.clock = 20.0
	s._collapse_depth += 1
	SpaceEvents.resolve(s)
	s._collapse_depth -= 1
	s._check_winner()
	check_eq([s.dimension, s.space_epoch, s.cell_ids.size()], [2, 1, 729], "完整729格只触发一次原子换图")
	check(not s.is_over(), "双方适配保留各自锚点，换维后继续")
	check_eq(s.civs.map(func(civ): return civ.assets[0]["entity_dim"]), [2, 2], "实体维度独立完成本步")
