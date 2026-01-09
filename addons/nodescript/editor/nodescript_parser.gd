@tool
extends RefCounted
class_name NodeScriptParser

const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")

const DEFAULT_METHOD_BODY_COMMENT := "NodeScript: default method body"
const DEFAULT_METHOD_BODY := [
	{"type": "comment", "text": DEFAULT_METHOD_BODY_COMMENT},
	{"type": "pass", "text": "pass"}
]

# Parse a script resource into the provided NodeScriptResource (mutates it in place).
static func parse_script(script: Script, nodescript, auto_space_enabled: bool = true) -> void:
	if nodescript == null or script == null:
		return
	var source := script.source_code
	if source.strip_edges() == "":
		return

	var lines: PackedStringArray = source.split("\n", true)
	var signals: Dictionary = {}
	var enums: Dictionary = {}
	var variables: Array = []
	var functions: Array = []
	var pending_annotations: Array[String] = []
	var current_function: Dictionary = {}
	var current_function_indent: int = -1
	var current_function_line: int = 0
	var regions: Array = []
	var current_region: String = ""
	var current_region_line: int = 0
	var region_stack: Array[String] = []
	var classes: Array = []
	var current_class: String = ""
	var current_class_line: int = 0
	var seen_classes: Dictionary = {}
	var order_map: Dictionary = {}
	var last_blank_for_scope: Dictionary = {}
	var scope_has_content: Dictionary = {}

	for i in range(lines.size()):
		var line := lines[i]
		var indent := _count_line_indent(line)
		var trimmed := line.strip_edges()
		var scope_key := _scope_key(current_class, current_region)

		if trimmed.begins_with("#region"):
			current_region = trimmed.substr("#region".length()).strip_edges()
			current_region_line = i + 1
			var parent_region: String = region_stack.back() if not region_stack.is_empty() else ""
			if current_region.strip_edges() != "" and not _region_exists(regions, current_region, current_class, parent_region):
				regions.append({"name": current_region, "class": current_class, "region": parent_region, "def_line": current_region_line, "scope_line": current_class_line if current_class != "" else 0})
			if current_region.strip_edges() != "":
				_append_order_entry(order_map, current_class, parent_region, "region", current_region, i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, _scope_key(current_class, parent_region))
			region_stack.append(current_region)
			continue

		if trimmed.begins_with("#endregion"):
			if not region_stack.is_empty():
				region_stack.pop_back()
			current_region = region_stack.back() if not region_stack.is_empty() else ""
			current_region_line = 0
			continue

		if trimmed.begins_with("class "):
			var cls_name := _parse_class_name(trimmed)
			if cls_name != "":
				_append_order_entry(order_map, "", current_region, "class", cls_name, i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, _scope_key("", current_region))
				current_class = cls_name
				current_class_line = i + 1
				if not seen_classes.has(cls_name):
					classes.append({"name": cls_name, "extends": _parse_class_extends(trimmed), "region": current_region, "def_line": current_class_line, "scope_line": 0})
					seen_classes[cls_name] = true
			continue
		if current_class != "" and indent == 0 and not trimmed.begins_with("class "):
			current_class = ""
			current_class_line = 0

		var has_current_function := not current_function.is_empty()

		if has_current_function:
			if trimmed == "":
				_append_function_body_line(current_function, line)
				continue
			if indent <= current_function_indent:
				current_function = {}
				current_function_indent = -1
				has_current_function = false
			else:
				_append_function_body_line(current_function, line)
				continue

		if trimmed == "":
			if scope_has_content.get(scope_key, false):
				var scope_arr: Array = order_map.get(scope_key, [])
				if not scope_arr.is_empty() and typeof(scope_arr.back()) == TYPE_DICTIONARY and str(scope_arr.back().get("type", "")) == "blank":
					var last_entry: Dictionary = scope_arr.back()
					last_entry["count"] = int(last_entry.get("count", 1)) + 1
					scope_arr[scope_arr.size() - 1] = last_entry
					order_map[scope_key] = scope_arr
				else:
					_append_order_entry(order_map, current_class, current_region, "blank", "", i + 1, "", indent, true, false)
					scope_arr = order_map.get(scope_key, [])
					if not scope_arr.is_empty():
						scope_arr[scope_arr.size() - 1]["count"] = 1
						order_map[scope_key] = scope_arr
			continue
		if trimmed.begins_with("#"):
			continue

		if trimmed.begins_with("class_name "):
			nodescript.meta["class_name"] = trimmed.substr("class_name ".length()).strip_edges()
			continue
		if trimmed.begins_with("extends "):
			nodescript.meta["extends"] = trimmed.substr("extends ".length()).strip_edges()
			continue

		var working := trimmed
		var annotations := pending_annotations.duplicate()

		while working.begins_with("@"):
			var space_index := working.find(" ")
			var annotation := working if space_index == -1 else working.substr(0, space_index)
			if annotation != "":
				annotations.append(annotation)
			if space_index == -1:
				if has_current_function and not current_function.has("body"):
					current_function["body"] = []
				if has_current_function:
					current_function["body"].append({"type": "annotation", "text": annotation})
				working = ""
				break
			working = working.substr(space_index + 1).strip_edges()

		if working == "":
			pending_annotations = annotations
			continue

		if _begins_with_func(working):
			var signature_text := _strip_to_func_keyword(working)
			var func_info = _parse_function_signature(signature_text, current_region)
			if func_info.size() > 0:
				func_info["class"] = current_class
				func_info["def_line"] = i + 1
				func_info["scope_line"] = current_class_line if current_class != "" else 0
				_append_order_entry(order_map, current_class, current_region, "function", str(func_info.get("name", "")), i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, scope_key)
				functions.append(func_info)
				current_function = func_info
				current_function_indent = indent
				current_function_line = i + 1
			pending_annotations.clear()
			continue

		if working.begins_with("signal "):
			var signal_info = _parse_signal_line(working)
			if signal_info and signal_info.has("name"):
				var signal_entry: Dictionary = {"parameters": signal_info.get("parameters", [])}
				signal_entry["region"] = current_region
				signal_entry["class"] = current_class
				signal_entry["scope_line"] = current_class_line if current_class != "" else 0
				signals[signal_info["name"]] = signal_entry
				_append_order_entry(order_map, current_class, current_region, "signal", str(signal_info.get("name", "")), i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, scope_key)
			pending_annotations.clear()
			continue

		if working.begins_with("enum "):
			var enum_info = _parse_enum_line(working)
			if enum_info and enum_info.has("name"):
				enum_info["region"] = current_region
				enum_info["class"] = current_class
				enum_info["scope_line"] = current_class_line if current_class != "" else 0
				enums[enum_info["name"]] = enum_info
				_append_order_entry(order_map, current_class, current_region, "enum", str(enum_info.get("name", "")), i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, scope_key)
			pending_annotations.clear()
			continue

		if working.begins_with("var ") or working.begins_with("const "):
			var var_info = _parse_variable_line(working, annotations, current_region)
			if var_info:
				var_info["class"] = current_class
				var_info["scope_line"] = current_class_line if current_class != "" else 0
				variables.append(var_info)
				_append_order_entry(order_map, current_class, current_region, "variable", str(var_info.get("name", "")), i + 1, trimmed, indent)
				_mark_scope_content(scope_has_content, last_blank_for_scope, scope_key)
			pending_annotations.clear()
			continue

		if trimmed.begins_with("@"):
			pending_annotations.append(trimmed.split(" ", false, 2)[0])
			continue

		pending_annotations.clear()

	var cleaned_functions: Array = []
	for f in functions:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var fname := str(f.get("name", "")).strip_edges()
		if fname == "":
			continue
		cleaned_functions.append(f)

	if cleaned_functions.is_empty():
		cleaned_functions = []

	nodescript.body["signals"] = signals
	nodescript.body["variables"] = variables
	nodescript.body["enums"] = enums
	nodescript.body["functions"] = cleaned_functions
	nodescript.body["regions"] = regions
	nodescript.body["classes"] = classes
	nodescript.body["order"] = order_map


