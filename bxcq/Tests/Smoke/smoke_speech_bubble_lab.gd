extends SceneTree
## Smoke for click-driven dialogue progression and bounded lab placement.

var _lab: Control
var _stage: Control
var _bubble: Control

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var scene := load("res://Scenes/Tests/SpeechBubbleLab.tscn") as PackedScene
	if scene == null:
		_fail("lab scene failed to load")
		return
	_lab = scene.instantiate() as Control
	root.add_child(_lab)
	await _wait_frames(4)
	_stage = _lab.get_node("Stage") as Control
	_bubble = _stage.get_node("AdaptiveSpeechBubble") as Control
	var body_label := _bubble.get_node("TextClip/BodyLabel") as Label
	var speaker_label := _bubble.get_node("SpeakerPlate/SpeakerLabel") as Label
	var anchor_marker := _stage.get_node("AnchorMarker") as Control
	if not _bubble.visible:
		_fail("demo did not start with a visible bubble")
		return

	if body_label.text != "好。":
		_fail("demo did not visibly present the opening short line")
		return
	var short_size: Vector2 = _bubble.get("TargetBodySize")
	var first_anchor := anchor_marker.position

	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	await _wait_frames(2)
	if speaker_label.text != "旅人":
		_fail("second click did not advance to the next speaker")
		return
	if anchor_marker.position.distance_to(first_anchor) < 40.0:
		_fail("dialogue advance did not move to a different anchor position")
		return

	# Reveal line 2, advance to line 3, reveal it, then advance to long line 4.
	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	await _wait_frames(2)
	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	await _wait_frames(2)
	_emit_stage_click(MOUSE_BUTTON_LEFT, _stage.size * 0.5)
	await _wait_frames(24)
	var long_size: Vector2 = _bubble.get("TargetBodySize")
	if long_size.y <= short_size.y:
		_fail("click sequence did not reach a vertically expanded long line")
		return

	_emit_stage_click(MOUSE_BUTTON_RIGHT, Vector2(2, 2))
	await _wait_frames(3)
	var bubble_rect := Rect2(_bubble.global_position, _bubble.size)
	var safe_rect := Rect2(_stage.global_position + Vector2(24, 24), _stage.size - Vector2(48, 48))
	if bubble_rect.position.x < safe_rect.position.x - 0.5 \
		or bubble_rect.position.y < safe_rect.position.y - 0.5 \
		or bubble_rect.end.x > safe_rect.end.x + 0.5 \
		or bubble_rect.end.y > safe_rect.end.y + 0.5:
		_fail("lab bubble escaped its safe stage rect: bubble=%s safe=%s" % [bubble_rect, safe_rect])
		return

	print("speech bubble lab smoke: PASS short=%s long=%s bounded=%s" % [short_size, long_size, bubble_rect])
	quit(0)

func _emit_stage_click(button: MouseButton, local_position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = local_position
	event.global_position = _stage.global_position + local_position
	_stage.emit_signal("gui_input", event)

func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame

func _fail(message: String) -> void:
	push_error("speech bubble lab smoke: %s" % message)
	quit(1)
