@tool
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "narrrail.nrstory_importer"

func _get_visible_name() -> String:
	return "NarrRail Story"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["nrstory"])

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	# Use generic Resource type for importer compatibility.
	# Custom script data is still preserved in the saved .res.
	return "Resource"

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Default"

func _get_import_options(path: String, preset_index: int) -> Array:
	return []

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array, gen_files: Array) -> int:
	var loader_script: Script = load("res://addons/narrrail/importer/nrstory_loader.gd")
	if loader_script == null:
		push_error("[NarrRail] Cannot load loader script.")
		return ERR_CANT_OPEN

	var result: Dictionary = loader_script.call("load_story", source_file)
	if not result.get("ok", false):
		push_error("[NarrRail] Import failed: %s" % _format_diagnostics(result))
		return ERR_PARSE_ERROR

	var res := NarrRailStoryResource.new()
	res.story_data = result.get("story", {})
	res.source_path = source_file

	var out_path := "%s.%s" % [save_path, _get_save_extension()]
	return ResourceSaver.save(res, out_path)

func _format_diagnostics(result: Dictionary) -> String:
	var diagnostics: Array = result.get("diagnostics", [])
	if diagnostics.is_empty():
		return String(result.get("error", "unknown"))

	var parts: Array[String] = []
	for d in diagnostics:
		var sev := String(d.get("severity", ""))
		var code := String(d.get("code", ""))
		var path := String(d.get("path", ""))
		var msg := String(d.get("message", ""))
		parts.append("[%s][%s] %s: %s" % [sev, code, path, msg])
	return " | ".join(parts)
