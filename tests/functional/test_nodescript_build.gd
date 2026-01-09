@tool
extends RefCounted

# Functional tests: build a script from blank toward a player-like layout using NodeScriptPanel + NodeScriptSync.

const NodeScriptPanelScene = preload("res://addons/nodescript/editor/nodescript_panel.tscn")

var _panel_instance: Control
var _failures := 0
var _temp_dir := "res://tests/temp/functional"
var _script_path := _temp_dir.path_join("build_test.gd")
var _tres_path := _temp_dir.path_join("build_test.nodescript.tres")

func get_failure_count() -> int:
	return _failures

func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("    [FAIL] %s" % msg)

func assert_eq(a, b, msg: String = "") -> void:
	if a != b:
		_failures += 1
		print("    [FAIL] %s: expected '%s' got '%s'" % [msg, str(b), str(a)])

func before_each() -> void:
	_failures = 0
	_cleanup_files()

	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists(_temp_dir):
		dir.make_dir_recursive(_temp_dir)

	var f = FileAccess.open(_script_path, FileAccess.WRITE)
	if f:
		f.store_string("extends CharacterBody2D\n")
		f.close()

	var script_res = ResourceLoader.load(_script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if script_res == null:
		print("    [ERROR] Failed to load blank script at %s" % _script_path)
		return

	_panel_instance = NodeScriptPanelScene.instantiate()
	Engine.get_main_loop().root.add_child(_panel_instance)
	_panel_instance.set_target_script(script_res)

func after_each() -> void:
	if _panel_instance:
		if _panel_instance.is_inside_tree():
			_panel_instance.get_parent().remove_child(_panel_instance)
		_panel_instance.queue_free()
	_panel_instance = null
	_cleanup_files()

func _cleanup_files() -> void:
	if FileAccess.file_exists(_script_path):
		DirAccess.remove_absolute(_script_path)
	if FileAccess.file_exists(_tres_path):
		DirAccess.remove_absolute(_tres_path)

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	return txt

func _save_all() -> void:
	if _panel_instance == null:
		return
	if _panel_instance.sync:
		_panel_instance.sync.save()
	_panel_instance._apply_declarations_to_script()
	if _panel_instance.sync:
		_panel_instance.sync.save()
	if _panel_instance.active_script:
		ResourceSaver.save(_panel_instance.active_script, _script_path)

func test_01_nodescript_created_from_blank() -> void:
	assert_true(FileAccess.file_exists(_tres_path), "NodeScript resource was created")
	var tres_text := _read_text(_tres_path)
	assert_true(tres_text.find("script_class=\"NodeScriptResource\"") != -1, "TRES header exists")

func test_02_add_variable_health() -> void:
	var var_data = {"name": "health", "type": "int", "value": "100", "region": "", "class": ""}
	_panel_instance._on_variable_editor_submitted(var_data)
	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)

	assert_true(gd_text.find("var health: int = 100") != -1, "GD: health variable emitted")
	assert_true(tres_text.find("\"name\": \"health\"") != -1, "TRES: health variable present")

func test_03_add_signal_died() -> void:
	var sig_data = {"name": "died", "parameters": [], "region": "", "class": ""}
	_panel_instance._on_signal_editor_submitted(sig_data)
	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)

	assert_true(gd_text.find("signal died") != -1, "GD: signal died emitted")
	assert_true(tres_text.find("\"died\"") != -1, "TRES: signal key present")

func test_04_add_enum_state() -> void:
	var enum_data = {"name": "State", "values": ["IDLE", "RUN"], "region": "", "class": ""}
	_panel_instance._on_enum_editor_submitted(enum_data)
	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)

	assert_true(gd_text.find("enum State { IDLE, RUN }") != -1, "GD: enum State emitted")
	assert_true(tres_text.find("\"State\"") != -1, "TRES: enum entry present")
	assert_true(tres_text.find("IDLE") != -1 and tres_text.find("RUN") != -1, "TRES: enum values present")

