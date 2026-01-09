@tool
extends RefCounted
class_name NodeScriptSync

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptResource = preload("res://addons/nodescript/core/nodescript_resource.gd")
const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const NodeScriptOrderUtils = preload("res://addons/nodescript/editor/nodescript_order_utils.gd")
const NodeScriptParser = preload("res://addons/nodescript/editor/nodescript_parser.gd")

const DEFAULT_METHOD_BODY_COMMENT := "NodeScript: default method body"
const DEFAULT_METHOD_BODY := [
	{"type": "comment", "text": DEFAULT_METHOD_BODY_COMMENT},
	{"type": "pass", "text": "pass"}
]

var script_path: String = ""
var nodescript_path: String = ""
var nodescript: NodeScriptResource

# Auto-spacing preferences (initialised from config; can be overridden by the panel at runtime).
var auto_space_enabled: bool = NodeScriptConfig.get_auto_space_enabled()
var consolidate_blank_lines: bool = NodeScriptConfig.get_consolidate_blank_lines()
var auto_space_strategy: String = NodeScriptConfig.get_auto_space_strategy()

#region Public API
# Public helper API (test-friendly) to exercise core logic without the panel UI.

# Re-point sync to a provided NodeScriptResource and ensure it has the expected structure.
func reset_nodescript(resource: NodeScriptResource) -> void:
	# Re-point to a provided resource and ensure required structure exists.
	nodescript = resource
	_ensure_body_structure()
	_dedupe_body()
	_ensure_order_map()


# Replace current body with a provided dictionary, shaping it for generation/parsing.
func normalize_body(body: Dictionary) -> Dictionary:
	# Apply a body dictionary to the current nodescript (creating one if needed)
	# and ensure it is shaped for generation/parsing. Returns the normalized body.
	if nodescript == null:
		nodescript = NodeScriptResource.new()
	nodescript.body = body
	_ensure_body_structure()
	_dedupe_body()
	_ensure_order_map()
	return nodescript.body


# Generate declaration text (and optionally functions) from the current nodescript state.
func emit_declarations(include_functions: bool = true) -> String:
	_ensure_body_structure()
	_dedupe_body()
	_ensure_order_map()
	return _generate_script_source(include_functions)


func _generate_script_source(include_functions: bool) -> String:
	if nodescript == null:
		return ""
	var lines: Array[String] = []
	if typeof(nodescript.meta) == TYPE_DICTIONARY:
		if nodescript.meta.get("tool", false):
			lines.append("@tool")
		var extends_value := str(nodescript.meta.get("extends", "")).strip_edges()
		if extends_value != "":
			lines.append("extends " + extends_value)
		var cname := str(nodescript.meta.get("class_name", "")).strip_edges()
		if cname != "":
			lines.append("class_name " + cname)
		if not lines.is_empty():
			lines.append("")
	_append_region_block(lines, "", include_functions)
	var final_lines := lines if include_functions else _clean_declaration_lines(lines)
	return _join_lines_with_newline(final_lines)


# Fetch the order array for a given scope (class + region).
func emit_scope_order(cls: String, region: String) -> Array:
	return _scope_order_for(cls, region)


# Set an explicit order array for a given scope (class + region).
func set_scope_order(cls: String, region: String, order: Array) -> void:
	_ensure_order_map()
	var order_map: Dictionary = nodescript.body.get("order", {})
	order_map[_scope_key(cls, region)] = order
	nodescript.body["order"] = order_map


# Append a single order entry into the order map for a given scope.
func append_order_entry(cls: String, region: String, type: String, name: String, line_number: int = 0, code: String = "", indent: int = 0, manual_blank: bool = false) -> void:
	_ensure_order_map()
	var order_map: Dictionary = nodescript.body.get("order", {})
	_append_order_entry(order_map, cls, region, type, name, line_number, code, indent, manual_blank)
	nodescript.body["order"] = order_map


# Append an explicit blank line into a scope order for layout control.
func append_blank(cls: String, region: String, indent: int = 0) -> void:
	_ensure_order_map()
	var order_map: Dictionary = nodescript.body.get("order", {})
	_append_order_entry(order_map, cls, region, "blank", "", 0, "", indent, true)
	nodescript.body["order"] = order_map


func set_auto_space_enabled(enabled: bool) -> void:
	auto_space_enabled = enabled
	# Re-apply spacing with the new preference so downstream calls see updated order.
	_ensure_order_map()


func set_consolidate_blank_lines(enabled: bool) -> void:
	consolidate_blank_lines = enabled
	# Re-apply consolidation to clean up immediately.
	_ensure_order_map()


func set_auto_space_strategy(strategy: String) -> void:
	var valid_strategies := ["none", "between_types", "after_groups"]
	if strategy in valid_strategies:
		auto_space_strategy = strategy
	else:
		auto_space_strategy = NodeScriptConfig.get_auto_space_strategy()
	_ensure_order_map()


# --- Function helpers (add/update/delete/reorder) ---
# Normalizes and mutates functions while keeping order map in sync.

func add_function(func_dict: Dictionary) -> void:
	if nodescript == null:
		return
	_ensure_body_structure()
	_ensure_order_map()
	var methods: Array = nodescript.body.get("functions", [])
	var cls := str(func_dict.get("class", "")).strip_edges()
	var region := str(func_dict.get("region", "")).strip_edges()
	var name := str(func_dict.get("name", "")).strip_edges()
	if name == "":
		return
	# Ensure unique within scope
	for m in methods:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("name", "")) == name and _entry_class(m) == cls and _entry_region(m) == region:
			return
	if not func_dict.has("body") or typeof(func_dict["body"]) != TYPE_ARRAY:
		func_dict["body"] = DEFAULT_METHOD_BODY.duplicate(true)
	methods.append(func_dict)
	nodescript.body["functions"] = methods
	append_order_entry(cls, region, "function", name, 0, "", int(func_dict.get("indent", 0)))


