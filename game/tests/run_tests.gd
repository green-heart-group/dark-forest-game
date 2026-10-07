extends SceneTree
## 规则测试，不打开窗口：
##   godot_console --headless --path game --script res://tests/run_tests.gd
## 只跑名字里带某个词的测试（文件名或函数名都行），在最后加 -- only=词，例如：
##   godot_console --headless --path game --script res://tests/run_tests.gd -- only=test_ai
## 测试都在 tests/rules/ 里：每个 test_*.gd 是一组，里面每个 test_ 开头的函数是一个测试。有失败时退出码为 1。

const TestLog := preload("res://tests/test_log.gd")
const DIR := "res://tests/rules"


func _init() -> void:
	var results := TestLog.new()
	for file in suite_files():
		var group := file.get_basename()
		var script = load(DIR.path_join(file))
		if script == null or not script.can_instantiate():
			results.fail("脚本编译不了", group)
			continue
		var suite = script.new()
		suite.results = results
		for m in suite.get_method_list():
			var name: String = m["name"]
			var full := group + "." + name
			if name.begins_with("test_") and results.wants(full):
				results.begin(full)
				suite.call(name)
				results.end()
	quit(results.finish("规则测试"))


## tests/rules/ 里所有 test_*.gd，按名字排好。
static func suite_files() -> Array[String]:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("test_") and f.get_extension() == "gd":
			files.append(f)
	files.sort()
	return files
