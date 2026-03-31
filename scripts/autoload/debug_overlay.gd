extends Node

## Debug Overlay — centralized debug aspect registry with observer-based filtering.
##
## Usage:
##   if DebugOverlay.should_draw("pathing/waypoints", self):
##       draw_circle(wpt, 10.0, Color.ORANGE)
##
##   DebugOverlay.log("precog/current_path", self, "PRECOG: P%d → P%d", [src, dst])
##
## Aspects are a 2-level hierarchy: "group/sub_aspect".
## Observers (human, test:<name>, script:<id>) independently request VISUAL and/or TEXTUAL output.
## Actualized state = union of all observer requests for each aspect.


# -- Constants -----------------------------------------------------------------

## Textual output destinations
enum TextMode { NONE, LOG, CONSOLE, BOTH }

const TEXT_MODE_NAMES := {
	TextMode.NONE: "none",
	TextMode.LOG: "log",
	TextMode.CONSOLE: "console",
	TextMode.BOTH: "both",
}

const TEXT_MODE_FROM_NAME := {
	"none": TextMode.NONE,
	"log": TextMode.LOG,
	"console": TextMode.CONSOLE,
	"both": TextMode.BOTH,
}

const SAVE_PATH := "user://debug_profile.json"


# -- Types ---------------------------------------------------------------------

## Per-observer request for a single aspect
class ObserverRequest:
	var visual: bool = false
	var textual: int = TextMode.NONE  # TextMode enum


## Registered aspect metadata
class AspectInfo:
	var path: String = ""           # "group/sub" full path
	var group: String = ""          # top-level group name
	var sub: String = ""            # sub-aspect name (empty for group-only)
	var description: String = ""
	## observer_id → ObserverRequest
	var observers: Dictionary = {}
	## Cached actualized state (updated when observers change)
	var _actual_visual: bool = false
	var _actual_textual: int = TextMode.NONE
	## Tick counters — incremented on every vis()/log() call, even when disabled.
	## Reset every second to compute ticks-per-second (TPS) rate.
	var _visual_ticks: int = 0      # Visual draw calls this second
	var _textual_ticks: int = 0     # Log calls this second
	var _visual_tps: int = 0        # Visual ticks per second (computed)
	var _textual_tps: int = 0       # Textual ticks per second (computed)


# -- State ---------------------------------------------------------------------

## Master on/off — gates ALL debug output. Does not change individual aspect states.
var global_enabled: bool = false

## Entity type filter: type_name → included (true = show debug for this type)
var entity_type_filter: Dictionary = {
	"monster": true,
	"dummy": true,
	"attacker": true,
}

## Entity ID wildcard pattern (empty or "*" = match all)
var entity_id_pattern: String = "*"

## All registered aspects: path → AspectInfo
var _aspects: Dictionary = {}

## Ordered list of aspect paths (insertion order for UI)
var _aspect_order: Array[String] = []

## Group collapse state for UI: group_name → collapsed (bool)
var collapsed_groups: Dictionary = {}

## Console reference for textual output to in-game console
var _console: Node = null


# -- Lifecycle -----------------------------------------------------------------

var _tps_timer: float = 0.0  # Accumulates delta for TPS calculation

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profile()


func _process(delta: float) -> void:
	_tps_timer += delta
	if _tps_timer >= 1.0:
		_tps_timer -= 1.0
		# Snapshot tick counts into TPS rates, then reset counters
		for path in _aspects:
			var info: AspectInfo = _aspects[path]
			info._visual_tps = info._visual_ticks
			info._textual_tps = info._textual_ticks
			info._visual_ticks = 0
			info._textual_ticks = 0


# -- Registration --------------------------------------------------------------

## Register a debug aspect. Call at startup or lazily on first use.
## path: "group/sub_aspect" (e.g., "pathing/waypoints")
## description: human-readable tooltip for the UI
func register(path: String, description: String = "") -> void:
	if _aspects.has(path):
		# Update description if provided
		if description != "":
			_aspects[path].description = description
		return

	var info := AspectInfo.new()
	info.path = path
	info.description = description

	var parts: PackedStringArray = path.split("/", false, 2)
	info.group = parts[0] if parts.size() > 0 else path
	info.sub = parts[1] if parts.size() > 1 else ""

	_aspects[path] = info
	_aspect_order.append(path)


## Get all registered aspect paths, in registration order.
func get_aspect_paths() -> Array[String]:
	return _aspect_order


