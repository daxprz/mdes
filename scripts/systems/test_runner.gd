extends Node

## Test Runner — loads and executes test files and suites.
## Tests are JSON files in data/tests/. Suites in data/tests/suites/.
## Executes sequentially via a task queue.

var _task_queue: Array = []   # Array of Callable tasks
var _running: bool = false
var _console: Node = null     # Reference to game_console for output
var _results: Array = []      # Array of {name, passed, checks, duration}
var _current_test_name: String = ""
var _current_suite_name: String = ""


func run_test(test_name: String, console: Node) -> void:
	## Run a single test by name.
	_console = console
	var test_data: Dictionary = _load_test(test_name)
	if test_data.is_empty():
		_log("ERR: test '%s' not found" % test_name, Color(1.0, 0.3, 0.3))
		return
	_results.clear()
	_current_suite_name = ""
	_queue_test(test_data)
	_queue_task(func(): _show_results())
	_start_queue()


func run_suite(suite_name: String, console: Node) -> void:
	## Run a test suite by name.
	_console = console
	var suite: Dictionary = _load_suite(suite_name)
	if suite.is_empty():
		_log("ERR: suite '%s' not found" % suite_name, Color(1.0, 0.3, 0.3))
		return
	_results.clear()
	_current_suite_name = suite.get("name", suite_name)
	_log("=== Suite: %s ===" % _current_suite_name, Color(1.0, 0.9, 0.3))

	var tests: Array = suite.get("tests", [])
	for test_path in tests:
		var test_name: String = test_path.get_file().replace(".json", "")
		var test_data: Dictionary = _load_test(test_name)
		if not test_data.is_empty():
			_queue_test(test_data)
		else:
			_log("  SKIP: test '%s' not found" % test_name, Color(1.0, 0.5, 0.3))

	_queue_task(func(): _show_results())
	_start_queue()


func _load_test(test_name: String) -> Dictionary:
	## Load a test JSON file by name. Searches bundled then user directories.
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
	## Load a suite JSON file by name.
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

func _queue_task(callable: Callable) -> void:
	_task_queue.append(callable)


func _queue_test(test_data: Dictionary) -> void:
	## Queue setup + wait + check tasks for a single test.
	var test_name: String = test_data.get("name", "unnamed")
	var setup_cmds: Array = test_data.get("setup", [])
	var wait_time: float = test_data.get("wait", 10.0)
	var checks: Array = test_data.get("checks", [])

	# Task 1: Setup — run RCON commands
	_queue_task(func():
		_current_test_name = test_name
		_log("--- %s ---" % test_name, Color(0.5, 0.9, 1.0))
		var rcon: Node = get_node_or_null("/root/Rcon")
		if rcon:
			for cmd in setup_cmds:
				var result: String = rcon._execute(cmd)
				_log("  %s → %s" % [cmd, result.substr(0, 60)], Color(0.5, 0.5, 0.5))
	)

	# Task 2: Wait
	_queue_task(func():
		_log("  Waiting %.0fs..." % wait_time, Color(0.6, 0.6, 0.6))
		await get_tree().create_timer(wait_time).timeout
	)

	# Task 3: Check results
	_queue_task(func():
		var test_result: Dictionary = {"name": test_name, "passed": true, "checks": []}
		var rcon: Node = get_node_or_null("/root/Rcon")
		if not rcon:
			test_result["passed"] = false
			_results.append(test_result)
			return

		for check in checks:
			var cmd: String = check.get("command", "")
			var extract_key: String = check.get("extract", "")
			var label: String = check.get("label", cmd)
			var response: String = rcon._execute(cmd)

			# Extract value from response
			var value: float = _extract_value(response, extract_key)

			# Evaluate check
			var passed: bool = true
			var expected_str: String = ""
			if check.has("expect_gt"):
				passed = value > check["expect_gt"]
				expected_str = "> %s" % str(check["expect_gt"])
			elif check.has("expect_lt"):
				passed = value < check["expect_lt"]
				expected_str = "< %s" % str(check["expect_lt"])
			elif check.has("expect_eq"):
				passed = absf(value - check["expect_eq"]) < 0.1
				expected_str = "= %s" % str(check["expect_eq"])
			elif check.has("expect_contains"):
				passed = check["expect_contains"] in response
				expected_str = "contains '%s'" % check["expect_contains"]

			var check_result: Dictionary = {
				"label": label, "value": value, "expected": expected_str,
				"passed": passed, "response": response.substr(0, 40)
			}
			test_result["checks"].append(check_result)

			if not passed:
				test_result["passed"] = false

			var col: Color = Color(0.3, 1.0, 0.3) if passed else Color(1.0, 0.3, 0.3)
			var status: String = "PASS" if passed else "FAIL"
			_log("  [%s] %s: %.0f (%s)" % [status, label, value, expected_str], col)

		var overall_col: Color = Color(0.3, 1.0, 0.3) if test_result["passed"] else Color(1.0, 0.3, 0.3)
		_log("  Result: %s" % ("PASS" if test_result["passed"] else "FAIL"), overall_col)
		_results.append(test_result)
	)


func _start_queue() -> void:
	if _running:
		return
	_running = true
	_process_queue()


func _process_queue() -> void:
	if _task_queue.is_empty():
		_running = false
		return
	var task: Callable = _task_queue.pop_front()
	var result = task.call()
	# If the task returned a coroutine (has await), wait for it
	if result is Signal:
		await result
	# Small delay between tasks to let physics settle
	await get_tree().create_timer(0.1).timeout
	_process_queue()


func _show_results() -> void:
	## Aggregation task: show summary of all test results.
	_log("", Color.WHITE)
	_log("=== RESULTS%s ===" % (" — " + _current_suite_name if _current_suite_name != "" else ""), Color(1.0, 0.9, 0.3))

	var total: int = _results.size()
	var passed: int = 0
	for r in _results:
		if r["passed"]:
			passed += 1

	# Per-test summary
	for r in _results:
		var col: Color = Color(0.3, 1.0, 0.3) if r["passed"] else Color(1.0, 0.3, 0.3)
		var status: String = "PASS" if r["passed"] else "FAIL"
		var check_summary: String = ""
		for c in r.get("checks", []):
			if not c["passed"]:
				check_summary += " [%s:%.0f]" % [c["label"], c["value"]]
		_log("  [%s] %s%s" % [status, r["name"], check_summary], col)

	# Overall
	var overall_col: Color = Color(0.3, 1.0, 0.3) if passed == total else Color(1.0, 0.8, 0.2)
	_log("=== %d/%d PASSED ===" % [passed, total], overall_col)

	# Also show on screen via RCON grid
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon and total > 0:
		var grid_lines: Array[String] = ["=== %d/%d PASSED ===" % [passed, total]]
		for r in _results:
			var status: String = "PASS" if r["passed"] else "FAIL"
			grid_lines.append("[%s] %s" % [status, r["name"]])
		rcon._execute("grid %s" % "|".join(grid_lines))


func _extract_value(response: String, key: String) -> float:
	## Extract a numeric value from an RCON response string.
	## Handles formats like "damage_taken=123", "fps=60", "ik_peak=500"
	if key.is_empty():
		# Try to parse the whole response as a number
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
