@tool
extends VBoxContainer
class_name NodeScriptTreeDockContent

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const NodeScriptTreeUtils = preload("res://addons/nodescript/utils/tree_utils.gd")
const _NodeScriptSyncScript = preload("res://addons/nodescript/editor/nodescript_sync.gd")

const DISPLAY_GROUPED_BY_TYPE := 0
const DISPLAY_TRUE_STRUCTURE := 1
const DISPLAY_ALPHABETICAL := 2

signal item_selected(item_type: String, item_name: String, metadata: Dictionary)
signal item_activated(item_type: String, item_name: String, payload: Dictionary)

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
var options_button: TextureButton
var options_menu: PopupMenu
var tree_context_menu: PopupMenu

var show_enum_values_in_tree: bool = true
var display_mode: int = DISPLAY_TRUE_STRUCTURE


func _ready() -> void:
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(toolbar)

	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter..."
	filter_edit.clear_button_enabled = true
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filter_edit.text_changed.connect(_on_filter_changed)
	toolbar.add_child(filter_edit)

	options_button = TextureButton.new()
	options_button.tooltip_text = "Display options"
	options_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	options_button.pressed.connect(_on_options_button_pressed)
	toolbar.add_child(options_button)

	tree = Tree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.item_selected.connect(_on_tree_item_selected)
	tree.item_activated.connect(_on_tree_item_activated)
	tree.gui_input.connect(Callable(self, "_on_tree_gui_input"))
	add_child(tree)

	_setup_loading_panel()
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
	_show_loading_panel()

	if not sync:
		sync = _NodeScriptSyncScript.new()
	var ok: bool = sync.load_for_script(script)
	if not sync or not sync.nodescript:
		if not ok:
			push_error("NodeScript: Failed to load NodeScript data for %s" % (script.resource_path if script else ""))
		clear_tree()
		_hide_loading_panel()
		return

	_build_tree()
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

	if display_mode == DISPLAY_GROUPED_BY_TYPE:
		_build_grouped_items(script_item)
	else:
		_build_scope_items(script_item, "", "")


func _ensure_order_map() -> void:
	if not sync:
		return
	if sync.has_method("_ensure_order_map"):
		sync._ensure_order_map()


func _build_scope_items(parent_item: TreeItem, cls: String, region: String) -> void:
	if not parent_item or not sync or not sync.nodescript:
		return

	var order := _visual_entries_for_scope(cls, region)
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", entry.get("id", "")))
		var line_num := int(entry.get("line", 0))

		match kind:
			"region":
				var region_data := _find_region_entry(name, cls, region)
				if region_data.is_empty():
					continue
				var has_descendant := _scope_has_filter_match(cls, name)
				if not _matches_filter(name) and not has_descendant:
					continue
				var region_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "region", "name": name, "class": cls, "region": region, "line": line_num}, _get_editor_icon(_get_region_icon_name(), "Folder"))
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
				var has_descendant_class := _scope_has_filter_match(name, cls_region)
				if not _matches_filter(name) and not has_descendant_class:
					continue
				var class_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "class", "name": name, "region": region, "line": line_num}, _get_editor_icon("MiniObject", "MiniObject"))
				class_item.collapsed = false
				_build_scope_items(class_item, name, cls_region)

			"signal":
				var sig_entry := _signal_entry(name)
				if sig_entry.is_empty():
					continue
				if NodeScriptUtils.entry_class(sig_entry) != cls or _entry_region(sig_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "signal", "name": name, "region": region, "class": cls, "line": line_num}, _get_editor_icon("Signal", "Signal"))

			"variable":
				var var_entry := _variable_entry(name)
				if var_entry.is_empty():
					continue
				if NodeScriptUtils.entry_class(var_entry) != cls or _entry_region(var_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var icon_name := _variable_type_icon(var_entry)
				NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "variable", "name": name, "region": region, "class": cls, "line": line_num}, _get_editor_icon(icon_name, "MemberProperty"))

			"enum":
				var enum_entry := _enum_entry(name)
				if enum_entry.is_empty():
					continue
				if NodeScriptUtils.enum_class(enum_entry) != cls or _entry_region(enum_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var enum_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "enum", "name": name, "region": region, "class": cls, "line": line_num}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
				if show_enum_values_in_tree:
					var values: Array = _enum_values(enum_entry)
					if typeof(values) == TYPE_ARRAY and not values.is_empty():
						for value_name in values:
							if not _matches_filter(str(value_name)):
								continue
							NodeScriptTreeUtils.create_item(tree, enum_item, str(value_name), {"type": "enum_value", "name": value_name, "enum": name}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))

			"function":
				var fn_index := _function_index_by_name(name)
				if fn_index == -1:
					continue
				var fn_entry := _function_entry_by_index(fn_index)
				if NodeScriptUtils.entry_class(fn_entry) != cls or _entry_region(fn_entry) != region:
					continue
				if not _matches_filter(name):
					continue
				var func_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "function", "name": name, "index": fn_index, "region": region, "class": cls, "line": line_num}, _get_editor_icon("MemberMethod", "MemberMethod"))
				func_item.collapsed = true


