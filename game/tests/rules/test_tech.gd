extends "res://tests/rules/rule_suite.gd"
## 科技树：等级条件、开放的先后、望远镜和预警的升级。


## 规则：科技树
func test_tech_tiers_and_prerequisites() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ap := me.actions_left
	check(me.has_tech("colony"), "殖民船开局就有（0 级）")
	check(s.research(me, "starship")["error"] != "", "没发现别人不能升 I 级")
	_open_tiers(me, 1)
	check(s.research(me, "starship")["error"] == "", "发现别人以后可以升 I 级（星舰，前置：殖民船）")
	check(me.actions_left == ap, "升级科技不花行动点")
	check(me.energy == 100 - Tech.cost("starship")[0], "升级科技花资源")
	check(s.research(me, "grain")["error"] != "", "没接触不能升 II 级")
	_open_tiers(me, 2)
	check(s.research(me, "devourer")["error"] == "", "接触后可以升 II 级（吞噬者，前置：采矿船）")
	check(s.research(me, "domain")["error"] != "", "III 级要能量收入达到门槛")
	_open_tiers(me, 3)
	check(s.research(me, "domain")["error"].contains("曲率引擎"), "黑域投放要先有曲率引擎")
	check(s.research(me, "starship")["error"] != "", "已经有的不能再升")


## E8：III 级要 II 级开放以后、能量收入达到门槛，再比 II 级晚 TIER_GAP 回合。
## 规则：科技树，E8
func test_tier3_needs_tier2_and_income() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	s.map.rocky[Vector3i.ZERO] = Balance.TIER3_ENERGY
	s.end_turn()
	check(me.tier3_turn < 0, "II 级没开时收入再高也不算")
	_open_tiers(me, 2)
	me.tier2_turn = s.turn
	s.end_turn()
	check(me.tier3_turn == me.tier2_turn + Balance.TIER_GAP, "收入达标后，III 级比 II 级晚 TIER_GAP 回合开放")
	check(not s.tier_open(me, 3), "还没到那一回合")
	s.map.rocky[Vector3i.ZERO] = 0
	_turns(s, Balance.TIER_GAP)
	check(s.tier_open(me, 3), "达到过一次，到时候就开")
	check(s.research(me, "dimension")["error"] == "", "可以升 III 级")


## 规则：视野，预警系统
func test_telescope_and_warning_upgrades() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ap := me.actions_left
	for i in Balance.TELESCOPE_MAX:
		s.upgrade(me, "telescope")
	check(me.telescope == Balance.TELESCOPE_MAX and me.actions_left == ap, "望远镜升到上限，不花行动点")
	check(s.upgrade(me, "telescope")["error"] != "", "不能再升")
	check(is_equal_approx(s.sphere_radius(me, Balance.VISION_HOME), Balance.VISION_HOME + Balance.TELESCOPE_MAX * Balance.TELESCOPE_STEP),
			"升满时母星系视野加 TELESCOPE_MAX × TELESCOPE_STEP")
	var p := _ship(s, me, Ship.PROBE, Vector3.ZERO, Vector3(1, 0, 0))
	check(s.cone_of(me, p)[1] == Balance.MAX_CONE_ANGLE, "圆锥张角最大 60°")
	check(s.upgrade(me, "warning")["error"] != "", "没建预警系统不能升级范围")
	me.has_warning = true
	s.upgrade(me, "warning")
	check(me.warning_range() == Balance.WARNING_RANGE + 1, "预警范围 +1")


## E8：II 级的条件是自己的任何舰船和别人的舰船相距 CONTACT_RANGE 以内，I 级开放以后才算。
## 规则：科技树，E8
func test_contact_opens_tier2_after_tier1() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	var ai := s.civs[1]
	_ship(s, me, Ship.PROBE, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(s, ai, Ship.COLONY, Vector3(3.9, 0, 0), Vector3(-1, 0, 0))
	s._combat()
	check(me.tier2_turn < 0, "I 级还没开时，接触不算")
	_open_tiers(me, 1)
	_open_tiers(ai, 1)
	s._combat()
	check(me.tier2_turn >= 0 and ai.tier2_turn >= 0, "探测器和殖民船相距 1 格以内，双方都算接触")
	check(me.tier2_turn == Balance.TIER_GAP, "II 级比 I 级晚 TIER_GAP 回合开放")
	var far := _two_civs(Vector3i(9, 9, 9))
	_open_tiers(far.human(), 1)
	_ship(far, far.human(), Ship.PROBE, Vector3(3, 0, 0), Vector3(1, 0, 0))
	_ship(far, far.civs[1], Ship.PROBE, Vector3(4.5, 0, 0), Vector3(1, 0, 0))
	far._combat()
	check(far.human().tier2_turn < 0, "隔得远不算")


## 规则：科技树，E8
func test_tiers_open_in_order_with_a_gap() -> void:
	var s := _two_civs(Vector3i(9, 9, 9))
	var me := s.human()
	s._engage(me, s.civs[1])
	check(me.tier2_turn < 0, "先接触、还没发现别人时不算")
	s._discover(me, "测试")
	check(me.tier1_turn == s.turn + 1 and not s.tier_open(me, 1), "发现的那一回合还不开，下一回合开 I 级")
	s.end_turn()
	check(s.tier_open(me, 1), "下一回合开 I 级")
	s._engage(me, s.civs[1])
	check(me.tier2_turn == me.tier1_turn + Balance.TIER_GAP, "接触以后 II 级比 I 级晚 TIER_GAP 回合")
	_turns(s, Balance.TIER_GAP - 1)
	check(not s.tier_open(me, 2), "间隔没满不开")
	s.end_turn()
	check(s.tier_open(me, 2), "间隔满了开 II 级")
