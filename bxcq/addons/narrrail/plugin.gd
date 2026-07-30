@tool
extends EditorPlugin

const SETTING_REPOSITORY_PATH := "narrrail/story_repository_path"
const SETTING_PULL_GIT_BEFORE_SYNC := "narrrail/pull_git_before_sync"
const SETTING_RESOURCE_ROOT := "narrrail/story_resource_root"
const DEFAULT_RESOURCE_ROOT := "res://narrrail_stories"
const SYNC_SCRIPT := "res://addons/narrrail/editor/story_repository_sync.gd"

var _importers: Array[EditorImportPlugin] = []
var _folder_dialog: EditorFileDialog
var _confirm_dialog: ConfirmationDialog
var _summary_dialog: AcceptDialog
var _dock: VBoxContainer
var _pending_repository_path: String = ""

func _enter_tree() -> void:
	var sync_script: Script = load(SYNC_SCRIPT)
	if sync_script != null:
		sync_script.call("ensure_project_settings")

	_add_importer("res://addons/narrrail/importer/nrstory_import_plugin.gd")
	_add_importer("res://addons/narrrail/importer/nroutline_import_plugin.gd")
	add_tool_menu_item("NarrRail Sync Stories", _on_sync_stories_pressed)
	_create_dialogs()
	_create_dock()
	print("[NarrRail] Plugin enabled")

func _exit_tree() -> void:
	remove_tool_menu_item("NarrRail Sync Stories")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	for importer in _importers:
		remove_import_plugin(importer)
	_importers.clear()
	if _folder_dialog != null:
		_folder_dialog.queue_free()
		_folder_dialog = null
	if _confirm_dialog != null:
		_confirm_dialog.queue_free()
		_confirm_dialog = null
	if _summary_dialog != null:
		_summary_dialog.queue_free()
		_summary_dialog = null
	print("[NarrRail] Plugin disabled")

func _create_dialogs() -> void:
	_folder_dialog = EditorFileDialog.new()
	_folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_folder_dialog.title = "Select NarrRail Story Repository"
	_folder_dialog.dir_selected.connect(_on_repository_dir_selected)
	add_child(_folder_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Sync NarrRail Stories"
	_confirm_dialog.confirmed.connect(_run_pending_sync)
	add_child(_confirm_dialog)

	_summary_dialog = AcceptDialog.new()
	_summary_dialog.title = "NarrRail Story Repository Sync"
	add_child(_summary_dialog)

func _add_importer(script_path: String) -> void:
	var importer_script: Script = load(script_path)
	if importer_script == null:
		push_error("[NarrRail] Failed to load import plugin script: %s" % script_path)
		return
	var importer: EditorImportPlugin = importer_script.new()
	add_import_plugin(importer)
	_importers.append(importer)

func _create_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "NarrRail"
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sync_button := Button.new()
	sync_button.text = "Sync Stories"
	sync_button.pressed.connect(_on_sync_stories_pressed)
	_dock.add_child(sync_button)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _on_sync_stories_pressed() -> void:
	var sync_script: Script = load(SYNC_SCRIPT)
	if sync_script == null:
		_show_summary("Failed to load NarrRail story repository sync script.")
		return

	sync_script.call("ensure_project_settings")
	var repository_path := String(ProjectSettings.get_setting(SETTING_REPOSITORY_PATH, ""))
	if repository_path.strip_edges().is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(repository_path)):
		_folder_dialog.popup_centered_ratio(0.6)
		return

	_prompt_sync(repository_path)

func _on_repository_dir_selected(path: String) -> void:
	var sync_script: Script = load(SYNC_SCRIPT)
	if sync_script == null:
		_show_summary("Failed to load NarrRail story repository sync script.")
		return

	ProjectSettings.set_setting(SETTING_REPOSITORY_PATH, path)
	ProjectSettings.save()
	_prompt_sync(path)

func _prompt_sync(repository_path: String) -> void:
	_pending_repository_path = repository_path
	_confirm_dialog.dialog_text = "Sync NarrRail story and outline files from:\n%s\n\nThis may update generated resources and delete stale NarrRail resources under the configured sync target." % repository_path
	_confirm_dialog.popup_centered()

func _run_pending_sync() -> void:
	var sync_script: Script = load(SYNC_SCRIPT)
	if sync_script == null:
		_show_summary("Failed to load NarrRail story repository sync script.")
		return

	var resource_root := String(ProjectSettings.get_setting(SETTING_RESOURCE_ROOT, DEFAULT_RESOURCE_ROOT))
	var pull_git := bool(ProjectSettings.get_setting(SETTING_PULL_GIT_BEFORE_SYNC, true))
	var report: Dictionary = sync_script.call("sync_repository", _pending_repository_path, resource_root, {
		"pull_git": pull_git,
		"delete_stale": true
	})
	_show_summary(_format_report(report))

func _format_report(report: Dictionary) -> String:
	var text := "Story repository sync finished.\nRepository: %s\nTarget: %s\nCreated: %d\nUpdated: %d\nDeleted: %d\nFailed: %d\nSkipped: %d" % [
		String(report.get("repository_path", "")),
		String(report.get("target_root", "")),
		int(report.get("created", 0)),
		int(report.get("updated", 0)),
		int(report.get("deleted", 0)),
		int(report.get("failed", 0)),
		int(report.get("skipped", 0))
	]
	var git_message := String(report.get("git_message", ""))
	if not git_message.is_empty():
		text += "\n\nGit:\n%s" % git_message
	var errors: Array = report.get("errors", [])
	if not errors.is_empty():
		text += "\n\nErrors:\n%s" % "\n".join(errors)
	return text

func _show_summary(text: String) -> void:
	_summary_dialog.dialog_text = text
	_summary_dialog.popup_centered()
