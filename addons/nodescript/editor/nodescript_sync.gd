@tool
extends RefCounted
class_name NodeScriptSync

const NodeScriptConfig = preload("res://addons/nodescript/config.gd")
const NodeScriptResource = preload("res://addons/nodescript/core/nodescript_resource.gd")
const NodeScriptOrderUtils = preload("res://addons/nodescript/editor/nodescript_order_utils.gd")
const NodeScriptParser = preload("res://addons/nodescript/editor/nodescript_parser.gd")

var script_path: String = ""
var nodescript_path: String = ""
var nodescript: NodeScriptResource

# Auto-spacing preferences (initialised from config; read-only viewer still honors them for fidelity).
var auto_space_enabled: bool = NodeScriptConfig.get_auto_space_enabled()
var consolidate_blank_lines: bool = NodeScriptConfig.get_consolidate_blank_lines()
var auto_space_strategy: String = NodeScriptConfig.get_auto_space_strategy()


func load_for_script(script: Script) -> bool:
	if script == null:
		script_path = ""
		nodescript_path = ""
		nodescript = null
		return false

	script_path = _resolve_script_path(script.resource_path)
	if script_path == "":
		nodescript_path = ""
		nodescript = null
		return false

	nodescript_path = _deduce_nodescript_path(script_path, script)

	if ResourceLoader.exists(nodescript_path):
		nodescript = ResourceLoader.load(nodescript_path)
	else:
		nodescript = NodeScriptResource.new()

	_ensure_body_structure()
	NodeScriptParser.parse_script(script, nodescript, auto_space_enabled)
	_dedupe_body()
	_ensure_order_map()
	return _save_nodescript()


func _sync_from_script_source(script: Script) -> void:
	NodeScriptParser.parse_script(script, nodescript)
	_dedupe_body()


func _ensure_body_structure() -> void:
	if nodescript == null:
		nodescript = NodeScriptResource.new()
	if typeof(nodescript.body) != TYPE_DICTIONARY:
		nodescript.body = {}
	if not nodescript.body.has("order"):
		nodescript.body["order"] = {}
	if not nodescript.body.has("signals"):
		nodescript.body["signals"] = {}
	if not nodescript.body.has("variables"):
		nodescript.body["variables"] = []
	if not nodescript.body.has("enums"):
		nodescript.body["enums"] = {}
	if not nodescript.body.has("functions"):
		nodescript.body["functions"] = []
	if not nodescript.body.has("regions"):
		nodescript.body["regions"] = []
	if not nodescript.body.has("classes"):
		nodescript.body["classes"] = []


func _dedupe_body() -> void:
	if nodescript == null or typeof(nodescript.body) != TYPE_DICTIONARY:
		return
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

	var regions: Array = nodescript.body.get("regions", [])
	var seen_regions: Dictionary = {}
	var cleaned_regions: Array = []
	for r in regions:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var key := "%s|%s" % [str(r.get("class", "")), str(r.get("name", ""))]
		if seen_regions.has(key):
			continue
		seen_regions[key] = true
		cleaned_regions.append(r)
	nodescript.body["regions"] = cleaned_regions

	var classes: Array = nodescript.body.get("classes", [])
	var seen_classes: Dictionary = {}
	var cleaned_classes: Array = []
	for c in classes:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var key := str(c.get("name", ""))
		if seen_classes.has(key):
			continue
		seen_classes[key] = true
		cleaned_classes.append(c)
	nodescript.body["classes"] = cleaned_classes


func _ensure_order_map() -> void:
	if nodescript == null:
		return
	if typeof(nodescript.body) != TYPE_DICTIONARY:
		nodescript.body = {}
	var order_map: Dictionary = nodescript.body.get("order", {})
	order_map = NodeScriptOrderUtils.apply_auto_spacing(order_map, auto_space_enabled, consolidate_blank_lines, auto_space_strategy)
	nodescript.body["order"] = order_map


func _save_nodescript() -> bool:
	if nodescript == null:
		return false
	if nodescript_path == "":
		return false
	var err := ResourceSaver.save(nodescript, nodescript_path)
	if err != OK:
		push_error("NodeScript: Failed to save %s (error %d)" % [nodescript_path, err])
		return false
	return true


func _deduce_nodescript_path(resolved_path: String, script: Script) -> String:
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
	return dir.path_join(base_name + ".nodescript.tres")


func _resolve_script_path(path: String) -> String:
	if path.is_empty():
		return ""
	return path


func _log(message: String, level: int = 1) -> void:
	if level <= 0:
		push_error("[NodeScriptSync] " + message)
