class_name R4Map
extends Control
## 只画已送达的历史；公开格子ID与下一维几何不泄露星体或敌方当前状态。
signal cell_selected(id: int)
var state
var player := 0
var target := -1
var preview := false
var yaw := 0.0
var screen_points: Dictionary = {}
var colors := [Color("65ded5"),Color("ef9069"),Color("db87da"),Color("e5cf76"),Color("8fafff")]

func _ready() -> void:
	custom_minimum_size=Vector2(540,540)
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func projection(p: Vector3, dimension: int) -> Vector2:
	if dimension==1: return Vector2(p.x,0)
	if dimension==2: return Vector2(p.x,-p.y)
	var rotated := p.rotated(Vector3.UP,yaw)
	return Vector2((rotated.x-rotated.z)*0.72,rotated.y*-0.92+(rotated.x+rotated.z)*0.31)

func shown_position(record: Dictionary, dimension: int) -> Vector3:
	var p: Vector3 = state.observation_position(record)
	return p if dimension==state.space.world_dim else state.space.remap_point(p,state.space.world_dim,dimension)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("091421"))
	if state==null: return
	var dimension: int = maxi(1,state.space.world_dim-1) if preview else state.space.world_dim
	var lo := Vector2(INF,INF)
	var hi := Vector2(-INF,-INF)
	var raw := {}
	for id in 729:
		var p := projection(state.space.position_for(id,dimension),dimension)
		raw[id]=p
		lo=lo.min(p)
		hi=hi.max(p)
	var span := hi-lo
	var scale: float = minf((size.x-65)/maxf(span.x,1),(size.y-100)/maxf(span.y,1))
	var center := (lo+hi)*0.5
	var origin := size*Vector2(0.5,0.53)
	screen_points.clear()
	for id in raw:
		var p: Vector2 = origin+(raw[id]-center)*scale
		screen_points[id]=p
		draw_circle(p,1.2,Color("253144"))
	var c: Dictionary = state.civs[player]
	for cell in c.known_cells.values():
		var p: Vector2 = screen_points[cell.id]
		var tint: Color = colors[cell.owner%colors.size()] if cell.owner>=0 else Color("aebed1")
		if cell.was_system:
			draw_circle(p,3.8 if cell.stars>0 else 2.5,tint)
			if cell.get("dim",3)<state.space.world_dim: draw_arc(p,6,0,TAU,16,Color("966eab"),1)
	for info in c.seen.values():
		if not info.alive: continue
		var p := origin+(projection(shown_position(info,dimension),dimension)-center)*scale
		var tint: Color = colors[info.owner%colors.size()]
		var stale: bool = state.now-info.t_observed>1.0
		if stale: tint.a=0.48
		if info.kind in R4Config.ANCHORS:
			draw_arc(p,8,0,TAU,20,tint,2)
		else:
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(3,3),p+Vector2(-3,3)]),tint)
	if screen_points.has(target):
		var p: Vector2 = screen_points[target]
		draw_arc(p,13,0,TAU,28,Color("ffffff"),1.5)
	var font := get_theme_default_font()
	draw_string(font,Vector2(18,28),"下一维几何预览" if preview else "已接收的星图",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("dceaf7"))
	draw_string(font,Vector2(18,size.y-18),"%dD   格距 %.5f ly   c %.2f ly/年   淡色为历史观测"%[dimension,state.config.spacing(dimension),state.config.c(dimension)],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("9daec3"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var selected := -1
		var best := 225.0
		for id in screen_points:
			var distance: float = event.position.distance_squared_to(screen_points[id])
			if distance<best: best=distance; selected=id
		if selected>=0: cell_selected.emit(selected)
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		yaw+=0.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -0.15
		queue_redraw()
