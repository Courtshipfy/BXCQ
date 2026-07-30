class_name NarrRailOutlineRunner
extends RefCounted

signal outline_node_entered(payload: Dictionary)
signal outline_branch_matched(payload: Dictionary)
signal line_changed(payload: Dictionary)
signal choices_changed(choices: Array)
signal variable_changed(payload: Dictionary)
signal event_emitted(payload: Dictionary)
signal choice_timer_changed(payload: Dictionary)
signal choice_timed_out(payload: Dictionary)
signal ended()
signal error_raised(message: String)

const STATE_IDLE := "idle"
const STATE_RUNNING := "running"
const STATE_WAITING_CHOICE := "waiting_choice"
const STATE_ENDED := "ended"
const SESSION_SCRIPT := "res://addons/narrrail/runtime/narrrail_session.gd"
const STORY_RESOURCE_LOADER_SCRIPT := "res://addons/narrrail/runtime/story_resource_loader.gd"
const MAX_OUTLINE_STEPS := 1000

var _outline: Dictionary = {}
var _story_library: Dictionary = {}
var _node_by_id: Dictionary = {}
var _out_edges: Dictionary = {}
var _variables: Dictionary = {}
var _state := STATE_IDLE
var _current_outline_node_id := ""
var _active_story_id := ""
var _active_session: RefCounted = null
var _error := ""
var _step_count := 0

func start(outline_data: Dictionary, story_library: Dictionary, initial_variables: Dictionary = {}) -> void:
	_outline = outline_data
	_story_library = story_library
	_variables = initial_variables.duplicate(true)
	_node_by_id.clear()
	_out_edges.clear()
	_state = STATE_RUNNING
	_current_outline_node_id = String(_outline.get("meta", {}).get("entryNodeId", ""))
	_active_story_id = ""
	_active_session = null
	_error = ""
	_step_count = 0
	_build_indexes()
	_continue_outline()

func next() -> void:
	if _active_session == null:
		if _state == STATE_RUNNING:
			_continue_outline()
		return
	_active_session.call("next")

func choose(index: int) -> void:
	if _active_session == null:
		_raise_error("Cannot choose(): no active story session")
		return
	_active_session.call("choose", index)

func advance_time(delta_seconds: float) -> void:
	if _active_session != null:
		_active_session.call("advance_time", delta_seconds)

func pause() -> void:
	if _active_session == null:
		_raise_error("Cannot pause(): no active story session")
		return
	_active_session.call("pause")

func resume() -> void:
	if _active_session == null:
		return
	_active_session.call("resume")

func get_state() -> Dictionary:
	var story_state := {}
	if _active_session != null:
		story_state = _active_session.call("get_state")
	return {
		"state": _state,
		"currentOutlineNodeId": _current_outline_node_id,
		"activeStoryId": _active_story_id,
		"activeStoryState": story_state,
		"variables": _variables.duplicate(true),
		"error": _error
	}

func _build_indexes() -> void:
	for node in _outline.get("nodes", []):
		var n: Dictionary = node
		_node_by_id[String(n.get("nodeId", ""))] = n
	for edge in _outline.get("edges", []):
		var e: Dictionary = edge
		var source := String(e.get("sourceNodeId", ""))
		if not _out_edges.has(source):
			_out_edges[source] = []
		_out_edges[source].append(e)
	for source in _out_edges.keys():
		(_out_edges[source] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var priority_a := int(a.get("priority", 0))
			var priority_b := int(b.get("priority", 0))
			if priority_a != priority_b:
				return priority_a < priority_b
			return String(a.get("targetNodeId", "")) < String(b.get("targetNodeId", ""))
		)

func _continue_outline() -> void:
	while _state == STATE_RUNNING and _active_session == null:
		_step_count += 1
		if _step_count > MAX_OUTLINE_STEPS:
			_raise_error("Outline execution exceeded max steps; possible loop.")
			return
		if not _node_by_id.has(_current_outline_node_id):
			_raise_error("Outline node not found: %s" % _current_outline_node_id)
			return

		var node: Dictionary = _node_by_id[_current_outline_node_id]
		var node_type := String(node.get("nodeType", ""))
		emit_signal("outline_node_entered", _outline_payload(node))
		match node_type:
			"Story":
				_enter_story_node(node)
				return
			"Branch":
				_enter_branch_node(node)
			"Note":
				_move_to_first_next(String(node.get("nodeId", "")))
			"End":
				_finish()
				return
			_:
				_raise_error("Unsupported outline nodeType: %s" % node_type)
				return

