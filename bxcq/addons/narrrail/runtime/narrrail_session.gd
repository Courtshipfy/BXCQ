class_name NarrRailSession
extends RefCounted

signal line_changed(payload: Dictionary)
signal choices_changed(choices: Array)
signal ended()
signal error_raised(message: String)
signal variable_changed(payload: Dictionary)
signal event_emitted(payload: Dictionary)
signal trace_logged(payload: Dictionary)
signal choice_timer_changed(payload: Dictionary)
signal choice_timed_out(payload: Dictionary)

const STATE_IDLE := "idle"
const STATE_RUNNING := "running"
const STATE_WAITING_CHOICE := "waiting_choice"
const STATE_PAUSED := "paused"
const STATE_ENDED := "ended"
const STORY_MODEL_SCRIPT := "res://addons/narrrail/runtime/story_model.gd"
const SAVE_SCHEMA_VERSION := 1
const TRACE_LEVEL_ERROR := 0
const TRACE_LEVEL_INFO := 1
const TRACE_LEVEL_DEBUG := 2

var _story: Dictionary = {}
var _node_by_id: Dictionary = {}
var _out_edges: Dictionary = {}
var _variable_defs: Dictionary = {}
var _variables: Dictionary = {}
var _emitted_events: Array = []
var _exhausted_choice_targets: Dictionary = {}
var _exhaustive_choice_stack: Array[String] = []
var _state: String = STATE_IDLE
var _current_node_id: String = ""
var _paused_event_node_id: String = ""
var _current_choices: Array = []
var _current_line_index: int = -1
var _choice_timer: Dictionary = {
	"enabled": false,
	"durationSeconds": 0.0,
	"remainingSeconds": 0.0,
	"timeoutChoiceTextKey": ""
}
var _trace_enabled: bool = false
var _trace_level: int = TRACE_LEVEL_INFO
var _trace_records: Array = []

func set_trace_enabled(enabled: bool) -> void:
	_trace_enabled = enabled

func set_trace_level(level: int) -> void:
	_trace_level = clampi(level, TRACE_LEVEL_ERROR, TRACE_LEVEL_DEBUG)

func get_trace_records() -> Array:
	return _trace_records.duplicate(true)

func start(story_data: Dictionary, initial_variables: Dictionary = {}) -> void:
	_trace_records.clear()
	var model_script: Script = load(STORY_MODEL_SCRIPT)
	if model_script == null:
		_emit_error("Failed to load story model script: %s" % STORY_MODEL_SCRIPT)
		return

	var check: Dictionary = model_script.call("validate_minimal", story_data)
	if not check.get("ok", false):
		_emit_error("Story validation failed: %s" % "; ".join(check.get("errors", [])))
		return

	_story = story_data
	_build_indexes()
	_emitted_events.clear()
	_exhausted_choice_targets.clear()
	_exhaustive_choice_stack.clear()
	var variables_check := _initialize_variables()
	if not variables_check.get("ok", false):
		_emit_error("Variable initialization failed: %s" % String(variables_check.get("error", "unknown")))
		return
	var initial_variables_check := _apply_initial_variables(initial_variables)
	if not initial_variables_check.get("ok", false):
		_emit_error("Initial variable snapshot failed: %s" % String(initial_variables_check.get("error", "unknown")))
		return

	_state = STATE_RUNNING
	_paused_event_node_id = ""
	_current_choices.clear()
	_current_line_index = -1
	_reset_choice_timer(false)
	_trace("session_start", TRACE_LEVEL_INFO, {"storyId": String(_story.get("meta", {}).get("storyId", ""))})

	var entry_id := String(_story.get("meta", {}).get("entryNodeId", ""))
	_enter_node(entry_id)

func next() -> void:
	if _state == STATE_ENDED:
		return
	if _state == STATE_PAUSED:
		_emit_error("Cannot next(): session is paused")
		return
	if _state == STATE_WAITING_CHOICE:
		_emit_error("Cannot next(): waiting for choose(index)")
		return
	if _state != STATE_RUNNING:
		_emit_error("Cannot next() in state: %s" % _state)
		return

	var node: Dictionary = _node_by_id.get(_current_node_id, {})
	var node_type := String(node.get("nodeType", ""))

	match node_type:
		"Dialogue":
			var leave_check := _execute_exit_actions(_current_node_id)
			if not leave_check.get("ok", false):
				_emit_error(String(leave_check.get("error", "Unknown exit action error")))
				return
			_move_to_next_by_edges(_current_node_id)
		"MultiDialogue":
			_advance_multi_dialogue(node)
		"End":
			_finish()
		_:
			_emit_error("next() not supported for nodeType: %s" % node_type)

func choose(index: int) -> void:
	if _state == STATE_PAUSED:
		_emit_error("Cannot choose(): session is paused")
		return
	if _state != STATE_WAITING_CHOICE:
		_emit_error("Cannot choose(): not in waiting_choice state")
		return

	if index < 0 or index >= _current_choices.size():
		_emit_error("Choice index out of range: %d" % index)
		return

	var chosen: Dictionary = _current_choices[index]
	var target := String(chosen.get("targetNodeId", ""))
	if target.is_empty():
		_emit_error("Chosen option has empty targetNodeId")
		return

	_select_choice_target(target, "choice", true)

func advance_time(delta_seconds: float) -> void:
	if _state != STATE_WAITING_CHOICE:
		return
	if not bool(_choice_timer.get("enabled", false)):
		return
	if delta_seconds <= 0.0:
		return

	var remaining := maxf(0.0, float(_choice_timer.get("remainingSeconds", 0.0)) - delta_seconds)
	_choice_timer["remainingSeconds"] = remaining
	_emit_choice_timer_changed()
	if remaining > 0.0:
		return

	_timeout_current_choice()

