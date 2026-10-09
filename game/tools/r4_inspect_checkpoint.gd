extends SceneTree
func _initialize() -> void:
	var summary_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("SUMMARY="): summary_path=arg.trim_prefix("SUMMARY=")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(summary_path))
	var checkpoint: Dictionary = report.checkpoints[str(report.rounds)]
	var file := FileAccess.open(checkpoint.path,FileAccess.READ)
	var data: Dictionary = bytes_to_var(file.get_buffer(file.get_length()).decompress(checkpoint.uncompressed_bytes,FileAccess.COMPRESSION_ZSTD))
	var s=load("res://rules/r4/state.gd").from_snapshot(data)
	var counts := {}
	for msg in s.messages:
		var e: Dictionary = s.entities.get(msg.target_id,{})
		var key := "%s/%s/%s"%[msg.kind,e.get("kind","absent"),str(e.get("moving",false))]
		counts[key]=counts.get(key,0)+1
	var civs: Array = []
	for c in s.civs:
		var inactive: Array = []
		var owners=load("res://rules/r4/simulation.gd").batchable_information_owners(s)
		for e in s.owned_entities(c.id):
			if not e.online: inactive.append(e.kind)
		civs.append({"id":c.id,"inactive":inactive,"stock":str(c.ledger.stock),"batchable":owners.has(c.id)})
	print(JSON.stringify({"round":s.round_index,"dynamic":s.messages.size(),"scheduled":s.scheduled_messages.size(),"dynamic_counts":counts,"civs":civs}))
	quit()
