class_name Tech
extends RefCounted
## 科技树（游戏设计 §5）：每项科技的编号、名字、等级和前置。价格在 Balance.TECH_COST。

## 键是规则代码里用的名字，按画面上的顺序排列
const ALL := {
	"miner": {"code": "001", "name": "采矿船", "tier": 0, "needs": []},
	"fission": {"code": "002", "name": "裂变能技术", "tier": 0, "needs": []},
	"telescope": {"code": "003", "name": "射电望远镜", "tier": 0, "needs": []},
	"probe": {"code": "004", "name": "探测器", "tier": 0, "needs": []},
	"broadcaster": {"code": "005", "name": "恒星广播器", "tier": 0, "needs": []},
	"warning": {"code": "006", "name": "预警系统", "tier": 0, "needs": []},
	"colony": {"code": "007", "name": "殖民船", "tier": 0, "needs": []},
	"dyson": {"code": "101", "name": "戴森球", "tier": 1, "needs": ["fission"]},
	"interstellar_probe": {"code": "102", "name": "星际探测器", "tier": 1, "needs": ["probe"]},
	"warship": {"code": "103", "name": "恒星级战舰", "tier": 1, "needs": ["probe"]},
	"bunker": {"code": "104", "name": "掩体构筑", "tier": 1, "needs": ["warning"]},
	"starship": {"code": "106", "name": "星舰", "tier": 1, "needs": ["colony"]},
	"beam": {"code": "107", "name": "高能粒子束", "tier": 1, "needs": ["warship"]},
	"torpedo": {"code": "108", "name": "星际鱼雷", "tier": 1, "needs": ["warship"]},
	"devourer": {"code": "201", "name": "吞噬者", "tier": 2, "needs": ["miner"]},
	"grain": {"code": "202", "name": "光粒投送", "tier": 2, "needs": []},
	"gravity": {"code": "203", "name": "引力波广播", "tier": 2, "needs": ["broadcaster"]},
	"antimatter": {"code": "204", "name": "反物质制造", "tier": 2, "needs": []},
	"warp": {"code": "205", "name": "曲率引擎", "tier": 2, "needs": []},
	"hbomb": {"code": "207", "name": "次声波氢弹", "tier": 2, "needs": ["warship"]},
	"sophon": {"code": "208", "name": "智子", "tier": 2, "needs": []},
	"dark_energy": {"code": "301", "name": "暗能量采集", "tier": 3, "needs": ["dyson"]},
	"dimension": {"code": "302", "name": "维度打击", "tier": 3, "needs": []},
	"domain": {"code": "303", "name": "黑域投放", "tier": 3, "needs": ["warp"]},
}

const TIER_NAMES := ["0 级", "I 级", "II 级", "III 级"]
## 每一级的条件要按顺序达到：上一级开放以后才算（E8）
const TIER_RULES := ["开局就有", "发现别人或听到广播以后", "I 级开放以后，和别人的舰船接触",
		"II 级开放以后，能量收入达到门槛"]
## 战舰的武器（T23），按开火的优先顺序
const WEAPONS := ["hbomb", "beam", "torpedo"]


static func tier(id: String) -> int:
	return ALL[id]["tier"]


static func title(id: String) -> String:
	return "%s %s" % [ALL[id]["code"], ALL[id]["name"]]


## 开局就有的科技。
static func starting() -> Array[String]:
	var result: Array[String] = []
	for id in ALL:
		if ALL[id]["tier"] == 0:
			result.append(id)
	return result


## 价格 [能量, 矿石]；0 级没有价格。
static func cost(id: String) -> Array:
	return Balance.TECH_COST.get(id, [0, 0])
