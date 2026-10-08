extends "res://tests/rules/rule_suite.gd"
## 对局记录和回放、调试面板改数值、AI 的想法记录。


## 「你」照固定的做法行动（不用随机数）：能升的科技升一项，造探测器朝固定方向派出，有已知目标就派战舰。
func _scripted_player_turn(s: GameState) -> void:
	var me := s.human()
	if not me.alive or s.is_over():
		return
	for id in Tech.ALL:
		if s.research_error(me, id) == "":
			s.research(me, id)
			break
	var probe = s.build(me, "probe")["ship"]
	if probe != null:
		s.dispatch(me, probe.id, Vector3(1, (s.turn % 5) - 2, 0.5), s.turn % 2 == 0)
	if not me.known.is_empty():
		var ship = s.build(me, "warship")["ship"]
		if ship != null:
			s.dispatch(me, ship.id, Vector3(me.known.keys()[0]) - ship.pos)


## 玩家照固定做法打 n 回合（中途让 AI 接管几回合再交还）。
func _player_game(seed_value: int, n: int) -> GameState:
	var s := GameState.new_game(seed_value)
	for i in n:
		if s.is_over():
			break
		if i == 8:
			s.set_autoplay(s.human(), true)
		elif i == 12:
			s.set_autoplay(s.human(), false)
		if not s.human().is_ai:
			_scripted_player_turn(s)
		s.end_turn()
	return s


func test_same_seed_same_game() -> void:
	var a := GameState.new_game(11)
	var b := GameState.new_game(11)
	for s in [a, b]:
		s.spectator = true
		s.human().is_ai = true
		for i in 60:
			s.end_turn()
	check(a.checksums.size() == b.checksums.size() and a.checksums == b.checksums, "同一个种子的两局 AI 对局每回合都一样")
	check(a.checksum() == b.checksum(), "最后的局面一样")


func test_history_records_every_civ() -> void:
	var s := _player_game(5, 20)
	var by_civ := {}
	var wrong := 0
	for h in s.history:
		by_civ[h["civ"]] = true
		# 第 8～11 次结束回合时玩家由 AI 接管
		var by_ai: bool = h["name"] != "set_autoplay" and (h["civ"] != 0 or (h["step"] >= 8 and h["step"] < 12))
		if h["ai"] != by_ai:
			wrong += 1
	check(wrong == 0, "AI 做的操作标成 AI，玩家做的不是")
	check(by_civ.size() >= 3, "记录里有玩家和几个 AI 的操作")
	check(s.history.any(func(h): return h["civ"] == 0 and h["name"] == "dispatch"), "记录了玩家派出单位")
	check(s.history.filter(func(h): return h["name"] == "set_autoplay").size() == 2, "记录了让 AI 接管和交还")


func test_replay_rebuilds_player_game() -> void:
	var s := _player_game(7, 40)
	var r := Replay.from_state(s)
	check(r.commands.all(func(c): return not c["ai"]), "记录里只有玩家的操作")
	check(r.last_step() == s.steps, "记录的回合数和对局一样")
	var again := r.play_to(r.last_step())
	check(r.desync_step == -1, "重算没有走偏")
	check(again.checksum() == s.checksum() and again.turn == s.turn, "重算出的最后局面和原来一样")
	var mid := r.play_to(10)
	check(mid.steps == 10 and mid.checksums[9] == s.checksums[9], "可以只重算到中间某一回合")
	check(mid.human().is_ai, "第 10 回合时玩家还由 AI 接管着（接管也重做了）")
	# 从中间一步一步往后走，和原来一样
	while mid.steps < r.last_step():
		check(r.step(mid), "第 %d 回合往后走一步和原来一样" % mid.turn)
	check(mid.checksum() == s.checksum(), "一步一步走到最后，局面一样")


func test_replay_save_and_load() -> void:
	var s := _player_game(9, 25)
	var path := Replay.DIR.path_join("_test.replay")
	var r := Replay.from_state(s)
	check(r.save(path) == OK, "记录能存文件")
	var loaded := Replay.load_file(path)
	check(loaded != null and loaded.commands.size() == r.commands.size(), "能读回来")
	check(loaded.balance_diff().is_empty(), "数值没改过时没有差异")
	var again := loaded.play_to(loaded.last_step())
	check(loaded.desync_step == -1 and again.checksum() == s.checksum(), "读回来的记录重算结果一样")
	DirAccess.remove_absolute(path)
	check(Replay.load_file(Replay.DIR.path_join("_none.replay")) == null, "文件不存在时返回 null")