func test_05_add_class_and_function() -> void:
	var cls_data = {"name": "Data", "extends": "Resource", "region": "", "class": ""}
	_panel_instance._on_class_editor_submitted(cls_data)

	# Add function inside the class by updating sync data and order map.
	var f_entry = {
		"name": "load",
		"parameters": [],
		"return_type": "void",
		"region": "",
		"class": "Data",
		"body": [ {"type": "pass", "text": "pass"}]
	}
	if not _panel_instance.sync.nodescript.body.has("order"):
		_panel_instance.sync.nodescript.body["order"] = {}
	var order_key := "Data|"
	if not _panel_instance.sync.nodescript.body["order"].has(order_key):
		_panel_instance.sync.nodescript.body["order"][order_key] = []
	_panel_instance.sync.nodescript.body["order"][order_key].append({
		"type": "function",
		"name": "load",
		"line": 1,
		"indent": 1
	})
	_panel_instance.sync.nodescript.body["functions"].append(f_entry)

	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)

	assert_true(gd_text.find("class Data extends Resource:") != -1, "GD: class Data emitted")
	assert_true(gd_text.find("func load() -> void:") != -1, "GD: func load emitted")
	assert_true(tres_text.find("\"name\": \"Data\"") != -1, "TRES: class Data entry")
	assert_true(tres_text.find("\"name\": \"load\"") != -1, "TRES: function load entry")

func test_06_reorder_variables() -> void:
	var var_health = {"name": "health", "type": "int", "value": "100", "region": "", "class": ""}
	var var_mana = {"name": "mana", "type": "int", "value": "50", "region": "", "class": ""}
	_panel_instance._on_variable_editor_submitted(var_health)
	_panel_instance._on_variable_editor_submitted(var_mana)

	# Reorder via order map so mana appears before health.
	if not _panel_instance.sync.nodescript.body.has("order"):
		_panel_instance.sync.nodescript.body["order"] = {}
	var root_key := "|"
	_panel_instance.sync.nodescript.body["order"][root_key] = [
		{"type": "variable", "name": "mana", "line": 1, "indent": 0},
		{"type": "variable", "name": "health", "line": 1, "indent": 0},
	]
	_panel_instance.sync.nodescript.body["variables"] = [
		var_mana,
		var_health,
	]

	_save_all()
	var gd_text := _read_text(_script_path)

	var mana_idx := gd_text.find("var mana")
	var health_idx := gd_text.find("var health")
	assert_true(mana_idx != -1 and health_idx != -1 and mana_idx < health_idx, "GD: mana appears before health")

func test_07_delete_signal() -> void:
	var sig_data = {"name": "died", "parameters": [], "region": "", "class": ""}
	_panel_instance._on_signal_editor_submitted(sig_data)
	_save_all()

	_panel_instance.current_signal_name = "died"
	_panel_instance.editing_signal = true
	_panel_instance._on_signal_editor_delete_requested()
	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)
	assert_true(gd_text.find("signal died") == -1, "GD: signal died removed")
	assert_true(tres_text.find("\"died\"") == -1, "TRES: signal died removed")


func test_08_region_and_move_variable() -> void:
	# Add region and move a variable into it, ensuring order map and script reflect the move.
	var region_name := "Stats"
	_panel_instance._on_region_editor_submitted({"name": region_name, "class": "", "region": ""})
	var var_data = {"name": "health", "type": "int", "value": "100", "region": region_name, "class": ""}
	_panel_instance._on_variable_editor_submitted(var_data)

	# Ensure region appears first, then variable inside region.
	_panel_instance.sync.set_scope_order("", "", [
		{"type": "region", "name": region_name, "line": 1, "indent": 0},
	])
	_panel_instance.sync.set_scope_order("", region_name, [
		{"type": "variable", "name": "health", "line": 2, "indent": 0},
	])

	_save_all()

	var gd_text := _read_text(_script_path)
	assert_true(gd_text.find("#region %s" % region_name) != -1, "GD: region header present")
	assert_true(gd_text.find("var health: int = 100") != -1, "GD: health inside region")