func update_function(name: String, cls: String, region: String, updates: Dictionary) -> void:
	if nodescript == null:
		return
	var idx := _function_index_by_name_scope(name, cls, region)
	if idx == -1:
		return
	var funcs: Array = nodescript.body.get("functions", [])
	var fn = funcs[idx]
	if typeof(fn) != TYPE_DICTIONARY:
		fn = {}
	for key in updates.keys():
		fn[key] = updates[key]
	funcs[idx] = fn
	nodescript.body["functions"] = funcs


func delete_function(name: String, cls: String, region: String) -> void:
	if nodescript == null:
		return
	var funcs: Array = nodescript.body.get("functions", [])
	var new_funcs: Array = []
	for fn in funcs:
		if typeof(fn) != TYPE_DICTIONARY:
			continue
		if str(fn.get("name", "")) == name and _entry_class(fn) == cls and _entry_region(fn) == region:
			continue
		new_funcs.append(fn)
	nodescript.body["functions"] = new_funcs
	# Remove from order map
	_ensure_order_map()
	var scope_key := _scope_key(cls, region)
	var order: Dictionary = nodescript.body.get("order", {})
	if order.has(scope_key):
		var filtered: Array = []
		for e in order[scope_key]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if str(e.get("type", "")) == "function" and str(e.get("name", "")) == name:
				continue
			filtered.append(e)
		order[scope_key] = filtered
		nodescript.body["order"] = order


func reorder_functions(cls: String, region: String, ordered_names: Array) -> void:
	# Replace function entries in order map for the scope with the provided name order.
	if nodescript == null:
		return
	_ensure_order_map()
	var scope_key := _scope_key(cls, region)
	var order: Dictionary = nodescript.body.get("order", {})
	if not order.has(scope_key):
		order[scope_key] = []
	var filtered: Array = []
	for name in ordered_names:
		filtered.append({"type": "function", "name": str(name), "line": 1, "indent": 0})
	# Keep non-function entries in this scope
	for entry in order[scope_key]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) == "function":
			continue
		filtered.append(entry)
	order[scope_key] = filtered
	nodescript.body["order"] = order


func set_function_body(name: String, cls: String, region: String, body: Array) -> void:
	if nodescript == null:
		return
	var idx := _function_index_by_name_scope(name, cls, region)
	if idx == -1:
		return
	var funcs: Array = nodescript.body.get("functions", [])
	var fn = funcs[idx]
	if typeof(fn) != TYPE_DICTIONARY:
		return
	fn["body"] = body if typeof(body) == TYPE_ARRAY else DEFAULT_METHOD_BODY.duplicate(true)
	funcs[idx] = fn
	nodescript.body["functions"] = funcs


# Load/initialize sync for a target script resource; creates .nodescript if missing.
func load_for_script(script: Script) -> void:
	if script == null:
		script_path = ""
		nodescript_path = ""
		nodescript = null
		_log("load_for_script: no script provided", 1)
		return

	script_path = script.resource_path
	if script_path == "":
		nodescript_path = ""
		nodescript = null
		_log("load_for_script: script has no path", 1)
		return

	var resolved_path := _resolve_script_path(script_path)
	if resolved_path == "":
		nodescript_path = ""
		nodescript = null
		_log("load_for_script: could not resolve script path", 1)
		return

	script_path = resolved_path
	nodescript_path = _deduce_nodescript_path(resolved_path, script)

	if ResourceLoader.exists(nodescript_path):
		nodescript = ResourceLoader.load(nodescript_path)
	else:
		nodescript = NodeScriptResource.new()

	_ensure_body_structure()
	NodeScriptParser.parse_script(script, nodescript, auto_space_enabled)
	_save_nodescript()
	_log("load_for_script: loaded script %s with NodeScript %s" % [script_path, nodescript_path], 1)


#region Path helpers

func _deduce_nodescript_path(resolved_path: String, script: Script) -> String:
	if script == null:
		return ""

	if resolved_path == "":
		return ""

	var dir := resolved_path.get_base_dir()
	if dir == "":
		return ""

	var file_name := resolved_path.get_file()
	if file_name == "":
		file_name = script.resource_name
	var base_name := file_name.get_basename()
	if base_name == "":
		base_name = file_name
		if base_name.begins_with(".") and base_name.length() > 1:
			base_name = base_name.substr(1, base_name.length() - 1)
	if base_name == "":
		base_name = script.resource_name.strip_edges()
	if base_name == "":
		base_name = "script"

	return dir.path_join("%s.nodescript.tres" % base_name)


func _resolve_script_path(path: String) -> String:
	if not path.begins_with("uid://"):
		return path

	var uid := ResourceUID.text_to_id(path)
	if uid == ResourceUID.INVALID_ID:
		return ""

	var resolved := ResourceUID.get_id_path(uid)
	return resolved if resolved != "" else ""

#endregion Path helpers


#region Body shaping

