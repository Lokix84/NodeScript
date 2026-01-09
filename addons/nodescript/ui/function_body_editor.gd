@tool
extends ScrollContainer

signal update_requested(method: Dictionary)
signal delete_requested
signal create_region_requested
signal create_class_requested

const CommentBlockScene: PackedScene = preload("res://addons/nodescript/ui/blocks/comment_block.tscn")
const StatementClassifier = preload("res://addons/nodescript/utils/statement_classifier.gd")
const EditorUIHelper = preload("res://addons/nodescript/utils/editor_ui_helper.gd")
const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")

var blocks_container: VBoxContainer
var empty_label: Label
var selection_label: Label
var statement_tree: Tree
var inspector_container: VBoxContainer
var function_form: VBoxContainer
var comment_form: VBoxContainer
var call_form: VBoxContainer
var signal_form: VBoxContainer
var assignment_form: VBoxContainer
var fallback_label: Label
var return_form: VBoxContainer
var if_form: VBoxContainer
var elif_form: VBoxContainer
var else_form: VBoxContainer
var match_form: VBoxContainer
var for_form: VBoxContainer
var while_form: VBoxContainer
var func_name_edit: LineEdit
var func_params_edit: LineEdit
var func_return_edit: LineEdit
var func_static: CheckBox
var func_virtual: CheckBox
var func_override: CheckBox
var func_vararg: CheckBox
var func_rpc: CheckBox
var params_container: VBoxContainer
var add_param_button: Button
var comment_text: TextEdit
var call_name_edit: LineEdit
var call_args: TextEdit
var signal_name_edit: LineEdit
var signal_args: TextEdit
var assign_target_edit: LineEdit
var assign_expr: TextEdit
var return_expr: LineEdit
var if_condition: LineEdit
var elif_condition: LineEdit
var match_subject: LineEdit
var for_var_edit: LineEdit
var for_iterable_edit: LineEdit
var while_condition: LineEdit
var add_comment_button: Button
var add_assign_button: Button
var add_call_button: Button
var add_signal_button: Button
var add_return_button: Button
var add_match_button: Button
var add_if_button: Button
var add_elif_button: Button
var add_else_button: Button
var add_for_button: Button
var add_while_button: Button
var add_pass_button: Button
var header_icon: TextureRect
var header_label: Label
var code_output_icon: TextureRect
var code_output_value: Label
var delete_button: Button
var update_button: Button
var indent_button: Button
var dedent_button: Button
var org_selector
var current_method: Dictionary = {}
var current_statement: Dictionary = {}
var pending_method: Dictionary = {}
var parameters: Array = []
var assigned_region: String = ""
var assigned_class: String = ""
var current_body: Array = []
var pending_new_index: int = -1
var current_statement_index: int = -1
var current_statement_type: String = ""
var _signature_item: TreeItem = null
var _building_tree: bool = false


func _ready() -> void:
	_refresh_node_refs()
	_update_empty_state()
	if statement_tree:
		statement_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
		if not statement_tree.item_selected.is_connected(_on_tree_item_selected):
			statement_tree.item_selected.connect(_on_tree_item_selected)


func set_method(method) -> void:
	current_method = method if typeof(method) == TYPE_DICTIONARY else {}
	pending_method = current_method.duplicate(true)
	current_body = _sanitize_body_array(current_method.get("body", []))
	pending_new_index = -1
	_apply_method_to_form(current_method)
	_build_statement_tree()
	_show_form(true)
	_show_only_form("function")
	_update_code_preview()
	_update_header()


func clear_method() -> void:
	current_method = {}
	pending_method = {}
	current_statement = {}
	parameters = []
	assigned_region = ""
	assigned_class = ""
	current_body = []
	pending_new_index = -1
	current_statement_index = -1
	current_statement_type = ""
	_reset_ui()


