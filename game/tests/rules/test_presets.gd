extends "res://tests/rules/rule_suite.gd"
## 数值方案和 balance.cfg。


func test_preset_save_and_read() -> void:
	var values := Balance.file_values()
	values["START_ENERGY"] = values["START_ENERGY"] + 7
	values["STAR_WEIGHTS"] = [7, 2, 1]
	var path := BalancePresets.USER_DIR.path_join("_test.cfg")
	check(BalancePresets.save(path, values, "测试") == OK, "方案能存文件")
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("STAR_WEIGHTS=[7, 2, 1]") and not text.contains("P_HAS_STAR"), "只存改过的数值，数组写成人看得懂的样子")
	var p := BalancePresets.read(path)
	check(p["values"].size() == 2 and p["values"]["START_ENERGY"] == values["START_ENERGY"], "读回来的数值一样")
	check(p["values"]["STAR_WEIGHTS"] == [7, 2, 1] and p["note"] == "测试" and p["warnings"].is_empty(), "数组和说明也读得回来")
	check(BalancePresets.list().any(func(x): return x["name"] == "_test" and not x["shared"]), "列表里有这个自己的方案")
	DirAccess.remove_absolute(path)
	check(BalancePresets.read(path).is_empty(), "文件不存在时返回空的")


func test_preset_read_skips_bad_values() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("values", "NO_SUCH_VALUE", 1)
	cfg.set_value("values", "START_ENERGY", "很多")
	cfg.set_value("values", "P_HAS_STAR", 1)
	var path := BalancePresets.USER_DIR.path_join("_bad.cfg")
	DirAccess.make_dir_recursive_absolute(BalancePresets.USER_DIR)
	cfg.save(path)
	var p := BalancePresets.read(path)
	check(p["warnings"].size() == 2, "没有的名字、类型不对的值都跳过并说明")
	check(p["values"].get("P_HAS_STAR") is float, "整数可以当小数用")
	DirAccess.remove_absolute(path)


func test_file_values_ignore_runtime_changes() -> void:
	var before := Balance.values()
	Balance.START_ENERGY = before["START_ENERGY"] + 50
	check(Balance.file_values()["START_ENERGY"] == before["START_ENERGY"], "读到的是 balance.cfg 里写的值")
	check(Balance.file_values().size() == before.size(), "每个数值都读到了")
	check(Balance.file_values()["STAR_WEIGHTS"].is_typed(), "数组的类型和 Balance 里的一样")


## Godot 在运行时列不出 static var，数值的名字、说明、文件里的值都取自 balance.cfg，所以两边的名字要对得上。
func test_balance_file_matches_declarations() -> void:
	var source := FileAccess.get_file_as_string("res://rules/balance.gd")
	var declared: Array[String] = []
	for m in RegEx.create_from_string("(?m)^static var ([A-Z]\\w*)").search_all(source):
		declared.append(m.get_string(1))
	check_eq(Balance.names(), declared, "balance.cfg 和 balance.gd 里的数值一样多、顺序一样（对不上时跑 uv run game/tools/sync_balance.py）")
	var docs := Balance.docs()
	check(docs.size() == declared.size(), "每个数值都有说明这一项")
	check(docs["P_HAS_STAR"].begins_with("α") and docs["ACTION_BASE"].contains("行动点"),
			"说明取自同一行后面的注释，没有时取上一行的")
	check(docs["AI_FOIL_ENERGY"].begins_with("AI 能量") and docs["START_ENERGY"] == "", "分段标题不算说明，空行以后不再沿用上面的说明")


func test_balance_loaded_from_file() -> void:
	var file := Balance.file_values()
	var now := Balance.values()
	for k in file:
		check(typeof(now[k]) == typeof(file[k]) and now[k] == file[k], "%s 是 balance.cfg 里写的值" % k)
	check(Balance.STAR_WEIGHTS.is_typed() and Balance.TECH_COST.has("grain"), "数组和字典也读进来了")


func test_rewrite_balance_file() -> void:
	var source := FileAccess.get_file_as_string(BalancePresets.BALANCE_PATH)
	var file := Balance.file_values()
	var cost: Dictionary = file["TECH_COST"].duplicate(true)
	cost["grain"] = [21, 1]
	var values := {"P_HAS_STAR": 0.6, "STAR_WEIGHTS": [7, 2, 1], "TECH_COST": cost,
			"START_ENERGY": file["START_ENERGY"], "VISION_HOME": 3.0}
	var r := BalancePresets.rewrite_source(source, values)
	check(r["missing"].is_empty(), "每个名字都找得到")
	check(r["changed"].size() == 4 and not r["changed"].has("START_ENERGY"), "只改值不一样的（没变的不动）")
	var new_source: String = r["source"]
	check(new_source.contains("\nP_HAS_STAR = 0.6") and new_source.contains("; α"), "改了值，行尾注释还在")
	check(new_source.contains("\nSTAR_WEIGHTS = [7, 2, 1]"), "数组写成人看得懂的样子")
	check(new_source.contains("\nVISION_HOME = 3.0"), "小数写成带小数点的")
	# 多行的字典重新排版后行数会变，所以只数数值行和注释行
	var count := func(text: String, pattern: String) -> int:
		return RegEx.create_from_string("(?m)" + pattern).search_all(text).size()
	check(count.call(new_source, "^\\w+ =") == count.call(source, "^\\w+ =")
			and count.call(new_source, "^;") == count.call(source, "^;"), "别的数值行和注释行一行没少")
	check(Balance.parse_docs(new_source) == Balance.docs(), "说明一字没变")
	# 改过的文件 Godot 读得出来，读出来就是新值
	var cfg := ConfigFile.new()
	check(cfg.parse(new_source) == OK, "改过的 balance.cfg 读得出来")
	check(cfg.get_value("values", "P_HAS_STAR") == 0.6 and cfg.get_value("values", "TECH_COST")["grain"] == [21, 1], "读到新的值")
	check(cfg.get_value("values", "START_ENERGY") == file["START_ENERGY"], "没改的数值不变")
	check(BalancePresets.rewrite_source(source, {"NO_SUCH": 1})["missing"] == ["NO_SUCH"], "找不到的名字会报出来")
	check(BalancePresets.rewrite_source(source, {})["source"] == source, "什么都不改时原文一字不动")

func test_set_value_checks_type() -> void:
	var before := Balance.values()
	check_eq(Balance.set_value("P_HAS_STAR", 1), "", "整数可以当小数用")
	check_eq(Balance.values()["P_HAS_STAR"], 1.0, "存成小数")
	check(Balance.set_value("START_ENERGY", 2.5) != "", "整数的数值不能设成小数")
	check_eq(Balance.START_ENERGY, before["START_ENERGY"], "设不了时不改")
	check(Balance.set_value("NO_SUCH", 1) != "" and Balance.set_value("STAR_WEIGHTS", "很多") != "", "没有的数值、类型不对的值设不了")
	check_eq(Balance.set_value("STAR_WEIGHTS", [7, 2, 1]), "", "数组可以设")
	check(Balance.STAR_WEIGHTS.is_typed() and Balance.STAR_WEIGHTS == [7, 2, 1], "数组原地改，Array[int] 的类型留着")
	check_eq(Balance.apply({"START_ENERGY": 1, "NO_SUCH": 1}).size(), 1, "一次设几个时，设不了的跳过并说明")
	check_eq(Balance.START_ENERGY, 1, "能设的照样设好")