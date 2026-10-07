extends RefCounted
## 规则测试的共同底子：check、check_eq，和摆测试局面用的小工具。
## tests/rules/ 下每个 test_*.gd 都继承它；运行器（tests/run_tests.gd）会填上 results。

## 记结果的对象（tests/test_log.gd），运行器填上
var results


func check(ok: bool, what: String) -> void:
	results.check(ok, what)


## 比较两个值，不一样时失败信息里写出实际值和期望值。
func check_eq(actual, expected, what: String) -> void:
	results.check_eq(actual, expected, what)


# ---------- 摆局面的小工具 ----------

## 空星图上手动放星系，方便控制测试条件。
func _map_with(cells: Dictionary) -> StarMap:
	var m := StarMap.new()
	for c in cells:
		m.stars[c] = cells[c]
	return m


## 两个文明：「你」在 (0,0,0)，「AI」在给定位置。两边都不自动行动（AI 测试再打开）。
func _two_civs(ai_home: Vector3i) -> GameState:
	var s := GameState.new()
	s.map = _map_with({Vector3i.ZERO: StarMap.Star.SINGLE, ai_home: StarMap.Star.SINGLE})
	s.system_cells = [Vector3i.ZERO, ai_home]
	s.civs.append(Civ.new("你", false, Vector3i.ZERO))
	var ai := Civ.new("AI", false, ai_home)
	s.civs.append(ai)
	for civ in s.civs:
		civ.energy = 100
		civ.mineral = 100
		s.start_turn(civ)
	return s


func _set_star(s: GameState, c: Vector3i, star: int) -> void:
	s.map.stars[c] = star
	if not s.system_cells.has(c):
		s.system_cells.append(c)


## 在星图上放一个宜居星系。
func _set_habitable(s: GameState, c: Vector3i, star: int) -> void:
	_set_star(s, c, star)
	s.map.habitable[c] = true
	s.map.rocky[c] = 1


func _give(civ: Civ, ids: Array) -> void:
	for id in ids:
		civ.techs[id] = true


## 造好一个单位并直接放到 pos，朝 dir 飞（测试用，不花资源）。
func _ship(s: GameState, civ: Civ, kind: String, pos: Vector3, dir := Vector3.ZERO) -> Ship:
	var sh := Ship.make(kind, pos, s.next_id())
	sh.docked = dir == Vector3.ZERO
	sh.direction = dir.normalized()
	civ.ships.append(sh)
	return sh


## 直接开放 I 到 tier 级（测试用，不管条件）。
func _open_tiers(civ: Civ, tier: int) -> void:
	for t in range(1, tier + 1):
		civ.set_tier_turn(t, 0)


func _turns(s: GameState, n: int) -> void:
	for i in n:
		s.end_turn()


## 三个文明：你在 (0,0,0)，AI 在 (9,9,9)，第三方在 (9,0,0)。
func _three_civs() -> GameState:
	var s := _two_civs(Vector3i(9, 9, 9))
	var third := Civ.new("第三方", false, Vector3i(9, 0, 0))
	_set_star(s, third.home, StarMap.Star.SINGLE)
	s.civs.append(third)
	s.start_turn(third)
	return s


## 测试里改过的数值，测完换回来。
func _restore_balance(values: Dictionary) -> void:
	var r := Replay.new()
	r.balance = values
	r.apply_balance()
