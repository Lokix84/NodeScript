@tool
extends PanelContainer

signal delete_requested
signal submitted(data: Dictionary)
signal add_param_requested
signal name_changed(new_name: String)
signal name_commit_requested(new_name: String)

var name_edit: LineEdit
var params_container: VBoxContainer
var add_param_button: Button
var signature_label: Label
var header_icon: TextureRect
var signature_icon: TextureRect
var assigned_region: String = ""
var assigned_class: String = ""
var org_selector

var parameters: Array = []
var confirm_button: Button
const EditorUIHelper = preload("res://addons/nodescript/utils/editor_ui_helper.gd")
const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")


func _ready() -> void:
	name_edit = find_child("SignalName", true, false)
	params_container = find_child("ParametersContainer", true, false)
	add_param_button = find_child("AddParamButton", true, false)
	signature_label = find_child("SignaturePreview", true, false)
	confirm_button = find_child("ConfirmButton", true, false)
	header_icon = find_child("HeaderIcon", true, false)
	signature_icon = find_child("SignatureIcon", true, false)
	org_selector = find_child("OrgSelector", true, false)
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

	if add_param_button and not add_param_button.pressed.is_connected(_on_add_param_pressed):
		add_param_button.pressed.connect(_on_add_param_pressed)
	if name_edit:
		if not name_edit.text_changed.is_connected(_on_name_text_changed):
			name_edit.text_changed.connect(_on_name_text_changed)
		if not name_edit.focus_exited.is_connected(_on_name_focus_exited):
			name_edit.focus_exited.connect(_on_name_focus_exited)

	_set_header_icon()
	_set_signature_icon()

	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)

	var confirm_button: Button = find_child("ConfirmButton", true, false)
	if confirm_button and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)

	# Auto-save on focus lost
	if not focus_exited.is_connected(_on_editor_focus_exited):
		focus_exited.connect(_on_editor_focus_exited)

	_set_action_icons()
	hide()
	_reset_state()


func start_new() -> void:
	_reset_state()
	_set_confirm_text("Save")
	show()
	if name_edit:
		name_edit.grab_focus()
	_emit_name_changed()


func show_signal(name: String, parameters_data) -> void:
	parameters.clear()
	if typeof(parameters_data) == TYPE_DICTIONARY:
		parameters_data = parameters_data.get("parameters", [])
	if typeof(parameters_data) == TYPE_ARRAY:
		for entry in parameters_data:
			if typeof(entry) == TYPE_DICTIONARY:
				parameters.append(entry.duplicate(true))
			else:
				parameters.append(entry)
	if name_edit:
		name_edit.text = name
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
	_refresh_params_ui()
	_update_signature_preview()
	_set_confirm_text("Save")
	show()
	_emit_name_changed()


func _reset_state() -> void:
	parameters.clear()
	if name_edit:
		name_edit.text = ""
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
		org_selector.set_lists([], [])
	_refresh_params_ui()
	_update_signature_preview()
	_emit_name_changed()
	_update_org_rows()


func _set_header_icon() -> void:
	if header_icon:
		header_icon.texture = IconHelper.get_editor_icon(self, "MemberSignal", "Signal")


func _set_signature_icon() -> void:
	if signature_icon:
		signature_icon.texture = IconHelper.get_editor_icon(self, "Script", "Script")


func _set_action_icons() -> void:
	var confirm_button_local: Button = find_child("ConfirmButton", true, false)
	if confirm_button_local:
		var save_icon := IconHelper.get_editor_icon(self, "Save", "Save")
		if save_icon:
			confirm_button_local.icon = save_icon
		confirm_button_local.tooltip_text = "Save"
	var delete_button_local: Button = find_child("DeleteButton", true, false)
	if delete_button_local:
		var remove_icon := IconHelper.get_editor_icon(self, "Remove", "Remove")
		if remove_icon:
			delete_button_local.icon = remove_icon
		delete_button_local.tooltip_text = "Delete"


func add_parameter_from_picker(type_info: Dictionary) -> void:
	if not type_info.has("name"):
		push_warning("SignalEditor: type info missing name.")
		return
	var entry = {
		"name": type_info.get("name", "param"),
		"type": type_info.get("type", "Variant"),
		"display": type_info.get("display", type_info.get("type", "Variant"))
	}
	parameters.append(entry)
	_refresh_params_ui()
	_update_signature_preview()


