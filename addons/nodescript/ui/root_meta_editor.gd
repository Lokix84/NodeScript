@tool
extends PanelContainer

signal submitted(data: Dictionary)

var name_label: Label
var tool_check: CheckBox
var extends_edit: LineEdit
var class_name_edit: LineEdit
var confirm_button: Button
var header_icon: TextureRect


func _ready() -> void:
	name_label = find_child("FileNameLabel", true, false)
	tool_check = find_child("ToolCheck", true, false)
	extends_edit = find_child("ExtendsEdit", true, false)
	class_name_edit = find_child("ClassNameEdit", true, false)
	confirm_button = find_child("ConfirmButton", true, false)
	header_icon = find_child("HeaderIcon", true, false)

	if confirm_button and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)

	_set_header_icon()

	hide()
	_reset()


func show_meta(meta: Dictionary, file_name: String) -> void:
	if name_label:
		name_label.text = file_name
	if tool_check:
		tool_check.button_pressed = meta.get("tool", false)
	if extends_edit:
		extends_edit.text = str(meta.get("extends", ""))
	if class_name_edit:
		class_name_edit.text = str(meta.get("class_name", ""))
	show()


func reset_state() -> void:
	_reset()


func _reset() -> void:
	if name_label:
		name_label.text = ""
	if tool_check:
		tool_check.button_pressed = false
	if extends_edit:
		extends_edit.text = ""
	if class_name_edit:
		class_name_edit.text = ""


func _on_confirm_pressed() -> void:
	var payload: Dictionary = {
		"tool": tool_check.button_pressed if tool_check else false,
		"extends": extends_edit.text.strip_edges() if extends_edit else "",
		"class_name": class_name_edit.text.strip_edges() if class_name_edit else ""
	}
	emit_signal("submitted", payload)


func _set_header_icon() -> void:
	if header_icon and has_theme_icon("Script", "EditorIcons"):
		header_icon.texture = get_theme_icon("Script", "EditorIcons")
