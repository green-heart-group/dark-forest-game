class_name Foil
extends RefCounted
## 一片降维箔（二向箔 / 单向著）：先在发射源准备几个回合，然后沿直线飞向目标坐标，每回合前进一段。
## 到达目标（最后一步直接落在目标上）就展开；单向著途中碰到别人的星系也会提前展开，二向箔不会（U2）。

var origin: Vector3
var target: Vector3i
## 还要准备几个回合，0 表示已经起飞
var prepare_left: int
## 已经飞过的距离
var traveled := 0.0
## false 为二向箔，true 为把二维平面压成直线的单向著。
var to_line := false
## 每回合飞多远
var speed := Balance.FOIL_SPEED
## 隐藏文明发的：只在目标展开，路上不停（二向箔本来就这样，只对单向著有用）
var precise := false
## V0.1 用永久载荷ID同步原绘图接口；position不再由旧准备倒计时重算。
var id := -1
var current_position := Vector3.ZERO
var position_override := false


func _init(p_origin: Vector3, p_target: Vector3i, p_prepare: int, p_to_line := false) -> void:
	origin = p_origin
	target = p_target
	prepare_left = p_prepare
	to_line = p_to_line


func direction() -> Vector3:
	return (Vector3(target) - origin).normalized()


func total_distance() -> float:
	return (Vector3(target) - origin).length()


## 现在的位置（浮点坐标，沿直线，不取整）。
func position() -> Vector3:
	if position_override:
		return current_position
	return origin + direction() * minf(traveled, total_distance())
