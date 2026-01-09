@tool
extends RefCounted
class_name NodeScriptTreeUtils

# Shared helpers for building Tree nodes with icons and metadata.

static func create_item(tree: Tree, parent: TreeItem, text: String, metadata: Dictionary, icon: Texture2D) -> TreeItem:
	if tree == null:
		return null
	var item := tree.create_item(parent)
	item.set_text(0, text)
	if icon:
		item.set_icon(0, icon)
	item.set_metadata(0, metadata)
	return item


static func get_icon(owner: Node, name: String, fallback: String = "Node") -> Texture2D:
	if owner and owner.has_theme_icon(name, "EditorIcons"):
		return owner.get_theme_icon(name, "EditorIcons")
	if owner and owner.has_theme_icon(fallback, "EditorIcons"):
		return owner.get_theme_icon(fallback, "EditorIcons")
	return null


static func ensure_region_item(tree: Tree, region_nodes: Dictionary, region_name: String, fallback_parent: TreeItem, owner: Node, parent_meta: Dictionary = {}) -> TreeItem:
	var key := str(region_name).strip_edges()
	if key == "":
		return fallback_parent
	if region_nodes.has(key):
		return region_nodes[key]
	var icon := get_icon(owner, "VisualShaderNodeComment", "Group")
	var region_item := create_item(tree, fallback_parent, key, {"type": "region", "name": key, "class": str(parent_meta.get("class", "")), "region": str(parent_meta.get("region", ""))}, icon)
	if region_item:
		region_item.collapsed = false
		region_nodes[key] = region_item
	return region_item


static func ensure_class_item(tree: Tree, class_nodes: Dictionary, class_title: String, fallback_parent: TreeItem, owner: Node) -> TreeItem:
	var key := str(class_title).strip_edges()
	if key == "":
		return fallback_parent
	if class_nodes.has(key):
		return class_nodes[key]
	var icon := get_icon(owner, "MiniObject", "MiniObject")
	var class_item := create_item(tree, fallback_parent, key, {"type": "class", "name": key}, icon)
	if class_item:
		class_item.collapsed = false
		class_nodes[key] = class_item
	return class_item


static func parent_for_entry(tree: Tree, class_nodes: Dictionary, class_region_nodes: Dictionary, region_nodes: Dictionary, entry_class: String, entry_region: String, fallback: TreeItem, owner: Node) -> TreeItem:
	var base_parent := ensure_class_item(tree, class_nodes, entry_class, fallback, owner)
	if str(entry_class).strip_edges() == "":
		var meta := {"class": entry_class, "region": ""}
		return ensure_region_item(tree, region_nodes, entry_region, base_parent, owner, meta)
	if not class_region_nodes.has(entry_class):
		class_region_nodes[entry_class] = {}
	var region_dict: Dictionary = class_region_nodes[entry_class]
	var parent_meta := {"class": entry_class, "region": ""}
	return ensure_region_item(tree, region_dict, entry_region, base_parent, owner, parent_meta)
