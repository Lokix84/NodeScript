@tool
extends RefCounted
class_name NodeScriptEditorUIHelper

# Utility to apply common header/code-output/footer wiring to editor panels.

static func set_header(panel: Node, title: String, icon_name: String, fallback_icon: String = "Node") -> void:
	if panel == null:
		return
	var icon_node: TextureRect = panel.find_child("HeaderIcon", true, false)
	var title_node: Label = panel.find_child("HeaderLabel", true, false)
	if title_node:
		title_node.text = title
	if icon_node:
		var icon := _get_editor_icon(icon_name, fallback_icon, panel)
		icon_node.texture = icon


static func set_code_output(panel: Node, text: String, icon_name: String = "Script") -> void:
	if panel == null:
		return
	var icon_node: TextureRect = panel.find_child("CodeOutputIcon", true, false)
	var value_node: Label = panel.find_child("CodeOutputValue", true, false)
	if icon_node:
		var icon := _get_editor_icon(icon_name, "Script", panel)
		icon_node.texture = icon
	if value_node:
		value_node.text = text


static func _get_editor_icon(name: String, fallback: String, owner: Node) -> Texture2D:
	if owner and owner.has_theme_icon(name, "EditorIcons"):
		return owner.get_theme_icon(name, "EditorIcons")
	if owner and owner.has_theme_icon(fallback, "EditorIcons"):
		return owner.get_theme_icon(fallback, "EditorIcons")
	return null
