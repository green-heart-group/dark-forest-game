extends SceneTree
# 平衡模拟：5 个文明全部由 AI 控制，打到只剩一个文明，统计多局的发展。
#   godot_console --headless --path game --script res://tools/simulate.gd
# 可以在 -- 后面临时覆盖 balance.cfg 里的数值，不用改文件；RUNS 指定局数，TURNS 指定每局最多几回合：
#   godot_console --headless --path game --script res://tools/simulate.gd -- COST_PROBE=8 RUNS=100
# 也可以先用一个数值方案（game/balance_presets/ 或个人目录里的），再单独改几个：
#   godot_console --headless --path game --script res://tools/simulate.gd -- PRESET=方案名 COST_PROBE=8
# 对局分给几个进程同时跑，最后合在一起统计，结果和一个进程跑完全一样。JOBS 指定几个进程
# （默认是 CPU 核数，最多 8 个），JOBS=1 时只用一个进程。
# PROFILE=1 时最后列出回合里每一步一共花了多少秒，用来找哪里慢（各进程加在一起）。
# FIRST 指定第一局的种子（默认 0，之后每局加 1）。OUT 是分出去的进程用的：把每局的结果写进这个文件，不打印统计。

const CHECKPOINTS := [20, 50, 100, 150]
const MAX_JOBS := 8
## 这些参数只管怎么跑，不传给分出去的进程（它们另外指定）
const RUN_KEYS := ["RUNS", "FIRST", "JOBS", "OUT"]


func _init() -> void:
	var runs := 50
	var first := 0
	var jobs := mini(OS.get_processor_count(), MAX_JOBS)
	var out := ""
	var max_turns := 200
	var profiling := false
	var changed: Array[String] = []
	# 先用数值方案（PRESET=方案名，见 game/balance_presets/），后面单独写的数值再盖过它
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("PRESET="):
			continue
		var path := BalancePresets.find(arg.trim_prefix("PRESET="))
		var preset := BalancePresets.read(path) if path != "" else {}
		if preset.is_empty():
			push_error("找不到数值方案 %s" % arg.trim_prefix("PRESET="))
			quit(1)
			return
		for w in preset["warnings"]:
			push_warning(w)
		Balance.apply(preset["values"])
		changed.append(arg)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2 or kv[0] == "PRESET":
			continue
		match kv[0]:
			"RUNS":
				runs = int(kv[1])
				continue
			"FIRST":
				first = int(kv[1])
				continue
			"JOBS":
				jobs = maxi(1, int(kv[1]))
				continue
			"OUT":
				out = kv[1]
				continue
			"TURNS":
				max_turns = int(kv[1])
				continue
			"PROFILE":
				profiling = kv[1] == "1"
				continue
		# 命令行上的值只能是数：写成整数的先当整数，数值本来是小数时 set_value 会换成小数
		var err := Balance.set_value(kv[0], int(kv[1]) if kv[1].is_valid_int() else float(kv[1]))
		if err != "":
			push_error(err)
			quit(1)
			return
		changed.append("%s=%s" % [kv[0], Balance.values()[kv[0]]])

	var started := Time.get_ticks_msec()
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(_play_all(first, runs, max_turns, profiling), "", false, true))
		file.close()
		quit()
		return
	jobs = mini(jobs, runs)
	var games := _play_all(first, runs, max_turns, profiling) if jobs <= 1 else _play_parallel(first, runs, jobs)
	if games.size() != runs:
		push_error("有进程没跑完：只拿到 %d / %d 局的结果" % [games.size(), runs])
		quit(1)
		return
	print("改动：%s；共 %d 局，每局最多 %d 回合，%d 个进程，用时 %.1f 秒" % [", ".join(changed) if changed else "无", runs,
			max_turns, maxi(jobs, 1), (Time.get_ticks_msec() - started) / 1000.0])
	_report(games, profiling)
	quit()


