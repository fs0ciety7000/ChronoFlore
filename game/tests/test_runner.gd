# Run with: godot --headless --path game --import && godot --headless --path game --script res://tests/test_runner.gd
extends SceneTree

const UNIT_DIR: String = "res://tests/unit"
const ErrorLogger := preload("res://tests/error_logger.gd")

var passed: int = 0
var failed: int = 0
var functions: int = 0
var _errors: ErrorLogger

func _initialize() -> void:
	_errors = ErrorLogger.new()
	OS.add_logger(_errors)
	_run_all()

func _run_all() -> void:
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(UNIT_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	if files.is_empty():
		failed += 1
		push_error("FAIL no test files found in %s" % UNIT_DIR)
	for f: String in files:
		await _run_file(f)
	await process_frame # errors from nodes freed at the end of the last test
	failed += _report_errors(_errors.count() - _seen, "after the last test")
	OS.remove_logger(_errors)
	print("Results: %d test functions, %d assertions passed, %d failed" % [functions, passed, failed])
	quit(1 if failed > 0 else 0)

var _seen: int = 0

## Fails `where` once per engine/script error logged since the last check; returns the count.
func _report_errors(count: int, where: String) -> int:
	if count <= 0:
		return 0
	for e: String in _errors.since(_seen):
		printerr("FAIL %s: runtime error: %s" % [where, e])
	_seen += count
	return count

func _run_file(file: String) -> void:
	var script: Script = load("%s/%s" % [UNIT_DIR, file])
	if script == null or not script.can_instantiate():
		failed += 1
		push_error("FAIL %s: cannot load script (parse error?)" % file)
		return
	var tc: Object = script.new()
	if tc == null or not ("tree" in tc):
		failed += 1
		push_error("FAIL %s: not a test case (extend res://tests/test_case.gd)" % file)
		return
	tc.tree = self
	var methods: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var n: String = m["name"]
		if n.begins_with("test_"):
			methods.append(n)
	methods.sort()
	for n: String in methods:
		tc.context = "%s::%s" % [file, n]
		var before: int = tc.passed + tc.failed
		failed += _report_errors(_errors.count() - _seen, "before %s" % tc.context)
		functions += 1
		await tc.call(n)
		if tc.passed + tc.failed == before:
			tc.failed += 1
			push_error("FAIL %s made no assertions (crashed?)" % tc.context)
		tc.failed += _report_errors(_errors.count() - _seen, tc.context)
	passed += tc.passed
	failed += tc.failed
