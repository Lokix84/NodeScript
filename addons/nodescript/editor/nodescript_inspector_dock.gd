@tool
extends VBoxContainer

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const _NodeScriptSyncScript = preload("res://addons/nodescript/editor/nodescript_sync.gd")

# Preload editor scenes
const FunctionBodyEditorScene = preload("res://addons/nodescript/ui/function_body_editor.tscn")
const VariableEditorScene = preload("res://addons/nodescript/ui/variable_editor.tscn")
const SignalEditorScene = preload("res://addons/nodescript/ui/signal_editor.tscn")
const EnumEditorScene = preload("res://addons/nodescript/ui/enum_editor.tscn")
const RegionEditorScene = preload("res://addons/nodescript/ui/region_editor.tscn")
const ClassEditorScene = preload("res://addons/nodescript/ui/class_editor.tscn")
const RootMetaEditorScene = preload("res://addons/nodescript/ui/root_meta_editor.tscn")

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	anchor_right = 1.0
	anchor_bottom = 1.0

var editor_plugin: EditorPlugin
var sync
var active_script: Script

# Signals
signal tree_refresh_requested

# Editor panels
var function_body_editor
var variable_editor
var signal_editor
var enum_editor
var region_editor
var class_editor
var root_meta_editor
var blank_editor

# State tracking
var selected_function_index: int = -1
var creating_signal: bool = false
var creating_variable: bool = false
var creating_enum: bool = false
var creating_region: bool = false
var creating_class: bool = false
var editing_signal: bool = false
var editing_variable: bool = false
var editing_enum: bool = false
var editing_region: bool = false
var editing_class: bool = false
var current_signal_name: String = ""
var current_variable_name: String = ""
var current_enum_name: String = ""
var current_region_name: String = ""
var current_class_name: String = ""

# UI
var editor_container: ScrollContainer
var no_selection_label: Label

func _ready() -> void:
	# Container for editors with scrolling
	editor_container = ScrollContainer.new()
	editor_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(editor_container)
	
	# Inner VBox
	var inner_vbox = VBoxContainer.new()
	inner_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_container.add_child(inner_vbox)
	
	# No selection message
	no_selection_label = Label.new()
	no_selection_label.text = "Select an item to edit"
	no_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner_vbox.add_child(no_selection_label)
	
	_setup_editors(inner_vbox)
	_apply_responsive_layout_to_editors()


func set_editor_plugin(plugin: EditorPlugin) -> void:
	editor_plugin = plugin


func _setup_editors(parent: VBoxContainer) -> void:
	# Load real editor scenes
	function_body_editor = FunctionBodyEditorScene.instantiate()
	function_body_editor.visible = false
	function_body_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(function_body_editor)
	
	variable_editor = VariableEditorScene.instantiate()
	variable_editor.visible = false
	variable_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(variable_editor)
	
	signal_editor = SignalEditorScene.instantiate()
	signal_editor.visible = false
	signal_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(signal_editor)
	
	enum_editor = EnumEditorScene.instantiate()
	enum_editor.visible = false
	enum_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(enum_editor)
	
	region_editor = RegionEditorScene.instantiate()
	region_editor.visible = false
	region_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(region_editor)
	
	class_editor = ClassEditorScene.instantiate()
	class_editor.visible = false
	class_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(class_editor)
	
	root_meta_editor = RootMetaEditorScene.instantiate()
	root_meta_editor.visible = false
	root_meta_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(root_meta_editor)

	blank_editor = VBoxContainer.new()
	blank_editor.visible = false
	blank_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var blank_label = Label.new()
	blank_label.text = "Blank Line"
	blank_label.theme_type_variation = &"panel_header_text"
	blank_editor.add_child(blank_label)
	var count_row = HBoxContainer.new()
	count_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count_label = Label.new()
	count_label.text = "Count"
	count_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	count_row.add_child(count_label)
	var count_spin = SpinBox.new()
	count_spin.name = "BlankCountSpin"
	count_spin.min_value = 1
	count_spin.max_value = 50
	count_spin.step = 1
	count_spin.allow_greater = true
	count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_spin)
	blank_editor.add_child(count_row)
	var blank_buttons = HBoxContainer.new()
	blank_buttons.alignment = BoxContainer.ALIGNMENT_END
	var blank_save = Button.new()
	blank_save.text = "Save"
	blank_save.pressed.connect(_on_blank_save_pressed)
	blank_buttons.add_child(blank_save)
	blank_editor.add_child(blank_buttons)
	parent.add_child(blank_editor)
	
	# Connect signals
	_connect_editor_signals()


