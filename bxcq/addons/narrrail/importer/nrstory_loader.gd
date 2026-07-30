class_name NarrRailStoryLoader
extends RefCounted

const SUPPORTED_SCHEMA_VERSION := 1

# Return shape:
# {
#   ok: bool,
#   story: Dictionary,
#   error: String,
#   diagnostics: Array[Dictionary]
# }
#
# Diagnostic shape:
# {
#   severity: "error" | "warning",
#   code: String,
#   path: String,
#   message: String,
#   suggestion: String,
#   line: int
# }

class _YamlParser:
	var _lines: Array = []
	var _index: int = 0

	func parse(text: String) -> Dictionary:
		_lines = _preprocess(text)
		_index = 0
		if _lines.is_empty():
			return {}
		var root = _parse_block(0)
		if typeof(root) != TYPE_DICTIONARY:
			return {}
		return root

	func _preprocess(text: String) -> Array:
		var out: Array = []
		for raw in text.split("\n"):
			var line := String(raw).replace("\r", "")
			var trimmed := line.strip_edges()
			if trimmed.is_empty():
				continue
			if trimmed.begins_with("#"):
				continue
			out.append(line)
		return out

	func _indent_of(line: String) -> int:
		var n := 0
		while n < line.length() and line[n] == " ":
			n += 1
		return n

	func _trim_comment(s: String) -> String:
		var p := s.find(" #")
		if p >= 0:
			return s.substr(0, p)
		return s

	func _parse_block(indent: int):
		if _index >= _lines.size():
			return {}
		var line: String = _lines[_index]
		if _indent_of(line) < indent:
			return {}
		var content := line.substr(indent).strip_edges()
		if content.begins_with("- "):
			return _parse_array(indent)
		return _parse_map(indent)

	func _parse_map(indent: int) -> Dictionary:
		var obj: Dictionary = {}
		while _index < _lines.size():
			var line: String = _lines[_index]
			var line_indent := _indent_of(line)
			if line_indent < indent:
				break
			if line_indent > indent:
				break

			var content := _trim_comment(line.substr(indent).strip_edges())
			if content.begins_with("- "):
				break

			var sep := content.find(":")
			if sep < 0:
				_index += 1
				continue

			var key := content.substr(0, sep).strip_edges()
			var rest := content.substr(sep + 1).strip_edges()
			_index += 1

			if rest.is_empty():
				if _index < _lines.size() and _indent_of(_lines[_index]) > indent:
					obj[key] = _parse_block(indent + 2)
				else:
					obj[key] = {}
			else:
				obj[key] = _parse_scalar(rest)
		return obj

	func _parse_array(indent: int) -> Array:
		var arr: Array = []
		while _index < _lines.size():
			var line: String = _lines[_index]
			var line_indent := _indent_of(line)
			if line_indent < indent:
				break
			if line_indent != indent:
				break

			var content := _trim_comment(line.substr(indent).strip_edges())
			if not content.begins_with("- "):
				break

			var item_head := content.substr(2).strip_edges()
			_index += 1

			if item_head.is_empty():
				if _index < _lines.size() and _indent_of(_lines[_index]) > indent:
					arr.append(_parse_block(indent + 2))
				else:
					arr.append(null)
				continue

			var sep := item_head.find(":")
			if sep >= 0:
				var key := item_head.substr(0, sep).strip_edges()
				var rest := item_head.substr(sep + 1).strip_edges()
				var item_obj: Dictionary = {}
				if rest.is_empty():
					if _index < _lines.size() and _indent_of(_lines[_index]) > indent:
						item_obj[key] = _parse_block(indent + 4)
					else:
						item_obj[key] = {}
				else:
					item_obj[key] = _parse_scalar(rest)

				while _index < _lines.size():
					var nline: String = _lines[_index]
					var nindent := _indent_of(nline)
					if nindent <= indent:
						break
					if nindent != indent + 2:
						break
					var ncontent := _trim_comment(nline.substr(nindent).strip_edges())
					if ncontent.begins_with("- "):
						break
					var nsep := ncontent.find(":")
					if nsep < 0:
						_index += 1
						continue
					var nkey := ncontent.substr(0, nsep).strip_edges()
					var nrest := ncontent.substr(nsep + 1).strip_edges()
					_index += 1
					if nrest.is_empty():
						if _index < _lines.size() and _indent_of(_lines[_index]) > nindent:
							item_obj[nkey] = _parse_block(nindent + 2)
						else:
							item_obj[nkey] = {}
					else:
						item_obj[nkey] = _parse_scalar(nrest)
				arr.append(item_obj)
				continue

			arr.append(_parse_scalar(item_head))
		return arr

	func _parse_scalar(raw: String):
		var s := raw.strip_edges()
		if s == "[]":
			return []
		if s == "{}":
			return {}
		if s == "null" or s == "~":
			return null
		if s == "true":
			return true
		if s == "false":
			return false
		if s.length() >= 2:
			if (s.begins_with("\"") and s.ends_with("\"")) or (s.begins_with("'") and s.ends_with("'")):
				return s.substr(1, s.length() - 2)
		if s.is_valid_int():
			return int(s)
		if s.is_valid_float():
			return float(s)
		return s

