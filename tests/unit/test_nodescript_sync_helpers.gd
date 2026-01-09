@tool
extends RefCounted

const NodeScriptSync = preload("res://addons/nodescript/editor/nodescript_sync.gd")
const NodeScriptResource = preload("res://addons/nodescript/core/nodescript_resource.gd")

var _failures := 0

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


func test_normalize_body_adds_defaults() -> void:
	var sync := NodeScriptSync.new()
	var normalized := sync.normalize_body({})

	assert_true(normalized.has("functions"), "functions array exists")
	var funcs: Array = normalized.get("functions", [])
	assert_true(funcs.size() == 1, "default function added")
	var first: Dictionary = funcs[0]
	assert_eq(first.get("name", ""), "_ready", "default function name")
	var body: Array = first.get("body", []) as Array
	assert_true(body.size() > 0 and str(body[0].get("text", "")).find("NodeScript") != -1, "default body comment present")


func test_emit_declarations_respects_order_map() -> void:
	var sync := NodeScriptSync.new()
	sync.normalize_body({
		"signals": {"hit": {"name": "hit", "region": "", "class": ""}},
		"variables": [
			{"name": "mana", "type": "int", "value": "50", "region": "", "class": ""},
			{"name": "health", "type": "int", "value": "100", "region": "", "class": ""}
		],
		"functions": [],
		"regions": [],
		"classes": []
	})

	sync.set_scope_order("", "", [
		{"type": "variable", "name": "mana", "indent": 0, "line": 1, "code": "var mana: int = 50"},
		{"type": "variable", "name": "health", "indent": 0, "line": 2, "code": "var health: int = 100"},
		{"type": "signal", "name": "hit", "indent": 0, "line": 3, "code": "signal hit"},
	])

	var text := sync.emit_declarations(true)
	var mana_idx := text.find("var mana")
	var health_idx := text.find("var health")
	var signal_idx := text.find("signal hit")

	assert_true(mana_idx != -1 and health_idx != -1 and signal_idx != -1, "all declarations emitted")
	assert_true(mana_idx < health_idx and health_idx < signal_idx, "order map applied")


func test_set_scope_order_round_trip() -> void:
	var sync := NodeScriptSync.new()
	var ns := NodeScriptResource.new()
	sync.reset_nodescript(ns)

	var order := [
		{"type": "variable", "name": "a"},
		{"type": "function", "name": "f"}
	]
	sync.set_scope_order("", "", order)
	var round_trip := sync.emit_scope_order("", "")
	assert_eq(round_trip.size(), 2, "order round-trip size")
	assert_eq(round_trip[0].get("name", ""), "a", "first entry name")
	assert_eq(round_trip[1].get("type", ""), "function", "second entry type")


func test_add_update_delete_function_helpers() -> void:
	var sync := NodeScriptSync.new()
	var ns := NodeScriptResource.new()
	sync.reset_nodescript(ns)

	var fn = {
		"name": "attack",
		"class": "",
		"region": "",
		"parameters": [{"name": "amount", "type": "int"}],
		"return_type": "void",
		"body": [{"type": "pass", "text": "pass"}]
	}
	sync.add_function(fn)
	var order := sync.emit_scope_order("", "")
	assert_true(order.any(func(e): return e.get("name", "") == "attack"), "function added to order")

	# Update function return type
	sync.update_function("attack", "", "", {"return_type": "int"})
	var lines := sync.emit_declarations(true)
	assert_true(lines.find("func attack") != -1, "function present in declarations")

	# Delete function
	sync.delete_function("attack", "", "")
	order = sync.emit_scope_order("", "")
	assert_true(not order.any(func(e): return e.get("name", "") == "attack"), "function removed from order")