func _connect_editor_signals() -> void:
	if variable_editor:
		if variable_editor.has_signal("delete_requested"):
			variable_editor.delete_requested.connect(_on_variable_editor_delete_requested)
		if variable_editor.has_signal("submitted"):
			variable_editor.submitted.connect(_on_variable_editor_submitted)
	
	if signal_editor:
		if signal_editor.has_signal("delete_requested"):
			signal_editor.delete_requested.connect(_on_signal_editor_delete_requested)
		if signal_editor.has_signal("submitted"):
			signal_editor.submitted.connect(_on_signal_editor_submitted)
	
	if enum_editor:
		if enum_editor.has_signal("delete_requested"):
			enum_editor.delete_requested.connect(_on_enum_editor_delete_requested)
		if enum_editor.has_signal("submitted"):
			enum_editor.submitted.connect(_on_enum_editor_submitted)
	
	if region_editor:
		if region_editor.has_signal("delete_requested"):
			region_editor.delete_requested.connect(_on_region_editor_delete_requested)
		if region_editor.has_signal("submitted"):
			region_editor.submitted.connect(_on_region_editor_submitted)
	
	if class_editor:
		if class_editor.has_signal("delete_requested"):
			class_editor.delete_requested.connect(_on_class_editor_delete_requested)
		if class_editor.has_signal("submitted"):
			class_editor.submitted.connect(_on_class_editor_submitted)
	
	if function_body_editor:
		if function_body_editor.has_signal("update_requested"):
			function_body_editor.update_requested.connect(_on_function_update_requested)
		if function_body_editor.has_signal("delete_requested"):
			function_body_editor.delete_requested.connect(_on_function_delete_requested)
	
	if root_meta_editor:
		if root_meta_editor.has_signal("submitted"):
			root_meta_editor.submitted.connect(_on_root_meta_submitted)


func load_script(script: Script) -> void:
	if not script:
		_hide_all_editors()
		return
	
	active_script = script
	
	if not sync:
		sync = _NodeScriptSyncScript.new()
	sync.load_for_script(script)
	if not sync.nodescript:
		_hide_all_editors()
		return
	
	_hide_all_editors()


