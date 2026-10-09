extends Control
## r4普通游戏入口。按钮、键盘、AI共用同一个规则提交函数；界面不写游戏实体。
const State := preload("res://rules/r4/state.gd")
const Map := preload("res://view/r4_map.gd")
const Replay := preload("res://rules/r4/replay.gd")
const UNIT_NAMES := {"miner_basic":"基础矿船","miner_advanced":"高效矿船","probe_basic":"电磁探测器","probe_nuclear":"核动力探测器","battleship":"恒星级战舰","stellar_broadcaster":"恒星广播器","warning":"预警装置","bunker":"类木掩体","transport":"运输船","colony":"登陆殖民地","devourer":"吞食者","antimatter_bomb":"反物质炸弹","starship":"110星舰","dyson":"戴森球","sophon":"智子","droplet":"水滴","photoid":"光粒","dimensional_weapon":"维度载荷","wandering_earth":"流浪地球","home":"母星"}
var state
var player := 0
var selected_host := -1
var target_cell := 0
var seed_value := 0
var profile := "C"
var map_view
var stats: Label
var detail: Label
var notices: RichTextLabel
var host_select: OptionButton
var target_select: SpinBox
var tabs: TabContainer
var tech_box: VBoxContainer
var build_box: VBoxContainer
var action_box: VBoxContainer
var queue_box: VBoxContainer
var module_checks := {}
var buttons: Dictionary = {}
var input_file: FileAccess
var receipt_file := "user://visible-ui.json"
var busy := false
var screenshot_count := 0
var refresh_pending := false
var event_file: FileAccess
var turn_file: FileAccess
var first_dimensions := {"3":0}
var migration_selection := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=",true,1)
		if pair.size()!=2: continue
		if pair[0]=="SEED": seed_value=int(pair[1])
		if pair[0]=="PROFILE": profile=pair[1]
	input_file=FileAccess.open("user://native-input.jsonl",FileAccess.WRITE)
	var bg := ColorRect.new()
	bg.color=Color("101c2b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left=14; outer.offset_top=10; outer.offset_right=-14; outer.offset_bottom=-10
	add_child(outer)
	var toolbar := HBoxContainer.new()
	outer.add_child(toolbar)
	var title := Label.new()
	title.text="黑暗森林  ·  数值候选 "+profile
	title.add_theme_font_size_override("font_size",23)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	add_button(toolbar,"save","存档",save_game)
	add_button(toolbar,"load","读档",load_game)
	add_button(toolbar,"capture","截图 F12",capture)
	add_button(toolbar,"restart","同种子重开",new_game)
	stats=Label.new()
	stats.add_theme_font_size_override("font_size",18)
	outer.add_child(stats)
	var body := HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(left)
	map_view=Map.new()
	map_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	map_view.cell_selected.connect(func(id):target_cell=id; target_select.value=id; refresh())
	left.add_child(map_view)
	var map_bar := HBoxContainer.new()
	left.add_child(map_bar)
	add_button(map_bar,"preview","当前 / 下一维",func():map_view.preview=not map_view.preview; refresh())
	var target_label := Label.new(); target_label.text="目的地ID"; map_bar.add_child(target_label)
	target_select=SpinBox.new(); target_select.min_value=0; target_select.max_value=728
	target_select.custom_minimum_size.x=105
	target_select.value_changed.connect(func(value):target_cell=int(value); refresh())
	map_bar.add_child(target_select)
	detail=Label.new(); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.y=78; left.add_child(detail)
	notices=RichTextLabel.new(); notices.custom_minimum_size.y=100; notices.bbcode_enabled=false; left.add_child(notices)
	var panel := VBoxContainer.new(); panel.custom_minimum_size.x=450; body.add_child(panel)
	var source_title := Label.new(); source_title.text="执行来源 · 仅列出已收到的己方记录"; panel.add_child(source_title)
	host_select=OptionButton.new(); panel.add_child(host_select)
	host_select.item_selected.connect(func(index):selected_host=host_select.get_item_id(index); refresh())
	tabs=TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; panel.add_child(tabs)
	tech_box=page("科技34项")
	build_box=page("船坞")
	action_box=page("行动")
	queue_box=page("队列与迁维")
	tabs.tab_changed.connect(func(_index):call_deferred("write_visible_receipt"))
	var next_button := add_button(panel,"end_round","结束回合  [空格]",end_round)
	next_button.custom_minimum_size.y=46
	new_game()

func page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.name=title
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(box)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value):call_deferred("write_visible_receipt"))
	return box

