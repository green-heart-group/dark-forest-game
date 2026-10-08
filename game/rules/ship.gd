class_name Ship
extends RefCounted
## 一个会动的单位：探测器、战舰、殖民船、星舰、吞噬者、智子，或者飞行中的光粒。
## 位置用小数记。每回合先加速（速度 + 加速度，不超过最高速度），再按新速度沿方向直线移动（G1）。
## 造好后先停在星系里（docked），派出以后才开始飞。

const PROBE := "probe"
const WARSHIP := "warship"
const COLONY := "colony"
const STARSHIP := "starship"
const DEVOURER := "devourer"
const GRAIN := "grain"
const SOPHON := "sophon"
## 朝一个方向派出去的（别的要选目的地）
const AIMED := [PROBE, WARSHIP, DEVOURER]
## 在飞的时候能转向的
const TURNABLE := [WARSHIP, DEVOURER]

const NAMES := {PROBE: "探测器", WARSHIP: "战舰", COLONY: "殖民船", STARSHIP: "星舰", DEVOURER: "吞噬者",
		GRAIN: "光粒", SOPHON: "智子"}

## 每个单位一个编号，整局不重复，画面的下拉菜单用它来选单位
var id := 0
var kind := PROBE
var pos := Vector3.ZERO
## 飞行方向（长度为 1）；停着时可以是零
var direction := Vector3.ZERO
var speed := 0.0
var max_speed := 0.0
var accel := 0.0
## 停在出发的星系里，还没派出
var docked := true
## 有目的地的单位（殖民船、星舰）：到了就停下
var has_target := false
var target := Vector3.ZERO
## 装了曲率引擎：在自己星系的视野外自动以光速飞（科技 205）
var warp := false
## 星际探测器（科技 102）
var interstellar := false
## 星际探测器停在了别人的星系上
var parked := false
## 探测器选了「先慢速飞出视野」，还没飞出去（G13.4）
var slow_start := false
## 战舰带着引力波广播器（科技 203）
var gravity := false
## 战舰带的武器（科技 107、108、207，T23）
var weapons: Array[String] = []
## 战舰挨了几发星际鱼雷
var damage := 0
## 造它花的 [能量, 矿石]（次声波氢弹打下它时收回）
var cost := [0, 0]
## 智子锁住的文明（GameState.civs 的下标，没锁时为 -1）和锁住的回合（D5）
var lock := -1
var lock_turn := 0
## 吞噬者正在吃行星，还要停几个回合
var eat_wait := 0
## 在光速几乎为 0 的地方已经停了几个回合（G14）
var stuck := 0
## 已经毁掉（这一回合结算完再从列表里拿掉）
var dead := false


static func make(p_kind: String, p_pos: Vector3, p_id: int) -> Ship:
	var s := Ship.new()
	s.kind = p_kind
	s.pos = p_pos
	s.id = p_id
	var move: Array = {PROBE: Balance.PROBE_MOVE, WARSHIP: Balance.WARSHIP_MOVE, COLONY: Balance.COLONY_MOVE,
			STARSHIP: Balance.STARSHIP_MOVE, DEVOURER: Balance.DEVOURER_MOVE, GRAIN: Balance.GRAIN_MOVE,
			SOPHON: Balance.SOPHON_MOVE}[p_kind]
	s.max_speed = move[0]
	s.accel = move[1]
	return s


## 现在的位置（浮点坐标）。
func position() -> Vector3:
	return pos


## 现在所在的格子。
func cell() -> Vector3i:
	return Vector3i(pos.round())


## 是否已经飞出星图（离边界超过半个格子）。
func is_outside(bounds: AABB) -> bool:
	return outside(pos, bounds)


static func outside(p: Vector3, bounds: AABB) -> bool:
	var lo := bounds.position - Vector3.ONE * Geometry.CELL_HALF
	var hi := bounds.end - Vector3.ONE * Geometry.CELL_HALF
	return p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z


## 在飞（不是停着，也不是停在别人星系上的星际探测器）。
func moving() -> bool:
	return not docked and not parked and (direction != Vector3.ZERO)


## 停着等命令：在星系里，或者到了目的地停在外面（殖民船、智子可以再派）。
func waiting() -> bool:
	return docked or direction == Vector3.ZERO


func label() -> String:
	var name: String = NAMES[kind]
	if kind == PROBE and interstellar:
		name = "星际探测器"
	return "%s #%d" % [name, id]