func _ensure_body_structure() -> void:
	if nodescript == null:
		return

	# Shape the nodescript body dictionary with required collections.
	# Ensure "body" exists
	if typeof(nodescript.body) != TYPE_DICTIONARY:
		nodescript.body = {}

	# Ensure functions array exists
	if not nodescript.body.has("functions") or typeof(nodescript.body["functions"]) != TYPE_ARRAY:
		nodescript.body["functions"] = []
	if not nodescript.body.has("signals") or typeof(nodescript.body["signals"]) != TYPE_DICTIONARY:
		nodescript.body["signals"] = {}
	if not nodescript.body.has("variables") or typeof(nodescript.body["variables"]) != TYPE_ARRAY:
		nodescript.body["variables"] = []
	if not nodescript.body.has("regions") or typeof(nodescript.body["regions"]) != TYPE_ARRAY:
		nodescript.body["regions"] = []
	if not nodescript.body.has("classes") or typeof(nodescript.body["classes"]) != TYPE_ARRAY:
		nodescript.body["classes"] = []

	var methods: Array = nodescript.body["functions"]
	var did_modify: bool = false

	for i in range(methods.size()):
		var method = methods[i]
		if typeof(method) != TYPE_DICTIONARY:
			method = {}
			did_modify = true
		if not method.has("body") or typeof(method["body"]) != TYPE_ARRAY:
			method["body"] = []
			did_modify = true
		if method["body"].is_empty():
			method["body"] = DEFAULT_METHOD_BODY.duplicate(true)
			did_modify = true
		methods[i] = method

	if did_modify:
		nodescript.body["functions"] = methods


# Persist current NodeScript resource to disk if possible.
func _save_nodescript() -> void:
	if nodescript == null:
		return
	if nodescript_path == "":
		return
	ResourceSaver.save(nodescript, nodescript_path)


func save() -> void:
	_save_nodescript()
	if nodescript_path != "":
		_log("Saved NodeScript resource: %s" % nodescript_path, 1)

#endregion Public API


func _sync_from_script_source(script: Script) -> void:
	NodeScriptParser.parse_script(script, nodescript)
	_dedupe_body()
	_log("Parsed %d functions" % nodescript.body.get("functions", []).size(), 1)


func _dedupe_body() -> void:
	if nodescript == null or typeof(nodescript.body) != TYPE_DICTIONARY:
		return
	# Remove duplicate entries across functions, variables, regions, classes while preserving first occurrence.
	# Functions
	var funcs: Array = nodescript.body.get("functions", [])
	var seen_funcs: Dictionary = {}
	var cleaned_funcs: Array = []
	for f in funcs:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var key := "%s|%s|%s" % [str(f.get("class", "")), str(f.get("region", "")), str(f.get("name", ""))]
		if seen_funcs.has(key):
			continue
		seen_funcs[key] = true
		cleaned_funcs.append(f)
	nodescript.body["functions"] = cleaned_funcs
	# Variables
	var vars: Array = nodescript.body.get("variables", [])
	var seen_vars: Dictionary = {}
	var cleaned_vars: Array = []
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var key := "%s|%s|%s" % [str(v.get("class", "")), str(v.get("region", "")), str(v.get("name", ""))]
		if seen_vars.has(key):
			continue
		seen_vars[key] = true
		cleaned_vars.append(v)
	nodescript.body["variables"] = cleaned_vars
	# Regions
	var regs: Array = nodescript.body.get("regions", [])
	var seen_regs: Dictionary = {}
	var cleaned_regs: Array = []
	for r in regs:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var key := "%s|%s|%s" % [str(r.get("class", "")), str(r.get("region", "")), str(r.get("name", ""))]
		if seen_regs.has(key):
			continue
		seen_regs[key] = true
		cleaned_regs.append(r)
	nodescript.body["regions"] = cleaned_regs
	# Classes
	var cls_arr: Array = nodescript.body.get("classes", [])
	var seen_cls: Dictionary = {}
	var cleaned_cls: Array = []
	for c in cls_arr:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var key := str(c.get("name", ""))
		if seen_cls.has(key):
			continue
		seen_cls[key] = true
		cleaned_cls.append(c)
	nodescript.body["classes"] = cleaned_cls


#endregion Body shaping


#region JSON helpers
# === JSON export helpers ===
func to_json_structure() -> Dictionary:
	if nodescript == null:
		return {}
	var meta_out := {
		"path": script_path,
		"class_name": str(nodescript.meta.get("class_name", "") if typeof(nodescript.meta) == TYPE_DICTIONARY else ""),
		"extends": str(nodescript.meta.get("extends", "") if typeof(nodescript.meta) == TYPE_DICTIONARY else ""),
		"tool": bool(nodescript.meta.get("tool", false) if typeof(nodescript.meta) == TYPE_DICTIONARY else false)
	}
	var pos := {"v": 0}
	var body: Array = []
	_emit_scope_json("", "", body, pos)
	return {
		"id": "file:%s" % (script_path.get_file() if script_path != "" else "script.gd"),
		"meta": meta_out,
		"body": body
	}


# Export the current NodeScript structure into a tree suitable for visualization/serialization.
func _emit_scope_json(cls: String, region: String, out_body: Array, pos: Dictionary) -> void:
	var order := _scope_order_for(cls, region)
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", ""))
		match kind:
			"blank":
				out_body.append(_json_blank_node(cls, region, pos, int(entry.get("indent", 0))))
			"region":
				var region_node := _json_region_node(name, cls, pos)
				out_body.append(region_node)
				if region_node.has("body"):
					_emit_scope_json(cls, name, region_node["body"], pos)
			"class":
				if cls != "":
					continue
				var class_node := _json_class_node(name, region, pos)
				out_body.append(class_node)
				if class_node.has("body"):
					_emit_scope_json(name, _entry_region(_find_class_entry(name)), class_node["body"], pos)
			"signal":
				out_body.append(_json_signal_node(name, cls, region, pos))
			"enum":
				out_body.append(_json_enum_node(name, cls, region, pos))
			"variable":
				out_body.append(_json_variable_node(name, cls, region, pos))
			"function":
				out_body.append(_json_function_node(name, cls, region, pos))
			_:
				continue


func _next_pos(pos: Dictionary) -> int:
	pos["v"] = int(pos.get("v", 0)) + 1
	return pos["v"]


func _json_base_node(id: String, cls: String, region: String, pos: Dictionary) -> Dictionary:
	return {
		"id": id,
		"position": _next_pos(pos),
		"class": cls,
		"region": region,
		"meta": {}
	}


