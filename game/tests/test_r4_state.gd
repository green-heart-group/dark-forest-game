extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ",label)

func _initialize() -> void:
	if not ResourceLoader.exists("res://rules/r4/state.gd"):
		check(false,"r4 state not implemented")
		finish()
		return
	var S = load("res://rules/r4/state.gd")
	var s = S.new(10,"C",2)
	check(s.config.catalog.size()==34,"A17 exactly34 technologies")
	check(s.civs[0].techs.size()==5,"only five specified initial technologies")
	check(s.entities.size()==2,"no free ships at start")
	var home: int = s.civs[0].home
	check(s.submit(0,{"kind":"build","item":"miner_basic","host":home}).error=="","build from valid anchor")
	check(s.civs[0].ledger.stock == Vector2i(7000,5000),"C miner paid upfront")
	check(s.owned_entities(0,"miner_basic").is_empty(),"work is not instant construction")
	s.progress_projects(1.0)
	check(s.owned_entities(0,"miner_basic").is_empty(),"one work is insufficient")
	s.progress_projects(1.0)
	check(s.owned_entities(0,"miner_basic").size()==1,"miner completes after specified work")
	check(s.submit(0,{"kind":"research","item":"008","host":home}).error!="","cannot spend future income")
	s.civs[0].ledger.stock=Vector2i(100000,100000)
	s.civs[0].ap=2
	check(s.submit(0,{"kind":"research","item":"008","host":home}).error=="","research starts paid project")
	check(not s.civs[0].techs.has("008"),"research start is distinct from acquired")
	s.progress_projects(2.0)
	check(s.civs[0].techs.has("008"),"research completed")
	check(s.owned_entities(0,"miner_basic").size()==1 and s.owned_entities(0,"miner_advanced").is_empty(),"research does not auto refit existing miner")
	s.civs[0].ap=2
	check(s.submit(0,{"kind":"research","item":"205","host":home}).error!="","tier permission cannot use stocks")
	var h = s.entities[home]
	h.dim=1
	h.online=false
	s.civs[0].ledger.stock=Vector2i.ZERO
	check(s.submit(0,{"kind":"emergency","resource":"M","host":home}).error=="","dormant emergency allowed")
	check(s.civs[0].ledger.stock==Vector2i.ZERO,"emergency command does not arrive at submission time")
	s.now=0.001
	load("res://rules/r4/simulation.gd").deliver_messages(s)
	check(s.civs[0].ledger.stock==Vector2i(360,0),"emergency yields one resource times entityQ")
	check(s.submit(0,{"kind":"emergency","resource":"E","host":home}).error!="","one emergency per empire per round")
	check(s.terminal_reason=="","one-dimensional anchor does not cause automatic victory")
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"r4_state","checks":checks,"failures":failures,"failure_count":failures.size(),"user_data_dir":OS.get_user_data_dir()}))
	quit(0 if failures.is_empty() else 1)