func pause() -> void:
	if _state == STATE_PAUSED:
		return
	if _state != STATE_RUNNING:
		_emit_error("Cannot pause() in state: %s" % _state)
		return

	_state = STATE_PAUSED
	_paused_event_node_id = ""
	var node: Dictionary = _node_by_id.get(_current_node_id, {})
	if String(node.get("nodeType", "")) == "EmitEvent":
		_paused_event_node_id = _current_node_id
	_trace("paused", TRACE_LEVEL_INFO, {"nodeId": _current_node_id})

func resume() -> void:
	if _state != STATE_PAUSED:
		return

	var resume_node_id := _paused_event_node_id
	_paused_event_node_id = ""
	_state = STATE_RUNNING
	_trace("resumed", TRACE_LEVEL_INFO, {"nodeId": _current_node_id})
	if not resume_node_id.is_empty():
		_move_to_next_by_edges(resume_node_id)

func get_state() -> Dictionary:
	return {
		"state": _state,
		"currentNodeId": _current_node_id,
		"pausedEventNodeId": _paused_event_node_id,
		"currentLineIndex": _current_line_index,
		"choices": _current_choices.duplicate(true),
		"choiceTimer": _choice_timer.duplicate(true),
		"variables": _variables.duplicate(true),
		"events": _emitted_events.duplicate(true),
		"exhaustedChoiceTargets": _exhausted_choice_targets.duplicate(true),
		"exhaustiveChoiceStack": _exhaustive_choice_stack.duplicate(true),
		"trace": _trace_records.duplicate(true)
	}

func get_variable_snapshot() -> Dictionary:
	return _variables.duplicate(true)

func create_save_snapshot() -> Dictionary:
	return {
		"saveSchemaVersion": SAVE_SCHEMA_VERSION,
		"story": {
			"schemaVersion": int(_story.get("meta", {}).get("schemaVersion", 0)),
			"storyId": String(_story.get("meta", {}).get("storyId", ""))
		},
		"session": get_state()
	}

func restore_save_snapshot(story_data: Dictionary, snapshot: Dictionary) -> bool:
	var snapshot_check := _validate_save_snapshot(story_data, snapshot)
	if not snapshot_check.get("ok", false):
		_emit_error(String(snapshot_check.get("error", "Invalid save snapshot")))
		return false

	var model_script: Script = load(STORY_MODEL_SCRIPT)
	if model_script == null:
		_emit_error("Failed to load story model script: %s" % STORY_MODEL_SCRIPT)
		return false

	var check: Dictionary = model_script.call("validate_minimal", story_data)
	if not check.get("ok", false):
		_emit_error("Story validation failed: %s" % "; ".join(check.get("errors", [])))
		return false

	_story = story_data
	_build_indexes()
	var variables_check := _initialize_variables()
	if not variables_check.get("ok", false):
		_emit_error("Variable initialization failed: %s" % String(variables_check.get("error", "unknown")))
		return false

	var session_data: Dictionary = snapshot.get("session", {})
	var apply_check := _apply_save_session_data(session_data)
	if not apply_check.get("ok", false):
		_emit_error(String(apply_check.get("error", "Invalid save session data")))
		return false

	_trace("session_restore", TRACE_LEVEL_INFO, {"storyId": String(_story.get("meta", {}).get("storyId", ""))})
	_emit_restored_presentation()
	return true

func _build_indexes() -> void:
	_node_by_id.clear()
	_out_edges.clear()

	for n in _story.get("nodes", []):
		var id := String(n.get("nodeId", ""))
		_node_by_id[id] = n

	for e in _story.get("edges", []):
		var s := String(e.get("sourceNodeId", ""))
		if not _out_edges.has(s):
			_out_edges[s] = []
		_out_edges[s].append(e)