## Get all unique group names, in order of first appearance.
func get_aspect_groups() -> Array[String]:
	var groups: Array[String] = []
	var seen: Dictionary = {}
	for path in _aspect_order:
		var info: AspectInfo = _aspects[path]
		if not seen.has(info.group):
			seen[info.group] = true
			groups.append(info.group)
	return groups


## Get all aspects in a group.
func get_aspects_in_group(group: String) -> Array[String]:
	var result: Array[String] = []
	for path in _aspect_order:
		if _aspects[path].group == group:
			result.append(path)
	return result


## Get aspect info (or null).
func get_aspect(path: String) -> AspectInfo:
	return _aspects.get(path)


# -- Observer Management -------------------------------------------------------

## Set an observer's request for an aspect.
## observer_id: "human", "test:leap_floor_to_P1", "script:foo"
## visual: whether the observer wants visual rendering
## textual: TextMode enum value
func set_observer(aspect_path: String, observer_id: String, visual: bool, textual: int = TextMode.NONE) -> void:
	# Auto-register unknown aspects
	if not _aspects.has(aspect_path):
		register(aspect_path)

	var info: AspectInfo = _aspects[aspect_path]

	if not visual and textual == TextMode.NONE:
		# Remove observer entirely
		info.observers.erase(observer_id)
	else:
		var req: ObserverRequest
		if info.observers.has(observer_id):
			req = info.observers[observer_id]
		else:
			req = ObserverRequest.new()
			info.observers[observer_id] = req
		req.visual = visual
		req.textual = textual

	_recompute_actual(info)


## Remove all requests from a specific observer across all aspects.
func remove_observer(observer_id: String) -> void:
	for path in _aspects:
		var info: AspectInfo = _aspects[path]
		if info.observers.erase(observer_id):
			_recompute_actual(info)


## Remove all transient (non-human) observers.
func clear_transient_observers() -> void:
	for path in _aspects:
		var info: AspectInfo = _aspects[path]
		var changed: bool = false
		var to_remove: Array[String] = []
		for obs_id in info.observers:
			if obs_id != "human":
				to_remove.append(obs_id)
		for obs_id in to_remove:
			info.observers.erase(obs_id)
			changed = true
		if changed:
			_recompute_actual(info)


## Get current observer state for an aspect and observer.
## Returns [visual, textual] or [false, NONE] if no observer.
func get_observer_state(aspect_path: String, observer_id: String) -> Array:
	if not _aspects.has(aspect_path):
		return [false, TextMode.NONE]
	var info: AspectInfo = _aspects[aspect_path]
	if not info.observers.has(observer_id):
		return [false, TextMode.NONE]
	var req: ObserverRequest = info.observers[observer_id]
	return [req.visual, req.textual]


## Recompute the actualized state for an aspect (union of all observers).
func _recompute_actual(info: AspectInfo) -> void:
	var vis: bool = false
	var txt: int = TextMode.NONE
	for obs_id in info.observers:
		var req: ObserverRequest = info.observers[obs_id]
		if req.visual:
			vis = true
		if req.textual != TextMode.NONE:
			# Merge: upgrade NONE→LOG/CONSOLE/BOTH
			if txt == TextMode.NONE:
				txt = req.textual
			elif txt == TextMode.LOG and req.textual == TextMode.CONSOLE:
				txt = TextMode.BOTH
			elif txt == TextMode.CONSOLE and req.textual == TextMode.LOG:
				txt = TextMode.BOTH
			elif req.textual == TextMode.BOTH:
				txt = TextMode.BOTH
	info._actual_visual = vis
	info._actual_textual = txt


# -- Query API (hot path) -----------------------------------------------------

## Check if visual debug should be drawn for this aspect + entity.
## ALWAYS increments the visual tick counter (even when disabled) for TPS metrics.
## Call from _draw() to gate debug rendering.
func should_draw(aspect_path: String, entity: Node = null) -> bool:
	if _aspects.has(aspect_path):
		_aspects[aspect_path]._visual_ticks += 1
	if not global_enabled:
		return false
	if not _aspects.has(aspect_path):
		return false
	if not _aspects[aspect_path]._actual_visual:
		return false
	if entity and not _entity_passes_filter(entity):
		return false
	return true


