extends Node

## Test Runner — loads and executes test files and suites.
## Tests are JSON files in data/tests/. Suites in data/tests/suites/.
## Executes sequentially via a typed task queue.

# Task types
const TASK_RCON := "rcon"       # Execute RCON commands
const TASK_WAIT := "wait"       # Wait N seconds
const TASK_CHECK := "check"     # Run checks and record results
const TASK_RESULTS := "results" # Show aggregated results
const TASK_DEBUG_PROFILE := "debug_profile"  # Apply/clear debug profile

var _task_queue: Array = []   # Array of {type, data}
var _running: bool = false
var _console: Node = null
var _results: Array = []
var _current_suite_name: String = ""
var _wait_timer: float = 0.0
var _test_start_time: float = 0.0    # Time.get_ticks_msec() when test started
var _current_test_name: String = ""   # Name of currently running test
var _current_test_script: Array = []  # Copy of the script being run
var _last_leap_eval: Array = []  # Captured leap edges with per-edge match detail from last bounded_leaps check
var _check_log: Array[String] = []  # Captured log lines during check execution
var _check_log_capture: bool = false  # True while capturing _log output into _check_log

# Breach monitoring during wait
var _breach_conditions: Array = []  # Active breach conditions for current wait
var _breach_initial_sides: Dictionary = {}  # {entity_name: sign} recorded at wait start
var _breach_result: Dictionary = {}  # {breached: bool, entity, pos, condition} set on breach

# Bounded leap continuous monitoring — collects matches/violations throughout the test
var _bleap_monitor_active: bool = false
var _bleap_monitor_defs: Dictionary = {}       # Bleap check data from RCON (leaps, min_matched)
var _bleap_matched_keys: Dictionary = {}       # {edge_key: edge_detail} — edges that matched a plan
var _bleap_violated_keys: Dictionary = {}      # {edge_key: edge_detail} — candidate edges that violated
var _bleap_monitor_poll: float = 0.0           # Throttle: poll graph every 0.5s not every frame


func run_test(test_name: String, console: Node) -> void:
	_console = console
	var test_data: Dictionary = _load_test(test_name)
	if test_data.is_empty():
		_log("ERR: test '%s' not found" % test_name, Color(1.0, 0.3, 0.3))
		return
	_results.clear()
	_current_suite_name = ""
	_reset_bleap_state()
	_current_test_name = test_name
	_current_test_script = test_data.get("script", test_data.get("setup", []))
	_test_start_time = Time.get_ticks_msec()
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


func run_test_script(script: Array[String], test_name: String, console: Node) -> void:
	## Execute a flat RCON script loaded via testload/testnew.
	## Meta-commands: "wait N", "check bounded_leaps <label>", "check fps > N".
	## All other lines (including bleap commands) execute as regular RCON commands.
	_console = console
	_results.clear()
	_current_suite_name = ""
	_reset_bleap_state()
	_last_leap_eval.clear()
	_breach_result = {}
	_current_test_name = test_name
	_current_test_script = []
	for line in script:
		_current_test_script.append(str(line))
	_test_start_time = Time.get_ticks_msec()

	_queue_script(script, test_name)

	_task_queue.append({"type": TASK_RESULTS})
	_start_queue()


func _queue_script(script: Array, test_name: String) -> void:
	## Queue tasks from a flat script array. Used by both run_test_script and _queue_test.
	## Automatically clears stale zones/debug state from previous tests.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon:
		rcon._execute("clearzones")
		rcon._execute("debug off testing/etz_daz_zones")
		rcon._execute("debug off testing/violations")
		rcon._execute("debug off testing/bounded_leap_checks")
		rcon._execute("debug off testing/planned_leaps")
	var current_batch: Array = []
	var first_batch: bool = true

	for line in script:
		var l: String = str(line).strip_edges()
		if l.is_empty() or l.begins_with("#"):
			continue

		if l.begins_with("wait "):
			# Flush current batch, then queue a wait
			if not current_batch.is_empty():
				_task_queue.append({
					"type": TASK_RCON,
					"test_name": test_name if first_batch else "",
					"commands": current_batch.duplicate(),
				})
				first_batch = false
				current_batch = []
			var wait_task: Dictionary = _parse_wait_line(l)
			_task_queue.append(wait_task)
			continue

		if l.begins_with("check "):
			# Flush batch first so bleap commands run before the check evaluates
			if not current_batch.is_empty():
				_task_queue.append({
					"type": TASK_RCON,
					"test_name": test_name if first_batch else "",
					"commands": current_batch.duplicate(),
				})
				first_batch = false
				current_batch = []
			var check_dict: Dictionary = _parse_script_check(l)
			if not check_dict.is_empty():
				_task_queue.append({
					"type": TASK_CHECK,
					"test_name": test_name,
					"checks": [check_dict],
				})
			continue

		# Regular RCON command (bleap, debug, spawn, standdown, etc.)
		current_batch.append(l)

	# Flush any remaining commands
	if not current_batch.is_empty():
		_task_queue.append({
			"type": TASK_RCON,
			"test_name": test_name if first_batch else "",
			"commands": current_batch.duplicate(),
		})


