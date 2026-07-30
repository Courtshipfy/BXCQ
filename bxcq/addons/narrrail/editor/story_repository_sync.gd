@tool
class_name NarrRailStoryRepositorySync
extends RefCounted

const SETTING_REPOSITORY_PATH := "narrrail/story_repository_path"
const SETTING_PULL_GIT_BEFORE_SYNC := "narrrail/pull_git_before_sync"
const SETTING_RESOURCE_ROOT := "narrrail/story_resource_root"
const SETTING_ALIAS_MAP := "narrrail/story_aliases"

const DEFAULT_RESOURCE_ROOT := "res://narrrail_stories"
const LOADER_SCRIPT := "res://addons/narrrail/importer/nrstory_loader.gd"
const OUTLINE_LOADER_SCRIPT := "res://addons/narrrail/importer/nroutline_loader.gd"
const STORY_RESOURCE_SCRIPT := "res://addons/narrrail/narrrail_story_resource.gd"
const STORY_REGISTRY_RESOURCE_SCRIPT := "res://addons/narrrail/narrrail_story_registry_resource.gd"
const GLOBAL_CONFIG_RESOURCE_SCRIPT := "res://addons/narrrail/narrrail_global_config_resource.gd"
const OUTLINE_RESOURCE_SCRIPT := "res://addons/narrrail/narrrail_outline_resource.gd"

static func ensure_project_settings() -> void:
	_ensure_setting(SETTING_REPOSITORY_PATH, "", TYPE_STRING)
	_ensure_setting(SETTING_PULL_GIT_BEFORE_SYNC, true, TYPE_BOOL)
	_ensure_setting(SETTING_RESOURCE_ROOT, DEFAULT_RESOURCE_ROOT, TYPE_STRING)
	_ensure_setting(SETTING_ALIAS_MAP, {}, TYPE_DICTIONARY)

static func sync_from_project_settings(options: Dictionary = {}) -> Dictionary:
	ensure_project_settings()
	var repository_path := String(ProjectSettings.get_setting(SETTING_REPOSITORY_PATH, ""))
	var resource_root := String(ProjectSettings.get_setting(SETTING_RESOURCE_ROOT, DEFAULT_RESOURCE_ROOT))
	var pull_git := bool(ProjectSettings.get_setting(SETTING_PULL_GIT_BEFORE_SYNC, true))
	return sync_repository(repository_path, resource_root, {
		"pull_git": pull_git,
		"delete_stale": bool(options.get("delete_stale", true)),
		"confirm_delete": bool(options.get("confirm_delete", false))
	})

