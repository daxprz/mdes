extends Node

## Test Runner — loads and executes test files and suites.
## Tests are JSON files in data/tests/. Suites in data/tests/suites/.
## Executes sequentially via a typed task queue.

# Task types
const TASK_RCON := "rcon"       # Execute RCON commands
const TASK_WAIT := "wait"       # Wait N seconds
const TASK_CHECK := "check"     # Run checks and record results
const TASK_RESULTS := "results" # Show aggregated results

var _task_queue: Array = []   # Array of {type, data}
var _running: bool = false
var _console: Node = null
var _results: Array = []
var _current_suite_name: String = ""
var _wait_timer: float = 0.0


func run_test(test_name: String, console: Node) -> void:
	_console = console
	var test_data: Dictionary = _load_test(test_name)
	if test_data.is_empty():
		_log("ERR: test '%s' not found" % test_name, Color(1.0, 0.3, 0.3))
		return
	_results.clear()
	_current_suite_name = ""
	_queue_test(test_data)
	_task_queue.append({"type": TASK_RESULTS})
	_start_queue()


func run_suite(suite_name: String, console: Node) -> void:
	_console = console
	var suite: Dictionary = _load_suite(suite_name)
	if suite.is_empty():
		_log("ERR: suite '%s' not found" % suite_name, Color(1.0, 0.3, 0.3))
		return
	_results.clear()
	_current_suite_name = suite.get("name", suite_name)
	_log("=== Suite: %s ===" % _current_suite_name, Color(1.0, 0.9, 0.3))

	var tests: Array = suite.get("tests", [])
	for test_name in tests:
		var test_data: Dictionary = _load_test(test_name)
		if not test_data.is_empty():
			_queue_test(test_data)
		else:
			_log("  SKIP: test '%s' not found" % test_name, Color(1.0, 0.5, 0.3))

	_task_queue.append({"type": TASK_RESULTS})
	_start_queue()


func _load_test(test_name: String) -> Dictionary:
	for dir_path in ["res://data/tests/", "user://data/tests/"]:
		var path: String = dir_path + test_name + ".json"
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					return json.data
				file.close()
	return {}


func _load_suite(suite_name: String) -> Dictionary:
	for dir_path in ["res://data/tests/suites/", "user://data/tests/suites/"]:
		var path: String = dir_path + suite_name + ".json"
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					return json.data
				file.close()
	return {}


# -- Task Queue ----------------------------------------------------------------

func _queue_test(test_data: Dictionary) -> void:
	## Queue setup + wait + check tasks for a single test.
	var test_name: String = test_data.get("name", "unnamed")
	var setup_cmds: Array = test_data.get("setup", [])
	var wait_time: float = test_data.get("wait", 10.0)
	var checks: Array = test_data.get("checks", [])

	# Task 1: Setup — run RCON commands (split on "wait N" for inline delays)
	var current_batch: Array = []
	var first_batch: bool = true
	for cmd in setup_cmds:
		if cmd.begins_with("wait "):
			# Flush current batch
			if not current_batch.is_empty():
				_task_queue.append({
					"type": TASK_RCON,
					"test_name": test_name if first_batch else "",
					"commands": current_batch,
				})
				first_batch = false
				current_batch = []
			# Insert wait task
			var wait_secs: float = float(cmd.substr(5))
			_task_queue.append({"type": TASK_WAIT, "duration": wait_secs, "test_name": ""})
		else:
			current_batch.append(cmd)
	if not current_batch.is_empty():
		_task_queue.append({
			"type": TASK_RCON,
			"test_name": test_name if first_batch else "",
			"commands": current_batch,
		})

	# Task 2: Wait
	_task_queue.append({
		"type": TASK_WAIT,
		"duration": wait_time,
		"test_name": test_name,
	})

	# Task 3: Check results
	_task_queue.append({
		"type": TASK_CHECK,
		"test_name": test_name,
		"checks": checks,
	})


func _start_queue() -> void:
	if _running:
		return
	_running = true
	set_process(true)
	_advance_queue()


func _advance_queue() -> void:
	## Start the next task in the queue.
	if _task_queue.is_empty():
		_running = false
		set_process(false)
		return

	var task: Dictionary = _task_queue.pop_front()
	match task["type"]:
		TASK_RCON:
			_execute_rcon_task(task)
			# Immediate — advance to next task after a brief delay
			_wait_timer = 0.5
		TASK_WAIT:
			_log("  Waiting %.0fs..." % task["duration"], Color(0.6, 0.6, 0.6))
			_wait_timer = task["duration"]
		TASK_CHECK:
			_execute_check_task(task)
			_wait_timer = 0.3
		TASK_RESULTS:
			_show_results()
			_wait_timer = 0.1