func _enter_node(node_id: String) -> void:
	if not _node_by_id.has(node_id):
		_emit_error("Node not found: %s" % node_id)
		return

	_current_node_id = node_id
	_current_line_index = -1
	var node: Dictionary = _node_by_id[node_id]
	var node_type := String(node.get("nodeType", ""))
	if node_type != "Choice":
		_reset_choice_timer(true)
	_trace("node_enter", TRACE_LEVEL_INFO, {"nodeType": node_type})
	var enter_check := _execute_actions(node.get("enterActions", []), "enter", node_id)
	if not enter_check.get("ok", false):
		_emit_error(String(enter_check.get("error", "Unknown enter action error")))
		return

	match node_type:
		"Dialogue":
			var dialogue: Dictionary = node.get("dialogue", {})
			var payload := {
				"nodeId": node_id,
				"lineIndex": 0,
				"speakerId": String(dialogue.get("speakerId", "")),
				"textKey": String(dialogue.get("textKey", ""))
			}
			_trace("line", TRACE_LEVEL_INFO, payload)
			line_changed.emit(payload)
		"MultiDialogue":
			_current_line_index = 0
			var emit_check := _emit_multi_dialogue_line(node)
			if not emit_check.get("ok", false):
				_emit_error(String(emit_check.get("error", "Unknown MultiDialogue error")))
				return
		"Choice":
			var available_check := _get_available_choices(node)
			if not available_check.get("ok", false):
				_emit_error(String(available_check.get("error", "Unknown choice availability error")))
				return
			var choices: Array = available_check.get("choices", [])
			if choices.is_empty() and _choice_mode(node) == "ExhaustiveUntilComplete":
				var completion_target := String(node.get("choiceCompletionTargetNodeId", ""))
				if completion_target.is_empty():
					_emit_error("Exhaustive choice has empty choiceCompletionTargetNodeId: %s" % node_id)
					return
				var leave_check := _execute_exit_actions(node_id)
				if not leave_check.get("ok", false):
					_emit_error(String(leave_check.get("error", "Unknown exhaustive choice exit action error")))
					return
				_pop_exhaustive_choice_frame(node_id)
				_enter_node(completion_target)
				return
			_current_choices = choices.duplicate(true)
			_state = STATE_WAITING_CHOICE
			_start_choice_timer(node)
			_trace("choices", TRACE_LEVEL_INFO, {"choiceCount": _current_choices.size()})
			choices_changed.emit(_current_choices.duplicate(true))
		"Jump":
			var target := String(node.get("jumpTargetNodeId", ""))
			if target.is_empty():
				_emit_error("Jump node has empty jumpTargetNodeId: %s" % node_id)
				return
			var leave_check := _execute_exit_actions(node_id)
			if not leave_check.get("ok", false):
				_emit_error(String(leave_check.get("error", "Unknown jump exit action error")))
				return
			_trace("transition", TRACE_LEVEL_INFO, {"sourceNodeId": node_id, "targetNodeId": target, "reason": "jump"})
			_enter_node(target)
		"SetVariable":
			var set_check := _execute_actions(node.get("actions", []), "node", node_id)
			if not set_check.get("ok", false):
				_emit_error(String(set_check.get("error", "Unknown SetVariable action error")))
				return
			_move_to_next_by_edges(node_id)
		"EmitEvent":
			var event_check := _execute_emit_event_node(node)
			if not event_check.get("ok", false):
				_emit_error(String(event_check.get("error", "Unknown EmitEvent node error")))
				return
			if _state == STATE_PAUSED and _paused_event_node_id == node_id:
				return
			_move_to_next_by_edges(node_id)
		"Condition":
			var condition_check := _resolve_condition_node_target(node)
			if not condition_check.get("ok", false):
				_emit_error(String(condition_check.get("error", "Unknown Condition node error")))
				return
			var condition_target := String(condition_check.get("targetNodeId", ""))
			if condition_target.is_empty():
				_finish()
				return
			_enter_node(condition_target)
		"End":
			_finish()
		_:
			_emit_error("Unsupported nodeType in MVP: %s" % node_type)

