extends RefCounted
## 只生成复核提示，不参与胜负，也不把发展阶段少判为已经不可逆。
static func assess(rounds: int, reason: String, first_dimensions: Dictionary, civs: Array, catalog: Dictionary, longest_quiet: int) -> Dictionary:
	var terminal := reason != ""
	var target := "not_observed_to_400"
	if terminal: target="met" if rounds<=400 else "missed_late_natural_terminal"
	elif rounds>=400: target="missed_right_censored"
	var flags: Array = []
	var coverage: Array = []
	for c in civs:
		var researched := {"0":0,"1":0,"2":0,"3":0}
		for id in c.techs:
			if catalog.has(id): researched[str(int(catalog[id].tier))]+=1
		var opened_second: bool = c.permissions.has(2) or c.permissions.has("2")
		coverage.append({"civ":c.id,"alive":c.alive,"researched_by_tier":researched,"permissions":c.permissions})
		if not c.alive and not opened_second:
			flags.append({"code":"eliminated_before_tier_II_opened","civ":c.id})
	if terminal and not first_dimensions.has("2"):
		flags.append({"code":"terminal_before_2D_entered"})
	if longest_quiet>=10:
		flags.append({"code":"ten_round_low_interaction_window","length":longest_quiet})
	return {"normal_400_round_target":target,"stage_coverage":coverage,"review_flags":flags,
		"flags_are_screening_only":true,"premature_irreversibility_verified":false,
		"countermeasure_window_verdict":"not_evaluated","permanent_stalemate_verified":false,
		"extension_policy":"800/1600 only diagnose unfinished anomalies; no score-based winner"}