func _process(delta: float) -> void:
	if not _running:
		return
	if _wait_timer > 0:
		_wait_timer -= delta
		return
	# Timer expired — advance to next task
	_advance_queue()


func _execute_rcon_task(task: Dictionary) -> void:
	var test_name: String = task.get("test_name", "")
	_log("--- %s ---" % test_name, Color(0.5, 0.9, 1.0))
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		_log("  ERR: RCON not available", Color(1.0, 0.3, 0.3))
		return
	for cmd in task.get("commands", []):
		var result: String = rcon._execute(cmd)
		_log("  %s → %s" % [cmd, result.substr(0, 60)], Color(0.5, 0.5, 0.5))


func _execute_check_task(task: Dictionary) -> void:
	var test_name: String = task.get("test_name", "")
	var checks: Array = task.get("checks", [])
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon:
		_results.append({"name": test_name, "passed": false, "checks": []})
		return

	var test_result: Dictionary = {"name": test_name, "passed": true, "checks": []}

	for check in checks:
		var cmd: String = check.get("command", "")
		var extract_key: String = check.get("extract", "")
		var label: String = check.get("label", cmd)
		var response: String = rcon._execute(cmd)
		var value: float = _extract_value(response, extract_key)

		var passed: bool = true
		var expected_str: String = ""
		if check.has("expect_gt"):
			passed = value > float(check["expect_gt"])
			expected_str = "> %s" % str(check["expect_gt"])
		elif check.has("expect_lt"):
			passed = value < float(check["expect_lt"])
			expected_str = "< %s" % str(check["expect_lt"])
		elif check.has("expect_eq"):
			passed = absf(value - float(check["expect_eq"])) < 0.1
			expected_str = "= %s" % str(check["expect_eq"])
		elif check.has("expect_contains"):
			passed = str(check["expect_contains"]) in response
			expected_str = "contains '%s'" % check["expect_contains"]

		test_result["checks"].append({
			"label": label, "value": value, "expected": expected_str, "passed": passed
		})
		if not passed:
			test_result["passed"] = false

		var col: Color = Color(0.3, 1.0, 0.3) if passed else Color(1.0, 0.3, 0.3)
		_log("  [%s] %s: %.0f (%s)" % ["PASS" if passed else "FAIL", label, value, expected_str], col)

	var overall_col: Color = Color(0.3, 1.0, 0.3) if test_result["passed"] else Color(1.0, 0.3, 0.3)
	_log("  Result: %s" % ("PASS" if test_result["passed"] else "FAIL"), overall_col)
	_results.append(test_result)


func _show_results() -> void:
	_log("", Color.WHITE)
	_log("=== RESULTS%s ===" % (" — " + _current_suite_name if _current_suite_name != "" else ""), Color(1.0, 0.9, 0.3))

	var total: int = _results.size()
	var passed: int = 0
	for r in _results:
		if r["passed"]:
			passed += 1

	for r in _results:
		var col: Color = Color(0.3, 1.0, 0.3) if r["passed"] else Color(1.0, 0.3, 0.3)
		var check_summary: String = ""
		for c in r.get("checks", []):
			if not c["passed"]:
				check_summary += " [%s:%.0f]" % [c["label"], c["value"]]
		_log("  [%s] %s%s" % ["PASS" if r["passed"] else "FAIL", r["name"], check_summary], col)

	var overall_col: Color = Color(0.3, 1.0, 0.3) if passed == total else Color(1.0, 0.8, 0.2)
	_log("=== %d/%d PASSED ===" % [passed, total], overall_col)

	# Show on-screen grid
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon and total > 0:
		var grid_parts: Array[String] = ["=== %d/%d PASSED ===" % [passed, total]]
		for r in _results:
			grid_parts.append("[%s] %s" % ["PASS" if r["passed"] else "FAIL", r["name"]])
		rcon._execute("grid %s" % "|".join(grid_parts))


func _extract_value(response: String, key: String) -> float:
	if key.is_empty():
		return float(response.strip_edges())
	var pattern: String = key + "="
	var idx: int = response.find(pattern)
	if idx < 0:
		return 0.0
	var start: int = idx + pattern.length()
	var end: int = start
	while end < response.length() and (response[end].is_valid_float() or response[end] == "." or response[end] == "-"):
		end += 1
	if end > start:
		return float(response.substr(start, end - start))
	return 0.0


func _log(text: String, color: Color = Color(0.7, 0.7, 0.7)) -> void:
	if _console and is_instance_valid(_console):
		_console._log(text, color)
	else:
		print(text)
