class_name EventQueue
extends RefCounted
## 连续结算的事件表（见 docs/proposals/event-queue.md）：WorldTime.advance 每一刀把「再过多久会发生什么」放进来，
## 取最早的一件，把世界推到那一刻。每一件都带原因，打开 profiling 时按原因数刀数。
## 现在每一刀都把所有预测重新放一遍，所以只记最早的一件；以后不变的预测留在表里，只重算变了的。

## 最早的一件还要多少年，和它的原因。
var due := INF
var why := ""


func _init(limit: float, reason: String) -> void:
	due = limit
	why = reason


## 放进一件：再过 after 年，因为 reason 要停下来处理。
func offer(after: float, reason: String) -> void:
	if after < due:
		due = after
		why = reason
