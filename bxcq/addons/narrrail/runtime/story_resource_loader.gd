class_name NarrRailStoryResourceLoader
extends RefCounted

const NRSTORY_LOADER_SCRIPT := "res://addons/narrrail/importer/nrstory_loader.gd"
const STORY_REGISTRY_RESOURCE_SCRIPT := "res://addons/narrrail/narrrail_story_registry_resource.gd"

static func load_story(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "story": {}, "error": "Story path is empty", "diagnostics": []}

	var resolved_path := resolve_story_path(path)
	if resolved_path.is_empty():
		return {"ok": false, "story": {}, "error": "NarrRail story not found for event/story name: %s" % path, "diagnostics": []}

	var imported := ResourceLoader.load(resolved_path)
	if imported != null and _has_property(imported, "story_data"):
		var data = imported.get("story_data")
		if typeof(data) == TYPE_DICTIONARY and not (data as Dictionary).is_empty():
			return {
				"ok": true,
				"story": _with_global_config_variables(data, resolved_path),
				"error": "",
				"diagnostics": []
			}

	var loader_script: Script = load(NRSTORY_LOADER_SCRIPT)
	if loader_script == null:
		return {"ok": false, "story": {}, "error": "Loader script missing", "diagnostics": []}

	var result: Dictionary = loader_script.call("load_story", resolved_path)
	if not result.get("ok", false):
		return result

	result["story"] = _with_global_config_variables(result.get("story", {}), resolved_path)
	return result

static func resolve_story_path(story_name_or_path: String, registry_path: String = "") -> String:
	var key := story_name_or_path.strip_edges()
	if key.is_empty():
		return ""
	if key.begins_with("res://") or key.begins_with("user://"):
		return key

	var registry_script: Script = load(STORY_REGISTRY_RESOURCE_SCRIPT)
	if registry_script == null:
		return ""
	if registry_path.strip_edges().is_empty():
		return String(registry_script.call("resolve_story_path", key))
	return String(registry_script.call("resolve_story_path", key, registry_path))

static func _with_global_config_variables(story_data: Dictionary, story_path: String) -> Dictionary:
	var story := story_data.duplicate(true)
	var global_variables := _find_global_variables_for_story(story_path)
	if global_variables.is_empty():
		return story

	var merged: Array = []
	var seen: Dictionary = {}
	for variable in global_variables:
		var v: Dictionary = variable
		var name := String(v.get("name", ""))
		if name.is_empty() or seen.has(name):
			continue
		merged.append(v.duplicate(true))
		seen[name] = merged.size() - 1

	for variable in story.get("variables", []):
		var v: Dictionary = variable
		var name := String(v.get("name", ""))
		if name.is_empty():
			continue
		if seen.has(name):
			merged[int(seen[name])] = v.duplicate(true)
		else:
			merged.append(v.duplicate(true))
			seen[name] = merged.size() - 1

	story["variables"] = merged
	return story

static func _find_global_variables_for_story(story_path: String) -> Array:
	var dir := story_path.get_base_dir()
	while dir.begins_with("res://") and dir != "res://":
		var found := _find_global_variables_in_dir(dir)
		if not found.is_empty():
			return found
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return []

static func _find_global_variables_in_dir(dir_path: String) -> Array:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []

	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and (name.ends_with(".tres") or name.ends_with(".res")):
			var path := "%s/%s" % [dir_path, name]
			var resource := ResourceLoader.load(path)
			if resource != null and _has_property(resource, "variables") and _has_property(resource, "config_data"):
				var variables = resource.get("variables")
				if typeof(variables) == TYPE_ARRAY:
					dir.list_dir_end()
					return variables
		name = dir.get_next()
	dir.list_dir_end()
	return []

static func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if String((property as Dictionary).get("name", "")) == property_name:
			return true
	return false
