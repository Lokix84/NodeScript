@tool
extends VBoxContainer

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const NodeScriptTreeUtils = preload("res://addons/nodescript/utils/tree_utils.gd")
const _NodeScriptSyncScript = preload("res://addons/nodescript/editor/nodescript_sync.gd")

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	anchor_right = 1.0
	anchor_bottom = 1.0

var sync
var editor_plugin: EditorPlugin
var active_script: Script
var tree: Tree
var filter_edit: LineEdit
var tree_filter_text: String = ""
var loading_panel: Panel

# Toolbar buttons
var add_item_button: TextureButton
var options_button: TextureButton
var add_item_menu: PopupMenu
var options_menu: PopupMenu
var tree_context_menu: PopupMenu

# Settings
# Signals
signal item_selected(item_type: String, item_name: String, metadata: Dictionary)
signal item_activated(item_type: String, item_name: String, payload: Dictionary)
var show_enum_values_in_tree: bool = true
var auto_space_enabled: bool = true
var consolidate_blank_lines_visual: bool = true
var show_blank_rows: bool = true

func _ready() -> void:
	# Toolbar
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(toolbar)
	
	# Add button (on left)
	add_item_button = TextureButton.new()
	add_item_button.tooltip_text = "Add item"
	add_item_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_item_button.pressed.connect(_on_add_item_pressed)
	toolbar.add_child(add_item_button)
	
	# Filter (in middle, expands)
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter..."
	filter_edit.clear_button_enabled = true
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filter_edit.text_changed.connect(_on_filter_changed)
	toolbar.add_child(filter_edit)
	
	# Options button (on right)
	options_button = TextureButton.new()
	options_button.tooltip_text = "Options"
	options_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	options_button.pressed.connect(_on_options_button_pressed)
	toolbar.add_child(options_button)
	
	# Tree
	tree = Tree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.item_selected.connect(_on_tree_item_selected)
	tree.item_activated.connect(_on_tree_item_activated)
	tree.gui_input.connect(_on_tree_gui_input)
	add_child(tree)
	
	# Loading panel (overlay, initially hidden)
	_setup_loading_panel()
	
	# Setup menus
	_setup_add_item_menu()
	_setup_options_menu()
	_setup_tree_context_menu()
	_load_config_settings()


func set_editor_plugin(plugin: EditorPlugin) -> void:
	editor_plugin = plugin


func load_script(script: Script) -> void:
	if not script:
		clear_tree()
		_hide_loading_panel()
		return
	
	active_script = script
	
	# Show loading panel while resolving
	_show_loading_panel()
	
	if not sync:
		sync = _NodeScriptSyncScript.new()
	sync.load_for_script(script)
	if not sync or not sync.nodescript:
		clear_tree()
		_hide_loading_panel()
		return
	
	# Build tree
	_build_tree()
	
	# Hide loading panel when done
	_hide_loading_panel()


func clear_tree() -> void:
	if tree:
		tree.clear()


func _build_tree() -> void:
	if not tree or not sync or not sync.nodescript:
		return
	
	tree.clear()
	_ensure_order_map()
	
	var root = tree.create_item()
	var script_item = tree.create_item(root)
	script_item.set_text(0, _get_script_display_name())
	script_item.set_icon(0, _get_editor_icon("Script", "File"))
	script_item.set_metadata(0, {"type": "script"})
	script_item.collapsed = false
	
	# Build true structure
	_build_scope_items(script_item, "", "")


func _ensure_order_map() -> void:
	if not sync:
		return
	if sync.has_method("_ensure_order_map"):
		sync._ensure_order_map()


