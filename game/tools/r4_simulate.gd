extends SceneTree
## r4固定种子模拟。流式轻量事件/指标，完整状态仅检查点；默认不运行真人席位。
const State := preload("res://rules/r4/state.gd")
const Diagnostics := preload("res://tools/r4_diagnostics.gd")
var output := ""
var record := true
var profile := "C"
var strategy := "balanced"
var order: Array = []
var performance := false

func _initialize() -> void:
	var first := 0
	var runs := 1
	var limit := 400
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=",true,1)
		if pair.size()!=2: continue
		match pair[0]:
			"PROFILE": profile=pair[1]
			"FIRST": first=int(pair[1])
			"RUNS": runs=int(pair[1])
			"TURNS": limit=int(pair[1])
			"OUT": output=pair[1]
			"RECORD": record=pair[1]!="0"
			"STRATEGY": strategy=pair[1]
			"PERF": performance=pair[1]=="1"
			"ORDER":
				for value in pair[1].split(","): order.append(int(value))
	assert(output!="","OUT is required")
	DirAccess.make_dir_recursive_absolute(output)
	for seed_id in range(first,first+runs): run_game(seed_id,limit)
	quit()

func run_game(seed_id: int, limit: int) -> void:
	var stem := output.path_join("%s_seed_%02d"%[profile,seed_id])
	assert(not FileAccess.file_exists(stem+"_summary.json"),"do not overwrite an earlier experiment")
	var event_file: FileAccess
	var row_file: FileAccess
	if record:
		event_file=FileAccess.open(stem+"_events.jsonl",FileAccess.WRITE)
		row_file=FileAccess.open(stem+"_turns.jsonl",FileAccess.WRITE)
	var s=State.new(seed_id,profile,5)
	s.capture_events=record
	for c in s.civs: c.strategy=strategy
	var tick := Time.get_ticks_usec()
	var checkpoints := {}
	var quiet := 0
	var longest_quiet := 0
	var first_sustained := -1
	var first_dim := {"3":0}
	s.initialize_sensors()
	for turn in limit:
		var history_before: int = s.history.size()
		var known_before := 0
		for c in s.civs: known_before+=c.known_cells.size()
		s.end_round(true,order)
		if performance and turn%10==9: print("PERF round=",s.round_index," ",JSON.stringify(s.last_performance)," messages=",s.message_count())
		var meaningful_actions := 0
		for i in range(history_before,s.history.size()):
			if s.history[i].request.kind!="emergency": meaningful_actions+=1
		var known_after := 0
		for c in s.civs: known_after+=c.known_cells.size()
		var interaction: bool = s.events.any(func(e):return e.kind in ["weapon_hit","cell_converted","entity_destroyed","system_suppressed","photoid_hit"])
		if meaningful_actions==0 and known_after==known_before and not interaction: quiet+=1
		else: quiet=0
		longest_quiet=maxi(longest_quiet,quiet)
		# 十回合仅为报告用的预设持续窗口，绝不把它判作永久僵局或胜负。
		if quiet==10 and first_sustained<0: first_sustained=s.round_index-9
		if not first_dim.has(str(s.space.world_dim)): first_dim[str(s.space.world_dim)]=s.round_index
		for ci in s.civs.size():
			var c: Dictionary = s.civs[ci]
			assert(c.ledger.invariant_errors().is_empty(),"negative or corrupt ledger")
			if not record: continue
			var choices := available_choices(s,ci)
			var row := {"seed":seed_id,"profile":profile,"round":s.round_index,"t":s.now,"world_dim":s.space.world_dim,"epoch":s.space.world_epoch,
				"civ":ci,"alive":c.alive,"anchors":s.anchors(ci).size(),"entities":s.owned_entities(ci).size(),
				"stock_M":c.ledger.stock.x/1000.0,"stock_E":c.ledger.stock.y/1000.0,"net_M":c.net.x,"net_E":c.net.y,
				"reference_M":c.reference_net.x,"reference_E":c.reference_net.y,"gross_M":c.gross.x,"gross_E":c.gross.y,
				"tech_count":c.techs.size(),"tier":c.permissions.keys().max(),"known_cells":c.known_cells.size(),
				"projects":c.ledger.projects.size(),"legal_major_choices":choices,"game_meaningful_actions":meaningful_actions,
				"game_newly_known_cells":known_after-known_before,"game_quiet_rounds":quiet,"alerts":c.alerts.size()}
			row_file.store_line(JSON.stringify(row,"",true,true))
		for event in s.events:
			event_file.store_line(JSON.stringify(json_value(event),"",true,true))
		s.events.clear()
		if s.round_index in [200,400,800,1600] or s.terminal_reason!="": checkpoints[str(s.round_index)]=checkpoint(s,stem)
		if turn%50==49: print(profile," seed=",seed_id," round=",s.round_index," entities=",s.entities.size()," messages=",s.messages.size())
		if s.terminal_reason!="": break
	if not checkpoints.has(str(s.round_index)): checkpoints[str(s.round_index)]=checkpoint(s,stem)
	var final_hash: String = checkpoints[str(s.round_index)].canonical_hash
	var civs: Array = []
	for c in s.civs:
		civs.append({"id":c.id,"alive":c.alive,"techs":c.techs.keys(),"permissions":c.permissions,"first":c.first,
			"stock_M":c.ledger.stock.x/1000.0,"stock_E":c.ledger.stock.y/1000.0,"anchors":s.anchors(c.id).size()})
	var summary := {"seed":seed_id,"profile":profile,"strategy":strategy,"horizon":limit,"rounds":s.round_index,"t":s.now,
		"censored":s.terminal_reason=="","terminal_reason":s.terminal_reason,"winners":s.winners,"world_dim":s.space.world_dim,
		"first_dimensions":first_dim,"elapsed_seconds":(Time.get_ticks_usec()-tick)/1000000.0,"config_hash":s.config.digest(),
		"state_hash":final_hash,"hash_format":"sha256-canonical-variant-v1","recording":record,"checkpoints":checkpoints,"civs":civs,
		"longest_low_interaction_window":longest_quiet,"first_10_round_low_interaction_window":first_sustained,
		"permanent_stalemate_verified":false,"human_play":false,"user_data_dir":OS.get_user_data_dir()}
	summary["diagnostics"]=Diagnostics.assess(s.round_index,s.terminal_reason,first_dim,civs,s.config.catalog,longest_quiet)
	write_json(stem+"_summary.json",summary)
	var replay := FileAccess.open(stem+".commands",FileAccess.WRITE)
	replay.store_buffer(var_to_bytes({"rules":"r4","seed":seed_id,"profile":profile,"config":s.config.digest(),"strategy":strategy,"history":s.history,"rounds":s.round_index,"civilizations":s.civs.size(),"final_hash":final_hash}))
	print(JSON.stringify(summary,"",true,true))

