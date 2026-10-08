class_name Snapshots
extends RefCounted
## 调试面板往回跳用的局面缓存：最近存进来的 RECENT 个回合，加上每 EVERY 回合一份。
## 存的是回合刚开始、玩家还没操作时的局面（结束回合以后马上存），连同当时的数值和重算发现不一样的回合。
## 局面打包成压缩的字节存（StateCopy），取的时候恢复成新的一份，缓存里的局面不会被之后的对局改到。
## 取的时候核对开局（种子、AI 个数、观战、开局数值）和之前每一次玩家操作都和记录一样，
## 所以换了记录、从中间另开一条路时，就算没有清掉，也不会取到另一条历史的局面。

const RECENT := 10
const EVERY := 10

## 结束过几回合 -> {"state": 打包的局面, "balance": 当时的数值, "desync": 当时已发现的不一样的回合,
## "record": 走到这里的对局记录，核对是不是同一条历史用（见 fits）}
var _saved: Dictionary[int, Dictionary] = {}
## 不是 EVERY 倍数的那些，按存进来的先后
var _recent: Array[int] = []


## 存下 s（必须是刚结束回合、还没做这一回合的操作的局面）。已经有了就不再存。
func remember(s: GameState, desync := -1) -> void:
	if _saved.has(s.steps):
		return
	_saved[s.steps] = {"state": StateCopy.pack(s), "balance": Balance.values(), "desync": desync,
			"record": Replay.from_state(s)}
	if s.steps % EVERY != 0:
		_recent.append(s.steps)
		if _recent.size() > RECENT:
			_saved.erase(_recent.pop_front())


## 往 target 回合走的路上，第 n 回合值不值得存：每 EVERY 回合一份，加上离 target 不到 RECENT 回合的。
## 打包一份要几十毫秒，和算一回合差不多，所以不是每回合都存。target 为 -1 时都存。
func worth(n: int, target: int) -> bool:
	return target < 0 or n % EVERY == 0 or n > target - RECENT


func has(n: int) -> bool:
	return _saved.has(n)


func size() -> int:
	return _saved.size()


## 不晚于 n、和记录 r 是同一条历史的最近一份是第几回合，没有时返回 -1。
func nearest(n: int, r: Replay) -> int:
	var best := -1
	for k in _saved:
		if k <= n and k > best and fits(_saved[k]["record"], r):
			best = k
	return best


## 把数值换成当时的，返回第 n 回合局面的一份新复制。
func restore(n: int) -> GameState:
	Balance.apply(_saved[n]["balance"])
	return StateCopy.unpack(_saved[n]["state"])


func desync(n: int) -> int:
	return _saved[n]["desync"]


## 丢掉比 n 晚的（从第 n 回合另开一条路以后，它们是另一条历史）。
func drop_after(n: int) -> void:
	for k in _saved.keys():
		if k > n:
			_saved.erase(k)
	_recent = _recent.filter(func(k): return k <= n)


func clear() -> void:
	_saved.clear()
	_recent.clear()


## 打包后一共多少字节（测内存用）。
func bytes() -> int:
	var total := 0
	for k in _saved:
		total += _saved[k]["state"].size()
	return total


## 走到 have 的记录是不是记录 r 的前一段：开局一样（种子、AI 个数、观战、开局数值），之前玩家的每一次操作也一样。
static func fits(have: Replay, r: Replay) -> bool:
	var n := have.last_step()
	if have.seed_value != r.seed_value or have.ai_count != r.ai_count or have.spectator != r.spectator \
			or n > r.last_step():
		return false
	for name in r.balance:  # 记录里有、现在已经没有的数值，开局时也跳过了
		if have.balance.has(name) and have.balance[name] != Balance.fit_value(name, r.balance[name]):
			return false
	return have.commands == r.commands.filter(func(c): return c["step"] < n)
