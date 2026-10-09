extends "res://tests/rules/rule_suite.gd"
## 对局记录和回放、调试面板改数值、AI 的想法记录。


func test_replay_validates_external_commands() -> void:
	var s := GameState.new_game(1)
	s.build(s.human(), "probe")
	var data := Replay.from_state(s).to_dict()
	check(Replay.valid_data(data), "有效的记录可以导入")
	for patch in [{"name": "free"}, {"step": -1}, {"civ": 999}, {"args": [42]}, {"args": ["probe", "不是坐标"]}]:
		var bad := data.duplicate(true)
		bad["commands"][0].merge(patch, true)
		check(not Replay.valid_data(bad), "损坏的命令参数在执行前被拒绝")
	var r := Replay.from_state(s)
	r.commands[0]["args"][0] = "starship"
	r.play_to(0)
	check_eq(r.desync_step, 0, "最后一个未结束回合操作失败也报告不一致")


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
	var a := GameState.new_game(11, Balance.AI_COUNT, true)
	var b := GameState.new_game(11, Balance.AI_COUNT, true)
	for s in [a, b]:
		for i in 180:
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
	var before := Balance.values()
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


## v 里（包括数组、字典里）的所有对象。
func _objects_in(v: Variant) -> Array:
	if v is Object:
		return [v]
	var found := []
	if v is Array:
		for x in v:
			found.append_array(_objects_in(x))
	elif v is Dictionary:
		for k in v:
			found.append_array(_objects_in(k))
			found.append_array(_objects_in(v[k]))
	return found


## 对象放在了 StateCopy.LINKS 以外的变量里的地方（打包时会被当成普通数据而丢掉）。
func _loose_objects(o: Object, path: String, seen := {}) -> Array:
	if seen.has(o) or o is RandomNumberGenerator:
		return []
	seen[o] = true
	var found := []
	var links: Array = StateCopy.LINKS.get(o.get_script().get_global_name(), [])
	for p in o.get_property_list():
		if not p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var inside := _objects_in(o.get(p["name"]))
		if links.has(p["name"]):
			for x in inside:
				found.append_array(_loose_objects(x, path + "." + p["name"], seen))
		elif not inside.is_empty():
			found.append(path + "." + p["name"])
	return found


func test_state_copy_is_independent() -> void:
	var s := GameState.new_game(3, Balance.AI_COUNT, true)
	for i in 40:
		s.end_turn()
	var loose := _loose_objects(s, "s")
	check(loose.is_empty(), "文明、舰船这些对象只放在 StateCopy.LINKS 列出的变量里：%s" % [loose])
	var copy := StateCopy.copy(s)
	check(copy.checksum() == s.checksum() and copy.checksums == s.checksums and copy.history == s.history,
			"复制出来的局面和原来一样")
	check(copy.civs[0] != s.civs[0] and copy.map != s.map and copy.rng != s.rng, "文明、星图、随机数都是新对象")
	var shared := 0
	for i in s.civs.size():
		for j in s.civs[i].ships.size():
			if copy.civs[i].ships[j] == s.civs[i].ships[j]:
				shared += 1
	check(shared == 0, "舰船也都是新对象")
	# 同一个文明被几处引用时，复制品里指向同一个复制出来的文明（字典的键也是）
	var other := StateCopy.copy(s)
	other.zero_winner = other.civs[1]
	other.broadcasts.append({"sender": other.civs[2], "heard": {other.civs[1]: true}})
	var again := StateCopy.copy(other)
	var b: Dictionary = again.broadcasts[-1]
	check(again.zero_winner == again.civs[1] and b["sender"] == again.civs[2] and b["heard"].has(again.civs[1]),
			"引用的文明换成复制品里的那个")
	check(again.civs[0].colonies.get_typed_builtin() == TYPE_VECTOR3I
			and again.civs[0].known.get_typed_key_builtin() == TYPE_VECTOR3I,
			"类型化的数组和字典保留类型")
	# 改复制品不影响原来的；两份各走 30 回合，每回合都一样
	var before := s.checksum()
	copy.civs[0].energy += 100
	copy.civs[1].ships.clear()
	copy.end_turn()
	check(s.checksum() == before, "改复制品、让它结束回合，原来的局面不变")
	var twin := StateCopy.copy(s)
	for i in 30:
		s.end_turn()
		twin.end_turn()
	check(twin.checksums == s.checksums, "复制品往后走和原来每回合都一样（随机数状态也复制了）")


