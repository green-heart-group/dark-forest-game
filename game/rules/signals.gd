class_name Signals
extends RefCounted
## 有限光速的点对点信息。存当前位置、已走距离和永久收件者ID，换图后继续走。
## 被动传感先到本地接收器，再转发控制锚点；两段时间分别记录。


## 收件者（entity 的结果）在 t 时刻在哪。t 在上一个子步里时，船按这一步的运动推出那一刻的位置；其余就是现在的位置。
static func position_at(s: GameState, receiver: Dictionary, t: float) -> Vector3:
	var ship: Ship = receiver.get("ship", receiver.get("carrier"))
	if ship != null and t < s.clock and t >= s.step_start and s.step_motions.has(ship.id):
		return Kinematics.position(s.step_motions[ship.id], t - s.step_start)
	return receiver["pos"]


static func entity(s: GameState, owner: int, id: int) -> Dictionary:
	if owner < 0 or owner >= s.civs.size():
		return {}
	var civ: Civ = s.civs[owner]
	var ship := civ.ship_by_id(id)
	if ship != null and not ship.dead:
		return {"id": id, "pos": ship.pos, "ship": ship}
	var asset := Assets.get_id(civ, id)
	if not asset.is_empty():
		if asset["carrier"] >= 0:
			var carrier := civ.ship_by_id(asset["carrier"])
			return {"id":id,"pos":carrier.pos,"asset":asset,"carrier":carrier} if carrier != null and not carrier.dead else {}
		return {"id": id, "pos": Vector3(asset["at"]), "asset": asset}
	return {}


## 控制锚点：母星上的据点（找到第一个就停，和 Assets.at 的第一个一样），没有时是星舰。
static func controller(civ: Civ) -> int:
	for asset in civ.assets:
		if asset["kind"] == "anchor" and asset["at"] == civ.home and asset["carrier"] < 0:
			return asset["id"]
	var ship := civ.starship()
	return ship.id if ship != null else -1


## 消息不在每个子步里挪动：发出时就按途经各格的光速算好什么时候到（eta），到时才收。
## source 是这一段的起点，target 是这一段瞄准的位置，sent 是从 source 出发的时刻。
## 收件者在动时瞄的是光和它相遇的地方（见 _aim）；到了发现它不在那里（中途改了航向），就从那里再追一段（见 receive_due）。
## 光确实在到达时刻走到了瞄准点，收件者也确实在那里才收下，所以不会早到，玩家拿不到光还没送到的情报。
## 同一刻从同一处发给同一收件者的情报走的是同一条路、同一刻到，合成一条（内容放进 more），收到时逐条拆开。
## merge 为 false：调用方之后还要单独改这条消息（比如 catch_up 改出发时刻），不能和别的合在一起。
static func send(s: GameState, owner: int, source: Vector3, recipient: int, kind: String, body: Dictionary, private_id:=0, merge := true) -> Dictionary:
	if merge and private_id == 0 and kind in MERGE_KINDS:
		var host := _merge_host(s, owner, source, recipient, kind)
		if not host.is_empty():
			host["more"].append(body.duplicate(true))
			if not host.get("prompt", false) and _prompt(owner, kind, entity(s, owner, recipient), body):
				host["prompt"] = true
				if not s.message_index.is_empty():
					s.message_index["exact"].append(host)
				_expect(s, host)
			return host
	var receiver := entity(s, owner, recipient)
	var fallback: Vector3 = body.get("recipient_pos", source)
	var message := {"id": s.next_id() if private_id==0 else private_id, "owner": owner, "pos": source, "source": source,
			"recipient": recipient, "kind": kind, "body": body.duplicate(true),
			"sent": s.clock, "distance": 0.0, "epoch": s.space_epoch, "dead": false, "target": fallback}
	if receiver.is_empty():
		message["eta"] = s.clock + travel_time(s, source, fallback)
	else:
		var aim := _aim(s, owner, receiver, source, 0.0)
		message["target"] = aim[0]
		message["eta"] = s.clock + aim[1]
		if _prompt(owner, kind, receiver, body):
			message["prompt"] = true
	if merge and private_id == 0 and kind in MERGE_KINDS:
		message["more"] = []
	message["n"] = s.message_serial
	s.message_serial += 1
	if not s.message_index.is_empty() and exact(message):
		s.message_index["exact"].append(message)
	_expect(s, message)
	s.messages.append(message)
	return message

## 光从 from 出发去找收件者：返回 [瞄准点, 光从 from 走到瞄准点要多少年]。lag 是光从 from 出发到现在已经过了多久。
## 收件者是在飞的船（或船上的设施）时，按它现在的运动往前推（加速到最高速度为止、到目的地停下），
## 反复几次：光到它现在的位置要 t，它那时在哪，光到那里又要多久……船比光慢，几次就差不多对上了。
## 推得不准（中途改航向、各处光速不同）也不要紧：到时它不在瞄准点，receive_due 会从那里再追，只会晚到。
static func _aim(s: GameState, owner: int, receiver: Dictionary, from: Vector3, lag: float) -> Array:
	var target: Vector3 = receiver["pos"]
	var travel := travel_time(s, from, target)
	var ship: Ship = receiver.get("ship", receiver.get("carrier"))
	if ship == null or travel == INF:
		return [target, travel]
	var motion := Kinematics.motion(s, s.civs[owner], ship, 0.0)
	if motion["velocity"] == Vector3.ZERO and motion["acceleration"] == Vector3.ZERO:
		return [target, travel]
	var here := [target, travel]
	var reach := Balance.COLLISION_EPSILON / s.physical_cell_size()
	for i in AIM_ROUNDS:
		var ahead := _ahead(motion, maxf(0.0, travel - lag))
		if ahead.distance_to(target) <= reach:
			break
		target = ahead
		travel = travel_time(s, from, target)
		if travel == INF:
			return here
	# 算出来光现在已经过了某个将来的位置：receive_due 会当场按它现在的位置交付，那不对，改回瞄它现在的位置。
	if travel <= lag and target != here[0]:
		return here
	return [target, travel]

## 往前推算收件者位置最多几次（前后两次差不到碰撞距离就停）。
const AIM_ROUNDS := 8


## 船按 motion 走 t 年后在哪：加速到 cap_time 为止，之后匀速；到了目的地就停在那里。
static func _ahead(motion: Dictionary, t: float) -> Vector3:
	if t >= motion["arrival"]:
		return motion["target"]
	var speeding_up := minf(t, motion["cap_time"])
	return motion["pos"] + motion["velocity"] * t + motion["acceleration"] * speeding_up * (t - 0.5 * speeding_up)


## 可以合并的消息种类：只是情报，收到后不改动实体。
const MERGE_KINDS := ["sensor", "report"]


## 刚发出、还能并进去的同路消息。同一刻的发送通常一条接一条，所以只往回看最近几条。
static func _merge_host(s: GameState, owner: int, source: Vector3, recipient: int, kind: String) -> Dictionary:
	for i in range(s.messages.size() - 1, maxi(-1, s.messages.size() - 17), -1):
		var m: Dictionary = s.messages[i]
		if m["sent"] != s.clock:
			break
		if m.has("more") and not m["dead"] and m["owner"] == owner and m["recipient"] == recipient \
				and m["kind"] == kind and m["source"] == source:
			return m
	return {}


## 消息其实在 lag 年前就该出发（事件在子步中间发生、到子步末才处理时）：出发和到达时刻都往前挪，送达时刻就和准时出发一样。
static func catch_up(s: GameState, message: Dictionary, lag: float) -> void:
	if lag <= 0.0:
		return
	message["sent"] -= lag
	message["eta"] -= lag
	_expect(s, message)


## 新消息或提前了的消息可能比记下的最早到达时刻还早；同时把它放进新的到达刻度。
static func _expect(s: GameState, message: Dictionary) -> void:
	if exact(message):
		s.message_due[0] = minf(s.message_due[0], message["eta"])
	s.message_due[1] = minf(s.message_due[1], message["eta"])
	if not s.message_index.is_empty():
		_file(s.message_index, message)


## 在途消息的索引：{"buckets": {分组: [消息]}, "low": 可能还有消息的最小分组, "exact": [到了就要切开的消息], "dead": 已收但还没从 messages 删掉的条数}。
## 第 k 组装到达时刻在 k×BUCKET 年到 (k+1)×BUCKET 年之间的消息。到达时刻改了就再放进新分组，旧分组里的那份收的时候认出来跳过。
## 算不出到达时间的（光速为 0）不放进去：光速一变就整份重算（retime）。
static func _indexed(s: GameState) -> Dictionary:
	if s.message_index.is_empty():
		var index := {"buckets": {}, "low": NEVER, "exact": [], "dead": 0}
		for message in s.messages:
			if not message.has("n"): # 旧存档
				message["n"] = s.message_serial
				s.message_serial += 1
			if message["dead"]:
				index["dead"] += 1
				continue
			if exact(message):
				index["exact"].append(message)
			_file(index, message)
		s.message_index = index
	return s.message_index


## 比任何分组都大，当作「没有」。
const NEVER := 1 << 62
## 在途消息按到达时刻分组的宽度（年）。只为查得快，不影响结果。
const BUCKET := 0.05
## 看视野时把目标按位置分桶（_entity_buckets）：桶有几格宽，一个方框最多碰几个桶。只为算得快，不影响结果。
const BUCKET_CELLS := 2.0
const BUCKET_LIMIT := 64