func _parse_script_check(line: String) -> Dictionary:
	## Parse a script "check <...>" line into a check descriptor dict.
	## Supported forms:
	##   check bounded_leaps <label>   — uses current RCON bleap state at check time
	##   check zones
	##   check fps > <n>
	##   check hp > <n>
	var after: String = line.substr(6).strip_edges()  # strip "check "

	if after.begins_with("bounded_leaps"):
		var label: String = after.substr(13).strip_edges()
		if label.is_empty():
			label = "bounded_leaps"
		# from_rcon_bleap signals _execute_check_task to pull bleap state from RCON
		return {"command": "bounded_leaps", "from_rcon_bleap": true, "label": label}

	if after == "zones":
		return {"command": "zones", "label": "zones"}

	# Generic check: "cmd [extract:key] [> N] [label:name]"
	# Tokens can appear in any order after the command name.
	# Examples:
	#   check fps > 20
	#   check hp extract:damage_taken > 0.0 label:damage
	#   check ik extract:ik_peak < 2000 label:ik_peak
	var tparts: PackedStringArray = after.split(" ", false)
	if tparts.size() >= 1:
		var subcmd: String = tparts[0]
		var label: String = subcmd
		var extract: String = ""
		var op: String = ""
		var threshold: float = 0.0

		# Scan tokens for extract:, label:, and operator
		var i: int = 1
		while i < tparts.size():
			if tparts[i].begins_with("extract:"):
				extract = tparts[i].substr(8)
				i += 1
			elif tparts[i].begins_with("label:"):
				label = tparts[i].substr(6)
				i += 1
			elif tparts[i] in [">", "<", "="] and i + 1 < tparts.size():
				op = tparts[i]
				threshold = float(tparts[i + 1])
				i += 2
			else:
				i += 1

		var check_dict: Dictionary = {"command": subcmd, "label": label}
		if not extract.is_empty():
			check_dict["extract"] = extract
		else:
			# Standard extract keys for known commands
			match subcmd:
				"fps": check_dict["extract"] = "fps"
				"hp":  check_dict["extract"] = "damage_taken"
		match op:
			">": check_dict["expect_gt"] = threshold
			"<": check_dict["expect_lt"] = threshold
			"=": check_dict["expect_eq"] = threshold
		return check_dict

	return {}


