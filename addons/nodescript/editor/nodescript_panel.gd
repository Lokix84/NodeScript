@tool
extends Control

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const NodeScriptTreeUtils = preload("res://addons/nodescript/utils/tree_utils.gd")

var editor_plugin: EditorPlugin
var active_script: Script

const _NodeScriptSyncScript = preload("res://addons/nodescript/editor/nodescript_sync.gd")

var sync

var tree: Tree
var tree_filter: LineEdit
var function_body_editor
var function_region_picker: OptionButton
var function_class_picker: OptionButton
var function_region_button: Button
var function_class_button: Button
var signal_editor
var variable_editor
var enum_editor
var region_editor
var root_meta_editor
var class_editor
var type_picker_popup
var selected_function_index: int = -1
var creating_signal: bool = false
var creating_variable: bool = false
var creating_enum: bool = false
var creating_region: bool = false
var creating_class: bool = false
var editing_signal: bool = false
var editing_variable: bool = false
var editing_enum: bool = false
var editing_region: bool = false
var editing_class: bool = false
var current_signal_name: String = ""
var current_variable_name: String = ""
var current_enum_name: String = ""
var current_region_name: String = ""
var current_class_name: String = ""
var _delete_dialog: ConfirmationDialog
var _delete_hold_timer: Timer
var _delete_hold_button: Button
var _pending_delete_kind: String = ""
var _pending_delete_name: String = ""
var show_enum_values_in_tree: bool = true
var auto_sort_tree_flag: bool = true
var auto_space_enabled: bool = true
var consolidate_blank_lines: bool = true
var tree_filter_text: String = ""
var tree_context_menu: PopupMenu
var _context_item_data: Dictionary = {}
var mode_grouped_btn: TextureButton
var mode_true_btn: TextureButton
var mode_flat_btn: TextureButton
var options_button: TextureButton
var options_menu: PopupMenu
var tree_display_mode: int = 1
var _tree_mode_locked: bool = false
var add_item_button: TextureButton
var add_item_menu: PopupMenu
var _pending_function_region_assign: bool = false
var _pending_function_class_assign: bool = false
var drag_notice_label: Label

func set_editor_plugin(plugin: EditorPlugin) -> void:
	editor_plugin = plugin


func _ready() -> void:
	# Dynamically find the UI nodes by name anywhere under this panel
	tree = find_child("Tree", true, false)
	tree_filter = find_child("TreeFilter", true, false)
	mode_grouped_btn = find_child("ModeGrouped", true, false)
	mode_true_btn = find_child("ModeTrue", true, false)
	mode_flat_btn = find_child("ModeFlat", true, false)
	options_button = find_child("OptionsButton", true, false)
	add_item_button = find_child("AddItemButton", true, false)
	drag_notice_label = find_child("DragNotice", true, false)
	function_body_editor = find_child("FunctionBodyEditor", true, false)
	function_region_picker = find_child("FunctionRegionPicker", true, false)
	function_class_picker = find_child("FunctionClassPicker", true, false)
	function_region_button = find_child("FunctionRegionButton", true, false)
	function_class_button = find_child("FunctionClassButton", true, false)
	signal_editor = find_child("SignalEditor", true, false)
	variable_editor = find_child("VariableEditor", true, false)
	enum_editor = find_child("EnumEditor", true, false)
	region_editor = find_child("RegionEditor", true, false)
	root_meta_editor = find_child("RootMetaEditor", true, false)
	class_editor = find_child("ClassEditor", true, false)
	type_picker_popup = find_child("TypePickerPopup", true, false)

	if function_body_editor == null:
		push_warning("NodeScriptPanel: Could not find a node named 'FunctionBodyEditor'.")

	_setup_editors()
	_setup_tree()
	_reload_config_flags()
	_apply_mode_buttons()
	_connect_mode_buttons()

	if tree_filter and not tree_filter.text_changed.is_connected(_on_tree_filter_changed):
		tree_filter.text_changed.connect(_on_tree_filter_changed)

	_setup_context_menu()
	_setup_add_item_menu()
	_setup_options_menu()
	_setup_delete_dialog()
	_connect_function_org_buttons()


func _setup_editors() -> void:
	if signal_editor:
		_connect_signal_if_present(signal_editor, "delete_requested", Callable(self, "_on_signal_editor_delete_requested"))
		_connect_signal_if_present(signal_editor, "submitted", Callable(self, "_on_signal_editor_submitted"))
		_connect_signal_if_present(signal_editor, "add_param_requested", Callable(self, "_on_signal_editor_add_param_requested"))
		_connect_signal_if_present(signal_editor, "name_changed", Callable(self, "_on_signal_editor_name_changed"))
		_connect_signal_if_present(signal_editor, "name_commit_requested", Callable(self, "_on_signal_editor_name_commit_requested"))
	if variable_editor:
		_connect_signal_if_present(variable_editor, "delete_requested", Callable(self, "_on_variable_editor_delete_requested"))
		_connect_signal_if_present(variable_editor, "submitted", Callable(self, "_on_variable_editor_submitted"))
		_connect_signal_if_present(variable_editor, "type_pick_requested", Callable(self, "_on_variable_editor_type_pick_requested"))
		_connect_signal_if_present(variable_editor, "name_changed", Callable(self, "_on_variable_editor_name_changed"))
		_connect_signal_if_present(variable_editor, "name_commit_requested", Callable(self, "_on_variable_editor_name_commit_requested"))
	if enum_editor:
		_connect_signal_if_present(enum_editor, "delete_requested", Callable(self, "_on_enum_editor_delete_requested"))
		_connect_signal_if_present(enum_editor, "submitted", Callable(self, "_on_enum_editor_submitted"))
		_connect_signal_if_present(enum_editor, "name_changed", Callable(self, "_on_enum_editor_name_changed"))
		_connect_signal_if_present(enum_editor, "name_commit_requested", Callable(self, "_on_enum_editor_name_commit_requested"))
	if region_editor:
		_connect_signal_if_present(region_editor, "delete_requested", Callable(self, "_on_region_editor_delete_requested"))
		_connect_signal_if_present(region_editor, "submitted", Callable(self, "_on_region_editor_submitted"))
		_connect_signal_if_present(region_editor, "name_changed", Callable(self, "_on_region_editor_name_changed"))
		_connect_signal_if_present(region_editor, "name_commit_requested", Callable(self, "_on_region_editor_name_commit_requested"))
	if root_meta_editor and not root_meta_editor.submitted.is_connected(_on_root_meta_submitted):
		root_meta_editor.submitted.connect(_on_root_meta_submitted)
	if class_editor:
		_connect_signal_if_present(class_editor, "delete_requested", Callable(self, "_on_class_editor_delete_requested"))
		_connect_signal_if_present(class_editor, "submitted", Callable(self, "_on_class_editor_submitted"))
		_connect_signal_if_present(class_editor, "name_changed", Callable(self, "_on_class_editor_name_changed"))
		_connect_signal_if_present(class_editor, "name_commit_requested", Callable(self, "_on_class_editor_name_commit_requested"))
	if function_body_editor:
		_connect_signal_if_present(function_body_editor, "update_requested", Callable(self, "_on_function_update_requested"))
	if function_region_picker and not function_region_picker.item_selected.is_connected(_on_function_region_selected):
		function_region_picker.item_selected.connect(_on_function_region_selected)
	if function_class_picker and not function_class_picker.item_selected.is_connected(_on_function_class_selected):
		function_class_picker.item_selected.connect(_on_function_class_selected)

	# Optional: uncomment to inspect the live tree
	# print(\"\\n--- NodeScriptPanel tree dump ---\")
	# _print_tree_recursive(self, 0)
	# print(\"--- End dump ---\\n\")


func _setup_tree() -> void:
	if tree == null:
		push_warning("NodeScriptPanel: Tree node missing.")
		return
	tree.columns = 1
	tree.hide_root = true
	tree.allow_reselect = true
	_update_drop_mode_flags()
	_set_tree_drag_forwarding()
	if not tree.item_selected.is_connected(_on_tree_item_selected):
		tree.item_selected.connect(_on_tree_item_selected)
	if not tree.item_collapsed.is_connected(_on_tree_item_collapsed):
		tree.item_collapsed.connect(_on_tree_item_collapsed)
	if not tree.gui_input.is_connected(_on_tree_gui_input):
		tree.gui_input.connect(_on_tree_gui_input)


func _connect_function_org_buttons() -> void:
	if function_region_button and not function_region_button.pressed.is_connected(_on_function_region_button_pressed):
		function_region_button.pressed.connect(_on_function_region_button_pressed)
	if function_class_button and not function_class_button.pressed.is_connected(_on_function_class_button_pressed):
		function_class_button.pressed.connect(_on_function_class_button_pressed)


func _on_tree_item_selected() -> void:
	if tree == null:
		return
	var item = tree.get_selected()
	if item == null:
		return
	var data = item.get_metadata(0)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var type = str(data.get("type", ""))
	match type:
		"signal_add":
			_show_signal_editor()
		"signal":
			_show_existing_signal(str(data.get("name", "")))
		"variable_add":
			_show_variable_editor()
		"variable":
			_show_existing_variable(str(data.get("name", "")))
		"enum_add":
			_show_enum_editor()
		"enum":
			_show_existing_enum(str(data.get("name", "")))
		"region_add":
			_show_region_editor(true, "")
		"region":
			_show_region_editor(false, str(data.get("name", "")))
		"class_add":
			_show_class_editor(true, "")
		"class":
			_show_class_editor(false, str(data.get("name", "")))
		"function_add":
			call_deferred("_append_function_deferred")
		"function":
			var func_index = int(data.get("index", -1))
			if func_index >= 0:
				if not item.collapsed:
					_ensure_function_blocks_for_item(item, func_index)
				_on_function_selected(func_index)
		"function_block":
			var parent_index = int(data.get("function_index", -1))
			if parent_index >= 0:
				_on_function_selected(parent_index)
		"script":
			_show_root_meta_editor()
		_:
			pass


func _on_tree_item_collapsed(item: TreeItem) -> void:
	if item == null or item.collapsed:
		return
	var data = item.get_metadata(0)
	if typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "function":
		_ensure_function_blocks_for_item(item, int(data.get("index", -1)))


func _get_drag_data(position: Vector2) -> Variant:
	if not _is_reorder_enabled():
		return null
	var payload := _drag_data_from_tree(position)
	if payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = str(payload.get("label", payload.get("name", "")))
	set_drag_preview(preview)
	return payload


func _can_drop_data(position: Vector2, data: Variant) -> bool:
	if not _is_reorder_enabled():
		return false
	var payload := _coerce_drag_payload(data)
	if payload.is_empty() or tree == null:
		return false
	var target := tree.get_item_at_position(position)
	if target == null:
		target = _fallback_drop_target()
		if target == null:
			return false
	var target_meta := _metadata_for_item(target)
	if not _is_valid_drop_target(payload, target_meta):
		return false
	var section := tree.get_drop_section_at_position(position) if tree.has_method("get_drop_section_at_position") else 0
	_update_drop_highlight(section, str(target_meta.get("type", "")))
	return true


func _drop_data(position: Vector2, data: Variant) -> void:
	if not _is_reorder_enabled():
		return
	var payload := _coerce_drag_payload(data)
	if payload.is_empty() or tree == null or sync == null or sync.nodescript == null:
		return
	var target := tree.get_item_at_position(position)
	var section := tree.get_drop_section_at_position(position) if tree.has_method("get_drop_section_at_position") else 0
	if target == null:
		target = _fallback_drop_target()
		section = 1 if section == 0 else section
	if target == null:
		return
	_apply_drag_drop(payload, target, section)


func _is_reorderable_kind(kind: String) -> bool:
	match kind:
		"function", "signal", "variable", "enum", "region", "class":
			return true
		_:
			return false


func _is_reorder_enabled() -> bool:
	return tree_display_mode == 1


func _is_container_type(kind: String) -> bool:
	return kind == "script" or kind == "region" or kind == "class"


func _is_valid_drop_target(payload: Dictionary, target_meta: Dictionary) -> bool:
	var kind := str(payload.get("drag_type", ""))
	var target_kind := str(target_meta.get("type", ""))
	# Ignore helper items.
	if target_kind in ["section", "enum_value", "signal_add", "variable_add", "enum_add", "region_add", "class_add", "function_add", "function_block"]:
		return false
	match kind:
		"region":
			return target_kind in ["region", "class", "script", "function", "signal", "variable", "enum"]
		"class":
			return target_kind in ["class", "region", "script", "function", "signal", "variable", "enum"]
		"function", "signal", "variable", "enum":
			return target_kind in ["function", "signal", "variable", "enum", "region", "class", "script"]
		_:
			return false


func _context_for_item(item: TreeItem) -> Dictionary:
	var ctx := {"class": "", "region": ""}
	var current := item
	while current:
		var meta := _metadata_for_item(current)
		var kind := str(meta.get("type", ""))
		if ctx["class"] == "" and kind == "class":
			ctx["class"] = str(meta.get("name", ""))
		if ctx["region"] == "" and kind == "region":
			ctx["region"] = str(meta.get("name", ""))
		current = current.get_parent()
	return ctx


func _apply_drag_drop(payload: Dictionary, target: TreeItem, section: int) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	if not _is_reorder_enabled():
		return
	var target_meta := _metadata_for_item(target)
	if not _is_valid_drop_target(payload, target_meta):
		return
	var context_item := target if section == 0 else target.get_parent()
	var ctx := _context_for_item(context_item)
	var dest_cls := ctx.get("class", "")
	var dest_region := ctx.get("region", "")
	match str(payload.get("drag_type", "")):
		"function":
			_move_function_payload(payload, target_meta, ctx, section)
		"signal":
			_move_signal_payload(payload, target_meta, ctx, section)
		"variable":
			_move_variable_payload(payload, target_meta, ctx, section)
		"enum":
			_move_enum_payload(payload, target_meta, ctx, section)
		"region":
			_move_region_payload(payload, target_meta, ctx, section)
		"class":
			_move_class_payload(payload, target_meta, ctx, section)
		_:
			return
	sync.save()
	_refresh_tree()
	_apply_declarations_to_script()


func _normalized_drop_section(section: int) -> int:
	if section < -1:
		return -1
	if section > 1:
		return 1
	return section


func _move_order_entry(entry_type: String, name: String, src_cls: String, src_region: String, dst_cls: String, dst_region: String, target_meta: Dictionary, section: int) -> void:
	var source_key := _scope_key(src_cls, src_region)
	var dest_key := _scope_key(dst_cls, dst_region)
	var source_order := _scope_order_for(src_cls, src_region)
	var dest_order := source_order if source_key == dest_key else _scope_order_for(dst_cls, dst_region)

	var removed := false
	for i in range(source_order.size()):
		var e = source_order[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("type", "")) == entry_type and str(e.get("name", "")) == name:
			source_order.remove_at(i)
			removed = true
			break
	if removed:
		_set_scope_order(src_cls, src_region, source_order)

	var insert_index := dest_order.size()
	var target_name := str(target_meta.get("name", ""))
	var target_type := str(target_meta.get("type", ""))
	for i in range(dest_order.size()):
		var e = dest_order[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("type", "")) == target_type and str(e.get("name", "")) == target_name:
			if section < 0:
				insert_index = i
			elif section > 0:
				insert_index = i + 1
			else:
				insert_index = i + 1
			break

	dest_order.insert(insert_index, {"type": entry_type, "name": name})
	_set_scope_order(dst_cls, dst_region, dest_order)


func _move_function_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var functions_array: Array = sync.nodescript.body.get("functions", [])
	var src_index := int(payload.get("index", -1))
	if src_index < 0 or src_index >= functions_array.size():
		return
	var entry = functions_array[src_index]
	var old_cls := str(entry.get("class", ""))
	var old_region := str(entry.get("region", ""))
	var new_cls := ctx.get("class", "")
	var new_region := ctx.get("region", "")
	entry["class"] = new_cls
	entry["region"] = new_region
	var target_index := _target_index_in_functions(functions_array, target_meta, ctx, _normalized_drop_section(section))
	functions_array.remove_at(src_index)
	if src_index < target_index:
		target_index -= 1
	target_index = clamp(target_index, 0, functions_array.size())
	functions_array.insert(target_index, entry)
	sync.nodescript.body["functions"] = functions_array
	var fname := str(entry.get("name", ""))
	_move_order_entry("function", fname, old_cls, old_region, new_cls, new_region, target_meta, section)
	_ensure_empty_class_has_pass(old_cls)


func _target_index_in_functions(functions_array: Array, target_meta: Dictionary, ctx: Dictionary, section: int) -> int:
	var ctx_indices: Array[int] = []
	for i in range(functions_array.size()):
		var e = functions_array[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if _entry_class(e) == ctx.get("class", "") and _entry_region(e) == ctx.get("region", ""):
			ctx_indices.append(i)
	if ctx_indices.is_empty():
		return functions_array.size()
	if str(target_meta.get("type", "")) != "function":
		return ctx_indices[ctx_indices.size() - 1] + 1
	var target_idx := int(target_meta.get("index", -1))
	var pos := ctx_indices.find(target_idx)
	if pos == -1:
		return ctx_indices[ctx_indices.size() - 1] + 1
	var insert_pos := pos
	if section > 0:
		insert_pos += 1
	if insert_pos >= ctx_indices.size():
		return ctx_indices[ctx_indices.size() - 1] + 1
	return ctx_indices[insert_pos]


func _move_signal_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	var name := str(payload.get("name", ""))
	if not signals_dict.has(name):
		return
	var order: Array = Array(signals_dict.keys())
	var entry = signals_dict.get(name, {})
	var old_cls := str(entry.get("class", ""))
	var old_region := str(entry.get("region", ""))
	var new_cls := ctx.get("class", "")
	var new_region := ctx.get("region", "")
	entry["class"] = new_cls
	entry["region"] = new_region
	order.erase(name)
	signals_dict.erase(name)

	var insert_index := order.size()
	if str(target_meta.get("type", "")) == "signal":
		var target_name := str(target_meta.get("name", ""))
		var target_pos := order.find(target_name)
		if target_pos != -1:
			var normalized := _normalized_drop_section(section)
			insert_index = target_pos if normalized < 0 else target_pos + 1

	order.insert(insert_index, name)
	var rebuilt := {}
	for sig_name in order:
		var sig_entry: Variant = entry if sig_name == name else signals_dict.get(sig_name, {})
		rebuilt[sig_name] = sig_entry
	sync.nodescript.body["signals"] = rebuilt
	_move_order_entry("signal", name, old_cls, old_region, new_cls, new_region, target_meta, section)
	_ensure_empty_class_has_pass(old_cls)


func _move_variable_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var vars: Array = sync.nodescript.body.get("variables", [])
	var name := str(payload.get("name", ""))
	var src_index := _variable_index_by_name(vars, name)
	if src_index == -1:
		return
	var entry = vars[src_index]
	var old_cls := str(entry.get("class", ""))
	var old_region := str(entry.get("region", ""))
	var new_cls := ctx.get("class", "")
	var new_region := ctx.get("region", "")
	entry["class"] = new_cls
	entry["region"] = new_region
	var target_index := _target_index_in_variables(vars, target_meta, ctx, _normalized_drop_section(section))
	vars.remove_at(src_index)
	if src_index < target_index:
		target_index -= 1
	target_index = clamp(target_index, 0, vars.size())
	vars.insert(target_index, entry)
	sync.nodescript.body["variables"] = vars
	_move_order_entry("variable", name, old_cls, old_region, new_cls, new_region, target_meta, section)
	_ensure_empty_class_has_pass(old_cls)


func _variable_index_by_name(arr: Array, name: String) -> int:
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("name", "")) == name:
			return i
	return -1


