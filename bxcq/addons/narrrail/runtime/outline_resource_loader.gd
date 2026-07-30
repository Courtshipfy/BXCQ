class_name NarrRailOutlineResourceLoader
extends RefCounted

const OUTLINE_LOADER_SCRIPT := "res://addons/narrrail/importer/nroutline_loader.gd"

static func load_outline(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "outline": {}, "error": "Outline path is empty", "diagnostics": []}

	var imported := ResourceLoader.load(path)
	if imported != null and _has_property(imported, "outline_data"):
		var data = imported.get("outline_data")
		if typeof(data) == TYPE_DICTIONARY and not (data as Dictionary).is_empty():
			return {
				"ok": true,
				"outline": data,
				"error": "",
				"diagnostics": []
			}

	var loader_script: Script = load(OUTLINE_LOADER_SCRIPT)
	if loader_script == null:
		return {"ok": false, "outline": {}, "error": "Outline loader script missing", "diagnostics": []}

	return loader_script.call("load_outline", path)

static func _has_property(resource: Resource, property_name: String) -> bool:
	for property in resource.get_property_list():
		if String((property as Dictionary).get("name", "")) == property_name:
			return true
	return false