func _validate_save_snapshot(story_data: Dictionary, snapshot: Dictionary) -> Dictionary:
	if int(snapshot.get("saveSchemaVersion", 0)) != SAVE_SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported saveSchemaVersion: %s" % String(snapshot.get("saveSchemaVersion", ""))}
	if not snapshot.has("story") or typeof(snapshot.get("story")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Save snapshot missing story metadata"}
	if not snapshot.has("session") or typeof(snapshot.get("session")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Save snapshot missing session data"}

	var save_story: Dictionary = snapshot.get("story", {})
	var story_meta: Dictionary = story_data.get("meta", {})
	var save_schema_version := int(save_story.get("schemaVersion", 0))
	var story_schema_version := int(story_meta.get("schemaVersion", 0))
	if save_schema_version != story_schema_version:
		return {"ok": false, "error": "Save story schemaVersion mismatch: expected %d got %d" % [story_schema_version, save_schema_version]}

	var save_story_id := String(save_story.get("storyId", ""))
	var story_id := String(story_meta.get("storyId", ""))
	if not save_story_id.is_empty() and not story_id.is_empty() and save_story_id != story_id:
		return {"ok": false, "error": "Save storyId mismatch: expected %s got %s" % [story_id, save_story_id]}

	return {"ok": true, "error": ""}

func _apply_save_session_data(session_data: Dictionary) -> Dictionary:
	var restored_state := String(session_data.get("state", ""))
	if not [STATE_RUNNING, STATE_WAITING_CHOICE, STATE_PAUSED, STATE_ENDED].has(restored_state):
		return {"ok": false, "error": "Unsupported saved session state: %s" % restored_state}

	var restored_node_id := String(session_data.get("currentNodeId", ""))
	if restored_state != STATE_ENDED and not _node_by_id.has(restored_node_id):
		return {"ok": false, "error": "Saved currentNodeId not found: %s" % restored_node_id}

	var variables = session_data.get("variables", {})
	if typeof(variables) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Saved variables must be a Dictionary"}
	for name in variables.keys():
		var variable_name := String(name)
		if not _variable_defs.has(variable_name):
			return {"ok": false, "error": "Saved variable not defined by story: %s" % variable_name}
		var def: Dictionary = _variable_defs[variable_name]
		var parsed := _parse_value_for_type(variables[name], String(def.get("type", "")))
		if not parsed.get("ok", false):
			return {"ok": false, "error": "Saved variable invalid for %s: %s" % [variable_name, String(parsed.get("error", "unknown"))]}
		_variables[variable_name] = parsed.get("value")

	var restored_events = session_data.get("events", [])
	if typeof(restored_events) != TYPE_ARRAY:
		return {"ok": false, "error": "Saved events must be an Array"}
	var restored_exhausted = session_data.get("exhaustedChoiceTargets", {})
	if typeof(restored_exhausted) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Saved exhaustedChoiceTargets must be a Dictionary"}
	var restored_stack = session_data.get("exhaustiveChoiceStack", [])
	if typeof(restored_stack) != TYPE_ARRAY:
		return {"ok": false, "error": "Saved exhaustiveChoiceStack must be an Array"}
	var restored_choice_timer = session_data.get("choiceTimer", {})
	if typeof(restored_choice_timer) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Saved choiceTimer must be a Dictionary"}

	_state = restored_state
	_current_node_id = restored_node_id
	_paused_event_node_id = String(session_data.get("pausedEventNodeId", ""))
	_current_line_index = int(session_data.get("currentLineIndex", -1))
	_emitted_events = (restored_events as Array).duplicate(true)
	_exhausted_choice_targets = (restored_exhausted as Dictionary).duplicate(true)
	_exhaustive_choice_stack.clear()
	for item in restored_stack:
		_exhaustive_choice_stack.append(String(item))
	_current_choices.clear()
	_reset_choice_timer(false)

	if _state == STATE_PAUSED:
		var paused_node: Dictionary = _node_by_id.get(_current_node_id, {})
		if String(paused_node.get("nodeType", "")) != "EmitEvent":
			return {"ok": false, "error": "Saved paused state is not on an EmitEvent node: %s" % _current_node_id}
		if _paused_event_node_id.is_empty():
			_paused_event_node_id = _current_node_id
		elif _paused_event_node_id != _current_node_id:
			return {"ok": false, "error": "Saved pausedEventNodeId mismatch: %s" % _paused_event_node_id}

	if _state == STATE_WAITING_CHOICE:
		var node: Dictionary = _node_by_id.get(_current_node_id, {})
		if String(node.get("nodeType", "")) != "Choice":
			return {"ok": false, "error": "Saved waiting_choice state is not on a Choice node: %s" % _current_node_id}
		var choices_check := _get_available_choices(node)
		if not choices_check.get("ok", false):
			return {"ok": false, "error": String(choices_check.get("error", "Unknown choice restore error"))}
		_current_choices = (choices_check.get("choices", []) as Array).duplicate(true)
		_start_choice_timer(node)
		if not (restored_choice_timer as Dictionary).is_empty():
			_restore_choice_timer(restored_choice_timer as Dictionary)

	return {"ok": true, "error": ""}

func _emit_restored_presentation() -> void:
	match _state:
		STATE_WAITING_CHOICE:
			_emit_choice_timer_changed()
			choices_changed.emit(_current_choices.duplicate(true))
		STATE_RUNNING:
			_emit_current_line_after_restore()
		STATE_PAUSED:
			_emit_current_line_after_restore()
		STATE_ENDED:
			ended.emit()

func _emit_current_line_after_restore() -> void:
	if not _node_by_id.has(_current_node_id):
		return
	var node: Dictionary = _node_by_id[_current_node_id]
	var node_type := String(node.get("nodeType", ""))
	match node_type:
		"Dialogue":
			var dialogue: Dictionary = node.get("dialogue", {})
			var payload := {
				"nodeId": _current_node_id,
				"lineIndex": 0,
				"speakerId": String(dialogue.get("speakerId", "")),
				"textKey": String(dialogue.get("textKey", ""))
			}
			_trace("line", TRACE_LEVEL_INFO, payload)
			line_changed.emit(payload)
		"MultiDialogue":
			var emit_check := _emit_multi_dialogue_line(node)
			if not emit_check.get("ok", false):
				_emit_error(String(emit_check.get("error", "Unknown MultiDialogue restore error")))

func _move_to_next_by_edges(source_node_id: String) -> void:
	var edges: Array = _out_edges.get(source_node_id, [])
	if edges.is_empty():
		_finish()
		return

	var filtered: Array = []
	for e in edges:
		var condition_check := _condition_true(e.get("condition", {}))
		if not condition_check.get("ok", false):
			_emit_error("Edge condition failed from %s to %s: %s" % [
				source_node_id,
				String(e.get("targetNodeId", "")),
				String(condition_check.get("error", "unknown"))
			])
			return
		if bool(condition_check.get("value", false)):
			filtered.append(e)

	if filtered.is_empty():
		_finish()
		return

	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) < int(b.get("priority", 0))
	)

	var target := String(filtered[0].get("targetNodeId", ""))
	if target.is_empty():
		_emit_error("Resolved edge has empty targetNodeId")
		return

	_trace("transition", TRACE_LEVEL_INFO, {"sourceNodeId": source_node_id, "targetNodeId": target, "reason": "edge"})
	_enter_node(target)

func _advance_multi_dialogue(node: Dictionary) -> void:
	var lines: Array = node.get("multiDialogue", {}).get("lines", [])
	if lines.is_empty():
		_emit_error("MultiDialogue node has no lines: %s" % _current_node_id)
		return

	if _current_line_index < lines.size() - 1:
		_current_line_index += 1
		var emit_check := _emit_multi_dialogue_line(node)
		if not emit_check.get("ok", false):
			_emit_error(String(emit_check.get("error", "Unknown MultiDialogue error")))
		return

	var leave_check := _execute_exit_actions(_current_node_id)
	if not leave_check.get("ok", false):
		_emit_error(String(leave_check.get("error", "Unknown exit action error")))
		return
	_move_to_next_by_edges(_current_node_id)

func _emit_multi_dialogue_line(node: Dictionary) -> Dictionary:
	var node_id := String(node.get("nodeId", ""))
	var multi_dialogue: Dictionary = node.get("multiDialogue", {})
	var lines: Array = multi_dialogue.get("lines", [])
	if lines.is_empty():
		return {"ok": false, "error": "MultiDialogue node has no lines: %s" % node_id}
	if _current_line_index < 0 or _current_line_index >= lines.size():
		return {"ok": false, "error": "MultiDialogue line index out of range on node %s: %d" % [node_id, _current_line_index]}

	var line: Dictionary = lines[_current_line_index]
	var payload := {
		"nodeId": node_id,
		"lineIndex": _current_line_index,
		"speakerId": String(multi_dialogue.get("speakerId", "")),
		"textKey": String(line.get("textKey", ""))
	}
	_trace("line", TRACE_LEVEL_INFO, payload)
	line_changed.emit(payload)
	return {"ok": true, "error": ""}

