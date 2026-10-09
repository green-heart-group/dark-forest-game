class_name R4Space
extends RefCounted
## 永久格子ID、物理光年坐标和局部光速。沿用原项目的Peano整数映射。
## 只在全图转换后换坐标；局部cell_dim与实体的生存适配互不替代。
const Layout := preload("res://rules/unfolding_layout.gd")
var config
var world_dim := 3
var world_epoch := 0
var cells: Array[Dictionary] = []
var coordinate_ids: Dictionary = {}
var fronts: Array[Dictionary] = []
var domains: Array[Dictionary] = []
var wakes: Array[Dictionary] = []
var domain_cells: Dictionary = {}
var domain_immune: Dictionary = {}
var front_schedule: Array[Dictionary] = []
var positions: Dictionary = {}
var ids_by_dimension: Dictionary = {}
var use_uniform_cache := false
var uniform_dimension := -1

func refresh_uniform_cache() -> void:
	uniform_dimension=world_dim
	for cell in cells:
		if cell.dim!=world_dim: uniform_dimension=-1; break

func _init(settings, seed_value := 0) -> void:
	config = settings
	var source := StarMap.generate(seed_value)
	for x in 9:
		for y in 9:
			for z in 9:
				var id := (x * 9 + y) * 9 + z
				var cube := Vector3i(x,y,z)
				cells.append({"id":id,"cube":cube,"dim":3,"stars":source.star_at(cube),
					"rocky":source.rocky.get(cube,0),"gas":source.gas.get(cube,0),"habitable":source.is_habitable(cube),
					"owner":-1,"was_system":source.star_at(cube)>0,"domain_until":-1.0})
	for dim in [3,2,1]:
		var table: Array[Vector3] = []
		for cell in cells:
			var p := Vector3(cell.cube)
			if dim == 2:
				var xy: Vector2i = Layout.fixed_plane(cell.cube)
				p = Vector3(xy.x, xy.y, 0)
			elif dim == 1:
				p = Vector3(Layout.plane_to_line(Layout.fixed_plane(cell.cube)),0,0)
			table.append(p * config.spacing(dim))
		positions[dim] = table
		var ids := {}
		for id in cells.size(): ids[Vector3i((table[id]/config.spacing(dim)).round())]=id
		ids_by_dimension[dim]=ids
	_reindex()
	uniform_dimension=world_dim

func position_for(cell_id: int, dim := -1) -> Vector3:
	return positions[world_dim if dim < 0 else dim][cell_id]

func _reindex() -> void:
	coordinate_ids.clear()
	for id in cells.size():
		coordinate_ids[Vector3i((position_for(id) / config.spacing(world_dim)).round())] = id

func cell_at(p: Vector3) -> int:
	return coordinate_ids.get(Vector3i((p / config.spacing(world_dim)).round()), -1)

func cell_dimension(p: Vector3) -> int:
	var id := cell_at(p)
	return cells[id].dim if id >= 0 else world_dim

func inside(p: Vector3) -> bool:
	return cell_at(p) >= 0

func cell_candidates(a: Vector3, b: Vector3, radius: float) -> Array:
	var spacing: float = config.spacing(world_dim)
	var lower := Vector3i(((a.min(b)-Vector3.ONE*radius)/spacing).ceil())
	var upper := Vector3i(((a.max(b)+Vector3.ONE*radius)/spacing).floor())
	var limit := 8 if world_dim==3 else (26 if world_dim==2 else 728)
	lower=lower.max(Vector3i.ZERO)
	upper=upper.min(Vector3i(limit,limit if world_dim>=2 else 0,limit if world_dim==3 else 0))
	var result: Array = []
	for x in range(lower.x,upper.x+1):
		for y in range(lower.y,upper.y+1):
			for z in range(lower.z,upper.z+1):
				var id: int = coordinate_ids.get(Vector3i(x,y,z),-1)
				if id>=0: result.append(cells[id])
	return result

func background_c(p: Vector3) -> float:
	var dim := cell_dimension(p)
	return 0.0 if dim == 0 else config.c(dim)

static func point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var d := b - a
	if d.length_squared() <= 1e-18: return p.distance_to(a)
	return p.distance_to(a + d * clampf((p-a).dot(d) / d.length_squared(),0.0,1.0))

func local_factor(p: Vector3, now: float) -> float:
	if domains.is_empty() and wakes.is_empty(): return 1.0
	var dcfg: Dictionary = config.physics.domain
	var cell := cell_at(p)
	var weight := 0.0
	var immunity: float = domain_immune.get(cell, -1.0)
	var permit := now >= immunity
	if domain_cells.has(cell) and now >= domain_cells[cell].expires:
		permit = false
	if permit:
		for source in domains:
			if now < source.born or now >= source.expires: continue
			var radius: float = minf(dcfg.radius, (now-source.born) * config.c(source.dim) * dcfg.spread_c_fraction)
			var dist: float = p.distance_to(source.pos)
			if dist > radius + 1e-9: continue
			if dist <= dcfg.core: return 0.0
			weight += dcfg.weight * maxf(0.0, 1.0-dist/dcfg.radius)
	var factor := 1.0 / (1.0 + weight)
	for wake in wakes:
		if now >= wake.expires: continue
		if point_segment_distance(p, wake.a, wake.b) <= config.physics.wake.radius:
			factor = minf(factor, config.physics.wake.factor)
	return factor