func _json_region_node(name: String, cls: String, pos: Dictionary) -> Dictionary:
	var node := _json_base_node("region:%s" % name, cls, "", pos)
	node["body"] = []
	return node


func _json_blank_node(cls: String, region: String, pos: Dictionary, indent: int) -> Dictionary:
	return {
		"id": "blank:%d" % _next_pos(pos),
		"position": pos.get("v", 0),
		"class": cls,
		"region": region,
		"meta": {"indent": indent},
		"body": []
	}


func _json_class_node(name: String, region: String, pos: Dictionary) -> Dictionary:
	var entry := _find_class_entry(name)
	var node := _json_base_node("class:%s" % name, "", region, pos)
	node["meta"] = {
		"extends": str(entry.get("extends", "")) if typeof(entry) == TYPE_DICTIONARY else ""
	}
	node["body"] = []
	return node


func _json_signal_node(name: String, cls: String, region: String, pos: Dictionary) -> Dictionary:
	var entry := _signal_entry(name)
	var node := _json_base_node("signal:%s" % name, cls, region, pos)
	if typeof(entry) == TYPE_DICTIONARY:
		node["meta"] = {"parameters": entry.get("parameters", [])}
	return node


func _json_enum_node(name: String, cls: String, region: String, pos: Dictionary) -> Dictionary:
	var entry := _enum_entry(name)
	var node := _json_base_node("enum:%s" % name, cls, region, pos)
	if typeof(entry) == TYPE_DICTIONARY:
		node["body"] = _enum_values(entry)
	return node


func _json_variable_node(name: String, cls: String, region: String, pos: Dictionary) -> Dictionary:
	var entry := _variable_entry(name)
	var node := _json_base_node("var:%s" % name, cls, region, pos)
	if typeof(entry) == TYPE_DICTIONARY:
		node["meta"] = {
			"type": str(entry.get("type", "")),
			"value": str(entry.get("value", "")),
			"export": entry.get("export", false),
			"const": entry.get("const", false),
			"onready": entry.get("onready", false),
			"export_group": str(entry.get("export_group", ""))
		}
	return node


func _json_function_node(name: String, cls: String, region: String, pos: Dictionary) -> Dictionary:
	var fn_index := _function_index_by_name(name)
	var entry := _function_entry(fn_index)
	var node := _json_base_node("func:%s" % name, cls, region, pos)
	if typeof(entry) == TYPE_DICTIONARY:
		node["meta"] = {
			"parameters": entry.get("parameters", []),
			"return_type": str(entry.get("return_type", "")),
			"flags": {
				"static": entry.get("static", false),
				"virtual": entry.get("virtual", false),
				"override": entry.get("override", false),
				"vararg": entry.get("vararg", false),
				"rpc": entry.get("rpc", false)
			}
		}
		node["body"] = entry.get("body", [])
	return node


#endregion JSON helpers

#region Entry helpers

func _enum_region(entry) -> String:
	return NodeScriptUtils.enum_region(entry)


func _enum_class(entry) -> String:
	return NodeScriptUtils.enum_class(entry)


func _enum_values(entry) -> Array:
	if typeof(entry) != TYPE_DICTIONARY:
		return []
	var values_data = entry.get("values", [])
	if typeof(values_data) != TYPE_ARRAY:
		return []
	var values: Array = []
	for v in values_data:
		if typeof(v) == TYPE_DICTIONARY:
			var name := str(v.get("name", "")).strip_edges()
			if name == "":
				continue
			var val := str(v.get("value", "")).strip_edges()
			if val != "":
				name += " = " + val
			values.append(name)
		else:
			var name := str(v).strip_edges()
			if name != "":
				values.append(name)
	return values


func _entry_class(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("class", "")).strip_edges()


func _entry_region(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("region", "")).strip_edges()


func _region_exists(regions: Array, name: String, cls: String = "", parent_region: String = "") -> bool:
	for r in regions:
		var candidate := ""
		var rcls := ""
		var parent := ""
		if typeof(r) == TYPE_DICTIONARY:
			candidate = str(r.get("name", ""))
			rcls = str(r.get("class", ""))
			parent = str(r.get("region", ""))
		else:
			candidate = str(r)
		if candidate.strip_edges() == name.strip_edges() and str(rcls).strip_edges() == cls.strip_edges() and parent.strip_edges() == parent_region.strip_edges():
			return true
	return false


func _collect_region_names(cls: String = "") -> Array:
	if nodescript == null:
		return []
	var regions_array: Array = nodescript.body.get("regions", [])
	var names: Array = []
	for r in regions_array:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if _entry_class(r) != cls:
			continue
		var name := str(r.get("name", "")).strip_edges()
		if name == "":
			continue
		if names.has(name):
			continue
		names.append(name)
	names.sort()
	return names


#endregion Entry helpers

#region Append helpers

