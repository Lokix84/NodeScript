@tool
extends PanelContainer

signal delete_requested
signal submitted(data: Dictionary)
signal type_pick_requested
signal name_changed(new_name: String)
signal name_commit_requested(new_name: String)

var name_edit: LineEdit
var type_button: Button
var export_check: CheckBox
var const_check: CheckBox
var onready_check: CheckBox
var export_group_edit: LineEdit
var value_edit: LineEdit
var confirm_button: Button
var signature_label: Label
var header_icon: TextureRect
var header_title: Label
var signature_icon: TextureRect
var _suppress_mode_change: bool = false
var assigned_region: String = ""
var assigned_class: String = ""
var org_selector
const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")

var selected_type: Dictionary = {"type": "Variant", "display": "Variant"}

func _ready() -> void:
	name_edit = find_child("VariableName", true, false)
	type_button = find_child("TypeButton", true, false)
	export_check = find_child("ExportCheck", true, false)
	const_check = find_child("ConstCheck", true, false)
	onready_check = find_child("OnreadyCheck", true, false)
	export_group_edit = find_child("ExportGroup", true, false)
	value_edit = find_child("ValueField", true, false)
	confirm_button = find_child("VarConfirmButton", true, false)
	signature_label = find_child("SignaturePreview", true, false)
	header_icon = find_child("HeaderIcon", true, false)
	header_title = find_child("Title", true, false)
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

	if type_button and not type_button.pressed.is_connected(_on_type_button_pressed):
		type_button.pressed.connect(_on_type_button_pressed)
	if name_edit:
		if not name_edit.text_changed.is_connected(_on_name_text_changed):
			name_edit.text_changed.connect(_on_name_text_changed)
		if not name_edit.focus_exited.is_connected(_on_name_focus_exited):
			name_edit.focus_exited.connect(_on_name_focus_exited)
	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)
	var confirm_button: Button = find_child("ConfirmButton", true, false)
	if confirm_button and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)
	if export_check and not export_check.toggled.is_connected(_on_export_mode_toggled):
		export_check.toggled.connect(_on_export_mode_toggled)
	if onready_check and not onready_check.toggled.is_connected(_on_onready_mode_toggled):
		onready_check.toggled.connect(_on_onready_mode_toggled)

	# Auto-save on focus lost
	if not focus_exited.is_connected(_on_editor_focus_exited):
		focus_exited.connect(_on_editor_focus_exited)

	_set_header_icon()
	_set_signature_icon()
	_update_signature_preview()
	_update_title()
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
	_update_signature_preview()


func show_variable(data: Dictionary) -> void:
	if name_edit:
		name_edit.text = str(data.get("name", ""))
	selected_type = {
		"type": data.get("type", "Variant"),
		"display": data.get("type_label", data.get("type", "Variant"))
	}
	if export_check:
		export_check.button_pressed = data.get("export", false)
	if const_check:
		const_check.button_pressed = data.get("const", false)
	if onready_check:
		onready_check.button_pressed = data.get("onready", false)
	_enforce_mode_constraints()
	if export_group_edit:
		export_group_edit.text = str(data.get("export_group", ""))
	if value_edit:
		value_edit.text = str(data.get("value", ""))
	assigned_region = str(data.get("region", ""))
	assigned_class = str(data.get("class", ""))
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)
	_update_org_rows()
	_update_type_button()
	_set_confirm_text("Save")
	show()
	_emit_name_changed()
	_update_signature_preview()


func _reset_state() -> void:
	selected_type = {"type": "Variant", "display": "Variant"}
	if name_edit:
		name_edit.text = ""
	if export_check:
		export_check.button_pressed = false
	if const_check:
		const_check.button_pressed = false
	if onready_check:
		onready_check.button_pressed = false
	_enforce_mode_constraints()
	if export_group_edit:
		export_group_edit.text = ""
	if value_edit:
		value_edit.text = ""
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
		org_selector.set_lists([], [])
	_update_org_rows()
	_update_type_button()
	_emit_name_changed()
	_update_signature_preview()


func set_selected_type(type_info: Dictionary) -> void:
	if type_info.is_empty():
		return
	selected_type = type_info.duplicate(true)
	_update_type_button()


func _update_type_button() -> void:
	if type_button:
		type_button.text = "Type: %s" % selected_type.get("display", "Variant")
	_update_signature_preview()
	_set_header_icon()


func _on_type_button_pressed() -> void:
	emit_signal("type_pick_requested")


func _on_delete_pressed() -> void:
	hide()
	emit_signal("delete_requested")