func add_button(parent: Node, id: String, text: String, callback: Callable) -> Button:
	var button := Button.new(); button.name=id; button.text=text
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y=32
	button.pressed.connect(callback)
	parent.add_child(button); buttons[id]=button
	return button

func clear_page(box: VBoxContainer) -> void:
	for child in box.get_children():
		if child is Button: buttons.erase(child.name)
		box.remove_child(child); child.queue_free()

func new_game() -> void:
	event_file=FileAccess.open("user://ui-events.jsonl",FileAccess.WRITE)
	turn_file=FileAccess.open("user://ui-turns.jsonl",FileAccess.WRITE)
	first_dimensions={"3":0}
	migration_selection.clear()
	state=State.new(seed_value,profile,5)
	state.civs[player].ai=false
	state.initialize_sensors()
	selected_host=state.civs[player].home
	target_cell=state.entities[selected_host].cell
	target_select.set_value_no_signal(target_cell)
	show_notice("1回合=1年。先建设矿船，再研究与侦察。远程命令和回报都需要传播时间。")
	refresh()

func refresh() -> void:
	if state==null: return
	var c: Dictionary = state.civs[player]
	stats.text="第 %d 年   %dD / epoch %d    M %.2f  E %.2f    净产能 %.2f / %.2f    行动 %d/2    科技 %d/34"%[state.round_index,state.space.world_dim,state.space.world_epoch,c.ledger.stock.x/1000.0,c.ledger.stock.y/1000.0,c.net.x,c.net.y,c.ap,c.techs.size()]
	map_view.state=state; map_view.player=player; map_view.target=target_cell; map_view.queue_redraw()
	host_select.clear()
	var selected := 0
	var own: Array = c.seen.values().filter(func(e):return e.owner==player and e.alive and UNIT_NAMES.has(e.kind))
	own.sort_custom(func(a,b):return a.id<b.id)
	for i in own.size():
		var e: Dictionary = own[i]
		host_select.add_item("%s #%d  · %dD  · 观测年龄 %.1f"%[UNIT_NAMES.get(e.kind,e.kind),e.id,e.dim,maxf(0,state.now-e.t_observed)],e.id)
		if e.id==selected_host: selected=i
	if not own.is_empty():
		host_select.select(selected); selected_host=host_select.get_item_id(selected)
	var host: Dictionary = state.observed_owned(player,selected_host)
	if not host.is_empty():
		var at: Vector3 = state.observation_position(host)
		var destination: Vector3 = state.space.position_for(target_cell)
		var distance: float = at.distance_to(destination)
		var nd: int = maxi(1,state.space.world_dim-1)
		var next_distance: float = state.space.remap_point(at,state.space.world_dim,nd).distance_to(state.space.position_for(target_cell,nd))
		var weapons := ""
		for id in host.get("modules",[]):
			if state.config.physics.weapons.has(id): weapons+=" %s:%.2fly"%[id,state.config.physics.weapons[id].range]
		var eta := navigation_estimate(host,distance,state.space.world_dim)
		var next_eta := navigation_estimate(host,next_distance,nd)
		detail.text="至 #%d：当前格距 %.5fly，距离 %.3fly；下一维格距 %.5fly，距离 %.3fly。\n背景光时 %.2f → %.2f年；已知舰况航行估计 %s → %s年（另加命令光时；黑域/转向可能延迟）。射程%s；预警%d。"%[target_cell,state.config.spacing(state.space.world_dim),distance,state.config.spacing(nd),next_distance,distance/state.config.c(state.space.world_dim),next_distance/state.config.c(nd),eta,next_eta,weapons if weapons!="" else "：未装备",c.alerts.size()]
	else: detail.text="没有已知可用来源；等待回报或检查存续锚点。"
	refresh_tech()
	refresh_build()
	refresh_actions()
	refresh_queue()
	buttons.end_round.disabled=busy or state.terminal_reason!=""
	if state.terminal_reason!="": show_notice("对局结束：%s；获胜文明 %s"%[state.terminal_reason,str(state.winners)])
	call_deferred("write_visible_receipt")

func navigation_estimate(host: Dictionary, distance: float, dim: int) -> String:
	var elapsed: float = state.navigation_years(host,distance,dim)
	return "%.1f"%elapsed if is_finite(elapsed) else "不可达/无推力"

func request_button(box: VBoxContainer, id: String, title: String, request: Dictionary) -> void:
	request["host"]=selected_host
	var error: String = state.action_error(player,request)
	var button := add_button(box,id,title,func():submit(request))
	button.set_meta("request",request)
	button.disabled=error!="" or busy
	button.tooltip_text=error if error!="" else "提交命令；远处执行和回报均有时延"

