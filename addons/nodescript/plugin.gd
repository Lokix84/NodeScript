@tool
extends EditorPlugin

const NodeScriptPanelScene: PackedScene = preload("res://addons/nodescript/editor/nodescript_panel.tscn")
const NodeScriptTreeDockScript: Script = preload("res://addons/nodescript/editor/nodescript_tree_dock.gd")
const NodeScriptInspectorDockScript: Script = preload("res://addons/nodescript/editor/nodescript_inspector_dock.gd")
const NodeScriptResource = preload("res://addons/nodescript/core/nodescript_resource.gd")
const NodeScriptSyncScript: Script = preload("res://addons/nodescript/editor/nodescript_sync.gd")

var nodescript_panel: Control
var tree_dock: Control
var inspector_dock: Control
var script_editor_ref: ScriptEditor
var _current_script: Script
var _pending_script_for_autocreate: Script
var _is_refreshing_from_fs: bool = false
var _last_refresh_path: String = ""


func _enter_tree() -> void:
	# Create the NodeScript main panel
	nodescript_panel = NodeScriptPanelScene.instantiate()
	nodescript_panel.name = "NodeScriptMain"

	# Let the panel know its plugin (optional but useful later)
	if nodescript_panel.has_method("set_editor_plugin"):
		nodescript_panel.set_editor_plugin(self)

	# Add as a MAIN SCREEN (top-center tab like 2D/3D/Script/Game/AssetLib)
	get_editor_interface().get_editor_main_screen().add_child(nodescript_panel)

	# Start hidden; editor calls _make_visible when you click the tab
	nodescript_panel.hide()

	# Create docks for integration with Script editor
	_setup_docks()

	# Connect to script editor signals
	_connect_script_editor()
	_connect_filesystem_signals()

	# Add Tools menu items
	_setup_tools_menu()


func _exit_tree() -> void:
	# Cleanup docks
	_safe_remove_dock(tree_dock)
	tree_dock = null

	_safe_remove_dock(inspector_dock)
	inspector_dock = null

	# Disconnect script editor
	if script_editor_ref:
		if script_editor_ref.editor_script_changed.is_connected(_on_script_changed):
			script_editor_ref.editor_script_changed.disconnect(_on_script_changed)
		if script_editor_ref.has_signal("script_saved") and script_editor_ref.script_saved.is_connected(_on_script_saved):
			script_editor_ref.script_saved.disconnect(_on_script_saved)
		script_editor_ref = null

	var file_system = get_editor_interface().get_resource_filesystem()
	if file_system and file_system.filesystem_changed.is_connected(_on_filesystem_changed):
		file_system.filesystem_changed.disconnect(_on_filesystem_changed)

	# Cleanup main panel
	if nodescript_panel and is_instance_valid(nodescript_panel):
		nodescript_panel.queue_free()
		nodescript_panel = null


# --- Tools Menu Setup ---

func _setup_tools_menu() -> void:
	add_tool_menu_item("NodeScript/Clear All .nodescript.tres Files", _on_clear_nodescript_files_pressed)


func _on_clear_nodescript_files_pressed() -> void:
	var confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.dialog_autowrap = true
	confirmation_dialog.title = "Clear All .nodescript.tres Files"
	confirmation_dialog.ok_button_text = "Clear All"
	confirmation_dialog.cancel_button_text = "Cancel"

	var label = Label.new()
	label.text = "This will DELETE all .nodescript.tres files in the project.\n\nThis action cannot be undone!\n\nAre you sure you want to proceed?"
	confirmation_dialog.add_child(label)

	confirmation_dialog.confirmed.connect(_perform_clear_nodescript_files)

	# Add dialog to editor and show it
	get_editor_interface().get_base_control().add_child(confirmation_dialog)
	confirmation_dialog.popup_centered_ratio(0.4)


func _perform_clear_nodescript_files() -> void:
	var file_system = get_editor_interface().get_resource_filesystem()
	var deleted_files = []
	_delete_nodescript_files_recursive("res://", deleted_files)

	# Refresh file system
	file_system.scan()

	var message = "Cleared %d .nodescript.tres file(s)" % deleted_files.size()
	print("NodeScript: " + message)