func _build_scope_items(parent_item: TreeItem, cls: String, region: String) -> void:
	if not parent_item or not sync or not sync.nodescript:
		return
	
	var order := _scope_order_for(cls, region)
	var added: Dictionary = {}
	var last_was_blank := false
	var last_blank_item: TreeItem = null
	
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		
		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", entry.get("id", "")))
		if kind != "blank":
			last_was_blank = false
			last_blank_item = null
		
		match kind:
			"blank":
				if not show_blank_rows:
					continue
				var entry_count := int(entry.get("count", 1))
				if consolidate_blank_lines_visual and last_was_blank:
					if last_blank_item:
						var meta := last_blank_item.get_metadata(0)
						if typeof(meta) == TYPE_DICTIONARY:
							var prev_count := int(meta.get("count", 1))
							meta["count"] = prev_count + (entry_count if entry_count > 0 else 1)
							last_blank_item.set_metadata(0, meta)
					continue
				if not _matches_filter(""):
					continue
				var line_num := int(entry.get("line", 0))
				var blank_item := NodeScriptTreeUtils.create_item(tree, parent_item, " ", {"type": "blank", "name": name, "region": region, "class": cls, "line": line_num, "count": entry_count}, null)
				blank_item.set_custom_color(0, Color(0.6, 0.6, 0.6, 0.5))
				blank_item.set_selectable(0, true)
				added[_order_key(kind, name)] = true
				last_was_blank = true
				last_blank_item = blank_item
			
			"region":
				var region_data := _find_region_entry(name, cls, region)
				if region_data.is_empty():
					continue
				if not _matches_filter(name):
					continue
				var region_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "region", "name": name, "class": cls, "region": region}, _get_editor_icon(_get_region_icon_name(), "Folder"))
				added[_order_key(kind, name)] = true
				_build_scope_items(region_item, cls, name)
			
			"class":
				if cls != "":
					continue
				var class_data := _find_class_entry(name)
				if class_data.is_empty():
					continue
				var cls_region := _entry_region(class_data)
				if cls_region != region:
					continue
				if not _matches_filter(name):
					continue
				var class_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "class", "name": name, "region": region}, _get_editor_icon("MiniObject", "MiniObject"))
				class_item.collapsed = false
				added[_order_key(kind, name)] = true
				_build_scope_items(class_item, name, cls_region)
			
			"signal":
				var sig_entry := _signal_entry(name)
				if sig_entry.is_empty():
					continue
				if NodeScriptUtils.entry_class(sig_entry) != cls or _entry_region(sig_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "signal", "name": name, "region": region, "class": cls}, _get_editor_icon("Signal", "Signal"))
				added[_order_key(kind, name)] = true
				last_was_blank = false
			
			"variable":
				var var_entry := _variable_entry(name)
				if var_entry.is_empty():
					continue
				if NodeScriptUtils.entry_class(var_entry) != cls or _entry_region(var_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var icon_name := _variable_type_icon(var_entry)
				NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "variable", "name": name, "region": region, "class": cls}, _get_editor_icon(icon_name, "MemberProperty"))
				added[_order_key(kind, name)] = true
				last_was_blank = false
			
			"enum":
				var enum_entry := _enum_entry(name)
				if enum_entry.is_empty():
					continue
				if NodeScriptUtils.enum_class(enum_entry) != cls or _entry_region(enum_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var enum_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "enum", "name": name, "region": region, "class": cls}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
				added[_order_key(kind, name)] = true
				if show_enum_values_in_tree:
					var values: Array = _enum_values(enum_entry)
					if typeof(values) == TYPE_ARRAY and not values.is_empty():
						for value_name in values:
							if not _matches_filter(str(value_name)):
								continue
							NodeScriptTreeUtils.create_item(tree, enum_item, str(value_name), {"type": "enum_value", "name": value_name, "enum": name}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
				last_was_blank = false
			
			"function":
				var fn_index := _function_index_by_name(name)
				if fn_index == -1:
					continue
				var fn_entry := _function_entry_by_index(fn_index)
				if NodeScriptUtils.entry_class(fn_entry) != cls or _entry_region(fn_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var func_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "function", "name": name, "index": fn_index, "region": region, "class": cls}, _get_editor_icon("MemberMethod", "MemberMethod"))
				func_item.collapsed = true
				added[_order_key(kind, name)] = true
				last_was_blank = false


func _scope_order_for(cls: String, region: String) -> Array:
	if not sync or not sync.nodescript:
		return []
	var key := _scope_key(cls, region)
	var order_map: Dictionary = sync.nodescript.body.get("order", {})
	if order_map.has(key):
		var result = order_map[key]
		if typeof(result) == TYPE_ARRAY:
			return result
	return []