func _enter_story_node(node: Dictionary) -> void:
	var story_id := String(node.get("storyId", ""))
	if story_id.is_empty():
		_raise_error("Story outline node has empty storyId: %s" % String(node.get("nodeId", "")))
		return
	var story_result := _resolve_story(story_id)
	if not story_result.get("ok", false):
		_raise_error(String(story_result.get("error", "Failed to resolve story: %s" % story_id)))
		return

	var session_script: Script = load(SESSION_SCRIPT)
	if session_script == null:
		_raise_error("Failed to load NarrRailSession")
		return

	_active_story_id = story_id
	_active_session = session_script.new()
	_connect_active_session()
	_active_session.call("start", story_result.get("story", {}), _variables)
	var session_state: Dictionary = _active_session.call("get_state")
	if String(session_state.get("state", "")) == "ended" and _active_session != null:
		_on_active_story_ended()

func _enter_branch_node(node: Dictionary) -> void:
	var branches: Array = node.get("branches", [])
	var matched_index := -1
	var error := ""
	for i in range(branches.size()):
		var check := _condition_true(branches[i] as Dictionary)
		if not check.get("ok", false):
			error = String(check.get("error", "Unknown branch condition error"))
			break
		if bool(check.get("value", false)):
			matched_index = i
			break
	if not error.is_empty():
		_raise_error(error)
		return

	var handle := "branch-%d" % matched_index if matched_index >= 0 else "branch-fallback"
	var edge := _edge_for_handle(String(node.get("nodeId", "")), handle)
	if edge.is_empty():
		_raise_error("Branch outline node %s missing outlet: %s" % [String(node.get("nodeId", "")), handle])
		return

	var payload := _outline_payload(node)
	payload["branchIndex"] = matched_index
	payload["sourceHandle"] = handle
	payload["targetNodeId"] = String(edge.get("targetNodeId", ""))
	outline_branch_matched.emit(payload)
	_current_outline_node_id = String(edge.get("targetNodeId", ""))

func _move_to_first_next(source_node_id: String) -> void:
	var edges: Array = _out_edges.get(source_node_id, [])
	if edges.is_empty():
		_finish()
		return
	_current_outline_node_id = String((edges[0] as Dictionary).get("targetNodeId", ""))

func _edge_for_handle(source_node_id: String, source_handle: String) -> Dictionary:
	for edge in _out_edges.get(source_node_id, []):
		var e: Dictionary = edge
		if String(e.get("sourceHandle", "")) == source_handle:
			return e
	return {}

func _resolve_story(story_id: String) -> Dictionary:
	if not _story_library.has(story_id):
		return {"ok": false, "story": {}, "error": "Story not found for outline storyId: %s" % story_id}
	var entry = _story_library[story_id]
	if typeof(entry) == TYPE_DICTIONARY:
		return {"ok": true, "story": entry, "error": ""}
	if entry is Resource and _has_property(entry, "story_data"):
		var data = entry.get("story_data")
		if typeof(data) == TYPE_DICTIONARY:
			return {"ok": true, "story": data, "error": ""}
	if typeof(entry) == TYPE_STRING:
		var loader_script: Script = load(STORY_RESOURCE_LOADER_SCRIPT)
		if loader_script == null:
			return {"ok": false, "story": {}, "error": "Story resource loader missing"}
		var result: Dictionary = loader_script.call("load_story", String(entry))
		if result.get("ok", false):
			return {"ok": true, "story": result.get("story", {}), "error": ""}
		return {"ok": false, "story": {}, "error": result.get("error", "Story load failed")}
	return {"ok": false, "story": {}, "error": "Unsupported story library entry for storyId: %s" % story_id}

