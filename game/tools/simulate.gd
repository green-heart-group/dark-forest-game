extends SceneTree
# 平衡模拟：5 个文明全部由 AI 控制，打到只剩一个文明，统计多局的发展。
#   godot --headless --path game --script res://tools/simulate.gd
# 可以在 -- 后面临时覆盖 balance.gd 里的数值，不用改文件；RUNS 指定局数：
#   godot --headless --path game --script res://tools/simulate.gd -- COST_PROBE=8 RUNS=100

const MAX_TURNS := 100
const CHECKPOINTS := [10, 30, 60]


func _init() -> void:
	var runs := 50
	var balance: Script = load("res://rules/balance.gd")
	var changed: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "RUNS":
			runs = int(kv[1])
			continue
		var old = balance.get(kv[0])
		if old == null:
			push_error("balance.gd 里没有 %s" % kv[0])
			quit(1)
			return
		balance.set(kv[0], int(kv[1]) if old is int else float(kv[1]))
		changed.append("%s=%s" % [kv[0], balance.get(kv[0])])

	var end_turns: Array[int] = []
	## 整张星图压成直线、平局结束的对局
	var draw_turns: Array[int] = []
	var contact_turns: Array[int] = []
	var first_death_turns: Array[int] = []
	var alive_sum := {}
	## 每个检查点上，活着的文明平均有几个星系（每局先求平均，再对多局求平均）
	var systems_sum := {}
	for k in CHECKPOINTS:
		alive_sum[k] = 0.0
		systems_sum[k] = 0.0

	for seed_value in runs:
		var s := GameState.new_game(seed_value)
		s.spectator = true
		s.human().is_ai = true
		var contact := -1
		var first_death := -1
		var alive_at := {}
		var systems_at := {}
		for t in MAX_TURNS:
			s.end_turn()
			var alive := s.civs.filter(func(c): return c.alive).size()
			if contact < 0 and s.civs.any(func(c): return not c.known.is_empty()):
				contact = s.turn
			if first_death < 0 and alive < s.civs.size():
				first_death = s.turn
			alive_at[s.turn] = alive
			var living := s.civs.filter(func(c): return c.alive)
			var systems := 0
			for c in living:
				systems += c.colonies.size()
			systems_at[s.turn] = systems / float(maxi(1, living.size()))
			if s.is_over():
				break
		var final_alive := s.civs.filter(func(c): return c.alive).size()
		for k in CHECKPOINTS:
			# 提前结束的对局，之后的存活数就是结束时的数
			alive_sum[k] += alive_at.get(k, final_alive)
			systems_sum[k] += systems_at.get(k, systems_at[s.turn])
		if s.winner == "平局":
			draw_turns.append(s.turn)
		elif s.is_over():
			end_turns.append(s.turn)
		if contact > 0:
			contact_turns.append(contact)
		if first_death > 0:
			first_death_turns.append(first_death)

	print("改动：%s；共 %d 局，每局最多 %d 回合" % [", ".join(changed) if changed else "无", runs, MAX_TURNS])
	print("  首次发现目标：%d 局，中位数第 %s 回合" % [contact_turns.size(), _median(contact_turns)])
	print("  首个文明灭亡：%d 局，中位数第 %s 回合" % [first_death_turns.size(), _median(first_death_turns)])
	print("  非平局终局：%d 局，中位数第 %s 回合" % [end_turns.size(), _median(end_turns)])
	print("  全图压成直线、平局：%d 局，中位数第 %s 回合" % [draw_turns.size(), _median(draw_turns)])
	for k in CHECKPOINTS:
		print("  第 %d 回合平均存活文明 %.2f / 5，每个文明平均 %.1f 个星系" % [k, alive_sum[k] / runs,
				systems_sum[k] / runs])
	quit()


func _median(values: Array[int]) -> String:
	if values.is_empty():
		return "-"
	var v := values.duplicate()
	v.sort()
	return str(v[v.size() / 2])
