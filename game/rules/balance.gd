class_name Balance
extends RefCounted
## 所有数值的名字和类型。值写在 res://balance.cfg（说明也在那里），这个脚本加载时读进来。
## 游戏里只读不改；写成 static var 是为了让平衡模拟工具和调试面板能临时改。
## 加、删数值只改 balance.cfg：下面的声明由 game/tools/sync_balance.py 生成，test.py 每次跑测试前都会先生成一遍。

const PATH := "res://balance.cfg"
const SECTION := "values"

# >>> 下面这段由 game/tools/sync_balance.py 按 balance.cfg 生成，只有类型可以手改（重新生成时留着）
static var AI_COUNT: int

# ---------- 星图生成（按 E7F6 的设想，概率都是暂定） ----------
static var P_HAS_STAR: float
static var STAR_WEIGHTS: Array[int]
static var MAX_PLANETS: Array[int]
static var P_ROCKY: float
static var P_HABITABLE_PLANET: float
static var HOME_MIN_DISTANCE: float

# ---------- 资源和行动点 ----------
static var START_ENERGY: int
static var START_MINERAL: int
static var FISSION_ENERGY: int
static var ENERGY_PER_SYSTEM: int
static var ENERGY_PER_STAR: int
static var MINERAL_PER_COLONY: int
static var ACTION_BASE: int
static var ACTION_MIN: int
static var STARSHIP_ENERGY: int
static var STARSHIP_MINERAL: int

# ---------- 科技（游戏设计 §5） ----------
static var TECH_COST: Dictionary
static var TIER3_ENERGY: int
static var TIER_GAP: int
static var CONTACT_RANGE: float
static var TECH_BURST_CHANCE: float

# ---------- 视野（游戏设计 §4） ----------
static var VISION_HOME: float
static var VISION_COLONY: float
static var VISION_SHIP: float
static var PROBE_ANGLE: float
static var PROBE_LENGTH: float
static var IPROBE_ANGLE: float
static var IPROBE_LENGTH: float
static var MAX_CONE_ANGLE: float
static var TELESCOPE_MAX: int
static var TELESCOPE_STEP: float
static var TELESCOPE_ANGLE_STEP: float
static var COST_TELESCOPE: int
static var WAKE_SPEED: float
static var SIGHTING_KEEP: int

# ---------- 移动（游戏设计 §3）：[最高速度, 加速度] ----------
static var GRAIN_MOVE: Array
static var PROBE_MOVE: Array
static var IPROBE_MOVE: Array
static var WARSHIP_MOVE: Array
static var STARSHIP_MOVE: Array
static var COLONY_MOVE: Array
static var DEVOURER_MOVE: Array
static var WARP_MOVE: Array
static var SLOW_START_SPEED: float

# ---------- 单位和设施 ----------
static var COST_PROBE: Array
static var COST_PROBE_LAUNCH: int
static var COST_WARSHIP: Array
static var COST_WARSHIP_GRAVITY: int
static var COST_WARSHIP_LAUNCH: int
static var COST_TURN: int
static var COST_COLONY: Array
static var COST_STARSHIP: Array
static var COST_STARSHIP_MOVE: int
static var COST_DEVOURER: Array
static var COST_DEVOURER_LAUNCH: int
static var COST_WARP_EXTRA: int
static var MAX_WARSHIPS: int
static var MAX_COLONY_SHIPS: int
static var MAX_STARSHIPS: int
static var MAX_DEVOURERS: int
static var DEVOURER_MINERAL: int
static var COST_MINER: Array
static var MINER_MINERAL: int
static var MAX_MINERS: int
static var COST_DYSON: Array
static var DYSON_ENERGY: int
static var COST_BUNKER: Array
static var COST_BROADCASTER: Array
static var COST_WARNING: Array
static var WARNING_RANGE: float
static var WARNING_MAX: int
static var COST_WARNING_UPGRADE: int
static var COST_ANTIMATTER: Array
static var MAX_ANTIMATTER: int
static var ANTIMATTER_RANGE: float
static var COST_GRAIN: Array
static var COST_GRAIN_LAUNCH: int
static var GRAIN_RADIUS: float

