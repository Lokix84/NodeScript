@tool
extends Control

const NodeScriptPanelScene = preload("res://addons/nodescript/editor/nodescript_panel.tscn")

@onready var tree: Tree = $Margin/VBox/HSplit/TreePanel/Tree
@onready var script_view: RichTextLabel = $Margin/VBox/HSplit/RightSplit/OutputsSplit/ScriptPanel/ScriptView
@onready var expected_view: RichTextLabel = $Margin/VBox/HSplit/RightSplit/OutputsSplit/ExpectedPanel/ExpectedView
@onready var log_view: RichTextLabel = $Margin/VBox/HSplit/RightSplit/LogPanel/LogView
@onready var play_pause_btn: Button = $Margin/VBox/Toolbar/PlayPause
@onready var step_btn: Button = $Margin/VBox/Toolbar/Step
@onready var reset_btn: Button = $Margin/VBox/Toolbar/Reset
@onready var speed_slider: HSlider = $Margin/VBox/Toolbar/Speed
@onready var status_label: Label = $Margin/VBox/Toolbar/Status

var panel: Control
var current_script: Script
var running: bool = false
var delay_time: float = 0.5
var step_index: int = 0
var run_token: int = 0
var temp_dir := "res://tests/temp/demo"
var script_path := temp_dir.path_join("visual_demo.gd")
var tres_path := temp_dir.path_join("visual_demo.nodescript.tres")

var steps: Array = []

func _ready() -> void:
	_init_ui()
	_init_panel()
	_prepare_steps()
	_connect_buttons()
	_reset_run()


func _init_ui() -> void:
	tree.hide_root = true
	log_view.bbcode_enabled = true
	script_view.bbcode_enabled = true
	speed_slider.value = delay_time
	_update_status("Idle")


func _init_panel() -> void:
	panel = NodeScriptPanelScene.instantiate()
	if panel == null:
		_log("[color=red]Failed to instantiate NodeScriptPanel[/color]")
		return
	add_child(panel)
	panel.hide() # Keep full UI hidden; reuse its Tree for display.
	var panel_tree = panel.find_child("Tree", true, false)
	if panel_tree and panel_tree is Tree:
		panel_tree.get_parent().remove_child(panel_tree)
		$Margin/VBox/HSplit/TreePanel.add_child(panel_tree)
		tree = panel_tree
		tree.hide_root = true
		# Use the same theme as the panel so icons (EditorIcons) show up.
		tree.theme = panel.get_theme()


func _connect_buttons() -> void:
	play_pause_btn.pressed.connect(_on_play_pause)
	step_btn.pressed.connect(_on_step)
	reset_btn.pressed.connect(_on_reset)
	speed_slider.value_changed.connect(_on_speed_changed)


func _prepare_steps() -> void:
	steps = [
		{"name": "Create blank script", "fn": Callable(self, "_step_create_blank")},
		{"name": "Add variable health", "fn": Callable(self, "_step_add_health")},
		{"name": "Add signal died", "fn": Callable(self, "_step_add_signal")},
		{"name": "Update signal parameter", "fn": Callable(self, "_step_update_signal_param")},
		{"name": "Add enum State", "fn": Callable(self, "_step_add_enum")},
		{"name": "Add class Data + func load", "fn": Callable(self, "_step_add_class_func")},
		{"name": "Add const MAX_HP", "fn": Callable(self, "_step_add_const")},
		{"name": "Edit health value", "fn": Callable(self, "_step_edit_health")},
		{"name": "Reorder variables", "fn": Callable(self, "_step_reorder_vars")},
		{"name": "Add region and move items", "fn": Callable(self, "_step_add_region_and_move")},
		{"name": "Insert blank spacers", "fn": Callable(self, "_step_insert_blank_spacing")},
		{"name": "Move const to top", "fn": Callable(self, "_step_move_const_top")},
		{"name": "Delete signal died", "fn": Callable(self, "_step_delete_signal")}
	]


func _on_play_pause() -> void:
	running = not running
	play_pause_btn.text = "Pause" if running else "Play"
	if running:
		await _run_steps()


func _on_step() -> void:
	if running:
		return
	await _run_single_step()