static func load_story(path: String) -> Dictionary:
	var parsed := load_document(path)
	if not parsed.get("ok", false):
		return parsed

	var story: Dictionary = parsed.get("data", {})
	if detect_file_kind(story) != "Story":
		return _fail([
			_diag("error", "FILE_KIND_INVALID", "$", "Expected story .nrstory but got: %s" % detect_file_kind(story), -1)
		])
	var diagnostics: Array = _validate_story_shape(story)
	diagnostics.append_array(_validate_schema_version(story))

	# Static validation pipeline (independent from runtime play flow)
	var validator_script: Script = load("res://addons/narrrail/importer/nrstory_validator.gd")
	if validator_script != null:
		var static_diags: Array = validator_script.call("validate_story", story)
		diagnostics.append_array(static_diags)

	if _has_errors(diagnostics):
		return _fail(diagnostics)

	return {
		"ok": true,
		"story": story,
		"error": "",
		"diagnostics": diagnostics
	}

static func load_global_config(path: String) -> Dictionary:
	var parsed := load_document(path)
	if not parsed.get("ok", false):
		return parsed

	var config: Dictionary = parsed.get("data", {})
	if detect_file_kind(config) != "GlobalConfig":
		return _fail([
			_diag("error", "FILE_KIND_INVALID", "$", "Expected GlobalConfig .nrstory but got: %s" % detect_file_kind(config), -1)
		])

	var diagnostics: Array = _validate_global_config_shape(config)
	if _has_errors(diagnostics):
		return _fail(diagnostics)

	return {
		"ok": true,
		"config": config,
		"error": "",
		"diagnostics": diagnostics
	}

static func load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail([
			_diag("error", "FILE_NOT_FOUND", "$", "Story file not found: %s" % path, -1)
		])

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail([
			_diag("error", "FILE_OPEN_FAILED", "$", "Failed to open story file: %s" % path, -1)
		])

	var content := file.get_as_text()
	file.close()

	var parsed := _parse_yaml_or_json(content)
	if not parsed.get("ok", false):
		return parsed

	return {
		"ok": true,
		"data": parsed.get("story", {}),
		"kind": detect_file_kind(parsed.get("story", {})),
		"error": "",
		"diagnostics": []
	}

static func detect_file_kind(data: Dictionary) -> String:
	var meta: Dictionary = data.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY:
		var config_type := String(meta.get("configType", ""))
		if config_type.to_lower() == "globalconfig":
			return "GlobalConfig"
		if meta.has("railId"):
			return "Outline"
		if meta.has("storyId"):
			return "Story"
	if data.has("nodes") or data.has("edges"):
		return "Story"
	return "Unknown"

static func _parse_yaml_or_json(content: String) -> Dictionary:
	var yaml_parser := _YamlParser.new()
	var yaml_data = yaml_parser.parse(content)
	if typeof(yaml_data) == TYPE_DICTIONARY and not yaml_data.is_empty():
		return {
			"ok": true,
			"story": yaml_data,
			"error": "",
			"diagnostics": []
		}

	var json := JSON.new()
	var parse_err := json.parse(content)
	if parse_err != OK:
		return _fail([
			_diag("error", "PARSE_FAILED", "$", "Failed to parse .nrstory as YAML/JSON: %s" % json.get_error_message(), json.get_error_line())
		])

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return _fail([
			_diag("error", "ROOT_TYPE_INVALID", "$", "Parsed story root is not an object/dictionary", -1)
		])

	return {
		"ok": true,
		"story": data,
		"error": "",
		"diagnostics": []
	}