# ---------- 战舰的打击（游戏设计 §6） ----------
static var WARSHIP_RANGE: float

# ---------- 战舰的武器（T23） ----------
static var BEAM_RANGE: float
static var TORPEDO_RANGE: float
static var HBOMB_RANGE: float
static var COST_BEAM_EXTRA: Array
static var COST_TORPEDO_EXTRA: Array
static var COST_HBOMB_EXTRA: Array
static var BEAM_SHOT: Array
static var TORPEDO_SHOT: Array
static var HBOMB_SHOT: Array
static var TORPEDO_HITS: int

# ---------- 智子（D5） ----------
static var COST_SOPHON: Array
static var COST_SOPHON_LAUNCH: int
static var SOPHON_MOVE: Array
static var MAX_SOPHONS: int
static var SOPHON_RESEARCH_TURNS: int
static var SOPHON_TIER_TURNS: int

# ---------- 降维（游戏设计 §9） ----------
static var COST_FOIL: int
static var COST_LINE_FOIL: int
static var FOIL_PREPARE_TURNS: int
static var FOIL_SPEED: float
static var FOIL_SPREAD: float
static var COST_SINGULARITY: int
static var SINGULARITY_TURNS: int
static var LINE_GRACE_TURNS: int
static var COST_REDUCE_BASE: int
static var COST_REDUCE_PER_UNIT: int
static var REDUCE_TURNS: int
static var AI_REDUCE_ALERT: int
static var AI_FOIL_HITS: int
static var AI_FOIL_ENERGY: int

# ---------- 黑域（游戏设计 §7） ----------
static var COST_BLACK_DOMAIN: int
static var BLACK_DOMAIN_PREPARE_TURNS: int
static var BLACK_DOMAIN_TURNS: int
static var DOMAIN_INCOME: float
static var GRAIN_MIN_LIGHT: float
static var SHIP_MIN_SPEED: float
static var SHIP_STUCK_TURNS: int

# ---------- 广播和隐藏文明（游戏设计 §8） ----------
static var COST_BROADCAST: int
static var BROADCAST_EXPOSE_HALF: float
static var HIDDEN_COUNT: int
static var HIDDEN_HEAR_RANGE: float
static var HIDDEN_STRIKE_CHANCE: float
static var HIDDEN_PATIENCE: int
static var HIDDEN_FOIL_CHANCE: float
static var HIDDEN_FOIL_SPEED: float

# ---------- 暗能量采集（科技 301） ----------
static var DARK_ENERGY_CELLS: int

# ---------- r4 numerical-loop profiles ----------
static var R4_ECONOMY_B: Dictionary
static var R4_ECONOMY_C: Dictionary
static var R4_PHYSICS: Dictionary
# <<< 生成的到这里为止


# ---------- 读 balance.cfg、按名字读改数值 ----------
# Godot 在运行时列不出 static var，所以数值的名字、说明、文件里写的值都取自 balance.cfg。
# 别的代码（对局记录、调试面板、数值方案、平衡模拟）都通过下面这几个函数读改数值，类型检查只写在这里。

## 读过的 balance.cfg：{"values": {名字: 值}, "docs": {名字: 说明}}。空字典表示还没读，或者写回以后要重读。
static var _file := {}


## 启动时把 balance.cfg 里的值设进来。名字不认识、类型不对的报错，那个数值留着空值。
static func _static_init() -> void:
	var values: Dictionary = _read_file()["values"]
	if values.is_empty():
		push_error("读不出 %s，或者里面没有 [%s]" % [PATH, SECTION])
	for name in values:
		var err := set_value(name, values[name])
		if err != "":
			push_error("%s：%s" % [PATH, err])