func test_09_class_in_region_and_update_var() -> void:
	var region_name := "Group"
	_panel_instance._on_region_editor_submitted({"name": region_name, "class": "", "region": ""})
	var cls_data = {"name": "Data", "extends": "Resource", "region": region_name, "class": ""}
	_panel_instance._on_class_editor_submitted(cls_data)

	# Add a variable and then update it.
	var var_data = {"name": "mana", "type": "int", "value": "50", "region": "", "class": ""}
	_panel_instance._on_variable_editor_submitted(var_data)
	_panel_instance.current_variable_name = "mana"
	_panel_instance.editing_variable = true
	var updated_var = {"name": "mana", "type": "int", "value": "75", "region": "", "class": ""}
	_panel_instance._on_variable_editor_submitted(updated_var)

	# Order: region then class
	_panel_instance.sync.set_scope_order("", "", [
		{"type": "region", "name": region_name, "line": 1, "indent": 0},
		{"type": "class", "name": "Data", "line": 2, "indent": 0},
		{"type": "variable", "name": "mana", "line": 3, "indent": 0},
	])

	_save_all()
	var gd_text := _read_text(_script_path)
	assert_true(gd_text.find("#region %s" % region_name) != -1, "GD: region present")
	assert_true(gd_text.find("class Data extends Resource:") != -1, "GD: class Data in region")
	assert_true(gd_text.find("var mana: int = 75") != -1, "GD: updated mana value")


func test_10_move_variable_out_of_region() -> void:
	# Start with a region and a variable inside it, then move variable back to root.
	var region_name := "Temp"
	_panel_instance._on_region_editor_submitted({"name": region_name, "class": "", "region": ""})
	var var_data = {"name": "armor", "type": "int", "value": "5", "region": region_name, "class": ""}
	_panel_instance._on_variable_editor_submitted(var_data)

	# Region order map
	_panel_instance.sync.set_scope_order("", "", [
		{"type": "region", "name": region_name, "line": 1, "indent": 0},
	])
	_panel_instance.sync.set_scope_order("", region_name, [
		{"type": "variable", "name": "armor", "line": 2, "indent": 0},
	])
	_save_all()

	# Move out of region: clear region field, place at root.
	var vars = _panel_instance.sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		if typeof(vars[i]) == TYPE_DICTIONARY and str(vars[i].get("name", "")) == "armor":
			vars[i]["region"] = ""
	_panel_instance.sync.nodescript.body["variables"] = vars
	_panel_instance.sync.set_scope_order("", "", [
		{"type": "variable", "name": "armor", "line": 1, "indent": 0},
	])

	_save_all()
	var gd_text := _read_text(_script_path)
	assert_true(gd_text.find("#region %s" % region_name) == -1 or gd_text.find("armor") < gd_text.find("#region %s" % region_name), "GD: armor moved to root")
	assert_true(gd_text.find("var armor: int = 5") != -1, "GD: armor exists after move")


func test_11_delete_variable_via_editor() -> void:
	var var_data = {"name": "temp_var", "type": "int", "value": "1", "region": "", "class": ""}
	_panel_instance._on_variable_editor_submitted(var_data)
	_save_all()

	_panel_instance.current_variable_name = "temp_var"
	_panel_instance.editing_variable = true
	_panel_instance._on_variable_editor_delete_requested()
	_save_all()

	var gd_text := _read_text(_script_path)
	var tres_text := _read_text(_tres_path)
	assert_true(gd_text.find("temp_var") == -1, "GD: temp_var removed")
	assert_true(tres_text.find("temp_var") == -1, "TRES: temp_var removed")
