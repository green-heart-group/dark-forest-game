extends SceneTree
const State := preload("res://rules/r4/state.gd")
const Sim := preload("res://rules/r4/simulation.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL: ",label)
func _initialize() -> void:
	var fast=State.new(0,"C",5)
	var plain=State.new(0,"C",5); plain.plain_checks=true
	var reversed=State.new(0,"C",5)
	var unrecorded=State.new(0,"C",5); unrecorded.capture_events=false
	for turn in 30:
		fast.end_round()
		plain.end_round()
		reversed.end_round(true,[4,3,2,1,0])
		unrecorded.end_round()
		check(fast.state_hash()==plain.state_hash(),"cached and plain complete state match round%d"%(turn+1))
		check(fast.state_hash()==reversed.state_hash(),"submission permutation matches round%d"%(turn+1))
		check(fast.state_hash()==unrecorded.state_hash(),"observer on/off matches round%d"%(turn+1))
		fast.events.clear(); plain.events.clear(); reversed.events.clear()
	# Deterministic broad-phase fixture: candidate pruning must preserve all hits.
	var s=State.new(2,"C",2)
	var rng:=RandomNumberGenerator.new(); rng.seed=2048
	for i in 24:
		var e=s.create_entity(i%2,"battleship",300,Vector2i.ZERO,[])
		e.pos=Vector3(3+i/2*0.1,3,3)+Vector3(0.008 if i%2 else 0,0,0)
		e.moving=true; e.direction=Vector3.RIGHT if i%2 else Vector3.LEFT; e.speed=rng.randf_range(0.01,0.15)
	var paths: Dictionary = Sim.predict(s,0.125)
	var indexed: Array = Sim.find_contacts(s,paths,0.125)
	s.plain_checks=true
	var scanned: Array = Sim.find_contacts(s,paths,0.125)
	check(var_to_bytes(indexed)==var_to_bytes(scanned),"spatial index preserves every accelerated contact")
	# Incoming information can start income only after arrival, including in batching.
	s=State.new(3,"C",2)
	var c: Dictionary = s.civs[0]; var home: Dictionary = s.entities[c.home]
	s.space.cells[home.cell].rocky=0; s.space.cells[home.cell].stars=0; c.ledger.stock=Vector2i.ZERO; c.techs["102"]=true
	var cell := {"id":728,"stars":1,"dim":3,"was_system":true,"t_observed":0.0,"epoch":0,"pos":home.pos+Vector3.RIGHT,"owner":-1}
	s.send_message(0,"sensor_photon",cell.pos,home.id,{"cells":[cell],"entities":[],"source":home.id,"t_observed":0.0})
	Sim.advance(s,0.999)
	check(c.ledger.stock.y==0,"no spendable information income before causal arrival")
	Sim.advance(s,1.001)
	check(abs(c.ledger.stock.y-1000)<=1,"received system supplies exactly one year of energy then expires")
	var acceleration_path := {"from":Vector3(1,0,0),"to":Vector3(1.02,0,0),"velocity":Vector3.ZERO,"acceleration":Vector3(0.01,0,0),"accelerating":2.0}
	check(absf(Sim.information_intercept(Vector3.ZERO,acceleration_path,1.0,2.0)-(100.0-sqrt(9800.0)))<0.000002,"moving receiver photon intercept includes acceleration")
	check(Sim.information_intercept(Vector3.ZERO,acceleration_path,1.0,1.0)<0.0,"moving receiver cannot receive the photon at old-position light time")
	for old_expiry in [0.5,1.5]:
		s=State.new(3,"C",2); c=s.civs[0]; home=s.entities[c.home]
		s.space.cells[home.cell].rocky=0; s.space.cells[home.cell].stars=0; c.ledger.stock=Vector2i.ZERO; c.techs["102"]=true
		c.coverage[728]={"stars":1,"dim":3,"was_system":true,"expires":old_expiry,"t_observed":-1.0,"source":home.id}
		cell.pos=home.pos+Vector3.RIGHT
		s.send_message(0,"sensor_report",cell.pos,home.id,{"cells":[cell],"entities":[],"source":home.id,"t_observed":0.0})
		Sim.advance(s,2.0)
		check(abs(c.ledger.stock.y-(1500 if old_expiry<1.0 else 2000))<=1,"coverage refresh preserves gap or continuous income for expiry%.1f"%old_expiry)
	print(JSON.stringify({"suite":"r4_optimizations_and_observer","checks":checks,"failure_count":failures.size(),"failures":failures,"end_hash":fast.state_hash()}))
	quit(0 if failures.is_empty() else 1)
