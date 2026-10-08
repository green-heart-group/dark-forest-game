class_name StateCopy
extends RefCounted
## 把一局的规则状态打包成压缩的字节，或者从字节恢复成一局新的（调试面板往回跳时的局面缓存用）。
## 恢复出来的文明、舰船、箔、星图都是新对象，和原来的不共用任何能改的东西；
## 同一个对象被好几处引用时（比如广播里的 "sender"、zero_winner 指向的文明），恢复后也指向同一个新对象。
## 按脚本里声明的变量逐个打包，以后给这些类加变量不用改这里；
## 只有新变量里要放文明、舰船这样的对象时，才要把它加进 LINKS（测试会检查有没有漏）。
## 150 回合的局面打包后一百多 KB，打包、恢复各要几十毫秒（2026-10-08 在开发机上测）。

## 每个类里可能放着对象的变量。其余变量只有数字、坐标、字符串和装着它们的数组、字典，直接交给 var_to_bytes。
const LINKS := {"GameState": ["map", "rng", "civs", "hidden_ships", "hidden_foils", "broadcasts", "zero_winner"],
		"Civ": ["ships", "foils"]}


static func pack(s: GameState) -> PackedByteArray:
	var raw := var_to_bytes(_encode(s, {}))
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u64(0, raw.size())  # 解压要知道原来多大
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func unpack(bytes: PackedByteArray) -> GameState:
	var raw := bytes.slice(8).decompress(bytes.decode_u64(0), FileAccess.COMPRESSION_ZSTD)
	return _decode(bytes_to_var(raw), [])


## 整份复制。
static func copy(s: GameState) -> GameState:
	return unpack(pack(s))


## 对象换成 {"#obj": 类名, "#id": 第几个, "p": 变量}，再次遇到同一个对象时换成 {"#ref": 第几个}。
static func _encode(v: Variant, ids: Dictionary) -> Variant:
	if v is Object:
		var o: Object = v
		if o == null:
			return null
		if o is RandomNumberGenerator:
			return {"#rng": [o.seed, o.state]}
		if ids.has(o):
			return {"#ref": ids[o]}
		var id := ids.size()
		ids[o] = id
		var kind: String = o.get_script().get_global_name()
		var links: Array = LINKS.get(kind, [])
		var props := {}
		for p in o.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var value = o.get(p["name"])
				props[p["name"]] = _encode(value, ids) if links.has(p["name"]) else value
		return {"#obj": kind, "#id": id, "p": props}
	if v is Array:
		return (v as Array).map(func(x): return _encode(x, ids))
	if v is Dictionary:
		var d := {}
		for k in v:
			var key = _encode(k, ids)  # 键也可能是文明（广播的 "heard"），先键后值，恢复时同样的顺序
			d[key] = _encode(v[k], ids)
		return d
	return v


static func _decode(v: Variant, made: Array) -> Variant:
	if v is Array:
		return (v as Array).map(func(x): return _decode(x, made))
	if not v is Dictionary:
		return v
	if v.has("#rng"):
		var rng := RandomNumberGenerator.new()
		rng.seed = v["#rng"][0]  # 设种子会重置状态，所以先设种子再设状态
		rng.state = v["#rng"][1]
		return rng
	if v.has("#ref"):
		return made[v["#ref"]]
	if v.has("#obj"):
		var o := _new(v["#obj"])
		made.append(o)
		assert(made.size() == v["#id"] + 1)
		var links: Array = LINKS.get(v["#obj"], [])
		var props: Dictionary = v["p"]
		for name in props:
			_put(o, name, _decode(props[name], made) if links.has(name) else props[name])
		return o
	var d := {}
	for k in v:
		var key = _decode(k, made)
		d[key] = _decode(v[k], made)
	return d


static func _new(kind: String) -> Object:
	match kind:
		"GameState":
			return GameState.new()
		"Civ":
			return Civ.new("", false, Vector3i.ZERO)
		"Ship":
			return Ship.new()
		"Foil":
			return Foil.new(Vector3.ZERO, Vector3i.ZERO, 0)
		"StarMap":
			return StarMap.new()
	assert(false, "StateCopy 不认识 %s" % kind)
	return null


## 类型化的数组、字典（Array[Civ] 等）原地换内容，保留类型。
static func _put(o: Object, name: String, value: Variant) -> void:
	var now = o.get(name)
	if (now is Array or now is Dictionary) and now.is_typed():
		now.assign(value)
	else:
		o.set(name, value)
