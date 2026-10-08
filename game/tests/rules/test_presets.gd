extends "res://tests/rules/rule_suite.gd"
## 数值方案和 balance.gd 的目录。


func test_preset_save_and_read() -> void:
	var values := BalancePresets.file_values()
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
	var before := Replay.balance_values()
	Balance.START_ENERGY = before["START_ENERGY"] + 50
	check(BalancePresets.file_values()["START_ENERGY"] == before["START_ENERGY"], "读到的是 balance.gd 文件里写的值")
	check(BalancePresets.file_values().size() == before.size(), "每个数值都读到了")
	check(BalancePresets.file_values()["STAR_WEIGHTS"].is_typed(), "数组的类型和 Balance 里的一样")
	_restore_balance(before)


## 运行时不读 balance.gd 的原文（导出的游戏里可能没有原文），数值的名字、说明、文件里的值都取自 balance_index.gd。
func test_balance_index_up_to_date() -> void:
	var source := FileAccess.get_file_as_string(BalancePresets.BALANCE_PATH)
	check(BalancePresets.index_source(source) == FileAccess.get_file_as_string(BalancePresets.INDEX_PATH),
			"balance_index.gd 和 balance.gd 对不上，运行 godot_console --headless --path game --script res://tools/make_balance_index.gd 重新生成")
	var count := RegEx.create_from_string("(?m)^static var ").search_all(source).size()
	check(Replay.balance_values().size() == count and BalanceIndex.DOCS.size() == count, "每个数值都在目录里")
	check(BalanceIndex.DOCS["P_HAS_STAR"].begins_with("α") and BalanceIndex.DOCS["ACTION_BASE"].contains("行动点"),
			"说明取自同一行后面的注释，没有时取上一行的")


func test_rewrite_balance_source() -> void:
	var source := FileAccess.get_file_as_string(BalancePresets.BALANCE_PATH)
	var file := BalancePresets.file_values()
	var cost: Dictionary = file["TECH_COST"].duplicate(true)
	cost["grain"] = [21, 1]
	var values := {"P_HAS_STAR": 0.6, "STAR_WEIGHTS": [7, 2, 1], "TECH_COST": cost,
			"START_ENERGY": file["START_ENERGY"], "VISION_HOME": 3.0}
	var r := BalancePresets.rewrite_source(source, values)
	check(r["missing"].is_empty(), "每个名字都找得到")
	check(r["changed"].size() == 4 and not r["changed"].has("START_ENERGY"), "只改值不一样的（没变的不动）")
	var new_source: String = r["source"]
	check(new_source.contains("static var P_HAS_STAR := 0.6") and new_source.contains("# α"), "改了值，行尾注释还在")
	check(new_source.contains("static var STAR_WEIGHTS: Array[int] = [7, 2, 1]"), "类型标注留着")
	check(new_source.contains("static var VISION_HOME := 3.0"), "小数写成带小数点的")
	# 多行的字典重新排版后行数会变，所以只数数值行和注释行
	var count := func(text: String, prefix: String) -> int:
		return Array(text.split("\n")).filter(func(l): return l.begins_with(prefix)).size()
	check(count.call(new_source, "static var") == count.call(source, "static var")
			and count.call(new_source, "#") == count.call(source, "#"), "别的数值行和注释行一行没少")
	# 改过的源码能编译，读出来就是新值
	var fresh := GDScript.new()
	fresh.source_code = RegEx.create_from_string("(?m)^class_name .*$").sub(new_source, "")
	check(fresh.reload() == OK, "改过的 balance.gd 能编译")
	check(fresh.get("P_HAS_STAR") == 0.6 and fresh.get("TECH_COST")["grain"] == [21, 1], "编译后读到新的值")
	check(fresh.get("START_ENERGY") == file["START_ENERGY"], "没改的数值不变")
	check(BalancePresets.rewrite_source(source, {"NO_SUCH": 1})["missing"] == ["NO_SUCH"], "找不到的名字会报出来")
	check(BalancePresets.rewrite_source(source, {})["source"] == source, "什么都不改时源码原样不动")