func _visual_entries_for_scope(cls: String, region: String) -> Array:
	var entries: Array = []
	for entry in _scope_order_for(cls, region):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) == "blank":
			continue
		entries.append(entry)

	match display_mode:
		DISPLAY_TRUE_STRUCTURE:
			return entries
		DISPLAY_ALPHABETICAL:
			entries.sort_custom(Callable(self, "_sort_entries_by_name"))
			return entries
		DISPLAY_GROUPED_BY_TYPE:
			var grouped: Dictionary = {}
			for entry in entries:
				var t := str(entry.get("type", ""))
				if not grouped.has(t):
					grouped[t] = []
				grouped[t].append(entry)

			var type_order := [
				"region",
				"class",
				"signal",
				"variable",
				"enum",
				"function"
			]
			var ordered: Array = []

			for t in type_order:
				if grouped.has(t):
					var arr: Array = grouped[t]
					arr.sort_custom(Callable(self, "_sort_entries_by_name"))
					ordered.append_array(arr)

			for t in grouped.keys():
				if t in type_order:
					continue
				var arr: Array = grouped[t]
				arr.sort_custom(Callable(self, "_sort_entries_by_name"))
				ordered.append_array(arr)

			return ordered

	return entries


func _all_visual_entries() -> Array:
	var entries: Array = []
	if not sync or not sync.nodescript:
		return entries
	var order_map: Dictionary = sync.nodescript.body.get("order", {})
	for key in order_map.keys():
		var scope_entries = order_map[key]
		if typeof(scope_entries) != TYPE_ARRAY:
			continue
		for entry in scope_entries:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if str(entry.get("type", "")) == "blank":
				continue
			entries.append(entry)
	return entries


func _build_grouped_items(parent_item: TreeItem) -> void:
	if not parent_item:
		return

	var grouped: Dictionary = {}
	for entry in _all_visual_entries():
		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", entry.get("id", "")))
		if name.is_empty():
			continue
		if not _matches_filter(name):
			continue
		if not grouped.has(kind):
			grouped[kind] = []
		grouped[kind].append(entry)

	var type_order := [
		"region",
		"class",
		"signal",
		"variable",
		"enum",
		"function"
	]

	for kind in type_order:
		if not grouped.has(kind):
			continue
		var items: Array = grouped[kind]
		items.sort_custom(Callable(self, "_sort_entries_by_name"))

		var group_item := NodeScriptTreeUtils.create_item(tree, parent_item, _type_label(kind), {"type": "group", "group": kind}, _type_icon(kind))
		group_item.set_selectable(0, false)

		for entry in items:
			var name := str(entry.get("name", entry.get("id", "")))
			var line_num := int(entry.get("line", 0))
			match kind:
				"region":
					NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "region", "name": name, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon(_get_region_icon_name(), "Folder"))
				"class":
					NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "class", "name": name, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon("MiniObject", "MiniObject"))
				"signal":
					NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "signal", "name": name, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon("Signal", "Signal"))
				"variable":
					var icon_name := _variable_type_icon(entry)
					NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "variable", "name": name, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon(icon_name, "MemberProperty"))
				"enum":
					var enum_item := NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "enum", "name": name, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
					if show_enum_values_in_tree:
						var values: Array = _enum_values(_enum_entry(name))
						if typeof(values) == TYPE_ARRAY and not values.is_empty():
							for value_name in values:
								if not _matches_filter(str(value_name)):
									continue
								NodeScriptTreeUtils.create_item(tree, enum_item, str(value_name), {"type": "enum_value", "name": value_name, "enum": name}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
				"function":
					var fn_index := _function_index_by_name(name)
					NodeScriptTreeUtils.create_item(tree, group_item, name, {"type": "function", "name": name, "index": fn_index, "region": str(entry.get("region", "")), "class": str(entry.get("class", "")), "line": line_num}, _get_editor_icon("MemberMethod", "MemberMethod"))


func _type_label(kind: String) -> String:
	match kind:
		"region":
			return "Regions"
		"class":
			return "Classes"
		"signal":
			return "Signals"
		"variable":
			return "Variables"
		"enum":
			return "Enums"
		"function":
			return "Functions"
	return kind.capitalize()


func _type_icon(kind: String) -> Texture2D:
	match kind:
		"region":
			return _get_editor_icon(_get_region_icon_name(), "Folder")
		"class":
			return _get_editor_icon("MiniObject", "MiniObject")
		"signal":
			return _get_editor_icon("Signal", "Signal")
		"variable":
			return _get_editor_icon("MemberProperty", "MemberProperty")
		"enum":
			return _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name())
		"function":
			return _get_editor_icon("MemberMethod", "MemberMethod")
	return _get_editor_icon("Node", "Node")


func _sort_entries_by_name(a: Dictionary, b: Dictionary) -> bool:
	var name_a := str(a.get("name", a.get("id", ""))).to_lower()
	var name_b := str(b.get("name", b.get("id", ""))).to_lower()
	if name_a == name_b:
		return str(a.get("type", "")).to_lower() < str(b.get("type", "")).to_lower()
	return name_a < name_b


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