func _variable_indices_for_context(arr: Array, ctx: Dictionary) -> Array[int]:
	var indices: Array[int] = []
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if _entry_class(e) == ctx.get("class", "") and _entry_region(e) == ctx.get("region", ""):
			indices.append(i)
	return indices


func _target_index_in_variables(arr: Array, target_meta: Dictionary, ctx: Dictionary, section: int) -> int:
	var ctx_indices := _variable_indices_for_context(arr, ctx)
	if ctx_indices.is_empty():
		return arr.size()
	if str(target_meta.get("type", "")) != "variable":
		return ctx_indices[ctx_indices.size() - 1] + 1
	var target_name := str(target_meta.get("name", ""))
	var target_index := _variable_index_by_name(arr, target_name)
	var pos := ctx_indices.find(target_index)
	if pos == -1:
		return ctx_indices[ctx_indices.size() - 1] + 1
	var insert_pos := pos
	if section > 0:
		insert_pos += 1
	if insert_pos >= ctx_indices.size():
		return ctx_indices[ctx_indices.size() - 1] + 1
	return ctx_indices[insert_pos]


func _move_enum_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	var name := str(payload.get("name", ""))
	if not enums_dict.has(name):
		return
	var order: Array = Array(enums_dict.keys())
	var entry = enums_dict.get(name, {})
	var old_cls := str(entry.get("class", ""))
	var old_region := str(entry.get("region", ""))
	var new_cls := ctx.get("class", "")
	var new_region := ctx.get("region", "")
	entry["class"] = new_cls
	entry["region"] = new_region
	order.erase(name)
	enums_dict.erase(name)

	var insert_index := order.size()
	if str(target_meta.get("type", "")) == "enum":
		var target_name := str(target_meta.get("name", ""))
		var target_pos := order.find(target_name)
		if target_pos != -1:
			var normalized := _normalized_drop_section(section)
			insert_index = target_pos if normalized < 0 else target_pos + 1
	order.insert(insert_index, name)

	var rebuilt := {}
	for enum_name in order:
		var enum_entry: Variant = entry if enum_name == name else enums_dict.get(enum_name, {})
		rebuilt[enum_name] = enum_entry
	sync.nodescript.body["enums"] = rebuilt
	_move_order_entry("enum", name, old_cls, old_region, new_cls, new_region, target_meta, section)
	_ensure_empty_class_has_pass(old_cls)


func _move_region_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var regions: Array = sync.nodescript.body.get("regions", [])
	var name := str(payload.get("name", ""))
	var ctx_class := str(ctx.get("class", "")).strip_edges()
	var ctx_region := str(ctx.get("region", "")).strip_edges()
	# Fallbacks if context could not determine class/region (e.g. dropping directly on an item).
	if ctx_class == "" and str(target_meta.get("type", "")) == "class":
		ctx_class = str(target_meta.get("name", "")).strip_edges()
	if ctx_class == "" and target_meta.has("class"):
		ctx_class = str(target_meta.get("class", "")).strip_edges()
	if ctx_region == "" and target_meta.has("region"):
		ctx_region = str(target_meta.get("region", "")).strip_edges()

	var old_class := str(payload.get("class", ""))
	var old_region := str(payload.get("region", ""))
	var src_index := _region_index_by_scope(regions, name, old_class, old_region)
	if src_index == -1:
		# If the region wasn't declared yet, create an entry so it can be reordered.
		regions.append({"name": name, "class": ctx_class, "region": ctx_region})
		src_index = regions.size() - 1

	var target_indices := _region_indices_for_scope(regions, ctx_class, ctx_region)
	var target_index := regions.size()
	if str(target_meta.get("type", "")) == "region":
		var target_name := str(target_meta.get("name", ""))
		var tpos := _region_index_by_scope(regions, target_name, ctx_class, ctx_region)
		if tpos != -1:
			var normalized := _normalized_drop_section(section)
			target_index = tpos if normalized < 0 else tpos + 1
	elif not target_indices.is_empty():
		target_index = target_indices[target_indices.size() - 1] + 1

	var entry = regions[src_index]
	entry["class"] = ctx_class
	entry["region"] = ctx_region
	regions.remove_at(src_index)
	if src_index < target_index:
		target_index -= 1
	target_index = clamp(target_index, 0, regions.size())
	regions.insert(target_index, entry)
	sync.nodescript.body["regions"] = regions
	_move_order_entry("region", name, old_class, old_region, ctx_class, ctx_region, target_meta, section)
	_relocate_region_children(name, old_class, ctx_class)
	_ensure_empty_class_has_pass(old_class)


func _move_class_payload(payload: Dictionary, target_meta: Dictionary, ctx: Dictionary, section: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	var classes: Array = sync.nodescript.body.get("classes", [])
	var name := str(payload.get("name", ""))
	var src_index := _class_index_by_name(classes, name)
	if src_index == -1:
		return
	var old_region := str(classes[src_index].get("region", ""))
	var old_cls_region := old_region
	var target_index := classes.size()
	if str(target_meta.get("type", "")) == "class":
		var target_name := str(target_meta.get("name", ""))
		var tpos := _class_index_by_name(classes, target_name)
		if tpos != -1:
			var normalized := _normalized_drop_section(section)
			target_index = tpos if normalized < 0 else tpos + 1
	else:
		var scoped := _class_indices_for_region(classes, ctx.get("region", ""))
		if not scoped.is_empty():
			target_index = scoped[scoped.size() - 1] + 1
	var entry = classes[src_index]
	entry["region"] = ctx.get("region", "")
	classes.remove_at(src_index)
	if src_index < target_index:
		target_index -= 1
	target_index = clamp(target_index, 0, classes.size())
	classes.insert(target_index, entry)
	sync.nodescript.body["classes"] = classes
	_move_order_entry("class", name, "", old_region, "", ctx.get("region", ""), target_meta, section)
	_update_child_regions_for_class(name, old_cls_region, entry.get("region", ""))
	_ensure_empty_class_has_pass(name)


func _index_in_named_array(arr: Array, name: String) -> int:
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) == TYPE_DICTIONARY:
			if str(e.get("name", "")) == name:
				return i
		elif str(e) == name:
			return i
	return -1


func _class_index_by_name(arr: Array, name: String) -> int:
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("name", "")) == name:
			return i
	return -1


func _class_indices_for_region(arr: Array, region: String) -> Array[int]:
	var indices: Array[int] = []
	var target := region.strip_edges()
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("region", "")).strip_edges() == target:
			indices.append(i)
	return indices


func _region_index_by_scope(arr: Array, name: String, cls, parent_region: String) -> int:
	var target_class := str(cls).strip_edges()
	var target_region := str(parent_region).strip_edges()
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("name", "")) != name:
			continue
		if str(e.get("class", "")).strip_edges() != target_class:
			continue
		if _entry_region(e) != target_region:
			continue
		return i
	return -1


func _region_indices_for_scope(arr: Array, cls: String, parent_region: String) -> Array[int]:
	var indices: Array[int] = []
	var target_class := cls.strip_edges()
	var target_region := parent_region.strip_edges()
	for i in range(arr.size()):
		var e = arr[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("class", "")).strip_edges() != target_class:
			continue
		if _entry_region(e) != target_region:
			continue
		indices.append(i)
	return indices


func _update_child_regions_for_class(class_title: String, old_region: String, new_region: String) -> void:
	var cname := str(class_title).strip_edges()
	if cname == "":
		return
	var trimmed_old := str(old_region).strip_edges()
	var trimmed_new := str(new_region).strip_edges()
	if trimmed_old == trimmed_new:
		return

	# Update member region values when a class is moved between regions.
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in signals_dict.keys():
		var entry = signals_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cname:
			continue
		entry["region"] = trimmed_new
		signals_dict[key] = entry
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var entry = enums_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cname:
			continue
		entry["region"] = trimmed_new
		enums_dict[key] = entry
	sync.nodescript.body["enums"] = enums_dict

	var vars: Array = sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		var entry = vars[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cname:
			continue
		entry["region"] = trimmed_new
		vars[i] = entry
	sync.nodescript.body["variables"] = vars

	var funcs: Array = sync.nodescript.body.get("functions", [])
	for i in range(funcs.size()):
		var entry = funcs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cname:
			continue
		entry["region"] = trimmed_new
		funcs[i] = entry
	sync.nodescript.body["functions"] = funcs

	var regions: Array = sync.nodescript.body.get("regions", [])
	for i in range(regions.size()):
		var entry = regions[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cname:
			continue
		entry["class"] = cname
		regions[i] = entry
	sync.nodescript.body["regions"] = regions
	_update_child_region_order_keys(cname, trimmed_old, trimmed_new)
	_relocate_class_children_order(cname, trimmed_old, trimmed_new)


func _relocate_region_children(region_name: String, old_class: String, new_class: String) -> void:
	var rname := str(region_name).strip_edges()
	var old_cls := str(old_class).strip_edges()
	var new_cls := str(new_class).strip_edges()
	if rname == "":
		return
	if old_cls == new_cls:
		return

	# Update member class when their region moves between classes.
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in signals_dict.keys():
		var entry = signals_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("region", "")).strip_edges() == rname and str(entry.get("class", "")).strip_edges() == old_cls:
			entry["class"] = new_cls
			signals_dict[key] = entry
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var entry = enums_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("region", "")).strip_edges() == rname and str(entry.get("class", "")).strip_edges() == old_cls:
			entry["class"] = new_cls
			enums_dict[key] = entry
	sync.nodescript.body["enums"] = enums_dict

	var vars: Array = sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		var entry = vars[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("region", "")).strip_edges() == rname and str(entry.get("class", "")).strip_edges() == old_cls:
			entry["class"] = new_cls
			vars[i] = entry
	sync.nodescript.body["variables"] = vars

	var funcs: Array = sync.nodescript.body.get("functions", [])
	for i in range(funcs.size()):
		var entry = funcs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("region", "")).strip_edges() == rname and str(entry.get("class", "")).strip_edges() == old_cls:
			entry["class"] = new_cls
			funcs[i] = entry
	sync.nodescript.body["functions"] = funcs

	# Move order scope for this region to the new class context.
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var old_key := _scope_key(old_cls, rname)
	var new_key := _scope_key(new_cls, rname)
	if order.has(old_key):
		var entries: Array = order.get(old_key, [])
		order.erase(old_key)
		var combined: Array = order.get(new_key, [])
		if combined == null:
			combined = []
		combined.append_array(entries)
		order[new_key] = combined
	sync.nodescript.body["order"] = order


