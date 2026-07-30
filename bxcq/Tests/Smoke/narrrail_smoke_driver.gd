extends RefCounted

static func advance(execution: Node) -> void:
	if execution == null or not bool(execution.get("IsRunning")) or bool(execution.get("IsPaused")):
		return
	if bool(execution.get("IsWaitingForChoice")):
		execution.call("Choose", 0)
	else:
		execution.call("Advance")
