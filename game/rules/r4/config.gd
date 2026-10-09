class_name R4Config
extends RefCounted
## 两个经济参数组共享同一规则。数值只取Balance，节点身份只取已校验Word目录。
const BUILD_TECH := {"miner_basic":"001", "miner_advanced":"008", "probe_basic":"004", "probe_nuclear":"010",
	"battleship":"005", "stellar_broadcaster":"006", "warning":"007", "bunker":"014", "transport":"015",
	"colony":"109", "devourer":"101", "antimatter_bomb":"107", "starship":"110", "dyson":"201",
	"sophon":"202", "droplet":"203", "photoid":"204", "dimensional_weapon":"302", "wandering_earth":"206"}
const ANCHORS := ["home", "colony", "starship", "wandering_earth"]
const MOBILE := ["probe_basic", "probe_nuclear", "battleship", "transport", "starship", "devourer", "sophon", "droplet", "wandering_earth"]
const CELESTIAL := ["miner_basic", "miner_advanced", "stellar_broadcaster", "warning", "bunker", "dyson"]
const AMMUNITION := ["antimatter_bomb", "photoid", "dimensional_weapon"]
const WARP_HULLS := ["battleship", "transport", "starship", "devourer"]
const PERSONNEL_TARGETS := ["battleship", "starship", "wandering_earth"]
var profile := "C"
var economy: Dictionary
var physics: Dictionary
var catalog: Dictionary

func _init(selected := "C") -> void:
	assert(selected in ["B", "C"])
	profile = selected
	economy = (Balance.R4_ECONOMY_B if selected == "B" else Balance.R4_ECONOMY_C).duplicate(true)
	physics = Balance.R4_PHYSICS.duplicate(true)
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://rules/r4/catalog.json"))
	assert(catalog.size() == 34)

func q(dim: int) -> float:
	return economy.scale.dimension_parameters[str(dim)].gross_output_factor

func work_factor(dim: int) -> float:
	return economy.scale.dimension_parameters[str(dim)].work_factor

func c(dim: int) -> float:
	return physics.background_c[str(dim)]

func spacing(dim: int) -> float:
	return physics.grid_spacing[str(dim)]

func price(section: String, id: String) -> Vector2i:
	var row: Dictionary = economy[section][id]
	var prefix := "research_" if section == "technologies" else "cost_"
	return Vector2i(roundi(row[prefix + "M"] * 1000), roundi(row[prefix + "E"] * 1000))

func work(section: String, id: String) -> float:
	return economy[section][id].work

func digest() -> String:
	return JSON.stringify({"profile":profile,"economy":economy,"physics":physics,"catalog":catalog}).sha256_text()
