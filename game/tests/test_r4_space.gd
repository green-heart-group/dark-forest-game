extends SceneTree
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	if not ResourceLoader.exists("res://rules/r4/space.gd"):
		check(false, "r4 space not implemented")
		finish()
		return
	var S = load("res://rules/r4/space.gd")
	var C = load("res://rules/r4/config.gd")
	var space = S.new(C.new("C"), 5)
	for dim in [3,2,1]:
		var found := {}
		for id in 729:
			var p = space.position_for(id, dim)
			check(not found.has(p), "A01 bijection dimension=%d id=%d" % [dim,id])
			found[p] = true
		check(found.size() == 729, "729 permanent cell identities")
	check(space.config.c(3) > space.config.c(2) and space.config.c(2) > space.config.c(1), "A02 slower light for same physical distance")
	var domain := {"id":1,"pos":Vector3.ZERO,"born":0.0,"expires":20.0,"dim":3}
	space.domains.append(domain)
	check(space.local_factor(Vector3.ZERO, 1.0) == 0.0, "A10 black domain core zero")
	check(space.local_factor(Vector3.ZERO, 21.0) == 1.0, "A10 source expires by world clock")
	space.wakes.append({"id":2,"a":Vector3.ZERO,"b":Vector3.RIGHT,"expires":20.0})
	check(is_equal_approx(space.local_factor(Vector3(0.5,0,0),21.0),1.0), "A10 wake lifetime not renewed")
	check(is_equal_approx(space.front_speed(),0.5), "A06 black domain cannot stop front")
	space.world_dim=2
	check(is_equal_approx(space.front_speed(),0.3), "A06 two dimensional .3 ly per round")
	space.world_dim=1
	check(is_equal_approx(space.front_speed(),0.18), "A06 terminal zone .18 ly per round")
	var collision = space.sweep_contact(Vector3(-1,0,0),Vector3(1,0,0),Vector3.ZERO,Vector3.ZERO,0.01)
	check(collision > 0.49 and collision < 0.51, "A11 swept crossing cannot tunnel")
	check(space.sweep_contact(Vector3(-1,1,0),Vector3(1,1,0),Vector3.ZERO,Vector3.ZERO,0.01) < 0.0, "near path outside radius misses")
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"r4_space","checks":checks,"failures":failures,"failure_count":failures.size(),"user_data_dir":OS.get_user_data_dir()}))
	quit(0 if failures.is_empty() else 1)
