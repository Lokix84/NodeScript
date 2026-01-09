@tool
extends RefCounted
class_name NodeScriptStatementClassifier

# Classifies a single line of code text into a normalized statement dictionary:
# {
#   "type": String, # e.g. comment, assignment, call, signal_emit, signal_connect, if, elif, else, match, case, default_case, for, while, return, pass, break, continue, raw
#   "text": String, # the original trimmed text
#   ...type-specific keys...
# }
static func classify_line(text: String) -> Dictionary:
	var trimmed := str(text).strip_edges()
	if trimmed == "":
		return {}

	# Comments
	if trimmed.begins_with("#"):
		return {"type": "comment", "text": trimmed.trim_prefix("#").strip_edges()}

	# Declarations / assignments
	if trimmed.begins_with("var ") or trimmed.begins_with("const "):
		return _classify_assignment(trimmed)

	# Conditionals
	if trimmed.begins_with("if "):
		return {"type": "if", "condition": trimmed.substr(3).strip_edges(), "text": trimmed}
	if trimmed.begins_with("elif "):
		return {"type": "elif", "condition": trimmed.substr(5).strip_edges(), "text": trimmed}
	if trimmed.begins_with("else"):
		return {"type": "else", "text": trimmed}

	# Match / cases
	if trimmed.begins_with("match "):
		return {"type": "match", "subject": trimmed.substr(6).strip_edges(), "text": trimmed}
	if trimmed.begins_with("case "):
		var pat := trimmed.substr(5).strip_edges().trim_suffix(":").strip_edges()
		return {"type": "case", "pattern": pat, "text": trimmed}
	if trimmed.begins_with("_:"):
		return {"type": "default_case", "text": trimmed}

	# Loops
	if trimmed.begins_with("for "):
		return {"type": "for", "text": trimmed}
	if trimmed.begins_with("while "):
		return {"type": "while", "text": trimmed}

	# Control flow
	if trimmed.begins_with("return"):
		return {"type": "return", "text": trimmed}
	if trimmed.begins_with("pass"):
		return {"type": "pass", "text": trimmed}
	if trimmed.begins_with("break"):
		return {"type": "break", "text": trimmed}
	if trimmed.begins_with("continue"):
		return {"type": "continue", "text": trimmed}

	# Signals
	if trimmed.begins_with("emit_signal("):
		var inside := trimmed.substr("emit_signal(".length())
		if inside.find(")") != -1:
			inside = inside.substr(0, inside.find(")"))
		var args := inside.split(",", false)
		var sig := ""
		if args.size() > 0:
			sig = str(args[0]).strip_edges().trim_prefix("\"").trim_prefix("'").trim_suffix("\"").trim_suffix("'")
		return {"type": "signal_emit", "signal": sig, "text": trimmed}
	if trimmed.begins_with("connect(") or trimmed.begins_with(".connect("):
		return {"type": "signal_connect", "text": trimmed}
	if trimmed.begins_with("disconnect(") or trimmed.begins_with(".disconnect("):
		return {"type": "signal_disconnect", "text": trimmed}

	# Assignment operators
	var assignment_ops := ["+=", "-=", "*=", "/=", "="]
	for op in assignment_ops:
		var op_idx := trimmed.find(op)
		if op_idx > 0:
			# ensure not part of == or >= etc for "=" detection
			if op == "=" and (trimmed.substr(op_idx, 2) == "==" or trimmed.substr(op_idx, 2) == ">=" or trimmed.substr(op_idx, 2) == "<="):
				continue
			var target := trimmed.substr(0, op_idx).strip_edges()
			var expr := trimmed.substr(op_idx + op.length()).strip_edges()
			return {"type": "assignment", "target": target, "expr": expr, "text": trimmed}

	# Calls (fallback)
	if trimmed.find("(") != -1:
		var before := trimmed.substr(0, trimmed.find("(")).strip_edges()
		if before.find(".") != -1:
			before = before.split(".")[-1]
		return {"type": "call", "call": before, "text": trimmed}

	return {"type": "raw", "text": trimmed}


static func _classify_assignment(txt: String) -> Dictionary:
	# Handle declarations like var/const with optional type/value or :=.
	var working := txt
	var target := ""
	var expr := ""
	if working.begins_with("var "):
		working = working.substr(4).strip_edges()
	elif working.begins_with("const "):
		working = working.substr(6).strip_edges()
	# Split on := or = or typed =.
	var op_idx := working.find(":=")
	var op_len := 2
	if op_idx == -1:
		op_idx = working.find("=")
		op_len = 1
	if op_idx != -1:
		target = working.substr(0, op_idx).strip_edges()
		expr = working.substr(op_idx + op_len).strip_edges()
	else:
		target = working.strip_edges()
	return {"type": "assignment", "target": target, "expr": expr, "text": txt}
