@tool
extends RefCounted
class_name NodeScriptUtils

static func entry_region(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("region", "")).strip_edges()

static func entry_class(entry) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str(entry.get("class", "")).strip_edges()

static func enum_values(entry) -> Array:
	if typeof(entry) == TYPE_DICTIONARY:
		return entry.get("values", [])
	if typeof(entry) == TYPE_ARRAY:
		return entry
	return []

static func enum_region(entry) -> String:
	if typeof(entry) == TYPE_DICTIONARY:
		return str(entry.get("region", "")).strip_edges()
	return ""

static func enum_class(entry) -> String:
	if typeof(entry) == TYPE_DICTIONARY:
		return str(entry.get("class", "")).strip_edges()
	return ""


static func is_reserved_identifier(name: String) -> bool:
	var n := name.strip_edges()
	if n == "":
		return false
	var lowered := n.to_lower()
	var keywords := [
		"if", "elif", "else", "for", "while", "match", "break", "continue", "pass", "return",
		"class", "class_name", "extends", "func", "var", "const", "enum", "signal", "static",
		"onready", "tool", "remote", "remotesync", "puppet", "puppetsync", "master", "mastersync",
		"self", "super", "true", "false", "null", "as", "is", "in", "and", "or", "not", "_"
	]
	return lowered in keywords

static func class_has_members(nodescript, class_title: String, region: String = "") -> bool:
	if nodescript == null:
		return false
	var cls := class_title.strip_edges()
	if cls == "":
		return false
	var target_region := region.strip_edges()

	var signals_dict: Dictionary = nodescript.body.get("signals", {})
	for entry in signals_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cls:
			continue
		if target_region == "" or entry_region(entry) == target_region:
			return true

	var enums_dict: Dictionary = nodescript.body.get("enums", {})
	for entry in enums_dict.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cls:
			continue
		if target_region == "" or enum_region(entry) == target_region:
			return true

	var variables_array: Array = nodescript.body.get("variables", [])
	for entry in variables_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cls:
			continue
		if target_region == "" or entry_region(entry) == target_region:
			return true

	var functions_array: Array = nodescript.body.get("functions", [])
	for entry in functions_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")).strip_edges() != cls:
			continue
		if target_region == "" or entry_region(entry) == target_region:
			return true

	return false