func _initialize_variables() -> Dictionary:
	_variable_defs.clear()
	_variables.clear()

	for v in _story.get("variables", []):
		var variable: Dictionary = v
		var name := String(variable.get("name", ""))
		var type_name := _normalize_variable_type(String(variable.get("type", "")))
		if type_name.is_empty():
			return {"ok": false, "error": "Unsupported variable type for %s: %s" % [name, String(variable.get("type", ""))]}

		var parsed := _parse_value_for_type(_default_value_for_variable(variable, type_name), type_name)
		if not parsed.get("ok", false):
			return {"ok": false, "error": "Invalid defaultValue for %s: %s" % [name, String(parsed.get("error", "unknown"))]}

		_variable_defs[name] = {
			"name": name,
			"type": type_name,
			"scope": String(variable.get("scope", "Session"))
		}
		_variables[name] = parsed.get("value")

	return {"ok": true, "error": ""}

func _apply_initial_variables(initial_variables: Dictionary) -> Dictionary:
	for name in initial_variables.keys():
		var variable_name := String(name)
		if not _variable_defs.has(variable_name):
			continue
		var def: Dictionary = _variable_defs[variable_name]
		var parsed := _parse_value_for_type(initial_variables[name], String(def.get("type", "")))
		if not parsed.get("ok", false):
			return {"ok": false, "error": "Invalid initial value for %s: %s" % [variable_name, String(parsed.get("error", "unknown"))]}
		_variables[variable_name] = parsed.get("value")
	return {"ok": true, "error": ""}

func _get_available_choices(node: Dictionary) -> Dictionary:
	var out: Array = []
	var node_id := String(node.get("nodeId", ""))
	var exhausted_targets: Dictionary = _exhausted_choice_targets.get(node_id, {})
	var is_exhaustive := _choice_mode(node) == "ExhaustiveUntilComplete"

	for raw_choice in node.get("choices", []):
		var choice: Dictionary = raw_choice
		var target := String(choice.get("targetNodeId", ""))
		if is_exhaustive and exhausted_targets.has(target):
			continue
		var availability: Dictionary = choice.get("availability", {})
		var check := _condition_true(availability)
		if not check.get("ok", false):
			return {
				"ok": false,
				"choices": [],
				"error": "Choice availability failed on node %s: %s" % [node_id, String(check.get("error", "unknown"))]
			}
		if bool(check.get("value", false)):
			out.append(choice)

	return {"ok": true, "choices": out, "error": ""}

func _choice_mode(node: Dictionary) -> String:
	return String(node.get("choiceMode", "SinglePass"))

func _select_choice_target(target: String, reason: String, mark_exhaustive: bool) -> void:
	var source_node_id := _current_node_id
	var leave_check := _execute_exit_actions(source_node_id)
	if not leave_check.get("ok", false):
		_emit_error(String(leave_check.get("error", "Unknown choice exit action error")))
		return

	if mark_exhaustive:
		_mark_exhaustive_choice_selected(source_node_id, target)
		_push_exhaustive_choice_frame(source_node_id)
	_current_choices.clear()
	_reset_choice_timer(true)
	_paused_event_node_id = ""
	_state = STATE_RUNNING
	_trace("transition", TRACE_LEVEL_INFO, {"sourceNodeId": source_node_id, "targetNodeId": target, "reason": reason})
	_enter_node(target)

func _timeout_current_choice() -> void:
	if _state != STATE_WAITING_CHOICE:
		return
	var source_node_id := _current_node_id
	var target_check := _target_for_source_handle(source_node_id, "choice-timeout")
	if not target_check.get("ok", false):
		_emit_error(String(target_check.get("error", "Choice timer timeout target missing")))
		return
	var target := String(target_check.get("targetNodeId", ""))
	if target.is_empty():
		_emit_error("Choice timer timeout target is empty on node: %s" % source_node_id)
		return

	var payload := _choice_timer_payload()
	payload["targetNodeId"] = target
	choice_timed_out.emit(payload)
	_select_choice_target(target, "choice_timeout", false)

func _start_choice_timer(node: Dictionary) -> void:
	var timer: Dictionary = node.get("choiceTimer", {})
	if typeof(timer) != TYPE_DICTIONARY or not bool(timer.get("enabled", false)):
		_reset_choice_timer(true)
		return
	var duration := _positive_float(timer.get("durationSeconds", 0.0), 0.0)
	if duration <= 0.0:
		_reset_choice_timer(true)
		return
	_choice_timer = {
		"enabled": true,
		"durationSeconds": duration,
		"remainingSeconds": duration,
		"timeoutChoiceTextKey": String(timer.get("timeoutChoiceTextKey", ""))
	}
	_emit_choice_timer_changed()

func _restore_choice_timer(saved_timer: Dictionary) -> void:
	if not bool(_choice_timer.get("enabled", false)):
		return
	if not bool(saved_timer.get("enabled", false)):
		_reset_choice_timer(true)
		return
	var duration := _positive_float(saved_timer.get("durationSeconds", _choice_timer.get("durationSeconds", 0.0)), float(_choice_timer.get("durationSeconds", 0.0)))
	var remaining := _positive_float(saved_timer.get("remainingSeconds", duration), duration)
	_choice_timer["durationSeconds"] = duration
	_choice_timer["remainingSeconds"] = minf(remaining, duration)
	_choice_timer["timeoutChoiceTextKey"] = String(saved_timer.get("timeoutChoiceTextKey", _choice_timer.get("timeoutChoiceTextKey", "")))

