extends SceneTree
## Smoke for adaptive nine-patch dialogue sizing and tail-tip anchoring.

var _bubble: Control
var _frames := 0
var _phase := 0
var _short_size := Vector2.ZERO
var _anchor := Vector2(640, 620)

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var scene := load("res://Scenes/UI/AdaptiveSpeechBubble.tscn") as PackedScene
	if scene == null:
		_fail("bubble scene failed to load")
		return
	_bubble = scene.instantiate() as Control
	root.add_child(_bubble)
	await process_frame
	if not _bubble.is_node_ready():
		_fail("bubble did not finish _Ready")
		return
	var body := _bubble.get_node_or_null("Body") as NinePatchRect
	var speaker_plate := _bubble.get_node_or_null("SpeakerPlate") as NinePatchRect
	var left_scroll := _bubble.get_node_or_null("LeftScroll") as Control
	var left_scroll_top := _bubble.get_node_or_null("LeftScroll/Top") as TextureRect
	var left_scroll_middle := _bubble.get_node_or_null("LeftScroll/Middle") as TextureRect
	var left_scroll_bottom := _bubble.get_node_or_null("LeftScroll/Bottom") as TextureRect
	var tail := _bubble.get_node_or_null("Tail") as TextureRect
	if body == null or body.texture == null:
		_fail("nine-patch body texture was not loaded")
		return
	if tail == null or tail.texture == null:
		_fail("tail texture was not loaded")
		return
	if speaker_plate == null or speaker_plate.texture == null:
		_fail("speaker scroll texture was not loaded")
		return
	if left_scroll == null \
		or left_scroll_top == null or left_scroll_top.texture == null \
		or left_scroll_middle == null or left_scroll_middle.texture == null \
		or left_scroll_bottom == null or left_scroll_bottom.texture == null:
		_fail("left scroll texture was not loaded")
		return
	if speaker_plate.position.y >= body.position.y:
		_fail("speaker scroll must sit above the dialogue paper")
		return
	if speaker_plate.size.x < body.size.x * 0.65:
		_fail("speaker scroll is too narrow for the reference composition")
		return
	var speaker_texture_ratio := float(speaker_plate.texture.get_width()) / float(speaker_plate.texture.get_height())
	var speaker_rendered_ratio := speaker_plate.size.x / speaker_plate.size.y
	if absf(speaker_rendered_ratio - speaker_texture_ratio) > 0.08:
		_fail("speaker scroll aspect ratio was distorted: %s" % speaker_rendered_ratio)
		return
	if left_scroll.position.x >= body.position.x:
		_fail("left scroll must overlap outside the dialogue paper")
		return
	if left_scroll.position.y >= body.position.y:
		_fail("left scroll must start above the dialogue paper")
		return
	if left_scroll.position.y + left_scroll.size.y <= body.position.y + body.size.y:
		_fail("left scroll must extend below the dialogue paper")
		return
	if tail.position.x <= body.position.x + body.size.x * 0.55:
		_fail("rope tail must attach on the right side of the dialogue paper")
		return
	if tail.position.y + tail.size.y <= body.position.y + body.size.y:
		_fail("rope tail must extend below the dialogue paper")
		return
	var tail_texture_ratio := float(tail.texture.get_width()) / float(tail.texture.get_height())
	var tail_rendered_ratio := tail.size.x / tail.size.y
	if absf(tail_rendered_ratio - tail_texture_ratio) > 0.08:
		_fail("rope tail aspect ratio was distorted: %s" % tail_rendered_ratio)
		return
	_bubble.call("BeginLine", "史官", "短句。")
	_bubble.call("SetVisibleText", "短句。")
	_bubble.call("PlaceAtScreenAnchor", _anchor, Vector2(1280, 720))

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false

	match _phase:
		0:
			_short_size = _bubble.get("TargetBodySize")
			if _short_size.x < float(_bubble.get("MinBubbleWidth")) - 0.5:
				_fail("short line width is below minimum")
				return false
			_bubble.call(
				"BeginLine",
				"史官",
				"这是一段足够长的测试文字，用来验证气泡达到最大宽度后会自动换行，并随着多行文字向下增长，而不是继续横向撑开。")
			_bubble.call("SetVisibleText", "这是一段足够长的测试文字，用来验证气泡达到最大宽度后会自动换行，并随着多行文字向下增长，而不是继续横向撑开。")
			_phase = 1
			_frames = 0
		1:
			_bubble.call("PlaceAtScreenAnchor", _anchor, Vector2(1280, 720))
			if _frames < 45:
				return false
			var long_size: Vector2 = _bubble.get("TargetBodySize")
			if long_size.x > float(_bubble.get("MaxBubbleWidth")) + 0.5:
				_fail("long line exceeded maximum width")
				return false
			if long_size.y <= _short_size.y:
				_fail("wrapped line did not grow vertically")
				return false
			var tip: Vector2 = _bubble.get("TailTipGlobalPosition")
			if tip.distance_to(_anchor) > 1.5:
				_fail("tail tip drifted from speaker anchor: %s" % tip)
				return false
			print("adaptive bubble smoke: PASS short=%s long=%s tip=%s" % [_short_size, long_size, tip])
			quit(0)
	return false

func _fail(message: String) -> void:
	push_error("adaptive bubble smoke: %s" % message)
	quit(1)
