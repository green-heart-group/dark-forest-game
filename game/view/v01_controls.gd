extends VBoxContainer
## 既有建造页中的附加操作；报价、合法性及提交统一调用规则。

const Widgets := preload("res://view/widgets.gd")
var main: Node
var state: GameState:
	get: return main.state
var modules: Dictionary = {}
var _refit := OptionButton.new()
var _refit_go := Button.new()
var _miner_go := Button.new()
var _orders := OptionButton.new()
var _cancel := Button.new()
var _hosts := OptionButton.new()
var _emergency := CheckBox.new()
var _automatic := CheckBox.new()
var _roster := VBoxContainer.new()
var _checks: Dictionary = {}
var _plans := OptionButton.new()
var _ready:=Widgets.hint_label("")
var _preview_go:=Button.new()
var _execute := Button.new()
var _e := Button.new()
var _m := Button.new()
var _earth := VBoxContainer.new()
var _earth_checks: Dictionary = {}
var _rocky := SpinBox.new()
var _maintenance := OptionButton.new()
var _stop := Button.new()
var _up := Button.new()
var _weapon := OptionButton.new()
var _policy := OptionButton.new()
var _policy_go := Button.new()


func setup(p_main: Node) -> void:
	main=p_main
	add_theme_constant_override("separation",6)
	add_child(Widgets.title("选装与改装"))
	add_child(Widgets.hint_label("研究战舰后可造基础舰体。勾选装备会增加适用舰船的造价和工期；给已有舰船加装需另付费用。"))
	var grid:=GridContainer.new()
	grid.columns=2
	add_child(grid)
	for id in Balance.MODULE_COST:
		var box:=CheckBox.new()
		box.clip_text=true
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		box.text=Tech.title(id)
		box.tooltip_text="%s · %s · 增加工期 %.1f 年（正常施工速度）"%[Tech.title(id),price(Balance.MODULE_COST[id]),Balance.MODULE_WORK[id]]
		box.toggled.connect(func(_on):main.refresh())
		modules[id]=box
		grid.add_child(box)
	add_child(_refit)
	_bind(_refit_go,"为选中舰船改装",func():return state.refit_ship(main.viewed(),selected(_refit),selected_modules()))
	_bind(_miner_go,"改装一艘当地基础矿船",func():return state.refit_miner(main.viewed(),main.panel.selected_origin()))
	add_child(Widgets.title("正在进行的工程"))
	add_child(_orders)
	_bind(_cancel,"取消选中的工程",func():return state.cancel_order(main.viewed(),selected(_orders)))
	add_child(Widgets.hint_label("只退还尚未使用的资源。远方取消和退款需等待消息往返；施工地点被毁则无法退回。"))
	add_child(Widgets.title("降维携带清单与应急生产"))
	add_child(_hosts)
	_emergency.text="紧急降维：一个据点及最多两艘矿船"
	_emergency.clip_text=true
	_emergency.tooltip_text="紧急降维只保护选中的星系或星舰，以及当地最多两艘采矿船。"
	_emergency.toggled.connect(func(_on):main.refresh())
	add_child(_emergency)
	_automatic.text="降维波抵达时自动进入低维空间"
	_automatic.clip_text=true
	_automatic.button_pressed=true
	add_child(_automatic)
	_preview_go.text="查看迁维地图与航程"
	_preview_go.custom_minimum_size.y=34
	_preview_go.pressed.connect(func():main.migration_preview.open_preview())
	add_child(_preview_go)
	add_child(_roster)
	add_child(_plans)
	add_child(_ready)
	_bind(_execute,"按已确认的清单开始降维",func():return state.execute_conversion(main.viewed(),selected(_plans)))
	var row:=HBoxContainer.new()
	add_child(row)
	_bind(_e,"应急生产能量",func():return state.emergency_work(main.viewed(),"E",selected(_hosts)),row)
	_bind(_m,"应急生产矿石",func():return state.emergency_work(main.viewed(),"M",selected(_hosts)),row)
	add_child(Widgets.title("流浪地球携带清单"))
	add_child(Widgets.hint_label("将原母星改造成可移动的家园。恒星、戴森球及未勾选的设施留在原地。"))
	_rocky.min_value=1
	_rocky.max_value=1
	_rocky.step=1
	_rocky.prefix="携带类地行星 "
	add_child(_rocky)
	add_child(_earth)
	add_child(Widgets.title("维护与武器优先级"))
	add_child(_maintenance)
	_bind(_up,"优先保留选中对象",_prioritize)
	_bind(_stop,"切换停机 / 恢复",_toggle_stopped)
	add_child(_weapon)
	for item in [["优先击毁目标","lethal"],["优先节省弹药","economy"],["优先使用次声波氢弹","special"]]:
		_policy.add_item(item[0])
		_policy.set_item_metadata(_policy.item_count-1,item[1])
	add_child(_policy)
	_bind(_policy_go,"发送武器优先级",func():return state.set_weapon_policy(main.viewed(),selected(_weapon),selected(_policy)))
	for pick in [_refit,_orders,_hosts,_plans,_maintenance,_weapon,_policy]:
		pick.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pick.clip_text=true
		pick.fit_to_longest_item=false
		pick.item_selected.connect(func(_i):main.refresh())


