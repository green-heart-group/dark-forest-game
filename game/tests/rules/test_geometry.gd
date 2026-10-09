extends "res://tests/rules/rule_suite.gd"
## 视野和打击范围用到的几何：圆锥、球、线段扫过的格子。

## 开局 9×9×9 星图的范围
const BOX := AABB(Vector3.ZERO, Vector3.ONE * StarMap.SIZE)


## 规则：视野
func test_cone_basic_shape() -> void:
	var o := Vector3(0, 0, 0)
	var cells := Geometry.cone_cells(o, Vector3(1, 0, 0), 3.0, 15.0, BOX)
	check(cells.has(Vector3i(1, 0, 0)) and cells.has(Vector3i(3, 0, 0)), "正前方在圆锥内")
	check(not cells.has(Vector3i(4, 0, 0)), "超出长度的格子不在圆锥内")
	check(not cells.has(Vector3i.ZERO), "起点自己不算")
	check(not cells.has(Vector3i(0, 3, 0)), "侧面 90 度的格子不在圆锥内")
	check(Geometry.cone_cells(o, Vector3.ZERO, 3.0, 15.0, BOX).is_empty(), "没有方向时什么都不覆盖")


## 规则：视野
func test_cone_width_follows_angle() -> void:
	var o := Vector3(5, 5, 5)
	# 张角 60 度：走到 3 格远时，离中轴线 3 × tan 30° ≈ 1.73，再加半个格子
	var wide := Geometry.cone_cells(o, Vector3(1, 0, 0), 3.0, 60.0, BOX)
	check(wide.has(Vector3i(8, 7, 5)) and wide.has(Vector3i(8, 3, 5)), "60 度的圆锥在 3 格远处宽到 2 格")
	check(not wide.has(Vector3i(8, 8, 5)), "60 度的圆锥在 3 格远处宽不到 3 格")
	# 张角 15 度：走到 2 格远时，离中轴线 2 × tan 7.5° ≈ 0.26，碰不到旁边一格
	var narrow := Geometry.cone_cells(o, Vector3(1, 0, 0), 2.0, 15.0, BOX)
	check(narrow.has(Vector3i(7, 5, 5)) and not narrow.has(Vector3i(7, 6, 5)), "15 度的圆锥在 2 格远处只有中间一格")


## 规则：光粒
func test_segment_cells_in_order() -> void:
	var cells := Geometry.segment_cells(Vector3(0.2, 0, 0), Vector3(3.2, 0, 0), 0.0, BOX)
	check(cells == [Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0)], "按由近到远排列，不含起点")
	var wide := Geometry.segment_cells(Vector3(0, 5, 5), Vector3(1, 5, 5), 0.5, BOX)
	check(wide.has(Vector3i(1, 6, 5)) and not wide.has(Vector3i(1, 6, 6)), "半径 0.5 的圆柱再加半个格子")


## 规则：二向箔
func test_wide_cylinder_any_direction() -> void:
	var o := Vector3(5, 5, 5)
	var forward := Geometry.cylinder_cells_between(o, Vector3(1, 0, 0), 1.0, 3.0, 1.0, BOX)
	var backward := Geometry.cylinder_cells_between(o, Vector3(-1, 0, 0), 1.0, 3.0, 1.0, BOX)
	var mirrored: Array[Vector3i] = []
	for c in forward:
		mirrored.append(Vector3i(10 - c.x, c.y, c.z))
	# 离起点一样远的格子谁先谁后不一定，排好再比
	mirrored.sort()
	backward.sort()
	check(forward.size() > 0 and backward == mirrored, "朝反方向的圆柱和朝正方向的左右对称")
	check(forward.has(Vector3i(7, 6, 5)) and forward.has(Vector3i(7, 4, 5)), "半径 1 的圆柱上下都宽到 1 格")
	check(not forward.has(Vector3i(6, 7, 5)) and not forward.has(Vector3i(6, 3, 5)), "半径 1 的圆柱宽不到 2 格")


## 规则：视野
func test_sphere_sizes_match_design() -> void:
	var c := Vector3(5, 5, 5)
	check(Geometry.sphere_cells(c, 1.0, BOX).size() - 1 == 6, "半径 1.0 看到 6 个相邻格子")
	check(Geometry.sphere_cells(c, 1.5, BOX).size() - 1 == 18, "半径 1.5 看到 18 格")
	check(Geometry.sphere_cells(c, 2.0, BOX).size() - 1 == 32, "半径 2.0 看到 32 格")


## 规则：视野
func test_sphere_stays_inside_map() -> void:
	var last := StarMap.SIZE - 1
	for corner in [Vector3.ZERO, Vector3(last, last, last)]:
		var cells := Geometry.sphere_cells(corner, 1.0, BOX)
		check(cells.all(func(x): return StarMap.in_bounds(x)), "星图角上的球不含星图外的格子")
		check_eq(cells.size(), 4, "星图角上半径 1.0 的球只有自己和 3 个相邻格子")


## 沿一个方向走多远出星图：和 Ship.outside 判断的边缘一致（格子边缘多算半格）。
## 规则：AI 怎么行动
func test_distance_to_edge() -> void:
	check_eq(Geometry.distance_to_edge(Vector3(8, 8, 8), Vector3(1, 0, 0), BOX), 0.5, "在角上朝外，半格就出去")
	check_eq(Geometry.distance_to_edge(Vector3(8, 8, 8), Vector3(-1, 0, 0), BOX), 8.5, "朝里面要走 8.5 格")
	var d := Vector3(-1, -1, 0).normalized()
	var t := Geometry.distance_to_edge(Vector3(8, 4, 4), d, BOX)
	check(absf(t - 4.5 * sqrt(2.0)) < 1e-4, "斜着走按先碰到的那一面算（y 先到边）")
	check(not Ship.outside(Vector3(8, 4, 4) + d * (t - 0.01), BOX) and Ship.outside(Vector3(8, 4, 4) + d * (t + 0.01), BOX),
			"走到这个距离正好出星图")
	check_eq(Geometry.distance_to_edge(Vector3(10, 4, 4), Vector3(1, 0, 0), BOX), 0.0, "已经在外面时是 0")
