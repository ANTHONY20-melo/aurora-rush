extends Node
## Headless automated test runner.
##
## Discovers every `tests/cases/*_test.gd`, instantiates it, invokes all
## `test_*` methods and prints a TAP-like report. Exits with code 0 when the
## whole suite is green, 1 otherwise -- so CI (or FRY) can trust the result.
##
## Usage:
##   godot --headless res://tests/TestRunner.tscn
##   godot --headless res://tests/TestRunner.tscn -- --filter=physics

const CASES_DIR := "res://tests/cases"
const SUITE_SCRIPT_NAME_SUFFIX := "_test.gd"

var _suites_passed: int = 0
var _suites_failed: int = 0
var _tests_passed: int = 0
var _tests_failed: int = 0
var _assertions: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _filter: String = ""


func _ready() -> void:
	# Suites that build real scenes need to call add_child, and the scene tree
	# root refuses children while it is still inside its own _ready(). Yield one
	# frame so the root is idle before any suite runs.
	await get_tree().process_frame

	_parse_args()
	print_rich("[b]AURORA RUSH - TEST SUITE[/b]")
	print("")

	var case_paths: PackedStringArray = _discover_cases()
	if case_paths.is_empty():
		print("[color=red]FAIL[/color] no test cases found in %s" % CASES_DIR)
		get_tree().quit(1)
		return

	for path in case_paths:
		_run_suite(path)

	_report()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.substr(9).to_lower()


func _discover_cases() -> PackedStringArray:
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return PackedStringArray()
	var found := PackedStringArray()
	for file_name in dir.get_files():
		if file_name.ends_with(SUITE_SCRIPT_NAME_SUFFIX):
			found.append(CASES_DIR.path_join(file_name))
	# Deterministic order so reports are diffable across runs.
	var sorted := Array(found)
	sorted.sort()
	return PackedStringArray(sorted)


func _run_suite(path: String) -> void:
	var script: GDScript = load(path)
	# A script with a parse error still loads as a resource, so a null check
	# alone is not enough: it must also be instantiable. Without this, a suite
	# that never compiled was skipped and the run still reported ALL GREEN.
	if script == null or not script.can_instantiate():
		_suites_failed += 1
		_failures.append("%s :: could not be instantiated (parse error?)" % path)
		print("[color=red]FAIL[/color] %s (unloadable)" % path)
		return

	var instance: Variant = script.new()
	if not (instance is TestCase):
		_suites_failed += 1
		_failures.append("%s :: does not extend TestCase" % path)
		print("[color=red]FAIL[/color] %s (not a TestCase)" % path)
		return

	var suite: TestCase = instance
	var suite_name: String = suite.suite_name()
	if not _filter.is_empty() and not suite_name.to_lower().contains(_filter) \
			and not path.to_lower().contains(_filter):
		return

	var test_names := PackedStringArray()
	for method in _collect_test_methods(suite):
		test_names.append(method)
	test_names.sort()

	if test_names.is_empty():
		_suites_failed += 1
		_failures.append("%s :: declares no test_* methods" % suite_name)
		print("[color=red]FAIL[/color] %s (no tests)" % suite_name)
		return

	var suite_failed: int = 0
	var lines: PackedStringArray = PackedStringArray()
	lines.append("  [bold]%s[/bold] (%d tests)" % [suite_name, test_names.size()])

	for test_name in test_names:
		suite.failures = PackedStringArray()
		var assertions_before: int = suite.assertion_count
		suite.before_each()
		# A test that raises must fail that test, not kill the whole run.
		suite.call(test_name)
		suite.after_each()
		_assertions += suite.assertion_count
		# A test that asserted nothing proved nothing. Letting it pass silently
		# is how a suite full of early `return`s reports a comfortable green
		# while testing nothing at all.
		if suite.assertion_count == assertions_before:
			_tests_failed += 1
			suite_failed += 1
			lines.append("    [color=red]FAIL[/color] %s (no assertions ran)" % test_name)
			_failures.append("%s :: %s :: test ran no assertions" % [suite_name, test_name])
			continue
		if suite.failures.is_empty():
			_tests_passed += 1
			lines.append("    [color=green]PASS[/color] %s" % test_name)
		else:
			_tests_failed += 1
			suite_failed += 1
			lines.append("    [color=red]FAIL[/color] %s" % test_name)
			for failure in suite.failures:
				var text := "        - %s" % failure
				lines.append("[color=red]%s[/color]" % text)
				_failures.append("%s :: %s :: %s" % [suite_name, test_name, failure])

	for line in lines:
		print(line)

	if suite_failed == 0:
		_suites_passed += 1
	else:
		_suites_failed += 1
	print("")


func _collect_test_methods(suite: TestCase) -> PackedStringArray:
	var names := PackedStringArray()
	for method: Dictionary in suite.get_method_list():
		var method_name: String = method.get("name", "")
		if method_name.begins_with("test_"):
			names.append(method_name)
	return names


func _report() -> void:
	print_rich("[b]================================================[/b]")
	var all_green: bool = _tests_failed == 0 and _suites_failed == 0
	if all_green:
		print_rich("[color=green][b]  RESULT: ALL GREEN[/b][/color]")
	elif _tests_failed == 0 and _suites_failed > 0:
		# A suite that never loaded is just as fatal as a failing assertion, and
		# reporting "0 TEST(S) FAILED" there reads like a pass.
		print_rich("[color=red][b]  RESULT: %d SUITE(S) FAILED TO LOAD[/b][/color]" % _suites_failed)
	else:
		print_rich("[color=red][b]  RESULT: %d TEST(S) FAILED[/b][/color]" % _tests_failed)
	print("  suites : %d passed, %d failed" % [_suites_passed, _suites_failed])
	print("  tests  : %d passed, %d failed" % [_tests_passed, _tests_failed])
	print("  asserts: %d" % _assertions)
	if not all_green:
		print("")
		print_rich("[color=red][b]FAILURE DETAIL[/b][/color]")
		for failure in _failures:
			print("  * %s" % failure)
	print_rich("[b]================================================[/b]")

	get_tree().quit(0 if all_green else 1)