func _refresh_node_refs() -> void:
	blocks_container = find_child("BlocksContainer", true, false)
	empty_label = find_child("FallbackLabel", true, false)
	selection_label = find_child("SelectionLabel", true, false)
	statement_tree = find_child("StatementTree", true, false)
	inspector_container = find_child("InspectorContainer", true, false)
	function_form = find_child("FunctionForm", true, false)
	comment_form = find_child("CommentForm", true, false)
	call_form = find_child("CallForm", true, false)
	signal_form = find_child("SignalForm", true, false)
	assignment_form = find_child("AssignmentForm", true, false)
	fallback_label = find_child("FallbackLabel", true, false)
	return_form = find_child("ReturnForm", true, false)
	if_form = find_child("IfForm", true, false)
	elif_form = find_child("ElifForm", true, false)
	else_form = find_child("ElseForm", true, false)
	match_form = find_child("MatchForm", true, false)
	for_form = find_child("ForForm", true, false)
	while_form = find_child("WhileForm", true, false)

	func_name_edit = find_child("FuncNameEdit", true, false)
	func_params_edit = find_child("FuncParamsEdit", true, false)
	func_return_edit = find_child("FuncReturnEdit", true, false)
	func_static = find_child("FuncStatic", true, false)
	func_virtual = find_child("FuncVirtual", true, false)
	func_override = find_child("FuncOverride", true, false)
	func_vararg = find_child("FuncVararg", true, false)
	func_rpc = find_child("FuncRpc", true, false)
	params_container = find_child("ParamsContainer", true, false)
	add_param_button = find_child("AddParamButton", true, false)
	comment_text = find_child("CommentText", true, false)
	call_name_edit = find_child("CallNameEdit", true, false)
	call_args = find_child("CallArgs", true, false)
	signal_name_edit = find_child("SignalNameEdit", true, false)
	signal_args = find_child("SignalArgs", true, false)
	assign_target_edit = find_child("AssignTargetEdit", true, false)
	assign_expr = find_child("AssignExpr", true, false)
	return_expr = find_child("ReturnExpr", true, false)
	if_condition = find_child("IfCondition", true, false)
	elif_condition = find_child("ElifCondition", true, false)
	match_subject = find_child("MatchSubject", true, false)
	for_var_edit = find_child("ForVarEdit", true, false)
	for_iterable_edit = find_child("ForIterableEdit", true, false)
	while_condition = find_child("WhileCondition", true, false)

	add_comment_button = find_child("AddCommentButton", true, false)
	add_assign_button = find_child("AddAssignButton", true, false)
	add_call_button = find_child("AddCallButton", true, false)
	add_signal_button = find_child("AddSignalButton", true, false)
	add_return_button = find_child("AddReturnButton", true, false)
	add_match_button = find_child("AddMatchButton", true, false)
	add_if_button = find_child("AddIfButton", true, false)
	add_elif_button = find_child("AddElifButton", true, false)
	add_else_button = find_child("AddElseButton", true, false)
	add_for_button = find_child("AddForButton", true, false)
	add_while_button = find_child("AddWhileButton", true, false)
	add_pass_button = find_child("AddPassButton", true, false)
	header_icon = find_child("HeaderIcon", true, false)
	header_label = find_child("HeaderLabel", true, false)
	code_output_icon = find_child("CodeOutputIcon", true, false)
	code_output_value = find_child("CodeOutputValue", true, false)
	delete_button = find_child("DeleteButton", true, false)
	update_button = find_child("UpdateButton", true, false)
	indent_button = find_child("IndentButton", true, false)
	dedent_button = find_child("DedentButton", true, false)
	org_selector = find_child("OrgSelector", true, false)

	_connect_button(update_button, _on_update_pressed)
	_connect_button(delete_button, _on_delete_pressed)
	_connect_button(indent_button, _on_indent_pressed)
	_connect_button(dedent_button, _on_dedent_pressed)
	_connect_button(add_param_button, _on_add_param_pressed)
	_connect_button(add_comment_button, func(): _add_statement("comment"))
	_connect_button(add_assign_button, func(): _add_statement("assignment"))
	_connect_button(add_call_button, func(): _add_statement("call"))
	_connect_button(add_signal_button, func(): _add_statement("signal_emit"))
	_connect_button(add_return_button, func(): _add_statement("return"))
	_connect_button(add_match_button, func(): _add_statement("match"))
	_connect_button(add_if_button, func(): _add_statement("if"))
	_connect_button(add_elif_button, func(): _add_statement("elif"))
	_connect_button(add_else_button, func(): _add_statement("else"))
	_connect_button(add_for_button, func(): _add_statement("for"))
	_connect_button(add_while_button, func(): _add_statement("while"))
	_connect_button(add_pass_button, func(): _add_statement("pass"))
	_set_add_button_icons_and_hints()
	_connect_text(func_name_edit, _on_live_field_changed)
	_connect_text(func_params_edit, _on_live_field_changed)
	_connect_text(func_return_edit, _on_live_field_changed)
	_connect_flag(func_static)
	_connect_flag(func_virtual)
	_connect_flag(func_override)
	_connect_flag(func_vararg)
	_connect_flag(func_rpc)
	if org_selector:
		if org_selector.has_signal("region_changed") and not org_selector.region_changed.is_connected(_on_org_region_changed):
			org_selector.region_changed.connect(_on_org_region_changed)
		if org_selector.has_signal("class_changed") and not org_selector.class_changed.is_connected(_on_org_class_changed):
			org_selector.class_changed.connect(_on_org_class_changed)
		if org_selector.has_signal("assign_region_requested") and not org_selector.assign_region_requested.is_connected(_on_org_assign_region_requested):
			org_selector.assign_region_requested.connect(_on_org_assign_region_requested)
		if org_selector.has_signal("assign_class_requested") and not org_selector.assign_class_requested.is_connected(_on_org_assign_class_requested):
			org_selector.assign_class_requested.connect(_on_org_assign_class_requested)
		if org_selector.has_signal("cleared_region") and not org_selector.cleared_region.is_connected(_on_org_cleared_region):
			org_selector.cleared_region.connect(_on_org_cleared_region)
		if org_selector.has_signal("cleared_class") and not org_selector.cleared_class.is_connected(_on_org_cleared_class):
			org_selector.cleared_class.connect(_on_org_cleared_class)
	_set_icons()
	_set_action_icons()


func _connect_button(btn: Button, callable: Callable) -> void:
	if btn and not btn.pressed.is_connected(callable):
		btn.pressed.connect(callable)


func _connect_text(edit: LineEdit, callable: Callable) -> void:
	if edit and not edit.text_changed.is_connected(callable):
		edit.text_changed.connect(callable)


func _connect_flag(flag: CheckBox) -> void:
	if flag and not flag.toggled.is_connected(_on_live_flag_changed):
		flag.toggled.connect(_on_live_flag_changed)