func _ensure_empty_class_has_pass(class_title: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	var cname := str(class_title).strip_edges()
	if cname == "":
		return
	if NodeScriptUtils.class_has_members(sync.nodescript, cname, ""):
		return
	# Clear the class scope order so codegen will emit pass for an empty class.
	_set_scope_order(cname, "", [])


func _split_scope_key(key: String) -> Array[String]:
	var raw_parts: PackedStringArray = key.split("|", false, 2)
	var parts: Array[String] = []
	parts.append_array(raw_parts)
	while parts.size() < 2:
		parts.append("")
	return parts


func _rename_class_references(old_name: String, new_name: String, old_region: String, new_region: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	var trimmed_old := str(old_name).strip_edges()
	var trimmed_new := str(new_name).strip_edges()
	if trimmed_old == "" or trimmed_old == trimmed_new:
		return

	# Update class references on members.
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in signals_dict.keys():
		var entry = signals_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == trimmed_old:
			entry["class"] = trimmed_new
			signals_dict[key] = entry
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var entry = enums_dict.get(key, {})
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == trimmed_old:
			entry["class"] = trimmed_new
			enums_dict[key] = entry
	sync.nodescript.body["enums"] = enums_dict

	var vars: Array = sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		var entry = vars[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == trimmed_old:
			entry["class"] = trimmed_new
			vars[i] = entry
	sync.nodescript.body["variables"] = vars

	var funcs: Array = sync.nodescript.body.get("functions", [])
	for i in range(funcs.size()):
		var entry = funcs[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == trimmed_old:
			entry["class"] = trimmed_new
			funcs[i] = entry
	sync.nodescript.body["functions"] = funcs

	var regions: Array = sync.nodescript.body.get("regions", [])
	for i in range(regions.size()):
		var entry = regions[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == trimmed_old:
			entry["class"] = trimmed_new
			regions[i] = entry
	sync.nodescript.body["regions"] = regions

	# Update order map: rename class scope keys and move the class entry if its parent region changed.
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var new_order: Dictionary = {}
	var moved_class_entry: Dictionary = {}

	for key in order.keys():
		var entries: Array = order.get(key, [])
		var parts := _split_scope_key(str(key))
		var scope_cls := parts[0]
		var scope_region := parts[1]
		var new_scope_cls := trimmed_new if scope_cls == trimmed_old else scope_cls
		var new_scope_region := scope_region
		var list: Array = []
		for e in entries:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var etype := str(e.get("type", ""))
			var ename := str(e.get("name", ""))
			var copy: Dictionary = e.duplicate(true)
			if etype == "class" and ename == trimmed_old:
				copy["name"] = trimmed_new
				# Move class listing to new parent region if needed.
				if scope_cls == "" and scope_region == old_region:
					moved_class_entry = copy
					continue
			list.append(copy)
		var new_key := _scope_key(new_scope_cls, new_scope_region)
		if not new_order.has(new_key):
			new_order[new_key] = []
		new_order[new_key].append_array(list)
	# If the class parent region changed, append the class entry under the new region scope.
	if not moved_class_entry.is_empty():
		var dest_key := _scope_key("", new_region)
		if not new_order.has(dest_key):
			new_order[dest_key] = []
		new_order[dest_key].append(moved_class_entry)
	sync.nodescript.body["order"] = new_order


func _update_child_region_order_keys(class_title: String, old_region: String, new_region: String) -> void:
	var cname := str(class_title).strip_edges()
	var old_r := str(old_region).strip_edges()
	var new_r := str(new_region).strip_edges()
	if sync == null or sync.nodescript == null:
		return
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var updated: Dictionary = {}
	for key in order.keys():
		var entries: Array = order.get(key, [])
		var parts := _split_scope_key(str(key))
		var scope_cls := parts[0]
		var scope_region := parts[1]
		var new_key: String = str(key)
		if scope_cls == cname and scope_region == old_r:
			new_key = _scope_key(cname, new_r)
		if not updated.has(new_key):
			updated[new_key] = []
		updated[new_key].append_array(entries)
	sync.nodescript.body["order"] = updated


func _relocate_class_children_order(class_title: String, old_region: String, new_region: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	var cname := str(class_title).strip_edges()
	var old_r := str(old_region).strip_edges()
	var new_r := str(new_region).strip_edges()
	if cname == "":
		return
	if old_r == new_r:
		return
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var old_key := _scope_key(cname, old_r)
	var new_key := _scope_key(cname, new_r)
	if not order.has(old_key):
		return
	var entries: Array = order.get(old_key, [])
	order.erase(old_key)
	var combined: Array = order.get(new_key, [])
	if combined == null:
		combined = []
	combined.append_array(entries)
	order[new_key] = combined
	sync.nodescript.body["order"] = order


func _find_region_entry(name: String, cls: String = "", parent_region: String = "") -> Dictionary:
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) != name:
			continue
		if cls.strip_edges() != "" and str(entry.get("class", "")).strip_edges() != cls.strip_edges():
			continue
		if parent_region.strip_edges() != "" and _entry_region(entry) != parent_region.strip_edges():
			continue
		return entry
	# Fallback: return first name match if parent filter missed.
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) != name:
			continue
		if cls.strip_edges() == "" or str(entry.get("class", "")).strip_edges() == cls.strip_edges():
			return entry
	return {}


func _find_class_entry(name: String) -> Dictionary:
	var classes: Array = sync.nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return entry
	return {}


func _signal_entry(name: String) -> Dictionary:
	var signals: Dictionary = sync.nodescript.body.get("signals", {})
	if signals.has(name):
		var entry = signals.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


func _variable_entry(name: String) -> Dictionary:
	var vars: Array = sync.nodescript.body.get("variables", [])
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if str(v.get("name", "")) == name:
			return v
	return {}


func _enum_entry(name: String) -> Dictionary:
	var enums: Dictionary = sync.nodescript.body.get("enums", {})
	if enums.has(name):
		var entry = enums.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


func _function_index_by_name(name: String) -> int:
	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for i in range(functions_array.size()):
		var entry = functions_array[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return i
	return -1


func _function_entry_by_index(index: int) -> Dictionary:
	var functions_array: Array = sync.nodescript.body.get("functions", [])
	if index < 0 or index >= functions_array.size():
		return {}
	var entry = functions_array[index]
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


func _on_tree_gui_input(event: InputEvent) -> void:
	if tree == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var pos: Vector2 = event.position
		var item := tree.get_item_at_position(pos)
		if item:
			tree.set_selected(item, 0)
			_context_item_data = item.get_metadata(0) if typeof(item.get_metadata(0)) == TYPE_DICTIONARY else {}
			if tree_context_menu:
				var global_pos := tree.get_screen_position() + pos
				tree_context_menu.position = global_pos
				tree_context_menu.popup()


func _drag_data_from_tree(local_position: Vector2) -> Dictionary:
	if tree == null:
		return {}
	if not _is_reorder_enabled():
		return {}
	var local := local_position
	if local.x < 0 or local.y < 0 or local.x > tree.size.x or local.y > tree.size.y:
		return {}
	var item := tree.get_item_at_position(local)
	if item == null:
		return {}
	var meta := _metadata_for_item(item)
	if meta.is_empty():
		return {}
	var kind := str(meta.get("type", ""))
	if not _is_reorderable_kind(kind):
		return {}
	var payload := meta.duplicate(true)
	payload["drag_type"] = kind
	payload["label"] = item.get_text(0)
	return payload


func _coerce_drag_payload(data: Variant) -> Dictionary:
	if typeof(data) == TYPE_DICTIONARY:
		if data.has("drag_type"):
			return data
	return {}


func _metadata_for_item(item: TreeItem) -> Dictionary:
	if item == null:
		return {}
	var meta = item.get_metadata(0)
	return meta if typeof(meta) == TYPE_DICTIONARY else {}


func _fallback_drop_target() -> TreeItem:
	if tree == null:
		return null
	var root := tree.get_root()
	if root == null:
		return null
	# Use the script item so drops with no hovered target append to the root scope.
	return root.get_first_child()


func _update_drop_highlight(section: int, target_kind: String) -> void:
	if tree == null:
		return
	if not _is_reorder_enabled():
		tree.drop_mode_flags = 0
		return
	# For container rows (class/region/script) prefer ON_ITEM highlighting so it’s clear the item will become a child.
	var is_container := _is_container_type(target_kind)
	if is_container:
		tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	else:
		tree.drop_mode_flags = Tree.DROP_MODE_INBETWEEN if section != 0 else Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN


func set_target_script(script: Script) -> void:
	active_script = script
	_reload_config_flags()
	_apply_mode_buttons()
	creating_signal = false
	creating_variable = false
	creating_enum = false
	editing_signal = false
	editing_variable = false
	editing_enum = false
	current_signal_name = ""
	current_variable_name = ""
	current_enum_name = ""
	_hide_signal_editor()
	_hide_variable_editor()
	_hide_enum_editor()

	if sync == null:
		if _NodeScriptSyncScript == null:
			push_warning("NodeScriptPanel: NodeScriptSync script missing.")
			return
		sync = _NodeScriptSyncScript.new()

	if script == null:
		_clear_tree()
		_clear_function_view()
		_hide_signal_editor()
		_hide_variable_editor()
		sync.load_for_script(null)
		return

	sync.load_for_script(script)
	if sync == null or sync.nodescript == null:
		_log("Failed to load NodeScript for script %s" % (script.resource_path if script else ""), 1)
	else:
		_log("Active script set to: %s | NodeScript: %s" % [ sync.script_path, sync.nodescript_path], 1)
	_refresh_tree()


func _on_function_selected(index: int) -> void:
	if sync == null or sync.nodescript == null:
		_clear_function_view()
		return
	_clear_pending_function_org_flags()
	_clear_region_state()
	_clear_class_state()
	if class_editor:
		class_editor.hide()

	var methods = sync.nodescript.body.get("functions", [])
	if index < 0 or index >= methods.size():
		_clear_function_view()
		return

	# Ensure other editors are not shown.
	creating_signal = false
	editing_signal = false
	creating_variable = false
	editing_variable = false
	creating_enum = false
	editing_enum = false
	creating_region = false
	editing_region = false
	creating_class = false
	editing_class = false

	var method_dict = methods[index]
	var name = str(method_dict.get("name", "<unnamed>"))
	selected_function_index = index
	_set_function_region_class_lists()
	_set_function_region_class(method_dict)
	_apply_function_body_to_editor(method_dict)
	# Hide other editors and show function view.
	if signal_editor:
		signal_editor.hide()
	if variable_editor:
		variable_editor.hide()
	if enum_editor:
		enum_editor.hide()
	if region_editor:
		region_editor.hide()
	if class_editor:
		class_editor.hide()
	if root_meta_editor:
		root_meta_editor.hide()
	_refresh_right_panel_visibility()


func _on_function_region_selected(index: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	if function_region_picker:
		var meta = function_region_picker.get_item_metadata(index)
		if typeof(meta) == TYPE_STRING and meta == "__add_region__":
			_on_function_add_region_pressed()
			return
	var methods: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index < 0 or selected_function_index >= methods.size():
		return
	var method = methods[selected_function_index]
	var old_cls := _entry_class(method)
	var old_region := _entry_region(method)
	var region := function_region_picker.get_item_text(index) if function_region_picker else ""
	var mthds: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index >= 0 and selected_function_index < mthds.size():
		var mthd = mthds[selected_function_index]
		if typeof(mthd) == TYPE_DICTIONARY:
			mthd["region"] = region
			mthds[selected_function_index] = mthd
			sync.nodescript.body["functions"] = mthds
			sync.save()
			var scope_changed := old_region != region or old_cls != _entry_class(mthd)
			_append_function_order_at_scope_end(mthd, old_cls, old_region, scope_changed)
			_apply_declarations_to_script()


func _on_function_region_button_pressed() -> void:
	_popup_option_at_mouse(function_region_picker)


func _on_function_class_selected(index: int) -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	if function_class_picker:
		var meta = function_class_picker.get_item_metadata(index)
		if typeof(meta) == TYPE_STRING and meta == "__add_class__":
			_on_function_add_class_pressed()
			return
	var mthds: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index < 0 or selected_function_index >= mthds.size():
		return
	var mthd = mthds[selected_function_index]
	var old_cls := _entry_class(mthd)
	var old_region := _entry_region(mthd)
	var cls := function_class_picker.get_item_text(index) if function_class_picker else ""
	if selected_function_index >= 0 and selected_function_index < mthds.size():
		mthd = mthds[selected_function_index]
		if typeof(mthd) == TYPE_DICTIONARY:
			mthd["class"] = cls
			mthds[selected_function_index] = mthd
			sync.nodescript.body["functions"] = mthds
			sync.save()
			var scope_changed := old_cls != cls
			_append_function_order_at_scope_end(mthd, old_cls, old_region, scope_changed)
			_apply_declarations_to_script()


func _on_function_class_button_pressed() -> void:
	_popup_option_at_mouse(function_class_picker)


func _on_function_add_region_pressed() -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	_pending_function_region_assign = true
	var method := _function_entry_by_index(selected_function_index)
	var cls := _entry_class(method)
	_show_region_editor(true, "")
	if region_editor and region_editor.has_method("set_region_class"):
		region_editor.set_region_class("", cls)


func _on_function_add_class_pressed() -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	_pending_function_class_assign = true
	var method := _function_entry_by_index(selected_function_index)
	var region := _entry_region(method)
	_show_class_editor(true, "")
	if class_editor and class_editor.has_method("set_region_class"):
		class_editor.set_region_class(region, "")


func _apply_function_body_to_editor(method_dict):
	if function_body_editor == null:
		return

	if method_dict == null:
		if function_body_editor.has_method("clear_method"):
			function_body_editor.call_deferred("clear_method")
		return

	if function_body_editor.has_method("set_region_class_lists"):
		function_body_editor.call_deferred("set_region_class_lists", _available_regions(), _available_classes())
	if typeof(method_dict) == TYPE_DICTIONARY and function_body_editor.has_method("set_region_class"):
		function_body_editor.call_deferred("set_region_class", _entry_region(method_dict), _entry_class(method_dict))
	if function_body_editor.has_method("set_method"):
		function_body_editor.call_deferred("set_method", method_dict)


func _set_function_region_class_lists() -> void:
	_populate_function_org_option(function_region_picker, _available_regions(), "__add_region__", "Add Region...")
	_populate_function_org_option(function_class_picker, _available_classes(), "__add_class__", "Add Class...")


func _set_function_region_class(method: Dictionary) -> void:
	if typeof(method) != TYPE_DICTIONARY:
		_select_in_option(function_region_picker, "")
		_select_in_option(function_class_picker, "")
		return
	var region := str(method.get("region", "")).strip_edges()
	var cls := str(method.get("class", "")).strip_edges()
	_select_in_option(function_region_picker, region)
	_select_in_option(function_class_picker, cls)


func _clear_tree() -> void:
	if tree:
		tree.clear()
		tree.columns = 1


func _refresh_tree() -> void:
	_reload_config_flags()
	tree_filter_text = tree_filter.text.strip_edges().to_lower() if tree_filter else ""
	if tree == null:
		return
	_prune_orphan_order_entries()
	var desired_type := ""
	var desired_identifier = null
	if editing_signal and current_signal_name != "":
		desired_type = "signal"
		desired_identifier = current_signal_name
	elif editing_variable and current_variable_name != "":
		desired_type = "variable"
	elif editing_enum and current_enum_name != "":
		desired_type = "enum"
		desired_identifier = current_enum_name
	elif editing_region and current_region_name != "":
		desired_type = "region"
		desired_identifier = current_region_name
	elif editing_class and current_class_name != "":
		desired_type = "class"
		desired_identifier = current_class_name
	elif selected_function_index >= 0:
		desired_type = "function"
		desired_identifier = selected_function_index

	tree.clear()

	if sync == null or sync.nodescript == null:
		return

	match tree_display_mode:
		1:
			_build_tree_true()
		2:
			_build_tree_flat()
		_:
			var script_item := _create_root_script_item()
			if script_item:
				_add_signals_to_tree(script_item)
				_add_variables_to_tree(script_item)
				_add_enums_to_tree(script_item)
				_add_regions_to_tree(script_item)
				_add_classes_to_tree(script_item)
				_add_functions_to_tree(script_item)

	if desired_type != "":
		if _select_tree_item(desired_type, desired_identifier):
			return

	_select_first_function_in_tree()


func _get_script_display_name() -> String:
	if active_script:
		if active_script.resource_path != "":
			return active_script.resource_path.get_file()
		if active_script.resource_name != "":
			return active_script.resource_name
	return "Script"


func _add_signals_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var section = _create_tree_item(parent, "Signals", {"type": "section", "section": "signals"}, "MemberSignal", "Folder")
	section.collapsed = false
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	var names: Array = signals_dict.keys()
	if _should_sort_tree():
		names.sort()
	for name in names:
		if not _matches_filter(str(name)):
			continue
		_create_tree_item(section, str(name), {"type": "signal", "name": name}, "Signal", "Signal")
	_create_tree_item(section, "Add Signal", {"type": "signal_add"}, "Add", "Add")


func _add_variables_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var section = _create_tree_item(parent, "Variables", {"type": "section", "section": "variables"}, "MemberProperty", "Folder")
	section.collapsed = false
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	if _should_sort_tree():
		variables_array = variables_array.duplicate(true)
		variables_array.sort_custom(_sort_variables)
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name = str(entry.get("name", "<unnamed>"))
		if not _matches_filter(name):
			continue
		var icon_name = _variable_type_icon(entry)
		_create_tree_item(section, name, {"type": "variable", "name": name}, icon_name, "MemberProperty")
	_create_tree_item(section, "Add Variable", {"type": "variable_add"}, "Add", "Add")


func _add_enums_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	var names: Array = enums_dict.keys()
	if names.is_empty():
		return
	var section = _create_tree_item(parent, "Enums", {"type": "section", "section": "enums"}, _get_enum_icon_name(), "Folder")
	section.collapsed = false
	if _should_sort_tree():
		names.sort()
	var show_enum_values := show_enum_values_in_tree
	_log("Building enums; show values: %s" % ("true" if show_enum_values else "false"), 2)
	for name in names:
		if not _matches_filter(str(name)):
			continue
		var entry = enums_dict.get(name, {})
		var enum_item = _create_tree_item(section, str(name), {"type": "enum", "name": name}, _get_enum_icon_name(), _get_enum_icon_name())
		if show_enum_values:
			var values: Array = _enum_values(entry)
			if typeof(values) == TYPE_ARRAY and not values.is_empty():
				for value_name in values:
					if not _matches_filter(str(value_name)):
						continue
					_create_tree_item(enum_item, str(value_name), {"type": "enum_value", "name": value_name, "enum": name}, _get_enum_icon_name(), _get_enum_icon_name())
	_create_tree_item(section, "Add Enum", {"type": "enum_add"}, "Add", "Add")


func _add_regions_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var regions_array: Array = sync.nodescript.body.get("regions", [])
	var section = _create_tree_item(parent, "Regions", {"type": "section", "section": "regions"}, _get_region_icon_name(), "Folder")
	section.collapsed = false
	for entry in regions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", "<unnamed>"))
		if not _matches_filter(name):
			continue
		_create_tree_item(section, name, {"type": "region", "name": name}, _get_region_icon_name(), _get_region_icon_name())
	_create_tree_item(section, "Add Region", {"type": "region_add"}, "Add", "Add")


func _add_classes_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var classes_array: Array = sync.nodescript.body.get("classes", [])
	var meta_class := ""
	if sync and sync.nodescript and typeof(sync.nodescript.meta) == TYPE_DICTIONARY:
		meta_class = str(sync.nodescript.meta.get("class_name", "")).strip_edges()
	if meta_class != "":
		var exists := false
		for entry in classes_array:
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == meta_class:
				exists = true
				break
		if not exists:
			classes_array = classes_array.duplicate()
			classes_array.append({"name": meta_class, "extends": str(sync.nodescript.meta.get("extends", ""))})
			sync.nodescript.body["classes"] = classes_array
	var section = _create_tree_item(parent, "Classes", {"type": "section", "section": "classes"}, "MiniObject", "Folder")
	section.collapsed = false
	for entry in classes_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", "<unnamed>"))
		if not _matches_filter(name):
			continue
		_create_tree_item(section, name, {"type": "class", "name": name}, "MiniObject", "MiniObject")
	_create_tree_item(section, "Add Class", {"type": "class_add"}, "Add", "Add")


func _add_functions_to_tree(parent: TreeItem) -> void:
	if tree == null or sync == null or sync.nodescript == null:
		return
	var section = _create_tree_item(parent, "Functions", {"type": "section", "section": "functions"}, "MemberMethod", "Folder")
	section.collapsed = false
	var methods: Array = sync.nodescript.body.get("functions", [])
	for i in range(methods.size()):
		var method = methods[i]
		if typeof(method) != TYPE_DICTIONARY:
			continue
		var name = str(method.get("name", "<unnamed>"))
		if not _matches_filter(name):
			continue
		var func_item = _create_tree_item(section, name, {"type": "function", "index": i}, "MemberMethod", "MemberMethod")
		func_item.collapsed = true
	_create_tree_item(section, "Add Function", {"type": "function_add"}, "Add", "Add")


func _add_function_blocks_to_tree(parent: TreeItem, method: Dictionary, function_index: int) -> void:
	return # detaching function body children for now


func _format_block_label(statement: Dictionary) -> String:
	var block_type = str(statement.get("type", "statement"))
	match block_type:
		"comment":
			var text = str(statement.get("text", "")).strip_edges()
			return text if text != "" else "comment"
		_:
			return block_type


func _create_tree_item(parent: TreeItem, text: String, metadata: Dictionary, icon_name: String = "", fallback_icon: String = "Node") -> TreeItem:
	return NodeScriptTreeUtils.create_item(tree, parent, text, metadata, _get_editor_icon(icon_name, fallback_icon))


func _select_tree_item(type: String, identifier) -> bool:
	var item = _find_tree_item_of_type(type, identifier)
	if item:
		tree.set_selected(item, 0)
		tree.ensure_cursor_is_visible()
		_on_tree_item_selected()
		return true
	return false


func _select_first_function_in_tree() -> void:
	if not _select_tree_item("function", null):
		_clear_function_view()


func _find_tree_item_of_type(desired_type: String, identifier) -> TreeItem:
	if tree == null:
		return null
	var root = tree.get_root()
	if root == null:
		return null
	return _find_tree_item_recursive(root.get_first_child(), desired_type, identifier)


func _find_tree_item_recursive(item: TreeItem, desired_type: String, identifier) -> TreeItem:
	var current = item
	while current:
		var data = current.get_metadata(0)
		if typeof(data) == TYPE_DICTIONARY and data.get("type", "") == desired_type:
			if identifier == null:
				return current
			match desired_type:
				"function":
					if int(data.get("index", -1)) == int(identifier):
						return current
				_:
					if str(data.get("name", "")) == str(identifier):
						return current
		var child = current.get_first_child()
		if child:
			var found = _find_tree_item_recursive(child, desired_type, identifier)
			if found:
				return found
		current = current.get_next()
	return null


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


func _ensure_function_blocks_for_item(item: TreeItem, index: int) -> void:
	if item == null or sync == null or sync.nodescript == null:
		return
	if item.get_first_child():
		return
	var methods: Array = sync.nodescript.body.get("functions", [])
	if index < 0 or index >= methods.size():
		return
	var method = methods[index]
	if typeof(method) != TYPE_DICTIONARY:
		return
	_add_function_blocks_to_tree(item, method, index)


func _clear_function_view() -> void:
	selected_function_index = -1
	_apply_function_body_to_editor(null)


func _show_signal_editor() -> void:
	if signal_editor:
		creating_signal = true
		editing_signal = false
		creating_variable = false
		editing_variable = false
		creating_enum = false
		editing_enum = false
		_clear_region_state()
		_clear_class_state()
		current_enum_name = ""
		creating_variable = false
		editing_variable = false
		current_signal_name = ""
		if signal_editor.has_method("set_region_class_lists"):
			signal_editor.set_region_class_lists(_available_regions(), _available_classes())
		if signal_editor.has_method("start_new"):
			signal_editor.start_new()
		signal_editor.show()
	if variable_editor:
		variable_editor.hide()
	if enum_editor:
		enum_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _hide_signal_editor(refresh_list: bool = true) -> void:
	if signal_editor:
		signal_editor.hide()
		if refresh_list and signal_editor.has_method("reset_form_state"):
			signal_editor.reset_form_state()
	creating_signal = false
	editing_signal = false
	current_signal_name = ""
	if refresh_list:
		_refresh_tree()
	_refresh_right_panel_visibility()


func _show_variable_editor() -> void:
	if variable_editor:
		creating_variable = true
		editing_variable = false
		creating_signal = false
		editing_signal = false
		creating_enum = false
		editing_enum = false
		_clear_region_state()
		_clear_class_state()
		current_enum_name = ""
		current_variable_name = ""
		if variable_editor.has_method("set_region_class_lists"):
			variable_editor.set_region_class_lists(_available_regions(), _available_classes())
		if variable_editor.has_method("start_new"):
			variable_editor.start_new()
		variable_editor.show()
	if signal_editor:
		signal_editor.hide()
	if enum_editor:
		enum_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _hide_variable_editor(refresh_list: bool = true) -> void:
	if variable_editor:
		variable_editor.hide()
		if refresh_list and variable_editor.has_method("reset_form_state"):
			variable_editor.reset_form_state()
	creating_variable = false
	editing_variable = false
	current_variable_name = ""
	if refresh_list:
		_refresh_tree()
	_refresh_right_panel_visibility()


func _show_enum_editor() -> void:
	if enum_editor:
		creating_enum = true
		editing_enum = false
		creating_signal = false
		editing_signal = false
		creating_variable = false
		editing_variable = false
		_clear_region_state()
		_clear_class_state()
		current_enum_name = ""
		if enum_editor.has_method("set_region_class_lists"):
			enum_editor.set_region_class_lists(_available_regions(), _available_classes())
		if enum_editor.has_method("start_new"):
			enum_editor.start_new()
		enum_editor.show()
	if signal_editor:
		signal_editor.hide()
	if variable_editor:
		variable_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _hide_enum_editor(refresh_list: bool = true) -> void:
	if enum_editor:
		enum_editor.hide()
		if refresh_list and enum_editor.has_method("reset_form_state"):
			enum_editor.reset_form_state()
	creating_enum = false
	editing_enum = false
	current_enum_name = ""
	_clear_region_state()
	if refresh_list:
		_refresh_tree()
	_refresh_right_panel_visibility()


func _show_existing_signal(signal_name: String) -> void:
	if signal_editor == null:
		return
	creating_signal = false
	editing_signal = true
	creating_variable = false
	editing_variable = false
	creating_enum = false
	editing_enum = false
	_clear_region_state()
	_clear_class_state()
	current_signal_name = signal_name
	var parameters = []
	var signal_entry: Dictionary = {}
	if sync and sync.nodescript:
		var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
		signal_entry = signals_dict.get(signal_name, [])
		if typeof(signal_entry) == TYPE_DICTIONARY:
			parameters = signal_entry.get("parameters", [])
		elif typeof(signal_entry) == TYPE_ARRAY:
			parameters = signal_entry
	if signal_editor.has_method("show_signal"):
		signal_editor.show_signal(signal_name, parameters)
	if signal_editor.has_method("set_region_class_lists"):
		signal_editor.set_region_class_lists(_available_regions(), _available_classes())
	if signal_editor.has_method("set_region_class"):
		signal_editor.set_region_class(str(signal_entry.get("region", "")), str(signal_entry.get("class", "")))
	signal_editor.show()
	if variable_editor:
		variable_editor.hide()
	if enum_editor:
		enum_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _show_existing_variable(variable_name: String) -> void:
	if variable_editor == null:
		return
	creating_variable = false
	editing_variable = true
	creating_signal = false
	editing_signal = false
	creating_enum = false
	editing_enum = false
	_clear_region_state()
	_clear_class_state()
	current_variable_name = variable_name
	var variable_data: Dictionary = {}
	if sync and sync.nodescript:
		var variables_array: Array = sync.nodescript.body.get("variables", [])
		for entry in variables_array:
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == variable_name:
				variable_data = entry
				break
	if variable_editor.has_method("set_region_class_lists"):
		variable_editor.set_region_class_lists(_available_regions(), _available_classes())
	if variable_editor.has_method("set_region_class"):
		variable_editor.set_region_class(str(variable_data.get("region", "")), str(variable_data.get("class", "")))
	if variable_editor.has_method("show_variable"):
		variable_editor.show_variable(variable_data)
	variable_editor.show()
	if signal_editor:
		signal_editor.hide()
	if enum_editor:
		enum_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _show_existing_enum(enum_name: String) -> void:
	if enum_editor == null:
		return
	creating_enum = false
	editing_enum = true
	creating_signal = false
	editing_signal = false
	creating_variable = false
	editing_variable = false
	_clear_region_state()
	_clear_class_state()
	current_enum_name = enum_name
	var values: Array = []
	var enum_entry: Dictionary = {}
	if sync and sync.nodescript:
		var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
		enum_entry = enums_dict.get(enum_name, {})
		values = _enum_values(enum_entry)
	if enum_editor.has_method("show_enum"):
		enum_editor.show_enum(enum_name, values)
	if enum_editor.has_method("set_region_class_lists"):
		enum_editor.set_region_class_lists(_available_regions(), _available_classes())
	if enum_editor.has_method("set_region_class"):
		enum_editor.set_region_class(str(enum_entry.get("region", "")), str(enum_entry.get("class", "")))
	enum_editor.show()
	if signal_editor:
		signal_editor.hide()
	if variable_editor:
		variable_editor.hide()
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _refresh_right_panel_visibility() -> void:
	var show_signal = creating_signal or editing_signal
	var show_variable = creating_variable or editing_variable
	var show_enum = creating_enum or editing_enum
	var show_region := creating_region or editing_region
	var show_class := creating_class or editing_class
	var show_root_meta := not show_signal and not show_variable and not show_enum and not show_region and not show_class and current_region_name == "" and current_signal_name == "" and current_variable_name == "" and current_enum_name == "" and selected_function_index == -1 and current_class_name == ""
	var show_function = not show_signal and not show_variable and not show_enum and not show_region and not show_class and not show_root_meta
	if function_body_editor:
		function_body_editor.visible = show_function
	if signal_editor:
		signal_editor.visible = show_signal
	if variable_editor:
		variable_editor.visible = show_variable
	if enum_editor:
		enum_editor.visible = show_enum
	if region_editor:
		region_editor.visible = show_region
	if class_editor:
		class_editor.visible = show_class
	if root_meta_editor:
		root_meta_editor.visible = show_root_meta
	# Show script info only when not in a specific editor view.
	# Script info/header are no longer used.


func _on_signal_editor_delete_requested() -> void:
	if creating_signal:
		_hide_signal_editor()
		return
	if not editing_signal or current_signal_name == "":
		_hide_signal_editor()
		return
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot delete signal without a loaded NodeScript resource.")
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	if signals_dict.has(current_signal_name):
		signals_dict.erase(current_signal_name)
		sync.nodescript.body["signals"] = signals_dict
		sync.save()
	current_signal_name = ""
	editing_signal = false
	_refresh_tree()
	_apply_declarations_to_script()
	_hide_signal_editor(false)


func _on_signal_editor_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot add signal without a loaded NodeScript resource.")
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	var desired_name: String = _sanitize_identifier(data.get("name", ""), "signal")
	var target_name: String = desired_name
	var parameters = data.get("parameters", []).duplicate(true)
	var region := str(data.get("region", "")).strip_edges()
	var cls := str(data.get("class", "")).strip_edges()

	if editing_signal and current_signal_name != "":
		var existing_names: Array = []
		for key in signals_dict.keys():
			if str(key) != current_signal_name:
				existing_names.append(str(key))
		target_name = _ensure_unique_name(desired_name, existing_names, "signal")
		if signals_dict.has(current_signal_name):
			signals_dict.erase(current_signal_name)
	else:
		var existing_names: Array = Array(signals_dict.keys())
		target_name = _ensure_unique_name(desired_name, existing_names, "signal")

	signals_dict[target_name] = {
		"parameters": parameters,
		"region": region,
		"class": cls
	}
	sync.nodescript.body["signals"] = signals_dict
	sync.save()
	creating_signal = false
	editing_signal = true
	current_signal_name = target_name
	_refresh_tree()
	_select_tree_item("signal", target_name)
	_apply_declarations_to_script()
	_hide_signal_editor(false)


func _on_signal_editor_add_param_requested() -> void:
	if signal_editor == null:
		return
	var callback = Callable(signal_editor, "add_parameter_from_picker") if signal_editor.has_method("add_parameter_from_picker") else Callable()
	if not callback.is_valid():
		push_warning("NodeScriptPanel: SignalEditor cannot accept parameters (method missing).")
		return
	_request_type_selection({
		"title": "Signal Parameter Type",
		"ask_for_name": true,
		"name_placeholder": "Parameter name"
	}, callback)


func _on_variable_editor_delete_requested() -> void:
	if creating_variable:
		_hide_variable_editor()
		return
	if not editing_variable or current_variable_name == "":
		_hide_variable_editor()
		return
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot delete variable without a loaded NodeScript resource.")
		return
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for i in range(variables_array.size()):
		var entry = variables_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_variable_name:
			variables_array.remove_at(i)
			break
	sync.nodescript.body["variables"] = variables_array
	sync.save()
	current_variable_name = ""
	editing_variable = false
	_refresh_tree()
	_apply_declarations_to_script()
	_hide_variable_editor(false)


func _on_variable_editor_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot add variable without a loaded NodeScript resource.")
		return
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	var desired_name: String = _sanitize_identifier(data.get("name", ""), "variable")
	var existing_names: Array = []
	for var_dict in variables_array:
		if typeof(var_dict) == TYPE_DICTIONARY:
			var name = str(var_dict.get("name", ""))
			if not (editing_variable and name == current_variable_name):
				existing_names.append(name)

	var target_name = _ensure_unique_name(desired_name, existing_names, "variable")
	data["name"] = target_name
	var region := str(data.get("region", "")).strip_edges()
	var cls := str(data.get("class", "")).strip_edges()
	data["region"] = region
	data["class"] = cls

	var did_update = false
	if editing_variable and current_variable_name != "":
		for i in range(variables_array.size()):
			var entry = variables_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_variable_name:
				variables_array[i] = data
				did_update = true
				break
	if not did_update:
		variables_array.append(data)

	sync.nodescript.body["variables"] = variables_array
	sync.save()
	creating_variable = false
	editing_variable = true
	current_variable_name = target_name
	_refresh_tree()
	_select_tree_item("variable", target_name)
	_apply_declarations_to_script()
	_hide_variable_editor(false)


func _on_variable_editor_type_pick_requested() -> void:
	if variable_editor == null:
		return
	var callback = Callable(variable_editor, "set_selected_type") if variable_editor.has_method("set_selected_type") else Callable()
	if not callback.is_valid():
		push_warning("NodeScriptPanel: VariableEditor missing 'set_selected_type'.")
		return
	_request_type_selection({
		"title": "Variable Type",
		"ask_for_name": false
	}, callback)


func _on_enum_editor_delete_requested() -> void:
	if creating_enum:
		_hide_enum_editor()
		return
	if not editing_enum or current_enum_name == "":
		_hide_enum_editor()
		return
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot delete enum without a loaded NodeScript resource.")
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	if enums_dict.has(current_enum_name):
		enums_dict.erase(current_enum_name)
		sync.nodescript.body["enums"] = enums_dict
		sync.save()
	current_enum_name = ""
	editing_enum = false
	_refresh_tree()
	_apply_declarations_to_script()
	_hide_enum_editor(false)


func _on_enum_editor_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot add enum without a loaded NodeScript resource.")
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	var desired_name: String = _sanitize_identifier(data.get("name", ""), "Enum")
	var values: Array = []
	if typeof(data.get("values", [])) == TYPE_ARRAY:
		for v in data.get("values", []):
			var sanitized := _sanitize_enum_value(str(v))
			if sanitized != "":
				values.append(sanitized)

	var region := str(data.get("region", "")).strip_edges()
	var cls := str(data.get("class", "")).strip_edges()

	var target_name: String = desired_name
	if editing_enum and current_enum_name != "":
		var existing_names: Array = []
		for key in enums_dict.keys():
			if str(key) != current_enum_name:
				existing_names.append(str(key))
		target_name = _ensure_unique_name(desired_name, existing_names, "Enum")
		if enums_dict.has(current_enum_name):
			enums_dict.erase(current_enum_name)
	else:
		var existing_names: Array = Array(enums_dict.keys())
		target_name = _ensure_unique_name(desired_name, existing_names, "Enum")

	enums_dict[target_name] = {"values": values, "region": region, "class": cls}
	sync.nodescript.body["enums"] = enums_dict
	sync.save()
	creating_enum = false
	editing_enum = true
	current_enum_name = target_name
	_refresh_tree()
	_select_tree_item("enum", target_name)
	_apply_declarations_to_script()
	_hide_enum_editor(false)


func _request_type_selection(config: Dictionary, callback: Callable) -> void:
	if type_picker_popup == null:
		push_warning("NodeScriptPanel: TypePickerPopup missing; cannot pick types.")
		return
	if callback.is_valid():
		type_picker_popup.prompt(config, callback)
	else:
		push_warning("NodeScriptPanel: Invalid callback for type picker.")


func _show_region_editor(create_new: bool, region_name: String) -> void:
	if region_editor == null:
		return
	creating_region = create_new
	editing_region = not create_new
	creating_signal = false
	editing_signal = false
	creating_variable = false
	editing_variable = false
	creating_enum = false
	editing_enum = false
	creating_class = false
	editing_class = false
	current_region_name = region_name
	if region_editor.has_method("set_region_class_lists"):
		region_editor.set_region_class_lists(_available_regions(), _available_classes())
	if create_new:
		if region_editor.has_method("start_new"):
			region_editor.start_new()
	else:
		var entry := _find_region_entry(region_name)
		entry["regions_list"] = _available_regions()
		entry["classes_list"] = _available_classes()
		if region_editor.has_method("show_region"):
			region_editor.show_region(entry)
		if region_editor.has_method("set_region_class"):
			region_editor.set_region_class(str(entry.get("region", "")), str(entry.get("class", "")))
	if class_editor:
		class_editor.hide()
	_refresh_right_panel_visibility()


func _on_region_editor_delete_requested() -> void:
	if sync == null or sync.nodescript == null:
		_hide_region_editor()
		return
	var has_children := _region_has_children(current_region_name)
	if has_children:
		_show_delete_dialog("region", current_region_name)
		return
	_delete_region_only(current_region_name)


func _on_region_editor_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot add region without a loaded NodeScript resource.")
		return
	var regions: Array = sync.nodescript.body.get("regions", [])
	var desired_name: String = _sanitize_identifier(data.get("name", ""), "Region")
	var existing_names: Array[String] = []
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var nm := str(entry.get("name", ""))
		if editing_region and nm == current_region_name:
			continue
		existing_names.append(nm)
	var target_name := _ensure_unique_name(desired_name, existing_names, "Region")

	if editing_region and current_region_name != "":
		for entry in regions:
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_region_name:
				entry["name"] = target_name
				entry["class"] = str(data.get("class", ""))
				entry["region"] = str(data.get("region", ""))
		_update_item_region_references(current_region_name, target_name)
	else:
		regions.append({
			"name": target_name,
			"class": str(data.get("class", "")),
			"region": str(data.get("region", ""))
		})

	sync.nodescript.body["regions"] = regions
	sync.save()
	creating_region = false
	editing_region = true
	current_region_name = target_name
	_refresh_tree()
	_select_tree_item("region", target_name)
	_apply_declarations_to_script()
	if _pending_function_region_assign:
		_assign_region_to_selected_function(target_name)
	_pending_function_region_assign = false
	_refresh_right_panel_visibility()


func _on_class_editor_delete_requested() -> void:
	if sync == null or sync.nodescript == null:
		_hide_class_editor()
		return
	var has_children := _class_has_children(current_class_name)
	if has_children:
		_show_delete_dialog("class", current_class_name)
		return
	_delete_class_only(current_class_name)


func _on_class_editor_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		push_warning("NodeScriptPanel: Cannot add class without a loaded NodeScript resource.")
		return
	var classes: Array = sync.nodescript.body.get("classes", [])
	var desired_name: String = _sanitize_identifier(data.get("name", ""), "Class")
	var region := str(data.get("region", "")).strip_edges()
	var cls_parent := str(data.get("class", "")).strip_edges()
	var existing_names: Array[String] = []
	var old_region := ""
	var old_name := current_class_name
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var nm := str(entry.get("name", ""))
		if editing_class and nm == current_class_name:
			old_region = str(entry.get("region", ""))
			continue
		existing_names.append(nm)
	var target_name := _ensure_unique_name(desired_name, existing_names, "Class")

	if editing_class and current_class_name != "":
		for i in range(classes.size()):
			var entry = classes[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_class_name:
				entry["name"] = target_name
				entry["extends"] = str(data.get("extends", ""))
				entry["region"] = region
				entry["class"] = cls_parent
				classes[i] = entry
	else:
		classes.append({
			"name": target_name,
			"extends": str(data.get("extends", "")),
			"region": region,
			"class": cls_parent
		})

	sync.nodescript.body["classes"] = classes
	if editing_class and old_name != "":
		_rename_class_references(old_name, target_name, old_region, region)
	sync.save()
	creating_class = false
	editing_class = true
	current_class_name = target_name
	_refresh_tree()
	_select_tree_item("class", target_name)
	_apply_declarations_to_script()
	if _pending_function_class_assign:
		_assign_class_to_selected_function(target_name, region)
	_pending_function_class_assign = false
	_refresh_right_panel_visibility()


func _on_class_editor_name_changed(new_name: String) -> void:
	pass


func _on_class_editor_name_commit_requested(new_name: String) -> void:
	if class_editor and class_editor.has_method("set_name_text"):
		var trimmed = _sanitize_identifier(new_name, "Class")
		class_editor.set_name_text(trimmed)


func _region_has_children(region_name: String) -> bool:
	if sync == null or sync.nodescript == null:
		return false
	if region_name.strip_edges() == "":
		return false
	var rn := region_name.strip_edges()
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_region(entry) == rn:
			return true
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for v in signals_dict.values():
		if typeof(v) == TYPE_DICTIONARY and str(v.get("region", "")) == rn:
			return true
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for k in enums_dict.keys():
		if str(_entry_region(enums_dict.get(k, {}))) == rn:
			return true
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
			return true
	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
			return true
	var classes_array: Array = sync.nodescript.body.get("classes", [])
	for entry in classes_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
			return true
	return false


func _class_has_children(class_title: String) -> bool:
	if sync == null or sync.nodescript == null:
		return false
	if class_title.strip_edges() == "":
		return false
	var cn := class_title.strip_edges()
	var class_entry := _find_class_entry(cn)
	var class_region := _entry_region(class_entry)
	if NodeScriptUtils.class_has_members(sync.nodescript, cn, class_region):
		return true

	var regions_array: Array = sync.nodescript.body.get("regions", [])
	for entry in regions_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("class", "")) == cn:
			return true

	# Check order scope for any entries (regions/classes/functions/etc).
	var order := _scope_order_for(cn, class_region)
	for e in order:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("type", "")) != "":
			return true

	return false


func _delete_region_only(region_name: String, flatten_children: bool = false) -> void:
	if sync == null or sync.nodescript == null:
		return
	var rn := region_name.strip_edges()
	var regions: Array = sync.nodescript.body.get("regions", [])
	var parent_region := ""
	var child_regions: Array[String] = []
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == rn:
			parent_region = _entry_region(entry)
			break
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_region(entry) == rn:
			child_regions.append(str(entry.get("name", "")).strip_edges())
	var new_regions: Array = []
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var name := str(entry.get("name", "")).strip_edges()
		if name == rn:
			continue
		# Flatten direct child regions up to the deleted region's parent.
		if flatten_children and str(entry.get("region", "")).strip_edges() == rn:
			entry["region"] = parent_region
		new_regions.append(entry)
	sync.nodescript.body["regions"] = new_regions
	if flatten_children and rn != "":
		var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
		for key in signals_dict.keys():
			var v = signals_dict.get(key, {})
			if typeof(v) == TYPE_DICTIONARY and str(v.get("region", "")) == rn:
				v["region"] = parent_region
				signals_dict[key] = v
		sync.nodescript.body["signals"] = signals_dict

		var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
		for key in enums_dict.keys():
			var val = enums_dict.get(key, {})
			if typeof(val) == TYPE_DICTIONARY and str(val.get("region", "")) == rn:
				val["region"] = parent_region
				enums_dict[key] = val
		sync.nodescript.body["enums"] = enums_dict

		var variables_array: Array = sync.nodescript.body.get("variables", [])
		for i in range(variables_array.size()):
			var entry = variables_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
				entry["region"] = parent_region
				variables_array[i] = entry
		sync.nodescript.body["variables"] = variables_array

		var functions_array: Array = sync.nodescript.body.get("functions", [])
		for i in range(functions_array.size()):
			var entry = functions_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
				entry["region"] = parent_region
				functions_array[i] = entry
		sync.nodescript.body["functions"] = functions_array

		var classes_array: Array = sync.nodescript.body.get("classes", [])
		for i in range(classes_array.size()):
			var entry = classes_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == rn:
				entry["region"] = parent_region
				classes_array[i] = entry
		sync.nodescript.body["classes"] = classes_array

	# Remove only the deleted region markers; keep child markers when flattening.
	_remove_region_markers_from_script([rn], false)
	_reparent_or_remove_region_order(rn, parent_region, "", false)

	sync.save()
	current_region_name = ""
	creating_region = false
	editing_region = false
	_refresh_tree()
	_hide_region_editor()
	_apply_declarations_to_script()


func _delete_region_with_children(region_name: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	var rn := region_name.strip_edges()
	if rn == "":
		return
	var descendant_regions := _collect_region_descendants(rn)
	_delete_region_only(rn, false)
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in Array(signals_dict.keys()):
		var v = signals_dict.get(key, {})
		if typeof(v) == TYPE_DICTIONARY and descendant_regions.has(str(v.get("region", ""))):
			signals_dict.erase(key)
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in Array(enums_dict.keys()):
		var val = enums_dict.get(key, {})
		if typeof(val) == TYPE_DICTIONARY and descendant_regions.has(str(val.get("region", ""))):
			enums_dict.erase(key)
	sync.nodescript.body["enums"] = enums_dict

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for i in range(variables_array.size() - 1, -1, -1):
		var entry = variables_array[i]
		if typeof(entry) == TYPE_DICTIONARY and descendant_regions.has(str(entry.get("region", ""))):
			variables_array.remove_at(i)
	sync.nodescript.body["variables"] = variables_array

	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for i in range(functions_array.size() - 1, -1, -1):
		var entry = functions_array[i]
		if typeof(entry) == TYPE_DICTIONARY and descendant_regions.has(str(entry.get("region", ""))):
			functions_array.remove_at(i)
	sync.nodescript.body["functions"] = functions_array

	var classes_array: Array = sync.nodescript.body.get("classes", [])
	for i in range(classes_array.size() - 1, -1, -1):
		var entry = classes_array[i]
		if typeof(entry) == TYPE_DICTIONARY and descendant_regions.has(str(entry.get("region", ""))):
			classes_array.remove_at(i)
	sync.nodescript.body["classes"] = classes_array

	_remove_region_markers_from_script(descendant_regions.keys(), true)
	_reparent_or_remove_region_order(rn, "", "", true)

	sync.save()
	current_region_name = ""
	creating_region = false
	editing_region = false
	_refresh_tree()
	_hide_region_editor()
	_apply_declarations_to_script()


func _delete_class_only(class_title: String, flatten_children: bool = false) -> void:
	if sync == null or sync.nodescript == null:
		return
	var classes: Array = sync.nodescript.body.get("classes", [])
	var new_classes: Array = []
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == class_title:
			continue
		new_classes.append(entry)
	sync.nodescript.body["classes"] = new_classes

	if flatten_children and class_title.strip_edges() != "":
		var cn := class_title.strip_edges()
		var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
		for key in signals_dict.keys():
			var v = signals_dict.get(key, {})
			if typeof(v) == TYPE_DICTIONARY and str(v.get("class", "")) == cn:
				v["class"] = ""
				signals_dict[key] = v
		sync.nodescript.body["signals"] = signals_dict

		var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
		for key in enums_dict.keys():
			var val = enums_dict.get(key, {})
			if typeof(val) == TYPE_DICTIONARY and str(val.get("class", "")) == cn:
				val["class"] = ""
				enums_dict[key] = val
		sync.nodescript.body["enums"] = enums_dict

		var variables_array: Array = sync.nodescript.body.get("variables", [])
		for i in range(variables_array.size()):
			var entry = variables_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("class", "")) == cn:
				entry["class"] = ""
				variables_array[i] = entry
		sync.nodescript.body["variables"] = variables_array

		var functions_array: Array = sync.nodescript.body.get("functions", [])
		for i in range(functions_array.size()):
			var entry = functions_array[i]
			if typeof(entry) == TYPE_DICTIONARY and str(entry.get("class", "")) == cn:
				entry["class"] = ""
				functions_array[i] = entry
		sync.nodescript.body["functions"] = functions_array

	sync.save()
	current_class_name = ""
	creating_class = false
	editing_class = false
	_refresh_tree()
	_hide_class_editor()
	_apply_declarations_to_script()


func _delete_class_with_children(class_title: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	var cn := class_title.strip_edges()
	if cn == "":
		return
	_delete_class_only(cn, false)

	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in Array(signals_dict.keys()):
		var v = signals_dict.get(key, {})
		if typeof(v) == TYPE_DICTIONARY and str(v.get("class", "")) == cn:
			signals_dict.erase(key)
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in Array(enums_dict.keys()):
		var val = enums_dict.get(key, {})
		if typeof(val) == TYPE_DICTIONARY and str(val.get("class", "")) == cn:
			enums_dict.erase(key)
	sync.nodescript.body["enums"] = enums_dict

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for i in range(variables_array.size() - 1, -1, -1):
		var entry = variables_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("class", "")) == cn:
			variables_array.remove_at(i)
	sync.nodescript.body["variables"] = variables_array

	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for i in range(functions_array.size() - 1, -1, -1):
		var entry = functions_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("class", "")) == cn:
			functions_array.remove_at(i)
	sync.nodescript.body["functions"] = functions_array

	sync.save()
	current_class_name = ""
	creating_class = false
	editing_class = false
	_refresh_tree()
	_hide_class_editor()
	_apply_declarations_to_script()


func _collect_region_descendants(root_region: String) -> Dictionary:
	var result: Dictionary = {}
	var target := root_region.strip_edges()
	if target == "":
		return result
	result[target] = true
	if sync == null or sync.nodescript == null:
		return result
	var regions: Array = sync.nodescript.body.get("regions", [])
	var changed := true
	while changed:
		changed = false
		for entry in regions:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var name := str(entry.get("name", "")).strip_edges()
			if name == "" or result.has(name):
				continue
			var parent := _entry_region(entry)
			if result.has(parent):
				result[name] = true
				changed = true
	return result


func _remove_region_markers_from_script(region_names: Array, include_descendants: bool = false) -> void:
	if active_script == null or region_names.is_empty():
		return
	var names: Array[String] = []
	for n in region_names:
		names.append(str(n).strip_edges())
	names = names.filter(func(x): return x != "")
	if names.is_empty():
		return
	var lines: PackedStringArray = active_script.source_code.split("\n", true)
	var filtered: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		var skip := false
		if trimmed.begins_with("#region") or trimmed.begins_with("#endregion"):
			for name in names:
				if name == "":
					continue
				var token_idx := trimmed.find(" ")
				var line_name := ""
				if token_idx != -1:
					line_name = trimmed.substr(token_idx + 1).strip_edges()
				if line_name == "":
					continue
				if line_name == name:
					skip = true
					break
				if include_descendants and line_name.begins_with(name):
					skip = true
					break
		if not skip:
			filtered.append(line)
	active_script.source_code = "\n".join(filtered)


func _reparent_or_remove_region_order(region_name: String, parent_region: String, parent_class: String, remove_descendants: bool) -> void:
	if sync == null or sync.nodescript == null:
		return
	var order: Dictionary = sync.nodescript.body.get("order", {})
	if order.is_empty():
		return
	var parent_key := _scope_key(parent_class, parent_region)
	if order.has(parent_key):
		var entries: Array = order.get(parent_key, [])
		var filtered: Array = []
		for e in entries:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if str(e.get("type", "")) == "region" and str(e.get("name", "")) == region_name:
				continue
			filtered.append(e)
		order[parent_key] = filtered

	var keys := Array(order.keys())
	for key in keys:
		var parts := _split_scope_key(str(key))
		var scope_cls := parts[0]
		var scope_region := parts[1]
		if scope_region != region_name:
			continue
		var entries: Array = order.get(key, [])
		order.erase(key)
		if remove_descendants:
			continue
		var dest_key := _scope_key(scope_cls, parent_region)
		var dest_entries: Array = order.get(dest_key, [])
		if dest_entries == null:
			dest_entries = []
		dest_entries.append_array(entries)
		order[dest_key] = dest_entries
	sync.nodescript.body["order"] = order


func _on_region_editor_name_changed(new_name: String) -> void:
	pass


func _on_region_editor_name_commit_requested(new_name: String) -> void:
	if region_editor and region_editor.has_method("set_name_text"):
		var trimmed = _sanitize_identifier(new_name, "Region")
		region_editor.set_name_text(trimmed)


func _update_item_region_references(old_name: String, new_name: String) -> void:
	if old_name == new_name or sync == null or sync.nodescript == null:
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for key in signals_dict.keys():
		var entry = signals_dict.get(key, {})
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == old_name:
			entry["region"] = new_name
			signals_dict[key] = entry
	sync.nodescript.body["signals"] = signals_dict

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var entry = enums_dict.get(key, {})
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == old_name:
			entry["region"] = new_name
			enums_dict[key] = entry
	sync.nodescript.body["enums"] = enums_dict

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for i in range(variables_array.size()):
		var entry = variables_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == old_name:
			entry["region"] = new_name
			variables_array[i] = entry
	sync.nodescript.body["variables"] = variables_array

	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for i in range(functions_array.size()):
		var entry = functions_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("region", "")) == old_name:
			entry["region"] = new_name
			functions_array[i] = entry
	sync.nodescript.body["functions"] = functions_array


func _hide_region_editor() -> void:
	if region_editor:
		region_editor.hide()
	creating_region = false
	editing_region = false
	current_region_name = ""
	_pending_function_region_assign = false
	_refresh_right_panel_visibility()


func _show_class_editor(create_new: bool, class_name_value: String) -> void:
	if class_editor == null:
		return
	creating_class = create_new
	editing_class = not create_new
	creating_signal = false
	editing_signal = false
	creating_variable = false
	editing_variable = false
	creating_enum = false
	editing_enum = false
	creating_region = false
	editing_region = false
	if signal_editor:
		signal_editor.hide()
	if variable_editor:
		variable_editor.hide()
	if enum_editor:
		enum_editor.hide()
	current_class_name = class_name_value
	if class_editor.has_method("set_region_class_lists"):
		class_editor.set_region_class_lists(_available_regions(), _available_classes())
	if create_new:
		if class_editor.has_method("start_new"):
			class_editor.start_new()
	else:
		var entry := _find_class_entry(class_name_value)
		if class_editor.has_method("show_class"):
			class_editor.show_class(entry)
		if class_editor.has_method("set_region_class"):
			class_editor.set_region_class(str(entry.get("region", "")), str(entry.get("class", "")))
	_refresh_right_panel_visibility()


func _hide_class_editor(refresh_list: bool = true) -> void:
	if class_editor:
		class_editor.hide()
		if refresh_list and class_editor.has_method("reset_form_state"):
			class_editor.reset_form_state()
	creating_class = false
	editing_class = false
	current_class_name = ""
	_pending_function_class_assign = false
	if refresh_list:
		_refresh_tree()
	_refresh_right_panel_visibility()

func _show_root_meta_editor() -> void:
	if root_meta_editor == null or sync == null or sync.nodescript == null:
		return
	creating_signal = false
	editing_signal = false
	creating_variable = false
	editing_variable = false
	creating_enum = false
	editing_enum = false
	creating_region = false
	editing_region = false
	creating_class = false
	editing_class = false
	current_region_name = ""
	current_signal_name = ""
	current_variable_name = ""
	current_enum_name = ""
	current_class_name = ""
	if class_editor:
		class_editor.hide()
	selected_function_index = -1
	var file_name := _get_script_display_name()
	root_meta_editor.show_meta(sync.nodescript.meta, file_name)
	_refresh_right_panel_visibility()


func _on_root_meta_submitted(data: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		return
	var meta: Dictionary = sync.nodescript.meta if typeof(sync.nodescript.meta) == TYPE_DICTIONARY else {}
	meta["tool"] = data.get("tool", false)
	meta["extends"] = str(data.get("extends", "")).strip_edges()
	meta["class_name"] = str(data.get("class_name", "")).strip_edges()
	sync.nodescript.meta = meta
	sync.save()
	_apply_declarations_to_script()


func _on_signal_editor_name_changed(new_name: String) -> void:
	pass


func _on_variable_editor_name_changed(new_name: String) -> void:
	pass


func _on_enum_editor_name_changed(new_name: String) -> void:
	pass


func _on_signal_editor_name_commit_requested(new_name: String) -> void:
	var trimmed = _sanitize_identifier(new_name, "New_Signal")
	var signals_dict: Dictionary = {}
	var keys: Array = []
	if sync and sync.nodescript:
		signals_dict = sync.nodescript.body.get("signals", {})
		keys = Array(signals_dict.keys())
	var unique_name = _ensure_unique_name(trimmed, keys, "signal")
	if signal_editor and signal_editor.has_method("set_name_text"):
		signal_editor.set_name_text(unique_name)


func _on_variable_editor_name_commit_requested(new_name: String) -> void:
	var trimmed = _sanitize_identifier(new_name, "New_Variable")
	var existing_names: Array = []
	if sync and sync.nodescript:
		var variables_array: Array = sync.nodescript.body.get("variables", [])
		for var_dict in variables_array:
			if typeof(var_dict) == TYPE_DICTIONARY:
				existing_names.append(str(var_dict.get("name", "")))
	var unique_name = _ensure_unique_name(trimmed, existing_names, "variable")
	if variable_editor and variable_editor.has_method("set_name_text"):
		variable_editor.set_name_text(unique_name)


func _on_enum_editor_name_commit_requested(new_name: String) -> void:
	var trimmed = _sanitize_identifier(new_name, "New_Enum")
	var enums_dict: Dictionary = {}
	var keys: Array = []
	if sync and sync.nodescript:
		enums_dict = sync.nodescript.body.get("enums", {})
		keys = Array(enums_dict.keys())
	var unique_name = _ensure_unique_name(trimmed, keys, "enum")
	if enum_editor and enum_editor.has_method("set_name_text"):
		enum_editor.set_name_text(unique_name)


func _ensure_unique_name(desired_name: String, existing_names: Array, fallback_prefix: String) -> String:
	var base = desired_name.strip_edges()
	if base == "":
		base = fallback_prefix
	var final_name = base
	var counter = 2
	var existing: Dictionary = {}
	for name in existing_names:
		existing[str(name)] = true
	while existing.has(final_name):
		final_name = "%s_%d" % [base, counter]
		counter += 1
	return final_name


func _apply_declarations_to_script() -> void:
	if sync == null or sync.nodescript == null:
		return
	if active_script == null or sync.script_path == "":
		return

	var declarations: String = _get_declaration_source()
	var functions_tail := _sanitize_functions_tail(_extract_functions_section(active_script.source_code))
	functions_tail = _strip_removed_region_markers(functions_tail)

	var header_text := declarations
	if header_text != "" and not header_text.ends_with("\n"):
		header_text += "\n"
	if header_text != "" and functions_tail.strip_edges() != "" and not header_text.ends_with("\n\n"):
		header_text += "\n" # Ensure a blank line between declarations and functions.

	var combined := header_text + functions_tail
	if combined == "":
		return
	if not combined.ends_with("\n"):
		combined += "\n"

	active_script.source_code = combined
	var err := ResourceSaver.save(active_script, sync.script_path)
	if err != OK:
		push_warning("NodeScriptPanel: Failed to update script declarations (error %d)." % err)
	else:
		_log("Updated script: %s" % sync.script_path, 1)


func _extract_functions_section(source: String) -> String:
	var lines: PackedStringArray = source.split("\n", true)
	var start_index := -1
	var offset := 0
	for i in range(lines.size()):
		var line = lines[i]
		if line.strip_edges().begins_with("func "):
			start_index = i
			break
		offset += line.length()
		if i < lines.size() - 1:
			offset += 1
	if start_index == -1:
		return ""
	var tail := source.substr(offset, source.length() - offset)
	return tail


func _sanitize_functions_tail(tail: String) -> String:
	var lines := tail.split("\n", true)
	while not lines.is_empty():
		var first := lines[0].strip_edges()
		if first == "":
			break
		if first.begins_with("func "):
			break
		lines.remove_at(0)
	return "\n".join(lines)


func _strip_removed_region_markers(tail: String) -> String:
	if sync == null or sync.nodescript == null:
		return tail
	var valid: Dictionary = {}
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var nm := str(entry.get("name", "")).strip_edges()
		if nm != "":
			valid[nm] = true
	var lines := tail.split("\n", true)
	var cleaned: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		var is_region_line := trimmed.begins_with("#region ")
		var is_end_line := trimmed.begins_with("#endregion ")
		if is_region_line or is_end_line:
			var name := trimmed.substr(trimmed.find(" ") + 1).strip_edges()
			if name != "" and not valid.has(name):
				continue
		cleaned.append(line)
	return "\n".join(cleaned)


func _sanitize_identifier(name: String, fallback: String) -> String:
	var result = name.strip_edges()
	result = result.replace(" ", "_")
	if result == "":
		result = fallback
	return result


func _sanitize_enum_value(value: String) -> String:
	var trimmed := value.strip_edges().replace(" ", "_")
	return trimmed.to_upper()


func _should_sort_tree() -> bool:
	return auto_sort_tree_flag or tree_display_mode == 0 or tree_display_mode == 2


func _matches_filter(text: String) -> bool:
	if tree_filter_text == "":
		return true
	if text.strip_edges() == "<unnamed>":
		return false
	return text.to_lower().find(tree_filter_text) != -1


func _sort_variables(a, b) -> bool:
	var an := str(a.get("name", ""))
	var bn := str(b.get("name", ""))
	return an.nocasecmp_to(bn) < 0


func _variable_type_icon(entry: Dictionary) -> String:
	var raw := str(entry.get("type", "")).strip_edges()
	var lower := raw.to_lower()

	if raw == "":
		return _first_icon(["Variant", "Object"])

	var candidates: Array[String] = []
	# Exact names first (preserve case for built-ins like Sprite2D)
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


func _get_enum_icon_name() -> String:
	if _has_editor_icon("Enumeration"):
		return "Enumeration"
	if _has_editor_icon("Enum"):
		return "Enum"
	return "Node"


func _available_regions() -> Array[String]:
	if sync == null or sync.nodescript == null:
		return []
	var names: Array[String] = []
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) == TYPE_DICTIONARY:
			var nm := str(entry.get("name", "")).strip_edges()
			if nm != "" and not names.has(nm):
				names.append(nm)
	return names


func _available_classes() -> Array[String]:
	if sync == null or sync.nodescript == null:
		return []
	var names: Array[String] = []
	var classes: Array = sync.nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) == TYPE_DICTIONARY:
			var nm := str(entry.get("name", "")).strip_edges()
			if nm != "" and not names.has(nm):
				names.append(nm)
	if typeof(sync.nodescript.meta) == TYPE_DICTIONARY:
		var root_class := str(sync.nodescript.meta.get("class_name", "")).strip_edges()
		if root_class != "" and not names.has(root_class):
			names.append(root_class)
	return names


func _populate_option_button(button: OptionButton, items: Array[String]) -> void:
	if button == null:
		return
	button.clear()
	if items.is_empty():
		button.disabled = true
		button.text = "None available"
	else:
		button.disabled = false
		button.text = "Select"
		for item in items:
			button.add_item(str(item))


func _populate_function_org_option(button: OptionButton, items: Array[String], add_key: String, add_label: String) -> void:
	if button == null:
		return
	button.clear()
	for item in items:
		button.add_item(str(item))
	if not items.has(add_label):
		button.add_separator()
		var idx := button.item_count
		button.add_item(add_label)
		button.set_item_metadata(idx, add_key)
	if items.is_empty():
		button.disabled = false
		button.text = add_label
	else:
		button.disabled = false
	button.select(-1)


func _select_in_option(button: OptionButton, value: String) -> void:
	if button == null:
		return
	if value.strip_edges() == "":
		button.select(-1)
		return
	for i in range(button.item_count):
		if button.get_item_text(i) == value:
			button.select(i)
			break


func _clear_pending_function_org_flags() -> void:
	_pending_function_region_assign = false
	_pending_function_class_assign = false


func _assign_region_to_selected_function(region_name: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	var methods: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index < 0 or selected_function_index >= methods.size():
		return
	var method = methods[selected_function_index]
	if typeof(method) != TYPE_DICTIONARY:
		return
	var old_cls := _entry_class(method)
	var old_region := _entry_region(method)
	method["region"] = region_name
	methods[selected_function_index] = method
	sync.nodescript.body["functions"] = methods
	sync.save()
	_set_function_region_class_lists()
	_set_function_region_class(method)
	var scope_changed := old_region != region_name or old_cls != _entry_class(method)
	_append_function_order_at_scope_end(method, old_cls, old_region, scope_changed)
	_apply_declarations_to_script()


func _popup_option_at_mouse(picker: OptionButton) -> void:
	if picker == null:
		return
	var popup := picker.get_popup()
	if popup == null:
		return
	popup.reset_size()
	var mouse: Vector2 = get_global_mouse_position()
	var size: Vector2i = popup.size
	if size == Vector2i.ZERO:
		var min_size: Vector2 = popup.get_combined_minimum_size()
		size = Vector2i(int(min_size.x), int(min_size.y))
	popup.popup_on_parent(Rect2i(Vector2i(mouse.round()), size))


func _assign_class_to_selected_function(class_title: String, class_region: String) -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	var methods: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index < 0 or selected_function_index >= methods.size():
		return
	var method = methods[selected_function_index]
	if typeof(method) != TYPE_DICTIONARY:
		return
	var old_cls := _entry_class(method)
	var old_region := _entry_region(method)
	method["class"] = class_title
	if _entry_region(method) == "" and class_region.strip_edges() != "":
		method["region"] = class_region.strip_edges()
	methods[selected_function_index] = method
	sync.nodescript.body["functions"] = methods
	sync.save()
	_set_function_region_class_lists()
	_set_function_region_class(method)
	var scope_changed := old_cls != class_title or old_region != _entry_region(method)
	_append_function_order_at_scope_end(method, old_cls, old_region, scope_changed)
	_apply_declarations_to_script()


func _on_function_update_requested(_method: Dictionary) -> void:
	if sync == null or sync.nodescript == null:
		return
	if selected_function_index < 0:
		return
	var method := _function_entry_by_index(selected_function_index)
	if method.is_empty():
		return
	# Persist name/flags from the method dict passed in (if provided).
	if typeof(_method) == TYPE_DICTIONARY:
		if _method.has("name"):
			method["name"] = str(_method.get("name", method.get("name", "")))
		if _method.has("parameters"):
			method["parameters"] = _method.get("parameters", method.get("parameters", []))
		if _method.has("return_type"):
			method["return_type"] = _method.get("return_type", method.get("return_type", ""))
		if _method.has("flags"):
			var flags := _method.get("flags", {})
			if typeof(flags) == TYPE_DICTIONARY:
				for key in ["static", "virtual", "override", "vararg", "rpc"]:
					if flags.has(key):
						method[key] = flags.get(key, method.get(key, false))
		if _method.has("body"):
			var body := _method.get("body", [])
			if typeof(body) == TYPE_ARRAY:
				method["body"] = body
		var funcs: Array = sync.nodescript.body.get("functions", [])
		if selected_function_index < funcs.size():
			funcs[selected_function_index] = method
			sync.nodescript.body["functions"] = funcs
	var cls := _entry_class(method)
	var region := _entry_region(method)
	_append_function_order_at_scope_end(method, cls, region)
	sync.save()
	_refresh_tree()
	_apply_declarations_to_script()


func _append_function_order_at_scope_end(method: Dictionary, old_cls: String, old_region: String, force_move: bool = false) -> void:
	if sync == null or sync.nodescript == null:
		return
	if typeof(method) != TYPE_DICTIONARY:
		return
	var fname := str(method.get("name", "")).strip_edges()
	if fname == "":
		return
	var new_cls := _entry_class(method)
	var new_region := _entry_region(method)
	var order := _scope_order_for(new_cls, new_region)
	var exists_in_scope := false
	for e in order:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("type", "")) == "function" and str(e.get("name", "")) == fname:
			exists_in_scope = true
			break
	# If scope didn't change and the entry is already present, do nothing unless forced.
	if not force_move and exists_in_scope and old_cls == new_cls and old_region == new_region:
		return
	_move_order_entry("function", fname, old_cls, old_region, new_cls, new_region, {}, 1)


func _get_region_icon_name() -> String:
	if _has_editor_icon("VisualShaderNodeComment"):
		return "VisualShaderNodeComment"
	if _has_editor_icon("Group"):
		return "Group"
	return "Node"


func _enum_values(entry) -> Array:
	return NodeScriptUtils.enum_values(entry)


func _entry_region(entry) -> String:
	return NodeScriptUtils.entry_region(entry)


func _entry_class(entry) -> String:
	return NodeScriptUtils.entry_class(entry)


func _jump_to_script_def(patterns: Array[String]) -> void:
	if patterns.is_empty():
		return
	if active_script == null:
		return
	var source := active_script.source_code
	if source == "":
		return
	var lines := source.split("\n")
	for i in range(lines.size()):
		var stripped := lines[i].strip_edges()
		for pattern in patterns:
			if stripped.begins_with(pattern):
				if editor_plugin and editor_plugin.get_editor_interface():
					_focus_script_editor()
					editor_plugin.get_editor_interface().edit_script(active_script, i + 1, 0)
				return


func _jump_to_line(line_number: int) -> void:
	if line_number <= 0:
		return
	if editor_plugin == null or editor_plugin.get_editor_interface() == null or active_script == null:
		return
	_focus_script_editor()
	editor_plugin.get_editor_interface().edit_script(active_script, line_number, 0)


func _focus_script_editor() -> void:
	if editor_plugin and editor_plugin.get_editor_interface():
		editor_plugin.get_editor_interface().set_main_screen_editor("Script")


func _setup_context_menu() -> void:
	if tree_context_menu:
		return
	tree_context_menu = PopupMenu.new()
	tree_context_menu.name = "TreeContextMenu"
	tree_context_menu.add_item("Insert blank space after", 2)
	tree_context_menu.add_item("Delete blank space", 3)
	tree_context_menu.add_separator()
	tree_context_menu.add_item("Go to script line", 1)
	tree_context_menu.hide_on_checkable_item_selection = true
	tree_context_menu.id_pressed.connect(_on_tree_context_menu_id_pressed)
	add_child(tree_context_menu)


func _setup_add_item_menu() -> void:
	if add_item_menu:
		return
	add_item_menu = PopupMenu.new()
	add_item_menu.name = "AddItemMenu"
	add_item_menu.add_item("Signal", 1)
	add_item_menu.set_item_icon(0, _get_editor_icon("MemberSignal", "EditorIcons"))
	add_item_menu.add_item("Variable", 2)
	add_item_menu.set_item_icon(1, _get_editor_icon("MemberProperty", "EditorIcons"))
	add_item_menu.add_item("Enum", 3)
	add_item_menu.set_item_icon(2, _get_editor_icon("Enumeration", "EditorIcons"))
	add_item_menu.add_item("Function", 4)
	add_item_menu.set_item_icon(3, _get_editor_icon("MemberMethod", "EditorIcons"))
	add_item_menu.add_item("Region", 5)
	add_item_menu.set_item_icon(4, _get_editor_icon("Group", "EditorIcons"))
	add_item_menu.add_item("Class", 6)
	add_item_menu.set_item_icon(5, _get_editor_icon("MiniObject", "EditorIcons"))
	add_item_menu.id_pressed.connect(_on_add_item_menu_id_pressed)
	add_child(add_item_menu)
	if add_item_button and add_item_button.texture_normal == null:
		add_item_button.texture_normal = _get_editor_icon("Add", "EditorIcons")


func _setup_options_menu() -> void:
	if options_menu:
		return
	options_menu = PopupMenu.new()
	options_menu.name = "OptionsMenu"
	options_menu.add_check_item("Grouped (sorted)", 0)
	options_menu.set_item_icon(0, _get_editor_icon("Group", "EditorIcons"))
	options_menu.add_check_item("True structure", 1)
	options_menu.set_item_icon(1, _get_editor_icon("Filesystem", "EditorIcons"))
	options_menu.add_check_item("Flat list", 2)
	options_menu.set_item_icon(2, _get_editor_icon("FileList", "EditorIcons"))
	options_menu.add_separator()
	options_menu.add_check_item("Auto space between types", 3)
	options_menu.set_item_icon(3, _get_editor_icon("AutoLayout", "EditorIcons"))
	options_menu.add_check_item("Consolidate blank lines", 4)
	options_menu.set_item_icon(4, _get_editor_icon("CollapseAll", "EditorIcons"))
	options_menu.hide_on_checkable_item_selection = true
	options_menu.id_pressed.connect(_on_options_menu_id_pressed)
	add_child(options_menu)
	if options_button and options_button.texture_normal == null:
		options_button.texture_normal = _get_editor_icon("GuiTabMenuHl", "EditorIcons")
	_update_options_menu_checks()


func _setup_delete_dialog() -> void:
	if _delete_dialog:
		return
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.name = "DeleteDialog"
	_delete_dialog.dialog_text = ""
	_delete_dialog.get_ok_button().hide()
	var vbox := VBoxContainer.new()
	vbox.name = "ContentBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delete_dialog.add_child(vbox)
	var info := Label.new()
	info.name = "InfoLabel"
	info.text = ""
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	var keep_btn := Button.new()
	keep_btn.name = "KeepChildrenButton"
	keep_btn.text = "Delete container only"
	keep_btn.pressed.connect(_on_delete_container_only_pressed)
	actions.add_child(keep_btn)
	var delete_all := Button.new()
	delete_all.name = "DeleteAllButton"
	delete_all.text = "DELETE ALL (HOLD TO CONFIRM)"
	delete_all.focus_mode = Control.FOCUS_NONE
	delete_all.button_down.connect(_on_delete_all_button_down)
	delete_all.button_up.connect(_on_delete_all_button_up)
	actions.add_child(delete_all)
	_delete_hold_button = delete_all
	_delete_hold_timer = Timer.new()
	_delete_hold_timer.one_shot = true
	_delete_hold_timer.wait_time = 2.0
	_delete_hold_timer.timeout.connect(_on_delete_all_hold_timeout)
	_delete_dialog.add_child(_delete_hold_timer)
	add_child(_delete_dialog)


func _show_delete_dialog(kind: String, name: String) -> void:
	_pending_delete_kind = kind
	_pending_delete_name = name
	if _delete_dialog == null:
		return
	var info: Label = _delete_dialog.get_node("ContentBox/InfoLabel") if _delete_dialog.has_node("ContentBox/InfoLabel") else null
	if info:
		var child_label := "items" if kind == "region" else "members"
		info.text = "Delete %s \"%s\"?\nChoose whether to keep contained %s or remove everything." % [kind, name, child_label]
	if _delete_hold_button:
		_delete_hold_button.text = "DELETE ALL (HOLD TO CONFIRM)"
	_delete_dialog.popup_centered()


func _clear_delete_dialog_state() -> void:
	_pending_delete_kind = ""
	_pending_delete_name = ""
	if _delete_hold_timer:
		_delete_hold_timer.stop()
	if _delete_hold_button:
		_delete_hold_button.text = "DELETE ALL (HOLD TO CONFIRM)"
	if _delete_dialog:
		_delete_dialog.hide()


func _on_delete_container_only_pressed() -> void:
	if _pending_delete_kind == "region":
		_delete_region_only(_pending_delete_name, true)
	elif _pending_delete_kind == "class":
		_delete_class_only(_pending_delete_name, true)
	_clear_delete_dialog_state()


func _on_delete_all_button_down() -> void:
	if _delete_hold_timer:
		_delete_hold_timer.start()
	if _delete_hold_button:
		_delete_hold_button.text = "Holding..."


func _on_delete_all_button_up() -> void:
	if _delete_hold_timer:
		_delete_hold_timer.stop()
	if _delete_hold_button:
		_delete_hold_button.text = "DELETE ALL (HOLD TO CONFIRM)"


func _on_delete_all_hold_timeout() -> void:
	if _pending_delete_kind == "region":
		_delete_region_with_children(_pending_delete_name)
	elif _pending_delete_kind == "class":
		_delete_class_with_children(_pending_delete_name)
	_clear_delete_dialog_state()


func _connect_mode_buttons() -> void:
	if mode_grouped_btn and not mode_grouped_btn.pressed.is_connected(_on_mode_grouped_pressed):
		mode_grouped_btn.pressed.connect(_on_mode_grouped_pressed)
	if mode_true_btn and not mode_true_btn.pressed.is_connected(_on_mode_true_pressed):
		mode_true_btn.pressed.connect(_on_mode_true_pressed)
	if mode_flat_btn and not mode_flat_btn.pressed.is_connected(_on_mode_flat_pressed):
		mode_flat_btn.pressed.connect(_on_mode_flat_pressed)
	if add_item_button and not add_item_button.pressed.is_connected(_on_add_item_pressed):
		add_item_button.pressed.connect(_on_add_item_pressed)
	if options_button and not options_button.pressed.is_connected(_on_options_button_pressed):
		options_button.pressed.connect(_on_options_button_pressed)


func _on_mode_grouped_pressed() -> void:
	_set_tree_mode(0)


func _on_mode_true_pressed() -> void:
	_set_tree_mode(1)


func _on_mode_flat_pressed() -> void:
	_set_tree_mode(2)


func _set_tree_mode(mode: int) -> void:
	tree_display_mode = mode
	NodeScriptConfig.set_tree_display_mode(mode)
	_tree_mode_locked = true
	_apply_mode_buttons()
	_update_drop_mode_flags()
	_set_tree_drag_forwarding()
	_update_drag_notice()
	_refresh_tree()


func _set_auto_space_enabled(enabled: bool) -> void:
	auto_space_enabled = enabled
	NodeScriptConfig.set_auto_space_enabled(enabled)
	if sync:
		sync.set_auto_space_enabled(enabled)
	_update_options_menu_checks()
	_refresh_tree()
	_apply_declarations_to_script()
	if sync:
		sync.save()


func _set_consolidate_blanks(enabled: bool) -> void:
	consolidate_blank_lines = enabled
	NodeScriptConfig.set_consolidate_blank_lines(enabled)
	if sync:
		sync.set_consolidate_blank_lines(enabled)
	_update_options_menu_checks()
	_refresh_tree()
	_apply_declarations_to_script()
	if sync:
		sync.save()


func _format_now() -> void:
	if sync == null:
		return
	# Re-apply spacing/consolidation with current flags, then refresh tree and script.
	sync.set_auto_space_enabled(sync.auto_space_enabled)
	sync.set_consolidate_blank_lines(sync.consolidate_blank_lines)
	_refresh_tree()
	_apply_declarations_to_script()
	sync.save()


func _on_options_button_pressed() -> void:
	if options_menu == null:
		return
	_update_options_menu_checks()
	var pos := options_button.get_screen_position() if options_button else Vector2()
	pos.y += options_button.size.y if options_button else 0.0
	options_menu.position = pos
	options_menu.popup()


func _on_options_menu_id_pressed(id: int) -> void:
	if id in [0, 1, 2]:
		_set_tree_mode(id)
		return

	if id == 3:
		_set_auto_space_enabled(not auto_space_enabled)
		return

	if id == 4:
		_set_consolidate_blanks(not consolidate_blank_lines)
		return


func _apply_mode_buttons() -> void:
	if mode_grouped_btn:
		mode_grouped_btn.button_pressed = tree_display_mode == 0
		if mode_grouped_btn.texture_normal == null:
			mode_grouped_btn.texture_normal = _get_editor_icon("Group", "Node")
		_set_mode_button_visual(mode_grouped_btn, tree_display_mode == 0)
	if mode_true_btn:
		mode_true_btn.button_pressed = tree_display_mode == 1
		if mode_true_btn.texture_normal == null:
			mode_true_btn.texture_normal = _get_editor_icon("Filesystem", "List")
		_set_mode_button_visual(mode_true_btn, tree_display_mode == 1)
	if mode_flat_btn:
		mode_flat_btn.button_pressed = tree_display_mode == 2
		if mode_flat_btn.texture_normal == null:
			mode_flat_btn.texture_normal = _get_editor_icon("FileList", "List")
		_set_mode_button_visual(mode_flat_btn, tree_display_mode == 2)
	_update_options_menu_checks()


func _set_mode_button_visual(btn: TextureButton, selected: bool) -> void:
	if btn == null:
		return
	var selected_modulate := Color(1.7, 1.7, 1.7, 1.0)
	var dim_modulate := Color(0.45, 0.45, 0.45, 0.8)
	btn.self_modulate = selected_modulate if selected else dim_modulate

	var normal_bg := StyleBoxFlat.new()
	normal_bg.bg_color = Color(0.35, 0.75, 1.0, 0.45) if selected else Color(0.5, 0.5, 0.5, 0.08)
	normal_bg.border_color = Color(0.9, 0.95, 1.0, 0.9) if selected else Color(1, 1, 1, 0.2)
	normal_bg.border_width_left = 2 if selected else 1
	normal_bg.border_width_right = 2 if selected else 1
	normal_bg.border_width_top = 2 if selected else 1
	normal_bg.border_width_bottom = 2 if selected else 1
	normal_bg.corner_radius_top_left = 5
	normal_bg.corner_radius_top_right = 5
	normal_bg.corner_radius_bottom_left = 5
	normal_bg.corner_radius_bottom_right = 5
	normal_bg.shadow_color = Color(0.6, 0.8, 1.0, 0.4) if selected else Color(0, 0, 0, 0)
	normal_bg.shadow_size = 4 if selected else 0
	normal_bg.shadow_offset = Vector2(0, 0)

	var hover_bg := StyleBoxFlat.new()
	hover_bg.bg_color = Color(0.35, 0.75, 1.0, 0.35)
	hover_bg.border_color = Color(0.85, 0.9, 1.0, 0.7)
	hover_bg.border_width_left = 2
	hover_bg.border_width_right = 2
	hover_bg.border_width_top = 2
	hover_bg.border_width_bottom = 2
	hover_bg.corner_radius_top_left = 5
	hover_bg.corner_radius_top_right = 5
	hover_bg.corner_radius_bottom_left = 5
	hover_bg.corner_radius_bottom_right = 5

	var pressed_bg := StyleBoxFlat.new()
	pressed_bg.bg_color = Color(0.35, 0.75, 1.0, 0.55)
	pressed_bg.border_color = Color(0.9, 0.95, 1.0, 1.0)
	pressed_bg.border_width_left = 2
	pressed_bg.border_width_right = 2
	pressed_bg.border_width_top = 2
	pressed_bg.border_width_bottom = 2
	pressed_bg.corner_radius_top_left = 5
	pressed_bg.corner_radius_top_right = 5
	pressed_bg.corner_radius_bottom_left = 5
	pressed_bg.corner_radius_bottom_right = 5

	btn.add_theme_stylebox_override("normal", normal_bg)
	btn.add_theme_stylebox_override("hover", hover_bg)
	btn.add_theme_stylebox_override("pressed", pressed_bg)
	btn.add_theme_stylebox_override("focus", pressed_bg)
	btn.add_theme_stylebox_override("hover_pressed", pressed_bg)


func _update_options_menu_checks() -> void:
	if options_menu == null:
		return
	for i in range(options_menu.item_count):
		var id := options_menu.get_item_id(i)
		if options_menu.is_item_separator(i) or not options_menu.is_item_checkable(i):
			continue
		match id:
			0, 1, 2:
				options_menu.set_item_checked(i, id == tree_display_mode)
			3:
				options_menu.set_item_checked(i, auto_space_enabled)
			4:
				options_menu.set_item_checked(i, consolidate_blank_lines)


func _update_drop_mode_flags() -> void:
	if tree == null:
		return
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN if _is_reorder_enabled() else 0
	_update_drag_notice()


func _set_tree_drag_forwarding() -> void:
	if tree == null:
		return
	if _is_reorder_enabled():
		tree.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	else:
		# Disable drag forwarding by supplying empty Callables.
		tree.set_drag_forwarding(Callable(), Callable(), Callable())


func _update_drag_notice() -> void:
	if drag_notice_label:
		drag_notice_label.visible = not _is_reorder_enabled()


func _prune_orphan_order_entries() -> void:
	if sync == null or sync.nodescript == null:
		return
	var order: Dictionary = sync.nodescript.body.get("order", {})
	if order.is_empty():
		return
	var cleaned: Dictionary = {}
	for key in order.keys():
		var entries: Array = order.get(key, [])
		var parts := _split_scope_key(str(key))
		var scope_cls := parts[0]
		var scope_region := parts[1]
		# Drop only explicit artifacts (panel name); keep all scopes otherwise to avoid losing children.
		if scope_cls == "NodeScriptMain" or scope_region == "NodeScriptMain":
			continue
		var new_entries: Array = []
		for e in entries:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var etype := str(e.get("type", ""))
			var ename := str(e.get("name", ""))
			if ename == "NodeScriptMain":
				continue
			# Keep blanks even if nameless to preserve spacing.
			if etype == "blank":
				new_entries.append(e)
				continue
			new_entries.append(e)
		if new_entries.is_empty():
			continue
		cleaned[key] = new_entries
	sync.nodescript.body["order"] = cleaned


func _scope_key(cls: String, region: String) -> String:
	return "%s|%s" % [cls, region]


func _ensure_order_map() -> void:
	if sync == null or sync.nodescript == null:
		return
	if typeof(sync.nodescript.body.get("order", null)) != TYPE_DICTIONARY:
		sync.nodescript.body["order"] = {}


func _scope_order_for(cls: String, region: String) -> Array:
	_ensure_order_map()
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var key := _scope_key(cls, region)
	if not order.has(key):
		order[key] = _generate_default_scope_order(cls, region)
		sync.nodescript.body["order"] = order
	return order.get(key, [])


func _set_scope_order(cls: String, region: String, entries: Array) -> void:
	_ensure_order_map()
	var order: Dictionary = sync.nodescript.body.get("order", {})
	order[_scope_key(cls, region)] = entries
	sync.nodescript.body["order"] = order


func _order_key(kind: String, name: String) -> String:
	return kind + "::" + name


func _generate_default_scope_order(cls: String, region: String) -> Array:
	var items: Array = []

	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var rname := str(entry.get("name", "")).strip_edges()
		if rname == "":
			continue
		var rclass := str(entry.get("class", "")).strip_edges()
		if rclass != cls:
			continue
		if _entry_region(entry) == region:
			items.append({"type": "region", "name": rname})

	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for name in signals_dict.keys():
		var entry = signals_dict.get(name, {})
		if NodeScriptUtils.entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "signal", "name": str(name)})

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if NodeScriptUtils.entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "variable", "name": str(entry.get("name", ""))})

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for name in enums_dict.keys():
		var entry = enums_dict.get(name, {})
		if NodeScriptUtils.enum_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "enum", "name": str(name)})

	# Classes appear only at root or region scopes (never nested in another class).
	if cls == "":
		var classes: Array = sync.nodescript.body.get("classes", [])
		for entry in classes:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if _entry_region(entry) != region:
				continue
			var cname := str(entry.get("name", "")).strip_edges()
			if cname != "":
				items.append({"type": "class", "name": cname})

	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for fn in functions_array:
		if typeof(fn) != TYPE_DICTIONARY:
			continue
		if NodeScriptUtils.entry_class(fn) != cls or _entry_region(fn) != region:
			continue
		var fname := str(fn.get("name", "")).strip_edges()
		if fname != "":
			items.append({"type": "function", "name": fname})

	return items


