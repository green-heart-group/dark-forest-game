extends Node
## 普通游戏的存读档：用对局记录重建，逐回合校验；失败或取消不替换当前对局和数值。
const WebFiles := preload("res://view/web_files.gd")
const VERSION := 1
const DIR := "user://saves"
var main: Node
var busy := false
var slice_msec := 50
var _dialog := FileDialog.new()
var _progress := AcceptDialog.new()
var _generation := 0
var _old_balance := {}
var _debug_visible := false
## 与手动存档使用同一格式；测试可以换成自己的路径。
var continue_path := DIR.path_join("continue.forest")
var _session_ready := false
var _saved_revision: Array = []
var _resume_dialog := ConfirmationDialog.new()
var _quit_dialog := ConfirmationDialog.new()
## 原生文件选择器不一定使 Godot Window.visible 为 true，单独跟踪其生命周期。
var _file_dialog_open := false
var prefs_path := "user://settings.cfg"


func setup(p_main: Node) -> void:
	main = p_main
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = OS.has_feature("macos") and DisplayServer.get_name() != "headless"
	_dialog.mode_overrides_title = false
	_dialog.filters = PackedStringArray(["*.forest ; 黑暗森林存档"])
	_dialog.size = Vector2i(700, 500)
	_dialog.file_selected.connect(func(path):
		_file_dialog_open = false
		_remember_directory(path.get_base_dir())
		if _dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			save_file(path)
		else:
			load_file(path))
	_dialog.canceled.connect(func(): _file_dialog_open = false)
	add_child(_dialog)
	_progress.title = "读取存档"
	_progress.ok_button_text = "取消"
	_progress.confirmed.connect(cancel)
	_progress.canceled.connect(cancel)
	add_child(_progress)
	_resume_dialog.title = "欢迎回来"
	_resume_dialog.dialog_text = "发现上次自动保存的对局。继续游戏，还是开始新的一局？"
	_resume_dialog.ok_button_text = "继续上次对局"
	_resume_dialog.cancel_button_text = "退出游戏"
	_resume_dialog.add_button("新开一局", true, "new")
	_resume_dialog.confirmed.connect(func(): load_file(continue_path))
	_resume_dialog.canceled.connect(main.request_quit)
	_resume_dialog.custom_action.connect(func(_action):
		_resume_dialog.hide()
		_session_ready = true
		save_if_changed())
	add_child(_resume_dialog)
	_quit_dialog.title = "尚未保存，暂未退出"
	_quit_dialog.dialog_text = "自动保存失败。请重试，或返回游戏用「保存」选择另一个位置。"
	_quit_dialog.ok_button_text = "重试并退出"
	_quit_dialog.cancel_button_text = "返回游戏"
	_quit_dialog.add_button("退出且不保存", false, "discard")
	_quit_dialog.confirmed.connect(main.request_quit)
	_quit_dialog.custom_action.connect(func(_action): get_tree().quit())
	add_child(_quit_dialog)


func begin_session(offer_resume := true) -> void:
	if continue_path == "" or main.autosave_path == "" or WebFiles.is_web():
		return
	if offer_resume and FileAccess.file_exists(continue_path):
		_resume_dialog.popup_centered()
	else:
		_session_ready = true
		save_if_changed()


func modal_open() -> bool:
	return busy or _file_dialog_open or _dialog.visible or _resume_dialog.visible or _quit_dialog.visible


func _resume_failed(path: String) -> void:
	if path == continue_path and not _session_ready:
		_resume_dialog.dialog_text = "上次自动存档无法恢复，原文件已保留。可以重试，或开始新的一局。"
		_resume_dialog.popup_centered()


func _revision() -> Array:
	var s: GameState = main.state
	return [s.get_instance_id(), s.steps, s.history.size(), collapse_stamp(s).duplicate(true)]


## refresh 也会在选目标时调用；只在规则局面变动后写盘。
func save_if_changed() -> void:
	if not _session_ready or main.autosave_path == "" or busy or continue_path == "":
		return
	if main.debug != null and (main.debug.replaying() or main.debug.seeking):
		return
	var revision := _revision()
	if revision == _saved_revision:
		return
	DirAccess.make_dir_recursive_absolute(continue_path.get_base_dir())
	if save_file(continue_path, false) == OK:
		_saved_revision = revision


## 退出前再写一次，失败保留窗口；尚未选择继续时不能覆盖上次对局。
func prepare_exit() -> bool:
	if busy:
		cancel()
	if not _session_ready or continue_path == "" or main.autosave_path == "" or WebFiles.is_web():
		return true
	if main.debug != null and (main.debug.replaying() or main.debug.seeking):
		return true
	DirAccess.make_dir_recursive_absolute(continue_path.get_base_dir())
	if save_file(continue_path, false) == OK:
		return true
	_quit_dialog.popup_centered()
	return false


