@tool
extends RefCounted

const StatementClassifier = preload("res://addons/nodescript/utils/statement_classifier.gd")

var _failures: int = 0

func get_failure_count() -> int:
	return _failures

func assert_eq(a, b, msg: String = "") -> void:
	if typeof(a) != typeof(b) or a != b:
		_failures += 1
		print("    [FAIL] %s Expected '%s' but got '%s'" % [msg, str(b), str(a)])
	else:
		# print("    [OK] %s" % msg)
		pass

func test_variable_declarations():
	var c = StatementClassifier
	
	var r = c.classify_line("var a = 1")
	assert_eq(r.get("type"), "assignment", "var decl")
	assert_eq(r.get("target"), "a", "target a")
	assert_eq(r.get("expr"), "1", "expr 1")
	
	r = c.classify_line("const PI = 3.14")
	assert_eq(r.get("type"), "assignment", "const decl")
	assert_eq(r.get("target"), "PI", "target PI")
	
	r = c.classify_line("var x: int = 5")
	assert_eq(r.get("type"), "assignment", "typed decl")
	assert_eq(r.get("target"), "x: int", "target x: int")

func test_control_flow():
	var c = StatementClassifier
	
	var r = c.classify_line("if x > 0:")
	assert_eq(r.get("type"), "if", "if type")
	assert_eq(r.get("condition"), "x > 0:", "condition x > 0:")
	
	r = c.classify_line("elif  y:")
	assert_eq(r.get("type"), "elif", "elif type")
	assert_eq(r.get("condition"), "y:", "condition y:")

	r = c.classify_line("for i in xs:")
	assert_eq(r.get("type"), "for", "for")
	
	r = c.classify_line("while  true:")
	assert_eq(r.get("type"), "while", "while")
	
	r = c.classify_line("match x:")
	assert_eq(r.get("type"), "match", "match")
	
	r = c.classify_line("pass")
	assert_eq(r.get("type"), "pass", "pass")

func test_signals():
	var c = StatementClassifier
	
	var r = c.classify_line("emit_signal(\"my_sig\", 1, 2)")
	assert_eq(r.get("type"), "signal_emit", "signal type")
	assert_eq(r.get("signal"), "my_sig", "signal name")

func test_assignments():
	var c = StatementClassifier
	
	var r = c.classify_line("x = 5")
	assert_eq(r.get("type"), "assignment", "simple assignment")
	
	r = c.classify_line("x += 1")
	assert_eq(r.get("type"), "assignment", "add assign")
	assert_eq(r.get("target"), "x", "add assign target")
	assert_eq(r.get("expr"), "1", "add assign expr")