## 依次跑种子 first 到 first + runs - 1 的对局，每局的结果见 _play。
func _play_all(first: int, runs: int, max_turns: int, profiling: bool) -> Array:
	var games := []
	for seed_value in range(first, first + runs):
		games.append(_play(seed_value, max_turns, profiling))
	return games


## 把对局分成 jobs 份，每份开一个进程同时跑（参数照原样传过去），等全部跑完，按种子顺序合起来。
func _play_parallel(first: int, runs: int, jobs: int) -> Array:
	var passed: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if not RUN_KEYS.has(arg.split("=")[0]):
			passed.append(arg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://simulate"))
	var parts: Array[Dictionary] = []  # 每项是 {"pid", "out"}
	var start := first
	for j in jobs:
		var count := runs / jobs + (1 if j < runs % jobs else 0)
		var path := ProjectSettings.globalize_path("user://simulate/part_%d_%d.json" % [OS.get_process_id(), j])
		DirAccess.remove_absolute(path)
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/simulate.gd",
				"--", "RUNS=%d" % count, "FIRST=%d" % start, "JOBS=1", "OUT=%s" % path]
		args.append_array(passed)
		parts.append({"pid": OS.create_process(OS.get_executable_path(), args), "out": path})
		start += count
	var games := []
	for part in parts:
		while OS.is_process_running(part["pid"]):
			OS.delay_msec(100)
		var text := FileAccess.get_file_as_string(part["out"])
		DirAccess.remove_absolute(part["out"])
		var data = JSON.parse_string(text)
		if data is Array:
			games.append_array(data)
	return games


## 跑一局，返回这一局要统计的东西。键都是字符串、值是数字或数组，可以写成 JSON 给别的进程读。
func _play(seed_value: int, max_turns: int, profiling: bool) -> Dictionary:
	var s := GameState.new_game(seed_value, Balance.AI_COUNT, true)
	s.profiling = profiling
	var first_death := -1
	var alive_at := {}
	var systems_at := {}
	var energy_at := {}
	var tier_seen := {}
	## 每个文明 I、II、III 级开放的回合
	var tiers := [[], [], []]
	for t in max_turns:
		s.end_turn()
		var living := s.civs.filter(func(c): return c.alive)
		if first_death < 0 and living.size() < s.civs.size():
			first_death = s.turn
		for c in s.civs:
			for tier in [1, 2, 3]:
				if s.tier_open(c, tier) and not tier_seen.has([c, tier]):
					tier_seen[[c, tier]] = true
					tiers[tier - 1].append(s.turn)
		alive_at[s.turn] = living.size()
		var systems := 0
		var energy := 0
		for c in living:
			systems += c.colonies.size()
			energy += s.energy_income(c)
		systems_at[s.turn] = systems / float(maxi(1, living.size()))
		energy_at[s.turn] = energy / float(maxi(1, living.size()))
		if s.is_over():
			break
	var techs := {}
	for c in s.civs:
		for id in c.techs:
			techs[id] = techs.get(id, 0) + 1
	var causes := {}
	for line in s.log_lines:
		for key in ["光粒", "战舰", "二向箔", "黑域", "压缩"]:
			if line.contains(key) and (line.contains("灭亡") or line.contains("抹掉") or line.contains("压缩")):
				causes[key] = causes.get(key, 0) + 1
	var final_alive := s.civs.filter(func(c): return c.alive).size()
	var checkpoints := {}
	for k in CHECKPOINTS:
		# 提前结束的对局，之后的存活数就是结束时的数
		checkpoints[str(k)] = [alive_at.get(k, final_alive), systems_at.get(k, systems_at[s.turn]),
				energy_at.get(k, energy_at[s.turn])]
	return {
		"seed": seed_value, "checksum": s.checksum(), "turn": s.turn, "draw": s.winner == "平局", "over": s.is_over(),
		"first_death": first_death, "tiers": tiers, "checkpoints": checkpoints, "techs": techs, "causes": causes,
		"profile": s.profile,
	}