func _set_add_button_icons_and_hints() -> void:
	var icon_map: Dictionary = {
		"AddCommentButton": "VisualShaderNodeComment",
		"AddAssignButton": "Property",
		"AddCallButton": "Callable",
		"AddSignalButton": "MemberSignal",
		"AddReturnButton": "Return",
		"AddMatchButton": "MatchCase",
		"AddIfButton": "Conditional",
		"AddElifButton": "Conditional",
		"AddElseButton": "Conditional",
		"AddForButton": "Loop",
		"AddWhileButton": "Loop",
		"AddPassButton": "Check"
	}
	for name in icon_map.keys():
		var node: Button = find_child(name, true, false)
		if node:
			var icon_name: String = str(icon_map[name])
			var icon := IconHelper.get_editor_icon(self, icon_name, icon_name)
			if icon:
				node.icon = icon
			match name:
				"AddCommentButton":
					node.text = ""
				"AddAssignButton":
					node.text = "[b]=[/b]"
				"AddCallButton":
					node.text = ""
				"AddSignalButton":
					node.text = ""
				_:
					pass
			var label := node.text.strip_edges()
			if label == "":
				label = node.name.replace("Add", "").replace("Button", "")
			node.tooltip_text = "Add " + label + " statement"

func _apply_method_to_form(method: Dictionary) -> void:
	if func_name_edit:
		func_name_edit.text = str(method.get("name", ""))
	parameters = _sanitize_params_array(method.get("parameters", []))
	_refresh_params_ui()
	if func_return_edit:
		var ret := str(method.get("return_type", "")).strip_edges()
		func_return_edit.text = ret if ret != "" else "void"
	if func_static:
		func_static.button_pressed = method.get("static", false)
	if func_virtual:
		func_virtual.button_pressed = method.get("virtual", false)
	if func_override:
		func_override.button_pressed = method.get("override", false)
	if func_vararg:
		func_vararg.button_pressed = method.get("vararg", false)
	if func_rpc:
		func_rpc.button_pressed = method.get("rpc", false)


func _reset_ui() -> void:
	if func_name_edit:
		func_name_edit.text = ""
	if func_params_edit:
		func_params_edit.text = ""
	if func_return_edit:
		func_return_edit.text = "void"
	for flag in [func_static, func_virtual, func_override, func_vararg, func_rpc]:
		if flag:
			flag.button_pressed = false
	parameters.clear()
	_refresh_params_ui()
	_show_form(false)
	_update_code_preview()
	_update_header()


func _show_form(has_method: bool) -> void:
	if inspector_container:
		inspector_container.visible = has_method
	if function_form:
		function_form.visible = has_method
	if fallback_label:
		fallback_label.visible = not has_method