func _append_signals(lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
	if nodescript == null:
		return
	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	if signals_dict.is_empty():
		return

	var signal_names: Array = []
	for name in signals_dict.keys():
		var entry = signals_dict.get(name, {})
		var entry_region := _entry_region(entry)
		var entry_class := _entry_class(entry)
		if class_title != "":
			if entry_class != class_title:
				continue
		else:
			if entry_class != "":
				continue
		if region == "":
			if entry_region != "":
				continue
		else:
			if entry_region != region:
				continue
		signal_names.append(name)

	signal_names.sort()
	for name in signal_names:
		var entry = signals_dict.get(name, {})
		var params: Array = []
		if typeof(entry) == TYPE_DICTIONARY:
			params = entry.get("parameters", [])
		elif typeof(entry) == TYPE_ARRAY:
			params = entry
		var declaration = "signal " + str(name)
		var formatted_params = _format_signal_parameters(params)
		if formatted_params != "":
			declaration += "(" + formatted_params + ")"
		lines.append(indent_prefix + declaration)
	lines.append(indent_prefix + "")


func _append_enums(lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
	if nodescript == null:
		return
	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	if enums_dict.is_empty():
		return

	var names: Array = []
	for enum_name in enums_dict.keys():
		var entry = enums_dict.get(enum_name, {})
		var entry_region := _enum_region(entry)
		var entry_class := _enum_class(entry)
		if class_title != "":
			if entry_class != class_title:
				continue
		else:
			if entry_class != "":
				continue
		if region == "":
			if entry_region != "":
				continue
		else:
			if entry_region != region:
				continue
		names.append(enum_name)

	names.sort()
	for enum_name in names:
		var entry = enums_dict.get(enum_name, {})
		var values: Array = _enum_values(entry)
		var body := ""
		if values.is_empty():
			body = "{}"
		else:
			body = "{ " + ", ".join(values) + " }"
		if str(enum_name).strip_edges() == "":
			lines.append(indent_prefix + "enum " + body)
		else:
			lines.append(indent_prefix + "enum %s %s" % [enum_name, body])
	lines.append(indent_prefix + "")


func _append_classes(lines: Array[String], classes: Array, region: String = "") -> void:
	if classes.is_empty():
		return
	for cls in classes:
		if typeof(cls) != TYPE_DICTIONARY:
			continue
		var entry_region := str(cls.get("region", "")).strip_edges()
		if region == "":
			if entry_region != "":
				continue
		else:
			if entry_region != region:
				continue
		_append_class_name_line(lines, cls)
		var cls_name := str(cls.get("name", "")).strip_edges()
		if not _class_has_members(cls_name, region):
			lines.append("\tpass")
	lines.append("")


func _append_class_name_line(lines: Array[String], cls: Dictionary, indent_prefix: String = "") -> void:
	if typeof(cls) != TYPE_DICTIONARY:
		return
	var name := str(cls.get("name", "")).strip_edges()
	if name == "":
		return
	var extends_value := str(cls.get("extends", "")).strip_edges()
	var line := "class " + name + ":"
	if extends_value != "":
		line = "class " + name + " extends " + extends_value + ":"
	lines.append(indent_prefix + line)

func _class_header_line(cls: Dictionary) -> String:
	if typeof(cls) != TYPE_DICTIONARY:
		return ""
	var name := str(cls.get("name", "")).strip_edges()
	if name == "":
		return ""
	var extends_value := str(cls.get("extends", "")).strip_edges()
	var line := "class " + name + ":"
	if extends_value != "":
		line = "class " + name + " extends " + extends_value + ":"
	return line


func _class_has_members(class_title: String, region: String) -> bool:
	return NodeScriptUtils.class_has_members(nodescript, class_title, region)


func _class_member_count(class_title: String) -> int:
	if nodescript == null:
		return 0
	var cls := class_title.strip_edges()
	if cls == "":
		return 0
	var count := 0

	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for entry in signals_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == cls:
			count += 1

	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for entry in enums_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == cls:
			count += 1

	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == cls:
			count += 1

	var functions_array: Array = nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() == cls:
			count += 1

	return count


func _has_unscoped_entries_for_class(class_title: String) -> bool:
	if nodescript == null:
		return false
	var cls := class_title.strip_edges()
	if cls == "":
		return false

	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for entry in signals_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) == cls and _entry_region(entry) == "":
			return true

	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for entry in enums_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _enum_class(entry) == cls and _enum_region(entry) == "":
			return true

	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) == cls and _entry_region(entry) == "":
			return true

	var functions_array: Array = nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) == cls and _entry_region(entry) == "":
			return true

	return false


func _append_classes_in_region(lines: Array[String], classes: Array, region_name: String, include_functions: bool, indent_prefix: String) -> void:
	if classes.is_empty():
		return
	var target := region_name.strip_edges()
	for cls in classes:
		if typeof(cls) != TYPE_DICTIONARY:
			continue
		var entry_region := str(cls.get("region", "")).strip_edges()
		if entry_region != target:
			continue
		_append_class_block(lines, cls, include_functions, indent_prefix)


# Emit a single region block (signals/enums/vars/functions/classes) for a given class/region.
func _append_region_block(lines: Array[String], region_name: String, include_functions: bool, class_title: String = "", indent_prefix: String = "") -> void:
	var scope_order := _scope_order_for(class_title, region_name)
	for entry in scope_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind := str(entry.get("type", ""))
		match kind:
			"blank":
				lines.append(indent_prefix + "")
			"signal":
				_append_signals(lines, region_name, class_title, indent_prefix)
			"enum":
				_append_enums(lines, region_name, class_title, indent_prefix)
			"variable":
				_append_variables(lines, region_name, class_title, indent_prefix)
			"class":
				var classes: Array = nodescript.body.get("classes", [])
				_append_classes_in_region(lines, classes, region_name, include_functions, indent_prefix)
			"function":
				if include_functions:
					_append_functions(lines, region_name, class_title, indent_prefix)
			"region":
				# Nested regions are emitted when encountered in order map
				lines.append(indent_prefix + "#region " + region_name)
				_append_region_block(lines, entry.get("name", ""), include_functions, class_title, indent_prefix)
				lines.append(indent_prefix + "#endregion")
			_:
				continue


