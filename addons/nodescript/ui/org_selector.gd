@tool
extends VBoxContainer

signal assign_region_requested
signal assign_class_requested
signal region_changed(region_name: String)
signal class_changed(class_title: String)
signal cleared_region
signal cleared_class

var region_picker: OptionButton
var class_picker: OptionButton
var region_button: Button
var class_button: Button
var region_row: HBoxContainer
var class_row: HBoxContainer
var region_label: Label
var class_label: Label

var assigned_region: String = ""
var assigned_class: String = ""
var blocked_region: String = ""
var blocked_class: String = ""
var _last_regions: Array = []
var _last_classes: Array = []


func _ready() -> void:
	region_picker = find_child("RegionPicker", true, false)
	class_picker = find_child("ClassPicker", true, false)
	region_button = find_child("RegionButton", true, false)
	class_button = find_child("ClassButton", true, false)
	region_row = find_child("RegionRow", true, false)
	class_row = find_child("ClassRow", true, false)
	region_label = find_child("RegionLabel", true, false)
	class_label = find_child("ClassLabel", true, false)

	var region_clear: Button = find_child("RegionClear", true, false)
	var class_clear: Button = find_child("ClassClear", true, false)

	if region_picker and not region_picker.item_selected.is_connected(_on_region_selected):
		region_picker.item_selected.connect(_on_region_selected)
	if class_picker and not class_picker.item_selected.is_connected(_on_class_selected):
		class_picker.item_selected.connect(_on_class_selected)
	if region_button and not region_button.pressed.is_connected(_on_region_button_pressed):
		region_button.pressed.connect(_on_region_button_pressed)
	if class_button and not class_button.pressed.is_connected(_on_class_button_pressed):
		class_button.pressed.connect(_on_class_button_pressed)
	if region_clear and not region_clear.pressed.is_connected(_on_region_clear_pressed):
		region_clear.pressed.connect(_on_region_clear_pressed)
	if class_clear and not class_clear.pressed.is_connected(_on_class_clear_pressed):
		class_clear.pressed.connect(_on_class_clear_pressed)

	_update_buttons()
	_update_org_rows()


func set_lists(regions: Array, classes: Array) -> void:
	_last_regions = regions.duplicate(true)
	_last_classes = classes.duplicate(true)
	_populate_picker(region_picker, _filtered_regions())
	_populate_picker(class_picker, _filtered_classes())
	_update_buttons()


func set_selection(region_name: String, class_title: String) -> void:
	assigned_region = region_name.strip_edges()
	assigned_class = class_title.strip_edges()
	if blocked_region != "" and assigned_region == blocked_region:
		assigned_region = ""
	if blocked_class != "" and assigned_class == blocked_class:
		assigned_class = ""
	_select_in_picker(region_picker, assigned_region)
	_select_in_picker(class_picker, assigned_class)
	_update_org_rows()
	_update_buttons()


func set_blocked(region_name: String, class_title: String) -> void:
	blocked_region = region_name.strip_edges()
	blocked_class = class_title.strip_edges()
	# Reapply lists to drop blocked entries and refresh selection if needed.
	set_lists(_last_regions, _last_classes)
	set_selection(assigned_region, assigned_class)


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
	picker.select(-1)


func _select_in_picker(picker: OptionButton, value: String) -> void:
	if picker == null:
		return
	if value.strip_edges() == "":
		picker.select(-1)
		return
	for i in range(picker.item_count):
		if picker.get_item_text(i) == value:
			picker.select(i)
			break


func _update_org_rows() -> void:
	if region_row and region_label:
		region_row.visible = assigned_region != ""
		region_label.text = "Region: %s" % assigned_region
	if class_row and class_label:
		class_row.visible = assigned_class != ""
		class_label.text = "Class: %s" % assigned_class
	if region_button:
		region_button.visible = assigned_region == ""
	if class_button:
		class_button.visible = assigned_class == ""
		class_button.disabled = false


func _on_region_button_pressed() -> void:
	_popup_option_at_mouse(region_picker)
	if region_picker and region_picker.item_count == 0:
		emit_signal("assign_region_requested")


func _on_class_button_pressed() -> void:
	_popup_option_at_mouse(class_picker)
	if class_picker and class_picker.item_count == 0:
		emit_signal("assign_class_requested")


func _on_region_selected(index: int) -> void:
	if region_picker == null:
		return
	var choice := region_picker.get_item_text(index)
	if blocked_region != "" and choice.strip_edges() == blocked_region:
		assigned_region = ""
		_select_in_picker(region_picker, "")
	else:
		assigned_region = choice
	_update_org_rows()
	emit_signal("region_changed", assigned_region)


func _on_class_selected(index: int) -> void:
	if class_picker == null:
		return
	var choice := class_picker.get_item_text(index)
	if blocked_class != "" and choice.strip_edges() == blocked_class:
		assigned_class = ""
		_select_in_picker(class_picker, "")
	else:
		assigned_class = choice
	_update_org_rows()
	emit_signal("class_changed", assigned_class)


func _on_region_clear_pressed() -> void:
	assigned_region = ""
	_select_in_picker(region_picker, "")
	_update_org_rows()
	emit_signal("cleared_region")


func _on_class_clear_pressed() -> void:
	assigned_class = ""
	_select_in_picker(class_picker, "")
	_update_org_rows()
	emit_signal("cleared_class")


func _filtered_regions() -> Array:
	if blocked_region == "":
		return _last_regions
	var filtered: Array = []
	for r in _last_regions:
		if str(r).strip_edges() == blocked_region:
			continue
		filtered.append(r)
	return filtered


func _filtered_classes() -> Array:
	if blocked_class == "":
		return _last_classes
	var filtered: Array = []
	for c in _last_classes:
		if str(c).strip_edges() == blocked_class:
			continue
		filtered.append(c)
	return filtered


func _update_buttons() -> void:
	if region_button:
		region_button.disabled = _filtered_regions().is_empty()
	if class_button:
		class_button.disabled = false


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
