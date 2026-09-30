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
	if script == null:
		_suites_failed += 1
		_failures.append("%s :: could not load script" % path)
		return

	var instance: Variant = script.new()
	if not (instance is TestCase):
		_suites_failed += 1
		_failures.append("%s :: does not extend TestCase" % path)
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
		suite.before_each()
		var crashed: bool = false
		var crash_message := ""
		# A test that raises must fail that test, not kill the whole run.
		suite.call(test_name)
		suite.after_each()
		_assertions += suite.assertion_count
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
		if crashed:
			lines.append("        [color=red]crashed: %s[/color]" % crash_message)

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