static func sync_repository(repository_path: String, resource_root: String = DEFAULT_RESOURCE_ROOT, options: Dictionary = {}) -> Dictionary:
	var report := _new_report(repository_path, resource_root)
	var repo_abs := _normalize_abs_dir(repository_path)
	if repo_abs.is_empty() or not DirAccess.dir_exists_absolute(repo_abs):
		report.errors.append("Story repository path does not exist: %s" % repository_path)
		return report

	resource_root = _normalize_resource_root(resource_root)
	if not resource_root.begins_with("res://"):
		report.errors.append("Story resource root must be under res://: %s" % resource_root)
		return report

	report.repository_path = repo_abs
	report.target_root = "%s/%s" % [resource_root, _sanitize_segment(repo_abs.get_file())]

	if bool(options.get("pull_git", false)):
		var pull_result := _pull_git_if_needed(repo_abs)
		report.git_message = pull_result.get("message", "")
		if not pull_result.get("ok", false):
			report.errors.append(report.git_message)
			return report

	var source_files := _find_narrrail_files(repo_abs)
	if source_files.is_empty():
		report.errors.append("No NarrRail story or outline files were found in: %s" % repo_abs)
		return report

	var loader_script: Script = load(LOADER_SCRIPT)
	var outline_loader_script: Script = load(OUTLINE_LOADER_SCRIPT)
	var story_resource_script: Script = load(STORY_RESOURCE_SCRIPT)
	var story_registry_resource_script: Script = load(STORY_REGISTRY_RESOURCE_SCRIPT)
	var global_config_resource_script: Script = load(GLOBAL_CONFIG_RESOURCE_SCRIPT)
	var outline_resource_script: Script = load(OUTLINE_RESOURCE_SCRIPT)
	if loader_script == null or outline_loader_script == null or story_resource_script == null or story_registry_resource_script == null or global_config_resource_script == null or outline_resource_script == null:
		report.errors.append("Failed to load NarrRail sync scripts/resources")
		return report

	var story_ids := _collect_story_ids(source_files, loader_script, report, repo_abs)
	var expected_paths: Dictionary = {}
	for source_file in source_files:
		var relative_path := _relative_path(repo_abs, source_file)
		if relative_path.is_empty():
			report.failed += 1
			report.errors.append("Failed to compute relative path: %s" % source_file)
			continue

		var doc: Dictionary = loader_script.call("load_document", source_file)
		if not doc.get("ok", false):
			report.failed += 1
			report.errors.append("%s: %s" % [relative_path, String(doc.get("error", "unknown"))])
			continue

		var kind := String(doc.get("kind", "Unknown"))
		var target_path := _target_resource_path(report.target_root, relative_path)
		if expected_paths.has(target_path):
			report.failed += 1
			report.errors.append("Target resource path collision: %s" % target_path)
			continue

		expected_paths[target_path] = source_file
		var result := _write_resource(kind, source_file, target_path, loader_script, outline_loader_script, story_resource_script, global_config_resource_script, outline_resource_script, story_ids)
		if not result.get("ok", false):
			report.failed += 1
			report.errors.append("%s: %s" % [relative_path, String(result.get("error", "unknown"))])
			continue

		if bool(result.get("created", false)):
			report.created += 1
		else:
			report.updated += 1

	if bool(options.get("delete_stale", true)):
		var stale_paths := _find_stale_resources(report.target_root, repo_abs, expected_paths)
		for stale_path in stale_paths:
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_path))
			if err == OK:
				report.deleted += 1
			else:
				report.failed += 1
				report.errors.append("Failed to delete stale resource: %s" % stale_path)

	var registry_result := _write_story_registry(resource_root, story_registry_resource_script, repo_abs)
	if not registry_result.get("ok", false):
		report.failed += 1
		report.errors.append(String(registry_result.get("error", "Failed to write story registry")))
	else:
		report["registry_path"] = String(registry_result.get("path", ""))

	return report

static func _write_story_registry(resource_root: String, story_registry_resource_script: Script, repo_abs: String) -> Dictionary:
	var registry_path := "%s/story_registry.tres" % resource_root
	var existing := ResourceLoader.load(registry_path) if ResourceLoader.exists(registry_path) else null
	var registry: Resource = existing if existing != null and _has_property(existing, "story_paths") else story_registry_resource_script.new()
	var story_paths: Dictionary = {}
	var basename_paths: Dictionary = {}
	var story_metadata: Dictionary = {}

	for path in _find_resource_files(ProjectSettings.globalize_path(resource_root)):
		var res_path := ProjectSettings.localize_path(path)
		if res_path == registry_path:
			continue
		var resource := ResourceLoader.load(res_path)
		if resource == null or not _has_property(resource, "story_data"):
			continue
		var story_data = resource.get("story_data")
		if typeof(story_data) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = (story_data as Dictionary).get("meta", {})
		var story_id := String(meta.get("storyId", ""))
		var basename := res_path.get_file().get_basename()
		var source_path := String(resource.get("source_path")) if _has_property(resource, "source_path") else ""
		var source_relative_path := _relative_path(repo_abs, source_path) if not source_path.is_empty() else ""
		var metadata := {
			"path": res_path,
			"basename": basename,
			"source_path": source_path,
			"source_relative_path": source_relative_path,
			"title": String(meta.get("title", "")),
			"updated_at_unix": Time.get_unix_time_from_system()
		}
		if not story_id.is_empty():
			story_paths[story_id] = res_path
			story_metadata[story_id] = metadata
		if not basename.is_empty():
			basename_paths[basename] = res_path
			if not story_metadata.has(basename):
				story_metadata[basename] = metadata

	registry.set("resource_root", resource_root)
	registry.set("generated_at_unix", Time.get_unix_time_from_system())
	registry.set("story_paths", story_paths)
	registry.set("basename_paths", basename_paths)
	registry.set("story_metadata", story_metadata)

	var make_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(resource_root))
	if make_err != OK:
		return {"ok": false, "error": "Failed to create story registry directory: %s" % resource_root}
	var save_err := ResourceSaver.save(registry, registry_path)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save story registry: %s" % registry_path}
	return {"ok": true, "path": registry_path}

