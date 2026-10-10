class_name Construction
extends RefCounted
## V0.1 建造类别。只保存名称、解锁与数值键；实际金额/工期统一来自 Balance。

const NAMES := {
	"miner": "基础采矿船",
	"advanced_miner": "高级采矿船",
	"probe": "化学探测器",
	"nuclear_probe": "核脉冲探测器",
	"warship": "恒星级战舰",
	"broadcaster": "恒星广播器",
	"warning": "预警系统",
	"bunker": "掩体",
	"colony": "运输船",
	"landing": "殖民地落地工程",
	"devourer": "吞食者",
	"antimatter": "反物质炸弹",
	"starship": "星舰",
	"dyson": "戴森球",
	"sophon": "智子",
	"droplet": "水滴",
	"grain": "光粒",
	"dimension_weapon": "降维武器",
	"wandering_earth": "流浪地球",
}
const TECH := {
	"miner": "miner",
	"advanced_miner": "mining_advanced",
	"probe": "probe",
	"nuclear_probe": "interstellar_probe",
	"warship": "warship",
	"broadcaster": "broadcaster",
	"warning": "warning",
	"bunker": "bunker",
	"colony": "interstellar_travel",
	"landing": "colony",
	"devourer": "devourer",
	"antimatter": "antimatter",
	"starship": "starship",
	"dyson": "dyson",
	"sophon": "sophon",
	"droplet": "droplet",
	"grain": "grain",
	"dimension_weapon": "dimension",
	"wandering_earth": "wandering_earth",
}
const FACILITIES := ["miner", "advanced_miner", "dyson", "bunker", "broadcaster", "warning"]
const UNITS := ["probe", "nuclear_probe", "warship", "colony", "starship", "devourer", "sophon", "droplet", "wandering_earth"]


static func cost(kind: String) -> Array:
	return Balance.value("COST_" + kind.to_upper())


static func work(kind: String) -> float:
	return float(Balance.BUILD_WORK[kind])


static func upkeep(kind: String) -> Array:
	return Balance.BUILD_UPKEEP[kind].duplicate()
