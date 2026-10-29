# Base class for unit tests: extend it from tests/unit/test_*.gd.
# Test methods are named test_*(), take no argument and may await.
extends RefCounted

var passed: int = 0
var failed: int = 0
# Set by the runner before each test method, used in failure messages.
var context: String = ""
# Set by the runner so tests can add nodes to tree.root and await frames.
var tree: SceneTree

func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		_fail("%s: expected %s, got %s" % [label, str(expected), str(actual)])

func assert_true(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		_fail("%s: expected true, got false" % label)

func assert_false(cond: bool, label: String) -> void:
	if not cond:
		passed += 1
	else:
		_fail("%s: expected false, got true" % label)

func assert_near(actual: float, expected: float, eps: float, label: String) -> void:
	if absf(actual - expected) <= eps:
		passed += 1
	else:
		_fail("%s: expected %s +/- %s, got %s" % [label, str(expected), str(eps), str(actual)])

func _fail(message: String) -> void:
	failed += 1
	push_error("FAIL %s %s" % [context, message])