func _bind(button: Button,text: String,action: Callable,parent: Node=null) -> void:
	button.text=text
	button.clip_text=true
	button.custom_minimum_size.y=34
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	Widgets.explain_disabled(button,main.panel.set_feedback)
	(parent if parent!=null else self).add_child(button)
	button.pressed.connect(func():
		if main.blocked():
			return
		var result: Dictionary=action.call()
		main.panel.set_feedback(result["error"])
		main.refresh())


static func selected(pick: OptionButton) -> Variant:
	return pick.get_item_metadata(pick.selected) if pick.selected>=0 and pick.item_count>0 else -1


static func price(cost: Array) -> String:
	return "%sE / %sM"%[Widgets.number(cost[0]),Widgets.number(cost[1])]


func selected_modules(kind: String="warship") -> Array:
	var result: Array=[]
	for id in modules:
		if modules[id].button_pressed and (kind=="warship" or (id=="warp" and kind in ["colony","starship","devourer"])):
			result.append(id)
	return result


func roster() -> Array:
	return _checks.keys().filter(func(id):return _checks[id].button_pressed)


func earth_ids() -> Array:
	return _earth_checks.keys().filter(func(id):return _earth_checks[id].button_pressed)


func earth_rocky() -> int:
	return int(_rocky.value)


func prepare_error(me: Civ) -> String:
	return Conversion.error(state,me,roster(),selected(_hosts),_emergency.button_pressed)


func quote() -> Dictionary:
	return Conversion.quote(roster(),_emergency.button_pressed)


func prepare() -> Dictionary:
	return state.prepare_conversion(main.viewed(),roster(),selected(_hosts),_emergency.button_pressed,_automatic.button_pressed)


func _choices(pick: OptionButton,items: Array) -> void:
	var before=selected(pick)
	var signature:=hash(items)
	if pick.get_meta("choices",-1)==signature:
		return
	pick.set_meta("choices",signature)
	pick.clear()
	for item in items:
		pick.add_item(item[0])
		pick.set_item_metadata(pick.item_count-1,item[1])
		if typeof(item[1])==typeof(before) and item[1]==before:
			pick.select(pick.item_count-1)


func _checklist(parent: VBoxContainer,checks: Dictionary,items: Array) -> void:
	var ids: Array=items.map(func(item):return item[1])
	for id in checks.keys():
		if not ids.has(id):
			parent.remove_child(checks[id])
			checks[id].queue_free()
			checks.erase(id)
	for item in items:
		if not checks.has(item[1]):
			var box:=CheckBox.new()
			box.clip_text=true
			box.button_pressed=true
			box.toggled.connect(func(_on):main.refresh())
			checks[item[1]]=box
			parent.add_child(box)
		checks[item[1]].text=item[0]
		checks[item[1]].tooltip_text=item[0]


func _enable(button: Button,error: String) -> void:
	button.disabled=error!="" or main.blocked()
	button.tooltip_text=error
	button.set_meta("disabled_reason",error if error!="" else main.locked_reason())


