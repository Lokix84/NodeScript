@tool
extends PanelContainer

signal delete_requested
signal submitted(data: Dictionary)
signal name_changed(new_name: String)
signal name_commit_requested(new_name: String)

var name_edit: LineEdit
var values_container: VBoxContainer
var add_value_button: Button
var confirm_button: Button
var signature_label: Label
var header_icon: TextureRect
var signature_icon: TextureRect
var assigned_region: String = ""
var assigned_class: String = ""
var org_selector

var values: Array[String] = []
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")

# Helper to get an editor icon without external IconHelper dependency
func _get_editor_icon(primary: String, fallback: String = "Script") -> Texture2D:
	var root := get_tree().root
	if root and root.has_theme_icon(primary, "EditorIcons"):
		return root.get_theme_icon(primary, "EditorIcons")
	if root and root.has_theme_icon(fallback, "EditorIcons"):
		return root.get_theme_icon(fallback, "EditorIcons")
	return null


func _ready() -> void:
	name_edit = find_child("EnumName", true, false)
	values_container = find_child("ValuesContainer", true, false)
	add_value_button = find_child("AddValueButton", true, false)
	confirm_button = find_child("ConfirmButton", true, false)
	signature_label = find_child("SignaturePreview", true, false)
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

	if name_edit:
		if not name_edit.text_changed.is_connected(_on_name_text_changed):
			name_edit.text_changed.connect(_on_name_text_changed)
		if not name_edit.focus_exited.is_connected(_on_name_focus_exited):
			name_edit.focus_exited.connect(_on_name_focus_exited)

	if add_value_button and not add_value_button.pressed.is_connected(_on_add_value_pressed):
		add_value_button.pressed.connect(_on_add_value_pressed)

	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)

	var confirm_button_local: Button = find_child("ConfirmButton", true, false)
	if confirm_button_local and not confirm_button_local.pressed.is_connected(_on_confirm_pressed):
		confirm_button_local.pressed.connect(_on_confirm_pressed)

	_set_header_icon()
	_set_signature_icon()
	_update_signature_preview()
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


func show_enum(name: String, value_list: Array) -> void:
	values.clear()
	for entry in value_list:
		values.append(str(entry))
	if name_edit:
		name_edit.text = name
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
	_update_org_rows()
	_refresh_values_ui()
	_update_signature_preview()
	_set_confirm_text("Save")
	show()
	_emit_name_changed()


func reset_form_state() -> void:
	_reset_state()
	_update_signature_preview()


func set_name_text(new_name: String) -> void:
	if not name_edit:
		return
	name_edit.text = new_name
	_emit_name_changed()
	_update_signature_preview()


func _reset_state() -> void:
	values.clear()
	if name_edit:
		name_edit.text = ""
	assigned_region = ""
	assigned_class = ""
	if org_selector:
		org_selector.set_selection("", "")
		org_selector.set_lists([], [])
	_update_org_rows()
	_refresh_values_ui()
	_emit_name_changed()
	_update_signature_preview()


func _refresh_values_ui() -> void:
	if values_container == null:
		return
	for child in values_container.get_children():
		if child != add_value_button:
			child.queue_free()

	if values.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No values"
		values_container.add_child(empty_label)
	else:
		for i in range(values.size()):
			var row := HBoxContainer.new()
			row.name = "ValueRow" + str(i)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var edit := LineEdit.new()
			edit.text = values[i]
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(_on_value_text_changed.bind(i))
			edit.focus_exited.connect(_on_value_focus_exited.bind(i))
			row.add_child(edit)

			var remove_button := Button.new()
			remove_button.text = "Remove"
			remove_button.focus_mode = Control.FOCUS_NONE
			remove_button.pressed.connect(_on_remove_value_pressed.bind(i))
			row.add_child(remove_button)

			values_container.add_child(row)
	# Ensure add button as last entry
	if add_value_button:
		if add_value_button.get_parent() != values_container:
			values_container.add_child(add_value_button)
		else:
			values_container.move_child(add_value_button, values_container.get_child_count() - 1)


func _on_add_value_pressed() -> void:
	var base_name := "Value"
	var unique := _ensure_unique_value(base_name)
	values.append(unique)
	_refresh_values_ui()
	_update_signature_preview()


func _on_remove_value_pressed(index: int) -> void:
	if index < 0 or index >= values.size():
		return
	values.remove_at(index)
	_refresh_values_ui()
	_update_signature_preview()


