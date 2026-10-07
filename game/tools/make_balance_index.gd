extends SceneTree
## 按现在的 balance.gd 重新生成 rules/balance_index.gd（数值目录，见 BalancePresets.index_source）：
##   godot_console --headless --path game --script res://tools/make_balance_index.gd


func _init() -> void:
	var err := BalancePresets.write_index()
	if err == OK:
		print("已更新 %s" % BalancePresets.INDEX_PATH)
	else:
		push_error("没能更新 %s：%s" % [BalancePresets.INDEX_PATH, error_string(err)])
	quit(0 if err == OK else 1)
