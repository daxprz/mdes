extends Node

## 3-tier version identifier: MAJOR.MINOR.PATCH
## MAJOR (0): pre-release. 1 = first full release.
## MINOR (X): feature milestones, new systems, gameplay changes.
## PATCH (Y): visual-only changes, art tweaks, UI polish. No gameplay impact.

const MAJOR := 0
const MINOR := 9
const PATCH := 2

static func get_string() -> String:
	return "%d.%d.%d" % [MAJOR, MINOR, PATCH]
