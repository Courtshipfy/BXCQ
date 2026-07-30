extends SceneTree
## Smoke for Examine and NarrRail-driven Investigate behavior.

const NarrRailSmokeDriver = preload("res://Tests/Smoke/narrrail_smoke_driver.gd")

var _frames := 0
var _phase := 0
var _advances := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("examine smoke: failed to load Village (%s)" % err)
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false

	var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
	var execution := root.get_node("/root/NarrRailExecution")
	match _phase:
		0:
			_phase = 1
			if presenter == null:
				push_error("examine smoke: presenter missing")
				quit(1)
				return false
			# Find well and call ShowExamine via presenter (skip path walk)
			var well: Node2D = null
			for node in root.get_tree().get_nodes_in_group("interactables"):
				if String(node.name) == "VillageWell":
					well = node
					break
			if well == null:
				push_error("examine smoke: VillageWell missing")
				quit(1)
				return false
			var anchor: Vector2 = well.get("AnchorGlobalPosition")
			var text := String(well.get("ExamineText"))
			if text.is_empty():
				push_error("examine smoke: ExamineText empty")
				quit(1)
				return false
			if not presenter.call("ShowExamine", anchor, "Village Well", text):
				push_error("examine smoke: ShowExamine failed")
				quit(1)
				return false
			print("examine smoke: examine opened")
		1:
			var gs := root.get_node("/root/GameState")
			if not bool(gs.get("IsDialogueBlocking")):
				push_error("examine smoke: examine should block")
				quit(1)
				return false
			if not bool(presenter.get("IsExamining")):
				push_error("examine smoke: IsExamining false")
				quit(1)
				return false
			# Dialogue should refuse while examining
			if execution.call("StartStory", "res://Stories/DevPrototype/village_elder_hello.nrstory"):
				push_error("examine smoke: StartStory should refuse during examine")
				quit(1)
				return false
			presenter.call("DismissExamine")
			_phase = 2
			_advances = 0
			_frames = 40
			print("examine smoke: examine dismissed, start notice board")
			if not execution.call("StartStory", "res://Stories/DevPrototype/notice_board_clue.nrstory"):
				push_error("examine smoke: notice board story failed")
				quit(1)
				return false
		2:
			if _frames % 10 == 0 and _advances < 20 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			var bridge := root.get_node("/root/NarrRailBridge")
			if bool(bridge.call("GetBool", "has_clue_manuscript", false)) and not bool(execution.get("IsRunning")):
				print("examine smoke: PASS")
				quit(0)
			if _frames > 300:
				push_error("examine smoke: investigate clue not set in time")
				quit(1)
	return false
