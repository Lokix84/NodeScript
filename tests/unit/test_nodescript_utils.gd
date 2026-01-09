@tool
extends RefCounted

const NodeScriptUtils = preload("res://addons/nodescript/utils/nodescript_utils.gd")

var _failures: int = 0

func get_failure_count() -> int:
	return _failures

func assert_eq(a, b, msg: String = "") -> void:
	if typeof(a) != typeof(b) or a != b:
		_failures += 1
		print("    [FAIL] %s Expected '%s' but got '%s'" % [msg, str(b), str(a)])

func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("    [FAIL] %s (Expected True)" % msg)

func assert_false(cond: bool, msg: String) -> void:
	if cond:
		_failures += 1
		print("    [FAIL] %s (Expected False)" % msg)

func test_reserved_identifiers():
	var u = NodeScriptUtils
	assert_true(u.is_reserved_identifier("if"), "if is reserved")
	assert_true(u.is_reserved_identifier("Var"), "Var (mixed case) is reserved")
	assert_true(u.is_reserved_identifier("class_name"), "class_name is reserved")
	assert_false(u.is_reserved_identifier("my_var"), "my_var is ok")
	assert_false(u.is_reserved_identifier("Player"), "Player is ok")

func test_entry_helpers():
	var u = NodeScriptUtils
	var entry = {"region": "Head", "class": "Enemy"}
	assert_eq(u.entry_region(entry), "Head", "entry_region")
	assert_eq(u.entry_class(entry), "Enemy", "entry_class")
	
	var empty = {}
	assert_eq(u.entry_region(empty), "", "entry_region empty")
	assert_eq(u.entry_class(empty), "", "entry_class empty")
	
	var enum_entry = {"region": "R", "class": "C", "values": ["A"]}
	assert_eq(u.enum_region(enum_entry), "R", "enum_region")
	assert_eq(u.enum_class(enum_entry), "C", "enum_class")
	assert_eq(u.enum_values(enum_entry), ["A"], "enum_values")

func test_class_has_members():
	pass
	# This requires a full 'nodescript' object mock, which is complex.
	# Leaving empty for now or implementing basic mock if needed.