static func _file(index: Dictionary, message: Dictionary) -> void:
	var eta: float = message.get("eta", INF)
	if eta > 1e12:
		return
	var tick := floori(eta / BUCKET)
	var buckets: Dictionary = index["buckets"]
	if not buckets.has(tick):
		buckets[tick] = []
	buckets[tick].append(message)
	index["low"] = mini(index["low"], tick)


## 光从 from 走到 to 要多少年：按途经各格（以及黑域、死线）的光速分段算。路上有光速为 0 的地方、走不过去时为 INF。
static func travel_time(s: GameState, from: Vector3, to: Vector3) -> float:
	var size := s.physical_cell_size()
	var length := from.distance_to(to) * size
	if length <= Balance.COLLISION_EPSILON:
		return 0.0
	# 全图光速处处相同时，光走直线、速度不变。
	if Hazards.uniform_light(s):
		return length / s.background_light()
	var direction := (to - from).normalized()
	var moved := 0.0
	var time := 0.0
	# light_travel 一次最多分 256 段，路很长、边界很多时接着再走。
	for i in 64:
		var trip := Hazards.light_travel(s, from + direction * moved / size, direction, length - moved, INF)
		if trip["arrival"] != INF:
			return time + trip["arrival"]
		if trip["distance"] <= 0.0:
			return INF
		moved += trip["distance"]
		time += trip["time"]
	return INF


## 消息现在在哪：从这一段的起点按现在的光速走了 (现在 − 出发时刻) 年的地方。只在换图、重新算到达时间时用。
## 不按时间比例在直线上取点：路上光速不一样时（先慢后快），按比例取的点会比真实位置靠前，重算出来的到达时刻就早了。
## 这一段出发以后光速只可能在上次重算之后才变（变了就会重算），所以按现在的光速走，最多差一个 0.05 年。
static func position(s: GameState, message: Dictionary) -> Vector3:
	if not message.has("eta"):
		return message["pos"] # 旧存档：消息还是逐步挪的，pos 就是现在的位置。
	var eta: float = message["eta"]
	var source: Vector3 = message["source"]
	var target: Vector3 = message["target"]
	if eta != INF and s.clock >= eta:
		return target
	var elapsed: float = s.clock - message["sent"]
	var size := s.physical_cell_size()
	var length := source.distance_to(target) * size
	if elapsed <= 0.0 or length <= Balance.COLLISION_EPSILON:
		return source
	var direction := (target - source).normalized()
	var moved := 0.0
	var time := 0.0
	# light_travel 一次最多分 256 段，路很长、边界很多时接着再走。
	for i in 64:
		var trip := Hazards.light_travel(s, source + direction * moved / size, direction, length - moved, elapsed - time)
		if trip["arrival"] != INF:
			return target
		moved += trip["distance"]
		time += trip["time"]
		if time >= elapsed - 1e-12 or trip["distance"] <= 0.0:
			break
	return source + direction * moved / size


## 把每条消息的起点挪到它现在所在的位置、出发时刻改成现在。换图前先做，坐标才能跟着迁移。
static func rebase(s: GameState) -> void:
	for message in s.messages:
		if not message["dead"]:
			_rebase_one(s, message)


static func _rebase_one(s: GameState, message: Dictionary) -> void:
	var at := position(s, message)
	message["pos"] = at
	message["source"] = at
	message["sent"] = s.clock


## 光速变了（黑域、死线、格子光速、换图）：从现在的位置按新的光速重新算到达时间。
## before 是上次算时的 medium。只是几个格子降了维、或者黑域在扩大、死线在延长（光速变化的范围变了，个数没变）时，
## 只重算路线碰到这些地方的消息（_retime_near）；其余消息一路光速没变，到达时间照旧。别的变化全部重算。
static func retime(s: GameState, before: Array = []) -> void:
	var now := medium(s)
	var near := before.size() == now.size()
	for i in now.size() if near else 0:
		if before[i] != now[i] and not (i >= MEDIUM_HAZARDS or (i == MEDIUM_CELLS and not s.converted_cells.is_empty())):
			near = false
	var shapes := hazard_shapes(s)
	if near:
		var cells: Array[Vector3i] = []
		if before[MEDIUM_CELLS] != now[MEDIUM_CELLS]:
			cells = s.converted_cells
		_retime_near(s, cells, shapes + s.hazard_shapes)
	else:
		rebase(s)
		for message in s.messages:
			if not message["dead"]:
				message["eta"] = s.clock + travel_time(s, message["source"], message["target"])
	s.hazard_shapes = shapes
	s.converted_cells.clear()
	s.message_due = [-INF, -INF]
	s.message_index.clear()


## 黑域和死线影响光速的范围：[一端, 另一端, 半径]，单位是格。黑域取算光速用的半径（Hazards.field_radius）。
static func hazard_shapes(s: GameState) -> Array:
	var shapes := []
	for source in s.black_domains:
		shapes.append(domain_shape(s, source))
	for line in s.deadlines:
		shapes.append(deadline_shape(s, line))
	return shapes


static func domain_shape(s: GameState, source: Dictionary) -> Array:
	var reach := Hazards.field_radius(s, source) + 1e-6
	return [source["pos"], source["pos"], reach / s.physical_cell_size()]


static func deadline_shape(s: GameState, line: Dictionary) -> Array:
	return [line["a"], line["b"], (Balance.DEADLINE_RADIUS + 1e-6) / s.physical_cell_size()]


## 光速马上要变（cells 里的格子、shapes 里的范围）：先把走过或要走这些地方的在途消息，按还没变的光速挪到现在的位置。
## 到达时间留给之后的 retime 重算。不先挪的话，retime 会把变化之前走的那段也按新光速重走一遍，光速变快时消息就提前到了。
static func before_light_change(s: GameState, cells: Array[Vector3i], shapes: Array) -> void:
	var boxes := Geometry.cell_boxes(cells)
	for message in s.messages:
		if not message["dead"] and message.has("eta") and message["sent"] < s.clock \
				and _touches(boxes, shapes, message["source"], message["target"]):
			_rebase_one(s, message)


## 降维前沿在 s.clock 这一刻扫过 cells（可能是过去的某一刻，当时没停、现在才补上，见 SpaceEvents.resolve）。
## 降维前调用：把那一刻之前发出、还没到、路线碰到这些格子的消息，按还没变的光速挪到那一刻的位置。
static func before_cells_change(s: GameState, cells: Array[Vector3i]) -> void:
	var boxes := Geometry.cell_boxes(cells)
	for message in s.messages:
		if message["dead"] or not message.has("eta") or message["sent"] >= s.clock or message["eta"] <= s.clock:
			continue
		if Geometry.crosses_cells(boxes, message["source"], message["target"]):
			_rebase_one(s, message)


## 降维后调用：那一刻和那以后发出、路线碰到这些格子的消息（包括刚挪过的），从出发的地方按新的光速重算到达时刻。
## 和那一刻停下来重算的结果一样，消息不会早到。
## 这些格子的消息都已经重算好，之后的 retime 不用再管它们：从 converted_cells 里拿掉。
## 要是交给 retime，它会从上次重算的时刻起把这几格都当成已经降维，消息被算晚。
static func after_cells_change(s: GameState, cells: Array[Vector3i]) -> void:
	var boxes := Geometry.cell_boxes(cells)
	for message in s.messages:
		if not message["dead"] and message.has("eta") and message["sent"] >= s.clock \
				and Geometry.crosses_cells(boxes, message["source"], message["target"]):
			message["eta"] = message["sent"] + travel_time(s, message["source"], message["target"])
	s.message_due = [-INF, -INF]
	s.message_index.clear()
	for cell in cells:
		s.converted_cells.erase(cell)
	# 格子维度的变化已经处理完，retime 就不会因为它把所有消息重算一遍。
	if s.converted_cells.is_empty() and s.message_medium.size() > MEDIUM_CELLS:
		s.message_medium[MEDIUM_CELLS] = hash(s.cell_dims)

## 只重算剩下的路线碰到 cells 里某一格、或者碰到 shapes 里某一处范围的消息。
static func _retime_near(s: GameState, cells: Array[Vector3i], shapes: Array) -> void:
	var boxes := Geometry.cell_boxes(cells)
	for message in s.messages:
		if message["dead"]:
			continue
		# 先用整段（起点到瞄准点）粗筛，碰不到的不用算现在的位置。
		if not _touches(boxes, shapes, message["source"], message["target"]):
			continue
		var at := position(s, message)
		if _touches(boxes, shapes, at, message["target"]):
			_rebase_one(s, message)
			message["eta"] = s.clock + travel_time(s, at, message["target"])


static func _touches(boxes: Array[AABB], shapes: Array, a: Vector3, b: Vector3) -> bool:
	if Geometry.crosses_cells(boxes, a, b):
		return true
	for shape in shapes:
		if Geometry.segment_distance(a, b, shape[0], shape[1]) <= shape[2]:
			return true
	return false


## 决定什么时候要重新算到达时间：这些东西变了，光速就可能变了。
## medium 里第几项是各格维度，从第几项起是黑域和死线（retime 据此认出可以只重算一部分的情况）：
## 黑域和死线的变化只影响它们新旧范围里的光速，所以只重算路线碰到这些范围的消息。
## 黑域长大时每 ROUGH_DT 年换一次半径（Hazards.field_radius），死线随船延长时多一小段，都会让这里变。
const MEDIUM_CELLS := 3
const MEDIUM_HAZARDS := 4


