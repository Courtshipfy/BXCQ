extends SceneTree
## NarrRail Execution runs a story without a Location or Dialogue Presenter.

const NarrRailSmokeDriver = preload("res://Tests/Smoke/narrrail_smoke_driver.gd")

var _frames := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	root.get_node("/root/NarrRailBridge").call("ClearStoryVariables")
	var execution := root.get_node_or_null("/root/NarrRailExecution")
	if execution == null:
		_fail("NarrRailExecution missing")
		return
	if root.get_tree().get_first_node_in_group("dialogue_presenter") != null:
		_fail("test must run without DialoguePresenter")
		return
	if not execution.call("StartStory", "res://Stories/DevPrototype/notice_board_clue.nrstory"):
		_fail("StartStory failed without UI")

func _process(_delta: float) -> bool:
	_frames += 1
	var execution := root.get_node("/root/NarrRailExecution")
	if _frames % 3 == 0:
		NarrRailSmokeDriver.advance(execution)
	var bridge := root.get_node("/root/NarrRailBridge")
	if bool(bridge.call("GetBool", "has_clue_manuscript", false)) and not bool(execution.get("IsRunning")):
		print("narrrail execution smoke: PASS without UI")
		quit(0)
	if _frames > 120:
		_fail("story did not finish without UI")
	return false

func _fail(message: String) -> void:
	push_error("narrrail execution smoke: " + message)
	quit(1)
