extends SceneTree
const State := preload("res://rules/r4/state.gd")
const Sim := preload("res://rules/r4/simulation.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL: ",label)
func _initialize() -> void:
	var measurements: Array = []
	for step in [0.125,0.0625,0.03125]:
		var s=State.new(40,"C",2)
		s.config.physics.physics_max_dt=step
		for c in s.civs: c.ledger.stock=Vector2i(1000000,1000000)
		for a in s.anchors(0): a.pos=Vector3.ZERO
		s.space.domains.append({"id":1,"owner":1,"pos":Vector3(4,4,4),"born":-4.0,"expires":20.0,"dim":3})
		var ship=s.create_entity(0,"sophon",364)
		ship.pos=Vector3(3.2,4.2,4); ship.direction=Vector3.RIGHT; ship.target=Vector3(6,4.2,4); ship.moving=true
		Sim.advance(s,2.0)
		measurements.append({"step":step,"x":ship.pos.x,"speed":ship.speed,"alive":ship.alive,"time":s.now})
	check(measurements.all(func(m):return m.alive and absf(m.time-2.0)<1e-8),"field integration makes positive time progress at all three resolutions")
	check(absf(measurements[0].x-measurements[2].x)<0.02,"field trajectory coarse-to-fine position difference below0.02ly")
	check(absf(measurements[1].x-measurements[2].x)<=absf(measurements[0].x-measurements[2].x)+0.000002,"halving the step improves the field trajectory")
	# A signal in a zero-c core waits for expiry rather than crossing it or
	# forcing the universe to stop. Front speed uses background c throughout.
	var s=State.new(41,"C",2)
	var home: Dictionary = s.entities[s.civs[0].home]
	home.pos=Vector3(4,4,5)
	s.space.domains.append({"id":1,"owner":1,"pos":Vector3(4,4,4),"born":0.0,"expires":20.0,"dim":3})
	s.send_message(0,"sensor_report",Vector3(4,4,4),home.id,{"cells":[],"entities":[],"source":home.id,"t_observed":0.0})
	Sim.advance(s,19.5)
	check(not s.events.any(func(e):return e.kind=="report_received"),"zero-c core prevents signal arrival before expiry")
	Sim.advance(s,1.6)
	check(s.events.any(func(e):return e.kind=="report_received" and e.t>=21.0-0.000002),"signal resumes after domain expiry with remaining flight time")
	for dim in [3,2,1]:
		s.space.world_dim=dim
		check(is_equal_approx(s.space.front_speed(),[0.0,0.18,0.3,0.5][dim]),"front speed uses0.5background c in%dD"%dim)
	print(JSON.stringify({"suite":"r4_time_resolution","checks":checks,"failure_count":failures.size(),"failures":failures,"field_measurements":measurements,"limit":"This convergence fixture does not certify every possible field geometry."}))
	quit(0 if failures.is_empty() else 1)
