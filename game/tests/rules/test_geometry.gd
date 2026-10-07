extends "res://tests/rules/rule_suite.gd"
## 视野和打击范围用到的几何：圆锥、球、线段扫过的格子。


## 规则：视野
func test_cone_basic_shape() -> void:
	var o := Vector3(0, 0, 0)
	var cells := Geometry.cone_cells(o, Vector3(1, 0, 0), 3.0, 15.0)
	check(cells.has(Vector3i(1, 0, 0)) and cells.has(Vector3i(3, 0, 0)), "正前方在圆锥内")
	check(not cells.has(Vector3i(4, 0, 0)), "超出长度的格子不在圆锥内")
	check(not cells.has(Vector3i.ZERO), "起点自己不算")
	check(not cells.has(Vector3i(0, 3, 0)), "侧面 90 度的格子不在圆锥内")
	check(Geometry.cone_cells(o, Vector3.ZERO, 3.0, 15.0).is_empty(), "没有方向时什么都不覆盖")


## 规则：光粒
func test_segment_cells_in_order() -> void:
	var cells := Geometry.segment_cells(Vector3(0.2, 0, 0), Vector3(3.2, 0, 0), 0.0)
	check(cells == [Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)], "按由近到远排列，不含起点")
	var wide := Geometry.segment_cells(Vector3(0, 5, 5), Vector3(1, 5, 5), 0.5)
	check(wide.has(Vector3i(1, 6, 5)) and not wide.has(Vector3i(1, 6, 6)), "半径 0.5 的圆柱再加半个格子")


## 规则：视野
func test_sphere_sizes_match_design() -> void:
	var c := Vector3(5, 5, 5)
	check(Geometry.sphere_cells(c, 1.0).size() - 1 == 6, "半径 1.0 看到 6 个相邻格子")
	check(Geometry.sphere_cells(c, 1.5).size() - 1 == 18, "半径 1.5 看到 18 格")
	check(Geometry.sphere_cells(c, 2.0).size() - 1 == 32, "半径 2.0 看到 32 格")