## 玩家照固定做法打到 n 回合，第 20 回合改一次数值，最后一回合做了操作还没结束。
func _dev_game(n: int) -> GameState:
	var s := GameState.new_game(8)
	for i in n:
		if s.is_over():
			break
		if i == 20:
			s.dev_balance("ENERGY_PER_STAR", Balance.ENERGY_PER_STAR + 3)
		_scripted_player_turn(s)
		s.end_turn()
	_scripted_player_turn(s)
	return s


func test_snapshots_match_full_replay() -> void:
	var before := Balance.values()
	var s := _dev_game(60)
	var r := Replay.from_state(s)
	var snaps := Snapshots.new()
	var last := r.play_to(r.last_step(), snaps)
	check(last.checksum() == s.checksum() and r.desync_step == -1, "带缓存重算到最后和原来一样（最后一回合的操作也补上）")
	check(snaps.has(r.last_step() - 1) and snaps.has(10) and not snaps.has(11), "存了最近几回合和每 10 回合一份")
	check(snaps.size() <= Snapshots.RECENT + r.last_step() / Snapshots.EVERY + 1, "缓存份数有上限")
	check(r.begin(r.last_step() - 2, snaps).steps == r.last_step() - 2, "回退一回合直接取缓存，不用补算")
	check(r.begin(15, snaps).steps == 10, "没存的回合从不晚于它的最近一份补算")
	# 连续单步回退、长距离跳转，每次都和从开局重算一样，数值也回到当时的
	var wrong := []
	for n in [r.last_step() - 1, r.last_step() - 2, r.last_step() - 3, 35, 21, 20, 19, 4, 3, 0, r.last_step()]:
		var full := Replay.from_state(s).play_to(n)
		var energy := Balance.ENERGY_PER_STAR
		var fast := r.play_to(n, snaps)
		if fast.checksum() != full.checksum() or fast.checksums != full.checksums or Balance.ENERGY_PER_STAR != energy:
			wrong.append(n)
	check(wrong.is_empty(), "从缓存补算的局面和从开局重算的一样：%s" % [wrong])
	# 取出来的局面怎么改都不影响缓存
	var mid := r.play_to(35, snaps)
	var expected := mid.checksum()
	mid.civs[0].energy += 500
	mid.end_turn()
	check(r.play_to(35, snaps).checksum() == expected, "改了取出来的局面，缓存里的不变")
	Balance.apply(before)


func test_snapshots_ignore_other_history() -> void:
	var before := Balance.values()
	var s := _player_game(6, 30)
	var r := Replay.from_state(s)
	var snaps := Snapshots.new()
	r.play_to(r.last_step(), snaps)
	# 从第 10 回合另开一条路：之后的缓存是另一条历史，不能取
	var branch := r.play_to(10)
	branch.dev_set(branch.human(), "energy", 999)
	for i in 10:
		branch.end_turn()
	var other := Replay.from_state(branch)
	check(snaps.nearest(25, other) == 10, "另一条路只能用分叉点及以前的缓存")
	check(other.play_to(18, snaps).checksum() == Replay.from_state(branch).play_to(18).checksum(),
			"从分叉点补算出的局面是这条路的")
	snaps.drop_after(10)
	check(not snaps.has(20) and snaps.has(10), "另开一条路时丢掉分叉点以后的")
	check(snaps.nearest(25, Replay.from_state(_player_game(9, 12))) == -1, "别的种子的记录取不到")
	Balance.apply(before)


