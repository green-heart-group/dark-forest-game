extends SceneTree
func _initialize() -> void:
	var State = load("res://rules/r4/state.gd")
	var s=State.new(0,"C",5)
	for turn in 20:
		s.end_round()
		for c in s.civs: assert(c.ledger.invariant_errors().is_empty())
		if turn%5==0: print("round=",s.round_index," t=",s.now," entities=",s.entities.size()," messages=",s.messages.size())
	print(JSON.stringify({"suite":"r4_smoke","round":s.round_index,"state_hash":s.state_hash(),"terminal":s.terminal_reason,"errors":0}))
	quit()
