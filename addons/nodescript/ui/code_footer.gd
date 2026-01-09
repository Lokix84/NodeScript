@tool
extends VBoxContainer

const IconHelper = preload("res://addons/nodescript/utils/icon_helper.gd")

func _ready() -> void:
	var delete_button: Button = find_child("DeleteButton", true, false)
	var confirm_button: Button = find_child("ConfirmButton", true, false)
	if confirm_button:
		var save_icon := _editor_icon("Save")
		if save_icon:
			confirm_button.icon = save_icon
		if confirm_button.tooltip_text.strip_edges() == "":
			confirm_button.tooltip_text = "Save"
	if delete_button:
		var remove_icon := _editor_icon("Remove")
		if remove_icon:
			delete_button.icon = remove_icon
		if delete_button.tooltip_text.strip_edges() == "":
			delete_button.tooltip_text = "Delete"


func _editor_icon(name: String) -> Texture2D:
	var root := get_tree().root if get_tree() else null
	if root and root.has_theme_icon(name, "EditorIcons"):
		return root.get_theme_icon(name, "EditorIcons")
	if has_theme_icon(name, "EditorIcons"):
		return get_theme_icon(name, "EditorIcons")
	# Fallback to default editor theme (available in editor context).
	if Engine.is_editor_hint():
		var theme := ThemeDB.get_default_theme()
		if theme and theme.has_icon(name, "EditorIcons"):
			return theme.get_icon(name, "EditorIcons")
	return null