func _delete_nodescript_files_recursive(path: String, deleted_files: Array) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path = path.path_join(file_name)

		if dir.current_is_dir():
			_delete_nodescript_files_recursive(full_path, deleted_files)
		elif file_name.ends_with(".nodescript.tres"):
			var err = DirAccess.remove_absolute(full_path)
			if err == OK:
				deleted_files.append(full_path)
				print("NodeScript: Deleted %s" % full_path)
			else:
				push_error("NodeScript: Failed to delete %s (error %d)" % [full_path, err])

		file_name = dir.get_next()


# --- Main Screen integration ---

func _has_main_screen() -> bool:
	# Disabled: NodeScript now works entirely through docks
	return false


func _make_visible(visible: bool) -> void:
	if not nodescript_panel:
		return

	nodescript_panel.visible = visible

	if visible:
		# When the NodeScript tab is shown, grab the current script
		var script_editor := get_editor_interface().get_script_editor()
		var current_script: Script = null

		if script_editor and script_editor.has_method("get_current_script"):
			current_script = script_editor.get_current_script()

		if nodescript_panel.has_method("set_target_script"):
			nodescript_panel.set_target_script(current_script)


func _get_plugin_name() -> String:
	# Label of the main tab
	return "NodeScript"


func _get_plugin_icon() -> Texture2D:
	# Use built-in Script icon for now
	return get_editor_interface().get_editor_theme().get_icon("Script", "EditorIcons")


# --- Dock Integration ---

func _setup_docks() -> void:
	# Remember current focused control to avoid stealing focus when adding docks
	var prev_focus: Control = null
	var base := get_editor_interface().get_base_control()
	if base and base.get_viewport():
		prev_focus = base.get_viewport().gui_get_focus_owner()

	# Create tree dock for left sidebar
	tree_dock = Control.new()
	tree_dock.tooltip_text = "NodeScript"
	tree_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tree_dock_content = NodeScriptTreeDockScript.new()
	tree_dock_content.name = "NodeScriptTreeDockContent"
	tree_dock_content.set_editor_plugin(self)
	tree_dock_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_dock_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_dock_content.anchor_right = 1.0
	tree_dock_content.anchor_bottom = 1.0
	tree_dock.add_child(tree_dock_content)

	# Add to left dock (top area near Scene tree)
	add_control_to_dock(DOCK_SLOT_LEFT_UR, tree_dock)

	_set_dock_tab_icon_from_list(tree_dock, ["Tree", "Filesystem", "Folder"])

	# Create inspector dock for right sidebar
	inspector_dock = Control.new()
	inspector_dock.tooltip_text = "NodeScript Inspector"
	inspector_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inspector_dock_content = NodeScriptInspectorDockScript.new()
	inspector_dock_content.name = "NodeScriptInspectorDockContent"
	inspector_dock_content.set_editor_plugin(self)
	inspector_dock_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_dock_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_dock_content.anchor_right = 1.0
	inspector_dock_content.anchor_bottom = 1.0
	inspector_dock.add_child(inspector_dock_content)

	# Add to right dock (alongside Inspector)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, inspector_dock)
	# Prefer custom icon if available; fall back to editor icons
	_set_dock_tab_icon_custom_or_list(inspector_dock, "res://addons/nodescript/icons/EditorProperty.svg", ["EditorProperty", "Inspector", "Property", "Object"])

	# Connect tree selection to inspector
	tree_dock_content.item_selected.connect(_on_tree_item_selected)
	tree_dock_content.item_activated.connect(_on_tree_item_activated)

	# Connect inspector updates to tree refresh
	inspector_dock_content.tree_refresh_requested.connect(_refresh_tree_dock)

	# Keep docks present even before a NodeScript exists
	tree_dock.visible = true
	inspector_dock.visible = true

	# Restore previous focus so docks don't steal it (deferred to let dock creation finish)
	if prev_focus and is_instance_valid(prev_focus):
		call_deferred("_deferred_restore_focus", prev_focus)

	# React when a dock tab becomes visible to trigger auto-create if needed
	tree_dock.visibility_changed.connect(_on_dock_visibility_changed)
	inspector_dock.visibility_changed.connect(_on_dock_visibility_changed)