func test_replay_detects_changes() -> void:
	var s := _player_game(4, 20)
	var r := Replay.from_state(s)
	# 改记录中间一回合的校验值（对局可能提前结束，所以按记录长度取中间）
	var mid := r.last_step() / 2
	check(mid >= 2, "对局至少打了几回合")
	r.checksums[mid] += 1
	r.play_to(r.last_step())
	check(r.desync_step == mid + 1, "结果和记录不一样时记下是第几回合")
	r.balance["START_ENERGY"] = Balance.START_ENERGY + 1
	check(r.balance_diff().has("START_ENERGY"), "能列出记录时和现在不一样的数值")


func test_replay_truncate_branches() -> void:
	var s := _player_game(6, 30)
	var r := Replay.from_state(s)
	r.truncate(10)
	check(r.last_step() == 10 and r.commands.all(func(c): return c["step"] < 10), "第 10 回合以后的记录丢掉")
	var branch := r.play_to(10)
	check(branch.checksums[9] == s.checksums[9], "分叉点之前一样")


func test_dev_changes_are_replayed() -> void:
	var before := Replay.balance_values()
	var s := GameState.new_game(8)
	for i in 5:
		_scripted_player_turn(s)
		s.end_turn()
	var me := s.human()
	check(s.dev_set(me, "energy", 500)["error"] == "" and me.energy == 500, "可以直接改文明的能量")
	check(s.dev_balance("ENERGY_PER_STAR", Balance.ENERGY_PER_STAR + 3)["error"] == "", "可以改 balance.gd 的数值")
	check(s.dev_balance("COST_PROBE", [0, 1])["error"] == "" and Balance.COST_PROBE == [0, 1], "数组数值也能改")
	check(s.dev_tech(s.civs[1], "warship", true)["error"] == "" and s.civs[1].has_tech("warship"), "可以直接给科技")
	check(s.dev_used, "改过数值的对局有标记")
	for i in 15:
		_scripted_player_turn(s)
		s.end_turn()
	var r := Replay.from_state(s)
	check(r.balance["ENERGY_PER_STAR"] == before["ENERGY_PER_STAR"], "记录里存的是开局时的数值")
	check(r.commands.filter(func(c): return String(c["name"]).begins_with("dev_")).size() == 4, "改数值记进了记录")
	var again := r.play_to(r.last_step())
	check(r.desync_step == -1 and again.checksum() == s.checksum(), "改过数值的对局也能原样重算")
	r.play_to(3)
	check(Balance.ENERGY_PER_STAR == before["ENERGY_PER_STAR"], "退回到改数值以前，数值也回到当时的")
	_restore_balance(before)


func test_dev_set_rejects_bad_input() -> void:
	var s := _two_civs(Vector3i(5, 5, 5))
	var me := s.human()
	check(s.dev_set(me, "is_ai", true)["error"] != "" and not me.is_ai, "不能用它改由谁控制")
	check(s.dev_set(me, "no_such", 1)["error"] != "", "没有的属性改不了")
	check(s.dev_set(me, "energy", "lots")["error"] != "", "类型不对改不了")
	check(s.dev_balance("NO_SUCH", 1)["error"] != "", "没有的数值改不了")
	check(s.history.is_empty() and not s.dev_used, "改不成的不记")


func test_ai_writes_notes() -> void:
	var s := GameState.new_game(2)
	s.spectator = true
	s.human().is_ai = true
	for i in 15:
		s.end_turn()
	var notes := s.history.filter(func(h): return h["name"] == "note")
	check(notes.size() >= 15, "AI 每回合写下想法")
	check(Replay.from_state(s).commands.is_empty(), "AI 的想法和操作都不进回放记录")
	var seen := {}
	var dup := 0
	for h in notes:
		var key := [h["step"], h["civ"], h["args"][0]]
		if seen.has(key):
			dup += 1
		seen[key] = true
	check(dup == 0, "同一回合一样的想法只记一次")