func _on_reset() -> void:
	running = false
	play_pause_btn.text = "Play"
	_reset_run()


func _on_speed_changed(value: float) -> void:
	delay_time = value


func _reset_run() -> void:
	run_token += 1
	running = false
	play_pause_btn.text = "Play"
	_clear_log()
	if tree:
		tree.clear()
	if script_view:
		script_view.bbcode_text = "[code][/code]"
	_update_status("Idle")
	# Clear panel state and selection immediately.
	if panel and panel.has_method("set_target_script"):
		panel.set_target_script(null)
	if panel and panel.sync and panel.sync.nodescript:
		panel.sync.nodescript.body = {}
		panel.sync.nodescript.meta = {}
		panel.sync.save()
	# Let any in-flight coroutines see the new token and exit.
	await get_tree().process_frame
	_cleanup_files()
	_setup_blank_script()
	step_index = 0
	_update_tree()
	_update_script_view()


func _run_steps() -> void:
	var token := run_token
	while step_index < steps.size():
		if token != run_token:
			return
		var step = steps[step_index]
		_update_status("Running: %s" % step.get("name", ""))
		_log("[color=cyan]Step %d: %s[/color]" % [step_index + 1, step.get("name", "")])
		step.fn.call()
		_save_all()
		_update_tree()
		_update_script_view()
		step_index += 1

		if step_index >= steps.size():
			break

		if running:
			await get_tree().create_timer(delay_time).timeout
		else:
			_update_status("Paused")
			break

	if step_index >= steps.size():
		_update_status("Done")
		running = false
		play_pause_btn.text = "Play"


func _run_single_step() -> void:
	var token := run_token
	if step_index >= steps.size():
		_update_status("Done")
		return
	if token != run_token:
		return
	var step = steps[step_index]
	_update_status("Running: %s" % step.get("name", ""))
	_log("[color=cyan]Step %d: %s[/color]" % [step_index + 1, step.get("name", "")])
	step.fn.call()
	_save_all()
	_update_tree()
	_update_script_view()
	step_index += 1
	if step_index >= steps.size():
		_update_status("Done")
	else:
		_update_status("Paused after step")


func _setup_blank_script() -> void:
	if panel == null:
		return
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists(temp_dir):
		dir.make_dir_recursive(temp_dir)
	var f = FileAccess.open(script_path, FileAccess.WRITE)
	if f:
		f.store_string("") # truly blank start
		f.close()
	current_script = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if current_script == null:
		_log("[color=red]Failed to load blank script[/color]")
		return
	panel.set_target_script(current_script)
	_save_all()


func _save_all() -> void:
	if panel == null or panel.sync == null or panel.active_script == null:
		return
	var full_source = panel.sync.emit_declarations(true)
	panel.active_script.source_code = full_source
	# Write script via FileAccess to avoid parse/save errors mid-demo.
	var f = FileAccess.open(script_path, FileAccess.WRITE)
	if f:
		f.store_string(full_source)
		f.close()
	else:
		_log("[color=red]Failed to write script file[/color]")
	panel.sync.save()


func _cleanup_files() -> void:
	if FileAccess.file_exists(script_path):
		DirAccess.remove_absolute(script_path)
	if FileAccess.file_exists(tres_path):
		DirAccess.remove_absolute(tres_path)


func _update_tree() -> void:
	if panel and panel.has_method("_refresh_tree"):
		panel._refresh_tree()


func _update_script_view() -> void:
	var text := ""
	if FileAccess.file_exists(script_path):
		var f = FileAccess.open(script_path, FileAccess.READ)
		text = f.get_as_text()
		f.close()
	# Compare against expected to highlight mismatches.
	var expected := _expected_output_for_step(step_index)
	if expected_view:
		expected_view.text = expected
	if script_view:
		script_view.clear()
		script_view.append_text(_format_diff_bbcode(text, expected))
	if expected != "":
		if _normalize_script(text) != _normalize_script(expected):
			_log("[color=red]Output differs from expected[/color]")
		else:
			_log("[color=green]Output matches expected[/color]")


func _clear_log() -> void:
	log_view.clear()


func _log(msg: String) -> void:
	log_view.append_text(msg + "\n")
	log_view.scroll_to_line(log_view.get_line_count() - 1)


