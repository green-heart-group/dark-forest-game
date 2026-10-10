extends "res://tests/rules/rule_suite.gd"


## 规则：移动
func test_v01_swept_relative_collision() -> void:
	var t := Kinematics.first_contact(Vector3(-1, 0, 0), Vector3(2, 0, 0), Vector3.ZERO, 0.01, 1.0)
	check(absf(t - 0.495) < 0.00001, "两个步末均不重叠的物体在中途首次接触")
	check_eq(Kinematics.first_contact(Vector3(-1, 0.1, 0), Vector3(2, 0, 0), Vector3.ZERO, 0.01, 1.0), INF, "近掠不能当成命中")
	var curved := Kinematics.first_contact(Vector3(-1, 0, 0), Vector3.ZERO, Vector3(2, 0, 0), 0.01, 1.0)
	check(absf(curved - sqrt(0.99)) <= 0.000002, "加速轨迹求首次接触，不只扫步末端点")
	var first_half := Kinematics.first_contact(Vector3(-1, 0, 0), Vector3.ZERO, Vector3(2, 0, 0), 0.01, 0.5)
	var second_half := Kinematics.first_contact(Vector3(-0.75, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), 0.01, 0.5)
	check(first_half == INF and absf(second_half + 0.5 - curved) <= 0.000002, "减半步长后的接触时刻收敛")


## 规则：移动，二维、单向著和奇异点
func test_v01_physical_units_and_acceleration() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	var ship := _ship(s, me, Ship.WARSHIP, Vector3.ZERO, Vector3.RIGHT)
	var m := Kinematics.motion(s, me, ship, 1.0)
	check(absf(Kinematics.position(m, 1.0).x - 0.005) < 0.000001, "从静止以.01加速度积分一年为.005ly")
	check_eq(m["cap_time"], 15.0, "战舰15年达到.15ly/年")
	s.dimension = 2
	for cell_id in s.cell_dims:
		s.cell_dims[cell_id] = 2
	m = Kinematics.motion(s, me, ship, 1.0)
	check(absf(Kinematics.position(m, 1.0).x - 0.01) < 0.000001, "二维格长.5ly，物理路程不变而逻辑格路程翻倍")
	var probe := _ship(s, me, Ship.PROBE, Vector3.ZERO, Vector3.RIGHT)
	m = Kinematics.motion(s, me, probe, 1.0)
	check(absf(Kinematics.position(m, 1.0).x - 0.36) < 0.000001, "化学探测器在二维直接以.3×.6ly/年匀速，无虚构加速")
	var grain := _ship(s, me, Ship.GRAIN, Vector3.ZERO, Vector3.RIGHT)
	m = Kinematics.motion(s, me, grain, 1.0)
	check(absf(m["speed"] - 0.594) < 0.000001, "二维光粒用.99×.6背景光速")


## 规则：自身降维，每回合的收入
func test_v01_per_entity_output_and_stable_ids() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.miners[me.home] = 2
	Assets.ensure(s, me)
	var miners := Assets.at(me, "miner", me.home)
	var ids := miners.map(func(asset): return asset["id"])
	miners[0]["entity_dim"] = 2
	check_eq(s.mineral_income(me), 3.2, "同一星系高低维矿船各按自己的Q产出")
	var before := s._next_id
	s.mineral_income(me)
	check_eq(s._next_id, before, "读取收入不得生成新ID")
	Assets.ensure(s, me)
	check_eq(Assets.at(me, "miner", me.home).map(func(asset): return asset["id"]), ids, "集合同步不重建实体ID")
	var copy := StateCopy.copy(s)
	check_eq(copy.human().assets, me.assets, "快照完整保留实体ID与维度")
	Assets.destroy(me, miners[0])
	check_eq([me.miner_count(), s.mineral_income(me)], [1, 2.0], "单个实体毁灭只移除自己的产能")


## 规则：每回合的收入
func test_v01_flow_integral_keeps_small_remainders() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	me.energy = 0.0
	me.mineral = 0.0
	for i in 20:
		Economy.integrate(s, me, {"net": [0.001, 0.7]}, 0.05)
	check_eq([me.energy, me.mineral], [0.001, 0.7], "分成20段的收入积分不损失千分之一余额")


## 规则：建造，每回合的收入
func test_v01_partial_year_completion_integrates_only_online_time() -> void:
	var s := _two_civs(Vector3i(8, 8, 8))
	var me := s.human()
	s.map.rocky[me.home] = 1
	s.build(me, "miner")
	WorkOrder.advance(me.pending[0], 1.5)
	me.mineral = 0.0
	WorldTime.advance(s, 1.0)
	check_eq(me.miner_count(), 1, "半年后完成余下.5工作量")
	check_eq(me.mineral, 1.0, "新矿船仅在后半年的真实在线时长产出1M")
	check_eq(s.clock, 1.0, "子步准确停在下一年边界")


## 规则：移动，交战
func test_v01_integrated_crossing_and_timestep_convergence() -> void:
	var defaults := Balance.PHYSICS_MAX_DT
	var outcomes: Array = []
	for dt in [0.05, 0.025]:
		Balance.PHYSICS_MAX_DT = dt
		var s := _two_civs(Vector3i(8, 8, 8))
		var a := _ship(s, s.human(), Ship.WARSHIP, Vector3(0, 0, 0), Vector3.RIGHT)
		var b := _ship(s, s.civs[1], Ship.WARSHIP, Vector3(0.1, 0, 0), Vector3.LEFT)
		a.speed = 0.15
		b.speed = 0.15
		WorldTime.advance(s, 1.0)
		check(a.dead and b.dead, "穿越期间发生自毁接触，不能互相穿过去")
		var hits: Array = s.events.filter(func(event): return event["kind"] == "hit")
		check(not hits.is_empty(), "实际主时钟记录命中时刻")
		if not hits.is_empty():
			outcomes.append(hits[0]["t"])
	Balance.PHYSICS_MAX_DT = defaults
	check(outcomes.size() == 2 and absf(outcomes[0] - outcomes[1]) <= 0.00002, "减半最大步长后的首次碰撞时刻差不超过2e-5年")


## 规则：建造
func test_v01_order_refund_independent_of_subdivision() -> void:
	var whole := WorkOrder.create(1, "warship", Vector3i.ZERO, [1, 5], 2.0)
	var split := WorkOrder.create(2, "warship", Vector3i.ZERO, [1, 5], 2.0)
	WorkOrder.advance(whole, 1.0)
	for i in 20:
		WorkOrder.advance(split, 0.05)
	check_eq(WorkOrder.refund(split), WorkOrder.refund(whole), "托管消耗按累计比例，不能靠细分子步少耗费用")


## 规则：二向箔
func test_v01_simultaneous_fronts_keep_order_independent_plane() -> void:
	for order in [[Vector3i(1,1,2),Vector3i(7,6,5)],[Vector3i(7,6,5),Vector3i(1,1,2)]]:
		var s := _collapse_match()
		s.ensure_cells()
		for at in order:
			SpaceEvents.unfold(s,at)
			SpaceEvents.resolve(s)
		check_eq(s.flat_plane,4,"同一物理时刻两前沿使用平均展示平面，交换顺序不变")
		check(s.flattened.values().all(func(z):return z==4),"已变换格子的展示平面同步")
		s.clock+=0.2
		SpaceEvents.unfold(s,Vector3i(8,0,8))
		check_eq(s.flat_plane,4,"同一年内较晚到达的载荷不能重选展示平面")
