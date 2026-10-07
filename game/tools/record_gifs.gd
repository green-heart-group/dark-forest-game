extends SceneTree
## 录 README 里的四段动图：把每一帧画面存成 PNG，再由 make_readme_gifs.py 用 ffmpeg 拼成 GIF。
## 不要直接运行这个脚本，用：
##
##     uv run game/tools/make_readme_gifs.py
##
## 参数（写在 `--` 后面）：out=<目录> 存帧的地方；再写 explore、domain、foil 中的一个，只录那一段。
## 面板、图例都藏起来，只录星图；相机每帧由这里摆好，动画也由这里一帧一帧地推，所以每次录出来都一样。

const SEED := 2026
const SIZE := Vector2i(960, 720)

var view
var map
var _out := ""
var _dir := ""
var _n := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.trim_prefix("out=")
		else:
			only = arg
	if _out == "":
		push_error("要给出 out=<目录>")
		quit(1)
		return
	view = load("res://view/main.tscn").instantiate()
	root.add_child(view)
	view.autosave_path = ""  # 不覆盖玩家自己的 last.replay
	await process_frame
	# 游戏会按上次关窗口时的大小摆窗口，这里改回固定大小，放到屏幕外面
	DisplayServer.window_set_size(SIZE)
	DisplayServer.window_set_position(Vector2i(-5000, -5000))
	for k in 5:
		await process_frame
	map = view.map
	if view.debug != null:
		view.debug.window.hide()
	view.set_process(false)
	map.set_process(false)
	if only in ["", "explore"]:
		await explore()
	if only in ["", "domain"]:
		await domain()
	if only in ["", "foil"]:
		await foil()
	quit(0)


## 一局全由 AI 打的观战局，先自己打 turns 回合。
func spectator(turns: int) -> GameState:
	var s := GameState.new_game(SEED)
	s.spectator = true
	s.human().is_ai = true
	for i in turns:
		s.end_turn()
	view.set_state(s)
	return s


## 开始录一段：帧存到 out/name/0000.png、0001.png……
func begin(name: String) -> void:
	_dir = _out.path_join(name)
	DirAccess.make_dir_recursive_absolute(_dir)
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	_n = 0


func camera(yaw: float, distance: float, focus: Vector3) -> void:
	map._yaw = yaw
	map._goal_yaw = yaw
	map._pitch = map.CAM_PITCH
	map._goal_pitch = map.CAM_PITCH
	map._distance = distance
	map._goal_distance = distance
	map._focus = focus
	map._goal_focus = focus
	map._update_camera()
	map._camera.h_offset = 0.0  # 面板藏起来了，星图放在画面正中


func frame() -> void:
	view._layer.visible = false
	map._selection.visible = false
	map._cursor_label.visible = false
	for ring in [map._selection_ring, map._cursor_ring]:
		if ring != null:
			ring.visible = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir.path_join("%04d.png" % _n))
	_n += 1


## 1. 三维星图：自己的视野、在飞的探测器和战舰，转着看。
func explore() -> void:
	var s := spectator(14)
	begin("explore")
	view.overlay.show_vision.button_pressed = true
	view.reveal.button_pressed = false
	view.refresh()
	for i in 96:
		if i % 8 == 7:
			s.end_turn()
			view.refresh()
		camera(map.CAM_YAW + i * 1.2, map.CAM_DISTANCE * 0.8, Vector3(4.5, 4.5, 3.8))
		await frame()


## 2. 黑域：投在自己的母星系上，光速为 0 的中心向外扩散，再慢慢恢复（G14）。
func domain() -> void:
	var s := spectator(10)
	begin("domain")
	view.overlay.show_vision.button_pressed = false
	view.reveal.button_pressed = false
	var me := s.human()
	me.techs["domain"] = true
	me.energy = 999
	me.actions_left = maxi(me.actions_left, 1)
	var center := me.home
	s.launch_black_domain(me, center)
	view.refresh()
	var i := 0
	for turn in 22:
		for k in 4:
			camera(map.CAM_YAW + i * 0.8, map.CAM_DISTANCE * 0.45, Vector3(center))
			await frame()
			i += 1
		s.end_turn()
		view.refresh()


## 3. 二向箔把整张星图压成平面；4. 单向著再压成直线，最后降到零维。所有文明先降好维，免得被压没。
func foil() -> void:
	var s := spectator(24)
	for civ in s.civs:
		civ.reduced = true
		civ.line_reduced = true
	view.overlay.show_vision.button_pressed = false
	view.reveal.button_pressed = true
	view.refresh()
	var step := [0]  # 相机一直在转，两段接得上
	begin("dimension-strike")
	for k in 6:
		await turning(step)
	s._unfold_foil(Vector3i(5, 4, 4))
	await collapse(s, func(): return s.all_flat(), step)
	begin("zero-dimension")
	s._unfold_line_foil(Vector3i(4, 5, s.flat_plane))
	await collapse(s, func(): return s.all_linear(), step)
	var winner := s.human()
	winner.singularity_left = 1
	s._advance_singularity(winner)
	view.refresh()
	for k in 30:
		if map.animating():
			map.advance_animation(map.ZERO_ANIM_SECONDS / 22.0)
		await turning(step)


func turning(step: Array) -> void:
	camera(map.CAM_YAW + step[0] * 0.6, map.CAM_DISTANCE * 0.8, Vector3(4.5, 4.5, 3.8))
	await frame()
	step[0] += 1


## 一步一步压，每步的动画录 5 帧，直到 done() 为真，再停 6 帧。
func collapse(s: GameState, done: Callable, step: Array) -> void:
	view.refresh()
	for k in 40:
		while map.animating():
			map.advance_animation(map.FLAT_ANIM_SECONDS / 5.0)
			await turning(step)
		if done.call():
			break
		s.advance_collapse()
		view.refresh()
	for k in 6:
		await turning(step)
