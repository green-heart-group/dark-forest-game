import json
import math
import random
import tkinter as tk
from dataclasses import dataclass, field
from tkinter import filedialog, messagebox, ttk

import matplotlib as mpl

mpl.use("TkAgg")
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
from mpl_toolkits.mplot3d import Axes3D, proj3d  # noqa
from mpl_toolkits.mplot3d.art3d import Line3DCollection

mpl.use("TkAgg")
mpl.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "PingFang SC", "Noto Sans CJK SC", "Arial Unicode MS"]
mpl.rcParams["axes.unicode_minus"] = False

# ==================== 常量 ====================
GRID = 10
LAYERS = 10

START_ENERGY = 25
START_MINERAL = 25
START_HP = 3
MAX_HP = 6

COST_SCOUT = 2
COST_BUILD_TELESCOPE = 3
COST_BUILD_PROBE = 4
COST_BUILD_MINER = 4
COST_BUILD_DYSON = 12
COST_BUILD_WARNING = 5
COST_BUILD_BROADCAST_STAR = 6
COST_BUILD_GRAVITY = 8
COST_BUILD_WARSHIP = 12
COST_BUILD_COLONY = 6
COST_BUILD_STARSHIP = 14
COST_MOVE_STARSHIP = 2
COST_STRIKE_WARSHIP = 3
COST_STRIKE_LIGHTGRAIN = 18
COST_STRIKE_2D = 20
COST_BROADCAST = 4
COST_DIMENSION_REDUCE = 40
COST_BLACK_DOMAIN = 28

INIT_SCOUT_RANGE = 3
INIT_STRIKE_RANGE = 5
INIT_CONE_ANGLE = 15.0
MAX_CONE_ANGLE = 60.0
INIT_WIDTH = 1
MAX_WIDTH = 4
MAX_RANGE = 10

WARSHIP_SPEED = 2
DIM2_SPEED = 1
DIM2_SPREAD = 1

STAR_NONE = "无"
STAR_SINGLE = "单星"
STAR_DOUBLE = "双星"
STAR_TRIPLE = "三星"
STAR_TYPES = [STAR_SINGLE, STAR_DOUBLE, STAR_TRIPLE]

STAR_PROD = {
    STAR_NONE:   {"energy": 0, "mineral": 0, "desc": "无星系"},
    STAR_SINGLE: {"energy": 3, "mineral": 2, "desc": "恒稳系统"},
    STAR_DOUBLE: {"energy": 4, "mineral": 2, "desc": "介稳系统"},
    STAR_TRIPLE: {"energy": 5, "mineral": 2, "desc": "混沌系统"},
}

ACTION_LIMIT = {
    STAR_SINGLE: 5,
    STAR_DOUBLE: 4,
    STAR_TRIPLE: 3,
    STAR_NONE: 3,
}

P_HAS_STAR = 0.55
P_HABITABLE = 0.15
HIDDEN_CIV_COUNT = 15
AI_COUNT = 4

# ==================== 数据结构 ====================
@dataclass
class Unit:
    coord: tuple[int, int, int]
    kind: str = "colony"
    is_home: bool = False
    direction: tuple[float, float, float] | None = None
    float_coord: tuple[float, float, float] | None = None

    def __post_init__(self):
        if self.float_coord is None:
            self.float_coord = (float(self.coord[0]), float(self.coord[1]), float(self.coord[2]))

@dataclass
class BuildTask:
    kind: str
    turns_left: int = 1

@dataclass
class Civ:
    name: str
    is_ai: bool
    home: tuple[int, int, int]
    star_type: str = STAR_SINGLE
    hp: int = START_HP
    energy: int = START_ENERGY
    mineral: int = START_MINERAL
    units: list[Unit] = field(default_factory=list)
    known_enemies: set[str] = field(default_factory=set)
    known_coords: set[tuple[int, int, int]] = field(default_factory=set)
    alive: bool = True
    is_starship: bool = False
    dimension_reduced: bool = False
    scout_range: int = INIT_SCOUT_RANGE
    strike_range: int = INIT_STRIKE_RANGE
    cone_angle: float = INIT_CONE_ANGLE
    width: int = INIT_WIDTH
    strike_damage: int = 1
    has_telescope: bool = False
    has_probe: bool = False
    has_miner: bool = False
    has_dyson: bool = False
    has_warning: bool = False
    has_broadcast_star: bool = False
    has_gravity: bool = False
    has_warship: bool = False
    dim2_foils: list[tuple[tuple[float,float,float], tuple[float,float,float], tuple[int, int, int] | None]] = field(default_factory=list)
    last_strike_from: tuple[int, int, int] | None = None
    hits_taken: int = 0
    hits_dealt: int = 0
    actions_left: int = 0
    build_queue: list[BuildTask] = field(default_factory=list)
    ai_phase: str = "explore"

    def __post_init__(self):
        if not self.units:
            self.units.append(Unit(self.home, kind="colony", is_home=True))
        self.actions_left = self.max_actions()

    def max_actions(self) -> int:
        base = ACTION_LIMIT.get(self.star_type, 3)
        colonies = sum(1 for u in self.units if u.kind == "colony")
        bonus = min(2, max(0, colonies - 1))
        return base + bonus

    def energy_per_turn(self) -> int:
        base = STAR_PROD.get(self.star_type, STAR_PROD[STAR_NONE])["energy"]
        if self.has_dyson:
            base += 3
        if self.dimension_reduced:
            base = base // 2
        return base

    def mineral_per_turn(self) -> int:
        base = STAR_PROD.get(self.star_type, STAR_PROD[STAR_NONE])["mineral"]
        if self.has_miner:
            base += 2
        if self.dimension_reduced:
            base = base // 2
        return base

    def has_colony(self) -> bool:
        return any(u.kind == "colony" for u in self.units)

    def has_starship_unit(self) -> bool:
        return any(u.kind == "starship" for u in self.units)

    def can_build(self) -> bool:
        return self.has_colony()

    def to_dict(self):
        return {
            "name": self.name, "is_ai": self.is_ai, "home": list(self.home),
            "star_type": self.star_type, "hp": self.hp,
            "energy": self.energy, "mineral": self.mineral,
            "units": [{"coord": list(u.coord), "kind": u.kind,
                       "is_home": u.is_home,
                       "direction": list(u.direction) if u.direction else None,
                       "float_coord": list(u.float_coord) if u.float_coord else None}
                      for u in self.units],
            "known_enemies": list(self.known_enemies),
            "known_coords": [list(c) for c in self.known_coords],
            "alive": self.alive, "is_starship": self.is_starship,
            "dimension_reduced": self.dimension_reduced,
            "scout_range": self.scout_range, "strike_range": self.strike_range,
            "cone_angle": self.cone_angle, "width": self.width,
            "strike_damage": self.strike_damage,
            "has_telescope": self.has_telescope, "has_probe": self.has_probe,
            "has_miner": self.has_miner, "has_dyson": self.has_dyson,
            "has_warning": self.has_warning, "has_broadcast_star": self.has_broadcast_star,
            "has_gravity": self.has_gravity, "has_warship": self.has_warship,
            "actions_left": self.actions_left,
            "dim2_foils": [[list(p), list(d), list(t) if t else None] for p, d, t in self.dim2_foils],
            "build_queue": [{"kind": b.kind, "turns_left": b.turns_left} for b in self.build_queue],
            "ai_phase": self.ai_phase,
        }

    @staticmethod
    def from_dict(d):
        c = Civ(d["name"], d["is_ai"], tuple(d["home"]), d.get("star_type", STAR_SINGLE),
                d["hp"], d["energy"], d["mineral"],
                [Unit(tuple(u["coord"]), u.get("kind", "colony"), u.get("is_home", False),
                      tuple(u["direction"]) if u.get("direction") else None,
                      tuple(u["float_coord"]) if u.get("float_coord") else None)
                 for u in d["units"]],
                set(d["known_enemies"]), set(tuple(x) for x in d["known_coords"]),
                d["alive"], d.get("is_starship", False),
                d.get("dimension_reduced", False),
                d["scout_range"], d["strike_range"], d.get("cone_angle", INIT_CONE_ANGLE),
                d["width"], d["strike_damage"],
                d.get("has_telescope", False), d.get("has_probe", False),
                d.get("has_miner", False), d.get("has_dyson", False),
                d.get("has_warning", False), d.get("has_broadcast_star", False),
                d.get("has_gravity", False), d.get("has_warship", False))
        c.actions_left = d.get("actions_left", c.max_actions())
        c.dim2_foils = [(tuple(p), tuple(dd), tuple(t) if t else None)
                        for p, dd, t in d.get("dim2_foils", [])]
        c.build_queue = [BuildTask(b["kind"], b.get("turns_left", 1)) for b in d.get("build_queue", [])]
        c.ai_phase = d.get("ai_phase", "explore")
        return c