func _append_class_block(lines: Array[String], cls: Dictionary, include_functions: bool, indent_prefix: String = "") -> void:
	if typeof(cls) != TYPE_DICTIONARY:
		return
	var cname := str(cls.get("name", "")).strip_edges()
	if cname == "":
		return
	_append_class_name_line(lines, cls, indent_prefix)
	var member_count := _class_member_count(cname)
	if member_count == 0:
		lines.append(indent_prefix + "\tpass")
		lines.append(indent_prefix + "")
		return
	var member_appended := false
	var regions: Array = _collect_region_names(cname)
	var appended_region := false
	for region_name in regions:
		if not _class_has_members(cname, region_name):
			continue
		_append_region_block(lines, region_name, include_functions, cname, indent_prefix + "\t")
		appended_region = true
		member_appended = true
	if not appended_region or _has_unscoped_entries_for_class(cname):
		_append_region_block(lines, "", include_functions, cname, indent_prefix + "\t")
		member_appended = true
	if _class_member_count(cname) == 0:
		lines.append(indent_prefix + "\tpass")
	lines.append(indent_prefix + "")


func _append_variables(lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
	if nodescript == null:
		return
	var variables_array: Array = nodescript.body.get("variables", [])
	if variables_array.is_empty():
		return

	var filtered: Array = []
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_region := _entry_region(entry)
		var entry_class := _entry_class(entry)
		if class_title != "":
			if entry_class != class_title:
				continue
		else:
			if entry_class != "":
				continue
		if region == "":
			if entry_region != "":
				continue
		else:
			if entry_region != region:
				continue
		filtered.append(entry)

	if filtered.is_empty():
		return

	var groups := {
		"const": [],
		"export": [],
		"onready": [],
		"var": []
	}
	for entry in filtered:
		var group := _variable_group(entry)
		if not groups.has(group):
			group = "var"
		groups[group].append(entry)

	var wrote_any := false
	for group_name in ["const", "export", "onready", "var"]:
		var group_entries: Array = groups.get(group_name, [])
		if group_entries.is_empty():
			continue
		if wrote_any:
			lines.append(indent_prefix + "")
		for entry in group_entries:
			var annotations: Array[String] = _format_variable_annotations(entry)
			var var_line := _format_variable_line(entry)

			if annotations.is_empty():
				lines.append(indent_prefix + var_line)
			else:
				# Compact annotations inline with the variable for cleaner output.
				var combined := " ".join(annotations + [var_line])
				lines.append(indent_prefix + combined)
		wrote_any = true
	lines.append(indent_prefix + "") # Ensure a blank line after the variable block.


func _append_functions(lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
	if nodescript == null:
		return
	var functions_array: Array = nodescript.body.get("functions", [])
	if functions_array.is_empty():
		return
	var filtered: Array = []
	for method in functions_array:
		if typeof(method) != TYPE_DICTIONARY:
			continue
		var entry_region := _entry_region(method)
		var entry_class := _entry_class(method)
		if class_title != "":
			if entry_class != class_title:
				continue
		else:
			if entry_class != "":
				continue
		# If a method has an explicit region, only include when matching; otherwise include when region filter is empty.
		if region == "":
			if entry_region != "":
				continue
		else:
			if entry_region != region:
				continue
		filtered.append(method)
	if filtered.is_empty():
		return
	if not lines.is_empty():
		if lines[lines.size() - 1].strip_edges() != "":
			lines.append(indent_prefix + "") # Separate declarations/variables from functions.
	for i in range(filtered.size()):
		var method = filtered[i]
		lines.append(indent_prefix + _format_function_header(method))
		_append_function_body(lines, method, indent_prefix)
		if i < filtered.size() - 1:
			lines.append(indent_prefix + "")


func _clean_declaration_lines(lines: Array[String]) -> Array[String]:
	var cleaned: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed == "":
			cleaned.append(line)
			continue
		if trimmed.begins_with("@") \
		or trimmed.begins_with("extends ") \
		or trimmed.begins_with("class_name ") \
		or trimmed.begins_with("class ") \
		or trimmed.begins_with("signal ") \
		or trimmed.begins_with("enum ") \
		or trimmed.begins_with("var ") \
		or trimmed.begins_with("const ") \
		or trimmed == "pass" \
		or trimmed.begins_with("#region") \
		or trimmed.begins_with("#endregion"):
			cleaned.append(line)
	return cleaned


#endregion Append helpers

#region Formatting

func _log(message: String, level: int = 1) -> void:
	if NodeScriptConfig.get_log_level() >= level:
		print("[NodeScriptSync] " + message)


func _join_lines_with_newline(lines: Array[String]) -> String:
	var script_text := "\n".join(lines)
	if script_text == "":
		return ""
	if not script_text.ends_with("\n"):
		script_text += "\n"
	return script_text


func _next_blank_name(scope_entries: Array) -> String:
	var max_idx := 0
	for entry in scope_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) != "blank":
			continue
		var nm := str(entry.get("name", ""))
		if nm.begins_with("blank_"):
			var idx_str := nm.substr("blank_".length(), nm.length() - "blank_".length())
			var idx := idx_str.to_int()
			if idx > max_idx:
				max_idx = idx
	return "blank_%d" % (max_idx + 1)


func _format_signal_parameters(params: Array) -> String:
	var pieces: Array[String] = []
	for param in params:
		if typeof(param) != TYPE_DICTIONARY:
			continue
		var name = str(param.get("name", "")).strip_edges()
		if name == "":
			continue
		var type_hint = str(param.get("type", "")).strip_edges()
		var part = name
		if type_hint != "":
			part += ": " + type_hint
		pieces.append(part)
	return ", ".join(pieces)


func _format_variable_annotations(entry: Dictionary) -> Array[String]:
	var annotations: Array[String] = []
	if entry.get("export", false):
		annotations.append("@export")
	var export_group: String = str(entry.get("export_group", "")).strip_edges()
	if export_group != "":
		annotations.append("@export_group(\"%s\")" % export_group)
	var onready_enabled: bool = entry.get("onready", false)
	if onready_enabled and not entry.get("const", false):
		annotations.append("@onready")
	return annotations


func _format_variable_line(entry: Dictionary) -> String:
	var is_const: bool = entry.get("const", false)
	var base := "const " if is_const else "var "
	var name: String = str(entry.get("name", "variable"))
	var line := base + name
	var type_hint: String = str(entry.get("type", "")).strip_edges()
	if type_hint != "":
		line += ": " + type_hint
	var default_value: String = str(entry.get("value", "")).strip_edges()
	if default_value != "":
		line += " = " + default_value
	elif is_const:
		line += " = null"
	return line


#endregion Formatting

#region Order map

# Store a single ordering hint for a scope (class + region).
func _append_order_entry(order_map: Dictionary, cls: String, region: String, type: String, name: String, line_number: int, code: String, indent: int, manual_blank: bool = false, auto_spacing: bool = false) -> void:
	var scope_key_str := _scope_key(cls, region)
	if not order_map.has(scope_key_str):
		order_map[scope_key_str] = []
	if type == "blank" and name.strip_edges() == "":
		name = _next_blank_name(order_map[scope_key_str])
	var entry := {
		"type": type,
		"name": name,
		"line": line_number,
		"indent": indent
	}
	if code != "":
		entry["code"] = code
	if type == "blank":
		entry["manual_blank"] = manual_blank
		entry["auto_spacing"] = auto_spacing
	order_map[scope_key_str].append(entry)


func _scope_key(cls: String, region: String) -> String:
	return "%s|%s" % [cls, region]


# Ensure nodescript.body has an order map dictionary.
func _ensure_order_map() -> void:
	if nodescript == null:
		return
	if typeof(nodescript.body.get("order", null)) != TYPE_DICTIONARY:
		nodescript.body["order"] = {}
	# Apply auto-spacing based on configured strategy
	nodescript.body["order"] = NodeScriptOrderUtils.apply_auto_spacing(nodescript.body["order"], auto_space_enabled, consolidate_blank_lines, auto_space_strategy)


func _scope_order_for(cls: String, region: String) -> Array:
	_ensure_order_map()
	var order: Dictionary = nodescript.body.get("order", {})
	var scope_key_str := _scope_key(cls, region)
	if not order.has(scope_key_str):
		order[scope_key_str] = _generate_default_scope_order(cls, region)
		nodescript.body["order"] = order
	return order.get(scope_key_str, [])


# Generate a default order when none is present for a scope.
func _generate_default_scope_order(cls: String, region: String) -> Array:
	# When no explicit order exists, rebuild one by scanning existing body entries in this scope.
	var items: Array = []

	var regions: Array = nodescript.body.get("regions", [])
	for entry in regions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var rname := str(entry.get("name", "")).strip_edges()
		if rname == "":
			continue
		var rclass := str(entry.get("class", "")).strip_edges()
		if rclass != cls:
			continue
		if region == "" or cls != "":
			items.append({"type": "region", "name": rname})

	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for name in signals_dict.keys():
		var entry = signals_dict.get(name, {})
		if _entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "signal", "name": str(name)})

	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "variable", "name": str(entry.get("name", ""))})

	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for name in enums_dict.keys():
		var entry = enums_dict.get(name, {})
		if _entry_class(entry) != cls or _entry_region(entry) != region:
			continue
		items.append({"type": "enum", "name": str(name)})

	if cls == "":
		var classes: Array = nodescript.body.get("classes", [])
		for entry in classes:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if _entry_region(entry) != region:
				continue
			var cname := str(entry.get("name", "")).strip_edges()
			if cname != "":
				items.append({"type": "class", "name": cname})

	var functions_array: Array = nodescript.body.get("functions", [])
	for fn in functions_array:
		if typeof(fn) != TYPE_DICTIONARY:
			continue
		if _entry_class(fn) != cls or _entry_region(fn) != region:
			continue
		var fname := str(fn.get("name", "")).strip_edges()
		if fname != "":
			items.append({"type": "function", "name": fname})

	return items


