class_name BalancePresets
extends RefCounted
## 数值方案：把一组和 balance.gd 不一样的数值存成文件，方便导出、导入、切换，也可以写回 balance.gd。
## 方案是文本格式（Godot 的 ConfigFile），人能直接看、能改：
##   [info]
##   note="E7F6 第二轮试玩"
##   [values]
##   FISSION_ENERGY=1
##   STAR_WEIGHTS=[6, 3, 1]
## 共享的方案放 res://balance_presets/（进 git，大家都能用）；自己的放 user://balance_presets/。

const SHARED_DIR := "res://balance_presets"
const USER_DIR := "user://balance_presets"
const BALANCE_PATH := "res://rules/balance.gd"
const INDEX_PATH := "res://rules/balance_index.gd"
const EXT := "cfg"


## 所有方案：[{"name": 名字, "path": 文件路径, "shared": 是不是共享的}]，共享的在前，各自按名字排序。
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for dir in [SHARED_DIR, USER_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue  # 还没存过方案；导出的游戏里也没有共享方案的文件夹
		var names: Array[String] = []
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() == EXT:
				names.append(f.get_basename())
		names.sort()
		for n in names:
			found.append({"name": n, "path": dir.path_join(n + "." + EXT), "shared": dir == SHARED_DIR})
	return found


## 按名字找方案文件（共享的优先），找不到返回空字符串。
static func find(name: String) -> String:
	for p in list():
		if p["name"] == name:
			return p["path"]
	return ""


## 方案的文件路径。名字里不能当文件名的字符换成下划线。
static func path_for(name: String, shared: bool) -> String:
	return (SHARED_DIR if shared else USER_DIR).path_join(name.validate_filename() + "." + EXT)


## 存方案：只存和 balance.gd 不一样的数值。返回 Godot 的错误码。
static func save(path: String, values: Dictionary, note := "") -> Error:
	var base := file_values()
	var cfg := ConfigFile.new()
	cfg.set_value("info", "note", note)
	cfg.set_value("info", "saved", Time.get_datetime_string_from_system())
	for k in values:
		if not base.has(k) or values[k] != base[k]:
			cfg.set_value("values", k, _plain(values[k]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return cfg.save(path)


## 读方案：{"values": {名字: 值}, "note": 说明, "warnings": [读的时候跳过的项]}，读不出来时返回空字典。
## balance.gd 里没有的名字、类型对不上的值都跳过（整数可以当小数用）。
static func read(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var now := Replay.balance_values()
	var values := {}
	var warnings: Array[String] = []
	if cfg.has_section("values"):
		for k in cfg.get_section_keys("values"):
			var v = cfg.get_value("values", k)
			if not now.has(k):
				warnings.append("balance.gd 里没有 %s" % k)
			elif typeof(v) == typeof(now[k]):
				values[k] = v
			elif now[k] is float and v is int:
				values[k] = float(v)
			else:
				warnings.append("%s 的类型不对" % k)
	return {"values": values, "note": cfg.get_value("info", "note", ""), "warnings": warnings}


## 把方案里的数值直接设进 Balance（不经过对局记录；新开一局之前用）。
static func apply(values: Dictionary) -> void:
	var r := Replay.new()
	r.balance = values
	r.apply_balance()


## balance.gd 文件里写的数值（不管这次运行里改过没有）。取自 balance_index.gd，这次运行里写回过的以写回的为准。
## 数组的类型和现在 Balance 里的一样（Array[int] 等）。
static func file_values() -> Dictionary:
	var now := Replay.balance_values()
	var values := {}
	for k in BalanceIndex.DEFAULTS:
		var v = _written.get(k, BalanceIndex.DEFAULTS[k])
		if now.get(k) is Array:
			var typed: Array = now[k].duplicate()
			typed.assign(v)
			v = typed
		values[k] = v.duplicate(true) if v is Array or v is Dictionary else v
	return values


# ---------- 数值目录（balance_index.gd） ----------
# Godot 在运行时列不出 static var，导出的游戏里也读不到 balance.gd 的原文。
# 所以从原文生成一份目录：有哪些数值、每个数值的说明（注释）、文件里写的值。运行时只读目录。

## 这次运行里写回 balance.gd 的数值。目录是编译好的常量，写回后要重开游戏才更新，这之前先记在这里。
static var _written := {}


## 由 balance.gd 的原文生成 balance_index.gd 的内容。
static func index_source(source: String) -> String:
	var names: Array[String] = []
	var docs := {}
	var above := ""
	var after_comment := false  # 上一行是不是注释：是的话这一行注释接着上一段，不是就另起一段
	for line in source.split("\n"):
		line = line.strip_edges()
		if line.begins_with("#"):
			var text := line.trim_prefix("#").strip_edges()
			if text.begins_with("---"):
				above = ""  # 分段标题，不是哪个数值的说明
			else:
				above = above + text if after_comment else text  # 连着几行的注释合成一段
			after_comment = true
			continue
		after_comment = false
		if line.begins_with("static var "):
			var name := line.trim_prefix("static var ").split(" ")[0].split(":")[0]
			var hash_at := line.find("#")
			names.append(name)
			# 说明：同一行后面的注释，没有时用上面那段注释（它是下面连着的这一组数值共同的说明，
			# 所以组里只适合第一个数值的注释要写在同一行后面）
			docs[name] = line.substr(hash_at + 1).strip_edges() if hash_at >= 0 else above
		elif line == "":
			above = ""
	# 文件里写的值：把原文另外编译一份（去掉 class_name，免得和正在用的 Balance 重名），读它的 static var
	var fresh := GDScript.new()
	fresh.source_code = RegEx.create_from_string("(?m)^class_name .*$").sub(source, "")
	if fresh.reload() != OK:
		return ""
	var defaults := {}
	for name in names:
		defaults[name] = fresh.get(name)
	var name_items: PackedStringArray = []
	var doc_items: PackedStringArray = []
	var value_items: PackedStringArray = []
	for name in names:
		name_items.append(format_value(name))
		doc_items.append("%s: %s," % [format_value(name), format_value(docs[name])])
		value_items.append("%s: %s," % [format_value(name), format_value(defaults[name]).replace("\n", "\n\t")])
	return "\n".join([
		"class_name BalanceIndex",
		"extends RefCounted",
		"## balance.gd 的目录：有哪些数值、每个数值的说明、文件里写的值。",
		"## 自动生成，不要手改。改了 balance.gd 以后运行：",
		"##     godot_console --headless --path game --script res://tools/make_balance_index.gd",
		"## （调试面板「写回 balance.gd」时会自动重新生成；没更新时规则测试会失败。）",
		"",
		"const NAMES: Array[String] = [",
		"\t" + ",\n\t".join(name_items) + ",",
		"]",
		"",
		"const DOCS := {",
		"\t" + "\n\t".join(doc_items),
		"}",
		"",
		"const DEFAULTS := {",
		"\t" + "\n\t".join(value_items),
		"}",
		"",
	])


## 按现在的 balance.gd 重新生成 balance_index.gd。返回 Godot 的错误码。
static func write_index() -> Error:
	var text := index_source(FileAccess.get_file_as_string(BALANCE_PATH))
	if text == "":
		return ERR_PARSE_ERROR
	var f := FileAccess.open(ProjectSettings.globalize_path(INDEX_PATH), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


## 能不能写回 balance.gd：只在用编辑器版的 Godot 运行时可以（导出的游戏里没有源码）。
static func can_write_back() -> bool:
	return OS.has_feature("editor") and FileAccess.file_exists(BALANCE_PATH)


## 把数值写回 balance.gd。返回 {"error": 出错原因，成功时为空, "changed": [改了的名字]}。
static func write_back(values: Dictionary) -> Dictionary:
	if not can_write_back():
		return {"error": "只有用编辑器版运行时才能写回 balance.gd", "changed": []}
	var result := rewrite_source(FileAccess.get_file_as_string(BALANCE_PATH), values)
	if not result["missing"].is_empty():
		return {"error": "balance.gd 里找不到：" + "，".join(result["missing"]), "changed": []}
	if result["changed"].is_empty():
		return {"error": "", "changed": []}
	var f := FileAccess.open(ProjectSettings.globalize_path(BALANCE_PATH), FileAccess.WRITE)
	if f == null:
		return {"error": "打不开 balance.gd：%s" % error_string(FileAccess.get_open_error()), "changed": []}
	f.store_string(result["source"])
	f.close()
	for name in result["changed"]:
		_written[name] = values[name]
	var err := write_index()
	if err != OK:
		return {"error": "balance.gd 写好了，但 balance_index.gd 没更新：%s" % error_string(err), "changed": result["changed"]}
	return {"error": "", "changed": result["changed"]}


## 在 balance.gd 的源码里改数值：只换「:=」或「=」后面的值，名字、类型和行尾注释都留着。
## 返回 {"source": 新源码, "changed": [改了的名字], "missing": [源码里找不到的名字]}。
static func rewrite_source(source: String, values: Dictionary) -> Dictionary:
	var decl := RegEx.create_from_string("^(static var (\\w+)(?:\\s*:\\s*[^=]*?)?\\s*:?=\\s*)(.*)$")
	var lines := source.split("\n")
	var out: PackedStringArray = []
	var changed: Array[String] = []
	var seen := {}
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var m := decl.search(line)
		if m == null or not values.has(m.get_string(2)):
			out.append(line)
			i += 1
			continue
		var name := m.get_string(2)
		seen[name] = true
		var head := m.get_string(1)
		var rest := m.get_string(3)
		# 跨几行的字典：一直到单独一行的「}」
		var last := i
		var hash_at := -1
		var old_value := ""
		var comment := ""
		if rest.strip_edges() == "{":
			while last + 1 < lines.size() and lines[last].strip_edges() != "}":
				last += 1
			old_value = "\n".join(lines.slice(i, last + 1)).substr(head.length())
			rest = ""
		else:
			hash_at = rest.find("#")
			old_value = (rest.substr(0, hash_at) if hash_at >= 0 else rest).strip_edges()
			comment = rest.substr(hash_at) if hash_at >= 0 else ""
		var new_value := format_value(values[name])
		var old_parsed = str_to_var(old_value)
		if typeof(old_parsed) == typeof(values[name]) and old_parsed == values[name]:
			for k in range(i, last + 1):
				out.append(lines[k])
			i = last + 1
			continue
		var text := head + new_value
		if comment != "":
			# 注释尽量留在原来的列
			var col := head.length() + (rest.substr(0, hash_at)).length()
			text = text.rpad(maxi(col, text.length() + 2)) + comment
		out.append(text)
		changed.append(name)
		i = last + 1
	var missing: Array[String] = []
	for k in values:
		if not seen.has(k):
			missing.append(k)
	return {"source": "\n".join(out), "changed": changed, "missing": missing}


## 数值写成 GDScript 源码里的样子。字典每行最多放几项，写成多行。
static func format_value(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		var s := str(v)
		return s if s.contains(".") or s.contains("e") or s.contains("inf") or s.contains("nan") else s + ".0"
	if v is String or v is StringName:
		return "\"%s\"" % String(v).c_escape()
	if v is Array:
		var parts: PackedStringArray = []
		for x in v:
			parts.append(format_value(x))
		return "[%s]" % ", ".join(parts)
	if v is Dictionary:
		var lines: PackedStringArray = []
		var line := ""
		for k in v:
			var item := "%s: %s," % [format_value(k), format_value(v[k])]
			if line != "" and line.length() + item.length() > 100:
				lines.append(line)
				line = ""
			line += (" " if line != "" else "") + item
		if line != "":
			lines.append(line)
		return "{\n\t%s\n}" % "\n\t".join(lines)
	return var_to_str(v)


## 存进文件时数组不带类型（写成 [6, 3, 1]，人看得懂）。
static func _plain(v: Variant) -> Variant:
	if v is Array:
		return Array(v)
	return v
