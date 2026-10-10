extends PanelContainer
## 原目的地选择的只读迁维对照；样式沿用科技树、提示标签和卡片。

const Widgets:=preload("res://view/widgets.gd")
const Navigation:=preload("res://rules/navigation_preview.gd")
var main: Node
var _summary:=Widgets.hint_label("")
var _current:=Label.new()
var _next:=Label.new()
var _ranges:=Widgets.hint_label("")
var _anchors:=Widgets.hint_label("")
var _threats:=Widgets.hint_label("")
var _warnings:=Widgets.hint_label("")
var _close:=Button.new()
var _return_focus: Control


func setup(p_main: Node) -> void:
	main=p_main
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style:=Widgets.card_style(1.0,16)
	style.bg_color=Color("111722")
	add_theme_stylebox_override("panel",style)
	var box:=Widgets.page_box()
	add_child(box)
	var header:=HBoxContainer.new()
	box.add_child(header)
	var title:=Widgets.title("迁维前后地图与航程")
	title.add_theme_font_size_override("font_size",22)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close.text="返回星图 · Esc"
	_close.pressed.connect(close_preview)
	header.add_child(_close)
	var content:=Widgets.page_box()
	var scroll:=Widgets.scroll_page(content)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	content.add_child(_summary)
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	content.add_child(columns)
	for label in [_current,_next]:
		var card:=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",Widgets.card_style(0.04,10))
		columns.add_child(card)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size",15)
		card.add_child(label)
	for item in [["武器射程",_ranges],["当前已知锚点",_anchors],["已收到的威胁",_threats],["准备与预警余量（当前世界）",_warnings]]:
		content.add_child(Widgets.title(item[0]))
		content.add_child(item[1])
	content.add_child(Widgets.hint_label("航行ETA从最后已知位置沿直线估算，包含加速和已知限速；下令传播另列。下一维按实体已完成适配计算，坐标采用固定映射的参考平面，实际整体平移需等待报告；平移不影响距离。准备时长对应当前勾选的新清单，已扣情报耗时、指令、施工及准备送达；移动、未知变化和额外安全余量仍会影响结果。"))
	hide()


func open_preview() -> void:
	_return_focus=get_viewport().gui_get_focus_owner()
	if main.debug!=null:
		main.debug.pause()
	main.map._drag_button=MOUSE_BUTTON_NONE
	main.map._set_hover({})
	show()
	refresh(main.viewed())
	_close.grab_focus()


func close_preview() -> void:
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	else:
		get_viewport().gui_release_focus()


static func number(value: float) -> String:
	var text:="%.6f"%value
	while text.ends_with("0"):
		text=text.left(-1)
	return text.trim_suffix(".")


static func years(value: float) -> String:
	return "暂无可达估计" if is_inf(value) else "约 %s 年"%Widgets.number(value)


func _journey(data: Dictionary,prefix: String) -> String:
	if data.get("outside",false):
		return "%s%d维\n格距  %s ly/格\n背景光速  %s ly/年\n目的地在星图外；舰船出界会损失，无法提供可达ETA。"%[prefix,data["dim"],number(data["cell_size"]),number(data["light_speed"])]
	return "%s%d维\n格距  %s ly/格\n背景光速  %s ly/年\n起点  %s\n目的地  %s\n物理距离  %s ly\n航行 ETA  %s\n光信号 ETA  %s"%[prefix,data["dim"],number(data["cell_size"]),number(data["light_speed"]),data["from"],data["target"],number(data["distance"]),years(data["eta"]),years(data["signal_eta"])]


func refresh(me: Civ) -> void:
	if not visible:
		return
	var aim: Dictionary=main.panel.actions.preview()
	var unit: Ship=aim.get("unit")
	if unit==null and main.panel.actions._action==main.panel.actions.Action.STARSHIP:
		unit=main.state.reported_starship(me)
	var controls=main.panel.advanced
	var options: Dictionary={"roster":controls.roster(),"host":controls.selected(controls._hosts),"emergency":controls._emergency.button_pressed,"automatic":controls._automatic.button_pressed}
	var data:=Navigation.compare(main.state,me,aim["from"],aim["target"],unit.id if unit!=null else -1,options)
	_summary.text="%s · 位置观测 t=%s 年 · 目的地沿用行动页的选择。ly 为光年，1回合=1年。ETA 是预计所需时间。"%[data["unit_label"],Widgets.number(data["unit_observed"])]
	_current.text=_journey(data["current"],"当前 ")
	_next.text=_journey(data["next"],"下一维 ") if not data["next"].is_empty() else ("目标在星图外，无法比较下一维航程。" if data["outside"] else "当前为一维，没有零维逃生。")
	var ranges: Array[String]=[]
	for weapon in data["weapons"].values():
		ranges.append("%s：%s ly · 当前 %s 格"%[weapon["name"],number(weapon["range"]),number(weapon["current_cells"])]+(" / 下一维 %s 格"%number(weapon["next_cells"]) if main.state.dimension>1 else ""))
	_ranges.text="公开武器参数，物理射程不随格距缩小。实际可用装备以舰船已收状态为准。\n"+"\n".join(ranges)
	var anchors: Array[String]=[]
	for entry in data["anchors"]:
		anchors.append("#%d %s：%s → %s · 观测 t=%s / 收到 t=%s 年"%[entry["id"],entry["name"],entry["current"],entry["next"],Widgets.number(entry["t_observed"]),Widgets.number(entry["t_received"])])
	_anchors.text="\n".join(anchors) if not anchors.is_empty() else "尚未收到锚点位置。"
	var threats: Array[String]=[]
	for entry in data["threats"]:
		threats.append("%s：%s → %s · 观测 t=%s / 收到 t=%s 年（原坐标阶段%d）"%[entry["name"],entry["current"],entry["next"],Widgets.number(entry["t_observed"]),Widgets.number(entry["t_received"]),entry["epoch"]])
	_threats.text="\n".join(threats) if not threats.is_empty() else "尚未收到威胁报告；不代表航路安全。"
	var warnings: Array[String]=[]
	for entry in data["warnings"]:
		var stages: String="#%d：准备指令 %s + 施工 %s + 准备送达 %s"%[entry["id"],years(entry["command_eta"]),years(entry["work_time"]),years(entry["distribution_eta"])]
		if entry["confirmation_eta"]>0.0:
			stages+=" + 回执与主动执行 "+years(entry["confirmation_eta"])
		if is_inf(entry["danger_eta"]):
			stages+="\n尚无可估算的降维威胁轨迹，预警余量未知。"
		else:
			stages+="\n已扣情报耗时 %s 年（传播 %s 年）；危险预计 %s 后到达，准备余量 %s。"%[Widgets.number(entry["information_age"]),Widgets.number(entry["information_delay"]),years(entry["danger_eta"]),"不足" if is_inf(entry["margin"]) else Widgets.signed_number(entry["margin"])+" 年"]
		warnings.append(stages)
	var reason: String="当前无法开始准备：%s\n以下为宿主空闲、具备条件后新清单的估算。\n"%data["preparation_error"] if data["preparation_error"]!="" else ""
	_warnings.text=reason+("\n".join(warnings) if not warnings.is_empty() else "请在建造页选好执行锚点与携带清单。")