# Find a specific order entry within a scope by type/name.
func _order_lookup(cls: String, region: String, type: String, name: String) -> Dictionary:
	var order: Dictionary = nodescript.body.get("order", {})
	var scope_key_str := _scope_key(cls, region)
	if not order.has(scope_key_str):
		return {}
	for order_entry in order[scope_key_str]:
		if typeof(order_entry) != TYPE_DICTIONARY:
			continue
		if str(order_entry.get("type", "")) == type and str(order_entry.get("name", "")) == name:
			return order_entry
	return {}


func _indent_from_entry(entry: Dictionary) -> String:
	var indent_count := int(entry.get("indent", 0))
	if indent_count < 0:
		indent_count = 0
	return " ".repeat(indent_count)


func _emit_line_with_prefix(entry: Dictionary, indent_prefix: String) -> String:
	var code := str(entry.get("code", ""))
	# Strip leading whitespace from stored code and apply current scope indent.
	var trimmed := code.lstrip(" \t")
	return indent_prefix + trimmed


#endregion Order map

#region Lookups

func _find_class_entry(name: String) -> Dictionary:
	var classes: Array = nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return entry
	return {}


func _signal_entry(name: String) -> Dictionary:
	var signals: Dictionary = nodescript.body.get("signals", {})
	if signals.has(name):
		var entry = signals.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


func _enum_entry(name: String) -> Dictionary:
	var enums: Dictionary = nodescript.body.get("enums", {})
	if enums.has(name):
		var entry = enums.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


func _variable_entry(name: String) -> Dictionary:
	var vars: Array = nodescript.body.get("variables", [])
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if str(v.get("name", "")) == name:
			return v
	return {}