## 规则：二向箔，二维、单向著和奇异点
func test_snapshots_across_dimensions() -> void:
	var s := GameState.new_game(71, 1)
	for civ in s.civs:
		s.set_autoplay(civ, false)
		s.dev_set(civ, "energy", 2000)
		s.dev_set(civ, "reduced", true)
		s.dev_set(civ, "line_reduced", true)
		s.dev_tech(civ, "dimension", true)
	var target := Vector3i(4, 4, 4)
	if s.human().owns(target):
		target.x += 1
	s.launch_foil(s.human(), target)
	var flat_step := -1
	for i in 100:
		if s.all_flat():
			break
		s.end_turn()
		if s.dimension == 2 and flat_step < 0:
			flat_step = s.steps
	s.launch_line_foil(s.human(), Vector3i(13, 13, s.flat_plane))
	for i in 200:
		if s.all_linear():
			break
		s.end_turn()
	check(flat_step > 0 and s.dimension == 1, "对局从三维到二维再到一维")
	check(_loose_objects(s, "s").is_empty(), "降维以后对象也只放在 StateCopy.LINKS 列出的变量里")
	var r := Replay.from_state(s)
	var snaps := Snapshots.new()
	r.play_to(r.last_step(), snaps)
	var wrong := []
	for n in [r.last_step() - 1, flat_step + 1, flat_step, flat_step - 1, 2, r.last_step() - 2]:
		var got := r.play_to(n, snaps)
		if got.checksum() != s.checksums[n - 1] or got.dimension != (3 if n < flat_step else 2 if n == flat_step else got.dimension):
			wrong.append(n)
	check(wrong.is_empty(), "跨三维、二维、一维来回跳，局面都和原来那一回合一样：%s" % [wrong])


func test_dev_set_rejects_bad_input() -> void:
	var s := _two_civs(Vector3i(5, 5, 5))
	var me := s.human()
	check(s.dev_set(me, "is_ai", true)["error"] != "" and not me.is_ai, "不能用它改由谁控制")
	check(s.dev_set(me, "alive", false)["error"] != "" and me.alive, "不能用它让文明灭亡")
	check(s.dev_set(me, "home", Vector3i(1, 1, 1))["error"] != "", "不能用它搬母星系")
	check(s.dev_set(me, "no_such", 1)["error"] != "", "没有的属性改不了")
	check(s.dev_set(me, "energy", "lots")["error"] != "", "类型不对改不了")
	check(s.dev_balance("NO_SUCH", 1)["error"] != "", "没有的数值改不了")
	check(s.history.is_empty() and not s.dev_used, "改不成的不记")


func test_ai_writes_notes() -> void:
	var s := GameState.new_game(2, Balance.AI_COUNT, true)
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


## 规则：二向箔，二维、单向著和奇异点
func test_replay_across_dimension_epochs() -> void:
	var s := GameState.new_game(71, 1)
	for civ in s.civs:
		s.set_autoplay(civ, false)
		s.dev_set(civ, "energy", 2000)
		s.dev_set(civ, "reduced", true)
		s.dev_set(civ, "line_reduced", true)
		s.dev_tech(civ, "dimension", true)
	var target := Vector3i(4, 4, 4)
	if s.human().owns(target):
		target.x += 1
	check(s.launch_foil(s.human(), target)["error"] == "", "通过正式行动触发可重放的展开")
	for i in 100:
		if s.all_flat():
			break
		s.end_turn()
	check(s.all_flat() and not s.is_over(), "首次换坐标后仍是可玩的对局")
	target = Vector3i(13, 13, s.flat_plane)
	check(s.launch_line_foil(s.human(), target)["error"] == "", "二维通过正式行动再次展开")
	for i in 200:
		if s.all_linear():
			break
		s.end_turn()
	check(s.all_linear(), "两次维度展开均完成")
	var replay := Replay.from_state(s)
	var again := replay.play_to(s.steps)
	check(replay.desync_step == -1 and again.checksum() == s.checksum(), "两次原子换图及新地图行动确定性重放")
	check(again.map.stars == s.map.stars and again.map.extent == s.map.extent, "重放恢复所有星系及地图边界")


## 规则：二向箔，二维、单向著和奇异点
func test_old_replay_is_rejected_explicitly() -> void:
	var path := Replay.DIR.path_join("_old-version.replay")
	DirAccess.make_dir_recursive_absolute(Replay.DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"version": 1, "seed": 71})
	file.close()
	check(Replay.load_file(path) == null, "旧 10³ 规则记录不能被新规则静默重算")
	DirAccess.remove_absolute(path)