static func _validate_story_shape(story: Dictionary) -> Array:
	var diagnostics: Array = []

	if not story.has("meta"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta", "Missing required field: meta", -1))
	elif typeof(story.get("meta")) != TYPE_DICTIONARY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "meta", "meta must be an object", -1))

	if not story.has("variables"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "variables", "Missing required field: variables", -1))
	elif typeof(story.get("variables")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "variables", "variables must be an array", -1))

	if not story.has("nodes"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "nodes", "Missing required field: nodes", -1))
	elif typeof(story.get("nodes")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "nodes", "nodes must be an array", -1))

	if not story.has("edges"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "edges", "Missing required field: edges", -1))
	elif typeof(story.get("edges")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "edges", "edges must be an array", -1))

	if story.has("meta") and typeof(story.get("meta")) == TYPE_DICTIONARY:
		var meta: Dictionary = story.get("meta", {})
		if not meta.has("schemaVersion"):
			diagnostics.append(_diag("error", "MISSING_FIELD", "meta.schemaVersion", "Missing required field: meta.schemaVersion", -1))
		if not meta.has("entryNodeId"):
			diagnostics.append(_diag("error", "MISSING_FIELD", "meta.entryNodeId", "Missing required field: meta.entryNodeId", -1))

	return diagnostics

static func _validate_schema_version(story: Dictionary) -> Array:
	var diagnostics: Array = []
	var meta: Dictionary = story.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		return diagnostics
	if not meta.has("schemaVersion"):
		return diagnostics

	var sv = meta.get("schemaVersion")
	if typeof(sv) != TYPE_INT:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "meta.schemaVersion", "schemaVersion must be int", -1))
		return diagnostics

	var version: int = int(sv)
	if version > SUPPORTED_SCHEMA_VERSION:
		diagnostics.append(_diag("error", "SCHEMA_UNSUPPORTED", "meta.schemaVersion", "Unsupported future schemaVersion: %d (supported <= %d)" % [version, SUPPORTED_SCHEMA_VERSION], -1))
	elif version < SUPPORTED_SCHEMA_VERSION:
		diagnostics.append(_diag("warning", "SCHEMA_OLDER", "meta.schemaVersion", "Older schemaVersion: %d (current: %d). Migration is not implemented yet." % [version, SUPPORTED_SCHEMA_VERSION], -1))

	return diagnostics

static func _validate_global_config_shape(config: Dictionary) -> Array:
	var diagnostics: Array = []
	var meta = config.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta", "Missing required field: meta", -1))
		return diagnostics

	if not meta.has("schemaVersion"):
		diagnostics.append(_diag("error", "MISSING_FIELD", "meta.schemaVersion", "Missing required field: meta.schemaVersion", -1))
	elif typeof(meta.get("schemaVersion")) != TYPE_INT:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "meta.schemaVersion", "schemaVersion must be int", -1))

	if String(meta.get("configType", "")).to_lower() != "globalconfig":
		diagnostics.append(_diag("error", "CONFIG_TYPE_INVALID", "meta.configType", "meta.configType must be GlobalConfig", -1))

	if config.has("variables") and typeof(config.get("variables")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "variables", "variables must be an array", -1))

	if config.has("presetSpeakers") and typeof(config.get("presetSpeakers")) != TYPE_ARRAY:
		diagnostics.append(_diag("error", "TYPE_MISMATCH", "presetSpeakers", "presetSpeakers must be an array", -1))

	return diagnostics

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
		"story": {},
		"error": _first_error_message(diagnostics),
		"diagnostics": diagnostics
	}

static func _first_error_message(diagnostics: Array) -> String:
	for d in diagnostics:
		if String(d.get("severity", "")) == "error":
			return String(d.get("message", "Unknown error"))
	if diagnostics.is_empty():
		return "Unknown error"
	return String(diagnostics[0].get("message", "Unknown error"))

static func _has_errors(diagnostics: Array) -> bool:
	for d in diagnostics:
		if String(d.get("severity", "")) == "error":
			return true
	return false