func _setup_options_menu() -> void:
	if options_menu:
		return
	options_menu = PopupMenu.new()
	options_menu.name = "OptionsMenu"
	options_menu.hide_on_checkable_item_selection = true
	options_menu.add_radio_check_item("True Structure", DISPLAY_TRUE_STRUCTURE)
	options_menu.add_radio_check_item("Alphabetical", DISPLAY_ALPHABETICAL)
	options_menu.add_radio_check_item("Grouped by Types", DISPLAY_GROUPED_BY_TYPE)
	options_menu.add_separator()
	options_menu.add_item("Delete all .nodescript.tres files...", 999)
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
	loading_panel = Panel.new()
	loading_panel.name = "LoadingPanel"
	loading_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loading_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loading_panel.modulate = Color(0, 0, 0, 0.7)
	loading_panel.visible = false
	add_child(loading_panel)
	move_child(loading_panel, -1)

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
	show_enum_values_in_tree = bool(NodeScriptConfig.get_setting("show_enum_values_in_tree", true))
	var mode := NodeScriptConfig.get_tree_display_mode()
	if not [DISPLAY_GROUPED_BY_TYPE, DISPLAY_TRUE_STRUCTURE, DISPLAY_ALPHABETICAL].has(mode):
		mode = DISPLAY_TRUE_STRUCTURE
	display_mode = mode


func _on_options_button_pressed() -> void:
	if not options_menu:
		return
	for i in range(options_menu.get_item_count()):
		if options_menu.is_item_checkable(i):
			var id := options_menu.get_item_id(i)
			options_menu.set_item_checked(i, id == display_mode)
	options_menu.popup(Rect2i(options_button.global_position + Vector2(0, options_button.size.y), Vector2i(220, 0)))


func _on_options_menu_id_pressed(id: int) -> void:
	if not [DISPLAY_GROUPED_BY_TYPE, DISPLAY_TRUE_STRUCTURE, DISPLAY_ALPHABETICAL].has(id):
		if id == 999 and editor_plugin and editor_plugin.has_method("show_clear_nodescript_files_dialog"):
			editor_plugin.show_clear_nodescript_files_dialog()
		return
	display_mode = id
	NodeScriptConfig.set_tree_display_mode(display_mode)
	_build_tree()


func _matches_filter(text: String) -> bool:
	if tree_filter_text.is_empty():
		return true
	return text.to_lower().find(tree_filter_text) != -1


func _scope_has_filter_match(cls: String, region: String) -> bool:
	# If no filter, everything matches.
	if tree_filter_text.is_empty():
		return true

	var entries := _scope_order_for(cls, region)
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", entry.get("id", "")))
		if _matches_filter(name):
			return true
		var kind := str(entry.get("type", ""))
		if kind == "region":
			if _scope_has_filter_match(cls, name):
				return true
		elif kind == "class":
			var class_entry := _find_class_entry(name)
			var cls_region := _entry_region(class_entry)
			if _scope_has_filter_match(name, cls_region):
				return true
	return false


func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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
		if item_type == "script" or item_type == "group":
			return

		tree_context_menu.clear()
		tree_context_menu.add_item("Jump to Line", 0)
		tree_context_menu.set_item_icon(0, _get_editor_icon("ArrowRight", "Forward"))
		tree_context_menu.set_meta("item_metadata", metadata)
		var global_pos := Vector2i((tree.get_screen_position() + mouse_pos).round())
		tree_context_menu.reset_size()
		tree_context_menu.position = global_pos
		tree_context_menu.popup()


func _on_tree_context_menu_id_pressed(id: int) -> void:
	var metadata = tree_context_menu.get_meta("item_metadata", {})
	if metadata.is_empty():
		return
	if id == 0:
		_jump_to_line_in_editor(metadata)


func _jump_to_line_in_editor(metadata: Dictionary) -> void:
	if not editor_plugin or not active_script:
		return

	var line_num = int(metadata.get("line", 0))

	if line_num == 0:
		var item_type = str(metadata.get("type", ""))
		var item_name = str(metadata.get("name", ""))
		var item_class = str(metadata.get("class", ""))
		var item_region = str(metadata.get("region", ""))

		var order := _scope_order_for(item_class, item_region)
		for entry in order:
			if typeof(entry) == TYPE_DICTIONARY:
				if str(entry.get("type", "")) == item_type and str(entry.get("name", "")) == item_name:
					line_num = int(entry.get("line", 0))
					break

	if line_num > 0:
		editor_plugin.get_editor_interface().edit_script(active_script, line_num, 0)
	else:
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

		if item_type != "script" and item_type != "group":
			_jump_to_line_in_editor(metadata)
		else:
			item_activated.emit(item_type, item_name, {})


func _on_filter_changed(new_text: String) -> void:
	tree_filter_text = new_text.to_lower()
	_build_tree()
