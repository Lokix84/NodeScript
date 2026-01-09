@tool
extends PanelContainer

signal delete_requested
signal submitted(data: Dictionary)
signal name_changed(new_name: String)
signal name_commit_requested(new_name: String)

var name_edit: LineEdit
var extends_edit: LineEdit
var confirm_button: Button
var header_icon: TextureRect
var signature_preview: Label
var signature_icon: TextureRect
var region_picker: OptionButton
var class_picker: OptionButton
const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")
const EditorUIHelper = preload("res://addons/nodescript/utils/editor_ui_helper.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
var assigned_region: String = ""
var assigned_class: String = ""
var region_button: Button
var class_button: Button
var region_row: HBoxContainer
var class_row: HBoxContainer
var region_label: Label
var class_label: Label
var _last_regions: Array = []
var _last_classes: Array = []
var org_selector


func _ready() -> void:
	name_edit = find_child("ClassName", true, false)
	extends_edit = find_child("ExtendsEdit", true, false)
	confirm_button = find_child("ConfirmButton", true, false)
	header_icon = find_child("HeaderIcon", true, false)
	signature_preview = find_child("SignaturePreview", true, false)
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


func show_class(data: Dictionary) -> void:
	_reset()
	if name_edit:
		name_edit.text = str(data.get("name", ""))
	if extends_edit:
		extends_edit.text = str(data.get("extends", ""))
	set_region_class(str(data.get("region", "")), str(data.get("class", "")))
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


func _reset() -> void:
	if name_edit:
		name_edit.text = ""
	if extends_edit:
		extends_edit.text = ""
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
		org_selector.set_lists([], [])
	_emit_name_changed()
	_update_signature_preview()
	_reapply_class_filter()


func _on_delete_pressed() -> void:
	hide()
	emit_signal("delete_requested")


func _on_confirm_pressed() -> void:
	var payload: Dictionary = {
		"name": name_edit.text.strip_edges() if name_edit else "",
		"extends": extends_edit.text.strip_edges() if extends_edit else "",
		"region": assigned_region,
		"class": assigned_class
	}
	if payload.get("name", "") == "":
		push_warning("Class name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(str(payload.get("name", ""))):
		push_warning("Class name cannot be a GDScript keyword.")
		return
	emit_signal("submitted", payload)
	_update_signature_preview()


func _on_name_changed(_new_text: String) -> void:
	_emit_name_changed()
	_update_signature_preview()
	_reapply_class_filter()


func _on_name_focus_exited() -> void:
	emit_signal("name_commit_requested", name_edit.text.strip_edges() if name_edit else "")


func _emit_name_changed() -> void:
	emit_signal("name_changed", name_edit.text.strip_edges() if name_edit else "")


func _set_confirm_text(text: String) -> void:
	if confirm_button:
		confirm_button.text = text


func set_region_class_lists(regions: Array, classes: Array) -> void:
	_last_regions = regions.duplicate(true)
	_last_classes = classes.duplicate(true)
	if org_selector:
		org_selector.set_lists(regions, _filtered_classes(regions, classes))


func set_region_class(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	_reapply_class_filter()
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _populate_picker(picker: OptionButton, items: Array) -> void:
	if picker == null:
		return
	picker.clear()
	if items.is_empty():
		picker.disabled = true
		picker.text = "None available"
	else:
		picker.disabled = false
		picker.text = "Select"
		for item in items:
			picker.add_item(str(item))


func _filtered_classes(regions: Array = [], classes: Array = []) -> Array:
	var list := classes if not classes.is_empty() else _last_classes
	var current_name := name_edit.text.strip_edges() if name_edit else ""
	if current_name == "":
		return list
	var filtered: Array = []
	for c in list:
		if str(c).strip_edges() == current_name:
			continue
		filtered.append(c)
	return filtered


func _is_blocked_class(name: String) -> bool:
	var current_name := name_edit.text.strip_edges() if name_edit else ""
	return current_name != "" and name.strip_edges() == current_name


func _reapply_class_filter() -> void:
	if org_selector == null:
		return
	var filtered := _filtered_classes(_last_regions, _last_classes)
	org_selector.set_lists(_last_regions, filtered)
	org_selector.set_selection(assigned_region, assigned_class if assigned_class in filtered else "")


func _select_in_picker(picker: OptionButton, value: String) -> void:
	if picker == null:
		return
	if value == "":
		picker.select(-1)
		return
	for i in range(picker.item_count):
		if picker.get_item_text(i) == value:
			picker.select(i)
			break


func _update_org_rows() -> void:
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)


func _on_region_button_pressed() -> void:
	_popup_option_at_mouse(region_picker)


func _on_class_button_pressed() -> void:
	_popup_option_at_mouse(class_picker)

func _on_region_clear_pressed() -> void:
	assigned_region = ""
	_select_in_picker(region_picker, "")
	_update_org_rows()


func _on_class_clear_pressed() -> void:
	assigned_class = ""
	_select_in_picker(class_picker, "")
	_update_org_rows()


func _on_org_region_changed(region_name: String) -> void:
	assigned_region = region_name.strip_edges()
	_update_signature_preview()
	_update_org_rows()


func _on_org_class_changed(class_title: String) -> void:
	assigned_class = class_title.strip_edges()
	_update_signature_preview()
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


func _popup_option_at_mouse(picker: OptionButton) -> void:
	if picker == null:
		return
	var popup := picker.get_popup()
	if popup:
		popup.reset_size()
		var mouse: Vector2 = get_global_mouse_position()
		var size: Vector2i = popup.size
		if size == Vector2i.ZERO:
			var min_size: Vector2 = popup.get_combined_minimum_size()
			size = Vector2i(int(min_size.x), int(min_size.y))
		popup.popup_on_parent(Rect2i(Vector2i(mouse.round()), size))

func _update_signature_preview() -> void:
	if signature_preview == null:
		return
	var cls_name := name_edit.text.strip_edges() if name_edit else ""
	if cls_name == "":
		cls_name = "MyInnerClass"
	signature_preview.text = "class %s:" % cls_name


func _set_icons() -> void:
	var icon := IconHelper.get_editor_icon(self, "MiniObject", "MiniObject")
	if header_icon:
		header_icon.texture = icon
	if signature_icon:
		signature_icon.texture = icon


func _set_action_icons() -> void:
	if confirm_button:
		var save_icon := IconHelper.get_editor_icon(self, "Save", "Save")
		if save_icon:
			confirm_button.icon = save_icon
		confirm_button.tooltip_text = "Save class"
	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button:
		var remove_icon := IconHelper.get_editor_icon(self, "Remove", "Remove")
		if remove_icon:
			delete_button.icon = remove_icon
		delete_button.tooltip_text = "Delete class"


func _get_editor_icon(name: String) -> Texture2D:
	return IconHelper.get_editor_icon(self, name, name)