# --- Helper functions (copied from previous parser section) ---
static func _count_line_indent(line: String) -> int:
	var count := 0
	for i in range(line.length()):
		var char := line[i]
		if char == " ":
			count += 1
		elif char == "\t":
			count += 4
		else:
			break
	return count


static func _mark_scope_content(scope_has_content: Dictionary, last_blank_for_scope: Dictionary, scope_key: String) -> void:
	scope_has_content[scope_key] = true
	last_blank_for_scope[scope_key] = false


static func _append_function_body_line(function_dict: Dictionary, line: String) -> void:
	if function_dict == null:
		return
	if not function_dict.has("body") or typeof(function_dict["body"]) != TYPE_ARRAY:
		function_dict["body"] = []
	else:
		if function_dict["body"].size() == 1:
			var first = function_dict["body"][0]
			if typeof(first) == TYPE_DICTIONARY and str(first.get("type", "")) == "comment" and str(first.get("text", "")).strip_edges() == DEFAULT_METHOD_BODY_COMMENT:
				function_dict["body"] = []
	function_dict["body"].append({
		"type": "raw",
		"text": line
	})


static func _parse_signal_line(line: String) -> Dictionary:
	var working = line.substr("signal ".length()).strip_edges()
	var name = working
	var params_string = ""
	var paren_start = working.find("(")
	if paren_start != -1:
		name = working.substr(0, paren_start).strip_edges()
		var paren_end = working.rfind(")")
		if paren_end == -1:
			paren_end = working.length()
		params_string = working.substr(paren_start + 1, paren_end - paren_start - 1)
	return {"name": name, "parameters": _parse_parameters(params_string)}


