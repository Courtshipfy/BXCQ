extends SceneTree
## Smoke for distinct Person and Examine interaction channels.

var _frames := 0
var _phase := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("roles smoke: failed to load Village")
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:
		return false

	var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
	match _phase:
		0:
			_phase = 1
			var elder: Node = null
			var well: Node = null
			var traveler: Node = null
			for node in root.get_tree().get_nodes_in_group("interactables"):
				match String(node.name):
					"VillageElder":
						elder = node
					"VillageWell":
						well = node
					"Traveler":
						traveler = node
			if elder == null or well == null or traveler == null:
				push_error("roles smoke: missing Elder/Well/Traveler")
				quit(1)
				return false
			if not bool(elder.get("IsPerson")):
				push_error("roles smoke: Elder should be IsPerson")
				quit(1)
				return false
			if not bool(well.get("IsExamineProp")):
				push_error("roles smoke: Well should be IsExamineProp")
				quit(1)
				return false
			if not bool(traveler.get("IsPerson")):
				push_error("roles smoke: Traveler should be IsPerson")
				quit(1)
				return false
			print("roles smoke: roles OK person/examine")
			# Examine channel
			var anchor: Vector2 = well.get("AnchorGlobalPosition")
			if not presenter.call("ShowExamine", anchor, "查看", String(well.get("ExamineText"))):
				push_error("roles smoke: ShowExamine failed")
				quit(1)
				return false
			if String(presenter.get("LastLineText")).is_empty():
				push_error("roles smoke: examine body empty")
				quit(1)
				return false
			if bool(presenter.call("StartSampleStory")):
				push_error("roles smoke: dialogue must refuse during examine")
				quit(1)
				return false
			presenter.call("DismissExamine")
			_phase = 2
			_frames = 40
		2:
			# Person channel
			if not presenter.call("StartStory", "res://Stories/DevPrototype/village_traveler_hello.nrstory"):
				push_error("roles smoke: traveler story failed")
				quit(1)
				return false
			_phase = 3
			_frames = 40
		3:
			if bool(presenter.get("IsRunning")) and String(presenter.get("LastLineText")).contains("赶路"):
				# Examine must refuse during dialogue
				var well2: Node = null
				for node in root.get_tree().get_nodes_in_group("interactables"):
					if String(node.name) == "VillageWell":
						well2 = node
						break
				var opened = presenter.call("ShowExamine", well2.get("AnchorGlobalPosition"), "查看", "x")
				if opened:
					push_error("roles smoke: examine must refuse during dialogue")
					quit(1)
					return false
				print("roles smoke: PASS person≠examine channels")
				quit(0)
			if _frames > 120:
				push_error("roles smoke: traveler line not seen")
				quit(1)
	return false
