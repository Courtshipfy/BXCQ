class_name NarrRailStoryModel
extends RefCounted

static func validate_minimal(story: Dictionary) -> Dictionary:
	var errors: Array[String] = []

	for key in ["meta", "variables", "nodes", "edges"]:
		if not story.has(key):
			errors.append("Missing required root field: %s" % key)

	if errors.size() > 0:
		return {"ok": false, "errors": errors}

	var meta: Dictionary = story.get("meta", {})
	if int(meta.get("schemaVersion", 0)) != 1:
		errors.append("Unsupported meta.schemaVersion: %s" % String(meta.get("schemaVersion", "")))
	if not meta.has("entryNodeId"):
		errors.append("Missing meta.entryNodeId")

	var variable_names: Dictionary = {}
	for v in story.get("variables", []):
		var var_name := String(v.get("name", ""))
		if var_name.is_empty():
			errors.append("Variable with empty name")
			continue
		if variable_names.has(var_name):
			errors.append("Duplicate variable name: %s" % var_name)
		else:
			variable_names[var_name] = true

	var node_ids: Dictionary = {}
	for n in story.get("nodes", []):
		var node_id := String(n.get("nodeId", ""))
		if node_id.is_empty():
			errors.append("Node with empty nodeId")
			continue
		if node_ids.has(node_id):
			errors.append("Duplicate nodeId: %s" % node_id)
		else:
			node_ids[node_id] = true

	var entry_id := String(meta.get("entryNodeId", ""))
	if not entry_id.is_empty() and not node_ids.has(entry_id):
		errors.append("entryNodeId not found in nodes: %s" % entry_id)

	for e in story.get("edges", []):
		var s := String(e.get("sourceNodeId", ""))
		var t := String(e.get("targetNodeId", ""))
		if s.is_empty() or t.is_empty():
			errors.append("Edge has empty source/target")
			continue
		if not node_ids.has(s):
			errors.append("Edge source not found: %s" % s)
		if not node_ids.has(t):
			errors.append("Edge target not found: %s" % t)

	for n in story.get("nodes", []):
		var node_type := String(n.get("nodeType", ""))
		if not ["Dialogue", "MultiDialogue", "Choice", "Jump", "SetVariable", "Condition", "EmitEvent", "End"].has(node_type):
			errors.append("Unsupported nodeType on node %s: %s" % [String(n.get("nodeId", "")), node_type])
		if node_type != "Choice":
			if node_type == "MultiDialogue":
				_validate_multi_dialogue(n, errors)
			if node_type == "Jump":
				var jump_target := String(n.get("jumpTargetNodeId", ""))
				var jump_node_id := String(n.get("nodeId", ""))
				if jump_target.is_empty():
					errors.append("Jump target is empty on node: %s" % jump_node_id)
				elif not node_ids.has(jump_target):
					errors.append("Jump target not found on node %s: %s" % [jump_node_id, jump_target])
			if node_type == "EmitEvent":
				_validate_emit_event_fields(n, String(n.get("nodeId", "")), "node", errors)
			_validate_node_actions(n, variable_names, errors)
			continue
		var source_node_id := String(n.get("nodeId", ""))
		var choice_mode := String(n.get("choiceMode", "SinglePass"))
		if choice_mode != "SinglePass" and choice_mode != "ExhaustiveUntilComplete":
			errors.append("Unsupported choiceMode on node %s: %s" % [source_node_id, choice_mode])
		if choice_mode == "ExhaustiveUntilComplete":
			var completion_target := String(n.get("choiceCompletionTargetNodeId", ""))
			if completion_target.is_empty():
				errors.append("Exhaustive choice missing choiceCompletionTargetNodeId on node: %s" % source_node_id)
			elif not node_ids.has(completion_target):
				errors.append("Exhaustive choice completion target not found on node %s: %s" % [source_node_id, completion_target])
		_validate_choice_timer(n, story.get("edges", []), node_ids, errors)
		for c in n.get("choices", []):
			var target := String(c.get("targetNodeId", ""))
			if target.is_empty():
				errors.append("Choice target is empty on node: %s" % source_node_id)
				continue
			if not node_ids.has(target):
				errors.append("Choice target not found on node %s: %s" % [source_node_id, target])
		_validate_node_actions(n, variable_names, errors)

	return {"ok": errors.is_empty(), "errors": errors}