func available_choices(s, ci: int) -> int:
	var c: Dictionary = s.civs[ci]
	if not c.alive: return 0
	var count := 0
	for info in c.seen.values():
		if not info.alive or info.owner!=ci or info.kind not in R4Config.ANCHORS: continue
		for id in s.config.catalog:
			if s.action_error(ci,{"kind":"research","host":info.id,"item":id})=="": count+=1
		for id in R4Config.BUILD_TECH:
			if s.action_error(ci,{"kind":"build","host":info.id,"item":id})=="": count+=1
	return count

func checkpoint(s, stem: String) -> Dictionary:
	var path := stem+"_%04d.state"%s.round_index
	var bytes: PackedByteArray = var_to_bytes(s.snapshot())
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return {"path":path,"round":s.round_index,"full_state_sha256":hashing.finish().hex_encode(),"canonical_hash":s.state_hash(),"compression":"zstd","uncompressed_bytes":bytes.size()}

func write_json(path: String, value: Dictionary) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(json_value(value),"\t",true,true))

static func json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)]=json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element in value: result.append(json_value(element))
		return result
	if value is Vector2 or value is Vector2i: return [value.x,value.y]
	if value is Vector3 or value is Vector3i: return [value.x,value.y,value.z]
	if value is float and not is_finite(value): return null
	return value
