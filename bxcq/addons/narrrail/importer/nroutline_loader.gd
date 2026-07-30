class_name NarrRailOutlineLoader
extends RefCounted

const SUPPORTED_SCHEMA_VERSION := 1
const NRSTORY_LOADER_SCRIPT := "res://addons/narrrail/importer/nrstory_loader.gd"

static func load_outline(path: String, known_story_ids: Array = []) -> Dictionary:
	var story_loader: Script = load(NRSTORY_LOADER_SCRIPT)
	if story_loader == null:
		return _fail([
			_diag("error", "LOADER_MISSING", "$", "Failed to load NarrRail story loader", -1)
		])

	var parsed: Dictionary = story_loader.call("load_document", path)
	if not parsed.get("ok", false):
		return parsed

	var outline: Dictionary = parsed.get("data", {})
	var diagnostics: Array = _validate_outline(outline, known_story_ids)
	if _has_errors(diagnostics):
		return _fail(diagnostics)

	return {
		"ok": true,
		"outline": outline,
		"error": "",
		"diagnostics": diagnostics
	}

static func _validate_outline(outline: Dictionary, known_story_ids: Array = []) -> Array:
	var diagnostics: Array = []

	if not outline.has("meta"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta", "Missing required field: meta", -1))
	elif typeof(outline.get("meta")) != TYPE_DICTIONARY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "meta", "meta must be an object", -1))

	if not outline.has("nodes"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "nodes", "Missing required field: nodes", -1))
	elif typeof(outline.get("nodes")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "nodes", "nodes must be an array", -1))

	if not outline.has("edges"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "edges", "Missing required field: edges", -1))
	elif typeof(outline.get("edges")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "edges", "edges must be an array", -1))

	if _has_errors(diagnostics):
		return diagnostics

	var meta: Dictionary = outline.get("meta", {})
	if not meta.has("schemaVersion"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta.schemaVersion", "Missing required field: meta.schemaVersion", -1))
	elif typeof(meta.get("schemaVersion")) != TYPE_INT:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "meta.schemaVersion", "schemaVersion must be int", -1))
	elif int(meta.get("schemaVersion")) > SUPPORTED_SCHEMA_VERSION:
		diagnostics.append(_diag("error", "SCHEMA_UNSUPPORTED", "meta.schemaVersion", "Unsupported future schemaVersion: %d (supported <= %d)" % [int(meta.get("schemaVersion")), SUPPORTED_SCHEMA_VERSION], -1))

	if String(meta.get("railId", "")).strip_edges().is_empty():
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta.railId", "Missing required field: meta.railId", -1))
	if String(meta.get("entryNodeId", "")).strip_edges().is_empty():
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta.entryNodeId", "Missing required field: meta.entryNodeId", -1))

	var nodes: Array = outline.get("nodes", [])
	var edges: Array = outline.get("edges", [])
	var node_ids: Dictionary = {}
	var outgoing: Dictionary = {}
	var story_id_set := _story_id_set(known_story_ids)

	for i in range(nodes.size()):
		if typeof(nodes[i]) != TYPE_DICTIONARY:
			diagnostics.append(_diag("error", "TYPE_MISMATCH", "nodes[%d]" % i, "Outline node must be an object", -1))
			continue
		var node: Dictionary = nodes[i]
		var node_id := String(node.get("nodeId", "")).strip_edges()
		if node_id.is_empty():
			diagnostics.append(_diag("error", "NODE_ID_EMPTY", "nodes[%d].nodeId" % i, "Outline nodeId must not be empty", -1))
			continue
		if node_ids.has(node_id):
			diagnostics.append(_diag("error", "NODE_ID_DUPLICATE", "nodes[%d].nodeId" % i, "Duplicate outline nodeId: %s" % node_id, -1))
		node_ids[node_id] = true

	var entry_id := String(meta.get("entryNodeId", ""))
	if not entry_id.is_empty() and not node_ids.has(entry_id):
		diagnostics.append(_diag("error", "ENTRY_NOT_FOUND", "meta.entryNodeId", "entryNodeId not found in outline nodes: %s" % entry_id, -1))

	for i in range(edges.size()):
		if typeof(edges[i]) != TYPE_DICTIONARY:
			diagnostics.append(_diag("error", "TYPE_MISMATCH", "edges[%d]" % i, "Outline edge must be an object", -1))
			continue
		var edge: Dictionary = edges[i]
		var source := String(edge.get("sourceNodeId", ""))
		var target := String(edge.get("targetNodeId", ""))
		if source.is_empty() or target.is_empty():
			diagnostics.append(_diag("error", "EDGE_ENDPOINT_EMPTY", "edges[%d]" % i, "Outline edge sourceNodeId and targetNodeId must not be empty", -1))
			continue
		if not node_ids.has(source):
			diagnostics.append(_diag("error", "EDGE_SOURCE_NOT_FOUND", "edges[%d].sourceNodeId" % i, "Outline edge source not found: %s" % source, -1))
		if not node_ids.has(target):
			diagnostics.append(_diag("error", "EDGE_TARGET_NOT_FOUND", "edges[%d].targetNodeId" % i, "Outline edge target not found: %s" % target, -1))
		if not outgoing.has(source):
			outgoing[source] = []
		outgoing[source].append(edge)

	for i in range(nodes.size()):
		if typeof(nodes[i]) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = nodes[i]
		var node_id := String(node.get("nodeId", ""))
		var node_type := String(node.get("nodeType", ""))
		match node_type:
			"Story":
				var story_id := String(node.get("storyId", "")).strip_edges()
				if story_id.is_empty():
					diagnostics.append(_diag("error", "STORY_ID_EMPTY", "nodes[%d].storyId" % i, "Story outline node has empty storyId: %s" % node_id, -1))
				elif not story_id_set.is_empty() and not story_id_set.has(story_id):
					diagnostics.append(_diag("error", "STORY_ID_NOT_FOUND", "nodes[%d].storyId" % i, "Story outline node references missing storyId: %s" % story_id, -1))
			"Branch":
				_validate_branch_node(node, i, outgoing.get(node_id, []), diagnostics)
			"Note", "End":
				pass
			_:
				diagnostics.append(_diag("error", "NODE_TYPE_UNSUPPORTED", "nodes[%d].nodeType" % i, "Unsupported outline nodeType: %s" % node_type, -1))

		if node_type != "End" and not outgoing.has(node_id):
			diagnostics.append(_diag("warning", "OUTLINE_NODE_NO_OUTGOING", "nodes[%d]" % i, "Non-End outline node has no outgoing edge: %s" % node_id, -1))

	_validate_reachability(entry_id, nodes, outgoing, diagnostics)
	return diagnostics