static func _validate_multi_dialogue(node: Dictionary, errors: Array[String]) -> void:
	var node_id := String(node.get("nodeId", ""))
	var multi_dialogue: Dictionary = node.get("multiDialogue", {})
	var lines: Array = multi_dialogue.get("lines", [])
	if lines.is_empty():
		errors.append("MultiDialogue node has no lines: %s" % node_id)
		return
	for i in range(lines.size()):
		var line: Dictionary = lines[i]
		if not line.has("textKey"):
			errors.append("MultiDialogue line missing textKey on node %s at index %d" % [node_id, i])

static func _validate_choice_timer(node: Dictionary, edges: Array, node_ids: Dictionary, errors: Array[String]) -> void:
	var timer = node.get("choiceTimer", {})
	if typeof(timer) != TYPE_DICTIONARY or not bool((timer as Dictionary).get("enabled", false)):
		return
	var timer_dict: Dictionary = timer
	var node_id := String(node.get("nodeId", ""))
	var duration = timer_dict.get("durationSeconds", 0)
	var duration_ok := false
	match typeof(duration):
		TYPE_INT, TYPE_FLOAT:
			duration_ok = float(duration) > 0.0
		_:
			duration_ok = str(duration).is_valid_float() and float(str(duration)) > 0.0
	if not duration_ok:
		errors.append("Choice timer durationSeconds must be greater than 0 on node: %s" % node_id)
	if String(timer_dict.get("timeoutChoiceTextKey", "")).strip_edges().is_empty():
		errors.append("Choice timer timeoutChoiceTextKey is empty on node: %s" % node_id)

	var timeout_edges: Array = []
	for edge in edges:
		var e: Dictionary = edge
		if String(e.get("sourceNodeId", "")) == node_id and String(e.get("sourceHandle", "")) == "choice-timeout":
			timeout_edges.append(e)
	if timeout_edges.is_empty():
		errors.append("Choice timer missing choice-timeout edge on node: %s" % node_id)
	elif timeout_edges.size() > 1:
		errors.append("Choice timer has multiple choice-timeout edges on node: %s" % node_id)
	for edge in timeout_edges:
		var target := String((edge as Dictionary).get("targetNodeId", ""))
		if target.is_empty():
			errors.append("Choice timer target is empty on node: %s" % node_id)
		elif not node_ids.has(target):
			errors.append("Choice timer target not found on node %s: %s" % [node_id, target])

static func _validate_node_actions(node: Dictionary, variable_names: Dictionary, errors: Array[String]) -> void:
	var node_id := String(node.get("nodeId", ""))
	for field in ["enterActions", "exitActions", "actions"]:
		for a in node.get(field, []):
			var action: Dictionary = a
			var action_type := String(action.get("actionType", ""))
			match action_type:
				"Set", "Add", "Subtract":
					var variable: Dictionary = action.get("variable", {})
					var name := _variable_ref_name(variable)
					if name.is_empty():
						errors.append("%s action has empty variable name on node: %s" % [action_type, node_id])
					elif not variable_names.has(name):
						errors.append("%s action variable not found on node %s: %s" % [action_type, node_id, name])
					if not action.has("value"):
						errors.append("%s action missing value on node: %s" % [action_type, node_id])
				"EmitEvent":
					_validate_emit_event_fields(action, node_id, "action", errors)
				_:
					errors.append("Unsupported actionType on node %s: %s" % [node_id, action_type])

static func _variable_ref_name(variable_ref: Dictionary) -> String:
	var name := String(variable_ref.get("name", ""))
	if name.is_empty():
		name = String(variable_ref.get("variableName", ""))
	return name

static func _validate_emit_event_fields(data: Dictionary, node_id: String, source: String, errors: Array[String]) -> void:
	var event_type := String(data.get("eventType", "")).strip_edges()
	if data.has("eventId"):
		errors.append("EmitEvent %s eventId is no longer supported on node: %s" % [source, node_id])
	if event_type.is_empty():
		errors.append("EmitEvent %s missing eventType on node: %s" % [source, node_id])
	if data.has("params") and typeof(data.get("params")) != TYPE_DICTIONARY:
		errors.append("EmitEvent %s params must be an object on node: %s" % [source, node_id])
