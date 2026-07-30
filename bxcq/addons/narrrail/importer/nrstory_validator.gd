class_name NarrRailStoryValidator
extends RefCounted

# Diagnostic shape:
# {
#   severity: "error" | "warning",
#   code: String,
#   path: String,
#   message: String,
#   suggestion: String
# }

static func validate_story(story: Dictionary) -> Array:
	var diagnostics: Array = []

	var nodes: Array = story.get("nodes", [])
	var edges: Array = story.get("edges", [])
	var meta: Dictionary = story.get("meta", {})

	# Collect node ids
	var node_ids: Dictionary = {}
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var node_id := String(node.get("nodeId", ""))
		if node_id.is_empty():
			diagnostics.append(_diag("error", "NODE_ID_EMPTY", "nodes[%d].nodeId" % i, "nodeId must not be empty", "Assign a unique non-empty nodeId."))
			continue
		if node_ids.has(node_id):
			diagnostics.append(_diag("error", "NODE_ID_DUPLICATE", "nodes[%d].nodeId" % i, "Duplicate nodeId: %s" % node_id, "Rename this nodeId or merge duplicate nodes."))
		else:
			node_ids[node_id] = true

	# entryNodeId existence
	var entry_id := String(meta.get("entryNodeId", ""))
	if not entry_id.is_empty() and not node_ids.has(entry_id):
		diagnostics.append(_diag("error", "ENTRY_NOT_FOUND", "meta.entryNodeId", "entryNodeId not found in nodes: %s" % entry_id, "Point entryNodeId to an existing nodeId."))

	# Edge refs
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		var s := String(edge.get("sourceNodeId", ""))
		var t := String(edge.get("targetNodeId", ""))
		if s.is_empty():
			diagnostics.append(_diag("error", "EDGE_SOURCE_EMPTY", "edges[%d].sourceNodeId" % i, "sourceNodeId must not be empty", "Set sourceNodeId to an existing source node."))
		elif not node_ids.has(s):
			diagnostics.append(_diag("error", "EDGE_SOURCE_NOT_FOUND", "edges[%d].sourceNodeId" % i, "sourceNodeId not found: %s" % s, "Create the source node or update sourceNodeId."))
		if t.is_empty():
			diagnostics.append(_diag("error", "EDGE_TARGET_EMPTY", "edges[%d].targetNodeId" % i, "targetNodeId must not be empty", "Set targetNodeId to an existing target node."))
		elif not node_ids.has(t):
			diagnostics.append(_diag("error", "EDGE_TARGET_NOT_FOUND", "edges[%d].targetNodeId" % i, "targetNodeId not found: %s" % t, "Create the target node or update targetNodeId."))

	# Choice target refs
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		if String(node.get("nodeType", "")) != "Choice":
			continue
		var choices: Array = node.get("choices", [])
		for j in range(choices.size()):
			var choice: Dictionary = choices[j]
			var target := String(choice.get("targetNodeId", ""))
			if target.is_empty():
				diagnostics.append(_diag("error", "CHOICE_TARGET_EMPTY", "nodes[%d].choices[%d].targetNodeId" % [i, j], "Choice targetNodeId must not be empty", "Set the choice targetNodeId to an existing node."))
			elif not node_ids.has(target):
				diagnostics.append(_diag("error", "CHOICE_TARGET_NOT_FOUND", "nodes[%d].choices[%d].targetNodeId" % [i, j], "Choice target not found: %s" % target, "Create the target node or update this choice targetNodeId."))
		diagnostics.append_array(_validate_choice_timer(node, i, edges, node_ids))

	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var node_type := String(node.get("nodeType", ""))
		if node_type == "EmitEvent":
			diagnostics.append_array(_validate_emit_event_fields(node, "nodes[%d]" % i, false))
		diagnostics.append_array(_validate_node_actions(node, i))

	# Orphan node warning (exclude entry)
	var incoming: Dictionary = {}
	for edge in edges:
		var t := String((edge as Dictionary).get("targetNodeId", ""))
		if not t.is_empty():
			incoming[t] = true

	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var node_id := String(node.get("nodeId", ""))
		if node_id.is_empty() or node_id == entry_id:
			continue
		if not incoming.has(node_id):
			diagnostics.append(_diag("warning", "NODE_ORPHAN", "nodes[%d].nodeId" % i, "Orphan node (no incoming edge): %s" % node_id, "Connect this node from another node or remove it if unused."))

	return diagnostics