# ==================== 矢量计算 ====================
def cylinder_coords(start, slope, width, max_range):
    sx, sy, sz = start
    dx, dy, dz = slope
    norm = math.sqrt(dx*dx + dy*dy + dz*dz)
    if norm < 1e-6:
        return [start]
    ux, uy, uz = dx/norm, dy/norm, dz/norm
    coords = set()
    steps = max_range * 4
    for i in range(steps + 1):
        t = i / steps * max_range
        cx, cy, cz = sx + ux*t, sy + uy*t, sz + uz*t
        for ox in range(-width, width+1):
            for oy in range(-width, width+1):
                for oz in range(-width, width+1):
                    x, y, z = int(round(cx))+ox, int(round(cy))+oy, int(round(cz))+oz
                    if 0 <= x < GRID and 0 <= y < GRID and 0 <= z < LAYERS:
                        coords.add((x, y, z))
    return list(coords)

def cone_coords(start, slope, max_angle_deg, max_range):
    sx, sy, sz = start
    dx, dy, dz = slope
    norm = math.sqrt(dx*dx + dy*dy + dz*dz)
    if norm < 1e-6:
        return [start]
    ux, uy, uz = dx/norm, dy/norm, dz/norm
    half_angle = math.radians(max_angle_deg / 2.0)
    coords = set()
    steps = max_range * 4
    for i in range(steps + 1):
        t = i / steps * max_range
        cx, cy, cz = sx + ux*t, sy + uy*t, sz + uz*t
        radius = t * math.tan(half_angle)
        w = int(math.ceil(radius))
        for ox in range(-w, w+1):
            for oy in range(-w, w+1):
                for oz in range(-w, w+1):
                    x, y, z = int(round(cx))+ox, int(round(cy))+oy, int(round(cz))+oz
                    if 0 <= x < GRID and 0 <= y < GRID and 0 <= z < LAYERS:
                        coords.add((x, y, z))
    return list(coords)

def ray_first_hit(start, slope, max_range, coord_owner_fn, exclude_name=None, black_domains=None):
    sx, sy, sz = start
    dx, dy, dz = slope
    norm = math.sqrt(dx*dx + dy*dy + dz*dz)
    if norm < 1e-6:
        return None, None
    ux, uy, uz = dx/norm, dy/norm, dz/norm
    steps = max_range * 4
    for i in range(steps + 1):
        t = i / steps * max_range
        x = int(round(sx + ux*t))
        y = int(round(sy + uy*t))
        z = int(round(sz + uz*t))
        if not (0 <= x < GRID and 0 <= y < GRID and 0 <= z < LAYERS):
            break
        c = (x, y, z)
        if black_domains and any(b[0] <= c[0] < b[0]+3 and b[1] <= c[1] < b[1]+3 and b[2] <= c[2] < b[2]+3 for b in black_domains):
            return c, None
        owner = coord_owner_fn(c)
        if owner and owner.name != exclude_name:
            return c, owner
    return None, None

