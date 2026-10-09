extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL: ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var ui=load("res://view/r4_main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	check(ui.tech_box.get_child_count()==34,"all34 technology nodes have native controls")
	check(ui.buttons.has("broadcast") and ui.host_select.item_count>0,"broadcast has explicit source selection")
	check(ui.buttons.build_miner_basic.disabled==false,"initial miner action uses real affordability")
	ui.buttons.build_miner_basic.pressed.emit()
	check(ui.state.civs[0].ledger.stock.x==7000 and ui.state.civs[0].ap==1,"native button submits paid shared rule action")
	check(ui.state.civs[0].ledger.projects.size()==1,"button starts queue rather than instant asset")
	check(ui.buttons.research_205.disabled,"unopened advanced research visibly disabled")
	ui.map_view.preview=true
	ui.refresh()
	check(ui.detail.text.contains("下一维"),"map preview displays physical next-dimension distance")
	check(ui.buttons.prepare_emergency.tooltip_text!="","migration readiness shows rule rejection")
	check(not ui.state.civs[0].ai,"player slot never gets AI-only decision by interface")
	var waiting_hash: String = ui.state.state_hash()
	var waiting_time: float = ui.state.now
	await create_timer(5.0).timeout
	check(ui.state.now==waiting_time and ui.state.state_hash()==waiting_hash,"five real seconds of player thinking advance no physics AI money or events")
	await process_frame
	check(FileAccess.file_exists("user://visible-ui.json"),"visible-only UI receipt written in isolated path")
	print(JSON.stringify({"suite":"r4_native_view","checks":checks,"failure_count":failures.size(),"failures":failures,"real_os_input":false}))
	quit(0 if failures.is_empty() else 1)