static func _validate_node_actions(node: Dictionary, node_index: int) -> Array:
	var diagnostics: Array = []
	for field in ["enterActions", "exitActions", "actions"]:
		var actions = node.get(field, [])
		if typeof(actions) != TYPE_ARRAY:
			continue
		for i in range((actions as Array).size()):
			var action: Dictionary = (actions as Array)[i]
			var action_type := String(action.get("actionType", ""))
			var path := "nodes[%d].%s[%d]" % [node_index, field, i]
			match action_type:
				"Set", "Add", "Subtract":
					var variable: Dictionary = action.get("variable", {})
					var variable_name := _variable_ref_name(variable)
					if variable_name.is_empty():
						diagnostics.append(_diag("error", "ACTION_VARIABLE_EMPTY", "%s.variable" % path, "%s action variable must not be empty" % action_type, "Set variable.name or variable.variableName to an existing variable."))
					if not action.has("value"):
						diagnostics.append(_diag("error", "ACTION_VALUE_MISSING", "%s.value" % path, "%s action value is required" % action_type, "Set value to the mutation operand for this action."))
				"EmitEvent":
					diagnostics.append_array(_validate_emit_event_fields(action, path, true))
				_:
					diagnostics.append(_diag("error", "ACTION_TYPE_UNSUPPORTED", "%s.actionType" % path, "Unsupported actionType: %s" % action_type, "Use Set, Add, Subtract, or EmitEvent."))
	return diagnostics

static func _validate_emit_event_fields(data: Dictionary, path: String, is_action: bool) -> Array:
	var diagnostics: Array = []
	var event_type := String(data.get("eventType", "")).strip_edges()
	if data.has("eventId"):
		var unsupported_code := "ACTION_EVENT_ID_UNSUPPORTED" if is_action else "EMIT_EVENT_ID_UNSUPPORTED"
		diagnostics.append(_diag("error", unsupported_code, "%s.eventId" % path, "EmitEvent eventId is no longer supported", "Use eventType and params."))
	if event_type.is_empty():
		if is_action:
			diagnostics.append(_diag("error", "ACTION_EVENT_TYPE_EMPTY", "%s.eventType" % path, "EmitEvent action eventType must not be empty", "Set eventType to the structured event type emitted by this action."))
		else:
			diagnostics.append(_diag("error", "EMIT_EVENT_TYPE_EMPTY", "%s.eventType" % path, "EmitEvent node eventType must not be empty", "Set eventType to the structured event type emitted by this node."))
	if data.has("params") and typeof(data.get("params")) != TYPE_DICTIONARY:
		var code := "ACTION_EVENT_PARAMS_TYPE_INVALID" if is_action else "EMIT_EVENT_PARAMS_TYPE_INVALID"
		var label := "action" if is_action else "node"
		diagnostics.append(_diag("error", code, "%s.params" % path, "EmitEvent %s params must be an object" % label, "Use a mapping/object for params, or omit params for an empty object."))
	return diagnostics

static func _variable_ref_name(variable_ref: Dictionary) -> String:
	var name := String(variable_ref.get("name", ""))
	if name.is_empty():
		name = String(variable_ref.get("variableName", ""))
	return name

