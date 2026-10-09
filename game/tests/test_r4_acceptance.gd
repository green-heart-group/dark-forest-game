extends SceneTree
const State := preload("res://rules/r4/state.gd")
const Sim := preload("res://rules/r4/simulation.gd")
const Combat := preload("res://rules/r4/combat.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _initialize() -> void:
	var s=State.new(10,"C",2)
	var a: Dictionary = s.entities[s.civs[0].home]
	var b: Dictionary = s.entities[s.civs[1].home]
	# A07/A08: 完成时间严格早于接触，冻结名册与receipt永不重算。
	a.ready["3"]={"prepared_at":1.0,"received_at":1.0,"emergency":true}
	check(not s.convert_entity(a.id,1.0),"A08 completion simultaneous with contact is too late")
	check(s.convert_entity(a.id,1.1),"A08 ready before contact can convert")
	check(s.civs[0].ledger.stock==Vector2i(4000,2000),"A07 emergency receipt retains40percent")
	var miner=s.create_entity(0,"miner_basic",a.cell,Vector2i(3000,0),[],a.id)
	miner.dim=3
	miner.ready["3"]={"prepared_at":0.0,"emergency":false}
	check(s.convert_entity(miner.id,1.1),"later explicitly prepared entity allowed")
	check(s.civs[0].ledger.stock==Vector2i(4000,2000),"A07 later full prep cannot change first receipt")
	var fresh=s.create_entity(0,"miner_basic",a.cell,Vector2i(3000,0),[],a.id)
	fresh.dim=3
	s.space.cells[a.cell].dim=2
	Sim.apply_space_contacts(s)
	check(not fresh.alive,"A08 new asset not in frozen manifest is unprotected")
	# A04/A05: 原子换图保留消息、弹丸、广播和永久ID；不立即制造送达。
	s=State.new(11,"C",2)
	a=s.entities[s.civs[0].home]
	b=s.entities[s.civs[1].home]
	var message=s.send_message(0,"sensor_report",b.pos,a.id,{"cells":[],"entities":[],"source":b.id,"t_observed":0.0})
	var id: int = message.id
	Sim.advance(s,0.5)
	var traveled: float = s.snapshot().messages[0].traveled
	for cell in s.space.cells: cell.dim=2
	Sim.remap_world(s)
	check(s.space.world_dim==2 and s.space.world_epoch==1,"A04 one atomic world epoch increment")
	check(s.messages.size()==1 and s.messages[0].id==id and is_equal_approx(s.messages[0].traveled,traveled),"A04 message identity and traveled distance preserved")
	check(s.messages[0].earliest>s.now,"A03 mapping cannot retroactively deliver")
	# A10: 重叠黑域不能刷新单格硬到期。
	s=State.new(12,"C",2)
	s.space.domains.append({"id":1,"pos":Vector3.ZERO,"born":0.0,"expires":20.0,"dim":3})
	s.space.advance_domains(0.0)
	s.space.domains.append({"id":2,"pos":Vector3.ZERO,"born":10.0,"expires":30.0,"dim":3})
	s.space.advance_domains(10.0)
	s.space.advance_domains(21.0)
	check(is_equal_approx(s.space.local_factor(Vector3.ZERO,21.0),1.0),"A10 overlap expires and immunity restores propagation")
	# A13: 防御抽样由seed+shot+target确定，不受调用顺序影响。
	var roll: float = Combat.defense_roll(2,10,20,"armor")
	for i in 20: Combat.defense_roll(2,i,30,"armor")
	check(roll==Combat.defense_roll(2,10,20,"armor"),"A13 defense RNG independent of unrelated order")
	# A17: 103来源收紧，普通星舰/殖民地没有母星能力。
	s=State.new(13,"C",2)
	s.civs[0].techs["103"]=true
	s.civs[0].ledger.stock=Vector2i(100000,100000)
	a=s.entities[s.civs[0].home]
	var ship=s.create_entity(0,"starship",a.cell)
	s.remember(0,ship)
	check(s.action_error(0,{"kind":"scan","host":ship.id})!="","103 not granted to110")
	a.kind="wandering_earth"
	s.remember(0,a)
	check(s.action_error(0,{"kind":"scan","host":a.id})=="","103 survives original home conversion206")
	# A12: 反转文明提交遍历顺序，不应改变同样决策的物理终态。
	var forward=State.new(0,"C",5)
	var reverse=State.new(0,"C",5)
	for i in 20:
		forward.end_round(true,[0,1,2,3,4])
		reverse.end_round(true,[4,3,2,1,0])
	check(forward.state_hash()==reverse.state_hash(),"A12 same-seed reversed submission order hash")
	print(JSON.stringify({"suite":"r4_acceptance_partial","checks":checks,"failure_count":failures.size(),"failures":failures,
		"order_forward_hash":forward.state_hash(),"order_reverse_hash":reverse.state_hash()}))
	quit(0 if failures.is_empty() else 1)
