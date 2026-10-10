class_name Replay
extends RefCounted
## 对局记录：开局种子、AI 个数，加上玩家（不是 AI）做过的每一次操作。
## 规则里所有随机数都来自 GameState.rng，所以同样的种子、同样的玩家操作，重算出来的对局完全一样；
## AI 的操作不用记，重算时 AI 会做出同样的决定。
## 每结束一回合还存一个校验值，重算时对比，发现不一样（比如改了规则或数值）就记下是第几回合。

const VERSION := 3
const DIR := "user://replays"

var seed_value := 0
var ai_count := 0
## 观战模式：所有文明都由 AI 控制
var spectator := false
## 玩家的操作，格式同 GameState.history
var commands: Array[Dictionary] = []
## 每结束一回合后的校验值
var checksums: Array[int] = []
## 记录时 balance.cfg 里的数值
var balance := {}
## 重算时第一次和记录不一样的地方（第几次结束回合后），一样时为 -1
var desync_step := -1


## 从正在进行的对局生成记录。
static func from_state(s: GameState) -> Replay:
	var r := Replay.new()
	r.seed_value = s.seed_value
	r.ai_count = s.ai_count
	r.spectator = s.spectator
	for h in s.history:
		if not h["ai"]:
			r.commands.append(h.duplicate(true))
	r.checksums = s.checksums.duplicate()
	r.balance = s.start_balance.duplicate(true) if not s.start_balance.is_empty() else Balance.values()
	return r


## 记录里一共结束过几回合。
func last_step() -> int:
	return checksums.size()


## 按记录重新开局（还没结束过回合）。数值先换回开局时的，中途改过的由记录里的操作再改。
func start() -> GameState:
	desync_step = -1
	apply_balance()
	return GameState.new_game(seed_value, ai_count, spectator)


## 在 s 上重做这一回合玩家的操作，再结束回合。只在记录范围内用（s.steps < last_step()）。
## 结果和记录不一样时返回 false，并记下 desync_step。
func step(s: GameState) -> bool:
	var ok := apply_pending(s)
	s.end_turn()
	if s.steps <= checksums.size():
		ok = ok and s.checksums[s.steps - 1] == checksums[s.steps - 1]
	if not ok and desync_step < 0:
		desync_step = s.steps
	return ok


## 重做玩家在这一回合（还没结束）做过的操作。有操作做不成时返回 false。
## 记录停在回合中间时（玩家做了几件事还没结束回合），走到记录末尾要用它补上最后这些操作。
func apply_pending(s: GameState) -> bool:
	var ok := true
	for c in commands:
		if c["step"] != s.steps:
			continue
		# civ 为 -1 的是不针对某个文明的操作（比如改 balance.cfg 的数值）
		var args: Array = [s.civs[c["civ"]]] if c["civ"] >= 0 else []
		args.append_array(c["args"])
		var result: Dictionary = s.callv(c["name"], args)
		ok = ok and result["error"] == ""
	return ok


## 重算到结束过 n 回合的局面。n 达到记录末尾时，最后一回合里已经做过的操作也补上。
## 给了局面缓存时，从缓存里不晚于 n 的最近一份接着算，算的路上把局面存进缓存；没有时从开局算。
func play_to(n: int, snaps: Snapshots = null) -> GameState:
	var s := begin(n, snaps)
	while s.steps < mini(n, last_step()) and not s.is_over():
		advance(s, snaps, n)
	finish(s)
	return s


## 重算的起点：缓存里不晚于 n、属于这份记录的最近一份局面（复制出来的），没有时重新开局。
func begin(n: int, snaps: Snapshots = null) -> GameState:
	var k := snaps.nearest(n, self) if snaps != null else -1
	if k < 0:
		return start()
	desync_step = snaps.desync(k)
	return snaps.restore(k)


## 按记录走一回合。给了缓存时，走完把要留的局面存进去（要往 target 走，见 Snapshots.worth）。
func advance(s: GameState, snaps: Snapshots = null, target := -1) -> void:
	step(s)
	if snaps != null and snaps.worth(s.steps, target):
		snaps.remember(s, desync_step)


## 走到记录末尾时，补上最后一回合里已经做过的操作。
func finish(s: GameState) -> void:
	if s.steps >= last_step():
		if not apply_pending(s) and desync_step < 0:
			desync_step = s.steps


## 记录比 n 晚的部分全部丢掉（从第 n 次结束回合之后另开一条路）。
func truncate(n: int) -> void:
	commands = commands.filter(func(c): return c["step"] < n)
	checksums.resize(mini(n, checksums.size()))


