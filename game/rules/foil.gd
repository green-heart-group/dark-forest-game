class_name Foil
extends RefCounted
## 一片降维箔（二向箔 / 单向箔）：先在发射源准备几个回合，然后沿直线飞向目标坐标，每回合前进一段。
## 到达目标（最后一步直接落在目标上），或途中碰到别人的星系，就展开。

var origin: Vector3i
var target: Vector3i
## 还要准备几个回合，0 表示已经起飞
var prepare_left: int
## 已经飞过的距离
var traveled := 0.0
## false 为二向箔，true 为把二维平面压成直线的单向箔。
var to_line := false


func _init(p_origin: Vector3i, p_target: Vector3i, p_prepare: int, p_to_line := false) -> void:
	origin = p_origin
	target = p_target
	prepare_left = p_prepare
	to_line = p_to_line


func direction() -> Vector3:
	return Vector3(target - origin).normalized()


func total_distance() -> float:
	return Vector3(target - origin).length()


## 现在的位置（浮点坐标，沿直线，不取整）。
func position() -> Vector3:
	return Vector3(origin) + direction() * minf(traveled, total_distance())