func _on_confirm_pressed() -> void:
	var var_name = name_edit.text.strip_edges() if name_edit else ""
	if var_name == "":
		push_warning("VariableEditor: Name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(var_name):
		push_warning("VariableEditor: Name cannot be a GDScript keyword.")
		return
	var data = {
		"name": var_name,
		"type": selected_type.get("type", "Variant"),
		"type_label": selected_type.get("display", "Variant"),
		"export": export_check.button_pressed if export_check else false,
		"const": const_check.button_pressed if const_check else false,
		"onready": onready_check.button_pressed if onready_check else false,
		"export_group": export_group_edit.text.strip_edges() if export_group_edit else "",
		"value": value_edit.text if value_edit else "",
		"region": assigned_region,
		"class": assigned_class
	}
	emit_signal("submitted", data)


func _on_editor_focus_exited() -> void:
	# Auto-save on focus loss if name is valid
	if name_edit and not name_edit.text.strip_edges().is_empty():
		var var_name = name_edit.text.strip_edges()
		if not NodeScriptUtils.is_reserved_identifier(var_name):
			_on_confirm_pressed()


func _on_name_text_changed(new_text: String) -> void:
	_emit_name_changed()
	if org_selector:
		org_selector.set_blocked(new_text.strip_edges(), "")
	_update_signature_preview()


func _on_region_selected(index: int) -> void:
	pass


func _on_class_selected(index: int) -> void:
	pass


func set_region_class_lists(regions: Array, classes: Array) -> void:
	if org_selector:
		org_selector.set_lists(regions, classes)


func set_region_class(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _update_org_rows() -> void:
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


func _on_name_focus_exited() -> void:
	var current = name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_commit_requested", current)


func set_name_text(new_name: String) -> void:
	if not name_edit:
		return
	name_edit.text = new_name
	_update_signature_preview()
	_emit_name_changed()


func _emit_name_changed() -> void:
	var current := name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_changed", current)


func reset_form_state() -> void:
	_reset_state()


func _set_confirm_text(text: String) -> void:
	if confirm_button:
		confirm_button.text = text


func _on_export_mode_toggled(pressed: bool) -> void:
	if _suppress_mode_change or not export_check or not onready_check:
		return
	if pressed:
		_suppress_mode_change = true
		onready_check.button_pressed = false
		_suppress_mode_change = false


func _on_onready_mode_toggled(pressed: bool) -> void:
	if _suppress_mode_change or not export_check or not onready_check:
		return
	if pressed:
		_suppress_mode_change = true
		export_check.button_pressed = false
		_suppress_mode_change = false


func _enforce_mode_constraints() -> void:
	if not export_check or not onready_check:
		return
	if export_check.button_pressed and onready_check.button_pressed:
		onready_check.button_pressed = false


func _update_signature_preview() -> void:
	if signature_label == null:
		return
	var var_name := name_edit.text.strip_edges() if name_edit else ""
	if var_name == "":
		var_name = "<variable>"
	var type_text := str(selected_type.get("display", "")).strip_edges()
	var prefix := "@export " if export_check and export_check.button_pressed else "@onready " if onready_check and onready_check.button_pressed else ""
	var keyword := "const " if const_check and const_check.button_pressed else "var "
	var line := prefix + keyword + var_name
	if type_text != "":
		line += ": " + type_text
	var value_text := value_edit.text if value_edit else ""
	if value_text.strip_edges() != "":
		line += " = " + value_text.strip_edges()
	signature_label.text = line

func _set_header_icon() -> void:
	if header_icon == null:
		return
	var icon_name := _variable_type_icon_name()
	var icon := IconHelper.get_editor_icon(self, icon_name, "Object")
	if icon == null:
		icon = IconHelper.get_editor_icon(self, "Object", "Node")
	header_icon.texture = icon

func _update_title() -> void:
	if header_title and header_title.text == "":
		header_title.text = "Variable"


func _set_signature_icon() -> void:
	if signature_icon == null:
		return
	signature_icon.texture = IconHelper.get_editor_icon(self, "Script", "Script")


func _set_action_icons() -> void:
	var confirm_button: Button = find_child("VarConfirmButton", true, false)
	if confirm_button == null:
		confirm_button = find_child("ConfirmButton", true, false)
	if confirm_button:
		var save_icon := IconHelper.get_editor_icon(self, "Save", "Save")
		if save_icon:
			confirm_button.icon = save_icon
		confirm_button.tooltip_text = "Save variable"
	var delete_button: Button = find_child("VarCancelButton", true, false)
	if delete_button == null:
		delete_button = find_child("DeleteButton", true, false)
	if delete_button:
		var remove_icon := IconHelper.get_editor_icon(self, "Remove", "Remove")
		if remove_icon:
			delete_button.icon = remove_icon
		delete_button.tooltip_text = "Delete variable"

func _variable_type_icon_name() -> String:
	var raw := str(selected_type.get("type", "")).strip_edges()
	var lower := raw.to_lower()

	if raw == "":
		return "Variant"

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
		"vector2":
			candidates.append_array(["Vector2"])
		"vector3":
			candidates.append_array(["Vector3"])

	candidates.append_array(["Object", "Variant"])

	for icon_name in candidates:
		if _has_editor_icon(icon_name):
			return icon_name
	return "Object"


func _has_editor_icon(name: String) -> bool:
	var tree := get_tree()
	var root := tree.root if tree else null
	if root and root.has_theme_icon(name, "EditorIcons"):
		return true
	return self != null and self.has_theme_icon(name, "EditorIcons")
