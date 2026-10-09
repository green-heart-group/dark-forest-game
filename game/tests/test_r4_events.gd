extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _initialize() -> void:
	if not ResourceLoader.exists("res://rules/r4/simulation.gd"):
		check(false,"continuous r4 simulation missing")
		finish()
		return
	var S = load("res://rules/r4/state.gd")
	var Sim = load("res://rules/r4/simulation.gd")
	var Combat = load("res://rules/r4/combat.gd")
	for reverse in [false,true]:
		var s = S.new(1,"C",2)
		var a=s.entities[s.civs[0].home]
		var b=s.entities[s.civs[1].home]
		a.kind="starship"
		b.kind="starship"
		a.hp=6
		b.hp=6
		var hits=[{"shot":1,"owner":0,"target":b.id,"damage":6.0,"kind":"physical"},{"shot":2,"owner":1,"target":a.id,"damage":6.0,"kind":"physical"}]
		if reverse: hits.reverse()
		Combat.apply_hits(s,hits)
		s.check_terminal()
		check(s.terminal_reason=="simultaneous_extinction_draw","A12 simultaneous death independent of hit list order")
	check(not Combat.eligible("104",{"kind":"transport"}),"104 cannot kill transport personnel")
	check(not Combat.eligible("104",{"kind":"devourer"}),"104 cannot kill devourer personnel")
	check(Combat.eligible("104",{"kind":"wandering_earth"}),"104 applies to206")
	var s=S.new(3,"C",2)
	var a=s.entities[s.civs[0].home]
	var b=s.entities[s.civs[1].home]
	a.pos=Vector3.ZERO
	b.pos=Vector3(1,0,0)
	var p={"cells":[],"entities":[],"source":b.id,"t_observed":0.0}
	s.send_message(0,"sensor_report",b.pos,a.id,p)
	Sim.advance(s,0.5)
	check(s.message_count()==1 and not s.events.any(func(e):return e.kind=="report_received"),"A03 report cannot travel1ly in0.5turn")
	Sim.advance(s,0.6)
	check(s.messages.is_empty(),"report arrives after physical travel")
	check(s.events.any(func(e):return e.kind=="report_received" and e.t>=1.0),"received timestamp respects c")
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"r4_events","checks":checks,"failure_count":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