func show_item_editor(item_type: String, item_name: String, item_data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	match item_type:
		"function":
			var func_index = item_data.get("index", -1)
			if func_index >= 0:
				_show_function_editor(func_index)
		"variable":
			_show_existing_variable(item_name)
		"signal":
			_show_existing_signal(item_name)
		"enum":
			_show_existing_enum(item_name)
		"region":
			_show_region_editor_for(item_name)
		"class":
			_show_class_editor_for(item_name)
		"script":
			_show_root_meta_editor()
		"blank":
			_show_blank_editor(item_data)
		_:
			_hide_all_editors()


func _hide_all_editors() -> void:
	no_selection_label.visible = true
	if function_body_editor:
		function_body_editor.visible = false
	if variable_editor:
		variable_editor.visible = false
	if signal_editor:
		signal_editor.visible = false
	if enum_editor:
		enum_editor.visible = false
	if region_editor:
		region_editor.visible = false
	if class_editor:
		class_editor.visible = false
	if root_meta_editor:
		root_meta_editor.visible = false
	if blank_editor:
		blank_editor.visible = false


func _show_function_editor(func_index: int) -> void:
	if not function_body_editor or not sync or not sync.nodescript:
		return
	
	var methods: Array = sync.nodescript.body.get("functions", [])
	if func_index < 0 or func_index >= methods.size():
		return
	
	var method = methods[func_index]
	if typeof(method) != TYPE_DICTIONARY:
		return
	
	selected_function_index = func_index
	_hide_all_editors()
	function_body_editor.visible = true

	# Use the function body's public API
	if function_body_editor.has_method("set_method"):
		function_body_editor.set_method(method)


func _show_existing_variable(var_name: String) -> void:
	if not variable_editor or not sync or not sync.nodescript:
		return
	
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == var_name:
			editing_variable = true
			creating_variable = false
			current_variable_name = var_name
			
			_hide_all_editors()
			variable_editor.visible = true
			
			if variable_editor.has_method("set_region_class_lists"):
				variable_editor.set_region_class_lists(_available_regions(), _available_classes())
			if variable_editor.has_method("show_variable"):
				variable_editor.show_variable(entry)
			return


func _show_existing_signal(signal_name: String) -> void:
	if not signal_editor or not sync or not sync.nodescript:
		return
	
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	if not signals_dict.has(signal_name):
		return
	
	var entry = signals_dict[signal_name]
	editing_signal = true
	creating_signal = false
	current_signal_name = signal_name
	
	_hide_all_editors()
	signal_editor.visible = true
	
	if signal_editor.has_method("set_region_class_lists"):
		signal_editor.set_region_class_lists(_available_regions(), _available_classes())
	if signal_editor.has_method("show_signal"):
		signal_editor.show_signal(signal_name, entry)


func _show_existing_enum(enum_name: String) -> void:
	if not enum_editor or not sync or not sync.nodescript:
		return
	
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	if not enums_dict.has(enum_name):
		return
	
	var entry = enums_dict[enum_name]
	editing_enum = true
	creating_enum = false
	current_enum_name = enum_name
	
	_hide_all_editors()
	enum_editor.visible = true
	
	if enum_editor.has_method("set_region_class_lists"):
		enum_editor.set_region_class_lists(_available_regions(), _available_classes())
	# Expect enum editor to accept name and values array
	var values_data = entry.get("values", [])
	if typeof(values_data) == TYPE_DICTIONARY:
		values_data = values_data.keys()
	if enum_editor.has_method("show_enum"):
		enum_editor.show_enum(enum_name, values_data)


func _show_region_editor_for(region_name: String) -> void:
	if not region_editor or not sync or not sync.nodescript:
		return
	
	var regions_array: Array = sync.nodescript.body.get("regions", [])
	for entry in regions_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == region_name:
			editing_region = true
			creating_region = false
			current_region_name = region_name
			
			_hide_all_editors()
			region_editor.visible = true
			
			if region_editor.has_method("show_region"):
				region_editor.show_region(entry)
			return


func _show_class_editor_for(klass_name: String) -> void:
	if not class_editor or not sync or not sync.nodescript:
		return
	
	var classes_array: Array = sync.nodescript.body.get("classes", [])
	for entry in classes_array:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == klass_name:
			editing_class = true
			creating_class = false
			current_class_name = klass_name
			
			_hide_all_editors()
			class_editor.visible = true
			
			if class_editor.has_method("show_class"):
				class_editor.show_class(entry)
			return


func _show_root_meta_editor() -> void:
	if not root_meta_editor or not sync or not sync.nodescript:
		return
	
	_hide_all_editors()
	root_meta_editor.visible = true
	
	if root_meta_editor.has_method("load_meta"):
		root_meta_editor.load_meta(sync.nodescript.meta)


# Make the inspector responsive: wrap labels and allow controls to shrink with the dock.
func _apply_responsive_layout_to_editors() -> void:
	var targets: Array[Node] = [
		function_body_editor,
		variable_editor,
		signal_editor,
		enum_editor,
		region_editor,
		class_editor,
		root_meta_editor
	]
	for target in targets:
		if target:
			_apply_responsive_layout(target)


func _apply_responsive_layout(root: Node) -> void:
	for child in root.get_children():
		_apply_responsive_layout(child)
		if child is Label:
			var label := child as Label
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif child is LineEdit or child is TextEdit:
			var editable := child as Control
			editable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif child is Button or child is CheckBox or child is OptionButton or child is TextureButton:
			var btn := child as Control
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _available_regions() -> Array[String]:
	if not sync or not sync.nodescript:
		return []
	var names: Array[String] = []
	var regions: Array = sync.nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) == TYPE_DICTIONARY:
			names.append(str(entry.get("name", "")))
	return names