func _update_status(text: String) -> void:
	status_label.text = text


# --- Step implementations ---

func _step_create_blank() -> void:
	panel.set_target_script(current_script)


func _step_add_health() -> void:
	var var_data = {"name": "health", "type": "int", "value": "100", "region": "", "class": ""}
	panel._on_variable_editor_submitted(var_data)


func _step_add_signal() -> void:
	var sig_data = {"name": "died", "parameters": [], "region": "", "class": ""}
	panel._on_signal_editor_submitted(sig_data)


func _step_update_signal_param() -> void:
	var sig_name := _find_signal_name()
	if sig_name == "":
		_step_add_signal()
		sig_name = _find_signal_name()
	if sig_name != "":
		panel.current_signal_name = sig_name
		panel.editing_signal = true
		var sig_data = {"name": sig_name, "parameters": [{"name": "amount", "type": "int"}], "region": "", "class": ""}
		panel._on_signal_editor_submitted(sig_data)


func _step_add_enum() -> void:
	var enum_data = {"name": "State", "values": ["IDLE", "RUN"], "region": "", "class": ""}
	panel._on_enum_editor_submitted(enum_data)


func _step_add_class_func() -> void:
	var cls_data = {"name": "Data", "extends": "Resource", "region": "", "class": ""}
	panel._on_class_editor_submitted(cls_data)

	var fn_entry = {
		"name": "load",
		"parameters": [],
		"return_type": "void",
		"region": "",
		"class": "Data",
		"body": [ {"type": "pass", "text": "pass"}]
	}
	if not panel.sync.nodescript.body.has("order"):
		panel.sync.nodescript.body["order"] = {}
	var order_key := "Data|"
	if not panel.sync.nodescript.body["order"].has(order_key):
		panel.sync.nodescript.body["order"][order_key] = []
	panel.sync.nodescript.body["order"][order_key].append({
		"type": "function",
		"name": "load",
		"line": 1,
		"indent": 1
	})
	panel.sync.nodescript.body["functions"].append(fn_entry)


func _step_add_const() -> void:
	var const_data = {"name": "MAX_HP", "type": "int", "value": "999", "region": "", "class": "", "const": true}
	panel._on_variable_editor_submitted(const_data)


func _step_edit_health() -> void:
	# Update health value to demonstrate edit.
	if panel == null or panel.sync == null or panel.sync.nodescript == null:
		return
	var vars: Array = panel.sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		if typeof(vars[i]) == TYPE_DICTIONARY and str(vars[i].get("name", "")) == "health":
			vars[i]["value"] = "150"
	panel.sync.nodescript.body["variables"] = vars


func _step_reorder_vars() -> void:
	if not _has_variable("mana"):
		var var_mana = {"name": "mana", "type": "int", "value": "50", "region": "", "class": ""}
		panel._on_variable_editor_submitted(var_mana)

	if not panel.sync.nodescript.body.has("order"):
		panel.sync.nodescript.body["order"] = {}
	var root_key := "|"
	var existing_order: Array = panel.sync.emit_scope_order("", "")
	var kept: Array = []
	for entry in existing_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) != "variable":
			kept.append(entry)

	var reordered_vars := [
		{"type": "variable", "name": "health", "line": 1, "indent": 0},
		{"type": "variable", "name": "mana", "line": 1, "indent": 0},
		{"type": "variable", "name": "MAX_HP", "line": 1, "indent": 0}
	]
	panel.sync.nodescript.body["order"][root_key] = reordered_vars + kept


