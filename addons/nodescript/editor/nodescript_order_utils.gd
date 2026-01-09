@tool
extends RefCounted
class_name NodeScriptOrderUtils

# Apply automatic spacing/consolidation to an order map and return the updated map.
static func apply_auto_spacing(order: Dictionary, auto_space_enabled: bool, consolidate_blank_lines: bool, auto_space_strategy: String) -> Dictionary:
	if order.is_empty():
		return order

	for scope_key in order.keys():
		var scope_order: Array = order.get(scope_key, [])
		if typeof(scope_order) != TYPE_ARRAY:
			continue

		_ensure_blank_counts(scope_order)
		_strip_auto_spacing_blanks(scope_order, not auto_space_enabled)

		if auto_space_enabled:
			match auto_space_strategy:
				"between_types":
					_apply_spacing_between_types(scope_order)
				"after_groups":
					_apply_spacing_after_groups(scope_order)
				_:
					pass

		if consolidate_blank_lines:
			_consolidate_blank_entries(scope_order)

		order[scope_key] = scope_order

	return order


static func _apply_spacing_between_types(scope_order: Array) -> void:
	var spacing_after_types := ["signal", "enum", "region", "class"]
	var result: Array = []
	var last_type := ""

	for entry in scope_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var entry_type := str(entry.get("type", ""))

		if entry_type == "blank":
			result.append(entry)
			last_type = entry_type
			continue

		if last_type != "" and last_type != "blank" and last_type in spacing_after_types and entry_type != "blank":
			var already_blank := not result.is_empty() and str(result.back().get("type", "")) == "blank"
			if not already_blank:
				result.append({"type": "blank", "name": "", "auto_spacing": true})

		result.append(entry)
		last_type = entry_type

	while scope_order.size() > 0:
		scope_order.pop_back()
	scope_order.append_array(result)


static func _apply_spacing_after_groups(scope_order: Array) -> void:
	var type_groups := [
		["variable"],
		["signal"],
		["enum"],
		["region", "class"],
		["function"]
	]

	var result: Array = []
	var current_group_idx := -1
	var has_blank_after_group := false

	for entry in scope_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var entry_type := str(entry.get("type", ""))

		if entry_type == "blank":
			has_blank_after_group = true
			result.append(entry)
			continue

		var entry_group_idx := -1
		for group_idx in range(type_groups.size()):
			if entry_type in type_groups[group_idx]:
				entry_group_idx = group_idx
				break

		if entry_group_idx != -1 and current_group_idx != -1 and entry_group_idx != current_group_idx and not has_blank_after_group:
			var already_blank := not result.is_empty() and str(result.back().get("type", "")) == "blank"
			if not already_blank:
				result.append({"type": "blank", "name": "", "auto_spacing": true})

		result.append(entry)
		current_group_idx = entry_group_idx
		has_blank_after_group = false

	while scope_order.size() > 0:
		scope_order.pop_back()
	scope_order.append_array(result)


static func _consolidate_blank_entries(scope_order: Array) -> void:
	var result: Array = []
	var last_was_blank := false
	var last_was_manual := false
	var last_blank_index := -1
	for entry in scope_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_type := str(entry.get("type", ""))
		if entry_type == "blank":
			var manual_blank: bool = bool(entry.get("manual_blank", true))
			if last_was_blank:
				if last_blank_index >= 0 and last_blank_index < result.size():
					var prev = result[last_blank_index]
					if typeof(prev) == TYPE_DICTIONARY:
						var prev_count := int(prev.get("count", 1))
						var this_count := int(entry.get("count", 1))
						prev["count"] = prev_count + (this_count if this_count > 0 else 1)
						result[last_blank_index] = prev
				continue
			last_was_blank = true
			last_was_manual = manual_blank
			last_blank_index = result.size()
			result.append(entry)
			continue
		last_was_blank = false
		last_was_manual = false
		last_blank_index = -1
		result.append(entry)

	while scope_order.size() > 0:
		scope_order.pop_back()
	scope_order.append_array(result)


static func _strip_auto_spacing_blanks(scope_order: Array, remove_unflagged: bool) -> void:
	var cleaned: Array = []
	for entry in scope_order:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_type := str(entry.get("type", ""))
		var is_blank := entry_type == "blank"
		var auto_spacing: bool = bool(entry.get("auto_spacing", false))
		var manual_blank: bool = bool(entry.get("manual_blank", true))
		if is_blank:
			if auto_spacing:
				continue
			if remove_unflagged and not manual_blank:
				continue
		cleaned.append(entry)
	while scope_order.size() > 0:
		scope_order.pop_back()
	scope_order.append_array(cleaned)


static func _ensure_blank_counts(scope_order: Array) -> void:
	for i in range(scope_order.size()):
		var entry = scope_order[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("type", "")) != "blank":
			continue
		if not entry.has("count") or int(entry.get("count", 0)) <= 0:
			entry["count"] = 1
		scope_order[i] = entry
