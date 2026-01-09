@tool
extends RefCounted
class_name NodeScriptConfig

# Central configuration for the NodeScript plugin.
# Values are read from res://addons/nodescript/config.cfg if present.

const CONFIG_PATH := "res://addons/nodescript/config.cfg"
const CONFIG_SECTION := "nodescript"

const DEFAULTS := {
	"show_enum_values_in_tree": true,
	"log_level": 1, # 0 = silent, 1 = minimal, 2 = verbose
	"tree_display_mode": 1, # 0 grouped/sorted, 1 true order, 2 flat sorted
	"auto_space_strategy": "between_types", # none, between_types, after_groups
	"auto_space_enabled": true,
	"consolidate_blank_lines": true
}

# Auto-space strategy modes:
# - "none": No automatic blank lines
# - "between_types": Insert blank after signals, enums, regions, classes
# - "after_groups": Insert blank after each type group (variables, signals, enums, etc)


static func get_setting(key: String, fallback=null):
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return DEFAULTS.get(key, fallback)
	return cfg.get_value(CONFIG_SECTION, key, DEFAULTS.get(key, fallback))


static func set_setting(key: String, value) -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		cfg = ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, key, value)
	cfg.save(CONFIG_PATH)


static func get_bool(key: String, fallback: bool = false) -> bool:
	var v = get_setting(key, fallback)
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_STRING:
			var lower: String = v.to_lower()
			if lower == "true":
				return true
			if lower == "false":
				return false
			return lower != ""
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		_:
			return bool(v)


static func get_int(key: String, fallback: int = 0) -> int:
	return int(get_setting(key, fallback))


static func set_bool(key: String, value: bool) -> void:
	set_setting(key, value)


static func set_int(key: String, value: int) -> void:
	set_setting(key, value)


static func get_log_level() -> int:
	return get_int("log_level", DEFAULTS["log_level"])


static func get_auto_space_strategy() -> String:
	var strategy = get_setting("auto_space_strategy", DEFAULTS["auto_space_strategy"])
	var valid_strategies := ["none", "between_types", "after_groups"]
	if str(strategy) in valid_strategies:
		return str(strategy)
	return DEFAULTS["auto_space_strategy"]


static func get_auto_space_enabled() -> bool:
	return get_bool("auto_space_enabled", DEFAULTS["auto_space_enabled"])


static func set_auto_space_enabled(enabled: bool) -> void:
	set_bool("auto_space_enabled", enabled)


static func get_consolidate_blank_lines() -> bool:
	return get_bool("consolidate_blank_lines", DEFAULTS["consolidate_blank_lines"])


static func set_consolidate_blank_lines(enabled: bool) -> void:
	set_bool("consolidate_blank_lines", enabled)


static func set_tree_display_mode(mode: int) -> void:
	set_int("tree_display_mode", mode)


static func get_tree_display_mode() -> int:
	return get_int("tree_display_mode", DEFAULTS.get("tree_display_mode", 1))
