class_name Replay
extends RefCounted
## 对局记录：开局种子、AI 个数，加上玩家（不是 AI）做过的每一次操作。
## 规则里所有随机数都来自 GameState.rng，所以同样的种子、同样的玩家操作，重算出来的对局完全一样；
## AI 的操作不用记，重算时 AI 会做出同样的决定。
## 每结束一回合还存一个校验值，重算时对比，发现不一样（比如改了规则或数值）就记下是第几回合。

const VERSION := 1
const DIR := "user://replays"

var seed_value := 0
var ai_count := 0
## 观战模式：所有文明都由 AI 控制
var spectator := false
## 玩家的操作，格式同 GameState.history
var commands: Array[Dictionary] = []
## 每结束一回合后的校验值
var checksums: Array[int] = []
## 记录时 balance.gd 里的数值
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
	r.balance = s.start_balance.duplicate(true) if not s.start_balance.is_empty() else balance_values()
	return r


## 记录里一共结束过几回合。
func last_step() -> int:
	return checksums.size()


## 按记录重新开局（还没结束过回合）。数值先换回开局时的，中途改过的由记录里的操作再改。
func start() -> GameState:
	desync_step = -1
	apply_balance()
	var s := GameState.new_game(seed_value, ai_count)
	if spectator:
		s.spectator = true
		s.human().is_ai = true
	return s


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
		# civ 为 -1 的是不针对某个文明的操作（比如改 balance.gd 的数值）
		var args: Array = [s.civs[c["civ"]]] if c["civ"] >= 0 else []
		args.append_array(c["args"])
		var result: Dictionary = s.callv(c["name"], args)
		ok = ok and result["error"] == ""
	return ok


## 从头重算到结束过 n 回合的局面。n 达到记录末尾时，最后一回合里已经做过的操作也补上。
func play_to(n: int) -> GameState:
	var s := start()
	while s.steps < mini(n, last_step()) and not s.is_over():
		step(s)
	if s.steps >= last_step():
		apply_pending(s)
	return s


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
	if not d is Dictionary or d.get("version", 0) > VERSION:
		return null
	return from_dict(d)


## 记录里的数值和现在 balance.gd 里不一样的地方：{名字: [记录时, 现在]}。
func balance_diff() -> Dictionary:
	var now := balance_values()
	var diff := {}
	for k in balance:
		if now.get(k) != balance[k]:
			diff[k] = [balance[k], now.get(k)]
	return diff


## 把 balance.gd 的数值改成记录时的（只在这次运行里有效）。
func apply_balance() -> void:
	var script: Script = load("res://rules/balance.gd")
	for k in balance:
		var now = script.get(k)
		if now is Array:
			now.assign(balance[k])
		elif now != null:
			script.set(k, balance[k])


## balance.gd 里所有 static var 的当前值。Godot 列不出 static var，名字取自 balance_index.gd。
static func balance_values() -> Dictionary:
	var script: Script = load("res://rules/balance.gd")
	var values := {}
	for name in BalanceIndex.NAMES:
		var v = script.get(name)
		values[name] = v.duplicate(true) if v is Array or v is Dictionary else v
	return values
