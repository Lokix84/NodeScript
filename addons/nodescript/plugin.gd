@tool
extends EditorPlugin

const NodeScriptTreeDockScript: Script = preload("res://addons/nodescript/editor/nodescript_tree_dock.gd")
const NodeScriptResource = preload("res://addons/nodescript/core/nodescript_resource.gd")
const NodeScriptSync = preload("res://addons/nodescript/editor/nodescript_sync.gd")

var tree_dock: Control
var script_editor_ref: ScriptEditor
var _current_script: Script
var _pending_script_for_autocreate: Script
var _editor_ready: bool = false
var _ready_frame_count: int = 0

func show_clear_nodescript_files_dialog() -> void:
	var confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.dialog_autowrap = true
	confirmation_dialog.title = "Clear All .nodescript.tres Files"
	confirmation_dialog.ok_button_text = "Clear All"
	confirmation_dialog.cancel_button_text = "Cancel"

	var label = Label.new()
	label.text = "This will DELETE all .nodescript.tres files in the project.\n\nThis action cannot be undone!\n\nAre you sure you want to proceed?"
	confirmation_dialog.add_child(label)

	confirmation_dialog.confirmed.connect(_perform_clear_nodescript_files)

	var base_control = get_editor_interface().get_base_control()
	if base_control:
		base_control.add_child(confirmation_dialog)
		confirmation_dialog.popup_centered_ratio(0.4)
	else:
		push_error("NodeScript: Unable to show confirmation dialog (no base control).")

func _enter_tree() -> void:
	# Initialization happens in _enable_plugin when the user enables the addon.
	pass

func _exit_tree() -> void:
	_disable_plugin()


func _enable_plugin() -> void:
	_setup_docks()
	_connect_script_editor()
	# Mark ready on the next frame to avoid startup churn
	call_deferred("_mark_editor_ready")


func _disable_plugin() -> void:
	_editor_ready = false
	_pending_script_for_autocreate = null
	_current_script = null

	_clear_dock_contents()

	if tree_dock and is_instance_valid(tree_dock):
		remove_control_from_docks(tree_dock)
		tree_dock.queue_free()
		tree_dock = null

	if script_editor_ref:
		if script_editor_ref.editor_script_changed.is_connected(_on_script_changed):
			script_editor_ref.editor_script_changed.disconnect(_on_script_changed)
		script_editor_ref = null

func _mark_editor_ready() -> void:
	_editor_ready = true
	if _pending_script_for_autocreate:
		call_deferred("_attempt_autocreate_if_visible")

func _on_clear_nodescript_files_pressed() -> void:
	show_clear_nodescript_files_dialog()

func _perform_clear_nodescript_files() -> void:
	var file_system = get_editor_interface().get_resource_filesystem()
	var deleted_files = []
	_delete_nodescript_files_recursive("res://", deleted_files)

	# Refresh file system
	if file_system:
		file_system.scan()

	if deleted_files.is_empty():
		push_warning("NodeScript: No .nodescript.tres files found to delete.")
	else:
		push_warning("NodeScript: Cleared %d .nodescript.tres file(s)." % deleted_files.size())

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
			else:
				push_error("NodeScript: Failed to delete %s (error %d)" % [full_path, err])

		file_name = dir.get_next()

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

	# Keep docks present even before a NodeScript exists
	tree_dock.visible = true

	# Restore previous focus so docks don't steal it (deferred to let dock creation finish)
	if prev_focus and is_instance_valid(prev_focus):
		call_deferred("_deferred_restore_focus", prev_focus)

	# React when a dock tab becomes visible to trigger auto-create if needed
	tree_dock.visibility_changed.connect(_on_dock_visibility_changed)

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

		# Load current script if any
		var current_script = script_editor_ref.get_current_script()
		if current_script:
			_on_script_changed(current_script)

# Note: FileSystemDock doesn't have file_selected signal
# Script changes are handled by editor_script_changed above
func _on_script_changed(script: Script) -> void:
	if not script:
		_current_script = null
		_pending_script_for_autocreate = null
		_clear_dock_contents()
		return
	
	# Skip if script file doesn't exist on disk
	if not FileAccess.file_exists(script.resource_path):
		_current_script = null
		_pending_script_for_autocreate = null
		_clear_dock_contents()
		return

	_current_script = script
	
	# Uncomment for debugging
	#if _editor_ready:
	#	print("NodeScript: Script changed to %s" % script.resource_path)
	
	# Check if this script has a NodeScript resource
	var ns_path = _get_nodescript_path(script)

	if not ns_path.is_empty():
		# Uncomment for debugging
		#if _editor_ready:
		#	print("NodeScript: Found existing resource at %s" % ns_path)
		_pending_script_for_autocreate = null
		_load_script_in_docks(script)
	else:
		# Only auto-create after editor is ready (avoid startup churn)
		_pending_script_for_autocreate = script
		if _editor_ready:
			call_deferred("_deferred_autocreate_nodescript", script)
		else:
			_clear_dock_contents()

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

func _load_script_in_docks(script: Script) -> void:
	# Uncomment for debugging
	#print("NodeScript: Loading script in docks: %s" % script.resource_path)
	# Load script in tree dock
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content and tree_content.has_method("load_script"):
			# Uncomment for debugging
			#print("NodeScript: Loading in tree dock")
			tree_content.load_script(script)

func _clear_dock_contents() -> void:
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content:
			if tree_content.has_method("clear_tree"):
				tree_content.clear_tree()
			elif tree_content.has_method("load_script"):
				tree_content.load_script(null)

func _on_dock_visibility_changed() -> void:
	if not _pending_script_for_autocreate:
		return
	# Only auto-create when the dock becomes visible (selected/tabbed)
	_attempt_autocreate_if_visible()

func _attempt_autocreate_if_visible() -> void:
	if not _pending_script_for_autocreate:
		return
	if (tree_dock and tree_dock.visible):
		var created_path = _ensure_nodescript_resource(_pending_script_for_autocreate)
		if not created_path.is_empty():
			_pending_script_for_autocreate = null
			_load_script_in_docks(_current_script)

func _deferred_autocreate_nodescript(script: Script) -> void:
	# Only create if script is valid (don't check if it's still current - allows batch creation during startup)
	if not script:
		return

	var created_path = _ensure_nodescript_resource(script)
	if not created_path.is_empty():
		# If this script is still the current one, load it in docks
		if script == _current_script:
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

	var sync = NodeScriptSync.new()
	var res = NodeScriptResource.new()
	sync.nodescript = res
	sync._ensure_body_structure()
	# Parse the existing script to populate the resource
	sync._sync_from_script_source(script)
	res = sync.nodescript

	var err = ResourceSaver.save(res, target_path)
	if err != OK:
		push_error("NodeScript: Failed to auto-create %s (error %d)" % [target_path, err])
		return ""

	# Force file system scan to register the new file
	var file_system = get_editor_interface().get_resource_filesystem()
	if file_system:
		file_system.scan()

	# Ensure ResourceLoader sees the new file without stale cache
	var _tmp = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_REPLACE)

	return target_path

func _refresh_tree_dock() -> void:
	if tree_dock:
		var tree_content = tree_dock.get_node_or_null("NodeScriptTreeDockContent")
		if tree_content and tree_content.has_method("_build_tree"):
			tree_content._build_tree()
