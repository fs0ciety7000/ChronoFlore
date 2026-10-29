extends Logger
## Collects the engine and script errors logged while the tests run, so the runner can fail the
## test that caused them. Assertion failures ("FAIL ...") are already counted by the test case;
## ALLOWED lists the errors a test provokes on purpose. Loggers may be called from any thread.

## Substrings of expected errors (test_save_store_corrupt reads a corrupt save on purpose).
const ALLOWED: Array[String] = ["Parse JSON failed"]

var _mutex := Mutex.new()
var _errors: Array[String] = []

func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	if text.begins_with("FAIL "):
		return
	for allowed in ALLOWED:
		if text.contains(allowed) or code.contains(allowed):
			return
	_mutex.lock()
	_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
	_mutex.unlock()

func count() -> int:
	_mutex.lock()
	var n := _errors.size()
	_mutex.unlock()
	return n

## Errors logged from index `from` on.
func since(from: int) -> Array[String]:
	_mutex.lock()
	var out: Array[String] = _errors.slice(from)
	_mutex.unlock()
	return out
