extends Control
## 鼠标悬停说明：限制宽度，过长自动换行。
## Godot 自带的说明框不换行，长句会横穿整个屏幕。main.gd 把这个脚本挂到界面里每个还没有脚本的控件上；
## 本身有脚本的控件（如 angle_dial.gd）在自己的 _make_custom_tooltip 里调 Tip.make()。

## 说明框里文字最宽多少（界面坐标的像素）
const MAX_WIDTH := 360.0


func _make_custom_tooltip(for_text: String) -> Object:
	return make(self, for_text)


## 做一个说明框：先按 MAX_WIDTH 断好行，再放进一个不自动换行的 Label，
## 这样 Label 的大小一开始就是对的（自动换行的 Label 要先有宽度才知道多高，弹出时会算错）。
## 底色不透明，盖在面板或星图上也看得清。
## 没有说明文字时返回隐藏的框：自己写了 _make_custom_tooltip 的控件，Godot 在文字为空时也会弹框，
## 只有返回的框是隐藏的才不弹。
static func make(from: Control, text: String) -> PanelContainer:
	var box := PanelContainer.new()
	if text.strip_edges() == "":
		box.visible = false
		return box
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.12, 0.97)
	bg.border_color = Color(0.35, 0.4, 0.55)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", bg)
	var label := Label.new()
	label.theme_type_variation = "TooltipLabel"
	var font := from.get_theme_font("font", "TooltipLabel")
	var font_size := from.get_theme_font_size("font_size", "TooltipLabel")
	label.text = "\n".join(wrap_lines(text, font, font_size, MAX_WIDTH))
	box.add_child(label)
	return box


## 把 text 断成不超过 width 宽的行。原有的换行保留，中文可以在任意两个字之间断开。
static func wrap_lines(text: String, font: Font, font_size: int, width: float) -> PackedStringArray:
	var para := TextParagraph.new()
	para.add_string(text, font, font_size)
	para.width = width
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var lines := PackedStringArray()
	for i in para.get_line_count():
		var r := para.get_line_range(i)
		lines.append(text.substr(r.x, r.y - r.x).rstrip(" \n"))
	return lines