func _on_tree_context_menu_id_pressed(id: int) -> void:
	# ID 2: Insert blank line after selected item
	if id == 2:
		_on_blank_insert_requested()
		return

	# ID 3: Delete blank space (only works on blank entries)
	if id == 3:
		_on_blank_delete_requested()
		return

	if id != 1:
		return
	if _context_item_data.is_empty():
		return
	var kind := str(_context_item_data.get("type", ""))
	var target_name := str(_context_item_data.get("name", ""))
	match kind:
		"blank":
			# Blanks are non-interactive; just navigate to the position
			var line := int(_context_item_data.get("line", 0))
			if line > 0:
				_jump_to_line(line)
			else:
				_jump_to_script_def([])
		"class":
			_jump_to_script_def(["class %s" % target_name, "class %s:" % target_name])
		"function":
			_jump_to_script_def(["func %s" % target_name, "func %s(" % target_name])
		"variable":
			_jump_to_script_def([
				"var %s" % target_name,
				"const %s" % target_name,
				"@export var %s" % target_name,
				"@onready var %s" % target_name,
				"@onready const %s" % target_name
			])
		"signal":
			_jump_to_script_def(["signal %s" % target_name])
		"enum":
			_jump_to_script_def(["enum %s" % target_name, "enum %s:" % target_name])
		"enum_value":
			var enum_name := str(_context_item_data.get("enum", ""))
			_jump_to_script_def(["enum %s" % enum_name, "enum %s:" % enum_name])
		"script":
			_jump_to_script_def([])
			_focus_script_editor()
			if editor_plugin and editor_plugin.get_editor_interface() and active_script:
				editor_plugin.get_editor_interface().edit_script(active_script, 1, 0)
		_:
			_jump_to_script_def([])

