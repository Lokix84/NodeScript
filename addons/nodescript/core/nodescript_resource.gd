@tool
extends Resource
class_name NodeScriptResource

@export var meta: Dictionary = {
	"class_name": "",
	"extends": "",
	"tool": false,
	"doc": ""
}

@export var body: Dictionary = {
	"enums": {},
	"signals": {},
	"variables": [],
	"functions": [],   # Array of function dictionaries
	"regions": []      # Array of region dictionaries { "name": String }
	,"classes": []     # Array of class dictionaries { "name": String, "extends": String }
}

@export var last_generated_hash: String = ""


func set_class_name(name: String) -> void:
	meta["class_name"] = name


func get_class_name() -> String:
	return meta.get("class_name", "")


func set_extends(base: String) -> void:
	meta["extends"] = base


func get_extends() -> String:
	return meta.get("extends", "")