func refresh_tech() -> void:
	clear_page(tech_box)
	var c: Dictionary = state.civs[player]
	var ids: Array = state.config.catalog.keys(); ids.sort()
	for id in ids:
		var node: Dictionary = state.config.catalog[id]
		var cost: Vector2i = state.config.price("technologies",id)
		var label: String = ("✓ " if c.techs.has(id) else "")+id+" "+node.name
		label+="  ["+node.category+"]"
		if not c.techs.has(id): label+="\n  %.0fM %.0fE · 工作%.1f · 前置 %s"%[cost.x/1000.0,cost.y/1000.0,state.config.work("technologies",id),",".join(node.dependencies)]
		request_button(tech_box,"research_"+id,label,{"kind":"research","item":id})

func refresh_build() -> void:
	var chosen: Array = []
	for id in module_checks:
		if is_instance_valid(module_checks[id]) and module_checks[id].button_pressed: chosen.append(id)
	clear_page(build_box); module_checks.clear()
	var label := Label.new(); label.text="新舰选装（裸型始终可造；舰型合法性由规则检查）"; build_box.add_child(label)
	for id in state.config.economy.ship_modules:
		var button := CheckBox.new(); button.text=id+" "+state.config.catalog[id].name
		button.button_pressed=chosen.has(id); button.disabled=not state.civs[player].techs.has(id)
		module_checks[id]=button; build_box.add_child(button)
		button.toggled.connect(func(_pressed):refresh())
	for kind in R4Config.BUILD_TECH:
		var cost: Vector2i = state.config.price("units",kind)
		var modules: Array = chosen if kind in R4Config.MOBILE else []
		var work: float = state.config.work("units",kind)
		for id in modules: cost+=state.config.price("ship_modules",id); work+=state.config.work("ship_modules",id)
		request_button(build_box,"build_"+kind,"%s · %.1fM %.1fE · 工作%.1f"%[UNIT_NAMES[kind],cost.x/1000.0,cost.y/1000.0,work],{"kind":"build","item":kind,"modules":modules})

func refresh_actions() -> void:
	clear_page(action_box)
	request_button(action_box,"move","航行至所选格 #"+str(target_cell),{"kind":"move","target_cell":target_cell})
	request_button(action_box,"broadcast","由所选来源广播目标坐标",{"kind":"broadcast","target_cell":target_cell})
	request_button(action_box,"scan","母星/206主动扫描 · 10年冷却",{"kind":"scan","target_cell":target_cell})
	request_button(action_box,"domain","向目标投送黑域核心",{"kind":"domain","target_cell":target_cell})
	request_button(action_box,"emergency_M","应急作业：只获取矿石",{"kind":"emergency","resource":"M"})
	request_button(action_box,"emergency_E","应急作业：只获取能量",{"kind":"emergency","resource":"E"})
	request_button(action_box,"radio","升级接收天线",{"kind":"radio"})
	request_button(action_box,"warning_upgrade","升级预警半径",{"kind":"warning_upgrade"})
	request_button(action_box,"miner_refit","原矿船付费升级",{"kind":"miner_refit"})
	request_button(action_box,"dormant","暂停运营：进入救援模式",{"kind":"operation","dormant":true})
	request_button(action_box,"operate","恢复运营：按库存结算维护",{"kind":"operation","dormant":false})
	for id in state.config.economy.ship_modules:
		request_button(action_box,"refit_"+id,"逐舰改装 "+id+" "+state.config.catalog[id].name,{"kind":"refit","item":id})
	for e in state.civs[player].seen.values():
		if e.owner==player and e.alive and e.kind in R4Config.AMMUNITION:
			request_button(action_box,"launch_"+str(e.id),"投放 "+UNIT_NAMES[e.kind]+" #"+str(e.id),{"kind":"bomb" if e.kind=="antimatter_bomb" else "launch","ammunition":e.id,"target_cell":target_cell})