static func _read_file() -> Dictionary:
	if _file.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var cfg := ConfigFile.new()
		var values := {}
		if cfg.parse(text) == OK and cfg.has_section(SECTION):
			for k in cfg.get_section_keys(SECTION):
				values[k] = cfg.get_value(SECTION, k)
		_file = {"values": values, "docs": parse_docs(text)}
	return _file


## balance.cfg 改过以后（比如调试面板写回了），下次用到时重读。
static func reload_file() -> void:
	_file = {}


## 所有数值的名字，按 balance.cfg 里的顺序。
static func names() -> Array[String]:
	var found: Array[String] = []
	found.assign(_read_file()["values"].keys())
	return found


## 每个数值的说明：{名字: 说明}，取自 balance.cfg 的注释。
static func docs() -> Dictionary:
	return _read_file()["docs"]


## 所有数值现在的值（可能被平衡模拟、调试面板、对局记录改过）。数组和字典是复制出来的，改了不影响 Balance。
static func values() -> Dictionary:
	var script: GDScript = Balance
	var found := {}
	for name in names():
		var v = script.get(name)
		found[name] = v.duplicate(true) if v is Array or v is Dictionary else v
	return found


## balance.cfg 里写的值（不管这次运行里改过没有）。数组的类型和 Balance 里的一样（Array[int] 等）。
static func file_values() -> Dictionary:
	var script: GDScript = Balance
	var found := {}
	var written: Dictionary = _read_file()["values"]
	for name in written:
		var v = written[name]
		var now = script.get(name)
		if now is Array:
			var typed: Array = now.duplicate()
			typed.assign(v)
			v = typed
		found[name] = v.duplicate(true) if v is Array or v is Dictionary else v
	return found


## 能不能把 name 设成 value：能的话返回空字符串，不能的话返回原因（没有这个数值、类型不对）。整数可以当小数用。
static func value_error(name: String, value: Variant) -> String:
	var now = (Balance as GDScript).get(name)
	if now == null:
		return "没有叫 %s 的数值" % name
	if typeof(now) != typeof(value) and not (now is float and value is int):
		return "%s 的类型不对" % name
	return ""


## value 换成 name 那个数值的类型：数值是小数、给的是整数时变成小数，其他原样返回。
static func fit_value(name: String, value: Variant) -> Variant:
	return float(value) if (Balance as GDScript).get(name) is float and value is int else value


## 把 name 设成 value（只在这次运行里有效，不改 balance.cfg）。成功返回空字符串，不然返回原因，什么都不改。
static func set_value(name: String, value: Variant) -> String:
	var err := value_error(name, value)
	if err != "":
		return err
	var script: GDScript = Balance
	var now = script.get(name)
	if now is Array:
		now.assign(value)  # 原地改，Array[int] 这样的类型留着
	else:
		script.set(name, fit_value(name, value))
	return ""


## 一次设好几个数值：{名字: 值}。设不了的跳过，返回 [原因]。
static func apply(changes: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for name in changes:
		var err := set_value(name, changes[name])
		if err != "":
			errors.append(err)
	return errors


## 由 balance.cfg 的原文取出每个数值的说明：同一行后面的注释；没有的话，用上面连着几行的注释
## （它是下面连着的这一组数值共同的说明，直到空行为止，所以组里只适合一个数值的注释要写在那一行后面）。
## 以「---」开头的注释是分段标题，不算说明。
static func parse_docs(text: String) -> Dictionary:
	var found := {}
	var above := ""
	var after_comment := false  # 上一行是不是注释：是的话这一行注释接着上一段，不是就另起一段
	var key := RegEx.create_from_string("^(\\w+)\\s*=")
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with(";"):
			var comment := line.trim_prefix(";").strip_edges()
			if comment.begins_with("---"):
				above = ""
			else:
				above = above + comment if after_comment else comment  # 连着几行的注释合成一段
			after_comment = true
			continue
		after_comment = false
		var m := key.search(line)
		if m != null:
			var semi := line.find(";")
			found[m.get_string(1)] = line.substr(semi + 1).strip_edges() if semi >= 0 else above
		elif line == "" or line.begins_with("["):
			above = ""
	return found