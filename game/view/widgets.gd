extends RefCounted
## 面板和叠加层共用的小控件：标题、提示文字、方块按钮、表格等。都是静态函数，只负责搭控件、设样式。

## 右侧面板宽度。星图的相机和点选、叠加层的提示都要让开它。
const PANEL_WIDTH := 400


## 只解释公开船型参数；不查询远端介质或舰船的隐藏实际状态。
static func ship_speed_tip(kind: String) -> String:
	if kind not in [Ship.PROBE,Ship.NUCLEAR_PROBE,Ship.COLONY,Ship.DEVOURER]:
		return ""
	var ship := Ship.make(kind,Vector3.ZERO,-1)
	var top := "最高为当地光速的 %s%%" % number(ship.max_speed*100.0) if Kinematics.uses_relative_speed(ship) else "最高 %s 光年/年" % number(ship.max_speed)
	var ramp := "派出后立即匀速飞行" if ship.accel==0.0 else "从静止加速 %s 年达到普通上限" % number(ship.max_speed/ship.accel)
	var tip := "普通航行：%s；%s。" % [top,ramp]
	if Kinematics.uses_relative_speed(ship):
		tip += "\n降低维度或进入黑域时，最高速度和加速度同步降低；自身维度的光速也会限制航行。"
	if kind in [Ship.COLONY,Ship.DEVOURER]:
		tip += "\n选装曲率引擎后，己方星系视野外按原曲率规则航行。"
	return tip


## 蓝色的小标题。
static func title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	return l


## 会自动换行的浅色小字提示。
static func hint_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	l.add_theme_font_size_override("font_size", 13)
	return l


## 灰色的小字，用作表单左边的说明。
static func dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	return l


## 一页的内容：竖着排，间距统一。
static func page_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	return box


## 方块按钮排成的格子。
static func tile_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## 一页的外框：可以上下滚动，右边留出滚动条的位置。
static func scroll_page(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 4)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(content)
	return scroll


## 一个方块按钮：上面一个大图标，下面是名字和花费。花费的标签存在按钮的 "cost" 元数据里，刷新时改文字。
## 按钮的高度跟着里面三行字走（字体不同时行高也不同，比如网页版带的字体），字不会超出边框。
static func tile(icon: String, name: String, cost: String) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(col)
	var fit := func(): button.custom_minimum_size.y = col.get_combined_minimum_size().y + 4
	col.minimum_size_changed.connect(fit)
	col.visibility_changed.connect(fit)
	button.ready.connect(fit)
	for spec in [[icon, 20, Color.WHITE], [name, 13, Color.WHITE], [cost, 12, Color(0.75, 0.75, 0.8)]]:
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.clip_text = spec[1] != 20
		if spec[1] == 20:
			# 彩色图标比文字高，往下放，上面留出空间，免得被切掉
			l.custom_minimum_size.y = 24
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		col.add_child(l)
		if spec[1] == 12:
			button.set_meta("cost", l)
	# 选中的行动：蓝色边框
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.2, 0.35, 0.6, 0.6)
	pressed.border_color = Color(0.5, 0.75, 1.0)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(4)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	return button


## 改方块按钮下面那行花费的文字。
static func set_tile_cost(button: Button, text: String) -> void:
	(button.get_meta("cost") as Label).text = text


## 可以点击展开或收起的小标题，控制 target 显示不显示。
static func fold_title(text: String, target: Control) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	var update := func(): b.text = ("▾ " if target.visible else "▸ ") + text
	update.call()
	target.visibility_changed.connect(update)
	b.pressed.connect(func(): target.visible = not target.visible; update.call())
	return b


## 两列表格：左边名字，右边数值（右对齐）。返回 [表格, {名字: 数值标签}]，刷新时改数值标签的文字。
static func stat_grid(keys: Array) -> Array:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	var values: Dictionary[String, Label] = {}
	for key in keys:
		grid.add_child(dim_label(key))
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		values[key] = value
	return [grid, values]


## 半透明圆角底色，用作卡片、资源栏的背景。
static func card_style(alpha: float, margin: float) -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, alpha)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(margin)
	return bg


## 价格 (能量, 矿石) 写成「⚡5 🪨2」，都是 0 时写「免费」。
static func cost_text(cost: Vector2i) -> String:
	var parts: Array[String] = []
	if cost.x > 0:
		parts.append("⚡%d" % cost.x)
	if cost.y > 0:
		parts.append("🪨%d" % cost.y)
	return " ".join(parts) if not parts.is_empty() else "免费"


## 保留账本的 .001 精度，整数余额不带无用的小数位。
static func number(value: float) -> String:
	var text := "%.3f" % value
	while text.ends_with("0"):
		text = text.left(-1)
	return text.trim_suffix(".")


static func signed_number(value: float) -> String:
	return ("+" if value >= 0 else "") + number(value)


## 仍保留禁用状态，但点按时把原因显示在面板，触屏用户也能读到。
static func explain_disabled(button: Button, feedback: Callable) -> void:
	button.gui_input.connect(func(event: InputEvent):
		if button.disabled and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			feedback.call(button.get_meta("disabled_reason",button.tooltip_text)))


static func order_name(kind: String) -> String:
	if Construction.NAMES.has(kind):
		return Construction.NAMES[kind]
	if Tech.ALL.has(kind):
		return Tech.ALL[kind]["name"]
	return {"reduce":"降维准备","refit":"舰船改装","miner_refit":"矿船改装","telescope":"望远镜升级"}.get(kind,"工程")


static func order_status(status: String) -> String:
	return {"sent":"开工命令传送中","working":"施工中","completed":"已完成","cancelled":"已取消","failed":"未能开工","destroyed":"施工地点已损毁"}.get(status,"等待回报")