func effective_c(p: Vector3, now: float, entity_dim := -1) -> float:
	if use_uniform_cache and uniform_dimension>0 and domains.is_empty() and wakes.is_empty():
		return config.c(uniform_dimension) if entity_dim<0 else minf(config.c(uniform_dimension),config.c(entity_dim))
	var value := background_c(p)
	if entity_dim > 0:
		value = minf(value, config.c(entity_dim))
	return value * local_factor(p, now)

## 只能从推进器调用；视野/界面的光速查询不会改变寿命或免疫时钟。
func advance_domains(now: float) -> void:
	for id in domain_cells.keys():
		if now >= domain_cells[id].expires:
			domain_immune[id] = domain_cells[id].expires + config.physics.domain.immunity
			domain_cells.erase(id)
	for source in domains:
		if now < source.born or now >= source.expires: continue
		var radius: float = minf(config.physics.domain.radius, (now-source.born)*config.c(source.dim)*config.physics.domain.spread_c_fraction)
		for id in cells.size():
			if domain_cells.has(id) or now < domain_immune.get(id,-1.0): continue
			var distance: float = position_for(id).distance_to(source.pos)
			if distance <= radius + 1e-9:
				var first: float = maxf(source.born + distance/(config.c(source.dim)*config.physics.domain.spread_c_fraction),domain_immune.get(id,-1.0))
				domain_cells[id] = {"started":first,"expires":first+config.physics.domain.cell_life}
	# 源的自然到期不会刷新已经记录的格子硬到期。
	domains = domains.filter(func(d): return now < d.expires)
	wakes = wakes.filter(func(w): return now < w.expires)

func front_speed() -> float:
	return config.c(world_dim) * config.physics.front_c_fraction

func add_front(id: int, owner: int, at: Vector3, now: float) -> Dictionary:
	var front := {"id":id,"owner":owner,"pos":at,"born":now,"from_dim":world_dim,"speed":front_speed()}
	fronts.append(front)
	for cell in cells:
		if cell.dim != world_dim: continue
		front_schedule.append({"t": now+position_for(cell.id).distance_to(at)/front.speed,
			"cell":cell.id,"front":id,"owner":owner,"from_dim":world_dim})
	front_schedule.sort_custom(func(a,b):
		if is_equal_approx(a.t,b.t): return a.cell < b.cell
		return a.t < b.t)
	return front

func next_front_time(now: float) -> float:
	while not front_schedule.is_empty():
		var item: Dictionary = front_schedule[0]
		if cells[item.cell].dim != item.from_dim:
			front_schedule.pop_front()
		else:
			return maxf(now,item.t)
	return INF

func convert_due(now: float) -> Array:
	var converted: Array = []
	while not front_schedule.is_empty() and front_schedule[0].t <= now + config.physics.event_epsilon:
		var item: Dictionary = front_schedule.pop_front()
		if cells[item.cell].dim == item.from_dim:
			uniform_dimension=-1
			cells[item.cell].dim -= 1
			converted.append(item)
	return converted

func transition_complete() -> bool:
	if world_dim <= 1: return false
	for cell in cells:
		if cell.dim == world_dim: return false
	return true

## 同一物理时刻的原子换图由state调用。所有需要重映射的对象由state枚举，不能在此清空消息。
func remap_point(p: Vector3, from_dim: int, to_dim: int) -> Vector3:
	var old_spacing: float = config.spacing(from_dim)
	var coord := Vector3i((p/old_spacing).round())
	var id: int = ids_by_dimension[from_dim].get(coord,-1)
	if id < 0:
		# 图外消息不夹入图内，保持在边界之外。
		var maximum := 728.0 if to_dim == 1 else 26.0
		return Vector3(-1 if p.x < 0 else maximum+1,0,0)*config.spacing(to_dim)
	var local: Vector3 = (p-position_for(id,from_dim))/old_spacing
	local.z = 0.0
	if to_dim == 1: local.y = 0.0
	return position_for(id,to_dim) + local*config.spacing(to_dim)

func commit_remap() -> void:
	assert(transition_complete())
	world_dim -= 1
	world_epoch += 1
	uniform_dimension=world_dim
	fronts.clear() # 只有已完成这轮任务的空间转换波退休。
	front_schedule.clear()
	_reindex()