func _step_add_region_and_move() -> void:
	var region_name := "Stats"
	panel._on_region_editor_submitted({"name": region_name, "class": "", "region": ""})
	var vars: Array = panel.sync.nodescript.body.get("variables", [])
	for i in range(vars.size()):
		if typeof(vars[i]) == TYPE_DICTIONARY and str(vars[i].get("name", "")) == "health":
			vars[i]["region"] = region_name
	panel.sync.nodescript.body["variables"] = vars

	# Rebuild root order explicitly to avoid duplicates and ensure expected ordering.
	var root_order: Array = []
	# Variables except health (now in region); prefer const first.
	var var_names: Array[String] = []
	for v in panel.sync.nodescript.body.get("variables", []):
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if str(v.get("region", "")) != "":
			continue
		var_names.append(str(v.get("name", "")))
	if "MAX_HP" in var_names:
		root_order.append({"type": "variable", "name": "MAX_HP", "line": 1, "indent": 0})
	if "mana" in var_names:
		root_order.append({"type": "variable", "name": "mana", "line": 1, "indent": 0})
	for n in var_names:
		if n == "MAX_HP" or n == "mana":
			continue
		root_order.append({"type": "variable", "name": n, "line": 1, "indent": 0})

	# Signals (from body)
	var signals: Dictionary = panel.sync.nodescript.body.get("signals", {})
	for sig_name in signals.keys():
		root_order.append({"type": "signal", "name": str(sig_name), "line": 1, "indent": 0})

	# Enums (from body)
	var enums: Dictionary = panel.sync.nodescript.body.get("enums", {})
	for enum_name in enums.keys():
		root_order.append({"type": "enum", "name": str(enum_name), "line": 1, "indent": 0})

	# Region before classes
	root_order.append({"type": "region", "name": region_name, "line": 1, "indent": 0})

	# Classes (from body)
	var classes: Array = panel.sync.nodescript.body.get("classes", [])
	for cls in classes:
		if typeof(cls) != TYPE_DICTIONARY:
			continue
		root_order.append({"type": "class", "name": str(cls.get("name", "")), "line": 1, "indent": 0})

	panel.sync.nodescript.body["order"]["|"] = root_order

	panel.sync.set_scope_order("", region_name, [
		{"type": "variable", "name": "health", "line": 1, "indent": 0},
	])


func _step_insert_blank_spacing() -> void:
	if not panel.sync.nodescript.body.has("order"):
		panel.sync.nodescript.body["order"] = {}
	var root_key := "|"
	var current_order: Array = panel.sync.emit_scope_order("", "")
	var with_blanks: Array = []
	for entry in current_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		with_blanks.append(entry)
		var kind := str(entry.get("type", ""))
		if kind == "signal" or kind == "enum" or kind == "region" or kind == "class":
			with_blanks.append({"type": "blank", "name": "", "line": int(entry.get("line", 0)), "indent": int(entry.get("indent", 0))})
	panel.sync.set_scope_order("", "", with_blanks)


func _step_move_const_top() -> void:
	if not panel.sync.nodescript.body.has("order"):
		panel.sync.nodescript.body["order"] = {}
	var root_key := "|"
	var current_order: Array = panel.sync.emit_scope_order("", "")
	var filtered: Array = []
	for entry in current_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) == "variable" and str(entry.get("name", "")) == "MAX_HP":
			continue
		filtered.append(entry)
	# Prepend MAX_HP as const at top
	filtered.push_front({"type": "variable", "name": "MAX_HP", "line": 1, "indent": 0})
	panel.sync.nodescript.body["order"][root_key] = filtered


func _step_delete_signal() -> void:
	var sig_name := _find_signal_name()
	if sig_name == "":
		var sig_data = {"name": "died", "parameters": [], "region": "", "class": ""}
		panel._on_signal_editor_submitted(sig_data)
		sig_name = _find_signal_name()
	if sig_name != "":
		panel.current_signal_name = sig_name
		panel.editing_signal = true
		panel._on_signal_editor_delete_requested()


func _has_variable(name: String) -> bool:
	if panel == null or panel.sync == null or panel.sync.nodescript == null:
		return false
	var vars: Array = panel.sync.nodescript.body.get("variables", [])
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if str(v.get("name", "")) == name:
			return true
	return false


func _find_signal_name() -> String:
	if panel == null or panel.sync == null or panel.sync.nodescript == null:
		return ""
	var sigs: Dictionary = panel.sync.nodescript.body.get("signals", {})
	for key in sigs.keys():
		return str(key)
	return ""


