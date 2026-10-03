class_name Balance
extends RefCounted
## 所有数值集中放在这里，方便边玩边调。
## 标「暂定」的是设计说明 §8 里还没定的数值，先用接近旧 Python 版的值。
## 游戏里只读不改；写成 static var 是为了让平衡模拟工具能临时覆盖。

static var AI_COUNT := 4

# 星图生成（按 E7F6 的设想，概率都是暂定）。一个格子大约 1 光年见方，最多一个星系。
static var P_HAS_STAR := 0.55          # α：一个格子有星系的概率
static var STAR_WEIGHTS: Array[int] = [6, 3, 1]  # β：单星、双星、三星的比例（E7F6 估计 6:3:1 或 7:2:1）
static var MAX_PLANETS: Array[int] = [8, 5, 3]   # 单星、双星、三星系统最多几颗行星（0 到这个数随机）
static var P_ROCKY := 0.5              # γ：一颗行星是类地行星（不是类木行星）的概率
static var P_HABITABLE_PLANET := 0.1   # δ：一颗类地行星宜居的概率
static var START_ENERGY := 25
static var START_MINERAL := 25

# 产出（暂定）：每个星系 2 能量，再加每颗恒星 1 能量。
# 这样单星 3、双星 4、三星 5，和旧版一致。
static var ENERGY_PER_SYSTEM := 2
static var ENERGY_PER_STAR := 1
static var MINERAL_PER_COLONY := 2

# 行动点（暂定）：6 减去恒星总数，最少 2。
# 只有母星时，单星 5、双星 4、三星 3，和旧版一致。
static var ACTION_BASE := 6
static var ACTION_MIN := 2

# 探测
static var COST_SCOUT := 2
static var INIT_SCOUT_RANGE := 3.0
static var MAX_SCOUT_RANGE := 10.0
static var INIT_CONE_ANGLE := 15.0  # 圆锥张开的总角度（度）
static var MAX_CONE_ANGLE := 60.0

# 升级探测能力（暂定）：下一回合生效。数值由平衡模拟选出（2026-10-03）：
# 第一个文明灭亡的中位数从第 6 回合推迟到第 11 回合。
static var COST_TELESCOPE := 8       # 能量
static var TELESCOPE_STEP := 10.0    # 张角增加（度）
static var COST_PROBE := 10          # 矿石
static var PROBE_STEP := 1.0         # 探测长度增加

# 光粒（暂定）：圆柱范围，打中最近的敌方星系，让它少一颗恒星。
# 要先建恒星广播器才能发光粒（见下面的广播设施）。射程和半径的上限还没有对应的升级。
static var COST_LIGHTGRAIN := 18
static var INIT_STRIKE_RANGE := 5.0
static var MAX_STRIKE_RANGE := 10.0
static var INIT_STRIKE_RADIUS := 0.5  # 圆柱半径（格），会额外加上半个格子
static var MAX_STRIKE_RADIUS := 2.0

# 战舰（暂定）：派出时同时建造，沿方向飞，碰到敌方星系就让它少一颗恒星，然后消耗掉。
# 比光粒便宜、没有射程限制，但飞得慢。宽度和光粒相同。
static var COST_WARSHIP_ENERGY := 6
static var COST_WARSHIP_MINERAL := 6
static var WARSHIP_SPEED := 2.0

# 预警系统（暂定）：抵消一次打击，用掉后可以再造；同一时间最多一个。下一回合生效。
# 成本由平衡模拟选出（2026-10-03）：5 太便宜，一大半对局 100 回合都打不完。
static var COST_WARNING := 10

# 殖民船（暂定）：派出时同时建造，沿方向飞，停在经过的第一个无主宜居星系，成为新的殖民地。
# 殖民地增加恒星：能量更多，行动点更少（乱纪元）。
# 成本由平衡模拟选出（2026-10-03）：8 太便宜，第 10 回合每个文明已有 6 个以上星系，
# 越滚越大，几乎没有对局能在 100 回合内打完；12 时第 10 回合约 2 个星系。
static var COST_COLONY_ENERGY := 12
static var COST_COLONY_MINERAL := 12
static var COLONY_SHIP_SPEED := 2.0
static var COLONY_SHIP_RADIUS := 0.5  # 和光粒一样，会额外加上半个格子

# 二向箔（暂定）：指定目标坐标，先在发射源准备几个回合，再飞过去；到达目标或途中碰到
# 别人的星系就展开（形状见下面的 FOIL_SQUISH），之后每回合向外扩散一圈，不会停。
# 被压没的星系消失，只有已经降维的文明能活下来。旧版是 20 能量、立即起飞。
static var COST_FOIL := 30
static var FOIL_PREPARE_TURNS := 2
static var FOIL_SPEED := 1.0
# 二向箔展开后的形状：中心那一列完全压平，压平的圆每回合半径加 1 格。
# 圆外面离圆边 x 格的地方，平面上下只剩 FOIL_SQUISH × x² 格高的空间，更高、更低的格子被压没。
# 侧面看像躺倒的沙漏：中心最扁，越往外留下的空间越厚。
static var FOIL_SQUISH := 1.0