func _scope_key(cls: String, region: String) -> String:
	return str(cls) + "|" + str(region)


func _order_key(kind: String, name: String) -> String:
	return kind + ":" + name


func _find_region_entry(name: String, cls: String, region: String) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			if str(entry.get("class", "")) == cls and _entry_region(entry) == region:
				return entry
	return {}


func _find_class_entry(name: String) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var classes: Array = sync.nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return entry
	return {}


func _signal_entry(name: String) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	return signals_dict.get(name, {})


func _variable_entry(name: String) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var variables: Array = sync.nodescript.body.get("variables", [])
	for entry in variables:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == name:
			return entry
	return {}


func _enum_entry(name: String) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	return enums_dict.get(name, {})


func _function_index_by_name(name: String) -> int:
	if not sync or not sync.nodescript:
		return -1
	var functions: Array = sync.nodescript.body.get("functions", [])
	for i in range(functions.size()):
		var entry = functions[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == name:
			return i
	return -1


func _function_entry_by_index(index: int) -> Dictionary:
	if not sync or not sync.nodescript:
		return {}
	var functions: Array = sync.nodescript.body.get("functions", [])
	if index >= 0 and index < functions.size():
		return functions[index]
	return {}


func _entry_region(entry: Dictionary) -> String:
	return str(entry.get("region", "")).strip_edges()


func _get_script_display_name() -> String:
	if active_script:
		return active_script.resource_path.get_file()
	return "Script"


func _setup_add_item_menu() -> void:
	if add_item_menu:
		return
	add_item_menu = PopupMenu.new()
	add_item_menu.name = "AddItemMenu"
	add_item_menu.add_item("Signal", 1)
	add_item_menu.set_item_icon(0, _get_editor_icon("MemberSignal", "Signal"))
	add_item_menu.add_item("Variable", 2)
	add_item_menu.set_item_icon(1, _get_editor_icon("MemberProperty", "MemberProperty"))
	add_item_menu.add_item("Enum", 3)
	add_item_menu.set_item_icon(2, _get_editor_icon("Enumeration", "Enum"))
	add_item_menu.add_item("Function", 4)
	add_item_menu.set_item_icon(3, _get_editor_icon("MemberMethod", "MemberMethod"))
	add_item_menu.add_item("Region", 5)
	add_item_menu.set_item_icon(4, _get_editor_icon("Group", "Folder"))
	add_item_menu.add_item("Class", 6)
	add_item_menu.set_item_icon(5, _get_editor_icon("MiniObject", "Node"))
	add_item_menu.id_pressed.connect(_on_add_item_menu_id_pressed)
	add_child(add_item_menu)
	if add_item_button:
		add_item_button.texture_normal = _get_editor_icon("Add", "Add")


func _setup_options_menu() -> void:
	if options_menu:
		return
	options_menu = PopupMenu.new()
	options_menu.name = "OptionsMenu"
	options_menu.add_check_item("Show enum values", 0)
	options_menu.set_item_checked(0, show_enum_values_in_tree)
	options_menu.add_check_item("Auto space between types", 1)
	options_menu.set_item_checked(1, auto_space_enabled)
	options_menu.add_check_item("Show blank rows (visual)", 2)
	options_menu.set_item_checked(2, show_blank_rows)
	options_menu.add_check_item("Consolidate blank spaces (visual)", 3)
	options_menu.set_item_checked(3, consolidate_blank_lines_visual)
	options_menu.hide_on_checkable_item_selection = true
	options_menu.id_pressed.connect(_on_options_menu_id_pressed)
	add_child(options_menu)
	if options_button:
		options_button.texture_normal = _get_editor_icon("GuiTabMenuHl", "Menu")


func _setup_tree_context_menu() -> void:
	if tree_context_menu:
		return
	tree_context_menu = PopupMenu.new()
	tree_context_menu.name = "TreeContextMenu"
	tree_context_menu.id_pressed.connect(_on_tree_context_menu_id_pressed)
	add_child(tree_context_menu)


func _setup_loading_panel() -> void:
	# Create semi-transparent overlay panel
	loading_panel = Panel.new()
	loading_panel.name = "LoadingPanel"
	loading_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loading_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loading_panel.modulate = Color(0, 0, 0, 0.7) # Semi-transparent dark overlay
	loading_panel.visible = false
	add_child(loading_panel)
	move_child(loading_panel, -1) # Move to front (above tree)
	
	# Add label in center
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	loading_panel.add_child(vbox)
	
	var label = Label.new()
	label.text = "Loading Nodescript"
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(label)


func _show_loading_panel() -> void:
	if loading_panel:
		loading_panel.visible = true


func _hide_loading_panel() -> void:
	if loading_panel:
		loading_panel.visible = false


func _load_config_settings() -> void:
	show_enum_values_in_tree = NodeScriptConfig.get_setting("show_enum_values_in_tree", true)
	auto_space_enabled = NodeScriptConfig.get_auto_space_enabled()
	show_blank_rows = NodeScriptConfig.get_show_blank_rows()
	consolidate_blank_lines_visual = NodeScriptConfig.get_consolidate_blank_lines_visual()
	consolidate_blank_lines_visual = NodeScriptConfig.get_setting("consolidate_blank_lines", true)
	show_blank_rows = NodeScriptConfig.get_setting("show_blank_rows", true)


func _on_add_item_pressed() -> void:
	if add_item_menu:
		add_item_menu.popup(Rect2i(add_item_button.global_position + Vector2(0, add_item_button.size.y), Vector2i(200, 0)))


func _on_options_button_pressed() -> void:
	if options_menu:
		# Update checkmarks
		options_menu.set_item_checked(0, show_enum_values_in_tree)
		options_menu.set_item_checked(1, auto_space_enabled)
		options_menu.set_item_checked(2, show_blank_rows)
		options_menu.set_item_checked(3, consolidate_blank_lines_visual)
		options_menu.popup(Rect2i(options_button.global_position + Vector2(0, options_button.size.y), Vector2i(200, 0)))


func _on_add_item_menu_id_pressed(id: int) -> void:
	# Emit signal to inspector dock to handle creation
	match id:
		1: # Signal
			item_activated.emit("signal_add", "", {})
		2: # Variable
			item_activated.emit("variable_add", "", {})
		3: # Enum
			item_activated.emit("enum_add", "", {})
		4: # Function
			item_activated.emit("function_add", "", {})
		5: # Region
			item_activated.emit("region_add", "", {})
		6: # Class
			item_activated.emit("class_add", "", {})


func _on_options_menu_id_pressed(id: int) -> void:
	match id:
		0: # Show enum values
			show_enum_values_in_tree = !show_enum_values_in_tree
			NodeScriptConfig.set_setting("show_enum_values_in_tree", show_enum_values_in_tree)
			_build_tree()
		1: # Auto space
			auto_space_enabled = !auto_space_enabled
			NodeScriptConfig.set_auto_space_enabled(auto_space_enabled)
			_build_tree()
		2: # Show blank rows (visual)
			show_blank_rows = !show_blank_rows
			NodeScriptConfig.set_show_blank_rows(show_blank_rows)
			_build_tree()
		3: # Consolidate blank lines (visual)
			consolidate_blank_lines_visual = !consolidate_blank_lines_visual
			NodeScriptConfig.set_consolidate_blank_lines_visual(consolidate_blank_lines_visual)
			_build_tree()


func _matches_filter(text: String) -> bool:
	if tree_filter_text.is_empty():
		return true
	return text.to_lower().find(tree_filter_text) != -1


func _on_tree_gui_input(event: InputEvent) -> void:
	# Handle right-click for context menu
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Get the item at mouse position and select it
		var mouse_pos = tree.get_local_mouse_position()
		var item_at_pos = tree.get_item_at_position(mouse_pos)
		if item_at_pos:
			item_at_pos.select(0)
		
		var selected = tree.get_selected()
		if not selected:
			return
		
		var metadata = selected.get_metadata(0)
		if not metadata:
			return
		
		var item_type = str(metadata.get("type", ""))
		var item_name = str(metadata.get("name", ""))
		
		# Build context menu based on item type
		tree_context_menu.clear()
		
		# All items except blanks can jump to line
		if item_type != "blank" and item_type != "script":
			tree_context_menu.add_item("Jump to Line", 0)
			tree_context_menu.set_item_icon(0, _get_editor_icon("ArrowRight", "Forward"))
			tree_context_menu.add_separator()
		
		# Editable items
		if item_type in ["function", "variable", "signal", "enum", "region", "class"]:
			tree_context_menu.add_item("Edit", 1)
			tree_context_menu.set_item_icon(tree_context_menu.get_item_count() - 1, _get_editor_icon("Edit", "Edit"))
			tree_context_menu.add_item("Delete", 2)
			tree_context_menu.set_item_icon(tree_context_menu.get_item_count() - 1, _get_editor_icon("Remove", "Remove"))
		
		if tree_context_menu.item_count > 0:
			# Store metadata for handler
			tree_context_menu.set_meta("item_metadata", metadata)
			var global_pos := Vector2i((tree.get_screen_position() + mouse_pos).round())
			tree_context_menu.reset_size()
			tree_context_menu.position = global_pos
			tree_context_menu.popup()


func _on_tree_item_mouse_selected(position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	
	var selected = tree.get_selected()
	if not selected:
		return
	
	var metadata = selected.get_metadata(0)
	if not metadata:
		return
	
	var item_type = str(metadata.get("type", ""))
	var item_name = str(metadata.get("name", ""))
	
	# Build context menu based on item type
	tree_context_menu.clear()
	
	# All items except blanks can jump to line
	if item_type != "blank" and item_type != "script":
		tree_context_menu.add_item("Jump to Line", 0)
		tree_context_menu.set_item_icon(0, _get_editor_icon("ArrowRight", "Forward"))
		tree_context_menu.add_separator()
	
	# Editable items
	if item_type in ["function", "variable", "signal", "enum", "region", "class"]:
		tree_context_menu.add_item("Edit", 1)
		tree_context_menu.set_item_icon(tree_context_menu.get_item_count() - 1, _get_editor_icon("Edit", "Edit"))
		tree_context_menu.add_item("Delete", 2)
		tree_context_menu.set_item_icon(tree_context_menu.get_item_count() - 1, _get_editor_icon("Remove", "Remove"))
	
	if tree_context_menu.item_count > 0:
		# Store metadata for handler
		tree_context_menu.set_meta("item_metadata", metadata)
		var global_pos := Vector2i((tree.get_screen_position() + position).round())
		tree_context_menu.reset_size()
		tree_context_menu.position = global_pos
		tree_context_menu.popup()


func _on_tree_context_menu_id_pressed(id: int) -> void:
	var metadata = tree_context_menu.get_meta("item_metadata", {})
	if metadata.is_empty():
		return
	
	var item_type = str(metadata.get("type", ""))
	var item_name = str(metadata.get("name", ""))
	
	match id:
		0: # Jump to Line
			_jump_to_line_in_editor(metadata)
		1: # Edit
			item_selected.emit(item_type, item_name, metadata)
		2: # Delete
			# Emit as activated with special delete action
			item_activated.emit(item_type + "_delete", item_name, metadata)


func _jump_to_line_in_editor(metadata: Dictionary) -> void:
	if not editor_plugin or not active_script:
		return
	
	# Try to get line number from metadata or order entry
	var line_num = int(metadata.get("line", 0))
	
	# If no line in metadata, try to find it from the order map
	if line_num == 0:
		var item_type = str(metadata.get("type", ""))
		var item_name = str(metadata.get("name", ""))
		var item_class = str(metadata.get("class", ""))
		var item_region = str(metadata.get("region", ""))
		
		# Look up in order map
		var order := _scope_order_for(item_class, item_region)
		for entry in order:
			if typeof(entry) == TYPE_DICTIONARY:
				if str(entry.get("type", "")) == item_type and str(entry.get("name", "")) == item_name:
					line_num = int(entry.get("line", 0))
					break
	
	if line_num > 0:
		# Line numbers in order map appear to be already 0-indexed for editor
		editor_plugin.get_editor_interface().edit_script(active_script, line_num, 0)
	else:
		# Fallback: just open the script
		editor_plugin.get_editor_interface().edit_script(active_script)


func _variable_type_icon(entry: Dictionary) -> String:
	var raw := str(entry.get("type", "")).strip_edges()
	var lower := raw.to_lower()

	if raw == "":
		return _first_icon(["Variant", "Object"])

	var candidates: Array[String] = []
	candidates.append(raw)
	candidates.append("Member" + raw)
	candidates.append(lower)
	candidates.append("member" + lower)

	match lower:
		"bool", "boolean":
			candidates.append_array(["Boolean"])
		"int", "integer":
			candidates.append_array(["int", "memberint", "Integer", "Number"])
		"float", "real":
			candidates.append_array(["Float"])
		"string":
			candidates.append_array(["String"])
		"array":
			candidates.append_array(["Array"])
		"dictionary", "dict", "map":
			candidates.append_array(["Dictionary"])

	candidates.append_array(["Object", "Variant"])
	return _first_icon(candidates)


func _get_enum_icon_name() -> String:
	if _has_editor_icon("Enumeration"):
		return "Enumeration"
	if _has_editor_icon("Enum"):
		return "Enum"
	return "Node"


func _get_region_icon_name() -> String:
	if _has_editor_icon("VisualShaderNodeComment"):
		return "VisualShaderNodeComment"
	if _has_editor_icon("Group"):
		return "Group"
	return "Node"


func _enum_values(entry: Dictionary) -> Array:
	var values_data = entry.get("values", [])
	if typeof(values_data) == TYPE_ARRAY:
		return values_data
	if typeof(values_data) == TYPE_DICTIONARY:
		return values_data.keys()
	return []


func _has_editor_icon(name: String) -> bool:
	var base_control: Control = editor_plugin.get_editor_interface().get_base_control() if editor_plugin and editor_plugin.get_editor_interface() else null
	if base_control and base_control.has_theme_icon(name, "EditorIcons"):
		return true
	if tree and tree.has_theme_icon(name, "EditorIcons"):
		return true
	return false


func _first_icon(candidates: Array[String]) -> String:
	for name in candidates:
		if _has_editor_icon(name):
			return name
	return "Object"


func _get_editor_icon(name: String, fallback: String = "Node") -> Texture2D:
	var theme: Theme = null
	var editor_icon: Texture2D = null

	if tree:
		var tree_theme := tree.get_theme()
		if tree_theme:
			theme = tree_theme

	if theme == null:
		var self_theme := get_theme()
		if self_theme:
			theme = self_theme

	if theme == null and editor_plugin and editor_plugin.get_editor_interface():
		var base_control := editor_plugin.get_editor_interface().get_base_control()
		if base_control:
			var base_theme := base_control.get_theme()
			if base_theme:
				theme = base_theme
			editor_icon = base_control.get_theme_icon(name, "EditorIcons")
			if editor_icon == null:
				editor_icon = base_control.get_theme_icon(fallback, "EditorIcons")

	if editor_icon:
		return editor_icon
	if theme and theme.has_icon(name, "EditorIcons"):
		return theme.get_icon(name, "EditorIcons")
	if theme and theme.has_icon(fallback, "EditorIcons"):
		return theme.get_icon(fallback, "EditorIcons")
	return null


func _on_tree_item_selected() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var metadata = selected.get_metadata(0)
	if metadata:
		var item_type = str(metadata.get("type", ""))
		var item_name = str(metadata.get("name", ""))
		item_selected.emit(item_type, item_name, metadata)


func _on_tree_item_activated() -> void:
	var selected = tree.get_selected()
	if not selected:
		return
	
	var metadata = selected.get_metadata(0)
	if metadata:
		var item_type = str(metadata.get("type", ""))
		var item_name = str(metadata.get("name", ""))
		
		# Jump to line for all items except blanks and script root
		if item_type != "blank" and item_type != "script":
			_jump_to_line_in_editor(metadata)
		else:
			item_activated.emit(item_type, item_name, {})


func _on_filter_changed(new_text: String) -> void:
	tree_filter_text = new_text.to_lower()
	_build_tree()
