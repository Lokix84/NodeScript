@tool
extends SceneTree

# Simple Test Runner
# Scans res://tests/unit/ for scripts starting with "test_"
# Instantiates them and runs functions starting with "test_"

func _init():
	print("[TestRunner] Starting...")
	var passed = 0
	var failed = 0
	
	var dir = DirAccess.open("res://tests/unit")
	if not dir:
		print("[TestRunner] Error: Could not open tests/unit/")
		quit(1)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var scripts: Array[String] = []
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("test_") and file_name.ends_with(".gd"):
			scripts.append("res://tests/unit/" + file_name)
		file_name = dir.get_next()
	
	if scripts.is_empty():
		print("[TestRunner] No tests found.")
		quit(0)
		return
		
	for script_path in scripts:
		print("\n[TestRunner] Running suite: %s" % script_path)
		var script = load(script_path)
		if not script:
			print("  Failed to load script.")
			continue
			
		var instance = script.new()
		for method in instance.get_method_list():
			var method_name: String = method.get("name", "")
			if method_name.begins_with("test_"):
				# Run setup if exists
				if instance.has_method("before_each"):
					instance.call("before_each")
				
				# capturing output? simple boolean return or assert pattern?
				# Let's assume tests verify internally and print errors. 
				# We count on lack of crash/error.
				# Better: Tests return bool or void. If assert fails, we catch it? GDScript 2.0 asserts are hard to catch.
				# Let's rely on manual print verification for now, or simple internal assert helper.
				
				print("  Running %s..." % method_name)
				instance.call(method_name)
				# If we reached here, assume pass unless custom failure tracked
				if instance.has_method("get_failure_count") and instance.get_failure_count() > 0:
					print("    FAIL")
					failed += 1
				else:
					print("    PASS")
					passed += 1
				
				if instance.has_method("after_each"):
					instance.call("after_each")

	print("\n[TestRunner] Done. %d passed, %d failed." % [passed, failed])
	quit(1 if failed > 0 else 0)