func _connect_active_session() -> void:
	_active_session.line_changed.connect(func(payload: Dictionary) -> void:
		var out := payload.duplicate(true)
		out["outlineNodeId"] = _current_outline_node_id
		out["storyId"] = _active_story_id
		line_changed.emit(out)
	)
	_active_session.choices_changed.connect(func(choices: Array) -> void:
		_state = STATE_WAITING_CHOICE
		choices_changed.emit(choices)
	)
	_active_session.variable_changed.connect(func(payload: Dictionary) -> void:
		_variables[String(payload.get("name", ""))] = payload.get("newValue")
		var out := payload.duplicate(true)
		out["outlineNodeId"] = _current_outline_node_id
		out["storyId"] = _active_story_id
		variable_changed.emit(out)
	)
	_active_session.event_emitted.connect(func(payload: Dictionary) -> void:
		var out := payload.duplicate(true)
		out["outlineNodeId"] = _current_outline_node_id
		out["storyId"] = _active_story_id
		event_emitted.emit(out)
	)
	_active_session.choice_timer_changed.connect(func(payload: Dictionary) -> void:
		choice_timer_changed.emit(payload)
	)
	_active_session.choice_timed_out.connect(func(payload: Dictionary) -> void:
		choice_timed_out.emit(payload)
	)
	_active_session.ended.connect(_on_active_story_ended)
	_active_session.error_raised.connect(func(message: String) -> void:
		_raise_error(message)
	)

func _on_active_story_ended() -> void:
	if _active_session != null:
		var state: Dictionary = _active_session.call("get_state")
		_variables = state.get("variables", {}).duplicate(true)
	var completed_outline_node := _current_outline_node_id
	_active_session = null
	_active_story_id = ""
	_state = STATE_RUNNING
	_move_to_first_next(completed_outline_node)
	_continue_outline()

func _condition_true(condition: Dictionary) -> Dictionary:
	var logic := String(condition.get("logic", "All"))
	var terms: Array = condition.get("terms", [])
	if terms.is_empty():
		return {"ok": true, "value": true, "error": ""}
	var any_mode := logic == "Any"
	if logic != "All" and logic != "Any":
		return {"ok": false, "value": false, "error": "Unsupported outline branch logic: %s" % logic}
	for raw_term in terms:
		var term: Dictionary = raw_term
		var check := _condition_term_true(term)
		if not check.get("ok", false):
			return check
		if any_mode and bool(check.get("value", false)):
			return {"ok": true, "value": true, "error": ""}
		if not any_mode and not bool(check.get("value", false)):
			return {"ok": true, "value": false, "error": ""}
	return {"ok": true, "value": not any_mode, "error": ""}

func _condition_term_true(term: Dictionary) -> Dictionary:
	var variable_ref: Dictionary = term.get("variable", {})
	var name := String(variable_ref.get("name", ""))
	if name.is_empty():
		name = String(variable_ref.get("variableName", ""))
	if name.is_empty():
		return {"ok": false, "value": false, "error": "Outline branch term has empty variable name"}
	if not _variables.has(name):
		return {"ok": false, "value": false, "error": "Outline branch variable not found: %s" % name}
	var type_name := _normalize_variable_type(String(variable_ref.get("type", variable_ref.get("variableType", ""))))
	var left = _variables.get(name)
	var right = _parse_value_for_type(term.get("compareValue", null), type_name, left)
	var compare := _compare_values(left, right, String(term.get("operator", "==")))
	return {"ok": true, "value": compare, "error": ""}

func _normalize_variable_type(type_name: String) -> String:
	if ["Bool", "Int", "Float", "String"].has(type_name):
		return type_name
	return ""

func _parse_value_for_type(raw_value, type_name: String, fallback):
	match type_name:
		"Bool":
			if typeof(raw_value) == TYPE_BOOL:
				return raw_value
			return str(raw_value).to_lower() == "true"
		"Int":
			return int(raw_value)
		"Float":
			return float(raw_value)
		"String":
			return str(raw_value)
		_:
			return raw_value

func _compare_values(left, right, op: String) -> bool:
	match op:
		"==":
			return left == right
		"!=":
			return left != right
		">":
			return left > right
		">=":
			return left >= right
		"<":
			return left < right
		"<=":
			return left <= right
	return false

func _outline_payload(node: Dictionary) -> Dictionary:
	return {
		"railId": String(_outline.get("meta", {}).get("railId", "")),
		"nodeId": String(node.get("nodeId", "")),
		"nodeType": String(node.get("nodeType", "")),
		"title": String(node.get("title", "")),
		"summary": String(node.get("summary", ""))
	}

func _finish() -> void:
	_state = STATE_ENDED
	_current_outline_node_id = ""
	_active_session = null
	_active_story_id = ""
	ended.emit()

func _raise_error(message: String) -> void:
	_error = message
	_state = STATE_ENDED
	_active_session = null
	error_raised.emit(message)

func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if String((property as Dictionary).get("name", "")) == property_name:
			return true
	return false
