extends "res://tests/rules/rule_suite.gd"
## 星图和母星系的位置。


## 规则：星图和星系生成
func test_same_seed_same_map() -> void:
	var a := StarMap.generate(42)
	var b := StarMap.generate(42)
	check(a.stars == b.stars, "同一个种子应生成同样的星系")
	check(a.habitable == b.habitable, "同一个种子应生成同样的宜居格子")


## 规则：星图和星系生成
func test_map_covers_every_cell() -> void:
	var m := StarMap.generate(1)
	check(m.stars.size() == StarMap.SIZE ** 3, "每个格子都应有记录")


## 规则：星图和星系生成
func test_star_ratio_roughly_right() -> void:
	var m := StarMap.generate(7)
	var with_star := 0
	for c in m.stars:
		if m.stars[c] != StarMap.Star.NONE:
			with_star += 1
	var ratio := with_star / float(m.stars.size())
	check(ratio > 0.45 and ratio < 0.65, "有星系的比例应接近 0.55，实际 %.2f" % ratio)


## 规则：星图和星系生成
func test_map_generation_follows_planet_rules() -> void:
	var m := StarMap.generate(11)
	for c in m.stars:
		var star: int = m.stars[c]
		if star == StarMap.Star.NONE:
			check(not m.rocky.has(c) and not m.habitable.has(c), "没有星系的格子没有行星")
			continue
		check(m.rocky[c] + m.gas[c] <= Balance.MAX_PLANETS[star - 1], "行星数不超过上限")
		if m.habitable.has(c):
			check(m.rocky[c] > 0, "宜居星系至少有一颗类地行星")


## 规则：星图和星系生成
func test_bounds() -> void:
	check(StarMap.in_bounds(Vector3i(0, 0, 0)), "原点在图内")
	check(StarMap.in_bounds(Vector3i(8, 8, 8)), "(8,8,8) 在图内")
	check(not StarMap.in_bounds(Vector3i(10, 0, 0)), "(10,0,0) 在图外")


## 规则：星图和星系生成
func test_new_game_places_civs() -> void:
	var s := GameState.new_game(5)
	check(s.civs.size() == 1 + Balance.AI_COUNT, "一个人类加 %d 个 AI" % Balance.AI_COUNT)
	var homes := {}
	for civ in s.civs:
		check(s.map.star_at(civ.home) != StarMap.Star.NONE, "%s 的母星必须有星系" % civ.name)
		check(civ.actions_left == civ.action_points(s.map), "%s 开局行动点已发放" % civ.name)
		check(civ.has_tech("probe") and civ.has_tech("colony") and not civ.has_tech("starship"), "开局只有 0 级科技（殖民船在 0 级）")
		homes[civ.home] = true
	check(homes.size() == s.civs.size(), "母星不能重叠")
	check(s.hidden.size() == Balance.HIDDEN_COUNT, "有 %d 个隐藏文明" % Balance.HIDDEN_COUNT)
	check(s.hidden.all(func(h): return not StarMap.in_bounds(h)), "隐藏文明都在星图外")
	var again := GameState.new_game(5)
	check(again.human().home == s.human().home, "同一个种子，母星位置相同")


## 规则：星图和星系生成，F3.1
func test_homes_far_apart() -> void:
	var close := 0
	for seed_value in 50:
		var s := GameState.new_game(seed_value)
		for a in s.civs:
			for b in s.civs:
				if a != b and Vector3(a.home).distance_to(Vector3(b.home)) < Balance.HOME_MIN_DISTANCE:
					close += 1
	check(close == 0, "50 局里母星系都彼此隔开 %.0f 格以上（太近的 %d 对）" % [Balance.HOME_MIN_DISTANCE, close])
