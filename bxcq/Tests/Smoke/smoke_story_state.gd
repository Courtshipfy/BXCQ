extends SceneTree
## Smoke for story state: layered GameState + story var branch.

const NarrRailSmokeDriver = preload("res://Tests/Smoke/narrrail_smoke_driver.gd")

var _frames := 0
var _phase := 0
var _advances := 0
var _saw_clue_line := false
var _clue_set := false

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("story-state smoke: failed to load Village (%s)" % err)
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false

	match _phase:
		0:
			_phase = 1
			var execution := root.get_node_or_null("/root/NarrRailExecution")
			if execution == null:
				push_error("story-state smoke: NarrRailExecution missing")
				quit(1)
				return false
			if not execution.call("StartStory", "res://Stories/DevPrototype/notice_board_clue.nrstory"):
				push_error("story-state smoke: notice board story failed")
				quit(1)
				return false
			print("story-state smoke: notice board started")
		1:
			_advance_if_running()
			var bridge := root.get_node_or_null("/root/NarrRailBridge")
			if bridge != null and bool(bridge.call("GetBool", "has_clue_manuscript", false)):
				_clue_set = true
			var execution := root.get_node("/root/NarrRailExecution")
			if _clue_set and not bool(execution.get("IsRunning")):
				_phase = 2
				_advances = 0
				_frames = 40
				print("story-state smoke: clue cached, starting elder")
				if not execution.call("StartStory", "res://Stories/DevPrototype/village_elder_hello.nrstory"):
					push_error("story-state smoke: elder story failed")
					quit(1)
					return false
		2:
			_advance_if_running()
			var execution := root.get_node("/root/NarrRailExecution")
			var line := String(execution.get("LastLineText"))
			if line.contains("告示") or line.contains("手稿"):
				_saw_clue_line = true
			if _frames > 280:
				var gs := root.get_node("/root/GameState")
				var scene_path := String(gs.get("CurrentScenePath"))
				if not scene_path.contains("Village"):
					push_error("story-state smoke: CurrentScenePath not Village (%s)" % scene_path)
					quit(1)
					return false
				if not _clue_set:
					push_error("story-state smoke: has_clue_manuscript never true")
					quit(1)
					return false
				if not _saw_clue_line:
					push_error("story-state smoke: elder clue branch line never seen")
					quit(1)
					return false
				var bridge := root.get_node("/root/NarrRailBridge")
				# Study hotspot requires story bool via C# query
				if not bool(bridge.call("GetBool", "has_clue_manuscript", false)):
					push_error("story-state smoke: bridge GetBool failed")
					quit(1)
					return false
				print("story-state smoke: PASS zone=%s" % String(gs.get("CurrentZoneName")))
				quit(0)
	return false

func _advance_if_running() -> void:
	if _frames % 10 != 0 or _advances > 40:
		return
	var execution := root.get_node("/root/NarrRailExecution")
	if bool(execution.get("IsRunning")):
		NarrRailSmokeDriver.advance(execution)
		_advances += 1

# NarrRailExecution exposes the latest Session line as an observable execution outcome.
func _notification(what: int) -> void:
	pass