static func medium(s: GameState) -> Array:
	var growth := []
	for source in s.black_domains:
		growth.append(Hazards.field_radius(s, source))
	var pieces := 0
	for line in s.deadlines:
		pieces += Hazards.pieces(line).size()
	return [s.space_epoch, s.dimension, hash(s.light), hash(s.cell_dims), s.black_domains.size(), s.deadlines.size(),
			hash(s.domain_cells), growth, pieces]

## 这几种消息到了就改动实体或执行命令，要在到达的那一刻处理。
const EXACT_KINDS := ["command", "conversion_ready", "conversion_execute"]
## 收件者缓存的整数键：文明序号乘它再加收件者 ID（ID 远小于它，-1 也不会撞）。
const RECEIVER_KEY := 1 << 32


## 到达时要让整个世界停下来的消息：命令类，以及发给会自己动作的船（带武器的船自动开火、星舰避开敌方星系）的观测，
## 这些船收到就要能在下一小步反应。其余的情报（传感、回报）到了以后，等所在的子步结束才一起收（见 receive_due），
## 收到时刻仍记准确的到达时刻，不为它多切一刀。
static func exact(message: Dictionary) -> bool:
	return message["kind"] in EXACT_KINDS or message.get("prompt", false)


## 发给 receiver 的这条观测要不要到了就切开处理：只有船会马上用到的才要。
## 带武器的船看到的敌方单位（自动开火），星舰看到的敌方星系（避开它）。其余观测船上用不到，子步末再收。
static func _prompt(owner: int, kind: String, receiver: Dictionary, body: Dictionary) -> bool:
	if kind != "sensor" or not receiver.has("ship"):
		return false
	var ship: Ship = receiver["ship"]
	var data: Dictionary = body.get("data", {})
	var enemy: bool = data.get("owner", -1) >= 0 and data.get("owner", -1) != owner
	if body["type"] == "entity":
		return enemy and not ship.weapons.is_empty()
	return body["type"] == "cell" and enemy and ship.kind == Ship.STARSHIP


## 下一条到了就要切开的消息（exact）还要多久到（换图后要等到 not_before 才收）。
static func next_arrival(s: GameState) -> float:
	var next := INF
	for message in _indexed(s)["exact"]:
		if not message["dead"]:
			var at: float = maxf(message.get("eta", INF), message.get("not_before", -INF))
			next = minf(next, maxf(0.0, at - s.clock))
	return next


static func receive_due(s: GameState, depth := 0) -> void:
	assert(depth < 8, "本地零距离收据不能无限重发")
	var received: Array[Dictionary] = []
	var dropped := 0 # 收件者已经不在、直接作废的条数
	var receivers: Dictionary={}
	var size := s.physical_cell_size()
	var reach2 := (Balance.COLLISION_EPSILON / size) * (Balance.COLLISION_EPSILON / size)
	var due := s.clock + Balance.TIME_EPSILON
	# 最早的一条都还没到，这一遍不用逐条看。
	if s.message_due[1] > due:
		return
	# 只看到达分组不晚于现在的消息，按发出的先后处理。没处理的（还没到、等换图结束、追收件者）放回索引。
	var index := _indexed(s)
	var buckets: Dictionary = index["buckets"]
	var last := floori(due / BUCKET)
	var found: Array[Dictionary] = []
	for tick in range(index["low"], last + 1):
		if buckets.has(tick):
			found.append_array(buckets[tick])
			buckets.erase(tick)
	if index["low"] <= last:
		index["low"] = NEVER
		for tick in buckets:
			index["low"] = mini(index["low"], tick)
	found.sort_custom(func(a, b): return a["n"] < b["n"])
	# 后面的刻度里的消息都不早于这个时刻。
	var next_any := (last + 1) * BUCKET
	var previous := {}
	for message in found:
		if message["dead"] or is_same(message, previous):
			continue
		previous = message
		var eta: float = message.get("eta", INF)
		if eta > due:
			_file(index, message)
			next_any = minf(next_any, eta)
			continue
		if s.clock < message.get("not_before", -INF):
			# 已经到了，只是还要等换图结束：下次照样要看它。
			_file(index, message)
			next_any = minf(next_any, eta)
			continue
		var owner: int=message["owner"]
		var key: int=owner*RECEIVER_KEY+message["recipient"]
		if not receivers.has(key):
			receivers[key]=entity(s,owner,message["recipient"])
		var receiver: Dictionary=receivers[key]
		message["pos"] = message["target"]
		# 到达时刻在这个子步里的，按收件者那一刻的位置判断收没收到；等换图结束才收的，按现在。
		var arrived: float = eta if eta >= s.step_start else s.clock
		if receiver.is_empty():
			# 收件者死亡不能令远端命令在发送瞬间退款，从余额泄露真实战况。
			message["dead"] = true
			dropped += 1
			if message["kind"] == "command":
				s._receive_command(message, false)
			continue
		if position_at(s, receiver, arrived).distance_squared_to(message["target"]) > reach2:
			# 收件者不在瞄准点：从瞄准点出发再追它。光到瞄准点以后已经又走了 clock - eta 年。
			var aim := _aim(s, owner, receiver, message["target"], s.clock - message["eta"])
			message["source"] = message["target"]
			message["sent"] = message["eta"]
			message["target"] = aim[0]
			message["eta"] += aim[1]
			if message["eta"] > due:
				_file(index, message)
				next_any = minf(next_any, message["eta"])
				continue
			message["pos"] = receiver["pos"]
			arrived = message["eta"]
		message["arrived"] = arrived
		message["dead"] = true
		received.append(message)
	var next_exact := INF
	var waiting: Array = []
	for message in index["exact"]:
		if not message["dead"]:
			waiting.append(message)
			next_exact = minf(next_exact, message.get("eta", INF))
	index["exact"] = waiting
	# 先记下剩下的消息里最早的到达时刻；下面收消息时新发出的消息会再往前更新（_expect）。
	s.message_due = [next_exact, minf(next_any, next_exact)]
	for message in received:
		_deliver(s, message)
		for body in message.get("more", []):
			var part: Dictionary = message.duplicate()
			part["body"] = body
			part.erase("more")
			_deliver(s, part)
	if dropped > 0 or not received.is_empty():
		# 收过的消息攒到总数的八分之一再一起删掉，不用每收一批就整份重排。
		index["dead"] += received.size() + dropped
		if index["dead"] * 8 >= s.messages.size():
			s.messages = s.messages.filter(func(m): return not m["dead"])
			index["dead"] = 0
		receive_due(s, depth + 1)