func _deferred_restore_focus(control: Control) -> void:
	if control and is_instance_valid(control):
		control.grab_focus()


func _set_dock_tab_icon_from_list(control: Control, icon_names: Array) -> void:
	if not control:
		return
	var theme = get_editor_interface().get_editor_theme()
	if not theme:
		return
	for name in icon_names:
		if theme.has_icon(name, "EditorIcons"):
			set_dock_tab_icon(control, theme.get_icon(name, "EditorIcons"))
			return


func _set_dock_tab_icon_custom_or_list(control: Control, custom_path: String, fallback_icons: Array) -> void:
	if not control:
		return
	if not custom_path.is_empty() and ResourceLoader.exists(custom_path):
		var tex = load(custom_path)
		if tex:
			set_dock_tab_icon(control, tex)
			return
	_set_dock_tab_icon_from_list(control, fallback_icons)


func _connect_script_editor() -> void:
	script_editor_ref = get_editor_interface().get_script_editor()
	if script_editor_ref:
		script_editor_ref.editor_script_changed.connect(_on_script_changed)
		if script_editor_ref.has_signal("script_saved"):
			script_editor_ref.script_saved.connect(_on_script_saved)

		# Load current script if any
		var current_script = script_editor_ref.get_current_script()
		if current_script:
			_on_script_changed(current_script)

	# Note: FileSystemDock doesn't have file_selected signal
	# Script changes are handled by editor_script_changed above


func _connect_filesystem_signals() -> void:
	var file_system = get_editor_interface().get_resource_filesystem()
	if file_system and not file_system.filesystem_changed.is_connected(_on_filesystem_changed):
		file_system.filesystem_changed.connect(_on_filesystem_changed)


func _on_script_changed(script: Script) -> void:
	if not script:
		_current_script = null
		_pending_script_for_autocreate = null
		_clear_dock_contents()
		return

	_current_script = script
	print("NodeScript: Script changed to %s" % script.resource_path)

	# Check if this script has a NodeScript resource
	var ns_path = _get_nodescript_path(script)

	if not ns_path.is_empty():
		print("NodeScript: Found existing resource at %s" % ns_path)
		_pending_script_for_autocreate = null
		_load_script_in_docks(script)
	else:
		print("NodeScript: No resource found, will auto-create for %s" % script.resource_path)
		# Defer auto-creation with guard to prevent stale calls from rapid clicks
		_pending_script_for_autocreate = script
		call_deferred("_deferred_autocreate_nodescript", script)


func _on_script_saved(script: Script) -> void:
	if script and script == _current_script:
		_refresh_current_from_source()


func _on_filesystem_changed() -> void:
	if _current_script:
		_refresh_current_from_source()


func _get_nodescript_path(script: Script) -> String:
	if not script:
		return ""
	# Typical naming used in examples: res://path/player.nodescript.tres
	var base = script.resource_path.get_basename()
	var candidate_basename = base + ".nodescript.tres"
	if ResourceLoader.exists(candidate_basename):
		return candidate_basename

	# Fallback to older scheme (script.gd.nodescript.tres)
	var candidate_suffix = script.resource_path + ".nodescript.tres"
	if ResourceLoader.exists(candidate_suffix):
		return candidate_suffix

	return ""


func _show_docks() -> void:
	# Docks remain visible by default
	pass


func _hide_docks() -> void:
	# Keep docks visible so users can trigger auto-create
	pass


func _load_script_in_docks(script: Script) -> void:
	# Load script in tree dock
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content and tree_content.has_method("load_script"):
			tree_content.load_script(script)

	# Load script in inspector dock
	if inspector_dock:
		var inspector_content = inspector_dock.get_node_or_null("NodeScriptInspectorDockContent")
		if inspector_content and inspector_content.has_method("load_script"):
			inspector_content.load_script(script)


