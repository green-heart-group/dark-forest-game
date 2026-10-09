extends SceneTree
const State := preload("res://rules/r4/state.gd")
const Sim := preload("res://rules/r4/simulation.gd")
const Combat := preload("res://rules/r4/combat.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL: ",label)
func _initialize() -> void:
	var s=State.new(20,"C",2)
	var c: Dictionary = s.civs[0]
	var home: Dictionary = s.entities[c.home]
	c.techs["206"]=true; c.ledger.stock=Vector2i(1000000,1000000)
	var mineral=s.create_entity(0,"miner_basic",home.cell,Vector2i.ZERO,[],home.id)
	var warning=s.create_entity(0,"warning",home.cell,Vector2i.ZERO,[],home.id)
	var dyson=s.create_entity(0,"dyson",home.cell,Vector2i.ZERO,[],home.id)
	var old_rocky: int = s.space.cells[home.cell].rocky
	check(s.submit(0,{"kind":"build","item":"wandering_earth","host":home.id}).error=="","206 uses paid original-home construction")
	s.progress_projects(12.0)
	check(home.kind=="wandering_earth" and home.hp==30.0,"206 completes as30HP survival anchor")
	check(s.space.cells[home.cell].rocky==old_rocky-1 and s.space.cells[home.cell].owner<0,"carried planet is not double-counted as stationary ownership")
	check(mineral.attached and mineral.host==home.id and warning.host<0 and dyson.host<0,"206 carries miners; external warning and stellar structures remain")
	var dyson_position: Vector3 = dyson.pos
	home.moving=true; home.direction=Vector3.RIGHT; home.speed=0.04; home.target=home.pos+Vector3.RIGHT
	Sim.move_paths(s,Sim.predict(s,0.1),0.1)
	check(mineral.pos.is_equal_approx(home.pos) and dyson.pos==dyson_position,"carried and external structures follow distinct trajectories")
	s.destroy_entity(home.id,"test")
	check(not mineral.alive and dyson.alive,"206 loss destroys its carried assets without teleporting/destroying external stars")
	# One stellar hit removes one star. A bunker protects its own ground
	# presence, not visiting ships or another civilization in that system.
	s=State.new(21,"C",2); home=s.entities[s.civs[1].home]
	s.space.cells[home.cell].stars=2; s.space.cells[home.cell].gas=1
	s.create_entity(1,"bunker",home.cell,Vector2i.ZERO,[],home.id)
	var first=s.create_entity(1,"dyson",home.cell,Vector2i.ZERO,[],home.id)
	var second=s.create_entity(1,"dyson",home.cell,Vector2i.ZERO,[],home.id)
	var visitor=s.create_entity(0,"starship",home.cell)
	var own_ship=s.create_entity(1,"battleship",home.cell)
	Sim.photoid_hit(s,{"owner":0,"id":100},home.cell)
	check(home.alive and s.space.cells[home.cell].owner==1 and s.space.cells[home.cell].stars==1,"bunker keeps its civilization anchor after one-star loss")
	check(first.alive and not second.alive,"one removed star destroys only its associated Dyson sphere")
	check(not visitor.alive and not own_ship.alive,"bunker grants no system-wide fleet immunity")
	# Same-time mutual personnel kills both apply and only then settle salvage.
	s=State.new(22,"C",2)
	var a=s.create_entity(0,"starship",100,Vector2i(3000,4000))
	var b=s.create_entity(1,"starship",100,Vector2i(5000,6000))
	Combat.apply_hits(s,[{"shot":1,"owner":0,"target":b.id,"damage":0.0,"kind":"personnel","weapon":"104"},{"shot":2,"owner":1,"target":a.id,"damage":0.0,"kind":"personnel","weapon":"104"}])
	check(not a.alive and not b.alive,"same-time mutually lethal crew attacks both resolve")
	check(s.civs[0].ledger.stock==Vector2i(15000,11000) and s.civs[1].ledger.stock==Vector2i(13000,9000),"mutual salvage settles actual paid hull bases after both deaths")
	# No dimensional escape past1D, and dormant survivors cannot mine0D.
	s=State.new(23,"C",2); home=s.entities[s.civs[0].home]
	home.dim=1; home.ready["1"]={"prepared_at":0.0,"emergency":true}
	check(not s.convert_entity(home.id,1.0),"no0D emergency survival")
	s.space.cells[home.cell].dim=0; s.now=1.0; Sim.apply_space_contacts(s)
	check(not home.alive,"zero-dimensional region destroys surviving anchors")
	s.check_terminal()
	check(s.winners==[1],"terminal result comes from remaining anchor, not merely1D technology")
	s=State.new(24,"C",2); home=s.entities[s.civs[0].home]
	var transmitter=s.create_entity(0,"stellar_broadcaster",home.cell,Vector2i.ZERO,[],home.id)
	var scout=s.create_entity(0,"probe_basic",home.cell)
	s.remember(0,transmitter); s.remember(0,scout)
	check(s.broadcast_capable(0,home,true) and not s.broadcast_capable(0,scout,true),"006 uses its system anchor, not an arbitrary co-located ship")
	var ship=s.create_entity(0,"battleship",home.cell,Vector2i.ZERO,["108"])
	check(s.broadcast_capable(0,ship,false),"108-equipped warship can be the explicit broadcast source")
	transmitter.alive=false
	check(not s.broadcast_capable(0,home,false) and s.broadcast_capable(0,home,true),"execution revalidates a source whose old received record is still alive")
	print(JSON.stringify({"suite":"r4_late_boundaries","checks":checks,"failure_count":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