func open_dialog(save: bool, legacy := false) -> void:
	if modal_open() or (main.debug != null and main.debug.seeking):
		return
	if main.debug != null:
		main.debug.pause()
	DirAccess.make_dir_recursive_absolute(DIR)
	var name := "黑暗森林-第%d回合-%s.forest" % [main.state.turn, Time.get_datetime_string_from_system().replace(":", "")]
	if WebFiles.is_web():
		if save:
			var path := DIR.path_join(name)
			if save_file(path) == OK:
				WebFiles.download(path)
		else:
			WebFiles.pick(".forest", load_file)
		return
	_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	_dialog.title = "保存对局" if save else "读取对局"
	_dialog.ok_button_text = "保存" if save else "读取"
	_dialog.cancel_button_text = "取消"
	_dialog.current_dir = ProjectSettings.globalize_path(DIR) if legacy else _default_directory()
	_dialog.current_file = name if save else ""
	_file_dialog_open = true
	_dialog.popup_centered()


func _default_directory() -> String:
	var cfg := ConfigFile.new()
	cfg.load(prefs_path)
	var last: String = cfg.get_value("saves", "directory", "")
	if last != "" and DirAccess.dir_exists_absolute(last):
		return last
	if OS.has_feature("macos"):
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	return ProjectSettings.globalize_path(DIR)


func _remember_directory(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(prefs_path)
	cfg.set_value("saves", "directory", path)
	cfg.save(prefs_path)


static func collapse_stamp(s: GameState) -> Array:
	return [s.dimension, s.foil_zones, s.line_zones]


func save_file(path: String, notify := true) -> Error:
	if busy or (main.debug != null and main.debug.seeking):
		return ERR_BUSY
	var s: GameState = main.state
	var data := {"version": VERSION, "replay": Replay.from_state(s).to_dict(),
			"checksum": s.checksum(), "collapse": collapse_stamp(s)}
	# 先写临时文件，成功后替换，写失败不会毁掉已有存档。
	var temp := path + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		main.overlay.show_toast("保存失败：无法写入文件")
		return FileAccess.get_open_error()
	f.store_var(data)
	f.flush()
	var error := f.get_error()
	f.close()
	if error == OK:
		error = DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
	if notify or error != OK:
		main.overlay.show_toast("对局已保存" if error == OK else "保存失败，原存档未改动")
	return error


func load_file(path: String) -> void:
	if busy:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = f.get_var() if f != null else null
	if f != null:
		f.close()
	if not data is Dictionary or data.get("version") != VERSION or not data.get("checksum") is int \
			or not data.get("collapse") is Array or not Replay.valid_data(data.get("replay")):
		main.overlay.show_toast("无法读取：存档损坏或版本不兼容")
		_resume_failed(path)
		return
	if main.debug != null:
		main.debug.pause()
		main.debug.cancel_seek()
		_debug_visible = main.debug.visible
		main.debug.visible = false
	_old_balance = Balance.values()
	busy = true
	_generation += 1
	var generation := _generation
	_progress.dialog_text = "正在重建对局…"
	_progress.popup_centered()
	main.refresh()
	var r := Replay.from_dict(data["replay"])
	var s := r.start()
	var slice := Time.get_ticks_msec()
	while s.steps < r.last_step() and not s.is_over():
		if not r.step(s):
			break
		if Time.get_ticks_msec() - slice >= slice_msec:
			_progress.dialog_text = "正在读取：%d / %d 回合" % [s.steps, r.last_step()]
			await get_tree().process_frame
			if generation != _generation:
				return
			slice = Time.get_ticks_msec()
	r.finish(s)
	# 终局后的展开不增加回合；恢复保存瞬间的展开进度。
	while r.desync_step < 0 and s.is_over() and s.collapse_pending() and collapse_stamp(s) != data["collapse"]:
		var before := collapse_stamp(s).duplicate(true)
		s.advance_collapse()
		if before == collapse_stamp(s):
			break
		if Time.get_ticks_msec() - slice >= slice_msec:
			await get_tree().process_frame
			if generation != _generation:
				return
			slice = Time.get_ticks_msec()
	var ok: bool = r.desync_step < 0 and s.steps == r.last_step() and s.checksum() == data["checksum"] \
			and collapse_stamp(s) == data["collapse"]
	busy = false
	if main.debug != null:
		main.debug.visible = _debug_visible
	_progress.hide()
	if not ok:
		Balance.apply(_old_balance)
		main.refresh()
		main.overlay.show_toast("读取失败：对局校验不一致，原对局保留")
		_resume_failed(path)
		return
	if main.debug != null:
		main.debug.replay = null
		main.debug.snapshots.clear()
		main.debug.desync_step = -1
		main.debug.view_idx = 0
		main.debug._seed.set_value_no_signal(s.seed_value)
	_session_ready = true
	main.set_state(s)
	main.map.reset_view(true)
	main.autosave()
	main.overlay.show_toast("对局已恢复，可以继续游戏")


func cancel() -> void:
	if not busy:
		return
	_generation += 1
	busy = false
	Balance.apply(_old_balance)
	if main.debug != null:
		main.debug.visible = _debug_visible
	_progress.hide()
	main.refresh()
	main.overlay.show_toast("已取消读档，原对局保留")
