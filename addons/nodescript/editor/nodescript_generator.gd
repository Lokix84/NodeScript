@tool
extends RefCounted
class_name NodeScriptGenerator

const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")
const NodeScriptOrderUtils = preload("res://addons/nodescript/editor/nodescript_order_utils.gd")

# Public API
static func generate_script_source(nodescript, auto_space_enabled: bool, consolidate_blank_lines: bool, auto_space_strategy: String, include_functions: bool = true) -> String:
	if nodescript == null:
		return ""
	var lines := _build_script_lines(nodescript, auto_space_enabled, consolidate_blank_lines, auto_space_strategy, include_functions)
	return _join_lines_with_newline(lines)


static func generate_declaration_source(nodescript, auto_space_enabled: bool, consolidate_blank_lines: bool, auto_space_strategy: String) -> String:
	if nodescript == null:
		return ""
	var lines := _build_script_lines(nodescript, auto_space_enabled, consolidate_blank_lines, auto_space_strategy, false)
	lines = _clean_declaration_lines(lines)
	return _join_lines_with_newline(lines)


# Core builders
static func _build_script_lines(nodescript, auto_space_enabled: bool, consolidate_blank_lines: bool, auto_space_strategy: String, include_functions: bool = true) -> Array[String]:
	var lines: Array[String] = []
	if nodescript == null:
		return lines

	_ensure_order_map(nodescript, auto_space_enabled, consolidate_blank_lines, auto_space_strategy)

	var meta: Dictionary = {}
	if typeof(nodescript.meta) == TYPE_DICTIONARY:
		meta = nodescript.meta

	if meta.get("tool", false):
		lines.append("@tool")

	var extends_value: String = str(meta.get("extends", "")).strip_edges()
	if extends_value != "":
		lines.append("extends " + extends_value)

	var class_name_value: String = str(meta.get("class_name", "")).strip_edges()
	if class_name_value != "":
		lines.append("class_name " + class_name_value)

	if not lines.is_empty():
		lines.append("")

	_append_scope(nodescript, lines, "", "", include_functions, "")

	return lines


static func _append_scope(nodescript, lines: Array[String], cls: String, region: String, include_functions: bool, indent_prefix: String) -> void:
	var emitted: Dictionary = {
		"region": {},
		"class": {},
		"signal": {},
		"enum": {},
		"variable": {},
		"function": {}
	}
	var order := _scope_order_for(nodescript, cls, region)
	for entry in order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind := str(entry.get("type", ""))
		var name := str(entry.get("name", ""))
		if kind == "blank":
			var count := int(entry.get("count", 1))
			var line_text := indent_prefix + _indent_from_entry(entry)
			for _i in range(max(1, count)):
				lines.append(line_text)
			continue
		if emitted.has(kind):
			var scope_map: Dictionary = emitted[kind]
			if scope_map.has(name):
				continue
			scope_map[name] = true
			emitted[kind] = scope_map
		match kind:
			"region":
				_append_region_scope(nodescript, lines, cls, name, include_functions, indent_prefix)
			"class":
				if cls != "":
					continue
				_append_class_scope(nodescript, lines, name, include_functions, indent_prefix)
			"signal":
				_append_single_signal(nodescript, lines, name, cls, region, indent_prefix)
			"enum":
				_append_single_enum(nodescript, lines, name, cls, region, indent_prefix)
			"variable":
				_append_single_variable(nodescript, lines, name, cls, region, indent_prefix)
			"function":
				if include_functions:
					_append_single_function(nodescript, lines, name, cls, region, indent_prefix)
			_:
				continue


static func _append_region_scope(nodescript, lines: Array[String], cls: String, region_name: String, include_functions: bool, indent_prefix: String) -> void:
	var trimmed := region_name.strip_edges()
	var has_header := trimmed != ""
	if has_header:
		lines.append(indent_prefix + "#region " + trimmed)
	_append_scope(nodescript, lines, cls, trimmed, include_functions, indent_prefix)
	if has_header:
		lines.append(indent_prefix + "#endregion " + trimmed)
	lines.append(indent_prefix + "")


