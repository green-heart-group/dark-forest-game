extends SceneTree
## 规则测试，不打开窗口：
##   godot_console --headless --path game --script res://tests/run_tests.gd
## 只跑名字里带某个词的测试（文件名或函数名都行），在最后加 -- only=词，例如：
##   godot_console --headless --path game --script res://tests/run_tests.gd -- only=test_ai
## 其他参数（tests=、report=、stop_on_fail）见 tests/test_log.gd；平常用 tools/test.py，它会分几个进程同时跑。
## 测试都在 tests/rules/ 里：每个 test_*.gd 是一组，里面每个 test_ 开头的函数是一个测试，名字是「文件名.函数名」。
## 有失败时退出码为 1。

const TestLog := preload("res://tests/test_log.gd")
const DIR := "res://tests/rules"

var results := TestLog.new()
## 文件名（不带 .gd）→ 这组测试的对象；编译不了的是 null
var _suites := {}


func _init() -> void:
	# 给了 tests= 时按里面的顺序跑，否则按文件名、函数名的顺序
	var names: Array[String] = results.listed if not results.listed.is_empty() else all_tests()
	for full in names:
		if not results.wants(full):
			continue
		var suite = _suite(full.get_slice(".", 0))
		if suite == null:
			continue
		results.begin(full)
		var balance := Balance.values()
		suite.call(full.get_slice(".", 1))
		Balance.apply(balance)  # 测试改过的数值都换回来，中途出错跳出来的也一样
		results.end()
	quit(results.finish("规则测试"))


## 所有规则测试的名字，按文件名排好，同一个文件里按函数出现的顺序。
func all_tests() -> Array[String]:
	var names: Array[String] = []
	for file in suite_files():
		var group := file.get_basename()
		var suite = _suite(group)
		if suite == null:
			continue
		for m in suite.get_method_list():
			if m["name"].begins_with("test_"):
				names.append(group + "." + m["name"])
	return names


func _suite(group: String):
	if not _suites.has(group):
		var script = load(DIR.path_join(group + ".gd"))
		if script == null or not script.can_instantiate():
			results.fail("脚本编译不了", group)
			_suites[group] = null
		else:
			var suite = script.new()
			suite.results = results
			_suites[group] = suite
	return _suites[group]


## tests/rules/ 里所有 test_*.gd，按名字排好。
static func suite_files() -> Array[String]:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("test_") and f.get_extension() == "gd":
			files.append(f)
	files.sort()
	return files
