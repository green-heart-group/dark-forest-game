class_name Balance
extends RefCounted
## 所有数值集中放在这里，方便边玩边调。
## 大部分是暂定的（游戏设计 §12、§13），价格先由 AI 拟定，平衡模拟后再调。
## 游戏里只读不改；写成 static var 是为了让平衡模拟工具能临时覆盖。

static var AI_COUNT := 4

# ---------- 星图生成（按 E7F6 的设想，概率都是暂定） ----------
# 一个格子 1 光年见方，最多一个星系。
static var P_HAS_STAR := 0.55          # α：一个格子有星系的概率
static var STAR_WEIGHTS: Array[int] = [6, 3, 1]  # β：单星、双星、三星的比例（E7F6 估计 6:3:1 或 7:2:1）
static var MAX_PLANETS: Array[int] = [8, 5, 3]   # 单星、双星、三星系统最多几颗行星（0 到这个数随机）
static var P_ROCKY := 0.5              # γ：一颗行星是类地行星（不是类木行星）的概率
static var P_HABITABLE_PLANET := 0.1   # δ：一颗类地行星宜居的概率
static var HOME_MIN_DISTANCE := 5.0    # 各文明的母星系彼此至少隔开几格（E7F6 2026-10-07 第三次）

# ---------- 资源和行动点 ----------
static var START_ENERGY := 20
static var START_MINERAL := 20
# 裂变能（科技 002）：自己星系里的每颗类地行星每回合多少能量（E7F6 2026-10-06 第二次：+1）
static var FISSION_ENERGY := 1
# 每个星系本身的能量：每个星系 ENERGY_PER_SYSTEM，再加每颗恒星 ENERGY_PER_STAR
# （E7F6 2026-10-06 第二次：只按恒星算，每颗 3E）
static var ENERGY_PER_SYSTEM := 0
static var ENERGY_PER_STAR := 3
static var MINERAL_PER_COLONY := 2   # 每个星系本身每回合的矿石
# 行动点 = ACTION_BASE − 母星系的恒星数，每多一个殖民地 +1（E2），最少 ACTION_MIN
static var ACTION_BASE := 6
static var ACTION_MIN := 2
# 星系全丢了、只剩星舰时每回合的收入
static var STARSHIP_ENERGY := 2
static var STARSHIP_MINERAL := 1

# ---------- 科技（游戏设计 §5） ----------
# 每项科技的价格：[能量, 矿石]。越高级、收益越高越贵（T2）。0 级开局就有，不用买。
static var TECH_COST := {
	"dyson": [10, 0], "interstellar_probe": [8, 6], "warship": [10, 8], "bunker": [8, 4],
	"devourer": [16, 12], "grain": [20, 0], "gravity": [12, 4], "antimatter": [16, 0], "warp": [24, 8],
	"starship": [16, 12], "beam": [12, 0], "torpedo": [4, 10], "hbomb": [16, 12], "sophon": [24, 0],
	"dark_energy": [40, 0], "dimension": [50, 0], "domain": [40, 0],
}
# III 级的门槛：每回合的能量收入达到多少（E8：35E）
static var TIER3_ENERGY := 35
# 一级开放以后，至少过这么多回合才开下一级（E8：先发展一段时间）
static var TIER_GAP := 8
# II 级的「接触」：自己的舰船和别人的舰船相距这么近（E8）
static var CONTACT_RANGE := 1.0
# AI 每回合不花资源直接得到一项能升的科技的机会（技术爆炸，D6）
static var TECH_BURST_CHANCE := 0.02

# ---------- 视野（游戏设计 §4） ----------
static var VISION_HOME := 2.0
static var VISION_COLONY := 1.5        # 殖民星系和星舰
static var VISION_SHIP := 1.0          # 战舰、殖民船、吞噬者
static var PROBE_ANGLE := 15.0         # 探测器圆锥的张角（度）
static var PROBE_LENGTH := 1.0
static var IPROBE_ANGLE := 30.0        # 星际探测器
static var IPROBE_LENGTH := 1.5
static var MAX_CONE_ANGLE := 60.0
# 射电望远镜（科技 003）：每次升级所有视野和圆锥长度 +TELESCOPE_STEP 格，张角 +15°，最多 4 次（T18）
static var TELESCOPE_MAX := 4
static var TELESCOPE_STEP := 0.5
static var TELESCOPE_ANGLE_STEP := 15.0
static var COST_TELESCOPE := 12        # 能量，每次升级
# 近光速舰船（每回合超过这么多格）留下航迹
static var WAKE_SPEED := 0.9
# 看到的飞船过了这么多回合就不再画
static var SIGHTING_KEEP := 12