func _available_classes() -> Array[String]:
	if not sync or not sync.nodescript:
		return []
	var names: Array[String] = []
	var classes: Array = sync.nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) == TYPE_DICTIONARY:
			names.append(str(entry.get("name", "")))
	return names


func _apply_declarations_to_script() -> void:
	if not sync or not active_script:
		return
	active_script.source_code = sync.emit_declarations()
	# Notify plugin to refresh tree dock
	tree_refresh_requested.emit()


# Signal handlers matching main panel
func _on_variable_editor_delete_requested() -> void:
	if not editing_variable or current_variable_name.is_empty():
		return
	if not sync or not sync.nodescript:
		return
	
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	for i in range(variables_array.size()):
		var entry = variables_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_variable_name:
			variables_array.remove_at(i)
			break
	
	sync.nodescript.body["variables"] = variables_array
	sync.save()
	current_variable_name = ""
	editing_variable = false
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_variable_editor_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	var variables_array: Array = sync.nodescript.body.get("variables", [])
	var desired_name: String = str(data.get("name", "")).strip_edges()
	
	# Find existing or add new
	var did_update = false
	if editing_variable and not current_variable_name.is_empty():
		for i in range(variables_array.size()):
			if typeof(variables_array[i]) == TYPE_DICTIONARY and str(variables_array[i].get("name", "")) == current_variable_name:
				variables_array[i] = data.duplicate(true)
				did_update = true
				break
	
	if not did_update:
		variables_array.append(data.duplicate(true))
	
	sync.nodescript.body["variables"] = variables_array
	sync.save()
	_apply_declarations_to_script()


func _on_signal_editor_delete_requested() -> void:
	if not editing_signal or current_signal_name.is_empty():
		return
	if not sync or not sync.nodescript:
		return
	
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	signals_dict.erase(current_signal_name)
	sync.nodescript.body["signals"] = signals_dict
	sync.save()
	current_signal_name = ""
	editing_signal = false
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_signal_editor_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	var signals_dict: Dictionary = sync.nodescript.body.get("signals", {})
	var signal_name: String = str(data.get("name", ""))
	
	if editing_signal and not current_signal_name.is_empty() and current_signal_name != signal_name:
		signals_dict.erase(current_signal_name)
	
	signals_dict[signal_name] = {
		"parameters": data.get("parameters", []),
		"region": data.get("region", ""),
		"class": data.get("class", "")
	}
	
	sync.nodescript.body["signals"] = signals_dict
	sync.save()
	current_signal_name = signal_name
	_apply_declarations_to_script()


func _on_enum_editor_delete_requested() -> void:
	if not editing_enum or current_enum_name.is_empty():
		return
	if not sync or not sync.nodescript:
		return
	
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	enums_dict.erase(current_enum_name)
	sync.nodescript.body["enums"] = enums_dict
	sync.save()
	current_enum_name = ""
	editing_enum = false
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_enum_editor_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	var enums_dict: Dictionary = sync.nodescript.body.get("enums", {})
	var enum_name: String = str(data.get("name", ""))
	
	if editing_enum and not current_enum_name.is_empty() and current_enum_name != enum_name:
		enums_dict.erase(current_enum_name)
	
	enums_dict[enum_name] = data.duplicate(true)
	sync.nodescript.body["enums"] = enums_dict
	sync.save()
	current_enum_name = enum_name
	_apply_declarations_to_script()


func _on_region_editor_delete_requested() -> void:
	if not editing_region or current_region_name.is_empty():
		return
	if not sync or not sync.nodescript:
		return
	
	var regions_array: Array = sync.nodescript.body.get("regions", [])
	for i in range(regions_array.size()):
		var entry = regions_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_region_name:
			regions_array.remove_at(i)
			break
	
	sync.nodescript.body["regions"] = regions_array
	sync.save()
	current_region_name = ""
	editing_region = false
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_region_editor_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	var regions_array: Array = sync.nodescript.body.get("regions", [])
	var region_name: String = str(data.get("name", ""))
	
	var did_update = false
	if editing_region and not current_region_name.is_empty():
		for i in range(regions_array.size()):
			if typeof(regions_array[i]) == TYPE_DICTIONARY and str(regions_array[i].get("name", "")) == current_region_name:
				regions_array[i] = data.duplicate(true)
				did_update = true
				break
	
	if not did_update:
		regions_array.append(data.duplicate(true))
	
	sync.nodescript.body["regions"] = regions_array
	sync.save()
	current_region_name = region_name
	_apply_declarations_to_script()


