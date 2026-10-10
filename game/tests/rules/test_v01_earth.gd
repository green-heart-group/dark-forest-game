extends "res://tests/rules/rule_suite.gd"


func earth_match() -> GameState:
	var s := _two_civs(Vector3i(8,8,8))
	var me := s.human()
	_set_habitable(s,me.home,StarMap.Star.SINGLE)
	s.map.rocky[me.home] = 2
	me.miners[me.home] = 2
	me.dysons[me.home] = 1
	me.warnings[me.home] = 2
	_give(me,["fission","fusion","wandering_earth","gravity_scan"])
	me.energy = 1000
	me.mineral = 1000
	s.ensure_cells()
	for civ in s.civs:
		Assets.ensure(s,civ)
	return s


## 规则：调度（派出和行动）
func test_v01_earth_transforms_original_anchor_without_external_income() -> void:
	var s := earth_match()
	var me := s.human()
	var anchor := me.original_anchor_id
	var at := me.home
	var miner: Dictionary = Assets.at(me,"miner",at)[0]
	var warning: Dictionary = Assets.at(me,"warning",at)[0]
	var ids := [miner["id"],warning["id"]]
	var result := s.start_earth(me,ids,1)
	check_eq(result["error"],"","完整支付206改造并冻结载荷名册")
	check(not me.has_starship(),"工程未完不能提前获得第二锚点")
	var project: Dictionary = me.pending[0]
	check_eq(project["earth_roster"],ids,"只携带选中设施")
	WorkOrder.advance(project,100.0)
	s._finish_pending(me,0.0)
	var earth := me.starship()
	check(earth != null,"完工后生成移动本体")
	if earth == null:
		return
	check_eq([earth.id,earth.max_hp(),earth.carried_rocky],[anchor,30,1],"沿用原锚点永久ID，30HP，携带一颗类地天体")
	check(me.colonies.is_empty(),"没有复制原母星锚点")
	check_eq([s.map.star_at(at),s.map.rocky[at]],[StarMap.Star.SINGLE,1],"外部恒星和未选择天体留在原地")
	check_eq(s.neutral_assets.size(),2,"未带走的矿船和戴森球保持实体记录")
	check_eq(EarthTransform.gross(me,earth)["actual"],[1.0,2.0],"只带走一颗类地裂变与选中矿船收入")
	check_eq(Economy.plan(s,me)["net"],[-1.0,0.0],"地球2E2M维护仍完整支付，外部恒星/戴森球不供能")
	check_eq(Information.scan_source(s,me)["id"],anchor,"扫描器跟随原母星移动本体")
	check(s.build_error(me,"starship",me.home)!="","流浪地球与普通星舰不能同时新建")
	earth.pos = Vector3(2,0,0)
	check_eq(Signals.entity(s,0,miner["id"])["pos"],earth.pos,"携带设施真实位置跟随本体")
	s._destroy(me,earth,"测试损毁")
	check(me.assets.is_empty(),"移动本体摧毁时不留下幽灵携带收入")
	check_eq(s.neutral_assets.size(),2,"本体损毁不抹去原地外部设施")


## 规则：调度（派出和行动），自身降维
func test_v01_earth_carried_entities_need_their_own_ready() -> void:
	var s := earth_match()
	var me := s.human()
	var miner: Dictionary = Assets.at(me,"miner",me.home)[0]
	check_eq(s.start_earth(me,[miner["id"]],1)["error"],"","选择一艘携带矿船")
	WorkOrder.advance(me.pending[0],100.0)
	s._finish_pending(me,0.0)
	var earth := me.starship()
	if earth == null:
		check(false,"流浪地球应已完工")
		return
	earth.ready["3>2"] = {"at":0.0,"fraction":0.75,"automatic":true,"plan":-1}
	s.clock = 1.0
	SpaceEvents.convert_cell(s,earth.cell())
	check(not earth.dead and earth.entity_dim==2,"本体有ready能跨越前沿")
	check(Assets.get_id(me,miner["id"]).is_empty(),"未在名册获得ready的携带矿船不能借本体资格幸存")
	check_eq(EarthTransform.gross(me,earth)["actual"],[0.6,0.0],"本体独立Q生效且被毁矿船停止收入")


## 规则：调度（派出和行动）
func test_v01_earth_roster_rejects_external_or_duplicate_ids() -> void:
	var s := earth_match()
	var me := s.human()
	var miner: Dictionary = Assets.at(me,"miner",me.home)[0]
	var dyson: Dictionary = Assets.at(me,"dyson",me.home)[0]
	check(s.start_earth(me,[dyson["id"]],1)["error"]!="","外部戴森球不能随本体带走")
	check(s.start_earth(me,[miner["id"],miner["id"]],1)["error"]!="","名册永久ID不得重复")
	check(s.start_earth(me,[miner["id"]],3)["error"]!="","不能创造不存在的类地天体")
	check_eq([me.energy,me.mineral,me.actions_left],[1000.0,1000.0,Balance.ACTION_BASE],"全部非法请求均无支付副作用")
	var grain := Ship.make(Ship.GRAIN,Vector3.ZERO,s.next_id())
	s._destroy(null,grain,"隐藏光粒")
	check(grain.dead,"无文明所有者的隐藏单位也可正常移除")