func _reset_choice_timer(emit_signal: bool) -> void:
	var was_enabled := bool(_choice_timer.get("enabled", false))
	_choice_timer = {
		"enabled": false,
		"durationSeconds": 0.0,
		"remainingSeconds": 0.0,
		"timeoutChoiceTextKey": ""
	}
	if emit_signal and was_enabled:
		_emit_choice_timer_changed()

func _emit_choice_timer_changed() -> void:
	choice_timer_changed.emit(_choice_timer_payload())

func _choice_timer_payload() -> Dictionary:
	var payload := _choice_timer.duplicate(true)
	payload["nodeId"] = _current_node_id
	return payload

func _positive_float(value, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value) if float(value) > 0.0 else fallback
		_:
			var text := str(value)
			if text.is_valid_float() and float(text) > 0.0:
				return float(text)
	return fallback

func _mark_exhaustive_choice_selected(source_node_id: String, target_node_id: String) -> void:
	if not _node_by_id.has(source_node_id):
		return
	var node: Dictionary = _node_by_id[source_node_id]
	if String(node.get("nodeType", "")) != "Choice":
		return
	if _choice_mode(node) != "ExhaustiveUntilComplete":
		return
	if not _exhausted_choice_targets.has(source_node_id):
		_exhausted_choice_targets[source_node_id] = {}
	var exhausted_targets: Dictionary = _exhausted_choice_targets[source_node_id]
	exhausted_targets[target_node_id] = true

func _push_exhaustive_choice_frame(source_node_id: String) -> void:
	if not _node_by_id.has(source_node_id):
		return
	var node: Dictionary = _node_by_id[source_node_id]
	if String(node.get("nodeType", "")) != "Choice":
		return
	if _choice_mode(node) != "ExhaustiveUntilComplete":
		return
	if not _exhaustive_choice_stack.is_empty() and _exhaustive_choice_stack.back() == source_node_id:
		return
	_exhaustive_choice_stack.append(source_node_id)

func _pop_exhaustive_choice_frame(choice_node_id: String) -> void:
	for i in range(_exhaustive_choice_stack.size() - 1, -1, -1):
		if _exhaustive_choice_stack[i] == choice_node_id:
			_exhaustive_choice_stack.remove_at(i)
			return

func _return_to_exhaustive_choice_if_needed() -> bool:
	if _exhaustive_choice_stack.is_empty():
		return false
	var choice_node_id := String(_exhaustive_choice_stack.back())
	if not _node_by_id.has(choice_node_id):
		_exhaustive_choice_stack.pop_back()
		return false
	_state = STATE_RUNNING
	_paused_event_node_id = ""
	_current_choices.clear()
	_enter_node(choice_node_id)
	return true

func _condition_true(condition: Dictionary) -> Dictionary:
	if condition.is_empty():
		return {"ok": true, "value": true, "error": ""}

	var logic := String(condition.get("logic", "All"))
	if logic != "All":
		return {"ok": false, "value": false, "error": "Unsupported condition logic: %s" % logic}

	var terms: Array = condition.get("terms", [])
	if terms.is_empty():
		return {"ok": true, "value": true, "error": ""}

	for raw_term in terms:
		var term: Dictionary = raw_term
		var term_check := _condition_term_true(term)
		if not term_check.get("ok", false):
			return term_check
		if not bool(term_check.get("value", false)):
			return {"ok": true, "value": false, "error": ""}

	return {"ok": true, "value": true, "error": ""}

func _condition_term_true(term: Dictionary) -> Dictionary:
	var variable_ref: Dictionary = term.get("variable", {})
	var name := _variable_ref_name(variable_ref)
	if name.is_empty():
		return {"ok": false, "value": false, "error": "Condition term has empty variable name"}
	if not _variable_defs.has(name):
		return {"ok": false, "value": false, "error": "Condition variable not defined: %s" % name}

	var def: Dictionary = _variable_defs[name]
	var type_name := String(def.get("type", ""))
	var ref_type := _variable_ref_type(variable_ref)
	if not ref_type.is_empty() and ref_type != type_name:
		return {
			"ok": false,
			"value": false,
			"error": "Condition variable type mismatch for %s: expected %s got %s" % [name, type_name, ref_type]
		}

	var right := _parse_value_for_type(term.get("compareValue", null), type_name)
	if not right.get("ok", false):
		return {"ok": false, "value": false, "error": "Invalid compareValue for %s: %s" % [name, String(right.get("error", "unknown"))]}

	var op := String(term.get("operator", ""))
	var left_value = _variables.get(name)
	var right_value = right.get("value")
	var compare := _compare_values(left_value, right_value, type_name, op)
	if not compare.get("ok", false):
		return compare

	return {"ok": true, "value": compare.get("value", false), "error": ""}

func _normalize_variable_type(type_name: String) -> String:
	match type_name:
		"Bool", "Int", "Float", "String":
			return type_name
		_:
			return ""