## Execute a visual debug lambda if the aspect is enabled.
## ALWAYS increments the visual tick counter for TPS metrics.
## Usage: DebugOverlay.vis("aspect/sub", self, func(): draw_circle(...))
func vis(aspect_path: String, entity: Node, draw_fn: Callable) -> void:
	if _aspects.has(aspect_path):
		_aspects[aspect_path]._visual_ticks += 1
	if not global_enabled:
		return
	if not _aspects.has(aspect_path):
		return
	if not _aspects[aspect_path]._actual_visual:
		return
	if entity and not _entity_passes_filter(entity):
		return
	draw_fn.call()


## Check if textual debug should be logged for this aspect + entity.
## Returns TextMode (NONE if nothing should be logged).
## Note: logging bypasses global_enabled — tests need logs even without the visual overlay.
func should_log(aspect_path: String, entity: Node = null) -> int:
	if not _aspects.has(aspect_path):
		return TextMode.NONE
	var txt: int = _aspects[aspect_path]._actual_textual
	if txt == TextMode.NONE:
		return TextMode.NONE
	if entity and not _entity_passes_filter(entity):
		return TextMode.NONE
	return txt


## Combined log call: checks aspect, formats message, routes to destination(s).
## ALWAYS increments the textual tick counter for TPS metrics.
func log(aspect_path: String, entity: Node, msg: String, args: Array = []) -> void:
	if _aspects.has(aspect_path):
		_aspects[aspect_path]._textual_ticks += 1
	var mode: int = should_log(aspect_path, entity)
	if mode == TextMode.NONE:
		return

	var formatted: String = msg % args if args.size() > 0 else msg

	if mode == TextMode.LOG or mode == TextMode.BOTH:
		print(formatted)

	if mode == TextMode.CONSOLE or mode == TextMode.BOTH:
		_log_to_console(formatted)


# -- Entity Filtering ----------------------------------------------------------

## Check if an entity passes the current type + ID filters.
func _entity_passes_filter(entity: Node) -> bool:
	# Type filter
	var entity_type: String = _get_entity_type(entity)
	if entity_type != "" and entity_type_filter.has(entity_type):
		if not entity_type_filter[entity_type]:
			return false

	# ID filter
	if entity_id_pattern != "" and entity_id_pattern != "*":
		var eid: String = entity.get("entity_id") if entity.get("entity_id") != null else ""
		if eid == "":
			eid = entity.name
		if not _wildcard_match(eid, entity_id_pattern):
			return false

	return true


## Determine entity type from group membership.
func _get_entity_type(entity: Node) -> String:
	if entity.is_in_group("enemies"):
		return "monster"
	if entity.is_in_group("players"):
		# Check if it's a dummy (spawned by RCON) vs real player
		if entity.name.begins_with("Dummy"):
			return "dummy"
		return "player"
	if entity.is_in_group("attackers"):
		return "attacker"
	return ""


## Simple wildcard matching: supports * (any chars) and ? (single char).
func _wildcard_match(text: String, pattern: String) -> bool:
	if pattern == "*":
		return true
	# Convert wildcard to regex-like matching via recursive approach
	return _wildcard_match_impl(text, pattern, 0, 0)


func _wildcard_match_impl(text: String, pattern: String, ti: int, pi: int) -> bool:
	while pi < pattern.length():
		if ti >= text.length():
			# Text exhausted — remaining pattern must be all *
			if pattern[pi] == "*":
				pi += 1
				continue
			return false
		if pattern[pi] == "*":
			# Try matching * against 0..N chars
			pi += 1
			if pi >= pattern.length():
				return true  # Trailing * matches everything
			while ti <= text.length():
				if _wildcard_match_impl(text, pattern, ti, pi):
					return true
				ti += 1
			return false
		elif pattern[pi] == "?":
			ti += 1
			pi += 1
		elif pattern[pi] == text[ti]:
			ti += 1
			pi += 1
		else:
			return false
	return ti >= text.length()


# -- Console Integration -------------------------------------------------------

func _log_to_console(text: String) -> void:
	if _console and is_instance_valid(_console):
		_console._log(text, Color(0.6, 0.8, 1.0))
		return
	# Try to find the console
	var console_node: Node = get_tree().get_first_node_in_group("game_console")
	if console_node:
		_console = console_node
		_console._log(text, Color(0.6, 0.8, 1.0))


# -- Persistence ---------------------------------------------------------------

