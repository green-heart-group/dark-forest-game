extends "res://tests/rules/rule_suite.gd"
## 仓库里的文件：冲突标记，规则文档和测试对不对得上。

const RULES_DOC := "res://../docs/design/current-rules.md"
## 规则编号，比如 T23、F3.5（前后不能紧挨着字母或数字，所以 E7F6 这样的名字不算）
const RULE_ID := "(?<![A-Za-z0-9_])[A-Z]\\d+(?:\\.\\d+)?(?![A-Za-z0-9_])"
## 文档里这一节以后是还没做的东西，不要求有测试
const NOT_BUILT := "还没做的"


## 拉取时放回本地改动冲突了，冲突标记没处理就提交进来（export_presets.cfg 出过两次）。
func test_no_conflict_markers() -> void:
	var bad: Array[String] = []
	_find_conflict_markers("res://", bad)
	check(bad.is_empty(), "这些文件里有没处理的合并冲突标记：%s" % ", ".join(bad))


func _find_conflict_markers(dir: String, bad: Array[String]) -> void:
	# 标记拼出来写，免得这个文件自己被查出来
	var markers := ["<".repeat(7) + " ", ">".repeat(7) + " ", "|".repeat(7) + " "]
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_find_conflict_markers(dir.path_join(sub), bad)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() not in ["gd", "cfg", "tscn", "tres", "godot"]:
			continue
		var path := dir.path_join(f)
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if markers.any(func(m): return line.begins_with(m)):
				bad.append(path)
				break


## 每条规则都有测试：docs/design/current-rules.md 里最小的每一节（没有下一级标题的 ## 或 ###）、
## 正文里出现的每个规则编号，都至少有一个测试在 `## 规则：` 这一行里写到。
## 写法：测试函数上面加一行 `## 规则：节标题，编号`，用「，」隔开，节标题照抄（去掉前面的「3. 」这样的序号）。
## 也查反过来的：写的节标题或编号在文档里找不到（改了标题、打错字）也算失败。
func test_every_rule_has_a_test() -> void:
	var doc := FileAccess.get_file_as_string(ProjectSettings.globalize_path(RULES_DOC))
	check(doc != "", "读得到 %s" % RULES_DOC)
	var built := _before_section(doc, NOT_BUILT)
	var sections := _leaf_sections(built)
	var ids := {}
	for m in RegEx.create_from_string(RULE_ID).search_all(built):
		ids[m.get_string()] = true
	var tagged := {}
	var tag_ids := {}
	for path in _test_files():
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with("## 规则："):
				continue
			for tag in line.trim_prefix("## 规则：").split("，"):
				tagged[tag.strip_edges()] = path.get_file()
			for m in RegEx.create_from_string(RULE_ID).search_all(line):
				tag_ids[m.get_string()] = true
	var untested := sections.filter(func(s): return not tagged.has(s))
	untested.append_array(ids.keys().filter(func(id): return not tag_ids.has(id)))
	check(untested.is_empty(), "这些规则还没有测试（或者测试上没写 `## 规则：`）：%s" % "，".join(untested))
	# 编号单独查（写在节标题里的编号，比如「智子（D5）」，也算写到了）
	var id_re := RegEx.create_from_string(RULE_ID)
	var unknown := tagged.keys().filter(func(t): return not sections.has(t) and id_re.search(t) == null)
	unknown.append_array(tag_ids.keys().filter(func(id): return not ids.has(id)))
	check(unknown.is_empty(), "测试上写的这些在规则文档里找不到（标题改了或打错字）：%s" % "，".join(unknown))


## 文档里标题为 title 的那一节之前的部分。
func _before_section(doc: String, title: String) -> String:
	var m := RegEx.create_from_string("(?m)^#{2,3} (?:\\d+\\. )?" + title).search(doc)
	return doc.substr(0, m.get_start()) if m != null else doc


## 没有下一级标题的 ## 和 ### 标题（去掉序号）。
func _leaf_sections(doc: String) -> Array[String]:
	var heads := RegEx.create_from_string("(?m)^(#{2,3}) (?:\\d+\\. )?(.+)$").search_all(doc)
	var leaves: Array[String] = []
	for i in heads.size():
		var level := heads[i].get_string(1).length()
		var next_level := heads[i + 1].get_string(1).length() if i + 1 < heads.size() else 0
		if next_level <= level:
			leaves.append(heads[i].get_string(2).strip_edges())
	return leaves


## 规则测试的每个文件，加上画面测试。
func _test_files() -> Array[String]:
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests/rules"):
		if f.get_extension() == "gd":
			files.append("res://tests/rules".path_join(f))
	files.append("res://tests/run_view_tests.gd")
	return files