# ==================== 游戏状态 ====================
class Game:
    def __init__(self, human_home=None, human_star_type=None):
        self.civs: list[Civ] = []
        self.hidden_civs: list[tuple[int, int, int]] = []
        self.turn = 0
        self.log: list[str] = []
        self.game_over = False
        self.winner: str | None = None
        self.galaxy: dict[tuple[int,int,int], dict] = {}
        self.reduced_plane: dict[tuple[int,int], int] = {}
        self.black_domains: list[tuple[int,int,int]] = []
        self.dim2_centers: list[tuple[int,int,int]] = []
        self.dim2_frontier: set[tuple[int,int]] = set()
        self.visual_changed = False
        self._gen_galaxy()
        self._init_civs(human_home, human_star_type)

    def _gen_galaxy(self):
        for x in range(GRID):
            for y in range(GRID):
                for z in range(LAYERS):
                    c = (x, y, z)
                    if random.random() < P_HAS_STAR:
                        st = random.choice(STAR_TYPES)
                    else:
                        st = STAR_NONE
                    habitable = (st != STAR_NONE) and (random.random() < P_HABITABLE)
                    self.galaxy[c] = {"star": st, "habitable": habitable}

    def _init_civs(self, human_home, human_star_type):
        used = set()
        def rand_coord():
            while True:
                c = (random.randint(0, GRID-1), random.randint(0, GRID-1), random.randint(0, LAYERS-1))
                if c not in used:
                    used.add(c)
                    return c
        if human_home is None:
            candidates = [c for c, info in self.galaxy.items() if info["habitable"]]
            if not candidates:
                candidates = list(self.galaxy.keys())
            human_home = random.choice(candidates)
        used.add(human_home)
        if human_star_type is None:
            human_star_type = self.galaxy[human_home]["star"]
            if human_star_type == STAR_NONE:
                human_star_type = random.choice(STAR_TYPES)
        human = Civ("你", False, human_home, human_star_type)
        self.civs.append(human)
        self.add_log(f"你的母星系：{human_home}，类型：{human_star_type}")
        self.add_log(f"每回合产能：能量 +{human.energy_per_turn()}，矿石 +{human.mineral_per_turn()}")
        for i in range(AI_COUNT):
            ai = Civ(f"AI-{i+1}", True, rand_coord(), random.choice(STAR_TYPES))
            self.civs.append(ai)
        for _ in range(HIDDEN_CIV_COUNT):
            self.hidden_civs.append(rand_coord())

    def human(self) -> Civ:
        return self.civs[0]

    def alive_civs(self) -> list[Civ]:
        return [c for c in self.civs if c.alive]

    def coord_owner(self, coord) -> Civ | None:
        for c in self.civs:
            if not c.alive:
                continue
            for u in c.units:
                if u.coord == coord:
                    return c
        return None

    def add_log(self, msg: str):
        self.log.append(msg)
        if len(self.log) > 500:
            self.log = self.log[-500:]

    def _in_black_domain(self, coord):
        for b in self.black_domains:
            if (b[0] <= coord[0] < b[0]+3 and
                b[1] <= coord[1] < b[1]+3 and
                b[2] <= coord[2] < b[2]+3):
                return True
        return False

    def scout(self, civ, slope):
        if civ.energy < COST_SCOUT or civ.actions_left <= 0:
            return []
        civ.energy -= COST_SCOUT
        civ.actions_left -= 1
        start = civ.home if civ.has_colony() else (civ.units[0].coord if civ.units else civ.home)
        coords = cone_coords(start, slope, civ.cone_angle, civ.scout_range)
        found = []
        for c in coords:
            owner = self.coord_owner(c)
            if owner and owner.name != civ.name:
                found.append(c)
                civ.known_coords.add(c)
                civ.known_enemies.add(owner.name)
        if found:
            self.add_log(f"{civ.name} 探知到 {len(found)} 个文明坐标")
        else:
            self.add_log(f"{civ.name} 探知未发现文明")
        return found

    def _damage_coord(self, coord, damage, attacker, ignore_warning=False):
        owner = self.coord_owner(coord)
        if not owner or owner.name == attacker.name:
            return None
        if owner.has_warning and not ignore_warning:
            owner.has_warning = False
            self.add_log(f"{owner.name} 预警系统抵消一次打击")
            return None
        owner.hp -= damage
        owner.hits_taken += damage
        attacker.hits_dealt += damage
        owner.last_strike_from = attacker.home
        for u in list(owner.units):
            if u.coord == coord:
                owner.units.remove(u)
                break
        self.add_log(f"{attacker.name} 命中 {owner.name}，造成 {damage} 伤害（剩余 HP {owner.hp}）")
        if owner.hp <= 0 or not owner.units:
            owner.alive = False
            self.add_log(f"{owner.name} 被 {attacker.name} 消灭！")
        return owner

    def strike_warship(self, civ, slope):
        if civ.energy < COST_STRIKE_WARSHIP or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        warships = [u for u in civ.units if u.kind == "warship"]
        if not warships:
            return "没有战舰"
        civ.energy -= COST_STRIKE_WARSHIP
        civ.actions_left -= 1
        ship = warships[0]
        ship.direction = slope
        self._move_single_warship(civ, ship)
        return "战舰已派出"

    def _move_single_warship(self, civ, ship):
        if ship.direction is None:
            return
        dx, dy, dz = ship.direction
        norm = math.sqrt(dx * dx + dy * dy + dz * dz)
        if norm < 1e-6:
            return
        ux, uy, uz = dx / norm, dy / norm, dz / norm
        if ship.float_coord is None:
            ship.float_coord = (float(ship.coord[0]), float(ship.coord[1]), float(ship.coord[2]))
        fx, fy, fz = ship.float_coord
        moved = 0
        while moved < WARSHIP_SPEED:
            fx += ux
            fy += uy
            fz += uz
            moved += 1
            ix, iy, iz = int(round(fx)), int(round(fy)), int(round(fz))
            if not (0 <= ix < GRID and 0 <= iy < GRID and 0 <= iz < LAYERS):
                civ.units.remove(ship)
                self.add_log(f"{civ.name} 战舰移出星图，消失")
                self.visual_changed = True
                return
            if self._in_black_domain((ix, iy, iz)) and not self._in_black_domain(ship.coord):
                ship.float_coord = (fx, fy, fz)
                ship.coord = (ix, iy, iz)
                self.add_log(f"{civ.name} 战舰进入黑域，无法离开")
                self.visual_changed = True
                return
            owner = self.coord_owner((ix, iy, iz))
            if owner and owner.name != civ.name:
                ship.float_coord = (fx, fy, fz)
                ship.coord = (ix, iy, iz)
                self.add_log(f"{civ.name} 战舰遭遇 {owner.name}，停驻并打击")
                self._damage_coord((ix, iy, iz), civ.strike_damage, civ)
                ship.direction = None
                self.visual_changed = True
                return
        ship.float_coord = (fx, fy, fz)
        ship.coord = (int(round(fx)), int(round(fy)), int(round(fz)))
        self.visual_changed = True
        self.add_log(f"{civ.name} 战舰移动至 {ship.coord}")

    def strike_lightgrain(self, civ, slope):
        if civ.energy < COST_STRIKE_LIGHTGRAIN or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        if not civ.has_broadcast_star:
            return "需要恒星广播器才能发射光粒"
        civ.energy -= COST_STRIKE_LIGHTGRAIN
        civ.actions_left -= 1
        start = civ.home
        coord, owner = ray_first_hit(start, slope, MAX_RANGE, self.coord_owner,
                                     exclude_name=civ.name,
                                     black_domains=self.black_domains)
        if owner:
            if owner.dimension_reduced:
                self.add_log(f"{civ.name} 光粒命中 {owner.name}，但对方已降维，无效")
                return "目标已降维，无效"
            if owner.has_warning:
                owner.has_warning = False
                owner.has_dyson = False
                owner.has_broadcast_star = False
                self.add_log(f"{owner.name} 预警系统生效，损失一颗恒星及附属设施")
                self.visual_changed = True
                return "命中，但被预警系统抵消"
            owner.alive = False
            owner.units.clear()
            self.add_log(f"{civ.name} 光粒摧毁 {owner.name}！")
            self.visual_changed = True
            return f"命中并摧毁 {owner.name}"
        self.add_log(f"{civ.name} 光粒未命中")
        return "未命中"

    def strike_2d(self, civ, target_coord):
        if civ.energy < COST_STRIKE_2D or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        if target_coord is None:
            return "需要指定目标坐标"
        civ.energy -= COST_STRIKE_2D
        civ.actions_left -= 1
        start = civ.home
        d = (target_coord[0]-start[0], target_coord[1]-start[1], target_coord[2]-start[2])
        if abs(d[0]) + abs(d[1]) + abs(d[2]) < 1e-6:
            return "目标不能是母星"
        start_f = (float(start[0]), float(start[1]), float(start[2]))
        civ.dim2_foils.append((start_f, d, target_coord))
        self.add_log(f"{civ.name} 发射二向箔，目标 {target_coord}")
        self.visual_changed = True
        return f"二向箔已发射，目标 {target_coord}"

    def dimension_reduce(self, civ):
        if civ.energy < COST_DIMENSION_REDUCE or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        civ.energy -= COST_DIMENSION_REDUCE
        civ.actions_left -= 1
        civ.dimension_reduced = True
        self.add_log(f"{civ.name} 主动降维，免疫光粒，仍可使用二向箔")
        return "已降维"

    def drop_black_domain(self, civ, coord):
        if civ.energy < COST_BLACK_DOMAIN or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        if coord is None:
            return "需要指定坐标"
        d = math.dist(civ.home, coord)
        if d > civ.scout_range + 2:
            return "目标超出探测范围"
        civ.energy -= COST_BLACK_DOMAIN
        civ.actions_left -= 1
        self.black_domains.append(coord)
        self.add_log(f"{civ.name} 在 {coord} 投放黑域")
        self.visual_changed = True
        return f"黑域已投放于 {coord}"

    def build(self, civ, kind) -> bool:
        if not civ.can_build() or civ.actions_left <= 0:
            return False
        costs = {
            "telescope": (COST_BUILD_TELESCOPE, 0),
            "probe": (0, COST_BUILD_PROBE),
            "miner": (0, COST_BUILD_MINER),
            "dyson": (0, COST_BUILD_DYSON),
            "warning": (COST_BUILD_WARNING, 0),
            "broadcast_star": (COST_BUILD_BROADCAST_STAR, 0),
            "gravity": (COST_BUILD_GRAVITY // 2, COST_BUILD_GRAVITY // 2),
            "warship": (COST_BUILD_WARSHIP // 2, COST_BUILD_WARSHIP // 2),
            "colony": (COST_BUILD_COLONY // 2, COST_BUILD_COLONY // 2),
            "starship": (COST_BUILD_STARSHIP // 2, COST_BUILD_STARSHIP // 2),
        }
        if kind not in costs:
            return False
        ce, cm = costs[kind]
        if civ.energy < ce or civ.mineral < cm:
            return False
        civ.energy -= ce
        civ.mineral -= cm
        civ.actions_left -= 1
        civ.build_queue.append(BuildTask(kind, 1))
        self.add_log(f"{civ.name} 开始建造 {kind}，下回合生效")
        return True

    def _apply_build(self, civ, kind):
        if kind == "telescope":
            civ.has_telescope = True
            civ.cone_angle = min(MAX_CONE_ANGLE, civ.cone_angle + 15)
            self.add_log(f"{civ.name} 射电望远镜建造完成，张角 {civ.cone_angle}°")
        elif kind == "probe":
            civ.has_probe = True
            civ.scout_range += 2
            self.add_log(f"{civ.name} 星际探测器建造完成，探距 +2")
        elif kind == "miner":
            civ.has_miner = True
            self.add_log(f"{civ.name} 采矿船建造完成")
        elif kind == "dyson":
            civ.has_dyson = True
            self.add_log(f"{civ.name} 戴森球建造完成")
        elif kind == "warning":
            civ.has_warning = True
            self.add_log(f"{civ.name} 预警系统建造完成")
        elif kind == "broadcast_star":
            civ.has_broadcast_star = True
            self.add_log(f"{civ.name} 恒星广播器建造完成")
        elif kind == "gravity":
            civ.has_gravity = True
            self.add_log(f"{civ.name} 引力波发射器建造完成")
        elif kind == "warship":
            civ.has_warship = True
            civ.units.append(Unit(civ.home, kind="warship"))
            self.add_log(f"{civ.name} 战舰建造完成")
        elif kind == "colony":
            civ.units.append(Unit(civ.home, kind="colony_ship"))
            self.add_log(f"{civ.name} 殖民船建造完成")
        elif kind == "starship":
            civ.is_starship = True
            civ.units.append(Unit(civ.home, kind="starship"))
            self.add_log(f"{civ.name} 星舰建造完成")

    def move_colony_ship(self, civ, slope):
        if civ.actions_left <= 0:
            return "行动点不足"
        ships = [u for u in civ.units if u.kind == "colony_ship"]
        if not ships:
            return "没有殖民船"
        civ.actions_left -= 1
        ship = ships[0]
        coords = cylinder_coords(ship.coord, slope, civ.width, MAX_RANGE)
        best = None
        best_d = 1e9
        for c in coords:
            info = self.galaxy.get(c)
            if info and info["habitable"] and self.coord_owner(c) is None:
                d = (c[0]-ship.coord[0])**2 + (c[1]-ship.coord[1])**2 + (c[2]-ship.coord[2])**2
                if d < best_d:
                    best_d = d
                    best = c
        if best:
            civ.units.remove(ship)
            civ.units.append(Unit(best, kind="colony"))
            if civ.hp < MAX_HP:
                civ.hp += 1
            self.add_log(f"{civ.name} 殖民船殖民 {best}")
            self.visual_changed = True
            return f"殖民 {best}"
        civ.units.remove(ship)
        self.add_log(f"{civ.name} 殖民船未找到适宜星系，消失")
        self.visual_changed = True
        return "未找到适宜星系"

    def move_starship(self, civ, slope):
        if civ.energy < COST_MOVE_STARSHIP or civ.actions_left <= 0:
            return "能量不足或行动点不足"
        ships = [u for u in civ.units if u.kind == "starship"]
        if not ships:
            return "没有星舰"
        civ.energy -= COST_MOVE_STARSHIP
        civ.actions_left -= 1
        ship = ships[0]
        coords = cylinder_coords(ship.coord, slope, civ.width, MAX_RANGE)
        target = None
        for c in coords:
            if self.coord_owner(c) is None:
                target = c
        if target:
            ship.coord = target
            self.add_log(f"{civ.name} 星舰移动至 {target}")
            self.visual_changed = True
            return f"移动至 {target}"
        return "无法移动"

    def broadcast(self, civ, coord) -> bool:
        if not (civ.has_broadcast_star or civ.has_gravity):
            return False
        if civ.energy < COST_BROADCAST or civ.actions_left <= 0:
            return False
        civ.energy -= COST_BROADCAST
        civ.actions_left -= 1
        self.add_log(f"{civ.name} 广播坐标 {coord}")
        owner = self.coord_owner(coord)
        if owner and owner.name != civ.name:
            self.add_log(f"⚠ {civ.name} 广播了 {owner.name} 的坐标！")
            owner.last_strike_from = civ.home
            d = math.dist(civ.home, coord)
            prob = max(0.05, 1.0 - d / 15.0)
            if random.random() < prob:
                self._hidden_strike(owner)
        return True

    def _hidden_strike(self, target):
        method = random.choice(["光粒", "二向箔"])
        if method == "光粒":
            if target.dimension_reduced:
                self.add_log(f"隐藏文明光粒打击 {target.name}，但对方已降维，无效")
                return
            if target.has_warning:
                target.has_warning = False
                target.has_dyson = False
                target.has_broadcast_star = False
                self.add_log(f"隐藏文明光粒打击 {target.name}，预警系统生效，损失一颗恒星")
                return
            target.alive = False
            target.units.clear()
            self.add_log(f"隐藏文明光粒摧毁 {target.name}！")
        else:
            if target.dimension_reduced:
                self.add_log(f"隐藏文明二向箔打击 {target.name}，但对方已降维，免疫")
                return
            d = (random.uniform(-1,1), random.uniform(-1,1), random.uniform(-1,1))
            target.dim2_foils.append(((float(target.home[0]), float(target.home[1]), float(target.home[2])), d, None))
            self.add_log(f"隐藏文明向 {target.name} 发射二向箔！")
        self.visual_changed = True

    def _apply_dim2_column(self, x, y, z_plane):
        if (x, y) in self.reduced_plane:
            return
        self.reduced_plane[(x, y)] = z_plane
        self.dim2_frontier.add((x, y))
        self.visual_changed = True
        if z_plane is not None:
            self.dim2_centers.append((x, y, z_plane))
        self.black_domains = [b for b in self.black_domains
                              if not (b[0] == x and b[1] == y)]
        for civ in self.civs:
            if not civ.alive:
                continue
            for u in list(civ.units):
                if u.coord[0] == x and u.coord[1] == y:
                    if civ.dimension_reduced:
                        u.coord = (x, y, z_plane)
                    else:
                        civ.units.remove(u)
                        if not civ.units:
                            civ.alive = False
                            self.add_log(f"{civ.name} 被二维化，灭亡")

    def _spread_dim2(self):
        if not self.dim2_frontier:
            return
        new_frontier = set()
        for (x, y) in list(self.dim2_frontier):
            z = self.reduced_plane.get((x, y), 0)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < GRID and 0 <= ny < GRID:
                        if (nx, ny) not in self.reduced_plane:
                            self._apply_dim2_column(nx, ny, z)
                            new_frontier.add((nx, ny))
        if new_frontier:
            self.visual_changed = True
        self.dim2_frontier = new_frontier

    def next_turn(self):
        if self.game_over:
            return
        self.turn += 1
        for civ in self.civs:
            if not civ.alive:
                continue
            remaining = []
            for task in civ.build_queue:
                task.turns_left -= 1
                if task.turns_left <= 0:
                    self._apply_build(civ, task.kind)
                else:
                    remaining.append(task)
            civ.build_queue = remaining
        for civ in self.civs:
            if civ.alive:
                civ.actions_left = civ.max_actions()
        for civ in self.civs:
            if not civ.alive:
                continue
            if civ.has_colony():
                civ.energy += civ.energy_per_turn()
                civ.mineral += civ.mineral_per_turn()
            elif civ.has_starship_unit():
                civ.energy += 2
                civ.mineral += 1
        for civ in self.civs:
            if not civ.alive:
                continue
            self._move_warships(civ)
        for civ in self.civs:
            if not civ.alive:
                continue
            self._advance_dim2(civ)
        self._spread_dim2()
        self._check_black_domain_death()
        for civ in self.civs:
            if civ.alive and civ.is_ai:
                self.ai_turn(civ)
        h = self.human()
        alive = self.alive_civs()
        if not h.alive:
            self.game_over = True
            self.winner = "AI"
        elif len(alive) == 1 and alive[0].name == h.name:
            self.game_over = True
            self.winner = "你"
        elif len(alive) == 1:
            self.game_over = True
            self.winner = alive[0].name

    def _move_warships(self, civ):
        for ship in list(civ.units):
            if ship.kind == "warship" and ship.direction is not None:
                self._move_single_warship(civ, ship)

    def _advance_dim2(self, civ):
        new_foils = []
        for (pos, slope, target) in civ.dim2_foils:
            dx, dy, dz = slope
            norm = math.sqrt(dx*dx + dy*dy + dz*dz)
            if norm < 1e-6:
                continue
            ux, uy, uz = dx/norm, dy/norm, dz/norm
            if target is not None:
                rem_x = target[0] - pos[0]
                rem_y = target[1] - pos[1]
                rem_z = target[2] - pos[2]
                rem_dist = math.sqrt(rem_x*rem_x + rem_y*rem_y + rem_z*rem_z)
            else:
                rem_dist = None
            if target is not None and rem_dist is not None and rem_dist <= DIM2_SPEED:
                self._apply_dim2_column(target[0], target[1], target[2])
                self.add_log(f"{civ.name} 二向箔到达目标 {target}，展开！")
                self.visual_changed = True
                continue
            nx_f = pos[0] + ux * DIM2_SPEED
            ny_f = pos[1] + uy * DIM2_SPEED
            nz_f = pos[2] + uz * DIM2_SPEED
            nx = int(round(nx_f))
            ny = int(round(ny_f))
            nz = int(round(nz_f))
            if not (0 <= nx < GRID and 0 <= ny < GRID and 0 <= nz < LAYERS):
                self.add_log(f"{civ.name} 二向箔飞出星图，消失")
                self.visual_changed = True
                continue
            c = (nx, ny, nz)
            owner = self.coord_owner(c)
            if owner and owner.name != civ.name:
                self._apply_dim2_column(nx, ny, nz)
                self.add_log(f"{civ.name} 二向箔遭遇 {owner.name}，展开于 {c}")
                self.visual_changed = True
                continue
            new_foils.append(((nx_f, ny_f, nz_f), slope, target))
        civ.dim2_foils = new_foils

    def _check_black_domain_death(self):
        for civ in self.civs:
            if not civ.alive:
                continue
            if not civ.units:
                continue
            all_surrounded = True
            for u in civ.units:
                if not self._in_black_domain(u.coord):
                    all_surrounded = False
                    break
            if all_surrounded:
                civ.alive = False
                self.add_log(f"{civ.name} 被黑域完全包围，灭亡")

    def ai_turn(self, ai):
        if not ai.alive:
            return
        if not ai.known_coords:
            ai.ai_phase = "explore"
        elif ai.hp <= 2:
            ai.ai_phase = "defend"
        elif ai.energy >= COST_STRIKE_LIGHTGRAIN and ai.has_broadcast_star:
            ai.ai_phase = "strike"
        else:
            ai.ai_phase = "expand"

        while ai.actions_left > 0:
            acted = False
            if ai.ai_phase == "explore":
                if ai.energy >= COST_SCOUT:
                    d = (random.uniform(-1,1), random.uniform(-1,1), random.uniform(-1,1))
                    self.scout(ai, d)
                    acted = True
                elif ai.can_build():
                    self.build(ai, "probe")
                    acted = True
            elif ai.ai_phase == "defend":
                if ai.can_build() and not ai.has_warning and ai.energy >= COST_BUILD_WARNING:
                    self.build(ai, "warning")
                    acted = True
                elif ai.can_build() and not ai.has_dyson and ai.mineral >= COST_BUILD_DYSON:
                    self.build(ai, "dyson")
                    acted = True
                elif ai.energy >= COST_DIMENSION_REDUCE:
                    self.dimension_reduce(ai)
                    acted = True
            elif ai.ai_phase == "strike":
                if ai.energy >= COST_STRIKE_LIGHTGRAIN and ai.known_coords and ai.has_broadcast_star:
                    target = random.choice(list(ai.known_coords))
                    d = (target[0]-ai.home[0], target[1]-ai.home[1], target[2]-ai.home[2])
                    self.strike_lightgrain(ai, d)
                    acted = True
                elif ai.energy >= COST_STRIKE_2D and ai.known_coords:
                    target = random.choice(list(ai.known_coords))
                    self.strike_2d(ai, target)
                    acted = True
            elif ai.ai_phase == "expand":
                if ai.can_build() and ai.mineral >= COST_BUILD_COLONY and random.random() < 0.5:
                    self.build(ai, "colony")
                    acted = True
                elif ai.can_build() and ai.energy >= COST_BUILD_WARSHIP and random.random() < 0.3:
                    self.build(ai, "warship")
                    acted = True
                elif ai.energy >= COST_SCOUT:
                    d = (random.uniform(-1,1), random.uniform(-1,1), random.uniform(-1,1))
                    self.scout(ai, d)
                    acted = True
                elif ai.mineral >= COST_BUILD_DYSON and not ai.has_dyson:
                    self.build(ai, "dyson")
                    acted = True
            if not acted:
                break

    def save(self, path):
        data = {
            "civs": [c.to_dict() for c in self.civs],
            "hidden_civs": [list(c) for c in self.hidden_civs],
            "turn": self.turn, "log": self.log,
            "game_over": self.game_over, "winner": self.winner,
            "galaxy": {f"{k[0]},{k[1]},{k[2]}": v for k, v in self.galaxy.items()},
            "reduced_plane": {f"{k[0]},{k[1]}": v for k, v in self.reduced_plane.items()},
            "black_domains": [list(b) for b in self.black_domains],
            "dim2_centers": [list(c) for c in self.dim2_centers],
            "dim2_frontier": [list(f) for f in self.dim2_frontier],
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load(self, path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        self.civs = [Civ.from_dict(d) for d in data["civs"]]
        self.hidden_civs = [tuple(c) for c in data["hidden_civs"]]
        self.turn = data["turn"]
        self.log = data["log"]
        self.game_over = data["game_over"]
        self.winner = data["winner"]
        self.galaxy = {}
        for k, v in data["galaxy"].items():
            parts = k.split(",")
            self.galaxy[(int(parts[0]), int(parts[1]), int(parts[2]))] = v
        self.reduced_plane = {}
        for k, v in data.get("reduced_plane", {}).items():
            parts = k.split(",")
            self.reduced_plane[(int(parts[0]), int(parts[1]))] = v
        self.black_domains = [tuple(b) for b in data.get("black_domains", [])]
        self.dim2_centers = [tuple(c) for c in data.get("dim2_centers", [])]
        self.dim2_frontier = set(tuple(f) for f in data.get("dim2_frontier", []))

# ==================== 图形界面 ====================
class GameUI:
    def __init__(self, root):
        self.root = root
        self.root.title("三体·黑暗森林 3D 桌游模拟器")
        self.root.geometry("1600x950")
        self.game = None
        self.selected_coord = None
        self.slope_x = tk.DoubleVar(value=1.0)
        self.slope_y = tk.DoubleVar(value=0.0)
        self.slope_z = tk.DoubleVar(value=0.0)
        self.show_preview = tk.BooleanVar(value=True)
        self.origin_choice = tk.StringVar(value="母星系")
        self.hover_text = None
        self.blink_state = True
        self.preview_kind = None
        self.zoom = 1.0
        self.target_x = tk.IntVar(value=0)
        self.target_y = tk.IntVar(value=0)
        self.target_z = tk.IntVar(value=0)
        self._dirty = True
        self._build_ui()
        self.ask_start()
        if self.game is not None:
            self.refresh()
            self._animate()

    def ask_start(self):
        dlg = tk.Toplevel(self.root)
        dlg.title("开局设置")
        dlg.geometry("440x320")
        dlg.configure(bg="#101020")
        tk.Label(dlg, text="自定义你的母星系", fg="#00ffcc", bg="#101020",
                 font=("Consolas", 14, "bold")).pack(pady=10)
        tk.Label(dlg, text="坐标 (0-9)", fg="#ffcc00", bg="#101020",
                 font=("Consolas", 11)).pack()
        frame = tk.Frame(dlg, bg="#101020")
        frame.pack(pady=6)
        ex = tk.Entry(frame, width=5, bg="#050510", fg="#00ffcc", font=("Consolas", 12))
        ey = tk.Entry(frame, width=5, bg="#050510", fg="#00ffcc", font=("Consolas", 12))
        ez = tk.Entry(frame, width=5, bg="#050510", fg="#00ffcc", font=("Consolas", 12))
        for e, lab in [(ex, "x"), (ey, "y"), (ez, "z")]:
            tk.Label(frame, text=lab, fg="#00ffcc", bg="#101020",
                     font=("Consolas", 12)).pack(side=tk.LEFT)
            e.pack(side=tk.LEFT, padx=4)
        ex.insert(0, str(random.randint(0, GRID-1)))
        ey.insert(0, str(random.randint(0, GRID-1)))
        ez.insert(0, str(random.randint(0, LAYERS-1)))
        tk.Label(dlg, text="星系类型（可留空由系统决定）", fg="#ffcc00", bg="#101020",
                 font=("Consolas", 11)).pack(pady=(12, 2))
        star_var = tk.StringVar(value="")
        for st in STAR_TYPES:
            info = STAR_PROD[st]
            tk.Radiobutton(dlg, text=f"{st}（能量+{info['energy']}，矿石+{info['mineral']}）",
                           variable=star_var, value=st, fg="#00ffcc", bg="#101020",
                           selectcolor="#203040", font=("Consolas", 10)).pack(anchor="w", padx=30)
        tk.Radiobutton(dlg, text="随机", variable=star_var, value="",
                       fg="#00ffcc", bg="#101020", selectcolor="#203040",
                       font=("Consolas", 10)).pack(anchor="w", padx=30)

        def confirm():
            try:
                x, y, z = int(ex.get()), int(ey.get()), int(ez.get())
                if not (0 <= x < GRID and 0 <= y < GRID and 0 <= z < LAYERS):
                    raise ValueError
            except ValueError:
                messagebox.showwarning("输入错误", "坐标必须是 0-9 的整数")
                return
            st = star_var.get() if star_var.get() else None
            self.game = Game((x, y, z), st)
            self._dirty = True
            dlg.destroy()
            self.refresh()
            self._animate()

        def on_close():
            if self.game is None:
                self.game = Game(None, None)
            self._dirty = True
            dlg.destroy()
            self.refresh()
            self._animate()

        dlg.protocol("WM_DELETE_WINDOW", on_close)
        tk.Button(dlg, text="开始游戏", command=confirm, bg="#203040", fg="#00ffcc",
                  font=("Consolas", 12, "bold")).pack(pady=14)

    def _build_ui(self):
        left_bar = tk.Frame(self.root, bg="#0a0a1a", width=360)
        left_bar.pack(side=tk.LEFT, fill=tk.Y)
        left_bar.pack_propagate(False)

        self.info_top = tk.Label(
            left_bar, text="", fg="#00ffcc", bg="#0a0a1a",
            font=("Consolas", 11), justify=tk.LEFT, anchor="nw",
            bd=2, relief=tk.SOLID,
        )
        self.info_top.pack(fill=tk.X, padx=6, pady=6)

        tk.Label(left_bar, text="已探知文明坐标", fg="#ffcc00", bg="#0a0a1a",
                 font=("Consolas", 11, "bold")).pack(anchor="w", padx=6, pady=(12, 2))
        list_frame = tk.Frame(left_bar, bg="#0a0a1a")
        list_frame.pack(fill=tk.BOTH, expand=True, padx=6, pady=2)
        self.known_listbox = tk.Listbox(
            list_frame, bg="#050510", fg="#ff8800",
            font=("Consolas", 10), selectbackground="#203040",
        )
        scrollbar = tk.Scrollbar(list_frame, command=self.known_listbox.yview)
        self.known_listbox.config(yscrollcommand=scrollbar.set)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.known_listbox.pack(fill=tk.BOTH, expand=True)

        center = tk.Frame(self.root, bg="#0a0a1a")
        center.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.fig = Figure(figsize=(8, 7), facecolor="#050510")
        self.ax = self.fig.add_subplot(111, projection="3d")
        self.fig.subplots_adjust(left=0.02, right=0.98, top=0.98, bottom=0.02)
        self.canvas = FigureCanvasTkAgg(self.fig, master=center)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)
        self.canvas.mpl_connect("scroll_event", self.on_scroll)

        right = tk.Frame(self.root, bg="#101020", width=560)
        right.pack(side=tk.RIGHT, fill=tk.Y)
        right.pack_propagate(False)

        f0 = tk.LabelFrame(right, text="打击起点", fg="#ffcc00", bg="#101020",
                           font=("Consolas", 10, "bold"))
        f0.pack(fill=tk.X, padx=8, pady=4)
        self.origin_menu = ttk.Combobox(f0, textvariable=self.origin_choice,
                                        values=["母星系"], state="readonly",
                                        font=("Consolas", 10))
        self.origin_menu.pack(fill=tk.X, padx=6, pady=4)

        f1 = tk.LabelFrame(right, text="矢量方向（斜率系数）", fg="#ffcc00", bg="#101020",
                           font=("Consolas", 10, "bold"))
        f1.pack(fill=tk.X, padx=8, pady=4)
        for name, var in [("dx", self.slope_x), ("dy", self.slope_y), ("dz", self.slope_z)]:
            row = tk.Frame(f1, bg="#101020")
            row.pack(fill=tk.X, padx=4, pady=1)
            tk.Label(row, text=name, fg="#00ffcc", bg="#101020", width=3,
                     font=("Consolas", 10)).pack(side=tk.LEFT)
            tk.Scale(row, from_=-2.0, to=2.0, resolution=0.1, orient=tk.HORIZONTAL,
                     variable=var, bg="#101020", fg="#00ffcc", highlightthickness=0,
                     length=400, command=lambda _: self.refresh()).pack(side=tk.LEFT, padx=4)

        f_target = tk.LabelFrame(right, text="目标坐标（二向箔/黑域/广播）",
                                 fg="#ffcc00", bg="#101020",
                                 font=("Consolas", 10, "bold"))
        f_target.pack(fill=tk.X, padx=8, pady=4)
        for name, var in [("x", self.target_x), ("y", self.target_y), ("z", self.target_z)]:
            row = tk.Frame(f_target, bg="#101020")
            row.pack(fill=tk.X, padx=4, pady=1)
            tk.Label(row, text=name, fg="#00ffcc", bg="#101020", width=3,
                     font=("Consolas", 10)).pack(side=tk.LEFT)
            tk.Scale(row, from_=0, to=9, resolution=1, orient=tk.HORIZONTAL,
                     variable=var, bg="#101020", fg="#00ffcc", highlightthickness=0,
                     length=400, command=lambda _: self.on_target_change()).pack(side=tk.LEFT, padx=4)

        f2 = tk.LabelFrame(right, text="行动", fg="#ffcc00", bg="#101020",
                           font=("Consolas", 10, "bold"))
        f2.pack(fill=tk.X, padx=8, pady=4)
        actions = [
            ("探测 (2E)", "scout", "scout", "消耗 2 能量，圆锥探知"),
            ("广播坐标 (4E)", "broadcast", None, "消耗 4 能量，需广播器"),
            ("射电望远镜 (3E)", "build_telescope", None, "消耗 3 能量，张角+15°"),
            ("星际探测器 (4M)", "build_probe", None, "消耗 4 矿石，探距+2"),
            ("采矿船 (4M)", "build_miner", None, "消耗 4 矿石，产矿+2"),
            ("戴森球 (12M)", "build_dyson", None, "消耗 12 矿石，产能+3"),
            ("预警系统 (5E)", "build_warning", None, "消耗 5 能量，抵消一次打击"),
            ("恒星广播器 (6E)", "build_broadcast_star", None, "消耗 6 能量，光粒前置"),
            ("引力波发射器 (4E4M)", "build_gravity", None, "消耗 4E+4M"),
            ("建造战舰 (6E6M)", "build_warship", None, "消耗 6E+6M"),
            ("建造殖民船 (3E3M)", "build_colony", None, "消耗 3E+3M"),
            ("建造星舰 (7E7M)", "build_starship", None, "消耗 7E+7M"),
            ("殖民船移动", "move_colony", "move_colony", "不消耗，自动殖民最近适宜星系"),
            ("星舰移动 (2E)", "move_starship", "move", "消耗 2 能量"),
            ("战舰打击 (3E)", "strike_warship", "strike", "消耗 3 能量，派出战舰"),
            ("光粒打击 (18E)", "strike_lightgrain", "strike", "消耗 18 能量，需广播器"),
            ("二向箔打击 (20E)", "strike_2d", "strike", "消耗 20 能量，需指定目标"),
            ("自身降维 (40E)", "dimension_reduce", None, "免疫光粒，仍可用二向箔"),
            ("投放黑域 (28E)", "drop_black_domain", None, "在探测范围生成 3×3×3 黑域"),
            ("结束回合", "end_turn", None, "重置行动点"),
            ("存档", "save", None, ""),
            ("读档", "load", None, ""),
        ]
        grid = tk.Frame(f2, bg="#101020")
        grid.pack(fill=tk.X, padx=4, pady=4)
        for i, (label, val, kind, tip) in enumerate(actions):
            btn = tk.Button(grid, text=label, command=lambda v=val: self.do_action(v),
                            bg="#203040", fg="#00ffcc", activebackground="#305060",
                            font=("Consolas", 9, "bold"), width=20, height=2)
            btn.grid(row=i//2, column=i%2, padx=3, pady=2, sticky="nsew")
            if kind is not None:
                btn.bind("<Enter>", lambda e, k=kind, t=tip: self.on_button_hover(k, t))
            else:
                btn.bind("<Enter>", lambda e, t=tip: self.on_button_hover(None, t))
            btn.bind("<Leave>", lambda e: self.on_button_leave())
        grid.columnconfigure(0, weight=1)
        grid.columnconfigure(1, weight=1)

        f5 = tk.LabelFrame(right, text="事件日志", fg="#ffcc00", bg="#101020",
                           font=("Consolas", 10, "bold"))
        f5.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        self.log_text = tk.Text(f5, bg="#050510", fg="#cccccc", font=("Microsoft YaHei", 10),
                                wrap=tk.WORD)
        scrollbar2 = tk.Scrollbar(f5, command=self.log_text.yview)
        self.log_text.config(yscrollcommand=scrollbar2.set)
        scrollbar2.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=4, pady=4)
        self.log_text.config(state=tk.DISABLED)

    def on_target_change(self):
        self.selected_coord = (self.target_x.get(),
                               self.target_y.get(),
                               self.target_z.get())
        self.refresh()

    def on_button_hover(self, kind, tip):
        self.preview_kind = kind
        self.hover_text = tip
        self.draw_3d()

    def on_button_leave(self):
        self.preview_kind = None
        self.hover_text = None
        self.draw_3d()

    def on_scroll(self, event):
        if self.game is None:
            return
        if event.inaxes != self.ax:
            return
        if event.button == "up":
            self.zoom *= 0.9
        else:
            self.zoom *= 1.1
        self.zoom = max(0.3, min(3.0, self.zoom))
        self.refresh()

    def _animate(self):
        if self.game is None:
            return
        self.blink_state = not self.blink_state
        self.root.after(600, self._animate)

    def _current_origin(self):
        h = self.game.human()
        choice = self.origin_choice.get()
        for u in h.units:
            label = f"{u.kind} ({u.coord[0]},{u.coord[1]},{u.coord[2]})"
            if label == choice:
                return u.coord
        return h.home

    def draw_3d(self):
        if self.game is None:
            return
        self.ax.clear()
        self.ax.set_facecolor("#050510")
        cx = (GRID - 1) / 2
        cy = (GRID - 1) / 2
        cz = (LAYERS - 1) / 2
        xr = (GRID - 1) / 2 * self.zoom
        yr = (GRID - 1) / 2 * self.zoom
        zr = (LAYERS - 1) / 2 * self.zoom
        self.ax.set_xlim(cx - xr, cx + xr)
        self.ax.set_ylim(cy - yr, cy + yr)
        self.ax.set_zlim(cz - zr, cz + zr)
        self.ax.set_xlabel("X", color="#00ffcc")
        self.ax.set_ylabel("Y", color="#00ffcc")
        self.ax.set_zlabel("Z", color="#00ffcc")
        self.ax.tick_params(colors="#446677")
        for pane in [self.ax.xaxis, self.ax.yaxis, self.ax.zaxis]:
            pane.pane.set_facecolor("#0a0a20")
            pane.pane.set_edgecolor("#1a3a4a")

        h = self.game.human()
        reduced = self.game.reduced_plane

        def map_coord(c):
            x, y, z = c
            if (x, y) in reduced:
                return (x, y, reduced[(x, y)])
            return c

        # ===== 空间网格：Line3DCollection 一次性绘制 =====
        segments = []
        colors = []
        for x in range(GRID):
            for y in range(GRID):
                if (x, y) in reduced:
                    z_plane = reduced[(x, y)]
                    segments.append([(x, y, 0), (x, y, z_plane)])
                    colors.append("#888888")
                    segments.append([(x, y, z_plane), (x, y, LAYERS-1)])
                    colors.append("#888888")
                else:
                    segments.append([(x, y, 0), (x, y, LAYERS-1)])
                    colors.append("#444466")
        for y in range(GRID):
            for z in range(LAYERS):
                pts = []
                for x in range(GRID):
                    if (x, y) in reduced:
                        pts.append((x, y, reduced[(x, y)]))
                    else:
                        pts.append((x, y, z))
                for i in range(len(pts)-1):
                    segments.append([pts[i], pts[i+1]])
                    colors.append("#444466")
        for x in range(GRID):
            for z in range(LAYERS):
                pts = []
                for y in range(GRID):
                    if (x, y) in reduced:
                        pts.append((x, y, reduced[(x, y)]))
                    else:
                        pts.append((x, y, z))
                for i in range(len(pts)-1):
                    segments.append([pts[i], pts[i+1]])
                    colors.append("#444466")
        if segments:
            lc = Line3DCollection(segments, colors=colors, linewidths=0.4, alpha=0.4)
            self.ax.add_collection3d(lc)

        # 黑域
        for b in self.game.black_domains:
            bx, by, bz = b
            for ox in range(3):
                for oy in range(3):
                    for oz in range(3):
                        self.ax.scatter(bx+ox, by+oy, bz+oz,
                                        c="#000000", s=60, marker="s",
                                        edgecolors="#4444ff", linewidths=0.5)

        # 星系蓝点：仅悬停“殖民船移动”时显示
        if self.preview_kind == "move_colony":
            gx, gy, gz, gc = [], [], [], []
            for c, info in self.game.galaxy.items():
                if info["star"] == STAR_NONE:
                    continue
                if not info["habitable"]:
                    continue
                gx.append(c[0]); gy.append(c[1]); gz.append(c[2])
                gc.append("#224466")
            if gx:
                self.ax.scatter(gx, gy, gz, c=gc, s=10, alpha=0.7)

        # 你的单位
        for u in h.units:
            if u.kind == "warship" and u.float_coord is not None:
                mc = u.float_coord
            else:
                mc = map_coord(u.coord)
            if u.kind == "colony":
                color, marker, size = "#00ffcc", "D", 140
            elif u.kind == "warship":
                color, marker, size = "#ff8800", "^", 160
            elif u.kind == "starship":
                color, marker, size = "#ff00ff", "s", 160
            elif u.kind == "colony_ship":
                color, marker, size = "#00ff88", "o", 140
            else:
                color, marker, size = "#00ffcc", "o", 120
            self.ax.scatter(*mc, c=color, s=size, marker=marker,
                            edgecolors="#ffffff", linewidths=1.5)

        # 已知文明坐标
        for c in h.known_coords:
            mc = map_coord(c)
            self.ax.scatter(*mc, c="#ff4444", s=100, marker="X",
                            edgecolors="#ffffff", linewidths=1)

        # 二向箔位置
        for civ in self.game.civs:
            for item in civ.dim2_foils:
                px, py, pz = item[0]
                ix, iy, iz = int(round(px)), int(round(py)), int(round(pz))
                mc = map_coord((ix, iy, iz))
                self.ax.scatter(*mc, c="#aa00ff", s=220, marker="*",
                                edgecolors="#ffffff", linewidths=1.5)

        # 当前选中目标
        if self.selected_coord is not None:
            self.ax.scatter(*self.selected_coord, c="#ffffff", s=220, marker="s",
                            edgecolors="#00aaff", linewidths=2)

        # 蓝色箭头射线
        slope = (self.slope_x.get(), self.slope_y.get(), self.slope_z.get())
        origin = self._current_origin()
        norm = math.sqrt(slope[0]**2 + slope[1]**2 + slope[2]**2)
        if norm > 1e-6:
            ux, uy, uz = slope[0]/norm, slope[1]/norm, slope[2]/norm
            arrow_len = MAX_RANGE
            ex = origin[0] + ux * arrow_len
            ey = origin[1] + uy * arrow_len
            ez = origin[2] + uz * arrow_len
            try:
                self.ax.quiver(origin[0], origin[1], origin[2],
                               ex - origin[0], ey - origin[1], ez - origin[2],
                               color="#00aaff", arrow_length_ratio=0.1, linewidth=2)
            except Exception:
                pass

        # 宽度预览
        if self.preview_kind is not None:
            if self.preview_kind == "scout":
                coords = cone_coords(origin, slope, h.cone_angle, h.scout_range)
                color = "#00ffff"
            elif self.preview_kind == "strike":
                coords = cylinder_coords(origin, slope, h.width, h.strike_range)
                color = "#ff4444"
            elif self.preview_kind == "move":
                coords = cylinder_coords(origin, slope, h.width, MAX_RANGE)
                color = "#44ff44"
            elif self.preview_kind == "move_colony":
                ships = [u for u in h.units if u.kind == "colony_ship"]
                if ships:
                    origin = ships[0].coord
                coords = cylinder_coords(origin, slope, h.width, MAX_RANGE)
                color = "#44ff44"
            else:
                coords = []
            if coords:
                cx2 = [c[0] for c in coords]
                cy2 = [c[1] for c in coords]
                cz2 = [c[2] for c in coords]
                self.ax.scatter(cx2, cy2, cz2, c=color, s=12, alpha=0.5)
            if self.blink_state:
                self.ax.scatter(*origin, c="#ffff00", s=200, marker="^",
                                edgecolors="#ffffff", linewidths=2)
            else:
                self.ax.scatter(*origin, c="#ffaa00", s=140, marker="^",
                                edgecolors="#ffffff", linewidths=1)

        if self.hover_text:
            self.ax.text2D(0.02, 0.95, self.hover_text, transform=self.ax.transAxes,
                           color="#ffff00", fontsize=11, fontweight="bold")

        self.canvas.draw()

    def update_status(self):
        if self.game is None:
            return
        h = self.game.human()
        alive_ai = [c for c in self.game.civs[1:] if c.alive]
        build_str = ", ".join([f"{b.kind}({b.turns_left})" for b in h.build_queue]) or "无"
        top_txt = (
            f"回合：{self.game.turn}  行动点：{h.actions_left}/{h.max_actions()}\n"
            f"母星坐标：{h.home}  星系：{h.star_type}\n"
            f"产能：能量 +{h.energy_per_turn()}，矿石 +{h.mineral_per_turn()}\n"
            f"HP：{h.hp}  能量：{h.energy}  矿石：{h.mineral}\n"
            f"张角：{h.cone_angle}°  探知距离：{h.scout_range}  打击宽度：{h.width}\n"
            f"设施：望远镜{'✓' if h.has_telescope else '✗'} "
            f"探测器{'✓' if h.has_probe else '✗'} "
            f"采矿船{'✓' if h.has_miner else '✗'} "
            f"戴森球{'✓' if h.has_dyson else '✗'}\n"
            f"预警{'✓' if h.has_warning else '✗'} "
            f"恒星广播{'✓' if h.has_broadcast_star else '✗'} "
            f"引力波{'✓' if h.has_gravity else '✗'}\n"
            f"战舰{'✓' if h.has_warship else '✗'}  星舰{'✓' if h.is_starship else '✗'}  "
            f"降维{'✓' if h.dimension_reduced else '✗'}\n"
            f"建造中：{build_str}\n"
            f"存活 AI：{len(alive_ai)} 个\n"
        )
        self.info_top.config(text=top_txt)

        self.known_listbox.delete(0, tk.END)
        for c in sorted(h.known_coords):
            self.known_listbox.insert(tk.END, f"  {c}")

        origins = ["母星系"]
        for u in h.units:
            if u.kind in ("warship", "starship"):
                origins.append(f"{u.kind} ({u.coord[0]},{u.coord[1]},{u.coord[2]})")
        self.origin_menu["values"] = origins
        if self.origin_choice.get() not in origins:
            self.origin_choice.set("母星系")

    def update_log(self):
        if self.game is None:
            return
        self.log_text.config(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        for line in self.game.log[-120:]:
            self.log_text.insert(tk.END, line + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)

    def refresh(self):
        if self.game is None:
            return
        self.draw_3d()
        self.update_status()
        self.update_log()

    def do_action(self, action):
        if self.game is None:
            return
        if self.game.game_over:
            messagebox.showinfo("游戏结束", f"胜者：{self.game.winner}")
            return
        h = self.game.human()
        if not h.alive:
            messagebox.showinfo("你已灭亡", "游戏结束")
            return
        slope = (self.slope_x.get(), self.slope_y.get(), self.slope_z.get())
        if action == "scout":
            self.game.scout(h, slope)
        elif action == "build_telescope":
            self.game.build(h, "telescope")
        elif action == "build_probe":
            self.game.build(h, "probe")
        elif action == "build_miner":
            self.game.build(h, "miner")
        elif action == "build_dyson":
            self.game.build(h, "dyson")
        elif action == "build_warning":
            self.game.build(h, "warning")
        elif action == "build_broadcast_star":
            self.game.build(h, "broadcast_star")
        elif action == "build_gravity":
            self.game.build(h, "gravity")
        elif action == "build_warship":
            self.game.build(h, "warship")
        elif action == "build_colony":
            self.game.build(h, "colony")
        elif action == "build_starship":
            self.game.build(h, "starship")
        elif action == "move_colony":
            msg = self.game.move_colony_ship(h, slope)
            messagebox.showinfo("殖民船移动", msg)
        elif action == "move_starship":
            msg = self.game.move_starship(h, slope)
            messagebox.showinfo("星舰移动", msg)
        elif action == "strike_warship":
            msg = self.game.strike_warship(h, slope)
            messagebox.showinfo("战舰打击", msg)
        elif action == "strike_lightgrain":
            msg = self.game.strike_lightgrain(h, slope)
            messagebox.showinfo("光粒打击", msg)
        elif action == "strike_2d":
            if self.selected_coord:
                msg = self.game.strike_2d(h, self.selected_coord)
                messagebox.showinfo("二向箔打击", msg)
            else:
                messagebox.showwarning("未选择坐标", "请先选择目标坐标")
        elif action == "dimension_reduce":
            msg = self.game.dimension_reduce(h)
            messagebox.showinfo("自身降维", msg)
        elif action == "drop_black_domain":
            if self.selected_coord:
                msg = self.game.drop_black_domain(h, self.selected_coord)
                messagebox.showinfo("投放黑域", msg)
            else:
                messagebox.showwarning("未选择坐标", "请先选择目标坐标")
        elif action == "broadcast":
            if self.selected_coord:
                if not self.game.broadcast(h, self.selected_coord):
                    messagebox.showwarning("广播失败", "需要恒星广播器或引力波发射器，且能量足够")
            else:
                messagebox.showwarning("未选择坐标", "请先选择广播坐标")
        elif action == "end_turn":
            self.game.next_turn()
        elif action == "save":
            path = filedialog.asksaveasfilename(defaultextension=".json")
            if path:
                self.game.save(path)
                messagebox.showinfo("存档", "已保存")
        elif action == "load":
            path = filedialog.askopenfilename(filetypes=[("JSON", "*.json")])
            if path:
                self.game.load(path)
                messagebox.showinfo("读档", "已加载")
        self.refresh()


def main() -> None:  # 启动游戏的代码放在函数里
    root = tk.Tk()
    app = GameUI(root)
    root.mainloop()


if __name__ == "__main__":  # 直接运行时调用它
    main()
    