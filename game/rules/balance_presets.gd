class_name BalancePresets
extends RefCounted
## 数值方案：把一组和 balance.cfg 不一样的数值存成文件，方便导出、导入、切换，也可以写回 balance.cfg。
## 方案和 balance.cfg 是同一种文本格式（Godot 的 ConfigFile），人能直接看、能改：
##   [info]
##   note="E7F6 第二轮试玩"
##   [values]
##   FISSION_ENERGY=1
##   STAR_WEIGHTS=[6, 3, 1]
## 共享的方案放 res://balance_presets/（进 git，大家都能用）；自己的放 user://balance_presets/。

const SHARED_DIR := "res://balance_presets"
const USER_DIR := "user://balance_presets"
const BALANCE_PATH := Balance.PATH
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


## 存方案：只存和 balance.cfg 不一样的数值。返回 Godot 的错误码。
static func save(path: String, values: Dictionary, note := "") -> Error:
	var base := Balance.file_values()
	var cfg := ConfigFile.new()
	cfg.set_value("info", "note", note)
	cfg.set_value("info", "saved", Time.get_datetime_string_from_system())
	for k in values:
		if not base.has(k) or values[k] != base[k]:
			cfg.set_value("values", k, _plain(values[k]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return cfg.save(path)


## 读方案：{"values": {名字: 值}, "note": 说明, "warnings": [读的时候跳过的项]}，读不出来时返回空字典。
## 没有的名字、类型对不上的值都跳过（整数可以当小数用）。
static func read(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var values := {}
	var warnings: Array[String] = []
	if cfg.has_section("values"):
		for k in cfg.get_section_keys("values"):
			var v = cfg.get_value("values", k)
			var err := Balance.value_error(k, v)
			if err != "":
				warnings.append(err)
			else:
				values[k] = Balance.fit_value(k, v)
	return {"values": values, "note": cfg.get_value("info", "note", ""), "warnings": warnings}


# ---------- 写回 balance.cfg ----------

## 能不能写回 balance.cfg：只在用编辑器版的 Godot 运行时可以（导出的游戏里改不了自己带的文件）。
static func can_write_back() -> bool:
	return OS.has_feature("editor") and FileAccess.file_exists(BALANCE_PATH)


## 把数值写回 balance.cfg。返回 {"error": 出错原因，成功时为空, "changed": [改了的名字]}。
static func write_back(values: Dictionary) -> Dictionary:
	if not can_write_back():
		return {"error": "只有用编辑器版运行时才能写回 balance.cfg", "changed": []}
	var result := rewrite_source(FileAccess.get_file_as_string(BALANCE_PATH), values)
	if not result["missing"].is_empty():
		return {"error": "balance.cfg 里找不到：" + "，".join(result["missing"]), "changed": []}
	if result["changed"].is_empty():
		return {"error": "", "changed": []}
	var f := FileAccess.open(ProjectSettings.globalize_path(BALANCE_PATH), FileAccess.WRITE)
	if f == null:
		return {"error": "打不开 balance.cfg：%s" % error_string(FileAccess.get_open_error()), "changed": []}
	f.store_string(result["source"])
	f.close()
	Balance.reload_file()
	return {"error": "", "changed": result["changed"]}


## 在 balance.cfg 的原文里改数值：只换「=」后面的值，名字和行尾注释都留着。
## 返回 {"source": 新原文, "changed": [改了的名字], "missing": [原文里找不到的名字]}。
static func rewrite_source(source: String, values: Dictionary) -> Dictionary:
	var decl := RegEx.create_from_string("^((\\w+)\\s*=\\s*)(.*)$")
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
		var semi := -1
		var old_value := ""
		var comment := ""
		if rest.strip_edges() == "{":
			while last + 1 < lines.size() and lines[last].strip_edges() != "}":
				last += 1
			old_value = "\n".join(lines.slice(i, last + 1)).substr(head.length())
			rest = ""
		else:
			semi = rest.find(";")
			old_value = (rest.substr(0, semi) if semi >= 0 else rest).strip_edges()
			comment = rest.substr(semi) if semi >= 0 else ""
		var old_parsed = str_to_var(old_value)
		if typeof(old_parsed) == typeof(values[name]) and old_parsed == values[name]:
			for k in range(i, last + 1):
				out.append(lines[k])
			i = last + 1
			continue
		var text := head + format_value(values[name])
		if comment != "":
			# 注释尽量留在原来的列
			var col := head.length() + rest.substr(0, semi).length()
			text = text.rpad(maxi(col, text.length() + 2)) + comment
		out.append(text)
		changed.append(name)
		i = last + 1
	var missing: Array[String] = []
	for k in values:
		if not seen.has(k):
			missing.append(k)
	return {"source": "\n".join(out), "changed": changed, "missing": missing}

## 数值写成 balance.cfg 里的样子（和 GDScript 源码的写法一样）。字典每行最多放几项，写成多行。
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
