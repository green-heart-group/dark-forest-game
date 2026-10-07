extends RefCounted
## 网页版里和电脑上的文件打交道。
## 浏览器不让游戏打开电脑上的文件夹，游戏自己存的文件（user://）放在浏览器里，玩家看不到。
## 所以网页版改成：要存到电脑上就「下载」，要打开电脑上的文件就让玩家选一个「上传」，
## 上传的文件先复制到 user://uploads/，再按普通文件打开。

const UPLOAD_DIR := "user://uploads"

## 浏览器选好文件后调用的函数要一直留着，不然会被回收
static var _picked_callback: JavaScriptObject = null
static var _on_picked: Callable


static func is_web() -> bool:
	return OS.has_feature("web")


## 网页地址里 ? 后面的参数，按命令行参数的样子返回，例如 ?debug&seed=5 → ["debug", "seed=5"]。
static func url_args() -> PackedStringArray:
	var out := PackedStringArray()
	if not is_web():
		return out
	var query: String = str(JavaScriptBridge.eval("window.location.search", true))
	for part in query.trim_prefix("?").split("&", false):
		out.append(part.uri_decode())
	return out


## 把 user:// 里的一个文件下载到电脑上（浏览器的「下载」文件夹）。
static func download(path: String) -> void:
	JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(path), path.get_file())


## 让玩家选一个电脑上的文件（accept 是扩展名，例如 ".replay"），
## 选好以后复制到 user://uploads/，再调用 on_picked(复制后的路径)。玩家取消时什么都不做。
## 浏览器只在「正在处理一次点击」时才肯弹出选文件的窗口，而 Godot 收到点击时这次点击已经处理完了。
## 所以按钮要设成按下就触发（make_pick_button），这里先准备好，等松开鼠标的那一下再弹窗口。
static func pick(accept: String, on_picked: Callable) -> void:
	_on_picked = on_picked
	if _picked_callback == null:
		_picked_callback = JavaScriptBridge.create_callback(_received)
		JavaScriptBridge.eval("""
			window.darkForestPickFile = function (accept, done) {
				var open = function () {
					window.removeEventListener('pointerup', open, true);
					window.removeEventListener('keyup', open, true);
					var input = document.createElement('input');
					input.type = 'file';
					input.accept = accept;
					input.onchange = function () {
						var file = input.files[0];
						if (!file) return;
						var reader = new FileReader();
						reader.onload = function () {
							var url = reader.result;
							done(file.name, url.substring(url.indexOf(',') + 1));
						};
						reader.readAsDataURL(file);
					};
					input.click();
				};
				window.addEventListener('pointerup', open, true);
				window.addEventListener('keyup', open, true);
			};
		""", true)
	var window = JavaScriptBridge.get_interface("window")  # 不写类型：darkForestPickFile 是上面刚加的
	window.darkForestPickFile(accept, _picked_callback)


## 网页版里，会调用 pick() 的按钮要在按下鼠标时就触发（原因见 pick()）。
static func make_pick_button(button: BaseButton) -> void:
	if is_web():
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


## 浏览器读好了文件：args 是 [文件名, base64 编码的内容]。
static func _received(args: Array) -> void:
	var name := str(args[0]).get_file()
	DirAccess.make_dir_recursive_absolute(UPLOAD_DIR)
	var path := UPLOAD_DIR.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(Marshalls.base64_to_raw(str(args[1])))
	f.close()
	_on_picked.call(path)