func refresh_queue() -> void:
	clear_page(queue_box)
	var c: Dictionary = state.civs[player]
	var host: Dictionary = state.observed_owned(player,selected_host)
	var manifest: Array = []
	var emergency: Array = []
	if not host.is_empty():
		manifest.append(host.id); emergency.append(host.id)
		for e in c.seen.values():
			if e.id==host.id or e.owner!=player or not e.alive or e.dim!=host.dim or e.kind in R4Config.AMMUNITION: continue
			if migration_selection.get(e.id,true): manifest.append(e.id)
			if emergency.size()<3 and e.cell==host.cell and e.kind in ["miner_basic","miner_advanced"]: emergency.append(e.id)
	request_button(queue_box,"prepare_all","完整准备：冻结所选名册 %d 项（自动转换）"%manifest.size(),{"kind":"prepare","manifest":manifest,"auto":true,"emergency":false})
	request_button(queue_box,"prepare_emergency","紧急准备：锚点及至多2矿船（自动转换）",{"kind":"prepare","manifest":emergency,"auto":true,"emergency":true})
	request_button(queue_box,"prepare_anchor","紧急准备：仅携带所选锚点",{"kind":"prepare","manifest":[selected_host],"auto":true,"emergency":true})
	request_button(queue_box,"convert","主动执行已完成的本步准备",{"kind":"convert"})
	for e in c.seen.values():
		if e.owner!=player or not e.alive or not UNIT_NAMES.has(e.kind): continue
		var ready: Dictionary = e.get("ready",{}).get(str(e.dim),{})
		var readiness := "本步尚未确认ready"
		if not ready.is_empty(): readiness="ready时间 %.3f年"%ready.get("received_at",ready.prepared_at)
		if e.id!=selected_host and not host.is_empty() and e.dim==host.dim and e.kind not in R4Config.AMMUNITION:
			var selection := CheckBox.new(); selection.text="携带 "+UNIT_NAMES[e.kind]+" #"+str(e.id)
			selection.button_pressed=migration_selection.get(e.id,true)
			selection.toggled.connect(func(value):migration_selection[e.id]=value; refresh())
			queue_box.add_child(selection)
		var label := Label.new(); label.text="#%d %s · %s · 情报年龄%.2f年"%[e.id,UNIT_NAMES[e.kind],readiness,maxf(0,state.now-e.t_observed)]; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; queue_box.add_child(label)
	for p in c.ledger.projects.values():
		var title := "#%d %s %s · 宿主 #%d"%[p.id,p.metadata.kind,p.metadata.get("item",""),p.host]
		if p.host==state.command_anchor(player).get("id",-1): title+=" · %.2f/%.2f工作"%[p.done,p.work]
		else: title+=" · 远程执行，以回报为准"
		request_button(queue_box,"cancel_"+str(p.id),"取消 "+title,{"kind":"cancel","project":p.id})

func submit(request: Dictionary) -> void:
	if busy: return
	var result: Dictionary = state.submit(player,request)
	show_notice(result.error if result.error!="" else "命令已提交："+request.kind+" "+request.get("item",""))
	refresh()

func end_round() -> void:
	if busy or state.terminal_reason!="": return
	busy=true; buttons.end_round.disabled=true
	await get_tree().process_frame
	state.end_round()
	if not first_dimensions.has(str(state.space.world_dim)): first_dimensions[str(state.space.world_dim)]=state.round_index
	for event in state.events: event_file.store_line(JSON.stringify(event))
	event_file.flush()
	for c in state.civs:
		turn_file.store_line(JSON.stringify({"round":state.round_index,"t":state.now,"world_dim":state.space.world_dim,"civ":c.id,"alive":c.alive,"anchors":state.anchors(c.id).size(),"stock_M":c.ledger.stock.x/1000.0,"stock_E":c.ledger.stock.y/1000.0,"net_M":c.net.x,"net_E":c.net.y,"tech_count":c.techs.size(),"tier":c.permissions.keys().max(),"known_cells":c.known_cells.size(),"alerts":c.alerts.size()}))
	turn_file.flush()
	state.events.clear()
	busy=false
	refresh()
	if state.round_index%10==0 or state.terminal_reason!="": Replay.save("user://autosave.r4save",state)

