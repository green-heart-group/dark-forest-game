class_name Tech
extends RefCounted
## 科技树（游戏设计 §5）：每项科技的编号、名字、等级和前置。价格在 Balance.TECH_COST。

## 键是规则代码里用的名字，按画面上的顺序排列
const ALL := {
	"miner": {"code": "001", "name": "地表采矿", "tier": 0, "needs": [], "initial": true},
	"fission": {"code": "002", "name": "裂变能技术", "tier": 0, "needs": [], "initial": true},
	"telescope": {"code": "003", "name": "射电望远镜", "tier": 0, "needs": [], "initial": true},
	"probe": {"code": "004", "name": "化学火箭", "tier": 0, "needs": [], "initial": true},
	"warship": {"code": "005", "name": "恒星级战舰", "tier": 0, "needs": [], "initial": false},
	"broadcaster": {"code": "006", "name": "恒星放大广播", "tier": 0, "needs": [], "initial": false},
	"warning": {"code": "007", "name": "预警系统", "tier": 0, "needs": [], "initial": true},
	"mining_advanced": {"code": "008", "name": "小行星带开采", "tier": 0, "needs": ["miner"], "initial": false},
	"fusion": {"code": "009", "name": "聚变能技术", "tier": 0, "needs": ["fission"], "initial": false},
	"interstellar_probe": {"code": "010", "name": "核脉冲推进", "tier": 0, "needs": ["probe"], "initial": false},
	"railgun": {"code": "011", "name": "电磁动能炮", "tier": 0, "needs": ["warship"], "initial": false},
	"beam": {"code": "012", "name": "高能粒子束", "tier": 0, "needs": ["warship"], "initial": false},
	"alloy": {"code": "013", "name": "合金装甲", "tier": 0, "needs": ["warship"], "initial": false},
	"bunker": {"code": "014", "name": "掩体构筑", "tier": 0, "needs": ["warning"], "initial": false},
	"interstellar_travel": {"code": "015", "name": "恒星际航行", "tier": 0, "needs": [], "initial": false},
	"devourer": {"code": "101", "name": "吞食者", "tier": 1, "needs": ["mining_advanced"], "initial": false},
	"antimatter_collection": {"code": "102", "name": "反物质收集", "tier": 1, "needs": [], "initial": false},
	"gravity_scan": {"code": "103", "name": "引力波探测", "tier": 1, "needs": ["telescope"], "initial": false},
	"hbomb": {"code": "104", "name": "次声波氢弹", "tier": 1, "needs": ["beam"], "initial": false},
	"torpedo": {"code": "105", "name": "星际鱼雷", "tier": 1, "needs": ["railgun"], "initial": false},
	"shield": {"code": "106", "name": "能量力场", "tier": 1, "needs": ["beam"], "initial": false},
	"antimatter": {"code": "107", "name": "反物质炸弹", "tier": 1, "needs": ["antimatter_collection"], "initial": false},
	"gravity": {"code": "108", "name": "引力波广播", "tier": 1, "needs": ["broadcaster"], "initial": false},
	"colony": {"code": "109", "name": "星际殖民", "tier": 1, "needs": ["interstellar_travel"], "initial": false},
	"starship": {"code": "110", "name": "星舰文明", "tier": 1, "needs": ["interstellar_travel"], "initial": false},
	"dyson": {"code": "201", "name": "戴森球", "tier": 2, "needs": ["devourer"], "initial": false},
	"sophon": {"code": "202", "name": "微观蚀刻", "tier": 2, "needs": [], "initial": false},
	"droplet": {"code": "203", "name": "强互作用力", "tier": 2, "needs": ["interstellar_probe"], "initial": false},
	"grain": {"code": "204", "name": "光粒投送", "tier": 2, "needs": [], "initial": false},
	"warp": {"code": "205", "name": "曲率引擎", "tier": 2, "needs": [], "initial": false},
	"wandering_earth": {"code": "206", "name": "流浪地球", "tier": 2, "needs": ["starship"], "initial": false},
	"dark_energy": {"code": "301", "name": "真空能提取", "tier": 3, "needs": ["antimatter_collection"], "initial": false},
	"dimension": {"code": "302", "name": "维度打击", "tier": 3, "needs": [], "initial": false},
	"domain": {"code": "303", "name": "黑域投放", "tier": 3, "needs": ["warp"], "initial": false},
}

const TIER_NAMES := ["0 级", "I 级", "II 级", "III 级"]
## 事件与名义净经常产能同时满足后永久开放，两者先后顺序不影响。
const TIER_RULES := ["可从开局研究", "发现未知星系或单位；每年净产能达到4E、10M",
		"在同一星系接触其他文明；每年净产能达到10E、30M",
		"侦察与战报确认已摧毁另一文明的全部星系；每年净产能达到40E、60M"]
## 战舰的武器（T23），按开火的优先顺序
const WEAPONS := ["hbomb", "beam", "torpedo", "railgun"]


static func tier(id: String) -> int:
	return ALL[id]["tier"]


static func title(id: String) -> String:
	return "%s %s" % [ALL[id]["code"], ALL[id]["name"]]


## 开局就有的科技。
static func starting() -> Array[String]:
	var result: Array[String] = []
	for id in ALL:
		if ALL[id]["initial"]:
			result.append(id)
	return result


## 价格 [能量, 矿石]；只有五项初始科技免费。
static func cost(id: String) -> Array:
	return Balance.TECH_COST.get(id, [0, 0])


## 研究所需工作量；与维度光速和产出倍率独立。
static func work(id: String) -> float:
	return float(Balance.TECH_WORK.get(id, 0))
