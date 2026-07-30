extends SceneTree
## Focused Path Network route and Junction test without a Location scene.

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var probe_script := load("res://Tests/Smoke/PathNetworkModuleProbe.cs")
	if probe_script == null:
		_fail("C# probe failed to load")
		return
	var probe := probe_script.new() as Node
	if probe == null:
		_fail("C# probe failed to instantiate")
		return
	root.add_child(probe)
	if not bool(probe.call("Run")):
		_fail(String(probe.get("FailureMessage")))
		return
	print("path network module smoke: PASS route + Junction without Location")
	quit(0)

func _fail(message: String) -> void:
	push_error("path network module smoke: " + message)
	quit(1)
