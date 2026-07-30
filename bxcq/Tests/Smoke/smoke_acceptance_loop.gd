extends SceneTree
## End-to-end smoke for the retained interaction acceptance loop.

const NarrRailSmokeDriver = preload("res://Tests/Smoke/narrrail_smoke_driver.gd")

var _frames := 0
var _phase := 0
var _advances := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("acceptance smoke: load Village failed")
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:
		return false

	var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
	var execution := root.get_node("/root/NarrRailExecution")
	var bridge := root.get_node("/root/NarrRailBridge")
	var player := root.get_tree().get_first_node_in_group("player")

	match _phase:
		0:
			_phase = 1
			var well := _find("VillageWell")
			if well == null or not bool(well.get("IsExamineProp")):
				push_error("acceptance smoke: well missing/examine")
				quit(1)
				return false
			if not presenter.call("ShowExamine", well.get("AnchorGlobalPosition"), "查看", String(well.get("ExamineText"))):
				push_error("acceptance smoke: examine failed")
				quit(1)
				return false
			print("acceptance smoke: A examine OK")
			presenter.call("DismissExamine")
		1:
			_phase = 2
			_advances = 0
			_frames = 40
			if not execution.call("StartStory", "res://Stories/DevPrototype/notice_board_clue.nrstory"):
				push_error("acceptance smoke: notice story failed")
				quit(1)
				return false
			print("acceptance smoke: B investigate started")
		2:
			if _frames % 8 == 0 and _advances < 24 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			if bool(bridge.call("GetBool", "has_clue_manuscript", false)) and not bool(execution.get("IsRunning")):
				_phase = 3
				_advances = 0
				_frames = 40
				print("acceptance smoke: C clue var OK")
				if not execution.call("StartStory", "res://Stories/DevPrototype/village_elder_hello.nrstory"):
					push_error("acceptance smoke: elder story failed")
					quit(1)
					return false
		3:
			if _frames % 8 == 0 and _advances < 16 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			var line := String(execution.get("LastLineText"))
			if line.contains("告示") or line.contains("手稿"):
				_phase = 4
				_frames = 40
				# Finish remaining lines quickly
				print("acceptance smoke: D elder clue branch OK")
		4:
			if bool(execution.get("IsRunning")):
				if _frames % 6 == 0:
					NarrRailSmokeDriver.advance(execution)
				if _frames > 200:
					push_error("acceptance smoke: elder never ended")
					quit(1)
				return false
			var study := _find("ToStudy")
			if study == null or player == null:
				push_error("acceptance smoke: study/player missing")
				quit(1)
				return false
			if not bool(study.get("IsAvailable")):
				push_error("acceptance smoke: To Study should allow interact with clue")
				quit(1)
				return false
			print("acceptance smoke: E study door open OK")
			print("acceptance smoke: PASS acceptance loop")
			quit(0)
	return false

func _find(node_name: String) -> Node:
	for node in root.get_tree().get_nodes_in_group("interactables"):
		if String(node.name) == node_name:
			return node
	for node in root.get_tree().get_nodes_in_group("scene_hotspots"):
		if String(node.name) == node_name:
			return node
	return null
