extends SceneTree
## r4 账本验收。固定点库存、已付施工资格、降维收据及战利品必须守恒。
const SUBJECT := "res://rules/r4/ledger.gd"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	if not ResourceLoader.exists(SUBJECT):
		check(false, "r4 ledger not implemented")
		finish()
		return
	var Ledger = load(SUBJECT)
	var l = Ledger.new()
	l.stock = Vector2i(10000, 5000)
	check(l.fund_project(1, Vector2i(8000, 4000), 4.0, 11), "full upfront reservation")
	check(l.stock == Vector2i(2000, 1000), "paid project is not spendable stock")
	check(not l.fund_project(2, Vector2i(3000, 0), 2.0, 11), "no future income credit")
	l.advance(1, 1.0)
	check(l.projects[1].consumed == Vector2i(2000, 1000), "one quarter consumed")
	check(l.apply_receipt("civ0:3to2", 0.75, [1]), "first receipt applied")
	check(not l.apply_receipt("civ0:3to2", 0.4, [1]), "duplicate cannot change retention")
	check(l.stock == Vector2i(1500, 750), "stock loses exactly one quarter")
	check(is_equal_approx(l.projects[1].done, 1.0), "migration retains paid work")
	check(l.projects[1].consumed == Vector2i(1500, 750), "consumed basis depreciates")
	check(l.cancel(1) == Vector2i(4500, 2250), "cancel refunds only retained unconsumed part")
	check(l.stock == Vector2i(6000, 3000), "cancel cannot mint paid consumed stock")
	check(l.fund_project(3, Vector2i(4000, 2000), 2.0, 11), "host project funded")
	l.destroy_host(11)
	check(not l.projects.has(3), "host destruction aborts project")
	check(l.stock == Vector2i(2000, 1000), "host destruction never refunds escrow")
	check(l.reserve_shot("shot1", Vector2i(1000, 1000)), "reserve from current cash")
	check(not l.reserve_shot("shot2", Vector2i(0, 1)), "reservations cannot overdraw")
	check(l.fire_shot("shot1") == Vector2i(1000, 1000), "consume reserved ammunition")
	check(l.fire_shot("shot1") == Vector2i.ZERO, "shot cannot be paid twice")
	check(l.stock == Vector2i(1000, 0), "ammunition is spent")
	check(l.salvage(42, Vector2i(2500, 1250), true) == Vector2i(2500, 1250), "enemy actual hull/module basis salvaged")
	check(l.salvage(42, Vector2i(2500, 1250), true) == Vector2i.ZERO, "target salvaged once")
	check(l.salvage(43, Vector2i(5000, 5000), false) == Vector2i.ZERO, "unqualified hull never salvaged")
	l.stock = Vector2i.ZERO
	var online = l.settle_packages([
		{"id": 1, "gross": Vector2i(720, 360), "upkeep": Vector2i.ZERO, "priority": 0},
		{"id": 2, "gross": Vector2i(0, 360), "upkeep": Vector2i(2000, 1000), "priority": 10}
	])
	check(online == [1], "unaffordable package shut down atomically")
	check(l.stock == Vector2i(720, 360), "offline package provides no output or debt")
	check(l.invariant_errors().is_empty(), "ledger invariants")
	finish()

func finish() -> void:
	var result := {"suite": "r4_ledger", "checks": checks, "failures": failures, "failure_count": failures.size(), "user_data_dir": OS.get_user_data_dir()}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("report="):
			var f := FileAccess.open(arg.trim_prefix("report="), FileAccess.WRITE)
			if f: f.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
