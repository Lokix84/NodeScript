@tool
extends PanelContainer

signal delete_requested
signal submitted(data: Dictionary)
signal name_changed(new_name: String)
signal name_commit_requested(new_name: String)

var name_edit: LineEdit
var confirm_button: Button
var header_icon: TextureRect
var signature_icon: TextureRect
var signature_preview: Label
var assigned_region: String = ""
var assigned_class: String = ""
var org_selector
const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")
const EditorUIHelper = preload("res://addons/nodescript/utils/editor_ui_helper.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")


func _ready() -> void:
	name_edit = find_child("RegionName", true, false)
	confirm_button = find_child("ConfirmButton", true, false)
	signature_preview = find_child("SignaturePreview", true, false)
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

	if name_edit:
		if not name_edit.text_changed.is_connected(_on_name_changed):
			name_edit.text_changed.connect(_on_name_changed)
		if not name_edit.focus_exited.is_connected(_on_name_focus_exited):
			name_edit.focus_exited.connect(_on_name_focus_exited)

	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)

	if confirm_button and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)

	_set_icons()
	_set_action_icons()
	hide()
	_reset()


func start_new() -> void:
	_reset()
	_set_confirm_text("Save")
	show()
	if name_edit:
		name_edit.grab_focus()
	_update_signature_preview()
	_update_org_blocklist()


func show_region(data: Dictionary) -> void:
	_reset()
	if name_edit:
		name_edit.text = str(data.get("name", ""))
	assigned_class = str(data.get("class", "")).strip_edges()
	assigned_region = str(data.get("region", "")).strip_edges()
	if org_selector:
		org_selector.set_lists(data.get("regions_list", []), data.get("classes_list", []))
		org_selector.set_selection(assigned_region, assigned_class)
		_update_org_blocklist()
	_set_confirm_text("Save")
	show()
	_emit_name_changed()
	_update_signature_preview()


func reset_form_state() -> void:
	_reset()
	_update_signature_preview()


func set_name_text(text: String) -> void:
	if name_edit:
		name_edit.text = text
	_emit_name_changed()
	_update_signature_preview()
	_update_org_blocklist()


func _reset() -> void:
	if name_edit:
		name_edit.text = ""
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_lists([], [])
		org_selector.set_selection("", "")
	_emit_name_changed()
	_update_signature_preview()
	_update_org_blocklist()


func _on_delete_pressed() -> void:
	hide()
	emit_signal("delete_requested")


func _on_confirm_pressed() -> void:
	var payload: Dictionary = {
		"name": name_edit.text.strip_edges() if name_edit else "",
		"class": assigned_class,
		"region": assigned_region
	}
	if payload.get("name", "") == "":
		push_warning("Region name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(str(payload.get("name", ""))):
		push_warning("Region name cannot be a GDScript keyword.")
		return
	emit_signal("submitted", payload)
	_update_signature_preview()


func _on_name_changed(new_text: String) -> void:
	_emit_name_changed()
	_update_signature_preview()
	_update_org_blocklist()


func _on_name_focus_exited() -> void:
	emit_signal("name_commit_requested", name_edit.text.strip_edges() if name_edit else "")


func _emit_name_changed() -> void:
	emit_signal("name_changed", name_edit.text.strip_edges() if name_edit else "")
	_update_signature_preview()


func _set_confirm_text(text: String) -> void:
	if confirm_button:
		confirm_button.text = text


func _update_signature_preview() -> void:
	if signature_preview == null:
		return
	var name := name_edit.text.strip_edges() if name_edit else ""
	if name == "":
		name = "Region"
	signature_preview.text = "#region %s\n#endregion %s" % [name, name]


func _set_icons() -> void:
	var icon := IconHelper.get_editor_icon(self, "VisualShaderNodeComment", "Group")
	if header_icon:
		header_icon.texture = icon
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


func _populate_pick_lists(regions: Array, classes: Array) -> void:
	if org_selector:
		org_selector.set_lists(regions, classes)


func set_region_class(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _on_region_clear_pressed() -> void:
	assigned_region = ""
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)
	emit_signal("cleared_region")


func _on_class_clear_pressed() -> void:
	assigned_class = ""
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)
	emit_signal("cleared_class")


func _on_region_selected(index: int) -> void:
	pass

func _on_class_selected(index: int) -> void:
	pass


func _on_org_region_changed(region_name: String) -> void:
	assigned_region = region_name.strip_edges()
	_update_signature_preview()
	_update_org_blocklist()


func _on_org_class_changed(class_title: String) -> void:
	assigned_class = class_title.strip_edges()
	_update_signature_preview()
	_update_org_blocklist()


func _on_org_assign_region_requested() -> void:
	push_warning("No regions available. Add a region first to assign.")


func _on_org_assign_class_requested() -> void:
	push_warning("No classes available. Add a class first to assign.")


func _on_org_cleared_region() -> void:
	_on_region_clear_pressed()


func _on_org_cleared_class() -> void:
	_on_class_clear_pressed()
	_update_signature_preview()


func _update_org_rows() -> void:
	# Refresh organization selector rows based on current assignments.
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _update_org_blocklist() -> void:
	if org_selector == null:
		return
	var current_name := name_edit.text.strip_edges() if name_edit else ""
	org_selector.set_blocked(current_name, "")