func _parse_value_for_type(raw_value, type_name: String) -> Dictionary:
	if raw_value == null:
		match type_name:
			"Bool":
				return {"ok": true, "value": false, "error": ""}
			"Int":
				return {"ok": true, "value": 0, "error": ""}
			"Float":
				return {"ok": true, "value": 0.0, "error": ""}
			"String":
				return {"ok": true, "value": "", "error": ""}

	match type_name:
		"Bool":
			if typeof(raw_value) == TYPE_BOOL:
				return {"ok": true, "value": raw_value, "error": ""}
			var bool_text := str(raw_value).to_lower()
			if bool_text == "true":
				return {"ok": true, "value": true, "error": ""}
			if bool_text == "false":
				return {"ok": true, "value": false, "error": ""}
			return {"ok": false, "value": false, "error": "Expected Bool but got %s" % str(raw_value)}
		"Int":
			if typeof(raw_value) == TYPE_INT:
				return {"ok": true, "value": raw_value, "error": ""}
			if typeof(raw_value) == TYPE_FLOAT and float(raw_value) == floor(float(raw_value)):
				return {"ok": true, "value": int(raw_value), "error": ""}
			var int_text := str(raw_value)
			if int_text.is_valid_int():
				return {"ok": true, "value": int(int_text), "error": ""}
			return {"ok": false, "value": 0, "error": "Expected Int but got %s" % str(raw_value)}
		"Float":
			if typeof(raw_value) == TYPE_FLOAT or typeof(raw_value) == TYPE_INT:
				return {"ok": true, "value": float(raw_value), "error": ""}
			var float_text := str(raw_value)
			if float_text.is_valid_float():
				return {"ok": true, "value": float(float_text), "error": ""}
			return {"ok": false, "value": 0.0, "error": "Expected Float but got %s" % str(raw_value)}
		"String":
			return {"ok": true, "value": str(raw_value), "error": ""}

	return {"ok": false, "value": null, "error": "Unsupported variable type: %s" % type_name}

func _default_value_for_variable(variable: Dictionary, type_name: String):
	if variable.has("defaultValue"):
		return variable.get("defaultValue")
	match type_name:
		"Bool":
			if variable.has("boolValue"):
				return variable.get("boolValue")
		"Int":
			if variable.has("intValue"):
				return variable.get("intValue")
		"Float":
			if variable.has("floatValue"):
				return variable.get("floatValue")
		"String":
			if variable.has("stringValue"):
				return variable.get("stringValue")
	return null

func _variable_ref_name(variable_ref: Dictionary) -> String:
	var name := String(variable_ref.get("name", ""))
	if name.is_empty():
		name = String(variable_ref.get("variableName", ""))
	return name

func _variable_ref_type(variable_ref: Dictionary) -> String:
	var raw_type := String(variable_ref.get("type", ""))
	if raw_type.is_empty():
		raw_type = String(variable_ref.get("variableType", ""))
	return _normalize_variable_type(raw_type)

func _compare_values(left_value, right_value, type_name: String, op: String) -> Dictionary:
	match type_name:
		"Bool":
			return _compare_ordered(int(bool(left_value)), int(bool(right_value)), op)
		"Int":
			return _compare_ordered(int(left_value), int(right_value), op)
		"Float":
			return _compare_ordered(float(left_value), float(right_value), op)
		"String":
			var string_order := String(left_value).casecmp_to(String(right_value))
			return _compare_ordered(string_order, 0, op)

	return {
		"ok": false,
		"value": false,
		"error": "Unsupported operator for %s: %s" % [type_name, op]
	}

func _compare_ordered(left_value, right_value, op: String) -> Dictionary:
	match op:
		"==":
			return {"ok": true, "value": left_value == right_value, "error": ""}
		"!=":
			return {"ok": true, "value": left_value != right_value, "error": ""}
		">":
			return {"ok": true, "value": left_value > right_value, "error": ""}
		">=":
			return {"ok": true, "value": left_value >= right_value, "error": ""}
		"<":
			return {"ok": true, "value": left_value < right_value, "error": ""}
		"<=":
			return {"ok": true, "value": left_value <= right_value, "error": ""}
		_:
			return {"ok": false, "value": false, "error": "Unsupported operator: %s" % op}

func _execute_exit_actions(node_id: String) -> Dictionary:
	if not _node_by_id.has(node_id):
		return {"ok": false, "error": "Cannot execute exit actions for missing node: %s" % node_id}
	var node: Dictionary = _node_by_id[node_id]
	return _execute_actions(node.get("exitActions", []), "exit", node_id)

func _execute_actions(actions: Array, phase: String, node_id: String) -> Dictionary:
	for raw_action in actions:
		var action: Dictionary = raw_action
		var result := _execute_action(action, phase, node_id)
		if not result.get("ok", false):
			return result
	return {"ok": true, "error": ""}

func _execute_action(action: Dictionary, phase: String, node_id: String) -> Dictionary:
	var action_type := String(action.get("actionType", ""))
	match action_type:
		"Set":
			return _execute_variable_action(action, phase, node_id, action_type)
		"Add":
			return _execute_variable_action(action, phase, node_id, action_type)
		"Subtract":
			return _execute_variable_action(action, phase, node_id, action_type)
		"EmitEvent":
			return _execute_emit_event_action(action, phase, node_id)
		_:
			return {
				"ok": false,
				"error": "Unsupported actionType on node %s: %s" % [node_id, action_type]
			}

