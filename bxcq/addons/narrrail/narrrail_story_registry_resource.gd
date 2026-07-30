@tool
class_name NarrRailStoryRegistry
extends Resource

const DEFAULT_REGISTRY_PATH := "res://narrrail_stories/story_registry.tres"
const DEFAULT_RESOURCE_ROOT := "res://narrrail_stories"
const SETTING_RESOURCE_ROOT := "narrrail/story_resource_root"
const SETTING_ALIAS_MAP := "narrrail/story_aliases"

@export var resource_root: String = ""
@export var generated_at_unix: int = 0
@export var story_paths: Dictionary = {}
@export var basename_paths: Dictionary = {}
@export var story_metadata: Dictionary = {}

static func resolve_story_path(story_name: String, registry_path: String = DEFAULT_REGISTRY_PATH) -> String:
	var key := story_name.strip_edges()
	if key.is_empty():
		return ""
	if key.begins_with("res://") or key.begins_with("user://"):
		return key

	registry_path = _normalize_registry_path(registry_path)

	var registry := load_registry(registry_path)
	if registry != null:
		var resolved := String(registry.call("get_story_path", key))
		if not resolved.is_empty():
			return resolved

	var alias_path := _resolve_alias(key)
	if not alias_path.is_empty():
		return alias_path

	if registry != null:
		var root := String(registry.get("resource_root"))
		if not root.is_empty():
			return _scan_for_story_path(key, root)

	return _scan_for_story_path(key, registry_path.get_base_dir())

static func _normalize_registry_path(registry_path: String) -> String:
	if registry_path.strip_edges().is_empty() or registry_path == DEFAULT_REGISTRY_PATH:
		var root := DEFAULT_RESOURCE_ROOT
		if ProjectSettings.has_setting(SETTING_RESOURCE_ROOT):
			root = String(ProjectSettings.get_setting(SETTING_RESOURCE_ROOT, DEFAULT_RESOURCE_ROOT))
		return "%s/story_registry.tres" % root.trim_suffix("/")
	return registry_path

static func load_registry(registry_path: String = DEFAULT_REGISTRY_PATH) -> Resource:
	registry_path = _normalize_registry_path(registry_path)
	if registry_path.strip_edges().is_empty() or not ResourceLoader.exists(registry_path):
		return null
	var registry := ResourceLoader.load(registry_path)
	if registry != null and _has_property(registry, "story_paths") and _has_property(registry, "basename_paths"):
		return registry
	return null

func get_story_path(story_name: String) -> String:
	var key := story_name.strip_edges()
	if key.is_empty():
		return ""
	if story_paths.has(key):
		return String(story_paths[key])
	if basename_paths.has(key):
		return String(basename_paths[key])

	var basename := key.get_file().get_basename()
	if not basename.is_empty() and basename_paths.has(basename):
		return String(basename_paths[basename])
	return ""

static func _resolve_alias(story_name: String) -> String:
	if not ProjectSettings.has_setting(SETTING_ALIAS_MAP):
		return ""
	var aliases = ProjectSettings.get_setting(SETTING_ALIAS_MAP, {})
	if typeof(aliases) != TYPE_DICTIONARY:
		return ""
	if not (aliases as Dictionary).has(story_name):
		return ""
	return String((aliases as Dictionary)[story_name])

static func _scan_for_story_path(story_name: String, root: String) -> String:
	if root.strip_edges().is_empty():
		return ""
	var found := _scan_dir_for_story_path(story_name, root)
	return found

static func _scan_dir_for_story_path(story_name: String, dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := "%s/%s" % [dir_path, name]
		if dir.current_is_dir():
			var found := _scan_dir_for_story_path(story_name, path)
			if not found.is_empty():
				dir.list_dir_end()
				return found
		elif (name.ends_with(".tres") or name.ends_with(".res")) and name != "story_registry.tres":
			var basename := name.get_basename()
			if basename == story_name:
				dir.list_dir_end()
				return path
			var resource := ResourceLoader.load(path)
			if resource != null and _has_property(resource, "story_data"):
				var story_data = resource.get("story_data")
				if typeof(story_data) == TYPE_DICTIONARY:
					var story_id := String((story_data as Dictionary).get("meta", {}).get("storyId", ""))
					if story_id == story_name:
						dir.list_dir_end()
						return path
		name = dir.get_next()
	dir.list_dir_end()
	return ""

static func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if String((property as Dictionary).get("name", "")) == property_name:
			return true
	return false