static func _write_resource(kind: String, source_file: String, target_path: String, loader_script: Script, outline_loader_script: Script, story_resource_script: Script, global_config_resource_script: Script, outline_resource_script: Script, story_ids: Array) -> Dictionary:
	var existing := ResourceLoader.load(target_path) if ResourceLoader.exists(target_path) else null
	var resource: Resource
	var created := existing == null

	match kind:
		"Story":
			var loaded: Dictionary = loader_script.call("load_story", source_file)
			if not loaded.get("ok", false):
				return {"ok": false, "error": loaded.get("error", "Story load failed")}
			resource = existing if existing != null and _has_property(existing, "story_data") else story_resource_script.new()
			resource.set("story_data", loaded.get("story", {}))
			resource.set("source_path", source_file)
		"GlobalConfig":
			var loaded_config: Dictionary = loader_script.call("load_global_config", source_file)
			if not loaded_config.get("ok", false):
				return {"ok": false, "error": loaded_config.get("error", "GlobalConfig load failed")}
			var config: Dictionary = loaded_config.get("config", {})
			resource = existing if existing != null and _has_property(existing, "config_data") else global_config_resource_script.new()
			resource.set("schema_version", int(config.get("meta", {}).get("schemaVersion", 1)))
			resource.set("variables", config.get("variables", []))
			resource.set("preset_speakers", config.get("presetSpeakers", []))
			resource.set("config_data", config)
			resource.set("source_path", source_file)
		"Outline":
			var loaded_outline: Dictionary = outline_loader_script.call("load_outline", source_file, story_ids)
			if not loaded_outline.get("ok", false):
				return {"ok": false, "error": loaded_outline.get("error", "Outline load failed")}
			resource = existing if existing != null and _has_property(existing, "outline_data") else outline_resource_script.new()
			resource.set("outline_data", loaded_outline.get("outline", {}))
			resource.set("source_path", source_file)
		_:
			return {"ok": false, "error": "Unknown NarrRail file kind: %s" % kind}

	var dir := target_path.get_base_dir()
	var make_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if make_err != OK:
		return {"ok": false, "error": "Failed to create target directory: %s" % dir}

	var save_err := ResourceSaver.save(resource, target_path)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save resource: %s" % target_path}

	return {"ok": true, "created": created}

static func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if String((property as Dictionary).get("name", "")) == property_name:
			return true
	return false

static func _find_stale_resources(target_root: String, repo_abs: String, expected_paths: Dictionary) -> Array:
	var out: Array = []
	var root_abs := ProjectSettings.globalize_path(target_root)
	if not DirAccess.dir_exists_absolute(root_abs):
		return out
	for path in _find_resource_files(root_abs):
		var res_path := ProjectSettings.localize_path(path)
		if not res_path.begins_with("res://"):
			continue
		if expected_paths.has(res_path):
			continue
		var resource := ResourceLoader.load(res_path)
		if resource == null:
			continue
		var source_path := String(resource.get("source_path"))
		if source_path == repo_abs or source_path.begins_with(repo_abs + "/"):
			out.append(res_path)
	return out

