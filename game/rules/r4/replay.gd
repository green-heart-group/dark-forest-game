class_name R4Replay
extends RefCounted
## 独立版本的r4存档；旧24项规则记录不被静默重算。读档必须核配置和完整状态哈希。

static func save(path: String, s) -> Error:
	var file := FileAccess.open_compressed(path,FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
	if file==null: return FileAccess.get_open_error()
	var payload := {"format":"dark_forest_r4_save","version":1,"state":s.snapshot(),"history":s.history,"hash":s.state_hash()}
	file.store_buffer(var_to_bytes(payload))
	return OK

static func read(path: String) -> Dictionary:
	var file := FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
	if file==null: return {"error":"无法读取存档"}
	var bytes := file.get_buffer(file.get_length())
	var data: Variant = bytes_to_var(bytes)
	if not data is Dictionary or data.get("format","")!="dark_forest_r4_save" or data.get("version",0)!=1: return {"error":"存档格式不属于r4；旧规则存档保持独立"}
	var s=load("res://rules/r4/state.gd").from_snapshot(data.state)
	if s==null: return {"error":"配置或存档版本与本次规则不一致"}
	if s.state_hash()!=data.hash: return {"error":"存档状态哈希不符"}
	s.history.assign(data.history)
	return {"error":"","state":s}

static func from_commands(data: Dictionary) -> Dictionary:
	if data.get("rules","")!="r4": return {"error":"不支持的记录规则"}
	var s=load("res://rules/r4/state.gd").new(data.seed,data.profile,data.get("civilizations",5))
	if s.config.digest()!=data.config: return {"error":"重放配置不一致"}
	for c in s.civs: c.strategy=data.get("strategy","balanced")
	s.initialize_sensors()
	var pointer := 0
	for turn in data.rounds:
		while pointer<data.history.size() and data.history[pointer].round==turn:
			var action: Dictionary = data.history[pointer]
			var result: Dictionary = s.submit(action.civ,action.request)
			if result.error!="": return {"error":"第%d步重放拒绝：%s"%[pointer,result.error]}
			pointer+=1
		s.end_round(false)
		s.events.clear()
	if pointer!=data.history.size(): return {"error":"记录超出回合范围"}
	if s.state_hash()!=data.final_hash: return {"error":"重放终态哈希不符","actual_hash":s.state_hash()}
	return {"error":"","state":s,"hash":s.state_hash()}
