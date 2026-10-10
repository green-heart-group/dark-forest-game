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


func setup(p_main: Node) -> void:
	main = p_main
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.forest ; 黑暗森林存档"])
	_dialog.size = Vector2i(700, 500)
	_dialog.file_selected.connect(func(path):
		if _dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			save_file(path)
		else:
			load_file(path))
	add_child(_dialog)
	_progress.title = "读取存档"
	_progress.ok_button_text = "取消"
	_progress.confirmed.connect(cancel)
	_progress.canceled.connect(cancel)
	add_child(_progress)


func open_dialog(save: bool) -> void:
	if busy or (main.debug != null and main.debug.seeking):
		return
	if main.debug != null:
		main.debug.pause()
	DirAccess.make_dir_recursive_absolute(DIR)
	var name := "%s-seed%d-t%d.forest" % [Time.get_datetime_string_from_system().replace(":", "-"), main.state.seed_value, main.state.turn]
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
	_dialog.current_dir = ProjectSettings.globalize_path(DIR)
	_dialog.current_file = name if save else ""
	_dialog.popup_centered()


static func collapse_stamp(s: GameState) -> Array:
	return [s.dimension, s.foil_zones, s.line_zones]


func save_file(path: String) -> Error:
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
	main.overlay.show_toast("对局已保存" if error == OK else "保存失败，原存档未改动")
	return error


func load_file(path: String) -> void:
	if busy:
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = f.get_var() if f != null else null
	if f != null:
		f.close()
	if data is Dictionary and data.get("replay") is Dictionary and data["replay"].get("version", 0) < Replay.VERSION:
		main.overlay.show_toast("这是旧规则存档，请用原版本打开；文件未修改")
		return
	if not data is Dictionary or data.get("version") != VERSION or not data.get("checksum") is int \
			or not data.get("collapse") is Array or not Replay.valid_data(data.get("replay")):
		main.overlay.show_toast("无法读取：存档损坏或版本不兼容")
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
		return
	if main.debug != null:
		main.debug.replay = null
		main.debug.snapshots.clear()
		main.debug.desync_step = -1
		main.debug.view_idx = 0
		main.debug._seed.set_value_no_signal(s.seed_value)
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