static func _validate_branch_node(node: Dictionary, node_index: int, edges: Array, diagnostics: Array) -> void:
	var node_id := String(node.get("nodeId", ""))
	if typeof(node.get("branches", [])) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "BRANCHES_TYPE_INVALID", "nodes[%d].branches" % node_index, "Branch node branches must be an array: %s" % node_id, -1))
		return
	var branches: Array = node.get("branches", [])

	var usable_outlet_count := 0
	for edge in edges:
		var source_handle := String((edge as Dictionary).get("sourceHandle", ""))
		if source_handle == "branch-fallback":
			usable_outlet_count += 1
			continue
		if source_handle.begins_with("branch-"):
			var index_text := source_handle.trim_prefix("branch-")
			if not index_text.is_valid_int() or int(index_text) < 0 or int(index_text) >= branches.size():
				diagnostics.append(_diag("error", "BRANCH_HANDLE_INVALID", "nodes[%d]" % node_index, "Branch node %s has invalid sourceHandle: %s" % [node_id, source_handle], -1))
			else:
				usable_outlet_count += 1

	if usable_outlet_count == 0:
		diagnostics.append(_diag("error", "BRANCH_OUTLET_MISSING", "nodes[%d]" % node_index, "Branch node has no usable outgoing edge: %s" % node_id, -1))

	var has_fallback := false
	for edge in edges:
		if String((edge as Dictionary).get("sourceHandle", "")) == "branch-fallback":
			has_fallback = true
			break
	if not has_fallback:
		diagnostics.append(_diag("warning", "BRANCH_FALLBACK_MISSING", "nodes[%d]" % node_index, "Branch node has no branch-fallback edge: %s" % node_id, -1))

static func _validate_reachability(entry_id: String, nodes: Array, outgoing: Dictionary, diagnostics: Array) -> void:
	if entry_id.is_empty():
		return
	var reachable := {entry_id: true}
	var queue: Array[String] = [entry_id]
	while not queue.is_empty():
		var current := queue.pop_front()
		for edge in outgoing.get(current, []):
			var target := String((edge as Dictionary).get("targetNodeId", ""))
			if target.is_empty() or reachable.has(target):
				continue
			reachable[target] = true
			queue.append(target)

	for i in range(nodes.size()):
		if typeof(nodes[i]) != TYPE_DICTIONARY:
			continue
		var node_id := String((nodes[i] as Dictionary).get("nodeId", ""))
		if not node_id.is_empty() and not reachable.has(node_id):
			diagnostics.append(_diag("warning", "OUTLINE_NODE_UNREACHABLE", "nodes[%d]" % i, "Unreachable outline node: %s" % node_id, -1))

static func _story_id_set(known_story_ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for id in known_story_ids:
		var story_id := String(id)
		if not story_id.is_empty():
			out[story_id] = true
	return out

static func _diag(severity: String, code: String, path: String, message: String, line: int) -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"path": path,
		"message": message,
		"suggestion": "",
		"line": line
	}

static func _fail(diagnostics: Array) -> Dictionary:
	return {
		"ok": false,
		"outline": {},
		"error": _first_error_message(diagnostics),
		"diagnostics": diagnostics
	}

static func _first_error_message(diagnostics: Array) -> String:
	for d in diagnostics:
		if String((d as Dictionary).get("severity", "")) == "error":
			return String((d as Dictionary).get("message", "Unknown error"))
	if diagnostics.is_empty():
		return "Unknown error"
	return String((diagnostics[0] as Dictionary).get("message", "Unknown error"))

static func _has_errors(diagnostics: Array) -> bool:
	for d in diagnostics:
		if String((d as Dictionary).get("severity", "")) == "error":
			return true
	return false
