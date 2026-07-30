extends SceneTree
## Smoke for dialogue presenter: Presenter replaces bottom panel; dialogue sets IsDialogueBlocking.

var _frames := 0
var _phase := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("dialogue presenter smoke: failed to load Village (%s)" % err)
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:
		return false

	match _phase:
		0:
			_phase = 1
			_assert_no_bottom_panel()
			_start_dialogue_and_assert_block()
		1:
			if _frames > 90:
				print("dialogue presenter smoke: PASS")
				quit(0)
	return false

func _assert_no_bottom_panel() -> void:
	var tree := root.get_tree()
	if tree.get_first_node_in_group("dialogue_presenter") == null:
		push_error("dialogue presenter smoke: DialoguePresenter missing")
		quit(1)
func _start_dialogue_and_assert_block() -> void:
	var execution := root.get_node("/root/NarrRailExecution")
	var started: bool = execution.call("StartStory", "res://Stories/DevPrototype/village_elder_hello.nrstory")
	if not started:
		push_error("dialogue presenter smoke: NarrRailExecution StartStory failed")
		quit(1)
	var gs := root.get_node("/root/GameState")
	if not gs.get("IsDialogueBlocking"):
		push_error("dialogue presenter smoke: IsDialogueBlocking expected true after start")
		quit(1)
	print("dialogue presenter smoke: blocking=true after NarrRailExecution.StartStory")