## Save human observer state to disk.
func save_profile() -> void:
	var data: Dictionary = {
		"global_enabled": global_enabled,
		"entity_filter": {
			"types": entity_type_filter.duplicate(),
			"id_pattern": entity_id_pattern,
		},
		"aspects": {},
		"collapsed_groups": collapsed_groups.duplicate(),
	}

	for path in _aspect_order:
		var info: AspectInfo = _aspects[path]
		if info.observers.has("human"):
			var req: ObserverRequest = info.observers["human"]
			data["aspects"][path] = {
				"visual": req.visual,
				"textual": TEXT_MODE_NAMES[req.textual],
			}

	var json_str: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("DebugOverlay: saved profile to %s" % SAVE_PATH)
	else:
		push_warning("DebugOverlay: failed to save profile to %s" % SAVE_PATH)


## Load human observer state from disk.
func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("DebugOverlay: failed to parse %s" % SAVE_PATH)
		return

	var data: Dictionary = json.data
	global_enabled = data.get("global_enabled", false)

	var ef: Dictionary = data.get("entity_filter", {})
	if ef.has("types"):
		for type_name in ef["types"]:
			entity_type_filter[type_name] = ef["types"][type_name]
	entity_id_pattern = ef.get("id_pattern", "*")

	collapsed_groups = data.get("collapsed_groups", {})

	var aspects_data: Dictionary = data.get("aspects", {})
	for path in aspects_data:
		var ad: Dictionary = aspects_data[path]
		var visual: bool = ad.get("visual", false)
		var textual: int = TEXT_MODE_FROM_NAME.get(ad.get("textual", "none"), TextMode.NONE)
		set_observer(path, "human", visual, textual)

	print("DebugOverlay: loaded profile from %s" % SAVE_PATH)


# -- Bulk Operations -----------------------------------------------------------

## Set human observer VISUAL for all aspects in a group.
func set_group_visual(group: String, visual: bool) -> void:
	for path in get_aspects_in_group(group):
		var state: Array = get_observer_state(path, "human")
		set_observer(path, "human", visual, state[1])


## Set human observer TEXTUAL for all aspects in a group.
func set_group_textual(group: String, textual: int) -> void:
	for path in get_aspects_in_group(group):
		var state: Array = get_observer_state(path, "human")
		set_observer(path, "human", state[0], textual)


## Apply a debug profile dictionary (from test JSON "debug" block).
## observer_id: the observer to set (e.g., "test:leap_floor_to_P1")
## profile: { "aspect/sub": "log"|"console"|"both"|"visual"|"all", ... }
func apply_profile(observer_id: String, profile: Dictionary) -> void:
	for path in profile:
		var mode_str: String = str(profile[path])
		var visual: bool = false
		var textual: int = TextMode.NONE

		match mode_str:
			"visual":
				visual = true
			"log":
				textual = TextMode.LOG
			"console":
				textual = TextMode.CONSOLE
			"both":
				textual = TextMode.BOTH
			"all":
				visual = true
				textual = TextMode.BOTH
			_:
				if TEXT_MODE_FROM_NAME.has(mode_str):
					textual = TEXT_MODE_FROM_NAME[mode_str]

		set_observer(path, observer_id, visual, textual)


## Remove a debug profile (clear all aspects for an observer).
func remove_profile(observer_id: String) -> void:
	remove_observer(observer_id)


# -- Debug Info ----------------------------------------------------------------

## Return a summary string of all aspects and their states (for RCON "debug list").
func get_status_text() -> String:
	var lines: Array[String] = []
	lines.append("global: %s" % ("ON" if global_enabled else "OFF"))
	lines.append("filter: types=%s id=%s" % [str(entity_type_filter), entity_id_pattern])
	lines.append("aspects: %d registered" % _aspects.size())

	var current_group: String = ""
	for path in _aspect_order:
		var info: AspectInfo = _aspects[path]
		if info.group != current_group:
			current_group = info.group
			lines.append("  %s/" % current_group)
		var vis_str: String = "V" if info._actual_visual else "."
		var txt_str: String = TEXT_MODE_NAMES[info._actual_textual] if info._actual_textual != TextMode.NONE else "."
		var obs_list: String = ",".join(PackedStringArray(info.observers.keys()))
		if obs_list == "":
			obs_list = "-"
		var sub_label: String = info.sub if info.sub != "" else "(group)"
		lines.append("    %-30s [%s|%s] obs=%s" % [sub_label, vis_str, txt_str, obs_list])

	return "\n".join(lines)
