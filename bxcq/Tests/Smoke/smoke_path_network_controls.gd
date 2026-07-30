extends SceneTree
## Exercises keyboard movement, click-command movement, and Smart Interact through PlayerController's public command seam.

var _frames := 0
var _phase := 0
var _player: Node
var _execution: Node
var _elder: Node
var _junction_start := Vector2.ZERO
var _click_target := Vector2(1750, 520)
var _click_start_distance := 0.0
var _click_started_ms := 0
var _smart_started_ms := 0

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var err := change_scene_to_file("res://Scenes/DevPrototype/Locations/Village.tscn")
	if err != OK:
		push_error("path controls smoke: failed to load Village")
		quit(1)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:
		return false

	match _phase:
		0:
			_player = root.get_tree().get_first_node_in_group("player")
			_execution = root.get_node_or_null("/root/NarrRailExecution")
			_elder = root.get_tree().current_scene.get_node("Interactables/VillageElder")
			if _player == null or _execution == null or _elder == null:
				_fail("required scene nodes missing")
				return false
			if not _player.get("UsesPathNetwork"):
				_fail("player is not bound to Path Network")
				return false
			_junction_start = _player.get("global_position")
			Input.action_press("move_up")
			_phase = 1
		1:
			if _frames < 80:
				return false
			Input.action_release("move_up")
			var branch_position: Vector2 = _player.get("global_position")
			if int(_player.get("CurrentPathId")) != 1:
				_fail("move_up at the Junction chose path %s instead of BranchPath" % _player.get("CurrentPathId"))
				return false
			if branch_position.distance_to(_junction_start) < 30.0:
				_fail("move_up at the Junction did not enter the rising branch: start=%s end=%s" % [_junction_start, branch_position])
				return false
			_phase = 2
		2:
			if not _player.has_method("RequestMoveTo"):
				_fail("PlayerController lacks the click-command seam")
				return false
			if not _player.call("RequestMoveTo", _click_target):
				_fail("click-command movement was rejected")
				return false
			_click_start_distance = _player.get("global_position").distance_to(_click_target)
			_click_started_ms = Time.get_ticks_msec()
			_phase = 3
		3:
			var click_distance: float = _player.get("global_position").distance_to(_click_target)
			if not _player.get("HasClickRoute"):
				if click_distance > _click_start_distance - 100.0:
					_fail("click-command route completed without meaningful progress")
					return false
				if not _player.has_method("RequestInteractionNode"):
					_fail("PlayerController lacks the Smart Interact command seam")
					return false
				if not _player.call("RequestInteractionNode", _elder):
					_fail("Smart Interact request was rejected")
					return false
				_smart_started_ms = Time.get_ticks_msec()
				_phase = 4
			elif Time.get_ticks_msec() - _click_started_ms > 5000:
				_fail("click-command route did not complete")
		4:
			if _execution.get("IsRunning"):
				print("path controls smoke: PASS")
				quit(0)
			elif Time.get_ticks_msec() - _smart_started_ms > 10000:
				_fail("Smart Interact did not walk to and start the elder dialogue")
	return false

func _fail(message: String) -> void:
	Input.action_release("move_up")
	push_error("path controls smoke: " + message)
	quit(1)