func _refresh_params_ui() -> void:
	if params_container == null:
		return
	for child in params_container.get_children():
		if child != add_param_button:
			child.queue_free()

	if parameters.is_empty():
		var label := Label.new()
		label.text = "No parameters"
		params_container.add_child(label)

	for i in range(parameters.size()):
		var param = parameters[i]
		var row := HBoxContainer.new()
		row.name = "ParamRow" + str(i)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := Label.new()
		label.text = "%s %s" % [param.get("display", param.get("type", "Variant")), param.get("name", "param")]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var remove_button := Button.new()
		remove_button.text = "Remove"
		remove_button.focus_mode = Control.FOCUS_NONE
		remove_button.pressed.connect(_on_remove_param_pressed.bind(i))
		row.add_child(remove_button)

		params_container.add_child(row)
	# Ensure add button stays at end
	if add_param_button and add_param_button.get_parent() != params_container:
		params_container.add_child(add_param_button)
	elif add_param_button:
		params_container.move_child(add_param_button, params_container.get_child_count() - 1)


func _update_signature_preview() -> void:
	if signature_label == null:
		return
	var name_text = "signal " + (name_edit.text.strip_edges() if name_edit else "<signal_name>")
	var parts: Array[String] = []
	for param in parameters:
		parts.append("%s %s" % [param.get("display", param.get("type", "Variant")), param.get("name", "param")])
	var signature = "%s(%s)" % [name_text if name_text != "" else "<signal>", ", ".join(parts)]
	signature_label.text = signature


func _on_remove_param_pressed(index: int) -> void:
	if index < 0 or index >= parameters.size():
		return
	parameters.remove_at(index)
	_refresh_params_ui()
	_update_signature_preview()


func _on_add_param_pressed() -> void:
	emit_signal("add_param_requested")


func _on_delete_pressed() -> void:
	hide()
	emit_signal("delete_requested")


func _on_confirm_pressed() -> void:
	var signal_name = name_edit.text.strip_edges() if name_edit else ""
	if signal_name == "":
		push_warning("SignalEditor: Name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(signal_name):
		push_warning("SignalEditor: Name cannot be a GDScript keyword.")
		return
	var data = {
		"name": signal_name,
		"parameters": parameters.duplicate(true),
		"region": assigned_region,
		"class": assigned_class
	}
	emit_signal("submitted", data)


func _on_editor_focus_exited() -> void:
	# Auto-save on focus loss if name is valid
	if name_edit and not name_edit.text.strip_edges().is_empty():
		var signal_name = name_edit.text.strip_edges()
		if not NodeScriptUtils.is_reserved_identifier(signal_name):
			_on_confirm_pressed()


func _on_name_text_changed(new_text: String) -> void:
	_update_signature_preview()
	_emit_name_changed()
	if org_selector:
		org_selector.set_blocked(new_text.strip_edges(), "")


func _emit_name_changed() -> void:
	var new_name = name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_changed", new_name)
	_update_signature_preview()


func _update_org_rows() -> void:
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _on_region_clear_pressed() -> void:
	assigned_region = ""
	_update_org_rows()


func _on_class_clear_pressed() -> void:
	assigned_class = ""
	_update_org_rows()


func _popup_option_at_mouse(picker: OptionButton) -> void:
	pass


func _on_name_focus_exited() -> void:
	var current = name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_commit_requested", current)


func set_name_text(new_name: String) -> void:
	if not name_edit:
		return
	name_edit.text = new_name
	_update_signature_preview()
	_emit_name_changed()


func reset_form_state() -> void:
	_reset_state()


func set_region_class_lists(regions: Array, classes: Array) -> void:
	if org_selector:
		org_selector.set_lists(regions, classes)


func set_region_class(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _on_org_region_changed(region_name: String) -> void:
	assigned_region = region_name.strip_edges()
	_update_org_rows()


func _on_org_class_changed(class_title: String) -> void:
	assigned_class = class_title.strip_edges()
	_update_org_rows()


func _on_org_assign_region_requested() -> void:
	push_warning("No regions available. Add a region first to assign.")


func _on_org_assign_class_requested() -> void:
	push_warning("No classes available. Add a class first to assign.")


func _on_org_cleared_region() -> void:
	assigned_region = ""
	_update_org_rows()


func _on_org_cleared_class() -> void:
	assigned_class = ""
	_update_org_rows()


func _set_confirm_text(text: String) -> void:
	if confirm_button:
		confirm_button.text = text