func _function_index_by_name(name: String) -> int:
	var functions_array: Array = nodescript.body.get("functions", [])
	for i in range(functions_array.size()):
		var entry = functions_array[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return i
	return -1

func _function_index_by_name_scope(name: String, cls: String, region: String) -> int:
	var functions_array: Array = nodescript.body.get("functions", [])
	for i in range(functions_array.size()):
		var entry = functions_array[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name and _entry_class(entry) == cls and _entry_region(entry) == region:
			return i
	return -1

func _function_entry(index: int) -> Dictionary:
	if nodescript == null:
		return {}
	var functions_array: Array = nodescript.body.get("functions", [])
	if index < 0 or index >= functions_array.size():
		return {}
	var entry = functions_array[index]
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


#endregion Lookups

#region Function formatting

func _variable_group(entry: Dictionary) -> String:
	if entry.get("const", false):
		return "const"
	if entry.get("export", false):
		return "export"
	if entry.get("onready", false):
		return "onready"
	return "var"


func _format_function_header(method: Dictionary) -> String:
	var name: String = str(method.get("name", "function"))
	var header := "func " + name + "("
	var parameters: Array = method.get("parameters", [])
	header += _format_function_parameters(parameters) + ")"
	var return_type: String = str(method.get("return_type", "")).strip_edges()
	if return_type != "":
		header += " -> " + return_type
	header += ":"
	return header


func _format_function_parameters(parameters: Array) -> String:
	var pieces: Array[String] = []
	for param in parameters:
		if typeof(param) != TYPE_DICTIONARY:
			continue
		var name: String = str(param.get("name", "")).strip_edges()
		if name == "":
			continue
		var part := name
		var type_hint: String = str(param.get("type", "")).strip_edges()
		if type_hint != "":
			part += ": " + type_hint
		var default_value: String = str(param.get("default", "")).strip_edges()
		if default_value != "":
			part += " = " + default_value
		pieces.append(part)
	return ", ".join(pieces)


#endregion Function formatting

func _append_function_body(lines: Array[String], method: Dictionary, indent_prefix: String = "") -> void:
	var body: Array = method.get("body", [])
	if body.is_empty():
		lines.append(indent_prefix + "\tpass")
		return
	# Emit structured statement dictionaries into GDScript lines, preserving indentation levels.
	var appended := false
	for statement in body:
		if typeof(statement) != TYPE_DICTIONARY:
			continue
		var block_type: String = str(statement.get("type", ""))
		var indent_level: int = int(statement.get("indent", 0))
		if indent_level < 0:
			indent_level = 0
		var tabs := "\t".repeat(1 + indent_level)
		var current_prefix := indent_prefix + tabs

		if block_type == "raw" and str(statement.get("text", "")).strip_edges() == "":
			continue

		match block_type:
			"comment":
				var text: String = str(statement.get("text", ""))
				if not text.begins_with("#"):
					text = "# " + text
				lines.append(current_prefix + text)
				appended = true
			"raw":
				var raw_text := str(statement.get("text", ""))
				if raw_text.strip_edges() != "":
					lines.append(current_prefix + raw_text)
					appended = true
			"assignment":
				var target := str(statement.get("target", "")).strip_edges()
				var expr := str(statement.get("expr", "")).strip_edges()
				if target != "" and expr != "":
					lines.append(current_prefix + "%s = %s" % [target, expr])
					appended = true
				elif statement.has("text"):
					lines.append(current_prefix + str(statement.get("text", "")))
					appended = true
			"call":
				if statement.has("text") and str(statement.get("text", "")).strip_edges() != "":
					lines.append(current_prefix + str(statement.get("text", "")))
					appended = true
				else:
					var cname := str(statement.get("call", "")).strip_edges()
					var args := str(statement.get("args", "")).strip_edges()
					var call_line := cname
					if cname != "":
						call_line += "(" + args + ")"
					if call_line.strip_edges() != "":
						lines.append(current_prefix + call_line)
						appended = true
			"signal_emit":
				var sig := str(statement.get("signal", "")).strip_edges()
				var sargs := str(statement.get("args", "")).strip_edges()
				var emit_line := "emit_signal(\"%s\"" % sig if sig != "" else "emit_signal("
				if sargs != "":
					if emit_line.ends_with("("):
						emit_line += sargs + ")"
					else:
						emit_line += ", " + sargs + ")"
				else:
					emit_line += ")"
				lines.append(current_prefix + emit_line)
				appended = true
			"return":
				var rexpr := str(statement.get("expr", "")).strip_edges()
				lines.append(current_prefix + ("return %s" % rexpr if rexpr != "" else "return"))
				appended = true
			"if", "elif":
				var cond := str(statement.get("condition", "")).strip_edges()
				if cond == "":
					cond = "true"
				lines.append(current_prefix + "%s %s:" % [block_type, cond])
				appended = true
			"else":
				lines.append(current_prefix + "else:")
				appended = true
			"match":
				var subject := str(statement.get("subject", "")).strip_edges()
				if subject == "":
					subject = "null"
				lines.append(current_prefix + "match %s:" % subject)
				appended = true
			"for":
				var variable := str(statement.get("variable", "")).strip_edges()
				var iterable := str(statement.get("iterable", "")).strip_edges()
				if variable == "":
					variable = "_"
				if iterable == "":
					iterable = "[]"
				lines.append(current_prefix + "for %s in %s:" % [variable, iterable])
				appended = true
			"while":
				var cond := str(statement.get("condition", "")).strip_edges()
				if cond == "":
					cond = "false"
				lines.append(current_prefix + "while %s:" % cond)
				appended = true
			"pass":
				lines.append(current_prefix + "pass")
				appended = true
			_:
				# Fallback for unknown types or legacy data
				if statement.has("text"):
					lines.append(current_prefix + str(statement.get("text", "")))
				else:
					lines.append(current_prefix + "# Unsupported block type: %s" % block_type)
				appended = true
	if not appended:
		lines.append(indent_prefix + "\tpass")
