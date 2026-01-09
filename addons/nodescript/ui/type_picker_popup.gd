@tool
extends AcceptDialog

signal type_picked(type_info)

const BASE_TYPE_OPTIONS := [
	{"label": "bool", "value": "bool"},
	{"label": "int", "value": "int"},
	{"label": "float", "value": "float"},
	{"label": "String", "value": "String"},
	{"label": "Variant", "value": "Variant"},
	{"label": "Object", "value": "Object"}
]

const CUSTOM_MANUAL_OPTION := {"label": "Custom Class (manual)", "value": "__custom_manual__", "is_manual": true}

var type_list: ItemList
var custom_class_line: LineEdit
var name_line: LineEdit
var custom_class_container: Control
var name_container: Control

var current_config: Dictionary = {}
var pending_callback: Callable = Callable()
var _option_metadata: Array = []


func _ready() -> void:
	type_list = find_child("TypeList", true, false)
	custom_class_line = find_child("CustomClassName", true, false)
	custom_class_container = find_child("CustomClassContainer", true, false)
	name_line = find_child("NameLine", true, false)
	name_container = find_child("NameContainer", true, false)

	if type_list:
		type_list.item_selected.connect(_on_type_selected)
		type_list.item_activated.connect(_on_type_activated)
		_style_type_list()

	if not is_connected("confirmed", _on_confirmed):
		confirmed.connect(_on_confirmed)
	if not is_connected("canceled", _on_canceled):
		canceled.connect(_on_canceled)

	_populate_type_list()
	_update_custom_class_state()
	_update_name_state()


func prompt(config: Dictionary, callback: Callable) -> void:
	current_config = config.duplicate()
	pending_callback = callback
	title = current_config.get("title", "Select Type")
	if name_container:
		name_container.visible = current_config.get("ask_for_name", false)
	if name_line:
		name_line.placeholder_text = current_config.get("name_placeholder", "Name")
		name_line.text = ""
	if custom_class_line:
		custom_class_line.text = ""
	_populate_type_list()
	popup_centered_ratio(0.3)


func _populate_type_list() -> void:
	if type_list == null:
		return
	type_list.clear()
	_option_metadata.clear()

	for option in BASE_TYPE_OPTIONS:
		var idx = type_list.add_item(option.get("label", "Variant"))
		type_list.set_item_icon(idx, _icon_for_type(option.get("label", "")))
		type_list.set_item_metadata(idx, {
			"type": option.get("value", "Variant"),
			"display": option.get("label", "Variant"),
			"is_manual": false
		})

	for project_class in _get_project_class_names():
		var idx_class = type_list.add_item("[Project] " + project_class)
		type_list.set_item_icon(idx_class, _icon_for_type(project_class))
		type_list.set_item_metadata(idx_class, {
			"type": project_class,
			"display": project_class,
			"is_manual": false,
			"is_project_class": true
		})

	var manual_idx = type_list.add_item(CUSTOM_MANUAL_OPTION.get("label", "Custom"))
	type_list.set_item_icon(manual_idx, _icon_for_type("Object"))
	type_list.set_item_metadata(manual_idx, {
		"type": CUSTOM_MANUAL_OPTION.get("value", "__custom_manual__"),
		"display": CUSTOM_MANUAL_OPTION.get("label", "Custom"),
		"is_manual": true
	})

	if type_list.item_count > 0:
		type_list.select(0)
	_update_custom_class_state()


func _on_type_selected(index: int) -> void:
	_update_custom_class_state()


func _on_type_activated(index: int) -> void:
	if get_ok_button():
		get_ok_button().emit_signal("pressed")


func _update_custom_class_state() -> void:
	if type_list == null or custom_class_container == null or custom_class_line == null:
		return
	var selected_idx = type_list.get_selected_items()
	var needs_custom = false
	if not selected_idx.is_empty():
		var meta: Dictionary = type_list.get_item_metadata(selected_idx[0])
		needs_custom = meta.get("is_manual", false)
	custom_class_container.visible = needs_custom
	if not needs_custom:
		custom_class_line.text = ""