static func _append_class_scope(nodescript, lines: Array[String], class_title: String, include_functions: bool, indent_prefix: String) -> void:
	var class_entry := _find_class_entry(nodescript, class_title)
	if class_entry.is_empty():
		return
	var class_region := _entry_region(class_entry)
	var order_entry := _order_lookup(nodescript, "", class_region, "class", class_title)
	if not order_entry.is_empty() and order_entry.has("code"):
		lines.append(_emit_line_with_prefix(order_entry, indent_prefix))
	else:
		var line: String = _class_header_line(class_entry)
		lines.append(indent_prefix + line)
	var before := lines.size()
	_append_scope(nodescript, lines, class_title, class_region, include_functions, indent_prefix + "\t")
	var has_body := _scope_has_content(lines, before)
	var only_regions := _scope_has_only_regions(lines, before)
	if not has_body or only_regions:
		lines.append(indent_prefix + "\tpass")
	lines.append(indent_prefix + "")


static func _scope_has_content(lines: Array[String], start: int) -> bool:
	for i in range(start, lines.size()):
		if lines[i].strip_edges() != "":
			return true
	return false


static func _scope_has_only_regions(lines: Array[String], start: int) -> bool:
	var any_region := false
	for i in range(start, lines.size()):
		var stripped := lines[i].strip_edges()
		if stripped == "":
			continue
		if stripped.begins_with("#region"):
			any_region = true
			continue
		if stripped.begins_with("#endregion"):
			continue
		return false
	return any_region


static func _append_single_signal(nodescript, lines: Array[String], name: String, cls: String, region: String, indent_prefix: String) -> void:
	var entry := _signal_entry(nodescript, name)
	if entry.is_empty():
		return
	if _entry_class(entry) != cls or _entry_region(entry) != region:
		return
	var order_entry := _order_lookup(nodescript, cls, region, "signal", name)
	if not order_entry.is_empty() and order_entry.has("code"):
		lines.append(_emit_line_with_prefix(order_entry, indent_prefix))
	else:
		var params: Array = []
		if entry.has("parameters") and typeof(entry["parameters"]) == TYPE_ARRAY:
			params = entry["parameters"]
		var declaration = "signal " + str(name)
		var formatted_params = _format_signal_parameters(params)
		if formatted_params != "":
			declaration += "(" + formatted_params + ")"
		lines.append(indent_prefix + declaration)
	lines.append(indent_prefix + "")


static func _append_single_enum(nodescript, lines: Array[String], name: String, cls: String, region: String, indent_prefix: String) -> void:
	var entry := _enum_entry(nodescript, name)
	if entry.is_empty():
		return
	if _enum_class(entry) != cls or _enum_region(entry) != region:
		return
	var order_entry := _order_lookup(nodescript, cls, region, "enum", name)
	if not order_entry.is_empty() and order_entry.has("code"):
		lines.append(_emit_line_with_prefix(order_entry, indent_prefix))
	else:
		var values: Array = _enum_values(entry)
		var body := "{}" if values.is_empty() else "{ " + ", ".join(values) + " }"
		if str(name).strip_edges() == "":
			lines.append(indent_prefix + "enum " + body)
		else:
			lines.append(indent_prefix + "enum %s %s" % [name, body])
	lines.append(indent_prefix + "")


static func _append_single_variable(nodescript, lines: Array[String], name: String, cls: String, region: String, indent_prefix: String) -> void:
	var entry := _variable_entry(nodescript, name)
	if entry.is_empty():
		return
	if _entry_class(entry) != cls or _entry_region(entry) != region:
		return
	var order_entry := _order_lookup(nodescript, cls, region, "variable", name)
	if not order_entry.is_empty() and order_entry.has("code"):
		lines.append(_emit_line_with_prefix(order_entry, indent_prefix))
	else:
		var annotations: Array[String] = _format_variable_annotations(entry)
		var var_line := _format_variable_line(entry)
		if annotations.is_empty():
			lines.append(indent_prefix + var_line)
		else:
			lines.append(indent_prefix + " ".join(annotations + [var_line]))