## 收下一条消息。收到的时刻记成它真正到达的时刻（arrived），不记现在：情报类消息到了以后，
## 等到所在的子步结束才一起收，不为它多切一刀。
static func _deliver(s: GameState, message: Dictionary) -> void:
	var owner: int = message["owner"]
	var civ: Civ = s.civs[owner]
	var receiver := entity(s, owner, message["recipient"])
	var body: Dictionary = message["body"]
	var now: float = message.get("arrived", s.clock)
	if message["kind"]=="survey_record":
		Information.receive_record(s,message)
		return
	if message["kind"]=="survey_query":
		Information.receive_query(s,message)
		return
	if message["kind"] == "command":
		s._receive_command(message, true)
		return
	if message["kind"] == "conversion_ready":
		if not receiver.is_empty():
			var ready: Dictionary = receiver["ship"].ready if receiver.has("ship") else receiver["asset"]["ready"]
			ready[body["step"]] = {"at": s.clock, "fraction": body["fraction"], "plan": body["plan"], "automatic": body.get("automatic", false)}
			send(s, owner, receiver["pos"], controller(civ), "report", {"type": "conversion_ready_receipt",
					"plan": body["plan"], "entity": message["recipient"], "t_observed": s.clock, "epoch": s.space_epoch})
		return
	if message["kind"] == "conversion_execute":
		if not receiver.is_empty():
			Conversion.apply(s, civ, receiver, body["step"], false)
		return
	if message["kind"] == "sensor":
		body["t_local_received"] = now
		if receiver.has("ship") and body["type"] == "cell":
			var key: String="cell:%d"%body["cell_id"]
			if receiver["ship"].local_contacts.get(key,{}).get("t_observed",-INF)<=body["t_observed"]:
				receiver["ship"].local_contacts[key]={"id":-body["cell_id"]-1,"kind":"anchor",
					"owner":body["data"]["owner"],"pos":Vector3(body["cell"]),"velocity":Vector3.ZERO,"hp":0,
					"t_observed":body["t_observed"],"t_received":now,"epoch":body["epoch"]}
		if receiver.has("ship") and body["type"] == "entity":
			var contact: Dictionary = body["data"].duplicate(true)
			contact["t_observed"] = body["t_observed"]
			contact["t_received"] = now
			contact["epoch"] = body["epoch"]
			if receiver["ship"].local_contacts.get(contact["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
				receiver["ship"].local_contacts[contact["id"]] = contact
		elif receiver.has("asset") and body["type"] == "entity":
			var contact: Dictionary = body["data"].duplicate(true)
			contact.merge({"t_observed":body["t_observed"],"t_received":now,"epoch":body["epoch"]},true)
			if not civ.local_contacts_by_source.has(message["recipient"]):
				civ.local_contacts_by_source[message["recipient"]] = {}
			if civ.local_contacts_by_source[message["recipient"]].get(contact["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
				civ.local_contacts_by_source[message["recipient"]][contact["id"]] = contact
		if message["recipient"] != controller(civ):
			if not receiver.is_empty():
				# 转发从到达的那一刻、收件者那时所在的位置出发，转多少手都不多等。
				var lag := s.clock - now
				var relay := send(s, owner, position_at(s, receiver, now), controller(civ), "report", body, 0, lag <= 0.0)
				catch_up(s, relay, lag)
			return
	body["t_received"] = now
	if body["type"]=="permission":
		var tier: int=body["tier"]
		var proof: Dictionary=civ.pending_permissions.get(tier,{})
		if proof.get("id",-1)==body["ticket"]:
			proof["waiting"].erase(body["source"])
	elif body["type"]=="front":
		var id: int=body["data"]["id"]
		if civ.front_reports.get(id,{}).get("t_observed",-INF)<=body["t_observed"]:
			civ.front_reports[id]=body.duplicate(true)
	elif body["type"]=="broadcast_sent":
		civ.broadcast_reports[body["data"]["id"]]=body["data"].duplicate(true)
	elif body["type"]=="wake":
		var data: Dictionary=body["data"]
		if not civ.wake_reports.has(data["id"]):
			civ.wake_reports[data["id"]]={}
		var ends: Dictionary=civ.wake_reports[data["id"]]
		if ends.get(data["endpoint"],{}).get("t_observed",-INF)<=body["t_observed"]:
			ends[data["endpoint"]]=body.duplicate(true)
	elif body["type"] == "conversion_ready_receipt":
		if civ.conversions.has(body["plan"]):
			var plan: Dictionary=civ.conversions[body["plan"]]
			if not plan.has("ready_reports"):
				plan["ready_reports"]={}
			if plan["ready_at"].get(body["entity"],-INF)<=body["t_observed"]:
				plan["ready_at"][body["entity"]]=body["t_observed"]
				plan["ready_reports"][body["entity"]]={"t_observed":body["t_observed"],"t_received":now,"epoch":body["epoch"]}
	elif body["type"] == "site_destroyed":
		Information.receive_battle(s,owner,body)
	elif body["type"] == "battle_survey":
		var id: int=s.battle_tokens.get(owner,{}).get(body["event_id"],-1)
		if id<0:
			return
		if not civ.battle_surveys.has(id):
			civ.battle_surveys[id]={"t_observed":body["t_observed"],"epoch":body["epoch"],"seen":{},"owners":{}}
		var survey: Dictionary=civ.battle_surveys[id]
		if survey["t_observed"]==body["t_observed"] and survey["epoch"]==body["epoch"]:
			survey["seen"][body["cell_id"]]=true
			survey["owners"][body["local_owner"]]=true
		Information.confirm_battles(s,civ)
	elif body["type"] == "hit":
		civ.times_hit+=1
		civ.hit_dirs.append({"at":body["cell"],"dir":body["direction"],"turn":s.turn,"t_observed":body["t_observed"],"t_received":now})
	elif body["type"] == "broadcast":
		civ.heard[body["target"]] = s.turn
		civ.known[body["target"]] = s.turn
		if body.get("has_exposure",false):
			civ.known[body["exposed"]] = s.turn
		s._discover(civ,"收到广播坐标")
	elif body["type"] == "warning":
		var warning: Dictionary = body["data"].duplicate(true)
		warning.merge({"turn":s.turn,"t_observed":body["t_observed"],"t_received":now,"source_id":body["source_id"],"epoch":body["epoch"]},true)
		civ.alerts = civ.alerts.filter(func(old):return old.get("id",-1)!=warning["id"])
		civ.alerts.append(warning)
	elif body["type"] == "payload":
		var data: Dictionary = body["data"]
		if civ.payload_reports.get(data["id"],{}).get("t_observed",-INF)>body["t_observed"]:
			return
		civ.payload_reports[data["id"]]=body.duplicate(true)
		if data["dead"]:
			civ.foils=civ.foils.filter(func(foil):return foil.id!=data["id"])
		else:
			for foil in civ.foils:
				if foil.id==data["id"]:
					foil.current_position=data["pos"]
					foil.traveled=data["distance"]/s.physical_cell_size()
	elif body["type"] == "order":
		var data: Dictionary = body["data"].duplicate(true)
		data["t_observed"] = body["t_observed"]
		data["t_received"] = now
		if civ.order_reports.get(data["id"],{}).get("t_observed",-INF)<=body["t_observed"]:
			var previous: String=civ.order_reports.get(data["id"],{}).get("status","")
			if previous in ["completed","failed","destroyed","cancelled"]:
				return
			if civ.order_reports.get(data["id"],{}).get("cancel_pending",false):
				data["cancel_pending"]=true
			civ.record_order(data["id"], data)
			if data["status"]=="failed":
				var refund: Array=data.get("failure_refund",[0,0])
				civ.energy_millis+=refund[0]
				civ.mineral_millis+=refund[1]
				civ.ledger.append({"t":s.clock,"kind":"failed_order_refund","order":data["id"],"delta":refund.duplicate()})
			if data["status"]=="completed" and previous!="completed":
				if data["category"]=="research":
					civ.techs[data["kind"]]=true
				elif data["category"]=="upgrade" and data["kind"]=="telescope":
					civ.telescope+=1
				elif data["kind"]=="antimatter":
					civ.antimatter+=1
				elif data["kind"]=="dimension_weapon":
					civ.dimension_ammo+=1
				if civ==s.human():
					s.add_log("收到工程完成回报：%s"%Tech.title(data["kind"]) if data["category"]=="research" else "收到建造完成回报：%s"%GameState.BUILD_NAMES.get(data["kind"],data["kind"]))
	elif body["type"] == "command_result":
		civ.energy_millis += body["refund"][0]
		civ.mineral_millis += body["refund"][1]
		civ.antimatter += body.get("ammo_refund",0)
		civ.dimension_ammo += body.get("dimension_refund",0)
		if not body["executed"] and body.get("payload_id",-1)>=0:
			civ.foils=civ.foils.filter(func(f):return f.id!=body["payload_id"])
		if body["request_name"]=="scan":
			civ.scan_ready_at = body["scan_ready_at"] if body["executed"] else s.clock
		civ.command_pending.erase(body["command"])
		civ.command_results.append(body.duplicate(true))
		civ.ledger.append({"t": s.clock, "kind": "command_receipt", "command": body["command"], "delta": body["refund"].duplicate()})
	elif body["type"] == "cell":
		var cell: Vector3i = body["cell"]
		var cell_id: int = body.get("cell_id", s.cell_ids.get(cell, -1))
		if body.get("passive", false):
			if not civ.coverage.has(cell_id):
				civ.coverage[cell_id] = {}
			civ.coverage[cell_id][body["source_id"]] = {"t_observed": body["t_observed"], "t_received": now, "epoch": body["epoch"]}
		var first_discovery := not civ.intel.has(cell) and not Knowledge.owns(s,civ,cell)
		var info: Dictionary = body["data"].duplicate(true)
		info.merge({"t_observed": body["t_observed"], "t_received": now,
				"source_id": body["source_id"], "epoch": body["epoch"]}, true)
		if civ.intel.has(cell) and civ.intel[cell].get("t_observed", -INF) > body["t_observed"]:
			return
		civ.intel[cell] = info
		if first_discovery:
			s._discover(civ, "首次收到未知星系观测")
		if body.get("contact", false):
			civ.contacted = true
		if info["owner"] >= 0 and info["owner"] != owner:
			civ.known[cell] = s.turn
			s._discover(civ, "收到异文明星系观测")
		else:
			civ.known.erase(cell)
	elif body["type"] == "entity":
		var contact: Dictionary = body["data"].duplicate(true)
		contact.merge({"t_observed": body["t_observed"], "t_received": now,
				"source_id": body["source_id"], "epoch": body["epoch"], "turn": s.turn}, true)
		# 一遍找出同一单位的旧记录：有更新的就不收，否则删掉旧的、新的放到末尾。
		var same: Array[int]=[]
		for i in civ.sightings.size():
			var old: Dictionary=civ.sightings[i]
			if old.get("id",-1)==contact["id"]:
				if old.get("t_observed",-INF)>body["t_observed"]:
					return
				same.append(i)
		for i in range(same.size()-1,-1,-1):
			civ.sightings.remove_at(same[i])
		civ.sightings.append(contact)
		if body.get("contact",false):
			civ.contacted=true
		if contact["owner"] >= 0 and contact["owner"] != owner:
			s._discover(civ, "收到异文明单位观测")
	elif body["type"] == "own_site":
		var cell: Vector3i=body["data"]["cell"]
		if civ.site_reports.get(cell,{}).get("t_observed",-INF)<=body["t_observed"]:
			civ.site_reports[cell]=body.duplicate(true)
			if civ.intel.get(cell,{}).get("t_observed",-INF)<=body["t_observed"]:
				civ.intel[cell]=body["data"]["snapshot"].duplicate(true)
				civ.intel[cell].merge({"t_observed":body["t_observed"],"t_received":now,"turn":s.turn,"source_id":body["source_id"],"epoch":body["epoch"]},true)
	elif body["type"] == "own":
		var id: int = body["data"]["id"]
		if not civ.telemetry.has(id) or civ.telemetry[id]["t_observed"] <= body["t_observed"]:
			civ.telemetry[id] = body.duplicate(true)
			civ.telemetry[id]["t_received"] = now
	if not civ.battle_reports.is_empty() and body["type"] in ["own","own_site"]:
		Information.query_battles(s,civ)
	_receive_permissions(s,civ)


static func _receive_permissions(s: GameState,civ: Civ) -> void:
	for tier in civ.pending_permissions.keys():
		var proof: Dictionary=civ.pending_permissions[tier]
		for cell in civ.site_reports:
			if not civ.site_reports[cell]["data"].get("owned",true):
				proof["missing_sites"].erase(s.cell_ids.get(cell,-1))
		for id in proof["missing_ships"].duplicate():
			if civ.telemetry.get(id,{}).get("data",{}).get("dead",false):
				proof["missing_ships"].erase(id)
		if proof["waiting"].is_empty() and proof["missing_sites"].is_empty() and proof["missing_ships"].is_empty():
			civ.set_tier_turn(tier,s.turn+1)
			civ.pending_permissions.erase(tier)


static func observers(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for asset in civ.assets:
		if asset["kind"] != "anchor" or civ.dormant_colonies.has(asset["at"]):
			continue
		result.append({"id": asset["id"], "pos": Vector3(asset["at"]), "dir": Vector3.ZERO,
				"radius": (Balance.VISION_HOME if asset["at"] == civ.home else Balance.VISION_COLONY) + civ.vision_bonus(),
				"angle": 0.0, "backward": 0.0})
	for ship in civ.ships:
		if ship.dead or ship.dormant or ship.kind == Ship.GRAIN:
			continue
		var cone := ship.kind in [Ship.PROBE, Ship.NUCLEAR_PROBE, Ship.DROPLET] and ship.direction != Vector3.ZERO
		var base := Balance.VISION_SHIP
		if ship.kind == Ship.SOPHON:
			base = Balance.SOPHON_VISION
		elif ship.kind in [Ship.STARSHIP, Ship.WANDERING_EARTH]:
			base = Balance.VISION_HOME if ship.kind == Ship.WANDERING_EARTH else Balance.VISION_COLONY
		result.append({"id": ship.id, "pos": ship.pos, "dir": ship.direction if cone else Vector3.ZERO,
				"radius": base + civ.vision_bonus(), "angle": Balance.PROBE_ANGLE + civ.telescope * Balance.TELESCOPE_ANGLE_STEP,
				"backward": civ.telescope * Balance.LINE_BACKWARD_PER_LEVEL if s.dimension == 1 else 0.0})
	return result


## in_view 能看到的点离观察者最远多少格（取平方），用来先便宜地排除远处的点；排除的点 in_view 一定也看不到。
## 圆锥最远在边沿上：半径 ÷ cos(半张角)。一维时视野不受这个距离限制，返回 INF。
static func view_reach2(s: GameState, observer: Dictionary) -> float:
	var reach: float = observer["radius"]
	if observer["dir"] != Vector3.ZERO:
		var half := deg_to_rad(observer["angle"] * 0.5)
		if s.dimension == 1 or half >= deg_to_rad(80.0):
			return INF
		reach = reach / cos(half) + Balance.COLLISION_EPSILON
	reach = (reach + 1e-6) / s.physical_cell_size() * 1.0001
	return reach * reach


static func in_view(s: GameState, observer: Dictionary, pos: Vector3) -> bool:
	var d: Vector3 = (pos - observer["pos"]) * s.physical_cell_size()
	var radius: float = observer["radius"]
	if observer["dir"] == Vector3.ZERO:
		return d.length() <= radius + 1e-7
	var forward := d.dot(observer["dir"])
	if s.dimension == 1:
		return forward <= radius and forward >= -radius * observer["backward"]
	return forward >= 0.0 and forward <= radius and (d - observer["dir"] * forward).length() <= forward * tan(deg_to_rad(observer["angle"] * 0.5)) + Balance.COLLISION_EPSILON


## 点离视野边缘多远（物理距离）：在视野里时不大于 0。和 in_view 用同样的判断，d 是点减观察者（物理距离）。
## 离得越远值越大，而且点每挪 1 光年，值最多变 _view_slope 光年，_first_seen 据此排除看不到的时间段。
static func _view_margin(s: GameState, observer: Dictionary, d: Vector3) -> float:
	var radius: float = observer["radius"]
	var dir: Vector3 = observer["dir"]
	if dir == Vector3.ZERO:
		return d.length() - radius - 1e-7
	var forward := d.dot(dir)
	if s.dimension == 1:
		return maxf(forward - radius, -radius * observer["backward"] - forward)
	var off := (d - dir * forward).length()
	return maxf(maxf(-forward, forward - radius), off - forward * tan(deg_to_rad(observer["angle"] * 0.5)) - Balance.COLLISION_EPSILON)


static func _view_slope(s: GameState, observer: Dictionary) -> float:
	if observer["dir"] == Vector3.ZERO or s.dimension == 1:
		return 1.0
	return 1.0 + tan(deg_to_rad(observer["angle"] * 0.5))


## 上一个子步里，目标最早什么时候在视野里（离子步开始多少年），一直看不到时为 INF。
## r0、v、a 是目标相对观察者的位置、速度、加速度（格），子步开始时的值；observer 给出视野形状（子步里不变）。
## 把时间段对半分：按视野边缘的距离和相对速度，整段都不可能进视野的就排除，最后准到 TIME_EPSILON 年。
## slack（光年）把视野边缘往外放宽：预测进入视野时用，宁可早一点，不会因为浮点误差错过刚好擦边的（见 ViewMarks）。
static func _first_seen(s: GameState, observer: Dictionary, r0: Vector3, v: Vector3, a: Vector3, dt: float, slack := 0.0) -> float:
	return _seen_between(s, observer, r0, v, a, _view_slope(s, observer) * s.physical_cell_size(), 0.0, dt, slack)


static func _seen_between(s: GameState, observer: Dictionary, r0: Vector3, v: Vector3, a: Vector3, scale: float, lo: float, hi: float, slack := 0.0) -> float:
	var size := s.physical_cell_size()
	var low := _view_margin(s, observer, (r0 + v * lo + 0.5 * a * lo * lo) * size) - slack
	if low <= 0.0:
		return lo
	var high := _view_margin(s, observer, (r0 + v * hi + 0.5 * a * hi * hi) * size) - slack
	# 这一段里离边缘最近也不小于 (low + high − 最快变化 × 段长) / 2。
	var change := ((v + a * lo).length() + a.length() * (hi - lo)) * scale * (hi - lo)
	if low + high - change > 0.0:
		return INF
	if hi - lo <= Balance.TIME_EPSILON:
		return hi if high <= 0.0 else INF
	var mid := (lo + hi) * 0.5
	var left := _seen_between(s, observer, r0, v, a, scale, lo, mid, slack)
	return left if left != INF else _seen_between(s, observer, r0, v, a, scale, mid, hi, slack)


## 上一个子步里这样东西怎么动：{"pos": 子步开始时的位置, "velocity", "acceleration"}（格/年）。
## id 没记下运动（不动的设施和据点）时，就当它一直在 pos。
static func _path(s: GameState, id: int, pos: Vector3) -> Dictionary:
	return s.step_motions.get(id, {"pos": pos, "velocity": Vector3.ZERO, "acceleration": Vector3.ZERO})


static func _moved(path: Dictionary) -> bool:
	return path["velocity"] != Vector3.ZERO or path["acceleration"] != Vector3.ZERO


## 观察者在上一个子步里的视野：圆锥朝它那时飞的方向（子步末可能刚转向）。
static func _past_view(observer: Dictionary, path: Dictionary) -> Dictionary:
	if observer["dir"] == Vector3.ZERO or not _moved(path):
		return observer
	var past := observer.duplicate()
	var heading: Vector3 = path["velocity"] if path["velocity"] != Vector3.ZERO else path["acceleration"]
	past["dir"] = heading.normalized()
	return past


## 动的观察者在上一个子步里有没有新看到不动的点 point（子步开始时已在视野里的，上一次采样看过，不算）。
## past 是那时的视野，path 是它这一步的运动。
static func _passed(s: GameState, past: Dictionary, path: Dictionary, point: Vector3, dt: float) -> bool:
	var seen := _first_seen(s, past, point - path["pos"], -path["velocity"], -path["acceleration"], dt)
	return seen > 0.0 and seen < INF


## 伤害提交前冻结实体事实，不保存对象引用，也不进存档或校验值。
static func capture_facts(s: GameState) -> void:
	s.step_facts.clear()
	for target in Combat.targets(s, true):
		s.step_facts[target["id"]] = {"id": target["id"], "owner": target["owner"], "kind": target["kind"], "hp": target["hp"]}


## 目标在上一个子步开始后 t 年时的样子：事实取段首，运动按 trail 推出。
static func _entity_data(s: GameState, target: Dictionary, trail: Dictionary, t: float, start: float) -> Dictionary:
	var facts: Dictionary = s.step_facts.get(target["id"], target)
	var data := {"id": facts["id"], "owner": facts["owner"], "kind": facts["kind"],
			"pos": Kinematics.position(trail, t), "velocity": trail["velocity"] + trail["acceleration"] * t,
			"acceleration": trail["acceleration"], "hp": facts["hp"]}
	if trail.get("cap_time", INF) < INF:
		data["accel_until"] = start + trail["cap_time"]
	return data


## 两条子步里的轨迹（起点 a0、b0，终点 a1、b1，各自加速度）有没有可能相距不到 reach 格。只是粗筛。
static func _may_meet(a0: Vector3, a1: Vector3, aa: Vector3, b0: Vector3, b1: Vector3, ba: Vector3, dt: float, reach: float) -> bool:
	if not is_finite(reach):
		return true
	var bend := (aa.length() + ba.length()) * dt * dt / 8.0
	return Geometry.segment_distance(a0, a1, b0, b1) <= reach + bend + 1e-6


## 按位置把目标分进 BUCKET_CELLS 格见方的桶，好让每个观察者只查附近的目标（只为算得快，结果不变）。
## 目标放进它这一步扫过的每个桶（起点到终点的方框，加上弯曲的余量）；扫过太多桶的放进 "wide"，谁都查它。
static func _entity_buckets(entities: Array[Dictionary], dt: float) -> Dictionary:
	var buckets := {"wide": []}
	for i in entities.size():
		var box := _sweep_box(entities[i]["path"], entities[i]["pos"], dt, 0.0)
		var keys := _bucket_keys(box[0], box[1])
		if keys.is_empty():
			buckets["wide"].append(i)
		for key in keys:
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(i)
	return buckets


## 这一步从 path 的起点走到 pos 扫过的方框 [最低角, 最高角]，四周再放宽 margin 格。path 是空的就当没动。
static func _sweep_box(path: Dictionary, pos: Vector3, dt: float, margin: float) -> Array[Vector3]:
	var low := pos
	var high := pos
	if not path.is_empty():
		margin += path["acceleration"].length() * dt * dt / 8.0
		low = low.min(path["pos"])
		high = high.max(path["pos"])
	return [low - Vector3.ONE * margin, high + Vector3.ONE * margin]


## 方框碰到的桶；超过 BUCKET_LIMIT 个（或方框无限大）时返回空，由调用方改为全查。
static func _bucket_keys(low: Vector3, high: Vector3) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	if not (low.is_finite() and high.is_finite()):
		return keys
	var a := Vector3i((low / BUCKET_CELLS).floor())
	var b := Vector3i((high / BUCKET_CELLS).floor())
	if (b.x - a.x + 1) * (b.y - a.y + 1) * (b.z - a.z + 1) > BUCKET_LIMIT:
		return keys
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				keys.append(Vector3i(x, y, z))
	return keys


## 观察者这一步可能看到的目标，按 entities 里的原顺序。box 是观察者扫过的方框（已放宽视野距离）。
static func _nearby(buckets: Dictionary, count: int, box: Array[Vector3]) -> Array:
	var keys := _bucket_keys(box[0], box[1])
	if keys.is_empty():
		return range(count)
	var found := {}
	for i in buckets["wide"]:
		found[i] = true
	for key in keys:
		for i in buckets.get(key, []):
			found[i] = true
	var result := found.keys()
	result.sort()
	return result


## 不动的观察者看得到的星系：[[格子, 消息键, 星系编号], ...]，顺序和 Geometry.cells_near 一样。
## 观察者的位置、视野和星系表都没变时，直接用上次的结果。
static func _cells_in_view(s: GameState, index: Dictionary, observer: Dictionary, reach2: float) -> Array:
	var shape := [observer["pos"], observer["dir"], observer["radius"], observer["angle"], observer["backward"], s.dimension, s.system_cells.size()]
	var known: Dictionary = s.view_cells.get(observer["id"], {})
	if known.get("shape") == shape:
		return known["cells"]
	var cells := []
	for cell in Geometry.cells_near(s.system_cells, index, observer["pos"], sqrt(reach2)):
		var point := Vector3(cell)
		if (point - observer["pos"]).length_squared() <= reach2 and in_view(s, observer, point):
			var id: int = s.cell_ids.get(cell, -1)
			cells.append([cell, "%d:cell:%d" % [observer["id"], id], id])
	s.view_cells[observer["id"]] = {"shape": shape, "cells": cells}
	return cells


## 观测内容不变时，每隔这么多年（心跳）照样重发一次。
const HEARTBEAT := 1.0

## 航位推算：观测里有位置和速度时，这两项不算进签名。目标照上次观测的速度和加速度走、
## 走到了推算的位置和速度，就当没变，不重发；收件方用 Combat.observed 按同样的式子推算。
## 加速度、种类、损伤等别的内容变了，或者实际位置、速度偏离推算，才立即重发。心跳照旧每年一次。
## at 是观测时刻（不给就是现在）：在上一个子步中间进入视野的，按进入那一刻发出（catch_up）。
## signature 不给时按 body 现算；同一次采样里很多观察者发同样内容时，由调用方算一次传进来。
static func _emit(s: GameState, owner: int, observer: Dictionary, origin: Vector3, key: String, body: Dictionary, heartbeat: bool, at := INF, signature = null) -> void:
	var now := s.clock if at == INF else at
	var data: Dictionary = body["data"]
	var moving: bool = data.has("pos") and data.has("velocity")
	if signature == null:
		var facts := data
		if moving:
			facts = data.duplicate()
			facts.erase("pos")
			facts.erase("velocity")
			facts.erase("accel_until") # 每次算出来都差一点浮点误差，不能因此重发；到了最高速度加速度会变成 0，那时照样重发。
		signature = hash([facts,body.get("contact",false)])
	var stamp: Dictionary = s.sensor_stamps.get(key, {})
	var same: bool = stamp.get("hash", -1) == signature
	if same and moving:
		var t: float = now - stamp["time"]
		var acceleration: Vector3 = data.get("acceleration", Vector3.ZERO)
		var velocity: Vector3 = stamp.get("velocity", Vector3.INF)
		var pos: Vector3 = stamp.get("pos", Vector3.INF) + velocity * t + 0.5 * acceleration * t * t
		same = stamp.get("epoch", -1) == s.space_epoch \
				and pos.distance_to(data["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON \
				and (velocity + acceleration * t).distance_to(data["velocity"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON
	if s.view_dry:
		# 核对模式（_check_missed）：只记下内容变了却没发的，心跳不算。
		if not same:
			s.view_missed.append(key)
		return
	if same and (not heartbeat or now - stamp.get("time", -INF) < HEARTBEAT):
		return
	s.sensor_stamps[key] = {"hash": signature, "time": now}
	if moving:
		s.sensor_stamps[key].merge({"pos": data["pos"], "velocity": data["velocity"], "epoch": s.space_epoch})
	body["t_observed"] = now
	body["epoch"] = s.space_epoch
	body["source_id"] = observer["id"]
	var lag := s.clock - now
	catch_up(s, send(s, owner, origin, observer["id"], "sensor", body, 0, lag <= 0.0), lag)


## 看视野。每回合开始时全看一遍；之后每个子步结束时，只看变了的东西和预测在这一步里进入视野的（ViewMarks）。
## 两次之间新进视野、或者整个穿过视野的：移动的单位按进入视野那一刻的位置和速度发出观测（_emit 的 at）；
## 不动的星系、航迹端点、空间前沿只要这一步里进过视野，就按现在发出（只会晚，不会早）。
static func sample(s: GameState, _force := false) -> void:
	Information.retry_archives(s)
	var entities := Combat.targets(s, true, true)
	# 上一个子步的长度；回合开始那一次没有上一步，只看现在。
	var dt := s.clock - s.step_start
	var sweep := dt > Balance.TIME_EPSILON and not s.step_motions.is_empty()
	var where := {}
	for i in entities.size():
		var target: Dictionary = entities[i]
		var mover: int = target["asset"]["carrier"] if target.has("asset") else target["id"]
		target["path"] = s.step_motions.get(mover, {}) if sweep else {}
		where[target["id"]] = i
	var look := {"entities": entities, "index": Geometry.cell_index(s.system_cells), "dt": dt, "sweep": sweep, "force": _force,
			"where": where, "snapshots": {}, "shapes": {}, "observers": []}
	ViewMarks.begin(s, look)
	for civ in s.civs:
		if not civ.alive:
			continue
		var owner := s.civs.find(civ)
		Knowledge.sample(s,civ,look)
		_sample_warning(s,civ,entities,dt if sweep else 0.0)
		for project in WorldTime.orders(civ):
			var period := 1.0
			if Balance.LOCAL_ORDER_REPORT_CURRENT == 1:
				var source: Dictionary = OrderControl.host(s,civ,project)
				var receiver := entity(s,owner,controller(civ))
				if not source.is_empty() and not receiver.is_empty() and source["pos"].distance_to(receiver["pos"])*s.physical_cell_size()<=Balance.COLLISION_EPSILON:
					# 本地也走报告链路；仅零距离时每次采样都报，不能把远端施工真值给界面或AI。
					period = 0.0
			if s.clock-project.get("report_time",-INF)>=period:
				project["report_time"] = s.clock
				OrderControl.report(s,civ,project,project.get("status","working"))
		for observer in observers(s, civ):
			var path := _path(s, observer["id"], observer["pos"]) if sweep else {}
			var moving := sweep and _moved(path)
			var past := _past_view(observer, path) if moving else observer
			var view := {"observer": observer, "path": path, "moving": moving, "past": past,
					"reach2": view_reach2(s, observer), "all": ViewMarks.observer_changed(s, look, observer)}
			look["observers"].append([owner, observer, view])
			for wake in s.deadlines:
				if wake["expires"]<=s.clock:
					continue
				# 两个端点各自走完整的光路；较近的一端不能替远端或被阻断端提供情报。
				for endpoint in 2:
					var pos: Vector3=wake["a"] if endpoint==0 else wake["b"]
					if in_view(s,observer,pos) or (moving and _passed(s, past, path, pos, dt)):
						_emit(s,owner,observer,pos,"%d:wake:%d:%d"%[observer["id"],wake["id"],endpoint],
							{"type":"wake","data":{"id":wake["id"],"endpoint":endpoint,"pos":pos,"turn":s.turn}},true)
			for entry in [["foil",s.foil_zones],["line",s.line_zones]]:
				for zone in entry[1]:
					var center := Vector3(zone["center"])
					if in_view(s,observer,center) or (moving and _passed(s, past, path, center, dt)):
						_emit(s,owner,observer,center,"%d:front:%d"%[observer["id"],zone.get("id",-1)],
							{"type":"front","front_type":entry[0],"data":zone.duplicate(true)},true)
			_look_cells(s, look, owner, view)
			_look_entities(s, look, owner, view)
		for ship in civ.ships:
			var key := "own:%d" % ship.id
			var stamp: Dictionary = s.sensor_stamps.get(key, {})
			# 每年一次常规定位回报；死亡等状态变化立即在当地发出，仍须等传回。
			var important := hash([ship.dead, ship.dormant, ship.damage, ship.weapons])
			if s.clock - stamp.get("time", -INF) < 1.0 and stamp.get("hash", -1) == important:
				continue
			var data := ship_status(ship)
			data["assets"]=civ.assets.filter(func(a):return a["carrier"]==ship.id).duplicate(true)
			s.sensor_stamps[key] = {"time": s.clock, "hash": important}
			send(s, owner, ship.pos, controller(civ), "report", {"type": "own", "data": data,
					"t_observed": s.clock, "source_id": ship.id, "epoch": s.space_epoch})
	ViewMarks.finish(s, look)
	if not look["full"]:
		var ne := 0
		for k in s.view_marks["entries"]: ne += s.view_marks["entries"][k].size()
	if s.view_check and not look["full"]:
		_check_missed(s, look)


## 一个观察者看星系。view["all"] 时看它视野里的全部，否则只看 ViewMarks 挑出来的。
static func _look_cells(s: GameState, look: Dictionary, owner: int, view: Dictionary) -> void:
	var observer: Dictionary = view["observer"]
	var path: Dictionary = view["path"]
	var origin_pos: Vector3 = observer["pos"]
	var reach2: float = view["reach2"]
	var dt: float = look["dt"]
	var seen_cells := []
	if not view["all"]:
		for cell in ViewMarks.cells_to_check(s, look, observer):
			var point := Vector3(cell)
			if ((point - origin_pos).length_squared() <= reach2 and in_view(s, observer, point)) or (view["moving"] and _passed(s, view["past"], path, point, dt)):
				var id: int = s.cell_ids.get(cell, -1)
				seen_cells.append([cell, "%d:cell:%d" % [observer["id"], id], id])
	elif view["moving"]:
		# 动的观察者看这一步扫过的整片地方：以起点和终点连线的中点为心，多看半条连线和弯曲的余量。
		var around: Vector3 = (path["pos"] + origin_pos) * 0.5
		var widen: float = path["pos"].distance_to(origin_pos) * 0.5 + path["acceleration"].length() * dt * dt / 8.0
		for cell in Geometry.cells_near(s.system_cells, look["index"], around, sqrt(reach2) + widen):
			var point := Vector3(cell)
			if ((point - origin_pos).length_squared() <= reach2 and in_view(s, observer, point)) or _passed(s, view["past"], path, point, dt):
				var id: int = s.cell_ids.get(cell, -1)
				seen_cells.append([cell, "%d:cell:%d" % [observer["id"], id], id])
	else:
		seen_cells = _cells_in_view(s, look["index"], observer, reach2)
	for seen in seen_cells:
		var cell: Vector3i = seen[0]
		# 同一次采样里几个观察者看同一个星系，星系的样子和签名只算一次（_emit 会复制一份发出去）。
		var seen_cell := ViewMarks.snapshot(s, look, cell)
		var data: Dictionary = seen_cell["data"]
		var contact: bool = data["owner"] >= 0 and data["owner"] != owner and Vector3i(observer["pos"].round()) == cell
		# 和 _emit 里的判断一样：没变、心跳也没到就不发。多数星系每次都是这样，省得每次拼一条消息。
		var stamp: Dictionary = s.sensor_stamps.get(seen[1], {})
		if stamp.get("hash", -1) == seen_cell[contact] and s.clock - stamp["time"] < HEARTBEAT:
			continue
		_emit(s, owner, observer, Vector3(cell), seen[1],
				{"type": "cell", "cell": cell, "cell_id": seen[2], "passive": true, "data": data, "contact": contact}, true, INF, seen_cell[contact])


## 一个观察者看单位。view["all"] 时看附近的全部，否则只看 ViewMarks 挑出来的。
static func _look_entities(s: GameState, look: Dictionary, owner: int, view: Dictionary) -> void:
	var observer: Dictionary = view["observer"]
	var path: Dictionary = view["path"]
	var moving: bool = view["moving"]
	var past: Dictionary = view["past"]
	var origin_pos: Vector3 = observer["pos"]
	var reach2: float = view["reach2"]
	var reach := sqrt(reach2)
	var dt: float = look["dt"]
	var sweep: bool = look["sweep"]
	var entities: Array = look["entities"]
	if view["all"] and not look.has("buckets"):
		look["buckets"] = _entity_buckets(entities, dt)
	var indices: Array = _nearby(look["buckets"], entities.size(), _sweep_box(path, origin_pos, dt, reach + 1e-5)) if view["all"] \
			else ViewMarks.targets_to_check(s, look, observer)
	for i in indices:
		var target: Dictionary = entities[i]
		if target["owner"] == owner:
			continue
		var trail: Dictionary = target["path"]
		var passed := false
		var key := ""
		# 两边这一步都没动，就不会有新进视野的；子步开始时已在视野里的，上一次采样已经看过（seen 为 0）。
		if sweep and (moving or (not trail.is_empty() and _moved(trail))):
			var from: Dictionary = trail if not trail.is_empty() else {"pos": target["pos"], "velocity": Vector3.ZERO, "acceleration": Vector3.ZERO}
			# 两条轨迹离得太远，这一步里不可能看到，现在也不在视野里。
			if not _may_meet(path["pos"], origin_pos, path["acceleration"], from["pos"], target["pos"], from["acceleration"], dt, reach):
				continue
			var seen := _first_seen(s, past, from["pos"] - path["pos"], from["velocity"] - path["velocity"], from["acceleration"] - path["acceleration"], dt)
			if seen <= 0.0:
				seen = INF
			if seen < dt - Balance.TIME_EPSILON and not trail.is_empty() and s.step_facts.has(target["id"]):
				# 在这一步中间进的视野：按那一刻的位置和速度补发，下面按现在再看时航位推算对得上就不重发。
				key = "%d:entity:%d" % [observer["id"], target["id"]]
				var data := _entity_data(s, target, trail, seen, s.step_start)
				var eye: Vector3 = Kinematics.position(path, seen)
				_emit(s, owner, observer, data["pos"], key, {"type":"entity","data":data,
					"contact":target["owner"]>=0 and Vector3i(eye.round())==Vector3i(data["pos"].round())}, true, s.step_start + seen)
			# 没记下运动的（不动的设施、这一刻才出现的船）不知道之前在哪，进过视野就按现在发出。
			passed = seen < INF and trail.is_empty()
		if not passed and ((target["pos"] - origin_pos).length_squared() > reach2 or not in_view(s, observer, target["pos"])):
			continue
		if key.is_empty():
			key = "%d:entity:%d" % [observer["id"], target["id"]]
		var data := {"id": target["id"], "owner": target["owner"], "kind": target["kind"],
				"pos": target["pos"], "velocity": target["velocity"], "acceleration": target["acceleration"], "hp": target["hp"]}
		if target.get("accel_until", INF) < INF:
			data["accel_until"] = target["accel_until"]
		_emit(s, owner, observer, target["pos"], key,
			{"type":"entity","data":data,"contact":target["owner"]>=0 and Vector3i(observer["pos"].round())==Vector3i(target["pos"].round())},true)


## 核对模式（s.view_check）：只看变了的之后，再把所有观察者的视野全看一遍，但不发出（s.view_dry）。
## 有内容变了却没发的（心跳不算），说明 ViewMarks 漏看了什么，报错并写出是哪一对。
static func _check_missed(s: GameState, look: Dictionary) -> void:
	s.view_dry = true
	s.view_missed.clear()
	for item in look["observers"]:
		var view: Dictionary = item[2].duplicate()
		view["all"] = true
		_look_cells(s, look, item[0], view)
		_look_entities(s, look, item[0], view)
	s.view_dry = false
	if not s.view_missed.is_empty():
		push_error("只看变了的视野漏发了观测（时刻 %.6f）：%s" % [s.clock, s.view_missed])
		s.view_missed_total += s.view_missed.size()


static func ship_status(ship: Ship) -> Dictionary:
	return {"id": ship.id, "kind": ship.kind, "pos": ship.pos, "direction": ship.direction,
			"speed": ship.speed, "target": ship.target, "has_target": ship.has_target,
			"docked": ship.docked, "dead": ship.dead, "dormant": ship.dormant,
			"lock": ship.lock, "parked": ship.parked, "warp": ship.warp, "gravity": ship.gravity,
			"damage": ship.damage, "modules": ship.modules.duplicate(), "weapons": ship.weapons.duplicate(),
			"entity_dim": ship.entity_dim, "work_locked": ship.work_locked,"weapon_policy":ship.weapon_policy,"carried_rocky":ship.carried_rocky,
			"slow_start":ship.slow_start,"pause_until":ship.pause_until}


static func reported_ships(s: GameState, civ: Civ, kinds: Array = []) -> Array[Ship]:
	var ids: Array = civ.telemetry.keys()
	var control := entity(s, s.civs.find(civ), controller(civ))
	if not control.is_empty():
		var listed := civ.telemetry.duplicate()
		for ship in civ.ships:
			if ship.pos.distance_to(control["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON and not listed.has(ship.id):
				ids.append(ship.id)
				listed[ship.id] = true
	ids.sort()
	var result: Array[Ship] = []
	for id in ids:
		# 只要某几种时，先看种类再拼，不用把每艘都拼出来。
		if not kinds.is_empty() and _reported_kind(civ, id, control, s) not in kinds:
			continue
		var ship := _reported_ship(s, civ, id, control)
		if ship != null:
			result.append(ship)
	return result


## _reported_ship 拼出来的船是哪一种（拼不出来时为空），不用真的拼。
static func _reported_kind(civ: Civ, id: int, control: Dictionary, s: GameState) -> String:
	var actual := civ.ship_by_id(id)
	if actual != null and not actual.dead and not control.is_empty() and actual.pos.distance_to(control["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON:
		return actual.kind
	if not civ.telemetry.has(id) or civ.telemetry[id]["data"]["dead"]:
		return ""
	return civ.telemetry[id]["data"]["kind"]


## 前端与命令校验使用最后收到的遥测；只在控制锚点原地时可直接读本地实体。
static func reported_ship(s: GameState, civ: Civ, id: int) -> Ship:
	return _reported_ship(s, civ, id, entity(s, s.civs.find(civ), controller(civ)))


## control 是控制锚点（entity 的结果）。一次查很多艘时由调用方先查好。
static func _reported_ship(s: GameState, civ: Civ, id: int, control: Dictionary) -> Ship:
	var actual := civ.ship_by_id(id)
	if actual != null and not actual.dead and not control.is_empty() and actual.pos.distance_to(control["pos"]) * s.physical_cell_size() <= Balance.COLLISION_EPSILON:
		return actual
	if not civ.telemetry.has(id):
		return null
	var status: Dictionary = civ.telemetry[id]["data"]
	if status["dead"]:
		return null
	var reported := Ship.make(status["kind"], status["pos"], id)
	for field in status:
		if not _SHIP_FIELDS.has(field):
			_SHIP_FIELDS[field] = field in reported
		if _SHIP_FIELDS[field]:
			if reported.get(field) is Array:
				reported.get(field).assign(status[field])
			else:
				reported.set(field, status[field])
	return reported


static func report_ship(s: GameState, civ: Civ, ship: Ship) -> void:
	var data:=ship_status(ship)
	data["assets"]=civ.assets.filter(func(a):return a["carrier"]==ship.id).duplicate(true)
	send(s, s.civs.find(civ), ship.pos, controller(civ), "report", {"type": "own", "data": data,
			"t_observed": s.clock, "source_id": ship.id, "epoch": s.space_epoch})


## 收入只认仍在线、仍在视野内且具有可传播链路的接收器；历史报告本身不产能。
static func coverage_packages(s: GameState, civ: Civ) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not civ.has_tech("antimatter_collection"):
		return result
	var owner := s.civs.find(civ)
	var control := entity(s, owner, controller(civ))
	if control.is_empty():
		return result
	# 按原星系顺序一次分桶。每个观察者仍按相同顺序处理自己的已收覆盖，
	# 不为每个观察者重新扫描全图并为未覆盖格分配空字典。
	var by_source:= {}
	for cell in s.system_cells:
		var id: int=s.cell_ids.get(cell,-1)
		if s.cell_dims.get(id,s.dimension)==0 or not civ.coverage.has(id): continue
		for source in civ.coverage[id]:
			if not by_source.has(source): by_source[source]=[]
			by_source[source].append([cell,id])
	for observer in observers(s, civ):
		var receiver := entity(s, owner, observer["id"])
		if not path_open(s, observer["pos"], control["pos"]):
			continue
		var dim: int = receiver["ship"].entity_dim if receiver.has("ship") else receiver["asset"]["entity_dim"]
		var parent: String = "ship:%d" % observer["id"] if receiver.has("ship") else Economy.package_key("anchor", receiver["asset"]["at"])
		for pair in by_source.get(observer["id"],[]):
			var cell: Vector3i=pair[0]
			var id: int=pair[1]
			if not in_view(s, observer, Vector3(cell)) or not path_open(s, Vector3(cell), observer["pos"]):
				continue
			var e: float = Balance.COVERED_ENERGY + (Balance.VACUUM_ENERGY if civ.has_tech("dark_energy") and s.map.star_at(cell) == StarMap.Star.NONE else 0)
			result.append({"key": "coverage:%d:%d" % [id,observer["id"]], "kind": "coverage", "at": cell,
					"coverage_cell": id, "nominal": [e,0.0], "q": Balance.DIMENSION_OUTPUT[str(dim)], "upkeep": [0.0,0.0], "parent": parent})
	return result


static func path_open(s: GameState, a: Vector3, b: Vector3) -> bool:
	# 没有任何修改光速的场或网格时，两端必为正光速，避免逐覆盖点重复构造场查询。
	if s.light.is_empty() and s.black_domains.is_empty() and s.deadlines.is_empty(): return true
	if s.relative_light(a) <= 0.0 or s.relative_light(b) <= 0.0:
		return false
	for source in s.black_domains:
		var closest := a
		var d := b-a
		if d.length_squared() > 1e-15:
			closest += d * clampf((source["pos"]-a).dot(d)/d.length_squared(),0.0,1.0)
		if s.relative_light(closest) <= 0.0:
			return false
	return true


## 预警范围（球形）里的敌方战舰、水滴、光粒和载荷。dt 是上一个子步的长度（0 表示只看现在）：
## 这一步中间闯进范围的，按闯进那一刻的位置和速度补发预警。targets 里的 "path" 由 sample 先填好。
static func _sample_warning(s: GameState, civ: Civ, targets: Array[Dictionary], dt := 0.0) -> void:
	for asset in civ.assets:
		if asset["kind"] != "warning":
			continue
		if (asset["carrier"] < 0 and civ.dormant_colonies.has(asset["at"])) or (asset["carrier"] >= 0 and civ.ship_by_id(asset["carrier"]).dormant):
			continue
		var observer := {"id":asset["id"],"pos":entity(s,s.civs.find(civ),asset["id"])["pos"]}
		var radius: float = Balance.WARNING_RANGE+asset.get("warning_level",civ.warnings.get(asset["at"],0))
		var view := {"radius": radius, "dir": Vector3.ZERO}
		var path := _path(s, asset["carrier"], observer["pos"]) if dt > 0.0 else {}
		var owner := s.civs.find(civ)
		for target in targets:
			if target["owner"] == owner or target["kind"] not in WARNING_KINDS:
				continue
			var trail: Dictionary = target.get("path", {})
			# 消息键要发的时候才拼：每一刀每一对都拼一次很费时间。
			var key := ""
			if dt > 0.0 and not trail.is_empty() and _may_meet(path["pos"], observer["pos"], path["acceleration"], trail["pos"], target["pos"], trail["acceleration"], dt, radius / s.physical_cell_size()):
				var seen := _first_seen(s, view, trail["pos"] - path["pos"], trail["velocity"] - path["velocity"], trail["acceleration"] - path["acceleration"], dt)
				if seen < dt - Balance.TIME_EPSILON:
					var early := _entity_data(s, target, trail, seen, s.step_start)
					early.erase("owner")
					early.erase("hp")
					if target.has("payload"):
						early["payload_kind"] = target["payload"]["kind"]
					key = "warning:%d:%d"%[asset["id"],target["id"]]
					_emit(s,owner,observer,early["pos"],key,{"type":"warning","data":early},true,s.step_start + seen)
			if observer["pos"].distance_to(target["pos"])*s.physical_cell_size()>radius:
				continue
			var data := {"id":target["id"],"kind":target["kind"],"pos":target["pos"],"velocity":target["velocity"],"acceleration":target["acceleration"]}
			if target.get("accel_until",INF)<INF:
				data["accel_until"]=target["accel_until"]
			if target.has("payload"):
				data["payload_kind"] = target["payload"]["kind"]
			if key.is_empty():
				key = "warning:%d:%d"%[asset["id"],target["id"]]
			_emit(s,owner,observer,target["pos"],key,{"type":"warning","data":data},true)


## 回报里的各项是不是 Ship 的属性（所有 Ship 都一样），记下来不用每次按名字查。
static var _SHIP_FIELDS := {}

## 预警看得到的几种单位。
const WARNING_KINDS := [Ship.WARSHIP, Ship.DROPLET, Ship.GRAIN, "payload"]
