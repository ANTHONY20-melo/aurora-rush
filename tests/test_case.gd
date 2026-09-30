## Base class for all automated test cases.
##
## Pure GDScript, no scene dependencies, so the entire suite runs under
## `godot --headless`. A test case is any RefCounted subclass that declares
## methods named `test_*`; the runner discovers them by reflection.
class_name TestCase
extends RefCounted

## Human readable name for this suite. Override in subclasses.
func suite_name() -> String:
	return "UnnamedSuite"

## Assertions executed so far. The runner aggregates these.
var assertion_count: int = 0

## Failure messages collected during the last executed test.
var failures: PackedStringArray = PackedStringArray()


# --- assertion primitives -------------------------------------------------

func ok(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failures.append(message)


func nope(message: String) -> void:
	assertion_count += 1
	failures.append(message)


func assert_true(value: bool, message: String = "") -> void:
	ok(value, _prefix("expected true, got false") + _with_context(message))


func assert_false(value: bool, message: String = "") -> void:
	ok(not value, _prefix("expected false, got true") + _with_context(message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	ok(actual == expected,
		_prefix("expected %s but got %s" % [str(expected), str(actual)]) + _with_context(message))


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	ok(actual != unexpected,
		_prefix("expected value different from %s" % str(unexpected)) + _with_context(message))


func assert_approx(actual: float, expected: float, epsilon: float = 0.001, message: String = "") -> void:
	ok(absf(actual - expected) <= epsilon,
		_prefix("expected %f (+/- %f) but got %f (delta %f)"
			% [expected, epsilon, actual, absf(actual - expected)]) + _with_context(message))


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	ok(actual > threshold, _prefix("expected > %f but got %f" % [threshold, actual]) + _with_context(message))


func assert_gte(actual: float, threshold: float, message: String = "") -> void:
	ok(actual >= threshold, _prefix("expected >= %f but got %f" % [threshold, actual]) + _with_context(message))


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	ok(actual < threshold, _prefix("expected < %f but got %f" % [threshold, actual]) + _with_context(message))


func assert_lte(actual: float, threshold: float, message: String = "") -> void:
	ok(actual <= threshold, _prefix("expected <= %f but got %f" % [threshold, actual]) + _with_context(message))


func assert_in_range(actual: float, low: float, high: float, message: String = "") -> void:
	ok(actual >= low and actual <= high,
		_prefix("expected value in [%f, %f] but got %f" % [low, high, actual]) + _with_context(message))


func assert_not_null(value: Variant, message: String = "") -> void:
	ok(value != null, _prefix("expected non-null value") + _with_context(message))


func assert_has_method(target: Object, method: String, message: String = "") -> void:
	var has: bool = target.has_method(method)
	ok(has, _prefix("object %s is missing method '%s'" % [target.get_class(), method]) + _with_context(message))


func assert_empty(collection: Variant, message: String = "") -> void:
	var size := _collection_size(collection)
	ok(size == 0, _prefix("expected empty collection, size=%d" % size) + _with_context(message))


## Inverse of assert_empty. Written as its own assertion rather than
## `not assert_empty(...)` so a failure report reads as a real expectation
## instead of a double negative.
func assert_not_empty(collection: Variant, message: String = "") -> void:
	var size := _collection_size(collection)
	ok(size > 0, _prefix("expected non-empty collection, size=%d" % size) + _with_context(message))


## Element count, or -1 for a type this harness does not know how to measure.
## An unknown type must fail the assertion, never silently pass.
func _collection_size(collection: Variant) -> int:
	if collection is Array or collection is Dictionary \
			or collection is PackedStringArray or collection is String:
		return collection.size()
	return -1


func _prefix(message: String) -> String:
	return message


## Join the assertion's own message with the caller's context, so a report
## line reads "expected 1 but got 2 -- mismatch on purpose" rather than
## running the two together into an unreadable blob.
func _with_context(message: String) -> String:
	if message.is_empty():
		return ""
	return " -- " + message


## Called before each test method. Override to set up shared state.
func before_each() -> void:
	pass


## Called after each test method. Override to tear down.
func after_each() -> void:
	pass
