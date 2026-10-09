extends SceneTree
const State := preload("res://rules/r4/state.gd")
const Space := preload("res://rules/r4/space.gd")
const Sim := preload("res://rules/r4/simulation.gd")
const Combat := preload("res://rules/r4/combat.gd")
const Commands := preload("res://rules/r4/commands.gd")
const Replay := preload("res://rules/r4/replay.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _initialize() -> void:
	contact_geometry()
	paid_and_optional()
	rescue()
	remap_and_signals()
	terminal_and_combat()
	serialization()
	print(JSON.stringify({"suite":"r4_boundary_regressions","checks":checks,"failure_count":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func contact_geometry() -> void:
	var a := {"from":Vector3.ZERO,"to":Vector3(2,0,0),"velocity":Vector3.ZERO,"acceleration":Vector3(4,0,0),"accelerating":1.0}
	var b := {"from":Vector3(1,0,0),"to":Vector3(1,0,0)}
	var hit := Space.accelerated_contact(a,b,1.0,0.01)
	check(absf(hit-sqrt(0.99/2.0))<0.000002,"accelerated sweep finds first crossing with no endpoint overlap")
	var miss := {"from":Vector3(1,0.02,0),"to":Vector3(1,0.02,0)}
	check(Space.accelerated_contact(a,miss,1.0,0.01)<0.0,"broad-phase inflation is not a false physical hit")
	var s=State.new(1,"C",2)
	var h: Dictionary = s.entities[s.civs[0].home]
	var transport=s.create_entity(1,"transport",h.cell)
	transport.pos=h.pos-Vector3(0.02,0,0)
	transport.moving=true
	transport.direction=Vector3.RIGHT
	transport.speed=0.08
	transport.target=h.pos+Vector3.RIGHT
	Sim.advance(s,0.5)
	check(not transport.alive and s.now>0.49,"contact boundary makes positive time progress and destroys hostile transport")

func paid_and_optional() -> void:
	var s=State.new(2,"C",2)
	var c: Dictionary = s.civs[0]
	var h: Dictionary = s.entities[c.home]
	for id in ["005","108","205","110","206"]: c.techs[id]=true
	c.ledger.stock=Vector2i(100000,100000)
	check(s.action_error(0,{"kind":"build","item":"transport","modules":[],"host":h.id})!="","015 still required independently of205")
	c.techs["015"]=true
	check(s.action_error(0,{"kind":"build","item":"transport","modules":[],"host":h.id})=="","205 research leaves bare rescue transport selectable")
	check(s.action_error(0,{"kind":"build","item":"transport","modules":["108"],"host":h.id})!="","108 module does not spread to ineligible hull")
	check(s.action_error(0,{"kind":"build","item":"battleship","modules":["108","108"],"host":h.id})!="","duplicate paid modules rejected")
	check(s.action_error(0,{"kind":"build","item":"wandering_earth","modules":["205"],"host":h.id})!="","206 cannot obtain205 warp")
	var before: Vector2i = c.ledger.stock
	var paid: Dictionary = s.submit(0,{"kind":"build","item":"battleship","modules":["108","205"],"host":h.id})
	var expected: Vector2i = s.config.price("units","battleship")+s.config.price("ship_modules","108")+s.config.price("ship_modules","205")
	check(paid.error=="" and before-c.ledger.stock==expected,"hull and selected modules are fully paid once")
	s.progress_projects(0.5)
	var refund: Vector2i = c.ledger.projects[paid.project].refundable
	before=c.ledger.stock
	s.submit(0,{"kind":"cancel","project":paid.project})
	check(c.ledger.stock-before==refund and refund.x<expected.x,"cancel refunds only unconsumed costs")
	c.ap=2
	paid=s.submit(0,{"kind":"build","item":"probe_basic","host":h.id})
	before=c.ledger.stock
	s.destroy_entity(h.id,"test")
	check(c.ledger.stock==before and c.ledger.projects.is_empty(),"host destruction loses escrow with no refund")
	# 3D reference output and real low-dimensional cash use independent factors.
	s=State.new(2,"C",2)
	h=s.entities[s.civs[0].home]
	s.space.cells[h.cell].rocky=1
	for i in 5: s.create_entity(0,"miner_advanced",h.cell,Vector2i.ZERO,[],h.id).dim=1
	h.dim=1
	var finance: Dictionary = s.reference_and_income(0,1.0,true)
	check(absf(s.civs[0].reference_net.x-20.0)<0.001 and absf(s.civs[0].net.x-7.2)<0.001,"gates use nominal online output while spendable cash losesQ")

func rescue() -> void:
	var s=State.new(3,"C",2)
	var c: Dictionary = s.civs[0]
	var h: Dictionary = s.entities[c.home]
	h.kind="colony"
	h.dim=1
	h.online=false
	h.forced_dormant=true
	c.techs["015"]=true
	c.ledger.stock=Vector2i.ZERO
	s.space.cells[h.cell].rocky=0
	s.space.cells[h.cell].stars=0
	s.remember(0,h)
	for turn in 15:
		var resource := "M" if c.ledger.stock.x<4000 else "E"
		check(s.submit(0,{"kind":"emergency","host":h.id,"resource":resource}).error=="","dormant emergency %d accepted"%turn)
		s.end_round(false)
	check(c.ledger.stock==Vector2i(4320,1080),"1D zero-start bare transport funding takes15 single-resource actions")
	check(s.submit(0,{"kind":"build","item":"transport","host":h.id}).error=="","dormant rescue pays bare transport in full")
	for turn in 6: s.end_round(false)
	check(s.owned_entities(0,"transport").is_empty(),"six dormant build rounds do not finish three work at0.45")
	s.end_round(false)
	check(s.round_index==22 and s.owned_entities(0,"transport").size()==1,"15funding plus7construction=22; no claim of colony recovery")
	check(not c.techs.has("109") and s.anchors(0).size()==1,"rescue fixture does not award colony technology or another anchor")

func remap_and_signals() -> void:
	var s=State.new(4,"C",2)
	var h: Dictionary = s.entities[s.civs[0].home]
	var remote=s.create_entity(0,"colony",h.cell)
	remote.pos=h.pos+Vector3.RIGHT
	s.remember(0,remote)
	s.civs[0].ledger.stock=Vector2i.ZERO
	s.submit(0,{"kind":"emergency","host":remote.id,"resource":"M"})
	Sim.move_messages(s,0.5)
	s.now=0.5
	Sim.deliver_messages(s)
	check(s.civs[0].ledger.stock==Vector2i.ZERO,"remote economic command cannot arrive faster than light")
	Sim.move_messages(s,0.5)
	s.now=1.0
	Sim.deliver_messages(s)
	check(s.civs[0].ledger.stock==Vector2i(1000,0),"remote economic command pays only after physical arrival")
	h.ready["3"]={"prepared_at":0.0,"auto":false,"emergency":true}
	s.space.cells[h.cell].dim=2
	Sim.apply_space_contacts(s)
	check(not h.alive,"manual-only preparation is not silently auto executed")
	s=State.new(5,"C",2)
	h=s.entities[s.civs[0].home]
	var echo=s.send_message(0,"sensor_report",h.pos+Vector3(0.0000005,0,0),h.id,{"cells":[],"entities":[],"source":h.id,"t_observed":0.0})
	Sim.advance(s,0.01)
	check(s.messages.is_empty(),"float32 endpoint cannot trap a message in epsilon steps")
	var historical := {"pos":h.pos,"epoch":0}
	for cell in s.space.cells: cell.dim=2
	Sim.remap_world(s)
	check(s.observation_position(historical).is_equal_approx(h.pos),"historical position can be displayed in next geometry without rewriting epoch")
	check(historical.epoch==0,"historical observation keeps source epoch")

func terminal_and_combat() -> void:
	var s=State.new(6,"C",2)
	var a: Dictionary = s.entities[s.civs[0].home]
	var b: Dictionary = s.entities[s.civs[1].home]
	var attacker=s.create_entity(0,"battleship",b.cell,Vector2i.ZERO,["011"])
	attacker.pos=b.pos+Vector3(0.1,0,0)
	attacker["local_seen"]={b.id:b.duplicate(true)}
	attacker.local_seen[b.id]["t_observed"]=0.0
	attacker.local_seen[b.id]["epoch"]=0
	s.civs[0].ledger.stock=Vector2i(100000,100000)
	s.space.cells[b.cell].gas=1
	s.create_entity(1,"bunker",b.cell,Vector2i.ZERO,[],b.id)
	var stars: int = s.space.cells[b.cell].stars
	for round_id in 3:
		s.round_index=round_id
		Sim.refresh_tactical(s)
		Combat.reserve(s)
		Sim.occupation(s,attacker,1.0)
		s.civs[0].ledger.release_all_shots()
	check(not b.alive and s.space.cells[b.cell].owner<0,"three paid uncontested occupation rounds defeat even a bunker")
	check(s.space.cells[b.cell].stars==stars,"occupation does not erase celestial bodies")
	s.check_terminal()
	check(s.winners==[0],"only surviving civilization wins after real anchor loss")
	s=State.new(7,"C",2)
	a=s.entities[s.civs[0].home]
	var lifeboat=s.create_entity(0,"transport",a.cell)
	s.destroy_entity(a.id,"test")
	s.check_terminal()
	check(lifeboat.alive and not s.civs[0].alive,"transport does not postpone elimination after last anchor dies")
	check(not Combat.eligible("104",{"kind":"transport"}) and Combat.eligible("104",{"kind":"wandering_earth"}),"104 target set excludes transport and includes206")

func serialization() -> void:
	var s=State.new(8,"C",5)
	for turn in 12: s.end_round()
	var initial_hash: String = s.state_hash()
	var clone=State.from_snapshot(s.snapshot())
	check(clone!=null and clone.state_hash()==initial_hash,"full snapshot restores all simulation state")
	check(Replay.save("user://boundary.r4save",s)==OK,"isolated save succeeds")
	var loaded: Dictionary = Replay.read("user://boundary.r4save")
	check(loaded.error=="" and loaded.state.state_hash()==initial_hash,"saved state verifies byte-derived canonical hash")
	var history: Array = s.history.duplicate(true)
	var result: Dictionary = Replay.from_commands({"rules":"r4","seed":8,"profile":"C","config":s.config.digest(),"rounds":12,"history":history,"final_hash":initial_hash})
	check(result.error=="","recorded paid actions replay to exact complete state")
	s.end_round()
	if clone!=null: clone.end_round()
	check(clone!=null and clone.state_hash()==s.state_hash(),"restored state continues deterministically")
	check(Replay.from_commands({"rules":"legacy_v2"}).error!="","legacy records rejected rather than silently reinterpreted")