func _on_add_item_pressed() -> void:
	if add_item_menu == null or not is_instance_valid(add_item_menu):
		add_item_menu = null
		_setup_add_item_menu()
	if add_item_button == null or add_item_menu == null:
		return
	if add_item_menu.get_parent() == null:
		add_child(add_item_menu)
	add_item_menu.reset_size()
	var pos := add_item_button.get_screen_position() + Vector2(0, add_item_button.size.y)
	add_item_menu.position = pos
	add_item_menu.popup()


# Insert a blank line at the position of the right-clicked item.
func _on_blank_insert_requested() -> void:
	if sync == null or sync.nodescript == null:
		return
	if _context_item_data.is_empty():
		return

	var cls := str(_context_item_data.get("class", "")).strip_edges()
	var region := str(_context_item_data.get("region", "")).strip_edges()

	# Get current scope order
	var scope_order: Array = sync.emit_scope_order(cls, region)
	if scope_order.is_empty():
		return

	# Find insertion point (after selected item)
	var insert_idx := scope_order.size()
	var item_type := str(_context_item_data.get("type", ""))
	var item_name := str(_context_item_data.get("name", ""))

	if item_type != "" and item_name != "":
		for i in range(scope_order.size()):
			var entry = scope_order[i]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if str(entry.get("type", "")) == item_type and str(entry.get("name", "")) == item_name:
				insert_idx = i + 1
				break

	# Insert blank at the position
	scope_order.insert(insert_idx, {"type": "blank", "name": "", "manual_blank": true})
	sync.set_scope_order(cls, region, scope_order)
	sync.save()
	_refresh_tree()
	_apply_declarations_to_script()