## 两段连续直线轨迹的首次球形相交参数，返回[0,1]或-1。
## 加速轨迹由推进器在误差受控的子步中切分，不能只比较端点距离。
static func sweep_contact(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, radius: float) -> float:
	var rel := a0-b0
	var vel := (a1-a0)-(b1-b0)
	var c := rel.length_squared()-radius*radius
	if c <= 0.0: return 0.0
	var a := vel.length_squared()
	if a <= 1e-20: return -1.0
	var b := 2.0*rel.dot(vel)
	var disc := b*b-4.0*a*c
	if disc < 0.0: return -1.0
	var t := (-b-sqrt(disc))/(2.0*a)
	return t if t >= 0.0 and t <= 1.0 else -1.0

static func polynomial(coefficients: Array, at: float) -> float:
	var value := 0.0
	for i in range(coefficients.size()-1,-1,-1): value=value*at+coefficients[i]
	return value

## Isolate quartic roots by derivative extrema, then bisect monotone intervals.
## This also catches a tangency without requiring an endpoint overlap.
static func polynomial_roots(coefficients: Array, lo: float, hi: float) -> Array:
	var c := coefficients.duplicate()
	while c.size()>1 and absf(c[-1])<1e-18: c.pop_back()
	if c.size()<=1: return []
	if c.size()==2:
		var root: float = -c[0]/c[1]
		return [root] if root>=lo-1e-10 and root<=hi+1e-10 else []
	var derivative: Array = []
	for i in range(1,c.size()): derivative.append(i*c[i])
	var cuts: Array = [lo]
	cuts.append_array(polynomial_roots(derivative,lo,hi))
	cuts.append(hi)
	cuts.sort()
	var roots: Array = []
	for point in cuts:
		if absf(polynomial(c,point))<1e-13 and not roots.has(point): roots.append(point)
	for i in range(cuts.size()-1):
		var left: float = cuts[i]
		var right: float = cuts[i+1]
		var sign_left := polynomial(c,left)
		if sign_left*polynomial(c,right)>=0.0: continue
		for _iteration in 48:
			var middle := (left+right)*0.5
			if sign_left*polynomial(c,middle)>0.0: left=middle
			else: right=middle
		roots.append((left+right)*0.5)
	roots.sort()
	return roots

static func path_position(path: Dictionary, at: float) -> Vector3:
	var accelerating: float = minf(at,path.get("accelerating",0.0))
	var velocity: Vector3 = path.get("velocity",Vector3.ZERO)
	var acceleration: Vector3 = path.get("acceleration",Vector3.ZERO)
	return path.from+velocity*at+acceleration*(0.5*accelerating*accelerating+accelerating*(at-accelerating))

static func accelerated_contact(a: Dictionary, b: Dictionary, duration: float, radius: float) -> float:
	var accel_a: Vector3 = a.get("acceleration",Vector3.ZERO)
	var accel_b: Vector3 = b.get("acceleration",Vector3.ZERO)
	var bound: float = (accel_a.length()+accel_b.length())*duration*duration/8.0
	if sweep_contact(a.from,a.to,b.from,b.to,radius+bound+0.000002)<0.0: return -1.0
	if a.from.distance_to(b.from)<=radius+0.000002: return 0.0
	var cuts: Array = [0.0,duration]
	for p in [a,b]:
		var t: float = p.get("accelerating",0.0)
		if t>0.0 and t<duration: cuts.append(t)
	cuts.sort()
	for i in range(cuts.size()-1):
		var start: float = cuts[i]
		var span: float = cuts[i+1]-start
		var r := path_position(a,start)-path_position(b,start)
		var v: Vector3 = a.get("velocity",Vector3.ZERO)+accel_a*minf(start,a.get("accelerating",0.0))-b.get("velocity",Vector3.ZERO)-accel_b*minf(start,b.get("accelerating",0.0))
		var acceleration: Vector3 = (accel_a if start<a.get("accelerating",0.0) else Vector3.ZERO)-(accel_b if start<b.get("accelerating",0.0) else Vector3.ZERO)
		var coefficients: Array = [r.dot(r)-radius*radius,2.0*r.dot(v),v.dot(v)+r.dot(acceleration),v.dot(acceleration),0.25*acceleration.dot(acceleration)]
		var roots := polynomial_roots(coefficients,0.0,span)
		if not roots.is_empty(): return clampf((start+roots[0])/duration,0.0,1.0)
	return -1.0

func snapshot() -> Dictionary:
	return {"world_dim":world_dim,"world_epoch":world_epoch,"cells":cells.duplicate(true),"fronts":fronts.duplicate(true),
		"domains":domains.duplicate(true),"wakes":wakes.duplicate(true),"domain_cells":domain_cells.duplicate(true),
		"domain_immune":domain_immune.duplicate(true),"front_schedule":front_schedule.duplicate(true)}

func restore(data: Dictionary) -> void:
	world_dim=data.world_dim
	world_epoch=data.world_epoch
	cells.assign(data.cells)
	fronts.assign(data.fronts)
	domains.assign(data.domains)
	wakes.assign(data.wakes)
	front_schedule.assign(data.front_schedule)
	domain_cells=data.domain_cells.duplicate(true)
	domain_immune=data.domain_immune.duplicate(true)
	_reindex()
	refresh_uniform_cache()
