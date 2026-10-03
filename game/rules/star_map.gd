class_name StarMap
extends RefCounted
## 星图：每个格子有没有星系、是几星系统、有哪些行星、适不适合殖民。
## 一个格子大约 1 光年见方，所以一个格子最多一个星系。
## 规则代码，不依赖任何画面节点，可以单独测试。生成用的概率在 Balance 里。

enum Star { NONE, SINGLE, DOUBLE, TRIPLE }

const SIZE := 10

## 格子坐标 (Vector3i) -> Star
var stars: Dictionary[Vector3i, int] = {}
## 适合殖民的格子（星系里至少有一颗宜居的类地行星）
var habitable: Dictionary[Vector3i, bool] = {}
## 每个星系的类地行星（固体行星）数
var rocky: Dictionary[Vector3i, int] = {}
## 每个星系的类木行星（气体行星）数。有类木行星的星系可以建掩体挡光粒。
var gas: Dictionary[Vector3i, int] = {}


## 用同一个种子生成的星图总是一样，方便复现和测试。按 E7F6 的设想，每个格子依次决定：
## 1. 有没有星系（概率 α）；
## 2. 几颗恒星（单星最常见，三星最少）；
## 3. 几颗行星：单星系统稳定，行星最多；双星、三星不稳定，行星容易被吞掉，依次变少；
## 4. 每颗行星是类地还是类木（类地的概率 γ）；
## 5. 每颗类地行星宜不宜居（概率 δ）。有一颗宜居，这个星系就能殖民。
static func generate(seed_value: int) -> StarMap:
	var m := StarMap.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var weights := Balance.STAR_WEIGHTS
	var total_weight := 0
	for w in weights:
		total_weight += w
	for x in SIZE:
		for y in SIZE:
			for z in SIZE:
				var c := Vector3i(x, y, z)
				var star := Star.NONE
				if rng.randf() < Balance.P_HAS_STAR:
					var roll := rng.randi_range(1, total_weight)
					star = Star.SINGLE
					while roll > weights[star - 1]:
						roll -= weights[star - 1]
						star += 1
				m.stars[c] = star
				if star == Star.NONE:
					continue
				var planets := rng.randi_range(0, Balance.MAX_PLANETS[star - 1])
				var n_rocky := 0
				var livable := false
				for i in planets:
					if rng.randf() < Balance.P_ROCKY:
						n_rocky += 1
						if rng.randf() < Balance.P_HABITABLE_PLANET:
							livable = true
				m.rocky[c] = n_rocky
				m.gas[c] = planets - n_rocky
				if livable:
					m.habitable[c] = true
	return m


static func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < SIZE and c.y >= 0 and c.y < SIZE and c.z >= 0 and c.z < SIZE


func star_at(c: Vector3i) -> int:
	return stars.get(c, Star.NONE)


func is_habitable(c: Vector3i) -> bool:
	return habitable.has(c)


## 一个星系里有几颗恒星（单星 1，双星 2，三星 3）。
static func star_count(star: int) -> int:
	return star