# Delete a blank line at the right-clicked item position.
func _on_blank_delete_requested() -> void:
	if sync == null or sync.nodescript == null:
		return
	if _context_item_data.is_empty():
		return

	var item_type := str(_context_item_data.get("type", ""))
	# Only allow deletion of blanks
	if item_type != "blank":
		return

	var cls := str(_context_item_data.get("class", "")).strip_edges()
	var region := str(_context_item_data.get("region", "")).strip_edges()
	var item_name := str(_context_item_data.get("name", ""))

	# Get current scope order
	var scope_order: Array = sync.emit_scope_order(cls, region)
	if scope_order.is_empty():
		return

	# Find and remove the blank entry
	for i in range(scope_order.size()):
		var entry = scope_order[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) == "blank" and str(entry.get("name", "")) == item_name:
			scope_order.remove_at(i)
			break

	# Update order, save, and refresh
	sync.set_scope_order(cls, region, scope_order)
	sync.save()
	_refresh_tree()
	_apply_declarations_to_script()


func _target_region_for_new_item() -> String:
	if tree_display_mode != 1:
		return ""
	if tree == null:
		return ""
	var item := tree.get_selected()
	if item == null:
		return ""
	var data = item.get_metadata(0)
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	if str(data.get("type", "")) == "region":
		return str(data.get("name", "")).strip_edges()
	return str(data.get("region", "")).strip_edges()