func save_game() -> void:
	var error := Replay.save("user://current.r4save",state)
	show_notice("存档完成" if error==OK else "存档失败")
	if error!=OK: return
	var civilizations: Array = []
	for c in state.civs: civilizations.append({"civ":c.id,"alive":c.alive,"first":c.first,"permissions":c.permissions,"techs":c.techs.keys(),"anchors":state.anchors(c.id).size()})
	var summary := {"seed":seed_value,"profile":profile,"round":state.round_index,"t":state.now,"world_dim":state.space.world_dim,"first_dimensions":first_dimensions,"terminal_reason":state.terminal_reason,"winners":state.winners,"censored":state.terminal_reason=="","state_hash":state.state_hash(),"config_hash":state.config.digest(),"civs":civilizations,"control_mode":"native_ui","human_play_verified":false}
	var file := FileAccess.open("user://ui-summary.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"\t",true,true))

func load_game() -> void:
	var result: Dictionary = Replay.read("user://current.r4save")
	if result.error!="": show_notice(result.error); return
	state=result.state
	refresh()
	show_notice("读档完成，配置和完整状态哈希已核验。")

func show_notice(message: String) -> void:
	if notices!=null: notices.text=message

func capture() -> void:
	await RenderingServer.frame_post_draw
	screenshot_count+=1
	var path := "user://screen_%03d_round_%04d.png"%[screenshot_count,state.round_index]
	get_viewport().get_texture().get_image().save_png(path)
	show_notice("截图保存："+ProjectSettings.globalize_path(path))
	write_visible_receipt()

func _input(event: InputEvent) -> void:
	if input_file!=null and (event is InputEventMouseButton or event is InputEventKey):
		var record := {"ticks_ms":Time.get_ticks_msec(),"round":state.round_index if state!=null else -1,"event":event.as_text()}
		if event is InputEventMouseButton: record["position"]=[event.position.x,event.position.y]
		input_file.store_line(JSON.stringify(record)); input_file.flush()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F12: capture()
		if get_viewport().gui_get_focus_owner() is LineEdit:
			if event.keycode==KEY_ESCAPE: get_viewport().gui_get_focus_owner().release_focus()
			return
		if event.keycode==KEY_SPACE: end_round()
		if event.keycode>=KEY_1 and event.keycode<=KEY_4: tabs.current_tab=int(event.keycode-KEY_1)
		if event.keycode in [KEY_Q,KEY_E] and host_select.item_count>0:
			var index: int = posmod(host_select.selected+(-1 if event.keycode==KEY_Q else 1),host_select.item_count)
			host_select.select(index); selected_host=host_select.get_item_id(index); refresh()

func write_visible_receipt() -> void:
	if state==null: return
	var visible: Array = []
	for id in buttons:
		var button=buttons[id]
		if not is_instance_valid(button): continue
		var rect: Rect2 = button.get_global_rect()
		var clickable: bool = button.is_visible_in_tree() and get_viewport_rect().has_point(rect.get_center())
		var ancestor: Node = button.get_parent()
		while ancestor!=null:
			if ancestor is ScrollContainer and not ancestor.get_global_rect().has_point(rect.get_center()): clickable=false
			ancestor=ancestor.get_parent()
		visible.append({"id":id,"text":button.text,"disabled":button.disabled,"visible":button.is_visible_in_tree(),"clickable":clickable,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"reason":button.tooltip_text,"request":button.get_meta("request",{})})
	var c: Dictionary = state.civs[player]
	var file := FileAccess.open(receipt_file,FileAccess.WRITE)
	var sources: Array = []
	for e in c.seen.values():
		if e.owner==player and e.alive and UNIT_NAMES.has(e.kind):
			var pos: Vector3 = state.observation_position(e)
			sources.append({"id":e.id,"kind":e.kind,"cell":e.cell,"pos":[pos.x,pos.y,pos.z],"modules":e.get("modules",[]),"dim":e.dim,"ready":e.get("ready",{}),"moving":e.get("moving",false),"t_observed":e.t_observed})
	var known: Array = []
	for cell in c.known_cells.values():
		var pos: Vector3 = state.observation_position(cell)
		known.append({"id":cell.id,"owner":cell.owner,"pos":[pos.x,pos.y,pos.z],"rocky":cell.rocky,"habitable":cell.habitable,"t_observed":cell.t_observed})
	var data := {"seed":seed_value,"profile":profile,"round":state.round_index,"busy":busy,"terminal":state.terminal_reason,"winners":state.winners,"player":player,"ap":c.ap,"stock":[c.ledger.stock.x,c.ledger.stock.y],"techs":c.techs.keys(),"selected_host":selected_host,"sources":sources,"known_cells":known,"target_cell":target_cell,"target_rect":[target_select.global_position.x,target_select.global_position.y,target_select.size.x,target_select.size.y],"tab":tabs.current_tab,"controls":visible,"user_data_dir":OS.get_user_data_dir()}
	data["viewport_size"]=[get_viewport_rect().size.x,get_viewport_rect().size.y]
	data["window_size"]=[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y]
	data["alerts"]=c.alerts.values()
	data["world_dim"]=state.space.world_dim
	data["projects"]=c.ledger.projects.values().map(func(p):return {"host":p.host,"kind":p.metadata.kind,"item":p.metadata.get("item","")})
	file.store_string(JSON.stringify(data,"\t",true,true))
