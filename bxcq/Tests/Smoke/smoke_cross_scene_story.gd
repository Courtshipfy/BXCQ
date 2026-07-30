extends SceneTree
## Cross-scene story-state chain smoke.
## Village notice → Study manuscript → Elder unlocks church → Church altar examine.

const NarrRailSmokeDriver = preload("res://Tests/Smoke/narrrail_smoke_driver.gd")

var _frames := 0
var _phase := 0
var _advances := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("story-chain smoke: load Village failed")
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
			_advances = 0
			_frames = 40
			if not execution.call("StartStory", "res://Stories/DevPrototype/notice_board_clue.nrstory"):
				push_error("story-chain smoke: notice story failed")
				quit(1)
				return false
			print("story-chain smoke: A notice started")
		1:
			if _frames % 8 == 0 and _advances < 24 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			if bool(bridge.call("GetBool", "has_clue_manuscript", false)) and not bool(execution.get("IsRunning")):
				_phase = 2
				_frames = 0
				print("story-chain smoke: B clue var OK — go Study")
				var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Study.tscn")
				if err != OK:
					push_error("story-chain smoke: load Study failed")
					quit(1)
					return false
		2:
			if _frames < 45:
				return false
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			if presenter == null:
				push_error("story-chain smoke: Study DialoguePresenter missing")
				quit(1)
				return false
			var desk := _find("ManuscriptDesk")
			if desk == null:
				push_error("story-chain smoke: ManuscriptDesk missing")
				quit(1)
				return false
			_phase = 3
			_advances = 0
			_frames = 40
			if not execution.call("StartStory", "res://Stories/DevPrototype/study_manuscript.nrstory"):
				push_error("story-chain smoke: manuscript story failed")
				quit(1)
				return false
			print("story-chain smoke: C manuscript started")
		3:
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			bridge = root.get_node("/root/NarrRailBridge")
			if _frames % 8 == 0 and _advances < 24 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			if bool(bridge.call("GetBool", "found_manuscript", false)) and not bool(execution.get("IsRunning")):
				_phase = 4
				_frames = 0
				print("story-chain smoke: D found_manuscript OK — return Village")
				var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
				if err != OK:
					push_error("story-chain smoke: reload Village failed")
					quit(1)
					return false
		4:
			if _frames < 45:
				return false
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			bridge = root.get_node("/root/NarrRailBridge")
			player = root.get_tree().get_first_node_in_group("player")
			if not bool(bridge.call("GetBool", "found_manuscript", false)):
				push_error("story-chain smoke: found_manuscript lost across scenes")
				quit(1)
				return false
			_phase = 5
			_advances = 0
			_frames = 40
			if not execution.call("StartStory", "res://Stories/DevPrototype/village_elder_hello.nrstory"):
				push_error("story-chain smoke: elder story failed")
				quit(1)
				return false
			print("story-chain smoke: E elder found branch started")
		5:
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			if _frames % 8 == 0 and _advances < 24 and bool(execution.get("IsRunning")):
				NarrRailSmokeDriver.advance(execution)
				_advances += 1
			var line := String(execution.get("LastLineText"))
			if line.contains("教堂") or line.contains("手稿"):
				_phase = 6
				_frames = 40
				print("story-chain smoke: F elder found line OK")
		6:
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			if bool(execution.get("IsRunning")):
				if _frames % 6 == 0:
					NarrRailSmokeDriver.advance(execution)
				if _frames > 200:
					push_error("story-chain smoke: elder never ended")
					quit(1)
				return false
			player = root.get_tree().get_first_node_in_group("player")
			var church_door := _find("ToChurch")
			if church_door == null or player == null:
				push_error("story-chain smoke: ToChurch/player missing")
				quit(1)
				return false
			if not bool(church_door.get("IsAvailable")):
				push_error("story-chain smoke: To Church should be unlocked after found manuscript")
				quit(1)
				return false
			_phase = 7
			_frames = 0
			print("story-chain smoke: G church door open — enter Church")
			var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Church.tscn")
			if err != OK:
				push_error("story-chain smoke: load Church failed")
				quit(1)
				return false
		7:
			if _frames < 45:
				return false
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			var altar := _find("ChurchAltar")
			if altar == null or not bool(altar.get("IsExamineProp")):
				push_error("story-chain smoke: ChurchAltar missing/examine")
				quit(1)
				return false
			if presenter == null:
				push_error("story-chain smoke: Church DialoguePresenter missing")
				quit(1)
				return false
			if not presenter.call("ShowExamine", altar.get("AnchorGlobalPosition"), "查看", String(altar.get("ExamineText"))):
				push_error("story-chain smoke: altar examine failed")
				quit(1)
				return false
			presenter.call("DismissExamine")
			print("story-chain smoke: H church examine OK")
			print("story-chain smoke: PASS cross-scene story chain")
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
