extends SceneTree
## Smoke for NarrRail bridge: EmitEvent → NarrRailBridge → camera / hotspot.

var _frames := 0
var _phase := 0
var _advances := 0
var _saw_camera := false
var _saw_hotspot := false

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("bridge smoke: failed to load Village (%s)" % err)
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false

	match _phase:
		0:
			_phase = 1
			var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
			if presenter == null:
				push_error("bridge smoke: DialoguePresenter missing")
				quit(1)
				return false
			if not presenter.call("StartSampleStory"):
				push_error("bridge smoke: StartSampleStory failed")
				quit(1)
				return false
			print("bridge smoke: story started")
		1:
			_poll_effects()
			if _frames % 8 == 0 and _advances < 28:
				var presenter := root.get_tree().get_first_node_in_group("dialogue_presenter")
				if presenter != null and presenter.get("IsRunning"):
					presenter.call("SmokeAdvance")
					_advances += 1
			if _frames > 260:
				if not _saw_camera:
					push_error("bridge smoke: camera never reached East")
					quit(1)
					return false
				if not _saw_hotspot:
					push_error("bridge smoke: to_church never enabled")
					quit(1)
					return false
				print("bridge smoke: PASS")
				quit(0)
	return false

func _poll_effects() -> void:
	var scene := root.get_tree().current_scene
	if scene == null:
		return
	var director := scene.get_node_or_null("CameraDirector")
	if director != null and String(director.get("CurrentZoneName")) == "East":
		_saw_camera = true
	for node in root.get_tree().get_nodes_in_group("scene_hotspots"):
		if String(node.get("HotspotId")) == "to_church" and bool(node.get("IsEnabled")):
			_saw_hotspot = true
			break