func _on_value_text_changed(new_text: String, index: int) -> void:
	_set_value_at(index, new_text)
	_update_signature_preview()


func _on_value_focus_exited(index: int) -> void:
	if index < 0 or index >= values.size():
		return
	var sanitized = _sanitize_value(values[index])
	if sanitized == "":
		sanitized = _ensure_unique_value("Value")
	values[index] = sanitized
	_refresh_values_ui()
	_update_signature_preview()


func _on_delete_pressed() -> void:
	hide()
	emit_signal("delete_requested")


func _on_confirm_pressed() -> void:
	var enum_name = name_edit.text.strip_edges() if name_edit else ""
	if enum_name == "":
		push_warning("EnumEditor: Name is required.")
		return
	if NodeScriptUtils.is_reserved_identifier(enum_name):
		push_warning("EnumEditor: Name cannot be a GDScript keyword.")
		return
	var payload = {
		"name": enum_name,
		"values": values.duplicate(),
		"region": assigned_region,
		"class": assigned_class
	}
	emit_signal("submitted", payload)
	_update_signature_preview()


func _on_name_text_changed(new_text: String) -> void:
	_emit_name_changed()
	_update_signature_preview()
	if org_selector:
		org_selector.set_blocked(new_text.strip_edges(), "")


func _on_name_focus_exited() -> void:
	var current = name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_commit_requested", current)
	_update_signature_preview()


func _emit_name_changed() -> void:
	var new_name = name_edit.text.strip_edges() if name_edit else ""
	emit_signal("name_changed", new_name)
	_update_signature_preview()


func _on_org_region_changed(new_region: String) -> void:
	assigned_region = new_region.strip_edges()
	_update_org_rows()
	_update_signature_preview()


func _on_org_class_changed(new_class: String) -> void:
	assigned_class = new_class.strip_edges()
	_update_org_rows()
	_update_signature_preview()

func _update_org_rows() -> void:
	if org_selector:
		org_selector.set_selection(assigned_region, assigned_class)

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


func _set_value_at(index: int, text: String) -> void:
	if index < 0:
		return
	if index >= values.size():
		return
	values[index] = text
	_update_signature_preview()


func _ensure_unique_value(base: String) -> String:
	var trimmed = _sanitize_value(base)
	if trimmed == "":
		trimmed = "Value"
	var candidate = trimmed
	var counter = 2
	var existing: Dictionary = {}
	for v in values:
		existing[str(v)] = true
	while existing.has(candidate):
		candidate = "%s_%d" % [trimmed, counter]
		counter += 1
	return candidate


func _sanitize_value(raw: String) -> String:
	return raw.strip_edges().replace(" ", "_").to_upper()


func _update_signature_preview() -> void:
	if signature_label == null:
		return
	var enum_name := name_edit.text.strip_edges() if name_edit else ""
	if enum_name == "":
		enum_name = "<Enum>"
	var shown_values: Array[String] = []
	for v in values:
		shown_values.append(str(v))
	var body := "{}"
	if not shown_values.is_empty():
		body = "{ " + ", ".join(shown_values) + " }"
	signature_label.text = "enum %s %s" % [enum_name, body]
func _set_header_icon() -> void:
	if header_icon == null:
		return
	var icon_names: Array[String] = ["Enumeration", "Enum", "Script", "MemberConstant"]
	for icon_name in icon_names:
		var icon = _get_editor_icon(icon_name, "Enumeration")
		if icon:
			header_icon.texture = icon
			return
	header_icon.texture = _get_editor_icon("Script", "Script")

func _set_signature_icon() -> void:
	if signature_icon == null:
		return
	var icon_names: Array[String] = ["Enumeration", "Enum", "Script", "MemberConstant"]
	for icon_name in icon_names:
		var icon = _get_editor_icon(icon_name, "Script")
		if icon:
			signature_icon.texture = icon
			return
	signature_icon.texture = _get_editor_icon("Script", "Script")


func _set_action_icons() -> void:
	if confirm_button:
		var save_icon := _get_editor_icon("Save", "Save")
		if save_icon:
			confirm_button.icon = save_icon
		confirm_button.tooltip_text = "Save enum"
	var delete_button: Button = find_child("DeleteButton", true, false)
	if delete_button:
		var remove_icon := _get_editor_icon("Remove", "Remove")
		if remove_icon:
			delete_button.icon = remove_icon
		delete_button.tooltip_text = "Delete enum"