## 把各局的结果合起来打印。games 按种子顺序排。
func _report(games: Array, profiling: bool) -> void:
	var runs := games.size()
	var end_turns: Array[int] = []
	## 整张星图压成直线、平局结束的对局
	var draw_turns: Array[int] = []
	var first_death_turns: Array[int] = []
	## 每个文明 I、II、III 级开放的回合（所有局、所有文明放在一起）
	var tier_turns := {1: [] as Array[int], 2: [] as Array[int], 3: [] as Array[int]}
	## 每项科技在多少个文明里升过
	var tech_count := {}
	## 每个检查点上：活着的文明数，活着的文明平均几个星系、多少能量收入（每局先求平均，再对多局求平均）
	var alive_sum := {}
	var systems_sum := {}
	var energy_sum := {}
	var causes := {}
	var profile := {}
	## 每局最后的校验值：改代码只为提速时，前后应该完全一样
	var checksums: Array[int] = []
	for k in CHECKPOINTS:
		alive_sum[k] = 0.0
		systems_sum[k] = 0.0
		energy_sum[k] = 0.0
	for g in games:
		checksums.append(int(g["checksum"]))
		for tier in [1, 2, 3]:
			for t in g["tiers"][tier - 1]:
				tier_turns[tier].append(int(t))
		for k in CHECKPOINTS:
			var values: Array = g["checkpoints"][str(k)]
			alive_sum[k] += values[0]
			systems_sum[k] += values[1]
			energy_sum[k] += values[2]
		for id in g["techs"]:
			tech_count[id] = tech_count.get(id, 0) + int(g["techs"][id])
		for key in g["causes"]:
			causes[key] = causes.get(key, 0) + int(g["causes"][key])
		for key in g["profile"]:
			profile[key] = profile.get(key, 0) + int(g["profile"][key])
		if g["draw"]:
			draw_turns.append(int(g["turn"]))
		elif g["over"]:
			end_turns.append(int(g["turn"]))
		if g["first_death"] > 0:
			first_death_turns.append(int(g["first_death"]))

	var civ_total := runs * (Balance.AI_COUNT + 1)
	for tier in [1, 2, 3]:
		print("  可以升 %s：%d / %d 个文明，中位数第 %s 回合" % [Tech.TIER_NAMES[tier], tier_turns[tier].size(),
				civ_total, _median(tier_turns[tier])])
	print("  首个文明灭亡：%d 局，中位数第 %s 回合" % [first_death_turns.size(), _median(first_death_turns)])
	print("  非平局终局：%d 局，中位数第 %s 回合" % [end_turns.size(), _median(end_turns)])
	print("  全图压成直线、平局：%d 局，中位数第 %s 回合" % [draw_turns.size(), _median(draw_turns)])
	for k in CHECKPOINTS:
		print("  第 %d 回合平均存活文明 %.2f / 5，每个文明平均 %.1f 个星系、每回合 %.1fE" % [k, alive_sum[k] / runs,
				systems_sum[k] / runs, energy_sum[k] / runs])
	var techs := []
	for id in Tech.ALL:
		if Tech.tier(id) > 0:
			techs.append("%s %d" % [Tech.ALL[id]["name"], tech_count.get(id, 0)])
	print("  升过的文明数：%s" % "，".join(techs))
	print("  日志里的打击结果：%s" % str(causes))
	print("  所有对局的校验值：%d" % hash(checksums))
	if profiling:
		var keys := profile.keys()
		keys.sort_custom(func(a, b): return profile[a] > profile[b])
		print("  每一步用时（秒，各进程加在一起）：")
		for k in keys:
			print("    %s %.1f" % [k, profile[k] / 1e6])


func _median(values: Array[int]) -> String:
	if values.is_empty():
		return "-"
	var v := values.duplicate()
	v.sort()
	return str(v[v.size() / 2])