func _execute_variable_action(action: Dictionary, phase: String, node_id: String, action_type: String) -> Dictionary:
	var variable_ref: Dictionary = action.get("variable", {})
	var name := _variable_ref_name(variable_ref)
	if name.is_empty():
		return {"ok": false, "error": "%s action has empty variable name on node %s" % [action_type, node_id]}
	if not _variable_defs.has(name):
		return {"ok": false, "error": "%s action references undefined variable on node %s: %s" % [action_type, node_id, name]}

	var def: Dictionary = _variable_defs[name]
	var type_name := String(def.get("type", ""))
	var ref_type := _variable_ref_type(variable_ref)
	if variable_ref.has("type") and not ref_type.is_empty() and ref_type != type_name:
		return {
			"ok": false,
			"error": "%s action variable type mismatch for %s on node %s: expected %s got %s" % [
				action_type,
				name,
				node_id,
				type_name,
				ref_type
			]
		}

	var parsed := _parse_value_for_type(action.get("value", null), type_name)
	if not parsed.get("ok", false):
		return {
			"ok": false,
			"error": "Invalid %s action value for %s on node %s: %s" % [
				action_type,
				name,
				node_id,
				String(parsed.get("error", "unknown"))
			]
		}

	var old_value = _variables.get(name)
	var operand = parsed.get("value")
	var new_value = old_value
	match action_type:
		"Set":
			new_value = operand
		"Add":
			if type_name != "Int" and type_name != "Float":
				return {"ok": false, "error": "Add action only supports Int/Float variables: %s" % name}
			new_value = old_value + operand
		"Subtract":
			if type_name != "Int" and type_name != "Float":
				return {"ok": false, "error": "Subtract action only supports Int/Float variables: %s" % name}
			new_value = old_value - operand

	_variables[name] = new_value
	var payload := {
		"nodeId": node_id,
		"phase": phase,
		"actionType": action_type,
		"name": name,
		"type": type_name,
		"oldValue": old_value,
		"newValue": new_value
	}
	_trace("variable", TRACE_LEVEL_INFO, payload)
	variable_changed.emit(payload)
	return {"ok": true, "error": ""}

func _execute_emit_event_action(action: Dictionary, phase: String, node_id: String) -> Dictionary:
	return _emit_structured_event(action, phase, node_id, "action")

func _execute_emit_event_node(node: Dictionary) -> Dictionary:
	var node_id := String(node.get("nodeId", ""))
	return _emit_structured_event(node, "node", node_id, "node")

func _emit_structured_event(data: Dictionary, phase: String, node_id: String, source: String) -> Dictionary:
	var payload_check := _build_event_payload(data, phase, node_id, source)
	if not payload_check.get("ok", false):
		return payload_check
	var payload: Dictionary = payload_check.get("payload", {})
	_emitted_events.append(payload)
	_trace("event", TRACE_LEVEL_INFO, payload)
	event_emitted.emit(payload)
	return {"ok": true, "error": ""}

func _build_event_payload(data: Dictionary, phase: String, node_id: String, source: String) -> Dictionary:
	var event_type := String(data.get("eventType", "")).strip_edges()
	if data.has("eventId"):
		return {"ok": false, "error": "EmitEvent %s eventId is no longer supported on node %s" % [source, node_id]}
	if event_type.is_empty():
		return {"ok": false, "error": "EmitEvent %s has empty eventType on node %s" % [source, node_id]}
	if data.has("params") and typeof(data.get("params")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "EmitEvent %s params must be an object on node %s" % [source, node_id]}
	var params: Dictionary = {}
	if data.has("params"):
		params = (data.get("params") as Dictionary).duplicate(true)
	return {
		"ok": true,
		"error": "",
		"payload": {
			"nodeId": node_id,
			"phase": phase,
			"eventType": event_type,
			"params": params
		}
	}

func _resolve_condition_node_target(node: Dictionary) -> Dictionary:
	var node_id := String(node.get("nodeId", ""))
	var condition_data: Dictionary = node.get("condition", {})
	var branches: Array = condition_data.get("branches", [])
	for i in range(branches.size()):
		var branch: Dictionary = branches[i]
		var check := _condition_true(branch)
		if not check.get("ok", false):
			return {"ok": false, "targetNodeId": "", "error": "Condition branch failed on node %s at index %d: %s" % [
				node_id,
				i,
				String(check.get("error", "unknown"))
			]}
		if bool(check.get("value", false)):
			return _target_for_source_handle(node_id, "condition-%d" % i)

	var fallback := _target_for_source_handle(node_id, "condition-fallback")
	if fallback.get("ok", false):
		return fallback
	return {"ok": true, "targetNodeId": "", "error": ""}

func _target_for_source_handle(source_node_id: String, source_handle: String) -> Dictionary:
	var edges: Array = _out_edges.get(source_node_id, [])
	for edge in edges:
		var e: Dictionary = edge
		if String(e.get("sourceHandle", "")) == source_handle:
			return {"ok": true, "targetNodeId": String(e.get("targetNodeId", "")), "error": ""}
	return {"ok": false, "targetNodeId": "", "error": "No edge found from %s with sourceHandle: %s" % [source_node_id, source_handle]}

func _finish() -> void:
	if _return_to_exhaustive_choice_if_needed():
		return
	_state = STATE_ENDED
	_paused_event_node_id = ""
	_current_choices.clear()
	_reset_choice_timer(true)
	_trace("ended", TRACE_LEVEL_INFO, {})
	ended.emit()

func _emit_error(message: String) -> void:
	_state = STATE_ENDED
	_paused_event_node_id = ""
	_current_choices.clear()
	_reset_choice_timer(true)
	_trace("error", TRACE_LEVEL_ERROR, {"message": message})
	error_raised.emit(message)

func _trace(event_type: String, level: int, data: Dictionary) -> void:
	if not _trace_enabled:
		return
	if level > _trace_level:
		return

	var payload := data.duplicate(true)
	payload["eventType"] = event_type
	payload["level"] = level
	payload["state"] = _state
	payload["nodeId"] = _current_node_id
	payload["storyId"] = String(_story.get("meta", {}).get("storyId", ""))
	_trace_records.append(payload)
	trace_logged.emit(payload)
