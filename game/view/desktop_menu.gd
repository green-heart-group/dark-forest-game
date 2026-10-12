extends MenuBar
## Mac 的原生「文件」菜单；操作仍走存档和重开界面的同一入口。
var main: Node
var files := PopupMenu.new()


func setup(p_main: Node) -> void:
	main = p_main
	files.name = "文件"
	add_child(files)
	files.add_item("保存对局…", 0, KEY_MASK_META | KEY_S)
	files.add_item("读取对局…", 1, KEY_MASK_META | KEY_O)
	files.add_item("读取旧存档…", 2)
	files.add_separator()
	files.add_item("新开一局…", 3)
	files.id_pressed.connect(_activate)
	visible = OS.has_feature("macos") and NativeMenu.has_feature(NativeMenu.FEATURE_GLOBAL_MENU)


func _activate(id: int) -> void:
	if main.game_input_blocked():
		return
	match id:
		0: main.saves.open_dialog(true)
		1: main.saves.open_dialog(false)
		2: main.saves.open_dialog(false, true)
		3: main.overlay._ask_restart()