func _on_add_item_menu_id_pressed(id: int) -> void:
	var target_region := _target_region_for_new_item()
	match id:
		1:
			_append_signal(target_region)
		2:
			_append_variable(target_region)
		3:
			_append_enum(target_region)
		4:
			_append_function(target_region)
		5:
			_show_region_editor(true, "")
		6:
			_show_class_editor(true, "")


func _build_tree_flat() -> void:
	var script_item := _create_root_script_item()
	if script_item == null:
		return

	var entries: Array = []

	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for name in signals_dict.keys():
		entries.append({"label": str(name), "type": "signal"})

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		entries.append({
			"label": str(entry.get("name", "<unnamed>")),
			"type": "variable",
			"data": entry
		})

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for enum_name in enums_dict.keys():
		entries.append({"label": str(enum_name), "type": "enum"})

	var methods: Array = sync.nodescript.body.get("functions", [])
	for i in range(methods.size()):
		var method = methods[i]
		if typeof(method) != TYPE_DICTIONARY:
			continue
		var fname := str(method.get("name", "")).strip_edges()
		if fname == "":
			continue
		entries.append({"label": fname, "type": "function", "index": i})

	if _should_sort_tree():
		entries.sort_custom(_sort_flat_entries)

	for entry in entries:
		var label := str(entry.get("label", ""))
		if not _matches_filter(label):
			continue
		var etype := str(entry.get("type", "node"))
		var metadata: Dictionary = entry.duplicate(true)
		var icon_name := "Node"
		match etype:
			"signal":
				icon_name = "Signal"
			"variable":
				icon_name = _variable_type_icon(metadata.get("data", {}))
			"enum":
				icon_name = "Enumeration"
			"function":
				icon_name = "MemberMethod"
			_:
				icon_name = "Node"
		_create_tree_item(script_item, label, metadata, icon_name, "Node")


func _sort_flat_entries(a, b) -> bool:
	return str(a.get("label", "")).nocasecmp_to(str(b.get("label", ""))) < 0


func _build_tree_true() -> void:
	_ensure_order_map()
	var script_item := _create_root_script_item()
	if script_item == null:
		return
	_build_scope_items(script_item, "", "")


func _create_root_script_item() -> TreeItem:
	if tree == null:
		return null
	var root := tree.create_item()
	if root == null:
		return null
	var script_item := tree.create_item(root)
	if script_item == null:
		return null
	script_item.set_text(0, _get_script_display_name())
	script_item.set_icon(0, _get_editor_icon("Script", "File"))
	script_item.set_metadata(0, {"type": "script"})
	script_item.collapsed = false
	return script_item


func _build_scope_items(parent_item: TreeItem, cls: String, region: String) -> void:
	if parent_item == null or sync == null or sync.nodescript == null:
		return
	var order := _scope_order_for(cls, region)
	var added: Dictionary = {}
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", entry.get("id", "")))
		match kind:
			"blank":
				if not _matches_filter(""):
					continue
				var is_auto_blank: bool = bool(entry.get("auto_spacing", false))
				var is_manual_blank: bool = bool(entry.get("manual_blank", true))
				# Show auto blanks only when spacing is enabled; otherwise hide them.
				if is_auto_blank and not (sync and sync.auto_space_enabled):
					continue
				# Treat legacy blanks (no flags) as manual so users still see them.
				var line_num := int(entry.get("line", 0))
				var blank_item := NodeScriptTreeUtils.create_item(tree, parent_item, " ", {"type": "blank", "name": name, "region": region, "class": cls, "line": line_num, "manual_blank": is_manual_blank, "auto_spacing": is_auto_blank}, null)
				# Make blank items appear greyed out
				blank_item.set_custom_color(0, Color(0.6, 0.6, 0.6, 0.5))
				blank_item.set_selectable(0, false) # Blank lines cannot be selected/edited
				added[_order_key(kind, name)] = true
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
				var class_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "class", "name": name, "region": region}, NodeScriptTreeUtils.get_icon(self, "MiniObject", "MiniObject"))
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
			_:
				continue

	# Append any missing items in this scope that are not yet ordered
	_append_unordered_scope_items(parent_item, cls, region, added)


