@tool
extends RefCounted
class_name NodeScriptIconHelper

static func get_editor_icon(owner: Node, name: String, fallback: String = "Node") -> Texture2D:
	if owner and owner.has_theme_icon(name, "EditorIcons"):
		return owner.get_theme_icon(name, "EditorIcons")
	if owner and owner.has_theme_icon(fallback, "EditorIcons"):
		return owner.get_theme_icon(fallback, "EditorIcons")
	return null