# ---------- 移动（游戏设计 §3）：[最高速度, 加速度] ----------
static var GRAIN_MOVE := [1.0, 0.5]
static var PROBE_MOVE := [0.99, 0.02]
static var IPROBE_MOVE := [0.99, 0.1]
static var WARSHIP_MOVE := [0.8, 0.1]
static var STARSHIP_MOVE := [0.6, 0.1]
static var COLONY_MOVE := [0.2, 0.05]
static var DEVOURER_MOVE := [0.15, 0.03]
static var WARP_MOVE := [1.0, 1.0]
# 探测器选「先慢速飞出视野」时，在自己星系的视野里最快多少（G13.4）
static var SLOW_START_SPEED := 0.15

# ---------- 单位和设施 ----------
# 单位造好后停在星系里，下一步「派出」时才出发（建造和调度各花 1 行动点）。
static var COST_PROBE := [0, 3]
static var COST_PROBE_LAUNCH := 1      # 能量
static var COST_WARSHIP := [8, 10]
static var COST_WARSHIP_GRAVITY := 4   # 带引力波广播器的战舰多花的能量（科技 203）
static var COST_WARSHIP_LAUNCH := 2    # 能量
static var COST_TURN := 2              # 战舰、吞噬者转向，能量（G8）
static var COST_COLONY := [10, 10]
static var COST_STARSHIP := [16, 16]
static var COST_STARSHIP_MOVE := 2
static var COST_DEVOURER := [10, 20]
static var COST_DEVOURER_LAUNCH := 2
static var COST_WARP_EXTRA := 4        # 装了曲率引擎的舰船多花的能量（科技 205）
static var MAX_WARSHIPS := 3
static var MAX_COLONY_SHIPS := 2
static var MAX_STARSHIPS := 1
static var MAX_DEVOURERS := 1          # 暂定（游戏设计 §12）
static var DEVOURER_MINERAL := 20      # 吃掉一颗类地行星得到的矿石（暂定）

# 采矿船：建在自己的星系上，下一回合建好，每艘每回合多产矿石
static var COST_MINER := [0, 4]
static var MINER_MINERAL := 2
static var MAX_MINERS := 5             # 每个星系最多几艘（E7F6 2026-10-07 第三次：1 → 5）
# 戴森球：总数不超过自己所有星系的恒星总数，下一回合建好
static var COST_DYSON := [0, 16]
static var DYSON_ENERGY := 6
# 掩体：只能建在有类木行星的自己的星系上，每个星系一个，建好后一直存在
static var COST_BUNKER := [8, 8]
# 恒星广播器：建在某个星系上，从那里广播
static var COST_BROADCASTER := [6, 0]
# 预警系统：整个文明一个；范围从母星系和殖民星系算起，可以升级
static var COST_WARNING := [10, 0]
static var WARNING_RANGE := 2.0
static var WARNING_MAX := 4
static var COST_WARNING_UPGRADE := 8   # 能量，每次 +1 格
# 反物质：要花大量能量，最多存 1 份；敌方战舰在自己星系这么近时可以下令用掉
static var COST_ANTIMATTER := [16, 0]
static var MAX_ANTIMATTER := 1
static var ANTIMATTER_RANGE := 1.0
# 光粒：「造光粒」花矿石，存在那个星系里，每个星系最多 1 颗；「发射光粒」花能量（G2）
static var COST_GRAIN := [0, 8]
static var COST_GRAIN_LAUNCH := 18
static var GRAIN_RADIUS := 0.5         # 打击范围：半径 0.5 的圆柱（会再加半个格子）

# ---------- 战舰的打击（游戏设计 §6） ----------
static var WARSHIP_RANGE := 1.0        # 「附近」：周围 1.0 格（T19）

# ---------- 战舰的武器（T23） ----------
# 升级后，之后造的战舰都带上，每带一种多花 COST_xxx_EXTRA [能量, 矿石]；
# 敌方战舰进了射程就自动开火，每次花 xxx_SHOT [能量, 矿石]
static var BEAM_RANGE := 1.5           # 高能粒子束：直接毁掉
static var TORPEDO_RANGE := 2.0        # 星际鱼雷：打中 TORPEDO_HITS 次才毁掉
static var HBOMB_RANGE := 1.0          # 次声波氢弹：杀死船员，收回对方造船花的资源
static var COST_BEAM_EXTRA := [4, 0]
static var COST_TORPEDO_EXTRA := [0, 4]
static var COST_HBOMB_EXTRA := [4, 4]
static var BEAM_SHOT := [3, 0]
static var TORPEDO_SHOT := [0, 3]
static var HBOMB_SHOT := [3, 3]
static var TORPEDO_HITS := 2          # 星际鱼雷打中几次才毁掉一艘战舰

