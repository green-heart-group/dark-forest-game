extends Node
## 游戏窗口的位置和大小、界面大小（ui_scale），以及存这些设置的 user://settings.cfg。
## 这些是玩家自己的设置，不进对局记录。

## 界面整体大小。窗口变大变小时界面会跟着等比缩放（以 1280×800 为准），这个值在此基础上再放大或缩小，
## 给觉得字太小或太大的人调。Ctrl + 加号 / 减号调整，Ctrl + 0 恢复，存在 SETTINGS_PATH。
var ui_scale := 1.0
const UI_SCALE_MIN := 0.6
const UI_SCALE_MAX := 1.3
## 刚打开（没调过界面大小）时，界面画多大：1 是系统缩放 100% 时 1280×800 的界面原样大小。
## 中文小字偏小，稍放大一点。窗口再大，多出来的地方给星图，字不跟着变大。
const UI_TARGET := 1.1
## 玩家自己的设置（不进对局记录）
const SETTINGS_PATH := "user://settings.cfg"
## 第一次打开时，窗口占屏幕可用高度的这么多（宽高比按 1280×800 的 16:10）
const WINDOW_SCREEN_SHARE := 0.85

var main: Node


## 网页版带的字体（game/tools/make_web_fonts.py 做的，不进仓库）。
## 网页里用不了电脑上装的字体，ui_font.tres 找不到字时改用这些。
const WEB_FONTS := ["res://view/web_fonts/cjk.otf", "res://view/web_fonts/emoji.ttf",
		"res://view/web_fonts/symbols.ttf"]


## 摆好游戏窗口，定下界面大小。
func setup(p_main: Node) -> void:
	main = p_main
	_use_web_fonts()
	_load_ui_scale(_place_window())
	get_window().size_changed.connect(_responsive_size)
	_responsive_size()


func _use_web_fonts() -> void:
	if not OS.has_feature("web"):
		return
	var fallbacks: Array[Font] = []
	for path in WEB_FONTS:
		if ResourceLoader.exists(path):
			fallbacks.append(load(path))
	var font: Font = load(ProjectSettings.get_setting("gui/theme/custom_font"))
	font.fallbacks = fallbacks


## 启动时摆好游戏窗口：用上次关游戏时的位置和大小（最大化也记着）；
## 第一次打开，或者原来的屏幕不在了，就按屏幕大小算一个，放在屏幕正中。
## 返回 true：窗口大小是这次新算的。
func _place_window() -> bool:
	if not _owns_window():
		return false
	var win := get_window()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var rect: Rect2i = cfg.get_value("window", "rect", Rect2i())
	var fresh := not title_bar_on_screen(rect)
	if fresh:
		var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
		var size := Vector2(screen.size.y * WINDOW_SCREEN_SHARE * 1.6, screen.size.y * WINDOW_SCREEN_SHARE)
		if size.x > screen.size.x * 0.95:
			size = Vector2(screen.size.x * 0.95, screen.size.x * 0.95 / 1.6)
		rect = Rect2i(screen.position + (screen.size - Vector2i(size)) / 2, Vector2i(size))
	win.size = rect.size
	win.position = rect.position
	if cfg.get_value("window", "maximized", false):
		win.mode = Window.MODE_MAXIMIZED
	return fresh


## 游戏窗口的位置和大小归游戏自己管。不带窗口跑测试时没有窗口；
## 在编辑器的「游戏」页里运行时，窗口嵌在编辑器里，大小由编辑器定；
## 命令行给了窗口大小（比如截图时 --resolution 加 --position 放到屏幕外）就听命令行的。
## 网页版的画面大小由浏览器定。这几种情况不摆窗口也不记窗口大小。
## 只给 --position 不算：编辑器用单独的窗口运行游戏时，总会按「运行时窗口位置」的设置带上它。
static func _owns_window() -> bool:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor() or OS.has_feature("web"):
		return false
	for arg in OS.get_cmdline_args():
		if arg in ["--resolution", "--fullscreen", "-f", "--maximized", "-m"]:
			return false
	return true


## 窗口的标题栏在某块屏幕上（存下的位置还能用）。调试面板的窗口也用它。
static func title_bar_on_screen(rect: Rect2i) -> bool:
	if rect.size.x <= 0:
		return false
	var bar := Rect2i(rect.position, Vector2i(rect.size.x, 30))
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).intersects(bar):
			return true
	return false


func _notification(what: int) -> void:
	# 关游戏时记下窗口的位置和大小（最大化时只记「最大化」，原来的大小留着）
	if what != NOTIFICATION_WM_CLOSE_REQUEST or not _owns_window():
		return
	var win := get_window()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("window", "maximized", win.mode == Window.MODE_MAXIMIZED)
	if win.mode == Window.MODE_WINDOWED:
		cfg.set_value("window", "rect", Rect2i(win.position, win.size))
	cfg.save(SETTINGS_PATH)


## fresh：窗口大小是这次新算的（第一次打开）。这时原来存的界面大小是按别的窗口大小调的，不用，按新窗口重算。
func _load_ui_scale(fresh: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if fresh or not cfg.has_section_key("ui", "scale"):
		apply_ui_scale(default_ui_scale())
	else:
		apply_ui_scale(cfg.get_value("ui", "scale", 1.0))


## 窗口按 1280×800 等比放大了几倍
func _window_stretch() -> float:
	var win := get_window()
	return minf(win.size.x / 1280.0, win.size.y / 800.0)


## 界面实际画多大（1 = 系统缩放 100% 时的原样大小）
func effective_ui_scale() -> float:
	return ui_scale * _window_stretch()


## 刚打开时的界面大小：让字和系统设置的缩放差不多大（UI_TARGET），不随窗口变大而变大。
## 不带窗口跑测试时保持 1，画面测试的排版不受屏幕影响。
func default_ui_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var system := DisplayServer.screen_get_dpi(get_window().current_screen) / 96.0
	return UI_TARGET * maxf(system, 1.0) / _window_stretch()


## 玩家调了界面大小：用上、存下，再在星图上方提示一下现在多大。
func set_ui_scale(value: float) -> void:
	apply_ui_scale(value)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.save(SETTINGS_PATH)
	main.overlay.show_toast("界面大小 %d%%　（Ctrl + 加号 / 减号调整，Ctrl + 0 恢复）" % roundi(effective_ui_scale() * 100))


## 用上界面大小（限制在上下限之间），不存。调试面板是单独的窗口，跟着一起变。
func apply_ui_scale(value: float) -> void:
	ui_scale = snappedf(clampf(value, UI_SCALE_MIN, UI_SCALE_MAX), 0.1)
	get_window().content_scale_factor = ui_scale
	if main.debug != null:
		main.debug.set_ui_scale(effective_ui_scale())


## 竖屏使用较窄的逻辑画布，防止把桌面界面整体缩成看不清的小字。
func _responsive_size() -> void:
	var win := get_window()
	var target := Vector2i(720, 800) if win.size.x < win.size.y * 1.25 else Vector2i(1280, 800)
	if DisplayServer.get_name() == "headless" and win.size == Vector2i(64, 64):
		target = Vector2i(1280, 800)
	if win.content_scale_size != target:
		win.content_scale_size = target
