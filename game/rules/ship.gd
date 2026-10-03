class_name Ship
extends RefCounted
## 一艘在飞的飞船（战舰或殖民船）：从发射源出发，沿固定方向每回合前进一段。

var origin: Vector3i
var direction: Vector3
## 已经飞过的距离
var traveled := 0.0


func _init(p_origin: Vector3i, p_direction: Vector3) -> void:
	origin = p_origin
	direction = p_direction.normalized()


## 现在的位置（浮点坐标，沿直线，不取整）。
func position() -> Vector3:
	return Vector3(origin) + direction * traveled


## 是否已经飞出星图（离边界超过半个格子）。
func is_outside() -> bool:
	var p := position()
	var lo := -Geometry.CELL_HALF
	var hi := StarMap.SIZE - 1 + Geometry.CELL_HALF
	return p.x < lo or p.y < lo or p.z < lo or p.x > hi or p.y > hi or p.z > hi