static func _parse_enum_line(line: String) -> Dictionary:
	var working = line.substr("enum ".length()).strip_edges()
	var name = ""
	var values: Array = []
	var brace_index = working.find("{")
	if brace_index != -1:
		name = working.substr(0, brace_index).strip_edges()
		if name.ends_with(":"):
			name = name.left(name.length() - 1).strip_edges()
		var body = working.substr(brace_index + 1, working.length() - brace_index - 1)
		var closing = body.find("}")
		if closing != -1:
			body = body.left(closing)
		for value in body.split(",", false):
			var trimmed = value.strip_edges()
			if trimmed != "":
				values.append(trimmed)
	elif ":" in working:
		name = working.split(":", false, 2)[0].strip_edges()
	else:
		name = working.strip_edges()
	return {"name": name, "values": values}


static func _parse_variable_line(line: String, annotations: Array[String], region: String) -> Dictionary:
	var constant = false
	var working = line
	if working.begins_with("const "):
		constant = true
		working = working.substr("const ".length()).strip_edges()
	else:
		working = working.substr("var ".length()).strip_edges()

	var name = working
	var type_hint = ""
	var default_value = ""

	if ":" in working:
		var parts = working.split(":", false, 2)
		name = parts[0].strip_edges()
		var rest = parts[1].strip_edges()
		if "=" in rest:
			var type_and_value = rest.split("=", false, 2)
			if type_and_value.size() >= 2:
				type_hint = type_and_value[0].strip_edges()
				default_value = type_and_value[1].strip_edges()
			else:
				type_hint = rest
				default_value = ""
		else:
			type_hint = rest
	else:
		if "=" in working:
			var name_and_value = working.split("=", false, 2)
			if name_and_value.size() >= 2:
				name = name_and_value[0].strip_edges()
				default_value = name_and_value[1].strip_edges()
			else:
				name = working.strip_edges()
				default_value = ""

	return {
		"name": name,
		"type": type_hint,
		"value": default_value,
		"export": _annotations_have(annotations, "@export"),
		"onready": _annotations_have(annotations, "@onready"),
		"const": constant,
		"region": region
	}