func refresh(me: Civ) -> void:
	var ships: Array=[]
	var weapons: Array=[]
	var anchors: Array=[]
	var candidates: Array=[]
	var earth: Array=[]
	for asset in Knowledge.assets(state,me):
		var name: String="星系" if asset["kind"]=="anchor" else Construction.NAMES.get(asset["kind"],asset["kind"])
		var item: Array=["#%d %s %s (%dD)"%[asset["id"],name,asset["at"],asset["entity_dim"]],asset["id"]]
		if asset["kind"]=="anchor":
			anchors.append(item)
		if asset["entity_dim"]==state.dimension:
			candidates.append(item)
		if EarthTransform.known_options(state,me).has(asset["id"]):
			earth.append(item)
	for ship in Signals.reported_ships(state,me):
		var item: Array=["#%d %s %s"%[ship.id,Ship.NAMES[ship.kind],ship.cell()],ship.id]
		if ship.kind!=Ship.GRAIN and ship.entity_dim==state.dimension:
			candidates.append(item)
		if ship.kind in [Ship.STARSHIP,Ship.WANDERING_EARTH]:
			anchors.append(item)
		if ship.waiting():
			ships.append(item)
		if ship.kind==Ship.WARSHIP:
			weapons.append(item)
	_choices(_refit,ships)
	_choices(_weapon,weapons)
	_choices(_hosts,anchors)
	_checklist(_roster,_checks,candidates)
	_checklist(_earth,_earth_checks,earth)
	_rocky.max_value=maxi(1,Knowledge.snapshot(state,me,me.original_home).get("rocky",0))
	var orders: Array=[]
	for order in OrderControl.visible(state,me):
		orders.append(["#%d %s %s/%s · %s"%[order["id"],Widgets.order_name(order["kind"]),Widgets.number(WorkOrder.amount(order["done"])),Widgets.number(WorkOrder.amount(order["work"])),Widgets.order_status(order.get("status",""))],order["id"]])
	_choices(_orders,orders)
	var plans: Array=[]
	for id in me.conversions:
		var plan: Dictionary=me.conversions[id]
		plans.append(["#%d %d维→%d维 · 已确认%d项准备完成"%[id,plan["from_dim"],plan["from_dim"]-1,plan["ready_at"].size()],id])
	_choices(_plans,plans)
	var ready_lines: Array[String]=[]
	for entry in Conversion.known_ready(state,me,selected(_plans)):
		var line: String="#%d %s · 准备到达："%[entry["id"],entry["name"]]
		if entry.has("ready_at"):
			line+="t=%s 年（已确认）"%Widgets.number(entry["ready_at"])
			if entry.has("received_at"):
				line+=" · 回执 t=%s 年"%Widgets.number(entry["received_at"])
		else:
			line+="待确认，回执尚未收到"
		ready_lines.append(line)
	_ready.text="\n".join(ready_lines)
	_ready.tooltip_text="准备到达时间来自各实体的回执。工程完工、遥测或未送达的真实状态不能代替确认；不同实体时间可以不同。"
	_ready.visible=not ready_lines.is_empty()
	var packages: Array=[]
	for p in Knowledge.maintenance(state,me):
		if p["kind"] in ["anchor","ship","dyson"]:
			packages.append(["%s · %s%s"%[{"anchor":"星系","ship":"舰船","dyson":"戴森球"}[p["kind"]],p["at"]," · 已停机" if me.stopped_packages.has(p["key"]) else ""],p["key"]])
	_choices(_maintenance,packages)
	_enable(_refit_go,state.refit_error(me,selected(_refit),selected_modules()))
	_refit_go.text="改装 · "+price(GameState.refit_cost(selected_modules()))
	_enable(_miner_go,state.refit_miner_error(me,main.panel.selected_origin()))
	_enable(_cancel,state.cancel_order_error(me,selected(_orders)))
	_enable(_execute,Conversion.execute_error(state,me,selected(_plans)))
	_enable(_e,state.emergency_work_error(me,"E",selected(_hosts)))
	_enable(_m,state.emergency_work_error(me,"M",selected(_hosts)))
	_enable(_up,"没有维护对象" if packages.is_empty() else "")
	_enable(_stop,"没有维护对象" if packages.is_empty() else "")
	_enable(_policy_go,"没有已知战舰" if weapons.is_empty() else "")


func _prioritize() -> Dictionary:
	var me: Civ=main.viewed()
	var order: Array=me.maintenance_priority.duplicate()
	var key=selected(_maintenance)
	order.erase(key)
	order.push_front(key)
	return state.set_maintenance(me,order,me.stopped_packages)


func _toggle_stopped() -> Dictionary:
	var me: Civ=main.viewed()
	var stopped: Array=me.stopped_packages.duplicate()
	var key=selected(_maintenance)
	if stopped.has(key):
		stopped.erase(key)
	else:
		stopped.append(key)
	return state.set_maintenance(me,me.maintenance_priority,stopped)
