extends SceneTree
const Diagnostics := preload("res://tools/r4_diagnostics.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func _initialize() -> void:
	var d := Diagnostics.assess(200,"",{"3":0},[],{},0)
	check(d.normal_400_round_target=="not_observed_to_400","200 unfinished is censored, not a loss or 400-round failure")
	d=Diagnostics.assess(400,"",{"3":0},[],{},0)
	check(d.normal_400_round_target=="missed_right_censored","400 unfinished misses target without inventing a winner")
	d=Diagnostics.assess(401,"last_surviving_civilization",{"3":0,"2":80},[],{},0)
	check(d.normal_400_round_target=="missed_late_natural_terminal","late natural terminal cannot satisfy 400-round target")
	d=Diagnostics.assess(400,"last_surviving_civilization",{"3":0,"2":80},[],{},0)
	check(d.normal_400_round_target=="met","natural end exactly at400 counts")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://rules/r4/catalog.json"))
	d=Diagnostics.assess(40,"last_surviving_civilization",{"3":0},[{"id":1,"alive":false,"techs":["001"],"permissions":{0:true,1:20}}],catalog,12)
	check(d.stage_coverage[0].researched_by_tier["0"]==1,"real JSON catalog numeric tiers normalize correctly")
	check(d.review_flags.size()==3,"stage bypass, elimination and inactivity are distinct review flags")
	check(not d.premature_irreversibility_verified and not d.permanent_stalemate_verified,"screening does not certify irreversibility or permanent stalemate")
	check(d.countermeasure_window_verdict=="not_evaluated","missing countermeasure analysis stays explicit")
	print(JSON.stringify({"suite":"r4_reporting_diagnostics","checks":checks,"failure_count":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