func _on_class_editor_delete_requested() -> void:
	if not editing_class or current_class_name.is_empty():
		return
	if not sync or not sync.nodescript:
		return
	
	var classes_array: Array = sync.nodescript.body.get("classes", [])
	for i in range(classes_array.size()):
		var entry = classes_array[i]
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == current_class_name:
			classes_array.remove_at(i)
			break
	
	sync.nodescript.body["classes"] = classes_array
	sync.save()
	current_class_name = ""
	editing_class = false
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_class_editor_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	var classes_array: Array = sync.nodescript.body.get("classes", [])
	var klass_name: String = str(data.get("name", ""))
	
	var did_update = false
	if editing_class and not current_class_name.is_empty():
		for i in range(classes_array.size()):
			if typeof(classes_array[i]) == TYPE_DICTIONARY and str(classes_array[i].get("name", "")) == current_class_name:
				classes_array[i] = data.duplicate(true)
				did_update = true
				break
	
	if not did_update:
		classes_array.append(data.duplicate(true))
	
	sync.nodescript.body["classes"] = classes_array
	sync.save()
	current_class_name = klass_name
	_apply_declarations_to_script()


func _on_function_update_requested(method: Dictionary) -> void:
	if not sync or not sync.nodescript or selected_function_index < 0:
		return
	
	var methods: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index >= methods.size():
		return
	
	methods[selected_function_index] = method.duplicate(true)
	sync.nodescript.body["functions"] = methods
	sync.save()
	_apply_declarations_to_script()


func _on_function_delete_requested() -> void:
	if not sync or not sync.nodescript or selected_function_index < 0:
		return
	
	var methods: Array = sync.nodescript.body.get("functions", [])
	if selected_function_index >= methods.size():
		return
	
	methods.remove_at(selected_function_index)
	sync.nodescript.body["functions"] = methods
	sync.save()
	selected_function_index = -1
	_apply_declarations_to_script()
	_hide_all_editors()


func _on_root_meta_submitted(data: Dictionary) -> void:
	if not sync or not sync.nodescript:
		return
	
	sync.nodescript.meta = data.duplicate(true)
	sync.save()
	_apply_declarations_to_script()


func _clear_editors() -> void:
	_hide_all_editors()
	no_selection_label.visible = true
	active_script = null
	sync = null

func _show_blank_editor(data: Dictionary) -> void:
	if not blank_editor:
		return
	_hide_all_editors()
	blank_editor.visible = true
	no_selection_label.visible = false
	var count_spin: SpinBox = blank_editor.get_node_or_null("BlankCountSpin")
	if count_spin:
		count_spin.value = data.get("count", 1)
		count_spin.set_meta("meta_data", data)


func _on_blank_save_pressed() -> void:
	var count_spin: SpinBox = blank_editor.get_node_or_null("BlankCountSpin")
	if not count_spin or not sync or not sync.nodescript:
		return
	var metadata: Dictionary = count_spin.get_meta("meta_data", {})
	if metadata.is_empty():
		return
	var target_count := int(max(1, count_spin.value))
	var region := str(metadata.get("region", ""))
	var cls := str(metadata.get("class", ""))
	var name := str(metadata.get("name", ""))
	var order: Dictionary = sync.nodescript.body.get("order", {})
	var key := "%s|%s" % [cls, region]
	if not order.has(key):
		return
	var updated: Array = []
	for entry in order[key]:
		if typeof(entry) != TYPE_DICTIONARY:
			updated.append(entry)
			continue
		if str(entry.get("type", "")) == "blank" and str(entry.get("name", "")) == name:
			entry["count"] = target_count
		updated.append(entry)
	order[key] = updated
	sync.nodescript.body["order"] = order
	sync.save()
	tree_refresh_requested.emit()