func _on_update_pressed() -> void:
	_apply_current_statement_from_form()
	var name := func_name_edit.text.strip_edges() if func_name_edit else ""
	if name == "":
		push_warning("Function name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(name):
		push_warning("Function name cannot be a GDScript keyword.")
		return
	var params := _gather_parameters()
	if params.has("error") and params["error"] != "":
		push_warning(str(params["error"]))
		return
	var param_list: Array = params.get("params", [])

	var return_type := func_return_edit.text.strip_edges() if func_return_edit else ""
	if return_type == "":
		return_type = "void"
	var flags := {
		"static": func_static.button_pressed if func_static else false,
		"virtual": func_virtual.button_pressed if func_virtual else false,
		"override": func_override.button_pressed if func_override else false,
		"vararg": func_vararg.button_pressed if func_vararg else false,
		"rpc": func_rpc.button_pressed if func_rpc else false
	}

	pending_method = current_method.duplicate(true)
	pending_method["name"] = name
	pending_method["parameters"] = param_list
	pending_method["return_type"] = return_type
	for key in flags.keys():
		pending_method[key] = flags[key]
	pending_method["region"] = assigned_region
	pending_method["class"] = assigned_class
	pending_method["body"] = current_body

	emit_signal("update_requested", {
		"name": name,
		"parameters": param_list,
		"return_type": return_type,
		"flags": flags,
		"region": assigned_region,
		"class": assigned_class,
		"body": current_body
	})
	pending_new_index = -1
	current_statement_index = -1
	current_statement_type = ""
	_update_code_preview()
	_update_header()


func _format_params_text(parameters: Array) -> String:
	var pieces: Array[String] = []
	for param in parameters:
		if typeof(param) != TYPE_DICTIONARY:
			continue
		var name: String = str(param.get("name", "")).strip_edges()
		if name == "":
			continue
		var part := name
		var type_hint: String = str(param.get("type", "")).strip_edges()
		if type_hint != "":
			part += ": " + type_hint
		var default_value: String = str(param.get("default", "")).strip_edges()
		if default_value != "":
			part += " = " + default_value
		pieces.append(part)
	return ", ".join(pieces)


func _update_code_preview() -> void:
	if code_output_value == null:
		return
	var name := func_name_edit.text.strip_edges() if func_name_edit else ""
	if name == "":
		name = "function"
	var header := "func %s(" % name
	var params_text := _format_params_text(parameters)
	header += params_text + ")"
	var ret := func_return_edit.text.strip_edges() if func_return_edit else ""
	if ret != "":
		header += " -> " + ret
	code_output_value.text = header


func _on_live_field_changed(_t: String) -> void:
	_update_code_preview()
	_update_header()


func _on_live_flag_changed(_toggled: bool) -> void:
	_update_code_preview()


func _on_delete_pressed() -> void:
	emit_signal("delete_requested")


func _on_indent_pressed() -> void:
	if current_statement_index < 0 or current_statement_index >= current_body.size():
		return
	var entry: Dictionary = current_body[current_statement_index]
	var lvl := int(entry.get("indent", 0))
	entry["indent"] = lvl + 1
	current_body[current_statement_index] = entry
	_build_statement_tree()
	_select_statement_in_tree(current_statement_index)


func _on_dedent_pressed() -> void:
	if current_statement_index < 0 or current_statement_index >= current_body.size():
		return
	var entry: Dictionary = current_body[current_statement_index]
	var lvl := int(entry.get("indent", 0))
	if lvl > 0:
		entry["indent"] = lvl - 1
		current_body[current_statement_index] = entry
		_build_statement_tree()
		_select_statement_in_tree(current_statement_index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_clear_pending_new_if_needed(-1)


func _update_empty_state() -> void:
	_show_form(not current_method.is_empty())


func _on_tree_item_selected() -> void:
	if statement_tree == null:
		return
	var item := statement_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var type := str(meta.get("type", ""))
	if type == "signature":
		_clear_pending_new_if_needed(-1)
		current_statement_index = -1
		current_statement_type = ""
		_show_form(true)
		_show_only_form("function")
	elif type == "statement":
		_show_form(true)
		var idx := int(meta.get("index", -1))
		if idx != -1 and (pending_new_index != -1 and idx != pending_new_index):
			_clear_pending_new_if_needed(idx)
		current_statement_index = idx
		var entry := {}
		if idx >= 0 and idx < current_body.size():
			entry = _normalized_statement(current_body[idx])
			current_body[idx] = entry
		current_statement_type = str(entry.get("type", "raw")) if typeof(entry) == TYPE_DICTIONARY else "raw"
		_show_statement_form(entry)


func _set_icons() -> void:
	var icon := IconHelper.get_editor_icon(self, "MemberMethod", "EditorIcons")
	if header_icon:
		header_icon.texture = icon
	if code_output_icon:
		code_output_icon.texture = icon


func _set_action_icons() -> void:
	if update_button:
		var save_icon := IconHelper.get_editor_icon(self, "Save", "Save")
		if save_icon:
			update_button.icon = save_icon
		update_button.text = "Save"
		update_button.tooltip_text = "Save changes"
	if delete_button:
		var remove_icon := IconHelper.get_editor_icon(self, "Remove", "Remove")
		if remove_icon:
			delete_button.icon = remove_icon
		delete_button.text = "Delete"
		delete_button.tooltip_text = "Delete this item"


func _update_header() -> void:
	if header_label == null:
		return
	var name := func_name_edit.text.strip_edges() if func_name_edit else ""
	if name == "":
		name = "Function"
	header_label.text = name


func _sanitize_params_array(arr) -> Array:
	var result: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return result
	for entry in arr:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		result.append({
			"name": str(entry.get("name", "")).strip_edges(),
			"type": str(entry.get("type", "")).strip_edges(),
			"default": str(entry.get("default", "")).strip_edges()
		})
	return result


func _sanitize_body_array(arr) -> Array:
	var result: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return result
	for entry in arr:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		result.append(entry.duplicate(true))
	return result


func _refresh_params_ui() -> void:
	if params_container == null:
		return
	for child in params_container.get_children():
		if child != add_param_button:
			child.queue_free()
	if parameters.is_empty():
		# keep add button only
		pass
	else:
		for i in range(parameters.size()):
			var row := HBoxContainer.new()
			row.name = "ParamRow" + str(i)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var name_edit := LineEdit.new()
			name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_edit.placeholder_text = "name"
			name_edit.text = str(parameters[i].get("name", ""))
			name_edit.text_changed.connect(_on_param_field_changed.bind(i, "name"))
			row.add_child(name_edit)

			var type_edit := LineEdit.new()
			type_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			type_edit.placeholder_text = "Type"
			type_edit.text = str(parameters[i].get("type", ""))
			type_edit.text_changed.connect(_on_param_field_changed.bind(i, "type"))
			row.add_child(type_edit)

			var default_edit := LineEdit.new()
			default_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			default_edit.placeholder_text = "default"
			default_edit.text = str(parameters[i].get("default", ""))
			default_edit.text_changed.connect(_on_param_field_changed.bind(i, "default"))
			row.add_child(default_edit)

			var remove_btn := Button.new()
			remove_btn.text = "Remove"
			remove_btn.focus_mode = Control.FOCUS_NONE
			remove_btn.pressed.connect(_on_remove_param_pressed.bind(i))
			row.add_child(remove_btn)

			params_container.add_child(row)
	if add_param_button and add_param_button.get_parent() == params_container:
		params_container.move_child(add_param_button, params_container.get_child_count() - 1)


func _on_add_param_pressed() -> void:
	var base := "param"
	var candidate := base
	var counter := 2
	var existing: Dictionary = {}
	for p in parameters:
		existing[str(p.get("name", ""))] = true
	while existing.has(candidate):
		candidate = "%s_%d" % [base, counter]
		counter += 1
	parameters.append({"name": candidate, "type": "", "default": ""})
	_refresh_params_ui()
	_update_code_preview()


func _on_param_field_changed(new_text: String, index: int, key: String) -> void:
	if index < 0 or index >= parameters.size():
		return
	parameters[index][key] = new_text.strip_edges()
	_update_code_preview()


func _on_remove_param_pressed(index: int) -> void:
	if index < 0 or index >= parameters.size():
		return
	parameters.remove_at(index)
	_refresh_params_ui()
	_update_code_preview()


func _selected_statement_index_from_tree() -> int:
	if statement_tree == null:
		return -1
	var item := statement_tree.get_selected()
	if item == null:
		return -1
	var meta = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return -1
	return int(meta.get("index", -1))


func _add_statement(kind: String) -> void:
	# Remove any pending new if user starts another insertion.
	_clear_pending_new_if_needed(-2)
	var insert_at := current_body.size()
	var selected_idx := _selected_statement_index_from_tree()
	var inherited_indent: int = 0

	if selected_idx >= 0 and selected_idx < current_body.size():
		insert_at = selected_idx + 1
		# Inherit indent from selected item
		var prev = current_body[selected_idx]
		if typeof(prev) == TYPE_DICTIONARY:
			inherited_indent = int(prev.get("indent", 0))

	var entry: Dictionary = {"type": kind, "__new": true, "indent": inherited_indent}
	match kind:
		"comment":
			entry["text"] = ""
		"assignment":
			entry["target"] = ""
			entry["expr"] = ""
		"call":
			entry["call"] = ""
			entry["args"] = ""
		"signal_emit":
			entry["signal"] = ""
			entry["args"] = ""
		"return":
			entry["expr"] = ""
		"if":
			entry["condition"] = ""
			entry["text"] = "if "
		"elif":
			entry["condition"] = ""
			entry["text"] = "elif "
		"else":
			entry["text"] = "else"
		"match":
			entry["subject"] = ""
			entry["text"] = "match "
		"for":
			entry["text"] = "for "
		"while":
			entry["text"] = "while "
		"pass":
			entry["text"] = "pass"
		_:
			entry["text"] = ""
	current_body.insert(insert_at, entry)
	pending_new_index = insert_at
	current_statement_index = insert_at
	current_statement_type = kind
	_build_statement_tree()
	_select_statement_in_tree(insert_at)
	_show_statement_form(entry)
	_focus_active_form(kind)


func _gather_parameters() -> Dictionary:
	var collected: Array = []
	for p in parameters:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pname := str(p.get("name", "")).strip_edges()
		if pname == "":
			return {"params": [], "error": "Parameter entries must include a name."}
		if NodeScriptUtils.is_reserved_identifier(pname):
			return {"params": [], "error": "Parameter '%s' cannot be a GDScript keyword." % pname}
		collected.append({
			"name": pname,
			"type": str(p.get("type", "")).strip_edges(),
			"default": str(p.get("default", "")).strip_edges()
		})
	return {"params": collected}


func _build_statement_tree() -> void:
	if statement_tree == null:
		return
	if _building_tree:
		return
	_building_tree = true

	_signature_item = null
	statement_tree.clear()
	statement_tree.columns = 1
	statement_tree.hide_root = false
	var root := statement_tree.create_item()
	_signature_item = root
	var name := str(current_method.get("name", "function")).strip_edges()
	if name == "":
		name = "function"
	var signature := "func %s(" % name
	signature += _format_params_text(parameters)
	signature += ")"
	var ret := func_return_edit.text.strip_edges() if func_return_edit else ""
	if ret != "":
		signature += " -> %s" % ret
	root.set_text(0, signature)
	root.set_metadata(0, {"type": "signature"})
	if statement_tree.has_method("set_selected"):
		statement_tree.set_selected(root, 0)
	elif root.has_method("select"):
		root.select(0)
	if not current_body.is_empty():
		# Stack of [TreeItem, indentation_level]
		# We start with the root at level -1 effectively, but implementation-wise:
		# The root accepts items at indent 0.
		var stack: Array = []
		stack.append({"item": root, "indent": - 1})

		for i in range(current_body.size()):
			var stmt = _normalized_statement(current_body[i])
			current_body[i] = stmt
			if not _should_display_statement(stmt):
				continue

			var indent_level: int = int(stmt.get("indent", 0))

			# Pop stack until we find the parent (an item with indent < current indent)
			while stack.size() > 1 and stack.back()["indent"] >= indent_level:
				stack.pop_back()

			var parent_obj = stack.back()["item"]
			if not is_instance_valid(parent_obj):
				_building_tree = false
				return

			var parent_item: TreeItem = parent_obj

			var text := _statement_display_text(stmt)
			var child := statement_tree.create_item(parent_item)
			child.set_text(0, text)
			child.set_metadata(0, {"type": "statement", "index": i})
			var icon_name := _statement_icon_name(stmt)
			if icon_name != "" and statement_tree.has_theme_icon(icon_name, "EditorIcons"):
				child.set_icon(0, statement_tree.get_theme_icon(icon_name, "EditorIcons"))

			# For optimization, we can push every item to stack, but logic only requires
			# strict parent tracking. However, "if" or "for" at indent N can be parent
			# to items at indent N+1.
			# Simple approach: push this item as a potential parent for the next items.
			stack.append({"item": child, "indent": indent_level})

			# Expand parent if it has children
			if parent_item != root:
				parent_item.set_collapsed(false)
	else:
		var child := statement_tree.create_item(root)
		child.set_text(0, "(empty)")
		child.set_metadata(0, {"type": "statement", "index": - 1})

	_building_tree = false


func _select_statement_in_tree(idx: int) -> void:
	if statement_tree == null:
		return
	var root := statement_tree.get_root()
	if root == null:
		return
	_find_and_select_recursive(root, idx)


func _find_and_select_recursive(item: TreeItem, idx: int) -> bool:
	if item == null:
		return false
	var meta = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY and int(meta.get("index", -1)) == idx:
		if statement_tree.has_method("set_selected"):
			statement_tree.set_selected(item, 0)
		elif item.has_method("select"):
			item.select(0)
		return true

	var child := item.get_first_child()
	while child:
		if _find_and_select_recursive(child, idx):
			return true
		child = child.get_next()
	return false


func _on_org_region_changed(region_name: String) -> void:
	assigned_region = region_name.strip_edges()


func _on_org_class_changed(class_title: String) -> void:
	assigned_class = class_title.strip_edges()


func _on_org_assign_region_requested() -> void:
	push_warning("No regions available. Add a region first to assign.")


func _on_org_assign_class_requested() -> void:
	push_warning("No classes available. Add a class first to assign.")


func _on_org_cleared_region() -> void:
	assigned_region = ""


func _on_org_cleared_class() -> void:
	assigned_class = ""


func set_region_class_lists(regions: Array, classes: Array) -> void:
	if org_selector:
		org_selector.set_lists(regions, classes)


func set_region_class(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _statement_display_text(stmt) -> String:
	if typeof(stmt) == TYPE_DICTIONARY:
		var t := str(stmt.get("type", ""))
		var txt := str(stmt.get("text", "")).strip_edges()
		# Indentation is now handled by tree structure, so we remove the prefix usage.
		var prefix := ""
		if stmt.get("__new", false):
			prefix += "(new) "
		var label_map := {
			"assignment": "[assign]",
			"return": "[return]",
			"if": "[if]",
			"elif": "[elif]",
			"else": "[else]",
			"match": "[match]",
			"for": "[for]",
			"while": "[while]"
		}
		if label_map.has(t):
			prefix += str(label_map[t]) + " "

		# If the text already starts with the keyword, just use the text
		if txt.begins_with(t + " ") or txt == t:
			return prefix + txt

		match t:
			"comment":
				return prefix + "# " + txt
			"if", "elif":
				return prefix + ("%s %s:" % [t, txt if txt != "" else "condition"])
			"else":
				return prefix + "else:"
			"match":
				return prefix + ("match %s:" % (txt if txt != "" else "value"))
			"for":
				return prefix + ("for %s:" % (txt if txt != "" else "elem in iterable"))
			"while":
				return prefix + ("while %s:" % (txt if txt != "" else "condition"))
			"assignment":
				var target := str(stmt.get("target", "")).strip_edges()
				var expr := str(stmt.get("expr", "")).strip_edges()
				if target != "" and expr != "":
					return prefix + "%s = %s" % [target, expr]
				return prefix + (txt if txt != "" else "assignment")
			"call":
				if txt != "":
					return prefix + txt
				var call_name := str(stmt.get("call", "call"))
				return prefix + "%s(...)" % call_name
			"signal_emit":
				var sig := str(stmt.get("signal", "")).strip_edges()
				if sig != "":
					return prefix + "emit_signal(\"%s\", ...)" % sig
				return prefix + "emit_signal(...)"
			"return":
				var expr2 := str(stmt.get("expr", "")).strip_edges()
				return prefix + ("return %s" % expr2 if expr2 != "" else "return")
			_:
				if txt != "":
					return prefix + txt
				return prefix + (t if t != "" else "statement")
	return str(stmt)


func _statement_icon_name(stmt) -> String:
	if typeof(stmt) != TYPE_DICTIONARY:
		return ""
	var t := str(stmt.get("type", ""))
	match t:
		"comment":
			return "VisualShaderNodeComment"
		"assignment":
			return "Property"
		"call":
			return "Play"
		"signal_emit":
			return "MemberSignal"
		"return":
			return "Return"
		"if", "elif", "else":
			return "Conditional"
		"match":
			return "MatchCase"
		"for":
			return "GuiTreeArrowRight"
		"while":
			return "Loop"
		"pass":
			return "Check"
		_:
			return ""


func _should_display_statement(stmt) -> bool:
	if typeof(stmt) != TYPE_DICTIONARY:
		return true
	var t := str(stmt.get("type", ""))
	if t == "raw":
		var txt := str(stmt.get("text", "")).strip_edges()
		return txt != ""
	return true


func _normalized_statement(stmt) -> Dictionary:
	var entry: Dictionary = {}
	if typeof(stmt) == TYPE_DICTIONARY:
		entry = stmt.duplicate(true)
	else:
		entry = {"type": "raw", "text": str(stmt)}

	var base_text := str(entry.get("text", "")).strip_edges()
	var base_type := str(entry.get("type", ""))
	var is_new := entry.get("__new", false)

	# If already typed (not raw/empty), keep.
	if base_type != "" and base_type != "raw":
		return entry

	var classified := StatementClassifier.classify_line(base_text)
	if classified.is_empty():
		entry["type"] = "raw"
		entry["text"] = base_text
		if is_new:
			entry["__new"] = true
		return entry

	entry["type"] = classified.get("type", "raw")
	entry["text"] = base_text
	match entry["type"]:
		"comment":
			entry["text"] = classified.get("text", base_text)
		"assignment":
			entry["target"] = classified.get("target", entry.get("target", ""))
			entry["expr"] = classified.get("expr", entry.get("expr", ""))
		"call":
			entry["call"] = classified.get("call", entry.get("call", ""))
			entry["args"] = classified.get("args", entry.get("args", ""))
		"signal_emit":
			entry["signal"] = classified.get("signal", entry.get("signal", ""))
			entry["args"] = classified.get("args", entry.get("args", ""))
		"return":
			entry["expr"] = classified.get("expr", entry.get("expr", ""))
		_:
			pass
	if is_new:
		entry["__new"] = true
	return entry


func _show_only_form(target: String) -> void:
	var forms = {
		"function": function_form,
		"comment": comment_form,
		"call": call_form,
		"signal": signal_form,
		"assignment": assignment_form,
		"return": return_form,
		"if": if_form,
		"elif": elif_form,
		"else": else_form,
		"match": match_form,
		"for": for_form,
		"while": while_form
	}
	for key in forms.keys():
		var node = forms[key]
		if node:
			node.visible = key == target
	if fallback_label:
		fallback_label.visible = false


func _show_statement_form(entry: Dictionary) -> void:
	var t := str(entry.get("type", "raw"))
	match t:
		"comment":
			_show_only_form("comment")
			if comment_text:
				comment_text.text = str(entry.get("text", ""))
				comment_text.grab_focus()
		"assignment":
			_show_only_form("assignment")
			if assign_target_edit:
				assign_target_edit.text = str(entry.get("target", ""))
			if assign_expr:
				assign_expr.text = str(entry.get("expr", ""))
			if assign_target_edit:
				assign_target_edit.grab_focus()
		"call":
			_show_only_form("call")
			if call_name_edit:
				call_name_edit.text = str(entry.get("call", entry.get("text", "")))
			if call_args:
				call_args.text = str(entry.get("args", ""))
			if call_name_edit:
				call_name_edit.grab_focus()
		"signal_emit":
			_show_only_form("signal")
			if signal_name_edit:
				signal_name_edit.text = str(entry.get("signal", ""))
			if signal_args:
				signal_args.text = str(entry.get("args", ""))
			if signal_name_edit:
				signal_name_edit.grab_focus()
		"return":
			_show_only_form("return")
			if return_expr:
				return_expr.text = str(entry.get("expr", ""))
			if return_expr:
				return_expr.grab_focus()
		"if":
			_show_only_form("if")
			if if_condition:
				if_condition.text = str(entry.get("condition", ""))
				if_condition.grab_focus()
		"elif":
			_show_only_form("elif")
			if elif_condition:
				elif_condition.text = str(entry.get("condition", ""))
				elif_condition.grab_focus()
		"else":
			_show_only_form("else")
		"match":
			_show_only_form("match")
			if match_subject:
				match_subject.text = str(entry.get("subject", ""))
				match_subject.grab_focus()
		"for":
			_show_only_form("for")
			if for_var_edit:
				for_var_edit.text = str(entry.get("variable", ""))
			if for_iterable_edit:
				for_iterable_edit.text = str(entry.get("iterable", ""))
			if for_var_edit:
				for_var_edit.grab_focus()
		"while":
			_show_only_form("while")
			if while_condition:
				while_condition.text = str(entry.get("condition", ""))
				while_condition.grab_focus()
		_:
			_show_only_form("function")


func _clear_pending_new_if_needed(selection_index: int) -> void:
	if pending_new_index == -1:
		return
	if selection_index == pending_new_index:
		return
	if pending_new_index >= 0 and pending_new_index < current_body.size():
		current_body.remove_at(pending_new_index)
	pending_new_index = -1
	current_statement_index = -1
	current_statement_type = ""
	_build_statement_tree()


func _focus_active_form(kind: String) -> void:
	match kind:
		"comment":
			if comment_text:
				comment_text.grab_focus()
		"assignment":
			if assign_target_edit:
				assign_target_edit.grab_focus()
		"call":
			if call_name_edit:
				call_name_edit.grab_focus()
		"signal_emit":
			if signal_name_edit:
				signal_name_edit.grab_focus()
		"return":
			if return_expr:
				return_expr.grab_focus()
		"if":
			if if_condition:
				if_condition.grab_focus()
		"elif":
			if elif_condition:
				elif_condition.grab_focus()
		"match":
			if match_subject:
				match_subject.grab_focus()
		"for":
			if for_var_edit:
				for_var_edit.grab_focus()
		"while":
			if while_condition:
				while_condition.grab_focus()


func _apply_current_statement_from_form() -> void:
	if current_statement_index < 0:
		return
	if current_statement_index >= current_body.size():
		return
	var entry = current_body[current_statement_index]
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var t := str(entry.get("type", "raw"))
	match t:
		"comment":
			entry["text"] = comment_text.text if comment_text else entry.get("text", "")
		"assignment":
			entry["target"] = assign_target_edit.text.strip_edges() if assign_target_edit else entry.get("target", "")
			entry["expr"] = assign_expr.text.strip_edges() if assign_expr else entry.get("expr", "")
			entry["text"] = "%s = %s" % [entry.get("target", ""), entry.get("expr", "")]
		"call":
			entry["call"] = call_name_edit.text.strip_edges() if call_name_edit else entry.get("call", "")
			entry["args"] = call_args.text.strip_edges() if call_args else entry.get("args", "")
			if entry.get("call", "") != "":
				entry["text"] = "%s(%s)" % [entry.get("call", ""), entry.get("args", "")]
		"signal_emit":
			entry["signal"] = signal_name_edit.text.strip_edges() if signal_name_edit else entry.get("signal", "")
			entry["args"] = signal_args.text.strip_edges() if signal_args else entry.get("args", "")
			entry["text"] = "emit_signal(\"%s\"%s%s)" % [
				entry.get("signal", ""),
				", " if str(entry.get("args", "")).strip_edges() != "" else "",
				entry.get("args", "")
			]
		"return":
			entry["expr"] = return_expr.text.strip_edges() if return_expr else entry.get("expr", "")
			entry["text"] = "return %s" % entry.get("expr", "")
		"if":
			entry["condition"] = if_condition.text.strip_edges() if if_condition else entry.get("condition", "")
			entry["text"] = "if %s:" % entry.get("condition", "")
		"elif":
			entry["condition"] = elif_condition.text.strip_edges() if elif_condition else entry.get("condition", "")
			entry["text"] = "elif %s:" % entry.get("condition", "")
		"else":
			entry["text"] = "else:"
		"match":
			entry["subject"] = match_subject.text.strip_edges() if match_subject else entry.get("subject", "")
			entry["text"] = "match %s:" % entry.get("subject", "")
		"for":
			entry["variable"] = for_var_edit.text.strip_edges() if for_var_edit else entry.get("variable", "")
			entry["iterable"] = for_iterable_edit.text.strip_edges() if for_iterable_edit else entry.get("iterable", "")
			entry["text"] = "for %s in %s:" % [entry.get("variable", ""), entry.get("iterable", "")]
		"while":
			entry["condition"] = while_condition.text.strip_edges() if while_condition else entry.get("condition", "")
			entry["text"] = "while %s:" % entry.get("condition", "")
		_:
			pass
	entry.erase("__new")
	current_body[current_statement_index] = entry
	_build_statement_tree()


func _get_drag_data(at_position: Vector2) -> Variant:
	if statement_tree == null:
		return null
	var item := statement_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var meta = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return null
	var type := str(meta.get("type", ""))
	if type != "statement":
		return null
	var idx := int(meta.get("index", -1))
	if idx < 0:
		return null

	# Create preview
	var preview := Label.new()
	preview.text = item.get_text(0)
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)

	return {"type": "statement", "index": idx, "origin_editor": self}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("origin_editor") != self:
		return false
	if data.get("type") != "statement":
		return false

	var dragged_idx = data.get("index")
	if typeof(dragged_idx) != TYPE_INT or dragged_idx < 0:
		return false

	if statement_tree == null:
		return false

	var target_item := statement_tree.get_item_at_position(at_position)
	# If dropping on usage/empty space, it implies append to end/root, which is usually fine
	# But we need to check if target is valid
	if target_item == null:
		# Check if dropping below the last item?
		return true

	var section := statement_tree.get_drop_section_at_position(at_position)
	var meta = target_item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return false

	var target_type := str(meta.get("type", ""))
	if target_type == "signature":
		# Can drop ON signature (make it first child)
		# Can NOT drop BEFORE signature
		if section < 0:
			return false
		return true

	var target_idx := int(meta.get("index", -1))
	if target_idx < 0:
		return true # Fallback

	# Prevent dropping a node into its own subtree
	# We need to know the range of the dragged subtree
	var subtree_range := _get_subtree_range(dragged_idx)
	if target_idx >= subtree_range[0] and target_idx <= subtree_range[1]:
		return false

	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return

	var dragged_idx: int = data.get("index")
	var target_item := statement_tree.get_item_at_position(at_position)
	var section := statement_tree.get_drop_section_at_position(at_position)

	var subtree_range := _get_subtree_range(dragged_idx)
	var start_idx: int = subtree_range[0]
	var end_idx: int = subtree_range[1]
	var count: int = end_idx - start_idx + 1

	# Extract the slice
	var moving_items: Array = []
	for i in range(count):
		moving_items.append(current_body[start_idx + i])

	# We need to determine new insertion index and new indentation base
	var insertion_idx: int = -1
	var target_base_indent: int = 0

	if target_item == null:
		# Dropped in empty space -> Append to end of root
		insertion_idx = current_body.size() # This will be adjusted after removal?
		target_base_indent = 0
	else:
		var meta = target_item.get_metadata(0)
		var target_type := str(meta.get("type", ""))

		if target_type == "signature" or meta.get("index", -1) == -1:
			# Dropped on signature -> First child
			insertion_idx = 0
			target_base_indent = 0
		else:
			var target_idx: int = int(meta.get("index"))
			var target_entry = current_body[target_idx]
			var target_indent = int(target_entry.get("indent", 0))

			if section == 0:
				# Drop ON item -> Make child
				# Insert after the target item, but indent + 1
				insertion_idx = target_idx + 1
				target_base_indent = target_indent + 1
			elif section == -1:
				# Drop BEFORE item
				insertion_idx = target_idx
				target_base_indent = target_indent
			elif section == 1:
				# Drop AFTER item
				# This is tricky because "After" visually means "Same indent, next sibling"
				# OR "First child of this item" if it was expanded?
				# Standard tree behavior: After means Sibling.
				# We need to skip the target's subtree to find the next sibling position
				var target_subtree := _get_subtree_range(target_idx)
				insertion_idx = target_subtree[1] + 1
				target_base_indent = target_indent

	# Adjust indices for removal
	# If insertion point is AFTER the moving block, we subtract count from insertion_idx
	# If insertion point is BEFORE, we don't.
	# BUT we must be careful not to use stale indices.

	# Strategy: Remove first, then Insert.
	if insertion_idx > start_idx:
		insertion_idx -= count

	# Remove
	for i in range(count):
		current_body.remove_at(start_idx)

	# Adjust Indentation
	var original_base_indent: int = int(moving_items[0].get("indent", 0))
	var indent_diff: int = target_base_indent - original_base_indent

	for item in moving_items:
		var old_indent: int = int(item.get("indent", 0))
		item["indent"] = old_indent + indent_diff

	# Insert
	# Clamp insertion index
	if insertion_idx < 0: insertion_idx = 0
	if insertion_idx > current_body.size(): insertion_idx = current_body.size()

	for i in range(count):
		current_body.insert(insertion_idx + i, moving_items[i])

	_build_statement_tree()

	# Restore selection to the moved item header
	var new_header_idx = insertion_idx
	# We need to find the tree item corresponding to new_header_idx
	# But _build_statement_tree rebuilds everything.
	# We can use _select_statement_in_tree(new_header_idx)
	_select_statement_in_tree(new_header_idx)


func _get_subtree_range(start_idx: int) -> Array:
	if start_idx < 0 or start_idx >= current_body.size():
		return [start_idx, start_idx]

	var start_item = current_body[start_idx]
	var base_indent: int = int(start_item.get("indent", 0))
	var end_idx: int = start_idx

	for i in range(start_idx + 1, current_body.size()):
		var item = current_body[i]
		var item_indent: int = int(item.get("indent", 0))
		if item_indent <= base_indent:
			break
		end_idx = i

	return [start_idx, end_idx]