# 自身降维（暂定）：花几个回合进入二维，期间不能建造。完成后不怕光粒，被二向箔压平也能活，
# 但产能减半。成本按要带进二维的单位数计算：每个星系、每艘在飞的飞船各算一个。
# 旧版是固定 40 能量、立即生效。
static var COST_REDUCE_BASE := 10
static var COST_REDUCE_PER_UNIT := 5
static var REDUCE_TURNS := 3
# AI 发现二向箔再过这么多回合以内就会压到自己的星系时，开始降维
static var AI_REDUCE_ALERT := 3
# AI 能量攒到这么多、又有已知目标时，先降维再发射二向箔
static var AI_FOIL_ENERGY := 60
# 戴森球（暂定）：建在自己的某个星系上，每个星系最多建到和它的恒星数一样多，
# 所以总上限等于恒星总数。下一回合生效。旧版是 12 矿石、产能 +3、只能建一个。
# 成本由平衡模拟选出（2026-10-03）：12 时 AI 越来越富，几乎每次都有预警系统挡着，
# 100 回合内一局都打不完；16 时和没有戴森球差不多。
static var COST_DYSON := 16        # 矿石
static var DYSON_ENERGY := 3       # 每个每回合多产的能量

# 掩体（按 E7F6 的说明和原著的掩体计划）：只能建在有类木行星的自己的星系上，每个星系一个，
# 下一回合建好。光粒照样打爆恒星，但人躲在类木行星背后活下来：以丢一颗恒星为代价，
# 最后一颗恒星没了，星系也不会丢。战舰照样能摧毁它。
static var COST_BUNKER_ENERGY := 8
static var COST_BUNKER_MINERAL := 8
# 采矿船（按旧版）：建在自己的星系上，每个星系最多一艘，下一回合建好，每回合多产矿石
static var COST_MINER := 4         # 矿石
static var MINER_MINERAL := 2
# 反物质（暂定）：防守用，像预警系统一样先造好存着，下一回合生效，最多存几个。
# 敌方战舰打到自己的任何星系时，先用一个反物质把它拦下，不受损失。挡不住光粒。
static var COST_ANTIMATTER_ENERGY := 6
static var COST_ANTIMATTER_MINERAL := 4
static var MAX_ANTIMATTER := 3
# 黑域（暂定）：在探测范围内指定中心坐标，准备几个回合后生成一个立方体区域（中心向外 1 格，
# 即 3×3×3）。光和飞船都不能穿过黑域的边界（进不去也出不来）：光粒停在边界，战舰和殖民船被困住，
# 探测看不到另一边。二向箔不受影响，压平时黑域消失。所有文明都看得到黑域。旧版是 28 能量、立即生效。
static var COST_BLACK_DOMAIN := 28
static var BLACK_DOMAIN_PREPARE_TURNS := 2
static var BLACK_DOMAIN_RADIUS := 1
# 广播（暂定）：指定任意坐标，准备几个回合后公开，所有文明都知道这个坐标。
# 如果那里有别人的星系，附近的隐藏文明可能出手打它（借刀杀人）。旧版是 4 能量、立即生效。
static var COST_BROADCAST := 6
static var BROADCAST_PREPARE_TURNS := 2
# 隐藏文明：看不见、打不到，只对广播做出反应。
static var HIDDEN_COUNT := 15
# 离广播的坐标多远以内的隐藏文明会听到；越近越可能出手
static var HIDDEN_HEAR_RANGE := 6.0
# 紧挨着的隐藏文明出手的概率，距离越远按比例越小，到 HIDDEN_HEAR_RANGE 时为 0
static var HIDDEN_STRIKE_CHANCE := 0.5
# 出手后几个回合打到
static var HIDDEN_STRIKE_DELAY := 2
# 出手时用二向箔（否则用光粒）的概率
static var HIDDEN_FOIL_CHANCE := 0.1
# 广播设施（按旧版，先建再用）：都是整个文明一个，下一回合建好。
# 恒星广播器：有了才能发光粒和广播。
static var COST_BROADCASTER := 6            # 能量
# 引力波发射器：有了才能广播（不能发光粒）。
static var COST_GRAVITY_ENERGY := 4
static var COST_GRAVITY_MINERAL := 4
# 星舰（按旧版的数值，规则参照原著里「蓝色空间」号这样的星舰文明）：
# 每个文明最多一艘，建在自己的星系上，下一回合建好。星舰不是星系，探测发现不了，
# 光粒（打恒星的）也打不到；但战舰（像水滴）撞上会毁掉它，二向箔压平那一列也会毁掉它。
# 星系全丢了、还有星舰，文明就还活着（星舰文明）：不能建造，收入很少，
# 可以把星舰开到无主的宜居星系，重新建立星系。
static var COST_STARSHIP_ENERGY := 7
static var COST_STARSHIP_MINERAL := 7
static var COST_STARSHIP_MOVE := 2         # 能量，每次移动还花 1 个行动点
static var STARSHIP_JUMP := 4.0            # 每次最多移动几格
static var STARSHIP_ENERGY := 2            # 只剩星舰时每回合的能量
static var STARSHIP_MINERAL := 1           # 只剩星舰时每回合的矿石