func _parse_wait_line(line: String) -> Dictionary:
	## Parse "wait N [unless breach X1 Y1 X2 Y2 pat... [unless breach ...] ...]"
	var parts := line.split(" ", false)
	var duration: float = float(parts[1]) if parts.size() > 1 else 10.0
	var task: Dictionary = {"type": TASK_WAIT, "duration": duration, "test_name": ""}

	# Collect all "unless breach/exit_circle" clauses
	var conditions: Array = []
	var i: int = 2
	while i < parts.size():
		if parts[i].to_lower() == "unless" and i + 1 < parts.size():
			var cond_type: String = parts[i + 1].to_lower()
			if cond_type == "breach" and i + 6 < parts.size():
				var cond: Dictionary = {
					"cond_type": "breach",
					"x1": float(parts[i + 2]), "y1": float(parts[i + 3]),
					"x2": float(parts[i + 4]), "y2": float(parts[i + 5]),
					"patterns": [],
				}
				var j: int = i + 6
				while j < parts.size() and parts[j].to_lower() != "unless":
					cond["patterns"].append(parts[j])
					j += 1
				conditions.append(cond)
				i = j
			elif cond_type == "exit_circle" and i + 5 < parts.size():
				var cond: Dictionary = {
					"cond_type": "exit_circle",
					"x": float(parts[i + 2]), "y": float(parts[i + 3]),
					"r": float(parts[i + 4]),
					"patterns": [],
				}
				var j: int = i + 5
				while j < parts.size() and parts[j].to_lower() != "unless":
					cond["patterns"].append(parts[j])
					j += 1
				conditions.append(cond)
				i = j
			else:
				i += 1
		else:
			i += 1

	if not conditions.is_empty():
		task["breach_conditions"] = conditions

	return task


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
	## Queue tasks for a single test. Handles both script format and legacy format.
	var test_name: String = test_data.get("name", "unnamed")

	# Script format: flat array of RCON commands + meta-commands
	if test_data.has("script"):
		_reset_bleap_state()
		var script: Array = test_data["script"]
		_queue_script(script, test_name)
		return

	# Legacy format: setup/wait/checks
	var setup_cmds: Array = test_data.get("setup", [])
	var wait_time: float = test_data.get("wait", 10.0)
	var checks: Array = test_data.get("checks", [])
	var debug_profile: Dictionary = test_data.get("debug", {})

	# Task 0: Apply debug profile (if present)
	if not debug_profile.is_empty():
		_task_queue.append({
			"type": TASK_DEBUG_PROFILE,
			"test_name": test_name,
			"profile": debug_profile,
			"action": "apply",
		})

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

	# Task 4: Clear debug profile (if one was applied)
	if not debug_profile.is_empty():
		_task_queue.append({
			"type": TASK_DEBUG_PROFILE,
			"test_name": test_name,
			"action": "clear",
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
			_breach_conditions.clear()
		TASK_WAIT:
			var breach_conds: Array = task.get("breach_conditions", [])
			if breach_conds.is_empty():
				_log("  Waiting %.0fs..." % task["duration"], Color(0.6, 0.6, 0.6))
			else:
				_log("  Waiting %.0fs (breach-guarded, %d fences)..." % [task["duration"], breach_conds.size()], Color(0.6, 0.7, 0.6))
			_wait_timer = task["duration"]
			_breach_conditions = breach_conds
			_breach_result = {}
			_breach_initial_sides.clear()
			for cond: Dictionary in breach_conds:
				_record_breach_initial_sides(cond)
			# Start bounded leap monitoring if bleap state is defined
			_start_bleap_monitor()
		TASK_CHECK:
			_execute_check_task(task)
			_wait_timer = 0.3
		TASK_DEBUG_PROFILE:
			_execute_debug_profile_task(task)
			_wait_timer = 0.1
		TASK_RESULTS:
			_show_results()
			_wait_timer = 0.1


func _process(delta: float) -> void:
	if not _running:
		return
	if _wait_timer > 0:
		_wait_timer -= delta
		# Check breach conditions each frame during wait
		if not _breach_conditions.is_empty() and _breach_result.is_empty():
			_check_breach_conditions()
			if not _breach_result.is_empty():
				_wait_timer = 0.0
				var breach_entity: String = _breach_result.get("entity", "?")
				var breach_pos: Vector2 = _breach_result.get("pos", Vector2.ZERO)
				_log("  BREACH: %s at (%.0f,%.0f) crossed fence — wait aborted" % [
					breach_entity, breach_pos.x, breach_pos.y],
					Color(1.0, 0.8, 0.2))
				_breach_conditions.clear()
		# Poll bounded leap graph monitoring
		if _bleap_monitor_active:
			_bleap_monitor_poll -= delta
			if _bleap_monitor_poll <= 0:
				_bleap_monitor_poll = 0.5
				_poll_bleap_monitor()
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
	_check_log.clear()
	_check_log_capture = true

	var test_result: Dictionary = {"name": test_name, "passed": true, "checks": []}

	for check in checks:
		var cmd: String = check.get("command", "")
		var extract_key: String = check.get("extract", "")
		var label: String = check.get("label", cmd)

		# Special zone check: validates ETZ/DAZ results
		if cmd == "zones":
			var zone_passed: bool = _check_zones(check, label, test_result)
			if not zone_passed:
				test_result["passed"] = false
			continue

		# Bounded leap check: validates precog graph edges against constraints
		if cmd == "bounded_leaps":
			var actual_check: Dictionary = check.duplicate()
			# When running from a script, pull current bleap state from RCON at check time
			if check.get("from_rcon_bleap", false) and rcon and rcon.has_method("get_bleap_check_data"):
				var bleap_data: Dictionary = rcon.get_bleap_check_data()
				if not bleap_data.is_empty():
					actual_check["leaps"] = bleap_data.get("leaps", [])
					actual_check["min_matched"] = bleap_data.get("min_matched", 1)
			var leaps_passed: bool = _check_bounded_leaps(actual_check, label, test_result)
			if not leaps_passed:
				test_result["passed"] = false
			continue

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
	_check_log_capture = false
	test_result["log"] = _check_log.duplicate()
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

	# Write test output to files
	_write_test_output(passed, total)


func _write_test_output(passed: int, total: int) -> void:
	## Write test results to user://test-output/<version>/<testname>/<timestamp>/
	var duration_ms: float = Time.get_ticks_msec() - _test_start_time
	var duration_s: float = duration_ms / 1000.0
	var version_str: String = Version.get_string()
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var test_name: String = _current_test_name if not _current_test_name.is_empty() else "unnamed"

	var base_dir: String = "user://test-output/%s/%s/%s" % [version_str, test_name, timestamp]
	DirAccess.make_dir_recursive_absolute(base_dir)

	# -- test.json: copy of the script that was run --
	var test_file := FileAccess.open(base_dir + "/test.json", FileAccess.WRITE)
	if test_file:
		test_file.store_string(JSON.stringify({
			"name": test_name,
			"script": _current_test_script,
		}, "\t"))
		test_file.close()

	# -- results.json: comprehensive output --
	var checks_output: Array = []
	for r: Dictionary in _results:
		var check_entries: Array = []
		for c: Dictionary in r.get("checks", []):
			check_entries.append({
				"label": c.get("label", ""),
				"passed": c.get("passed", false),
				"value": c.get("value", 0),
				"expected": c.get("expected", ""),
			})
		checks_output.append({
			"name": r.get("name", ""),
			"passed": r.get("passed", false),
			"checks": check_entries,
			"log": r.get("log", []),
		})

	# Violation details from the leap monitor
	var violations_output: Array = []
	for edge: Dictionary in _last_leap_eval:
		if edge.get("result", "") == "failed":
			var breaches: Array = []
			for bp: Dictionary in edge.get("breach_points", []):
				breaches.append({
					"pos": [bp["pos"].x, bp["pos"].y],
					"reason": bp.get("reason", ""),
				})
			violations_output.append({
				"from": [edge["from_pos"].x, edge["from_pos"].y],
				"arrival": [edge["arrival"].x, edge["arrival"].y],
				"result": edge.get("result", ""),
				"breach_count": breaches.size(),
				"breaches": breaches,
			})

	# Matched edges
	var matched_output: Array = []
	for edge: Dictionary in _last_leap_eval:
		if edge.get("result", "") == "matched":
			matched_output.append({
				"from": [edge["from_pos"].x, edge["from_pos"].y],
				"arrival": [edge["arrival"].x, edge["arrival"].y],
			})

	var results_data: Dictionary = {
		"test_name": test_name,
		"version": version_str,
		"timestamp": timestamp,
		"duration_seconds": snapped(duration_s, 0.01),
		"passed": passed,
		"total": total,
		"all_passed": passed == total,
		"checks": checks_output,
		"violations": violations_output,
		"matched_edges": matched_output,
		"bleap_matched_count": _bleap_matched_keys.size(),
		"bleap_violation_count": _bleap_violated_keys.size(),
		"breach_result": {
			"breached": not _breach_result.is_empty(),
			"entity": _breach_result.get("entity", ""),
			"pos": [_breach_result.get("pos", Vector2.ZERO).x, _breach_result.get("pos", Vector2.ZERO).y] if not _breach_result.is_empty() else [],
		},
	}

	var results_file := FileAccess.open(base_dir + "/results.json", FileAccess.WRITE)
	if results_file:
		results_file.store_string(JSON.stringify(results_data, "\t"))
		results_file.close()

	_log("  Output: %s" % base_dir, Color(0.5, 0.5, 0.5))


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


func _check_zones(check: Dictionary, label: String, test_result: Dictionary) -> bool:
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon or not rcon._zone_manager or not is_instance_valid(rcon._zone_manager):
		_log("  [FAIL] %s: no zone manager" % label, Color(1.0, 0.3, 0.3))
		test_result["checks"].append({"label": label, "value": 0, "expected": "zones", "passed": false})
		return false

	var result: Dictionary = rcon._zone_manager.get_check_result()
	var all_pass: bool = true

	# Check ETZ entered
	var etz_ok: bool = result["etz_entered"] == result["etz_total"]
	var etz_label: String = "etz (%d/%d)" % [result["etz_entered"], result["etz_total"]]
	var etz_col: Color = Color(0.3, 1.0, 0.3) if etz_ok else Color(1.0, 0.3, 0.3)
	_log("  [%s] %s" % ["PASS" if etz_ok else "FAIL", etz_label], etz_col)
	test_result["checks"].append({"label": "etz", "value": result["etz_entered"], "expected": "= %d" % result["etz_total"], "passed": etz_ok})
	if not etz_ok:
		all_pass = false

	# Check DAZ not violated
	var daz_ok: bool = result["daz_violated"] == 0
	var daz_label: String = "daz (violations: %d)" % result["daz_violated"]
	var daz_col: Color = Color(0.3, 1.0, 0.3) if daz_ok else Color(1.0, 0.3, 0.3)
	_log("  [%s] %s" % ["PASS" if daz_ok else "FAIL", daz_label], daz_col)
	test_result["checks"].append({"label": "daz", "value": result["daz_violated"], "expected": "= 0", "passed": daz_ok})
	if not daz_ok:
		all_pass = false

	# Check order
	var order_ok: bool = result["order_ok"]
	var order_col: Color = Color(0.3, 1.0, 0.3) if order_ok else Color(1.0, 0.3, 0.3)
	_log("  [%s] order" % ("PASS" if order_ok else "FAIL"), order_col)
	test_result["checks"].append({"label": "order", "value": 1 if order_ok else 0, "expected": "= 1", "passed": order_ok})
	if not order_ok:
		all_pass = false

	return all_pass


func _execute_debug_profile_task(task: Dictionary) -> void:
	var test_name: String = task.get("test_name", "")
	var action: String = task.get("action", "")
	var observer_id: String = "test:%s" % test_name

	if action == "apply":
		var profile: Dictionary = task.get("profile", {})
		DebugOverlay.apply_profile(observer_id, profile)
		_log("  debug: applied %d aspects for %s" % [profile.size(), observer_id], Color(0.6, 0.8, 1.0))
	elif action == "clear":
		DebugOverlay.remove_profile(observer_id)
		_log("  debug: cleared profile for %s" % observer_id, Color(0.6, 0.8, 1.0))



func _check_bounded_leaps(check: Dictionary, label: String, test_result: Dictionary) -> bool:
	## Read results from the continuous bounded leap monitor.
	## Pass if: matched >= min_matched AND violations == 0.
	_bleap_monitor_active = false  # Stop monitoring
	var min_matched: int = check.get("min_matched", 1)

	# Do one final poll to catch the latest graph state
	if not _bleap_monitor_defs.is_empty():
		_poll_bleap_monitor()

	var matched_count: int = _bleap_matched_keys.size()
	var violation_count: int = _bleap_violated_keys.size()

	_log("  [LEAPS] %s: monitor collected %d matched, %d violations" % [
		label, matched_count, violation_count], Color(0.5, 0.8, 1.0))

	# Log matched edges
	for key: String in _bleap_matched_keys:
		var detail: Dictionary = _bleap_matched_keys[key]
		_log("    MATCHED: from=(%.0f,%.0f) arrival=(%.0f,%.0f)" % [
			detail["from_pos"].x, detail["from_pos"].y,
			detail["arrival"].x, detail["arrival"].y], Color(0.3, 1.0, 0.3))

	# Log violated edges
	for key: String in _bleap_violated_keys:
		var detail: Dictionary = _bleap_violated_keys[key]
		var breach_count: int = detail.get("breach_points", []).size()
		_log("    VIOLATION: from=(%.0f,%.0f) arrival=(%.0f,%.0f) breaches=%d" % [
			detail["from_pos"].x, detail["from_pos"].y,
			detail["arrival"].x, detail["arrival"].y, breach_count], Color(1.0, 0.3, 0.3))

	var passed: bool = matched_count >= min_matched and violation_count == 0
	var expected_str: String = ">= %d matched, 0 violations" % min_matched
	var value_str: String = "%d matched, %d violations" % [matched_count, violation_count]

	test_result["checks"].append({
		"label": label, "value": float(matched_count),
		"expected": expected_str, "passed": passed
	})

	# Build _last_leap_eval for the editor overlay
	_last_leap_eval.clear()
	for key: String in _bleap_matched_keys:
		var d: Dictionary = _bleap_matched_keys[key]
		_last_leap_eval.append({
			"arc_c": d.get("arc_c", PackedVector2Array()),
			"from_pos": d["from_pos"], "arrival": d["arrival"],
			"result": "matched", "breach_points": [],
		})
	for key: String in _bleap_violated_keys:
		var d: Dictionary = _bleap_violated_keys[key]
		_last_leap_eval.append({
			"arc_c": d.get("arc_c", PackedVector2Array()),
			"from_pos": d["from_pos"], "arrival": d["arrival"],
			"result": "failed", "breach_points": d.get("breach_points", []),
		})

	var col: Color = Color(0.3, 1.0, 0.3) if passed else Color(1.0, 0.3, 0.3)
	_log("  [%s] %s: %s (%s)" % [
		"PASS" if passed else "FAIL", label, value_str, expected_str], col)
	return passed


func _circle_matches_platform(circle: Dictionary, plat_pos: Vector2,
		plat_min_x: float, plat_max_x: float) -> bool:
	## True if the circle overlaps any point of the platform's horizontal bar.
	## Platform A/B circles identify WHICH platform the edge comes from/goes to.
	if circle.is_empty():
		return true  # No constraint = accept any platform
	var cx: float = float(circle.get("x", 0))
	var cy: float = float(circle.get("y", 0))
	var cr: float = float(circle.get("radius", 0))
	var closest_x: float = clampf(cx, plat_min_x, plat_max_x)
	return Vector2(cx, cy).distance_to(Vector2(closest_x, plat_pos.y)) <= cr


func _edge_satisfies_plan(edge: Dictionary, plan: Dictionary) -> bool:
	## True if the edge's launch/landing/arcs satisfy all constraints in a plan.
	var from_pos: Vector2 = edge.get("from_pos", Vector2.ZERO)
	var arrival: Vector2  = edge.get("arrival",  Vector2.ZERO)

	# START rect: launch point must be inside the rectangle
	var start: Dictionary = plan.get("start", {})
	if not start.is_empty():
		var rect := Rect2(
			float(start.get("x", 0)), float(start.get("y", 0)),
			float(start.get("w", 9999)), float(start.get("h", 9999)))
		if not rect.has_point(from_pos):
			return false

	# END circle: landing point must be within the circle
	var end_d: Dictionary = plan.get("end", {})
	if not end_d.is_empty():
		var ec := Vector2(float(end_d.get("x", 0)), float(end_d.get("y", 0)))
		var er: float = float(end_d.get("radius", 9999))
		if arrival.distance_to(ec) > er:
			return false

	# DISALLOW capsules: no arc point may be within radius of any forbidden path segment
	var disallows: Array = plan.get("disallow", [])
	for dis in disallows:
		var dr: float = float(dis.get("radius", 20))
		var p1 := Vector2(float(dis.get("x1", 0)), float(dis.get("y1", 0)))
		var p2 := Vector2(float(dis.get("x2", 0)), float(dis.get("y2", 0)))
		for arc_key in ["arc_c", "arc_l", "arc_r"]:
			for pt: Vector2 in edge.get(arc_key, []):
				if _dist_point_to_segment(pt, p1, p2) < dr:
					return false

	return true


func _dist_point_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	## Minimum distance from point pt to line segment a→b.
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return pt.distance_to(a)
	var t: float = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab)

# -- Bounded leap continuous monitoring ----------------------------------------

func _reset_bleap_state() -> void:
	## Clear all bleap monitor state AND reset RCON's bleap builder so stale
	## state from a previous test doesn't leak into the next.
	_bleap_matched_keys.clear()
	_bleap_violated_keys.clear()
	_bleap_monitor_active = false
	_bleap_monitor_defs = {}
	var rcon: Node = get_node_or_null("/root/Rcon")
	if rcon:
		rcon._execute("bleap reset")


func _start_bleap_monitor() -> void:
	## Begin monitoring if RCON has bleap state defined.
	var rcon: Node = get_node_or_null("/root/Rcon")
	if not rcon or not rcon.has_method("get_bleap_check_data"):
		_bleap_monitor_active = false
		return
	var bleap_data: Dictionary = rcon.get_bleap_check_data()
	if bleap_data.is_empty():
		_bleap_monitor_active = false
		return
	_bleap_monitor_defs = bleap_data
	_bleap_monitor_active = true
	_bleap_monitor_poll = 0.0  # Poll immediately on first frame
	# Don't clear accumulated results — they persist across waits within the same test


func _poll_bleap_monitor() -> void:
	## Evaluate the current leap graph against bleap defs. Collect matches and violations.
	var leap_defs: Array = _bleap_monitor_defs.get("leaps", [])
	if leap_defs.is_empty():
		return

	# Gather all edges
	var all_edges: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("get_leap_graph"):
			for edge in enemy.get_leap_graph():
				all_edges.append(edge)
	if all_edges.is_empty():
		return

	for leap_def in leap_defs:
		var plat_a: Dictionary = leap_def.get("platform_a", {})
		var plat_b: Dictionary = leap_def.get("platform_b", {})
		var plans: Array = leap_def.get("plans", [])

		for edge in all_edges:
			var from_pos: Vector2 = edge.get("from_pos", Vector2.ZERO)
			var arrival: Vector2 = edge.get("arrival", Vector2.ZERO)
			# Platform identification: circle must contain the platform center
			var from_ok: bool = _circle_matches_platform(
				plat_a, edge["from_plat_pos"], edge["from_plat_min_x"], edge["from_plat_max_x"])
			var to_ok: bool = _circle_matches_platform(
				plat_b, edge["to_plat_pos"], edge["to_plat_min_x"], edge["to_plat_max_x"])
			if not from_ok or not to_ok:
				continue  # Not a candidate — ignore
			var arc_c: PackedVector2Array = edge.get("arc_c", PackedVector2Array())
			var edge_key: String = "%.0f,%.0f>%.0f,%.0f" % [from_pos.x, from_pos.y, arrival.x, arrival.y]

			## Evaluate this candidate edge against all plans.
			##
			## Bounded Leap Evaluation Rules:
			## ─────────────────────────────
			## Platform A/B circles: identify WHICH PLATFORM (broad match on platform bar).
			##   Any edge between those platforms is a "candidate."
			##
			## For each candidate, check against every plan:
			##   START rect: does launch point fall inside? If not → plan doesn't apply, skip.
			##   END circle: does arrival fall inside? If not → plan doesn't apply, skip.
			##   DISALLOW:   does any arc point (arc_c/l/r) breach a disallow zone?
			##
			## Classification:
			##   MATCHED   = edge satisfies ≥1 plan (START ok, END ok, no disallow breach)
			##   VIOLATION = edge breaches a DISALLOW zone in any plan where START+END match
			##   UNMATCHED = edge doesn't fit any plan's START/END — ignored (not a violation)
			##
			## The check passes when: matched ≥ min_matched AND violations == 0.

			var edge_matched: bool = false
			var edge_violated: bool = false
			var edge_breaches: Array = []

			for plan in plans:
				var start_ok := true
				var end_ok := true
				var disallow_breaches: Array = []

				# START rect — does the launch point fall inside?
				var st: Dictionary = plan.get("start", {})
				if not st.is_empty():
					var rect := Rect2(float(st.get("x",0)), float(st.get("y",0)),
						float(st.get("w",9999)), float(st.get("h",9999)))
					if not rect.has_point(from_pos):
						start_ok = false

				# END circle — does the arrival fall inside?
				var end_d: Dictionary = plan.get("end", {})
				if not end_d.is_empty():
					var ec := Vector2(float(end_d.get("x",0)), float(end_d.get("y",0)))
					var er: float = float(end_d.get("radius", 9999))
					if arrival.distance_to(ec) > er:
						end_ok = false

				# If START or END don't match, this plan simply doesn't apply to this edge.
				# NOT a violation — just skip to the next plan.
				if not start_ok or not end_ok:
					continue

				# START and END both match — now check DISALLOW zones.
				# If the arc breaches a disallow, THIS is a violation.
				# Check: at each point on arc_c, does a circle of body_radius
				# intersect the disallow capsule? This matches the planner's
				# circle-sweep approach. The effective check distance is
				# disallow_radius + body_radius.
				var body_radius: float = 55.0  # LEAP_BODY_RADIUS from monster
				var disallows: Array = plan.get("disallow", [])
				for dis in disallows:
					var dr: float = float(dis.get("radius", 20))
					var p1 := Vector2(float(dis.get("x1",0)), float(dis.get("y1",0)))
					var p2 := Vector2(float(dis.get("x2",0)), float(dis.get("y2",0)))
					var check_dist: float = dr + body_radius  # Circle-to-capsule intersection
					for pt: Vector2 in arc_c:
						if _dist_point_to_segment(pt, p1, p2) < check_dist:
							disallow_breaches.append({"pos": pt, "reason": "disallow (body r=%.0f)" % body_radius})

				if disallow_breaches.is_empty():
					# START ok, END ok, no disallow breach → MATCHED
					edge_matched = true
					break
				else:
					# START ok, END ok, BUT disallow breached → VIOLATION
					edge_violated = true
					edge_breaches.append_array(disallow_breaches)

			var detail: Dictionary = {
				"from_pos": from_pos, "arrival": arrival,
				"arc_c": arc_c, "breach_points": edge_breaches,
			}

			if edge_matched:
				if not _bleap_matched_keys.has(edge_key):
					_bleap_matched_keys[edge_key] = detail
					_log("    MONITOR: MATCHED edge %s" % edge_key, Color(0.3, 1.0, 0.3))
			elif edge_violated:
				if not _bleap_violated_keys.has(edge_key):
					_bleap_violated_keys[edge_key] = detail
					_log("    MONITOR: VIOLATION edge %s (disallow breach)" % edge_key, Color(1.0, 0.3, 0.3))
			# else: unmatched — edge doesn't fit any plan's START/END, silently ignored


# -- Breach monitoring ---------------------------------------------------------

func _record_breach_initial_sides(cond: Dictionary) -> void:
	## Record which side of the fence line each matched entity is on at the start of the wait.
	## Only needed for "breach" (line) conditions, not "exit_circle".
	if cond.get("cond_type", "breach") != "breach":
		return
	var p1 := Vector2(cond.get("x1", 0.0), cond.get("y1", 0.0))
	var p2 := Vector2(cond.get("x2", 0.0), cond.get("y2", 0.0))
	var patterns: Array = cond.get("patterns", [])
	var entities := _find_matching_entities(patterns)
	for entity: Node2D in entities:
		# Only record initial side if entity is within the segment span.
		# Entities outside the span are not tracked — the fence is a finite segment.
		if not _within_segment_span(entity.global_position, p1, p2):
			continue
		var side := _line_side(entity.global_position, p1, p2)
		var key := entity.name + "|" + str(cond.get("x1")) + "," + str(cond.get("y1"))
		_breach_initial_sides[key] = side
		print("BREACH INIT: entity=%s pos=(%.0f,%.0f) fence=(%.0f,%.0f)→(%.0f,%.0f) side=%.0f patterns=%s" % [
			entity.name, entity.global_position.x, entity.global_position.y,
			p1.x, p1.y, p2.x, p2.y, side, str(cond.get("patterns", []))])


func _check_breach_conditions() -> void:
	## Check all active breach conditions. Sets _breach_result on first breach.
	for cond: Dictionary in _breach_conditions:
		var cond_type: String = cond.get("cond_type", "breach")
		var patterns: Array = cond.get("patterns", [])
		var entities := _find_matching_entities(patterns)

		if cond_type == "breach":
			# Fence segment — triggers if entity crosses within the segment span
			var p1 := Vector2(cond.get("x1", 0.0), cond.get("y1", 0.0))
			var p2 := Vector2(cond.get("x2", 0.0), cond.get("y2", 0.0))
			for entity: Node2D in entities:
				var key := entity.name + "|" + str(cond.get("x1")) + "," + str(cond.get("y1"))
				var initial_side: float = _breach_initial_sides.get(key, 0.0)
				if absf(initial_side) < 0.001:
					continue
				var pos: Vector2 = entity.global_position
				if not _within_segment_span(pos, p1, p2):
					continue
				var current_side := _line_side(pos, p1, p2)
				if initial_side * current_side < 0:
					print("BREACH DEBUG: entity=%s pos=(%.0f,%.0f) fence=(%.0f,%.0f)→(%.0f,%.0f) patterns=%s initial_side=%.0f current_side=%.0f" % [
						entity.name, pos.x, pos.y, p1.x, p1.y, p2.x, p2.y,
						str(patterns), initial_side, current_side])
					_breach_result = {"breached": true, "entity": entity.name, "pos": pos, "condition": cond}
					return

		elif cond_type == "exit_circle":
			# Circle — triggers if entity moves outside the circle
			var center := Vector2(cond.get("x", 0.0), cond.get("y", 0.0))
			var radius: float = cond.get("r", 100.0)
			for entity: Node2D in entities:
				if entity.global_position.distance_to(center) > radius:
					_breach_result = {"breached": true, "entity": entity.name, "pos": entity.global_position, "condition": cond}
					return


func _find_matching_entities(patterns: Array) -> Array:
	## Find all entities (enemies + players) whose name matches any of the glob patterns.
	var result: Array = []
	var all_nodes: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("players")
	for node: Node in all_nodes:
		for pattern: String in patterns:
			if _glob_match(node.name, pattern):
				result.append(node)
				break
		# Also check entity_id if present
		if node not in result and "entity_id" in node:
			for pattern: String in patterns:
				if _glob_match(node.entity_id, pattern):
					result.append(node)
					break
	return result


func _glob_match(text: String, pattern: String) -> bool:
	## Simple glob: * at end matches prefix, otherwise exact match.
	if pattern.ends_with("*"):
		return text.begins_with(pattern.substr(0, pattern.length() - 1))
	return text == pattern


func _within_segment_span(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> bool:
	## True if the point's projection onto the line through A→B falls within [0,1] of the segment.
	## Uses a small margin so entities near the endpoints still trigger.
	var ab := seg_b - seg_a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return point.distance_to(seg_a) < 30.0
	var t := (point - seg_a).dot(ab) / len_sq
	return t >= 0.0 and t <= 1.0  # Strict segment bounds — no margin past endpoints


func _line_side(point: Vector2, line_a: Vector2, line_b: Vector2) -> float:
	## Returns the sign of the cross product (B-A) × (P-A). Positive = left side, negative = right.
	var ab := line_b - line_a
	var ap := point - line_a
	return ab.x * ap.y - ab.y * ap.x


func _log(text: String, color: Color = Color(0.7, 0.7, 0.7)) -> void:
	if _check_log_capture:
		_check_log.append(text.strip_edges())
	if _console and is_instance_valid(_console):
		_console._log(text, color)
	else:
		print(text)