func _update_name_state() -> void:
	if name_container:
		name_container.visible = current_config.get("ask_for_name", false)


func _gather_selection() -> Dictionary:
	var result: Dictionary = {}
	if type_list == null:
		return result
	var selected_indices: PackedInt32Array = type_list.get_selected_items()
	if selected_indices.is_empty():
		return result
	var meta: Dictionary = type_list.get_item_metadata(selected_indices[0])
	if meta.get("is_manual", false):
		if custom_class_line == null:
			return {}
		var custom_name = custom_class_line.text.strip_edges()
		if custom_name == "":
			push_warning("TypePicker: Custom class requires a name.")
			return {}
		result = {
			"type": custom_name,
			"display": custom_name,
			"is_custom_class": true
		}
	else:
		result = {
			"type": meta.get("type", "Variant"),
			"display": meta.get("display", meta.get("type", "Variant")),
			"is_custom_class": meta.get("is_project_class", false)
		}

	if current_config.get("ask_for_name", false):
		var param_name = name_line.text.strip_edges() if name_line else ""
		if param_name == "":
			push_warning("TypePicker: Name is required.")
			return {}
		result["name"] = param_name

	return result


func _on_confirmed() -> void:
	var selection = _gather_selection()
	if selection.is_empty():
		return
	if pending_callback.is_valid():
		pending_callback.call(selection)
	emit_signal("type_picked", selection)
	pending_callback = Callable()


func _on_canceled() -> void:
	pending_callback = Callable()


func _get_project_class_names() -> Array:
	var names: Array[String] = []
	if ProjectSettings.has_setting("application/config/script_classes"):
		var classes: Array = ProjectSettings.get_setting("application/config/script_classes", [])
		for entry in classes:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var cls_name: String = str(entry.get("class", entry.get("class_name", ""))).strip_edges()
			if cls_name != "" and not names.has(cls_name):
				names.append(cls_name)
	names.sort()
	return names


func _style_type_list() -> void:
	if type_list == null:
		return
	type_list.icon_mode = ItemList.ICON_MODE_LEFT
	type_list.fixed_icon_size = Vector2i(20, 20)
	type_list.icon_scale = 1.0
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.08, 0.08, 0.8)
	panel.corner_radius_top_left = 4
	panel.corner_radius_top_right = 4
	panel.corner_radius_bottom_left = 4
	panel.corner_radius_bottom_right = 4
	type_list.add_theme_stylebox_override("panel", panel)

	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(0.2, 0.45, 0.8, 0.7)
	selected.border_color = Color(0.75, 0.9, 1.0, 0.95)
	selected.border_width_left = 2
	selected.border_width_right = 2
	selected.border_width_top = 2
	selected.border_width_bottom = 2
	selected.corner_radius_top_left = 6
	selected.corner_radius_top_right = 6
	selected.corner_radius_bottom_left = 6
	selected.corner_radius_bottom_right = 6
	type_list.add_theme_stylebox_override("selected", selected)
	type_list.add_theme_stylebox_override("selected_focus", selected)


func _icon_for_type(raw: String) -> Texture2D:
	var name_lower := str(raw).strip_edges()
	if name_lower == "":
		name_lower = "Variant"
	var candidates: Array[String] = []
	candidates.append(name_lower)
	candidates.append(name_lower.capitalize())
	match name_lower.to_lower():
		"bool", "boolean":
			candidates.append_array(["Boolean"])
		"int", "integer":
			candidates.append_array(["int", "memberint", "Integer", "Number"])
		"float", "real":
			candidates.append_array(["Float"])
		"string", "str":
			candidates.append_array(["String"])
		"array":
			candidates.append_array(["Array"])
		"dictionary", "dict", "map":
			candidates.append_array(["Dictionary"])
		"object", "variant":
			candidates.append_array(["Object", "Variant"])
	for candidate in candidates:
		if has_theme_icon(candidate, "EditorIcons"):
			return get_theme_icon(candidate, "EditorIcons")
	return get_theme_icon("Object", "EditorIcons") if has_theme_icon("Object", "EditorIcons") else null