static func _append_single_function(nodescript, lines: Array[String], name: String, cls: String, region: String, indent_prefix: String) -> void:
	var fn_index := _function_index_by_name(nodescript, name)
	if fn_index == -1:
		return
	var method: Dictionary = _function_entry(nodescript, fn_index)
	if _entry_class(method) != cls or _entry_region(method) != region:
		return
	var order_entry := _order_lookup(nodescript, cls, region, "function", name)
	if not order_entry.is_empty() and order_entry.has("code"):
		lines.append(_emit_line_with_prefix(order_entry, indent_prefix))
		_append_function_body(lines, method, indent_prefix)
	else:
		lines.append(indent_prefix + _format_function_header(method))
		_append_function_body(lines, method, indent_prefix)
	lines.append(indent_prefix + "")


static func _collect_region_names(nodescript, class_title: String = "") -> Array[String]:
	var names: Array[String] = []
	if nodescript == null:
		return names
	var region_entries = nodescript.body.get("regions", [])
	if typeof(region_entries) == TYPE_ARRAY:
		for r in region_entries:
			var candidate := ""
			if typeof(r) == TYPE_DICTIONARY:
				if class_title != "":
					var region_class := str(r.get("class", "")).strip_edges()
					if region_class != "" and region_class != class_title:
						continue
					if region_class == "" and class_title != "":
						continue
				candidate = str(r.get("name", ""))
				var nested_region := str(r.get("region", "")).strip_edges()
				if nested_region != "" and not names.has(nested_region):
					names.append(nested_region)
			else:
				candidate = str(r)
			candidate = candidate.strip_edges()
			if candidate != "" and not names.has(candidate):
				names.append(candidate)

	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for value in signals_dict.values():
		var region_name := _entry_region(value)
		if class_title != "" and _entry_class(value) != class_title:
			continue
		if class_title == "" and _entry_class(value) != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var region_name := _enum_region(enums_dict.get(key, {}))
		var cls := _enum_class(enums_dict.get(key, {}))
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_name := _entry_region(entry)
		var cls := _entry_class(entry)
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	var functions_array: Array = nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var region_name := _entry_region(entry)
		var cls := _entry_class(entry)
		if class_title != "" and cls != class_title:
			continue
		if class_title == "" and cls != "":
			continue
		if region_name != "" and not names.has(region_name):
			names.append(region_name)

	return names


static func _append_region_block(nodescript, lines: Array[String], region_name: String, include_functions: bool, class_title: String = "", indent_prefix: String = "", classes: Array = []) -> void:
	var region_label := region_name.strip_edges()
	var has_header := region_label != ""
	if has_header:
		lines.append(indent_prefix + "#region " + region_label)
	_append_signals(nodescript, lines, region_label, class_title, indent_prefix)
	_append_enums(nodescript, lines, region_label, class_title, indent_prefix)
	_append_variables(nodescript, lines, region_label, class_title, indent_prefix)
	if class_title == "" and region_label != "":
		_append_classes_in_region(nodescript, lines, classes, region_label, include_functions, indent_prefix)
	if include_functions:
		_append_functions(nodescript, lines, region_label, class_title, indent_prefix)
	if has_header:
		if not lines.is_empty() and lines[lines.size() - 1].strip_edges() != "":
			lines.append(indent_prefix + "")
		lines.append(indent_prefix + "#endregion " + region_label)
		lines.append(indent_prefix + "")


static func _has_unscoped_entries_for_class(nodescript, class_title: String) -> bool:
	if nodescript == null:
		return false
	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for value in signals_dict.values():
		if _entry_class(value) != class_title:
			continue
		if _entry_region(value) == "":
			return true
	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for key in enums_dict.keys():
		var entry = enums_dict.get(key, {})
		if _enum_class(entry) != class_title:
			continue
		if _enum_region(entry) == "":
			return true
	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) != class_title:
			continue
		if _entry_region(entry) == "":
			return true
	var functions_array: Array = nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if _entry_class(entry) != class_title:
			continue
		if _entry_region(entry) == "":
			return true
	return false


