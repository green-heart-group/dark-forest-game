extends "res://tests/rules/rule_suite.gd"
## 文档的规矩（见 docs/README.md「现在的事实和历史记录」和 AGENTS.md）：
## 编号查得到出处，答完的问题挪走，现在的事实里没有做事时的记录，每个文件都在目录的索引里。
## 文档里的数字和表格跟着代码更新，由 game/tools/update_docs.py 管（test.py 跑完全部测试时调用它）。

## 「现在的事实」：只写现在是什么样的文件（相对仓库根目录；以 / 结尾的是整个目录）
const CURRENT_DOCS := [
	"README.md", "AGENTS.md", "docs/README.md", "docs/status.md", "docs/open-questions.md", "docs/roadmap.md",
	"docs/design/game-design.md", "docs/design/current-rules.md", "docs/guides/", "game/balance_presets/README.md",
]
## 决定记录（相对仓库根目录）
const DECISION_LOG := "docs/design/decision-log.md"
## 不在索引里检查的目录（相对 docs/）
const UNINDEXED := ["local", "images", "proposals/images"]


func _read(rel: String) -> String:
	return FileAccess.get_file_as_string(root.path_join(rel))


## 「现在的事实」的每个文件（相对仓库根目录）
func _current_files() -> Array[String]:
	var files: Array[String] = []
	for rel in CURRENT_DOCS:
		if rel.ends_with("/"):
			for f in DirAccess.get_files_at(root.path_join(rel)):
				if f.get_extension() == "md":
					files.append(rel + f)
		else:
			files.append(rel)
	return files


## 文档里标题为 title 的那一节（到下一个同级或更高的标题为止）。
func _section(doc: String, title: String) -> String:
	var head := RegEx.create_from_string("(?m)^(#{2,4}) (?:\\d+\\. )?" + title + "\\s*$").search(doc)
	if head == null:
		return ""
	var level := head.get_string(1).length()
	var rest := doc.substr(head.get_end())
	var next := RegEx.create_from_string("(?m)^#{1,%d} " % level).search(rest)
	return rest.substr(0, next.get_start()) if next != null else rest


## 表格每一行的第一格（跳过表头和分隔行）。
func _first_cells(table_text: String) -> Array[String]:
	var cells: Array[String] = []
	for line in table_text.split("\n"):
		if not line.begins_with("|") or line.begins_with("| ---"):
			continue
		cells.append(line.split("|")[1].strip_edges())
	return cells.slice(1) if not cells.is_empty() else cells


## 「编号从哪里来」第一格里的一个范围（A～E、T17～T23、F1.1～F1.5、G14）包不包括 id。
## 两头只有字母的（A～E）包括这几个字母开头的所有编号；有小数点的按「字母和整数部分相同、小数部分在范围里」算；
## 其余按「字母相同、整数部分在范围里」算（所以 G1～G13 也包括 G13.5）。
func _range_has(token: String, id: String) -> bool:
	var ends := token.split("～")
	var lo := ends[0]
	var hi := ends[1] if ends.size() > 1 else ends[0]
	var part := RegEx.create_from_string("^([A-Z])(\\d+)?(?:\\.(\\d+))?$")
	var a := part.search(lo)
	var b := part.search(hi)
	var m := part.search(id)
	if a == null or b == null or m == null:
		return false
	var letter := m.get_string(1)
	if a.get_string(2) == "":
		return letter >= a.get_string(1) and letter <= b.get_string(1)
	if letter != a.get_string(1):
		return false
	var n := m.get_string(2).to_int()
	if a.get_string(3) != "":
		return n == a.get_string(2).to_int() and m.get_string(3) != "" \
			and m.get_string(3).to_int() >= a.get_string(3).to_int() and m.get_string(3).to_int() <= b.get_string(3).to_int()
	return n >= a.get_string(2).to_int() and n <= b.get_string(2).to_int()


## 「编号从哪里来」表第一格里登记的范围（「（没有 F6、F7）」这种说明行里的编号也算登记过）。
func _id_sources() -> Array[String]:
	var tokens: Array[String] = []
	var token := RegEx.create_from_string("[A-Z]\\d*(?:\\.\\d+)?(?:～[A-Z]\\d*(?:\\.\\d+)?)?")
	for cell in _first_cells(_section(_read(DECISION_LOG), "编号从哪里来")):
		for m in token.search_all(cell):
			tokens.append(m.get_string())
	return tokens


## 要确定的问题里还开着的问题编号（标题「### T24. ……」）。
func _open_question_ids() -> Array[String]:
	var ids: Array[String] = []
	var doc := _read("docs/open-questions.md")
	for m in RegEx.create_from_string("(?m)^### ([A-Z]\\d+(?:\\.\\d+)?)\\. ").search_all(doc):
		ids.append(m.get_string(1))
	return ids