func _append_unordered_scope_items(parent_item: TreeItem, cls: String, region: String, added: Dictionary) -> void:
	var order := _scope_order_for(cls, region)
	var order_entries := {}
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) == "blank":
			continue
		order_entries[_order_key(str(entry.get("type", "")), str(entry.get("name", "")))] = true

	# Classes (only when cls is root)
	if cls == "":
		var classes: Array = sync.nodescript.body.get("classes", [])
		for entry in classes:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if _entry_region(entry) != region:
				continue
			var name := str(entry.get("name", "")).strip_edges()
			var key := _order_key("class", name)
			if name != "" and not order_entries.has(key):
				order.append({"type": "class", "name": name})
				order_entries[key] = true
			if name != "" and not added.has(key) and _matches_filter(name):
				var class_item := NodeScriptTreeUtils.create_item(tree, parent_item, name, {"type": "class", "name": name, "region": region}, NodeScriptTreeUtils.get_icon(self, "MiniObject", "MiniObject"))
				class_item.collapsed = false
				added[key] = true
				_build_scope_items(class_item, name, region)

	# Regions owned by this class scope
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var rname := str(entry.get("name", "")).strip_edges()
		if rname == "":
			continue
		var rclass := str(entry.get("class", "")).strip_edges()
		if rclass != cls:
			continue
		if _entry_region(entry) != region:
			continue
		var key := _order_key("region", rname)
		if not order_entries.has(key):
			order.append({"type": "region", "name": rname})
			order_entries[key] = true
			var region_item := NodeScriptTreeUtils.create_item(tree, parent_item, rname, {"type": "region", "name": rname, "class": cls, "region": region}, _get_editor_icon(_get_region_icon_name(), "Folder"))
			_build_scope_items(region_item, cls, rname)

	# Signals
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for name in signals_dict.keys():
		var entry = signals_dict.get(name, {})
		if NodeScriptUtils.entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		var key := _order_key("signal", str(name))
		if order_entries.has(key):
			continue
		order.append({"type": "signal", "name": str(name)})
		order_entries[key] = true
		if _matches_filter(str(name)):
			NodeScriptTreeUtils.create_item(tree, parent_item, str(name), {"type": "signal", "name": str(name), "region": region, "class": cls}, _get_editor_icon("Signal", "Signal"))

	# Variables
	var vars: Array = sync.nodescript.body.get("variables", [])
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if NodeScriptUtils.entry_class(v) != cls or _entry_region(v) != region:
			continue
		var vname := str(v.get("name", "")).strip_edges()
		var key := _order_key("variable", vname)
		if order_entries.has(key):
			continue
		order.append({"type": "variable", "name": vname})
		order_entries[key] = true
		if _matches_filter(vname):
			var icon_name := _variable_type_icon(v)
			NodeScriptTreeUtils.create_item(tree, parent_item, vname, {"type": "variable", "name": vname, "region": region, "class": cls}, _get_editor_icon(icon_name, "MemberProperty"))

	# Enums
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for en_name in enums_dict.keys():
		var en = enums_dict.get(en_name, {})
		if NodeScriptUtils.enum_class(en) != cls or _entry_region(en) != region:
			continue
		var key := _order_key("enum", str(en_name))
		if order_entries.has(key):
			continue
		order.append({"type": "enum", "name": str(en_name)})
		order_entries[key] = true
		if _matches_filter(str(en_name)):
			var enum_item := NodeScriptTreeUtils.create_item(tree, parent_item, str(en_name), {"type": "enum", "name": str(en_name), "region": region, "class": cls}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))
			if show_enum_values_in_tree:
				var values: Array = _enum_values(en)
				if typeof(values) == TYPE_ARRAY and not values.is_empty():
					for value_name in values:
						if not _matches_filter(str(value_name)):
							continue
						NodeScriptTreeUtils.create_item(tree, enum_item, str(value_name), {"type": "enum_value", "name": value_name, "enum": str(en_name)}, _get_editor_icon(_get_enum_icon_name(), _get_enum_icon_name()))

	# Functions
	var funcs: Array = sync.nodescript.body.get("functions", [])
	for fn in funcs:
		if typeof(fn) != TYPE_DICTIONARY:
			continue
		if NodeScriptUtils.entry_class(fn) != cls or _entry_region(fn) != region:
			continue
		var fname := str(fn.get("name", "")).strip_edges()
		if fname == "":
			continue
		var key := _order_key("function", fname)
		if order_entries.has(key):
			continue
		order.append({"type": "function", "name": fname})
		order_entries[key] = true
		if _matches_filter(fname):
			var fidx := _function_index_by_name(fname)
			var func_item := NodeScriptTreeUtils.create_item(tree, parent_item, fname, {"type": "function", "name": fname, "index": fidx, "region": region, "class": cls}, _get_editor_icon("MemberMethod", "MemberMethod"))
			func_item.collapsed = true

	_set_scope_order(cls, region, order)


func _region_names_for_tree(class_title: String = "") -> Array[String]:
	if sync == null or sync.nodescript == null:
		return []
	var names: Array[String] = []
	var raw = sync.nodescript.body.get("regions", [])
	if typeof(raw) == TYPE_ARRAY:
		for r in raw:
			var candidate := ""
			if typeof(r) == TYPE_DICTIONARY:
				candidate = str(r.get("name", ""))
			else:
				candidate = str(r)
			candidate = candidate.strip_edges()
			if candidate != "" and not names.has(candidate):
				names.append(candidate)

	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	for value in signals_dict.values():
		var region_name := _entry_region(value)
		if class_title != "" and _entry_class(value) != class_title:
			continue
		if class_title == "" and _entry_class(value) != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var region_name := _entry_region(enums_dict.get(key, {}))
		var cls := _entry_class(enums_dict.get(key, {}))
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_name := _entry_region(entry)
		var cls := _entry_class(entry)
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var functions_array: Array = sync.nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_name := _entry_region(entry)
		var cls := NodeScriptUtils.entry_class(entry)
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var classes_array: Array = sync.nodescript.body.get("classes", [])
	for entry in classes_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_name := _entry_region(entry)
		if region_name == "":
			continue
		var cls_name := str(entry.get("name", "")).strip_edges()
		if cls_name == "":
			continue
		if class_title != "" and cls_name != class_title:
			continue
		if class_title == "" and cls_name != "":
			if region_name != "" and not names.has(region_name):
				names.append(region_name)

	return names


func _region_parent_item(region_nodes: Dictionary, region_name: String, fallback: TreeItem) -> TreeItem:
	var key := region_name.strip_edges()
	if key == "":
		return fallback
	if not region_nodes.has(key):
		var parent_meta := _metadata_for_item(fallback)
		var parent_region := str(parent_meta.get("region", ""))
		var parent_class := str(parent_meta.get("class", ""))
		var region_item = _create_tree_item(fallback, key, {"type": "region", "name": key, "class": parent_class, "region": parent_region}, _get_region_icon_name(), _get_region_icon_name())
		region_item.collapsed = false
		region_nodes[key] = region_item
	return region_nodes[key]


func _class_parent_item(class_nodes: Dictionary, class_title: String, fallback: TreeItem) -> TreeItem:
	var key := class_title.strip_edges()
	if key == "":
		return fallback
	if not class_nodes.has(key):
		var class_item = _create_tree_item(fallback, key, {"type": "class", "name": key}, "MiniObject", "MiniObject")
		class_item.collapsed = false
		class_nodes[key] = class_item
	return class_nodes[key]


func _ensure_region_nodes_for_parent(parent: TreeItem, region_nodes: Dictionary, region_names: Array[String]) -> Dictionary:
	var nodes := region_nodes
	for region_name in region_names:
		_region_parent_item(nodes, region_name, parent)
	return nodes


func _parent_for_entry(class_nodes: Dictionary, class_region_nodes: Dictionary, region_nodes: Dictionary, class_title: String, region_name: String, fallback: TreeItem) -> TreeItem:
	return NodeScriptTreeUtils.parent_for_entry(tree, class_nodes, class_region_nodes, region_nodes, class_title, region_name, fallback, self)


func _append_signal(region: String = "") -> void:
	if sync == null or sync.nodescript == null:
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	var desired := "NewSignal"
	var name := _ensure_unique_name(desired, Array(signals_dict.keys()), "Signal")
	signals_dict[name] = {"parameters": [], "region": region, "class": ""}
	sync.nodescript.body["signals"] = signals_dict
	sync.save()
	_refresh_tree()
	_select_tree_item("signal", name)


func _append_variable(region: String = "") -> void:
	if sync == null or sync.nodescript == null:
		return
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	var desired := "new_variable"
	var existing: Array = []
	for v in variables_array:
		if typeof(v) == TYPE_DICTIONARY:
			existing.append(str(v.get("name", "")))
	var name := _ensure_unique_name(desired, existing, "var")
	variables_array.append({
		"name": name,
		"type": "Variant",
		"value": "",
		"export": false,
		"const": false,
		"onready": false,
		"region": region,
		"class": ""
	})
	sync.nodescript.body["variables"] = variables_array
	sync.save()
	_refresh_tree()
	_select_tree_item("variable", name)


func _append_enum(region: String = "") -> void:
	if sync == null or sync.nodescript == null:
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	var desired := "NewEnum"
	var names: Array = enums_dict.keys()
	var name := _ensure_unique_name(desired, names, "Enum")
	enums_dict[name] = {"values": [], "region": region, "class": ""}
	sync.nodescript.body["enums"] = enums_dict
	sync.save()
	_refresh_tree()
	_select_tree_item("enum", name)


func _append_function(region: String = "") -> void:
	if sync == null or sync.nodescript == null:
		return
	var methods: Array = sync.nodescript.body.get("functions", [])
	var desired := "new_function"
	var existing: Array = []
	for m in methods:
		if typeof(m) == TYPE_DICTIONARY:
			existing.append(str(m.get("name", "")))
	var name := _ensure_unique_name(desired, existing, "func")
	var method := {
		"name": name,
		"parameters": [],
		"return_type": "void",
		"region": region,
		"body": [ {
			"type": "pass",
			"text": "pass"
		}]
	}
	methods.append(method)
	sync.nodescript.body["functions"] = methods
	sync.save()
	_refresh_tree()
	_select_tree_item("function", methods.size() - 1)


func _append_function_deferred() -> void:
	_append_function()


func _append_region() -> void:
	if sync == null or sync.nodescript == null:
		return
	var desired := "Region"
	var existing: Array[String] = []
	var regions: Array = sync.nodescript.body.get("regions", [])
	for r in regions:
		if typeof(r) == TYPE_DICTIONARY:
			existing.append(str(r.get("name", "")))
	var name := _ensure_unique_name(desired, existing, "Region")
	if typeof(regions) != TYPE_ARRAY:
		regions = []
	regions.append({
		"name": name,
		"class": "",
		"region": ""
	})
	sync.nodescript.body["regions"] = regions
	sync.save()
	_refresh_tree()


func _append_class() -> void:
	if sync == null or sync.nodescript == null:
		return
	var classes: Array = sync.nodescript.body.get("classes", [])
	var desired := "NewClass"
	var existing: Array[String] = []
	for c in classes:
		if typeof(c) == TYPE_DICTIONARY:
			existing.append(str(c.get("name", "")))
	var name := _ensure_unique_name(desired, existing, "Class")
	classes.append({
		"name": name,
		"extends": ""
	})
	sync.nodescript.body["classes"] = classes
	sync.save()
	_refresh_tree()
	_select_tree_item("class", name)


func _log(message: String, level: int = 1) -> void:
	if NodeScriptConfig.get_log_level() >= level:
		print("[NodeScriptPanel] " + message)


func _clear_region_state() -> void:
	creating_region = false
	editing_region = false
	current_region_name = ""


func _clear_class_state() -> void:
	creating_class = false
	editing_class = false
	current_class_name = ""


func _reload_config_flags() -> void:
	show_enum_values_in_tree = NodeScriptConfig.get_bool("show_enum_values_in_tree", false)
	auto_sort_tree_flag = NodeScriptConfig.get_bool("auto_sort_tree", false)
	auto_space_enabled = NodeScriptConfig.get_auto_space_enabled()
	consolidate_blank_lines = NodeScriptConfig.get_consolidate_blank_lines()
	if not _tree_mode_locked:
		tree_display_mode = NodeScriptConfig.get_int("tree_display_mode", 1)
	if sync:
		sync.auto_space_enabled = auto_space_enabled
		sync.consolidate_blank_lines = consolidate_blank_lines
	_log("Config reloaded: show_enum_values_in_tree=%s, auto_sort_tree=%s, auto_space_enabled=%s, consolidate_blank_lines=%s" % [show_enum_values_in_tree, auto_sort_tree_flag, auto_space_enabled, consolidate_blank_lines], 2)
	_apply_mode_buttons()


func _connect_signal_if_present(target: Object, signal_name: String, callable: Callable) -> void:
	if target == null or not target.has_signal(signal_name):
		return
	if not target.is_connected(signal_name, callable):
		target.connect(signal_name, callable)


func _on_tree_filter_changed(new_text: String) -> void:
	tree_filter_text = new_text.strip_edges().to_lower()
	_refresh_tree()


func _get_declaration_source() -> String:
	if sync and sync.has_method("generate_declaration_source"):
		return sync.generate_declaration_source()
	return _generate_declaration_fallback()


func _generate_declaration_fallback() -> String:
	if sync == null or sync.nodescript == null:
		return ""
	var lines: Array[String] = []
	var meta: Dictionary = sync.nodescript.meta if typeof(sync.nodescript.meta) == TYPE_DICTIONARY else {}

	if meta.get("tool", false):
		lines.append("@tool")

	var extends_value: String = str(meta.get("extends", "")).strip_edges()
	if extends_value != "":
		lines.append("extends " + extends_value)

	var class_name_value: String = str(meta.get("class_name", "")).strip_edges()
	if class_name_value != "":
		lines.append("class_name " + class_name_value)

	if not lines.is_empty():
		lines.append("")

	_append_fallback_signals(lines)
	_append_fallback_enums(lines)
	_append_fallback_variables(lines)

	var text := "\n".join(_clean_declaration_lines(lines))
	if text != "" and not text.ends_with("\n"):
		text += "\n"
	return text


func _append_fallback_signals(lines: Array[String]) -> void:
	if sync == null or sync.nodescript == null:
		return
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	if signals_dict.is_empty():
		return
	var names: Array = Array(signals_dict.keys())
	names.sort()
	for name in names:
		var entry = signals_dict.get(name, {})
		var params: Array = []
		if typeof(entry) == TYPE_DICTIONARY:
			params = entry.get("parameters", [])
		elif typeof(entry) == TYPE_ARRAY:
			params = entry
		var declaration = "signal " + str(name)
		var param_text := _format_fallback_signal_parameters(params)
		if param_text != "":
			declaration += "(" + param_text + ")"
		lines.append(declaration)
	lines.append("")


func _format_fallback_signal_parameters(params: Array) -> String:
	var pieces: Array[String] = []
	for param in params:
		if typeof(param) != TYPE_DICTIONARY:
			continue
		var name = str(param.get("name", "")).strip_edges()
		if name == "":
			continue
		var type_hint = str(param.get("type", "")).strip_edges()
		var piece = name
		if type_hint != "":
			piece += ": " + type_hint
		pieces.append(piece)
	return ", ".join(pieces)


func _append_fallback_enums(lines: Array[String]) -> void:
	if sync == null or sync.nodescript == null:
		return
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	if enums_dict.is_empty():
		return
	var names: Array = Array(enums_dict.keys())
	names.sort()
	for enum_name in names:
		var values: Array = _enum_values(enums_dict.get(enum_name, []))
		var body := "{}" if values.is_empty() else "{ " + ", ".join(values) + " }"
		if str(enum_name).strip_edges() == "":
			lines.append("enum " + body)
		else:
			lines.append("enum %s %s" % [enum_name, body])
	lines.append("")


func _append_fallback_variables(lines: Array[String]) -> void:
	if sync == null or sync.nodescript == null:
		return
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	if variables_array.is_empty():
		return
	var groups := {
		"const": [],
		"export": [],
		"onready": [],
		"var": []
	}
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var group := _variable_group(entry)
		if not groups.has(group):
			group = "var"
		groups[group].append(entry)

	var wrote_any := false
	for group_name in ["const", "export", "onready", "var"]:
		var group_entries: Array = groups.get(group_name, [])
		if group_entries.is_empty():
			continue
		if wrote_any:
			lines.append("")
		for entry in group_entries:
			var annotations := _format_fallback_variable_annotations(entry)
			var var_line := _format_fallback_variable_line(entry)
			if annotations.is_empty():
				lines.append(var_line)
			else:
				lines.append(" ".join(annotations + [var_line]))
		wrote_any = true
	lines.append("") # Ensure a blank line after the variable block.


func _format_fallback_variable_annotations(entry: Dictionary) -> Array[String]:
	var annotations: Array[String] = []
	if entry.get("export", false):
		annotations.append("@export")
	var group_text: String = str(entry.get("export_group", "")).strip_edges()
	if group_text != "":
		annotations.append("@export_group(\"%s\")" % group_text)
	if entry.get("onready", false) and not entry.get("const", false):
		annotations.append("@onready")
	return annotations


func _clean_declaration_lines(lines: Array[String]) -> Array[String]:
	var cleaned: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed == "":
			cleaned.append(line)
			continue
		if trimmed.begins_with("@") \
		or trimmed.begins_with("extends ") \
		or trimmed.begins_with("class_name ") \
		or trimmed.begins_with("signal ") \
		or trimmed.begins_with("enum ") \
		or trimmed.begins_with("var ") \
		or trimmed.begins_with("const "):
			cleaned.append(line)
	return cleaned


func _format_fallback_variable_line(entry: Dictionary) -> String:
	var is_const: bool = entry.get("const", false)
	var base := "const " if is_const else "var "
	var name: String = str(entry.get("name", "variable"))
	var line := base + name
	var type_hint: String = str(entry.get("type", "")).strip_edges()
	if type_hint != "":
		line += ": " + type_hint
	var default_value: String = str(entry.get("value", "")).strip_edges()
	if default_value != "":
		line += " = " + default_value
	elif is_const:
		line += " = null"
	return line


func _variable_group(entry: Dictionary) -> String:
	if entry.get("const", false):
		return "const"
	if entry.get("export", false):
		return "export"
	if entry.get("onready", false):
		return "onready"
	return "var"


func _print_tree_recursive(node: Node, indent: int) -> void:
	var prefix = ""
	for i in range(indent):
		prefix += "  "
	print(prefix, node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		_print_tree_recursive(child, indent + 1)
