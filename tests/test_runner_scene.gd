@tool
extends Control

@onready var output_label: RichTextLabel = $MarginContainer/VBoxContainer/OutputLabel
@onready var status_rect: ColorRect = $StatusRect
@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ProgressBar

const TEST_DIRS := [
	"res://tests/unit",
	"res://tests/integration",
	"res://tests/functional"
]

var _passed := 0
var _failed := 0
var _total_tests := 0
var _tests_run := 0

func _ready() -> void:
	if output_label == null:
		# Just in case run from editor without scene setup correctly
		return

	output_label.text = "[b]Starting Tests...[/b]\n\n"
	status_rect.color = Color(0.2, 0.2, 0.2) # Neutral gray

	await get_tree().process_frame
	_run_all_tests()

func _log(msg: String, color: String = "") -> void:
	if color != "":
		output_label.append_text("[color=%s]%s[/color]\n" % [color, msg])
	else:
		output_label.append_text(msg + "\n")
	print(msg) # Mirror to console

func _run_all_tests() -> void:
	var scripts: Array[String] = []

	for folder in TEST_DIRS:
		var dir = DirAccess.open(folder)
		if not dir:
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.begins_with("test_") and file_name.ends_with(".gd"):
				scripts.append(folder + "/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	scripts.sort() # deterministic order for CI/logging

	if scripts.is_empty():
		_log("No tests found in unit/, integration/, or functional/.", "yellow")
		return

	_passed = 0
	_failed = 0
	_total_tests = 0
	_tests_run = 0

	# Count tests first for progress bar
	for script_path in scripts:
		var script = load(script_path)
		if script == null:
			continue
		var instance = script.new()
		for method in instance.get_method_list():
			var method_name: String = method.get("name", "")
			if method_name.begins_with("test_"):
				_total_tests += 1

	if _total_tests > 0:
		progress_bar.visible = true
		progress_bar.max_value = _total_tests
		progress_bar.value = 0

	for script_path in scripts:
		_log("[b]Suite: %s[/b]" % script_path.get_file(), "cyan")
		var script = load(script_path)
		if not script:
			_log("  Failed to load script.", "#ff5555")
			_failed += 1
			continue

		var instance = script.new()
		for method in instance.get_method_list():
			var method_name: String = method.get("name", "")
			if method_name.begins_with("test_"):
				_run_single_test(instance, method_name)

	_finish()

func _run_single_test(instance: Object, method_name: String) -> void:
	if instance.has_method("before_each"):
		instance.call("before_each")

	# Reset failure count for this instance if it tracks it?
	# Actually, our simple test scripts track their own failures internally per assert.
	# We need to hook into that or read it.
	# Let's assume the test script has `get_failure_count()` and resets it or we check diff.

	var start_failures = 0
	if instance.has_method("get_failure_count"):
		start_failures = instance.get_failure_count()

	instance.call(method_name)

	var end_failures = 0
	if instance.has_method("get_failure_count"):
		end_failures = instance.get_failure_count()

	if end_failures > start_failures:
		_log("  [FAIL] %s" % method_name, "#ff5555")
		_failed += 1
	else:
		_log("  [PASS] %s" % method_name, "green")
		_passed += 1

	if instance.has_method("after_each"):
		instance.call("after_each")

	_tests_run += 1
	if progress_bar.visible:
		progress_bar.value = _tests_run

func _finish() -> void:
	output_label.append_text("\n")
	if _failed > 0:
		_log("RESULTS: %d PASSED, %d FAILED" % [_passed, _failed], "#ff5555")
		status_rect.color = Color(0.4, 0.1, 0.1) # Darker Red (Maroon)
	else:
		_log("RESULTS: %d PASSED, %d FAILED" % [_passed, _failed], "green")
		status_rect.color = Color(0.2, 0.6, 0.2) # Green
