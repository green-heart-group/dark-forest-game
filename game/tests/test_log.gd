extends RefCounted
## 记下一次测试的结果，规则测试和画面测试共用：
## 数测试和检查；失败时写出是哪个测试；只跑名字里带某个词的测试（命令行最后加 -- only=词）；
## 最后打印一行汇总和最慢的几个测试，返回退出码（有失败时是 1）。

## 只跑名字里带这个词的测试；空的时候全跑
var only := ""
var tests := 0
var checks := 0
## 失败的测试名（同一个测试失败几次只记一次）
var failed: Array[String] = []

var _name := ""
var _checks_before := 0
var _started_at := 0
var _all_started_at := 0
## 测试名 → 花了多少毫秒
var _times := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.trim_prefix("only=")
	_all_started_at = Time.get_ticks_msec()


## 这个测试要不要跑。
func wants(name: String) -> bool:
	return only == "" or name.contains(only)


func begin(name: String) -> void:
	_name = name
	tests += 1
	_checks_before = checks
	_started_at = Time.get_ticks_msec()


func end() -> void:
	_times[_name] = Time.get_ticks_msec() - _started_at
	# 测试代码出错时，GDScript 不停下来，只是这个函数后面的都不跑了，所以一次检查都没做到也算失败
	if checks == _checks_before:
		fail("没有跑到任何检查（可能是代码出错）")
	_name = ""


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fail(what)


## 比较两个值，不一样时写出实际值和期望值。整数和小数按数值比，其他类型不同就算不一样。
func check_eq(actual, expected, what: String) -> void:
	checks += 1
	if not _same(actual, expected):
		fail("%s（实际 %s，期望 %s）" % [what, var_to_str(actual), var_to_str(expected)])


## 记一次失败。不在某个测试里时（比如测试文件编译不了），用 where 说明是哪里。
func fail(what: String, where := "") -> void:
	var name := _name if _name != "" else where
	if not failed.has(name):
		failed.append(name)
	push_error("失败：[%s] %s" % [name, what])


## 打印汇总，返回退出码。
func finish(title: String) -> int:
	if only != "" and tests == 0 and failed.is_empty():
		fail("没有名字里带「%s」的测试" % only, "only")
	var seconds := (Time.get_ticks_msec() - _all_started_at) / 1000.0
	print("%s：%d 个测试，%d 个失败（%d 次检查，%.1f 秒）" % [title, tests, failed.size(), checks, seconds])
	var slow := _times.keys().filter(func(n): return _times[n] >= 1000)
	slow.sort_custom(func(a, b): return _times[a] > _times[b])
	if not slow.is_empty():
		var parts := slow.slice(0, 3).map(func(n): return "%s %.1f 秒" % [n, _times[n] / 1000.0])
		print("最慢的：" + "，".join(parts))
	if not failed.is_empty():
		print("失败的测试：" + "，".join(failed))
	return 1 if not failed.is_empty() else 0


static func _same(a, b) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return a == b
	return typeof(a) == typeof(b) and a == b