static func _find_resource_files(abs_dir: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := "%s/%s" % [abs_dir, name]
		if dir.current_is_dir():
			out.append_array(_find_resource_files(child))
		elif name.ends_with(".tres") or name.ends_with(".res"):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()
	return out

static func _find_narrrail_files(abs_dir: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := "%s/%s" % [abs_dir, name]
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_find_narrrail_files(child))
		elif _is_narrrail_source_file(name):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return _filter_legacy_outline_files(out)

static func _target_resource_path(target_root: String, relative_source_path: String) -> String:
	var is_outline := relative_source_path.ends_with(".nroutline") or relative_source_path.ends_with(".nrrail")
	var without_ext := relative_source_path
	for ext in [".nrstory", ".nroutline", ".nrrail"]:
		without_ext = without_ext.trim_suffix(ext)
	var parts := without_ext.split("/", false)
	var out := target_root
	for part in parts:
		out += "/%s" % _sanitize_segment(part)
	if is_outline:
		out += "_outline"
	return "%s.tres" % out

static func _is_narrrail_source_file(name: String) -> bool:
	return name.ends_with(".nrstory") or name.ends_with(".nroutline") or name.ends_with(".nrrail")

static func _filter_legacy_outline_files(paths: Array) -> Array:
	var modern_outline_stems: Dictionary = {}
	for path in paths:
		if String(path).ends_with(".nroutline"):
			modern_outline_stems[String(path).trim_suffix(".nroutline")] = true

	var out: Array = []
	for path in paths:
		var text := String(path)
		if text.ends_with(".nrrail") and modern_outline_stems.has(text.trim_suffix(".nrrail")):
			continue
		out.append(path)
	return out

static func _collect_story_ids(source_files: Array, loader_script: Script, report: Dictionary, repo_abs: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for source_file in source_files:
		if not String(source_file).ends_with(".nrstory"):
			continue
		var doc: Dictionary = loader_script.call("load_document", source_file)
		if not doc.get("ok", false):
			continue
		if String(doc.get("kind", "Unknown")) != "Story":
			continue
		var data: Dictionary = doc.get("data", {})
		var story_id := String(data.get("meta", {}).get("storyId", ""))
		if story_id.is_empty():
			continue
		if seen.has(story_id):
			report.errors.append("Duplicate storyId while syncing repository: %s" % story_id)
			report.failed += 1
			continue
		seen[story_id] = true
		out.append(story_id)
	return out

static func _relative_path(repo_abs: String, source_abs: String) -> String:
	var repo := repo_abs.replace("\\", "/").trim_suffix("/")
	var source := source_abs.replace("\\", "/")
	if not source.begins_with(repo + "/"):
		return ""
	return source.substr(repo.length() + 1)

static func _sanitize_segment(raw: String) -> String:
	var out := ""
	var invalid_chars := {"/": true, "\\": true, ":": true, "*": true, "?": true, "\"": true, "<": true, ">": true, "|": true}
	for i in range(raw.length()):
		var c := raw.substr(i, 1)
		if invalid_chars.has(c) or c.unicode_at(0) < 32:
			out += "_"
		else:
			out += c
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return "Item" if out.is_empty() else out

static func _normalize_resource_root(path: String) -> String:
	var out := path.strip_edges().replace("\\", "/")
	while out.ends_with("/"):
		out = out.trim_suffix("/")
	return DEFAULT_RESOURCE_ROOT if out.is_empty() else out

static func _normalize_abs_dir(path: String) -> String:
	if path.strip_edges().is_empty():
		return ""
	var out := ProjectSettings.globalize_path(path)
	out = out.replace("\\", "/")
	while out.ends_with("/"):
		out = out.trim_suffix("/")
	return out

static func _pull_git_if_needed(repo_abs: String) -> Dictionary:
	var check := []
	var output := []
	var code := OS.execute("git", ["-C", repo_abs, "rev-parse", "--is-inside-work-tree"], check, true)
	if code != 0 or check.is_empty() or String(check[0]).strip_edges().to_lower() != "true":
		return {"ok": true, "message": "Selected story repository is not a Git working tree; skipped git pull."}

	code = OS.execute("git", ["-C", repo_abs, "pull", "--ff-only"], output, true)
	return {
		"ok": code == 0,
		"message": "\n".join(output).strip_edges()
	}

static func _ensure_setting(name: String, default_value, type: int) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)
	ProjectSettings.add_property_info({
		"name": name,
		"type": type
	})

static func _new_report(repository_path: String, resource_root: String) -> Dictionary:
	return {
		"ok": true,
		"repository_path": repository_path,
		"target_root": resource_root,
		"created": 0,
		"updated": 0,
		"deleted": 0,
		"failed": 0,
		"skipped": 0,
		"errors": [],
		"git_message": "",
		"registry_path": ""
	}
