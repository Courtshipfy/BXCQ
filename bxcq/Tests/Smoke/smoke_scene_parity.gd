extends SceneTree
## Full scene parity: Church + Study match Village mechanics
## (Path Network fork, camera zones, Person / Examine / Investigate).

var _frames := 0
var _phase := 0
var _advances := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Church.tscn")
	if err != OK:
		push_error("parity smoke: load Church failed")
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 50:
		return false

	var bridge := root.get_node("/root/NarrRailBridge")
	var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
	var host := root.get_tree().current_scene.get_node_or_null("PathNetwork")

	match _phase:
		0:
			if host == null:
				push_error("parity: Church PathNetwork missing")
				quit(1)
				return false
			var path_kids := 0
			for c in host.get_children():
				if c is Path2D:
					path_kids += 1
			if path_kids < 2:
				push_error("parity: Church need >=2 Walk Paths (got %s)" % path_kids)
				quit(1)
				return false
			var zones := root.get_tree().get_nodes_in_group("camera_zones")
			if zones.size() < 2:
				push_error("parity: Church need >=2 camera zones")
				quit(1)
				return false
			if _find("ChurchNovice") == null or not bool(_find("ChurchNovice").get("IsPerson")):
				push_error("parity: ChurchNovice Person missing")
				quit(1)
				return false
			if _find("ChurchAltar") == null or not bool(_find("ChurchAltar").get("IsExamineProp")):
				push_error("parity: ChurchAltar Examine missing")
				quit(1)
				return false
			if _find("Reliquary") == null:
				push_error("parity: Reliquary investigate missing")
				quit(1)
				return false
			print("parity: A Church structure OK")
			_phase = 1
			_advances = 0
			_frames = 40
			bridge.call("ClearStoryVariables")
			if not presenter.call("StartStory", "res://Stories/DevPrototype/church_reliquary_clue.nrstory"):
				push_error("parity: reliquary story failed")
				quit(1)
				return false
		1:
			if _frames % 8 == 0 and _advances < 24 and bool(presenter.get("IsRunning")):
				presenter.call("SmokeAdvance")
				_advances += 1
			if bool(bridge.call("GetBool", "has_church_relic_clue", false)) and not bool(presenter.get("IsRunning")):
				print("parity: B relic clue OK")
				_phase = 2
				_advances = 0
				_frames = 40
				if not presenter.call("StartStory", "res://Stories/DevPrototype/church_novice_hello.nrstory"):
					push_error("parity: novice story failed")
					quit(1)
					return false
		2:
			if _frames % 8 == 0 and _advances < 20 and bool(presenter.get("IsRunning")):
				presenter.call("SmokeAdvance")
				_advances += 1
			var line := String(presenter.get("LastLineText"))
			if line.contains("圣龛") or line.contains("记号") or line.contains("认真"):
				print("parity: C novice relic branch OK")
				_phase = 3
				_frames = 0
				# Finish story then go Study
				return false
		3:
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			if bool(presenter.get("IsRunning")):
				if _frames % 6 == 0:
					presenter.call("SmokeAdvance")
				if _frames > 200:
					push_error("parity: novice never ended")
					quit(1)
				return false
			_phase = 4
			_frames = 0
			print("parity: D enter Study")
			root.get_node("/root/SceneTransition").call("GoTo", "res://Scenes/DevPrototype/Locations/Study.tscn", "from_church")
		4:
			if _frames < 55:
				return false
			if bool(root.get_node("/root/SceneTransition").get("IsBusy")):
				return false
			host = root.get_tree().current_scene.get_node_or_null("PathNetwork")
			var path_kids2 := 0
			for c in host.get_children():
				if c is Path2D:
					path_kids2 += 1
			if path_kids2 < 2:
				push_error("parity: Study need >=2 Walk Paths")
				quit(1)
				return false
			if root.get_tree().get_nodes_in_group("camera_zones").size() < 2:
				push_error("parity: Study need >=2 camera zones")
				quit(1)
				return false
			if _find("StudyScribe") == null or not bool(_find("StudyScribe").get("IsPerson")):
				push_error("parity: StudyScribe Person missing")
				quit(1)
				return false
			if _find("Bookshelf") == null or not bool(_find("Bookshelf").get("IsExamineProp")):
				push_error("parity: Bookshelf Examine missing")
				quit(1)
				return false
			if _find("ManuscriptDesk") == null:
				push_error("parity: ManuscriptDesk missing")
				quit(1)
				return false
			presenter = root.get_tree().get_first_node_in_group("dialogue_presenter")
			var altar_like := _find("Bookshelf")
			if not presenter.call("ShowExamine", altar_like.get("AnchorGlobalPosition"), "查看", String(altar_like.get("ExamineText"))):
				push_error("parity: study examine failed")
				quit(1)
				return false
			presenter.call("DismissExamine")
			print("parity: E Study structure + examine OK")
			print("parity: PASS full scene mechanics")
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