static func _validate_choice_timer(node: Dictionary, node_index: int, edges: Array, node_ids: Dictionary) -> Array:
	var diagnostics: Array = []
	var timer = node.get("choiceTimer", {})
	var enabled := false
	if typeof(timer) == TYPE_DICTIONARY:
		enabled = bool((timer as Dictionary).get("enabled", false))

	var node_id := String(node.get("nodeId", ""))
	var timeout_edges: Array = []
	for edge in edges:
		var e: Dictionary = edge
		if String(e.get("sourceNodeId", "")) == node_id and String(e.get("sourceHandle", "")) == "choice-timeout":
			timeout_edges.append(e)

	if not enabled:
		if not timeout_edges.is_empty():
			diagnostics.append(_diag("warning", "CHOICE_TIMER_EDGE_UNUSED", "nodes[%d].choiceTimer" % node_index, "Choice has choice-timeout edge but choiceTimer is disabled: %s" % node_id, "Enable choiceTimer or remove the choice-timeout edge."))
		return diagnostics

	if typeof(timer) != TYPE_DICTIONARY:
		diagnostics.append(_diag("error", "CHOICE_TIMER_TYPE_INVALID", "nodes[%d].choiceTimer" % node_index, "choiceTimer must be an object when enabled", "Use choiceTimer.enabled, durationSeconds, and timeoutChoiceTextKey."))
		return diagnostics

	var timer_dict: Dictionary = timer
	var duration = timer_dict.get("durationSeconds", 0)
	var duration_ok := false
	match typeof(duration):
		TYPE_INT, TYPE_FLOAT:
			duration_ok = float(duration) > 0.0
		_:
			duration_ok = str(duration).is_valid_float() and float(str(duration)) > 0.0
	if not duration_ok:
		diagnostics.append(_diag("error", "CHOICE_TIMER_DURATION_INVALID", "nodes[%d].choiceTimer.durationSeconds" % node_index, "Choice timer durationSeconds must be greater than 0", "Set durationSeconds to a positive number."))

	if String(timer_dict.get("timeoutChoiceTextKey", "")).strip_edges().is_empty():
		diagnostics.append(_diag("error", "CHOICE_TIMER_TEXT_EMPTY", "nodes[%d].choiceTimer.timeoutChoiceTextKey" % node_index, "Choice timer timeoutChoiceTextKey must not be empty", "Set display text for the timeout choice."))

	if timeout_edges.is_empty():
		diagnostics.append(_diag("error", "CHOICE_TIMER_EDGE_MISSING", "nodes[%d].choiceTimer" % node_index, "Enabled choice timer is missing choice-timeout edge: %s" % node_id, "Connect one edge with sourceHandle: choice-timeout."))
	elif timeout_edges.size() > 1:
		diagnostics.append(_diag("error", "CHOICE_TIMER_EDGE_DUPLICATE", "nodes[%d].choiceTimer" % node_index, "Enabled choice timer has multiple choice-timeout edges: %s" % node_id, "Keep exactly one choice-timeout edge."))

	for edge in timeout_edges:
		var target := String((edge as Dictionary).get("targetNodeId", ""))
		if target.is_empty():
			diagnostics.append(_diag("error", "CHOICE_TIMER_TARGET_EMPTY", "nodes[%d].choiceTimer" % node_index, "Choice timer targetNodeId must not be empty", "Set the choice-timeout edge target."))
		elif not node_ids.has(target):
			diagnostics.append(_diag("error", "CHOICE_TIMER_TARGET_NOT_FOUND", "nodes[%d].choiceTimer" % node_index, "Choice timer target not found: %s" % target, "Create the target node or update the choice-timeout edge."))

	return diagnostics

static func _diag(severity: String, code: String, path: String, message: String, suggestion: String) -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"path": path,
		"message": message,
		"suggestion": suggestion
	}

static func has_errors(diagnostics: Array) -> bool:
	for d in diagnostics:
		if String((d as Dictionary).get("severity", "")) == "error":
			return true
	return false