# ---------- 智子（D5） ----------
static var COST_SOPHON := [40, 1]     # 造一个智子 [能量, 矿石]
static var COST_SOPHON_LAUNCH := 3     # 能量
static var SOPHON_MOVE := [0.99, 0.99]  # 一出发就是 0.99
static var MAX_SOPHONS := 2           # 同时最多有几个智子
# 到了别人的母星系以后，对方这么多回合不能升级科技、这么多回合达到的科技等级条件不算
static var SOPHON_RESEARCH_TURNS := 5
static var SOPHON_TIER_TURNS := 15

# ---------- 降维（游戏设计 §9） ----------
static var COST_FOIL := 30
static var COST_LINE_FOIL := 30
static var FOIL_PREPARE_TURNS := 2
static var FOIL_SPEED := 0.2           # 展开前每回合飞多远（B7）
static var FOIL_SPREAD := 0.9          # 展开后每回合向外扩散多远（T17）
# 二向箔展开后的形状：中心那一列完全压平，压平的圆半径每回合加 FOIL_SPREAD。
# 圆外面离圆边 x 格的地方，平面上下只剩 FOIL_SQUISH × x² 格高的空间，更高、更低的格子被压没。
static var FOIL_SQUISH := 1.0
# 奇异点：全图压成直线后，准备这么多回合，完成的文明降到零维，赢得对局
static var COST_SINGULARITY := 30
static var SINGULARITY_TURNS := 3
# 全图压成直线后，这么多回合内没人完成奇异点，就平局
static var LINE_GRACE_TURNS := 15
# 自身降维：花几个回合进入下一维，期间不能建造。全部单位一起携带、按个数收费。
static var COST_REDUCE_BASE := 10
static var COST_REDUCE_PER_UNIT := 5
static var REDUCE_TURNS := 3
# AI 发现二向箔再过这么多回合以内就会压到自己的星系时，开始降维
static var AI_REDUCE_ALERT := 4
# AI 能量攒到这么多、又有已知目标时，先降维再发射二向箔
static var AI_FOIL_ENERGY := 60

# ---------- 黑域（游戏设计 §7） ----------
static var COST_BLACK_DOMAIN := 28
static var BLACK_DOMAIN_PREPARE_TURNS := 2
static var BLACK_DOMAIN_TURNS := 10    # 中心的光速保持 0 几回合，然后慢慢恢复（G14）
static var DOMAIN_INCOME := 0.1        # 被困在黑域里的星系，产出变成原来的多少（向上取整，G14）
# 每格的光速（G14）：光速低于 GRAIN_MIN_LIGHT 的地方光粒没有杀伤力，也算「在黑域里」；
# 舰船实际速度低于 SHIP_MIN_SPEED 就停在原地，这样过 SHIP_STUCK_TURNS 回合就消失。
# 光速低于 SHIP_MIN_SPEED 的格子，光和情报也过不去。
static var GRAIN_MIN_LIGHT := 0.95
static var SHIP_MIN_SPEED := 0.01
static var SHIP_STUCK_TURNS := 5

# ---------- 广播和隐藏文明（游戏设计 §8） ----------
static var COST_BROADCAST := 6
# 广播者离被广播的坐标这么远时，有一半机会暴露自己（B6）
static var BROADCAST_EXPOSE_HALF := 4.0
static var HIDDEN_COUNT := 15         # 星图外的隐藏文明有几个
# 隐藏文明离被广播的坐标多远以内会出手；越近越可能出手
static var HIDDEN_HEAR_RANGE := 10.0
# 听到以后每回合出手的机会（紧挨着时），距离越远按比例越小
static var HIDDEN_STRIKE_CHANCE := 0.15
# 听到以后最多等这么多回合，过了就不管了
static var HIDDEN_PATIENCE := 10
# 出手时用二向箔（否则用光粒）的机会
static var HIDDEN_FOIL_CHANCE := 0.1
# 隐藏文明的二向箔和别人的一样快（游戏设计 §8）
static var HIDDEN_FOIL_SPEED := 0.2

# ---------- 暗能量采集（科技 301） ----------
static var DARK_ENERGY_CELLS := 10     # 视野里每这么多格 +1 能量