static func _parse_class_name(line: String) -> String:
	var working := line.substr("class ".length()).strip_edges()
	if working.ends_with(":"):
		working = working.left(working.length() - 1).strip_edges()
	if "(" in working:
		return working.split("(", false, 2)[0].strip_edges()
	return working


static func _parse_class_extends(line: String) -> String:
	var working := line.substr("class ".length()).strip_edges()
	var paren_start := working.find("(")
	var paren_end := working.find(")")
	if paren_start == -1 or paren_end == -1 or paren_end <= paren_start:
		return ""
	return working.substr(paren_start + 1, paren_end - paren_start - 1).strip_edges()


static func _parse_function_signature(line: String, region: String) -> Dictionary:
	var working = line.substr("func ".length()).strip_edges()
	if working.ends_with(":"):
		working = working.left(working.length() - 1).strip_edges()
	var return_type = ""
	if "->" in working:
		var func_and_type = working.split("->", false, 2)
		working = func_and_type[0].strip_edges()
		return_type = func_and_type[1].strip_edges()
	var paren_start = working.find("(")
	var paren_end = working.rfind(")")
	if paren_start == -1 or paren_end == -1:
		return {}
	var name = working.substr(0, paren_start).strip_edges()
	if name == "":
		return {}
	var params_string = working.substr(paren_start + 1, paren_end - paren_start - 1)
	return {
		"name": name,
		"parameters": _parse_parameters(params_string),
		"return_type": return_type,
		"region": region,
		"body": DEFAULT_METHOD_BODY.duplicate(true)
	}


static func _parse_parameters(param_string: String) -> Array:
	var params: Array = []
	if param_string.strip_edges() == "":
		return params
	var pieces = param_string.split(",", false)
	for piece in pieces:
		var segment = piece.strip_edges()
		if segment == "":
			continue
		var name = segment
		var type_hint = ""
		var default_value = ""
		if ":" in segment:
			var parts = segment.split(":", false, 2)
			name = parts[0].strip_edges()
			var rest = parts[1].strip_edges()
			if "=" in rest:
				var type_and_default = rest.split("=", false, 2)
				type_hint = type_and_default[0].strip_edges()
				default_value = type_and_default[1].strip_edges()
			else:
				type_hint = rest
		else:
			if "=" in segment:
				var name_and_default = segment.split("=", false, 2)
				name = name_and_default[0].strip_edges()
				default_value = name_and_default[1].strip_edges()
		params.append({
			"name": name,
			"type": type_hint,
			"default": default_value
		})
	return params


static func _begins_with_func(text: String) -> bool:
	var t := text.strip_edges()
	if t.begins_with("func "):
		return true
	for prefix in ["static func ", "virtual func ", "override func "]:
		if t.begins_with(prefix):
			return true
	return false


static func _strip_to_func_keyword(text: String) -> String:
	var t := text.strip_edges()
	var idx := t.find("func ")
	if idx == -1:
		return t
	return t.substr(idx, t.length() - idx)


static func _annotations_have(annotations: Array[String], token: String) -> bool:
	for annotation in annotations:
		if annotation.begins_with(token):
			return true
	return false


static func _scope_key(cls: String, region: String) -> String:
	return "%s|%s" % [cls, region]


static func _append_order_entry(order_map: Dictionary, cls: String, region: String, type: String, name: String, line_number: int, code: String, indent: int, manual_blank: bool = false, auto_spacing: bool = false) -> void:
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


static func _next_blank_name(scope_entries: Array) -> String:
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


static func _region_exists(regions: Array, name: String, cls: String = "", parent_region: String = "") -> bool:
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

#endregion