static func _append_signals(nodescript, lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
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


static func _append_enums(nodescript, lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
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


static func _append_classes_in_region(nodescript, lines: Array[String], classes: Array, region_name: String, include_functions: bool, indent_prefix: String) -> void:
	if classes.is_empty():
		return
	var target := region_name.strip_edges()
	for cls in classes:
		if typeof(cls) != TYPE_DICTIONARY:
			continue
		var entry_region := str(cls.get("region", "")).strip_edges()
		if entry_region != target:
			continue
		_append_class_block(nodescript, lines, cls, include_functions, indent_prefix)


static func _append_class_block(nodescript, lines: Array[String], cls: Dictionary, include_functions: bool, indent_prefix: String = "") -> void:
	if typeof(cls) != TYPE_DICTIONARY:
		return
	var cname := str(cls.get("name", "")).strip_edges()
	if cname == "":
		return
	_append_class_name_line(lines, cls, indent_prefix)
	var member_count := _class_member_count(nodescript, cname)
	if member_count == 0:
		lines.append(indent_prefix + "\tpass")
		lines.append(indent_prefix + "")
		return
	var member_appended := false
	var regions := _collect_region_names(nodescript, cname)
	var appended_region := false
	for region_name in regions:
		if not _class_has_members(nodescript, cname, region_name):
			continue
		_append_region_block(nodescript, lines, region_name, include_functions, cname, indent_prefix + "\t")
		appended_region = true
		member_appended = true
	if not appended_region or _has_unscoped_entries_for_class(nodescript, cname):
		_append_region_block(nodescript, lines, "", include_functions, cname, indent_prefix + "\t")
		member_appended = true
	if _class_member_count(nodescript, cname) == 0:
		lines.append(indent_prefix + "\tpass")
	lines.append(indent_prefix + "")


static func _append_variables(nodescript, lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
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
				var combined := " ".join(annotations + [var_line])
				lines.append(indent_prefix + combined)
		wrote_any = true
	lines.append(indent_prefix + "")


static func _append_functions(nodescript, lines: Array[String], region: String = "", class_title: String = "", indent_prefix: String = "") -> void:
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
			lines.append(indent_prefix + "")
	for i in range(filtered.size()):
		var method = filtered[i]
		lines.append(indent_prefix + _format_function_header(method))
		_append_function_body(lines, method, indent_prefix)
		if i < filtered.size() - 1:
			lines.append(indent_prefix + "")


static func _clean_declaration_lines(lines: Array[String]) -> Array[String]:
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


# Formatting helpers
static func _join_lines_with_newline(lines: Array[String]) -> String:
	var script_text := "\n".join(lines)
	if script_text == "":
		return ""
	if not script_text.ends_with("\n"):
		script_text += "\n"
	return script_text


static func _format_signal_parameters(params: Array) -> String:
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


static func _format_variable_annotations(entry: Dictionary) -> Array[String]:
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


static func _format_variable_line(entry: Dictionary) -> String:
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


static func _variable_group(entry: Dictionary) -> String:
	if entry.get("const", false):
		return "const"
	if entry.get("export", false):
		return "export"
	if entry.get("onready", false):
		return "onready"
	return "var"


static func _format_function_header(method: Dictionary) -> String:
	var name: String = str(method.get("name", "function"))
	var header := "func " + name + "("
	var parameters: Array = method.get("parameters", [])
	header += _format_function_parameters(parameters) + ")"
	var return_type: String = str(method.get("return_type", "")).strip_edges()
	if return_type != "":
		header += " -> " + return_type
	header += ":"
	return header


static func _format_function_parameters(parameters: Array) -> String:
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


static func _append_function_body(lines: Array[String], method: Dictionary, indent_prefix: String = "") -> void:
	var body: Array = method.get("body", [])
	if body.is_empty():
		lines.append(indent_prefix + "\tpass")
		return
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
				if statement.has("text"):
					lines.append(current_prefix + str(statement.get("text", "")))
				else:
					lines.append(current_prefix + "# Unsupported block type: %s" % block_type)
				appended = true
	if not appended:
		lines.append(indent_prefix + "\tpass")


# Order helpers (local copies to avoid coupling back to NodeScriptSync internals)
static func _ensure_order_map(nodescript, auto_space_enabled: bool, consolidate_blank_lines: bool, auto_space_strategy: String) -> void:
	if nodescript == null:
		return
	if typeof(nodescript.body.get("order", null)) != TYPE_DICTIONARY:
		nodescript.body["order"] = {}
	nodescript.body["order"] = NodeScriptOrderUtils.apply_auto_spacing(nodescript.body["order"], auto_space_enabled, consolidate_blank_lines, auto_space_strategy)


static func _scope_key(cls: String, region: String) -> String:
	return "%s|%s" % [cls, region]


static func _scope_order_for(nodescript, cls: String, region: String) -> Array:
	_ensure_order_map(nodescript, true, true, "between_types") # spacing already applied upstream with real flags
	var order: Dictionary = nodescript.body.get("order", {})
	var scope_key_str := _scope_key(cls, region)
	if not order.has(scope_key_str):
		order[scope_key_str] = _generate_default_scope_order(nodescript, cls, region)
		nodescript.body["order"] = order
	return order.get(scope_key_str, [])


static func _generate_default_scope_order(nodescript, cls: String, region: String) -> Array:
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


static func _order_lookup(nodescript, cls: String, region: String, type: String, name: String) -> Dictionary:
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


static func _indent_from_entry(entry: Dictionary) -> String:
	var indent_count := int(entry.get("indent", 0))
	if indent_count < 0:
		indent_count = 0
	return " ".repeat(indent_count)


static func _emit_line_with_prefix(entry: Dictionary, indent_prefix: String) -> String:
	var code := str(entry.get("code", ""))
	var trimmed := code.lstrip(" \t")
	return indent_prefix + trimmed


# Lookups/utilities mirroring NodeScriptSync private helpers
static func _find_class_entry(nodescript, name: String) -> Dictionary:
	var classes: Array = nodescript.body.get("classes", [])
	for entry in classes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return entry
	return {}


static func _signal_entry(nodescript, name: String) -> Dictionary:
	var signals: Dictionary = nodescript.body.get("signals", {})
	if signals.has(name):
		var entry = signals.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


static func _enum_entry(nodescript, name: String) -> Dictionary:
	var enums: Dictionary = nodescript.body.get("enums", {})
	if enums.has(name):
		var entry = enums.get(name, {})
		return entry if typeof(entry) == TYPE_DICTIONARY else {}
	return {}


static func _variable_entry(nodescript, name: String) -> Dictionary:
	var vars: Array = nodescript.body.get("variables", [])
	for v in vars:
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if str(v.get("name", "")) == name:
			return v
	return {}


static func _function_index_by_name(nodescript, name: String) -> int:
	var functions_array: Array = nodescript.body.get("functions", [])
	for i in range(functions_array.size()):
		var entry = functions_array[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == name:
			return i
	return -1


static func _function_entry(nodescript, index: int) -> Dictionary:
	if nodescript == null:
		return {}
	var functions_array: Array = nodescript.body.get("functions", [])
	if index < 0 or index >= functions_array.size():
		return {}
	var entry = functions_array[index]
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


static func _entry_region(entry) -> String:
	return NodeScriptUtils.entry_region(entry)


static func _entry_class(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("class", "")).strip_edges()


static func _enum_values(entry) -> Array:
	return NodeScriptUtils.enum_values(entry)


static func _enum_region(entry) -> String:
	return NodeScriptUtils.enum_region(entry)


static func _enum_class(entry) -> String:
	return NodeScriptUtils.enum_class(entry)


static func _append_class_name_line(lines: Array[String], cls: Dictionary, indent_prefix: String = "") -> void:
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


static func _class_header_line(cls: Dictionary) -> String:
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


static func _class_has_members(nodescript, class_title: String, region: String) -> bool:
	return NodeScriptUtils.class_has_members(nodescript, class_title, region)


static func _class_member_count(nodescript, class_title: String) -> int:
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
