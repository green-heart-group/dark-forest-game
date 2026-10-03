extends Control
## 圆盘形的角度选择：圆周上有一个圆钮，按住沿着圆边拖动（在圆盘上任意处按下，圆钮会先跳过去）；
## 滚轮每格调 1°。
## 角度从右边（0°）开始，逆时针变大。half 为 true 时只用右半圆（-90° 到 90°），用来调俯仰角。

signal value_changed(value: float)

## 现在的角度（度）。直接赋值不会发出 value_changed（点星图时用）。
var value := 0.0:
	set(v):
		value = _clamp(v)
		queue_redraw()
## 只用右半圆
var half := false
## 圆盘边上的文字：键是角度，值是文字
var marks := {}

const RADIUS := 44.0
const COLOR_RIM := Color(0.35, 0.38, 0.48)
const COLOR_FACE := Color(0.12, 0.13, 0.18)
const COLOR_HAND := Color(0.45, 0.75, 1.0)
const COLOR_TEXT := Color(0.7, 0.72, 0.8)

var _dragging := false


func _init() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS + 40, 2 * RADIUS + 30) if half else Vector2(2 * RADIUS + 40, 2 * RADIUS + 30)


## 圆心：半圆贴着左边放，整圆放在中间。
func _center() -> Vector2:
	return Vector2(14 if half else size.x / 2.0, size.y / 2.0)


## 角度对应的画面方向（画面的 y 朝下，所以取负）。
static func _screen_dir(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(cos(r), -sin(r))


func _clamp(v: float) -> float:
	return clampf(v, -90.0, 90.0) if half else fposmod(v, 360.0)


func _draw() -> void:
	var c := _center()
	var font := get_theme_default_font()
	if half:
		var pts := PackedVector2Array([c])
		for i in 37:
			pts.append(c + _screen_dir(-90.0 + i * 5.0) * RADIUS)
		draw_colored_polygon(pts, COLOR_FACE)
		pts.remove_at(0)
		draw_polyline(pts, COLOR_RIM, 2.0, true)
		draw_line(c + Vector2(0, -RADIUS), c + Vector2(0, RADIUS), COLOR_RIM, 1.0)
	else:
		draw_circle(c, RADIUS, COLOR_FACE)
		draw_arc(c, RADIUS, 0, TAU, 64, COLOR_RIM, 2.0, true)
	# 每 15° 一个刻度，每 45° 长一点
	var lo := -90 if half else 0
	var hi := 90 if half else 345
	for a in range(lo, hi + 1, 15):
		var d := _screen_dir(a)
		var inner := RADIUS - (8.0 if a % 45 == 0 else 4.0)
		draw_line(c + d * inner, c + d * RADIUS, COLOR_RIM, 1.0)
	for a in marks:
		var text: String = marks[a]
		var p: Vector2 = c + _screen_dir(a) * (RADIUS + 9)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, p + Vector2(-w / 2.0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)
	# 圆钮在圆周上，沿着圆边拖动；圆心连一条细线到圆钮，看得出指向
	var knob := c + _screen_dir(value) * RADIUS
	draw_line(c, knob, Color(COLOR_HAND, 0.6), 2.0, true)
	draw_circle(c, 3.0, COLOR_HAND)
	draw_circle(knob, 8.0, COLOR_HAND)
	draw_circle(knob, 8.0, Color.WHITE, false, 1.5, true)
	# 度数写在圆心下方（半圆写在圆心右边一点）
	var label := "%d°" % roundi(value)
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var at := c + (Vector2(10, 22) if half else Vector2(-lw / 2.0, 24))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_point_at(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_and_emit(value + (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0))
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_point_at((event as InputEventMouseMotion).position)
		accept_event()


## 让指针指向画面上的点 pos。
func _point_at(pos: Vector2) -> void:
	var d := pos - _center()
	if d.length() < 2.0:
		return
	var deg := rad_to_deg(atan2(-d.y, d.x))
	if half and absf(deg) > 90.0:
		deg = 90.0 if deg > 0 else -90.0
	_set_and_emit(roundf(deg))


func _set_and_emit(v: float) -> void:
	var old := value
	value = v
	if value != old:
		value_changed.emit(value)