func _clear_dock_contents() -> void:
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content:
			if tree_content.has_method("clear_tree"):
				tree_content.clear_tree()
			elif tree_content.has_method("load_script"):
				tree_content.load_script(null)
	if inspector_dock:
		var inspector_content = inspector_dock.get_node_or_null("NodeScriptInspectorDockContent")
		if inspector_content:
			if inspector_content.has_method("_clear_editors"):
				inspector_content._clear_editors()
			elif inspector_content.has_method("load_script"):
				inspector_content.load_script(null)


func _on_dock_visibility_changed() -> void:
	if not _pending_script_for_autocreate:
		return
	# Only auto-create when the dock becomes visible (selected/tabbed)
	_attempt_autocreate_if_visible()


func _attempt_autocreate_if_visible() -> void:
	if not _pending_script_for_autocreate:
		return
	if (tree_dock and tree_dock.visible) or (inspector_dock and inspector_dock.visible):
		var created_path = _ensure_nodescript_resource(_pending_script_for_autocreate)
		if not created_path.is_empty():
			_pending_script_for_autocreate = null
			_load_script_in_docks(_current_script)


func _deferred_autocreate_nodescript(script: Script) -> void:
	# Guard: only create if this script is still the current one
	# (prevents stale queued calls from rapid clicks)
	if not script or script != _current_script:
		return

	var created_path = _ensure_nodescript_resource(script)
	if not created_path.is_empty():
		_pending_script_for_autocreate = null
		# Give filesystem a moment to sync before loading
		call_deferred("_load_script_in_docks", script)


func _ensure_nodescript_resource(script: Script) -> String:
	if not script:
		return ""
	var ns_path = _get_nodescript_path(script)
	if not ns_path.is_empty():
		return ns_path

	# Create a new NodeScript resource beside the script
	var base = script.resource_path.get_basename()
	var target_path = base + ".nodescript.tres"
	var res = NodeScriptResource.new()
	res.set_class_name(script.resource_name)

	var err = ResourceSaver.save(res, target_path)
	if err != OK:
		push_error("NodeScript: Failed to auto-create %s (error %d)" % [target_path, err])
		return ""

	print("NodeScript: Auto-created %s" % target_path)

	# Force file system scan to register the new file
	var file_system = get_editor_interface().get_resource_filesystem()
	if file_system:
		file_system.scan()

	# Ensure ResourceLoader sees the new file without stale cache (Godot 4: force replace in cache)
	var _tmp = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_REPLACE)

	return target_path


func _on_tree_item_selected(item_type: String, item_name: String, item_data: Dictionary) -> void:
	# When user selects an item in the tree, show it in the inspector dock
	if inspector_dock:
		var inspector_content = inspector_dock.get_node_or_null("NodeScriptInspectorDockContent")
		if inspector_content and inspector_content.has_method("show_item_editor"):
			inspector_content.show_item_editor(item_type, item_name, item_data)


func _refresh_tree_dock() -> void:
	# Refresh tree dock after inspector makes changes
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content and tree_content.has_method("_build_tree"):
			tree_content._build_tree()


func _refresh_current_from_source() -> void:
	if _is_refreshing_from_fs:
		return
	_is_refreshing_from_fs = true
	if _current_script:
		var path := _current_script.resource_path
		if _last_refresh_path == path:
			_is_refreshing_from_fs = false
			return
		var sync = NodeScriptSyncScript.new()
		sync.load_for_script(_current_script)
		_load_script_in_docks(_current_script)
		_last_refresh_path = path
	call_deferred("_clear_refresh_flag")


func _clear_refresh_flag() -> void:
	_is_refreshing_from_fs = false
	_last_refresh_path = ""


func _safe_remove_dock(control: Control) -> void:
	if control and is_instance_valid(control):
		if control.get_parent():
			remove_control_from_docks(control)
		control.queue_free()


func _on_tree_item_activated(item_type: String, item_name: String) -> void:
	# When user double-clicks an item, could jump to code location
	# For now, just ensure the inspector is visible
	if inspector_dock:
		inspector_dock.visible = true