func _format_diff_bbcode(actual: String, expected: String) -> String:
	var actual_lines := actual.split("\n", false)
	var expected_lines := expected.split("\n", false)
	var output: Array[String] = []
	var max_lines = max(actual_lines.size(), expected_lines.size())
	for i in range(max_lines):
		var a = actual_lines[i] if i < actual_lines.size() else ""
		var e = expected_lines[i] if i < expected_lines.size() else ""
		# Normalize indentation/spacing for comparison
		var norm_a := a.strip_edges()
		var norm_e := e.strip_edges()
		var escaped_a := a.replace("[", "\\[").replace("]", "\\]")
		# Treat blank lines as equal when both blank.
		if (norm_a == "" and norm_e == "") or norm_a == norm_e:
			output.append(escaped_a if escaped_a != "" else "")
		else:
			output.append("[color=red]%s[/color]" % escaped_a)
	return "\n".join(output)


func _normalize_script(text: String) -> String:
	var lines: Array[String] = []
	for line in text.split("\n", false):
		var trimmed := line.strip_edges()
		if trimmed == "":
			continue
		lines.append(trimmed)
	return "\n".join(lines)


func _hint_for_step(step_idx: int) -> String:
	var hints: Dictionary = {
		0: "Step 0: blank file setup (_setup_blank_script in visual runner).",
		1: "Step 1: variable add via _step_add_health/_on_variable_editor_submitted.",
		2: "Step 2: signal add via _step_add_signal/_on_signal_editor_submitted.",
		3: "Step 3: signal param update via _step_update_signal_param.",
		4: "Step 4: enum add via _step_add_enum/_on_enum_editor_submitted.",
		5: "Step 5: class/function add via _step_add_class_func / nodescript_sync.generate.",
		6: "Step 6: const add via _step_add_const/_on_variable_editor_submitted.",
		7: "Step 7: variable edit (health value) via _step_edit_health.",
		8: "Step 8: reorder vars via _step_reorder_vars/order map.",
		9: "Step 9: region add/move via _step_add_region_and_move/order map.",
		10: "Step 10: insert blank spacers into order map.",
		11: "Step 11: move const to top via _step_move_const_top/order map.",
		12: "Step 12: signal delete via _step_delete_signal/_on_signal_editor_delete_requested."
	}
	return hints.get(step_idx, "Check order map generation and step logic around this stage.")


func _expected_output_for_step(step_idx: int) -> String:
	match step_idx:
		0:
			return "" # blank script at start
		1:
			return "var health: int = 100"
		2:
			return "var health: int = 100\nsignal died"
		3:
			return "var health: int = 100\nsignal died(amount: int)"
		4:
			return """var health: int = 100
signal died(amount: int)

enum State { IDLE, RUN }"""
		5:
			return """var health: int = 100
signal died(amount: int)

enum State { IDLE, RUN }

class Data extends Resource:
	func load() -> void:
		pass


"""
		6:
			return """var health: int = 100
signal died(amount: int)

enum State { IDLE, RUN }

class Data extends Resource:
	func load() -> void:
		pass


const MAX_HP: int = 999"""
		7:
			return """var health: int = 150
signal died(amount: int)

enum State { IDLE, RUN }

class Data extends Resource:
	func load() -> void:
		pass


const MAX_HP: int = 999"""
		8:
			return """var health: int = 150
var mana: int = 50
const MAX_HP: int = 999
signal died(amount: int)

enum State { IDLE, RUN }

class Data extends Resource:
	func load() -> void:
		pass


"""
		9:
			return """const MAX_HP: int = 999
var mana: int = 50
signal died(amount: int)
enum State { IDLE, RUN }
#region Stats
var health: int = 150
#endregion Stats
class Data extends Resource:
	func load() -> void:
		pass"""
		10:
			return """const MAX_HP: int = 999
var mana: int = 50

signal died(amount: int)

enum State { IDLE, RUN }

#region Stats
var health: int = 150
#endregion Stats

class Data extends Resource:
	func load() -> void:
		pass


"""
		11:
			return """const MAX_HP: int = 999
var mana: int = 50

enum State { IDLE, RUN }

#region Stats
var health: int = 150
#endregion Stats

class Data extends Resource:
	func load() -> void:
		pass


"""
		12:
			return """const MAX_HP: int = 999
var mana: int = 50

enum State { IDLE, RUN }

#region Stats
var health: int = 150
#endregion Stats

class Data extends Resource:
	func load() -> void:
		pass


"""
		_:
			return ""
