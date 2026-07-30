extends SceneTree
## Smoke for adaptive nine-patch dialogue sizing and tail-tip anchoring.

var _bubble: Control
var _speaker_plate: NinePatchRect
var _speaker_label: Label
var _frames := 0
var _phase := 0
var _short_size := Vector2.ZERO
var _anchor := Vector2(640, 620)
var _authored_speaker_anchors := Vector4.ZERO
var _authored_speaker_offsets := Vector4.ZERO
var _authored_speaker_label_anchors := Vector4.ZERO
var _authored_speaker_label_offsets := Vector4.ZERO

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var scene := load("res://Scenes/UI/AdaptiveSpeechBubble.tscn") as PackedScene
	if scene == null:
		_fail("bubble scene failed to load")
		return
	_bubble = scene.instantiate() as Control
	var authored_speaker_plate := _bubble.get_node("SpeakerPlate") as NinePatchRect
	var authored_speaker_label := _bubble.get_node("SpeakerPlate/SpeakerLabel") as Label
	_authored_speaker_anchors = _geometry_anchors(authored_speaker_plate)
	_authored_speaker_offsets = _geometry_offsets(authored_speaker_plate)
	_authored_speaker_label_anchors = _geometry_anchors(authored_speaker_label)
	_authored_speaker_label_offsets = _geometry_offsets(authored_speaker_label)
	root.add_child(_bubble)
	await process_frame
	if not _bubble.is_node_ready():
		_fail("bubble did not finish _Ready")
		return
	var body := _bubble.get_node_or_null("Body") as NinePatchRect
	var speaker_plate := _bubble.get_node_or_null("SpeakerPlate") as NinePatchRect
	var speaker_label := _bubble.get_node_or_null("SpeakerPlate/SpeakerLabel") as Label
	_speaker_plate = speaker_plate
	_speaker_label = speaker_label
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
	if not _speaker_layout_is_authored():
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
				"一位名字非常长但不应撑大底板的史官",
				"这是一段足够长的测试文字，用来验证气泡达到最大宽度后会自动换行，并随着多行文字向下增长，而不是继续横向撑开。")
			_bubble.call("SetVisibleText", "这是一段足够长的测试文字，用来验证气泡达到最大宽度后会自动换行，并随着多行文字向下增长，而不是继续横向撑开。")
			_phase = 1
			_frames = 0
		1:
			_bubble.call("PlaceAtScreenAnchor", _anchor, Vector2(1280, 720))
			if _frames < 45:
				return false
			if not _speaker_layout_is_authored():
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
			var viewport_sizes := [Vector2(1280, 720), Vector2(900, 520)]
			for viewport_size in viewport_sizes:
				var edge_anchors := [
					Vector2(8, 8),
					Vector2(viewport_size.x - 8, 8),
					Vector2(8, viewport_size.y - 8),
					viewport_size - Vector2(8, 8),
				]
				for edge_anchor in edge_anchors:
					_bubble.call("PlaceAtScreenAnchor", edge_anchor, viewport_size)
					var bubble_rect := Rect2(_bubble.global_position, _bubble.size)
					if bubble_rect.position.x < 15.5 \
						or bubble_rect.position.y < 15.5 \
						or bubble_rect.end.x > viewport_size.x - 15.5 \
						or bubble_rect.end.y > viewport_size.y - 15.5:
						_fail(
							"bubble escaped viewport safe bounds size=%s anchor=%s rect=%s"
							% [viewport_size, edge_anchor, bubble_rect])
						return false
			print("adaptive bubble smoke: PASS short=%s long=%s tip=%s bounded_edges=8" % [_short_size, long_size, tip])
			quit(0)
	return false

func _fail(message: String) -> void:
	push_error("adaptive bubble smoke: %s" % message)
	quit(1)

func _geometry_anchors(control: Control) -> Vector4:
	return Vector4(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom)

func _geometry_offsets(control: Control) -> Vector4:
	return Vector4(control.offset_left, control.offset_top, control.offset_right, control.offset_bottom)

func _speaker_layout_is_authored() -> bool:
	if _speaker_plate == null \
		or _geometry_anchors(_speaker_plate) != _authored_speaker_anchors \
		or _geometry_offsets(_speaker_plate) != _authored_speaker_offsets:
		_fail("runtime overwrote the scene-authored speaker plate anchors or offsets")
		return false
	if _speaker_label == null \
		or _geometry_anchors(_speaker_label) != _authored_speaker_label_anchors \
		or _geometry_offsets(_speaker_label) != _authored_speaker_label_offsets:
		_fail("runtime overwrote the scene-authored speaker label anchors or offsets")
		return false
	return true