## 编号查得到出处：游戏设计、原型现在的规则和决定记录里写到的每个编号，要么在决定记录「编号从哪里来」登记的范围里（已经定了），
## 要么是要确定的问题里还开着的问题。新的一批决定用了新字母、忘了登记来源时，这里会失败。
func test_every_decision_id_has_a_source() -> void:
	var sources := _id_sources()
	check(not sources.is_empty(), "找得到决定记录「编号从哪里来」的表")
	var open := _open_question_ids()
	var missing := {}
	for rel in ["docs/design/game-design.md", "docs/design/current-rules.md", DECISION_LOG]:
		for m in RegEx.create_from_string(RULE_ID).search_all(_read(rel)):
			var id := m.get_string()
			if not open.has(id) and not sources.any(func(t): return _range_has(t, id)):
				missing[id] = rel.get_file()
	check(missing.is_empty(), "这些编号在决定记录「编号从哪里来」里没有登记来源，也不是还开着的问题：%s"
		% "，".join(missing.keys().map(func(id): return "%s（%s）" % [id, missing[id]])))


## 答完的问题挪走：决定记录里已经有一行的编号，不能还在要确定的问题里当标题。
func test_answered_questions_are_moved_out() -> void:
	var decided := {}
	for cell in _first_cells(_read(DECISION_LOG)):
		if RegEx.create_from_string("^" + RULE_ID + "$").search(cell) != null:
			decided[cell] = true
	check(decided.size() > 20, "读得到决定记录的表（%d 行）" % decided.size())
	var still_open := _open_question_ids().filter(func(id): return decided.has(id))
	check(still_open.is_empty(), "这些问题在决定记录里已经有决定，要从要确定的问题里挪走：%s" % "，".join(still_open))


## 现在的事实里没有做事时的记录：分支名、「还没合并」、自己电脑上的路径、勾选清单（路线图除外）。
## 这些写进当月的开发日志。
func test_current_docs_have_no_work_notes() -> void:
	var rules := {
		"分支名": "(?<![\\w/])(?:codex|claude|feature|fix|hotfix)/[\\w.-]+",
		"合并状态": "尚未合并|还没合并|本功能分支",
		"本机路径": "/Users/|/home/|[A-Za-z]:[\\\\/]Users[\\\\/]",
		"勾选清单": "(?m)^\\s*- \\[[ xX~]\\] ",
	}
	var bad: Array[String] = []
	for rel in _current_files():
		var doc := _read(rel)
		check(doc != "", "读得到 %s" % rel)
		for what in rules:
			if what == "勾选清单" and rel == "docs/roadmap.md":
				continue
			var m := RegEx.create_from_string(rules[what]).search(doc)
			if m != null:
				bad.append("%s 里有%s「%s」" % [rel, what, m.get_string().strip_edges()])
	check(bad.is_empty(), "现在的事实里不写做事时的记录（写进开发日志）：%s" % "；".join(bad))


## 测试个数只写在现状里（由 test.py 写），别的现在的事实里不写，免得几处对不上。
func test_test_counts_only_in_status() -> void:
	var count := RegEx.create_from_string("测试 ?\\d+ ?个|\\d+ 个(?:规则|画面)?测试")
	var bad: Array[String] = []
	for rel in _current_files():
		if rel != "docs/status.md" and count.search(_read(rel)) != null:
			bad.append("%s（「%s」）" % [rel, count.search(_read(rel)).get_string()])
	check(bad.is_empty(), "测试个数只写在 docs/status.md：%s" % "，".join(bad))
	check(count.search(_read("docs/status.md")) != null, "docs/status.md 里有测试个数，test.py 才找得到地方写")


## 每个文件都在索引里：docs/ 下每个目录都有 README.md，目录里的每个 .md 文件和每个下一级目录都在这个 README 里有链接。
func test_every_doc_is_indexed() -> void:
	var bad: Array[String] = []
	_check_index("", bad)
	check(bad.is_empty(), "这些文件没写进所在目录的 README.md：%s" % "，".join(bad))


func _check_index(rel: String, bad: Array[String]) -> void:
	var dir := root.path_join("docs").path_join(rel)
	var readme := FileAccess.get_file_as_string(dir.path_join("README.md"))
	var mds := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.get_extension() == "md" and f != "README.md")
	var subs := Array(DirAccess.get_directories_at(dir)).filter(func(d): return not UNINDEXED.has(rel.path_join(d).trim_prefix("/")))
	if readme == "":
		if not mds.is_empty():
			bad.append("docs/%s（没有 README.md）" % rel)
		return
	for f in mds:
		if not readme.contains("](%s" % f) and not readme.contains("](./%s" % f):
			bad.append("docs/" + rel.path_join(f).trim_prefix("/"))
	for d in subs:
		if not readme.contains("](%s/" % d):
			bad.append("docs/" + rel.path_join(d).trim_prefix("/") + "/")
		_check_index(rel.path_join(d).trim_prefix("/"), bad)