func to_dict() -> Dictionary:
	return {"version": VERSION, "seed": seed_value, "ai_count": ai_count, "spectator": spectator,
			"commands": commands, "checksums": checksums, "balance": balance}


static func from_dict(d: Dictionary) -> Replay:
	var r := Replay.new()
	r.seed_value = d.get("seed", 0)
	r.ai_count = d.get("ai_count", Balance.AI_COUNT)
	r.spectator = d.get("spectator", false)
	r.commands.assign(d.get("commands", []))
	r.checksums.assign(d.get("checksums", []))
	r.balance = d.get("balance", {})
	return r


## 存成二进制文件（浮点数原样保存，重算才能完全一样）。返回 Godot 的错误码。
func save(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(to_dict())
	return OK


## 读文件，读不出来时返回 null。
static func load_file(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = f.get_var()
	if not valid_data(d):
		return null
	return from_dict(d)


## 外部文件只能重做已登记的玩家操作；先验证结构和参数，再调用规则函数。
static func valid_data(d: Variant) -> bool:
	if not d is Dictionary or d.get("version") != VERSION:
		return false
	if not d.get("seed") is int or not d.get("ai_count") is int or d["ai_count"] < 0 or d["ai_count"] > 32:
		return false
	if not d.get("spectator") is bool or not d.get("commands") is Array or not d.get("checksums") is Array or not d.get("balance") is Dictionary:
		return false
	for value in d["checksums"]:
		if not value is int:
			return false
	for name in d["balance"]:
		if not name is String or Balance.value_error(name, d["balance"][name]) != "":
			return false
	var allowed := ["research", "upgrade", "build", "dispatch", "turn_ship", "send_colony", "move_starship",
			"settle_starship", "launch_grain", "use_antimatter", "send_sophon", "broadcast", "launch_foil",
			"launch_line_foil", "start_reduce", "launch_singularity", "launch_black_domain", "set_autoplay",
			"set_play_on_after_death", "dev_balance", "dev_set", "dev_tech", "cancel_order", "emergency_work",
			"refit_ship", "start_landing", "refit_miner", "prepare_conversion", "execute_conversion", "active_scan", "start_earth", "set_weapon_policy", "set_maintenance"]
	var signatures := {}
	for method in GameState.new().get_method_list():
		if method["name"] in allowed:
			signatures[method["name"]] = method["args"]
	var previous := 0
	for command in d["commands"]:
		if not command is Dictionary or not command.get("name") in allowed:
			return false
		if not command.get("step") is int or command["step"] < previous or command["step"] > d["checksums"].size():
			return false
		previous = command["step"]
		if not command.get("civ") is int or not command.get("args") is Array or command.get("ai") != false:
			return false
		var global_command: bool = command["name"] in ["dev_balance", "set_play_on_after_death"]
		if (global_command and command["civ"] != -1) or (not global_command and (command["civ"] < 0 or command["civ"] > d["ai_count"])):
			return false
		var args: Array = signatures[command["name"]].slice(0 if global_command else 1)
		if command["args"].size() != args.size():
			return false
		for i in args.size():
			if args[i]["type"] != TYPE_NIL and typeof(command["args"][i]) != args[i]["type"]:
				return false
	return true


## 记录里的数值和现在的数值不一样的地方：{名字: [记录时, 现在]}。
func balance_diff() -> Dictionary:
	var now := Balance.values()
	var diff := {}
	for k in balance:
		if now.get(k) != balance[k]:
			diff[k] = [balance[k], now.get(k)]
	return diff


## 把数值改成记录时的（只在这次运行里有效）。现在已经没有的数值跳过。
func apply_balance() -> void:
	Balance.apply(balance)
	if not balance.is_empty() and not balance.has("BUILD_SLOTS"):
		Balance.set_value("BUILD_SLOTS",Balance.file_values()["BUILD_SLOTS"])
	# 既有V0.1记录没有母星容量键，必须按原单槽重放，不能用新默认容量改变AI历史。
	if not balance.is_empty() and not balance.has("HOME_BUILD_SLOTS"):
		Balance.set_value("HOME_BUILD_SLOTS",Balance.BUILD_SLOTS)
	# W7之前的V0.1记录用绝对速度与加速度；缺键不能套用新局的当地光速分档。
	if not balance.is_empty() and not balance.has("SHIP_SPEED_RELATIVE"):
		Balance.set_value("SHIP_SPEED_RELATIVE",0)
	if not balance.is_empty() and not balance.has("LOCAL_ORDER_REPORT_CURRENT"):
		Balance.set_value("LOCAL_ORDER_REPORT_CURRENT",0)
